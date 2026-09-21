# Soft-release backlog — Ashen Veil gap closure

Updated: 2026-09-20. Live regrowth countdown, Manage region status, global click smoke, art queue.

## Shipped this pass

- **Potions**: 21 blood-tiered 1h buffs (single + combined); shop ~2.7× craft price; level gates
- **Profile**: potion icons with hover tip (name + mods); online/offline + nick lookup
- **Inventory**: consumables show heal/buff mods, duration, blood tier; requirements (level) on the right
- **Gather**: per-group regrowth, tool durability, herbalist recipes, rare craft gear
- **Soft-release loop**: cell regrowth timers, herb/fish dailies, night herb weights, craft-only auction
- **Progression**: Blood I triad, Blood III anti-stack + clan laboratory gate, compact gear comparison
- **Live countdown**: Stimulus `nl-regrowth-timer` ticks server-projected remaining seconds on map cells
- **Manage region**: PlayableRegionStatus cache + dashboard last-build confirmation (boot + CTA)
- **Smoke**: `scripts/smoke_click.mjs` (+ `SMOKE_GLOBAL=1` full route walk)
- **Art**: markers done; `scripts/art_queue/fetch_cc0.py` + potion/herb/fish procedural queue

## Remaining / ideas

1. Hotspot re-authoring on new city arts
2. Forpost→Oktal still fare-only `[EVIDENCE]`
3. Broader profession-contract rotation
4. Wire procedural potion/herb icons into inventory/buff CSS when crops look good
5. GitHub push (auth still local-only; Railway via `railway up`)
