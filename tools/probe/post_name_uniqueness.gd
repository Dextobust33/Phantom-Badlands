extends SceneTree
## ⛑ IS EVERY POST NAME UNIQUE, AND DOES THE RENAME HOLD STILL?
##
## A post carries no id. `WorldSystem.npc_post_id()` synthesises one from the NAME, and the server
## keys its coordinate table by that id - so two posts sharing a name share a key and one silently
## answers for the other. Measured on the owner's world: **17 of 102 names duplicated across 120
## posts**, and a board at distance 74 priced as though it stood at distance 3037. XP goes as
## `pow(area_level + 1, 2.2)`, which turned a 42x level error into roughly 3000x in the payout.
##
## ⛑ STABILITY IS THE HALF THAT IS EASY TO MISS. A rename that is not deterministic moves a
## post's id on the next boot, and every quest id ever built from it moves with it - so this
## asserts that running the migration TWICE changes nothing the second time, and that running it
## on a shuffled list produces the SAME names. A "fix" that renames a different post each boot
## would pass a uniqueness check on every single run.
##
## Run:
##   godot --headless --path . --script res://tools/probe/post_name_uniqueness.gd

const NpcPosts = preload("res://shared/npc_post_database.gd")
const WorldSys = preload("res://shared/world_system.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _load_posts() -> Array:
	var path := "user://data/npc_posts.json"
	if not FileAccess.file_exists(path):
		return []
	var txt := FileAccess.get_file_as_string(path)
	var d = JSON.parse_string(txt)
	if d is Dictionary and d.has("posts"):
		return d["posts"]
	return d if d is Array else []


func _dupe_ids(posts: Array) -> Dictionary:
	var seen := {}
	for p in posts:
		var id := WorldSys.npc_post_id(p)
		if not seen.has(id):
			seen[id] = 0
		seen[id] += 1
	var out := {}
	for k in seen.keys():
		if int(seen[k]) > 1:
			out[k] = seen[k]
	return out


func _names(posts: Array) -> Array:
	var out: Array = []
	for p in posts:
		out.append(String(p.get("name", "")))
	return out


func _init() -> void:
	var posts := _load_posts()
	if posts.is_empty():
		print("[PROBE] SKIP no user://data/npc_posts.json - run the game once to generate a world")
		quit(0)
		return
	print("  %d posts in the live world" % posts.size())

	var before := _dupe_ids(posts)
	print("  colliding ids BEFORE: %d" % before.size())
	for k in before.keys():
		print("    %s x%d" % [k, int(before[k])])

	var renamed: int = NpcPosts.deduplicate_post_names(posts)
	print("  renamed %d post(s)" % renamed)

	var after := _dupe_ids(posts)
	ck(after.is_empty(), "every post id is now unique (%d collisions remain)" % after.size())

	# Idempotent: a second pass must be a no-op, or the file is rewritten every boot and the ids
	# move underneath every quest that references them.
	var names_once := _names(posts)
	var again: int = NpcPosts.deduplicate_post_names(posts)
	ck(again == 0, "a second pass renames nothing (got %d)" % again)
	ck(_names(posts) == names_once, "and leaves every name exactly as it was")

	# Order-independent: the SAME post must win the plain name regardless of list order, or a
	# world saved in a different order gets different ids.
	var shuffled := posts.duplicate(true)
	shuffled.reverse()
	NpcPosts.deduplicate_post_names(shuffled)
	var a := {}
	for p in posts:
		a[Vector2i(int(p.get("x", 0)), int(p.get("y", 0)))] = String(p.get("name", ""))
	var mismatched := 0
	for p in shuffled:
		var key := Vector2i(int(p.get("x", 0)), int(p.get("y", 0)))
		if a.has(key) and String(a[key]) != String(p.get("name", "")):
			mismatched += 1
	ck(mismatched == 0, "the same post keeps the same name whatever order the list is in (%d differ)" % mismatched)

	print("")
	if fails == 0:
		print("[PROBE] PASS post ids are unique, stable and order-independent")
	else:
		print("[PROBE] FAIL %d check(s)" % fails)
	quit(1 if fails > 0 else 0)
