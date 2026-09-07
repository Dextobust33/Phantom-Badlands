# ARCHIVED — the legacy combat simulator (2026-09-07)

Superseded by `../real_combat_sim.gd`, which drives the REAL shared game code
(`shared/combat_manager.gd`, `shared/character.gd`, `shared/monster_database.gd`) instead of
re-implementing it.

**Do not run these to answer a balance question.** They carry hand-ported copies of the combat
formulas, the class passives and the stat model, and those copies are known to have drifted from
the game. One example found on 2026-09-07: `simulated_character.gd` held its own `CLASS_PASSIVES`
table that still described retired passives, so any measurement it produced about a class was
answering a question about a game that no longer exists.

They were fully orphaned when archived — nothing outside this folder referenced them, and
`real_combat_sim.gd` preloads none of them. Kept rather than deleted because the older simulation
RESULTS in `docs/simulation_results/` were produced by this code, and reading those numbers means
knowing what generated them.

Live tooling and how to use it: see `../README.md` and `docs/BACKLOG.md`
("How to work on balance without burning sessions").
