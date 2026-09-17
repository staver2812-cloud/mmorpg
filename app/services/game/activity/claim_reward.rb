# frozen_string_literal: true

module Game
  module Activity
    # Claims NV/XP rewards from completed daily contracts or achievements.
    class ClaimReward
      Result = Struct.new(:success?, :message, keyword_init: true)

      def initialize(character:, kind:, id:)
        @character = character
        @kind = kind.to_s
        @id = id.to_i
      end

      def call
        case kind
        when "contract"
          claim_contract!
        when "achievement"
          claim_achievement!
        else
          Result.new(success?: false, message: I18n.t("game.activity.unknown_kind"))
        end
      end

      private

      attr_reader :character, :kind, :id

      def claim_contract!
        row = DailyActivityContract.lock.find_by!(id:, character:)
        return Result.new(success?: false, message: I18n.t("game.activity.not_ready")) if row.completed_at.blank?
        return Result.new(success?: false, message: I18n.t("game.activity.already_claimed")) if row.claimed_at.present?

        grant!(row.reward.to_h)
        row.update!(claimed_at: Time.current)
        Result.new(success?: true, message: I18n.t("game.activity.claimed"))
      end

      def claim_achievement!
        row = ActivityAchievement.lock.find_by!(id:, character:)
        return Result.new(success?: false, message: I18n.t("game.activity.not_ready")) if row.completed_at.blank?
        return Result.new(success?: false, message: I18n.t("game.activity.already_claimed")) if row.claimed_at.present?

        grant!(row.metadata.to_h.fetch("rewards", {}))
        row.update!(claimed_at: Time.current)
        Result.new(success?: true, message: I18n.t("game.activity.claimed"))
      end

      def grant!(reward)
        nv = reward["nv"].to_i
        xp = reward["xp"].to_i
        if nv.positive?
          wallet = character.user.currency_wallet || character.user.create_currency_wallet!(nv_balance: 0)
          wallet.adjust!(amount: nv, reason: "activity.claim", metadata: {"kind" => kind, "id" => id})
        end
        if xp.positive?
          character.with_lock do
            character.reload
            character.update!(experience: character.experience.to_i + xp)
          end
        end
      end
    end
  end
end
