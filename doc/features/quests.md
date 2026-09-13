---
title: Quests Feature
description: Ashen sandbox starter quest journal with kill and delivery objectives.
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
auto-accept `veil_lure_drill` once. They can accept other contracts, track
kill/delivery progress, and turn in completed ones for NV and item rewards.

## 3. Server ownership

- `Game::Quests::Catalog` — YAML quest definitions
- `Game::Quests::Journal` — accept / progress / turn-in mutations on
  `character.metadata["ashen_quests"]`
- `QuestsController` — HTTP boundary
- `Arena::CombatProcessor` — records NPC kill progress after victory

## 4. Persistence and failure

All accept/turn-in mutations run under character lock. Failed turn-in leaves
quest state and inventory unchanged. Unknown keys and already-completed quests
reject safely.

## 5. Coverage

Focused service/request coverage exists for accept, incomplete turn-in, and
reward grant paths where present. Live smoke exercises accept on
`veil_tail_delivery`. Starter craft contracts include Tar Smith bandage and
Ash Healer novice bag (`ash_healer_first_bag`).

## 6. Non-goals

- Neverlands dialogue trees, cancellation UI, and shared party quests
- Merchant qualification “quest” owned by Shop Economy
- Invented evidence for missing Neverlands quest formulas

## 7. History

| Date | Change |
|---|---|
| 2026-09-13 | Added Ash Healer first-bag delivery contract (`ash_healer_first_bag`). |
| 2026-09-13 | Promoted from NOT_IMPLEMENTED: Ashen starter journal + kill/delivery loop. |
| 2026-08-26 | Gap record under feature-gap-v2. |
| 2026-07-29 | Recorded audited NOT_IMPLEMENTED boundary. |
