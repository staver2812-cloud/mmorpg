# frozen_string_literal: true

module Game
  module World
    # Clears sticky post-fight chrome when a match already completed but the
    # player never pressed Finish (common after DefeatRecovery redirects).
    class DismissCompletedFight
      Result = Struct.new(:dismissed, :recovery, keyword_init: true)

      def initialize(character:)
        @character = character
      end

      def call
        dismissed = false
        recovery = nil

        character.arena_participations.includes(:arena_match).find_each do |participation|
          match = participation.arena_match
          next unless match&.completed?
          next if participation.metadata.to_h["finished_at"].present?

          participation.with_lock do
            participation.reload
            next if participation.metadata.to_h["finished_at"].present?

            participation.metadata = participation.metadata.to_h.merge(
              "finished_at" => Time.current.iso8601,
              "dismissed_via" => "shell"
            )
            participation.save!
            dismissed = true
          end
        end

        if character.in_combat?
          character.exit_combat!
          dismissed = true
        end

        dismissed = true if clear_stale_pulse_ambushes!

        recovery = DefeatRecovery.new(character:).call if character.reload.current_hp.to_i <= 0
        Result.new(dismissed:, recovery:)
      end

      private

      attr_reader :character

      # Pulse ambushes that never reached end_match leave yellow bot labels on the
      # outdoor map. Sweep orphan ashen_ambush_* rows that no live match owns.
      def clear_stale_pulse_ambushes!
        return false if character.arena_participations.joins(:arena_match).merge(ArenaMatch.active).exists?

        cleared = false
        remembered_id = character.metadata.to_h.dig("live_ambush", "tile_npc_id")
        if remembered_id
          npc = TileNpc.find_by(id: remembered_id)
          if npc && ambush_npc?(npc)
            npc.destroy!
            cleared = true
          end
        end

        position = character.position
        if position
          npc = TileNpc.find_by(zone: position.zone.name, x: position.x, y: position.y)
          if npc && ambush_npc?(npc)
            npc.destroy!
            cleared = true
          end
        end

        TileNpc.where("npc_key LIKE ?", "ashen_ambush_%").find_each do |npc|
          next if live_match_owns_tile_npc?(npc.id)

          npc.destroy!
          cleared = true
        rescue ActiveRecord::RecordNotFound
          next
        end

        if cleared && character.metadata.to_h["live_ambush"].present?
          character.update!(
            metadata: character.metadata.to_h.except("live_ambush")
          )
        end

        cleared
      end

      def ambush_npc?(npc)
        meta = npc.metadata.to_h
        npc.npc_key.to_s.start_with?("ashen_ambush_") ||
          meta["source"].to_s == "world_live_ambush" ||
          meta["ambush_label"].present?
      end

      def live_match_owns_tile_npc?(tile_npc_id)
        ArenaMatch.active.where("metadata->>'tile_npc_id' = ?", tile_npc_id.to_s).exists?
      end
    end
  end
end
