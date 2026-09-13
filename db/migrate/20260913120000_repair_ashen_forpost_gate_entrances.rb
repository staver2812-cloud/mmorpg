# frozen_string_literal: true

class RepairAshenForpostGateEntrances < ActiveRecord::Migration[8.1]
  def up
    repair_path = Rails.root.join("db/seeds/forpost_gate_repair.rb")
    support_path = Rails.root.join("db/seeds/world_content_support.rb")
    return unless File.exist?(repair_path) && File.exist?(support_path)

    say_with_time "repair Forpost outdoor gate TileBuilding entrances" do
      load support_path
      load repair_path
      result = Seeds::ForpostGateRepair.new.call
      say "gate repair changes=#{result.inspect}"
      result
    end
  end

  def down
  end
end
