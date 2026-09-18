extends SceneTree
## ⛑ DOES A STATION'S ART COVER THE TILE ANOTHER STATION STANDS ON?
##
## Owner 2026-09-18, live: *"Warden hollis is also standing on a portion of the Quest board."*
##
## ⛑ THIS IS A LAYOUT INVARIANT, NOT A SPRITE OPINION, and it is why the fix is a span and not a
## nudge. `_place_stations` guarantees exactly one thing about spacing: **no two stations are
## CARDINALLY adjacent**. Nothing stops a station sitting diagonally, or two cells away. Meanwhile
## `overworld_room.gd` PASS 2 anchors big art to the BOTTOM of its base cell and grows it UPWARD
## and outward, centred — so a span of R rows reaches R-1 cells north, and a span of C columns
## reaches (C-1)/2 cells each side.
##
## Put those together and the rule falls out: **art may reach the cardinal north cell and nothing
## further**, because north-cardinal is the only neighbour the placer promises to leave empty.
## A 3-row span reaches two cells north, which the placer is free to fill — and at the Crossroads
## it filled it with the Warden.
##
## This probe runs the REAL generator on the REAL live world seed and reports every collision,
## rather than reasoning about spans on paper.
##
## Run:
##   godot --headless --path . --script res://tools/probe/post_art_does_not_cover_people.gd

const NpcPostDatabaseScript := preload("res://shared/npc_post_database.gd")

## The live world seed, read off the production server 2026-09-18. The Crossroads main room is a
## fixed size (`STARTER_MAIN_SIZE`) so its interior does not depend on this, but its DOORS do, and
## doors decide which interior tiles are candidates for a station.
const LIVE_SEED := 349942589444

## Tiles that are a PERSON. `bake_person` gives these a plain 32px figure with no big art, so they
## can never cover anything — but they are the worst thing to be covered BY, which is what the
## owner reported.
const PEOPLE := ["warden", "blacksmith", "healer", "cartographer"]

var _fails: Array = []


class TileSink:
	var tiles: Dictionary = {}
	func set_tile(x: int, y: int, d: Dictionary) -> void:
		tiles["%d,%d" % [x, y]] = String(d.get("type", ""))


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


