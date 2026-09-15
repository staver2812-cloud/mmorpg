# frozen_string_literal: true

# Starts an Ashen same-cell PvP assault that consumes a combat trauma scroll.
class WorldAssaultsController < ApplicationController
  include CurrentCharacterContext

  before_action :ensure_active_character!

  def create
    result = Game::World::StartPlayerAssault.new(
      attacker: current_character,
      defender_id: params[:defender_id]
    ).call

    if result.success
      redirect_to arena_match_path(result.match), notice: result.message
    else
      redirect_to world_path(assault_denied: 1), alert: result.message, status: :see_other
    end
  end
end
