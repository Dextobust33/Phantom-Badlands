extends SceneTree
## ⛑ CAN A DUNGEON FEED YOU?
##
## Owner 2026-09-10: *"One argument for the chickens is they could be a food source that can be
## found in the dungeon so they can use it when they rest."* Asked in 2026-09-17 between a
## floor-loot kind, a creature you catch and an interactive tile: *"A creature you catch."*
##
## Four things here can break silently, which is why each has a check:
##   1. the food material is not actually EDIBLE (the Rest handler refuses it and says nothing
##      useful) — this is the fault the twelve-copy food-type list was waiting to produce
##   2. `meat` stayed a twelfth private copy somewhere
##   3. the sprite does not LOAD (a failed `[img]` draws nothing at all — no gap, no error)
##   4. a chicken starts a FIGHT, because the critter branch sits after a combat trigger
##
## Run:
##   godot --headless --path . --script res://tools/probe/dungeon_critters.gd

const CDB := preload("res://shared/crafting_database.gd")
const DS := preload("res://client/dungeon_sprites.gd")
const DDB := preload("res://shared/dungeon_database.gd")
const ServerScript = preload("res://server/server.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	print("===== 1. THE RATION IS EDIBLE =====")
	var mat: Dictionary = CDB.MATERIALS.get("wild_fowl", {})
	print("           wild_fowl = %s" % str(mat))
	ck(not mat.is_empty(), "the material exists")
	ck(String(mat.get("type", "")) == "meat", "and it is meat (%s)" % String(mat.get("type", "")))
	# ⛑ THE CHECK THAT MATTERS: not "is it meat" but "does the game think meat is food". Those
	# were different questions until FOOD_MATERIAL_TYPES had one owner.
	ck(CDB.is_food_material("wild_fowl"), "and the game's own food test accepts it")
	ck(int(mat.get("tier", 0)) == 1 and int(mat.get("value", 999)) <= 10,
		"at tier 1 and near-worthless, so it is a ration and not a valor farm")
	# The four older edible types must still be edible - adding a fifth is exactly when one of
	# them gets dropped from the list.
	for t in ["plant", "herb", "fungus", "fish", "meat"]:
		ck(t in CDB.FOOD_MATERIAL_TYPES, "%s is still food" % t)

	print("\n===== 2. THE FOOD LIST HAS ONE OWNER =====")
	# ⛑ It had TWELVE. `["plant", "herb", "fungus", "fish"]` was written out in the Rest handler,
	# five market and order filters, two supply calculators, the client's food picker, the
	# client's food counter, the market panel and a probe. Adding `meat` to eleven of them would
	# have produced a bird you can sell but not eat, and nothing would have failed loudly.
	#
	# Written as a token BAN over the real files rather than a check that the constant exists,
	# because the constant existing says nothing about whether anyone reads it.
	var files := [
		"res://server/server.gd", "res://client/client.gd", "res://client/market_panel.gd",
		"res://shared/character.gd", "res://shared/drop_tables.gd",
		"res://tools/probe/starter_dungeon_size.gd",
	]
	var copies: Array = []
	for f in files:
		var src := FileAccess.get_file_as_string(f)
		if src == "":
			continue
		for line in src.split("\n"):
			# `"ore"` excludes the materials DISPLAY ORDER, which is a list of every material
			# type and not a food list. Worth noting that this false positive found a real
			# (smaller) fault next door: that list had no `meat` entry, so Wild Fowl fell into
			# the unstyled "ungrouped" branch.
			if '"fungus"' in line and '"fish"' in line and '"ore"' not in line and "FOOD_MATERIAL_TYPES" not in line:
				copies.append("%s: %s" % [f.get_file(), line.strip_edges().substr(0, 90)])
	for c in copies:
		print("           SECOND COPY: " + String(c))
	ck(copies.is_empty(), "nobody carries a private copy of the list (%d found)" % copies.size())

	print("\n===== 3. THE SPRITE LOADS =====")
	# ⛑ `ResourceLoader.exists()` LIES under a .gdignore and a failed [img] draws NOTHING - no
	# gap, no placeholder, no error. So the check is calling load().
	var frames_ok := 0
	var frames_total := 0
	for fr in range(3):
		for al in [false, true]:
			frames_total += 1
			var path: String = DS.monster_path("Chicken", fr, al)
			if path != "" and load(path) != null:
				frames_ok += 1
			else:
				print("           MISSING: frame %d alert=%s -> %s" % [fr, str(al), path])
	print("           %d/%d baked chicken tiles load" % [frames_ok, frames_total])
	ck(frames_ok == frames_total, "every frame the renderer can ask for exists")
	# And it must resolve through the SAME resolver the floor uses, by the name the server puts
	# on the wire - not by a path this probe knows.
	ck(DS.monster_path("Chicken", 0).contains("chicken"),
		"resolved by the floor's own lookup from the wire name")

	print("\n===== 4. A CHICKEN NEVER STARTS A FIGHT =====")
	# ⛑ There are TWO places an entity meets the player: the player steps onto it (the move
	# handler) and it steps onto the player (the monster turn). A critter has to be handled
	# before the combat trigger in BOTH, and a source check is the only way to see ordering.
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	var lines: PackedStringArray = srv.split("\n")
	var critter_move := -1
	var combat_move := -1
	var critter_turn := -1
	var combat_turn := -1
	for i in range(lines.size()):
		var t: String = lines[i].strip_edges()
		if t.begins_with("if stepped_critter != null and"):
			critter_move = i
		if t == "var stepped_monster = _get_monster_at_position(instance_id, character.dungeon_floor, new_x, new_y)":
			combat_move = i
		if t.begins_with("if m.get(\"is_critter\", false)):") or t == 'if m.get("is_critter", false):':
			critter_turn = i
		if t == "_start_dungeon_monster_combat(peer_id, m)" and combat_turn < 0:
			combat_turn = i
	print("           move handler: critter at line %d, combat at %d" % [critter_move + 1, combat_move + 1])
	print("           monster turn: critter at line %d, combat at %d" % [critter_turn + 1, combat_turn + 1])
	ck(critter_move > 0 and combat_move > 0 and critter_move < combat_move,
		"stepping ONTO a critter is handled before the combat check")
	ck(critter_turn > 0 and combat_turn > 0 and critter_turn < combat_turn,
		"and a critter's own turn ends before any combat trigger")
	ck("_catch_dungeon_critter" in srv and "_move_dungeon_critter" in srv,
		"both critter handlers are present")

	print("\n===== 5. HOW MUCH FOOD A RUN ACTUALLY YIELDS =====")
	# Stated in meals rather than in probabilities, because "35% per floor" tells nobody whether
	# a long run can feed itself. A rest costs ONE food.
	var srv_chance := 0.0
	for line in lines:
		if line.begins_with("const DUNGEON_CRITTER_FLOOR_CHANCE"):
			srv_chance = float(line.split(":=")[1].strip_edges())
	print("           spawn chance %.2f per floor, 1-3 rations each (mean 2.0)" % srv_chance)
	for floors in [3, 5, 9]:
		print("           %d floors -> %.1f birds, %.1f meals" % [
			floors, floors * srv_chance, floors * srv_chance * 2.0])
	ck(srv_chance > 0.0, "the spawn chance was found in the server (%.2f)" % srv_chance)
	ck(9 * srv_chance * 2.0 < 9.0,
		"the deepest run still cannot feed itself outright (%.1f meals for 9 floors)" % (9 * srv_chance * 2.0))
	ck(3 * srv_chance * 2.0 > 1.0,
		"but even a short run usually yields a meal (%.1f)" % (3 * srv_chance * 2.0))
	# ⛑ WHAT THIS PROBE DOES NOT PROVE: that the bird is CATCHABLE. That depends on the flee
	# rule against a real grid, and it is asserted here only arithmetically - at a 65% flee
	# chance the player closes one tile every ~2.9 turns on open ground, and a corridor or dead
	# end closes it faster. A 100% flee chance would be uncatchable on open ground, which is the
	# whole reason the constant is not 1.0. Verifying the chase properly needs a live floor.
	var flee := 0.0
	for line in lines:
		if line.begins_with("const DUNGEON_CRITTER_FLEE_CHANCE"):
			flee = float(line.split(":=")[1].strip_edges())
	ck(flee > 0.0 and flee < 1.0,
		"the bird sometimes fails to run, so it can be caught at all (%.2f)" % flee)

	print("\n===== 6. THE SPAWNER, AGAINST REAL FLOORS =====")
	# ⛑ Driving the real function rather than asserting about it, because the two ways a bird
	# fails to appear are both invisible from the source: it lands somewhere illegal, or it is
	# spawned and then wiped.
	var srv2 = ServerScript.new()
	var placed := 0
	var illegal := 0
	var tried := 0
	for id in ["goblin_caves", "wolf_den", "balrog_depths", "chaos_sanctum"]:
		if DDB.get_dungeon(id).is_empty():
			continue
		for fl in range(3):
			var fg: Dictionary = DDB.generate_floor_grid(id, fl, fl == 2)
			var grid: Array = fg.get("grid", [])
			if grid.is_empty():
				continue
			var iid := "probe_%s_%d" % [id, fl]
			srv2.dungeon_monsters = {}
			tried += 1
			if not srv2._spawn_dungeon_critter(iid, fl, grid):
				continue
			placed += 1
			var ents: Array = srv2.dungeon_monsters.get(iid, {}).get(fl, [])
			for e in ents:
				var t: int = int(grid[int(e.y)][int(e.x)])
				# EMPTY is the only tile a wandering entity may stand on: a wall is inside the
				# rock, and the entrance/exit are the stairs the player arrives and leaves on.
				if t != int(DDB.TileType.EMPTY):
					illegal += 1
					print("           ILLEGAL TILE: %s floor %d at (%d,%d) tile=%d" % [id, fl, int(e.x), int(e.y), t])
				if not bool(e.get("is_critter", false)):
					illegal += 1
					print("           NOT FLAGGED AS A CRITTER: %s" % str(e))
	print("           %d/%d floors got a bird, %d illegal placements" % [placed, tried, illegal])
	ck(placed == tried, "the spawner always found somewhere to stand (%d/%d)" % [placed, tried])
	ck(illegal == 0, "and every bird stands on open floor, flagged as a critter")
	srv2.free()

	# ⚑ THE ORDERING THAT KEEPS IT ALIVE. `_spawn_all_dungeon_monsters` clears
	# `dungeon_monsters[instance_id]` and then calls `_spawn_all_dungeon_floor_items`, which is
	# where the critter spawn lives. Reorder those two and every bird in the game silently
	# vanishes - with no error, because clearing a dictionary is not a failure.
	var reset_line := -1
	var items_call := -1
	for i in range(lines.size()):
		var t: String = lines[i].strip_edges()
		if t == "dungeon_monsters[instance_id] = {}" and reset_line < 0:
			reset_line = i
		if t.begins_with("_spawn_all_dungeon_floor_items(instance_id"):
			items_call = i
	print("           monster-dict reset at line %d, floor-item pass at %d" % [reset_line + 1, items_call + 1])
	ck(reset_line > 0 and items_call > reset_line,
		"the floor-item pass (which spawns the birds) runs AFTER the monster dict is cleared")

	print("\n===== VERDICT =====")
	print("  all checks PASS" if fails == 0 else "  %d check(s) FAIL" % fails)
	quit(0)