func _init() -> void:
	var spans: Dictionary = {}
	var f := FileAccess.open("res://client/sprites/overworld32/big/big_tiles.json", FileAccess.READ)
	if f == null:
		print("[PROBE] FAIL big_tiles.json is missing - the map has no multi-cell art at all")
		quit(1)
		return
	spans = JSON.parse_string(f.get_as_text())
	f.close()

	print("")
	print("===== 1. THE REACH OF EVERY PIECE OF BIG ART =====")
	# ⛑ THE RULE, STATED ONCE AND CHECKED AGAINST THE PLACER'S ONLY PROMISE.
	var names: Array = spans.keys()
	names.sort()
	print("  %-18s %-8s %-10s %s" % ["tile", "span", "reaches N", "verdict"])
	for n in names:
		var rows: int = int(spans[n][0])
		var cols: int = int(spans[n][1])
		var north: int = rows - 1
		var verdict := "ok"
		if north > 1:
			verdict = "REACHES PAST THE GUARANTEED-EMPTY CELL"
		print("  %-18s %-8s %-10d %s" % [n, "%dx%d" % [rows, cols], north, verdict])

	print("")
	print("===== 2. THE REAL CROSSROADS, STAMPED FROM THE LIVE SEED =====")
	var posts: Array = NpcPostDatabaseScript.generate_posts(LIVE_SEED)
	var starter: Dictionary = {}
	for p in posts:
		if bool((p as Dictionary).get("is_starter", false)):
			starter = p
			break
	if starter.is_empty():
		_fail("no starter post in the generated world")
		_finish()
		return
	var sink := TileSink.new()
	NpcPostDatabaseScript.stamp_post_into_chunks(starter, sink)

	# Every station cell, by type.
	var station_at: Dictionary = {}   # Vector2i -> type
	for key in sink.tiles.keys():
		var t := String(sink.tiles[key])
		if t in ["floor", "wall", "door"]:
			continue
		var parts: PackedStringArray = String(key).split(",")
		station_at[Vector2i(int(parts[0]), int(parts[1]))] = t
	print("  %d stations placed in the Crossroads" % station_at.size())
	var cells: Array = station_at.keys()
	cells.sort_custom(func(a, b): return (a.y * 1000 + a.x) < (b.y * 1000 + b.x))
	for c in cells:
		print("    (%3d,%3d)  %s" % [c.x, c.y, String(station_at[c])])

	print("")
	print("===== 3. WHOSE ART LANDS ON WHOSE TILE =====")
	# ⛑ RUN THE RENDERER'S OWN GEOMETRY IN PIXELS, not a description of it in cells. PASS 2 does:
	#     bx = x*CELL + (CELL - w)/2      by = (y+1)*CELL - h
	# so the art is CENTRED horizontally and anchored to the BOTTOM of its base cell. An odd span
	# lands on cell boundaries; an EVEN one straddles, covering half of each side neighbour — which
	# a cell-counting check rounds away. Overlap is reported as a fraction of the victim's cell.
	#
	# ⚑ AND SCREEN-UP IS +Y IN THE WORLD. `get_direction_offset` has south at dy = -1, and the map
	# draws north at the TOP, so art growing upward on screen grows toward HIGHER world y. The
	# first version of this probe subtracted, reported a different victim, and would have had me
	# shrink the board in the wrong direction. This is the third time the map's y has been
	# inverted in a check.
	const CELL := 32
	var hits := 0
	for cell in station_at.keys():
		var tile := String(station_at[cell])
		if not spans.has(tile):
			continue
		var rows: int = int(spans[tile][0])
		var cols: int = int(spans[tile][1])
		# Art rect in pixels, in a space where +x is east and +y is NORTH.
		var ax0: float = float(cell.x) * CELL + (CELL - cols * CELL) / 2.0
		var ax1: float = ax0 + cols * CELL
		var ay0: float = float(cell.y) * CELL          # bottom edge = the base cell's own row
		var ay1: float = ay0 + rows * CELL
		for other in station_at.keys():
			if other == cell:
				continue
			var ox0: float = float(other.x) * CELL
			var oy0: float = float(other.y) * CELL
			var ow: float = maxf(0.0, minf(ax1, ox0 + CELL) - maxf(ax0, ox0))
			var oh: float = maxf(0.0, minf(ay1, oy0 + CELL) - maxf(ay0, oy0))
			var frac: float = (ow * oh) / float(CELL * CELL)
			if frac <= 0.0:
				continue
			hits += 1
			var victim := String(station_at[other])
			var who := "PERSON" if victim in PEOPLE else "station"
			_fail("%s art at (%d,%d) covers %d%% of the %s %s at (%d,%d)" % [
				tile, cell.x, cell.y, int(round(frac * 100.0)), who, victim, other.x, other.y])
	if hits == 0:
		_ok("no station's art reaches another station's tile")

	print("")
	print("===== 4. EVERY POST IN THE LIVE WORLD, NOT JUST THE ONE THAT WAS REPORTED =====")
	# ⛑ THE NEW RULE COSTS SPACE, so the thing that could go wrong is a post that can no longer
	# fit its services. Measured across all of them rather than assumed from the Crossroads, which
	# has the largest main room in the game and is therefore the least informative sample.
	var want_stations: int = 0
	var worst_short: int = 0
	var short_posts: int = 0
	var total_overlaps: int = 0
	for p in posts:
		var post: Dictionary = p
		var sink2 := TileSink.new()
		NpcPostDatabaseScript.stamp_post_into_chunks(post, sink2)
		var here: Dictionary = {}
		for key in sink2.tiles.keys():
			var t := String(sink2.tiles[key])
			if t in ["floor", "wall", "door"]:
				continue
			var parts: PackedStringArray = String(key).split(",")
			here[Vector2i(int(parts[0]), int(parts[1]))] = t
		# 10 base stations (forge, apothecary, enchant_table, writing_desk, workbench, quest_board,
		# blacksmith, healer, market, cartographer) + the post marker, + companion_stable at T5+,
		# + the throne at the Crossroads. Counted off the real list, because the first version of
		# this line guessed 11 and reported all 120 posts one station short.
		var expect: int = 10 + 1
		if int(post.get("tier", 1)) >= 5:
			expect += 1
		if bool(post.get("is_starter", false)):
			expect += 1
		want_stations += expect
		if here.size() < expect:
			short_posts += 1
			worst_short = maxi(worst_short, expect - here.size())
		for cell in here.keys():
			var tile := String(here[cell])
			if not spans.has(tile):
				continue
			var rows: int = int(spans[tile][0])
			var cols: int = int(spans[tile][1])
			var ax0: float = float(cell.x) * 32.0 + (32.0 - cols * 32.0) / 2.0
			var ax1: float = ax0 + cols * 32.0
			var ay0: float = float(cell.y) * 32.0
			var ay1: float = ay0 + rows * 32.0
			for other in here.keys():
				if other == cell:
					continue
				var ow: float = maxf(0.0, minf(ax1, float(other.x) * 32.0 + 32.0) - maxf(ax0, float(other.x) * 32.0))
				var oh: float = maxf(0.0, minf(ay1, float(other.y) * 32.0 + 32.0) - maxf(ay0, float(other.y) * 32.0))
				if ow * oh > 0.0:
					total_overlaps += 1
					if total_overlaps <= 12:
						print("    %s at (%d,%d) in %s (T%d, main %dx%d) covers %s at (%d,%d)" % [
							tile, cell.x, cell.y, String(post.get("name", "?")),
							int(post.get("tier", 1)),
							int(post.get("main_room", {}).get("x1", 0)) - int(post.get("main_room", {}).get("x0", 0)) + 1,
							int(post.get("main_room", {}).get("y1", 0)) - int(post.get("main_room", {}).get("y0", 0)) + 1,
							String(here[other]), other.x, other.y])
	print("  %d posts swept, %d station slots wanted" % [posts.size(), want_stations])
	print("  posts missing a station: %d   (worst: %d short)" % [short_posts, worst_short])
	print("  art-on-station overlaps world-wide: %d" % total_overlaps)
	if total_overlaps > 0:
		_fail("%d overlap(s) survive somewhere in the world" % total_overlaps)
	else:
		_ok("no post anywhere draws one station on top of another")
	if short_posts > 0:
		_fail("%d post(s) could not fit all their services under the new spacing" % short_posts)
	else:
		_ok("every post still fits every service it is meant to have")

	print("")
	_finish()


func _finish() -> void:
	if not _fails.is_empty():
		print("[PROBE] FAIL %d overlap(s):" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS every station's art stays within the cells the placer guarantees are")
	print("       empty, so nobody stands in the middle of the furniture.")
	quit()
