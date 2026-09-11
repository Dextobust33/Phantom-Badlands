extends SceneTree
## Three dungeon-map faults the owner reported on 2026-09-10, and the rules that retire them.
##
## 1. A monster standing in your footsteps was invisible - the companion branch came SECOND in
##    the cell chain, ahead of every entity the server actually placed.
## 2. A knocked-out companion kept following you around the floor.
## 3. (found while fixing 1) Stepping onto a lamp put the lamp out, because the light set was
##    gathered inside the "nothing is here" branch.
##
## The KO rule is tested by CALLING it. The draw order is a property of one if/elif chain, so it
## is tested by reading that chain's branch order out of the source - there is no way to observe
## "which branch won" from a returned string without standing up the whole client.
const CLIENT := "res://client/client.gd"

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _chain() -> Array:
	"""The branch order of the cell-drawing chain in `_render_dungeon_grid`, as tags."""
	var src := FileAccess.get_file_as_string(CLIENT)
	var lines := src.split("\n")
	var a := -1
	var b := -1
	for i in range(lines.size()):
		var l: String = lines[i]
		if l.begins_with("func _render_dungeon_grid"):
			a = i
		elif a >= 0 and l.begins_with("func ") and i > a:
			b = i
			break
	if a < 0:
		return []
	var out: Array = []
	for i in range(a, b):
		var t: String = lines[i].strip_edges()
		if t.begins_with("if x == player_x"):
			out.append("player")
		elif t.begins_with("if npc_map.has") or t.begins_with("elif npc_map.has"):
			out.append("npc")
		elif t.begins_with("elif monster_map.has"):
			out.append("monster")
		elif t.begins_with("elif trap_map.has"):
			out.append("trap")
		elif t.begins_with("elif item_map.has"):
			out.append("item")
		elif t.begins_with("elif _dungeon_companion_at") or t.begins_with("if _dungeon_companion_at"):
			out.append("companion")
	return out


func _init() -> void:
	print("--- 1. draw order: the phantom yields to everything the server placed ---")
	var order := _chain()
	print("      chain: %s" % ", ".join(order))
	ck(order.has("companion"), "the companion is drawn at all")
	ck(order.has("monster"), "monsters are drawn at all")
	if order.has("companion") and order.has("monster"):
		var ci: int = order.find("companion")
		# EVERY server-placed entity must be decided before the companion is.
		for real in ["npc", "monster", "trap", "item"]:
			var ri: int = order.find(real)
			ck(ri >= 0 and ri < ci,
				"'%s' is resolved BEFORE the companion (server-placed beats phantom)" % real)
		ck(order.find("player") < ci, "the player still outranks the companion")

	print("\n--- 2. light does not depend on what is standing on the cell ---")
	var src := FileAccess.get_file_as_string(CLIENT)
	var lines := src.split("\n")
	var a := -1
	var b := -1
	for i in range(lines.size()):
		if lines[i].begins_with("func _render_dungeon_grid"):
			a = i
		elif a >= 0 and lines[i].begins_with("func ") and i > a:
			b = i
			break
	# The gather must sit at the SAME indent as the player/companion decision, not nested inside
	# the branch that draws bare floor. Indent is the whole point, so indent is what is measured.
	var gather_indent := -1
	var decide_indent := -1
	for i in range(a, b):
		var raw: String = lines[i]
		var t: String = raw.strip_edges()
		if t == "_lights.append(Vector2i(x, y))" and gather_indent < 0:
			gather_indent = raw.length() - raw.lstrip("\t").length()
		if t.begins_with("if x == player_x") and decide_indent < 0:
			decide_indent = raw.length() - raw.lstrip("\t").length()
	print("      gather at %d tabs, cell decision at %d tabs" % [gather_indent, decide_indent])
	ck(gather_indent > 0 and gather_indent == decide_indent + 1,
		"light is gathered beside the cell decision, not inside the empty-floor branch")

	print("\n--- 3. a knocked-out companion is not on the floor (the real function) ---")
	var C = load(CLIENT)
	var c = C.new()
	# the follower test reads exactly three things; give it all three.
	c.set("_dungeon_prev_pos", Vector2i(4, 5))
	c.set("_dungeon_last_pos", Vector2i(5, 5))

	c.set("character_data", {"active_companion": {"monster_type": "Wolf", "combat_hp": 30}})
	ck(c._dungeon_companion_at(4, 5), "a HEALTHY companion stands in the player's footsteps")
	ck(not c._dungeon_companion_at(9, 9), "and only there")

	c.set("character_data", {"active_companion": {"monster_type": "Wolf", "combat_hp": 0}})
	ck(not c._dungeon_companion_at(4, 5), "a KNOCKED-OUT companion occupies no cell")

	c.set("character_data", {"active_companion": {"monster_type": "Wolf", "combat_hp": -12}})
	ck(not c._dungeon_companion_at(4, 5), "...including overkill, where HP went below zero")

	# Never fought: the server lazy-initialises combat_hp at full on first read, so an absent
	# field means FULL, not dead. Reading it as 0 would delete the companion from the map of
	# every player who has not yet been in a fight.
	c.set("character_data", {"active_companion": {"monster_type": "Wolf"}})
	ck(c._dungeon_companion_at(4, 5), "no combat_hp field yet = never fought = alive, not dead")

	c.set("character_data", {})
	ck(not c._dungeon_companion_at(4, 5), "no companion at all draws nothing")
	c.free()

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
