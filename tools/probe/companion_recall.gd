extends SceneTree
## Recall: a checked-out Sanctuary companion can be pulled back to its slot from character select.
##
## Owner 2026-09-11: *"should we make a way for players to be able to send a checked out companion
## back to the sanctuary?"* Decided: a Recall button on the Sanctuary companions page. The slot
## must receive the companion's LIVE state (level, XP) and the holder must be left holding nothing,
## or the next login carries a companion the house already lists as home - two copies of one pet.
##
## The strip runs on the REAL helper against real Character objects. The wiring (route, refusal of
## a live holder, the client's button and message) is checked in source because it needs a peer.
const SERVER := preload("res://server/server.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _held(slot: int, with_house_slot: bool = true) -> Character:
	var ch := Character.new()
	ch.name = "Holder"
	var comp := {"id": "pet-1", "name": "Ember", "monster_type": "wolf", "level": 7, "experience": 340}
	if with_house_slot:
		comp["house_slot"] = slot
	ch.active_companion = comp.duplicate(true)
	ch.collected_companions = [comp.duplicate(true), {"id": "pet-2", "name": "Other", "level": 2}]
	ch.using_registered_companion = true
	ch.registered_companion_slot = slot
	return ch


func _init() -> void:
	var s = SERVER.new()

	print("--- the live state goes home and the holder is left with nothing ---")
	var ch := _held(1)
	var state: Dictionary = s._recall_companion_from_character(ch, 1)
	ck(state.get("name", "") == "Ember" and int(state.get("level", 0)) == 7 and int(state.get("experience", 0)) == 340,
		"the returned state is the companion as it is NOW (L7, 340xp), not the checkout copy")
	ck(not state.has("house_slot") and not state.has("checked_out_by") and not state.has("checkout_time"),
		"checkout metadata is stripped before it is written back to the slot")
	ck(ch.active_companion.is_empty(), "active_companion cleared")
	ck(not ch.using_registered_companion and ch.registered_companion_slot == -1, "registration flags reset")
	ck(ch.collected_companions.size() == 1 and ch.collected_companions[0].get("id", "") == "pet-2",
		"the roster mirror is removed and the unrelated companion is kept")

	print("\n--- a legacy save with no house_slot on the roster entry is matched by id ---")
	ch = _held(2, false)
	state = s._recall_companion_from_character(ch, 2)
	ck(state.get("name", "") == "Ember", "recalled through the registered_companion_slot flag")
	ck(ch.collected_companions.size() == 1, "...and the roster copy went with it")

	print("\n--- the wrong slot touches nothing ---")
	ch = _held(1)
	state = s._recall_companion_from_character(ch, 3)
	ck(state.is_empty(), "returns {} for a slot the character does not hold")
	ck(not ch.active_companion.is_empty() and ch.collected_companions.size() == 2 and ch.using_registered_companion,
		"character untouched")

	print("\n--- a roster-only mirror (not active) is still recalled ---")
	ch = _held(1)
	ch.active_companion = {}
	ch.using_registered_companion = false
	ch.registered_companion_slot = -1
	state = s._recall_companion_from_character(ch, 1)
	ck(state.get("name", "") == "Ember" and ch.collected_companions.size() == 1, "removed from the roster, state returned")
	s.free()

	print("\n--- wiring ---")
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	ck(srv.find('"house_recall_companion":\n\t\t\thandle_house_recall_companion(peer_id, message)') >= 0,
		"server routes house_recall_companion")
	var h0 := srv.find("func handle_house_recall_companion(")
	var h1 := srv.find("\nfunc ", h0 + 1)
	var body := srv.substr(h0, h1 - h0)
	ck(body.find("is logged in right now") >= 0 and body.find("characters.keys()") >= 0,
		"the handler refuses while the holder is logged in")
	ck(body.find("saved_combat_state") >= 0, "the handler refuses a holder saved mid-fight")
	ck(body.find("_recall_companion_from_character(") >= 0 and body.find("return_companion_to_house(") >= 0,
		"the handler strips through the shared helper and returns through the shared persistence path")
	ck(body.find("_send_house_update(peer_id)") >= 0, "the Sanctuary screen is refreshed afterwards")
	var cli := FileAccess.get_file_as_string("res://client/client.gd")
	ck(cli.find('"label": "Recall", "action_type": "local", "action_data": "house_recall_start"') >= 0,
		"the companions page has a Recall button")
	ck(cli.find('send_to_server({"type": "house_recall_companion", "slot": house_recall_companion_slot})') >= 0,
		"confirm sends the slot to the server")
	ck(cli.find('pending_house_action == "recall_select"') >= 0 and cli.find('"houserecall_%d_pressed"') >= 0,
		"keys 1-5 pick in recall_select with the consume guard (pitfall #10)")
	ck(cli.find("Recall a companion a character is holding back to its slot") >= 0, "the help page says it exists")

	print("\n[RECALL] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
