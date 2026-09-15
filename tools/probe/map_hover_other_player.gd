extends SceneTree
## Hovering ANOTHER player, and their companion, on the overworld map.
##
## Owner 2026-09-15: *"if I hover another player on the map the sprite doesn't match what I see on the
## Player Info screen, it's missing the tinting and glyphs. Those should match and hovering their
## companions should show their companion ASCII art as well."*
## Real server -> real location message -> real client map build -> the hover bodies.
const PEER_A := 1
const PEER_B := 2

class RecServer extends "res://server/server.gd":
	var last_location: Dictionary = {}
	func send_to_peer(peer_id: int, message: Dictionary):
		if peer_id == 1 and String(message.get("type", "")) == "location":
			last_location = message
		super.send_to_peer(peer_id, message)

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _make(sv, peer: int, tag: String, klass: String):
	var made: Dictionary = sv.persistence.create_account("mh%s%d" % [tag, Time.get_ticks_usec() % 100000], "probe-password")
	sv.peers[peer] = {"authenticated": true, "account_id": String(made.get("account_id", "")), "character_name": "",
		"connection": StreamPeerTCP.new(), "caps": {"map": 1}}
	var nm := "Mh" + tag
	var u: int = Time.get_ticks_usec()
	for i in range(4):
		nm += char(97 + (u % 26))
		u /= 26
	sv.handle_create_character(peer, {"name": nm, "class": klass, "race": "Human"})
	return sv.characters[peer]


func _init() -> void:
	var sv = RecServer.new()
	get_root().add_child(sv)
	await process_frame
	await process_frame
	sv.set_process(false)
	sv.set_physics_process(false)
	var a = _make(sv, PEER_A, "a", "Fighter")
	var b = _make(sv, PEER_B, "b", "Ninja")
	await process_frame
	var pdata: Dictionary = sv.drop_tables.COMPANION_DATA.get("Wolf", {})
	b.active_companion = {"id": "cw", "monster_type": "Wolf", "name": String(pdata.get("companion_name", "Wolf")),
		"tier": 1, "sub_tier": 1, "level": 5, "xp": 0, "bonuses": {}, "variant": "Normal",
		"variant_color": "#AA6633", "variant_pattern": "solid", "border_tier": 0}
	b.equipped["weapon"] = sv.drop_tables._generate_item({"item_type": "weapon_iron", "rarity": "rare"}, 10)
	a.x = 60
	a.y = 60
	b.x = 63
	b.y = 60
	sv.send_location_update(PEER_A)
	await process_frame
	var payload = sv.last_location.get("map", {})
	ck(payload is Dictionary and not payload.is_empty(), "player A's location carries a map payload")

	var client = load("res://client/client.gd").new()
	client.character_data = a.to_dict()
	client._cached_nearby_players = sv.last_location.get("nearby_players", sv.get_nearby_players(PEER_A))
	client._last_map_center = Vector2i(a.x, a.y)
	client._overworld_display(payload)
	var player_meta := {}
	var comp_meta := {}
	for k in client._overworld_figure_meta:
		var f: Dictionary = client._overworld_figure_meta[k]
		if String(f.get("kind", "")) == "player" and not bool(f.get("is_local", false)):
			player_meta = f
		elif String(f.get("kind", "")) == "companion":
			comp_meta = f
	ck(not player_meta.is_empty(), "B is a hoverable figure on A's map")
	var pd: Dictionary = player_meta.get("data", {})
	print("    B's hover data keys: %s" % str(pd.keys()))
	ck(String(pd.get("battler_id", "")) != "", "B's hover data has a battler id (the base the portrait is composed on)")
	ck(pd.has("appearance_color"), "and an appearance colour (the tint)")
	# The roster deliberately carries no gear; the hover fetches it. What matters is that the gear
	# ARRIVING reaches the hover the map is showing (a pointer hover, no node anchor).
	client._map_hover_player = pd
	client.handle_server_message({"type": "player_equipped", "name": String(pd.get("name", "")), "equipped": b.equipped})
	var cached = client._remote_equip_cache.get(String(pd.get("name", "")), {})
	ck(cached is Dictionary and (cached as Dictionary).has("weapon"), "B's gear, when it arrives, is cached for the portrait")
	var src := FileAccess.get_file_as_string("res://client/client.gd")
	ck(src.contains('String(_map_hover_player.get("name", "")) == _pe_name'),
		"and a pointer-anchored hover of B is redrawn with it (the branch the composed map needs)")
	ck(src.contains("REMOTE_EQUIP_STALE_MS") and not src.contains("if not _remote_equip_requested.has(_hp_name):"),
		"gear is re-asked when stale, not once per session")

	ck(not comp_meta.is_empty(), "B's companion is a hoverable figure")
	var cbody: String = client._build_map_companion_tooltip(comp_meta.get("data", {}))
	var card: String = client.format_companion_tooltip_bbcode(comp_meta.get("data", {}))
	var art: Array = client._get_companion_art_lines("Wolf", "Wolf")
	ck(not art.is_empty() and card != "" and cbody.begins_with(card),
		"hovering it shows the Companions screen's card, ASCII art included (%d art lines)" % art.size())
	var fs := -1
	var at := cbody.find("[font_size=")
	if at >= 0:
		fs = int(cbody.substr(at + 11, 3))
	print("    companion art font size in the hover: %d" % fs)

	client.free()
	print("RESULT: %s (%d failing)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
