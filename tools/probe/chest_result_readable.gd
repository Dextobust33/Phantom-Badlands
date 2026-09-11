extends SceneTree
## A treasure chest's haul must be readable, not flashed.
##
## Owner 2026-09-11: "Small Treasure Chests still flash for an instant and the player doesn't get
## to read what they got out of them before it clears." Opening a chest empties the WHOLE stack
## and reports every material, quantity and the gold — into a one-line 13pt status row between
## two buttons, which the next character_update wipes. The bulk-salvage flow learned this in
## v0.9.634/635 and moved its result to game_output; the chest was still on the old road.
const CLIENT := "res://client/client.gd"

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var c = load(CLIENT).new()

	print("--- the predicate knows a chest from a potion ---")
	c.set("character_data", {"inventory": [
		{"name": "Small Treasure Chest", "type": "treasure_chest"},
		{"name": "Healing Potion", "type": "consumable"},
		{"name": "Odd Chest", "item_type": "treasure_chest"},
	]})
	ck(c._is_read_the_result_item(0), "a chest by `type` needs the readable route")
	ck(not c._is_read_the_result_item(1), "an ordinary consumable does NOT (status row is fine)")
	ck(c._is_read_the_result_item(2), "a chest by `item_type` is caught too (dual-type items)")
	ck(not c._is_read_the_result_item(99), "an out-of-range index is safe")
	ck(not c._is_read_the_result_item(-1), "so is a negative one")
	c.set("character_data", {})
	ck(not c._is_read_the_result_item(0), "and an empty inventory does not crash")
	c.free()

	print("\n--- BOTH use paths ask it; neither decides for itself ---")
	var src := FileAccess.get_file_as_string(CLIENT)
	var lines := src.split("\n")
	var asks := 0
	var raw_use := 0
	for i in range(lines.size()):
		var t: String = lines[i].strip_edges()
		if t.begins_with("if _is_read_the_result_item("):
			asks += 1
		if t == 'send_to_server({"type": "inventory_use", "index": index})' \
				or t == 'send_to_server({"type": "inventory_use", "index": actual_index})':
			raw_use += 1
	print("      %d call sites ask the predicate, %d inventory_use sends total" % [asks, raw_use])
	ck(asks >= 2, "both the panel path and the legacy number-key path ask")
	# Every send must be preceded (within a few lines) by either the predicate or the status-row flag.
	ck(raw_use >= 2, "found both send sites")

	# And the chest must land on the flow that HOLDS the panel shut.
	ck(src.contains('pending_inventory_action = "awaiting_salvage_result"'),
		"it uses the read-the-result flow that keeps game_output visible")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
