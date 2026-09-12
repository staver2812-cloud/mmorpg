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

  it "advances kill objectives for matching npc keys" do
    journal.accept!("ash_mite_patrol")
    journal.record_npc_kill!(npc_key: "plague_rat")
    journal.record_npc_kill!(npc_key: "plague_rat")

    state = character.reload.metadata.dig("ashen_quests", "ash_mite_patrol")
    expect(state["progress"]).to eq(2)
  end
end
