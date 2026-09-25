# frozen_string_literal: true

require "rails_helper"

RSpec.describe Arena::CombatFormulaCalculator do
  describe ".calculate_max_hp" do
    it "calculates max HP using the modernized formula" do
      # Max_HP = (level * 50) + (stamina * 12) + (strength * 2)
      # Example: level 10, stamina 20, strength 15
      # Expected: (10 * 50) + (20 * 12) + (15 * 2) = 500 + 240 + 30 = 770
      result = described_class.calculate_max_hp(level: 10, stamina: 20, strength: 15)
      expect(result).to eq(770)
    end

    it "calculates max HP for level 1 character" do
      # level 1, stamina 10, strength 10
      # Expected: (1 * 50) + (10 * 12) + (10 * 2) = 50 + 120 + 20 = 190
      result = described_class.calculate_max_hp(level: 1, stamina: 10, strength: 10)
      expect(result).to eq(190)
    end

    it "calculates max HP for high-level character" do
      # level 50, stamina 100, strength 80
      # Expected: (50 * 50) + (100 * 12) + (80 * 2) = 2500 + 1200 + 160 = 3860
      result = described_class.calculate_max_hp(level: 50, stamina: 100, strength: 80)
      expect(result).to eq(3860)
    end
  end

  describe ".calculate_damage_range" do
    it "calculates physical damage range based on strength and weapon" do
      # strength 30, weapon 10-20
      # min = (30 * 0.4) + 10 = 12 + 10 = 22
      # max = (30 * 0.8) + 20 = 24 + 20 = 44
      result = described_class.calculate_damage_range(
        strength: 30,
        weapon_min_damage: 10,
        weapon_max_damage: 20
      )

      expect(result[:min_damage]).to eq(22.0)
      expect(result[:max_damage]).to eq(44.0)
    end

    it "calculates damage range without weapon" do
      # strength 25, no weapon
      # min = (25 * 0.4) + 0 = 10
      # max = (25 * 0.8) + 0 = 20
      result = described_class.calculate_damage_range(strength: 25)

      expect(result[:min_damage]).to eq(10.0)
      expect(result[:max_damage]).to eq(20.0)
    end

    it "handles zero strength" do
      result = described_class.calculate_damage_range(
        strength: 0,
        weapon_min_damage: 5,
        weapon_max_damage: 10
      )

      expect(result[:min_damage]).to eq(5.0)
      expect(result[:max_damage]).to eq(10.0)
    end
  end

  describe ".calculate_crit_chance" do
    it "calculates critical chance with basic stats" do
      # attacker intuition 50, luck 20, defender intuition 30
      # crit_modifier = (50 * 1.5) / (30 + 1.0) = 75 / 31 = 2.419
      # crit_chance = (2.419 * 10) + (20 * 0.5) = 24.19 + 10 = 34.19
      result = described_class.calculate_crit_chance(
        attacker_intuition: 50,
        attacker_luck: 20,
        defender_intuition: 30
      )

      expect(result).to be_within(0.1).of(34.2)
    end

    it "clamps critical chance at minimum 5%" do
      # Very low attacker stats vs high defender
      result = described_class.calculate_crit_chance(
        attacker_intuition: 1,
        attacker_luck: 1,
        defender_intuition: 100
      )

      expect(result).to eq(5.0)
    end

    it "clamps critical chance at maximum 75%" do
      # Very high attacker stats vs low defender
      result = described_class.calculate_crit_chance(
        attacker_intuition: 200,
        attacker_luck: 100,
        defender_intuition: 1
      )

      expect(result).to eq(75.0)
    end

    it "handles defender with zero intuition" do
      # Should use defender_intuition + 1.0 to avoid division issues
      result = described_class.calculate_crit_chance(
        attacker_intuition: 30,
        attacker_luck: 15,
        defender_intuition: 0
      )

      # crit_modifier = (30 * 1.5) / (0 + 1.0) = 45 / 1 = 45
      # crit_chance = (45 * 10) + (15 * 0.5) = 450 + 7.5 = 457.5, clamped to 75
      expect(result).to eq(75.0)
    end
  end

  describe ".calculate_evasion_chance" do
    it "calculates evasion chance with basic stats" do
      # defender agility 60, attacker agility 40, attacker luck 15
      # evasion_modifier = (60 * 1.5) / (40 + 1.0) = 90 / 41 = 2.195
      # evasion_chance = (2.195 * 12) - (15 * 0.3) = 26.34 - 4.5 = 21.84
      result = described_class.calculate_evasion_chance(
        defender_agility: 60,
        attacker_agility: 40,
        attacker_luck: 15
      )

      expect(result).to be_within(0.1).of(21.8)
    end

    it "clamps evasion chance at minimum 5%" do
      # Low defender agility vs high attacker stats
      result = described_class.calculate_evasion_chance(
        defender_agility: 10,
        attacker_agility: 100,
        attacker_luck: 50
      )

      expect(result).to eq(5.0)
    end

    it "clamps evasion chance at maximum 70%" do
      # Very high defender agility vs low attacker
      result = described_class.calculate_evasion_chance(
        defender_agility: 200,
        attacker_agility: 1,
        attacker_luck: 1
      )

      expect(result).to eq(70.0)
    end
  end

  describe ".calculate_block_chance" do
    it "calculates block chance when shield is equipped" do
      # stamina 50, has shield
      # block_chance = 10 + (50 * 0.2) = 10 + 10 = 20
      result = described_class.calculate_block_chance(
        defender_stamina: 50,
        has_shield: true
      )

      expect(result).to eq(20.0)
    end

    it "returns 0% when no shield is equipped" do
      result = described_class.calculate_block_chance(
        defender_stamina: 100,
        has_shield: false
      )

      expect(result).to eq(0.0)
    end

    it "clamps block chance at maximum 50%" do
      # Very high stamina: 10 + (300 * 0.2) = 10 + 60 = 70, clamped to 50
      result = described_class.calculate_block_chance(
        defender_stamina: 300,
        has_shield: true
      )

      expect(result).to eq(50.0)
    end

    it "clamps block chance at minimum 0%" do
      # Edge case with potential negative calculation
      result = described_class.calculate_block_chance(
        defender_stamina: -100,
        has_shield: true
      )

      expect(result).to be >= 0.0
    end
  end

  describe ".calculate_final_damage" do
    it "calculates final damage when not blocked" do
      # incoming 100, not blocked, stamina 30, armor 10
      # armor_reduction = (30 * 0.15) + 10 = 4.5 + 10 = 14.5
      # final_damage = 100 - 14.5 = 85.5, rounded to 86
      result = described_class.calculate_final_damage(
        incoming_damage: 100,
        blocked: false,
        defender_stamina: 30,
        equipment_armor: 10
      )

      expect(result).to eq(86)
    end

    it "calculates final damage when blocked" do
      # incoming 100, blocked (30% damage), stamina 30, armor 10
      # damage_after_block = 100 * 0.3 = 30
      # armor_reduction = (30 * 0.15) + 10 = 14.5
      # final_damage = 30 - 14.5 = 15.5, rounded to 16
      result = described_class.calculate_final_damage(
        incoming_damage: 100,
        blocked: true,
        defender_stamina: 30,
        equipment_armor: 10
      )

      expect(result).to eq(16)
    end

    it "ensures minimum damage of 1" do
      # Very low damage vs high armor
      result = described_class.calculate_final_damage(
        incoming_damage: 5,
        blocked: true,
        defender_stamina: 100,
        equipment_armor: 50
      )

      expect(result).to eq(1)
    end

    it "handles zero armor" do
      result = described_class.calculate_final_damage(
        incoming_damage: 50,
        blocked: false,
        defender_stamina: 20,
        equipment_armor: 0
      )

      # armor_reduction = (20 * 0.15) + 0 = 3
      # final_damage = 50 - 3 = 47
      expect(result).to eq(47)
    end

    it "calculates correctly for high damage attacks" do
      # High damage attack against moderate defense
      result = described_class.calculate_final_damage(
        incoming_damage: 500,
        blocked: false,
        defender_stamina: 50,
        equipment_armor: 25
      )

      # armor_reduction = (50 * 0.15) + 25 = 7.5 + 25 = 32.5
      # final_damage = 500 - 32.5 = 467.5, rounded to 468
      expect(result).to eq(468)
    end
  end

  describe ".calculate_base_hit_damage" do
    let(:seeded_rng) { Random.new(42) }

    it "calculates damage within the min-max range" do
      result = described_class.calculate_base_hit_damage(
        attacker_strength: 40,
        weapon_min_damage: 10,
        weapon_max_damage: 30,
        rng: seeded_rng
      )

      # min = (40 * 0.4) + 10 = 16 + 10 = 26
      # max = (40 * 0.8) + 30 = 32 + 30 = 62
      expect(result).to be_between(26.0, 62.0)
    end

    it "returns min damage when min equals max" do
      result = described_class.calculate_base_hit_damage(
        attacker_strength: 25,
        weapon_min_damage: 15,
        weapon_max_damage: 15,
        rng: seeded_rng
      )

      # min = (25 * 0.4) + 15 = 10 + 15 = 25
      # max = (25 * 0.8) + 15 = 20 + 15 = 35
      # With equal weapon damage, still has strength-based variance
      expect(result).to be_between(25.0, 35.0)
    end

    it "produces different results with different RNG seeds" do
      rng1 = Random.new(1)
      rng2 = Random.new(2)

      result1 = described_class.calculate_base_hit_damage(
        attacker_strength: 50,
        weapon_min_damage: 20,
        weapon_max_damage: 40,
        rng: rng1
      )

      result2 = described_class.calculate_base_hit_damage(
        attacker_strength: 50,
        weapon_min_damage: 20,
        weapon_max_damage: 40,
        rng: rng2
      )

      # Results should be different with different RNG seeds
      expect(result1).not_to eq(result2)
    end
  end
end
