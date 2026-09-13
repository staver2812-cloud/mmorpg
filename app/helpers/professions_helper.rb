# frozen_string_literal: true

module ProfessionsHelper
  # Human craft input line: "Пепельный бинт 1/2" using inventory counts.
  def craft_input_labels(recipe, character:)
    Game::Professions::Templates.ensure_craft_items!
    inventory = character.inventory
    recipe.fetch("inputs").map do |item_key, need|
      template = ItemTemplate.find_by(key: item_key.to_s)
      name = template&.display_name || item_key.to_s
      have = if inventory && template
        inventory.inventory_items.where(item_template: template, equipped: false).sum(:quantity)
      else
        0
      end
      "#{name} #{have}/#{need}"
    end.join(", ")
  end
end
