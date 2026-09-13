# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProfessionsHelper, type: :helper do
  include described_class

  let(:character) { create(:character) }

  before do
    Game::Professions::Templates.ensure_craft_items!
  end

  it "labels craft inputs with display names and owned counts" do
    Game::Inventory::Manager.new(inventory: character.inventory).add_item!(
      item_template: ItemTemplate.find_by!(key: "wood_chips"),
      quantity: 2
    )
    recipe = {
      "inputs" => {"wood_chips" => 3, "rat_tail" => 1}
    }

    line = craft_input_labels(recipe, character:)

    expect(line).to include("2/3")
    expect(line).to include("0/1")
    expect(line).not_to include("wood_chips×")
  end
end
