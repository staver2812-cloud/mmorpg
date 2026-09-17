# frozen_string_literal: true

module Game
  module World
    # Equips an Ashen wilderness NPC with one thematic set matching its world tier
    # and derives combat attack/defense/HP from the worn pieces (server-authoritative).
    class NpcLoadout
      SET_IDS = %w[blood demiurge distortion judge swamp].freeze
      CATALOG_TIERS = [5, 10, 15, 20, 25, 30, 35, 40, 45, 50].freeze
      PIECE_SUFFIXES = %w[
        weapon-sword helm armor-plate gloves bracers boots amulet ring earring-1 waist
      ].freeze

      Result = Struct.new(:item_keys, :combat_stats, :set_id, :set_tier, keyword_init: true)

      def initialize(npc_template:, world_tier: nil, rng: Random.new)
        @npc_template = npc_template
        @world_tier = (world_tier || npc_template.metadata.to_h["world_tier"] || 1).to_i
        @rng = rng
      end

      def call
        set_id = pick_set_id
        set_tier = catalog_tier_for(world_tier)
        keys = PIECE_SUFFIXES.map { |suffix| "set-#{set_id}-#{suffix}-t#{set_tier}" }
        templates = ItemTemplate.where(key: keys).index_by(&:key)
        present = keys.select { |key| templates.key?(key) }
        present = keys if present.empty?

        Result.new(
          item_keys: present,
          combat_stats: derive_stats(templates.values_at(*present).compact),
          set_id:,
          set_tier:
        )
      end

      def self.catalog_tier_for(world_tier)
        index = (((world_tier.to_i.clamp(1, 23) - 1) * (CATALOG_TIERS.size - 1)) / 22)
        CATALOG_TIERS.fetch(index.clamp(0, CATALOG_TIERS.size - 1))
      end

      def self.drop_chance_percent(role:, set_tier:)
        base = case role.to_s
        when "boss" then 4.0
        when "elite" then 2.5
        else 1.5
        end
        # Higher catalog tiers are scarcer.
        rarity_scale = case set_tier.to_i
        when 40..50 then 0.25
        when 25..39 then 0.45
        when 15..24 then 0.7
        when 10..14 then 0.85
        else 1.0
        end
        (base * rarity_scale).clamp(0.15, 5.0).round(2)
      end

      private

      attr_reader :npc_template, :world_tier, :rng

      def catalog_tier_for(tier)
        self.class.catalog_tier_for(tier)
      end

      def pick_set_id
        role = npc_template.metadata.to_h["ashen_role"].to_s
        focus = case role
        when "boss" then %w[judge blood demiurge]
        when "elite" then %w[blood distortion swamp]
        else SET_IDS
        end
        focus.fetch(rng.rand(focus.length))
      end

      def derive_stats(templates)
        base = npc_template.combat_stats.to_h.symbolize_keys
        attack = base[:attack].to_i
        defense = base[:defense].to_i
        hp = base[:hp].to_i
        agility = base[:agility].to_i
        accuracy = base[:accuracy].to_i
        luck = base[:luck].to_i

        templates.each do |template|
          mods = template.stat_modifiers.to_h
          dmin = mods["damage_min"].to_i
          dmax = mods["damage_max"].to_i
          if dmax.positive?
            attack += ((dmin + dmax) / 2.0).round
          end
          defense += mods["armor_class"].to_i
          hp += mods["hp"].to_i
          agility += mods["evasion"].to_i + mods["dexterity"].to_i
          accuracy += mods["accuracy"].to_i
          luck += mods["luck"].to_i
          attack += (mods["strength"].to_i / 2)
        end

        {
          "attack" => [attack, 1].max,
          "defense" => [defense, 0].max,
          "hp" => [hp, 10].max,
          "agility" => [agility, 0].max,
          "accuracy" => [accuracy, 0].max,
          "luck" => [luck, 0].max,
          "crit_chance" => base[:crit_chance].to_i,
          "dodge_chance" => base[:dodge_chance].to_i
        }
      end
    end
  end
end
