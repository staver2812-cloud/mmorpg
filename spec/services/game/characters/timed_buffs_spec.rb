# frozen_string_literal: true

require "rails_helper"

RSpec.describe Game::Characters::TimedBuffs do
  include ActiveSupport::Testing::TimeHelpers

  let(:character) { create(:character, max_hp: 100) }

  around { |example| freeze_time { example.run } }

  it "applies modifiers and replaces the same buff key" do
    buffs = described_class.new(character:)
    buffs.apply!(key: "strength_brew", label: "Strength Brew", mods: {attack: 8}, duration_seconds: 3600)
    buffs.apply!(key: "strength_brew", label: "Strength Brew", mods: {attack: 12}, duration_seconds: 3600)

    expect(buffs.modifier(:attack)).to eq(12)
    expect(character.reload.metadata["active_buffs"].size).to eq(1)
  end

  it "prunes expired buffs on read and removes their character modifiers" do
    described_class.new(character:).apply!(
      key: "vigor",
      label: "Vigor",
      mods: {max_hp: 80},
      duration_seconds: 3600
    )
    expect(character.effective_max_hp).to eq(180)

    travel 1.hour + 1.second

    expect(character.reload.effective_max_hp).to eq(100)
    expect(character.reload.metadata["active_buffs"]).to eq([])
  end
end
