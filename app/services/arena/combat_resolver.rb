# frozen_string_literal: true

module Arena
  # Resolves one Neverlands-style arena attack.
  #
  # The captured client flow makes AP/cost data fight-specific, then resolves a
  # submitted turn into clear outcomes: miss, dodge, block, hit, critical hit,
  # and damage. This service keeps that result shape explicit so player, team,
  # and NPC fights do not drift into separate combat engines.
  class CombatResolver
    BODY_PART_HIT_MODIFIERS = {
      "head" => -10,
      "torso" => 0,
      "stomach" => 5,
      "legs" => -5
    }.freeze

    BODY_PART_DODGE_MODIFIERS = {
      "head" => 3,
      "torso" => 0,
      "stomach" => -2,
      "legs" => -5
    }.freeze

    BODY_PART_BLOCK_MODIFIERS = {
      "head" => -5,
      "torso" => 5,
      "stomach" => 2,
      "legs" => -3
    }.freeze

    BODY_PART_DAMAGE_MULTIPLIERS = {
      "head" => 1.3,
      "torso" => 1.0,
      "stomach" => 1.1,
      "legs" => 0.9
    }.freeze

    BASE_HIT_CHANCE = 85
    BASE_DODGE_CHANCE = 5
    BASE_BLOCK_CHANCE = 45
    BASE_CRIT_CHANCE = 10
    CRITICAL_MULTIPLIER = 2.0
    DEFENSE_DIVISOR = 2
    MIN_DAMAGE = 0

    attr_reader :match, :rng

    def initialize(match:, rng: Random.new)
      @match = match
      @rng = rng
    end

    def resolve_physical_attack(attacker_participation:, defender_participation:, action_key:, body_part:, block: nil)
      action_key = action_key.to_s
      body_part = body_part.to_s

      hit = hit_result(attacker_participation, defender_participation, action_key, body_part)
      return outcome(:miss, action_key:, body_part:, hit:) unless hit[:hit]

      dodge = dodge_result(attacker_participation, defender_participation, action_key, body_part)
      return outcome(:dodge, action_key:, body_part:, hit:, dodge:) if dodge[:dodged]

      block_result_data = {}
      block_success = false
      if block_covers?(block, body_part)
        block_result_data = block_result(attacker_participation, defender_participation, block, body_part)
        block_success = block_result_data[:blocked]
      end

      critical = critical_result(attacker_participation, defender_participation, action_key, body_part)
      damage = damage_amount(attacker_participation, defender_participation, action_key, body_part, critical:, block_success:)

      if block_success
        return outcome(
          :blocked,
          action_key:,
          body_part:,
          hit:,
          dodge:,
          block: block.merge(
            "attempted" => true,
            "blocked" => true,
            "damage_reduction" => 0.7,
            "roll" => block_result_data[:roll],
            "chance" => block_result_data[:chance]
          ),
          critical:,
          damage:
        )
      end

      block_data = block_result_data.present? ? block.merge(
        "attempted" => true,
        "blocked" => false,
        "roll" => block_result_data[:roll],
        "chance" => block_result_data[:chance]
      ) : {}

      outcome(:hit, action_key:, body_part:, hit:, dodge:, block: block_data, critical:, damage:)
    end

    def attack_power(participation)
      if participation.npc?
        npc_stats(participation)[:attack].to_i
      else
        participation.character&.attack_power.to_i
      end
    end

    def defense_power(participation)
      if participation.npc?
        npc_stats(participation)[:defense].to_i
      else
        participation.character&.defense.to_i
      end
    end

    private

    def outcome(type, action_key:, body_part:, hit: {}, dodge: {}, block: {}, critical: {}, damage: 0)
      {
        outcome: type,
        hit: type == :hit,
        miss: type == :miss,
        dodge: type == :dodge,
        blocked: type == :blocked,
        critical: critical.fetch(:critical, false),
        damage: damage.to_i,
        action_key:,
        body_part:,
        hit_roll: hit[:roll],
        hit_chance: hit[:chance],
        dodge_roll: dodge[:roll],
        dodge_chance: dodge[:chance],
        crit_roll: critical[:roll],
        crit_chance: critical[:chance],
        block_key: block["action_key"],
        block_table: block["block_table"],
        block_attempted: block["attempted"] == true,
        block_success: block["blocked"] == true,
        block_roll: block["roll"],
        block_chance: block["chance"]
      }
    end

    def hit_result(attacker, defender, action_key, body_part)
      chance = BASE_HIT_CHANCE
      chance += stat(attacker, :dexterity) * 0.3
      chance += stat(attacker, :accuracy) * 0.5
      chance += Game::Combat::ActionCatalog.attack_hit_bonus(action_key)
      chance += BODY_PART_HIT_MODIFIERS.fetch(body_part, 0)
      chance -= stat(defender, :agility) * 0.2
      chance -= stat(defender, :evasion) * 0.4
      chance = chance.clamp(5.0, 95.0)

      roll = rng.rand(100)
      {hit: roll < chance, roll:, chance: chance.round(1)}
    end

    def dodge_result(attacker, defender, action_key, body_part)
      # New evasion formula:
      # evasion_modifier = (defender.agility * 1.5) / (attacker.agility + 1.0)
      # evasion_chance = (evasion_modifier * 12) - (attacker.luck * 0.3)
      # Clamped to 5-70%
      defender_agility = stat(defender, :agility).to_f
      attacker_agility = stat(attacker, :agility).to_f
      attacker_luck = stat(attacker, :luck).to_f

      evasion_modifier = (defender_agility * 1.5) / (attacker_agility + 1.0)
      chance = (evasion_modifier * 12) - (attacker_luck * 0.3)
      chance += BODY_PART_DODGE_MODIFIERS.fetch(body_part, 0)
      chance -= 10 if action_key == "aimed"
      chance = chance.clamp(5.0, 70.0)

      roll = rng.rand(100)
      {dodged: roll < chance, roll:, chance: chance.round(1)}
    end

    def critical_result(attacker, defender, action_key, body_part)
      # New critical formula:
      # crit_modifier = (attacker.intelligence * 1.5) / (defender.intelligence + 1.0)
      # crit_chance = (crit_modifier * 10) + (attacker.luck * 0.5)
      # Clamped to 5-75%
      attacker_intelligence = stat(attacker, :intelligence).to_f
      defender_intelligence = stat(defender, :intelligence).to_f
      attacker_luck = stat(attacker, :luck).to_f

      crit_modifier = (attacker_intelligence * 1.5) / (defender_intelligence + 1.0)
      chance = (crit_modifier * 10) + (attacker_luck * 0.5)
      chance += 10 if action_key == "aimed"
      chance += 5 if body_part == "head"
      chance += 2 if body_part == "stomach"
      chance -= 3 if body_part == "legs"
      chance = chance.clamp(5.0, 75.0)

      roll = rng.rand(100)
      {critical: roll < chance, roll:, chance: chance.round(1)}
    end

    def block_result(attacker, defender, block, body_part)
      # New block formula (only if shield equipped):
      # block_chance = (10 + (defender.vitality * 0.2)).clamp(0, 50)
      covered_parts = Array(block["body_parts"]).map(&:to_s)
      defender_vitality = stat(defender, :vitality).to_f

      # Check if defender has a shield equipped
      has_shield = defender_has_shield?(defender)

      if has_shield
        chance = 10 + (defender_vitality * 0.2)
        chance += BODY_PART_BLOCK_MODIFIERS.fetch(body_part, 0)
        chance -= [covered_parts.size - 1, 0].max * 4
        chance = chance.clamp(0.0, 50.0)
      else
        # Without shield, use reduced block chance
        chance = (defender_vitality * 0.1).clamp(0.0, 25.0)
      end

      roll = rng.rand(100)
      {blocked: roll < chance, roll:, chance: chance.round(1)}
    end

    def damage_amount(attacker, defender, action_key, body_part, critical:, block_success: false)
      # New damage formula:
      # min_damage = (strength * 0.4) + weapon_min_damage
      # max_damage = (strength * 0.8) + weapon_max_damage
      # base_hit = rand(min_damage..max_damage)
      attacker_strength = stat(attacker, :strength).to_f
      weapon_min = weapon_min_damage(attacker)
      weapon_max = weapon_max_damage(attacker)

      min_damage = (attacker_strength * 0.4) + weapon_min
      max_damage = (attacker_strength * 0.8) + weapon_max

      # Random damage in range
      base_damage = if max_damage > min_damage
        rng.rand(min_damage..max_damage)
      else
        min_damage
      end

      # Apply body part multiplier
      base_damage *= BODY_PART_DAMAGE_MULTIPLIERS.fetch(body_part, 1.0)

      # Apply critical multiplier if critical hit
      base_damage = (base_damage * CRITICAL_MULTIPLIER) if critical[:critical]

      # Apply block damage reduction if blocked (30% of incoming damage)
      damage_after_block = block_success ? (base_damage * 0.3) : base_damage

      # Apply armor reduction:
      # armor_reduction = (defender.vitality * 0.15) + defender.equipment_armor
      defender_vitality = stat(defender, :vitality).to_f
      defender_armor = equipment_armor(defender)
      armor_reduction = (defender_vitality * 0.15) + defender_armor

      # Final damage (minimum 1)
      final_damage = damage_after_block - armor_reduction
      [final_damage.round, 1].max
    end

    def block_covers?(block, body_part)
      return false if block.blank?

      Array(block["body_parts"]).map(&:to_s).include?(body_part)
    end

    def stat(participation, stat_name)
      if participation.npc?
        npc_stats(participation)[stat_name].to_i
      else
        character_stat(participation.character, stat_name)
      end
    end

    def character_stat(character, stat_name)
      return 0 unless character
      return character.critical_chance if stat_name == :critical_chance
      return character.agility if stat_name == :agility
      return character.stats.get(:vitality).to_i if stat_name == :vitality
      return character.stats.get(:intelligence).to_i if stat_name == :intelligence

      direct = character.public_send(stat_name) if character.respond_to?(stat_name)
      return direct.to_i if direct.present?

      character.stats.get(stat_name).to_i
    end

    def npc_stats(participation)
      npc = participation.npc_template
      config = Game::World::ArenaNpcConfig.find_npc(npc&.npc_key)
      stats = if config
        Game::World::ArenaNpcConfig.extract_stats(config)
      else
        npc&.combat_stats || {}
      end

      stats.with_indifferent_access
    end

    def defender_has_shield?(participation)
      return false unless participation.character&.inventory

      participation.character.inventory.inventory_items.equipped.includes(:item_template).any? do |item|
        item.item_template&.slot == "shield" || item.item_template&.family == "shield"
      end
    end

    def weapon_min_damage(participation)
      return 5 unless participation.character&.inventory

      participation.character.inventory.inventory_items.equipped.includes(:item_template).sum do |item|
        template = item.item_template
        next 0 unless template&.slot == "weapon" || template&.family == "weapon"

        stats = template.stat_modifiers || {}
        (stats["damage_min"] || stats[:damage_min] || stats["min_damage"] || stats[:min_damage] || 0).to_f
      end + 5
    end

    def weapon_max_damage(participation)
      return 10 unless participation.character&.inventory

      participation.character.inventory.inventory_items.equipped.includes(:item_template).sum do |item|
        template = item.item_template
        next 0 unless template&.slot == "weapon" || template&.family == "weapon"

        stats = template.stat_modifiers || {}
        (stats["damage_max"] || stats[:damage_max] || stats["max_damage"] || stats[:max_damage] || 0).to_f
      end + 10
    end

    def equipment_armor(participation)
      return 0 unless participation.character&.inventory

      participation.character.inventory.inventory_items.equipped.includes(:item_template).sum do |item|
        stats = item.item_template&.stat_modifiers || {}
        (stats["defense"] || stats[:defense] || stats["armor"] || stats[:armor] || stats["armor_class"] || stats[:armor_class] || 0).to_f
      end
    end
  end
end
