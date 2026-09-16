extends SceneTree
## ⛑ DOES A TRIVIAL ENCOUNTER PAY WHAT THE FIGHT WOULD HAVE PAID?
##
## Owner 2026-09-13, accepting trivial-encounter auto-resolve: **"FULL rewards, not token XP"** -
## because anything less quietly taxes the player the feature exists to help.
##
## That claim is the whole design, and it is exactly the shape of claim this project has got wrong
## before: the co-op payout paid raw BASE XP for the life of party combat because a second reward
## site existed beside `kill_xp`, and nobody noticed for months. So this does not read the code -
## it runs the resolve and compares the XP actually banked against `kill_xp`, the one place XP is
## sized, and checks that no combat is left running afterwards.
##
## Run:
##   godot --headless --path . --script res://tools/probe/trivial_encounter.gd

const ServerScript := preload("res://server/server.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	get_root().add_child(sim)
	await process_frame
	var cm = sim.combat_mgr if "combat_mgr" in sim else null
	if cm == null:
		cm = load("res://shared/combat_manager.gd").new()
		get_root().add_child(cm)

	print("===== 1. THE PAYOUT IS THE SAME SUM THE FIGHT USES =====")
	var ch = sim.make_char(30, "average", "Fighter", "Human")
	ch.initialize_deck_collection_if_needed()
	var mdb = load("res://shared/monster_database.gd").new()
	add_child_safe(mdb)
	var monster: Dictionary = mdb.generate_monster_by_name("Goblin", 8, true, "normal")
	ck(not monster.is_empty(), "a level 8 Goblin was generated")

	# The one place XP is sized. Asked BEFORE the resolve, because the resolve banks it.
	# Is `kill_xp` even deterministic? If it rolls, comparing one call against another proves
	# nothing - so ask twice before trusting the number as an expectation.
	var e1: int = int(cm.kill_xp(ch, monster, []).get("xp", -1))
	var e2: int = int(cm.kill_xp(ch, monster, []).get("xp", -1))
	ck(e1 == e2, "kill_xp is deterministic (%d, %d) - safe to compare against" % [e1, e2])
	var expected: int = e1
	var xp_before: int = int(ch.experience)
	var comp_battles_before: int = int(ch.companion_battles) if "companion_battles" in ch else 0

	var res: Dictionary = cm.resolve_without_fight(1, ch, monster)
	var banked: int = int(ch.experience) - xp_before
	print("  kill_xp said %d, the character banked %d" % [expected, banked])
	ck(bool(res.get("success", false)), "the resolve reported success")
	ck(expected > 0, "the kill is worth something at all (%d)" % expected)
	# ⛑ `kill_xp` IS NOT THE FINAL NUMBER, and the first version of this check assumed it was.
	# It reported "kill_xp said 126, banked 138" and called the feature broken. The gap is
	# `add_experience`, which applies the RACE and Sanctuary multiplier (Human +10%) on top -
	# and a real victory goes through exactly the same call. So the honest expectation is
	# "kill_xp, passed through this character's add_experience", and it is MEASURED by banking
	# the same number on a twin rather than restating the multiplier here. Restating it would
	# be the second copy of a formula that this probe exists to rule out.
	var twin = sim.make_char(30, "average", "Fighter", "Human")
	var twin_before: int = int(twin.experience)
	twin.add_experience(expected)
	var through_mult: int = int(twin.experience) - twin_before
	ck(banked == through_mult,
		"banked (%d) == kill_xp through add_experience (%d) - no second reward site" % [banked, through_mult])

	print("\n===== 2. AND IT LEAVES NO FIGHT RUNNING =====")
	# The resolve starts a real combat and wins it. If the victory path did not tear that down,
	# the player would be stuck in a fight they were never shown.
	ck(not bool(ch.in_combat), "the character is NOT left in combat")
	ck(not cm.active_combats.has(1), "no combat state is left registered for the peer")

	print("\n===== 3. WHICH ENCOUNTERS COUNT AS TRIVIAL =====")
	var srv = ServerScript.new()
	var lo = mdb.generate_monster_by_name("Goblin", 8, true, "normal")     # 8 vs 30/3 = 10
	var hi = mdb.generate_monster_by_name("Goblin", 15, true, "normal")    # 15 > 10
	var elite = mdb.generate_monster_by_name("Goblin", 8, true, "elite")
	ck(srv._encounter_is_trivial(ch, lo, 8), "level 8 against a level 30 player IS trivial")
	ck(not srv._encounter_is_trivial(ch, hi, 15), "level 15 against a level 30 player is NOT")
	ck(not srv._encounter_is_trivial(ch, elite, 8), "an ELITE is never trivial, however low")
	var spill = lo.duplicate()
	spill["threat_source"] = "Wraith Barrow"
	ck(not srv._encounter_is_trivial(ch, spill, 8), "a threat-corridor spill is never trivial")
	var hot = lo.duplicate()
	hot["hotspot_intensity"] = 0.4
	ck(not srv._encounter_is_trivial(ch, hot, 8), "a hunting ground is never trivial")
	var young = sim.make_char(6, "average", "Fighter", "Human")
	ck(not srv._encounter_is_trivial(young, mdb.generate_monster_by_name("Goblin", 1, true, "normal"), 1),
		"a low-level character never gets free kills (everything is still a fight for them)")

	print("\n===== VERDICT =====")
	print("  all checks PASS" if fails == 0 else "  %d check(s) FAIL" % fails)
	quit(0)


func add_child_safe(n: Node) -> void:
	if n is Node and n.get_parent() == null:
		get_root().add_child(n)
