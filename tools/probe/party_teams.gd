extends SceneTree
## Item 14 party play: every member's companion TEAM fights in a party. Driven through the functions a party
## round really calls (_party_apply_member_action, _party_process_monster_phase).
## Run:  godot --headless --path . --script res://tools/probe/party_teams.gd
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _text(entries: Array) -> String:
	var out := PackedStringArray()
	for e in entries:
		if e is Dictionary:
			out.append(String(e.get("self", "")) + " " + String(e.get("other", "")))
	return " | ".join(out)

func _init() -> void:
	var sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	get_root().add_child(sim)
	await process_frame
	var cm = sim.combat_mgr
	sim._companion_mode = "lag"
	sim._team_flag = true
	cm.active_party_combats.clear()
	cm.party_combat_membership.clear()
	var a = sim.make_char(100, "average", "Fighter", "Human")
	var b = sim.make_char(100, "average", "Sorcerer", "Human")
	a.name = "Alpha"
	b.name = "Bravo"
	var mon = sim.make_monster(100, "normal", 50.0)
	mon["abilities"] = []
	mon["empowered_mods"] = []
	var r = cm.start_party_combat_simul([1, 2], {1: a, 2: b}, mon)
	var combat: Dictionary = r["combat"]
	ck(a.get_companion_party_ids().size() == 4 and b.get_companion_party_ids().size() == 4, "both members own a full team (%d / %d)" % [a.get_companion_party_ids().size(), b.get_companion_party_ids().size()])

	print("--- the team acts when its owner acts ---")
	var RolesScript = load("res://shared/companion_roles.gd")
	ck(RolesScript.party_team_cap(1) == 4 and RolesScript.party_team_cap(2) == 1 and RolesScript.party_team_cap(3) == 0 and RolesScript.party_team_cap(5) == 0, "slot split: alone 4, a pair 1 each, three or more none")
	var lines_a := ""
	for i in 3:
		a.current_hp = a.get_total_max_hp()
		combat.member_states[1]["queued_action"] = {"kind": "attack"}
		lines_a += _text(cm._party_apply_member_action(combat, 1)) + " | "
	var names_a: Array = []
	for c in a.get_companion_party():
		names_a.append(str(c.name))
	var acted := 0
	for n in names_a:
		if lines_a.find(n) >= 0:
			acted += 1
	ck(acted == 1, "in a pair each player's team is trimmed to ONE of the four slots, and that one acts (%d of 4 appear)" % acted)

	print("--- the monster can hit a member's teammates ---")
	var hit_team := {1: 0, 2: 0}
	for rnd in 12:
		combat["round"] = int(combat.get("round", 1)) + 1
		for pid in [1, 2]:
			var ch = combat.characters[pid]
			ch.current_hp = ch.get_total_max_hp()
			for cc in ch.get_companion_party_ids():
				ch.set_party_companion_combat_hp(String(cc), ch.get_party_companion_max_hp(String(cc)))
		var t := _text(cm._party_process_monster_phase(combat))
		for pid in [1, 2]:
			for c in combat.characters[pid].get_companion_party():
				if t.find("your " + str(c.name)) >= 0 or t.find(str(c.name)) >= 0:
					hit_team[pid] += 1
	print("  rounds in which each member's column companions were hit: ", hit_team)
	ck(hit_team[1] > 0 and hit_team[2] > 0, "both members' column companions soak hits in a party")
	print("--- what the clients are told, and that nothing sticks ---")
	var sizes: Array = [cm.party_team_view(combat, a).size(), cm.party_team_view(combat, b).size()]
	ck(sizes == [1, 1], "each member's snapshot carries a team of ONE (%s)" % str(sizes))
	cm._party_member_view(combat, 1)   # the read-only view (status strip, snapshot) must not trim anything
	ck(a.team_cap_override == -1, "building the read-only view leaves no cap behind")
	ck(a.team_cap_override == -1 and b.team_cap_override == -1, "the cap is lifted again after the snapshot is built")
	ck(a.companion_party.size() == 4 and a.get_companion_party_ids().size() == 4, "the stored team is untouched - leaving the party gives all four back")

	print("--- a companion's cooldown survives into the next action ---")
	var st: Dictionary = combat.member_states[1]
	var carry: Dictionary = st.get("view_carry", {})
	ck(carry.has("companion_state"), "the per-companion state is carried between a member's actions")
	print("")
	print(("PASS - party_teams" if fails == 0 else "FAIL - party_teams: %d check(s)" % fails))
	quit(1 if fails > 0 else 0)
