# Overnight note — 2026-09-13

## Critical fix
Production outdoor gate cells (`[6,8]`, `[11,9]`) existed, but `TileBuilding`
rows for `outpost_gate` / `outpost_east_gate` were missing — players could leave
the city and had **no enter-city action**. Migration
`20260913120000_repair_ashen_forpost_gate_entrances` runs `Seeds::ForpostGateRepair`.

## Also shipped
- Landmark interiors (tavern rumors, guard map, library handbook)
- Airship return-to-city header
- Dust chanter NPC + quest
- `scripts/ashen_nav_smoke.py` connectivity checks

## Verify
- `python scripts/ashen_smoke.py`
- `python scripts/ashen_nav_smoke.py` (west/east re-enter must pass)

## GitHub
Push still needs interactive login on your machine. Do not paste passwords in chat.
Local branch is ahead of origin; bundle backups under `%USERPROFILE%\tidekeep-backups\`.
