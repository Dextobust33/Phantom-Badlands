extends SceneTree
## You should not be able to walk blind into country that will kill you.
##
## Owner 2026-09-13: *"we need to make sure players aren't blindsided by high level areas. We
## should either warn players before they enter a level much higher level than them or make it
## where players can hover an area of the map to see the area level."*
##
## The hover is the tool for players who look. This is the guard for players who do not, and it
## is the one that can go wrong in a way that HURTS: a guard that refuses a step it should not
## can strand a character, and under permadeath stranded is close to dead. So the checks below
## are as much about what it must NOT block as what it must.
const WorldSystemScript = preload("res://shared/world_system.gd")
const ChunkManagerScript = preload("res://shared/chunk_manager.gd")
const ServerScript = preload("res://server/server.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


class FakeChar:
	var level := 1
	var x := 0
	var y := 0


## A stand-in for the server that records what it would have sent, so the guard can be driven
## without a socket.
var sent: Array = []


func _init() -> void:
	var cm = ChunkManagerScript.new()
	get_root().add_child(cm)
	cm.load_world_seed()
	cm.load_npc_posts()
	var ws = WorldSystemScript.new()
	get_root().add_child(ws)
	ws.chunk_manager = cm
	cm.terrain_generator = ws

	# The guard is a method on the server. Take the real object and give it only what the guard
	# touches - driving the real code rather than a copy of its logic.
	var srv = ServerScript.new()
	srv.world_system = ws
	var outbox: Array = []
	# `send_to_peer` is what the guard uses to explain itself; capture instead of transmitting.
	srv.set_script(srv.get_script())

	print("===== THE BANDS ARE THE ONES THE PLAYER ALREADY SEES =====")
	ck(ServerScript.DANGER_STEP_RATIO == 2.0,
		"the guard fires at 2x, where the Area readout already says 'far above you'")
	ck(srv._danger_band(1.9) == 0, "1.9x does not ask")
	ck(srv._danger_band(2.0) == 1, "2.0x asks")
	ck(srv._danger_band(3.0) == 2, "3x is a louder band")
	ck(srv._danger_band(4.0) == 3, "4x is the loudest")

	print("\n===== IT STOPS THE FIRST STEP AND ALLOWS THE SECOND =====")
	# Find real ground that is at least twice a level-20 character.
	var ch := FakeChar.new()
	ch.level = 20
	var target := Vector2i(0, 0)
	var found := false
	for r in range(20, 900, 5):
		var lv: int = int(ws.get_post_anchored_level(r, 0))
		if float(lv) / 20.0 >= 2.0:
			target = Vector2i(r, 0)
			found = true
			break
	ck(found, "found real country at 2x a level-20 character: (%d,%d) is Lv %d" % [
		target.x, target.y, int(ws.get_post_anchored_level(target.x, target.y))])

	srv._danger_step_ack.clear()
	var first: bool = srv._confirm_dangerous_step(1, ch, target.x, target.y)
	ck(first == false, "the first step into it is REFUSED")
	var second: bool = srv._confirm_dangerous_step(1, ch, target.x, target.y)
	ck(second == true, "pressing the same direction again goes through")

	print("\n===== IT CANNOT STRAND ANYBODY =====")
	# Having accepted the danger, walking BACK toward safety must never be gated - that is the
	# failure that would turn a guard into a trap.
	var back_blocked := 0
	for r in range(target.x, -1, -5):
		if not srv._confirm_dangerous_step(1, ch, r, 0):
			back_blocked += 1
	ck(back_blocked == 0, "walking all the way home is never blocked (%d refusals)" % back_blocked)
	# And having walked home, the guard re-arms.
	var rearmed: bool = not srv._confirm_dangerous_step(1, ch, target.x, target.y)
	ck(rearmed, "returning to safe ground re-arms it, so the next trip asks again")

	print("\n===== IT ASKS ON ENTERING, NOT ON EVERY STEP =====")
	# The owner's question: does this fire once when you cross in, or every step you stay?
	# Once. Walk deep into accepted country and count.
	srv._danger_step_ack.clear()
	srv._danger_step_below.clear()
	var deep := FakeChar.new()
	deep.level = 20
	var asks := 0
	for i in range(60):
		if not srv._confirm_dangerous_step(7, deep, target.x + i, 0):
			asks += 1
	ck(asks == 1, "60 steps into 2x country asked %d time(s), not 60" % asks)

	print("\n===== AND FIGHTING ALONG A BORDER DOES NOT NAG =====")
	# Step out, step back, twenty times - the shape of retreating to heal and re-engaging.
	# Clearing the acceptance the instant you left would ask on every re-entry.
	srv._danger_step_ack.clear()
	srv._danger_step_below.clear()
	var safe_x: int = target.x - 1
	while safe_x > 0 and float(ws.get_post_anchored_level(safe_x, 0)) / 20.0 >= 2.0:
		safe_x -= 1
	var oscillation := 0
	for i in range(20):
		if not srv._confirm_dangerous_step(8, deep, safe_x, 0):
			oscillation += 1
		if not srv._confirm_dangerous_step(8, deep, target.x, 0):
			oscillation += 1
	ck(oscillation == 1, "twenty crossings back and forth asked %d time(s)" % oscillation)

	# But a real trip home and back out SHOULD ask again.
	for i in range(ServerScript.DANGER_ACK_DECAY_STEPS + 2):
		srv._confirm_dangerous_step(8, deep, safe_x, 0)
	ck(not srv._confirm_dangerous_step(8, deep, target.x, 0),
		"...while staying away %d steps re-arms it for the next trip out" % ServerScript.DANGER_ACK_DECAY_STEPS)

	print("\n===== IT IS SILENT WHERE IT SHOULD BE =====")
	# A character AT level for the ground must never be asked, anywhere.
	srv._danger_step_ack.clear()
	var spurious := 0
	var sampled := 0
	for r in range(5, 1200, 7):
		# ⚑ AT THE LEVEL OF WHAT SPAWNS, not of the terrain. This read the terrain baseline and
		# started failing the moment the guard learned about hotzones - correctly: inside one,
		# a character at the BASELINE level is underlevelled for what actually arrives, and
		# stopping them is the entire point of the change.
		var lv: int = maxi(1, ws.danger_level_at(r, 0))
		var at_level := FakeChar.new()
		at_level.level = lv
		sampled += 1
		if not srv._confirm_dangerous_step(2, at_level, r, 0):
			spurious += 1
	ck(spurious == 0,
		"a character at the country's own level is never stopped (%d of %d steps)" % [spurious, sampled])

	# ...and walking one step at a time out from the start, a LEVEL-APPROPRIATE player should
	# almost never see it. This is the "is it annoying" question, measured.
	srv._danger_step_ack.clear()
	var walker := FakeChar.new()
	walker.level = 8
	var stops := 0
	for r in range(0, 400):
		if not srv._confirm_dangerous_step(3, walker, r, 0):
			stops += 1
	print("  a level-8 character walking 400 tiles straight out is stopped %d times" % stops)
	# Hotzones legitimately add prompts now - they are 2-2.75x jumps and are exactly the thing
	# a player should be stopped for. Counted separately so the budget is honest about why.
	var hot_crossed := 0
	for r in range(0, 400):
		if ws.get_hotspot_at(r, 0).get("in_hotspot", false):
			hot_crossed += 1
	print("  (%d of those 400 tiles are hotzone)" % hot_crossed)
	ck(stops <= 6, "which is %d - a handful of boundaries, not a nag" % stops)

	print("\n===== AND IT SEES HOTZONES, WHICH IS WHERE IT MATTERS MOST =====")
	# A hotzone multiplies what spawns by 1.5-2.5x over the terrain baseline. Reading the
	# baseline made this guard SILENT on the biggest jump in the game: measured across 1124
	# hotzone tiles, spawns run 2.06x the baseline on average and up to 2.75x.
	#
	# Find a real one whose baseline is comfortable for a character but whose spawns are not.
	var hz_found := false
	var hz_char := FakeChar.new()
	var hz_x := 0
	var hz_y := 0
	for y in range(-140, 141, 2):
		for x in range(60, 700, 2):
			if not ws.get_hotspot_at(x, y).get("in_hotspot", false):
				continue
			var base: int = int(ws.get_post_anchored_level(x, y))
			var real: int = ws.danger_level_at(x, y)
			# A character exactly at the terrain level: the old reading would say "you are fine".
			if base >= 10 and float(real) / float(base) >= 2.0:
				hz_char.level = base
				hz_x = x
				hz_y = y
				hz_found = true
				break
		if hz_found:
			break
	ck(hz_found, "found a hotzone where spawns are 2x the terrain baseline: (%d,%d) baseline Lv %d, spawns Lv %d" % [
		hz_x, hz_y, int(ws.get_post_anchored_level(hz_x, hz_y)), ws.danger_level_at(hz_x, hz_y)])
	srv._danger_step_ack.clear()
	srv._danger_step_below.clear()
	ck(not srv._confirm_dangerous_step(11, hz_char, hz_x, hz_y),
		"a character AT the terrain level is still warned, because the hotzone is what spawns")

	print("\n===== A REFUSED STEP HAS NO OTHER CONSEQUENCE =====")
	# A step that did not happen must not break a trade, and resting in place must never be
	# gated. Both are questions about ORDER inside handle_move, which is where they are checked.
	var hm_src := FileAccess.get_file_as_string("res://server/server.gd")
	var at_guard: int = hm_src.find("_confirm_dangerous_step(peer_id, character")
	var at_trade: int = hm_src.find("_cancel_trade(peer_id, \"Trade cancelled - you moved away.\")")
	ck(at_guard > 0 and at_trade > 0 and at_guard < at_trade,
		"the guard runs BEFORE the trade cancel, so a refused step keeps your trade")
	ck(hm_src.find("if new_pos != Vector2i(old_x, old_y) and not _confirm_dangerous_step") >= 0,
		"and a step that does not move you (rest, or blocked terrain) is never gated")

	print("\n===== AND IT EXPLAINS ITSELF =====")
	var src := FileAccess.get_file_as_string("res://server/server.gd")
	ck(src.find('"type": "danger_step_warning"') >= 0, "the refusal sends a message, not silence")
	ck(src.find("Step again to go anyway") >= 0, "...that says how to proceed anyway")
	var csrc := FileAccess.get_file_as_string("res://client/client.gd")
	ck(csrc.find('"danger_step_warning":') >= 0,
		"and the CLIENT handles that type, or the refusal is a step that silently does nothing")
	ck(csrc.find('display_game("\n%s\n%s\n%s\n" % [rule,') >= 0,
		"...drawn between rules, so it reads as a stop rather than a line of chatter")

	print("\n===== IT DOES NOT COST A STEP =====")
	var t0 := Time.get_ticks_usec()
	for i in range(2000):
		srv._confirm_dangerous_step(9, walker, i, i)
	var us := float(Time.get_ticks_usec() - t0) / 2000.0
	print("  %.1f us per step" % us)
	ck(us < 200.0, "the guard costs %.1f us a move (< 200)" % us)

	print("\n[DANGERSTEP] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
