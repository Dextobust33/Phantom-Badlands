extends SceneTree
## Listing an egg says what it is worth BEFORE you sell it, and pays exactly that.
##
## Owner 2026-09-15: listing an egg on the market *"doesn't tell the player what they got or will
## get for it. It should also give the player a confirmation that it worked."*
##
## Two faults, measured here:
##  1. the picker listed eggs by name and tier only - nothing said what any of them would fetch;
##  2. on success the picker was rebuilt from the client's own copy of the character, which still
##     held the egg just sold, so the list visibly did not change and it read as if nothing had
##     happened. `refresh_picker()` existed and had no callers at all.
##
## The quote and the payout now come from ONE server helper, which is the property worth guarding:
## a preview computed separately is a preview that will one day lie.
const ServerScript = preload("res://server/server.gd")

class RecServer extends "res://server/server.gd":
	var sent: Array = []
	func send_to_peer(peer_id: int, message: Dictionary):
		sent.append(message)
		super.send_to_peer(peer_id, message)
	func last_of(t: String) -> Dictionary:
		for i in range(sent.size() - 1, -1, -1):
			if String(sent[i].get("type", "")) == t:
				return sent[i]
		return {}

const PEER := 1

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var sv = RecServer.new()
	get_root().add_child(sv)
	await process_frame
	await process_frame
	sv.set_process(false)
	sv.set_physics_process(false)
	var made: Dictionary = sv.persistence.create_account("eg%d" % (Time.get_ticks_usec() % 100000), "probe-password")
	var acct := String(made.get("account_id", ""))
	sv.peers[PEER] = {"authenticated": true, "account_id": acct, "character_name": "",
		"connection": StreamPeerTCP.new()}
	var nm := "Eggy"
	var u: int = Time.get_ticks_usec()
	for i in range(4):
		nm += char(97 + (u % 26))
		u /= 26
	# HALFLING on purpose: they carry a +15% market bonus, so a quote that forgot to apply
	# the bonus would read differently from the payout. On a race with no bonus the check that the
	# two agree cannot fail, which would make it decoration.
	sv.handle_create_character(PEER, {"name": nm, "class": "Fighter", "race": "Halfling"})
	await process_frame
	var ch = sv.characters[PEER]

	# Three eggs worth visibly different amounts.
	ch.incubating_eggs = [
		{"monster_type": "Wolf", "companion_name": "Wolf", "tier": 1, "sub_tier": 1,
			"variant": "Normal", "variant_color": "#AAAAAA", "progress": 0},
		{"monster_type": "Lich", "companion_name": "Lich", "tier": 6, "sub_tier": 3,
			"variant": "Gilded", "variant_color": "#FFD700", "progress": 0},
		{"monster_type": "Goblin", "companion_name": "Goblin", "tier": 1, "sub_tier": 2,
			"variant": "Venomous", "variant_color": "#66FF66", "progress": 0},
	]
	sv.at_trading_post[PEER] = {"post_id": "post_probe_0_0", "name": "Probe Post"}

	# --- what the picker is told ---
	sv.handle_market_egg_values(PEER, {})
	var vals: Array = sv.last_of("market_egg_values").get("valors", [])
	print("  quoted valors: %s" % str(vals))
	ck(vals.size() == ch.incubating_eggs.size(), "one number per egg (%d for %d eggs)" % [vals.size(), ch.incubating_eggs.size()])
	var raw_first: int = sv.drop_tables.calculate_egg_valor({"tier": 1, "sub_tier": 1, "variant": "Normal"})
	print("  this Halfling's market bonus is real: raw %d -> quoted %d" % [raw_first, int(vals[0])])
	ck(int(vals[0]) > raw_first, "the quote INCLUDES the player's market bonus (or the agreement below proves nothing)")
	var all_positive := true
	for v in vals:
		if int(v) <= 0:
			all_positive = false
	ck(all_positive, "every egg is quoted a real number")
	ck(vals.size() >= 2 and int(vals[1]) > int(vals[0]),
		"and the numbers differ by what the egg IS (tier 6 gilded %s vs tier 1 %s)" % [str(vals[1]), str(vals[0])])

	# --- and what it actually pays ---
	var quoted_for_first: int = int(vals[0])
	var before_valor: int = sv.persistence.get_valor(acct)
	var before_eggs: int = ch.incubating_eggs.size()
	sv.handle_market_list_egg(PEER, {"index": 0})
	var success: Dictionary = sv.last_of("market_list_success")
	ck(not success.is_empty(), "listing the first egg succeeds")
	print("  quoted %d, paid %s, named '%s'" % [quoted_for_first, str(success.get("base_valor", "?")), String(success.get("item_name", ""))])
	ck(int(success.get("base_valor", -1)) == quoted_for_first,
		"the payout is EXACTLY what the picker quoted - one sum, not two")
	ck(String(success.get("item_name", "")) != "", "and the confirmation names the egg")
	ck(ch.incubating_eggs.size() == before_eggs - 1, "the egg really left the incubator")
	ck(sv.persistence.get_valor(acct) == before_valor + quoted_for_first, "and the valor really arrived")

	# The quote must follow the player's market bonuses, or it becomes a lie for anyone who has one.
	var src := FileAccess.get_file_as_string("res://server/server.gd")
	ck(src.count("func _egg_listing_valor(") == 1, "one definition of an egg's listing value")
	ck(src.count("_egg_listing_valor(character, egg)") == 2, "and both the quote and the payout ask it")

	# --- the client half ---
	var csrc := FileAccess.get_file_as_string("res://client/client.gd")
	ck(csrc.count('send_to_server({"type": "market_egg_values"})') >= 4,
		"every way into the egg picker asks what the eggs are worth")
	ck(csrc.contains("_market_picker_stale"), "a listing marks the picker stale...")
	ck(csrc.contains("market_panel.open_egg_picker(character_data.get(\"incubating_eggs\", []), _market_egg_valors)"),
		"...and it is rebuilt from the server's state when it arrives")
	var psrc := FileAccess.get_file_as_string("res://client/market_panel.gd")
	ck(psrc.contains("→  %s Valor"), "the picker row prints the value")
	ck(psrc.count("func picker_mode()") == 1 and psrc.count("func get_status()") == 1,
		"the panel exposes what it is showing, so the refresh keeps the success line")

	print("RESULT: %s (%d failing)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
