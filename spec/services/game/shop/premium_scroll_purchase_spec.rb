# frozen_string_literal: true

require "rails_helper"

RSpec.describe Game::Shop::PremiumScrollPurchase do
  it "buys a combat trauma scroll for veil marks" do
    character = create(:character)
    wallet = character.user.currency_wallet || character.user.create_currency_wallet!(nv_balance: 0)
    wallet.update!(veil_marks: 50)

    result = described_class.new(character:, item_key: "combat_trauma_scroll").call

    expect(result.success).to be(true)
    expect(wallet.reload.veil_marks).to eq(35)
    expect(
      character.inventory.inventory_items.joins(:item_template).where(item_templates: {key: "combat_trauma_scroll"}).sum(:quantity)
    ).to eq(1)
  end
end
