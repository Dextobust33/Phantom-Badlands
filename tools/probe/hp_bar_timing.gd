extends SceneTree
## How long is a player allowed to act while their own HP bar has not moved yet?
##
## Owner: *"I didn't see my health bar drop from the first round of the combat before I selected my
## second round card (I may have been moving too fast though)."*
##
## Two things were already ruled OUT: the bar's tween is 0.3s, and it reads `current_hp` directly,
## so it is neither a slow animation nor a stale field. The backlog asked for a MEASUREMENT rather
## than a third theory. This is it: drive real rounds against real multi-hit monsters, count the
## messages each produces, and price them at the client's OWN pacing constants.
const CM := preload("res://shared/combat_manager.gd")
const MD := preload("res://shared/monster_database.gd")
const CH := preload("res://shared/character.gd")
const DT := preload("res://shared/drop_tables.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _client_const(name: String) -> float:
	var src := FileAccess.get_file_as_string("res://client/client.gd")
	var re := RegEx.new()
	re.compile("const " + name + ": float = ([0-9.]+)")
	var m := re.search(src)
	return float(m.get_string(1)) if m != null else -1.0


func _mk(klass: String):
	var c = CH.new()
	c.name = "P"
	c.class_type = klass
	c.level = 12
	c.max_hp = 4000
	c.current_hp = 4000
	c.max_energy = 999
	c.current_energy = 999
	return c


func _round_msgs(mon_name: String, ability: String) -> int:
	"""Messages one full round produces for a monster with a multi-hit / ability kit."""
	var cm = CM.new()
	cm.monster_database = MD.new()
	cm.drop_tables = DT.new()
	var f := FileAccess.open("res://server/balance_config.json", FileAccess.READ)
	if f != null:
		var j := JSON.new()
		if j.parse(f.get_as_text()) == OK:
			cm.balance_config = j.data
		f.close()
	var mon = cm.monster_database.generate_monster_by_name(mon_name, 12, false, "")
	if mon == null or not (mon is Dictionary):
		return -1
	if ability != "" and not (ability in mon.get("abilities", [])):
		mon["abilities"] = mon.get("abilities", []) + [ability]
	var ch = _mk("Warrior")
	cm.start_combat(1, ch, mon)
	var best := 0
	# Several rounds: multi-hit counts and ability procs are random, so take the WORST case a
	# player can actually meet, not an average - the average is not what caught them out.
	for i in range(40):
		if not cm.active_combats.has(1):
			break
		var res = cm.process_combat_command(1, "attack")
		var n: int = res.get("messages", []).size()
		var mt = cm.monster_turn_lines(res)
		n += (mt.size() if mt is Array else 0)
		best = maxi(best, n)
		if int(cm.active_combats.get(1, {}).get("monster", {}).get("current_hp", 0)) <= 0:
			break
		ch.current_hp = ch.max_hp
	return best


func _init() -> void:
	var inter := _client_const("INTER_ATTACK_DELAY")
	var ambient := _client_const("AMBIENT_DELAY")
	var post := _client_const("POST_FINAL_ATTACK_DELAY")
	print("client pacing: INTER_ATTACK %.2fs  AMBIENT %.2fs  POST_FINAL %.2fs" % [inter, ambient, post])
	ck(inter > 0.0 and ambient > 0.0, "read the client's real pacing constants (not copies)")

	print("\n--- how long a round takes to PLAY, at the client's own pacing ---")
	var worst := 0.0
	for probe in [["Giant Spider", "multi_strike"], ["Wolf", "multi_strike"],
			["Goblin", "berserker"], ["Skeleton", "poison"]]:
		var n := _round_msgs(String(probe[0]), String(probe[1]))
		if n <= 0:
				# Say WHY, not a guessed why. The first version printed "no such monster" for what
			# was actually a wrong function name - an error reported as the wrong cause, the
			# exact shape this repo keeps getting bitten by.
			print("    %s: round produced no messages - check the combat call, not the name" % probe[0])
			continue
		# Attack lines carry INTER_ATTACK; the last one carries POST_FINAL.
		var secs := float(maxi(0, n - 1)) * inter + post
		worst = maxf(worst, secs)
		print("    %-14s worst round = %2d messages -> %.2fs of playback" % [probe[0], n, secs])

	print("\n--- and the bar does not move until that playback ENDS ---")
	var src := FileAccess.get_file_as_string("res://client/client.gd")
	ck(src.contains("if _coop_playback_pending() and not from_beat:"),
		"update_player_hp_bar is gated on playback - correct, and deliberate since 2026-09-02")
	ck(src.contains("_settle_combat_bars()"), "bars settle only when the queue empties")

	print("
--- so that is the window a player stares at a hand they cannot play ---")
	print("    up to %.1fs, with the HP bar still reading the PREVIOUS round" % worst)
	# Where the refusal actually lives - NOT here. See the correction below.
	var a := src.find("func send_combat_command(")
	var body := src.substr(a, src.find("\nfunc ", a + 10) - a) if a >= 0 else ""
	ck(a >= 0, "found send_combat_command")
	# CORRECTION, same day. My first pass read send_combat_command's body, found no playback
	# check, and reported "in SOLO nothing gates the press". Wrong UNIT: the gate is one level
	# UP, in `trigger_action` (hotkey) and `_on_combat_card_played` (mouse), and it has been
	# there since 2026-09-04. Input was never ungated. What was missing was any SIGN of it.
	ck(src.contains("func _combat_input_gated() -> bool:"), "the animation gate exists")
	var trig := src.find("func trigger_action(")
	var trig_body := src.substr(trig, src.find("
func ", trig + 10) - trig) if trig >= 0 else ""
	ck(trig_body.contains("_combat_input_gated()"), "the hotkey path refuses during playback")
	var click := src.find("func _on_combat_card_played(")
	var click_body := src.substr(click, src.find("
func ", click + 10) - click) if click >= 0 else ""
	ck(click_body.contains("_combat_input_gated()"), "and so does the mouse path")

	print("")
	print("--- ...and now the player can SEE it, which is the half that was missing ---")
	# Every combat card slot, not just the server-pushed hand: _get_combat_ability_actions
	# falls back to two legacy branches that build the same buttons.
	var dimmed := src.count('"enabled": has_resource and not _combat_input_gated(),')
	ck(dimmed == 3, "all 3 card-slot builders dim while the round plays - got %d" % dimmed)
	ck(src.contains("set_hand_gated(_gated)"), "the combat panel's hand is dimmed too")
	var panel := FileAccess.get_file_as_string("res://client/combat_scene_panel.gd")
	ck(panel.contains("and not _hand_gated"),
		"a gated card renders as uncastable - the state the panel already had for this")
	ck(panel.contains("to skip ahead"),
		"and the hand says HOW to skip - the fast-forward existed but was never advertised")

	print("")
	print("--- the dimming must never outlive the reason for it ---")
	var proc := src.find("_combat_hand_gated_shown = _gated")
	ck(proc >= 0, "the gate UI is driven from one tick, not from each enqueue site")
	# Driving it off `in_combat` would strand the hand dimmed: in_combat is cleared at
	# combat_end while the round is still animating. That is the exact trap _combat_ui_busy
	# was created for, and six separate bugs walked into it before.
	var seg := src.substr(maxi(0, proc - 900), 900)
	ck(not seg.contains("if in_combat:"),
		"...and NOT off `in_combat`, which is cleared while the round is still playing")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
