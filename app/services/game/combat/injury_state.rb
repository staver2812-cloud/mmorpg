# frozen_string_literal: true

module Game
  module Combat
    # Ashen sandbox injury state on character.metadata.
    # Severities: light < heavy < combat.
    # Combat trauma only comes from PvP matches that consumed a combat scroll.
    class InjuryState
      METADATA_KEY = "ashen_injuries"
      SEVERITIES = %w[light heavy combat].freeze
      RANK = {"light" => 1, "heavy" => 2, "combat" => 3}.freeze

      def initialize(character:, clock: -> { Time.current })
        @character = character
        @clock = clock
      end

      def active
        purge_expired!
        Array(character.metadata.to_h[METADATA_KEY]).select { |row| active_row?(row) }
      end

      def any?
        active.any?
      end

      def blocks_movement?
        active.any? { |row| %w[heavy combat].include?(row["severity"].to_s) }
      end

      def apply!(severity:, duration:, source_match_id: nil)
        raise ArgumentError, "unknown severity" unless SEVERITIES.include?(severity.to_s)

        character.with_lock do
          character.reload
          rows = Array(character.metadata.to_h[METADATA_KEY]).map(&:deep_stringify_keys)
          rows.reject! { |row| !active_row?(row) }
          rows << {
            "severity" => severity.to_s,
            "expires_at" => (clock.call + duration).iso8601(6),
            "source_match_id" => source_match_id,
            "applied_at" => clock.call.iso8601(6)
          }
          character.update!(metadata: character.metadata.to_h.merge(METADATA_KEY => rows))
        end
      end

      def clear_all!
        character.with_lock do
          character.reload
          metadata = character.metadata.to_h
          return unless metadata.key?(METADATA_KEY)

          character.update!(metadata: metadata.except(METADATA_KEY))
        end
      end

      # Free hospital rest clears ordinary wounds, not paid combat trauma.
      def clear_non_combat!
        clear_up_to!("heavy")
      end

      def clear_light!
        clear_up_to!("light")
      end

      # Clears active injuries whose rank is <= the given severity.
      # @return [Integer] removed count
      def clear_up_to!(max_severity)
        max_rank = RANK.fetch(max_severity.to_s)
        character.with_lock do
          character.reload
          metadata = character.metadata.to_h
          rows = Array(metadata[METADATA_KEY]).map(&:deep_stringify_keys)
          keep = []
          removed = 0
          rows.each do |row|
            next unless active_row?(row)

            rank = RANK.fetch(row["severity"].to_s, 0)
            if rank.positive? && rank <= max_rank
              removed += 1
            else
              keep << row
            end
          end
          return 0 if removed.zero?

          character.update!(metadata: metadata.merge(METADATA_KEY => keep))
          removed
        end
      end

      def summary_ru
        summary
      end

      def summary
        labels = active.map do |row|
          I18n.t("game.injuries.severity.#{row["severity"]}", default: row["severity"].to_s)
        end
        return nil if labels.empty?

        I18n.t("game.injuries.summary", list: labels.join(", "))
      end

      private

      attr_reader :character, :clock

      def purge_expired!
        metadata = character.metadata.to_h
        rows = Array(metadata[METADATA_KEY])
        keep = rows.select { |row| active_row?(row) }
        return if keep.size == rows.size

        character.update!(metadata: metadata.merge(METADATA_KEY => keep))
      end

      def active_row?(row)
        row = row.to_h.deep_stringify_keys
        expires = Time.iso8601(row["expires_at"].to_s)
        expires > clock.call
      rescue ArgumentError, TypeError
        false
      end
    end
  end
end
