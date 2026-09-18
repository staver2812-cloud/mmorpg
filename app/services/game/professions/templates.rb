# frozen_string_literal: true

module Game
  module Professions
    # Ensures craftable Ashen consumable/material templates exist at runtime.
    class Templates
      def self.ensure_craft_items!
        ensure_item!(
          key: "wood_chips",
          name: "Щепа Смолы",
          item_type: "material",
          slot: "material",
          weight: 1,
          stack_limit: 99,
          base_price: 2,
          enhancement_rules: {
            "inventory_family" => "things",
            "subcategory" => "misc",
            "source_name" => "Щепа Смолы",
            "shop" => {"sold" => true, "mode" => "buy", "position" => 80},
            "shop_stock" => {"current" => 500, "max" => 500}
          }
        )
        ensure_item!(
          key: "rat_tail",
          name: "Хвост Крысы Завесы",
          item_type: "material",
          slot: "material",
          weight: 1,
          stack_limit: 99,
          base_price: 3
        )
        ensure_item!(
          key: "ashen_bait",
          name: "Приманка Завесы",
          item_type: "material",
          slot: "material",
          weight: 1,
          stack_limit: 99,
          base_price: 5
        )
        ensure_item!(
          key: "ashen_bandage",
          name: "Пепельный бинт",
          item_type: "consumable",
          slot: "none",
          weight: 1,
          stack_limit: 20,
          base_price: 12,
          stat_modifiers: {"heal_hp" => 40, "clear_light_injury" => true},
          enhancement_rules: {
            "inventory_family" => "things",
            "subcategory" => "consumables",
            "source_name" => "Пепельный бинт",
            "description" => "Полевой бинт Смолокура. +40 HP и снимает лёгкие травмы."
          }
        )
        ensure_item!(
          key: "veil_field_kit",
          name: "Полевой набор Завесы",
          item_type: "consumable",
          slot: "none",
          weight: 2,
          stack_limit: 10,
          base_price: 35,
          stat_modifiers: {"heal_hp" => 80, "clear_light_injury" => true},
          enhancement_rules: {
            "inventory_family" => "things",
            "subcategory" => "consumables",
            "source_name" => "Полевой набор Завесы",
            "description" => "Усиленный набор Смолокура. +80 HP и снимает лёгкие травмы."
          }
        )
        ensure_item!(
          key: "ash_herb",
          name: "Пепельная трава",
          item_type: "material",
          slot: "material",
          weight: 1,
          stack_limit: 99,
          base_price: 4,
          enhancement_rules: {
            "inventory_family" => "things",
            "subcategory" => "misc",
            "source_name" => "Пепельная трава",
            "description" => "Трава берега для сумок лекаря."
          }
        )
        ensure_item!(
          key: "healer_bag_light",
          name: "Сумка новичка-лекаря",
          item_type: "consumable",
          slot: "none",
          weight: 1,
          stack_limit: 20,
          base_price: 40,
          stat_modifiers: {"heal_hp" => 30, "clear_injury_tier" => "light"},
          enhancement_rules: {
            "inventory_family" => "things",
            "subcategory" => "aid_kits",
            "source_name" => "Сумка новичка-лекаря",
            "description" => "Снимает лёгкие травмы и лечит 30 HP."
          }
        )
        ensure_item!(
          key: "healer_bag_heavy",
          name: "Сумка опытного лекаря",
          item_type: "consumable",
          slot: "none",
          weight: 2,
          stack_limit: 10,
          base_price: 90,
          stat_modifiers: {"heal_hp" => 60, "clear_injury_tier" => "heavy"},
          enhancement_rules: {
            "inventory_family" => "things",
            "subcategory" => "aid_kits",
            "source_name" => "Сумка опытного лекаря",
            "description" => "Снимает лёгкие и тяжёлые травмы, лечит 60 HP."
          }
        )
        ensure_item!(
          key: "healer_bag_combat",
          name: "Сумка мастера-лекаря",
          item_type: "consumable",
          slot: "none",
          weight: 3,
          stack_limit: 5,
          base_price: 200,
          stat_modifiers: {"heal_hp" => 100, "clear_injury_tier" => "combat"},
          enhancement_rules: {
            "inventory_family" => "things",
            "subcategory" => "aid_kits",
            "source_name" => "Сумка мастера-лекаря",
            "description" => "Снимает любые травмы, включая боевые. Лечит 100 HP."
          }
        )
        ensure_item!(
          key: "assault_scroll_peaceful",
          name: "Свиток нападения (Мирный)",
          item_type: "consumable",
          slot: "none",
          weight: 1,
          stack_limit: 20,
          base_price: 0,
          stat_modifiers: {"assault_scroll_kind" => "peaceful"},
          enhancement_rules: {
            "inventory_family" => "things",
            "subcategory" => "scrolls",
            "source_name" => "Свиток нападения (Мирный)",
            "description" => "PvP без гарантированной травмы. Списывается при «Напасть» или заявке арены.",
            "premium_currency" => "veil_marks",
            "premium_price" => 8,
            "assault_scroll" => true
          }
        )
        ensure_item!(
          key: "assault_scroll_normal",
          name: "Свиток нападения (Обычный)",
          item_type: "consumable",
          slot: "none",
          weight: 1,
          stack_limit: 20,
          base_price: 0,
          stat_modifiers: {"assault_scroll_kind" => "normal"},
          enhancement_rules: {
            "inventory_family" => "things",
            "subcategory" => "scrolls",
            "source_name" => "Свиток нападения (Обычный)",
            "description" => "Стандартная PvP-травматичность (лёгкая/средняя). Списывается при нападении.",
            "premium_currency" => "veil_marks",
            "premium_price" => 15,
            "assault_scroll" => true
          }
        )
        ensure_item!(
          key: "assault_scroll_bloody",
          name: "Свиток нападения (Кровавый)",
          item_type: "consumable",
          slot: "none",
          weight: 1,
          stack_limit: 20,
          base_price: 0,
          stat_modifiers: {"assault_scroll_kind" => "bloody"},
          enhancement_rules: {
            "inventory_family" => "things",
            "subcategory" => "scrolls",
            "source_name" => "Свиток нападения (Кровавый)",
            "description" => "Гарантирует тяжёлую травму проигравшему. Списывается при нападении.",
            "premium_currency" => "veil_marks",
            "premium_price" => 35,
            "assault_scroll" => true
          }
        )
        ensure_item!(
          key: "combat_trauma_scroll",
          name: "Свиток боевой травмы (наследие)",
          item_type: "consumable",
          slot: "none",
          weight: 1,
          stack_limit: 20,
          base_price: 0,
          stat_modifiers: {"assault_scroll_kind" => "bloody"},
          enhancement_rules: {
            "inventory_family" => "things",
            "subcategory" => "scrolls",
            "source_name" => "Свиток боевой травмы",
            "description" => "Устаревший ключ: работает как Кровавый свиток нападения.",
            "premium_currency" => "veil_marks",
            "premium_price" => 35,
            "assault_scroll" => true,
            "legacy_bloody" => true
          }
        )
        ensure_item!(
          key: "protection_scroll",
          name: "Свиток защиты",
          item_type: "consumable",
          slot: "none",
          weight: 1,
          stack_limit: 20,
          base_price: 0,
          stat_modifiers: {"join_as_protector" => true},
          enhancement_rules: {
            "inventory_family" => "things",
            "subcategory" => "scrolls",
            "source_name" => "Свиток защиты",
            "description" => "Позволяет войти в любой идущий бой защитником стороны А или Б.",
            "premium_currency" => "veil_marks",
            "premium_price" => 25,
            "protection_scroll" => true
          }
        )
        ensure_item!(
          key: "combat_heal_scroll",
          name: "Свиток снятия боевой травмы",
          item_type: "consumable",
          slot: "none",
          weight: 1,
          stack_limit: 20,
          base_price: 0,
          stat_modifiers: {"clear_injury_tier" => "combat", "heal_hp" => 50},
          enhancement_rules: {
            "inventory_family" => "things",
            "subcategory" => "scrolls",
            "source_name" => "Свиток снятия боевой травмы",
            "description" => "Снимает тяжёлые и боевые травмы. Покупается за Veil Marks.",
            "premium_currency" => "veil_marks",
            "premium_price" => 20
          }
        )
      end

      def self.ensure_item!(attrs)
        item = ItemTemplate.find_or_initialize_by(key: attrs.fetch(:key))
        item.assign_attributes(
          name: attrs.fetch(:name),
          item_type: attrs.fetch(:item_type),
          slot: attrs.fetch(:slot),
          weight: attrs.fetch(:weight),
          stack_limit: attrs.fetch(:stack_limit),
          base_price: attrs[:base_price] || 0,
          durability_max: attrs[:durability_max] || 1,
          requirements: attrs[:requirements] || {},
          stat_modifiers: attrs[:stat_modifiers] || {},
          enhancement_rules: attrs[:enhancement_rules] || item.enhancement_rules.to_h
        )
        item.save!
        item
      end
      private_class_method :ensure_item!
    end
  end
end
