extends SceneTree
## ⛑ DOES EVERY CRAFTING FOCUS HAVE A FIELD SERVICE, AND DOES EACH ONE DO SOMETHING?
##
## Owner 2026-09-18: *"we should try to have a similar type of specialisation service for each of
## the crafting focuses."* Two claims are being made and they fail differently:
##
##   1. COVERAGE  - every specialty job has a service. A job with none is the ask unfinished.
##   2. EFFECT    - every service measurably changes the character. A service that is offered and
##                  does nothing is the exact defect the card-upgrade redesign existed to remove,
##                  and the owner's words then were that the options were "useless or non working".
##
## ⛑ IT EXECUTES, IT DOES NOT READ. `card_upgrade_effects.gd` records why: a hand-maintained list
## of "wired" ids went stale and reported 23 upgrades unwired while several were plainly consumed.
## Reading source for the branch name would pass on a branch that returns a nice message and
## mutates nothing. So each service is run against a character in a KNOWN BAD state and the state
## is diffed afterwards.
##
## `chart_course` is the one that cannot be executed here - it needs live `active_dungeons` on a
## running server - so it is covered structurally and that limit is PRINTED rather than hidden.
##
## Run:
##   godot --headless --path . --script res://tools/probe/specialist_services.gd

const CharacterScript := preload("res://shared/character.gd")

var _fails: Array = []


func _fail(msg: String) -> void:
	_fails.append(msg)
	print("  FAIL  %s" % msg)


func _ok(msg: String) -> void:
	print("  ok    %s" % msg)


func _make(level: int = 12):
	var ch = CharacterScript.new()
	ch.initialize("Probe", "Fighter", "Human")
	for _i in range(level - 1):
		ch.level_up()
	return ch


