extends SceneTree
## Sanctuary points are earned by PLAYING (owner 2026-10-20), without being paid twice at death.
const SP = preload("res://shared/sanctuary_points.gd")
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _init() -> void:
	var even: int = SP.win_points(30, 30)
	ck(SP.win_points(5, 30) < even, "a trivial monster pays less than an even one (%d < %d)" % [SP.win_points(5, 30), even])
	ck(SP.win_points(40, 30) > even, "a monster above you pays more")
	ck(SP.win_points(30, 30, true) >= even * 3, "a boss pays about four times")
	ck(SP.win_points(1, 500) >= 1, "never zero")
	# pacing: 90 even wins + 6 quests + 1 tier-3 three-floor dungeon an hour, against the 3,250/hour target
	var hour: int = 90 * even + 6 * SP.POINTS_PER_QUEST + SP.dungeon_points(3, 3)
	ck(hour >= 2000 and hour <= 5000, "an hour of plausible play earns %d points (target ~3,250)" % hour)
	# no double payment: the death award no longer grows with kills or quests
	var P = load("res://server/persistence_manager.gd")
	var CH = load("res://shared/character.gd")
	var pm = P.new()
	var a = CH.new()
	a.initialize("p_a", "Fighter", "Human")
	var b = CH.new()
	b.initialize("p_b", "Fighter", "Human")
	b.monsters_killed = 5000
	b.completed_quests = ["q1", "q2", "q3"]
	ck(pm.calculate_baddie_points(a) == pm.calculate_baddie_points(b), "death award ignores kills and quests (already paid as played)")
	var src := FileAccess.get_file_as_string("res://server/server.gd")
	ck(src.find("_award_play_points(peer_id, SanctuaryPointsScript.win_points(") >= 0, "a won fight awards points")
	ck(src.find('SanctuaryPointsScript.POINTS_PER_QUEST, "quest")') >= 0, "a quest turn-in awards points")
	ck(src.find('"dungeon")') >= 0, "a dungeon clear awards points")
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
