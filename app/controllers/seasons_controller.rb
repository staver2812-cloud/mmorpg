# frozen_string_literal: true

# Seasonal battle-pass FOMO surface (Mist-style retention + convenience VM track).
class SeasonsController < ApplicationController
  include CurrentCharacterContext

  before_action :ensure_active_character!
  layout "game"

  def show
    @season = Game::Seasons::Progress.new(character: current_character).snapshot
    @wallet = current_user.currency_wallet || current_user.create_currency_wallet!(nv_balance: 0)
  end

  def unlock_premium
    result = Game::Seasons::Progress.new(character: current_character).unlock_premium!
    redirect_to season_path, status: :see_other, **flash_for(result)
  end

  def claim
    result = Game::Seasons::Progress.new(character: current_character).claim!(
      track: params[:track],
      level: params[:level]
    )
    redirect_to season_path, status: :see_other, **flash_for(result)
  end

  private

  def flash_for(result)
    result.success ? {notice: result.message} : {alert: result.message}
  end
end
