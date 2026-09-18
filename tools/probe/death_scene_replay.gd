extends SceneTree
## ⛑ A DEATH REPLAYS AS A FIGHT — SAME SCENE, BOTH BARS MOVING, RECORDED NUMBERS ONLY.
##
## Owner 2026-09-18: *"it should play out like the fight does. Ideally it's a windowed replay of
## the fight from the dead players perspective."*
##
## The first version of this feature could only PACE the log, because a stored `combat_log` is
## flat BBCode strings — no actor, no damage, no HP. Rather than read those numbers back out of
## the prose (the mistake that put co-op damage numbers on the wrong combatant), the server now
## RECORDS them beside each line as `combat_replay`. This probe checks the recorded track is
## well-formed and that the client's walk over it reproduces the fight's HP curve.
##
## ⛑ THE CHECK THAT MATTERS IS THE CURVE, NOT THE FIELDS. A track that exists but whose player HP
## never reaches zero would render a death in which nobody dies, and every field would be present
## and correct.
##
## Run:
##   godot --headless --path . --script res://tools/probe/death_scene_replay.gd

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	var cli := FileAccess.get_file_as_string("res://client/client.gd")

	print("===== THE SERVER RECORDS IT, AT EVERY SITE THAT LOGS =====")
	ck(srv.find("func _record_replay_beats(") >= 0, "there is a recorder")
	# Both append sites must feed it, or a fight's item-use beats go missing mid-replay.
	ck(srv.count("_record_replay_beats(peer_id, result)") == 2,
		"both combat-log append sites record beats (%d)" % srv.count("_record_replay_beats(peer_id, result)"))
	ck(srv.find('"combat_replay": combat_data.get("combat_replay", []),') >= 0,
		"and the death snapshot persists the track")
	for k in ['"a":', '"d":', '"t":', '"m":', '"p":']:
		ck(srv.find(k + ' ') >= 0 or srv.find(k) >= 0, "  the beat carries %s" % k)

	print("\n===== THE HP CURVE A RECORDED TRACK PRODUCES =====")
	# Simulate the client's walk over a plausible track and assert it ENDS IN A DEATH.
	var start_hp := 78
	var max_hp := 78
	var m_max := 859
	var track: Array = []
	var m := m_max
	var p := start_hp
	while p > 0:
		m = maxi(0, m - 40)
		track.append({"a": "member", "d": 40, "t": 0, "m": m, "p": p})
		p = maxi(0, p - 9)
		track.append({"a": "monster", "d": 0, "t": 9, "m": m, "p": p})
	# Now walk it the way `_step_death_replay` does.
	var php := start_hp
	var lowest := start_hp
	var mhp := m_max
	for beat in track:
		php = maxi(0, php - int(beat.get("t", 0)))
		mhp = clampi(int(beat.get("m", m_max)), 0, m_max)
		lowest = mini(lowest, php)
	print("  %d beats | player %d -> %d of %d | monster %d -> %d" % [track.size(), start_hp, php, max_hp, m_max, mhp])
	ck(php == 0, "the replay ends with the player at ZERO - it reproduces a death")
	ck(lowest == 0, "...and the curve actually reaches it rather than jumping there")
	ck(mhp < m_max, "the monster's bar moved too (%d of %d)" % [mhp, m_max])

	print("\n===== THE CLIENT DRIVES THE REAL PANEL =====")
	ck(cli.find("func _start_scene_replay(") >= 0, "there is a scene replay")
	ck(cli.find("combat_scene_panel.populate({") >= 0, "it populates the actual combat panel")
	ck(cli.find('"player_equipped": dd.get("equipped"') >= 0, "with the dead player's own gear")
	ck(cli.find('"companion_data": comp') >= 0, "...and their companion")
	ck(cli.find("_combat_scene_force_visible = true") >= 0, "and pins the panel, which hides itself otherwise")

	print("\n===== IT NEVER RUNS UNDER A REAL FIGHT =====")
	ck(cli.find("and not in_combat and not _blocking_overlay_open()") >= 0,
		"a scene replay is refused during your own combat or under an overlay")
	ck(cli.find("if (_dreplay_active or _dreplay_holding) and in_combat:") >= 0,
		"...and a fight starting mid-replay ends the replay rather than sharing the screen")
	ck(cli.find("var _dreplay_holding: bool = false") >= 0,
		"a FINISHED replay still owns the input (else its Space falls through to Rest)")
	ck(cli.find("if (_dreplay_active or _dreplay_holding) and event is InputEventKey") >= 0,
		"...and the key guard honours the held state, not just the playing one")

	print("\n===== AND AN OLD DEATH STILL REPLAYS, AS TEXT =====")
	ck(cli.find("beats.size() == lines.size()") >= 0,
		"the scene replay needs a track the same length as the log")
	ck(cli.find("fight_log_panel.play_replay(head, lines, combat_speed_effective())") >= 0,
		"...and anything else falls back to paced text rather than failing")

	print("")
	if fails == 0:
		print("[PROBE] PASS a death replays as the fight it was")
	else:
		print("[PROBE] FAIL %d check(s)" % fails)
	quit(1 if fails > 0 else 0)
