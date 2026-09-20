# frozen_string_literal: true

module Game
  module Activity
    # Daily activity contracts — quest-journal substitute for procedural Ashen Veil quests.
    class DailyContracts
      def self.definitions_for(day_key)
        seed = day_key.each_byte.sum
        [
          {key: "daily_kills", kind: "kill_npc", target: 5 + (seed % 6), reward: {"nv" => 35, "xp" => 40}, metadata: {"source" => "ashen_quest_mirror"}},
          {key: "daily_instances", kind: "instance_launch", target: 1 + (seed % 3), reward: {"nv" => 50, "xp" => 60}, metadata: {"source" => "ashen_quest_mirror"}},
          {key: "daily_arena", kind: "arena_fight", target: 2 + (seed % 4), reward: {"nv" => 40, "xp" => 45}, metadata: {"source" => "ashen_quest_mirror"}},
          {key: "daily_ticks", kind: "idle_tick", target: 3 + (seed % 5), reward: {"nv" => 20, "xp" => 25}, metadata: {"source" => "ashen_quest_mirror"}},
          {key: "daily_herbalist", kind: "gather_herb", target: 4 + (seed % 4), reward: {"nv" => 30}, metadata: {"source" => "ashen_gather"}},
          {key: "daily_fisher", kind: "catch_fish", target: 3 + (seed % 3), reward: {"nv" => 35}, metadata: {"source" => "ashen_gather"}}
        ]
      end
    end
  end
end
