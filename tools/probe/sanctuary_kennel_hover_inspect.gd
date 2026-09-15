extends SceneTree
## The Sanctuary's Companion Stable shows a kennel companion's ASCII art on hover and can inspect it.
##
## Owner 2026-09-15: *"When in the sanctuary we need to make it where you can hover your companions in
## your Companion Kennel to see their ASCII art. Also, players should be able to inspect their
## companions in their companion kennel."* The Sanctuary's K tile opens sanctuary_stable_panel.gd,
## whose kennel rows had neither. Drives the real panel with the real client builders.

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node
	for ch in node.get_children():
		var b := _find_button(ch, text)
		if b != null:
			return b
	return null


func _init() -> void:
	var client = load("res://client/client.gd").new()
	var panel = load("res://client/sanctuary_stable_panel.gd").new()
	panel.client_ref = client
	get_root().add_child(panel)
	await process_frame
	var wolf := {"id": "k1", "name": "Wolf Pup", "monster_type": "Wolf", "tier": 1, "sub_tier": 2, "level": 7,
		"variant": "Normal", "variant_color": "#AAAAAA", "variant_pattern": "solid", "border_tier": 0, "xp": 0,
		"bonuses": {}}
	var art: Array = client._get_companion_art_lines("Wolf", "Wolf Pup")
	ck(not art.is_empty(), "control: a Wolf has ASCII art to show (%d lines)" % art.size())
	panel.show_with_data({"kennel": [wolf], "kennel_capacity": 30, "registered_count": 0, "registered_capacity": 2})
	await process_frame

	var row: Control = panel._kennel_list.get_child(0) if panel._kennel_list.get_child_count() > 0 else null
	ck(row != null, "the kennel lists the companion")
	if row != null:
		row.mouse_entered.emit()
		await process_frame
		await process_frame
		var tip: String = panel._tooltip_label.text if panel._tooltip_label else ""
		ck(panel._tooltip.visible, "hovering the row shows a card")
		ck(tip.contains(String(art[art.size() / 2]).strip_edges().substr(0, 6)) or tip.contains("[font_size="),
			"and the card carries the ASCII art")
		row.mouse_exited.emit()
		ck(not panel._tooltip.visible, "leaving the row hides it")

		var insp := _find_button(row, "Inspect")
		ck(insp != null, "the row has an Inspect button")
		if insp != null:
			insp.pressed.emit()
			await process_frame
			ck(panel._inspect_view.visible and not panel._kennel_view.visible, "Inspect replaces the list with the inspect page")
			ck(String(panel._inspect_text.text).contains("Wolf Pup"), "the page is that companion's inspect text")
			var back := _find_button(panel._inspect_view, "< Back to the Kennel")
			if back != null:
				back.pressed.emit()
			await process_frame
			ck(panel._kennel_view.visible and not panel._inspect_view.visible, "Back returns to the kennel list")

	panel.queue_free()
	client.free()
	print("RESULT: %s (%d failing)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
