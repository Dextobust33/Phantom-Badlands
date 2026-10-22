extends SceneTree
## THE TIMING WINDOW (docs/design/combat_loop_variety.md section 12): while a boss burst winds up, a well-timed Brace / Ward / Slip is a bigger guard.
## Server side: the graded reduction, the rules that keep it a pure upside (ignored with no burst pending, ignored when garbled, clamped), the parry's rider cancel, and the state the client
## needs. Client side: the bar's quality maths and that the press carries it.
const CombatManagerScript := preload("res://shared/combat_manager.gd")
const CharacterScript := preload("res://shared/character.gd")
const MonsterDB := preload("res://shared/monster_database.gd")
const PanelScript := preload("res://client/combat_scene_panel.gd")
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _fight(cm, db, ability: String, period: int) -> Dictionary:
	var ch = CharacterScript.new()
	ch.initialize("Probe", "Barbarian", "Human")
	seed(hash("%s|%d" % [ability, period]))
	var mon: Dictionary = db.generate_monster(20, 20)
	mon["empowered_mods"] = []
	mon["abilities"] = [ability]
	mon["max_hp"] = 999999
	mon["current_hp"] = 999999
	mon["strength"] = 1
	mon["attack"] = 1
	cm.start_combat(0, ch, mon)
	ch.current_hp = ch.get_total_max_hp()
	var combat: Dictionary = cm.active_combats[0]
	combat["round"] = period
	return {"combat": combat, "char": ch}

func _burst_damage(cm, db, ability: String, period: int, command: String) -> Array:
	"""[damage the burst did, the brace result]: wind-up round, then the player answers with `command`, then the burst resolves."""
	var f: Dictionary = _fight(cm, db, ability, period)
	var combat: Dictionary = f["combat"]
	var ch = f["char"]
	cm._process_monster_turn_inner(combat)             # the wind-up
	combat["player_can_act"] = true
	ch.current_hp = ch.get_total_max_hp()
	var before: int = ch.current_hp
	var res: Dictionary = cm.process_combat_command(0, command)   # the answer, and the monster's turn that follows it
	combat = cm.active_combats[0]
	combat["round"] = int(combat["round"]) + 1
	cm._process_monster_turn_inner(combat)             # in case the burst waits one more turn
	var lost: int = before - int(ch.current_hp)
	var out := [lost, res, combat, ch]
	return out

