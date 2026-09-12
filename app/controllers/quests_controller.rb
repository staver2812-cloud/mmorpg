# frozen_string_literal: true

class QuestsController < ApplicationController
  include CurrentCharacterContext

  before_action :ensure_active_character!
  layout "game"

  def index
    @entries = Game::Quests::Journal.new(character: current_character).entries
  end

  def accept
    result = Game::Quests::Journal.new(character: current_character).accept!(params[:id])
    redirect_to quests_path, status: :see_other, **flash_for(result)
  end

  def turn_in
    result = Game::Quests::Journal.new(character: current_character).turn_in!(params[:id])
    redirect_to quests_path, status: :see_other, **flash_for(result)
  end

  private

  def flash_for(result)
    result.success ? {notice: result.message} : {alert: result.message}
  end
end
