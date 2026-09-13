# frozen_string_literal: true

module Game
  module World
    # One-time Ashen sandbox starter kit for a newly created character.
    # Grants bait, starter NV, and a free equipped blade so the shore loop is
    # reachable without an empty wallet or bare fists.
    class StarterKit
      METADATA_KEY = "ashen_starter_kit_v2"
      LEGACY_METADATA_KEYS = %w[ashen_starter_kit_v1].freeze
      STARTER_NV = 100
      NV_REASON = "ashen.starter_kit_nv"
      WEAPON_KEY = "ashen_starter_blade"

      def initialize(character:)
        @character = character
      end

      def call
        character.with_lock do
          character.reload
          grant_bait!
          grant_starter_nv!
          grant_weapon!
          mark_granted!
        end

        character
      end

      def self.ensure_weapon_template!
        ItemTemplate.find_or_initialize_by(key: WEAPON_KEY).tap do |item|
          item.assign_attributes(
            name: "Клинок Угля",
            item_type: "equipment",
            slot: "main_hand",
            weight: 2,
            stack_limit: 1,
            base_price: 1,
            durability_max: 40,
            requirements: {},
            stat_modifiers: {"attack" => 3, "accuracy" => 2},
            enhancement_rules: {
              "inventory_family" => "weapons",
              "subcategory" => "swords",
              "source_name" => "Клинок Угля",
              "description" => "Стартовый клинок Пепельной Завесы.",
              "shop" => {"sold" => true, "mode" => "buy", "position" => 5},
              "shop_stock" => {"current" => 200, "max" => 200}
            }
          )
          item.save!
        end
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

      def grant_weapon!
        template = self.class.ensure_weapon_template!
        inventory = character.inventory || character.create_inventory!
        owned = inventory.inventory_items.find_by(item_template: template)
        unless owned
          owned = Game::Inventory::Manager.new(inventory:).add_item!(item_template: template, quantity: 1)
        end
        return if owned.equipped?

        Game::Inventory::EquipmentService.new(character:, item: owned.reload).equip!
      end

      def mark_granted!
        metadata = character.metadata.to_h.except(*LEGACY_METADATA_KEYS)
        character.update!(
          metadata: metadata.merge(
            METADATA_KEY => {
              "granted_at" => Time.current.iso8601(6),
              "bait" => Bait::STARTER_GRANT,
              "nv" => STARTER_NV,
              "weapon" => WEAPON_KEY
            }
          )
        )
      end
    end
  end
end
