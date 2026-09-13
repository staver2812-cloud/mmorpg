---
title: Professions Feature
description: Ashen sandbox workshop craft (Tar Smith) plus remaining Neverlands profession gaps.
status: Partially Implemented
updated: 2026-09-13
owners: [Professions]
template: feature-v3
---

# Professions

## 1. Authority and scope

Ashen sandbox ships a playable Tar Smith craft loop at the Pitch Forge
(`workshop`). Broader Neverlands gathering/fishing/mining counters and tool
timers remain deferred; those flows are not invented here.

- Design gap / Neverlands boundary: `doc/design/features/professions.md`
- Related runtime: `doc/features/city.md`, `doc/features/player_inventory.md`, `doc/features/world.md`

Shipped now: workshop recipes, material consumption, output grant, profession
skill bump in `character.metadata["profession_skills"]["tar_smith"]`, plus Ash
Healer bags crafted at Coal Infirmary (`ash_healer`) that clear light/heavy/combat
injuries by tier instantly. Injury timers (light ~20–45m, heavy ~2h, combat ~12h)
are untreated expiry only. Combat trauma scrolls and heal scrolls are bought for
Veil Marks (VM) at the Infirmary premium desk. The trauma scroll also powers
same-cell world Assault (`POST /world/assault`), not only the Arena checkbox.
Sandbox players can claim +50 VM once per hour at the same desk
(`POST /city/buildings/hospital/topup_vm`) so scroll testing does not stall.
Starter kits grant capacity-safe `ash_herb` stacks; the junk dealer buys herbs and
surplus thematic `set-*-t5` drops (8 NV each).

## 2. Player-facing behavior

On the Pitch Forge building page the player sees Tar Smith skill and recipe
cards. Crafting posts to the workshop craft route, consumes exact unequipped
material stacks, grants the output item, and increases skill. Recipes with a
`min_skill` gate reject early without consuming inputs.

## 3. Server ownership

- `Game::Professions::Catalog` — YAML recipes
- `Game::Professions::Craft` — locked craft mutation
- `Game::Professions::Templates` — craft item templates
- `CityBuildingsController#craft` — HTTP boundary
- Config: `config/gameplay/ashen_professions.yml`

## 4. Persistence and failure

Craft runs under the character lock. Missing materials, capacity overflow, or
skill gate leave inventory unchanged. Successful craft persists inventory and
metadata skill together.

## 5. UI surfaces

- `/city/buildings/workshop` lists recipes and craft buttons; desk exposes
  `data-workshop-any-ready` plus per-card `data-workshop-recipe` /
  `data-workshop-ready`
- `/city/buildings/hospital` Ash Healer craft exposes
  `data-hospital-craft-any-ready` plus per-card `data-hospital-recipe` /
  `data-hospital-craft-ready`
- Consumables `ashen_bandage` / `veil_field_kit` heal via existing inventory use

## 6. Tests

- `spec/services/game/professions/craft_spec.rb`

## 7. Explicit gaps

Neverlands successful fishing/gathering/digging timers, tools, Observation
modifiers, and profession quests remain unimplemented.

## 8. Change log

| Date | Change |
|---|---|
| 2026-09-13 | Pitch Forge states gear repair is deferred and links to Inventory wear/broken clarity. |
| 2026-09-13 | Sandbox Veil Marks hourly top-up at Infirmary desk for trauma/heal scroll testing. |
| 2026-09-13 | Craft buttons gate on skill/materials; craft flash names the correct profession. |
| 2026-09-13 | Workshop/Infirmary craft cards show owned/needed material counts with display names. |
| 2026-09-13 | Junk buyback accepts surplus `set-*-t5` drops at 8 NV. |
| 2026-09-13 | Junk buyback accepts ash herbs; starter kit grants capacity-safe herbs for healer craft. |
| 2026-09-13 | Clarified instant healer treatment vs injury expiry timers; trauma scroll also powers same-cell world Assault. |
| 2026-09-13 | Promoted from NOT_IMPLEMENTED: Ashen Tar Smith workshop craft loop. |
| 2026-07-29 | Recorded the audited NOT_IMPLEMENTED boundary. |
