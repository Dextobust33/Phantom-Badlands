extends SceneTree
## `gold_find` must actually do something.
##
## It was authored on companion passives (the Kobold's "Treasure Sense"), shown to players as
## "+N% Valor Find", and consumed by NOTHING - it appeared only in client display code. Its own
## description promised "extra gold from kills", which could never work: `gold` is deprecated and
## an ordinary monster kill pays no valor at all.
##
## Owner supplied the wiring rather than have a faucet invented: *"It could offer a better chance
## to get the combat loot minigame which does give valor."*
const DT := preload("res://shared/drop_tables.gd")
const CL := preload("res://client/client.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var srv := FileAccess.get_file_as_string("res://server/server.gd")

	print("--- it is consumed by the server now, not only drawn by the client ---")
	ck(srv.contains('get_companion_bonus("gold_find")'),
		"the server reads the bonus")
	ck(srv.contains("_scratch_chance *= 1.0 + float(_gf) / 100.0"),
		"...and applies it to the loot-minigame roll, the faucet that pays Valor")

	print("\n--- applied RELATIVELY, so it cannot swamp the base rate ---")
	# A flat +20 percentage points on a 7% base would make the minigame the common case, which
	# the C3 dungeon tuning deliberately moved away from.
	var base := 0.07
	for gf in [0, 5, 20, 50]:
		var lifted: float = base * (1.0 + float(gf) / 100.0)
		print("    +%-3d%% companion -> %.1f%% chance (base %.1f%%)" % [gf, lifted * 100.0, base * 100.0])
		ck(lifted < 0.20, "  +%d%% stays well under the 20%% mark" % gf)
	ck(srv.contains("_scratch_chance = minf(_scratch_chance, COMBAT_SCRATCH_MAX_CHANCE)"),
		"and the existing cap still bounds it, so no companion guarantees the minigame")

	print("")
	print("--- and it is REACHABLE: it survives from the passive to the roll ---")
	# The first version of this probe checked only `bonuses` and FAILED - no companion carries
	# gold_find there. It lives on the Kobold as a PASSIVE, and the passive applier had no branch
	# for it, so the effect was dropped by a match that fell through. Reading one source would
	# have shipped a no-op that compiled cleanly.
	var carriers: Array[String] = []
	var cli := FileAccess.get_file_as_string("res://client/client.gd")
	for mtype in DT.COMPANION_DATA:
		var b: Dictionary = DT.COMPANION_DATA[mtype].get("bonuses", {})
		if int(b.get("gold_find", 0)) > 0:
			carriers.append(String(mtype))
	var as_passive: bool = cli.contains('"effect": "gold_find"')
	ck(as_passive or not carriers.is_empty(),
		"some companion actually grants it (bonuses: %s | as passive: %s)" % [
			("none" if carriers.is_empty() else ", ".join(carriers)), str(as_passive)])
	var cm := FileAccess.get_file_as_string("res://shared/combat_manager.gd")
	ck(cm.contains('combat_state["companion_gold_find"]'),
		"the passive applier has a branch for it now - it used to fall through silently")
	ck(cm.contains('"companion_gold_find": int(combat.get("companion_gold_find", 0)),'),
		"...and the combat-end result carries it out to the server")
	ck(srv.contains('_gf += int(result.get("companion_gold_find", 0))'),
		"...where the loot roll adds it to any bonuses value, reading BOTH sources")
	ck(cm.contains('combat_state["companion_gathering_hint"]'),
		"gathering_hint, which fell through the same match, has a branch too")

	print("\n--- and its description no longer promises the thing that never existed ---")
	var d: String = String(CL.COMPANION_STAT_HELP.get("gold_find", ""))
	ck(not d.contains("NOT CURRENTLY APPLIED"), "the 'not applied' warning is gone")
	ck(not d.to_lower().contains("gold from kills"),
		"...and it no longer claims gold from kills, which is not a thing that happens")
	ck(d.contains("loot minigame"), "it says what it really does: \"%s\"" % d.substr(0, 62))

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
