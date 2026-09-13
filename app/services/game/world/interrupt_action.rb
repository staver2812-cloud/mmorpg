# frozen_string_literal: true

module Game
  module World
    # Resolves whether a valid wilderness action is replaced by the hostile NPC
    # encounter anchored on the character's current cell.
    #
    # Ashen rule: passive ambushes happen on their own timer (~5 minutes).
    # Forced same-cell fights from Look / Enter / shell actions require bait.
    class InterruptAction
      Result = Struct.new(:interrupted, :match, :npc, :message, keyword_init: true) do
        def interrupted?
          interrupted
        end
      end

      def initialize(character:, return_context: "world")
        @character = character
        @return_context = return_context
      end

      def call
        Game::Movement::CompleteMove.new(character:).call
        character.with_lock do
          character.reload
          next Result.new(interrupted: false) if character.active_airship_journey

          active_world_action = LocalActionState.new(character:).call
          if (match = active_match)
            next Result.new(
              interrupted: true,
              match:,
              message: I18n.t("game.flashes.fight_still_active")
            )
          end

          if MovementCommand.moving.where(character:).exists?
            raise StartNpcFight::FightViolationError, I18n.t("game.flashes.movement_in_progress")
          end
          if active_world_action
            raise StartNpcFight::FightViolationError, I18n.t("game.world.local_action_in_progress")
          end

          npc = hostile_npc_at_current_cell
          next Result.new(interrupted: false) unless npc

          bait = Bait.new(character:)
          next Result.new(interrupted: false) unless bait.available?

          bait.consume!
          match = StartNpcFight.new(character:, tile_npc: npc, return_context:).call
          Result.new(
            interrupted: true,
            match:,
            npc:,
            message: I18n.t("game.world.bait_ambush", name: npc.display_name)
          )
        end
      rescue Bait::MissingBaitError
        Result.new(interrupted: false)
      end

      private

      attr_reader :character, :return_context

      def active_match
        character.arena_participations
          .joins(:arena_match)
          .merge(ArenaMatch.active)
          .order("arena_participations.created_at DESC")
          .first
          &.arena_match
      end

      def hostile_npc_at_current_cell
        position = character.position
        return unless position&.zone&.outdoor?

        npc = TileNpcService.new(
          character:,
          zone: position.zone,
          x: position.x,
          y: position.y
        ).tile_npc

        npc if npc&.alive? && npc.hostile?
      end
    end
  end
end
