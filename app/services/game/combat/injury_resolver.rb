# frozen_string_literal: true

module Game
  module Combat
    # Applies Ashen injury outcomes after a completed fight.
    #
    # Severity is driven by combat-trauma flag and by critical/head intensity
    # recorded on the defeated participation — never always-light.
    class InjuryResolver
      Result = Struct.new(:applied, :severity, :message, keyword_init: true)

      def initialize(match:, rng: Random.new, clock: -> { Time.current })
        @match = match
        @rng = rng
        @clock = clock
      end

      def call
        trauma = match.metadata.to_h["trauma_percent"].presence || match.try(:trauma_percent)
        trauma = trauma.to_i
        trauma = 30 if trauma <= 0
        combat = truthy?(match.metadata.to_h["combat_trauma"])
        applied = []

        match.arena_participations.players.includes(:character).find_each do |participation|
          character = participation.character
          next unless character

          outcome = resolve_for(participation, trauma, combat:)
          next unless outcome

          InjuryState.new(character:, clock:).apply!(
            severity: outcome.fetch(:severity),
            duration: outcome.fetch(:duration),
            source_match_id: match.id
          )
          applied << Result.new(
            applied: true,
            severity: outcome.fetch(:severity),
            message: outcome.fetch(:message)
          )
        end

        applied
      end

      private

      attr_reader :match, :rng, :clock

      def resolve_for(participation, trauma, combat:)
        case participation.result.to_s
        when "defeat"
          if combat
            return {
              severity: "combat",
              duration: 12.hours,
              message: I18n.t("game.injuries.applied_combat")
            }
          end

          intensity = injury_intensity(participation, trauma)
          if intensity >= 8
            {
              severity: "heavy",
              duration: 3.hours,
              message: I18n.t("game.injuries.applied_heavy")
            }
          elsif intensity >= 4 || rng.rand(100) < [[trauma, 95].min, 25].max
            {
              severity: "heavy",
              duration: 2.hours,
              message: I18n.t("game.injuries.applied_heavy")
            }
          else
            {
              severity: "light",
              duration: 45.minutes,
              message: I18n.t("game.injuries.applied_light")
            }
          end
        when "victory"
          return nil if combat

          intensity = injury_intensity(participation, trauma / 2)
          return nil if intensity < 2 && rng.rand(100) >= (trauma / 4.0).floor

          if intensity >= 5
            {
              severity: "heavy",
              duration: 45.minutes,
              message: I18n.t("game.injuries.applied_heavy")
            }
          else
            {
              severity: "light",
              duration: 20.minutes,
              message: I18n.t("game.injuries.applied_light_win")
            }
          end
        end
      end

      # Crit damage taken and head strikes raise severity; trauma% is a soft floor.
      def injury_intensity(participation, trauma)
        meta = participation.metadata.to_h
        crits = meta["critical_hits_taken"].to_i
        crit_damage = meta["critical_damage_taken"].to_i
        head_hits = meta["head_hits_taken"].to_i
        (
          (crits * 2) +
          (crit_damage / 40) +
          (head_hits * 2) +
          (trauma / 20)
        ).floor
      end

      def truthy?(value)
        value == true || value.to_s == "true" || value.to_i == 1
      end
    end
  end
end
