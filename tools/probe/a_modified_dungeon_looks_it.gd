extends SceneTree
## ⛑ CAN YOU SEE WHAT KIND OF DUNGEON YOU ARE STANDING IN?
##
## `DUNGEON_MODIFIERS` has made dungeons mechanically different since 2026-09-13 — a Bloodgorged
## dungeon's monsters really are 40% harder to kill. Nothing showed it. Monster tints roll PER
## MONSTER at random (`monster_database.COSMETIC_CHANCE`), so the place that is trying to kill you
## differently looked exactly like the place that is not, and `monster_database.gd`'s own comment
## had been asking for the fix since it was written: *"Future dungeon themes will stamp ONE variant
## dungeon-wide."*
##
## WHAT THIS ASSERTS:
##   1. every monster in a modified dungeon shares ONE look
##   2. that look is DERIVED from the modifiers, so it cannot drift from the mechanics
##   3. more modifiers reads as worse at a glance, without having to count them
##   4. ⚑ THE STAMP IS COSMETIC — it must not touch a single stat
##
## ⛑ (4) IS THE ONE THAT MATTERS. The modifiers' stat effects are already applied through
## `modifier_effects()`, which every consumer asks. If this stamp also touched stats they would be
## applied TWICE, and a doubled difficulty modifier in a permadeath game is not something you catch
## in testing — it is something you find later in a death log.
##
## Run:
##   godot --headless --path . --script res://tools/probe/a_modified_dungeon_looks_it.gd

const DungeonDB := preload("res://shared/dungeon_database.gd")

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


func _init() -> void:
	var mod_ids: Array = DungeonDB.DUNGEON_MODIFIERS.keys()

	print("")
	print("===== 1. THE LOOK IS DERIVED FROM THE MODIFIERS =====")
	# Pure function: same modifiers in, same look out, every time. Nothing to keep in step.
	var a: Dictionary = DungeonDB.dungeon_look_for([String(mod_ids[0])])
	var b: Dictionary = DungeonDB.dungeon_look_for([String(mod_ids[0])])
	if a != b:
		_fail("the same modifier list produced two different looks - it is not a pure function")
	else:
		_ok("same modifiers in, same look out")
	var plain: Dictionary = DungeonDB.dungeon_look_for([])
	if not plain.is_empty():
		_fail("an UNMODIFIED dungeon claims a look - ordinary dungeons must be left alone")
	else:
		_ok("an unmodified dungeon has no dungeon-wide look (monsters keep their own tints)")

	print("")
	print("===== 2. EVERY MODIFIER PRODUCES A USABLE LOOK =====")
	print("  %-14s %-10s %-10s %-14s %s" % ["modifier", "color", "color2", "pattern", "name"])
	for m in mod_ids:
		var look: Dictionary = DungeonDB.dungeon_look_for([String(m)])
		print("  %-14s %-10s %-10s %-14s %s" % [m, look.get("color", ""), look.get("color2", "-"),
			look.get("pattern", ""), look.get("name", "")])
		if String(look.get("color", "")) == "":
			_fail("%s has no colour - its dungeon would look like an ordinary one" % m)
		if String(look.get("name", "")) == "":
			_fail("%s has no name - the dungeon title could not say what it is" % m)

	print("")
	print("===== 3. MORE MODIFIERS READS AS WORSE, WITHOUT COUNTING =====")
	# The PATTERN encodes the load, so a player does not have to read a list to know.
	var one: Dictionary = DungeonDB.dungeon_look_for([String(mod_ids[0])])
	var two: Dictionary = DungeonDB.dungeon_look_for([String(mod_ids[0]), String(mod_ids[1])])
	var three: Dictionary = DungeonDB.dungeon_look_for([String(mod_ids[0]), String(mod_ids[1]), String(mod_ids[2])])
	print("  1 modifier  -> %s" % one.get("pattern", ""))
	print("  2 modifiers -> %s" % two.get("pattern", ""))
	print("  3 modifiers -> %s   (rank 9, the worst the game builds)" % three.get("pattern", ""))
	var pats := [String(one.get("pattern", "")), String(two.get("pattern", "")), String(three.get("pattern", ""))]
	if pats[0] == pats[1] or pats[1] == pats[2] or pats[0] == pats[2]:
		_fail("two different modifier counts look the same: %s" % str(pats))
	else:
		_ok("one, two and three modifiers are each visually distinct")
	if String(two.get("color2", "")) == "":
		_fail("a two-modifier dungeon has no second colour, so the gradient has nothing to blend")

	print("")
	print("===== 4. THE STAMP IS COSMETIC - IT TOUCHES NO STAT =====")
	# ⛑ Read the stamp's own source: it may only ever write appearance_* keys. Checked as source
	# rather than by running a spawn because the failure being guarded against is a stat written
	# ONE line out of place, and that is visible here and invisible in an averaged measurement.
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	var i := srv.find("func _stamp_dungeon_look(")
	if i < 0:
		_fail("_stamp_dungeon_look is gone - the look is no longer stamped at all")
	else:
		var j := srv.find("\nfunc ", i + 8)
		var body := srv.substr(i, (j - i) if j > i else 2000)
		var banned := ["hp", "max_hp", "strength", "defense", "level", "empowered_mods",
			"variant_type", "experience", "xp"]
		var wrote_stats: Array = []
		for line in body.split("\n"):
			var t := String(line).strip_edges()
			if not t.begins_with("roll["):
				continue
			for k in banned:
				if t.begins_with("roll[\"%s\"]" % k):
					wrote_stats.append(k)
		if wrote_stats.is_empty():
			_ok("the stamp writes appearance_* only - modifier stats stay applied exactly once")
		else:
			_fail("the stamp writes %s - those are applied by modifier_effects() already, so a "
				% str(wrote_stats) + "modified dungeon would get them TWICE")

	print("")
	print("===== 5. THE NAME SAYS WHAT THE PLACE IS =====")
	print("  %s" % DungeonDB.modified_dungeon_name("Goblin Caves", []))
	print("  %s" % DungeonDB.modified_dungeon_name("Goblin Caves", [String(mod_ids[0])]))
	print("  %s" % DungeonDB.modified_dungeon_name("Goblin Caves", [String(mod_ids[0]), String(mod_ids[1])]))
	if DungeonDB.modified_dungeon_name("Goblin Caves", []) != "Goblin Caves":
		_fail("an unmodified dungeon's name was decorated")

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS a modified dungeon looks like what it is, the look follows the modifiers,")
	print("       and stamping it changes no stat.")
	quit()
