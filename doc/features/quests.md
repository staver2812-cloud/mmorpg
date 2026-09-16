---
title: Quests Feature
description: Ashen sandbox starter quest journal with gated craft/shore chains.
status: Partially Implemented
updated: 2026-09-13
owners: [NPCs and Quests]
template: feature-v3
---

# Quests

## 1. Authority and scope

Ashen sandbox ships a playable starter quest journal. Full Neverlands NPC
dialogue trees and multi-step quest engines remain deferred; this handbook
describes only the verified Ashen runtime.

- Config: `config/gameplay/ashen_quests.yml`
- Related runtime: `doc/features/city.md`, `doc/features/world.md`, `doc/features/arena_combat.md`

## 2. Player-facing behavior

Players open quests from Coal Hall or `/quests`. New playable characters
auto-accept `veil_lure_drill` once. Contracts use `requires` / `unlocks` so
later shore and craft jobs stay locked until earlier ones are turned in;
successful turn-in can auto-accept the next key in `unlocks`. Journal cards show
where-hints, named item rewards, and locked/available/active/completed status.
Kill and delivery objectives grant NV, XP, and item rewards. Soft-release
`veil_lure_drill` also accepts a Help Hall `arena_training_dummy` kill so
level-zero players can complete the first contract without waiting on shore
ambushes.

## 3. Server ownership

- `Game::Quests::Catalog` — YAML quest definitions
- `Game::Quests::Journal` — accept / progress / turn-in mutations on
  `character.metadata["ashen_quests"]` (requirement gate + auto-unlock)
- `QuestsController` — HTTP boundary
- `Arena::CombatProcessor` — records NPC kill progress after victory

## 4. Persistence and failure

All accept/turn-in mutations run under character lock. Failed turn-in leaves
quest state and inventory unchanged. Unknown keys, unmet `requires`, and
already-completed quests reject safely.

## 5. Coverage

Focused service/request coverage exists for accept, locked gate, auto-unlock,
incomplete turn-in, and reward grant paths where present. Live smoke verifies
the starter lure is active and chain accepts of `veil_tail_delivery` stay locked.
Craft spine includes Tar Smith bandage, field kit / lure pack, and Ash Healer
novice → adept → master bags.

## 6. Non-goals

- Neverlands dialogue trees, cancellation UI, and shared party quests
- Merchant qualification “quest” owned by Shop Economy
- Invented evidence for missing Neverlands quest formulas

## 7. History

| Date | Change |
|---|---|
| 2026-09-16 | Soft-release smoke farms `ash_mite_patrol` gate-mite bait wins and turns in after gift. |
| 2026-09-16 | Soft-release adept prep caps light-bag skill climb so bandages accumulate for `healer_bag_heavy` (343/343). |
| 2026-09-15 | Soft-release smoke crafts `healer_bag_heavy` and turns in `ash_healer_adept_bag` after lure pack. |
| 2026-09-15 | Soft-release smoke crafts `tar_lure_pack` and turns in `tar_lure_pack_contract` (5 bait) after field kit. |
| 2026-09-15 | Soft-release smoke restocks Relic mats (incl. `rat_tail`), crafts `veil_field_kit`, and turns in `tar_field_kit_contract`. |
| 2026-09-15 | Soft-release smoke chain: Help Hall win → `veil_lure_drill` → `veil_tail_delivery` → forge bandage → Infirmary healer bag turn-ins. |
| 2026-09-15 | Soft-release turn-in: bag-full item rewards are skipped (logged) instead of 500; `veil_lure_drill` no longer grants redundant bait. |
| 2026-09-15 | Help Hall training dummy soft-release: always-defend (`defend_chance=1`), no injected magic attacks. |
| 2026-09-15 | Soft-release: `veil_lure_drill` also counts Help Hall `arena_training_dummy` kills; where-hint covers Arena → Help Hall. |
| 2026-09-15 | Failed accept/turn-in (unknown or rejected) returns to the journal with `quest_denied=1` recovery chrome. |
| 2026-09-14 | Hall/World journal board link exposes `data-quest-recovery`; smoke asserts it. |
| 2026-09-14 | Quests journal always links to Coal Hall board (`data-quest-hall-link`); when Hall is out of district the link opens City. Locked contracts recover to World. |
| 2026-09-14 | Completed quest cards also recover to World (`data-quest-done`). |
| 2026-09-14 | Coarse-pointer quest accept/turn-in controls and recovery links target ~44×44 CSS px (`UI-ADAPT-005`). |
| 2026-09-13 | City Hall quest summary exposes status counts (`data-city-hall-quest-active` / `available` / `locked` / `completed`) beside ready. |
| 2026-09-13 | Journal summary also exposes ready-to-turn-in count (`data-quest-ready-count`). |
| 2026-09-13 | Journal summary exposes available/active/locked/completed counts (`data-quest-summary` / `data-quest-available` / `active` / `locked` / `completed`); HUD chip exposes `data-quest-chip`. |
| 2026-09-13 | HUD quest chip marks ready-to-turn-in state (`chip_ready` / `nl-quest-chip--ready`). |
| 2026-09-13 | Active quests gate turn-in until progress meets target; ready badge + `data-quest-ready`. |
| 2026-09-13 | Live delivery progress, journal status sort, City Hall board counts/active chip, thematic reward ensure. |
| 2026-09-13 | Quest spine: `requires`/`unlocks`/`where_*`, Tar Smith + Healer mastery contracts, locked UI. |
| 2026-09-13 | Added Ash Healer first-bag delivery contract (`ash_healer_first_bag`). |
| 2026-09-13 | Promoted from NOT_IMPLEMENTED: Ashen starter journal + kill/delivery loop. |
| 2026-08-26 | Gap record under feature-gap-v2. |
| 2026-07-29 | Recorded audited NOT_IMPLEMENTED boundary. |
