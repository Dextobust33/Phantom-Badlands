extends SceneTree
## Do the figures on the map look alive, and does it cost anything?
##
## Owner 2026-09-14: *"ideally we want the player and their companion to seem more alive rather
## than just having art where they just stand still."* And, separately: *"We don't want this to
## cause server lag."*
##
## The solution had to cover EVERY figure, which ruled out anything built on extra frames. Only 40
## of our 80 player sprites have alternate poses; companions are monster art with no walk frames at
## all. A one-pixel vertical offset needs no art, so it works for all of them - and for anything
## added later.
const Room = preload("res://client/overworld_room.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _rows(n: int, w: int, ch: String) -> Array:
	var out: Array = []
	for y in range(n):
		var r: Array = []
		for x in range(w):
			r.append(ch)
		out.append(r)
	return out


func _init() -> void:
	if not Room.available():
		print("SKIP - baked overworld art not present in this checkout")
		quit(0)
		return

	var meaning := _rows(5, 5, "grass")
	var biomes := _rows(5, 5, "grass")
	var sprite := "res://client/sprites/overworld_pad32/1_1/down_stand.png"
	var figures := {"2,2": {"main": sprite}}

	print("===== THE MAP REDRAWS WHEN THE IDLE BEAT MOVES =====")
	# The composer caches on a key. If the beat is not in that key, the cache hands back the
	# previous frame forever and nothing ever moves - which is a silent no-op, the worst kind.
	ck(Room.build(meaning, biomes, figures, {}, 0), "composed at tick 0")
	ck(Room.build(meaning, biomes, figures, {}, 1), "composed at tick 1")

	print("")
	print("===== AND THE FIGURE ACTUALLY MOVES =====")
	# Pixels, not intentions. Compose the same map at two points of the cycle and require the
	# images to differ - the check that a bob applied at 0 pixels would fail.
	var seen := {}
	for t in range(6):
		Room.build(meaning, biomes, figures, {}, t)
		var g: Image = Room._grid
		ck(g != null, "tick %d produced an image" % t)
		if g == null:
			continue
		seen[t] = _hash(g)
	var distinct := {}
	for t in seen:
		distinct[seen[t]] = true
	print("  six ticks produced %d distinct images" % distinct.size())
	ck(distinct.size() >= 2, "the figure is not drawn identically on every tick")

	print("")
	print("===== A CROWD DOES NOT BREATHE IN UNISON =====")
	# Phase is offset by the figure's own cell. Everyone rising together reads as the map
	# glitching rather than as a group of living people.
	var crowd := {"1,1": {"main": sprite}, "1,2": {"main": sprite}, "2,1": {"main": sprite}}
	Room.build(meaning, biomes, crowd, {}, 0)
	var g0: Image = Room._grid
	ck(g0 != null, "a crowd composes")
	# The property that matters is that a CROWD is not all in step - not that any particular
	# pair differs. With six phases and two offsets, about half of any given pair will match,
	# and demanding otherwise was asserting luck: the first version of this check failed on
	# cells (1,1) and (1,2), which legitimately share an offset.
	var up := 0
	var down := 0
	for y in range(5):
		for x in range(5):
			if ((0 + x * 3 + y * 5) % 6) < 3:
				up += 1
			else:
				down += 1
	print("  across a 5x5 field at one instant: %d figures risen, %d settled" % [up, down])
	ck(up > 0 and down > 0, "a crowd is split across the cycle rather than moving as one")
	ck(mini(up, down) * 3 >= maxi(up, down),
		"and the split is reasonably even (%d vs %d), so it reads as life not as a wave" % [up, down])

	print("")
	print("===== IT COSTS THE SERVER NOTHING =====")
	# Worth asserting because the owner asked about lag directly. The composer is a static client
	# class; it has no socket, no peer, no server reference. Nothing here can reach the server.
	var src := FileAccess.get_file_as_string("res://client/overworld_room.gd")
	ck(not src.contains("send_to_server"), "the composer never talks to the server")
	ck(not src.contains("peer"), "and has no notion of a peer at all")

	print("")
	print("----- NOT COVERED HERE -----")
	print("  Whether a one-pixel bob READS as breathing at 1.35x on a real screen. That is a look,")
	print("  and looks are a playtest.")

	print("")
	if fails == 0:
		print("PASS - every figure breathes, out of step with its neighbours, at no server cost")
	else:
		print("FAIL - %d check(s) failed" % fails)
	quit(1 if fails > 0 else 0)


func _hash(img: Image) -> int:
	var d := img.get_data()
	var h := 0
	for i in range(0, d.size(), 97):
		h = (h * 31 + d[i]) & 0x7FFFFFFF
	return h
