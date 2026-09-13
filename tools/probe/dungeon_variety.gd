extends SceneTree
## 53 dungeon types must not all draw the same marker.
##
## Owner 2026-09-13: *"regarding dungeons on the over world they should have a variety, not all
## the same tile."*
##
## Two things can go wrong and only one of them is visible. The obvious one is that every type
## still maps to one picture. The dangerous one is a family whose art was never cut: the marker
## then resolves to nothing and the dungeon becomes INVISIBLE on the map - strictly worse than
## the sameness being fixed. So the fallback is tested as hard as the variety.
const DungeonDB = preload("res://shared/dungeon_database.gd")
const Room = preload("res://client/overworld_room.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	print("===== EVERY DUNGEON TYPE HAS A FAMILY =====")
	var types: Array = DungeonDB.DUNGEON_TYPES.keys()
	var by_family: Dictionary = {}
	for t in types:
		var f: String = DungeonDB.entrance_family(String(t))
		by_family[f] = int(by_family.get(f, 0)) + 1
	ck(types.size() >= 50, "%d dungeon types" % types.size())
	var unmapped: Array = []
	for t in types:
		if not DungeonDB.ENTRANCE_FAMILY.has(t):
			unmapped.append(t)
	# Falling back to `cave` is legitimate, but a long tail of unmapped types means new content
	# quietly stopped getting its own look - worth knowing, not worth failing on.
	print("  %d of %d types are explicitly mapped; %s" % [
		types.size() - unmapped.size(), types.size(),
		"none rely on the fallback" if unmapped.is_empty()
			else "falling back to cave: " + ", ".join(unmapped)])
	ck(unmapped.is_empty(), "no dungeon type is left to the default")

	print("\n===== AND THE FAMILIES ARE ACTUALLY USED =====")
	var keys: Array = by_family.keys()
	keys.sort()
	for f in keys:
		print("    %-10s %d types" % [f, int(by_family[f])])
	ck(by_family.size() >= 6, "%d distinct families across the roster" % by_family.size())
	var biggest := 0
	for f in by_family:
		biggest = maxi(biggest, int(by_family[f]))
	ck(biggest <= types.size() / 3,
		"the largest family is %d of %d types, so this is variety and not one bucket" % [
			biggest, types.size()])

	print("\n===== ART: WHAT IS CUT, AND WHAT FALLS BACK =====")
	var with_art: Array = []
	var without: Array = []
	for f in DungeonDB.ENTRANCE_FAMILIES:
		if ResourceLoader.exists("res://client/sprites/overworld32/overlay/dungeon_%s.png" % f):
			with_art.append(f)
		else:
			without.append(f)
	print("  own art:  %s" % ", ".join(with_art))
	print("  fallback: %s" % (", ".join(without) if not without.is_empty() else "(none)"))
	ck(with_art.size() >= 5, "%d families have their own entrance art" % with_art.size())

	print("\n===== NO FAMILY DRAWS A HOLE =====")
	# ⚑ THE CHECK THAT MATTERS. `_overlay_img` must return a picture for EVERY family, including
	# ones with no art of their own and including a family that does not exist yet - a dungeon
	# you cannot see on the map is far worse than one drawn generically.
	if not Room.available():
		print("  (art not present in this checkout - skipping the render half)")
	else:
		for f in DungeonDB.ENTRANCE_FAMILIES:
			var im: Image = Room._overlay_img("dungeon_%s" % f)
			ck(im != null, "dungeon_%s resolves to a picture" % f)
		var future: Image = Room._overlay_img("dungeon_somethingneverbaked")
		ck(future != null,
			"a family added tomorrow with no art still draws, rather than vanishing")

		print("\n===== AND THE MARKERS ARE DISTINCT FROM EACH OTHER =====")
		var imgs: Dictionary = {}
		for f in with_art:
			var im2: Image = Room._overlay_img("dungeon_%s" % f)
			if im2 != null:
				imgs[f] = im2
		var ks: Array = imgs.keys()
		ks.sort()
		var same := 0
		for i in range(ks.size()):
			for j in range(i + 1, ks.size()):
				var a: Image = imgs[ks[i]]
				var b: Image = imgs[ks[j]]
				if a.get_data() == b.get_data():
					print("    %s and %s are the SAME picture" % [ks[i], ks[j]])
					same += 1
		ck(same == 0, "no two families with their own art share a picture")

	print("\n===== THE SERVER SENDS IT AND THE MAP CARRIES IT =====")
	var ssrc := FileAccess.get_file_as_string("res://server/server.gd")
	ck(ssrc.find("DungeonDatabaseScript.entrance_family(") >= 0,
		"the server tags each visible dungeon with its family")
	var wsrc := FileAccess.get_file_as_string("res://shared/world_system.gd")
	ck(wsrc.find('sem_parts.append("!dungeon_%s" % _fam if _fam != "" else "!dungeon")') >= 0,
		"...and the map payload carries it, falling back to the plain marker if absent")

	print("\n[DUNGEONVARIETY] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
