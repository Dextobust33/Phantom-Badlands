extends SceneTree
## A second item in one round costs your guard — and the monster must SAY it took the swing.
##
## Owner 2026-09-11: "not sure if using two items is working right? Didn't seem like the monster
## did anything?" It did: HP fell 91 in the reproduction while only two messages came back, and
## neither was the monster's.
##
## Cause: `process_monster_turn` has a dozen return points in TWO shapes — most {"message": "a\nb"}
## and a couple {"messages": [...]}. The item branch read only "messages", found nothing, and
## appended nothing. CLAUDE.md Pitfall #9, word for word.
const CM := preload("res://shared/combat_manager.gd")
const MD := preload("res://shared/monster_database.gd")
const CH := preload("res://shared/character.gd")
const DT := preload("res://shared/drop_tables.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	print("--- the reader understands both shapes ---")
	ck(CM.monster_turn_lines({"message": "one"}).size() == 1, "singular 'message' yields its line")
	ck(CM.monster_turn_lines({"message": "a\nb\nc"}).size() == 3, "a newline-joined message splits")
	ck(CM.monster_turn_lines({"messages": ["x", "y"]}).size() == 2, "plural 'messages' yields its lines")
	ck(CM.monster_turn_lines({}).is_empty(), "an empty result yields nothing")
	ck(CM.monster_turn_lines({"message": ""}).is_empty(), "an empty string yields nothing, not a blank line")
	ck(CM.monster_turn_lines({"messages": [], "message": "solo"}).size() == 1,
		"an empty array alongside a real message still yields the message")

	print("\n--- and a second item actually reports the monster's turn ---")
	var cm = CM.new()
	cm.monster_database = MD.new()
	cm.drop_tables = DT.new()
	var f := FileAccess.open("res://server/balance_config.json", FileAccess.READ)
	if f != null:
		var j := JSON.new()
		if j.parse(f.get_as_text()) == OK:
			cm.balance_config = j.data
		f.close()

	var ch = CH.new()
	ch.name = "Probe"
	ch.class_type = "Barbarian"
	ch.level = 8
	ch.max_hp = 329
	ch.current_hp = 300
	for i in range(3):
		ch.inventory.append({"name": "Test Potion", "type": "health_potion", "tier": 3,
			"quantity": 1, "is_consumable": true})
	var mon = cm.monster_database.generate_monster_by_name("Giant Spider", 8)
	cm.start_combat(1, ch, mon)

	var first: Array = cm.process_use_item(1, 0).get("messages", [])
	ck(first.size() >= 2, "the FIRST item is a free action (%d lines)" % first.size())
	var joined_first := " ".join(first)
	ck(joined_first.contains("Free action"), "...and says so")

	var second: Array = cm.process_use_item(1, 0).get("messages", [])
	var joined := " ".join(second)
	print("      second item returned %d lines" % second.size())
	for m in second:
		var t := String(m)
		if t.length() > 84:
			t = t.substr(0, 84)
		print("        | %s" % t)
	ck(joined.contains("seizes the moment"), "the second item costs the guard")
	# The monster's own line must be there. It names the monster whatever it did — attack, miss,
	# charm, last stand — so the assertion is on the NAME, not on one phrasing.
	ck(second.size() > first.size(),
		"the second item returns MORE lines than the first (the monster's turn is included)")
	ck(joined.contains(String(mon.name)),
		"the monster is named in the output, so the player can see what it did")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
