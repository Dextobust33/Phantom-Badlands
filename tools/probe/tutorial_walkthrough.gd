extends SceneTree
## Walk a brand-new character through the whole opening, on the REAL server.
##
## ⛑ THIS EXISTS BECAUSE EVERY OTHER PROBE TESTS A FUNCTION, AND THIS SESSION PROVED THAT IS NOT
## ENOUGH. The Warden's aggro rule had a passing unit test and had never fired once in play: the
## rule was correct and nothing called it. A test that reaches into a function cannot see whether
## the game reaches that function.
##
## So this one boots `server.gd` itself, fakes a connected peer, and drives the real handlers in
## the order a player triggers them. Owner 2026-09-14: *"We still haven't confirmed this is
## working, why would I release it?"* Quite.
##
## What it cannot do is judge how any of it FEELS, or whether a sentence reads well. That is a
## playthrough and always will be.
const ServerScript = preload("res://server/server.gd")

var fails := 0
var sv = null
const PEER := 1

func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	sv = ServerScript.new()
	get_root().add_child(sv)
	await process_frame
	await process_frame
	# The server's _process polls sockets and hangs up on anything not CONNECTED, which would
	# drop the fake peer a frame after it is registered. Handlers are called directly here, so
	# the poll loop is not needed - switch it off rather than fake a socket well enough to
	# survive it.
	sv.set_process(false)
	sv.set_physics_process(false)

	# A REAL account, made the way the login path makes one - `can_create_character` reads
	# accounts_data and refuses an id that was never registered, so hand-stuffing the peer dict
	# is not enough.
	var uname := "probeacct"
	var _u: int = Time.get_ticks_usec() % 456976
	for _i in range(4):
		uname += char(97 + (_u % 26))
		_u /= 26
	var made: Dictionary = sv.persistence.create_account(uname, "probe-password")
	ck(bool(made.get("success", false)), "a test account is registered (%s)" % uname)
	var acct := String(made.get("account_id", ""))
	# An UNCONNECTED StreamPeerTCP: send_to_peer checks the status and returns early, so every
	# message the server tries to push is harmlessly dropped and nothing here has to stub the
	# protocol. What matters is the server-side state each handler leaves behind.
	sv.peers[PEER] = {"authenticated": true, "account_id": acct, "character_name": "",
		"connection": StreamPeerTCP.new()}
	sv.persistence.houses_data = sv.persistence.houses_data if sv.persistence.houses_data else {}

	print("===== 1. A CHARACTER IS CREATED =====")
	# Letters only (the name regex rejects digits), and unique per run so a second run does not
	# collide with the first character this probe ever made.
	var nm := "Probe"
	var _n: int = Time.get_ticks_usec() % 456976
	for _i in range(4):
		nm += char(97 + (_n % 26))
		_n /= 26
	sv.handle_create_character(PEER, {"name": nm, "class": "Fighter", "race": "Human"})
	await process_frame
	ck(sv.characters.has(PEER), "creation produced a live character")
	if not sv.characters.has(PEER):
		_finish(); return
	var ch = sv.characters[PEER]
	print("  %s the %s, level %d" % [ch.name, ch.class_type, ch.level])
	ck(ch.current_hp == ch.get_total_max_hp(),
		"starts at FULL health (%d/%d)" % [ch.current_hp, ch.get_total_max_hp()])
	ck(ch.equipped.get("weapon", null) == null, "and unarmed - the Warden arms you")
	var on_chain := false
	for q in ch.active_quests:
		if String(q.get("quest_id", q.get("id", ""))).begins_with("wardens_watch"):
			on_chain = true
	ck(on_chain, "and holding Warden's Watch")

	print("")
	print("===== 2. THE POST IS SHUT UNTIL YOU MEET HIM =====")
	ck(not ch.met_warden, "they have not met him yet")
	ck(not sv._guide_escorts_overworld(PEER, ch),
		"so he is NOT following them (this was the bug: stage 1 starts at creation)")

	print("")
	print("===== 3. YOU WALK INTO HIM =====")
	sv._handle_warden_interact(PEER, ch)
	await process_frame
	ck(ch.met_warden, "meeting him is recorded")
	var has_blade := false
	for it in ch.inventory:
		if it is Dictionary and ch.get_item_slot_from_type(String(it.get("type", ""))) == "weapon":
			has_blade = true
	ck(has_blade, "and he really hands over a weapon")
	ck(sv._guide_escorts_overworld(PEER, ch), "NOW he escorts")

	print("")
	print("===== 4. HE WILL NOT LET YOU LEAVE UNARMED =====")
	# Put them on a post tile with open ground outside, so the threshold test is meaningful.
	var inside := _find_post_edge()
	if inside.x == 0x7FFFFFFF:
		print("  SKIP - no post threshold found near the origin in this world seed")
	else:
		ch.x = inside.x
		ch.y = inside.y
		var out := Vector2i(inside.z, inside.w)
		ck(not sv._warden_lets_you_go(PEER, ch, out.x, out.y),
			"a step out of the post is refused while the blade is in the pack")
		# Equip it and try again.
		for i in range(ch.inventory.size()):
			var it = ch.inventory[i]
			if it is Dictionary and ch.get_item_slot_from_type(String(it.get("type", ""))) == "weapon":
				ch.equip_item(ch.remove_item(i), "weapon")
				break
		ck(ch.equipped.get("weapon", null) != null, "  the weapon goes on")
		ck(sv._warden_lets_you_go(PEER, ch, out.x, out.y), "  and now the gate opens")

	print("")
	print("===== 5. THE FIRST FIGHT, AND HE TAKES WHAT WOULD KILL YOU =====")
	var mon: Dictionary = sv.monster_db.generate_monster(1, 1) if sv.monster_db else {}
	ck(not mon.is_empty(), "a monster is generated")
	if not mon.is_empty():
		mon["strength"] = 60          # lethal to a level 1 in two hits
		mon["current_hp"] = 9999
		mon["max_hp"] = 9999
		var started: bool = sv._start_guided_overworld_combat(PEER, ch, mon)
		ck(started, "the guided fight starts")
		if started:
			ck(sv.combat_mgr.active_party_combats.has(PEER), "  as a real party combat")
			var c = sv.combat_mgr.active_party_combats[PEER]
			ck(sv.GUIDE_PEER_ID in c.get("npc_members", []), "  with the Warden in it as an NPC")
			var hp0: int = ch.current_hp
			for r in range(6):
				c["round"] = r + 1
				sv.combat_mgr._party_process_monster_phase(c)
				if ch.current_hp <= 0:
					break
			print("  after 6 monster rounds at 60 strength: player %d/%d hp"
				% [max(0, ch.current_hp), ch.get_total_max_hp()])
			ck(ch.current_hp > 0, "THE PLAYER IS ALIVE — the Warden did his job")
			var gd = c["characters"][sv.GUIDE_PEER_ID]
			ck(gd.current_hp >= 1, "  and the Warden is still standing")
			# Owner 2026-09-14: *"the warden should have a bunch more HP so he's not sitting
			# missing pretty much all of his HP during some fights."* A protector whose bar is
			# empty reads as about to die, which is the opposite of the reassurance he is for.
			var gpct: float = 100.0 * gd.current_hp / maxf(1.0, float(gd.get_total_max_hp()))
			print("  Warden on %d/%d hp (%.0f%%) after taking the round six times"
				% [gd.current_hp, gd.get_total_max_hp(), gpct])
			ck(gpct > 40.0, "  and he still LOOKS like a protector, not a casualty")
			ck(ch.current_hp < hp0, "  but the player was still hurt - the fight is real")

	print("")
	print("===== 6. A KILL CREDITS THE QUEST =====")
	var before := _stage1_progress(ch)
	sv.check_kill_quest_progress(PEER, 1, String(mon.get("name", "Wolf")))
	await process_frame
	var after := _stage1_progress(ch)
	print("  Warden's Watch I: %d -> %d" % [before, after])
	ck(after > before or _stage_done(ch),
		"the kill counts (co-op never credited a kill quest at all before today)")

	print("")
	print("===== 7. AND FINISHING THE STEP TELLS YOU THE NEXT ONE =====")
	# Owner 2026-09-14: *"Once again I completed the first fight and it shows my quest is done
	# but hasn't told me what to do now."* The hook is on the COMPLETED update - so the question
	# is whether completion is actually reported, and whether the lesson had already been spent.
	ck(ch.seen_guide_recovery_hint,
		"the recovery lesson fired when the step completed (Rest, danger, stances)")
	# ⛑ AND THE CHAIN MOVES ON BY ITSELF.
	#
	# Owner 2026-09-14: *"I killed the three enemies and now it's complete but I don't know what
	# to do next, he didn't tell me anything."* Step one turned itself in and step two did not,
	# so the chain stopped at a quest marked complete with nothing to advance it. Checking only
	# step one would have missed that, which is exactly what happened - so walk the WHOLE chain.
	var stage_now: int = sv._wardens_watch_stage(ch)
	print("  after step one settles, the player is on stage %d" % stage_now)
	ck(stage_now == 2, "step one turned itself in and step TWO is live")
	ck(ch.equipped.get("armor", null) != null or _has_armor(ch),
		"  and the armour he owes arrived with it")

	print("")
	print("===== 8. AND SO DOES EVERY STEP AFTER IT =====")
	for _k in range(3):
		sv.check_kill_quest_progress(PEER, 1, String(mon.get("name", "Wolf")))
		await process_frame
	var stage_after: int = sv._wardens_watch_stage(ch)
	print("  three more kills later, the player is on stage %d" % stage_after)
	ck(stage_after == 3, "step two settled itself too - the chain did not stall")
	ck(ch.seen_guide_world_hint, "  and the world lesson fired on the way past")

	_finish()


