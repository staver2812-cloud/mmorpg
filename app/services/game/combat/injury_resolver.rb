# frozen_string_literal: true

module Game
  module Combat
    # Applies Ashen injury outcomes after a completed fight.
    # Combat trauma matches (PvP with combat scroll) apply combat severity on defeat.
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

          outcome = resolve_for(participation.result.to_s, trauma, combat:)
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

      def resolve_for(result, trauma, combat:)
        case result
        when "defeat"
          if combat
            return {
              severity: "combat",
              duration: 12.hours,
              message: I18n.t("game.injuries.applied_combat")
            }
          end

          chance = [[trauma, 95].min, 25].max
          if rng.rand(100) < chance
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

          chance = (trauma / 4.0).floor
          return nil if chance <= 0 || rng.rand(100) >= chance

          {
            severity: "light",
            duration: 20.minutes,
            message: I18n.t("game.injuries.applied_light_win")
          }
        end
      end

      def truthy?(value)
        value == true || value.to_s == "true" || value.to_i == 1
      end
    end
  end
end
