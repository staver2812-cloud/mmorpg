# frozen_string_literal: true

module Game
  module World
    # Places Ashen Veil catalog NPCs across outdoor tiles by level→tier bands (1..23).
    # Personal instances: respawn_seconds = 0, concurrent farm, scarce set-piece loot.
    class AshenPopulation
      SEED_SOURCE = "ashen_veil_world_population"
      OUTDOOR_ZONE = "Пепельный Берег"
      TIERS = (1..23).freeze

      Result = Struct.new(:placed, :updated, :skipped, keyword_init: true)

      def initialize(zone_name: OUTDOOR_ZONE)
        @zone_name = zone_name
      end

      def call
        templates = NpcTemplate.where("npc_key LIKE 'av_%'").order(:level, :id).to_a
        return Result.new(placed: 0, updated: 0, skipped: 0) if templates.empty?

        cells = passable_cells_by_tier
        placed = 0
        updated = 0
        skipped = 0

        templates.each_with_index do |template, index|
          tier = tier_for_level(template.level.to_i)
          cell = pick_cell(cells, tier, index)
          unless cell
            skipped += 1
            next
          end

          loadout = NpcLoadout.new(npc_template: template, world_tier: tier).call
          loot = build_loot(template, loadout, tier)
          meta = template.metadata.to_h.merge(
            "loot_table" => loot,
            "respawn_seconds" => 0,
            "respawn_variance_seconds" => 0,
            "drop_chance_multiplier" => 1.0,
            "world_tier" => tier,
            "personal_instance" => true,
            "equipped_set_keys" => loadout.item_keys,
            "equipped_set_id" => loadout.set_id,
            "equipped_set_tier" => loadout.set_tier,
            "stats" => loadout.combat_stats,
            "health" => loadout.combat_stats["hp"],
            "base_damage" => loadout.combat_stats["attack"],
            "base_defense" => loadout.combat_stats["defense"],
            "seed_source" => SEED_SOURCE
          )
          template.update!(metadata: meta, level: template.level)

          tile = TileNpc.find_or_initialize_by(zone: zone_name, x: cell[:x], y: cell[:y])
          was_new = tile.new_record?
          hp = loadout.combat_stats["hp"].to_i.clamp(1, 50_000)
          tile.assign_attributes(
            npc_template: template,
            npc_key: template.npc_key,
            npc_role: "hostile",
            level: template.level,
            max_hp: hp,
            current_hp: hp,
            defeated_at: nil,
            respawns_at: nil,
            metadata: {
              "active" => true,
              "seed_source" => SEED_SOURCE,
              "world_tier" => tier,
              "personal_instance" => true,
              "respawn_seconds" => 0,
              "respawn_variance_seconds" => 0,
              "drop_chance_multiplier" => 1.0,
              "encounter_count" => 1,
              "passive_delay_windows" => [{"min_seconds" => 300, "max_seconds" => 300}]
            }
          )
          tile.save!
          was_new ? placed += 1 : updated += 1
        end

        Result.new(placed:, updated:, skipped:)
      end

      def self.tier_for_level(level)
        # Enemy catalog spans ~1..50 → soft-release shop tiers 1..23.
        (((level.to_i.clamp(1, 50) - 1) * 22) / 49) + 1
      end

      private

      attr_reader :zone_name

      def tier_for_level(level)
        self.class.tier_for_level(level)
      end

      def passable_cells_by_tier
        tiles = MapTileTemplate.where(zone: zone_name, passable: true)
          .where("x BETWEEN 1 AND 900 AND y BETWEEN 1 AND 900")
          .order(:x, :y)
          .pluck(:x, :y)
        buckets = Hash.new { |h, k| h[k] = [] }
        tiles.each do |x, y|
          # 23 vertical corridors along X.
          tier = ((x - 1) * 23 / 900).clamp(0, 22) + 1
          buckets[tier] << {x:, y:}
        end
        # Fallback: if map is sparse, synthesize grid points per tier.
        TIERS.each do |tier|
          next if buckets[tier].size >= 5

          base_x = ((tier - 1) * 900 / 23) + 10
          5.times do |i|
            buckets[tier] << {x: base_x + (i * 3), y: 20 + (i * 7)}
          end
        end
        buckets
      end

      def pick_cell(cells, tier, index)
        pool = cells[tier].presence || cells.values.flatten
        return if pool.blank?

        pool[index % pool.size]
      end

      def build_loot(template, loadout, tier)
        role = template.metadata.to_h["ashen_role"].to_s
        chance = NpcLoadout.drop_chance_percent(role:, set_tier: loadout.set_tier)
        # Fractional chance (<1) so LootEntry keeps sub-percent rarity.
        loot = [
          {
            "kind" => "set_piece",
            "quantity" => 1,
            "chance" => (chance / 100.0).clamp(0.0015, 0.05),
            "item_keys" => loadout.item_keys
          }
        ]
        silver = template.metadata.to_h["silver"].to_i
        nv = silver.positive? ? silver : [tier * 4, 5].max
        loot << {"kind" => "currency", "currency" => "NV", "amount" => nv, "chance" => role == "boss" ? 100 : 70}
        loot
      end
    end
  end
end
