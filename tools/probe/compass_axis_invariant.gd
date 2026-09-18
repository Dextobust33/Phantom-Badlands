extends SceneTree
## ⛑ DOES THE COMPASS POINT THE RIGHT WAY? Checked against the world's OWN direction table.
##
## Found 2026-09-18 while building the Scribe's Chart a Course: THREE functions in server.gd
## answered "which way is that" and TWO of them had north and south backwards.
##
##   `_get_direction_text`      +y = north   CORRECT   (11 call sites)
##   `_compass_direction`       +y = south   INVERTED  (8 call sites, incl. the Cartographer's
##                                                      15-Valor Locate — a paid service that
##                                                      named north when the dungeon was south)
##   `_compass_direction_label` +y = south   INVERTED  (the Sanctuary Compass HUD glyph — a
##                                                      permanent Valor upgrade pointing up for
##                                                      south)
##
## ⛑ AND THE COMMENT IS WHY IT SURVIVED. `_compass_direction_label` carried "same thresholds as
## _get_direction_text so the compass agrees with prose direction text" directly above code that
## returned the opposite letter for every north and south. Anyone checking by reading agreed with
## it. So this probe does not read: it takes `WorldSystem.get_direction_offset`, which is the
## table the game MOVES the player with, and asserts the compass names the same direction the
## player would actually walk.
##
## Run:
##   godot --headless --path . --script res://tools/probe/compass_axis_invariant.gd

const WorldSystemScript := preload("res://shared/world_system.gd")

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _init() -> void:
	var ws = WorldSystemScript.new()
	get_root().add_child(ws)

	print("")
	print("===== THE AXIS, AGAINST THE TABLE THE GAME MOVES PLAYERS WITH =====")
	print("  %-4s %-12s %-10s %-12s %s" % ["dir", "moves to", "world calls", "compass says", ""])
	# Numpad directions. 5 is "here" and has no offset.
	for d in [1, 2, 3, 4, 6, 7, 8, 9]:
		var off: Vector2i = ws.get_direction_offset(0, 0, d)
		var world_name: String = ws.get_direction_name(d)
		# ⛑ Scaled out to (±30, ±30). At (±1, ±1) the mostly-horizontal / mostly-vertical
		# thresholds use integer division by 3, so every step is "diagonal" and the pure
		# north/south/east/west cases would never be exercised at all — the probe would pass
		# while the cardinal axes were untested, which is the whole question.
		var dx: int = off.x * 30
		var dy: int = off.y * 30
		var said: String = WorldSystemScript.compass_octant(dx, dy)
		var good: bool = said == world_name
		print("  %-4d (%3d,%3d)   %-10s %-12s %s" % [d, dx, dy, world_name, said, "ok" if good else "<<< WRONG"])
		if not good:
			_fail("direction %d moves %s but the compass calls it %s" % [d, world_name, said])

	print("")
	print("===== THE THREE SURFACES AGREE =====")
	# ⛑ Each of these has a DIFFERENT output contract (bare word / prose+distance / letters), so
	# they are compared on the one thing they must share: the north-south sense.
	var src := FileAccess.get_file_as_string("res://server/server.gd")
	var surfaces := {
		"_compass_direction (prose, Cartographer Locate)": "func _compass_direction(",
		"_get_direction_text (prose + distance)": "func _get_direction_text(",
		"_compass_direction_label (Sanctuary Compass glyph)": "func _compass_direction_label(",
	}
	for label in surfaces.keys():
		var sig := String(surfaces[label])
		var i: int = src.find(sig)
		if i < 0:
			_fail("%s no longer exists" % label)
			continue
		# The body must delegate, not re-derive. A surface that spells out its own
		# `"north" if dy > 0` is exactly how the three drifted apart in the first place.
		var body: String = src.substr(i, 1400)
		var nxt: int = body.find("\nfunc ")
		if nxt > 0:
			body = body.substr(0, nxt)
		if body.find("compass_octant") < 0:
			_fail("%s does not delegate to WorldSystem.compass_octant — it derives its own axis" % label)
		elif body.find("\"north\" if") >= 0 or body.find("\"N\" if") >= 0:
			_fail("%s still has its own north/south arithmetic" % label)
		else:
			print("  ok    %s" % label)

	print("")
	print("===== THE GLYPH MATCHES THE WORD =====")
	# The Sanctuary Compass draws an arrow from the letters. An arrow that disagrees with the
	# word beside it is the same bug wearing a different coat.
	var pairs := {"north": "N", "south": "S", "east": "E", "west": "W",
		"northeast": "NE", "northwest": "NW", "southeast": "SE", "southwest": "SW"}
	var glyphs := {"N": "↑", "S": "↓", "E": "→", "W": "←",
		"NE": "↗", "NW": "↖", "SE": "↘", "SW": "↙"}
	for d in [1, 2, 3, 4, 6, 7, 8, 9]:
		var off: Vector2i = ws.get_direction_offset(0, 0, d)
		var word: String = WorldSystemScript.compass_octant(off.x * 30, off.y * 30)
		var want_letters: String = String(pairs.get(word, "?"))
		if not glyphs.has(want_letters):
			_fail("no glyph for %s" % word)
			continue
		# ↑ must mean north, and north must mean +y, which must mean the way direction 8 moves.
		if want_letters == "N" and off.y <= 0:
			_fail("glyph ↑ would be shown for a direction that decreases y")
		if want_letters == "S" and off.y >= 0:
			_fail("glyph ↓ would be shown for a direction that increases y")
	if _fails.is_empty():
		print("  ok    ↑ means north means +y means the way direction 8 walks")

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for f in _fails:
			print("   - %s" % f)
		quit(1)
		return
	print("[PROBE] PASS the compass names the direction the player actually walks, all three")
	print("       surfaces delegate to one axis, and the glyph agrees with the word.")
	quit()
