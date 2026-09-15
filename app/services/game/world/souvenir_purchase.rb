# frozen_string_literal: true

module Game
  module World
    # Souvenir counter: buy small Ashen materials for NV without a trading license.
    class SouvenirPurchase
      Result = Struct.new(:success, :message, keyword_init: true)
      OFFERINGS = {
        "ashen_bait" => 8,
        "wood_chips" => 3,
        "ash_herb" => 5,
        "rat_tail" => 5
      }.freeze

      def initialize(character:, item_key:)
        @character = character
        @item_key = item_key.to_s
      end

      def call
        price = OFFERINGS[item_key]
        return failure(I18n.t("game.buildings.souvenir_unknown")) unless price

        character.with_lock do
          character.reload
          Game::Professions::Templates.ensure_craft_items!
          template = ItemTemplate.find_by(key: item_key)
          return failure(I18n.t("game.buildings.souvenir_unknown")) unless template

          wallet = character.user.currency_wallet || character.user.create_currency_wallet!(nv_balance: 0)
          if wallet.nv_balance.to_i < price
            return failure(I18n.t("game.buildings.souvenir_short", amount: price))
          end

          inventory = character.inventory || character.create_inventory!(slot_capacity: 30, weight_capacity: 100)
          wallet.adjust!(
            amount: -price,
            reason: "ashen.souvenir_buy",
            metadata: {"item_key" => item_key}
          )
          Game::Inventory::Manager.new(inventory:).add_item!(item_template: template, quantity: 1)
          Result.new(
            success: true,
            message: I18n.t("game.buildings.souvenir_bought", name: template.display_name, amount: price)
          )
        end
      rescue StandardError => error
        raise unless error.class.name.end_with?("CapacityExceededError")

        failure(I18n.t("game.buildings.souvenir_full"))
      end

      private

      attr_reader :character, :item_key

      def failure(message)
        Result.new(success: false, message:)
      end
    end
  end
end
