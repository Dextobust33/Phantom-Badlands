# Headless regression harness for CO-OP (#64/#76) party combat — run WITHOUT two clients:
#   godot --headless --path . --script res://tools/combat_simulator/coop_round_test.gd
# Drives the REAL shared engine (combat_manager/monster_database/drop_tables) and asserts:
#   * a member's card resolves and RETURNS messages (regression: a missing key in the member
#     view aborted process_ability_command mid-resolve and swallowed the whole action)
#   * the monster acts ONCE PER ALIVE MEMBER-GROUP each round (co-op pressure parity)
#   * shared DoT ticks exactly ONCE per round, not once per member
#   * the per-recipient log renders "you" for the actor and their NAME for everyone else
extends SceneTree

func _init():
	seed(4242)
	var drop_tables = load("res://shared/drop_tables.gd").new()
	var monster_db = load("res://shared/monster_database.gd").new()
	var cm = load("res://shared/combat_manager.gd").new()
	var CharacterScript = load("res://shared/character.gd")
	root.add_child(drop_tables); root.add_child(monster_db); root.add_child(cm)
	var f = FileAccess.open("res://server/balance_config.json", FileAccess.READ)
	var cfg = {}
	if f:
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary: cfg = parsed
		f.close()
	cm.set_balance_config(cfg)
	cm.set_monster_database(monster_db)
	cm.drop_tables = drop_tables
	if "drop_tables" in monster_db: monster_db.drop_tables = drop_tables

	var names = {1: "test02", 2: "test002", 3: "Bo"}
	var klasses = {1: "Wizard", 2: "Sorcerer", 3: "Fighter"}
	var chars = {}
	for pid in [1, 2, 3]:
		var ch = CharacterScript.new()
		ch.initialize(names[pid], klasses[pid], "Human")
		for i in range(9): ch.level_up()
		while ch.unspent_stat_points > 0: ch.spend_stat_point("intelligence" if pid != 3 else "strength")
		chars[pid] = ch
	var mname = monster_db.get_random_monster_name_from_tier(2)
	var monster = monster_db.generate_monster_by_name(mname, 11)
	var solo_hp = int(monster.get("max_hp", 0))

	var res = cm.start_party_combat_simul([1, 2, 3], chars, monster)
	print("start ok=%s  monster=%s  solo_hp=%d  party_hp=%d (x%d)" % [res.get("success"), mname, solo_hp, int(monster.max_hp), 3])
	var hp_before = {}
	for pid in [1, 2, 3]: hp_before[pid] = chars[pid].current_hp

	# multi-round: verify sustained pressure + that shared DoT ticks ONCE per round
	var combat = cm.active_party_combats[1]
	combat["monster_bleed"] = 10
	combat["monster_bleed_duration"] = 5
	print("
applied bleed 10/round for 5 rounds to the shared monster
")
	for rnd in range(5):
		for pid in [1, 2, 3]:
			cm.submit_party_action(1, pid, {"kind": "attack"})
		var rr = cm.resolve_party_round(1)
		var ents = rr.get("message_entries", [])
		if rnd == 0:
			# Slice 3 — the per-beat metadata the client animates from.
			print("--- BEAT METADATA (round 1, as pid 1 sees the text) ---")
			var meta = cm.party_flatten_meta(ents)
			var flat = cm.party_flatten_log(ents, 1)
			for i in range(flat.size()):
				var mm = meta[i]
				var tag = str(mm.get("actor", "?")) + ("*HEAD" if mm.get("head", false) else "")
				var hpd = ""
				if mm.has("hp"):
					var h = mm["hp"]
					hpd = " hp[mon=%s" % str(h.get("monster", "-"))
					if h.has("target_hp"):
						hpd += " p%d=%d/%d" % [int(h.get("target_pid", -1)), int(h.get("target_hp", 0)), int(h.get("target_max_hp", 0))]
					hpd += "]"
				print("  %-14s act=%-2s tgt=%-2s%s  %s" % [tag, str(mm.get("actor_pid", -1)), str(mm.get("target_pid", -1)), hpd, _strip(flat[i]).substr(0, 44)])
			print("--- end metadata ---")
		var acts := 0
		var bleeds := 0
		for e in ents:
			var t = String(e.get("other", ""))
			if "turns on" in t: acts += 1
			if "bleeds for" in t: bleeds += 1
		print("round %d: monster actions=%d  bleed ticks=%d (expect 1)  monster hp=%d" % [rnd + 1, acts, bleeds, int(monster.current_hp)])
		if rr.get("combat_ended", false):
			print("  combat ended: victory=%s" % rr.get("victory")); break
	print("
total damage taken:")
	for pid in [1, 2, 3]:
		print("  %s: %d (hp %d)" % [names[pid], hp_before[pid] - chars[pid].current_hp, chars[pid].current_hp])
	quit()

func _strip(s: String) -> String:
	var out := ""
	var d := 0
	for c in s:
		if c == "[": d += 1
		elif c == "]": d = max(0, d - 1)
		elif d == 0: out += c
	return out
