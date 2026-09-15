extends SceneTree
## The Warden stops joining your party once Warden's Watch is over - abandoned OR finished and home.
##
## Owner 2026-09-15: *"I canceled my starter quest partially through and now he is joining my party
## still whenever I leave the post even though I have no quest with him active."*
const ServerScript = preload("res://server/server.gd")
const PEER := 1

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var sv = ServerScript.new()
	get_root().add_child(sv)
	await process_frame
	await process_frame
	sv.set_process(false)
	sv.set_physics_process(false)
	var made: Dictionary = sv.persistence.create_account("wl%d" % (Time.get_ticks_usec() % 100000), "probe-password")
	sv.peers[PEER] = {"authenticated": true, "account_id": String(made.get("account_id", "")), "character_name": "",
		"connection": StreamPeerTCP.new()}
	var nm := "Wlv"
	var u: int = Time.get_ticks_usec()
	for i in range(4):
		nm += char(97 + (u % 26))
		u /= 26
	sv.handle_create_character(PEER, {"name": nm, "class": "Fighter", "race": "Human"})
	await process_frame
	var ch = sv.characters[PEER]
	ch.met_warden = true
	# Out in the open, not inside a post.
	var spot := Vector2i(200, 200)
	for t in range(40):
		if not sv.world_system._is_npc_post_interior(spot.x + t, spot.y):
			spot = Vector2i(spot.x + t, spot.y)
			break
	ch.x = spot.x
	ch.y = spot.y

	ck(sv._guide_escorts_overworld(PEER, ch), "control: on step one he escorts you in the open")

	# Step one handed in, then the chain abandoned.
	ch.active_quests = []
	ch.completed_quests = ["wardens_watch_1"]
	ck(sv._wardens_watch_stage(ch) == 0, "an ABANDONED Watch reads as no Watch (stage %d)" % sv._wardens_watch_stage(ch))
	ck(not sv._guide_escorts_overworld(PEER, ch), "and he does not join you outside the post")

	# Finished properly, on the way home.
	ch.completed_quests = ["wardens_watch_1", "wardens_watch_2", "wardens_watch_3"]
	ch.seen_guide_home_hint = false
	ck(sv._wardens_watch_stage(ch) == 4, "handing in step three finishes it (stage 4)")
	ck(sv._guide_escorts_overworld(PEER, ch), "and he still walks you home")

	# ...and once he has left you at a post.
	ch.seen_guide_home_hint = true
	ck(not sv._guide_escorts_overworld(PEER, ch), "once he has left you at a post he stops coming along")

	print("RESULT: %s (%d failing)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
