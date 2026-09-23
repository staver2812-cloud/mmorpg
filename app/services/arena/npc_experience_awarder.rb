# frozen_string_literal: true

module Arena
  # Awards NPC experience for PvE victories. Solo fights use template xp_reward
  # (or explicit encounter_experience_reward). Multi-bot pools follow wiki
  # «средний уровень ботов» — average template XP × count with a small group
  # efficiency bonus. Party shares split by damage dealt (equal fallback).
  class NpcExperienceAwarder
    Result = Data.define(:character_id, :experience_awarded, :levels_gained, :skipped_reason, :party_awards)

    def initialize(match:, winning_team:)
      @match = match
      @winning_team = winning_team
    end

    def call
      return skipped("draw") if winning_team.blank?

      winners = match.arena_participations.players.where(team: winning_team).includes(:character).to_a
      return skipped("no_winners") if winners.empty?

      pool = experience_pool
      return skipped("no_configured_experience") unless pool.positive?

      shares = damage_shares(winners)
      party_awards = []
      primary = nil

      winners.each do |participation|
        character = participation.character
        raw = (pool * shares.fetch(participation.id)).round
        cap = Game::Progression::Catalog.fight_experience_cap(character.level)
        awarded = [raw, cap].min
        next unless awarded.positive?

        progression = Players::Progression::LevelUpService.new(character:).apply_experience!(awarded)
        entry = {
          character_id: character.id,
          experience_awarded: awarded,
          levels_gained: progression.levels_gained
        }
        party_awards << entry
        primary ||= entry
      end

      return skipped("unsupported_level") if party_awards.empty?

      Result.new(
        character_id: primary.fetch(:character_id),
        experience_awarded: primary.fetch(:experience_awarded),
        levels_gained: primary.fetch(:levels_gained),
        skipped_reason: nil,
        party_awards:
      )
    end

    private

    attr_reader :match, :winning_team

    def experience_pool
      explicit = explicit_encounter_experience
      return explicit if explicit

      npcs = defeated_enemy_npcs
      rewards = npcs.filter_map { |p| p.npc_template&.xp_reward.to_i }.select(&:positive?)
      return 0 if rewards.empty?
      return rewards.first if rewards.one?

      # Wiki: group bot fights use average bot strength, not a raw sum of outliers.
      average = rewards.sum.to_f / rewards.size
      efficiency = 1.0 + ((rewards.size - 1) * 0.05)
      (average * rewards.size * efficiency).round
    end

    def damage_shares(winners)
      damages = winners.to_h do |participation|
        dealt = participation.metadata.to_h["damage_dealt"].to_i
        [participation.id, [dealt, 0].max]
      end
      total = damages.values.sum
      if total <= 0
        equal = 1.0 / winners.size
        return winners.to_h { |p| [p.id, equal] }
      end

      damages.transform_values { |d| d.to_f / total }
    end

    def defeated_enemy_npcs
      match.arena_participations.npcs.where.not(team: winning_team).includes(:npc_template).select(&:defeat?)
    end

    def explicit_encounter_experience
      Integer(match.metadata.to_h["encounter_experience_reward"], exception: false)
    end

    def skipped(reason)
      Result.new(character_id: nil, experience_awarded: 0, levels_gained: 0, skipped_reason: reason, party_awards: [])
    end
  end
end