func _init() -> void:
	seed(4242)
	print("")
	print("===== 1. COVERAGE: one service per specialty job =====")
	var jobs: Array = CharacterScript.SPECIALTY_JOBS
	var svc_ids: Array = []
	for job in jobs:
		var svc: Dictionary = CharacterScript.SPECIALIST_SERVICES.get(job, {})
		if svc.is_empty():
			_fail("%s has no field service" % job)
			continue
		var sid := String(svc.get("id", ""))
		var sname := String(svc.get("name", ""))
		if sid == "" or sname == "":
			_fail("%s service is missing an id or a name" % job)
			continue
		if sid in svc_ids:
			# Two jobs sharing an id means one of them silently performs the other's trade.
			_fail("%s reuses service id '%s'" % [job, sid])
		svc_ids.append(sid)
		_ok("%-10s -> %-14s (%s)" % [job, sid, sname])
	# The reverse direction too: a service defined for a job that does not exist is dead weight
	# that reads as coverage.
	for key in CharacterScript.SPECIALIST_SERVICES.keys():
		if not (String(key) in jobs):
			_fail("SPECIALIST_SERVICES has '%s', which is not a specialty job" % key)

	print("")
	print("===== 2. EFFECT: each service changes a character in a known bad state =====")

	# --- field_repair: worn gear -> wear 0 -------------------------------------------------
	var ch = _make()
	var worn := 0
	for slot in ch.equipped.keys():
		if ch.equipped[slot] is Dictionary and not ch.equipped[slot].is_empty():
			ch.equipped[slot]["wear"] = 0.4
			worn += 1
	if worn == 0:
		# ⛑ NOT A SKIP. A starting character with no equipment would make this test vacuous and
		# it would pass forever while field_repair was broken.
		ch.equipped["weapon"] = {"name": "Probe Blade", "wear": 0.4}
		worn = 1
	var msg_repair := ch.apply_specialist_service("field_repair")
	var still_worn := 0
	for slot in ch.equipped.keys():
		if ch.equipped[slot] is Dictionary and float(ch.equipped[slot].get("wear", 0.0)) > 0.0:
			still_worn += 1
	if still_worn > 0:
		_fail("field_repair left %d of %d pieces worn" % [still_worn, worn])
	elif msg_repair == "":
		_fail("field_repair mended gear but returned no message")
	else:
		_ok("field_repair  %d worn -> 0 worn" % worn)
	# ⛑ And it must report honestly when there was nothing to do, or a player burns a 3-minute
	# cooldown on a no-op and is told it worked.
	var idle_repair := ch.apply_specialist_service("field_repair")
	if idle_repair.find("Nothing") < 0:
		_fail("field_repair on undamaged gear did not say it did nothing (got: %s)" % idle_repair)
	else:
		_ok("field_repair  reports honestly when nothing is worn")

	# --- field_remedy: hurt + poisoned -> whole ---------------------------------------------
	var ch2 = _make()
	ch2.current_hp = maxi(1, int(ch2.get_total_max_hp() / 4))
	ch2.poison_active = true
	ch2.poison_turns_remaining = 5
	# Blinded and drained too, because the post healer fixes all of it and a probe that only
	# poisons cannot tell a complete mirror from the half that shipped first.
	ch2.blind_active = true
	ch2.current_mana = 0
	var hp_before: int = ch2.current_hp
	var msg_remedy := ch2.apply_specialist_service("field_remedy")
	if ch2.blind_active:
		_fail("field_remedy left blindness uncured -- the post healer cures it")
	if ch2.current_mana < ch2.get_total_max_mana():
		_fail("field_remedy did not refill mana -- the post healer does")
	if ch2.current_hp <= hp_before:
		_fail("field_remedy did not raise HP (%d -> %d)" % [hp_before, ch2.current_hp])
	elif ch2.poison_active or ch2.poison_turns_remaining > 0:
		_fail("field_remedy left the poison running")
	elif msg_remedy == "":
		_fail("field_remedy healed but returned no message")
	else:
		_ok("field_remedy  hp %d -> %d, poison cleared" % [hp_before, ch2.current_hp])
	# ⛑ IT MUST NOT EXCEED THE SHRINE. Healing past max would make the post service strictly
	# worse than a friend, which is the "convenience, not content" line being crossed.
	if ch2.current_hp > ch2.get_total_max_hp():
		_fail("field_remedy healed ABOVE max hp (%d > %d)" % [ch2.current_hp, ch2.get_total_max_hp()])
	else:
		_ok("field_remedy  does not exceed max hp")

	# --- recharge: all three pools drained -> full -------------------------------------------
	var ch3 = _make()
	ch3.current_mana = 0
	ch3.current_stamina = 0
	ch3.current_energy = 0
	var msg_recharge := ch3.apply_specialist_service("recharge")
	var short: Array = []
	if ch3.current_mana < ch3.get_total_max_mana():
		short.append("mana")
	if ch3.current_stamina < ch3.get_total_max_stamina():
		short.append("stamina")
	if ch3.current_energy < ch3.get_total_max_energy():
		short.append("energy")
	if not short.is_empty():
		_fail("recharge left %s below max" % ", ".join(short))
	elif msg_recharge == "":
		_fail("recharge filled the pools but returned no message")
	else:
		_ok("recharge      mana/stamina/energy 0 -> %d/%d/%d" % [
			ch3.current_mana, ch3.current_stamina, ch3.current_energy])

	# --- make_camp: safe passage steps granted, and never REDUCED ----------------------------
	var ch4 = _make()
	ch4.safe_passage_steps = 0
	var msg_camp := ch4.apply_specialist_service("make_camp")
	if ch4.safe_passage_steps <= 0:
		_fail("make_camp granted no safe passage steps")
	elif msg_camp == "":
		_fail("make_camp granted steps but returned no message")
	else:
		_ok("make_camp     safe passage 0 -> %d steps" % ch4.safe_passage_steps)
	# ⛑ A camp must never SHORTEN a scroll already running. maxi() is what prevents it, and a
	# future edit to `=` would be invisible without this.
	ch4.safe_passage_steps = 400
	ch4.apply_specialist_service("make_camp")
	if ch4.safe_passage_steps < 400:
		_fail("make_camp CUT an active safe passage (400 -> %d)" % ch4.safe_passage_steps)
	else:
		_ok("make_camp     does not shorten a longer passage already running")

	# --- an unknown id must do nothing and say nothing ---------------------------------------
	var ch5 = _make()
	if ch5.apply_specialist_service("not_a_service") != "":
		_fail("an unknown service id returned a message")
	else:
		_ok("unknown id    returns \"\"")

	print("")
	print("===== 3. EVERY SERVICE ID IS REACHABLE =====")
	# ⛑ The four above are proven by execution. This catches the fifth, and any service added to
	# the table later that nobody wires up - the "offered but read by nothing" shape.
	var char_src := FileAccess.get_file_as_string("res://shared/character.gd")
	var srv_src := FileAccess.get_file_as_string("res://server/server.gd")
	for job in jobs:
		var sid := String(CharacterScript.SPECIALIST_SERVICES.get(job, {}).get("id", ""))
		if sid == "":
			continue
		var quoted := "\"%s\"" % sid
		# A branch in the Character effects OR an explicit branch on the server.
		var in_char := char_src.find("\t\t" + quoted + ":") >= 0
		var in_srv := srv_src.find(quoted) >= 0
		if in_char or in_srv:
			_ok("%-14s reachable (%s)" % [sid, "Character" if in_char else "server"])
		else:
			_fail("%s is offered to players and nothing performs it" % sid)

	print("")
	print("===== 4. THE ROUTE EXISTS =====")
	# ⛑ Six times this arc a capability was built and the route was missing - party invite, Duel
	# for Valor, the fight log, the death log, the Bestiary Page, the bestiary reader. It is the
	# single most repeated defect here, so it gets a check rather than a glance.
	var client_src := FileAccess.get_file_as_string("res://client/client.gd")
	var checks := {
		"server route registered": srv_src.find("\"specialist_service\":") >= 0,
		"server handler defined": srv_src.find("func handle_specialist_service(") >= 0,
		"client sends the message": client_src.find("{\"type\": \"specialist_service\"") >= 0,
		"client has a button": client_src.find("\"action_data\": \"specialist_service\"") >= 0,
		"client handles the click": client_src.find("\"specialist_service\":") >= 0,
		"ally variant wired": client_src.find("\"specialist_service_ally\":") >= 0,
	}
	for k in checks.keys():
		if bool(checks[k]):
			_ok(String(k))
		else:
			_fail("%s -- MISSING" % k)

	print("")
	print("===== LIMITS OF THIS PROBE =====")
	print("  chart_course is checked structurally only: it reads live active_dungeons on a")
	print("  running server, which this probe has none of. Its arithmetic is shared with")
	print("  handle_dungeon_locate (_compass_direction + cartography_locate_precision).")
	print("  Cooldown and adjacency are enforced in handle_specialist_service, which needs a")
	print("  live peer table; neither is executed here.")
	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for f in _fails:
			print("   - %s" % f)
		quit(1)
		return
	print("[PROBE] PASS %d specialty jobs each have a service; 4 of 5 proven by execution," % jobs.size())
	print("       all 5 reachable, and the client/server route is complete.")
	quit()
