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
    if @building_key == "junk_dealer" || @building_key == "market"
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
    if @building_key == "bank"
      wallet = current_user.currency_wallet || current_user.create_currency_wallet!(nv_balance: 0)
      @bank_wallet_nv = wallet.nv_balance.to_i
      @bank_vault_nv = Game::World::BankVault.balance_for(current_character)
      @veil_marks = wallet.veil_marks.to_i
      @bank_item = Game::World::BankItemLocker.stored_for(current_character)
      @bank_deposit_options = current_character.inventory&.inventory_items
        &.where(equipped: false)
        &.includes(:item_template)
        &.select { |row| row.quantity.to_i.positive? }
        &.map { |row| [row.item_template.display_name, row.item_template.key, row.quantity.to_i] }
        &.uniq { |(_, key, _)| key } || []
    end
    if @building_key == "post"
      @post_note = Game::World::PostOfficeNote.current_for(current_character)
    end
    if @building_key == "souvenir_shop"
      Game::Professions::Templates.ensure_craft_items!
    end
    if @building_key == "obelisk"
      @obelisk_bound = Game::World::ObeliskRecall.bound_for(current_character)
    end
    if @building_key == "guard_tower"
      @guard_routes = Game::World::GuardTowerRoutes.new(character: current_character).call
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
      redirect_to world_path(building_denied: 1), alert: I18n.t("game.buildings.rest_unavailable"), status: :see_other
      return
    end

    if result.success
      redirect_to target, notice: result.message
    else
      redirect_to target, alert: result.message
    end
  end

  def craft
    unless %w[workshop hospital].include?(@building_key)
      redirect_to world_path(building_denied: 1), alert: I18n.t("game.professions.workshop_only"), status: :see_other
      return
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
      redirect_to world_path(building_denied: 1), alert: I18n.t("game.buildings.hospital_only"), status: :see_other
      return
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
      redirect_to world_path(building_denied: 1), alert: I18n.t("game.buildings.hospital_only"), status: :see_other
      return
    end

    result = Game::Shop::VeilMarksTopUp.new(character: current_character).call
    if result.success
      redirect_to city_building_path("hospital"), notice: result.message
    else
      redirect_to city_building_path("hospital"), alert: result.message
    end
  end

  def traumatologist
    unless @building_key == "hospital"
      redirect_to world_path(building_denied: 1), alert: I18n.t("game.buildings.hospital_only"), status: :see_other
      return
    end

    result = Game::Shop::TraumatologistClearance.new(character: current_character).call
    if result.success
      redirect_to city_building_path("hospital"), notice: result.message
    else
      redirect_to city_building_path("hospital"), alert: result.message
    end
  end

  def bless
    unless @building_key == "temple"
      redirect_to world_path(building_denied: 1), alert: I18n.t("game.buildings.temple_only"), status: :see_other
      return
    end

    result = Game::World::TempleBlessing.new(character: current_character).call
    extra = result.success ? {} : {temple_denied: 1}
    flash_opts = result.success ? {notice: result.message} : {alert: result.message}
    redirect_to city_building_path("temple", **extra), **flash_opts
  end

  def bank
    unless @building_key == "bank"
      redirect_to world_path(building_denied: 1), alert: I18n.t("game.buildings.bank_only"), status: :see_other
      return
    end

    result = Game::World::BankVault.new(
      character: current_character,
      amount: params[:amount],
      action: params[:bank_action]
    ).call
    redirect_bank(result)
  end

  def bank_item
    unless @building_key == "bank"
      redirect_to world_path(building_denied: 1), alert: I18n.t("game.buildings.bank_only"), status: :see_other
      return
    end

    result = Game::World::BankItemLocker.new(
      character: current_character,
      action: params[:bank_item_action],
      item_key: params[:item_key],
      quantity: params[:quantity]
    ).call
    redirect_bank(result)
  end

  def post
    unless @building_key == "post"
      redirect_to world_path(building_denied: 1), alert: I18n.t("game.buildings.post_only"), status: :see_other
      return
    end

    service = Game::World::PostOfficeNote.new(character: current_character, body: params[:body])
    result = if params[:post_action].to_s == "clear"
      service.clear!
    else
      service.save!
    end
    extra = result.success ? {} : {post_denied: 1}
    flash_opts = result.success ? {notice: result.message} : {alert: result.message}
    redirect_to city_building_path("post", **extra), **flash_opts
  end

  def souvenir
    unless @building_key == "souvenir_shop"
      redirect_to world_path(building_denied: 1), alert: I18n.t("game.buildings.souvenir_only"), status: :see_other
      return
    end

    result = Game::World::SouvenirPurchase.new(
      character: current_character,
      item_key: params[:item_key]
    ).call
    extra = result.success ? {} : {souvenir_denied: 1}
    flash_opts = result.success ? {notice: result.message} : {alert: result.message}
    redirect_to city_building_path("souvenir_shop", **extra), **flash_opts
  end

  def obelisk
    unless @building_key == "obelisk"
      redirect_to world_path(building_denied: 1), alert: I18n.t("game.buildings.obelisk_only"), status: :see_other
      return
    end

    result = Game::World::ObeliskRecall.new(
      character: current_character,
      action: params[:obelisk_action]
    ).call
    if result.success
      if params[:obelisk_action].to_s == "recall"
        redirect_to world_path, notice: result.message
      else
        redirect_to city_building_path("obelisk"), notice: result.message
      end
    else
      redirect_to city_building_path("obelisk", obelisk_desk_denied: 1), alert: result.message
    end
  end

  def law
    unless @building_key == "law_abode"
      redirect_to world_path(building_denied: 1), alert: I18n.t("game.buildings.law_only"), status: :see_other
      return
    end

    result = Game::World::LawAlignmentPledge.new(
      character: current_character,
      alignment: params[:alignment]
    ).call
    if result.success
      redirect_to city_building_path("law_abode"), notice: result.message
    else
      redirect_to city_building_path("law_abode"), alert: result.message
    end
  end

  def sell
    unless @building_key == "junk_dealer"
      redirect_to world_path(building_denied: 1), alert: I18n.t("game.buildings.junk_only"), status: :see_other
      return
    end

    result = Game::Shop::JunkBuyback.new(
      character: current_character,
      item_key: params[:item_key],
      quantity: params[:quantity]
    ).call
    extra = result.success ? {} : {junk_denied: 1}
    flash_opts = result.success ? {notice: result.message} : {alert: result.message}
    redirect_to city_building_path("junk_dealer", **extra), **flash_opts
  end

  private

  def load_building
    @building_key = params[:building_key].to_s
    @building = Game::World::CityBuildingCatalog.fetch(@building_key)
    redirect_to(world_path(building_denied: 1), alert: I18n.t("game.flashes.building_not_found")) unless @building
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

    redirect_to world_path(building_denied: 1), alert: I18n.t("game.flashes.building_district_required")
  end

  def redirect_bank(result)
    extra = result.success ? {} : {bank_denied: 1}
    flash_opts = result.success ? {notice: result.message} : {alert: result.message}
    redirect_to city_building_path("bank", **extra), **flash_opts
  end
end
