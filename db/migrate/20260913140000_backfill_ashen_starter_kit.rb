# frozen_string_literal: true

# Backfills the Ashen starter kit (bait + NV) for characters created before
# Game::World::StarterKit was hooked into Character.after_create.
class BackfillAshenStarterKit < ActiveRecord::Migration[8.1]
  def up
    return unless defined?(Character) && defined?(Game::World::StarterKit)

    updated = 0
    Character.find_each do |character|
      before = character.metadata.to_h[Game::World::StarterKit::METADATA_KEY]
      Game::World::StarterKit.new(character:).call
      after = character.reload.metadata.to_h[Game::World::StarterKit::METADATA_KEY]
      updated += 1 if before.blank? && after.present?
    end
    say "backfilled ashen starter kit for #{updated} characters"
  end

  def down
  end
end
