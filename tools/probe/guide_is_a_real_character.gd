extends SceneTree
## Is the Warden a real character, or a blank standing in a party slot?
##
## Owner 2026-09-14: *"still no sprite for the Warden in party combat, just a ? mark."*
##
## The "?" was the party card's fallback for an empty name, and the empty name came from the
## snapshot resolving members out of the server's peer->Character map, which an NPC is not in.
## Chasing that turned up the real fault underneath: he was built with class "Warrior", and there
## is no such class - Warrior is the PATH, Fighter is the class. So he matched no entry in the
## battler pools and fell through to the empty class passive, so he fought with no class identity
## and no face. His hit points were fine - those come from the path and the race - which is why
## nothing looked obviously broken. Found by CALLING pick_expanded and getting "" back.
const Character = preload("res://shared/character.gd")
const BattlerPools = preload("res://shared/battler_pools.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var src := FileAccess.get_file_as_string("res://server/server.gd")

	print("===== HE IS BUILT AS A CLASS THAT EXISTS =====")
	ck(src.contains('g.initialize(GUIDE_NAME, "Fighter", "Human")'),
		"the guide is a Fighter")
	ck(not src.contains('g.initialize(GUIDE_NAME, "Warrior"'),
		"and NOT a \"Warrior\", which is a path and not a class")

	# Prove it by building one and asking the real tables, rather than reading the string.
	var g = Character.new()
	g.initialize("Warden Hollis", "Fighter", "Human")
	g.level = 5
	ck(g.get_total_max_hp() > 0, "he has hit points (%d)" % g.get_total_max_hp())
	var passive = g.get_class_passive() if g.has_method("get_class_passive") else {}
	ck(passive is Dictionary and not (passive as Dictionary).is_empty(),
		"and a class passive (%s)" % String((passive as Dictionary).get("name", "NONE")))

	# The control. Note what it does NOT say: a "Warrior" still gets hit points, because those
	# come from the path and the race rather than the class name. What it loses is the class
	# passive - it resolves to a fallback literally named "None" - and the battler sprite.
	var bad = Character.new()
	bad.initialize("Nobody", "Warrior", "Human")
	bad.level = 5
	var bad_passive = bad.get_class_passive()
	var bad_name := String((bad_passive as Dictionary).get("name", "NONE"))
	print("  control - a \"Warrior\" resolves passive '%s', hp %d" % [bad_name, bad.get_total_max_hp()])
	ck(bad_name == "None",
		"  the old class fell through to the empty passive (so this check is not vacuous)")
	ck(String((passive as Dictionary).get("name", "")) != "None",
		"  and a Fighter does not")

	print("")
	print("===== HE HAS A FACE, AND IT IS THE SAME FACE ON THE MAP =====")
	ck(src.contains('g.battler_id = "m1_1"'), "his battler is pinned rather than rolled")
	ck("m1_1" in BattlerPools.all_ids(), "and m1_1 is a real id the pool serves")
	var bake := FileAccess.get_file_as_string("res://tools/bake_overworld_tiles.py")
	ck(bake.contains("overworld_pad32/m1_1/"),
		"and it is the sprite his OVERWORLD tile is cut from - one man, not two")

	# The rolled version returned "" for the class he was built with. Prove that too.
	var r := RandomNumberGenerator.new()
	r.seed = 1
	var rolled := BattlerPools.pick_expanded("Warrior", r)
	print("  control - pick_expanded(\"Warrior\") returns '%s'" % rolled)
	ck(rolled == "", "  a bad class really does yield no sprite, which is what the '?' was")

	print("")
	print("===== AND THE SNAPSHOT CAN SEE HIM AT ALL =====")
	ck(src.contains('ch = c.get("characters", {}).get(pid, null)'),
		"the party snapshot falls back to the COMBAT's own character map for NPC members")

	print("")
	print("----- NOT COVERED HERE -----")
	print("  Whether his card LOOKS right beside a player's. That is a look, and looks are a")
	print("  playtest.")

	print("")
	if fails == 0:
		print("PASS - the Warden is a real Fighter with a real face")
	else:
		print("FAIL - %d check(s) failed" % fails)
	quit(1 if fails > 0 else 0)
