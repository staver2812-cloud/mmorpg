# frozen_string_literal: true

require "rails_helper"

RSpec.describe "City building action denied recovery", type: :request do
  let(:user) { create(:user) }
  let(:city) { create(:zone, :city_node, name: "Action Deny Quarter") }
  let(:character) { create(:character, user:, level: 10) }
  let!(:position) { create(:character_position, character:, zone: city, x: 5, y: 5) }
  let!(:shop) { create(:city_hotspot, :shop, zone: city) }

  before { sign_in user, scope: :user }

  it "recovers when resting in a building that does not offer rest" do
    post city_building_rest_path("shop")

    expect(response).to redirect_to(world_path(building_denied: 1))
    follow_redirect!
    expect(response.body).to include('data-building-denied="1"')
  end

  it "recovers when a bank vault transfer fails" do
    create(:city_hotspot, :building, zone: city, key: "bank", name: "Bank",
      action_params: {"feature" => "bank"})

    post city_building_bank_path("bank"), params: {bank_action: "deposit", amount: 0}

    expect(response).to redirect_to(city_building_path("bank", bank_denied: 1))
    follow_redirect!
    expect(response.body).to include('data-bank-denied="1"')
    expect(response.body).to include('data-bank-recovery="world"')
    expect(response.body).to include('data-bank-recovery="bank"')
  end

  it "recovers when a post office note save fails" do
    create(:city_hotspot, :building, zone: city, key: "post", name: "Post",
      action_params: {"feature" => "post"})

    post city_building_post_path("post"), params: {body: "   "}

    expect(response).to redirect_to(city_building_path("post", post_denied: 1))
    follow_redirect!
    expect(response.body).to include('data-post-denied="1"')
    expect(response.body).to include('data-post-recovery="world"')
    expect(response.body).to include('data-post-recovery="post"')
  end

  it "recovers when a souvenir purchase fails" do
    create(:city_hotspot, :building, zone: city, key: "souvenir_shop", name: "Souvenir",
      action_params: {"feature" => "souvenir_shop"})

    post city_building_souvenir_path("souvenir_shop"), params: {item_key: "__missing_ashen_souvenir__"}

    expect(response).to redirect_to(city_building_path("souvenir_shop", souvenir_denied: 1))
    follow_redirect!
    expect(response.body).to include('data-souvenir-denied="1"')
    expect(response.body).to include('data-souvenir-recovery="world"')
    expect(response.body).to include('data-souvenir-recovery="souvenir"')
  end

  it "recovers when a junk buyback fails" do
    create(:city_hotspot, :building, zone: city, key: "junk_dealer", name: "Junk",
      action_params: {"feature" => "junk_dealer"})

    post city_building_sell_path("junk_dealer"), params: {item_key: "__missing_ashen_junk__", quantity: 1}

    expect(response).to redirect_to(city_building_path("junk_dealer", junk_denied: 1))
    follow_redirect!
    expect(response.body).to include('data-junk-denied="1"')
    expect(response.body).to include('data-junk-recovery="world"')
    expect(response.body).to include('data-junk-recovery="junk"')
  end
end
