extends SceneTree
## Does everything inside a dungeon read the grade the PLAYER is in, or the one its type says?
##
## ⛑ Reported live 2026-09-14. A player entered a Phoenix's Nest and could not use a Scroll of
## Escape. Owner: *"what's the alternative, I wasn't aware the scrolls of escape don't work in
## high level dungeons, how are they meant to get out?"*
##
## They were never in a high level dungeon. The monsters were LEVEL 29, and the bands settle it:
## F5 covers 26-29, C5 covers 278-322. The instance was F. But `phoenix_nest`'s TYPE says tier 6,
## and the scroll gate read the type - so it refused a tier-4 scroll on the grounds that Phoenix's
## Nests are tier 6.
##
## Since 2026-09-11 a dungeon's grade belongs to the INSTANCE; the land decides it. Every read of
## the type's tier from inside a dungeon is therefore wrong for any instance the land regraded,
## and there were five of them.
const DDB = preload("res://shared/dungeon_database.gd")
const PowerRank = preload("res://shared/power_rank.gd")
const DropTables = preload("res://shared/drop_tables.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	print("===== THE EVIDENCE THAT NAMED THE BUG =====")
	var f5: Dictionary = DDB.get_sub_tier_level_range(3, 5)
	var c5: Dictionary = DDB.get_sub_tier_level_range(6, 5)
	print("  F5 covers levels %d-%d;  C5 covers %d-%d;  the phoenix was level 29"
		% [int(f5.get("min_level", 0)), int(f5.get("max_level", 0)),
			int(c5.get("min_level", 0)), int(c5.get("max_level", 0))])
	ck(29 >= int(f5.get("min_level", 0)) and 29 <= int(f5.get("max_level", 0)),
		"level 29 sits inside F5 - so the instance really was F")
	ck(29 < int(c5.get("min_level", 0)),
		"and nowhere near C5 - the grade it was refused against")
	ck(PowerRank.letter(3) == "F" and PowerRank.letter(6) == "C",
		"F is tier 3 and C is tier 6 (three grades apart)")
	ck(int(DDB.get_dungeon("phoenix_nest").get("tier", 0)) == 6,
		"and phoenix_nest's TYPE says 6, which is where the C came from")

	print("")
	print("===== NOTHING INSIDE A DUNGEON READS THE TYPE ANY MORE =====")
	var src := FileAccess.get_file_as_string("res://server/server.gd")
	ck(src.contains("func _current_dungeon_tier(character) -> int:"),
		"there is one resolver for 'the grade this player is standing in'")
	ck(src.contains("return _instance_tier(inst)"),
		"  and it answers from the INSTANCE")
	var n := src.count("_current_dungeon_tier(character)")
	print("  %d call sites use it" % n)
	ck(n >= 5, "every site that used to read the type now asks it")

	# The property that matters: no read of the TYPE's tier keyed off the character's current
	# dungeon survives. This is the check that would catch the sixth one somebody adds.
	var bad := 0
	var lines := src.split("\n")
	for i in range(lines.size()):
		var ln: String = lines[i]
		if not ln.contains("get_dungeon(character.current_dungeon_type)"):
			continue
		# does this line, or the next, pull a tier out of it?
		var window: String = ln + (lines[i + 1] if i + 1 < lines.size() else "")
		if window.contains('"tier"') or window.contains(".tier"):
			bad += 1
			print("    still reading the TYPE's tier at line %d" % (i + 1))
	ck(bad == 0, "no site reads the type's tier for the dungeon a player is inside")

	print("")
	print("===== AND THE REFUSAL TELLS THEM THE WAY OUT =====")
	# The old message said only what did not work. Every dungeon places a scroll matching its own
	# grade on the first floor; a player who walked past it had no way to know it existed.
	# There is no refusal any more - the gate is gone entirely, so the thing to assert is its
	# ABSENCE. These two checks used to look for the wording of a better refusal message, which
	# is a weaker property: a well-worded "no" is still a player who cannot leave.
	ck(not src.contains("This scroll only reaches tier"),
		"there is no tier refusal left to word well")
	ck(not src.contains("dungeon_tier > tier_max"), "  the gate itself is gone")
	ck(src.contains("one is on the FIRST FLOOR of every dungeon"),
		"and the no-free-exit notice names where a scroll is")

	print("")
	print("===== AND THE NAME ON SCREEN CARRIES THE INSTANCE'S GRADE =====")
	# ⛑ THIS is the F-versus-C. `get_dungeon_display_name(type, tier, rank)` was being handed the
	# TYPE's tier beside the INSTANCE's rank, so a phoenix_nest (type 6 = C) standing as an
	# F-grade instance rendered "Phoenix's Nest [C5]" - while the overworld, resolving through
	# _dungeon_data_for, correctly said F. Both numbers were real; they came from different
	# places. Owner: *"showed as F4 or near that on the overworld and instead it put them in a
	# C5 phoenix dungeon."*
	var bad_names := 0
	var nlines := src.split("
")
	for i in range(nlines.size()):
		var ln: String = nlines[i]
		if not ln.contains("get_dungeon_display_name("):
			continue
		# the tier argument must not be a raw type read
		if ln.contains("dungeon_data.tier"):
			# only legitimate when dungeon_data came from _dungeon_data_for
			var from_instance := false
			for k in range(maxi(0, i - 12), i):
				if nlines[k].contains("dungeon_data = _dungeon_data_for("):
					from_instance = true
			if not from_instance:
				bad_names += 1
				print("    line %d passes a TYPE tier into the display name" % (i + 1))
	ck(bad_names == 0, "every display name is built from the grade the instance actually has")

	print("")
	print("===== AND THE EGG IS GRADED BY THE DUNGEON, NOT THE SPECIES =====")
	# Owner 2026-09-14: *"the egg you get from the boss of a dungeon [should be] at a minimum the
	# same Rank"* and *"they got a C rank egg out of it even though the monsters were only lvl
	# 29."* Both point the same way: an F-grade Phoenix's Nest has an F-grade boss, and the egg
	# it leaves should be an F-grade phoenix egg. Reading the SPECIES' tier handed out three
	# grades of companion for an afternoon's work.
	var dt = DropTables.new()
	get_root().add_child(dt)
	await process_frame
	var by_species: Dictionary = dt.get_egg_for_monster("Phoenix", {}, 5, 0)
	var by_dungeon: Dictionary = dt.get_egg_for_monster("Phoenix", {}, 5, 3)
	var t_species := int(by_species.get("tier", 0))
	var t_dungeon := int(by_dungeon.get("tier", 0))
	print("  a Phoenix egg: by species tier %d (%s), from an F-grade dungeon tier %d (%s)"
		% [t_species, PowerRank.letter(maxi(1, t_species)), t_dungeon, PowerRank.letter(maxi(1, t_dungeon))])
	ck(t_species == 6, "the species really is C-grade (or this proves nothing)")
	ck(t_dungeon == 3, "and an F-grade dungeon leaves an F-grade egg")
	# And the override is OPT-IN: everything with no dungeon behind it keeps the species tier.
	ck(int(dt.get_egg_for_monster("Phoenix", {}, 5).get("tier", 0)) == 6,
		"  while a wild or market egg, with no dungeon to speak for it, is unchanged")
	ck(src.contains("var tier: int = _instance_tier(active_dungeons.get(instance_id, {}))"),
		"and the floor-loot spawner grades its whole contents from the instance too")

	print("")
	print("----- what this does NOT claim -----")

	print("  That the OVERWORLD was wrong. It was not - it resolves through _dungeon_data_for")
	print("  and showed F correctly, and the live log confirms rank inherited (5 -> 5, no")
	print("  mismatch flag). The C came from the display NAME and from seven behaviour sites")
	print("  reading the type's tier. The entry log prints tier and its letter now as well.")

	print("")
	if fails == 0:
		print("PASS - a dungeon's grade is the one the player is standing in")
	else:
		print("FAIL - %d check(s) failed" % fails)
	quit(1 if fails > 0 else 0)
