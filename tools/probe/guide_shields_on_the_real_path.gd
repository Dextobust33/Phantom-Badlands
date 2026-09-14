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
	while rounds < 10 and pl.current_hp > 0:
		rounds += 1
		combat["round"] = rounds
		cm._party_process_monster_phase(combat)
	print("  survived %d rounds (guide on %d hp)" % [rounds, gd.current_hp])
	# NOTE: the guide HERE is hand-built by `_mk`, not by the server's _make_guide_character, so
	# his HP POOL is not the real one and this file must not judge it. How healthy his bar looks
	# is checked in tutorial_walkthrough.gd, where he is constructed the way the game constructs
	# him. Duplicating that construction here once already produced a false failure.
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
	print("===== A MONSTER GAINS NOTHING FROM HITTING HIM =====")
	# Owner 2026-09-14, round nine of an escorted fight: *"this Wight fight is pretty crazy, it
	# gets a ton of health back so I don't know that we can even kill it."* Life steal heals 50%
	# of damage dealt, and the guide is BUILT to be hit - so the escort had turned him into a
	# battery, and every point of HP added to him made the fight last longer.
	# The player is put on LOW hp on purpose, so every hit this round is shielded onto the guide
	# and any healing at all must have come off him. At a comfortable hp the player takes some of
	# the hits themselves and draining off a PLAYER is legitimate - the first cut of this check
	# measured that and reported a false failure.
	var drain := _mk(cm, 25, 60)
	drain["monster"]["abilities"] = [cm.ABILITY_LIFE_STEAL]
	drain["monster"]["current_hp"] = 200
	drain["monster"]["max_hp"] = 400
	var before_hp: int = int(drain["monster"]["current_hp"])
	for r in range(4):
		drain["round"] = r + 1
		cm._party_process_monster_phase(drain)
	var after_hp: int = int(drain["monster"]["current_hp"])
	print("  four rounds against a life-stealer, every hit shielded: monster %d -> %d hp"
		% [before_hp, after_hp])
	ck(after_hp <= before_hp,
		"it heals NOTHING off the guide - the fight can still be won")

	print("")
	print("===== AND A GUIDE LEFT ALONE ENDS THE FIGHT =====")
	# *"I fled from that fight since it is unwinnable and now I'm stuck out of this fight and can
	# only watch so I'm effectively soft locked."* He cannot die - held at 1 HP - so a fight with
	# only him left had no way to finish.
	var fled := _mk(cm, 100, 20)
	fled["member_states"][PLAYER]["fled"] = true
	ck(cm._only_npcs_left(fled, cm._party_alive_members(fled)),
		"with the player gone, only the guide is left and that counts as nobody")
	var both := _mk(cm, 100, 20)
	ck(not cm._only_npcs_left(both, cm._party_alive_members(both)),
		"  and while the player IS in it, the fight continues (control)")
	# The rule has to answer for BOTH resolvers, which keep member state in different places.
	var csrc := FileAccess.get_file_as_string("res://shared/combat_manager.gd")
	ck(csrc.contains("_only_npcs_left(combat, _party_alive_members(combat))"),
		"  the simultaneous resolver asks it")
	ck(csrc.contains("_only_npcs_left(combat, _get_active_members(combat))"),
		"  and so does the sequential one - fixing only one is how the tutorial stayed locked")

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
