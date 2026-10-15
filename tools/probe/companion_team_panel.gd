extends SceneTree
## Item 14 S4: the Companions panel shows the TEAM (column companions) with role, HP and a per-companion
## Tactics button + Remove, says when slots are locked, and its buttons emit the signals the client sends.
## UI pixels are not reachable headless; this proves the nodes exist, carry the right text, and are wired.
## Run:  godot --headless --path . --script res://tools/probe/companion_team_panel.gd
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _all_text(n: Node) -> String:
	var t := ""
	if n is RichTextLabel:
		t += (n as RichTextLabel).text
	if n is Button:
		t += "[btn:%s]" % (n as Button).text
	for ch in n.get_children():
		t += _all_text(ch)
	return t

func _init() -> void:
	var fake := Node.new()
	var gs := GDScript.new()
	gs.source_code = "extends Node\nvar character_data = {}\nfunc _get_variant_rarity_info(v):\n\treturn {\"color\": \"#FFFFFF\", \"tier\": \"R1\"}\n"
	gs.reload()
	fake.set_script(gs)
	get_root().add_child(fake)
	var panel = load("res://client/companions_panel.gd").new()
	get_root().add_child(panel)
	await process_frame
	panel.client_ref = fake
	var wolf := {"id": "a", "name": "Wolf Pup", "monster_type": "Wolf", "level": 20, "tier": 1, "sub_tier": 1, "variant": "Normal", "bonuses": {"attack": 3, "aggro": 25}}
	var golem := {"id": "g", "name": "Golem Fragment", "monster_type": "Iron Golem", "level": 20, "tier": 6, "sub_tier": 1, "variant": "Normal", "bonuses": {"defense": 15, "aggro": 65}, "combat_hp": 80, "combat_max_hp": 200, "ko": false, "tactics": "protect"}
	var phoenix := {"id": "p", "name": "Phoenix Chick", "monster_type": "Phoenix", "level": 20, "tier": 6, "sub_tier": 1, "variant": "Normal", "bonuses": {"attack": 8, "aggro": 35}, "combat_hp": 0, "combat_max_hp": 150, "ko": true}

	print("--- locked ---")
	fake.character_data = {"companion_slots": 0, "companion_team": [], "companion_party": []}
	panel.populate_companions([wolf, golem, phoenix], wolf, "level", false)
	var t0: String = _all_text(panel._team_vbox)
	ck(t0.find("unlock at character level 10") >= 0, "with no slots it says when they unlock")

	print("--- two on the team ---")
	fake.character_data = {"companion_slots": 3, "companion_team": [golem, phoenix], "companion_party": ["g", "p"]}
	panel.populate_companions([wolf, golem, phoenix], wolf, "level", false)
	await process_frame
	var t1: String = _all_text(panel._team_vbox)
	ck(t1.find("2 / 3 slots") >= 0, "header counts slots (2 / 3)")
	ck(t1.find("Golem Fragment") >= 0 and t1.find("Tank") >= 0, "the Golem row names its role (Tank)")
	ck(t1.find("Phoenix Chick") >= 0 and t1.find("Healer") >= 0, "the Phoenix row names its role (Healer)")
	ck(t1.find("HP 80 / 200") >= 0, "HP is shown")
	ck(t1.find("KNOCKED OUT") >= 0, "a knocked-out member says so")
	ck(t1.find("[btn:Tactics: Protect]") >= 0 and t1.find("[btn:Remove]") >= 0, "per-companion Tactics and Remove buttons exist")

	print("--- the buttons send what the client expects ---")
	var got: Array = []
	panel.companion_tactics_requested.connect(func(t, id): got.append(["tactics", t, id]))
	panel.companion_unfield_requested.connect(func(id): got.append(["unfield", id]))
	var buttons: Array = []
	var stack: Array = [panel._team_vbox]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button:
			buttons.append(n)
		for ch in n.get_children():
			stack.append(ch)
	for b in buttons:
		if b.text.begins_with("Tactics: Protect") or b.text == "Remove":
			b.pressed.emit()
	ck(got.has(["tactics", "support", "g"]), "Golem's Tactics cycles Protect -> Support and names the companion (%s)" % str(got))
	ck(got.has(["unfield", "g"]) and got.has(["unfield", "p"]), "Remove names its companion")

	print("")
	print(("PASS - companion_team_panel" if fails == 0 else "FAIL - companion_team_panel: %d check(s)" % fails))
	quit(1 if fails > 0 else 0)
