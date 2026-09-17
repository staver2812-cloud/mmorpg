# frozen_string_literal: true

# Registers Ashen Veil dungeon/raid/progression catalogs as config payloads.
# Runtime entry/UI intentionally deferred — catalogs are available for later wiring
# without changing Neverlands shell or combat button locks.
return unless defined?(Rails)

%w[
  ashen_veil_progression.json
  ashen_veil_dungeon_catalog.json
  ashen_veil_raid_catalog.json
].each do |name|
  path = Rails.root.join("config/gameplay", name)
  unless path.exist?
    warn "#{name} missing — skip"
    next
  end

  payload = JSON.parse(path.read)
  count = payload["count"] || Array(payload["dungeons"] || payload["raids"] || payload["level_bands"]).size
  puts "Ashen Veil catalog ready: #{name} entries=#{count} version=#{payload["catalog_version"] || payload["milestone"]}"
end
