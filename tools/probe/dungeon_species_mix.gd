extends SceneTree
## A dungeon holds more than one kind of monster, and its floor eggs follow what was really there.
##
## Owner 2026-09-11: *"I would be fine with dungeons having other monsters of the same tier
## spawning within them (more rare, less likely than the main dungeon monster/boss type). The
## floor loot eggs could also be of any of the monster types that spawn in that dungeon, the boss
## should still be of the dungeon type and the guaranteed egg should be of it as well."*
##
## Until now every regular monster on every floor came from one string, `boss.monster_type`, so a
## Goblin Caves was 100% Goblins - while the Dungeon Atlas showed the player a three-species
## `monster_pool` that drove nothing at all.
##
## The two halves that must NOT move are as important as the half that does: the boss and the
## guaranteed clear egg stay the dungeon's own creature.
const MD := preload("res://shared/monster_database.gd")
const DD := preload("res://shared/dungeon_database.gd")
const PR := preload("res://shared/power_rank.gd")
const SRC := "res://server/server.gd"

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _body(src: String, fname: String) -> String:
	var i := src.find("func %s(" % fname)
	if i < 0:
		return ""
	var j := src.find("\nfunc ", i + 10)
	return src.substr(i, (j if j > 0 else src.length()) - i)


func _init() -> void:
	var md = MD.new()
	get_root().add_child(md)
	var src := FileAccess.get_file_as_string(SRC)

	print("--- every grade has neighbours to draw on ---")
	var thin := 0
	for t in range(1, 10):
		var names: PackedStringArray = md.tier_species_names(t)
		if names.size() < 2:
			thin += 1
		print("  %s: %d species" % [PR.letter(t), names.size()])
	ck(thin == 0, "no grade has so few species that a 'mix' would be one creature")
	var dup := 0
	for t in range(1, 10):
		var seen := {}
		for n in md.tier_species_names(t):
			if seen.has(n):
				dup += 1
			seen[n] = true
	ck(dup == 0, "and no species is listed twice within a grade")

	print("\n--- the mix is a MINORITY, and it MEASURABLY happens ---")
	# Measured, not read off the source. The first version of this section looked for the constant
	# and passed happily when the branch using it was replaced by `if false:` - the text was still
	# there, sitting inside a branch that could no longer be reached. That is exactly the
	# "a detector that never fires looks like one that finds nothing" trap.
	var pool: PackedStringArray = md.tier_species_names(2)
	var native := String(pool[0])
	var native_hits := 0
	var others := {}
	var N := 20000
	for i in range(N):
		var got: String = DD.pick_floor_species(native, pool)
		if got == native:
			native_hits += 1
		else:
			others[got] = true
	var got_share := float(native_hits) / float(N)
	print("  %s made up %.1f%% of the floor; %d other species appeared" % [native, got_share * 100.0, others.size()])
	ck(got_share > 0.6 and got_share < 0.9, "the dungeon's own species is most of the floor, but not all of it")
	ck(others.size() >= 2, "neighbours really do turn up (%d distinct)" % others.size())
	ck(not others.has(native), "and a neighbour is never the native species wearing another hat")
	ck(DD.pick_floor_species(native, PackedStringArray()) == native,
		"a grade with no pool falls back to the dungeon's own rather than to nothing")
	ck(DD.pick_floor_species(native, pool, 1.0) == native,
		"...and a share of 1.0 turns the mix off cleanly, for tuning")

	print("\n--- the species is decided per MONSTER, and remembered ---")
	var f := _body(src, "_dungeon_floor_species")
	ck(f != "", "_dungeon_floor_species exists")
	ck(f.find("monster_db.tier_species_names(grade_tier)") >= 0,
		"...it draws neighbours from the dungeon's GRADE, not from its type's old fixed tier")
	ck(f.find("DungeonDatabaseScript.pick_floor_species(") >= 0,
		"...through the shared chooser the probe measures above")
	ck(f.find('"spawned_species"') >= 0,
		"...and every species that spawns is recorded, because the eggs are drawn from it")
	var spawn := _body(src, "_spawn_dungeon_floor_monsters")
	ck(spawn.find("_dungeon_floor_species(instance_id, monster_type,") >= 0,
		"the floor spawner asks it for each monster")
	ck(spawn.find('"monster_type": _species,') >= 0,
		"the entity carries its OWN species, so the fight matches what the player walked into")
	ck(spawn.find('var display_char = _species[0]') >= 0,
		"and the map letter follows the monster (it used to be the dungeon's one species)")
	ck(spawn.find("generate_monster_by_name(_species, monster_level)") >= 0,
		"...as does the variant roll")

	print("\n--- the boss and the guaranteed egg do NOT move ---")
	# This is the half of the owner's instruction that is easy to break by accident.
	ck(spawn.find('boss_data.get("monster_type"') >= 0 or spawn.find("boss_data") >= 0,
		"the boss still comes from boss_data, untouched by the mix")
	var boss_section := spawn.substr(spawn.find("Spawn boss on boss floor"))
	ck(boss_section.find("_dungeon_floor_species") < 0,
		"...the boss is never routed through the species mix")
	var complete := _body(src, "_complete_dungeon")
	ck(complete.find('var boss_egg_monster = rewards.get("boss_egg", "")') >= 0,
		"the guaranteed clear egg is still the dungeon's own boss_egg")
	ck(complete.find("_floor_egg_species") < 0,
		"...and is never drawn from the mix")

	print("\n--- floor eggs follow what was actually down there ---")
	var fe := _body(src, "_floor_egg_species")
	ck(fe != "", "_floor_egg_species exists")
	ck(fe.find('"spawned_species"') >= 0, "...it reads the species that really spawned")
	ck(fe.find("return fallback") >= 0, "...and falls back to the dungeon's own when there are none")
	var roll := _body(src, "_roll_floor_item")
	ck(roll.find("_floor_egg_species(instance_id, boss_egg_monster)") >= 0,
		"the floor-egg roll asks for a species")
	ck(roll.find("if egg.is_empty() and egg_species != boss_egg_monster:") >= 0,
		"...and a species with no egg falls back rather than dropping nothing")

	print("\n[SPECIESMIX] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
