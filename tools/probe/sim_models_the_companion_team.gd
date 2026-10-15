extends SceneTree
## Item 14 S3: the simulator must PLAY the game being shipped (CLAUDE.md: an instrument that does not will certify the
## wrong curve with full confidence). With `--team` every character with a companion fields the whole team its level
## unlocks, and a fight really uses it. WITHOUT the flag nothing changes - the reference player stays companion-free.
## Run:  godot --headless --path . --script res://tools/probe/sim_models_the_companion_team.gd
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _init() -> void:
	var sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	get_root().add_child(sim)
	await process_frame
	sim._companion_mode = "lag"
	var plain = sim.make_char(100, "average", "Fighter", "Human")
	ck(plain.get_companion_party_ids().is_empty(), "without the flag: no team (%d)" % plain.get_companion_party_ids().size())
	ck(not plain.active_companion.is_empty(), "...but the beside-you companion is still drawn")
	sim._team_flag = true
	var t = sim.make_char(100, "average", "Fighter", "Human")
	ck(t.get_companion_party_ids().size() == 4, "with the flag at L100: the full four-companion column (%d)" % t.get_companion_party_ids().size())
	var roles := {}
	for c in t.get_companion_party():
		var Roles = load("res://shared/companion_roles.gd")
		roles[Roles.role_of(c)] = true
	ck(roles.size() == 4, "...role-balanced: tank, healer, striker, utility (%s)" % str(roles.keys()))
	var low = sim.make_char(5, "average", "Fighter", "Human")
	ck(low.get_companion_party_ids().is_empty(), "a level-5 character has no unlocked slots, so no team")
	var und = sim.make_char(100, "under", "Fighter", "Human")
	ck(und.active_companion.is_empty() and und.get_companion_party_ids().is_empty(), "an 'under' character still has no companions at all (the sim's own rule)")

	# A fight really uses the team. PAIRED: each trial is the SAME character fought twice, once alone and once after
	# the team is fielded (the first version compared two random characters and measured their gear, not the team).
	sim._team_flag = false
	var taken_plain := 0
	var taken_team := 0
	for i in 60:
		var ch = sim.make_char(100, "average", "Fighter", "Human")
		for pass_i in 2:
			if pass_i == 1:
				sim._field_team(ch, 100)
			var mon = sim.make_monster(100, "normal", 1.0)
			mon["abilities"] = []
			mon["empowered_mods"] = []
			ch.current_hp = ch.get_total_max_hp()
			ch.in_combat = false
			sim.combat_mgr.start_combat(0, ch, mon)
			var c = sim.combat_mgr.active_combats[0]
			c["monster_turns_taken"] = 5
			var hp0: int = ch.current_hp
			for r in 5:
				sim.combat_mgr.process_monster_turn(c)
			if pass_i == 0:
				taken_plain += hp0 - ch.current_hp
			else:
				taken_team += hp0 - ch.current_hp
			sim.combat_mgr.end_combat(0, false, false)
	ck(taken_team < taken_plain * 0.85, "the same player takes less damage once the team is fielded (%d vs %d over 60 paired fights)" % [taken_team, taken_plain])
	print("")
	print(("PASS - sim_models_the_companion_team" if fails == 0 else "FAIL - sim_models_the_companion_team: %d check(s)" % fails))
	quit(1 if fails > 0 else 0)
