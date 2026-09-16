# frozen_string_literal: true

# Soft-release: reseed gate mite so early shore patrol quests are winnable.
class ReseedAshenOutdoorGateMiteSoftRelease < ActiveRecord::Migration[8.1]
  def up
    path = Rails.root.join("db/seeds/outdoor_npcs.rb")
    load path if File.exist?(path)
  end

  def down
  end
end
