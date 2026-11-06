# Todo

## 2026-11-06 — "Character name already taken" for dead character Dexto
- [x] Root cause: delete left `.json.bak`; `_safe_load` resurrected the character file
- [x] Fix `persistence_manager.gd::delete_character` to sweep `.bak`/`.tmp`
- [x] Deploy server (2026-11-06, hash e28fb43b verified via /proc/PID/exe)
- [x] Ghost acc_1_dexto.json* moved to ~/ghost_backup on server
- [ ] Owner: recall the Dexto-held companion in the Sanctuary; confirm "Dexto" can be created

## 2026-11-06 — Buff/debuff chips hard to read (Fighter opening turn)
- [x] Defence/guard buffs folded into ONE "Damage taken -N%" chip; sources + turns left in hover
- [x] "4T" -> "4 turns"; chip labels spelled out; hovers state the live value and turns left
- [x] Probe `tools/probe/status_chips_plain_words.gd` PASS
- [x] Shipped in client v0.9.847 (2026-11-06)
- [ ] Owner: look at it live; server combat-log lines still say "for 4T" (combat_manager.gd:9612/9622, needs server deploy)
