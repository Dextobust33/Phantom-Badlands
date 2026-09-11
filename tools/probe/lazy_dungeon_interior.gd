extends SceneTree
## A dungeon nobody has entered must not build its rooms.
##
## 2026-09-11, costing the owner's *"massively increase the amount of dungeons that players can
## find on the map... in a cost efficient manner"*. A world dungeon is a marker on the overworld.
## It used to build, the moment it spawned, every floor's BSP grid and a monster entity for every
## room - and then nothing read any of it, because entering a world `D` creates a PERSONAL
## instance that generates its own from scratch.
##
## This probe holds two things:
##   1. no world-dungeon creator builds an interior any more;
##   2. the price that used to be paid, measured, so the reason is on the record rather than
##      asserted. If someone re-adds an eager build, the first half fails.
const DD := preload("res://shared/dungeon_database.gd")
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
	var src := FileAccess.get_file_as_string(SRC)

	print("--- the three world-dungeon creators build no rooms ---")
	for fname in ["_create_world_dungeon", "_create_world_dungeon_near", "_ensure_starter_dungeon_exists"]:
		var b := _body(src, fname)
		ck(b != "", "%s exists" % fname)
		ck(b.find("generate_floor_grid") < 0, "%s does not generate a floor grid" % fname)
		ck(b.find("_spawn_all_dungeon_monsters") < 0, "%s does not spawn monsters" % fname)

	print("\n--- a player's own instance still does, because it is about to be walked in ---")
	for fname in ["_create_player_dungeon_instance", "_create_dungeon_instance"]:
		var b := _body(src, fname)
		ck(b.find("generate_floor_grid") >= 0, "%s still builds its interior up front" % fname)

	print("\n--- and there is a way back if anything ever asks ---")
	var acc := _body(src, "_ensure_dungeon_interior")
	ck(acc != "", "_ensure_dungeon_interior exists")
	ck(acc.find("if dungeon_floors.has(instance_id):") >= 0 and acc.find("return true") >= 0,
		"...it costs one dictionary lookup when the interior is already there")
	ck(acc.find("generate_floor_grid") >= 0 and acc.find("_spawn_all_dungeon_monsters") >= 0,
		"...and builds the whole thing, floors and monsters, when it is not")
	ck(acc.find("[LAZY-DUNGEON]") >= 0,
		"...and SAYS SO in the log, so 'nothing reads this' is proven in play rather than assumed")

	print("\n--- what a marker used to cost, measured ---")
	var types: Array = DD.DUNGEON_TYPES.keys()
	var sample: Array = []
	for i in range(mini(8, types.size())):
		sample.append(types[i * maxi(1, types.size() / 8) % types.size()])
	var t0 := Time.get_ticks_usec()
	var floors_built := 0
	var tiles := 0
	for dt in sample:
		var dd: Dictionary = DD.get_dungeon(dt)
		var n: int = int(dd.get("floors", 1))
		for f in range(n):
			var fd = DD.generate_floor_grid(dt, f, f == n - 1)
			floors_built += 1
			tiles += fd.grid.size() * (fd.grid[0].size() if fd.grid.size() > 0 else 0)
	var us := Time.get_ticks_usec() - t0
	var per := float(us) / float(maxi(1, sample.size()))
	print("  %d dungeons, %d floors, %d tiles of grid: %.1f ms, %.1f ms each" % [
		sample.size(), floors_built, tiles, us / 1000.0, per / 1000.0])
	print("  a Variant is 24 bytes, so those grids alone are ~%.0f KB per dungeon" % [
		float(tiles) / float(maxi(1, sample.size())) * 24.0 / 1024.0])
	ck(per > 1000.0, "building one interior is %.1f ms, which is why the cap existed" % (per / 1000.0))

	# A CACHE of grids keyed by (type, floor) was the obvious next saving, because the generator
	# seeds itself `hash(dungeon_id + floor_num)` and plainly means to be deterministic. It is
	# not. Two `Array.shuffle()` calls in `_carve_alcove_spurs` draw from the GLOBAL rng, not the
	# seeded one, so the same type and floor give a different layout every call. Recorded here
	# rather than fixed: making it deterministic would also make every goblin_caves floor 2 in
	# the world identical, which is a design choice and not mine to take.
	var a = DD.generate_floor_grid(String(sample[0]), 1, false)
	var b = DD.generate_floor_grid(String(sample[0]), 1, false)
	ck(str(a.grid) != str(b.grid),
		"grids are NOT reproducible from (type, floor) - two shuffle() calls escape the seed, so a cache would change layouts")

	print("\n[LAZYDUNGEON] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
