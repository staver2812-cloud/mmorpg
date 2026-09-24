# frozen_string_literal: true

require "rails_helper"

RSpec.describe Game::World::DismissCompletedFight do
  let(:character) { create(:character, in_combat: true, current_hp: 0) }
  let(:match) { create(:arena_match, :completed) }
  let!(:participation) { create(:arena_participation, character:, arena_match: match, metadata: {}) }

  it "stamps finished_at, clears in_combat, and recovers zero HP" do
    result = described_class.new(character:).call

    expect(result.dismissed).to be(true)
    expect(participation.reload.metadata["finished_at"]).to be_present
    expect(character.reload).not_to be_in_combat
    expect(character.current_hp).to be_positive
    expect(result.recovery.recovered).to be(true)
  end

  it "is a no-op when the fight was already finished" do
    participation.update!(metadata: {"finished_at" => 1.minute.ago.iso8601})
    character.update!(in_combat: false, current_hp: 50)

    result = described_class.new(character:).call

    expect(result.dismissed).to be(false)
    expect(result.recovery).to be_nil
  end

  it "removes orphan pulse ambush tile NPCs when no live match remains" do
    participation.update!(metadata: {"finished_at" => 1.minute.ago.iso8601})
    character.update!(in_combat: false, current_hp: 50)
    zone = create(:zone, name: "Ambush Sweep", location_type: "outdoor")
    create(:character_position, character:, zone:, x: 2, y: 2)
    template = create(:npc_template, npc_key: "ashen_ambush_coal_guard", name: "Угольный Страж", level: 50)
    sticky = TileNpc.create!(
      npc_template: template,
      zone: zone.name,
      x: 4,
      y: 5,
      npc_key: template.npc_key,
      npc_role: "hostile",
      level: 50,
      metadata: {"personal_instance" => true, "active" => true, "source" => "world_live_ambush", "ambush_label" => "Угольный Страж"}
    )

    result = described_class.new(character:).call

    expect(result.dismissed).to be(true)
    expect(TileNpc.find_by(id: sticky.id)).to be_nil
  end
end
