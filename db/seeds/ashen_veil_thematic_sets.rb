# frozen_string_literal: true

# Port of Ashen Veil thematic sets (packages/game-data/src/thematic-sets.ts):
# tiers 5/10/…/50 (step 5), stats strictly grow with tier, not sold in shop.
return unless defined?(ItemTemplate)

SET_META = {
  "blood" => {"ru" => "Кровь Завесы", "focus" => "strength", "acquisition" => "drop"},
  "demiurge" => {"ru" => "Демиург", "focus" => "intelligence", "acquisition" => "premium"},
  "distortion" => {"ru" => "Искажение", "focus" => "dexterity", "acquisition" => "craft"},
  "judge" => {"ru" => "Судия", "focus" => "armor_class", "acquisition" => "drop"},
  "swamp" => {"ru" => "Топь", "focus" => "hp", "acquisition" => "drop"}
}.freeze

CATALOG_TIERS = [5, 10, 15, 20, 25, 30, 35, 40, 45, 50].freeze

CORE_SLOTS = [
  {"slot" => "main_hand", "key" => "weapon-sword", "label" => "Клинок", "asset" => "weapon-sword.png"},
  {"slot" => "head", "key" => "helm", "label" => "Шлем", "asset" => "helm.png"},
  {"slot" => "chest", "key" => "armor-plate", "label" => "Доспех", "asset" => "armor-plate.png"},
  {"slot" => "hands", "key" => "gloves", "label" => "Перчатки", "asset" => "gloves.png"},
  {"slot" => "bracers", "key" => "bracers", "label" => "Наручи", "asset" => "bracers.png"},
  {"slot" => "feet", "key" => "boots", "label" => "Сапоги", "asset" => "boots.png"},
  {"slot" => "amulet", "key" => "amulet", "label" => "Амулет", "asset" => "amulet.png"},
  {"slot" => "ring", "key" => "ring", "label" => "Кольцо", "asset" => "ring.png"},
  {"slot" => "amulet", "key" => "earring-1", "label" => "Серьга", "asset" => "earring-1.png"},
  {"slot" => "belt", "key" => "waist", "label" => "Пояс", "asset" => "waist.png"}
].freeze

SLOT_SUBCATEGORY = {
  "main_hand" => "weapons",
  "head" => "helmets",
  "chest" => "armor",
  "hands" => "gloves",
  "bracers" => "bracers",
  "feet" => "boots",
  "amulet" => "jewelry",
  "ring" => "jewelry",
  "belt" => "belts",
  "relic" => "relics"
}.freeze

def rarity_for_tier(tier)
  return "ancient" if tier >= 40
  return "mythic" if tier >= 25
  return "epic" if tier >= 12
  return "rare" if tier >= 5

  "common"
end

def set_piece_stats(set_id, tier, nl_slot)
  t = tier.to_i.clamp(1, 50)
  focus = SET_META.fetch(set_id).fetch("focus")
  # Stronger curve: T5 starter kit vs T50 endgame must feel like years of grind.
  stats = {
    "strength" => ((set_id == "blood" || set_id == "judge") ? (t / 3) : (t / 5)) + (t / 20),
    "dexterity" => ((set_id == "distortion" || set_id == "swamp") ? (t / 3) : (t / 5)) + (t / 20),
    "vitality" => ((set_id == "swamp" || set_id == "judge") ? (t / 3) : (t / 5)) + (t / 15),
    "intelligence" => ((set_id == "demiurge" || set_id == "distortion") ? (t / 3) : (t / 5)) + (t / 20),
    "luck" => (t / 6)
  }

  case nl_slot
  when "main_hand"
    dmg = 4 + (t * 1.15).floor
    stats["weapon_family"] = "sword"
    stats["damage_min"] = [2, dmg - 3].max
    stats["damage_max"] = dmg + 2
    stats["accuracy"] = 3 + (t / 3)
    if set_id == "demiurge"
      stats["mana"] = 10 + (t * 2)
      stats["intelligence"] = stats["intelligence"] + 2 + (t / 3)
    end
  when "chest", "head"
    stats["armor_class"] = 2 + (t * 0.75).floor
    stats["hp"] = 12 + (t * 5)
  when "hands", "feet", "bracers"
    stats["armor_class"] = [2, (t / 3)].max
    stats["evasion"] = [2, (t / 3)].max
    stats["dexterity"] = stats["dexterity"] + 1 + (t / 10)
  else
    stats[focus] = stats.fetch(focus, 0) + 2 + (t / 3)
    stats["mana"] = 8 + (t * 2) if focus == "intelligence"
    stats["hp"] = 15 + (t * 4) if focus == "hp"
    stats["armor_class"] = 1 + (t / 4) if focus == "armor_class"
  end

  stats.reject do |k, v|
    v.is_a?(Numeric) && v.to_i <= 0 && !k.to_s.start_with?("weapon", "damage")
  end
end

created = 0
previous_by_slot = Hash.new { |h, k| h[k] = {} }

