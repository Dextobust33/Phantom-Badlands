extends SceneTree
## Playtest sheet item 7 (owner decisions 2026-10-14):
##  * a Settings toggle for the single-item salvage prompt, default ON
##  * auto-salvage never eats an item that would beat (or fill) what you wear
const CharacterScript = preload("res://shared/character.gd")
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _init() -> void:
	var worn := {"weapon": {"rarity": "uncommon", "level": 20}, "armor": {"rarity": "rare", "level": 20}}
	var better := {"type": "weapon_sword", "rarity": "rare", "level": 25, "name": "Better Sword"}
	var same := {"type": "weapon_sword", "rarity": "uncommon", "level": 20, "name": "Same Sword"}
	var worse := {"type": "weapon_sword", "rarity": "common", "level": 18, "name": "Worse Sword"}
	var higher_rarity_lower_level := {"type": "weapon_sword", "rarity": "epic", "level": 5, "name": "Weak Epic"}
	var empty_slot := {"type": "helm_iron", "rarity": "common", "level": 3, "name": "First Helm"}
	ck(CharacterScript.is_probable_upgrade(better, worn), "better rarity at >= level is an upgrade")
	ck(not CharacterScript.is_probable_upgrade(same, worn), "equal rarity is not")
	ck(not CharacterScript.is_probable_upgrade(worse, worn), "worse is not")
	ck(not CharacterScript.is_probable_upgrade(higher_rarity_lower_level, worn), "a higher rarity at a much lower level is not assumed better")
	ck(CharacterScript.is_probable_upgrade(empty_slot, worn), "an item for an EMPTY slot counts as an upgrade")
	ck(not CharacterScript.is_probable_upgrade({"type": "potion", "rarity": "common"}, worn), "a non-gear item is never one")
	# The destructive rule itself, max rarity 3 = up to rare.
	ck(not CharacterScript.would_auto_salvage(better, true, 3, [], false, worn), "auto-salvage SPARES the upgrade")
	ck(not CharacterScript.would_auto_salvage(empty_slot, true, 3, [], false, worn), "...and the first item for an empty slot")
	ck(CharacterScript.would_auto_salvage(worse, true, 3, [], false, worn), "...but still eats the worse one (control)")
	ck(CharacterScript.would_auto_salvage(same, true, 3, [], false, worn), "...and the equal one")
	ck(CharacterScript.would_auto_salvage(better, true, 3, [], false), "with no equipped info it behaves exactly as before")
	# Source: the make-room path asks the same rule, as a statement.
	var sv := FileAccess.get_file_as_string("res://server/server.gd")
	var i := sv.find("func _try_auto_salvage(")
	var body := sv.substr(i, sv.find("\nfunc ", i + 10) - i)
	ck(body.find("\t\tif Character.is_probable_upgrade(item, character.equipped):\n\t\t\tcontinue") >= 0, "make-room skips upgrades (statement-level)")
	# The client toggle.
	get_root().set_content_scale_size(Vector2i(1920, 1080))
	get_root().size = Vector2i(1920, 1080)
	var c = (load("res://client/client.tscn") as PackedScene).instantiate()
	get_root().add_child(c)
	for _i in range(8):
		await process_frame
	ck(c.confirm_single_salvage == true, "the prompt defaults ON")
	c.inventory_mode = true
	c.character_data = {"inventory": [{"type": "weapon_sword", "name": "Junk", "rarity": "common"}]}
	c._panel_salvage_item(0, {"name": "Junk", "rarity": "common"})
	var dlg = c.get_node_or_null("/root/ClientScene/SalvageSingleConfirm")
	if dlg == null:
		dlg = c.find_child("SalvageSingleConfirm", true, false)
	ck(dlg != null and dlg.visible, "ON: the confirmation dialog opens")
	if dlg != null:
		dlg.hide()
	c._panel_salvage_index = -1
	c.execute_local_action("settings_toggle_salvage_confirm")
	ck(c.confirm_single_salvage == false, "the Settings button turns it OFF")
	c._panel_salvage_item(0, {"name": "Junk", "rarity": "common"})
	ck(dlg == null or not dlg.visible, "OFF: no dialog, it goes straight through")
	ck(c._panel_salvage_index == -1 and c.awaiting_item_use_result, "...and the request was sent (index consumed, result awaited)")
	c.execute_local_action("settings_toggle_salvage_confirm")
	ck(c.confirm_single_salvage == true, "it turns back ON")
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
