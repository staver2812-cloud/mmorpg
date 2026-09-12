# frozen_string_literal: true

class LocalesController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :reject_closed_game_session

  def update
    locale = params[:locale].to_s
    locale = I18n.default_locale.to_s unless I18n.available_locales.map(&:to_s).include?(locale)

    session[:locale] = locale
    cookies.permanent[:locale] = locale

    redirect_back fallback_location: root_path, status: :see_other
  end
end
