# frozen_string_literal: true

class CityBuildingsController < ApplicationController
  include CurrentCharacterContext

  before_action :ensure_active_character!
  before_action :load_building
  around_action :with_building_access

  def show
    Game::World::ResumeContext.new(character: current_character).remember_city_building!(
      building_key: params[:building_key]
    )
    @building = Game::World::CityBuildingCatalog.fetch(@building_key, zone: @position.zone)
    if @building_key == "airship_station"
      @airship_routes = Game::World::AirshipTravel.new(character: current_character).station_routes!
    end
    if @building_key == "workshop"
      Game::Professions::Templates.ensure_craft_items!
      @profession_recipes = Game::Professions::Catalog.recipes_for_building("workshop")
      @tar_smith_skill = current_character.metadata.to_h.dig("profession_skills", "tar_smith").to_i
    end
    if @building_key == "junk_dealer"
      Game::Professions::Templates.ensure_craft_items!
      @junk_offers = Game::Shop::JunkBuyback.offer_rows_for(current_character)
    end
    if @building_key == "hospital"
      Game::Professions::Templates.ensure_craft_items!
      @injury_summary = Game::Combat::InjuryState.new(character: current_character).summary
      @profession_recipes = Game::Professions::Catalog.recipes_for_building("hospital")
      @ash_healer_skill = current_character.metadata.to_h.dig("profession_skills", "ash_healer").to_i
      @veil_marks = (current_user.currency_wallet || current_user.create_currency_wallet!(nv_balance: 0)).veil_marks.to_i
      @premium_offers = Game::Shop::PremiumScrollPurchase::OFFERINGS
    end
    prepare_presence_context
  end

  def rest
    case @building_key
    when "hospital"
      result = Game::World::HospitalRest.new(character: current_character).call
      target = city_building_path("hospital")
    when "tavern"
      result = Game::World::TavernRest.new(character: current_character).call
      target = city_building_path("tavern")
    else
      redirect_to world_path, alert: I18n.t("game.buildings.rest_unavailable") and return
    end

    if result.success
      redirect_to target, notice: result.message
    else
      redirect_to target, alert: result.message
    end
  end

  def craft
    unless %w[workshop hospital].include?(@building_key)
      redirect_to world_path, alert: I18n.t("game.professions.workshop_only") and return
    end

    recipe = Game::Professions::Catalog.recipe(params[:recipe_key])
    profession = recipe && Game::Professions::Catalog.professions[recipe["profession"].to_s]
    if profession && profession["building_key"].to_s != @building_key
      redirect_to city_building_path(@building_key), alert: I18n.t("game.professions.wrong_building") and return
    end

    result = Game::Professions::Craft.new(
      character: current_character,
      recipe_key: params[:recipe_key]
    ).call
    if result.success
      redirect_to city_building_path(@building_key), notice: result.message
    else
      redirect_to city_building_path(@building_key), alert: result.message
    end
  end

  def buy_premium
    unless @building_key == "hospital"
      redirect_to world_path, alert: I18n.t("game.buildings.hospital_only") and return
    end

    result = Game::Shop::PremiumScrollPurchase.new(
      character: current_character,
      item_key: params[:item_key]
    ).call
    if result.success
      redirect_to city_building_path("hospital"), notice: result.message
    else
      redirect_to city_building_path("hospital"), alert: result.message
    end
  end

  def topup_vm
    unless @building_key == "hospital"
      redirect_to world_path, alert: I18n.t("game.buildings.hospital_only") and return
    end

    result = Game::Shop::VeilMarksTopUp.new(character: current_character).call
    if result.success
      redirect_to city_building_path("hospital"), notice: result.message
    else
      redirect_to city_building_path("hospital"), alert: result.message
    end
  end

  def sell
    unless @building_key == "junk_dealer"
      redirect_to world_path, alert: I18n.t("game.buildings.junk_only") and return
    end

    result = Game::Shop::JunkBuyback.new(
      character: current_character,
      item_key: params[:item_key],
      quantity: params[:quantity]
    ).call
    if result.success
      redirect_to city_building_path("junk_dealer"), notice: result.message
    else
      redirect_to city_building_path("junk_dealer"), alert: result.message
    end
  end

  private

  def load_building
    @building_key = params[:building_key].to_s
    @building = Game::World::CityBuildingCatalog.fetch(@building_key)
    redirect_to(world_path, alert: "Здание не найдено.") unless @building
  end

  # Entry changes saved room state. Revalidate and render under the same lock
  # as city movement so a concurrent relocation cannot admit a stale building.
  def with_building_access
    current_character.with_lock do
      ensure_building_access!
      unless performed?
        @position = current_character.position
        yield
      end
    end
  end

  def ensure_building_access!
    return if performed?
    return if Game::World::CityBuildingCatalog.accessible?(
      character: current_character,
      building_key: @building_key
    )

    redirect_to world_path, alert: "Войдите в здание из текущего района города."
  end
end
