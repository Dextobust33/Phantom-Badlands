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
			# The guide's id is per-player now (two tutorials at once must not share a key), so
			# ask whether there is an NPC member rather than for a constant that no longer exists.
			ck(not (c.get("npc_members", []) as Array).is_empty(),
				"  with the Warden in it as an NPC")
			var hp0: int = ch.current_hp
			for r in range(6):
				c["round"] = r + 1
				sv.combat_mgr._party_process_monster_phase(c)
				if ch.current_hp <= 0:
					break
			print("  after 6 monster rounds at 60 strength: player %d/%d hp"
				% [max(0, ch.current_hp), ch.get_total_max_hp()])
			ck(ch.current_hp > 0, "THE PLAYER IS ALIVE — the Warden did his job")
			var gd = c["characters"][(c.get("npc_members", []) as Array)[0]]
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

	print("")
	print("===== 9. HE IS STILL WITH YOU, AND HE POINTS AT A REAL DUNGEON =====")
	# Owner 2026-09-14: *"It told me to go do the D on my map. I don't see a D and the warden
	# doesn't seem to be in my party anymore. I immediately ran into a wolf and had to fight it
	# solo."* Step three IS the walk to the dungeon - open ground a level-2 has to cross - and
	# the escort was ending as step three began.
	ck(sv._guide_escorts_overworld(PEER, ch),
		"the escort covers step THREE as well - the walk to the dungeon is the dangerous part")
	# And there has to be something to walk to. A starter dungeon sits ~30 tiles out against a
	# vision radius of 11, so it is off screen: the bearing in his popup is the only guidance
	# until the ring lights up, which makes "is there one at all" worth asserting.
	# Ask through the REAL path - the one the location message uses - rather than reaching for a
	# lookup of my own. The first cut called _find_nearest_dungeon_for_quest directly and so
	# measured a different function than the game runs.
	sv._ensure_starter_dungeon_exists()
	var goal: Dictionary = sv._escort_goal_for(PEER, ch)
	if goal.is_empty():
		print("  he is leading them nowhere")
	else:
		print("  leading to: %s, %s" % [String(goal.get("name", "?")), String(goal.get("where", "?"))])
	ck(not goal.is_empty(), "he is LEADING them somewhere, not just naming a bearing once")
	ck(String(goal.get("where", "")).contains("tiles"),
		"  with a live distance and bearing that rides every location message")
	# And it says the distance ONCE. `direction_text` already contains it, so printing the
	# number beside it produced "22 tiles 22 tiles northwest".
	var _w := String(goal.get("where", ""))
	ck(_w.count("tiles") == 1, "  said once, not twice (%s)" % _w)

	print("")
	print("===== 9a. AND HE WALKS THEM THERE =====")
	# Owner 2026-09-14: *"I shouldn't have to press anything. He should be leading/moving us too
	# it."* A bearing the player has to steer by is still the player finding their own way.
	# ⛑ END THE FIGHT FIRST. Section 5 starts a real party combat and resolves rounds directly,
	# so the combat is still ACTIVE here - and handle_move refuses every step with "you cannot
	# move while in combat". That cost three wrong theories about the escort before the guard was
	# measured: the feature was fine, the probe's state was dirty.
	if sv.combat_mgr.active_party_combats.has(PEER):
		sv.combat_mgr.active_party_combats.erase(PEER)
	sv.combat_mgr.party_combat_membership.erase(PEER)
	if sv.combat_mgr.is_in_combat(PEER):
		sv.combat_mgr.end_combat(PEER, false)
	ck(not sv.combat_mgr.is_in_combat(PEER), "the tutorial fight is over before the walk begins")

	# Stand them in OPEN GROUND, which is where a player actually is at step three. Section 4
	# left them on a post threshold to test the gate, and a post is walled - the first cut
	# measured the escort failing to move somebody who was boxed in by the test before it.
	var _open := _find_open_ground(int(ch.x), int(ch.y))
	if _open.x != 0x7FFFFFFF:
		ch.x = _open.x
		ch.y = _open.y
	# Start it the way the GAME does - from the tick - rather than by calling the starter by
	# hand. Calling the starter directly is what hid the real bug: the walk only ever began at
	# the instant step two completed, so anybody already on step three was never started and the
	# Warden just stood there, while this probe passed because it started him itself.
	sv._escort_released.erase(PEER)
	# ⛑ HE ASKS BEFORE HE MOVES YOU, so the FIRST tick raises the question and does not walk.
	#
	# Found red on master 2026-09-15, and it had been red since the ask shipped: this asserted
	# that one tick starts the walk, which stopped being true the moment the owner asked for an
	# acknowledgement first (*"He should instead talk to you and you have to acknowledge what's
	# about to happen before he starts moving you."*). Pinning the OLD behaviour meant the gate
	# failed for a day on a fact that had deliberately changed - the same shape as the stale
	# assertion in warden_walks_with_you.gd.
	#
	# Walked the way a player walks it now: tick, answer, tick.
	sv._escort_walk_tick()
	ck(not sv._escort_walk.has(PEER),
		"the first tick ASKS rather than setting off under an unread popup")
	ck(bool(sv._escort_asked.get(PEER, false)), "  and the question really went out")
	sv.handle_tutorial_ack(PEER, {"ack": "escort_ready"})
	sv._escort_walk_tick()
	ck(sv._escort_walk.has(PEER), "the tick starts the walk once they have said go")
	if sv._escort_walk.has(PEER):
		# He STEPS TOWARD the goal rather than following a precomputed path - measured,
		# compute_path_between returns nothing for this trip at any time budget, so a
		# path-shaped walk would never have set off at all.
		var _gx: int = int(sv._escort_walk[PEER].get("gx", 0))
		var _gy: int = int(sv._escort_walk[PEER].get("gy", 0))
		print("  heading for (%d,%d) from (%d,%d)  [inside a post: %s]"
			% [_gx, _gy, ch.x, ch.y,
				str(sv.world_system._is_npc_post_interior(int(ch.x), int(ch.y)))])
		ck(_gx != 0 or _gy != 0, "  with a real destination recorded")
		var _d0: float = Vector2(float(_gx - int(ch.x)), float(_gy - int(ch.y))).length()
		var _before := Vector2i(int(ch.x), int(ch.y))
		# Force the step timer and tick. FIFTEEN, not five - and the number is a measurement,
		# not a taste. The walk is a GREEDY stepper (straight at the goal, then the two axis
		# fallbacks) rather than a path, so a wall between here and there costs it sidesteps that
		# make no net progress. The starter dungeon is placed at a random angle, so whether five
		# ticks cleared the obstacle was a coin flip: observed 2026-09-15 failing on one run and
		# passing the next three with nothing changed between them.
		#
		# Raising the window is the honest fix. Weakening the assertion to "it moved at all" would
		# have hidden the very thing it exists to catch - a walk that jiggles without arriving is
		# exactly the wedged behaviour the owner reported.
		# Measured from OUTSIDE THE POST, because the door detour is legitimate. A post is a
		# walled room; when the dungeon lies on the far side of it, walking to the door moves you
		# AWAY from the dungeon in a straight line while being exactly the right step. Observed
		# 2026-09-15: every failing run of this check started inside a post and every passing one
		# started outside, which is what identified the door routing rather than a broken walk.
		#
		# So progress is judged from the moment they are clear of the walls. Judging from the
		# start would have punished the correct behaviour, and loosening the check to "it moved"
		# would have stopped catching the wedge it exists for.
		var _outside_at: float = -1.0
		for _t in range(30):
			# The tick ERASES the entry when the walk ends - arrival, wedged, or the player
			# entering a dungeon - so it has to be re-checked each pass rather than indexed
			# blind. The first cut indexed it and crashed on the first tick that finished.
			if not sv._escort_walk.has(PEER):
				print("    tick %d: the walk ENDED (wedged, or arrived)" % _t)
				break
			sv._escort_walk[PEER]["next_ms"] = 0
			var _p0 := Vector2i(int(ch.x), int(ch.y))
			sv._escort_walk_tick()
			# Per-tick trace, so a failure says WHAT happened rather than only that it happened.
			# Without this the check could only report "did not get closer", which is the shape
			# that cost three wrong theories about this same walk a day earlier.
			if Vector2i(int(ch.x), int(ch.y)) == _p0:
				print("    tick %d: refused at %v (stuck=%d, gathering=%s)" % [_t, _p0,
					int((sv._escort_walk.get(PEER, {}) as Dictionary).get("stuck", -1)),
					str(sv.active_gathering.has(PEER))])
			if _outside_at < 0.0 and not sv.world_system._is_npc_post_interior(int(ch.x), int(ch.y)):
				_outside_at = Vector2(float(_gx - int(ch.x)), float(_gy - int(ch.y))).length()
				print("    tick %d: clear of the post at %v, %.0f tiles to go" % [_t,
					Vector2i(int(ch.x), int(ch.y)), _outside_at])
			await process_frame
		var _after := Vector2i(int(ch.x), int(ch.y))
		var _d1: float = Vector2(float(_gx - int(ch.x)), float(_gy - int(ch.y))).length()
		print("  after thirty ticks: %v -> %v   (distance %.0f -> %.0f)" % [_before, _after, _d0, _d1])
		ck(_after != _before, "the character actually MOVED without the player pressing anything")
		# Either he got somewhere, or he GAVE UP AND SAID SO. Both are acceptable outcomes; what
		# is not acceptable is the third one, which is what this section caught: walking the
		# player's character in a circle for thirty steps and never stopping, because the
		# refusal counter only ever noticed a walk that could not MOVE.
		#
		# A starter dungeon is placed at a random angle from spawn, so some runs genuinely face a
		# lake shore that a greedy stepper cannot round. Demanding progress every time would be
		# demanding a pathfinder; demanding that he never pretends is the real requirement.
		var _from: float = _outside_at if _outside_at >= 0.0 else _d0
		var _progressed: bool = _d1 < _from
		var _gave_up: bool = not sv._escort_walk.has(PEER)
		ck(_progressed or _gave_up,
			"  and either moved CLOSER (%.0f -> %.0f) or handed the controls back - never paced"
				% [_from, _d1])
		if _gave_up and not _progressed:
			print("    (he gave up honestly - retry armed: %s)"
				% str(sv._escort_retry_ms.has(PEER)))
			ck(sv._escort_retry_ms.has(PEER),
				"  giving up arms the quiet retry rather than restarting on the next frame")
	# ...and a step of their own takes the reins back.
	if sv._escort_walk.has(PEER):
		sv.handle_move(PEER, {"direction": 6})
		ck(not sv._escort_walk.has(PEER),
			"and any manual move cancels it - he leads, he does not drive")

	print("")
	print("===== 9b. THE DUNGEON KNOWS IT IS THE STARTER ONE =====")
	# ⛑ Owner 2026-09-14, from inside it: *"I don't have him following me anymore here in the
	# dungeon and he's also not in the fights."* He could not be: `_get_dungeon_at_location`
	# never returned the `starter` flag, so `_inherit_starter` was false every single time and
	# the instance generated as an ordinary dungeon - FIVE floors instead of two, and
	# `_is_starter_dungeon` false, which is the gate his dungeon escort hangs off.
	var loc_src := FileAccess.get_file_as_string("res://server/server.gd")
	ck(loc_src.contains('"starter": bool(instance.get("starter", false)),'),
		"the tile lookup carries the starter flag that handle_dungeon_enter reads")
	ck(loc_src.contains("_inherit_starter: bool = bool(_tile_dungeon.get(\"starter\", false))"),
		"  which is where the instance gets it from")
	ck(loc_src.contains("if _is_starter_dungeon(instance_id) and not _is_party_leader(peer_id):"),
		"and the guide's dungeon escort hangs off that same flag")

	print("")
	print("===== 9c. AND THE KIT CANNOT BE WALKED PAST =====")
	# *"Seems like I could miss all of it then and just go straight to the boss."* It is placed
	# on random empty tiles, so yes. Finding it stays; the dungeon settles up on the way out.
	ck(loc_src.contains("THE STARTER DUNGEON OWES YOU THE KIT"),
		"anything missed is handed over when the dungeon is cleared")
	ck(loc_src.contains('for _slot in ["helm", "boots", "shield", "accessory"]:'),
		"  covering the four pieces the floor was meant to provide")
	ck(loc_src.contains("if _in_pack:"),
		"  and skipping what the player already found, so nobody gets two of everything")

	print("")
	print("===== 9d. CLEARING THE DUNGEON FINISHES THE CHAIN =====")
	# ⛑ Owner 2026-09-15, live on v0.9.790: *"I walked back to the post manually and doesn't seem
	# like I have a way to turn in the Warden's Watch III Quest at all."* Section 10 below FAKES
	# completion by editing the quest lists, which is exactly how this hid: nothing ever drove
	# step three through the dungeon-progress path. Two faults, both measured here -
	#   1. the Warden's settle loop only ran for KILL updates, and step three is a DUNGEON_CLEAR;
	#   2. the post compared "crossroads" with the runtime id "npc_crossroads", so its hand-in
	#      list was empty.
	ck(sv._wardens_watch_stage(ch) == 3, "the player is on step three going in")
	ch.in_dungeon = true
	var _dq: Array = sv.quest_mgr.check_dungeon_progress(ch, "starter")
	var _dq_done := false
	for _dqu in _dq:
		if String(_dqu.get("quest_id", "")) == "wardens_watch_3" and bool(_dqu.get("completed", false)):
			_dq_done = true
	ck(_dq_done, "clearing a dungeon completes step three")
	sv._warden_settle_steps(PEER, ch, _dq)
	await process_frame
	ck(sv._wardens_watch_stage(ch) == 4, "and the Warden hands it in on the spot - stage %d" % sv._wardens_watch_stage(ch))
	ck("wardens_watch_3" in ch.completed_quests, "  so it is in completed_quests, rewards and all")
	ch.in_dungeon = false
	# ...and for a character ALREADY stranded by the old build (step three complete, never
	# settled): walking into him hands it in. Recreate that state for real and bump him.
	ch.completed_quests.erase("wardens_watch_3")
	sv.quest_mgr.accept_quest(ch, "wardens_watch_3", int(ch.x), int(ch.y))
	ch.update_quest_progress("wardens_watch_3", 1)
	ck(sv._wardens_watch_stage(ch) == 3 and sv.quest_mgr.is_quest_complete(ch, "wardens_watch_3"),
		"a stranded character: step three complete and still active")
	sv._handle_warden_interact(PEER, ch)
	await process_frame
	ck(sv._wardens_watch_stage(ch) == 4, "  walking into the Warden settles it (stage %d)" % sv._wardens_watch_stage(ch))
	# The dungeon-completion path must actually CALL the routine exercised above.
	var _dsrc := FileAccess.get_file_as_string("res://server/server.gd")
	var _dcall := _dsrc.find("var quest_updates = quest_mgr.check_dungeon_progress(character, dungeon_type)")
	ck(_dcall != -1 and _dsrc.substr(_dcall, 600).contains("_warden_settle_steps(peer_id, character, quest_updates)"),
		"  and dungeon completion calls it, right after reporting the progress")
	# The post, in case he is not there to settle it: the runtime id carries the npc_ prefix.
	ck(sv._same_post("crossroads", "npc_crossroads"), "Crossroads counts as Crossroads whatever prefix the runtime id carries")
	ck(not sv._same_post("crossroads", "npc_haven"), "  and a different post still does not")

	print("")
	print("===== 10. AND HE SEES THEM HOME =====")
	# Owner 2026-09-14: *"this is a starter dungeon, the player doesn't even have full equipment
	# at this point... they have to live to get to it and back from it."* The escort used to end
	# the moment the boss died, leaving a level-2 with an unfinished kit ~30 tiles from anywhere,
	# carrying everything they had just earned.
	var _completed: Array = ch.completed_quests.duplicate()
	ch.active_quests.clear()
	ch.completed_quests.append("wardens_watch_3")
	ck(sv._wardens_watch_stage(ch) == 4, "with the chain finished the character reads stage 4")
	ch.x = 9999
	ch.y = 9999       # far from any post interior
	ck(sv._guide_escorts_overworld(PEER, ch),
		"he is STILL with them out in the open - the walk home is the same walk")
	# ...and lets go once they are safe. Find a real post interior to stand in.
	var home := _find_post_interior()
	if home.x == 0x7FFFFFFF:
		print("  SKIP - no post interior found near the origin in this seed")
	else:
		ch.x = home.x
		ch.y = home.y
		ck(not sv._guide_escorts_overworld(PEER, ch),
			"and he leaves once they are standing inside a post")
	ch.completed_quests = _completed

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


func _find_open_ground(near_x: int, near_y: int) -> Vector2i:
	"""A walkable tile outside any post, with walkable neighbours - somewhere a walk can start."""
	for r in range(2, 30):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var x: int = near_x + dx
				var y: int = near_y + dy
				if sv.world_system._is_npc_post_interior(x, y):
					continue
				var t = sv.world_system.chunk_manager.get_tile(x, y)
				if bool(t.get("blocks_move", false)):
					continue
				var open_neighbours := 0
				for o in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
					var n = sv.world_system.chunk_manager.get_tile(x + o.x, y + o.y)
					if not bool(n.get("blocks_move", false)):
						open_neighbours += 1
				if open_neighbours >= 3:
					return Vector2i(x, y)
	return Vector2i(0x7FFFFFFF, 0x7FFFFFFF)


func _find_post_interior() -> Vector2i:
	for r in range(1, 45):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				if sv.world_system._is_npc_post_interior(dx, dy):
					return Vector2i(dx, dy)
	return Vector2i(0x7FFFFFFF, 0x7FFFFFFF)


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
