# Todo

## 2026-11-06 — "Character name already taken" for dead character Dexto
- [x] Root cause: delete left `.json.bak`; `_safe_load` resurrected the character file
- [x] Fix `persistence_manager.gd::delete_character` to sweep `.bak`/`.tmp`
- [ ] Deploy server (needs release + countdown — owner's call)
- [ ] Live cleanup: remove ghost `acc_1_dexto.json*` (+ `dexto2/3/dextobust` .bak) and free the companion slot checked out by "Dexto"
