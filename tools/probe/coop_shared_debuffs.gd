extends SceneTree
## ⛑ A DEBUFF ONE MEMBER LANDS PROTECTS THE WHOLE PARTY — AND TICKS ONCE.
##
## Owner decision 2026-09-16: charm, weakness and slow are SHARED in co-op, not per-member. Before
## this a charm protected only its caster - the monster stood motionless for one player and hit the
## other four in the same round.
##
## The half that is easy to get wrong is the SECOND half. The monster acts once per MEMBER in
## simultaneous co-op, and all three of these tick down inside that turn - weakness and slow in
## `_process_monster_dots`, charm in `process_monster_turn` itself. Shared but not de-duplicated, a
## 1-turn charm is spent by whoever acts first and a 2-round weakness expires in one round of a
## four-party. That is the same fault the poison keys were fixed for in #76, and it is invisible
## from the log: the debuff simply seems not to work for anybody but the caster.
##
## So this asserts the two properties together, off the real key tables.
##
## Run:
##   godot --headless --path . --script res://tools/probe/coop_shared_debuffs.gd

const CM := preload("res://shared/combat_manager.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var shared: Array = CM._PARTY_SHARED_MONSTER_KEYS
	var dots: Array = CM._PARTY_DOT_KEYS

	print("===== 1. THE THREE DEBUFFS ARE SHARED ACROSS THE PARTY =====")
	for k in ["monster_charmed", "monster_charmed_duration",
			"monster_weakness", "monster_weakness_duration",
			"monster_slowed", "monster_slow_duration"]:
		ck(k in shared, "%s is party-shared" % k)

	print("\n===== 2. AND EACH TICKS ONCE PER ROUND, NOT ONCE PER MEMBER =====")
	# Only the keys that actually COUNT DOWN need de-duplicating. The magnitude keys
	# (`monster_weakness`, `monster_slowed`) are read, not decremented, so zeroing them per action
	# would remove the debuff from every member after the first - the opposite mistake.
	for k in ["monster_charmed", "monster_weakness_duration", "monster_slow_duration"]:
		ck(k in dots, "%s is de-duplicated per round" % k)
	for k in ["monster_weakness", "monster_slowed"]:
		ck(not (k in dots), "%s is NOT de-duplicated (it is a magnitude, not a countdown)" % k)

	print("\n===== 3. AND THE OLD SHARED SET IS UNTOUCHED =====")
	# A regression here would be silent and expensive: poison ticking per member is 4x damage in a
	# four-party, which is what these lists were introduced to stop.
	for k in ["monster_poison", "monster_poison_duration", "monster_burn", "monster_burn_duration",
			"monster_bleed", "monster_bleed_duration"]:
		ck(k in shared and k in dots, "%s is still shared AND de-duplicated" % k)

	print("\n===== VERDICT =====")
	print("  all checks PASS" if fails == 0 else "  %d check(s) FAIL" % fails)
	quit(0)