func _init() -> void:
	var cm := CombatManagerScript.new()
	var db := MonsterDB.new()
	root.add_child(cm)

	print("--- the graded guard ---")
	var plain: Array = _burst_damage(cm, db, "boss_aerial_dive", 4, "brace")
	cm.active_combats.erase(0)
	var good: Array = _burst_damage(cm, db, "boss_aerial_dive", 4, "brace 60")
	cm.active_combats.erase(0)
	var perfect: Array = _burst_damage(cm, db, "boss_aerial_dive", 4, "brace 92")
	cm.active_combats.erase(0)
	var lp: int = int(plain[0])
	var lg: int = int(good[0])
	var lf: int = int(perfect[0])
	ck(lp > 0 and lg < lp and lf < lg, "the burst lands softer the better the press: plain %d, well-timed %d, perfect %d" % [lp, lg, lf])
	# The exact numbers, with the ordinary hit out of the way: a burst of 1000 through each guard.
	var mit := []
	for timing in [-1, 60, 92]:
		var fm: Dictionary = _fight(cm, db, "boss_aerial_dive", 4)
		cm._process_monster_turn_inner(fm["combat"])      # a burst is now pending
		fm["char"].active_buffs.clear()
		cm.process_brace(fm["combat"], timing)
		mit.append(cm._mitigate_burst(fm["char"], 1000))
		cm.active_combats.erase(0)
	ck(mit == [600, 450, 300], "a burst of 1000 through a plain / well-timed / perfect guard is %s (want 600 / 450 / 300)" % str(mit))
	ck(String(perfect[1].get("message", "")).find("PERFECT") >= 0 or JSON.stringify(perfect[1]).find("PERFECT") >= 0, "the log says PERFECT")
	ck(String(good[1].get("message", "")).find("WELL-TIMED") >= 0 or JSON.stringify(good[1]).find("WELL-TIMED") >= 0, "...and WELL-TIMED for the middle grade")

	print("--- it can only ever help ---")
	var low: Array = _burst_damage(cm, db, "boss_aerial_dive", 4, "brace 10")
	cm.active_combats.erase(0)
	ck(abs(int(low[0]) - lp) <= 1, "a badly timed press is exactly the plain guard (%d vs %d) - never worse" % [int(low[0]), lp])
	var junk: Array = _burst_damage(cm, db, "boss_aerial_dive", 4, "brace banana")
	cm.active_combats.erase(0)
	ck(abs(int(junk[0]) - lp) <= 1, "a garbled argument is the plain guard (%d)" % int(junk[0]))
	var huge: Array = _burst_damage(cm, db, "boss_aerial_dive", 4, "brace 9999")
	cm.active_combats.erase(0)
	ck(abs(int(huge[0]) - lf) <= 1, "an out-of-range claim is clamped to 100, no better than a perfect press (%d vs %d)" % [int(huge[0]), lf])
	# no burst pending: the number is ignored
	var f: Dictionary = _fight(cm, db, "boss_aerial_dive", 1)   # round 1: nothing winds up
	f["combat"]["player_can_act"] = true
	var ch0 = f["char"]
	ch0.active_buffs.clear()
	cm.process_brace(f["combat"], 99)
	ck(ch0.get_buff_value("damage_reduction") == CombatManagerScript.BRACE_DAMAGE_REDUCTION, "with NO burst pending a 99 is ignored: the guard is the plain %d%% (%d%%)" % [CombatManagerScript.BRACE_DAMAGE_REDUCTION, ch0.get_buff_value("damage_reduction")])
	cm.active_combats.erase(0)

	print("--- a parry denies the rider ---")
	var st: Array = _burst_damage(cm, db, "boss_tremor_stomp", 3, "brace 95")
	cm.active_combats.erase(0)
	var st_plain: Array = _burst_damage(cm, db, "boss_tremor_stomp", 3, "brace")
	var lulled_plain: bool = bool(st_plain[2].get("player_lulled", false))
	cm.active_combats.erase(0)
	ck(not bool(st[2].get("player_lulled", false)) and lulled_plain, "Tremor Stomp's stagger lands on a plain guard (%s) and is denied by a perfect one (%s)" % [lulled_plain, bool(st[2].get("player_lulled", false))])

	print("--- what the client is told ---")
	var f2: Dictionary = _fight(cm, db, "boss_aerial_dive", 4)
	cm._process_monster_turn_inner(f2["combat"])
	var info: Dictionary = cm._combat_status_view(f2["char"], f2["combat"]) if cm.has_method("_combat_status_view") else {}
	var ms: Dictionary = {}
	for m in ["_combat_status_view", "combat_status_for_client", "_status_payload"]:
		if cm.has_method(m):
			ms = cm.call(m, f2["char"], f2["combat"]).get("monster_status", {})
			break
	if ms.is_empty():
		# the builder is private to the manager; read it by the source instead
		var src: String = FileAccess.get_file_as_string("res://shared/combat_manager.gd")
		ck(src.contains("\"burst_pending\": String(combat.get(\"pending_burst_ability\", \"\"))") and src.contains("\"burst_text\":"), "the monster status carries burst_pending and burst_text for the client")
	else:
		ck(String(ms.get("burst_pending", "")) == "boss_aerial_dive" and String(ms.get("burst_text", "")).find("circling") >= 0, "the monster status says which burst winds up and how to word it")
	cm.active_combats.erase(0)

	print("--- the bar ---")
	var bar = PanelScript.TimingBar.new()
	bar.begin("test")
	# put the marker exactly on the zone centre: a ping-pong at phase t has position 1 - |2t - 1|, so the centre c is at t = (1 - c) / 2 on the way up
	var c: float = PanelScript.TimingBar.ZONE_CENTER
	var t_centre: float = (1.0 - (1.0 - c)) / 2.0 * 0.0 + c / 2.0
	bar.started_ms = Time.get_ticks_msec() - int(t_centre * PanelScript.TimingBar.PERIOD_MS)
	var q_centre: int = bar.quality()
	bar.started_ms = Time.get_ticks_msec()   # t = 0: the marker is at the far left
	var q_edge: int = bar.quality()
	ck(q_centre >= 95 and q_edge <= 5, "on the zone's centre the press grades %d, at the far edge %d" % [q_centre, q_edge])
	bar.finish()
	ck(bar.quality() == -1, "a closed bar grades nothing (-1)")
	var csrc: String = FileAccess.get_file_as_string("res://client/client.gd")
	var i: int = csrc.find("func send_combat_command(")
	var body: String = csrc.substr(i, csrc.find("\nfunc ", i + 10) - i)
	ck(body.contains("command in CombatManagerScript.BRACE_COMMANDS") and body.contains("burst_timing_quality()") and body.contains("command = \"%s %d\" % [command, _tq]"), "send_combat_command attaches the grade to a brace command")
	var pbody: String = FileAccess.get_file_as_string("res://client/combat_scene_panel.gd")
	var j: int = pbody.find("func burst_timing_quality(")
	var jb: String = pbody.substr(j, pbody.find("\nfunc ", j + 10) - j)
	ck(jb.contains("_timing_bar.finish()"), "reading the grade closes the window: one press, one grade")
	bar.free()
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
