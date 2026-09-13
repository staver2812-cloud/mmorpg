# frozen_string_literal: true

module Game
  module World
    # Free Ashen hospital rest: restores HP/MP and clears sandbox injuries when
    # the character is out of combat inside the hospital.
    class HospitalRest
      Result = Struct.new(:success, :message, keyword_init: true)

      def initialize(character:)
        @character = character
      end

      def call
        character.with_lock do
          character.reload
          if character.in_combat?
            return Result.new(success: false, message: I18n.t("game.buildings.hospital_in_combat"))
          end

          injuries = Game::Combat::InjuryState.new(character:)
          max_hp = character.effective_max_hp.to_i
          max_mp = character.effective_max_mp.to_i
          full = character.current_hp.to_i >= max_hp && character.current_mp.to_i >= max_mp
          if full && !injuries.any?
            return Result.new(success: false, message: I18n.t("game.buildings.hospital_already_full"))
          end

          character.update!(current_hp: max_hp, current_mp: max_mp, in_combat: false)
          injuries.clear_all!
          Result.new(success: true, message: I18n.t("game.buildings.hospital_rested_injuries"))
        end
      end

      private

      attr_reader :character
    end
  end
end
