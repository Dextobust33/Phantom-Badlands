extends SceneTree
## A post may not be ringed with dungeons - and the world already is, so both halves must exist.
##
## Owner 2026-09-13: *"posts being overwhelmed with an enormous amount of dungeons spilling out
## monsters. The starter post alone is overwhelmed."*
##
## Measured cause (`tools/probe/dungeon_spread.gd`): the world is 0.0% H-grade country, 44.8% A
## and 16.6% S, and 100% of its H-grade land is within 40 tiles of a post - so a low-grade
## dungeon, which must stand in low-grade country to BE graded low, has one legal address: a
## post's doorstep.
##
## Two halves are needed and it is worth stating why: the spawn CAP stops it recurring, and the
## CULL undoes the world that already exists. Shipping only the cap would leave the owner's
## starter post exactly as reported until every dungeon on it despawned of its own accord.
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
	return src.substr(i, j - i)


func _init() -> void:
	var src := FileAccess.get_file_as_string(SRC)

	print("--- the spawn cap ---")
	ck(src.find("const POST_DUNGEON_RADIUS: int = 40") >= 0, "a doorstep radius is defined")
	ck(src.find("const MAX_DUNGEONS_NEAR_POST: int = 6") >= 0, "and a cap on how many may sit there")
	var place := _body(src, "_create_world_dungeon")
	ck(place.find("_too_crowded") >= 0, "placement rejects a candidate that would crowd a post")
	ck(place.find("if _inst.has(\"owner_peer_id\"):") >= 0,
		"...counting only WORLD dungeons, not players' personal instances")
	# The gate must not repeat v0.9.598's mistake of exempting tier 1 - which is precisely the
	# grade the land forces onto posts.
	var gate_i := place.find("_too_crowded")
	var gate := place.substr(maxi(0, gate_i - 1400), 1600)
	ck(gate.find("enforce_threat_limits") < 0,
		"the count cap is NOT behind the tier-2 threat gate - tier 1 is what crowds posts")

	print("\n--- the cull, for the world that already exists ---")
	var cull := _body(src, "_cull_crowded_posts")
	ck(cull != "", "a cull exists")
	ck(cull.find("if inst.has(\"owner_peer_id\"):") >= 0, "it never removes a personal instance")
	ck(cull.find("if not (inst.get(\"active_players\", []) as Array).is_empty():") >= 0,
		"...nor one somebody is standing in")
	ck(cull.find("int(inst.get(\"completed_at\", 0)) > 0") >= 0,
		"...nor one already completed and despawning")
	ck(cull.find("return int(a[\"d2\"]) > int(b[\"d2\"])") >= 0,
		"furthest from the post goes first, so a post keeps the nearest few")
	ck(cull.find("_dungeons_near(px, py, POST_DUNGEON_RADIUS)") >= 0,
		"and it reads the spatial index rather than scanning every dungeon")

	print("\n--- and it is actually WIRED into the maintenance tick ---")
	# A cull nothing calls is the shape that let three backlog items ship unticked.
	ck(src.find("world_dungeon_count -= _cull_crowded_posts()") >= 0,
		"the tick calls it AND corrects the count it just invalidated")

	print("\n[POSTCROWD] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
