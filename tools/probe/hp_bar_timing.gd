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

	print("\n--- so this is the window, and nothing guards it ---")
	print("    a player can act for ~%.1fs while their HP bar still shows the PREVIOUS round" % worst)
	# The real finding: send_combat_command gates on connected / in_combat / party turn, and on
	# nothing else. In SOLO there is no playback check at all.
	var a := src.find("func send_combat_command(")
	var body := src.substr(a, src.find("\nfunc ", a + 10) - a) if a >= 0 else ""
	ck(a >= 0, "found send_combat_command")
	ck(body.contains("if not in_combat:") and body.contains("_party_action_blocked()"),
		"send_combat_command gates on connection, on being in combat, and on your party turn")
	# NOT a check - an OPEN FINDING, printed with its number so the decision is the owner's.
	# Turning it into a failing assertion would be asserting a fix nobody has chosen: the
	# options (gate the cards until the round has played, fast-forward on the press, or leave
	# it) are materially different games, not implementation details.
	var guarded: bool = body.contains("_combat_playback_active(") or body.contains("_combat_fastforward")
	print("")
	if not guarded:
		print("    FINDING: in SOLO nothing gates the press. send_combat_command checks connected,")
		print("    in_combat and the party turn - and no playback state. So for up to %.1fs the" % worst)
		print("    cards are live while the bar still reads the PREVIOUS round's HP. The owner")
		print("    hedged with \"I may have been moving too fast\" - at %.1fs, they were not." % worst)
	else:
		print("    A playback guard is now present in send_combat_command.")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
