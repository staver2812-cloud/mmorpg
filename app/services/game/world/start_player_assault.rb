# frozen_string_literal: true

module Game
  module World
    # Starts an Ashen location PvP duel against another playable character who
    # shares the attacker's exact Presence cell/room. Requires and consumes a
    # combat trauma scroll so the fight applies combat injuries on defeat.
    class StartPlayerAssault
      class AssaultViolationError < StandardError; end
      SCROLL_KEY = "combat_trauma_scroll"
      SAFE_BUILDINGS = %w[hospital temple].freeze

      Result = Struct.new(:success, :match, :message, keyword_init: true)

      def initialize(attacker:, defender_id:)
        @attacker = attacker
        @defender_id = defender_id.to_i
      end

      # UI/discovery predicate: same Presence cell/room and not blocked by
      # safe-zone/busy/offline rules. Scroll ownership is checked at mutation time.
      def self.offerable?(attacker:, defender:)
        return false unless attacker && defender
        return false if attacker.id == defender.id
        return false if attacker.active_airship_journey || defender.active_airship_journey
        return false if MovementCommand.moving.where(character: [attacker, defender]).exists?
        return false if active_match_for?(attacker) || active_match_for?(defender)
        return false unless co_located?(attacker, defender)
        return false if safe_zone?(attacker) || safe_zone?(defender)
        return false unless UserSession.recent.exists?(user_id: defender.user_id)

        true
      end

      def self.has_trauma_scroll?(character)
        trauma_scroll_quantity(character).positive?
      end

      def self.trauma_scroll_quantity(character)
        return 0 unless character&.inventory

        Game::Professions::Templates.ensure_craft_items!
        template = ItemTemplate.find_by(key: SCROLL_KEY)
        return 0 unless template

        character.inventory.inventory_items.where(item_template: template, equipped: false).sum(:quantity)
      end

      def self.co_located?(attacker, defender)
        a = attacker.position
        d = defender.position
        return false unless a && d
        return false unless a.zone_id == d.zone_id && a.x == d.x && a.y == d.y

        Presence.new(character: attacker).context_key == Presence.new(character: defender).context_key
      end

      def self.safe_zone?(character)
        ctx = character.gameplay_context
        name = ctx["name"].to_s
        return true if name == "arena_room"
        return true if name == "shop"

        name == "city_building" && SAFE_BUILDINGS.include?(ctx.dig("params", "building_key").to_s)
      end

      def self.active_match_for?(character)
        character.arena_participations.joins(:arena_match).merge(ArenaMatch.active).exists?
      end

      def call
        match = nil
        defender_name = nil
        ActiveRecord::Base.transaction do
          attacker.with_lock do
            attacker.reload
            defender = Character.lock.find_by(id: defender_id)
            validate!(defender)
            consume_scroll!
            match = create_match!(defender)
            create_participations!(match, defender)
            Arena::CombatProcessor.new(match).start_match
            defender_name = defender.name
          end
        end

        Result.new(
          success: true,
          match:,
          message: I18n.t("game.world.assault_started", name: defender_name)
        )
      rescue AssaultViolationError => error
        Result.new(success: false, message: error.message)
      end

      private

      attr_reader :attacker, :defender_id

      def validate!(defender)
        raise AssaultViolationError, I18n.t("game.world.assault_missing_target") unless defender
        raise AssaultViolationError, I18n.t("game.world.assault_self") if defender.id == attacker.id
        raise AssaultViolationError, I18n.t("game.flashes.disembark_first") if attacker.active_airship_journey
        raise AssaultViolationError, I18n.t("game.world.assault_target_busy") if defender.active_airship_journey
        if MovementCommand.moving.where(character: [attacker, defender]).exists?
          raise AssaultViolationError, I18n.t("game.flashes.movement_in_progress")
        end
        raise AssaultViolationError, I18n.t("game.flashes.fight_still_active") if self.class.active_match_for?(attacker)
        raise AssaultViolationError, I18n.t("game.world.assault_target_fighting") if self.class.active_match_for?(defender)
        raise AssaultViolationError, I18n.t("game.world.assault_not_nearby") unless self.class.co_located?(attacker, defender)
        raise AssaultViolationError, I18n.t("game.world.assault_safe_zone") if self.class.safe_zone?(attacker) || self.class.safe_zone?(defender)
        unless UserSession.recent.exists?(user_id: defender.user_id)
          raise AssaultViolationError, I18n.t("game.world.assault_target_offline")
        end
      end

      def consume_scroll!
        Game::Professions::Templates.ensure_craft_items!
        template = ItemTemplate.find_by(key: SCROLL_KEY)
        raise AssaultViolationError, I18n.t("arena.combat_scroll_missing") unless template

        inventory = attacker.inventory
        raise AssaultViolationError, I18n.t("arena.combat_scroll_missing") unless inventory

        stack = inventory.inventory_items.find_by(item_template: template, equipped: false)
        if stack.blank? || stack.quantity.to_i <= 0
          raise AssaultViolationError, I18n.t("arena.combat_scroll_missing")
        end

        Game::Inventory::Manager.new(inventory:).remove_item!(item_template: template, quantity: 1)
      rescue Game::Inventory::Manager::InventoryUnderflowError
        raise AssaultViolationError, I18n.t("arena.combat_scroll_missing")
      end

      def create_match!(defender)
        position = attacker.position
        ArenaMatch.create!(
          zone: position.zone,
          match_type: :duel,
          status: :pending,
          turn_timeout_seconds: ArenaMatch::DEFAULT_TURN_TIMEOUT,
          trauma_percent: 100,
          metadata: {
            "source" => "world_pvp",
            "fight_kind" => "free",
            "combat_trauma" => true,
            "return_context" => "world",
            "zone" => position.zone.name,
            "x" => position.x,
            "y" => position.y,
            "attacker_id" => attacker.id,
            "defender_id" => defender.id,
            "fight_timeout_seconds" => ArenaMatch::DEFAULT_TURN_TIMEOUT
          }
        )
      end

      def create_participations!(match, defender)
        ArenaParticipation.create!(
          arena_match: match,
          character: attacker,
          user: attacker.user,
          team: "a",
          joined_at: Time.current
        )
        ArenaParticipation.create!(
          arena_match: match,
          character: defender,
          user: defender.user,
          team: "b",
          joined_at: Time.current
        )
      end
    end
  end
end
