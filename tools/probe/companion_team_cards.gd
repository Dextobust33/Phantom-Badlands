extends SceneTree
## Item 14 S4: a COLUMN COMPANION is drawn on the combat scene's right-hand party card with the human half hidden.
## Run:  godot --headless --path . --script res://tools/probe/companion_team_cards.gd
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _init() -> void:
	var panel = load("res://client/combat_scene_panel.gd").new()
	get_root().add_child(panel)
	await process_frame
	await process_frame
	var comp := {"name": "Golem Fragment [Tank]", "monster_type": "Iron Golem", "combat_hp": 80, "max_hp": 200, "variant_color": "#FFFFFF", "variant_pattern": "solid", "border_tier": 0}
	var human := {"name": "Kira", "current_hp": 100, "max_hp": 100, "companion": {"name": "Her Wolf", "monster_type": "Wolf", "combat_hp": 10, "max_hp": 20}}
	panel.set_party_members([{"name": "", "companion_only": true, "companion": comp, "current_hp": 1, "max_hp": 1}, human])
	var cards: Array = panel._party_member_cards
	ck(cards.size() == 2 and cards[0].visible and cards[1].visible, "two cards are shown (%d)" % cards.size())
	var c0: Control = cards[0]
	ck(not (c0.get_meta("name_lbl") as Control).get_parent().visible, "the companion-only card hides the human's stats")
	ck(not (c0.get_meta("sprite") as Control).get_parent().visible, "...and the human's portrait")
	ck((c0.get_meta("comp_name") as Label).text == "Golem Fragment [Tank]" and (c0.get_meta("comp_name") as Control).visible, "...and shows the companion's name with its role")
	ck(int((c0.get_meta("comp_hp") as ProgressBar).value) == 80 and int((c0.get_meta("comp_hp") as ProgressBar).max_value) == 200, "...and its own HP bar (80/200)")
	var c1: Control = cards[1]
	ck((c1.get_meta("name_lbl") as Control).get_parent().visible, "a real party member's card still shows the human half")
	# the card is REUSED for a human next round: the human half must come back
	panel.set_party_members([human])
	ck((cards[0].get_meta("name_lbl") as Control).get_parent().visible, "reusing the card for a human brings the human half back")
	panel.set_party_members([])
	ck(not panel._party_column.visible, "no cards -> the column is hidden (solo play unchanged)")
	print("")
	print(("PASS - companion_team_cards" if fails == 0 else "FAIL - companion_team_cards: %d check(s)" % fails))
	quit(1 if fails > 0 else 0)
