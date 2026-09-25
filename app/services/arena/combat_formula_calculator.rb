# frozen_string_literal: true

module Arena
  # Modernized combat formula calculator
  #
  # NOTE: This service implements explicit mathematical formulas requested
  # via automation for combat modernization. These formulas deviate from
  # the Neverlands evidence-based approach documented in AGENTS.md and
  # doc/design/features/combat.md. Use with caution.
  #
  # Authority: System automation request (2026-09-25)
  # Rationale: Mathematical balance update for ashenveil.net game
  class CombatFormulaCalculator
    CRITICAL_MULTIPLIER = 2.0
    MIN_DAMAGE_FLOOR = 1

    # Calculate maximum HP using the modernized formula
    #
    # @param level [Integer] character level
    # @param stamina [Integer] stamina/vitality stat
    # @param strength [Integer] strength stat
    # @return [Integer] maximum HP
    def self.calculate_max_hp(level:, stamina:, strength:)
      (level * 50) + (stamina * 12) + (strength * 2)
    end

    # Calculate physical damage range
    #
    # @param strength [Integer] attacker's strength
    # @param weapon_min_damage [Integer] weapon's minimum damage
    # @param weapon_max_damage [Integer] weapon's maximum damage
    # @return [Hash] with :min_damage and :max_damage keys
    def self.calculate_damage_range(strength:, weapon_min_damage: 0, weapon_max_damage: 0)
      {
        min_damage: (strength * 0.4) + weapon_min_damage,
        max_damage: (strength * 0.8) + weapon_max_damage
      }
    end

    # Calculate critical hit chance (%)
    #
    # @param attacker_intuition [Integer] attacker's intuition/dexterity
    # @param attacker_luck [Integer] attacker's luck
    # @param defender_intuition [Integer] defender's intuition/dexterity
    # @return [Float] critical chance percentage, clamped between 5% and 75%
    def self.calculate_crit_chance(attacker_intuition:, attacker_luck:, defender_intuition:)
      crit_modifier = (attacker_intuition * 1.5) / (defender_intuition + 1.0)
      crit_chance = (crit_modifier * 10) + (attacker_luck * 0.5)
      crit_chance.clamp(5.0, 75.0)
    end

    # Calculate evasion/dodge chance (%)
    #
    # @param defender_agility [Integer] defender's agility
    # @param attacker_agility [Integer] attacker's agility
    # @param attacker_luck [Integer] attacker's luck
    # @return [Float] evasion chance percentage, clamped between 5% and 70%
    def self.calculate_evasion_chance(defender_agility:, attacker_agility:, attacker_luck:)
      evasion_modifier = (defender_agility * 1.5) / (attacker_agility + 1.0)
      evasion_chance = (evasion_modifier * 12) - (attacker_luck * 0.3)
      evasion_chance.clamp(5.0, 70.0)
    end

    # Calculate block chance (%) - only applicable if shield equipped
    #
    # @param defender_stamina [Integer] defender's stamina/vitality
    # @param has_shield [Boolean] whether defender has a shield equipped
    # @return [Float] block chance percentage, clamped between 0% and 50%
    def self.calculate_block_chance(defender_stamina:, has_shield: false)
      return 0.0 unless has_shield

      block_chance = 10 + (defender_stamina * 0.2)
      block_chance.clamp(0.0, 50.0)
    end

    # Calculate final damage after block and armor
    #
    # @param incoming_damage [Numeric] the raw damage before mitigation
    # @param blocked [Boolean] whether the block succeeded
    # @param defender_stamina [Integer] defender's stamina/vitality
    # @param equipment_armor [Integer] defender's equipment armor value
    # @return [Integer] final damage to apply, minimum 1
    def self.calculate_final_damage(incoming_damage:, blocked:, defender_stamina:, equipment_armor: 0)
      damage_after_block = if blocked
        incoming_damage * 0.3
      else
        incoming_damage
      end

      armor_reduction = (defender_stamina * 0.15) + equipment_armor
      final_damage = damage_after_block - armor_reduction

      [final_damage.round, MIN_DAMAGE_FLOOR].max
    end

    # Calculate base hit damage using the modernized formula
    #
    # @param attacker_strength [Integer] attacker's strength
    # @param weapon_min_damage [Integer] weapon's minimum damage
    # @param weapon_max_damage [Integer] weapon's maximum damage
    # @param rng [Random] random number generator for variance
    # @return [Float] base hit damage before modifiers
    def self.calculate_base_hit_damage(attacker_strength:, weapon_min_damage: 0, weapon_max_damage: 0, rng: Random.new)
      range = calculate_damage_range(
        strength: attacker_strength,
        weapon_min_damage: weapon_min_damage,
        weapon_max_damage: weapon_max_damage
      )

      # Random damage strictly between min and max
      min = range[:min_damage]
      max = range[:max_damage]

      return min if min >= max

      min + rng.rand * (max - min)
    end
  end
end