SET_META.each_key do |set_id|
  meta = SET_META.fetch(set_id)
  CATALOG_TIERS.each do |tier|
    CORE_SLOTS.each do |piece|
      key = "set-#{set_id}-#{piece.fetch("key")}-t#{tier}"
      name = "#{piece.fetch("label")} «#{meta.fetch("ru")}» · T#{tier}"
      stats = set_piece_stats(set_id, tier, piece.fetch("slot"))
      slot_key = "#{set_id}:#{piece.fetch("key")}"

      # Guarantee monotonic growth vs previous catalog tier for numeric combat stats.
      prev = previous_by_slot[slot_key]
      if prev.any?
        %w[strength dexterity vitality intelligence luck armor_class hp mana evasion accuracy damage_min damage_max].each do |stat|
          next unless stats.key?(stat) && prev.key?(stat)
          stats[stat] = [stats[stat].to_i, prev[stat].to_i + 1].max
        end
      end
      previous_by_slot[slot_key] = stats

      item = ItemTemplate.find_or_initialize_by(key: key)
      rules = {
        "subcategory" => SLOT_SUBCATEGORY.fetch(piece.fetch("slot"), "misc"),
        "source_name" => name,
        "set_key" => "set-#{set_id}",
        "set_name" => meta.fetch("ru"),
        "set_tier" => tier,
        "rarity" => rarity_for_tier(tier),
        "acquisition" => meta.fetch("acquisition"),
        "icon" => "/ashen/items/set-#{set_id}/#{piece.fetch("asset")}",
        "shop" => {"sold" => false},
        "description" => "Комплект «#{meta.fetch("ru")}», тир #{tier} (треб. ур. #{tier}). Канал: #{meta.fetch("acquisition")}. Не продаётся в стартовой лавке."
      }
      item.assign_attributes(
        name: name,
        item_type: "equipment",
        slot: piece.fetch("slot"),
        weight: 2 + (tier / 10),
        stack_limit: 1,
        base_price: 20 + (tier * 18),
        durability_max: 20 + (tier * 2),
        requirements: {"level" => tier},
        stat_modifiers: stats,
        enhancement_rules: rules
      )
      item.save!
      created += 1
    end
  end
end

# Named uniques / chests stay outside shop.
UNIQUES = [
  {key: "anchor_cleaver", name: "Якорный Резак", slot: "main_hand", icon: "weapon/anchor-cleaver.png",
   level: 12, price: 420, durability: 55, acquisition: "drop",
   stats: {"weapon_family" => "axe", "damage_min" => 8, "damage_max" => 14, "armor_pierce" => 4, "strength" => 2}},
  {key: "archdeacon_signet", name: "Печатка Архидиакона", slot: "ring", icon: "ring/archdeacon-signet.png",
   level: 25, price: 900, durability: 60, acquisition: "drop",
   stats: {"intelligence" => 4, "luck" => 2, "mana" => 20}},
  {key: "glass_hoop", name: "Стеклянная дужка", slot: "amulet", icon: "earring/glass-hoop.png",
   level: 10, price: 280, durability: 40, acquisition: "drop",
   stats: {"intelligence" => 2, "all_resistances" => 1}},
  {key: "clan_war_chest_bronze", name: "Клановый сундук (бронза)", slot: "relic", icon: "relic/clan-war-chest-bronze.png",
   level: 5, price: 300, durability: 99, acquisition: "drop", stats: {"luck" => 1}},
  {key: "clan_war_chest_silver", name: "Клановый сундук (серебро)", slot: "relic", icon: "relic/clan-war-chest-silver.png",
   level: 15, price: 700, durability: 99, acquisition: "drop", stats: {"luck" => 2}},
  {key: "clan_war_chest_gold", name: "Клановый сундук (золото)", slot: "relic", icon: "relic/clan-war-chest-gold.png",
   level: 30, price: 1500, durability: 99, acquisition: "premium", stats: {"luck" => 3}}
].freeze

UNIQUES.each do |piece|
  item = ItemTemplate.find_or_initialize_by(key: piece[:key])
  item.assign_attributes(
    name: piece[:name],
    item_type: "equipment",
    slot: piece[:slot],
    weight: 3,
    stack_limit: 1,
    base_price: piece[:price],
    durability_max: piece[:durability],
    requirements: {"level" => piece[:level]},
    stat_modifiers: piece[:stats],
    enhancement_rules: {
      "subcategory" => SLOT_SUBCATEGORY.fetch(piece[:slot], "misc"),
      "source_name" => piece[:name],
      "set_key" => "ashen_uniques",
      "acquisition" => piece[:acquisition],
      "icon" => "/ashen/items/#{piece[:icon]}",
      "shop" => {"sold" => false},
      "description" => "Уникальный трофей Пепельной Завесы. Канал: #{piece[:acquisition]}."
    }
  )
  item.save!
end

sample = ItemTemplate.where("key LIKE ?", "set-blood-helm-t%").order(:key).pluck(:key, :requirements, :stat_modifiers)
puts "Ashen thematic sets upserted: #{created} pieces (5 sets × #{CATALOG_TIERS.size} tiers × #{CORE_SLOTS.size} slots)"
puts "Uniques upserted: #{UNIQUES.size}"
if sample.size >= 2
  low = sample.first
  high = sample.last
  puts "Monotonic check blood helm: #{low[0]} lvl=#{low[1]["level"]} armor=#{low[2]["armor_class"]} -> #{high[0]} lvl=#{high[1]["level"]} armor=#{high[2]["armor_class"]}"
end
