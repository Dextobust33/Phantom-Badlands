extends SceneTree
## A Sanctuary checkout must never fail without saying why, and the player's pending selection
## must survive a routine `house_data` refresh.
##
## Owner 2026-09-10: "I ... Selected Checkout on my Glowing Wolf Pup (in slot 2) ... but it's not
## actually giving me the Glowing Wolf Pup."
const CLIENT := "res://client/client.gd"
const SERVER := "res://server/server.gd"

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	print("--- the selection survives a refresh, but only while it is still valid ---")
	var c = load(CLIENT).new()

	c.set("house_data", {"registered_companions": {"companions": [
		{"name": "Pup A"}, {"name": "Glowing Wolf Pup"}, {"name": "Pup C"}]}})
	c.set("house_checkout_companion_slot", 1)
	c._revalidate_pending_checkout()
	ck(int(c.get("house_checkout_companion_slot")) == 1,
		"a free slot stays selected across a house_data refresh")

	c.set("house_checkout_companion_slot", 1)
	c.set("house_data", {"registered_companions": {"companions": [
		{"name": "Pup A"}, {"name": "Glowing Wolf Pup", "checked_out_by": "Someone"}]}})
	c._revalidate_pending_checkout()
	ck(int(c.get("house_checkout_companion_slot")) == -1,
		"a slot someone else now holds is dropped, not promised")

	c.set("house_checkout_companion_slot", 5)
	c.set("house_data", {"registered_companions": {"companions": [{"name": "Pup A"}]}})
	c._revalidate_pending_checkout()
	ck(int(c.get("house_checkout_companion_slot")) == -1, "a slot that no longer exists is dropped")

	c.set("house_checkout_companion_slot", -1)
	c._revalidate_pending_checkout()
	ck(int(c.get("house_checkout_companion_slot")) == -1, "no selection stays no selection")
	c.free()

	print("\n--- the refresh handler no longer resets the selection blindly ---")
	var cs := FileAccess.get_file_as_string(CLIENT)
	var lines := cs.split("\n")
	var a := -1
	for i in range(lines.size()):
		if lines[i].strip_edges() == "\"house_data\":":
			a = i
			break
	var blind := false
	var revalidates := false
	for i in range(a, mini(a + 40, lines.size())):
		var t: String = lines[i].strip_edges()
		if t == "house_checkout_companion_slot = -1":
			blind = true
		if t == "_revalidate_pending_checkout()":
			revalidates = true
	ck(a >= 0, "found the house_data handler")
	ck(not blind, "it does NOT reset the pending checkout unconditionally")
	ck(revalidates, "it re-validates it instead")

	print("\n--- every server checkout path reports a reason ---")
	var ss := FileAccess.get_file_as_string(SERVER)
	ck(ss.contains("func _checkout_companion_for_character(account_id: String, character: Character, slot: int, char_name: String) -> String:"),
		"the helper returns a player-readable reason")
	# Every call site must DO something with that reason.
	var srv := ss.split("\n")
	var calls := 0
	var handled := 0
	for i in range(srv.size()):
		var t: String = srv[i].strip_edges()
		if t.contains("_checkout_companion_for_character(") and not t.begins_with("func "):
			calls += 1
			# assigned to a variable that is then tested, on this line or the next few
			if t.contains("= _checkout_companion_for_character("):
				for j in range(i, mini(i + 8, srv.size())):
					if srv[j].contains("_why") or srv[j].contains("_cwhy") or srv[j].contains("_swhy"):
						if srv[j].contains("!= \"\"") or srv[j].contains("== \"\""):
							handled += 1
							break
	print("      %d call sites, %d check the reason" % [calls, handled])
	ck(calls > 0 and handled == calls, "no call site throws the reason away")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
