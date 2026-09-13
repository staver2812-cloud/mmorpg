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

## Recent shipped
- Gate re-entry repair (west/east)
- Nav smoke 33/33, ashen smoke 39/39
- Shore NPCs/quests, landmark handbook, airship city exit
