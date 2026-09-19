extends SceneTree
## ⛑ DOES A DEATH IN A PARTY RECORD WHAT ACTUALLY HAPPENED?
##
## Measured on the LIVE death log, 2026-09-19: **7 of 50 deaths had no fight in them at all** —
## `rounds 0`, `player_hp_at_start 0`, zero damage dealt and zero taken. Not a 0 HP fight: an
## absent argument. `handle_permadeath(peer_id, cause, combat_data := {})` takes the fight as an
## OPTIONAL parameter, and both party death paths passed nothing.
##
## ⚡ WHY THIS IS A BALANCE BUG, NOT A LOGGING ONE. Every field in the record defaults to 0, so a
## blank is indistinguishable from a character who entered combat at 0 HP and was killed before
## acting. `death_log_audit.py` printed each one under **"AT PARITY — these are the curve's, not
## the player's"** — three of that section's fourteen rows. That section is the strongest evidence
## available that the early curve is too hard, and a fifth of it was manufactured by a missing
## function argument. The early-game nerf that evidence would have justified is a change nobody
## needed.
##
## WHAT THIS ASSERTS:
##   1. the party summary carries the MEMBER's own numbers, not zeros and not the party's total
##   2. it uses exactly the keys the solo summary uses, since one consumer reads both
##   3. ⚑ it is taken in `_party_collect_fallen` — NOT where the death is recorded
##   4. a record can tell "no fight recorded" apart from "a fight of zeros"
##
## ⛑ (3) IS THE ONE THAT WOULD HAVE BITTEN. `_party_kill_fallen` runs after the round is sent,
## and a WIPE tears down `active_party_combats` before then — which is why collect and kill are
## split at all. It also erases the member's `party_combat_membership`. Asking for the summary
## there returns an empty dictionary and silently re-creates the exact bug, while looking like
## the fix.
##
## Run:
##   godot --headless --path . --script res://tools/probe/a_party_death_records_its_fight.gd

const CombatManagerScript := preload("res://shared/combat_manager.gd")

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


func _init() -> void:
	var cm := CombatManagerScript.new()

	print("")
	print("===== 1. THE SUMMARY CARRIES THIS MEMBER'S FIGHT =====")
	# Two members with DIFFERENT numbers, so a party-wide total cannot pass by accident.
	var combat := {
		"round": 6,
		"combat_log": ["a", "b"],
		"monster": {"name": "Dire Wolf", "base_name": "Wolf", "level": 3, "max_hp": 140},
		"member_states": {
			11: {"player_hp_at_start": 64, "total_damage_dealt": 120, "total_damage_taken": 90},
			22: {"player_hp_at_start": 200, "total_damage_dealt": 5, "total_damage_taken": 7},
		},
	}
	var s: Dictionary = cm.get_party_combat_summary(combat, 11)
	print("  member 11 -> rounds=%s hp_at_start=%s dealt=%s taken=%s monster=%s Lv%s"
		% [s.get("rounds"), s.get("player_hp_at_start"), s.get("total_damage_dealt"),
			s.get("total_damage_taken"), s.get("monster_name"), s.get("monster_level")])
	if int(s.get("rounds", 0)) != 6:
		_fail("rounds came back %s, not the combat's 6" % s.get("rounds"))
	else:
		_ok("the round count is the fight's")
	if int(s.get("player_hp_at_start", 0)) != 64:
		_fail("hp_at_start came back %s - this is the blank that caused the bug" % s.get("player_hp_at_start"))
	else:
		_ok("HP at start is this member's own")
	# ⛑ THE TELL FOR A PARTY-WIDE SUM: 120+5 = 125. "How much of its own bar this character had"
	# is the question the death log exists to answer; a party total answers a different one.
	if int(s.get("total_damage_dealt", 0)) == 125:
		_fail("damage dealt is the PARTY's total (125), not this member's 120")
	elif int(s.get("total_damage_dealt", 0)) != 120:
		_fail("damage dealt came back %s, expected 120" % s.get("total_damage_dealt"))
	else:
		_ok("damage is per member, not the party's total")
	if String(s.get("monster_base_name", "")) != "Wolf":
		_fail("the monster's base name is missing - the audit groups kills by it")
	else:
		_ok("the killer is named")

	print("")
	print("===== 2. A MEMBER WITH NO STATE IS NOT INVENTED =====")
	var missing: Dictionary = cm.get_party_combat_summary(combat, 99)
	if int(missing.get("player_hp_at_start", -1)) != 0:
		_fail("a member with no state produced a fabricated HP")
	else:
		_ok("an unknown member yields zeros rather than erroring")

	print("")
	print("===== 3. THE SAME KEYS AS THE SOLO SUMMARY =====")
	# One consumer reads both. A party death spelling a key differently would be
	# indistinguishable from one that recorded nothing - this bug in a different hat.
	var src := FileAccess.get_file_as_string("res://shared/combat_manager.gd")
	var i := src.find("func get_combat_summary(")
	var j := src.find("func get_party_combat_summary(")
	if i < 0 or j < 0:
		_fail("one of the two summary functions is gone")
	else:
		var solo := src.substr(i, src.find("\nfunc ", i + 8) - i)
		var party := src.substr(j, src.find("\nfunc ", j + 8) - j)
		var rx := RegEx.new()
		rx.compile('"([a-z_]+)":')
		var solo_keys := {}
		for m in rx.search_all(solo):
			solo_keys[m.get_string(1)] = true
		var party_keys := {}
		for m in rx.search_all(party):
			party_keys[m.get_string(1)] = true
		var missing_keys: Array = []
		for k in solo_keys.keys():
			if not party_keys.has(k):
				missing_keys.append(k)
		print("  solo keys %d, party keys %d" % [solo_keys.size(), party_keys.size()])
		if not missing_keys.is_empty():
			_fail("the party summary is missing %s - a party death would be blank in those fields"
				% str(missing_keys))
		else:
			_ok("every key the solo summary writes, the party summary writes")

	print("")
	print("===== 4. IT IS TAKEN WHERE THE COMBAT STILL EXISTS =====")
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	var c := srv.find("func _party_collect_fallen(")
	var k := srv.find("func _party_kill_fallen(")
	if c < 0 or k < 0:
		_fail("the party death path has been restructured - re-check where the summary is taken")
	else:
		var collect := srv.substr(c, srv.find("\nfunc ", c + 8) - c)
		var kill := srv.substr(k, srv.find("\nfunc ", k + 8) - k)
		# Matched on the CALL, never a nearby word: two probes passed this week while reading a
		# comment that named the thing being checked.
		if collect.find("get_party_combat_summary(combat, pid)") < 0:
			_fail("the summary is no longer taken in _party_collect_fallen. Taking it in "
				+ "_party_kill_fallen returns nothing - the combat is torn down by then on a "
				+ "wipe, and this member's party_combat_membership has already been erased")
		else:
			_ok("the summary is taken while the combat is still in hand")
		if kill.find('entry.get("summary"') < 0:
			_fail("_party_kill_fallen no longer passes the summary on - it is collected and dropped")
		else:
			_ok("and handed to handle_permadeath")

	print("")
	print("===== 5. A BLANK IS DISTINGUISHABLE FROM A FIGHT OF ZEROS =====")
	var h := srv.find('"has_combat_detail"')
	if h < 0:
		_fail("the death record no longer stamps has_combat_detail - a future path that forgets "
			+ "the fight will look like a one-shot at parity again, exactly as before")
	else:
		_ok("the record says whether a fight was recorded at all")

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS a party death records its own fight, in the same shape a solo death does,")
	print("       taken while the combat still exists.")
	quit()
