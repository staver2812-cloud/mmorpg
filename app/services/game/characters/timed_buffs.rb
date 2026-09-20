# frozen_string_literal: true

module Game
  module Characters
    # Persists and resolves expiring character modifiers in character metadata.
    class TimedBuffs
      METADATA_KEY = "active_buffs"
      DEFAULT_DURATION = 1.hour.to_i

      def initialize(character:, clock: -> { Time.current })
        @character = character
        @clock = clock
      end

      def apply!(key:, label:, mods:, duration_seconds: DEFAULT_DURATION)
        now = clock.call
        entry = {
          "key" => key.to_s,
          "label" => label.to_s,
          "expires_at" => (now + duration_seconds.to_i).iso8601,
          "mods" => normalize_mods(mods)
        }

        character.with_lock do
          character.reload
          retained = stored_buffs.select { |buff| active?(buff, now:) && buff["key"].to_s != entry["key"] }
          persist!(retained << entry)
        end
        entry
      end

      def active
        now = clock.call
        current = stored_buffs
        retained = current.select { |buff| active?(buff, now:) }
        persist!(retained) if retained.size != current.size
        retained
      end

      def modifier(key)
        active.sum { |buff| buff.fetch("mods", {}).fetch(key.to_s, 0).to_f }
      end

      private

      attr_reader :character, :clock

      def stored_buffs
        Array(character.metadata.to_h[METADATA_KEY]).filter_map do |buff|
          buff.deep_stringify_keys if buff.is_a?(Hash)
        end
      end

      def active?(buff, now:)
        expires_at = Time.zone.parse(buff["expires_at"].to_s)
        expires_at.present? && expires_at > now
      rescue ArgumentError, TypeError
        false
      end

      def normalize_mods(mods)
        mods.to_h.each_with_object({}) do |(key, value), normalized|
          number = Float(value, exception: false)
          normalized[key.to_s] = number if number
        end
      end

      def persist!(buffs)
        character.update_column(:metadata, character.metadata.to_h.merge(METADATA_KEY => buffs))
      end
    end
  end
end
