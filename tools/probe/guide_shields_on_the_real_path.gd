extends SceneTree
## Does the guide shield the player in the fight the PLAYER actually has?
##
## ⛑ This probe exists because the previous one passed while the feature did nothing.
##
## `guide_aggro.gd` calls `_guide_shield_targets` directly and asserts it remaps targets. It does.
## But that function was only ever reached from `_select_monster_targets`, which belongs to the
## SEQUENTIAL party resolver - and the tutorial runs the SIMULTANEOUS one, which lands one action
## on every alive member and never asked. So the helper worked, its test passed, and the Warden
## had never taken a single hit for anybody.
##
## Owner 2026-09-14, twice: *"I did a test fight and died to the skeleton, the warden didn't
## prevent that"* and *"I also just tried to fight a skeleton outside the post and died to it
## again. The warden still isn't doing his job."*
##
## So this one drives `_party_process_monster_phase` - the function the server really calls - and
## asks what the PLAYER's hit points did.
const CM = preload("res://shared/combat_manager.gd")
const Character = preload("res://shared/character.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

const PLAYER := 1
const GUIDE := -9001


func _mk(cm, player_hp: int, monster_str: int) -> Dictionary:
	var pl = Character.new()
	pl.initialize("Newbie", "Fighter", "Human")
	pl.level = 1
	pl.calculate_derived_stats()
	pl.current_hp = player_hp
	var gd = Character.new()
	gd.initialize("Warden Hollis", "Fighter", "Human")
	gd.level = 3
	gd.strength = 15
	gd.constitution = 17
	gd.calculate_derived_stats()
	gd.current_hp = gd.get_total_max_hp()
	var combat := {
		"monster": {"name": "Skeleton", "strength": monster_str, "current_hp": 400,
			"max_hp": 400, "abilities": [], "level": 1},
		"members": [PLAYER, GUIDE],
		"npc_members": [GUIDE],
		"characters": {PLAYER: pl, GUIDE: gd},
		"member_states": {
			PLAYER: {"dead": false, "fled": false, "submitted_this_round": false},
			GUIDE: {"dead": false, "fled": false, "submitted_this_round": false},
		},
		"round": 1, "enrage_stacks": 0, "current_turn_index": 0,
	}
	cm.active_party_combats[PLAYER] = combat
	return combat


func _init() -> void:
	var cm = CM.new()
	get_root().add_child(cm)

	print("===== THE PATH THE SERVER ACTUALLY CALLS =====")
	var src := FileAccess.get_file_as_string("res://shared/combat_manager.gd")
	var i_p := src.find("func _party_process_monster_phase")
	var i_e := src.find("\nfunc ", i_p + 10)
	var body := src.substr(i_p, (i_e - i_p) if i_e > i_p else 6000)
	ck(body.contains("_guide_shield_targets("),
		"the SIMULTANEOUS phase consults the guide shield (it never used to)")
	ck(src.find("_guide_shield_targets(") < src.rfind("_guide_shield_targets("),
		"  and so does the sequential one - both paths, not one")

	print("")
	print("===== A PLAYER WHO WOULD DIE DOES NOT =====")
	# Hit points inside the window that killed the owner twice: survivable once, not twice, and
	# the monster gets one action per member.
	var worst := 58
	var hp := 80
	var combat := _mk(cm, hp, worst)
	print("  player on %d hp, %d-damage hits, 2 members = 2 actions this round" % [hp, worst])
	var pl = combat["characters"][PLAYER]
	var gd = combat["characters"][GUIDE]
	var gd_before: int = gd.current_hp
	cm._party_process_monster_phase(combat)
	print("  after one round: player %d hp, Warden %d -> %d" % [pl.current_hp, gd_before, gd.current_hp])
	ck(pl.current_hp > 0, "the player is ALIVE after the round")
	ck(gd.current_hp < gd_before, "and the Warden took damage - he is the one absorbing it")

	print("")
	print("===== AND HE KEEPS DOING IT UNTIL THE FIGHT ENDS =====")
	# One round proves the wiring; the owner died over several. Run until someone drops.
	var rounds := 0
	while rounds < 25 and pl.current_hp > 0:
		rounds += 1
		combat["round"] = rounds
		cm._party_process_monster_phase(combat)
	print("  survived %d rounds (guide on %d hp)" % [rounds, gd.current_hp])
	ck(pl.current_hp > 0, "the player is still standing after %d rounds" % rounds)
	ck(gd.current_hp >= 1, "and the guide never fell (held at 1 by design)")

	print("")
	print("----- the control: WITHOUT a guide, the same player dies -----")
	# Otherwise this proves only that the monster is weak.
	var solo := _mk(cm, hp, worst)
	solo["npc_members"] = []
	solo["members"] = [PLAYER]
	solo["characters"].erase(GUIDE)
	solo["member_states"].erase(GUIDE)
	var spl = solo["characters"][PLAYER]
	var srounds := 0
	while srounds < 25 and spl.current_hp > 0:
		srounds += 1
		solo["round"] = srounds
		cm._party_process_monster_phase(solo)
	print("  alone, the same character lasted %d round(s) and ended on %d hp" % [srounds, spl.current_hp])
	ck(spl.current_hp <= 0 or srounds < rounds,
		"an unguided character really does fall (so the guide is what saved the other one)")

	print("")
	print("----- NOT COVERED HERE -----")
	print("  Whether the fight still FEELS dangerous with him there. He leaves you every hit you")
	print("  can certainly survive, so you should still finish bloodied - but that is a playtest.")

	print("")
	if fails == 0:
		print("PASS - the guide shields on the path the player actually fights on")
	else:
		print("FAIL - %d check(s) failed" % fails)
	quit(1 if fails > 0 else 0)
