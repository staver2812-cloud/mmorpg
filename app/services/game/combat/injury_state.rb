# frozen_string_literal: true

module Game
  module Combat
    # Ashen sandbox injury state on character.metadata.
    # Explicitly sandbox-tuned (not Neverlands-parity probabilities).
    class InjuryState
      METADATA_KEY = "ashen_injuries"
      SEVERITIES = %w[light heavy].freeze

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
        active.any? { |row| row["severity"].to_s == "heavy" }
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

      # Field bandages clear light injuries only. Heavy trauma stays hospital-only.
      # @return [Integer] number of light injuries removed
      def clear_light!
        character.with_lock do
          character.reload
          metadata = character.metadata.to_h
          rows = Array(metadata[METADATA_KEY]).map(&:deep_stringify_keys)
          keep = rows.select { |row| active_row?(row) && row["severity"].to_s != "light" }
          removed = rows.count { |row| active_row?(row) && row["severity"].to_s == "light" }
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
          key = (row["severity"].to_s == "heavy") ? "heavy" : "light"
          I18n.t("game.injuries.severity.#{key}")
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
