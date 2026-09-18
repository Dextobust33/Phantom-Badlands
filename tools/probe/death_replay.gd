extends SceneTree
## ⛑ A STORED FIGHT PLAYS BACK, ONE LINE AT A TIME, AND ENDS WHOLE.
##
## The backlog asked for a link to the combat log, *"ideally a replay"*. This is the replay half.
##
## ⛑ WHAT IT DELIBERATELY IS NOT. A stored `combat_log` is plain BBCode strings - no actor tag, no
## damage number, no HP per line - so a re-animation with moving bars and acting sprites could only
## be built by reading numbers back out of the prose. That is precisely the mistake that put co-op
## damage numbers on the wrong combatant ("The Goblin hits Warden Hollis for 43" has no "you" in
## it, and the parser credited the monster). The line ORDER is the fight, and the order is stored
## exactly, so pacing is the honest replay and needs none of that.
##
## This probe DRIVES the playback rather than reading the source, because a replay that renders
## nothing and a replay that works look identical from the outside: same panel, same buttons.
##
## Run:
##   godot --headless --path . --script res://tools/probe/death_replay.gd

const FightLog = preload("res://client/fight_log_panel.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _lines(n: int) -> Array:
	var out: Array = []
	for i in range(n):
		out.append("[color=#FFFFFF]round beat %d[/color]" % i)
	return out


func _init() -> void:
	var p = FightLog.new()
	get_root().add_child(p)
	await process_frame

	print("===== IT STARTS EMPTY AND FILLS =====")
	var lines := _lines(40)
	# Fast, so the probe is not a stopwatch: 40 lines at 20x is well under a second of game time.
	p.play_replay("Testchar (Lv 7 Ninja) — slain by a Gnoll — 12 rounds", lines, 20.0)
	await process_frame
	ck(p.visible, "the panel opens")
	ck(p._body.text.length() < 200,
		"it does NOT dump the whole fight immediately (%d chars on frame 1)" % p._body.text.length())
	var first_len: int = p._body.text.length()

	# Drive real frames and let the tick advance it.
	for i in range(240):
		await process_frame
		if p._replay_i >= lines.size():
			break
	ck(p._body.text.length() > first_len, "the log GREW as it played (%d -> %d chars)"
		% [first_len, p._body.text.length()])
	ck(p._replay_i >= lines.size(), "it reached the end (%d of %d lines)" % [p._replay_i, lines.size()])
	ck(p._body.text.find("beat 0") >= 0, "the FIRST beat is present at the end")
	ck(p._body.text.find("beat 39") >= 0, "...and so is the last - nothing was dropped in between")
	ck(not p._replay_playing, "it stops when it runs out")
	ck(p._play_btn.text.find("Replay") >= 0, "...and the button offers to run it again")

	print("\n===== SKIP SHOWS EVERYTHING AT ONCE =====")
	p.play_replay("t", _lines(50), 1.0)
	await process_frame
	p._skip_replay()
	ck(p._body.text.find("beat 0") >= 0 and p._body.text.find("beat 49") >= 0,
		"skipping to the end shows the whole fight")
	ck(not p._replay_playing, "...and stops the clock")

	print("\n===== A FIGHT WITH NO RECORD SAYS SO =====")
	p.play_replay("t", [], 1.0)
	await process_frame
	ck(p._body.text.to_lower().find("no blow-by-blow") >= 0,
		"an empty log explains itself rather than showing a blank panel")
	ck(not p._play_btn.visible, "...and offers no transport controls for nothing")

	print("\n===== THE PANEL IS SHARED, SO REPLAY MUST NOT LEAK =====")
	# ⛑ A ticking replay left running underneath a log the player asked to READ would append
	# lines into it from underneath. Same panel, two modes; switching must stop the clock.
	p.play_replay("t", _lines(60), 1.0)
	await process_frame
	p.show_log("an ordinary log", "[color=#FFFFFF]a static line[/color]", false, false)
	await process_frame
	await process_frame
	ck(not p._replay_playing, "opening a static log stops any replay in progress")
	ck(p._body.text.find("a static line") >= 0, "...and shows the static log")
	ck(p._body.text.find("beat ") < 0, "...with no replay lines bleeding into it")
	ck(not p._play_btn.visible and not p._progress.visible,
		"...and the transport controls are put away")

	print("")
	if fails == 0:
		print("[PROBE] PASS a death replays at the pace it happened")
	else:
		print("[PROBE] FAIL %d check(s)" % fails)
	quit(1 if fails > 0 else 0)
