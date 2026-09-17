# frozen_string_literal: true

module Game
  module World
    # Places Ashen Veil catalog NPCs across outdoor tiles by level→tier bands (1..23).
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

        pools = item_pools_by_tier
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

          loot = build_loot(template, pools, tier)
          respawn = respawn_for(template)
          meta = template.metadata.to_h.merge(
            "loot_table" => loot,
            "respawn_seconds" => respawn,
            "respawn_variance_seconds" => (respawn / 5).clamp(30, 600),
            "drop_chance_multiplier" => template.metadata.to_h["drop_chance_multiplier"].presence || 1.0,
            "world_tier" => tier,
            "seed_source" => SEED_SOURCE
          )
          template.update!(metadata: meta)

          tile = TileNpc.find_or_initialize_by(zone: zone_name, x: cell[:x], y: cell[:y])
          was_new = tile.new_record?
          hp = (template.metadata.to_h["health"].presence || template.metadata.to_h["max_hp"] || 50).to_i.clamp(1, 50_000)
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
              "respawn_seconds" => respawn,
              "respawn_variance_seconds" => (respawn / 5).clamp(30, 600),
              "drop_chance_multiplier" => meta["drop_chance_multiplier"],
              "encounter_count" => 1
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

      def item_pools_by_tier
        pools = Hash.new { |h, k| h[k] = [] }
        ItemTemplate.where("enhancement_rules -> 'ashen_veil' IS NOT NULL").find_each do |item|
          tier = item.enhancement_rules.to_h.dig("shop", "tier").to_i
          tier = 1 if tier < 1
          pools[tier] << item.key
        end
        # Include thematic set pieces keyed by set_tier.
        ItemTemplate.where("enhancement_rules ->> 'set_key' LIKE 'set-%'").find_each do |item|
          tier = item.enhancement_rules.to_h["set_tier"].to_i
          next if tier < 1

          mapped = ((tier.clamp(1, 50) - 1) * 22 / 49) + 1
          pools[mapped] << item.key
        end
        pools
      end

      def build_loot(template, pools, tier)
        candidates = (
          pools[tier] + pools[[tier - 1, 1].max] + pools[[tier + 1, 23].min]
        ).uniq
        sample = candidates.first(4)
        role = template.metadata.to_h["ashen_role"].to_s
        chances = case role
        when "boss" then [35, 28, 22, 15]
        when "elite" then [22, 16, 12, 8]
        else [12, 9, 6, 4]
        end
        loot = sample.each_with_index.map do |key, idx|
          {"kind" => "item", "item_key" => key, "quantity" => 1, "chance" => chances[idx] || 5}
        end
        silver = template.metadata.to_h["silver"].to_i
        nv = silver.positive? ? silver : [tier * 4, 5].max
        loot << {"kind" => "currency", "currency" => "NV", "amount" => nv, "chance" => role == "boss" ? 100 : 75}
        loot
      end

      def respawn_for(template)
        role = template.metadata.to_h["ashen_role"].to_s
        case role
        when "boss" then 1800
        when "elite" then 600
        else 180
        end
      end
    end
  end
end
