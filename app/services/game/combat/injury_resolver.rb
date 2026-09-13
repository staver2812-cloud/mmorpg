# frozen_string_literal: true

module Game
  module Combat
    # Applies Ashen injury outcomes after a completed fight.
    # Defeat: trauma_percent chance of heavy (blocks outdoor move) else light.
    # Victory: small light-injury chance scaled by trauma_percent.
    class InjuryResolver
      Result = Struct.new(:applied, :severity, :message, keyword_init: true)

      def initialize(match:, rng: Random.new, clock: -> { Time.current })
        @match = match
        @rng = rng
        @clock = clock
      end

      def call
        trauma = match.metadata.to_h["trauma_percent"].to_i
        trauma = 30 if trauma <= 0
        applied = []

        match.arena_participations.players.includes(:character).find_each do |participation|
          character = participation.character
          next unless character

          outcome = resolve_for(participation.result.to_s, trauma)
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

      def resolve_for(result, trauma)
        case result
        when "defeat"
          chance = [[trauma, 95].min, 25].max
          if rng.rand(100) < chance
            {
              severity: "heavy",
              duration: 2.hours,
              message: "Тяжёлая травма: выход в дикие клетки закрыт, пока не полечитесь в Лазарете."
            }
          else
            {
              severity: "light",
              duration: 45.minutes,
              message: "Лёгкая травма: заживает со временем или в Лазарете."
            }
          end
        when "victory"
          chance = (trauma / 4.0).floor
          return nil if chance <= 0 || rng.rand(100) >= chance

          {
            severity: "light",
            duration: 20.minutes,
            message: "Лёгкая травма после тяжёлого боя."
          }
        end
      end
    end
  end
end
