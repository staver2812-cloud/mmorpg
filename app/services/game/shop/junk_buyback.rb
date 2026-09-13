# frozen_string_literal: true

module Game
  module Shop
    # License-free Ashen junk buyback for craft materials at the junk dealer.
    class JunkBuyback
      Result = Struct.new(:success, :message, :paid, keyword_init: true)

      PRICES = {
        "wood_chips" => 1,
        "rat_tail" => 2,
        "ashen_bait" => 2,
        "ashen_bandage" => 4
      }.freeze

      def initialize(character:, item_key:, quantity: 1)
        @character = character
        @item_key = item_key.to_s
        @quantity = [quantity.to_i, 1].max
      end

      def call
        price_each = PRICES[item_key]
        return failure("Скупщик это не берёт.") unless price_each

        character.with_lock do
          character.reload
          template = ItemTemplate.find_by(key: item_key)
          return failure("Предмет не найден.") unless template

          inventory = character.inventory
          return failure("Инвентарь пуст.") unless inventory

          have = inventory.inventory_items.where(item_template: template, equipped: false).sum(:quantity)
          return failure("Недостаточно предметов.") if have < quantity

          Game::Inventory::Manager.new(inventory:).remove_item!(item_template: template, quantity:)
          paid = price_each * quantity
          wallet = character.user.currency_wallet || character.user.create_currency_wallet!(nv_balance: 0)
          wallet.adjust!(
            amount: paid,
            reason: "ashen.junk_buyback",
            metadata: {"item_key" => item_key, "quantity" => quantity}
          )

          Result.new(
            success: true,
            paid:,
            message: I18n.t("game.buildings.junk_sold", name: template.display_name, amount: paid, qty: quantity)
          )
        end
      rescue StandardError => error
        raise unless error.class.name.end_with?("InventoryUnderflowError")

        failure("Недостаточно предметов.")
      end

      def self.offer_rows_for(character)
        inventory = character.inventory
        return [] unless inventory

        PRICES.filter_map do |key, price|
          template = ItemTemplate.find_by(key:)
          next unless template

          qty = inventory.inventory_items.where(item_template: template, equipped: false).sum(:quantity)
          next if qty <= 0

          {key:, name: template.display_name, quantity: qty, price:}
        end
      end

      private

      attr_reader :character, :item_key, :quantity

      def failure(message)
        Result.new(success: false, message:, paid: 0)
      end
    end
  end
end
