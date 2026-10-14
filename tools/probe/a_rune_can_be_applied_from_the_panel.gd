extends SceneTree
## Playtest sheet item 14: "runes can't be applied".
## The inventory PANEL's Use sent a bare `inventory_use` for a rune - the server has no slot to put
## it in. The choose-a-slot flow existed only in the old text-mode inventory, and even there the
## slot choice was number-keys behind a DISABLED "1-9 Select" label. This drives the real client:
## Use on a rune -> slot buttons exist and are enabled -> clicking one sends it and holds the result.
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _init() -> void:
	get_root().set_content_scale_size(Vector2i(1920, 1080))
	get_root().size = Vector2i(1920, 1080)
	var c = (load("res://client/client.tscn") as PackedScene).instantiate()
	get_root().add_child(c)
	for _i in range(8):
		await process_frame
	c.character_data = {
		"name": "Probe", "level": 20, "class": "Fighter",
		"inventory": [
			{"type": "potion", "name": "Potion", "is_consumable": true, "quantity": 1},
			{"type": "rune", "name": "Rune of Might", "target_slot": "weapon,ring", "rune_stat": "attack_bonus", "rune_cap": 8, "rarity": "rare"},
		],
		"equipped": {"weapon": {"name": "Rusty Sword", "rarity": "common", "affixes": {"attack_bonus": 3}}, "ring": {"name": "Tin Ring", "rarity": "common"}},
	}
	c.inventory_mode = true
	c.in_combat = false
	c._panel_use_item(1)
	ck(c.pending_inventory_action == "rune_apply", "Use on a rune enters the apply flow (state: %s)" % c.pending_inventory_action)
	ck(c.rune_apply_index == 1, "it remembers WHICH rune (index %d)" % c.rune_apply_index)
	var slots: Array = c.get_meta("rune_slot_list", [])
	ck(slots == ["weapon", "ring"], "it lists the equipped slots the rune fits: %s" % str(slots))
	c.update_action_bar()
	var labels: Array = []
	var enabled_local := 0
	for a in c.current_actions:
		if String(a.get("action_data", "")).begins_with("rune_apply_slot_") and bool(a.get("enabled", false)) and String(a.get("action_type", "")) == "local":
			enabled_local += 1
			labels.append(String(a.get("label", "")))
	ck(enabled_local == 2, "one CLICKABLE button per slot: %s" % str(labels))
	c.execute_local_action("rune_apply_slot_0")
	ck(c.pending_inventory_action == "awaiting_salvage_result", "clicking holds the result for reading (state: %s)" % c.pending_inventory_action)
	ck(c.rune_apply_index == -1 and not c.rune_apply_mode, "and the apply state is cleared")
	# The plain potion must still go the ordinary way.
	c.pending_inventory_action = ""
	c._panel_use_item(0)
	ck(c.pending_inventory_action != "rune_apply", "a potion is not diverted into the rune flow")
	# Statement-level source check: the helper really sends use_rune (the probe has no connection).
	var src := FileAccess.get_file_as_string("res://client/client.gd")
	var i := src.find("func _apply_rune_to_slot_choice(")
	var body := src.substr(i, src.find("\nfunc ", i + 10) - i)
	ck(body.find("\tsend_to_server({\"type\": \"use_rune\", \"rune_index\": idx, \"target_slot\": target_slot})") >= 0, "the helper sends use_rune with the rune and the slot")
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
