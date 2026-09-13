# frozen_string_literal: true

require "rails_helper"

RSpec.describe Game::World::StarterKit do
  it "grants bait and starter NV once per character" do
    create(
      :item_template,
      :material,
      key: Game::World::Bait::ITEM_KEY,
      name: "Приманка Завесы",
      weight: 1,
      stack_limit: 99,
      base_price: 5
    )
    character = create(:character)
    described_class.new(character:).call

    expect(Game::World::Bait.new(character:).quantity).to eq(Game::World::Bait::STARTER_GRANT)
    expect(character.user.currency_wallet.nv_balance).to eq(Game::World::StarterKit::STARTER_NV)

    expect {
      described_class.new(character:).call
    }.not_to change { Game::World::Bait.new(character: character.reload).quantity }
  end
end
