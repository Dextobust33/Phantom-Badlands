extends SceneTree
## The onboarding guide holds aggro — but not blindly.
##
## Owner 2026-09-13: *"Guide should have all aggro to ensure player survives unless its a hit that
## the player can for sure survive."*
##
## That is two requirements pulling against each other, and both matter. The tutorial must not
## kill the player. It must ALSO not wrap them in cotton wool, or the first fight teaches nothing
## and the real world comes as a surprise at level 4. So a hit the player can certainly live
## through is left alone, and only a hit that might not be is taken by the guide.
##
## The estimate is deliberately pessimistic: being wrong is only allowed in the direction where
## the guide steps in unnecessarily, never in the direction where the player dies.
const CombatMgr = preload("res://shared/combat_manager.gd")
const CharacterScript = preload("res://shared/character.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _hero(nm: String, hp: int) -> Character:
	var c = CharacterScript.new()
	c.initialize(nm, "warrior", "human")
	c.level = 1
	c.current_hp = hp
	return c


func _combat(cm, player_hp: int, monster_str: int, with_guide: bool) -> Dictionary:
	var player := _hero("Newbie", player_hp)
	var guide := _hero("Guide", 500)
	var chars := {1: player}
	var members := [1]
	var npcs: Array = []
	if with_guide:
		chars[-1] = guide
		members.append(-1)
		npcs = [-1]
	return {
		"monster": {"name": "Goblin", "strength": monster_str, "abilities": []},
		"characters": chars, "members": members, "npc_members": npcs,
		"member_states": {}, "enrage_stacks": 0, "target_weights": {},
	}


func _init() -> void:
	var cm = CombatMgr.new()

	print("===== THE WORST-CASE ESTIMATE ERRS UPWARD, ON PURPOSE =====")
	var c := _combat(cm, 100, 20, true)
	var worst: int = cm._worst_case_hit(c)
	print("  a strength-20 monster: worst single hit estimated at %d" % worst)
	ck(worst >= 23, "at least strength x1.15 variance ceiling (%d)" % worst)
	c["enrage_stacks"] = 5
	var worst_enraged: int = cm._worst_case_hit(c)
	print("  ...and enraged five stacks: %d" % worst_enraged)
	ck(worst_enraged > worst, "enrage raises the estimate - a guard blind to it would be stale")

	print("")
	print("===== A HIT THE PLAYER CAN SURVIVE IS LEFT ALONE =====")
	# This is the half that is easy to get wrong by being too protective. If the guide eats
	# everything, the tutorial teaches that combat is free.
	var healthy := _combat(cm, 200, 20, true)      # worst ~23, margin 1.35 -> needs > 31
	var out_healthy: Array = cm._guide_shield_targets(healthy, [1, 1, 1], [1, -1])
	print("  player at 200 HP vs worst hit ~%d: targets %s" % [cm._worst_case_hit(healthy), str(out_healthy)])
	ck(out_healthy == [1, 1, 1],
		"every hit still lands on the player - they are in no danger and should feel the fight")

	print("")
	print("===== A HIT THAT MIGHT KILL THEM IS TAKEN BY THE GUIDE =====")
	var hurt := _combat(cm, 25, 20, true)          # worst ~23, 25 is NOT > 31
	var out_hurt: Array = cm._guide_shield_targets(hurt, [1, 1], [1, -1])
	print("  player at 25 HP vs worst hit ~%d: targets %s" % [cm._worst_case_hit(hurt), str(out_hurt)])
	ck(out_hurt == [-1, -1], "the guide takes both")

	print("")
	print("----- and the boundary is guarded by a MARGIN, not by exactness -----")
	# Exactly survivable is not good enough: the estimate ignores defence, dodge and any ability
	# that could change the number between now and the swing.
	var edge := _combat(cm, 24, 20, true)          # survives the raw worst by 1
	var out_edge: Array = cm._guide_shield_targets(edge, [1], [1, -1])
	ck(out_edge == [-1],
		"a player who survives the worst hit by ONE point is still shielded (margin %.2f)"
			% CombatMgr.GUIDE_SAFE_MARGIN)

	print("")
	print("===== NO GUIDE, NO CHANGE - EVERY OTHER FIGHT IN THE GAME =====")
	# The dangerous failure mode for this feature is leaking into ordinary combat.
	var solo := _combat(cm, 5, 500, false)         # nearly dead against a huge monster
	var out_solo: Array = cm._guide_shield_targets(solo, [1, 1, 1], [1])
	ck(out_solo == [1, 1, 1],
		"a player with no guide is not protected, however close to death they are")

	print("")
	print("----- a fallen guide cannot shield -----")
	var down := _combat(cm, 10, 200, true)
	var out_down: Array = cm._guide_shield_targets(down, [1], [1])   # guide not in active_members
	ck(out_down == [1], "with the guide out of the fight, hits land where they were aimed")

	print("")
	print("===== AND THE GUIDE DOES NOT INFLATE THE MONSTER =====")
	# A boss with doubled HP that the guide is tanking is a longer walkover, not a better lesson.
	var mon_solo := {"name": "Boss", "max_hp": 1000, "strength": 20, "abilities": []}
	var mon_guided := {"name": "Boss", "max_hp": 1000, "strength": 20, "abilities": []}
	var p1 := _hero("Solo", 100)
	var p2 := _hero("Escorted", 100)
	var g := _hero("Guide", 500)
	cm.start_party_combat_simul([1, 2], {1: p1, 2: p2}, mon_solo)
	cm.active_party_combats.clear()
	cm.party_combat_membership.clear()
	cm.start_party_combat_simul([3, -1], {3: p2, -1: g}, mon_guided, [-1])
	print("  two players: boss at %d HP.  one player + guide: boss at %d HP."
		% [int(mon_solo["max_hp"]), int(mon_guided["max_hp"])])
	ck(int(mon_guided["max_hp"]) == 1000, "the guide adds no HP")
	ck(int(mon_solo["max_hp"]) == 2000, "  ...while a second PLAYER still does")

	print("")
	if fails == 0:
		print("PASS - the guide shields what would kill you and nothing else")
	else:
		print("FAIL - %d check(s) failed" % fails)
	quit(1 if fails > 0 else 0)
