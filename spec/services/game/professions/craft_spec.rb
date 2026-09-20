# frozen_string_literal: true

require "rails_helper"

RSpec.describe Game::Professions::Craft do
  let(:character) { create(:character) }

  before do
    Game::Professions::Templates.ensure_craft_items!
    inventory = character.inventory
    manager = Game::Inventory::Manager.new(inventory:)
    manager.add_item!(item_template: ItemTemplate.find_by!(key: "pine_resin"), quantity: 2)
    manager.add_item!(item_template: ItemTemplate.find_by!(key: "wood_chips"), quantity: 4)
    manager.add_item!(item_template: ItemTemplate.find_by!(key: "rat_tail"), quantity: 2)
  end

  it "crafts an ashen bandage and raises tar_smith skill" do
    result = described_class.new(character:, recipe_key: "ashen_bandage").call

    expect(result.success).to be(true)
    expect(result.skill).to eq(1)
    expect(character.inventory.inventory_items.joins(:item_template).where(item_templates: {key: "ashen_bandage"}).sum(:quantity)).to eq(1)
    expect(character.reload.metadata.dig("profession_skills", "tar_smith")).to eq(1)
  end

  it "crafts bandage from chips via fallback recipe" do
    result = described_class.new(character:, recipe_key: "ashen_bandage_chips").call
    expect(result.success).to be(true)
  end

  it "rejects craft without materials" do
    character.inventory.inventory_items.destroy_all

    result = described_class.new(character:, recipe_key: "ashen_bandage").call

    expect(result.success).to be(false)
    expect(character.inventory.inventory_items.joins(:item_template).where(item_templates: {key: "ashen_bandage"})).to be_empty
  end

  it "crafts rare ranger gear from rare hides and high-tier materials" do
    character.update!(metadata: {"profession_skills" => {"tar_smith" => 12}})
    manager = Game::Inventory::Manager.new(inventory: character.inventory)
    {
      "ash_wolf_pelt" => 3,
      "mist_spider_silk" => 2,
      "ember_cedar_plank" => 3
    }.each do |key, quantity|
      manager.add_item!(item_template: ItemTemplate.find_by!(key: key), quantity:)
    end

    result = described_class.new(character:, recipe_key: "ash_ranger_jacket").call

    expect(result.success).to be(true)
    crafted = character.inventory.inventory_items.joins(:item_template)
      .find_by!(item_templates: {key: "ash_ranger_jacket"})
    expect(crafted.item_template.requirements["level"]).to eq(12)
  end
end
