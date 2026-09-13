# Overnight note — local-first saves

## Backup strategy (current)
- **Primary:** files + git history on this PC (`sandbox/neverlands-mmorpg`)
- **Safety copy:** `%USERPROFILE%\tidekeep-local-save\` via `scripts/local_save.ps1`
- **GitHub:** optional; not required while working alone on one computer

## Run save
```powershell
cd C:\Users\comp1\Projects\tidekeep\sandbox\neverlands-mmorpg
powershell -File scripts\local_save.ps1
```

## Live
https://web-production-bc5d0.up.railway.app/

## Recent shipped (2026-09-13)
- 5-minute passive bot ambush; forced fights consume Ashen Bait
- Starter kit: bait + 100 NV on first playable character
- Hospital free rest (HP/MP) out of combat
- Main-square starter tip for shore loop
- Gate re-entry, shore NPCs/quests, handbook, fight chrome lock

## Release staging (honest)
1. **Playable closed alpha (now → ~3–7 focused days):** register→city→gate→fight→quest→hospital loop holds for a stranger without soft-locks. Gaps left: death/return polish, starter weapon, denser shore, fewer stub buildings, mobile pass.
2. **Friends alpha (~1.5–3 weeks):** content pack + fewer empty interiors + chat/presence trust + crash/ops basics.
3. **Commercial / Mist-parity launch (2–4+ months):** professions, full shop/economy, injuries, dungeons, PvP depth — not the current target.

## Next slices (priority order)
1. Starter weapon + death/finish → hospital path
2. Shore content density (more cells/quests that pay off)
3. Stub buildings: clear “coming soon” vs one working action each
4. Mobile/viewport pass on fight + city
5. Ops: backup restore drill, wipe-safe admin
