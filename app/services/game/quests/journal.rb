# frozen_string_literal: true

module Game
  module Quests
    # Character-scoped Ashen quest journal stored in metadata["ashen_quests"].
    class Journal
      META_KEY = "ashen_quests"

      Result = Data.define(:success, :message, :quest_key)

      def initialize(character:)
        @character = character
      end

      def entries
        Catalog.ordered.map { |quest| present(quest) }
      end

      def present(quest)
        state = state_for(quest.fetch("key"))
        {
          quest:,
          status: state["status"] || "available",
          progress: state["progress"].to_i,
          target: objective_count(quest),
          completed_at: state["completed_at"],
          accepted_at: state["accepted_at"]
        }
      end

      def accept!(quest_key)
        quest = Catalog.find(quest_key)
        return failure(quest_key, I18n.t("game.quests.unknown")) unless quest

        character.with_lock do
          character.reload
          state = state_for(quest_key)
          return failure(quest_key, I18n.t("game.quests.already_done")) if state["status"] == "completed"
          return failure(quest_key, I18n.t("game.quests.already_active")) if state["status"] == "active"

          write_state!(quest_key, {
            "status" => "active",
            "progress" => 0,
            "accepted_at" => Time.current.iso8601
          })
        end

        success(quest_key, I18n.t("game.quests.accepted", title: title_for(quest)))
      end

      # Quietly arms the first Ashen shore contract once. Safe to call every login.
      STARTER_QUEST_KEY = "veil_lure_drill"

      def ensure_starter!
        state = state_for(STARTER_QUEST_KEY)
        return if state["status"].in?(%w[active completed])

        accept!(STARTER_QUEST_KEY)
      end

      def turn_in!(quest_key)
        quest = Catalog.find(quest_key)
        return failure(quest_key, I18n.t("game.quests.unknown")) unless quest

        character.with_lock do
          character.reload
          state = state_for(quest_key)
          return failure(quest_key, I18n.t("game.quests.not_active")) unless state["status"] == "active"

          unless objective_met?(quest, state)
            return failure(quest_key, I18n.t("game.quests.objective_incomplete"))
          end

          consume_delivery!(quest) if quest.dig("objective", "type") == "deliver_item"
          grant_rewards!(quest)
          write_state!(quest_key, state.merge(
            "status" => "completed",
            "progress" => objective_count(quest),
            "completed_at" => Time.current.iso8601
          ))
        end

        success(quest_key, I18n.t("game.quests.completed", title: title_for(quest)))
      end

      # Called after a solo NPC victory. Quiet no-op when nothing matches.
      def record_npc_kill!(npc_key:)
        key = npc_key.to_s
        return if key.blank?

        character.with_lock do
          character.reload
          Catalog.ordered.each do |quest|
            next unless quest.dig("objective", "type") == "kill_npc"
            next unless Array(quest.dig("objective", "npc_keys")).map(&:to_s).include?(key)

            state = state_for(quest.fetch("key"))
            next unless state["status"] == "active"

            target = objective_count(quest)
            progress = [state["progress"].to_i + 1, target].min
            write_state!(quest.fetch("key"), state.merge("progress" => progress))
          end
        end
      end

      private

      attr_reader :character

      def bag
        character.metadata.to_h.fetch(META_KEY, {})
      end

      def state_for(quest_key)
        bag.fetch(quest_key.to_s, {}).to_h
      end

      def write_state!(quest_key, state)
        next_bag = bag.merge(quest_key.to_s => state)
        character.update!(metadata: character.metadata.to_h.merge(META_KEY => next_bag))
      end

      def objective_count(quest)
        quest.dig("objective", "count").to_i.clamp(1, 99)
      end

      def objective_met?(quest, state)
        case quest.dig("objective", "type")
        when "kill_npc"
          state["progress"].to_i >= objective_count(quest)
        when "deliver_item"
          item_quantity(quest.dig("objective", "item_key")) >= objective_count(quest)
        else
          false
        end
      end

      def item_quantity(item_key)
        template = ItemTemplate.find_by(key: item_key.to_s)
        return 0 unless template

        character.inventory.inventory_items.where(item_template: template, equipped: false).sum(:quantity)
      end

      def consume_delivery!(quest)
        item_key = quest.dig("objective", "item_key").to_s
        needed = objective_count(quest)
        template = ItemTemplate.find_by!(key: item_key)
        remaining = needed
        character.inventory.inventory_items.where(item_template: template, equipped: false).order(:id).each do |row|
          break if remaining <= 0

          take = [row.quantity, remaining].min
          if take >= row.quantity
            row.destroy!
          else
            row.update!(quantity: row.quantity - take)
          end
          remaining -= take
        end
        raise ArgumentError, "missing delivery items" if remaining.positive?
      end

      def grant_rewards!(quest)
        reward = quest.fetch("reward", {})
        xp = reward["experience"].to_i
        if xp.positive?
          Players::Progression::LevelUpService.new(character:).apply_experience!(xp)
        end

        nv = reward["currency_nv"].to_i
        if nv.positive?
          wallet = character.user.currency_wallet || character.user.create_currency_wallet!(nv_balance: 0)
          wallet.adjust!(
            amount: nv,
            reason: "quest.ashen_reward",
            metadata: {"quest_key" => quest.fetch("key")}
          )
        end

        item_key = reward["item_key"].presence
        return unless item_key

        template = ItemTemplate.find_by(key: item_key)
        return unless template

        Game::Inventory::Manager.new(inventory: character.inventory).add_item!(
          item_template: template,
          quantity: 1
        )
      end

      def title_for(quest)
        locale_key = I18n.locale.to_s.start_with?("ru") ? "title_ru" : "title_en"
        quest[locale_key].presence || quest["title_ru"] || quest.fetch("key")
      end

      def success(quest_key, message)
        Result.new(success: true, message:, quest_key: quest_key.to_s)
      end

      def failure(quest_key, message)
        Result.new(success: false, message:, quest_key: quest_key.to_s)
      end
    end
  end
end
