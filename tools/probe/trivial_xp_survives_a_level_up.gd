extends SceneTree
## Found reading the rank-1 Sorcerer's journal (2026-10-14): "Auto-resolved trivial encounter ...
## Corrosive Balrog (Lv 68) +-865071 XP". `resolve_without_fight` reported the change in the XP BAR,
## which wraps on a level-up, so a level-up fight was negative and printed NO "+XP" line to the player.
## The same kill must report the same XP whether or not it happens to level you.
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _gain(sim, level: int, exp_fraction: float) -> Dictionary:
	var ch = sim.make_char(level, "average", "Fighter", "Human")
	ch.experience = int(float(ch.experience_to_next_level) * exp_fraction)
	var mon = sim.make_monster(level - 20, "normal", 1.0)
	ch.in_combat = false
	var lv0: int = ch.level
	var r: Dictionary = sim.combat_mgr.resolve_without_fight(0, ch, mon)
	return {"gain": int(r.get("xp_gained", -1)), "levels": int(ch.level) - lv0, "ok": bool(r.get("success", false))}

func _init() -> void:
	var sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	get_root().add_child(sim)
	await process_frame
	seed(7)
	var plain := _gain(sim, 60, 0.0)
	seed(7)
	var lvl := _gain(sim, 60, 0.999)
	ck(plain.ok and lvl.ok, "both trivial fights resolved")
	ck(plain.levels == 0, "control: starting from an empty bar does not level (%d)" % plain.levels)
	ck(lvl.levels >= 1, "test: starting just under the threshold DOES level (%d level(s))" % lvl.levels)
	ck(plain.gain > 0, "control reports a positive XP gain (%d)" % plain.gain)
	ck(lvl.gain > 0, "the level-up fight reports a POSITIVE gain, not a wrapped negative (%d)" % lvl.gain)
	ck(absf(float(lvl.gain - plain.gain)) <= float(plain.gain) * 0.02, "...and it is the same XP as the same kill without a level-up (%d vs %d)" % [lvl.gain, plain.gain])
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
