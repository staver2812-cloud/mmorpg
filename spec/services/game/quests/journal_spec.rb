# frozen_string_literal: true

RSpec.describe Game::Quests::Journal do
  let(:user) { create(:user) }
  let(:character) { create(:character, user:) }
  let(:journal) { described_class.new(character:) }

  before do
    Game::Quests::Catalog.reload!
  end

  it "accepts a starter quest into character metadata" do
    result = journal.accept!("veil_tail_delivery")

    expect(result.success).to eq(true)
    state = character.reload.metadata.dig("ashen_quests", "veil_tail_delivery")
    expect(state["status"]).to eq("active")
    expect(state["progress"]).to eq(0)
  end

  it "accepts the Ash Healer first-bag delivery contract" do
    result = journal.accept!("ash_healer_first_bag")

    expect(result.success).to eq(true)
    state = character.reload.metadata.dig("ashen_quests", "ash_healer_first_bag")
    expect(state["status"]).to eq("active")
    expect(Game::Quests::Catalog.find("ash_healer_first_bag").dig("objective", "item_key")).to eq("healer_bag_light")
  end
end
