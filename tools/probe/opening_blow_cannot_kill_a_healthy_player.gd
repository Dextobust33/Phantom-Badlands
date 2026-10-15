extends SceneTree
## Owner 2026-10-14 (rank-1 Sorcerer: 6,060 damage in round one against 2,242 HP, no action taken):
## "it should still be possible to get killed in the first round but only if the player is blatantly
## pushing way past what they should be fighting (severely underleveled and undergeared)."
##
## In a PROTECTED fight the monster's FIRST turn cannot take more than 75% of max HP. An over-reacher
## (monster far above you, or gear far behind) is NOT protected and can still die in round one.
## Every case uses a monster strong enough that one landed hit would kill outright.
const CharacterScript = preload("res://shared/character.gd")
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

var sim

func _fight(level: int, mon_level: int, gear: String = "average"):
	var ch = sim.make_char(level, gear, "Sorcerer", "Dwarf")
	var mon = sim.make_monster(mon_level, "normal", 1.0)
	mon["strength"] = 5000000
	ch.in_combat = false
	sim.combat_mgr.start_combat(0, ch, mon)
	var c = sim.combat_mgr.active_combats[0]
	c["monster_turns_taken"] = 0          # the fight's OWN first strike (if any) already ran; test a fresh opening
	ch.current_hp = ch.get_total_max_hp()
	return [ch, c]

# one trial: the monster's opening turn; returns [dead, hp_after, max_hp, message]
func _opening(level: int, mon_level: int, start_frac: float = 1.0, gear: String = "average") -> Array:
	var f = _fight(level, mon_level, gear)
	var ch = f[0]
	var c = f[1]
	ch.current_hp = int(ch.get_total_max_hp() * start_frac)
	var r: Dictionary = sim.combat_mgr.process_monster_turn(c)
	var out: Array = [ch.current_hp <= 0, ch.current_hp, ch.get_total_max_hp(), str(r)]
	sim.combat_mgr.end_combat(0, false, false)
	return out

func _deaths(n: int, level: int, mon_level: int, start_frac: float = 1.0, gear: String = "average") -> Array:
	var dead := 0
	var saved := 0
	var min_frac := 9.0
	for i in n:
		var r := _opening(level, mon_level, start_frac, gear)
		if r[0]:
			dead += 1
		else:
			min_frac = minf(min_frac, float(r[1]) / float(r[2]))
		if str(r[3]).find("weather the opening blow") >= 0:
			saved += 1
	return [dead, saved, min_frac]

func _init() -> void:
	sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	get_root().add_child(sim)
	await process_frame
	var N := 40

	print("--- protected: a healthy player, monster +10 levels (the rank-1 Sorcerer's case) ---")
	var a := _deaths(N, 91, 101)
	ck(int(a[0]) == 0, "0 of %d opening turns killed a healthy L91 player (killed %d)" % [N, int(a[0])])
	ck(int(a[1]) > 0, "...and the cap really fired (%d of %d trials)" % [int(a[1]), N])
	ck(float(a[2]) >= 0.249, "...leaving at least 25%% of the bar (lowest survivor %.0f%%)" % (float(a[2]) * 100.0))

	print("--- not protected: blatantly over-reaching ---")
	var b := _deaths(N, 91, 91 + 91)       # monster at 2x the player's level
	ck(int(b[0]) > 0, "a monster at 2x your level CAN still kill in round one (%d of %d did)" % [int(b[0]), N])
	# severely under-geared: a L80 character with no stat growth at all (max HP far below the reference)
	var weak = CharacterScript.new()
	weak.initialize("Weak", "Sorcerer", "Dwarf")
	weak.level = 80
	var weak_dead := 0
	for i in N:
		weak.current_hp = weak.get_total_max_hp()
		var mon = sim.make_monster(80, "normal", 1.0)
		mon["strength"] = 5000000
		weak.in_combat = false
		sim.combat_mgr.start_combat(0, weak, mon)
		var c = sim.combat_mgr.active_combats[0]
		c["monster_turns_taken"] = 0
		weak.current_hp = weak.get_total_max_hp()
		sim.combat_mgr.process_monster_turn(c)
		if weak.current_hp <= 0:
			weak_dead += 1
		sim.combat_mgr.end_combat(0, false, false)
	ck(weak_dead > 0, "a severely under-geared L80 (max HP %d vs reference %.0f) is NOT protected and can die (%d of %d)" % [weak.get_total_max_hp(), CharacterScript.reference_player_hp(80), weak_dead, N])

	print("--- the edges ---")
	var w := _deaths(N, 91, 101, 0.4)
	ck(int(w[0]) > 0, "walking in under half health gets no cap (%d of %d died)" % [int(w[0]), N])
	# second turn is uncapped
	var f = _fight(91, 101)
	var ch = f[0]
	var c = f[1]
	sim.combat_mgr.process_monster_turn(c)                     # opening (capped)
	var second_dead := 0
	for i in 30:
		ch.current_hp = ch.get_total_max_hp()
		sim.combat_mgr.process_monster_turn(c)                 # later turns: uncapped
		if ch.current_hp <= 0:
			second_dead += 1
			break
	ck(second_dead > 0, "turns after the opening are NOT capped (a later turn killed a full-HP player)")
	sim.combat_mgr.end_combat(0, false, false)
	# a modest hit is untouched
	var g = _fight(91, 91)
	var mon2 = g[1].monster
	mon2["strength"] = 200
	var before: int = g[0].current_hp
	var rr: Dictionary = sim.combat_mgr.process_monster_turn(g[1])
	ck(str(rr).find("weather the opening blow") < 0, "an ordinary opening hit is left exactly as it was (no cap message)")
	sim.combat_mgr.end_combat(0, false, false)
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
