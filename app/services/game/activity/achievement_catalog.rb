# frozen_string_literal: true

module Game
  module Activity
    # Compact achievement chains derived from Ashen Veil trigger kinds.
    # Full 19k+ rows stay in ashen-veil backup; runtime uses these activity mirrors.
    class AchievementCatalog
      CHAINS = [
        {id: "kill_pack", kind: "kill_npc", step: 0, required: 10, name_ru: "Зачистка I", name_en: "Clearing I", rewards: {"nv" => 20, "xp" => 30}},
        {id: "kill_pack", kind: "kill_npc", step: 1, required: 50, name_ru: "Зачистка II", name_en: "Clearing II", rewards: {"nv" => 60, "xp" => 80}},
        {id: "kill_pack", kind: "kill_npc", step: 2, required: 200, name_ru: "Зачистка III", name_en: "Clearing III", rewards: {"nv" => 150, "xp" => 200}},
        {id: "instance_launch", kind: "instance_launch", step: 0, required: 3, name_ru: "Первые врата", name_en: "First Gates", rewards: {"nv" => 40, "xp" => 50}},
        {id: "instance_launch", kind: "instance_launch", step: 1, required: 15, name_ru: "Исследователь разломов", name_en: "Rift Explorer", rewards: {"nv" => 120, "xp" => 160}},
        {id: "arena_fight", kind: "arena_fight", step: 0, required: 5, name_ru: "Арена I", name_en: "Arena I", rewards: {"nv" => 30, "xp" => 40}},
        {id: "arena_fight", kind: "arena_fight", step: 1, required: 25, name_ru: "Арена II", name_en: "Arena II", rewards: {"nv" => 100, "xp" => 120}},
        {id: "shop_purchase", kind: "shop_purchase", step: 0, required: 5, name_ru: "Торговец I", name_en: "Trader I", rewards: {"nv" => 15, "xp" => 20}},
        {id: "idle_tick", kind: "idle_tick", step: 0, required: 10, name_ru: "Сторож времени", name_en: "Time Keeper", rewards: {"nv" => 25, "xp" => 25}}
      ].freeze

      def self.chains_for(kind)
        CHAINS.select { |row| row[:kind].to_s == kind.to_s }
      end

      def self.all
        CHAINS
      end
    end
  end
end
