# frozen_string_literal: true

require "rails_helper"

RSpec.describe Game::Combat::InjuryResolver do
  let(:zone) { create(:zone, :city_node) }
  let(:character) { create(:character, current_hp: 0, max_hp: 100) }
  let(:match) { create(:arena_match, :completed, metadata: {"trauma_percent" => 80, "source" => "world_npc"}) }
  let!(:participation) do
    create(:arena_participation, arena_match: match, character:, user: character.user, result: "defeat", team: "a")
  end

  it "applies a heavy injury on a high-trauma defeat" do
    rng = instance_double(Random)
    expect(rng).to receive(:rand).with(100).and_return(10)

    results = described_class.new(match:, rng:).call

    expect(results.first.severity).to eq("heavy")
    expect(Game::Combat::InjuryState.new(character: character.reload).blocks_movement?).to be(true)
  end
end
