# frozen_string_literal: true

module Game
  module Shop
    # License-free Ashen junk buyback for craft materials and surplus T5 drops.
    class JunkBuyback
      Result = Struct.new(:success, :message, :paid, keyword_init: true)

      PRICES = {
        "wood_chips" => 1,
        "rat_tail" => 2,
        "ashen_bait" => 2,
        "ashen_bandage" => 4,
        "ash_herb" => 2
      }.freeze

      T5_SET_PRICE = 8
      T5_SET_PATTERN = /\Aset-.+-t5\z/

      def initialize(character:, item_key:, quantity: 1)
        @character = character
        @item_key = item_key.to_s
        @quantity = [quantity.to_i, 1].max
      end

      def call
        price_each = price_for(item_key)
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

      def self.price_for(item_key)
        key = item_key.to_s
        return PRICES[key] if PRICES.key?(key)
        return T5_SET_PRICE if key.match?(T5_SET_PATTERN)

        nil
      end

      def self.offer_rows_for(character)
        inventory = character.inventory
        return [] unless inventory

        rows = []
        PRICES.each do |key, price|
          template = ItemTemplate.find_by(key:)
          next unless template

          qty = inventory.inventory_items.where(item_template: template, equipped: false).sum(:quantity)
          next if qty <= 0

          rows << {key:, name: template.display_name, quantity: qty, price:}
        end

        t5_qty = Hash.new(0)
        t5_names = {}
        inventory.inventory_items.includes(:item_template).where(equipped: false).find_each do |row|
          key = row.item_template.key
          next if PRICES.key?(key)
          next unless key.match?(T5_SET_PATTERN)

          t5_qty[key] += row.quantity
          t5_names[key] = row.item_template.display_name
        end
        t5_qty.each do |key, qty|
          rows << {key:, name: t5_names[key], quantity: qty, price: T5_SET_PRICE}
        end

        rows
      end

      private

      attr_reader :character, :item_key, :quantity

      def price_for(key)
        self.class.price_for(key)
      end

      def failure(message)
        Result.new(success: false, message:, paid: 0)
      end
    end
  end
end
