# frozen_string_literal: true

require "rails_helper"

RSpec.describe Game::Combat::InjuryResolver do
  let(:zone) { create(:zone, :city_node) }
  let(:character) { create(:character, current_hp: 0, max_hp: 100) }
  let(:match) do
    create(
      :arena_match,
      :completed,
      metadata: {"trauma_percent" => 80, "source" => "world_npc", "combat_trauma" => true}
    )
  end
  let!(:participation) do
    create(:arena_participation, arena_match: match, character:, user: character.user, result: "defeat", team: "a")
  end

  it "applies combat trauma on defeat when the match used a combat scroll" do
    results = described_class.new(match:, rng: Random.new(1)).call

    expect(results.first.severity).to eq("combat")
    expect(Game::Combat::InjuryState.new(character: character.reload).blocks_movement?).to be(true)
    expect(Game::Combat::InjuryState.new(character:).active.map { |r| r["severity"] }).to include("combat")
  end
end
