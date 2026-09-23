# frozen_string_literal: true

module Arena
  # Resolves and persists one NPC participant's typed loot table exactly once.
  #
  # Item ownership and NV balances are committed in the same transaction as the
  # participant processing marker and player-facing GameEvent projection. The
  # marker, not the presentation event, is the retry authority.
  class NpcLootAwarder
    class InvalidEntryError < StandardError; end
    class InvalidParticipantError < StandardError; end

    Award = Data.define(
      :kind,
      :entry_index,
      :event_key,
      :item_template,
      :quantity,
      :currency,
      :amount,
      :currency_transaction_id
    ) do
      def item?
        kind == "item"
      end

      def currency?
        kind == "currency"
      end

      def description
        if item?
          Arena::CombatLogMessages.item_award(item_template.display_name, quantity)
        else
          Arena::CombatLogMessages.funds_award(amount, currency)
        end
      end

      def metadata
        if item?
          {
            "kind" => kind,
            "entry_index" => entry_index,
            "event_key" => event_key,
            "item_template_id" => item_template.id,
            "item_key" => item_template.key,
            "item_name" => item_template.name,
            "quantity" => quantity
          }
        else
          {
            "kind" => kind,
            "entry_index" => entry_index,
            "event_key" => event_key,
            "currency" => currency,
            "amount" => amount,
            "currency_transaction_id" => currency_transaction_id
          }
        end
      end
    end

    Failure = Data.define(:entry_index, :message) do
      def metadata
        {"entry_index" => entry_index, "message" => message}
      end
    end

    Result = Data.define(:awards, :failures, :already_processed) do
      def already_processed?
        already_processed
      end
    end

    def initialize(
      match:,
      npc_participation:,
      character:,
      rng:,
      event_publisher: Chat::EventPublisher.new,
      clock: -> { Time.current }
    )
      @match = match
      @npc_participation = npc_participation
      @character = character
      @rng = rng
      @event_publisher = event_publisher
      @clock = clock
    end

    def call
      ApplicationRecord.transaction do
        # Inventory requests hold the character before inventory/wallet rows.
        # Keep that order when a killing turn awards loot before progression.
        character.lock!
        npc_participation.lock!
        validate_npc_participation!
        participation = player_participation
        raise InvalidParticipantError, I18n.t("arena.validations.loot_recipient_required") unless participation

        participation.lock!

        if loot_already_processed?
          Result.new(awards: [], failures: [], already_processed: true)
        else
          process_loot_table
        end
      end
    end

    private

    attr_reader :match, :npc_participation, :character, :rng, :event_publisher, :clock

    def process_loot_table
      awards = []
      failures = []
      item_awarded = false

      Array(npc_participation.npc_template.loot_table).each_with_index do |raw_entry, entry_index|
        loot_entry = Game::LootEntry.new(raw_entry)
        entry = loot_entry.attributes
        next unless roll_succeeds?(loot_entry)

        # Hard law: at most one gear piece per NPC kill.
        if item_drop_kind?(entry) && item_awarded
          next
        end

        award = award_entry(entry, entry_index)
        awards << award
        item_awarded = true if award.item?
      rescue Game::Inventory::Manager::CapacityExceededError,
        Game::LootEntry::InvalidError,
        InvalidEntryError => e
        failures << Failure.new(entry_index:, message: e.message)
      end

      record_player_awards!(awards)
      publish_awards!(awards)
      record_resolution!(awards, failures)

      Result.new(awards:, failures:, already_processed: false)
    end

    def roll_succeeds?(loot_entry)
      chance = loot_entry.chance_percent * drop_chance_multiplier
      rng.rand < (chance / 100.0)
    end

    def drop_chance_multiplier
      meta = match.metadata.to_h
      template_raw = npc_participation.npc_template&.metadata.to_h["drop_chance_multiplier"]
      tile_raw = meta["drop_chance_multiplier"]
      dungeon_raw = meta["loot_bonus_chance"] if meta["dungeon_loot_bonus"]
      raw = tile_raw.presence || dungeon_raw.presence || template_raw
      value = Float(raw, exception: false)
      base = if value
        # Values below 1.0 are treated as an additive bonus (0.5 → ×1.5).
        (value < 1.0 ? (1.0 + value) : value)
      else
        1.0
      end
      # Wiki Observation (Наблюдательность): non-linear — first 100 most effective,
      # each further hundred half as strong. Use uncapped base skill when present.
      observation = if character.respond_to?(:base_passive_skill_level)
        character.base_passive_skill_level(:observation).to_i
      else
        character.passive_skill_level(:observation).to_i
      end
      observation_mult = observation_multiplier(observation)
      (base * observation_mult).clamp(0.1, 5.0)
    end

    def observation_multiplier(observation)
      remaining = [observation, 0].max
      mult = 1.0
      band = 0
      while remaining.positive? && band < 6
        chunk = [remaining, 100].min
        mult += chunk / (200.0 * (2**band))
        remaining -= chunk
        band += 1
      end
      mult
    end

    def award_entry(entry, entry_index)
      case loot_kind(entry)
      when "item"
        award_item(entry, entry_index)
      when "set_piece"
        award_set_piece(entry, entry_index)
      when "currency"
        award_currency(entry, entry_index)
      else
        raise InvalidEntryError, I18n.t("arena.validations.loot_kind_unsupported", kind: loot_kind(entry))
      end
    end

    def item_drop_kind?(entry)
      %w[item set_piece].include?(loot_kind(entry))
    end

    def loot_kind(entry)
      (entry[:kind].presence || "item").to_s
    end

    def award_set_piece(entry, entry_index)
      keys = Array(entry[:item_keys]).presence ||
        Array(npc_participation.metadata.to_h["equipped_set_keys"]).presence ||
        Array(npc_participation.npc_template.metadata.to_h["equipped_set_keys"])
      keys = keys.map(&:to_s).reject(&:blank?)
      raise InvalidEntryError, I18n.t("arena.validations.loot_item_missing", identity: "set_piece") if keys.empty?

      chosen_key = keys.fetch(rng.rand(keys.length))
      award_item(entry.merge(item_key: chosen_key, kind: "item"), entry_index)
    end

    def award_item(entry, entry_index)
      item_template = find_item_template!(entry)
      quantity = positive_integer(entry.fetch(:quantity, 1), field: I18n.t("arena.validations.loot_field_item_quantity"))
      event_key = event_key_for(entry_index)

      Game::Inventory::Manager.new(inventory: character.inventory).add_item!(
        item_template:,
        quantity:
      )

      Award.new(
        kind: "item",
        entry_index:,
        event_key:,
        item_template:,
        quantity:,
        currency: nil,
        amount: nil,
        currency_transaction_id: nil
      )
    end

    def award_currency(entry, entry_index)
      amount = positive_integer(entry[:amount], field: I18n.t("arena.validations.loot_field_currency_amount"))
      currency = entry.fetch(:currency, "NV").to_s.upcase
      raise InvalidEntryError, I18n.t("arena.validations.loot_currency_unsupported", currency: currency) unless currency == "NV"

      nv_mult = Float(match.metadata.to_h["loot_bonus_nv_mult"], exception: false) if match.metadata.to_h["dungeon_loot_bonus"]
      amount = (amount * nv_mult).round.clamp(1, 1_000_000) if nv_mult&.positive?

      recipients = loot_recipients
      share = [(amount / recipients.size.to_f).floor, 1].max
      event_key = event_key_for(entry_index)
      last_txn = nil
      recipients.each do |recipient|
        wallet = recipient.user.currency_wallet || recipient.user.create_currency_wallet!(nv_balance: 0)
        wallet.adjust!(
          amount: share,
          reason: "combat.npc_loot",
          metadata: source_payload(entry_index).merge(
            "event_key" => event_key,
            "loot_split" => recipients.size > 1,
            "share_of" => amount
          )
        )
        last_txn = wallet.currency_transactions.order(:id).last!
      end

      Award.new(
        kind: "currency",
        entry_index:,
        event_key:,
        item_template: nil,
        quantity: nil,
        currency:,
        amount: share * recipients.size,
        currency_transaction_id: last_txn.id
      )
    end

    def loot_recipients
      ids = Array(match.metadata.to_h["party_character_ids"]).map(&:to_i)
      return [character] if ids.blank? || !match.metadata.to_h["loot_split"]

      members = Character.where(id: ids).to_a
      members.presence || [character]
    end

    def find_item_template!(entry)
      key = entry[:item_key] || entry[:item] || entry[:key]
      name = entry[:item_name] || entry[:name] || entry[:source_name]
      template = ItemTemplate.find_by(key:) if key.present?
      template ||= ItemTemplate.find_by(name:) if name.present?
      return template if template

      identity = key.presence || name.presence || "missing"
      raise InvalidEntryError, I18n.t("arena.validations.loot_item_missing", identity: identity)
    end

    def positive_integer(value, field:)
      amount = Integer(value, exception: false)
      raise InvalidEntryError, I18n.t("arena.validations.loot_positive_integer", field: field) unless amount&.positive?

      amount
    end

    def publish_awards!(awards)
      recipient = character.user
      return unless recipient

      awards.each do |award|
        payload = source_payload(award.entry_index)

        if award.item?
          event_publisher.item_found!(
            recipient:,
            item_name: award.item_template.name,
            quantity: award.quantity,
            event_key: award.event_key,
            payload: payload.merge(item_template_id: award.item_template.id)
          )
        else
          event_publisher.money_found!(
            recipient:,
            amount: award.amount,
            currency: award.currency,
            event_key: award.event_key,
            payload: payload.merge(currency_transaction_id: award.currency_transaction_id)
          )
        end
      end
    end

    def record_player_awards!(awards)
      participation = player_participation
      return unless participation

      metadata = participation.metadata.to_h
      awarded_at = clock.call.iso8601
      award_metadata = awards.map do |award|
        award.metadata.merge(
          "npc_key" => npc_participation.npc_template.npc_key,
          "awarded_at" => awarded_at
        )
      end
      metadata["loot_awards"] = Array(metadata["loot_awards"]) + award_metadata
      metadata["loot_drops"] = Array(metadata["loot_drops"]) + award_metadata.select do |award|
        award["kind"] == "item"
      end
      participation.update!(metadata:)
    end

    def record_resolution!(awards, failures)
      metadata = npc_participation.metadata.to_h
      metadata["loot_resolution"] = {
        "processed_at" => clock.call.iso8601,
        "character_id" => character.id,
        "awards" => awards.map(&:metadata),
        "failures" => failures.map(&:metadata)
      }
      npc_participation.update!(metadata:)
    end

    def loot_already_processed?
      npc_participation.metadata.to_h.key?("loot_resolution")
    end

    def validate_npc_participation!
      return if npc_participation.arena_match_id == match.id && npc_participation.npc?

      raise InvalidParticipantError, I18n.t("arena.validations.loot_source_npc_required")
    end

    def player_participation
      @player_participation ||= match.arena_participations.find_by(character:)
    end

    def event_key_for(entry_index)
      "arena-match:#{match.id}:npc-participation:#{npc_participation.id}:" \
        "loot:#{entry_index}:user:#{character.user_id}"
    end

    def source_payload(entry_index)
      {
        arena_match_id: match.id,
        character_id: character.id,
        npc_participation_id: npc_participation.id,
        npc_template_id: npc_participation.npc_template_id,
        loot_entry_index: entry_index
      }
    end
  end
end