func _has_armor(ch) -> bool:
	for it in ch.inventory:
		if it is Dictionary and ch.get_item_slot_from_type(String(it.get("type", ""))) == "armor":
			return true
	return false


func _stage1_progress(ch) -> int:
	for q in ch.active_quests:
		if String(q.get("quest_id", q.get("id", ""))) == "wardens_watch_1":
			return int(q.get("progress", 0))
	return -1


func _stage_done(ch) -> bool:
	for qid in ch.completed_quests:
		if String(qid) == "wardens_watch_1":
			return true
	return _stage1_progress(ch) == -1


func _find_post_edge() -> Vector4i:
	# An interior tile with a walkable non-interior neighbour: the threshold the gate guards.
	for r in range(1, 45):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				if not sv.world_system._is_npc_post_interior(dx, dy):
					continue
				for o in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
					var nx: int = dx + o.x
					var ny: int = dy + o.y
					if sv.world_system._is_npc_post_interior(nx, ny):
						continue
					var t = sv.world_system.chunk_manager.get_tile(nx, ny)
					if not bool(t.get("blocks_move", false)):
						return Vector4i(dx, dy, nx, ny)
	return Vector4i(0x7FFFFFFF, 0, 0, 0)


func _finish() -> void:
	print("")
	print("----- NOT COVERED HERE -----")
	print("  How any of it READS. Whether the popups land in a sensible order on screen, whether")
	print("  the ring is noticeable, whether four floor pieces are findable. A playthrough.")
	print("")
	if fails == 0:
		print("PASS - a new character can be walked through the opening on the real server")
	else:
		print("FAIL - %d check(s) failed" % fails)
	quit(1 if fails > 0 else 0)
