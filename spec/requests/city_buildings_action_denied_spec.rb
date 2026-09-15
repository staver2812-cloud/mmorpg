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
end
