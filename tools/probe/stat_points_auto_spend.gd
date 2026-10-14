extends SceneTree
## Playtest sheet item 29 (owner decision 2026-10-14): auto-apply stat points to the class preset,
## with an opt-out in the Stats panel; points already banked are never touched.
const CharacterScript = preload("res://shared/character.gd")
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

class QuietServer extends "res://server/server.gd":
	func save_character(_p) -> void:
		pass
class StubConn:
	func get_status() -> int:
		return 0

func _hero(klass: String):
	var c = CharacterScript.new()
	c.initialize("Hero", klass, "Human")
	return c

func _init() -> void:
	ck(CharacterScript.preset_stat_for_class("Wizard") == "intelligence" and CharacterScript.preset_stat_for_class("Ninja") == "dexterity" and CharacterScript.preset_stat_for_class("Fighter") == "strength", "presets: mage INT, trickster DEX, warrior STR")
	# ON (default): a level's point is spent on the preset.
	var w = _hero("Wizard")
	ck(w.auto_spend_stats == true, "auto-spend defaults ON")
	var int0: int = w.intelligence
	var r = w.add_experience(w.experience_to_next_level)
	ck(bool(r.get("leveled_up", false)), "the hero levelled")
	ck(w.unspent_stat_points == 0, "ON: the new point is not left in the bank (%d)" % w.unspent_stat_points)
	ck(w.intelligence >= int0 + 1, "...it went to INT (%d -> %d)" % [int0, w.intelligence])
	# Points banked BEFORE are never touched.
	var f = _hero("Fighter")
	f.unspent_stat_points = 5
	var str0: int = f.strength
	f.add_experience(f.experience_to_next_level)
	ck(f.unspent_stat_points == 5, "ON: points already banked stay banked (%d)" % f.unspent_stat_points)
	ck(f.strength >= str0 + 1, "...only the new one was spent")
	# OFF: the point waits.
	var g = _hero("Fighter")
	g.auto_spend_stats = false
	g.add_experience(g.experience_to_next_level)
	ck(g.unspent_stat_points == 1, "OFF: the point is banked (%d)" % g.unspent_stat_points)
	# Persistence, and old saves without the key default to ON.
	var d: Dictionary = g.to_dict()
	var g2 = CharacterScript.new()
	g2.from_dict(d)
	ck(g2.auto_spend_stats == false, "OFF survives a save round trip")
	d.erase("auto_spend_stats")
	var g3 = CharacterScript.new()
	g3.from_dict(d)
	ck(g3.auto_spend_stats == true, "a save from before this shipped loads as ON")
	# Server toggle.
	var srv = QuietServer.new()
	var h = _hero("Ranger")
	srv.characters = {1: h}
	srv.peers = {1: {"authenticated": true, "account_id": "a", "connection": StubConn.new()}}
	srv.handle_set_auto_spend_stats(1, {"enabled": false})
	ck(h.auto_spend_stats == false, "server: the toggle turns it OFF")
	srv.handle_set_auto_spend_stats(1, {"enabled": true})
	ck(h.auto_spend_stats == true, "server: ...and back ON")
	# The panel: a real button, and pressing it emits.
	var panel = load("res://client/stats_panel.gd").new()
	get_root().add_child(panel)
	await process_frame
	var got: Array = []
	panel.auto_spend_toggled.connect(func(e): got.append(e))
	panel.open(5, 0, 100, {"strength": 10, "constitution": 10, "dexterity": 10, "intelligence": 10, "wisdom": 10, "wits": 10}, 0, "Wizard")
	ck(panel._auto_btn != null and panel._auto_btn.text.find("INT") >= 0, "the panel shows the preset stat (%s)" % (panel._auto_btn.text if panel._auto_btn else "none"))
	panel._auto_btn.pressed.emit()
	ck(got == [false], "pressing the button emits the new state (%s)" % str(got))
	ck(panel._auto_btn.text.find("OFF") >= 0, "and the label says OFF")
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
