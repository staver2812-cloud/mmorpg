# frozen_string_literal: true

module Game
  module World
    # One-time Ashen sandbox starter kit for a newly created character.
    # Grants bait and starter NV so the outdoor fight loop is reachable without
    # waiting for the five-minute passive ambush or an empty wallet.
    class StarterKit
      METADATA_KEY = "ashen_starter_kit_v1"
      STARTER_NV = 100
      NV_REASON = "ashen.starter_kit_nv"

      def initialize(character:)
        @character = character
      end

      def call
        character.with_lock do
          character.reload
          metadata = character.metadata.to_h
          return character if metadata[METADATA_KEY].present?

          grant_bait!
          grant_starter_nv!
          character.update!(
            metadata: metadata.merge(
              METADATA_KEY => {
                "granted_at" => Time.current.iso8601(6),
                "bait" => Bait::STARTER_GRANT,
                "nv" => STARTER_NV
              }
            )
          )
        end

        character
      end

      private

      attr_reader :character

      def grant_bait!
        template = Bait.item_template
        return unless template

        inventory = character.inventory || character.create_inventory!
        existing = Bait.new(character:).quantity
        need = Bait::STARTER_GRANT - existing
        return if need <= 0

        Game::Inventory::Manager.new(inventory:).add_item!(item_template: template, quantity: need)
      end

      def grant_starter_nv!
        user = character.user
        return unless user

        wallet = user.currency_wallet || user.create_currency_wallet!(nv_balance: 0)
        wallet.with_lock do
          next if wallet.currency_transactions.where(reason: NV_REASON).exists?

          wallet.adjust!(
            amount: STARTER_NV,
            reason: NV_REASON,
            metadata: {"source" => "ashen_starter_kit", "character_id" => character.id}
          )
        end
      end
    end
  end
end
