extends SceneTree
# v0.9.696 WIP — headless combat sim driving the REAL shared code (Character,
# CombatManager, MonsterDatabase, DropTables) so balance data never drifts.
# Outputs avg turns-to-kill + win-rate across level × gear tier × enemy tier,
# with a representative active companion. Foundation for the tiered combat-length
# balance pass (Warrior Momentum etc.).

var drop_tables
var monster_db
var combat_mgr
var CharacterScript
# Cost-tier emulation: after each cast, drain EXTRA resource = spent×(_cost_mult-1)
# to model a higher-tier (pricier) version of the card WITHOUT editing the const
# cost table. Damage held at base → conservatively OVER-states drain (real higher
# tiers also hit harder → shorter fights → less total spend), a safe direction for
# finding the cost curve that restores early-game pressure. 1.0 = unchanged.
var _cost_mult: float = 1.0
# Martial DUMP emulation: after the finisher (Devastate / Gambit) resolves, drain this
# fraction of the CURRENT pool — models a dump finisher (consume the bar, damage scales
# with spend). 0 = off. Only the martial finisher branches apply it.
var _dump_pct: float = 0.0

const FIGHTS_PER_CELL := 200
const SLOTS := ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]
# Warrior damage cards, best→worst; the sim casts the highest-priority one that's
# actually in the drawn hand + affordable (the deck constraint is real). Buffs
# (war_cry/berserk/iron_skin/fortify/rally) are cast opportunistically for uptime.
const WARRIOR_DMG_PRIORITY := ["devastate", "cleave", "shield_bash", "power_strike"]
const WARRIOR_BUFFS := ["berserk", "war_cry"]

func _init():
	seed(20260824)  # reproducible run-to-run (gear affixes/crits/empowered are RNG)
	drop_tables = load("res://shared/drop_tables.gd").new()
	monster_db = load("res://shared/monster_database.gd").new()
	combat_mgr = load("res://shared/combat_manager.gd").new()
	CharacterScript = load("res://shared/character.gd")
	root.add_child(drop_tables)
	root.add_child(monster_db)
	root.add_child(combat_mgr)
	var cfg: Dictionary = {}
	var f = FileAccess.open("res://server/balance_config.json", FileAccess.READ)
	if f:
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			cfg = parsed
		f.close()
	combat_mgr.set_balance_config(cfg)
	combat_mgr.set_monster_database(monster_db)
	combat_mgr.drop_tables = drop_tables
	if "drop_tables" in monster_db:
		monster_db.drop_tables = drop_tables

	_run_selected_audits()
	quit()

# --- Audit selection -----------------------------------------------------------
# Pass audits after a bare `--`, e.g.
#   godot --headless --path . --script res://tools/combat_simulator/real_combat_sim.gd -- classes
# With no argument the default set runs. `list` prints the registry.
# Added #5 (2026-09-02): the file had grown ~20 audits that could only be selected by
# editing _init, so every measurement was a source edit + a lost diff.
const DEFAULT_AUDITS := ["verify", "min_spend", "difficulty", "overlevel"]

func _audit_registry() -> Dictionary:
	return {
		"verify": ["card + party wiring checks", func():
			_verify_new_mage_cards(); _verify_dungeon_cards(); _verify_party_combat()],
		"min_spend": ["min-cost cast vs same-level mob HP", run_min_spend_probe],
		"difficulty": ["level x gear x enemy-tier feel", run_difficulty_audit],
		"overlevel": ["how far above level a class can reach", run_overlevel_audit],
		"classes": ["all 9 classes: does each actually SPEND its cards?", run_class_audit],
		"focusgear": ["does chasing your resource affix change the class table?", run_focus_gear_audit],
		"gearsources": ["every stat gear can carry, where from, and what gates it", run_gear_sources_audit],
		"names": ["do all the tables agree on what each card is CALLED?", run_name_consistency_audit],
		"adjudicate": ["refcal vs roles: which win-rate measurement is right?", run_adjudicate_audit],
		"newplayer": ["what a character created TODAY actually faces at L1-L10", run_newplayer_audit],
		"grow": ["grow a character from creation the way a player must", run_grow_audit],
		"growdiag": ["is the grown character built correctly? (instrument check)", run_grow_diag],
		"growref": ["EARNED gear profile per level - the reference make_char should encode", run_grow_reference],
		"growtune": ["what monster nerf a grown player needs to hit target", run_grow_tune],
		"polytest": ["run warrior strategies head to head and pick the best", run_policy_test],
		"species": ["is the same level the same fight across monster types?", run_species_audit],
		"speciescal": ["calibrate per-species power into a band", run_species_calibrate],
		"races": ["all 8 races on one class", run_race_audit],
		"calibrate": ["make_char vs REAL saved characters", run_calibration_audit],
		"gear_solve": ["solve the average-gear model against real characters", run_gear_solve],
		"progression": ["does difficulty hold from L1 to L10000?", run_progression_audit],
		"underlevel": ["what fighting below your level is worth (post pull-down)", run_underlevel_audit],
		"selection": ["why the curve is jagged: tier bands vs monster base levels", run_selection_audit],
		"refcurve": ["measure the reference-player curve the monster model anchors to", run_reference_curve],
		"comphp": ["how much max HP the active companion adds, by level", run_companion_hp_probe],
		"compcap": ["verify the companion ceiling binds AND rarity still pays more", run_companion_cap_probe],
		"outcomes": ["classify how normal fights END (win / death / escape / stall)", run_outcome_probe],
		"spread": ["what progression is worth: gear vs companion vs difficulty", run_progression_spread],
		"gearpower": ["where the gear ladder goes flat: stat contribution per tier", run_gear_power_audit],
		"offer": ["does a rank-up actually deal a nine-card offer?", run_offer_probe],
		"art": ["every monster name checked against the ASCII art it resolves to", run_art_audit],
		"mcheck": ["anchor values vs what make_monster actually builds", run_monster_check],
		"forensics": ["why one anchor misses: what spawns there and what kills you", run_level_forensics],
		"actortag": ["verify every solo combat line is attributed to the right actor", run_actor_tag_probe],
		"deck": ["does playing a card actually change your hand next round?", run_deck_probe],
		"dmgtag": ["does each ability line carry its damage number in the metadata?", run_damage_tag_probe],
		"refval": ["validate the reference model: predicted vs actual fight length", run_reference_validate],
		"refcal": ["calibrate monster stats against REAL fights until they hit target", run_reference_calibrate],
		"rolecal": ["calibrate the elite/boss multipliers against real fights", run_role_calibrate],
		"roles": ["elite/boss fights vs their ROLE_TARGETS", run_role_audit],
		"fallback": ["does a win rate mean the same thing for every class?", run_fallback_audit],
		"xp": ["how many fights to level, and what is the best way", run_xp_audit],
		"risk": ["over-level gambles: kill/escape/death and what the reward is worth", run_risk_reward_audit],
		"companion": ["does levelling a companion keep paying?", run_companion_audit],
		"comp_unlock": ["what a companion actually does: survival, soak, unlock boundaries", run_companion_unlock_audit],
		"resource": ["resource-economy telemetry", run_resource_audit],
		"economy": ["is an ability cost real, or does regen cover it?", run_resource_economy_audit],
		"efficiency": ["damage per resource point by ability", run_ability_efficiency],
		"ability_hp": ["ability damage vs monster HP across all levels", run_ability_vs_hp],
		"flock": ["flock-chain sustain", run_flock_audit],
		"baseline": ["baseline matrix", run_baseline],
		"matrix": ["level x gear x enemy matrix", run_matrix],
		"mage": ["mage Focus ramp", run_mage_matrix],
		"trickster": ["trickster Read/Outsmart", run_trickster_matrix],
	}

func _run_selected_audits() -> void:
	var reg := _audit_registry()
	var wanted: Array = []
	for a in OS.get_cmdline_user_args():
		var arg := String(a).lstrip("-")
		if arg.begins_with("n="):
			_audit_n = maxi(1, int(arg.substr(2)))
			continue
		wanted.append(arg)
	if wanted.is_empty():
		wanted = DEFAULT_AUDITS.duplicate()
	if "list" in wanted or "help" in wanted:
		print("\nAudits (pass after `--`, space separated; `all` runs every one):")
		for k in reg.keys():
			print("  %-12s %s" % [k, reg[k][0]])
		print("  %-12s %s" % ["(default)", " ".join(DEFAULT_AUDITS)])
		print("")
		return
	if "all" in wanted:
		wanted = reg.keys()
	for name in wanted:
		if not reg.has(name):
			print("[sim] unknown audit '%s' — run with `-- list`" % name)
			continue
		# Reset to the REFERENCE PLAYER before every audit. The companion audits opt back in
		# via _use_companions_for_this_audit(); resetting here rather than restoring inside each
		# of them means an opt-in can never leak into whatever runs next, however the audits are
		# ordered on the command line.
		_companion_mode = "none"
		reg[name][1].call()

func _verify_party_combat() -> void:
	# #64 Slice 2 — verify the simultaneous engine: 2 members both hit the SHARED monster,
	# then the monster acts ONCE per round, and hands redraw for round 2.
	print("===== #64 PARTY COMBAT ENGINE CHECK =====")
	var ch0 = make_char(20, "average", "Fighter")
	var ch1 = make_char(20, "average", "Wizard")
	var chars := {0: ch0, 1: ch1}
	var monster = make_monster(20, "boss", 3.0)  # beefy so it survives one round
	var start = combat_mgr.start_party_combat_simul([0, 1], chars, monster)
	if not combat_mgr.active_party_combats.has(0):
		print("FAILED to start party combat"); return
	var m = combat_mgr.active_party_combats[0]
	var mhp0: int = int(m.monster.current_hp)
	var hp0b: int = ch0.current_hp
	var hp1b: int = ch1.current_hp
	print("started: monster max_hp=%d (x2 party), hands: ch0=%d ch1=%d cards" % [int(monster.get("max_hp", 0)), (m.member_states[0]["hand"] as Array).size(), (m.member_states[1]["hand"] as Array).size()])
	combat_mgr.submit_party_action(0, 0, {"kind": "attack"})
	var sub = combat_mgr.submit_party_action(0, 1, {"kind": "attack"})
	print("both submitted -> all_submitted=%s" % str(sub.get("all_submitted", false)))
	var res = combat_mgr.resolve_party_round(0)
	var mhp1: int = int(m.monster.current_hp)
	var monster_acted: bool = (ch0.current_hp < hp0b) or (ch1.current_hp < hp1b)
	print("round resolved: monster %d->%d (both hit shared target=%s) | ch0 %d->%d ch1 %d->%d (monster acted on 1=%s) | ended=%s round=%d" % [
		mhp0, mhp1, str(mhp1 < mhp0), hp0b, ch0.current_hp, hp1b, ch1.current_hp, str(monster_acted), str(res.get("combat_ended", false)), int(res.get("round", 0))])
	combat_mgr.active_party_combats.erase(0)
	combat_mgr.party_combat_membership.clear()
	ch0.in_combat = false
	ch1.in_combat = false
	print("=========================================")

func run_min_spend_probe() -> void:
	# #70 — the cheese the user hit: does a MINIMUM spend one-shot a same-level normal
	# monster? For each class + level, measure single-cast damage at the SMALLEST spend
	# vs the target's HP. Ratio >= 1.0 means a min-spend cast one-shots (trivialized).
	print("\n===== #70 MIN-SPEND ONE-SHOT PROBE (dmg of a minimum-cost cast vs same-level normal-mob HP) =====")
	print("ratio = min_cast_damage / monster_max_hp. >=1.0 = a single cheap cast one-shots. Also show cost.")
	var cases := [
		["Wizard", "Mag", "magic_bolt"],
		["Fighter", "War", "power_strike"],
		["Thief", "Trk", "ambush"],
	]
	for lvl in [3, 6, 10, 30, 100]:
		var line := "L%-4d" % lvl
		for c in cases:
			var ch = make_char(lvl, "average", c[0])
			# For magic_bolt the sim passes the spend as arg; use the SMALLEST (1 mana).
			# For variable-cost abilities the floor is enforced by apply_variable_cost.
			var monster = make_monster(lvl, "normal", 1.0)
			var mhp: int = int(monster.get("max_hp", 1))
			combat_mgr.start_combat(0, ch, monster)
			if not combat_mgr.active_combats.has(0):
				line += "  %s:n/a" % c[1]; continue
			var combat = combat_mgr.active_combats[0]
			_force_hand(combat, c[2])
			# Realistic SMALL spend: for Magic Bolt (free-choice), spend 10% of the mana pool
			# (a "little mana" cast, like the player report) — NOT the 1-mana theoretical floor.
			# Variable-cost martial/trickster abilities spend their enforced floor automatically.
			var pool10: int = max(1, int(ch.get_total_max_mana() * 0.10))
			var arg: String = str(pool10) if c[2] == "magic_bolt" else ""
			ch.set_meta("path_last_ability_cost", 0)
			var mhp0: int = int(monster.current_hp)
			combat_mgr.process_ability_command(0, c[2], arg)
			var dmg: int = mhp0 - int(monster.current_hp)
			var spent: int = pool10 if c[2] == "magic_bolt" else int(ch.get_meta("path_last_ability_cost", 0))
			var extra: String = ("(INT%d,mana%d)" % [ch.get_effective_stat("intelligence"), ch.get_total_max_mana()]) if c[2] == "magic_bolt" else ""
			line += "  %s dmg=%d/%d(x%.1f) spent=%d%s" % [c[1], dmg, mhp, float(dmg) / float(max(1, mhp)), spent, extra]
			combat_mgr.active_combats.erase(0)
		print(line)
	print("================================================================================\n")

func _verify_dungeon_cards() -> void:
	# #38 functional check — grant each dungeon-exclusive card, confirm it appears in the
	# available pool and casts without runtime error across classes.
	var DT = load("res://shared/drop_tables.gd")
	print("===== #38 DUNGEON CARD FUNCTIONAL CHECK =====")
	print("spider_nest -> %s" % DT.dungeon_card_id_for_dungeon("spider_nest"))
	print("vampire_crypt -> %s" % DT.dungeon_card_id_for_dungeon("vampire_crypt"))
	var cards := ["dungeon_card_venom_fang", "dungeon_card_crimson_draught", "dungeon_card_bulwark_of_bone", "dungeon_card_executioners_edge"]
	for cid in cards:
		var ch = make_char(60, "average", "Fighter")
		ch.combat_deck_collection[cid] = 1
		var avail := false
		for e in ch.get_all_available_abilities():
			if String(e.get("name", "")) == cid:
				avail = true
		var monster = make_monster(60, "boss", 50.0)
		combat_mgr.start_combat(0, ch, monster)
		var combat = combat_mgr.active_combats[0]
		_force_hand(combat, cid)
		var mhp0: int = int(monster.current_hp)
		var res = combat_mgr.process_ability_command(0, cid, "")
		print("%-30s avail=%s cast_ok=%s dmg=%d name='%s'" % [cid, str(avail), str(res.get("success", false)), mhp0 - int(monster.current_hp), DT.card_display_name(cid)])
		combat_mgr.active_combats.erase(0)
	print("=============================================")

func _verify_new_mage_cards() -> void:
	# #36 functional check — force-cast Overload + Frost Nova and confirm effects fire
	# without runtime errors, plus the low-HP Overload block.
	print("===== #36 NEW MAGE CARD FUNCTIONAL CHECK =====")
	for lvl in [50, 200]:
		var ch = make_char(lvl, "average", "Wizard")
		var monster = make_monster(lvl, "boss", 50.0)  # ultra-tanky so it survives the casts
		combat_mgr.start_combat(0, ch, monster)
		if not combat_mgr.active_combats.has(0):
			print("L%d: could not start combat" % lvl); continue
		var combat = combat_mgr.active_combats[0]
		var maxhp: int = ch.get_total_max_hp()
		var hp0: int = ch.current_hp
		_force_hand(combat, "overload")
		var ov = combat_mgr.process_ability_command(0, "overload", "")
		print("L%-4d Overload : ok=%s  HP %d->%d (-%.0f%% of max)  damage_buff=+%d%%" % [lvl, str(ov.get("success", false)), hp0, ch.current_hp, 100.0 * float(hp0 - ch.current_hp) / float(max(1, maxhp)), int(ch.get_buff_value("damage"))])
		var mhp0: int = int(monster.current_hp)
		_force_hand(combat, "frost_nova")
		var fn = combat_mgr.process_ability_command(0, "frost_nova", "")
		print("L%-4d FrostNova: ok=%s  dmg=%d  enemy_-acc=%d%%  focus=%d" % [lvl, str(fn.get("success", false)), mhp0 - int(monster.current_hp), int(combat.get("enemy_distracted", 0)), int(combat.get("focus", 0))])
		# Low-HP block: drop to 10% and confirm Overload refuses.
		ch.current_hp = int(maxhp * 0.10)
		var ov2 = combat_mgr.process_ability_command(0, "overload", "")
		print("L%-4d Overload@10%%HP: ok=%s (expect false — blocked below 25%%)" % [lvl, str(ov2.get("success", false))])
		combat_mgr.active_combats.erase(0)
	print("==============================================")

func _debug_tier_xp():
	# Does a HIGHER-TIER monster grant more XP / HP at the SAME level than a lower tier?
	for lvl in [50, 100]:
		for tier in [1, 4, 6, 9]:
			var nm = monster_db.get_random_monster_name_from_tier(tier)
			var m = monster_db.generate_monster_by_name(nm, lvl)
			print("[TIERXP] L%-4d T%d  hp=%-8d str=%-6d exp=%-8d  '%s'" % [
				lvl, tier, int(m.get("max_hp", 0)), int(m.get("strength", 0)), int(m.get("experience_reward", 0)), str(nm).substr(0, 20)])


func _debug_xp_dump():
	# How many levels does a low-level Trickster gain from Outsmarting ONE big enemy?
	for pair in [[20, 200], [20, 100], [50, 200], [20, 60]]:
		var plvl: int = pair[0]
		var mlvl: int = pair[1]
		var ch = make_char(plvl, "average", "Thief")
		var mon = make_monster(mlvl, "boss")
		var base_xp: int = int(mon.get("experience_reward", 0))
		var diff: int = mlvl - plvl
		var mult: float = 1.0
		if diff > 0:
			mult = 1.0 + sqrt(float(diff) / (10.0 + float(plvl) * 0.05)) * 0.7
		var final_xp: int = int(base_xp * mult * 1.10)
		var lvl_before: int = ch.level
		ch.add_experience(final_xp)
		print("[XP] P%d vs L%d boss: base_xp=%d  over-lvl mult=%.2f  final_xp=%d  ->  L%d to L%d  (+%d levels)" % [
			plvl, mlvl, base_xp, mult, final_xp, lvl_before, ch.level, ch.level - lvl_before])


func run_overlevel_audit():
	var N := 60
	var plevels := [20, 60, 150]
	var deltas := [0, 20, 40, 60, 90, 130]
	var classes := [["Fighter", "War"], ["Wizard", "Mag"], ["Thief", "Trk"]]
	print("\n===== OVER-LEVEL REACH (%d fights/cell, AVERAGE gear, normal mob) =====" % N)
	print("Win%% vs a monster at (player level + delta). 'Reliable' ~ >=60%%. Higher delta reachable = punches further above level.")
	for pl in plevels:
		for c in classes:
			var row := "P%-4d %-4s" % [pl, c[1]]
			for d in deltas:
				var wins := 0
				for i in range(N):
					var r = run_fight(pl, "average", "normal", 1.0, 1.0, 1.0, c[0], pl + d)
					if r.win:
						wins += 1
				row += "  +%-2d:%3d%%" % [d, int(100.0 * wins / N)]
			print(row)
	print("")
	print("===== SAME-LEVEL RISK vs LEVEL (does fighting your OWN level get safer as you level?) =====")
	print("AVERAGE gear vs a same-level ELITE. Win%% / avg lowest-HP%% reached.")
	for c in classes:
		var row2 := "%-4s " % c[1]
		for pl in [10, 30, 60, 120, 250]:
			var wins := 0
			var mhp := 0.0
			for i in range(N):
				var r = run_fight(pl, "average", "elite", 1.0, 1.0, 1.0, c[0])
				if r.win:
					wins += 1
				mhp += float(r.get("min_hp_pct", 0.0))
			row2 += "| L%-3d %3d%% H%2.0f " % [pl, int(100.0 * wins / N), mhp / N]
		print(row2)
	print("=====================================================================\n")

const ALL_CLASSES := [
	["Fighter", "warrior"], ["Barbarian", "warrior"], ["Paladin", "warrior"],
	["Wizard", "mage"], ["Sorcerer", "mage"], ["Sage", "mage"],
	["Thief", "trickster"], ["Ranger", "trickster"], ["Ninja", "trickster"],
]
const ALL_RACES := ["Human", "Elf", "Dwarf", "Ogre", "Halfling", "Orc", "Gnome", "Undead"]

func run_newplayer_audit():
	"""What does a character created TODAY actually face at L1-L10?

	2026-09-04, from live: two players on new characters, "they can't really make much of any
	progress, just death after death". The L1-5 gearless question was DECLINED on 2026-09-03 on
	an explicit premise - "the tutorial we are adding will fill that gap or existing equipment
	and companions will" - and item 7 is not built, so the premise is not true yet. The starter
	Pathfinder chain was retired in the same pass.

	Measures the three states a new character can be in, against what actually spawns."""
	var N := 60
	print("
===== WHAT A NEW CHARACTER FACES (%d fights/cell, normal monsters) =====" % N)
	print("gearless = every slot empty, no companion (a character created today)")
	print("under    = a poor kit, uncommon, 8 levels behind")
	print("average  = the reference player the curve is calibrated against")
	print("%-7s %10s %10s %10s %10s %10s" % ["level", "gearless", "kit", "kit+unc", "kit+comp", "average"])
	for lvl in [1, 2, 3, 5, 8, 10]:
		var row := "%-7d" % lvl
		for g in ["gearless", "starter7", "starter7u", "starter7c", "average"]:
			var wins := 0
			for klass in ["Fighter", "Wizard", "Thief"]:
				for i in range(int(N / 3.0)):
					if run_fight(lvl, g, "normal", 1.0, 1.0, 1.0, klass).win:
						wins += 1
			row += "%9d%%" % int(100.0 * wins / (int(N / 3.0) * 3))
		print(row)
	print("
A 60%% win rate is the design target for a normal fight at any level.")
	print("=====================================================================
")

func run_adjudicate_audit():
	"""Which audit is telling the truth about the win rate — refcal, or roles?

	2026-09-04. They disagree by up to 47pp at the same levels on the same curve, and both
	arrive there through code that LOOKS equivalent: same three classes, same player AI, same
	win definition, both end their combats, neither truncates the fight. So rather than keep
	reading, measure both in ONE process, on ONE curve, at an n where noise cannot explain a
	gap this size.

	`refcal` reports through `_fight_stats_at`; `roles` reports through a `run_fight` loop. If
	they agree here, the disagreement was process-to-process variance at small n and the curve is
	fine. If they diverge, it is systematic and the difference is in those two functions."""
	var N := 90   # per level per method: sigma ~5.3pp at p=0.5, so a 20pp gap cannot be noise
	print("
===== WHICH AUDIT IS RIGHT? _fight_stats_at vs run_fight, same process =====")
	print("%d fights per cell per method. Sampling error ~5pp; anything above ~15pp is systematic." % N)
	print("%-8s %14s %14s %10s" % ["level", "_fight_stats_at", "run_fight", "gap"])
	for lvl in [10, 50, 250, 1000, 5000]:
		var a := _fight_stats_at(lvl, int(N / 3.0))
		var wins := 0
		var tot := 0
		for klass in ["Fighter", "Wizard", "Thief"]:
			for i in range(int(N / 3.0)):
				var r = run_fight(lvl, "average", "normal", 1.0, 1.0, 1.0, klass)
				if r.win:
					wins += 1
				tot += 1
		var wa := 100.0 * float(a.get("win", 0.0))
		var wb := 100.0 * float(wins) / float(maxi(1, tot))
		print("%-8d %13.0f%% %13.0f%% %9.0fpp" % [lvl, wa, wb, absf(wa - wb)])
	print("=====================================================================
")

func run_name_consistency_audit():
	"""Does every table agree on what a card is CALLED?

	2026-09-04. The owner reported the same bug twice: "it's called Arcane Surge in battle but
	Haste in the deck screen", then after a partial fix, "Did we ever fix the differing names on
	cards like Arcane Surge and Haste (shows different names on upgrades, in combat, in deck)".

	The first fix reconciled the two tables I had found. There were SIX, and four disagreed - the
	rank-up screen kept its own resolver, and so did an ability-tome table and a constants table
	nobody had looked at. Reconciling the two you can see is not the same as counting them.

	CombatManager.ABILITY_DISPLAY_NAMES is canonical. This walks every other table and reports
	anything that disagrees, so the next rename cannot half-land."""
	print("
===== CARD NAME CONSISTENCY =====")
	var CM = load("res://shared/combat_manager.gd")
	var canon: Dictionary = CM.ABILITY_DISPLAY_NAMES
	var cm = combat_mgr
	var bad := 0
	var checked := 0
	print("%-18s %-16s %-16s %-16s" % ["id", "canonical", "resolver", "tome table"])
	for id in canon.keys():
		var want := String(canon[id])
		var got := String(cm._ability_display_name(null, String(id)))
		var tome := String(drop_tables.ABILITY_TOME_DISPLAY_NAMES.get(id, want))
		var info: Dictionary = {}
		checked += 1
		var ok := (got == want) and (tome == want)
		if not ok:
			bad += 1
		print("%-18s %-16s %-16s %-16s %s" % [id, want, got, tome, ("" if ok else "*** MISMATCH ***")])
	print("
checked %d names, disagreements: %d" % [checked, bad])
	print("=====================================================================
")

func run_gear_sources_audit():
	"""EVERY stat a piece of equipment can carry, where it comes from, and what gates it.

	2026-09-04, written after repeatedly getting this wrong in conversation - claiming gear was
	worth nothing (an unsound comparison), then claiming there was no mana regen on gear at all
	(there is `mana_on_hit`, epic+). Owner: "You continually get that wrong. You need to take a
	deeper look at equipment that's possible to get in the game because you keep failing and
	leaving things out... Once you have a good picture of it you need to find a way to keep that
	in mind in all future sessions."

	So this is not a one-off answer, it is the answer REGENERATED from the game's own tables. It
	walks the pools rather than restating them, so it cannot go stale the way a hand-written note
	would - which is the same reason the boss-art mapping is derived from dungeon_database.

	The last section is the one that matters most: character.get_equipment_bonuses() declares a
	set of stat fields, and this reports any of them that NO item can actually roll. A field that
	combat reads and nothing grants is invisible unless something enumerates both sides."""
	print("
===== EQUIPMENT: EVERY STAT AND WHERE IT COMES FROM =====")
	var sources := {}   # stat -> [source strings]
	var _add := func(stat: String, src: String) -> void:
		if not sources.has(stat):
			sources[stat] = []
		if not (src in sources[stat]):
			sources[stat].append(src)

	for entry in drop_tables.PREFIX_POOL:
		_add.call(String(entry.get("stat", "?")), "prefix (any rarity)")
	for entry in drop_tables.SUFFIX_POOL:
		_add.call(String(entry.get("stat", "?")), "suffix (any rarity)")
	for entry in drop_tables.CHASE_SUFFIX_POOL:
		_add.call(String(entry.get("stat", "?")), "CHASE (epic+ only)")
	for entry in drop_tables.PROC_SUFFIX_POOL:
		_add.call("proc:" + String(entry.get("proc_type", "?")), "proc suffix (tier 6+)")
	for spec in drop_tables.SPECIALTY_AFFIX_STATS.keys():
		var sd = drop_tables.SPECIALTY_AFFIX_STATS[spec]
		for st in (sd.get("stats", []) if sd is Dictionary else []):
			_add.call(String(st), "crafted: %s specialty" % spec)
	for st in drop_tables.RUNE_AFFIX_CAPS.keys():
		_add.call(String(st), "enchanter rune")

	print("
-- by stat --")
	var keys := sources.keys()
	keys.sort()
	for k in keys:
		print("   %-28s %s" % [k, ", ".join(sources[k])])

	print("
-- rarity gates --")
	print("   affixes per rarity: %s" % str(drop_tables.AFFIX_COUNTS))
	print("   chase-roll chance:  %s" % str(drop_tables.CHASE_ROLL_CHANCE_BY_RARITY))
	print("   drop weights:       %s" % str(drop_tables.RARITY_WEIGHTS))

	# ---- BASE ITEM TYPES ------------------------------------------------------------------------
	# 2026-09-04 — this section exists because the FIRST version of this audit did not have it,
	# enumerated only the affix pools, and concluded that five declared stats were granted by
	# nothing. They are granted by BASE TYPE. Owner found it in one question: "what do Minotaurs
	# drop? Do they not drop warrior gear? Does it not help with getting stamina back?" - yes, and
	# yes. An audit built to stop me being wrong was wrong in the same way, one level down.
	#
	# Measured by EXECUTION, not by reading character.gd: equip one bare item of each base type,
	# with no affixes, and diff get_equipment_bonuses(). An if/elif chain cannot be enumerated
	# safely any other way, and this cannot drift when a branch is added.
	print("
-- ACQUISITION PATHS: every function in drop_tables that yields equipment --")
	# 2026-09-04 — this section is the owner's correction, twice over. The first version of this
	# audit read only the affix pools. The second added base types but enumerated them from
	# EQUIPMENT_BASES, which is the ORDINARY drop pool and does NOT contain the class-specific
	# bases at all — so it reported "no base type grants a class-specific stat" while
	# `ring_arcane` visibly grants mana_regen three lines away in character.gd.
	#
	# Owner: "You should be exploring all avenues of how players could possibly get gear and
	# painting a picture of it after based on fact not assumption."
	#
	# So the unit here is the ACQUISITION PATH, not the table. Each generator is CALLED and its
	# output inspected, which is the only way that cannot miss a path that builds items inline.
	var paths := [
		["generate_weapon(lvl)", func(l): return drop_tables.generate_weapon(l)],
		["generate_shield(lvl)", func(l): return drop_tables.generate_shield(l)],
		["generate_mage_gear (Arcane Hoarder)", func(l): return drop_tables.generate_mage_gear(l)],
		["generate_trickster_gear (Shadow Hoarder)", func(l): return drop_tables.generate_trickster_gear(l)],
		["generate_warrior_gear (Warrior Hoarder)", func(l): return drop_tables.generate_warrior_gear(l)],
		["roll_dungeon_chest_equipment", func(l): return drop_tables.roll_dungeon_chest_equipment(5, l)],
		["generate_mystery_box_item", func(l): return drop_tables.generate_mystery_box_item(5)],
	]
	var type_seen := {}
	for entry in paths:
		var label := String(entry[0])
		var fn: Callable = entry[1]
		var types := {}
		for _i in range(400):
			var it = fn.call(60)
			if it is Dictionary and not it.is_empty():
				var ty := String(it.get("type", it.get("item_type", "?")))
				types[ty] = true
				type_seen[ty] = true
		var tl := types.keys()
		tl.sort()
		print("   %-42s -> %s" % [label, ", ".join(tl) if not tl.is_empty() else "(nothing)"])
	# The ordinary drop pool, listed separately because it is table-driven rather than a call.
	for t in drop_tables.EQUIPMENT_BASES.keys():
		for e in drop_tables.EQUIPMENT_BASES[t]:
			type_seen[String(e.get("item_type", ""))] = true

	print("
-- what each ITEM TYPE grants BEFORE affixes (probed, not read) --")
	# Equip one bare item of each type and diff the aggregator. An if/elif chain in character.gd
	# cannot be enumerated any other way without re-implementing it, which is how it drifts.
	var tkeys := type_seen.keys()
	tkeys.sort()
	for ty in tkeys:
		var it2 := String(ty)
		if it2 == "" or it2 == "?":
			continue
		var probe_ch = CharacterScript.new()
		probe_ch.initialize("BaseProbe", "Fighter", "Human")
		var slot := it2.split("_")[0]
		probe_ch.equipped[slot] = {"id": 1, "type": it2, "rarity": "common", "level": 50,
			"affixes": {}, "name": it2}
		var b: Dictionary = probe_ch.get_equipment_bonuses()
		var notable: Array = []
		for f in ["mana_regen", "energy_regen", "stamina_regen", "meditate_bonus", "flee_bonus"]:
			if int(b.get(f, 0)) > 0:
				notable.append("%s +%d" % [f, int(b[f])])
				_add.call(f, "BASE TYPE %s" % it2)
		if not notable.is_empty():
			print("   %-22s %s" % [it2, ", ".join(notable)])

	print("
-- monsters that drop TARGETED class gear (35% chance on kill) --")
	for ab in ["arcane_hoarder", "warrior_hoarder", "cunning_prey"]:
		var who: Array = []
		for mt in monster_db.MonsterType.values():
			var md = monster_db.get_monster_base_stats(mt)
			if md is Dictionary and (ab in (md.get("abilities", []) as Array)):
				who.append(String(md.get("name", "?")))
		print("   %-18s %s" % [ab + ":", ", ".join(who) if not who.is_empty() else "(none found)"])
	print("   ^ class-targeted drops DO exist - through monster ABILITIES. drop_tables itself")
	print("     never reads the player's class; the MONSTER decides.")

	print("
-- uniques and sets --")
	var udb = load("res://shared/unique_database.gd")
	if udb != null:
		print("   uniques: %d, sets: %d  (FIXED rolls, not from the pools above)" % [
			int(udb.UNIQUES.size()), int(udb.SETS.size())])
		print("   see shared/unique_database.gd. NOTE: they are NOT the only class-shaped gear -")
		print("   the hoarder bases above are class-shaped and come from ordinary kills.")
	print("=====================================================================
")

func run_focus_gear_audit():
	"""Does chasing your class's resource affix change the picture?

	The nine-class audit rolls gear at RANDOM, so it measures an unsorted kit. If a focused kit
	moves the mage rows materially, then "mages run dry at L80" is a statement about the gear
	model and not about mages, and the class table must not be tuned against it."""
	var N := 60
	print("
===== FOCUSED vs RANDOM GEAR (%d fights/cell) =====" % N)
	print("`focus` keeps the best of %d real drops per slot for the class's own resource affix." % FOCUS_ROLLS)
	print("nokit   = no class kit at all (the model used before 2026-09-04)")
	print("ref     = THE REFERENCE PLAYER: mixed rarity plus a piece or two of the class kit")
	print("full    = the whole kit, sifted for the stats that class wants")
	print("%-11s %-8s %s" % ["Class", "Path", "L30 elite: nokit  ref    full  |  L80 elite: nokit  ref    full"])
	for c in ALL_CLASSES:
		var row := "%-11s %-8s" % [c[0], c[1]]
		for lvl in [30, 80]:
			var cell := ""
			for g in ["average_nokit", "average", "focus"]:
				var wins := 0
				var turns := 0
				var casts := 0
				for i in range(N):
					var r = run_fight(lvl, g, "elite", 1.0, 1.0, 1.0, c[0])
					if r.win:
						wins += 1
					turns += int(r.turns)
					casts += int(r.get("casts", 0))
				cell += "  %3d%%" % int(100.0 * wins / N)
			row += "  " + cell + " |"
		print(row)
	print("=====================================================================
")

func run_class_audit():
	# #5 — the sim only ever drove three of the nine classes. Casts/turn is the tell:
	# a class whose AI never matches its hand falls through to basic attacks, so its
	# win-rate is a measurement of AUTO-ATTACKING, not of the class. Any row near
	# 0.00 casts/turn is not being simulated, whatever number sits next to it.
	var N := 60
	print("\n===== #5 NINE-CLASS ABILITY-SPEND AUDIT (%d fights/cell, AVERAGE gear) =====" % N)
	print("Casts/turn near 0 = the class is auto-attacking, i.e. NOT actually simulated.")
	print("%-11s %-10s %s" % ["Class", "Path", "  L10 normal        L30 elite         L80 elite"])
	for c in ALL_CLASSES:
		var row := "%-11s %-10s" % [c[0], c[1]]
		for case in [[10, "normal"], [30, "elite"], [80, "elite"]]:
			var wins := 0
			var turns := 0
			var casts := 0
			for i in range(N):
				var r = run_fight(int(case[0]), "average", String(case[1]), 1.0, 1.0, 1.0, c[0])
				if r.win:
					wins += 1
				turns += int(r.turns)
				casts += int(r.get("casts", 0))
			var cpt: float = float(casts) / float(maxi(1, turns))
			row += "  %3d%% %4.1ft %.2fc/t" % [int(100.0 * wins / N), float(turns) / N, cpt]
		print(row)
	print("=====================================================================\n")

func _load_real_characters() -> Array:
	# #5 — GROUND TRUTH. Real saved characters written by the dev server live in
	# user://data/characters (same user:// as the server, since the sim runs from this
	# project). Loaded through Character.from_dict so every derived number comes out of
	# the SAME code the game uses — no re-implementation to drift.
	var out: Array = []
	var dir = DirAccess.open("user://data/characters")
	if dir == null:
		return out
	for fname in dir.get_files():
		if not fname.ends_with(".json") or fname.ends_with(".bak"):
			continue
		var f = FileAccess.open("user://data/characters/" + fname, FileAccess.READ)
		if f == null:
			continue
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if not (parsed is Dictionary):
			continue
		var ch = CharacterScript.new()
		ch.from_dict(parsed)
		out.append(ch)
	out.sort_custom(func(a, b): return a.level < b.level)
	return out

# Gear affixes are rolled per item, so ONE make_char is a coin flip, not a measurement —
# the first version of this audit had "under" gear out-hitting "average" purely on RNG.
# Average the sim side over this many independent builds per cell.
const CALIB_ROLLS := 25

const RARITY_RANK := {"common": 0, "uncommon": 1, "rare": 2, "epic": 3, "legendary": 4, "artifact": 5}

func _classify_real(ch) -> Dictionary:
	# #5 — a saved character file is NOT automatically "a representative player". Half the
	# local cohort turned out to be naked test accounts (0 equipped slots) and one was an
	# admin-boosted all-epic build. Averaging those together produced a gear model fitted to
	# characters wearing nothing, which would have made the sim UNDER-state player power —
	# the opposite of the inflation it was supposed to fix. So classify first, then compare
	# each band against the sim tier that band actually corresponds to.
	var slots := 0
	var rank_sum := 0.0
	for slot in SLOTS:
		var it = ch.equipped.get(slot, null)
		if it is Dictionary and not it.is_empty():
			slots += 1
			rank_sum += float(RARITY_RANK.get(String(it.get("rarity", "common")), 0))
	var avg_rank: float = rank_sum / float(maxi(1, slots))
	var band := "partial"
	var tier := "under"
	if slots == 0:
		band = "naked"
		tier = "-"
	elif slots >= 5 and avg_rank >= 3.0:
		band = "chase"
		tier = "bis"
	elif slots >= 5:
		band = "geared"
		tier = "average"
	return {"slots": slots, "avg_rank": avg_rank, "band": band, "tier": tier}

func _ratios_vs(real, gear: String) -> Array:
	# Mean sim/real over CALIB_ROLLS builds at the same level/class/race.
	var path: String = String(real.get_class_path())
	var r := [float(maxi(1, real.get_total_max_hp())), float(maxi(1, real.get_total_attack())), float(maxi(1, _pool_for_path(real, path)))]
	var acc := [0.0, 0.0, 0.0]
	for i in range(CALIB_ROLLS):
		var sim = make_char(int(real.level), gear, String(real.class_type), String(real.race))
		acc[0] += float(sim.get_total_max_hp()) / r[0]
		acc[1] += float(sim.get_total_attack()) / r[1]
		acc[2] += float(_pool_for_path(sim, path)) / r[2]
	for i in range(3):
		acc[i] /= float(CALIB_ROLLS)
	return acc

func _median(arr: Array) -> float:
	if arr.is_empty():
		return 0.0
	var c := arr.duplicate()
	c.sort()
	if c.size() % 2 == 1:
		return float(c[c.size() / 2])
	return 0.5 * (float(c[c.size() / 2 - 1]) + float(c[c.size() / 2]))

func run_calibration_audit():
	# #5 — make_char is the sim's model of "a player at level N", and every balance number
	# the sim produces is only as good as that model. This measures it against real saved
	# characters instead of asserting it in a comment.
	var reals := _load_real_characters()
	print("
===== #5 make_char CALIBRATION vs REAL SAVED CHARACTERS =====")
	if reals.is_empty():
		print("No characters in user://data/characters — run the dev server once to create some.")
		print("=====================================================================
")
		return
	print("Ratio sim/real (1.00 = matched), sim side averaged over %d gear rolls per cell." % CALIB_ROLLS)
	print("Real values read through Character.from_dict + the same getters combat uses.")
	print("Each character is compared against the sim tier its OWN kit corresponds to:")
	print("  naked (0 slots) -> no tier, listed for reference only")
	print("  partial (1-4)   -> 'under'      geared (5+) -> 'average'      chase (5+ epic+) -> 'bis'")
	print("")
	print("%-11s %-10s %-9s %-4s %-8s %-8s %s" % ["Name", "Class", "Race", "Lvl", "Band", "vs tier", "HP     ATK    POOL   (real hp/atk/pool)"])
	var bands := {}
	for real in reals:
		var info := _classify_real(real)
		var band: String = String(info["band"])
		var tier: String = String(info["tier"])
		var path: String = String(real.get_class_path())
		var gear_for_compare: String = tier if tier != "-" else "under"
		var acc := _ratios_vs(real, gear_for_compare)
		if not bands.has(band):
			bands[band] = {"tier": tier, "rows": []}
		bands[band]["rows"].append(acc)
		bands[band]["levels"] = bands[band].get("levels", [])
		bands[band]["levels"].append([int(real.level), acc[1]])
		print("%-11s %-10s %-9s %-4d %-8s %-8s %5.2fx %5.2fx %5.2fx  (%d/%d/%d)" % [
			String(real.name).substr(0, 11), String(real.class_type), String(real.race), int(real.level),
			"%s/%d" % [band, int(info["slots"])], tier,
			acc[0], acc[1], acc[2],
			int(real.get_total_max_hp()), int(real.get_total_attack()), int(_pool_for_path(real, path))])
	print("")
	print("Median per band. ONLY the 'geared' row calibrates the average tier — a naked")
	print("character measures nothing about gear, and a chase build is the 'bis' bookend.")
	print("%-9s %-8s %8s %8s %8s %5s" % ["Band", "vs tier", "HP", "ATK", "POOL", "n"])
	for band in ["naked", "partial", "geared", "chase"]:
		if not bands.has(band):
			continue
		var rows: Array = bands[band]["rows"]
		var cols := [[], [], []]
		for row in rows:
			for i in range(3):
				cols[i].append(float(row[i]))
		print("%-9s %-8s %7.2fx %7.2fx %7.2fx %5d" % [
			band, String(bands[band]["tier"]),
			_median(cols[0]), _median(cols[1]), _median(cols[2]), rows.size()])
	# A median can hide a SLOPE error: if the model is hot at low level and cold at high
	# level, the middle looks perfect while both ends are wrong. Say so explicitly — the
	# whole point of this audit is to stop the sim quietly mis-modelling the player.
	var geared: Array = bands.get("geared", {}).get("levels", [])
	if geared.size() >= 2:
		geared.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
		var lo: Array = geared[0]
		var hi: Array = geared[geared.size() - 1]
		var spread: float = float(hi[1]) / maxf(0.01, float(lo[1]))
		print("")
		print("Level trend (ATK ratio): L%d %.2fx  ->  L%d %.2fx" % [int(lo[0]), float(lo[1]), int(hi[0]), float(hi[1])])
		if spread < 0.67 or spread > 1.5:
			print("*** SLOPE WARNING: the model does not hold across levels — it is %s at L%d and" % ["hot" if float(lo[1]) > float(hi[1]) else "cold", int(lo[0])])
			print("    %s at L%d. A single item-level ratio cannot fix both ends; balance numbers" % ["cold" if float(lo[1]) > float(hi[1]) else "hot", int(hi[0])])
			print("    taken from the far end of that range are NOT trustworthy. Needs a level-")
			print("    dependent gear model, which needs more real characters to fit against.")
	print("=====================================================================
")

# The full playable range. Max level is 10000 (COMPANION_MAX_LEVEL / world_system cap),
# so a balance claim that only holds to L50 is a claim about 0.5% of the game.
const PROGRESSION_LEVELS := [1, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000]

func run_progression_audit():
	# #5 (user direction 2026-09-02) — the question this sim exists to answer: does the
	# difficulty HOLD as a player progresses, or does the game trivialize itself? Sweeps the
	# whole level range at representative gear and reports, per archetype, the win rate and
	# how close the player came to dying. A game that gets harder shows win% falling or at
	# least flat with danger rising; a game that trivializes shows win% climbing to 100%
	# and min-HP climbing with it.
	var N := _audit_n
	print("
===== #5 PROGRESSION SWEEP: does difficulty hold from L1 to L10000? =====")
	print("AVERAGE gear (calibrated), same-level enemy, %d fights/cell." % N)
	print("Win%% = how often the player wins. H%% = average LOWEST HP%% reached (danger:")
	print("high H%% means it was never close). T = turns. Trivialized looks like 100%%/H90+.")
	for et in ["normal", "elite", "boss"]:
		print("")
		print("--- %s ---" % et.to_upper())
		print("%-7s %-22s %-22s %-22s" % ["Level", "Fighter", "Wizard", "Thief"])
		for lvl in PROGRESSION_LEVELS:
			var row := "L%-6d" % lvl
			for klass in ["Fighter", "Wizard", "Thief"]:
				var wins := 0
				var turns := 0
				var mhp := 0.0
				for i in range(N):
					var r = run_fight(lvl, "average", et, 1.0, 1.0, 1.0, klass)
					if r.win:
						wins += 1
					turns += int(r.turns)
					mhp += float(r.get("min_hp_pct", 0.0))
				row += " %3d%% %5.1ft H%3.0f%%      " % [int(100.0 * wins / N), float(turns) / N, mhp / N]
			print(row)
	print("=====================================================================
")

func run_companion_audit():
	# #5 (user direction 2026-09-02) — the intended loop is "level your companion to reach
	# bigger challenges". That only works if a companion's contribution KEEPS UP with the
	# content. Measured here as the win-rate a player has WITHOUT a companion vs WITH one at
	# several companion levels. If the columns converge as player level rises, companion
	# investment stops mattering and the loop is broken at the top end.
	var N := _audit_n
	print("
===== #5 COMPANION CONTRIBUTION vs LEVEL =====")
	print("Win%% at same-level ELITE, Fighter, AVERAGE gear, %d fights/cell." % N)
	print("If 'none' and 'maxed' converge as level rises, levelling a companion has stopped")
	print("paying — the grind-your-companion loop only works while the gap is real.")
	print("%-8s %10s %10s %10s %10s" % ["Level", "none", "compL1", "compL=char", "comp x10"])
	for lvl in PROGRESSION_LEVELS:
		var row := "L%-7d" % lvl
		for mode in ["none", "l1", "match", "x10"]:
			var wins := 0
			for i in range(N):
				_companion_mode = mode
				var r = run_fight(lvl, "average", "elite", 1.0, 1.0, 1.0, "Fighter")
				if r.win:
					wins += 1
			row += " %9d%%" % int(100.0 * wins / N)
		_companion_mode = "match"
		print(row)
	print("=====================================================================
")

func run_underlevel_audit():
	# #6 (user question 2026-09-02: "there is a formula that weakens monsters near the starter
	# post — is the sim accounting for it?"). Two separate mechanisms exist:
	#   1. world_system.get_post_anchored_level() — posts pull the ENCOUNTER LEVEL down in their
	#      vicinity and can never push it up ("posts are settlements, not difficulty elevators").
	#   2. monster_database._calculate_tiered_stat_scale() — when a monster spawns BELOW its
	#      natural base level its stats collapse linearly, so a clamped high-tier monster is a
	#      runt of its species rather than an apex predator wearing a low level tag.
	# The sim models NEITHER, because it fights same-level, tier-natural monsters — the right
	# unit for tuning abilities against each other. What that leaves unmeasured is the
	# ENCOUNTER: get_area_level_range is a pure function of (x, y) and never reads the player's
	# level, so what a player meets depends on where they stand, not on how strong they are.
	# This audit measures what that is worth: a player at `level` against monsters BELOW it.
	var N := 60
	print("
===== #6 UNDER-LEVEL ENCOUNTERS (what standing near a post is worth) =====")
	print("Win%% for a player at L, fighting a NORMAL monster at a fraction of their level,")
	print("%d fights/cell, AVERAGE gear. 100%% with no HP lost = free XP forever." % N)
	print("%-8s %-6s %s" % ["Class", "PlyrL", "  mob=L    mob=75%L   mob=50%L   mob=25%L   mob=10%L"])
	for klass in ["Fighter", "Wizard", "Thief"]:
		for lvl in [50, 250, 1000, 5000]:
			var row := "%-8s %-6d" % [klass, lvl]
			for frac in [1.0, 0.75, 0.5, 0.25, 0.10]:
				var mob_level: int = maxi(1, int(round(float(lvl) * frac)))
				var wins := 0
				var mhp := 0.0
				for i in range(N):
					var r = run_fight(lvl, "average", "normal", 1.0, 1.0, 1.0, klass, mob_level)
					if r.win:
						wins += 1
					mhp += float(r.get("min_hp_pct", 0.0))
				row += "  %3d%% H%3.0f%%" % [int(100.0 * wins / N), mhp / N]
			print(row)
	print("")
	print("H%% is the average LOWEST health the player dropped to. Where win%% is 100 and H%% is")
	print("~100, the fight is not a fight — and because encounter level is a function of")
	print("position only, a player of ANY level can choose that fight by walking to a post.")
	print("=====================================================================
")

func run_selection_audit():
	# #6 (2026-09-02) — WHY the difficulty curve is jagged and slides in the late game.
	# select_monster_type picks a TIER from the level, then a monster from that tier. But a
	# tier's level BAND and the base_levels of the monsters inside it do not line up:
	#   T6 monsters are base 150-400, but T6 covers L~150-1000
	#   T7 monsters are base 700-1500, but T7 covers L~1000-2500
	#   T8 monsters are base 2500-4500, but T8 covers L~2500-5000
	# scale_monster_to_level scales UP from base with a tiered percentage curve, but scales
	# DOWN with a bare LINEAR ratio (target/base). So near the START of a band most picks sit
	# ABOVE the target level and generate as downscaled RUNTS, while near the END of the same
	# band every pick is scaled up and generates at full strength. The result is a SAWTOOTH:
	# difficulty collapses at each tier boundary and climbs back to the end of the band.
	# It also produces enormous same-level variance — at L2500 a monster can roll anywhere
	# from ~8k to ~656k HP, an 80x spread for the same player at the same place.
	var N := 400
	print("
===== #6 MONSTER SELECTION AUDIT (%d picks/level) =====" % N)
	print("runt%% = picked monster's base_level is ABOVE the target level, so it takes the")
	print("linear downscale path. HP spread = max/min generated HP at the SAME level.")
	print("%-8s %6s %7s %12s %12s %12s %9s" % ["Level", "tier", "runt%", "medianHP", "minHP", "maxHP", "spread"])
	for lvl in [50, 100, 250, 400, 500, 800, 1000, 1500, 2000, 2500, 4000, 5000, 7500, 10000]:
		var runts := 0
		var hps: Array = []
		var tier := 0
		for i in range(N):
			var t = monster_db.select_monster_type(lvl)
			var bs = monster_db.get_monster_base_stats(t)
			if int(bs.get("base_level", 1)) > lvl:
				runts += 1
			var m = monster_db.scale_monster_to_level(bs, lvl, true)
			hps.append(int(m.get("max_hp", 0)))
		tier = int(monster_db._get_tier_info(lvl).tier)
		hps.sort()
		var lo: int = maxi(1, int(hps[0]))
		var hi: int = int(hps[hps.size() - 1])
		print("%-8d %6d %6d%% %12d %12d %12d %8.0fx" % [
			lvl, tier, int(100.0 * runts / N), int(hps[hps.size() / 2]), lo, hi, float(hi) / float(lo)])
	print("")
	print("Read the medianHP column DOWN: it is not a curve, it is a sawtooth. Where it FALLS")
	print("as level rises, the game is getting easier as the player gets stronger. Fixing this")
	print("by re-authoring base_levels only moves the teeth — the level->difficulty mapping has")
	print("to stop going through each monster's hand-authored base_level. Same conclusion as")
	print("the reference-player model in item 6, reached from a different direction.")
	print("=====================================================================
")

# ============================================================================
# REFERENCE-PLAYER MONSTER MODEL (#6, 2026-09-02)
# ============================================================================
# Everything measured this session pointed at one fix, from two independent
# directions:
#   * PLAYER SIDE — player damage grows ~L^2 while monster HP grows on an
#     unrelated curve, so the ratio drifts: abilities are 2.6-35x overkill at L1,
#     collapse to 8-40% of a health bar around L100-500, then partly recover.
#   * MONSTER SIDE — level->difficulty is routed through each monster's
#     hand-authored base_level with an ASYMMETRIC up/down scale, so difficulty
#     collapses at every tier boundary (median monster HP falls 6.7x from L2000
#     to L2500) and same-level HP variance reaches 85x.
# Re-tuning either side moves the problem. The fix is to stop deriving monster
# magnitude from hand-authored tables at all, and derive it from what a real
# player at that level can actually do.
#
# This curve is the measurement that makes that possible. For each anchor level
# it records, from the REAL combat code driven by the calibrated make_char:
#   dpt      — damage per turn a reference player deals
#   ehp      — the player's max HP (what the monster has to chew through)
#   taken_ps — damage the player takes per turn per point of monster strength
# From those three, monster stats follow by algebra rather than by authorship:
#   monster.hp  = dpt * target_turns(role)
#   monster.str = ehp * danger(role) / (target_turns(role) * taken_ps)
# Difficulty then holds by construction at every level, and "gets harder as you
# progress" becomes an explicit knob (danger/target_turns) instead of an
# emergent accident of 54 stat blocks.
#
# Measured across all three archetypes and MEDIANED, so the reference is not a
# single class's build. Run with:  -- refcurve
const REF_ANCHOR_LEVELS := [1, 2, 3, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000]
# The probe window MUST equal the fight length the model is designing for. This was
# originally 12 and the model came out badly wrong in a LEVEL-DEPENDENT way (real
# in-fight damage was 0.46x the prediction at L1 but 0.06x at L5000). The cause is
# self-reference: a player bursts with abilities and then runs dry, so damage-per-turn
# depends on how long the fight is — and the fight length depends on the monster HP the
# curve is being used to set. Averaging over 12 turns while designing 5-turn fights
# amortises the opening burst over the wrong window, and the error grows with level
# because high-level fights ran longest. Measuring over exactly the target window closes
# the loop: hp = (mean output over N turns) * N really does produce an N-turn fight.
const REF_PROBE_TURNS := 5    # == TARGET_TURNS_NORMAL in the monster model
const REF_SAMPLES := 12       # independent characters per class per level

func _measure_reference_at(level: int, klass: String) -> Dictionary:
	# One character's contribution to the reference curve. Damage per turn is
	# measured over a real fight against an unkillable dummy so ability rotation,
	# resource drain and regen all behave exactly as they do in play — a single
	# cast would flatter classes that open with a nuke and then run dry.
	var dpt_total := 0.0
	var taken_total := 0.0
	var ehp_total := 0.0
	var samples := 0
	for s in range(REF_SAMPLES):
		var ch = make_char(level, "average", klass)
		var max_hp: int = ch.get_total_max_hp()
		# Dummy: real generated monster so defense/abilities behave, but with an
		# HP pool far beyond what the player can chew through in the probe window,
		# and a KNOWN strength so damage-taken can be normalised per strength point.
		var monster := make_monster(level, "normal", 1.0)
		var probe_str: int = maxi(1, int(monster.get("strength", 1)))
		var huge: int = maxi(1000, int(monster.get("max_hp", 1)) * 10000)
		monster["max_hp"] = huge
		monster["current_hp"] = huge
		monster["strength"] = probe_str
		ch.in_combat = false
		combat_mgr.start_combat(0, ch, monster)
		if not combat_mgr.active_combats.has(0):
			continue
		var combat = combat_mgr.active_combats[0]
		var dealt := 0
		var taken := 0
		var turns := 0
		for t in range(REF_PROBE_TURNS):
			if ch.current_hp <= 0:
				break
			var mhp0: int = int(monster.get("current_hp", 0))
			var php0: int = ch.current_hp
			if combat.get("player_can_act", true):
				match ch.get_class_path():
					"trickster": _player_act_trickster(combat, ch)
					"mage": _player_act_mage(combat, ch)
					_: _player_act(combat, ch)
			dealt += maxi(0, mhp0 - int(monster.get("current_hp", 0)))
			combat_mgr.process_monster_turn(combat)
			taken += maxi(0, php0 - ch.current_hp)
			turns += 1
			# Keep the player alive: this probe measures RATES, not survival, and a
			# death mid-window would truncate the average toward whoever is tankiest.
			ch.current_hp = max_hp
		combat_mgr.end_combat(0, false, false)
		if turns == 0:
			continue
		dpt_total += float(dealt) / float(turns)
		taken_total += (float(taken) / float(turns)) / float(probe_str)
		ehp_total += float(max_hp)
		samples += 1
	if samples == 0:
		return {}
	return {
		"dpt": dpt_total / float(samples),
		"taken_ps": taken_total / float(samples),
		"ehp": ehp_total / float(samples),
	}

# Sim-side mirrors of the monster model's knobs, so validation reports against the same
# targets the model is aiming at without the sim reaching into monster_database internals.
const TARGET_TURNS_NORMAL_SIM := 5.0
const DANGER_NORMAL_SIM := 0.40
# 2026-09-03 — the base curve's danger axis now steers by WIN RATE, for the same reason rolecal
# does: cost is measured across all fights and a dead player has spent 100% of their bar, so the
# metric saturates exactly where the monster is strongest and the correction runs out of signal.
#
# It also removes a contradiction the last calibration exposed. rolecal had already moved to
# win-rate targets, so ROLE_TARGETS said a normal monster should be a 60% fight while refcal was
# steering the same monsters by cost — and they came out at 72-100% win, with L250 at a flat
# 100%. Two calibrators disagreeing about what "normal" means is how a curve ends up nobody's
# intent.
const WIN_NORMAL_SIM := 0.60
# How hard each calibration pass corrects toward the target. 0.5 (sqrt) is heavily damped and
# needs many passes to close a large gap; 0.75 converges in the budget we run while staying
# stable at the sample sizes `-- n=` now provides.
const CAL_CORRECTION_EXP := 0.75

func _curve_at(level: int) -> Dictionary:
	# Read the generated reference curve the same way monster_database does.
	if _curve_cache.is_empty():
		var f = FileAccess.open("res://shared/reference_player_curve.json", FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary and parsed.get("anchors", null) is Array:
				_curve_cache = {"anchors": parsed["anchors"]}
	var anchors: Array = _curve_cache.get("anchors", [])
	if anchors.is_empty():
		return {}
	var lvl := maxf(1.0, float(level))
	if lvl <= float(anchors[0].get("level", 1)):
		return anchors[0]
	if lvl >= float(anchors[anchors.size() - 1].get("level", 1)):
		return anchors[anchors.size() - 1]
	for i in range(1, anchors.size()):
		var a: Dictionary = anchors[i - 1]
		var b: Dictionary = anchors[i]
		var la := float(a.get("level", 1))
		var lb := float(b.get("level", 1))
		if lvl <= lb:
			var t: float = (log(lvl) - log(la)) / maxf(0.000001, (log(lb) - log(la)))
			return {
				"dpt": lerp(float(a.get("dpt", 1.0)), float(b.get("dpt", 1.0)), t),
				"ehp": lerp(float(a.get("ehp", 1.0)), float(b.get("ehp", 1.0)), t),
				"taken_ps": lerp(float(a.get("taken_ps", 1.0)), float(b.get("taken_ps", 1.0)), t),
			}
	return anchors[anchors.size() - 1]

func run_reference_validate():
	# #6 — close the loop on the reference model. The curve predicts that a plain
	# same-level fight lasts TARGET_TURNS_NORMAL turns and costs DANGER_NORMAL of the
	# player's health bar. This measures whether it actually does, and reports the
	# correction factor if not.
	#
	# The first run of the model came out at 13 turns against a target of 5, which means
	# the probe's damage-per-turn over-reads real in-fight output. Likely causes, all
	# checkable from the columns below: the probe never lets the monster die (so the
	# player's opening burst is averaged over a long window differently), it tops the
	# player's HP up each turn, and it measures against whatever monster the OLD model
	# produced. This prints predicted vs actual side by side so the correction is
	# measured rather than guessed.
	var N := 40
	print("\n===== #6 REFERENCE MODEL VALIDATION =====")
	print("Target: a plain same-level fight lasts ~%.0f turns and costs ~%.0f%% of the bar." % [TARGET_TURNS_NORMAL_SIM, DANGER_NORMAL_SIM * 100.0])
	print("dptCurve = what the curve says; dptReal = damage/turn actually dealt in the fight.")
	print("The ratio is the correction the curve needs.")
	print("%-8s %11s %11s %8s %8s %8s %8s" % ["Level", "dptCurve", "dptReal", "ratio", "turns", "win%", "HPcost"])
	for lvl in PROGRESSION_LEVELS:
		var ref := _curve_at(lvl)
		if ref.is_empty():
			continue
		var tot_turns := 0.0
		var tot_dealt := 0.0
		var wins := 0
		var hp_cost := 0.0
		var n := 0
		for klass in ["Fighter", "Wizard", "Thief"]:
			for i in range(N / 3):
				var ch = make_char(lvl, "average", klass)
				var monster := make_monster(lvl, "normal", 1.0)
				var mhp0: int = int(monster.get("max_hp", 1))
				var php0: int = ch.get_total_max_hp()
				ch.in_combat = false
				combat_mgr.start_combat(0, ch, monster)
				if not combat_mgr.active_combats.has(0):
					continue
				var combat = combat_mgr.active_combats[0]
				var turns := 0
				while turns < 300:
					if ch.current_hp <= 0 or int(monster.get("current_hp", 0)) <= 0 or combat.get("combat_ended", false):
						break
					turns += 1
					if combat.get("player_can_act", true):
						match ch.get_class_path():
							"trickster": _player_act_trickster(combat, ch)
							"mage": _player_act_mage(combat, ch)
							_: _player_act(combat, ch)
					if int(monster.get("current_hp", 0)) <= 0:
						break
					combat_mgr.process_monster_turn(combat)
				var won: bool = int(monster.get("current_hp", 0)) <= 0 and ch.current_hp > 0
				if won:
					wins += 1
				tot_turns += float(turns)
				# AGGREGATE totals, not a mean of per-fight ratios. The mean of
				# (dealt/turns) is dominated by short fights while the mean of turns is
				# dominated by long ones, so dividing one by the other is not a rate and
				# reads far too high — the first version of this audit reported a dpt that
				# was mathematically inconsistent with its own turn count.
				tot_dealt += float(mhp0 - maxi(0, int(monster.get("current_hp", 0))))
				hp_cost += 100.0 * float(php0 - maxi(0, ch.current_hp)) / float(maxi(1, php0))
				n += 1
				combat_mgr.end_combat(0, false, false)
		if n == 0:
			continue
		var dpt_real: float = tot_dealt / maxf(1.0, tot_turns)
		print("%-8d %11.0f %11.0f %7.2fx %8.1f %7d%% %7.0f%%" % [
			lvl, float(ref.get("dpt", 0.0)), dpt_real,
			dpt_real / maxf(1.0, float(ref.get("dpt", 1.0))),
			tot_turns / float(n), int(100.0 * wins / n), hp_cost / float(n)])
	print("")
	print("If the ratio column is roughly CONSTANT, the curve is the right shape and only")
	print("needs one scalar correction. If it drifts with level, the probe is wrong in a")
	print("level-dependent way and the measurement itself has to change.")
	print("=====================================================================\n")

func run_companion_cap_probe():
	_use_companions_for_this_audit()
	"""Does the ceiling actually bind, and does a rarer variant still pay MORE?

	Two things have to hold at once. The runaway must stop (it reached +1127% max HP), and
	the rarest variants must remain the best thing you can be carrying — the owner\'s point
	that players hunt rare variants and will use them constantly. A hard clamp would satisfy
	the first and destroy the second, which is why the ceiling is approached asymptotically
	and is itself scaled by the variant multiplier."""
	print("\n===== COMPANION CEILING — does it bind, and does rarity still pay? =====")
	print("Titan \'Titanic Endurance\' (hp_bonus, base 12, scaling 0.25), ceiling 40% x variant.")
	print("%-10s %12s %12s %12s %12s" % ["cLvl", "common 1.00x", "rare 1.30x", "rarest 1.60x", "rarest/common"])
	for lvl in [1, 10, 50, 100, 500, 1000, 5000, 10000]:
		var row: Array = []
		for vm in [1.0, 1.30, 1.60]:
			var ab = drop_tables.get_monster_companion_abilities("Titan", lvl, vm, 1, "")
			row.append(float(int(ab.passive.get("value", 0))))
		print("%-10d %11.0f%% %11.0f%% %11.0f%% %11.2fx" % [lvl, row[0], row[1], row[2],
			row[2] / maxf(0.01, row[0])])
	print("")
	print("Old formula for comparison (base*vm + scaling*lvl*vm), common variant:")
	var line := "   "
	for lvl in [1, 10, 50, 100, 500, 1000, 5000, 10000]:
		line += "L%d=%.0f%%  " % [lvl, 12.0 + 0.25 * float(lvl)]
	print(line)
	print("=====================================================================\n")

func run_companion_hp_probe():
	_use_companions_for_this_audit()
	"""How large is the companion's max-HP bonus, and does it scale with level?

	`start_combat` applies it as `max_hp += get_total_max_hp() * pct / 100`, so the whole
	health bar is multiplied by (1 + pct/100) the moment a fight begins. The outcome probe
	saw that reach 12.27x at L5000, which is a balance question, not only a measurement one."""
	print("
===== COMPANION MAX-HP BONUS =====")
	print("%-8s %10s %10s %10s %10s" % ["level", "n", "median%", "worst%", "worst mult"])
	for lvl in [1, 5, 10, 50, 100, 500, 1000, 5000, 10000]:
		var vals: Array = []
		for klass in ["Fighter", "Wizard", "Thief"]:
			for i in range(12):
				var ch = make_char(lvl, "average", klass)
				if not ch.has_active_companion():
					vals.append(0.0)
					continue
				vals.append(float(int(ch.get_companion_bonus("hp_bonus"))))
		if vals.is_empty():
			continue
		vals.sort()
		var med: float = vals[vals.size() / 2]
		var worst: float = vals[vals.size() - 1]
		print("%-8d %10d %9.0f%% %9.0f%% %9.2fx" % [lvl, vals.size(), med, worst, 1.0 + worst / 100.0])
	print("=====================================================================
")

var _probe_override: bool = false

func run_deck_probe():
	"""Does a played card actually produce a DIFFERENT hand next round?

	Reported: "Round 1 test002 had Arcane Surge, Bolt, and Life Leech. I used Bolt. It's back to
	my turn and I still have the same three options." With a six-card deck and a hand of three,
	the next hand should be the three you did NOT hold - so a repeat is proof of a fault, not
	bad luck. Exercises `_consume_card_from_hand` and `_draw_to_hand` directly."""
	print("
===== DECK CYCLE =====")
	var view := {
		"combat_hand": [],
		"combat_deck": ["a", "b", "c", "d", "e", "f"],
		"combat_discard": [],
		"combat_hand_size": 3,
	}
	combat_mgr._draw_to_hand(view)
	var h1: Array = (view["combat_hand"] as Array).duplicate()
	h1.sort()
	print("  round 1 hand: %s   (deck %d, discard %d)" % [str(h1), (view["combat_deck"] as Array).size(), (view["combat_discard"] as Array).size()])
	var played := String(view["combat_hand"][0])
	combat_mgr._consume_card_from_hand(view, played)
	var h2: Array = (view["combat_hand"] as Array).duplicate()
	h2.sort()
	print("  played '%s' -> round 2 hand: %s   (deck %d, discard %d)" % [played, str(h2), (view["combat_deck"] as Array).size(), (view["combat_discard"] as Array).size()])
	var overlap := 0
	for c in h2:
		if c in h1:
			overlap += 1
	print("  cards carried over from the previous hand: %d of %d" % [overlap, h2.size()])
	if overlap == 0:
		print("  PASS — a full six-card deck yields the three you did not hold")
	else:
		print("  FAIL — the deck is not cycling as designed")
	print("=====================================================================
")

func run_damage_tag_probe():
	"""Does the damage number ride BESIDE each ability line, and on the right line?

	The floating number over the monster used to be recovered by regex from the line text, so
	folding each cast onto one line silently switched the numbers off. The fix moves the value
	onto the per-beat metadata; this probe is what says it actually arrives, and lands on the
	line that shows the hit rather than a neighbour."""
	print("
===== ABILITY DAMAGE METADATA =====")
	var checked := 0
	var tagged := 0
	var mismatched := 0
	for cls in ["Wizard", "Fighter", "Thief"]:
		var ch = make_char(60, "average", cls)
		var monster := make_monster(60, "normal", 1.0)
		monster["current_hp"] = int(monster.get("max_hp", 100000)) * 500   # survive the whole probe
		monster["max_hp"] = int(monster["current_hp"])
		# Every ability in the list is cast, whatever the class, so the probe covers all ten
		# damage lines in one pass. The stat gates are about build identity, not about the
		# damage plumbing being tested here.
		ch.intelligence = max(ch.intelligence, 40)
		ch.wits = max(ch.wits, 40)
		ch.strength = max(ch.strength, 40)
		ch.calculate_derived_stats()
		ch.in_combat = false
		combat_mgr.start_combat(0, ch, monster)
		if not combat_mgr.active_combats.has(0):
			continue
		print("--- %s ---" % cls)
		for ab in ABILITY_PROBE_LIST:
			# Top the resources up so the cast never bounces off a cost check.
			ch.current_mana = ch.max_mana
			ch.current_stamina = ch.max_stamina
			ch.current_energy = ch.max_energy
			# Deal the card we want to test. Otherwise the hand gate rejects it before any of
			# the damage code runs, and the probe would report a clean zero.
			combat_mgr.active_combats[0]["combat_hand"] = [ab]
			# Magic Bolt spends an amount the player names, so it needs the arg the chat command
			# carries; without one it returns a usage string and the probe would silently skip
			# the single most-used card in the game.
			var arg := str(int(ch.max_mana * 0.25)) if ab == "magic_bolt" else ""
			var r: Dictionary = combat_mgr.process_ability_command(0, ab, arg)
			if not bool(r.get("success", false)):
				print("   skip %-12s %s" % [ab, _strip_bb(String(r.get("message", (r.get("messages", ["?"])[0] if not (r.get("messages", []) as Array).is_empty() else "?")))).substr(0, 60)])
				continue
			var msgs: Array = r.get("messages", [])
			var dmgs: Array = r.get("message_damage", []) if r.get("message_damage", null) is Array else []
			for i in range(msgs.size()):
				var d := int(dmgs[i]) if i < dmgs.size() else 0
				if d <= 0:
					continue
				checked += 1
				# The line the number is attached to must CONTAIN that number - otherwise the
				# index has drifted and the pop would land on the wrong beat.
				if String(msgs[i]).contains(str(d)):
					tagged += 1
				else:
					mismatched += 1
					print("   MISMATCH dmg=%d not in: %s" % [d, _strip_bb(String(msgs[i])).substr(0, 70)])
				print("   %-10s dmg=%-9d | %s" % [ab, d, _strip_bb(String(msgs[i])).substr(0, 62)])
		combat_mgr.end_combat(0, false, false)
	# ---- phase 2: the lines that used to be REGEXED out of their own prose ------------------
	# Basic attacks, companion swings, double-strike / shocking / execute procs, poison, burn,
	# bleed and the reflect family. These were the parser's whole remaining job.
	print("--- basic attacks, companions, procs and damage-over-time ---")
	var kinds := {}
	var multi_line_actions := 0
	var total_actions := 0
	for cls in ["Wizard", "Fighter", "Thief"]:
		var ch2 = make_char(60, "average", cls)
		var mon2 := make_monster(60, "normal", 1.0)
		mon2["current_hp"] = int(mon2.get("max_hp", 100000)) * 200
		mon2["max_hp"] = int(mon2["current_hp"])
		ch2.in_combat = false
		combat_mgr.start_combat(0, ch2, mon2)
		if not combat_mgr.active_combats.has(0):
			continue
		var combat2 = combat_mgr.active_combats[0]
		for _r in range(30):
			ch2.current_hp = ch2.max_hp   # stay alive long enough to see every proc
			var r2: Dictionary = combat_mgr.process_combat_action(0, combat_mgr.CombatAction.ATTACK)
			var m2: Array = r2.get("messages", [])
			var d2: Array = r2.get("message_damage", []) if r2.get("message_damage", null) is Array else []
			# How many damage lines does ONE action produce? The party path attaches its enemy-bar
			# snapshot to the LAST line of the actor's beat, so anything above 1 is a number that
			# pops with the bar still frozen.
			var _n_dmg := 0
			for i in range(m2.size()):
				if i < d2.size() and int(d2[i]) > 0:
					_n_dmg += 1
			if _n_dmg > 1:
				multi_line_actions += 1
			if _n_dmg >= 1:
				total_actions += 1
			for i in range(m2.size()):
				var d := int(d2[i]) if i < d2.size() else 0
				if d <= 0:
					continue
				checked += 1
				var clean := _strip_bb(String(m2[i]))
				# One key per wording, so the summary says WHICH kinds were actually exercised
				# rather than just how many lines passed - a shape never reached is not verified.
				var key := clean.substr(0, 26)
				if String(m2[i]).contains(str(d)):
					tagged += 1
					kinds[key] = int(kinds.get(key, 0)) + 1
				else:
					mismatched += 1
					print("   MISMATCH dmg=%d not in: %s" % [d, clean.substr(0, 70)])
			if int(mon2.get("current_hp", 0)) <= 0:
				break
			combat_mgr.process_monster_turn(combat2)
		combat_mgr.end_combat(0, false, false)
	for k in kinds:
		print("   %-4d x %s" % [int(kinds[k]), k])
	print("
actions with MORE THAN ONE damage line: %d of %d  (each extra line pops a number with the enemy bar frozen)" % [multi_line_actions, total_actions])
	print("
lines carrying a number: %d   on the right line: %d   drifted: %d" % [checked, tagged, mismatched])
	print("=====================================================================
")

const ABILITY_PROBE_LIST := ["magic_bolt", "blast", "meteor", "power_strike", "shield_bash",
	"cleave", "devastate", "ambush", "exploit", "gambit"]

func _strip_bb(line: String) -> String:
	var out := ""
	var skip := false
	for c in line.replace("
", " "):
		if c == "[":
			skip = true
		elif c == "]":
			skip = false
		elif not skip:
			out += c
	return out

func run_actor_tag_probe():
	"""Does every solo combat line come back attributed to the right actor?

	The tag ships inert - nothing renders it yet - so a mistake here would sit unnoticed until
	the log work is built on top of it. Printing the attribution beside the line is the cheapest
	way to see it is right, and a companion line landing under `member` is obvious on sight."""
	print("
===== SOLO ACTOR TAGGING =====")
	var ch = make_char(30, "average", "Fighter")
	var monster := make_monster(30, "normal", 1.0)
	ch.in_combat = false
	combat_mgr.start_combat(0, ch, monster)
	if not combat_mgr.active_combats.has(0):
		print("no combat")
		return
	var combat = combat_mgr.active_combats[0]
	print("companion: %s" % ("yes - " + String(ch.get_active_companion().get("name", "?")) if ch.has_active_companion() else "NONE (companion lines will not appear)"))
	var rounds := 0
	while rounds < 4 and ch.current_hp > 0 and int(monster.get("current_hp", 0)) > 0:
		rounds += 1
		# process_combat_action is what the SERVER calls - process_attack is only part of it, and
		# the monster's retaliation is appended by the OUTER function. Probing the inner one
		# would have verified a path the game does not take.
		var r: Dictionary = combat_mgr.process_combat_action(0, combat_mgr.CombatAction.ATTACK)
		var msgs: Array = r.get("messages", [])
		var actors: Array = r.get("message_actors", []) if r.get("message_actors", null) is Array else []
		print("--- round %d: %d lines, %d tags ---" % [rounds, msgs.size(), actors.size()])
		for i in range(msgs.size()):
			var a := String(actors[i]) if i < actors.size() else "(none)"
			var line := String(msgs[i]).replace("
", " ")
			# Strip BBCode so the attribution is what stands out, not the colour tags.
			var clean := ""
			var skip := false
			for c in line:
				if c == "[":
					skip = true
				elif c == "]":
					skip = false
				elif not skip:
					clean += c
			print("   %-10s | %s" % [a, clean.substr(0, 78)])
		if int(monster.get("current_hp", 0)) <= 0:
			break
		combat_mgr.process_monster_turn(combat)
	combat_mgr.end_combat(0, false, false)
	print("=====================================================================
")

func run_level_forensics():
	"""Why is ONE anchor off when its neighbours land?

	L100 verified at 43% and 52% win across two rounds against a 60% target, while every other
	anchor from L1 to L10000 came in within a few points. Its strength ramp is the tell: L50 ->
	L100 is 4.28x for a 2x level step where every other step is 2.0-2.3x.

	A single bad anchor with well-behaved neighbours is not a tuning failure, it is something
	about that level. So: what actually SPAWNS there, how strong is each thing relative to the
	curve, and which of them is doing the killing."""
	var levels: Array = [50, 100, 250]
	for lvl in levels:
		print("\n===== LEVEL %d FORENSICS =====" % lvl)
		# --- what spawns, and how strong is it vs the curve anchor ---
		var seen := {}
		var hp_by := {}
		var st_by := {}
		var n_spawn := 300
		for i in range(n_spawn):
			var m := make_monster(lvl, "normal", 1.0)
			var nm := String(m.get("name", "?"))
			# Strip variant/empowered prefixes so species group together.
			var base := String(m.get("base_name", nm))
			seen[base] = int(seen.get(base, 0)) + 1
			hp_by[base] = float(hp_by.get(base, 0.0)) + float(m.get("max_hp", 0))
			st_by[base] = float(st_by.get(base, 0.0)) + float(m.get("strength", 0))
		var names: Array = seen.keys()
		names.sort()
		print("%-26s %6s %10s %10s %8s" % ["species", "share", "mean hp", "mean str", "apex"])
		for nm in names:
			var c: int = int(seen[nm])
			var apex := "APEX" if monster_db.has_method("is_apex_species") and monster_db.is_apex_species(nm) else ""
			print("%-26s %5.0f%% %10.0f %10.0f %8s" % [nm, 100.0 * float(c) / float(n_spawn),
				float(hp_by[nm]) / float(c), float(st_by[nm]) / float(c), apex])
		# --- how deadly is each, measured ---
		print("  --- win rate per species (Fighter/Wizard/Thief pooled) ---")
		var wins := {}
		var runs := {}
		var samples := 12
		for klass in ["Fighter", "Wizard", "Thief"]:
			for i in range(samples * maxi(1, names.size())):
				var ch = make_char(lvl, "average", klass)
				var monster := make_monster(lvl, "normal", 1.0)
				var base2 := String(monster.get("base_name", monster.get("name", "?")))
				ch.in_combat = false
				combat_mgr.start_combat(0, ch, monster)
				if not combat_mgr.active_combats.has(0):
					continue
				var combat = combat_mgr.active_combats[0]
				var turns := 0
				while turns < 400:
					if ch.current_hp <= 0 or int(monster.get("current_hp", 0)) <= 0 or combat.get("combat_ended", false):
						break
					turns += 1
					if combat.get("player_can_act", true):
						match ch.get_class_path():
							"trickster": _player_act_trickster(combat, ch)
							"mage": _player_act_mage(combat, ch)
							_: _player_act(combat, ch)
					if int(monster.get("current_hp", 0)) <= 0:
						break
					combat_mgr.process_monster_turn(combat)
				runs[base2] = int(runs.get(base2, 0)) + 1
				if int(monster.get("current_hp", 0)) <= 0 and ch.current_hp > 0:
					wins[base2] = int(wins.get(base2, 0)) + 1
				combat_mgr.end_combat(0, false, false)
		var keys: Array = runs.keys()
		keys.sort()
		for nm in keys:
			var r: int = int(runs[nm])
			if r < 4:
				continue
			print("  %-26s n=%-4d win %3.0f%%" % [nm, r, 100.0 * float(wins.get(nm, 0)) / float(r)])
	print("=====================================================================\n")

func run_monster_check():
	"""Does `make_monster` produce what the curve says? The calibration verifies through
	`_cal_override`, which forces hp/str directly, but a player fights whatever make_monster
	builds. If the two disagree the curve is tuned for a monster that never spawns."""
	print("
===== ANCHOR vs make_monster =====")
	print("%-8s %10s %10s %10s %10s %8s" % ["level", "anchor hp", "made hp", "anchor str", "made str", "def"])
	var f = FileAccess.open("res://shared/reference_monster_curve.json", FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	for a in parsed.get("anchors", []):
		var lvl := int(a.get("level", 0))
		if lvl > 100:
			continue
		var tot_hp := 0.0
		var tot_st := 0.0
		var tot_df := 0.0
		var n := 40
		for i in range(n):
			var m := make_monster(lvl, "normal", 1.0)
			tot_hp += float(m.get("max_hp", 0))
			tot_st += float(m.get("strength", 0))
			tot_df += float(m.get("defense", 0))
		print("%-8d %10d %10.0f %10d %10.0f %8.0f" % [lvl, int(a.get("hp", 0)), tot_hp / n,
			int(a.get("str", 0)), tot_st / n, tot_df / n])
	print("=====================================================================
")

func run_art_audit():
	"""Every monster name the game can show, checked against the ASCII art it would resolve to.

	Missing art has now been reported by players three separate times, each time as a single
	name — Venomous Orc, a Frenzied Ogre that turned out fine, and now a Spider. Each was fixed
	as a one-off. An inventory retires the class instead: it walks every species the database
	can produce AND every dungeon boss, applies the variant and empowered prefixes a real
	monster can carry, and lists what `resolve_art_key` cannot place.

	Dungeon BOSSES are the gap the per-name fixes kept missing. They are named independently of
	their species (\"Spider Queen\" for a Giant Spider, \"Goblin King\" for a Goblin), so no amount
	of prefix-stripping reaches the species art — \"Spider Queen\" reduces to \"Queen\", which is
	not a monster at all."""
	var ArtScript = load("res://client/monster_art.gd")
	if ArtScript == null:
		print("could not load monster_art.gd")
		return
	print("
===== ASCII ART COVERAGE =====")
	var missing: Array = []
	var checked := 0

	var species: Array = monster_db.get_all_monster_names()
	# The prefixes a live monster can actually arrive with.
	var prefixes: Array = ["", "Venomous ", "Frenzied ", "Swift ", "Armored ", "Ancient "]
	for nm in species:
		for pre in prefixes:
			var full: String = pre + String(nm)
			checked += 1
			if String(ArtScript.resolve_art_key(full)) == "":
				missing.append(full)

	# Dungeon bosses, which carry their OWN names rather than their species'.
	var DungeonScript = load("res://shared/dungeon_database.gd")
	if DungeonScript != null:
		var dd = DungeonScript.new()
		var seen := {}
		for prop in ["DUNGEON_TYPES", "DUNGEONS"]:
			if not (prop in dd):
				continue
			var tbl = dd.get(prop)
			if not (tbl is Dictionary):
				continue
			for k in tbl.keys():
				var entry = tbl[k]
				if not (entry is Dictionary):
					continue
				var boss = entry.get("boss", {})
				if boss is Dictionary and boss.has("name"):
					var bn := String(boss["name"])
					if seen.has(bn):
						continue
					seen[bn] = true
					checked += 1
					if String(ArtScript.resolve_art_key(bn)) == "":
						missing.append("[BOSS] " + bn + "  (species: " + String(boss.get("monster_type", "?")) + ")")

	print("checked %d names, %d with NO art:" % [checked, missing.size()])
	for m in missing:
		print("   " + m)
	if missing.is_empty():
		print("   (none)")
	print("=====================================================================
")

func run_offer_probe():
	"""Does a rank-up actually DEAL an offer? The reveal never fired in play.

	The client falls back to the legacy three-option popup when `upgrade_offer` arrives empty,
	so an offer that fails to build is indistinguishable, from the player's seat, from the
	feature not existing. That is exactly what was reported: cleave, blast and forcefield all
	produced the old menu."""
	var CU = load("res://shared/card_upgrades.gd")
	print("
===== RANK-UP OFFER PROBE =====")
	print("%-16s %-10s %6s %6s   %s" % ["ability", "kind", "m1", "m3", "sample of the m3 draw"])
	for ab in ["cleave", "power_strike", "shield_bash", "blast", "forcefield", "haste",
			"magic_bolt", "meteor", "ambush", "distract", "analyze", "gambit", "vanish"]:
		var is_damage: bool = ab in combat_mgr.ABILITY_WEIGHTS or ab in ["shield_bash", "devastate", "ambush", "gambit", "exploit", "frost_nova"]
		var is_buff: bool = ab in ["forcefield", "shield", "haste", "iron_skin", "fortify", "rally", "berserk", "war_cry", "overload", "vanish"]
		var is_control: bool = ab in ["paralyze", "banish", "sabotage", "distract", "analyze"]
		var kind: String = CU.card_kind(ab, is_damage, is_buff, is_control)
		var m1: Array = CU.draw_choices(kind, 1, [])
		var m3: Array = CU.draw_choices(kind, 3, [])
		var names := ""
		for u in m3:
			names += String(u.get("id", "?")) + " "
		print("%-16s %-10s %6d %6d   %s" % [ab, kind, m1.size(), m3.size(), names.substr(0, 60)])
	print("")
	print("OFFER_SIZE=%d  REVEALS_ALLOWED=%d  TRADEOFF_MIN_MILESTONE=%d" % [
		CU.OFFER_SIZE, CU.REVEALS_ALLOWED, CU.TRADEOFF_MIN_MILESTONE])
	var total := 0
	var wired := 0
	for u in CU.UPGRADES:
		total += 1
		if bool(u.get("wired", false)):
			wired += 1
	print("UPGRADES: %d total, %d wired (only wired ones may be offered)" % [total, wired])
	print("=====================================================================
")

func run_gear_power_audit():
	"""WHERE does the gear ladder go flat?

	The progression spread showed a gear step (under -> average) worth about 0 percentage
	points of win rate while a companion is worth +28 to +69. Before changing any numbers it is
	worth knowing whether gear contributes nothing, or contributes plenty but identically at
	both tiers - those want opposite fixes. So this reports the raw stat contribution rather
	than a fight outcome: no combat, no RNG beyond the affix rolls themselves.

	`naked` is the same character with every slot empty, which is the only honest denominator -
	comparing two geared states to each other cannot show what gear is worth in total."""
	print("\n===== GEAR POWER — what does each rung of the ladder actually add? =====")
	print("Same character, same level, only the equipment changes. HP and ATK are totals.")
	print("%-7s %-10s %9s %9s %9s %9s %9s" % ["level", "gear", "maxHP", "vs naked", "attack", "vs naked", "affixes"])
	var saved_mode: String = _companion_mode
	_companion_mode = "none"   # isolate GEAR; the companion is the other axis
	for lvl in [10, 100, 1000, 5000]:
		var base_hp: float = 0.0
		var base_atk: float = 0.0
		for gear in ["naked", "common", "uncommon", "rare", "epic", "legendary"]:
			var hp_tot: float = 0.0
			var atk_tot: float = 0.0
			var affix_tot: float = 0.0
			# Was a hardcoded 8. Rarity rolls affixes, so a rung's stats are a DISTRIBUTION, and
			# at n=8 the top three rungs read as inverted (legendary below epic) - which would
			# have been reported as a defect on the strength of noise.
			var n := maxi(40, _audit_n)
			for i in range(n):
				var ch = make_char(lvl, gear, "Fighter")
				if gear == "naked":
					# `equipped`, not `equipment` - the first version of this probe guessed the
					# field name and errored out, which is the same guess-instead-of-read habit
					# that has bitten the test fixtures repeatedly today.
					for slot in SLOTS:
						ch.equipped[slot] = {}
				hp_tot += float(ch.get_total_max_hp())
				var eb: Dictionary = ch.get_equipment_bonuses()
				atk_tot += float(int(eb.get("attack", 0)) + int(ch.strength))
				for slot in SLOTS:
					var it = ch.equipped.get(slot, {})
					if it is Dictionary and it.has("affixes") and it["affixes"] is Dictionary:
						# A DICTIONARY of stat -> value, not an array. Testing `is Array` here
						# reported 0.0 affixes at every level and every rarity, which would have
						# been read as "gear never rolls affixes" - a fabricated defect from a
						# probe that was wrong about the shape of the data it was reading.
						affix_tot += float((it["affixes"] as Dictionary).size())
			var hp: float = hp_tot / float(n)
			var atk: float = atk_tot / float(n)
			if gear == "naked":
				base_hp = hp
				base_atk = atk
			print("%-7d %-10s %9.0f %8.2fx %9.0f %8.2fx %9.1f" % [lvl, gear, hp,
				hp / maxf(1.0, base_hp), atk, atk / maxf(1.0, base_atk), affix_tot / float(n)])
		print("")
	_companion_mode = saved_mode
	print("Every rung fills ALL slots at ONE rarity, at the character's own level, so the only")
	print("variable is rarity. Read the step BETWEEN consecutive rows: if common -> legendary is")
	print("a small climb, the ladder is flat and the rarity steps want widening. The earlier")
	print("under/average/bis comparison was NOT a ladder - `average` leaves slots empty by")
	print("design - and reading it as one produced a wrong answer.")
	print("=====================================================================\n")

func run_progression_spread():
	"""How much is PROGRESSION worth, and do gear and companion keep pace with each other?

	The owner's question, in two parts: can a player walk through the content on common gear
	with no rare companion, and can equipment keep up with companion power as both scale?
	Neither is answerable from a single reference player - the calibration measures one point
	(average gear + a matched companion) and reports a win rate for it, which says nothing
	about the spread around that point.

	So this measures the SAME fight at four progression states and reports the gradient. Read
	it as: a healthy curve has the under-geared player clearly struggling, the reference near
	its target, and the best-geared player strong but not untouchable. If every row is high,
	progression buys nothing and the content is walkable from the start. If the gear rows move
	far less than the companion rows, equipment is not keeping pace and the companion is
	carrying the player - which is what the uncapped companion scaling used to do."""
	var samples: int = maxi(12, int(_audit_n / 3.0))
	var saved_mode: String = _companion_mode
	print("\n===== PROGRESSION SPREAD — what is gear and companion worth? =====")
	print("Same normal monster at each level; only the PLAYER changes. Target for the")
	print("reference row (avg gear + companion) is %.0f%% win." % (WIN_NORMAL_SIM * 100.0))
	print("%-8s %-34s %8s %8s %8s" % ["level", "player state", "win", "turns", "cost"])
	for lvl in [10, 100, 1000, 5000]:
		var rows: Array = []
		# The RARITY LADDER, not under/average/bis. Those three are not consecutive rungs -
		# `average` leaves slots empty by design - so the step between them measured as ~0pp and
		# was wrongly read as "gear progression is flat". Each row below differs from the one
		# above it in exactly one variable, so the steps mean something.
		for st in [
			{"gear": "common", "comp": "none", "label": "common gear, no companion"},
			{"gear": "uncommon", "comp": "none", "label": "uncommon gear, no companion"},
			{"gear": "rare", "comp": "none", "label": "rare gear, no companion"},
			{"gear": "epic", "comp": "none", "label": "epic gear, no companion"},
			{"gear": "rare", "comp": "match", "label": "rare gear + COMPANION"},
			{"gear": "legendary", "comp": "match", "label": "legendary gear + companion"},
		]:
			_companion_mode = String(st["comp"])
			var r := _fight_stats_at(lvl, samples, String(st["gear"]))
			if r.is_empty():
				continue
			rows.append({"label": st["label"], "win": float(r["win"]), "turns": float(r["turns"]), "cost": float(r["cost"])})
			print("%-8d %-34s %7.0f%% %8.1f %7.0f%%" % [lvl, st["label"],
				100.0 * float(r["win"]), float(r["turns"]), 100.0 * float(r["cost"])])
		if rows.size() >= 6:
			# Three GEAR rungs, each one rarity step, against ONE companion step taken at the
			# same gear. That is the comparison the owner asked for - whether equipment keeps
			# pace with companion power - in units that can actually be compared.
			var s1: float = 100.0 * (rows[1]["win"] - rows[0]["win"])   # common   -> uncommon
			var s2: float = 100.0 * (rows[2]["win"] - rows[1]["win"])   # uncommon -> rare
			var s3: float = 100.0 * (rows[3]["win"] - rows[2]["win"])   # rare     -> epic
			var cs: float = 100.0 * (rows[4]["win"] - rows[2]["win"])   # rare, +companion
			print("         gear rungs: +%.0f / +%.0f / +%.0fpp   |   ONE companion at rare gear: +%.0fpp" % [s1, s2, s3, cs])
			print("         (mean gear rung %.0fpp vs companion %.0fpp)" % [(s1 + s2 + s3) / 3.0, cs])
		print("")
	_companion_mode = saved_mode
	print("=====================================================================\n")

func run_outcome_probe():
	"""Classify how fights actually END, rather than only counting wins.

	`_fight_stats_at` reports a WIN RATE, and everything that is not a win is implicitly read
	as a death. That is an assumption, and the calibration output contradicted it: L5000 came
	back at 62% win with a 13% mean health-bar cost. Those cannot both be true if the other 38%
	were deaths — a death spends the whole bar, so the mean cost could not be below 0.38.

	So this counts the four ways the loop can leave a fight separately. Same `make_char` /
	`make_monster` / turn loop as the calibration path, deliberately: a hand-copied fight loop
	would be the two-paths-one-field defect, and a probe that disagrees with the thing it is
	probing measures nothing."""
	var samples: int = maxi(6, int(_audit_n / 5.0))
	print("
===== OUTCOME PROBE — how do normal fights END? =====")
	print("win = monster dead, player alive.  death = player at 0.")
	print("escape = combat ended with BOTH alive (Outsmart).  stall = hit the 400-turn cap.")
	print("%-8s %6s %7s %7s %7s %7s %8s" % ["level", "n", "win", "death", "escape", "stall", "cost"])
	# Two sweeps. The plain one is what a player meets. The `override` one forces the exact
	# hp/str refcal wrote, which is what refcal's own verify pass measures - if the two
	# disagree, the disagreement lives in the override path, not in the game.
	var anchors := {}
	var cf = FileAccess.open("res://shared/reference_monster_curve.json", FileAccess.READ)
	if cf:
		var parsed = JSON.parse_string(cf.get_as_text())
		cf.close()
		if parsed is Dictionary:
			for a in parsed.get("anchors", []):
				anchors[int(a.get("level", 0))] = a
	for lvl in [1, 5, 10, 50, 500, 5000]:
		var tally := {"win": 0, "death": 0, "escape": 0, "stall": 0}
		var by_class := {}
		var cost_tot := 0.0
		var n := 0
		# Cost is a MEAN, so a few impossible values drag it a long way without ever looking
		# wrong in the summary. Track the extremes and count the negatives: a negative
		# share-of-health-bar is not noise, it is a broken measurement, and it is the only way
		# a run containing deaths can report a mean below its own death rate.
		var cost_min := 99.0
		var cost_max := -99.0
		var cost_neg := 0
		var hp_grew := 0
		var hp_grow_max := 1.0
		var peak_over := 0
		var peak_over_max := 1.0
		for klass in ["Fighter", "Wizard", "Thief"]:
			by_class[klass] = {"win": 0, "death": 0, "escape": 0, "stall": 0}
			for i in range(samples):
				var ch = make_char(lvl, "average", klass)
				if _probe_override and anchors.has(lvl):
					_cal_override = {"level": lvl, "hp": int(anchors[lvl].get("hp", 0)), "str": int(anchors[lvl].get("str", 0))}
				var monster := make_monster(lvl, "normal", 1.0)
				_cal_override = {}
				var php0: int = ch.get_total_max_hp()
				ch.in_combat = false
				combat_mgr.start_combat(0, ch, monster)
				if not combat_mgr.active_combats.has(0):
					continue
				# The cost denominator is sampled BEFORE combat starts. If anything raises max
				# HP after that point, `php0 - current_hp` can come out negative and quietly
				# drag a mean below its own death rate. Measure the growth rather than assume it.
				var php_after: int = ch.get_total_max_hp()
				if php_after > php0:
					hp_grew += 1
					hp_grow_max = maxf(hp_grow_max, float(php_after) / float(maxi(1, php0)))
					if float(php_after) > 1.5 * float(php0) and hp_grew < 4:
						print("           !! php0=%d -> %d (%.2fx)  base max_hp=%d  companion boost applied=%d  has_comp=%s" % [
							php0, php_after, float(php_after) / float(maxi(1, php0)), ch.max_hp,
							int(combat_mgr.active_combats[0].get("companion_hp_boost_applied", 0)),
							str(ch.has_active_companion())])
				var combat = combat_mgr.active_combats[0]
				var turns := 0
				var peak_hp: int = ch.current_hp
				while turns < 400:
					if ch.current_hp <= 0 or int(monster.get("current_hp", 0)) <= 0 or combat.get("combat_ended", false):
						break
					turns += 1
					if combat.get("player_can_act", true):
						match ch.get_class_path():
							"trickster": _player_act_trickster(combat, ch)
							"mage": _player_act_mage(combat, ch)
							_: _player_act(combat, ch)
					peak_hp = maxi(peak_hp, ch.current_hp)
					if int(monster.get("current_hp", 0)) <= 0:
						break
					combat_mgr.process_monster_turn(combat)
					peak_hp = maxi(peak_hp, ch.current_hp)
				if peak_hp > php0:
					peak_over += 1
					peak_over_max = maxf(peak_over_max, float(peak_hp) / float(maxi(1, php0)))
				var outcome := ""
				if ch.current_hp <= 0:
					outcome = "death"
				elif int(monster.get("current_hp", 0)) <= 0:
					outcome = "win"
				elif turns >= 400:
					outcome = "stall"
				else:
					outcome = "escape"
				tally[outcome] += 1
				by_class[klass][outcome] += 1
				var c: float = float(php0 - maxi(0, ch.current_hp)) / float(maxi(1, php0))
				cost_tot += c
				cost_min = minf(cost_min, c)
				cost_max = maxf(cost_max, c)
				if c < 0.0:
					cost_neg += 1
				n += 1
				combat_mgr.end_combat(0, false, false)
		if n == 0:
			continue
		print("%-8d %6d %6.0f%% %6.0f%% %6.0f%% %6.0f%% %7.0f%%" % [lvl, n,
			100.0 * tally["win"] / n, 100.0 * tally["death"] / n,
			100.0 * tally["escape"] / n, 100.0 * tally["stall"] / n,
			100.0 * cost_tot / n])
		print("           cost min %.2f  max %.2f  NEGATIVE %d of %d" % [cost_min, cost_max, cost_neg, n])
		print("           max-HP grew after start_combat: %d of %d (worst %.2fx);  in-fight HP exceeded php0: %d (worst %.2fx)" % [hp_grew, n, hp_grow_max, peak_over, peak_over_max])
		for klass in ["Fighter", "Wizard", "Thief"]:
			var b = by_class[klass]
			print("           %-8s win %d  death %d  escape %d  stall %d" % [klass, b["win"], b["death"], b["escape"], b["stall"]])
	if not _probe_override:
		_probe_override = true
		print("--- same levels, forcing refcal's WRITTEN anchors (its verify path) ---")
		run_outcome_probe()
		_probe_override = false
		return
	print("=====================================================================
")

func _inject_curve(table: Array) -> void:
	"""Push a candidate anchor table into the monster database so the REAL spawn path uses it.

	This replaces `_cal_override`, which forced `max_hp` and `strength` onto a monster AFTER
	`generate_monster` had already applied that species' shape - so the calibration measured a
	creature the game never builds. Measured against the curve it had just written:

	    level   anchor str   what make_monster actually built
	    L1              22                       14   (0.64x)
	    L5              31                       21   (0.68x)
	    L50            495                      592   (1.20x)
	    L100          1752                     2138   (1.22x)

	Species shape is clamped to a designed 0.70-1.45 band and the mix is not centred on 1.0 at
	either end, so the override erased a systematic factor rather than noise. The consequence
	is visible in play: at n=240 the anchors measured 58-61% win at L1-L10 while the monsters
	a player actually meets measured 66-71%, and at L50 the anchors said 43% while real spawns
	said 47%. Two different games.

	Injecting the candidate curve instead means every measurement runs through
	`generate_monster` with its species roll, so the species mix is inside the loop and the
	numbers that get written are tuned for what spawns."""
	monster_db._reference_anchors = table.duplicate(true)
	monster_db._curve_is_calibrated = true
	# The per-tier shape cache is derived from the curve, so a stale one would silently apply
	# the PREVIOUS pass's shape to this pass's numbers.
	if "_tier_shape_cache" in monster_db:
		monster_db._tier_shape_cache.clear()

func _median3(a: float, b: float, c: float) -> float:
	"""Middle of three. Returns `b` unchanged whenever b lies between a and c, which is every
	point on a monotonic ramp - so this preserves curvature exactly and only acts on a local
	extreme, i.e. a sampling spike."""
	return maxf(minf(a, b), minf(maxf(a, b), c))

func _fight_stats_at(level: int, samples: int, gear: String = "average") -> Dictionary:
	# Run real same-level fights across all three archetypes and report what actually
	# happened: mean turns, mean share of the player's health bar spent, win rate.
	# This is the ground truth the calibration drives toward.
	var turns_tot := 0.0
	var eff_tot := 0.0
	var cost_tot := 0.0
	var wins := 0
	var n := 0
	for klass in ["Fighter", "Wizard", "Thief"]:
		for i in range(samples):
			var ch = make_char(level, gear, klass)
			var monster := make_monster(level, "normal", 1.0)
			var php0: int = ch.get_total_max_hp()
			ch.in_combat = false
			combat_mgr.start_combat(0, ch, monster)
			if not combat_mgr.active_combats.has(0):
				continue
			var combat = combat_mgr.active_combats[0]
			var turns := 0
			while turns < 400:
				if ch.current_hp <= 0 or int(monster.get("current_hp", 0)) <= 0 or combat.get("combat_ended", false):
					break
				turns += 1
				if combat.get("player_can_act", true):
					match ch.get_class_path():
						"trickster": _player_act_trickster(combat, ch)
						"mage": _player_act_mage(combat, ch)
						_: _player_act(combat, ch)
				if int(monster.get("current_hp", 0)) <= 0:
					break
				combat_mgr.process_monster_turn(combat)
			if int(monster.get("current_hp", 0)) <= 0 and ch.current_hp > 0:
				wins += 1
			turns_tot += float(turns)
			# EFFECTIVE turns — how long the monster would have taken to kill at the rate the
			# player was actually chewing through it, whether or not they survived to finish.
			# Observed `turns` is TRUNCATED by death, so it reads short exactly where the
			# monster is too strong, and the HP correction then reads that as "too weak" and
			# raises HP further. Filtering to wins instead is the selection-bias trap already
			# hit once this session (boss win rate fell 30-47% -> 15-33% when turns were
			# measured on wins only). This is neither: every fight contributes, extrapolated
			# to completion.
			var m_max: float = maxf(1.0, float(monster.get("max_hp", 1)))
			var m_left: float = maxf(0.0, float(monster.get("current_hp", 0)))
			var dealt: float = maxf(1.0, m_max - m_left)
			eff_tot += minf(200.0, float(turns) * m_max / dealt)
			cost_tot += float(php0 - maxi(0, ch.current_hp)) / float(maxi(1, php0))
			n += 1
			combat_mgr.end_combat(0, false, false)
	if n == 0:
		return {}
	return {"turns": turns_tot / float(n), "eff_turns": eff_tot / float(n),
		"cost": cost_tot / float(n), "win": float(wins) / float(n)}

func run_reference_calibrate():
	# #6 — SELF-CALIBRATING monster model.
	#
	# The analytic route (measure player damage-per-turn, set monster HP = dpt * N) is
	# self-referential and does not converge on its own: a player bursts and then runs
	# dry, so their damage-per-turn depends on how long the fight lasts, which depends
	# on the monster HP the measurement is being used to set. Measuring over a 12-turn
	# window produced fights 2x too long at L1 and 16x too long at L5000; matching the
	# window to the target instead made percentage-of-max-HP abilities blow up against
	# the oversized probe dummy. Both are symptoms of predicting a fixed point rather
	# than finding one.
	#
	# So: stop predicting. Set monster stats, RUN REAL FIGHTS, and correct toward the
	# design target. Two or three passes converge, and the result is robust to every
	# subtlety that broke the analytic version (ability rotations, resource drain,
	# percentage-based damage, mitigation, monster abilities) because it never models
	# any of them — it measures the outcome they jointly produce.
	#
	# Targets: TARGET_TURNS_NORMAL turns, DANGER_NORMAL of the player's health bar.
	# Sample size drives everything downstream — monster stats are corrected toward the
	# target from these fights, so noise here is baked into the curve and inherited by
	# every later measurement. `-- n=N` sets the per-cell budget.
	var passes := 6
	# Raised with the metric change. `cost` was a mean over a continuous variable and eight
	# fights sufficed; a WIN RATE is a proportion, and at n=8 its standard error is ~17
	# percentage points. Calibrating against that noise is what produced str_mult values of
	# 20-30 when rolecal was converted without touching its sample size.
	var samples: int = maxi(25, int(_audit_n))  # per class; all 3 run
	print("\n===== #6 MONSTER MODEL CALIBRATION (target %.0f turns, %.0f%% win) =====" % [TARGET_TURNS_NORMAL_SIM, WIN_NORMAL_SIM * 100.0])
	print("HP steers TURNS (a mean); STR steers WIN RATE (a proportion). Cost is reported, not targeted.")
	var table: Array = []
	# The working curve, seeded from the CURVE FILE'S OWN ANCHORS.
	#
	# Seeding it from `make_monster` was tried and is wrong in a way that compounds: that
	# returns a monster with the species SHAPE already applied, so injecting it back as the
	# curve makes `generate_monster` apply shape a second time. One round doubled the whole
	# table - L1 strength 22 -> 38, L100 1752 -> 3594 - and L100 verified at 8% win. The curve
	# and a spawned monster are different quantities and must not be mixed, which is the same
	# confusion `_cal_override` embodied.
	var work: Array = []
	var seed_file = FileAccess.open("res://shared/reference_monster_curve.json", FileAccess.READ)
	if seed_file != null:
		var seed_parsed = JSON.parse_string(seed_file.get_as_text())
		seed_file.close()
		if seed_parsed is Dictionary:
			for a in seed_parsed.get("anchors", []):
				work.append({"level": int(a.get("level", 0)), "hp": int(a.get("hp", 100)), "str": int(a.get("str", 10))})
	if work.size() != REF_ANCHOR_LEVELS.size():
		# No usable curve to start from. Refuse rather than seed from shaped monsters, which is
		# the mistake above; a bad seed is silently baked into everything downstream.
		print("REFCAL ABORTED: reference_monster_curve.json has %d anchors, expected %d." % [work.size(), REF_ANCHOR_LEVELS.size()])
		return
	for lvl in REF_ANCHOR_LEVELS:
		# Seed from the WORKING CURVE for this level, not from a spawned monster - the same
		# shape-doubling trap as above. `work` already carries the corrections made at lower
		# anchors during this run, so each level starts from the best current estimate.
		var hp := 100.0
		var st := 10.0
		for wrow in work:
			if int(wrow["level"]) == lvl:
				hp = float(wrow["hp"])
				st = float(wrow["str"])
		var last := {}
		for pass_i in range(passes):
			# Write the candidate into the WORKING table and push the whole table into the
			# monster database, rather than forcing the numbers onto an already-built monster.
			# The fight then runs through the real spawn path, species shape and all.
			for wrow in work:
				if int(wrow["level"]) == lvl:
					wrow["hp"] = int(round(hp))
					wrow["str"] = int(round(st))
			_inject_curve(work)
			var r := _fight_stats_at(lvl, samples)
			if r.is_empty():
				break
			last = r
			# Correct toward target. Damped (sqrt) so a noisy sample cannot send the
			# next pass wildly off; converges in a handful of passes either way.
			# Correction exponent, was sqrt (0.5). Damping that heavy needs many passes to close
			# a large gap: at n=8/class the noise justified it, but with the sample budget now
			# wired to `-- n=` the measurement is tight enough to move faster. Measured at n=90
			# with 0.5, four passes left the DANGER axis systematically short of target — normal
			# 33% against 40%, elite 43% against 70%, boss 51% against 85% — while turn counts
			# (the HP axis, which starts much closer) landed fine. That is under-convergence,
			# not a wrong target.
			var k: float = CAL_CORRECTION_EXP
			# OBSERVED turns, deliberately. Correcting against `eff_turns` (extrapolated to
			# completion) was tried and made things worse: for a WON fight it equals observed
			# turns, but for a lost one it extrapolates upward, so the mean is always >=
			# observed, the calibrator concluded fights ran long, and it shrank monsters —
			# L1-L100 fell from 4.5-6.5 turns to 2.5-3.0 against a 5-turn target. A player who
			# dies on turn 4 experienced a 4-turn fight against a monster that is too STRONG,
			# which is the `str`/danger axis's job, not HP's. `eff_turns` is still reported as
			# a diagnostic because the truncation it measures is real.
			var turn_err: float = TARGET_TURNS_NORMAL_SIM / maxf(0.5, float(r["turns"]))
			# 2026-09-04 - REVERTED: an attempt to make the win target override the turns
			# target here was measured twice and rejected both times. It is kept as a comment
			# because the reasoning is sound and only the remedy was wrong.
			#
			# The two axes genuinely do conflict. Raising HP to lengthen a fight always costs
			# win rate, so at a level already short on wins, obeying the turns target makes it
			# worse - measured at L100, where strength fell 8% while HP rose 22% to chase turns
			# 4.4 -> 5.1 and the win rate went 52% -> 43% as a result.
			#
			# But braking the HP rise fixes that one level and damages the rest, because the
			# conflict is not what is usually happening when win sits a little low - noise is.
			# Rows landing within 5 points of target, out of 14:
			#
			#     no brake (shipped)                        13   L100 the only miss
			#     hard block whenever win < target          10   L1, L5, L100, L1000 miss
			#     brake scaled by the deficit                8   six miss
			#
			# Both remedies traded a broad fit for one row. The real fault is upstream: this
			# model sizes HP and STRENGTH, while a monster's lethality is dominated by its
			# ABILITIES. Jabberwock wins 16% and Demon Lord 82% on near-identical stat lines
			# (1869/19470 vs 1645/16606), and the per-species spread is systemic rather than an
			# L100 quirk - L50 runs 13% to 100%, L250 runs 9% to 100%. An anchor is therefore an
			# average over a pool whose members differ ~5x in real difficulty, and how well any
			# single level fits depends on which species happen to dominate it. Fixing that
			# means bringing abilities into the shape model, not adding another brake here.
			hp *= pow(clampf(turn_err, 0.15, 6.0), k)
			# Steer the danger axis by WIN RATE. Direction: a higher measured win means the
			# monster is too weak, so strength rises; lower means too strong, so it falls. The
			# measurement is floored well above zero because a 0% sample carries no gradient —
			# without it a too-hard monster would be told to get several times harder.
			#
			# The clamp is much tighter than the cost version's 0.15-6.0. HP and STR are BOTH
			# being calibrated here and win rate depends on both, so the two axes are coupled
			# through it — the same coupling that made rolecal oscillate when it chased two
			# targets. A gentle per-pass step is what keeps that coupling stable rather than
			# resonant; if a future change makes it oscillate anyway, the fix is to fix HP by
			# construction as rolecal does, not to widen this.
			var win_meas: float = maxf(0.03, float(r.get("win", 0.0)))
			var win_err: float = win_meas / maxf(0.01, WIN_NORMAL_SIM)
			st *= pow(clampf(win_err, 0.7, 1.4), k)
		table.append({"level": lvl, "hp": int(round(hp)), "str": int(round(st))})
		if last.is_empty():
			print("L%-6d  (no data)" % lvl)
		else:
			print("L%-6d raw hp=%12d str=%10d   (pre-smoothing)" % [lvl, int(round(hp)), int(round(st))])
	# Each anchor is calibrated INDEPENDENTLY, so a noisy cell leaves a permanent dent in what
	# is supposed to be a difficulty RAMP. Measured: L100 came out at 8507 HP and L250 at 6022 —
	# monsters getting weaker as the player got stronger, the exact fault the reference model
	# was built to remove, reintroduced by sampling noise. Everything downstream reads it: the
	# ability table showed a matching bump at L250-500 (power_strike 59-66%, magic_bolt
	# 179-350%) that is the dip, not the abilities.
	# Enforce a non-decreasing ramp by carrying the running maximum forward. Deliberately does
	# not smooth or average — it only refuses to go DOWN, so a genuinely hard level stays hard.
	# SMOOTH BEFORE CLAMPING (2026-09-02). The monotonic clamp alone has a failure mode the
	# comment above did not anticipate: it turns a single noisy SPIKE into a permanent plateau.
	# Measured on the first decoupled run — L250 spiked to 35351 and L500, which had calibrated
	# itself to 16106, was clamped UP to 35351 to preserve the ramp. One bad sample inflated
	# every level above it, and the curve stepped 5.04x from L100 to L250 then 1.00x to L500.
	# That is the sawtooth a player feels as a wall followed by a coast.
	#
	# MEDIAN, not a mean (2026-09-03). The previous kernel was [0.25, 0.5, 0.25] in log space,
	# justified by "the curve is near-linear in log-log". At the low end it is not: measured
	# log-str ran 3.47 (L5) -> 3.93 (L10) -> 5.31 (L25), which is steep convexity, and a mean
	# kernel on a convex curve biases every interior point UPWARD. It was not averaging out
	# noise there, it was distorting shape.
	#
	# The damage was precisely the L1-L50 band that would not calibrate. The correction loop
	# converged, and then smoothing overwrote its answer:
	#
	#     level   calibrated str   written str          resulting win (target 60%)
	#     L5                  32            40  (+25%)                       45%
	#     L10                 51            70  (+37%)                       42%
	#     L50                361           468  (+30%)                       47%
	#     L25                202           168  (-17%)                       56%
	#
	# Eighteen correction passes across three runs could not fix those levels because nothing
	# they produced survived to be written. The single level smoothing made WEAKER is the one
	# that landed nearest target, which is the tell.
	#
	# A median filter keeps the reason smoothing exists and drops the side effect. On any
	# monotonic run median(a, b, c) == b, so genuine curvature passes through EXACTLY
	# unchanged; a lone spike is not merely halved but removed outright, since the median of
	# {neighbour, spike, neighbour} is a neighbour. The case that motivated smoothing - L250
	# spiking to 35351 between 8507 and 16106 - resolves to 16106 rather than to a blend.
	#
	# One pass, not two: a median filter is idempotent on monotonic data, so a second pass can
	# only act on whatever the first one created.
	var log_hp: Array = []
	var log_st: Array = []
	for row in table:
		log_hp.append(log(maxf(1.0, float(row["hp"]))))
		log_st.append(log(maxf(1.0, float(row["str"]))))
	for i in range(1, table.size() - 1):
		table[i]["hp"] = int(round(exp(_median3(float(log_hp[i - 1]), float(log_hp[i]), float(log_hp[i + 1])))))
		table[i]["str"] = int(round(exp(_median3(float(log_st[i - 1]), float(log_st[i]), float(log_st[i + 1])))))

	var fixed_hp := 0
	var fixed_str := 0
	var repaired := 0
	for row in table:
		var h := int(row["hp"])
		var st2 := int(row["str"])
		if h < fixed_hp or st2 < fixed_str:
			repaired += 1
		row["hp"] = maxi(h, fixed_hp)
		row["str"] = maxi(st2, fixed_str)
		fixed_hp = int(row["hp"])
		fixed_str = int(row["str"])
	if repaired > 0:
		print("
Monotonicity repair: %d anchor(s) would have made monsters WEAKER as level rose;" % repaired)
		print("clamped to the running maximum so the curve is a ramp, never a dip.")

	# Verify the FINAL table. Smoothing and the monotonic clamp both run AFTER the per-anchor
	# loop, so anything measured in there describes numbers that no longer exist. This is the
	# only table a reader should trust: it is measured against exactly what gets written.
	print("
--- VERIFIED against the curve actually being written ---")
	print("%-8s %12s %10s %8s %8s %6s" % ["level", "hp", "str", "turns", "HPcost", "win"])
	# Verify through the REAL path too: inject the finished table once, then measure each level
	# with no override at all. This is what a player fights.
	_inject_curve(table)
	for row in table:
		var v := _fight_stats_at(int(row["level"]), samples)
		if v.is_empty():
			continue
		print("%-8d %12d %10d %7.1f %7.0f%% %5.0f%%" % [
			int(row["level"]), int(row["hp"]), int(row["str"]),
			float(v["turns"]), 100.0 * float(v["cost"]), 100.0 * float(v["win"])])

	# START FROM THE EXISTING FILE and overwrite only what refcal owns.
	#
	# This used to name the keys to preserve, and that failed twice for the same reason. First
	# refcal emitted only `anchors`, so the documented order (refcal then rolecal) silently
	# DESTROYED a prior role calibration. That was fixed by carrying `role_multipliers` forward
	# by name - and `species_power`, written by `speciescal`, was then wiped by every refcal run
	# from the day it was added. The mechanism that reads it is live in monster_database and was
	# simply never receiving data, so per-species power correction has been dead the whole time.
	#
	# An allow-list of keys to keep has to be updated by whoever adds the next key, and will not
	# be. Preserving the whole document and overwriting only refcal's own three fields means any
	# future block survives by construction.
	var out := {}
	var _prev = FileAccess.open("res://shared/reference_monster_curve.json", FileAccess.READ)
	if _prev != null:
		var _parsed = JSON.parse_string(_prev.get_as_text())
		_prev.close()
		if _parsed is Dictionary:
			out = _parsed
	var _kept: Array = []
	for _k in out.keys():
		if _k not in ["generated", "target_turns", "anchors"]:
			_kept.append(String(_k))
	out["generated"] = "sim run_reference_calibrate"
	out["target_turns"] = TARGET_TURNS_NORMAL_SIM
	out["anchors"] = table
	if not _kept.is_empty():
		_kept.sort()
		print("(carried forward: %s — re-run their audits if the base curve moved much)" % ", ".join(_kept))
	var f = FileAccess.open("res://shared/reference_monster_curve.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out, "\t"))
		f.close()
		print("\nWrote shared/reference_monster_curve.json (%d anchors)." % table.size())
		# CRITICAL: monster_database caches the curve on first load and _load_reference_curve
		# early-returns once populated, so writing the file is NOT enough — any audit running
		# after refcal in the SAME process keeps using the pre-calibration curve. That is exactly
		# what happened: a `-- refcal roles ability_hp` run showed the calibration hitting ~5
		# turns while the roles audit that followed measured ~3, and the disagreement was read as
		# "high-level HP under-converges" when the two were simply measuring different curves.
		monster_db._reference_anchors = []
		monster_db._curve_is_calibrated = false
	print("Re-run `-- refval` to confirm the model lands on target with these anchors.")
	print("=====================================================================\n")

func run_role_audit():
	# #6 — do elite and boss fights actually feel like their ROLE_TARGETS say they should?
	# Reports measured turns / share of the player's health bar spent / win rate against the
	# target for each role, so the derived multipliers can be checked rather than assumed.
	var samples: int = maxi(10, int(_audit_n / 3.0))  # per class
	print("
===== #6 ROLE AUDIT (measured vs ROLE_TARGETS) =====")
	print("Each role states a target fight length and cost; multipliers are derived from them.")
	# `turns` is TRUNCATED BY DEATH: a lost fight ends the moment the player dies, so at a 23%
	# elite win rate the mean is dominated by short deaths and reads far below target even when
	# a fight you WIN lands on it. Reading that column as "elite fights are too short" is an
	# instrument artifact, and acting on it is what made hp_mult run away to 305x once already
	# (see a9e3545 — two coupled targets oscillate).
	#
	# `eff` is the unbiased companion: turns extrapolated to completion at the rate the player
	# was actually chewing through the monster, so every fight contributes and none is selected
	# for. It is REPORT-ONLY and must stay that way — feeding a length signal back into the
	# calibrator is the failure mode above, whereas printing one is just being honest.
	print("%-10s %-8s %10s %8s %10s %10s %10s %8s" % [
		"Role", "Level", "turns(obs)", "eff", "target", "HPcost", "target", "win%"])
	for role in ["normal", "empowered", "elite", "boss"]:
		var tgt: Dictionary = monster_db.ROLE_TARGETS.get(role, {})
		for lvl in [1, 10, 50, 250, 1000, 5000]:
			var turns_tot := 0.0
			var eff_tot := 0.0
			var cost_tot := 0.0
			var wins := 0
			var n := 0
			for klass in ["Fighter", "Wizard", "Thief"]:
				for i in range(samples):
					var ch = make_char(lvl, "average", klass)
					var monster := make_monster(lvl, role, 1.0)
					var php0: int = ch.get_total_max_hp()
					ch.in_combat = false
					combat_mgr.start_combat(0, ch, monster)
					if not combat_mgr.active_combats.has(0):
						continue
					var combat = combat_mgr.active_combats[0]
					var turns := 0
					while turns < 400:
						if ch.current_hp <= 0 or int(monster.get("current_hp", 0)) <= 0 or combat.get("combat_ended", false):
							break
						turns += 1
						if combat.get("player_can_act", true):
							match ch.get_class_path():
								"trickster": _player_act_trickster(combat, ch)
								"mage": _player_act_mage(combat, ch)
								_: _player_act(combat, ch)
						if int(monster.get("current_hp", 0)) <= 0:
							break
						combat_mgr.process_monster_turn(combat)
					if int(monster.get("current_hp", 0)) <= 0 and ch.current_hp > 0:
						wins += 1
					turns_tot += float(turns)
					# Extrapolate to completion so death does not truncate the length signal.
					var m_max: float = maxf(1.0, float(monster.get("max_hp", 1)))
					var m_left: float = maxf(0.0, float(monster.get("current_hp", 0)))
					var dealt: float = maxf(1.0, m_max - m_left)
					eff_tot += minf(200.0, float(turns) * m_max / dealt)
					cost_tot += 100.0 * float(php0 - maxi(0, ch.current_hp)) / float(maxi(1, php0))
					n += 1
					combat_mgr.end_combat(0, false, false)
			if n == 0:
				continue
			print("%-10s %-8d %10.1f %8.1f %10.1f %9.0f%% %9.0f%% %7d%%" % [
				role, lvl, turns_tot / n, eff_tot / n, float(tgt.get("turns", 0.0)),
				cost_tot / n, 100.0 * float(tgt.get("danger", 0.0)), int(100.0 * wins / n)])
	print("=====================================================================
")

func run_fallback_audit():
	# Owner's question (2026-09-03), and it is a question about the INSTRUMENT:
	#   "If they fail they have no fallback other than fleeing. Do other classes suffer from the
	#    same situation, are we accounting for this when talking about win rates or health
	#    costs?"
	#
	# The answer is no, and this audit is the evidence. `roles` and `classes` FIGHT TO THE
	# DEATH — nobody ever disengages — so every non-win is recorded identically whether the
	# player would really have died or would have walked away with 40% of their bar. And a
	# death registers as 100% HP cost, which means the cost column saturates for whichever
	# class dies most, independently of how dangerous the fight actually was.
	#
	# Durability makes that bias class-specific: a Trickster carries roughly half a Fighter's
	# health bar, so the same absolute hit is twice the PERCENTAGE, and it reaches the death
	# floor sooner. Comparing raw cost% across archetypes is therefore comparing two different
	# things, which is what this prints.
	var samples: int = FIGHTS_PER_CELL
	print("\n===== FALLBACK AUDIT: does a win rate mean the same thing for every class? =====")

	print("\n-- Durability, average gear (the divisor behind every cost%% figure) --")
	print("%-10s %-11s %9s %9s %11s" % ["class", "archetype", "L30 maxHP", "L80 maxHP", "vs Fighter"])
	for klass in ["Fighter", "Paladin", "Wizard", "Sorcerer", "Thief", "Ranger", "Ninja"]:
		var a = make_char(30, "average", klass)
		var b = make_char(80, "average", klass)
		var fa = make_char(30, "average", "Fighter")
		print("%-10s %-11s %9d %9d %10.0f%%" % [
			klass, String(a.get_class_path()), a.get_total_max_hp(), b.get_total_max_hp(),
			100.0 * float(a.get_total_max_hp()) / maxf(1.0, float(fa.get_total_max_hp()))])

	for role in ["elite", "boss"]:
		for lvl in [30, 80]:
			print("\n-- L%d %s: fight-to-the-death (what `roles`/`classes` measure) vs. a player who RUNS --" % [lvl, role])
			print("%-10s %26s %30s" % ["", "FIGHT TO THE DEATH", "MAY FLEE BELOW 45%"])
			print("%-10s %7s %7s %7s %6s   %7s %8s %7s %7s" % [
				"class", "win%", "died%", "cost%", "OSatt", "win%", "escaped%", "died%", "cost%"])
			for klass in ["Fighter", "Wizard", "Ranger"]:
				var a: Dictionary = _fallback_run(lvl, role, klass, samples, false)
				var b: Dictionary = _fallback_run(lvl, role, klass, samples, true)
				print("%-10s %6d%% %6d%% %6.0f%% %6.1f   %6d%% %7d%% %6d%% %6.0f%%" % [
					klass, int(a.win), int(a.died), a.cost, a.os,
					int(b.win), int(b.escaped), int(b.died), b.cost])
	print("\nRead it this way: where `escaped%%` is large, the fight-to-the-death `died%%` and")
	print("`cost%%` were overstating the real consequence, and they overstate it MOST for the")
	print("class that dies most. A cost%% column cannot be compared across archetypes with")
	print("different health bars — the survivors' cost is the honest figure.")
	print("=====================================================================")

func _fallback_run(lvl: int, role: String, klass: String, samples: int, may_flee: bool) -> Dictionary:
	var wins := 0
	var died := 0
	var escaped := 0
	var os_tot := 0.0
	var cost_tot := 0.0
	var n := 0
	for i in range(samples):
		var ch = make_char(lvl, "average", klass)
		var monster := make_monster(lvl, role, 1.0)
		var php0: int = ch.get_total_max_hp()
		ch.in_combat = false
		combat_mgr.start_combat(0, ch, monster)
		if not combat_mgr.active_combats.has(0):
			continue
		var combat = combat_mgr.active_combats[0]
		var turns := 0
		var fled := false
		while turns < 400:
			if ch.current_hp <= 0 or int(monster.get("current_hp", 0)) <= 0 or combat.get("combat_ended", false):
				break
			turns += 1
			if may_flee and float(ch.current_hp) / float(maxi(1, php0)) < 0.45:
				var fr = combat_mgr.process_flee(combat)
				# process_flee returns success for any PROCESSED attempt; only `fled` escaped.
				if fr.get("fled", false):
					fled = true
					break
			if combat.get("player_can_act", true):
				match ch.get_class_path():
					"trickster": _player_act_trickster(combat, ch)
					"mage": _player_act_mage(combat, ch)
					_: _player_act(combat, ch)
			if int(monster.get("current_hp", 0)) <= 0:
				break
			combat_mgr.process_monster_turn(combat)
		if int(monster.get("current_hp", 0)) <= 0 and ch.current_hp > 0:
			wins += 1
		elif fled:
			escaped += 1
		else:
			died += 1
		os_tot += float(int(combat.get("outsmart_attempts", 0)))
		cost_tot += 100.0 * float(php0 - maxi(0, ch.current_hp)) / float(maxi(1, php0))
		n += 1
		combat_mgr.end_combat(0, false, false)
	if n == 0:
		return {"win": 0.0, "died": 0.0, "escaped": 0.0, "cost": 0.0, "os": 0.0}
	return {"win": 100.0 * wins / n, "died": 100.0 * died / n, "escaped": 100.0 * escaped / n,
			"cost": cost_tot / n, "os": os_tot / n}

func _xp_to_next(level: int) -> float:
	# The LIVE formula. character.gd also contains check_level_up() using
	# pow(level+1, 2.5) * 100 with a small override table, but nothing calls it — the
	# path that actually runs is level_up() setting experience_to_next_level.
	# Flagged rather than used: if anything ever calls the dead one, levelling changes
	# by orders of magnitude at high level.
	return pow(float(level + 1), 2.2) * 50.0

func _fight_for_xp(level: int, klass: String, role: String, monster_level: int) -> Dictionary:
	# One fight. Returns the XP the kill is WORTH, whether the player won, and the turns.
	#
	# IMPORTANT: XP is NOT read as a delta on the character. Measured 2026-09-02 — the solo
	# XP grant does not happen inside combat_manager at all (neither the killing blow nor
	# end_combat moves character.experience); combat_manager returns the reward and
	# server.gd applies it. A simulator that drives the shared combat code therefore cannot
	# observe it, and an earlier version of this audit that tried reported nonsense
	# (~1 fight per level at every level). So the XP is computed from the monster's own
	# experience_reward plus the level-gap multiplier from combat_manager, which is the
	# same arithmetic the server performs.
	var ch = make_char(level, "average", klass)
	var monster := make_monster(monster_level, role, 1.0)
	var reward: float = float(monster.get("experience_reward", 0))
	ch.in_combat = false
	combat_mgr.start_combat(0, ch, monster)
	if not combat_mgr.active_combats.has(0):
		return {"xp": 0.0, "win": false, "turns": 0}
	var combat = combat_mgr.active_combats[0]
	var turns := 0
	while turns < 400:
		if ch.current_hp <= 0 or int(monster.get("current_hp", 0)) <= 0 or combat.get("combat_ended", false):
			break
		turns += 1
		if combat.get("player_can_act", true):
			match ch.get_class_path():
				"trickster": _player_act_trickster(combat, ch)
				"mage": _player_act_mage(combat, ch)
				_: _player_act(combat, ch)
		if int(monster.get("current_hp", 0)) <= 0:
			break
		combat_mgr.process_monster_turn(combat)
	var won: bool = int(monster.get("current_hp", 0)) <= 0 and ch.current_hp > 0
	combat_mgr.end_combat(0, won, false)
	# Mirror combat_manager's level-gap XP scaling (sqrt bonus above level, graduated
	# penalty below with a 40% floor), then its flat +10% boost.
	var diff: int = int(monster_level) - level
	var mult := 1.0
	if diff > 0:
		mult = 1.0 + sqrt(float(diff) / (10.0 + float(level) * 0.05)) * 0.7
	elif diff < 0:
		var under: float = float(-diff)
		var threshold: float = 5.0 + float(level) * 0.03
		if under > threshold:
			mult = maxf(0.4, 1.0 - minf(0.6, (under - threshold) * 0.03))
	var xp: float = reward * mult * 1.10 if won else 0.0
	return {"xp": xp, "win": won, "turns": turns}

func run_xp_audit():
	# #6 (user question 2026-09-02) — how long does levelling actually take, and what is
	# the best way to do it? Reports fights-to-level per role at each level, measured from
	# the real reward path rather than from the formulas.
	var samples := 8
	print("\\n===== #6 XP AUDIT: how many fights to gain a level? =====")
	print("XP is read as the delta on a real character after a real fight, so every live")
	print("multiplier is included. Losses count as fights too — 'fights' is the expected")
	print("number INCLUDING the ones you lose, which is what a player actually experiences.")
	print("%-8s %12s %10s %10s %10s %10s" % ["Level", "XP needed", "normal", "empowered", "elite", "boss"])
	for lvl in [1, 5, 10, 25, 50, 100, 250, 1000, 5000]:
		var need := _xp_to_next(lvl)
		var row := "%-8d %12.0f" % [lvl, need]
		for role in ["normal", "empowered", "elite", "boss"]:
			var xp_tot := 0.0
			var n := 0
			for klass in ["Fighter", "Wizard", "Thief"]:
				for i in range(samples):
					var r := _fight_for_xp(lvl, klass, role, lvl)
					xp_tot += float(r.xp)
					n += 1
			var per_fight: float = xp_tot / maxf(1.0, float(n))
			if per_fight <= 0.0:
				row += "%10s" % "--"
			else:
				row += "%10.1f" % (need / per_fight)
		print(row)
	print("")
	print("--- Is fighting ABOVE or BELOW your level better? (L50 and L1000) ---")
	print("XP/fight counts losses as zero, so it already prices in the risk of dying.")
	print("XP/turn is the throughput measure — how fast you level per unit of time spent.")
	print("%-8s %-10s %8s %10s %10s %10s %10s" % ["Level", "monster", "win%", "XP/fight", "XP/turn", "turns", "fights/lv"])
	for lvl in [50, 1000]:
		var need := _xp_to_next(lvl)
		for mult in [0.25, 0.5, 1.0, 1.5, 2.0, 3.0]:
			var mlvl: int = maxi(1, int(round(float(lvl) * mult)))
			var xp_tot := 0.0
			var turn_tot := 0.0
			var wins := 0
			var n := 0
			for klass in ["Fighter", "Wizard", "Thief"]:
				for i in range(samples):
					var r := _fight_for_xp(lvl, klass, "normal", mlvl)
					xp_tot += float(r.xp)
					turn_tot += float(r.turns)
					if r.win:
						wins += 1
					n += 1
			var per_fight: float = xp_tot / maxf(1.0, float(n))
			print("%-8d %-10s %7d%% %10.0f %10.1f %10.1f %10s" % [
				lvl, "x%.2f" % mult, int(100.0 * wins / maxi(1, n)), per_fight,
				xp_tot / maxf(1.0, turn_tot), turn_tot / maxf(1.0, float(n)),
				("%.0f" % (need / per_fight)) if per_fight > 0.0 else "--"])
	print("=====================================================================\\n")

func run_risk_reward_audit():
	# #6 (user direction 2026-09-02) — "taking big risks should be rewarding, but killing
	# something 3x your level shouldn't be easy, and if you pull it off the reward should be
	# far more than 1/7th of a level."
	#
	# The earlier XP audit measured throughput only (XP per fight, losses counted as zero)
	# and concluded that over-levelling was "optimal". That framing was WRONG because it
	# priced a loss at zero rather than at the cost of the character. This models what a real
	# player actually experiences: fight, and once it is clearly going badly (below the flee
	# threshold) try to run — using the real process_flee, which is heavily penalised by
	# level gap and floored at 10%.
	#
	# Outcomes are therefore three-way: KILL, ESCAPE, or DEATH (permadeath = the run ends).
	# Reward is expressed in LEVELS, because "how much of a level did that heroic kill pay"
	# is the question actually being asked.
	var samples: int = maxi(12, int(_audit_n / 3.0))  # per class
	# Bail threshold. Raised from 0.35 after measuring: against something far above the
	# player, they are killed from full HP without ever passing through a low-HP band, so a
	# late threshold never fires and reads as "0% escape" when the player simply never got
	# to try. 0.70 models a player who reads the first exchange and runs.
	var flee_at := 0.70
	print("\\n===== #6 RISK vs REWARD: what does punching above your level really cost? =====")
	print("A player who fights, then tries to FLEE once below %.0f%% HP (real process_flee)." % (flee_at * 100.0))
	print("death%% is permadeath — the character is gone. reward is the kill's XP as a")
	print("fraction of a level at that level. EV/level nets the reward against the death risk.")
	print("%-8s %-9s %7s %8s %8s %10s %12s" % ["Level", "monster", "kill%", "escape%", "death%", "reward(lv)", "levels/death"])
	for lvl in [50, 250, 1000]:
		var need := _xp_to_next(lvl)
		for mult in [1.0, 1.5, 2.0, 3.0, 5.0]:
			var mlvl: int = maxi(1, int(round(float(lvl) * mult)))
			var kills := 0
			var escapes := 0
			var deaths := 0
			var xp_tot := 0.0
			var n := 0
			for klass in ["Fighter", "Wizard", "Thief"]:
				for i in range(samples):
					var ch = make_char(lvl, "average", klass)
					var monster := make_monster(mlvl, "normal", 1.0)
					var reward: float = float(monster.get("experience_reward", 0))
					var max_hp: int = ch.get_total_max_hp()
					ch.in_combat = false
					combat_mgr.start_combat(0, ch, monster)
					if not combat_mgr.active_combats.has(0):
						continue
					var combat = combat_mgr.active_combats[0]
					var turns := 0
					var fled := false
					while turns < 400:
						if ch.current_hp <= 0 or int(monster.get("current_hp", 0)) <= 0 or combat.get("combat_ended", false):
							break
						turns += 1
						if combat.get("player_can_act", true):
							if float(ch.current_hp) / float(max_hp) < flee_at:
								var fr = combat_mgr.process_flee(combat)
								# Only "fled" means escaped. process_flee returns success:true
								# for a FAILED attempt too (the action processed), so falling
								# back to `success` counts every attempt as an escape.
								if bool(fr.get("fled", false)):
									fled = true
									break
							else:
								match ch.get_class_path():
									"trickster": _player_act_trickster(combat, ch)
									"mage": _player_act_mage(combat, ch)
									_: _player_act(combat, ch)
						if int(monster.get("current_hp", 0)) <= 0:
							break
						combat_mgr.process_monster_turn(combat)
					var killed: bool = int(monster.get("current_hp", 0)) <= 0 and ch.current_hp > 0
					if killed:
						kills += 1
						var diff: int = mlvl - lvl
						var m2 := 1.0
						if diff > 0:
							m2 = 1.0 + sqrt(float(diff) / (10.0 + float(lvl) * 0.05)) * 0.7
						xp_tot += reward * m2 * 1.10
					elif fled:
						escapes += 1
					else:
						deaths += 1
					n += 1
					combat_mgr.end_combat(0, killed, false)
			if n == 0:
				continue
			var reward_levels: float = (xp_tot / maxf(1.0, float(kills))) / need if kills > 0 else 0.0
			var deaths_f: float = float(deaths) / float(n)
			# How many levels of progress you buy per character you lose, at this gap.
			var per_death: float = (reward_levels * float(kills) / float(n)) / maxf(0.0001, deaths_f)
			print("%-8d %-9s %6d%% %7d%% %7d%% %10.2f %12.2f" % [
				lvl, "x%.1f" % mult, int(100.0 * kills / n), int(100.0 * escapes / n),
				int(100.0 * deaths / n), reward_levels, per_death])
	print("")
	print("Read 'levels/death': how many levels of progress a player buys for each character")
	print("they lose trying. Below ~1.0 the gamble destroys more progress than it creates, so")
	print("no rational player takes it and the over-level reward is dead content.")
	print("=====================================================================\\n")

func run_companion_unlock_audit():
	_use_companions_for_this_audit()
	# #6b (user direction 2026-09-02) — WHY does a level-1 companion measure the same as no
	# companion, when a companion is targetable (a damage sponge) and attacks every round?
	#
	# Win rate alone cannot answer that, so this measures what the companion actually DOES:
	#   survived   — rounds it stayed up before being knocked out
	#   soaked     — hits the monster spent on the companion instead of the player (aggro)
	#   dealt      — damage it contributed
	# across the ABILITY UNLOCK BOUNDARIES (passive always, active at companion level 5,
	# threshold at 15) plus a level-matched companion, so unlock pacing and raw survivability
	# can be told apart.
	var samples: int = maxi(24, _audit_n)
	print("\\n===== #6b COMPANION: what does it actually do? =====")
	print("Same-level ELITE, Fighter, AVERAGE gear, %d fights/cell." % samples)
	print("compHP is the companion's max combat HP: 30 + level*5 + sub_tier*10 + hp_bonus.")
	print("survived = rounds up before KO (capped at fight length). soaked = hits taken FOR you.")
	print("%-7s %-9s %8s %9s %8s %8s %7s" % ["PlyrL", "compL", "compHP", "survived", "soaked", "dealt%", "win%"])
	for lvl in [5, 50, 250, 1000, 10000]:
		# "carry" = a registered companion far above the player's level, the case the design
		# depends on: an established companion pulling a fresh character forward.
		for comp_mode in ["none", "1", "match", "carry"]:
			var wins := 0
			var surv := 0.0
			var soak := 0.0
			var dealt := 0.0
			var total_dmg := 0.0
			var comp_hp := 0
			var n := 0
			for i in range(samples):
				var ch = make_char(lvl, "average", "Fighter")
				if comp_mode == "none":
					ch.active_companion = {}
				else:
					var cl: int = lvl
					if comp_mode == "carry":
						cl = mini(10000, lvl * 10)
					elif comp_mode != "match":
						cl = int(comp_mode)
					ch.active_companion["level"] = cl
					ch.active_companion["combat_hp"] = ch.get_companion_max_hp()
				# Accumulate: reporting the last sample's value made the column jump around
				# (player HP and companion sub-tier are both rolled per sample).
				comp_hp += ch.get_companion_max_hp() if comp_mode != "none" else 0
				var monster := make_monster(lvl, "elite", 1.0)
				var mhp0: int = int(monster.get("max_hp", 1))
				ch.in_combat = false
				combat_mgr.start_combat(0, ch, monster)
				if not combat_mgr.active_combats.has(0):
					continue
				var combat = combat_mgr.active_combats[0]
				var turns := 0
				var rounds_up := 0
				var hits_on_comp := 0
				var php_prev: int = ch.current_hp
				while turns < 400:
					if ch.current_hp <= 0 or int(monster.get("current_hp", 0)) <= 0 or combat.get("combat_ended", false):
						break
					turns += 1
					if combat.get("player_can_act", true):
						_player_act(combat, ch)
					if int(monster.get("current_hp", 0)) <= 0:
						break
					php_prev = ch.current_hp
					var comp_hp_before: int = int(ch.active_companion.get("combat_hp", 0)) if comp_mode != "none" else 0
					combat_mgr.process_monster_turn(combat)
					if comp_mode != "none":
						var comp_now: int = int(ch.active_companion.get("combat_hp", 0))
						if comp_now > 0:
							rounds_up += 1
						# A monster turn that cost the companion HP but not the player is a hit
						# the companion took FOR the player — the sponge working.
						if comp_now < comp_hp_before and ch.current_hp >= php_prev:
							hits_on_comp += 1
				if int(monster.get("current_hp", 0)) <= 0 and ch.current_hp > 0:
					wins += 1
				surv += float(rounds_up)
				soak += float(hits_on_comp)
				total_dmg += float(mhp0 - maxi(0, int(monster.get("current_hp", 0))))
				n += 1
				combat_mgr.end_combat(0, false, false)
			if n == 0:
				continue
			print("%-7d %-9s %8d %9.1f %8.1f %8s %6d%%" % [
				lvl, comp_mode, int(float(comp_hp) / float(n)), surv / n, soak / n, "-", int(100.0 * wins / n)])
	print("")
	print("If `survived` collapses to ~1 round at high level, the companion is not a sponge or")
	print("an attacker — it is a one-hit casualty, and no amount of ability unlocking fixes it.")
	print("=====================================================================\\n")

func _role_fight_stats(level: int, role: String, samples: int) -> Dictionary:
	# Real fights against a monster of `role` at `level`, reporting mean turns and mean share
	# of the player's health bar spent. Same shape as _fight_stats_at but for a non-normal role.
	var turns_tot := 0.0
	var win_turns_tot := 0.0
	var cost_tot := 0.0
	var wins := 0
	var win_n := 0
	var n := 0
	for klass in ["Fighter", "Wizard", "Thief"]:
		for i in range(samples):
			var ch = make_char(level, "average", klass)
			var monster := make_monster(level, role, 1.0)
			var php0: int = ch.get_total_max_hp()
			ch.in_combat = false
			combat_mgr.start_combat(0, ch, monster)
			if not combat_mgr.active_combats.has(0):
				continue
			var combat = combat_mgr.active_combats[0]
			var turns := 0
			while turns < 400:
				if ch.current_hp <= 0 or int(monster.get("current_hp", 0)) <= 0 or combat.get("combat_ended", false):
					break
				turns += 1
				if combat.get("player_can_act", true):
					match ch.get_class_path():
						"trickster": _player_act_trickster(combat, ch)
						"mage": _player_act_mage(combat, ch)
						_: _player_act(combat, ch)
				if int(monster.get("current_hp", 0)) <= 0:
					break
				combat_mgr.process_monster_turn(combat)
			if int(monster.get("current_hp", 0)) <= 0 and ch.current_hp > 0:
				wins += 1
				# NOTE: measuring turns on WINS ONLY was tried here and made things WORSE —
				# boss win rate fell from 30-47% to 15-33%. Conditioning on wins SELECTS the
				# favourable fights, which are the SHORT ones, so win-only turns read short at
				# low win rates; the calibrator then raised HP, which lowered the win rate,
				# which selected even more lopsided wins. A runaway, not a correction.
				win_turns_tot += float(turns)
				win_n += 1
			turns_tot += float(turns)
			cost_tot += float(php0 - maxi(0, ch.current_hp)) / float(maxi(1, php0))
			n += 1
			combat_mgr.end_combat(0, false, false)
	if n == 0:
		return {}
	# turns over ALL fights (see the note above on why win-only is biased).
	return {"turns": turns_tot / float(n), "cost": cost_tot / float(n),
		"win": float(wins) / float(n),
		"win_turns": (win_turns_tot / float(win_n)) if win_n > 0 else 0.0}

func run_role_calibrate():
	# #6 (2026-09-02) — calibrate the ROLE multipliers against real fights, PER ANCHOR LEVEL.
	#
	# Two lessons are baked in here. First, deriving the multipliers from algebra does not work:
	# it assumes an elite fight really lasts `turns_elite`, it does not, and the damage never
	# accumulates to the intended cost. Second, ONE calibrated pair for the whole game does not
	# work either — measured that way, boss win rate ran 23-24% at L10-L50 against 47% at
	# L1000, so the same nominal encounter was twice as lethal in the mid game as in the late
	# game. A single multiplier cannot correct a level-dependent gap.
	#
	# So each anchor level is calibrated independently, exactly as the baseline curve already
	# is, and monster_database interpolates between them.
	var passes := 6
	# 2026-09-03 — SAMPLE SIZE HAD TO RISE WITH THE METRIC CHANGE, and this is the part that is
	# easy to miss. `danger` was a mean over a continuous variable, so six fights gave a usable
	# estimate. A WIN RATE is a proportion: at n=6 its standard error is about 20 percentage
	# points, which is not a signal at all — and the loop was then applying corrections of up to
	# 4x off that noise, compounded across eight passes. That is why the first win-rate run
	# produced str_mult values of 20-30 at the top levels while the low levels converged fine.
	#
	# So: more samples (SE ~9pp at n=30) AND a much tighter per-pass clamp, so no single noisy
	# reading can whipsaw a multiplier. 1.35^6 still spans ~6x overall, which is ample range.
	var samples: int = maxi(30, int(_audit_n))
	var levels := [1, 10, 50, 250, 1000, 5000, 10000]
	print("
===== #6 ROLE CALIBRATION (measured, per anchor level) =====")
	print("Each level is corrected toward its role's own targets. Final pass shown per level.")
	print("%-11s %7s %9s %9s %9s %9s %7s %8s" % [
		"Role", "Level", "hp_mult", "str_mult", "turns", "HPcost", "win%", "target"])
	var out_roles := {}
	for role in ["empowered", "elite", "boss"]:
		var tgt: Dictionary = monster_db.ROLE_TARGETS.get(role, {})
		var t_turns: float = float(tgt.get("turns", 9.0))
		var t_danger: float = float(tgt.get("danger", 0.65))
		var t_win: float = float(tgt.get("win", 0.40))
		var anchors: Array = []
		for lvl in levels:
			var seed_m: Dictionary = monster_db.role_multipliers(role)
			var hp_m: float = float(seed_m.hp_mult)
			var st_m: float = float(seed_m.str_mult)
			var last := {}
			# SINGLE-AXIS calibration. Feeding BOTH turns and cost back made the two
			# corrections fight through the win rate: raising HP to lengthen a fight raises
			# the cost, which kills the player sooner, which shortens the measured fight.
			# Two knobs chasing two coupled targets oscillated instead of converging.
			# Only the COST target — the one the owner actually signed off — is corrected.
			# hp_mult is fixed at the role's design length ratio with no feedback, so the
			# fight is proportionally longer by construction and cannot chase its own tail.
			hp_m = t_turns / maxf(0.1, float(monster_db.ROLE_TARGETS.get("normal", {}).get("turns", 5.0)))
			for pass_i in range(passes):
				# Override with a single-anchor table so this level uses exactly these values.
				monster_db.set_calibrated_role_multipliers({
					role: [{"level": lvl, "hp_mult": hp_m, "str_mult": st_m}]})
				var r := _role_fight_stats(lvl, role, samples)
				monster_db.set_calibrated_role_multipliers({})
				if r.is_empty():
					break
				last = r
				# 2026-09-03 — steer by WIN RATE, not cost. Cost saturates on death (a corpse has
				# spent 100% of its bar), so at a low win rate the signal was pinned near the
				# target's ceiling and the correction had nothing left to push against — which
				# is why this loop could not converge at L1-L50 and left bosses at 7-12%.
				#
				# Direction: a HIGHER measured win means the monster is too weak, so str_mult
				# rises; a lower one means it is too strong, so str_mult falls. The measured
				# value is floored well above zero because a 0% sample carries no gradient —
				# without that floor a too-hard monster would be told to get 4x harder.
				var w_meas: float = maxf(0.02, float(r["win"]))
				st_m *= pow(clampf(w_meas / maxf(0.01, t_win), 0.75, 1.35), CAL_CORRECTION_EXP)
			# Same lag refcal had: the loop measures THEN corrects, so `last` describes the
			# multiplier one step before the one being written. Measured consequence — empowered
			# was written past its target and came out at 59-74% cost against 55%, above ELITE
			# in the middle band, inverting the tier order. Verify against the final value.
			monster_db.set_calibrated_role_multipliers({
				role: [{"level": lvl, "hp_mult": hp_m, "str_mult": st_m}]})
			var verify := _role_fight_stats(lvl, role, samples)
			monster_db.set_calibrated_role_multipliers({})
			if not verify.is_empty():
				last = verify
			anchors.append({"level": lvl, "hp_mult": hp_m, "str_mult": st_m})
			if last.is_empty():
				print("%-11s %7d  (no data)" % [role, lvl])
			else:
				var _w: float = float(last.get("win", 0.0)) * 100.0
				var _tw: float = t_win * 100.0
				print("%-11s %7d %9.2f %9.2f %9.1f %8.0f%% %6.0f%% %7.0f%% %s" % [
					role, lvl, hp_m, st_m, float(last["turns"]),
					float(last["cost"]) * 100.0, _w, _tw,
					"ok" if absf(_w - _tw) <= 8.0 else "OFF"])
		out_roles[role] = anchors
	# Merge into the existing curve file — the baseline anchors from refcal must survive.
	var existing := {}
	var rf = FileAccess.open("res://shared/reference_monster_curve.json", FileAccess.READ)
	if rf:
		var parsed = JSON.parse_string(rf.get_as_text())
		rf.close()
		if parsed is Dictionary:
			existing = parsed
	existing["role_multipliers"] = out_roles
	var wf = FileAccess.open("res://shared/reference_monster_curve.json", FileAccess.WRITE)
	if wf:
		wf.store_string(JSON.stringify(existing, "	"))
		wf.close()
		print("
Wrote per-level role_multipliers for %d roles into the curve file." % out_roles.size())
	monster_db._reference_anchors = []
	monster_db._curve_is_calibrated = false
	print("=====================================================================
")

func run_species_audit():
	# #6c (user challenge 2026-09-02: "monsters differ substantially — is the sim testing a
	# variety?"). The sim does: select_monster_type picks 20-35 species per level. But every
	# audit reports the AGGREGATE, which hides the question that actually matters — whether the
	# same nominal encounter is a different fight depending on WHICH monster shows up.
	# A wide spread here means average difficulty is meaningless to a player, who meets one
	# monster at a time, not an average.
	var samples: int = maxi(8, int(_audit_n / 6.0))
	print("
===== #6c PER-SPECIES SPREAD (same level, same gear, Fighter) =====")
	print("Win%% against each species the game can actually pick at that level, %d fights each." % (samples * 3))
	for lvl in [50, 1000]:
		# Collect the species the selector really produces at this level.
		var seen := {}
		for i in range(400):
			var t = monster_db.select_monster_type(lvl)
			var nm := String(monster_db.get_monster_base_stats(t).get("name", "?"))
			seen[nm] = int(seen.get(nm, 0)) + 1
		var names: Array = seen.keys()
		names.sort_custom(func(a, b): return int(seen[a]) > int(seen[b]))
		var rows: Array = []
		for nm in names:
			if int(seen[nm]) < 8:   # ignore the long tail of rare bleed-through picks
				continue
			var wins := 0
			var turns := 0.0
			var n := 0
			for klass in ["Fighter", "Wizard", "Thief"]:
				for i in range(samples):
					var ch = make_char(lvl, "average", klass)
					var monster = monster_db.generate_monster_by_name(nm, lvl, true)
					if monster == null or monster.is_empty():
						continue
					monster["current_hp"] = monster.get("max_hp", 1)
					ch.in_combat = false
					combat_mgr.start_combat(0, ch, monster)
					if not combat_mgr.active_combats.has(0):
						continue
					var combat = combat_mgr.active_combats[0]
					var t2 := 0
					while t2 < 400:
						if ch.current_hp <= 0 or int(monster.get("current_hp", 0)) <= 0 or combat.get("combat_ended", false):
							break
						t2 += 1
						if combat.get("player_can_act", true):
							match ch.get_class_path():
								"trickster": _player_act_trickster(combat, ch)
								"mage": _player_act_mage(combat, ch)
								_: _player_act(combat, ch)
						if int(monster.get("current_hp", 0)) <= 0:
							break
						combat_mgr.process_monster_turn(combat)
					if int(monster.get("current_hp", 0)) <= 0 and ch.current_hp > 0:
						wins += 1
					turns += float(t2)
					n += 1
					combat_mgr.end_combat(0, false, false)
			if n > 0:
				rows.append([nm, int(100.0 * wins / n), turns / n, int(seen[nm]) * 100 / 400])
		rows.sort_custom(func(a, b): return int(a[1]) < int(b[1]))
		print("")
		print("--- L%d ---   %-22s %7s %8s %7s" % [lvl, "species", "win%", "turns", "spawn%"])
		for r in rows:
			print("              %-22s%s %6d%% %8.1f %6d%%" % [r[0], " APEX" if monster_db.is_apex_species(String(r[0])) else "     ", r[1], r[2], r[3]])
		# Report the two populations SEPARATELY. Apex species are deliberately outside the
		# normal band, so a combined spread mixes "monsters that should be alike" with
		# "monsters that should be frightening" and reads as a regression when it is the
		# design working. The number that matters is the spread WITHIN each group.
		var normal_rows: Array = []
		var apex_rows: Array = []
		for r in rows:
			if monster_db.is_apex_species(String(r[0])):
				apex_rows.append(r)
			else:
				normal_rows.append(r)
		if normal_rows.size() >= 2:
			print("              NORMAL spread: %d%% (%s) to %d%% (%s) — %d points" % [
				int(normal_rows[0][1]), normal_rows[0][0],
				int(normal_rows[normal_rows.size()-1][1]), normal_rows[normal_rows.size()-1][0],
				int(normal_rows[normal_rows.size()-1][1]) - int(normal_rows[0][1])])
		if apex_rows.size() >= 1:
			var atot := 0
			for r in apex_rows:
				atot += int(r[1])
			print("              APEX: %d species, mean win %d%% (target %d%%) — should sit BELOW the normal group" % [
				apex_rows.size(), int(float(atot) / float(apex_rows.size())), int(monster_db.APEX_TARGET_WIN * 100.0)])
	print("=====================================================================
")

func run_resource_economy_audit():
	# #6c (user report 2026-09-02: "Blast shows it costs 0 but did 1900 damage").
	# Ability costs scale with the NAKED pool while per-turn regen is a % of the pool capped at
	# 25 + level/2. When regen >= cost, the ability is FREE and the resource system stops being
	# a constraint at all — every card becomes "press the biggest button". This measures cost
	# against regen for every damage ability, per class, so it is clear which are free and
	# whether it is a mage problem or a whole-game problem.
	print("
===== #6c RESOURCE ECONOMY: is the cost real? =====")
	print("cost = actual resource spent on one cast. regen = restored per player turn.")
	print("NET = cost - regen. NET <= 0 means the ability is FREE: the turn pays for itself.")
	print("%-9s %-14s %7s %9s %9s %9s %8s" % ["Class", "Ability", "Level", "pool", "cost", "regen", "NET"])
	var cases := [
		["Fighter", ["power_strike", "cleave", "devastate"]],
		["Wizard", ["blast", "meteor", "magic_bolt"]],
		["Thief", ["ambush", "exploit", "gambit"]],
	]
	for lvl in [10, 50, 250, 1000]:
		for c in cases:
			var klass: String = String(c[0])
			for ab in (c[1] as Array):
				var ch = make_char(lvl, "average", klass)
				var monster := make_monster(lvl, "normal", 1.0)
				monster["max_hp"] = int(monster.get("max_hp", 1)) * 100
				monster["current_hp"] = monster.get("max_hp", 1)
				ch.in_combat = false
				combat_mgr.start_combat(0, ch, monster)
				if not combat_mgr.active_combats.has(0):
					continue
				var combat = combat_mgr.active_combats[0]
				_force_hand(combat, String(ab))
				var pool: int = _class_max_resource(ch)
				# GROSS cost, read from the `path_last_ability_cost` meta that apply_variable_cost
				# stamps. A before/after delta on the resource measures NET, because regen fires
				# during the same turn as the cast — the first version of this audit did exactly
				# that and reported a cost of 0 for nearly every ability, which then double-counted
				# regen when NET was computed. _measure_ability already documented this trap.
				var arg: String = str(maxi(1, int(float(ch.get_total_max_mana()) * 0.20))) if ab == "magic_bolt" else ""
				ch.set_meta("path_last_ability_cost", 0)
				combat_mgr.process_ability_command(0, String(ab), arg)
				var cost: int = int(ch.get_meta("path_last_ability_cost", 0))
				if ab == "magic_bolt":
					cost = int(arg) if arg.is_valid_int() else 0
				# Regen restored on a fresh player turn, measured on its own.
				var before_regen: int = _class_resource(ch)
				var msgs: Array = []
				combat_mgr._apply_gear_resource_regen(ch, msgs)
				var regen: int = maxi(0, _class_resource(ch) - before_regen)
				combat_mgr.end_combat(0, false, false)
				var net: int = cost - regen
				var flag: String = "  FREE" if net <= 0 else ""
				print("%-9s %-14s %7d %9d %9d %9d %8d%s" % [klass, ab, lvl, pool, cost, regen, net, flag])
	print("")
	print("Any row marked FREE has no resource cost in practice: the turn's regen covers the")
	print("spend, so there is nothing to manage and no reason to ever cast anything cheaper.")
	print("=====================================================================
")

# === RELATIVE SPECIES POWER (2026-09-04) ===
# `speciescal` used to correct each species toward an ABSOLUTE win band (48-72%, or 28-48% for
# apex). That made it fight `refcal`, because a species' win rate depends on two things at once
# - how strong the species is, and how strong the base curve is - and an absolute target cannot
# tell them apart:
#
#   1. base curve slightly too hard, so the average fight sits at 50% instead of 60%
#   2. speciescal measures EVERY species low and weakens them all toward their absolute bands
#   3. the average is now ~68%, too easy
#   4. refcal strengthens the base to pull it back to 60%
#   5. every species measures differently again, so all the corrections are stale -> goto 1
#
# Both were trying to control the same quantity - average difficulty - from opposite ends.
# Measured as ringing rather than convergence: consecutive rounds moved L50 68% -> 51% and
# L5000 53% -> 69%, against a ~4.5pp sampling error.
#
# Now each species is corrected toward a RATIO of the mix it belongs to. If the base curve is
# off, every species moves together, the ratios are unchanged, and speciescal correctly does
# nothing - it has no opinion about the average. `refcal` owns "how hard is this level";
# speciescal owns "how much do monsters differ from each other". Independent quantities, so one
# pass of each settles instead of needing iteration.
#
# The comparison is done in LOG-ODDS, not raw ratios. Win rate is bounded at 0 and 1, so a raw
# ratio distorts badly near the ends - 95% and 100% look nearly identical as ratios though one
# is plainly worse - and "one band harder" would mean different things depending on where the
# mix average happened to sit. Log-odds is the standard treatment for a bounded proportion: the
# offset between apex and normal is a constant shift whatever the mean.
const LOGIT_EPS := 0.02

static func _logit(p: float) -> float:
	var q: float = clampf(p, LOGIT_EPS, 1.0 - LOGIT_EPS)
	return log(q / (1.0 - q))

static func _inv_logit(x: float) -> float:
	return 1.0 / (1.0 + exp(-x))

func _species_win_at(nm: String, lvl: int, samples: int) -> Dictionary:
	"""Win rate against ONE species at ONE level, pooled across the three archetypes.

	Extracted so the calibration can solve a correction PER LEVEL without the measurement loop
	being nested four deep inside it. Returns n as well as the rate so the caller can tell "this
	species never spawns here" apart from "it spawns and always wins", which are the same 0.0
	otherwise."""
	var wins := 0
	var n := 0
	for klass in ["Fighter", "Wizard", "Thief"]:
		for i in range(samples):
			var ch = make_char(lvl, "average", klass)
			var monster = monster_db.generate_monster_by_name(nm, lvl, true)
			if monster == null or monster.is_empty():
				continue
			monster["current_hp"] = monster.get("max_hp", 1)
			ch.in_combat = false
			combat_mgr.start_combat(0, ch, monster)
			if not combat_mgr.active_combats.has(0):
				continue
			var combat = combat_mgr.active_combats[0]
			var t2 := 0
			while t2 < 300:
				if ch.current_hp <= 0 or int(monster.get("current_hp", 0)) <= 0 or combat.get("combat_ended", false):
					break
				t2 += 1
				if combat.get("player_can_act", true):
					match ch.get_class_path():
						"trickster": _player_act_trickster(combat, ch)
						"mage": _player_act_mage(combat, ch)
						_: _player_act(combat, ch)
				if int(monster.get("current_hp", 0)) <= 0:
					break
				combat_mgr.process_monster_turn(combat)
			if int(monster.get("current_hp", 0)) <= 0 and ch.current_hp > 0:
				wins += 1
			n += 1
			combat_mgr.end_combat(0, false, false)
	return {"win": (float(wins) / float(n)) if n > 0 else 0.0, "n": n}

func run_species_calibrate():
	# #6c — calibrate a per-species power correction so the same level is roughly the same
	# fight whichever monster shows up. Measured spread before this: 31%-100% win at L50 and
	# 22%-86% at L1000, driven by monster ABILITIES which sit outside the stat anchor.
	#
	# Deliberately targets a BAND rather than equality. Species variety is the point — a Hydra
	# should be a harder fight than a Harpy — so only species outside the band are corrected,
	# and only toward its edge. Equalising them would make every monster the same fight, which
	# is a worse outcome than the spread.
	# Raised 2026-09-04 with the per-level split. Pooling three levels per measurement meant 4
	# per class was really 12 per class; measuring ONE level made every cell 3x smaller, and at
	# 12 fights the standard error is ~14 percentage points - which is exactly what the first
	# per-level run produced: Ancient Dragon corrections of 0.50, 0.65, 1.37, 1.25, 1.15, 1.70
	# across six levels, a noise sequence rather than a curve.
	var samples: int = maxi(15, int(_audit_n / 3.0))
	var passes := 3
	# Widened 2026-09-04 from [50, 250, 1000]. Two measured reasons. L100 was the anchor that
	# would not calibrate and it was NOT SAMPLED here at all, so the corrections applied to it
	# were extrapolated from levels either side. And coverage: only 29 species were being
	# calibrated, because low-tier species stop spawning well before L50 and the highest tiers
	# only appear far above L1000 — neither end was ever measured.
	var levels := [10, 50, 100, 250, 1000, 5000]
	var base_target := 0.60     # centre of the acceptable win-rate band
	var base_band := 0.12       # +/- this is left alone
	print("
===== #6c SPECIES POWER CALIBRATION =====")
	print("Target band: %.0f%%-%.0f%% win. Species inside it are left alone." % [(base_target - base_band) * 100.0, (base_target + base_band) * 100.0])
	print("APEX species are calibrated to a HARDER band (%.0f%%-%.0f%%) on purpose — they are the" % [(monster_db.APEX_TARGET_WIN - monster_db.APEX_TARGET_BAND) * 100.0, (monster_db.APEX_TARGET_WIN + monster_db.APEX_TARGET_BAND) * 100.0])
	print("monsters a player should learn to be careful of, and they pay %.1fx XP for it." % monster_db.APEX_XP_MULT)
	var power := {}
	# Collect the species actually reachable at these levels.
	var species := {}
	# PER LEVEL, because a species must only be calibrated where it actually turns up. The first
	# per-level run calibrated a Giant Rat at L5000 (100% win, correction capped at x1.71) and a
	# Mimic likewise: `generate_monster_by_name` FORCES a spawn, so a "does it appear here" guard
	# based on generation never fires. Those anchors are meaningless and then get interpolated
	# into levels that are real.
	var species_at := {}
	for lvl in levels:
		species_at[lvl] = {}
		for i in range(400):
			var t = monster_db.select_monster_type(lvl)
			var nm := String(monster_db.get_monster_base_stats(t).get("name", ""))
			if nm != "":
				species[nm] = int(species.get(nm, 0)) + 1
				species_at[lvl][nm] = int(species_at[lvl].get(nm, 0)) + 1
	var names: Array = []
	for k in species.keys():
		if int(species[k]) >= 10:
			names.append(k)
	names.sort()
	print("Calibrating %d species PER LEVEL at %s." % [names.size(), str(levels)])
	# Apex sits a fixed distance BELOW its mix in log-odds, rather than at a fixed win rate. The
	# shift is derived from the existing intent (38% against 60%) so the design is unchanged -
	# only its expression, from an absolute that breaks when the base curve moves to a relative
	# one that does not.
	var apex_shift: float = _logit(float(monster_db.APEX_TARGET_WIN)) - _logit(base_target)
	var band_logit: float = _logit(base_target + base_band) - _logit(base_target)
	print("Each species is judged against the MIX at its own level, not an absolute win rate.")
	print("Apex target = mix shifted %.2f in log-odds (38%% vs 60%%); band +/-%.2f." % [apex_shift, band_logit])
	# Measure the mix once per level, through the real spawn distribution.
	var mix_at := {}
	for lvl in levels:
		var mres := _fight_stats_at(lvl, maxi(20, int(_audit_n / 2.0)))
		mix_at[lvl] = float(mres.get("win", base_target)) if not mres.is_empty() else base_target
		print("  mix at L%-6d %.0f%% win" % [lvl, 100.0 * float(mix_at[lvl])])
	for nm in names:
		# Apex species aim at a deliberately harder band than their peers.
		var is_apex: bool = monster_db.is_apex_species(nm)
		var target: float = float(monster_db.APEX_TARGET_WIN) if is_apex else base_target
		var band: float = float(monster_db.APEX_TARGET_BAND) if is_apex else base_band
		# PER LEVEL, not one scalar for the species. Measured with the flat form: Ancient Dragon
		# was corrected x0.66 from samples at L50/L250/L1000 and then read 88% win at L100, while
		# Minotaur calibrated to 56% and read 31% at that same level. A species' difficulty
		# relative to the curve is not constant with level, because its ABILITIES scale
		# differently from its stats — which is the entire reason this correction exists.
		var sp_anchors: Array = []
		var shown: Array = []
		for cal_lvl in levels:
			# At least a 1-in-100 spawn share here, or this level is not part of this species'
			# life and an anchor for it would be fiction.
			if int(species_at[cal_lvl].get(nm, 0)) < 4:
				continue
			# The MIX this species belongs to, measured at this level through the real spawn
			# distribution. This is the reference the species is judged against, instead of a
			# fixed number that silently encodes an assumption about the base curve.
			var mix_win: float = float(mix_at.get(cal_lvl, base_target))
			var target_logit: float = _logit(mix_win) + (apex_shift if is_apex else 0.0)
			var corr := 1.0
			var last_win := 0.0
			var measured := false
			for pass_i in range(passes):
				# A bare float while measuring: this pass tests ONE candidate at ONE level, so a
				# constant is exactly right. The per-level anchors are assembled from the solved
				# values afterwards.
				monster_db.set_species_power({nm: corr})
				var r := _species_win_at(nm, cal_lvl, samples)
				monster_db.set_species_power({})
				if int(r.get("n", 0)) == 0:
					break
				measured = true
				last_win = float(r.get("win", 0.0))
				# Distance from where this species SHOULD sit relative to its mix, in log-odds.
				# Inside the band it is left alone - variety is the point, and only outliers are
				# corrected, toward the nearest edge rather than to the centre.
				var d: float = _logit(last_win) - target_logit
				if absf(d) <= band_logit:
					break
				var edge_logit: float = target_logit + (band_logit if d > 0.0 else -band_logit)
				var edge: float = _inv_logit(edge_logit)
				# Too-hard species (low win) need LESS power; too-easy need more.
				corr *= pow(clampf(last_win / maxf(0.02, edge), 0.4, 2.5), 0.6)
				corr = clampf(corr, 0.35, 2.5)
			if not measured:
				continue   # this species does not spawn at this level; leave a gap, do not guess
			sp_anchors.append({"level": cal_lvl, "power": corr})
			if absf(corr - 1.0) > 0.02:
				shown.append("L%d %.0f%%->x%.2f" % [cal_lvl, last_win * 100.0, corr])
		if sp_anchors.is_empty():
			continue
		power[nm] = sp_anchors
		if not shown.is_empty():
			print("  %-22s%s %s" % [nm, " APEX" if is_apex else "     ", "  ".join(shown)])
	var existing := {}
	var rf = FileAccess.open("res://shared/reference_monster_curve.json", FileAccess.READ)
	if rf:
		var parsed = JSON.parse_string(rf.get_as_text())
		rf.close()
		if parsed is Dictionary:
			existing = parsed
	existing["species_power"] = power
	var wf = FileAccess.open("res://shared/reference_monster_curve.json", FileAccess.WRITE)
	if wf:
		wf.store_string(JSON.stringify(existing, "	"))
		wf.close()
		print("
Wrote species_power for %d species." % power.size())
	monster_db._reference_anchors = []
	monster_db._curve_is_calibrated = false
	print("=====================================================================
")

# HP ACCOUNTING RECONCILIATION — REMOVED 2026-09-02, and worth recording why.
#
# The goal was sound: a player reported a fight where the log said 298 damage but only 82 HP
# was lost, and said it would be hard to reproduce by hand. That is exactly what a simulator
# should catch instead of a person.
#
# The IMPLEMENTATION was wrong, three times over. It worked by parsing the combat message text
# and summing the numbers in it, which is brittle by construction:
#   * v1 took the LAST number in lines containing "damage"/"heal" — missed poison, bleed and
#     regen entirely, and reported 13-50% of turns as unreconciled. Those were its own blind
#     spots, not game bugs.
#   * v2 broadened the keywords and switched to the FIRST number — which in "hits 2 times for
#     298 total damage" is the HIT COUNT. Mismatches jumped to 93% with gaps of 12,833.
# Each version produced confident, specific, wrong numbers. A tool that cries wolf about 103
# bugs when there are none is worse than no tool: the next person to run it wastes a day.
#
# The right way to build this is to INSTRUMENT THE SOURCE rather than read its prose — have
# process_monster_turn accumulate a per-turn ledger of every HP change with its cause, and
# assert that ledger against the actual delta. That is a change to shared combat code and
# deserves doing deliberately rather than bolted onto an audit.
#
# What was established without it, by direct trace: monster damage application is CORRECT
# (logged damage matched HP lost exactly across 4 Chimaera multi-strike trials — 160/160,
# 224/224, 98/98, 183/183), and the reported confusion was companion lifesteal reporting its
# intended heal instead of the clamped actual one, which is fixed.

func run_reference_curve():
	print("\n===== #6 REFERENCE-PLAYER CURVE (the anchor for the monster model) =====")
	print("Per level, measured from the real combat code with the calibrated make_char:")
	print("  dpt      = damage/turn a reference player deals (full ability rotation)")
	print("  ehp      = reference player max HP")
	print("  taken_ps = damage taken per turn per point of monster strength")
	print("Median across the three archetypes, %d chars x %d turns each." % [REF_SAMPLES, REF_PROBE_TURNS])
	print("%-8s %12s %12s %12s %10s %10s" % ["Level", "dpt", "ehp", "taken_ps", "dpt/ehp", "classes"])
	var table: Array = []
	for lvl in REF_ANCHOR_LEVELS:
		var dpts: Array = []
		var ehps: Array = []
		var tps: Array = []
		var ok := 0
		for klass in ["Fighter", "Wizard", "Thief"]:
			var r := _measure_reference_at(lvl, klass)
			if r.is_empty():
				continue
			dpts.append(float(r["dpt"]))
			ehps.append(float(r["ehp"]))
			tps.append(float(r["taken_ps"]))
			ok += 1
		if ok == 0:
			continue
		var row := {
			"level": lvl,
			"dpt": _median(dpts),
			"ehp": _median(ehps),
			"taken_ps": _median(tps),
		}
		table.append(row)
		print("%-8d %12.1f %12.1f %12.4f %10.3f %10d" % [
			lvl, float(row["dpt"]), float(row["ehp"]), float(row["taken_ps"]),
			float(row["dpt"]) / maxf(1.0, float(row["ehp"])), ok])
	# Growth exponents: how fast each side actually scales. If dpt grows much
	# faster than ehp, the player's offence outruns their own durability, which is
	# what makes flat monster tables read as "easy late".
	print("")
	print("Growth between consecutive anchors (x per level-decade) — the shape the")
	print("monster model has to track. A flat column means that quantity scales with")
	print("level; a rising one means it outruns level.")
	print("%-14s %10s %10s %10s" % ["Range", "dpt x", "ehp x", "taken_ps x"])
	for i in range(1, table.size()):
		var a: Dictionary = table[i - 1]
		var b: Dictionary = table[i]
		print("%-14s %9.2fx %9.2fx %9.2fx" % [
			"L%d->L%d" % [int(a["level"]), int(b["level"])],
			float(b["dpt"]) / maxf(0.001, float(a["dpt"])),
			float(b["ehp"]) / maxf(0.001, float(a["ehp"])),
			float(b["taken_ps"]) / maxf(0.000001, float(a["taken_ps"]))])
	var out := {"generated": "sim run_reference_curve", "anchors": table}
	var f = FileAccess.open("res://shared/reference_player_curve.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out, "\t"))
		f.close()
		print("\nWrote shared/reference_player_curve.json (%d anchors)." % table.size())
	else:
		print("\nCould not write shared/reference_player_curve.json")
	print("=====================================================================\n")


func run_gear_solve():
	# #5 — pick the "average" gear model from DATA instead of hand-tuning a rarity string.
	# Sweeps the two knobs against the real-character cohort and prints the cohort median
	# sim/real ratio for each combination. The combination whose three medians sit nearest
	# 1.00 is the calibration; anything else is a guess with a comment attached.
	var all_reals := _load_real_characters()
	var reals: Array = []
	for r in all_reals:
		if String(_classify_real(r)["band"]) == "geared":
			reals.append(r)
	print("
===== #5 GEAR-MODEL SOLVE (average tier) =====")
	print("Fitted ONLY to the %d of %d saved characters that are actually GEARED (5+ slots," % [reals.size(), all_reals.size()])
	print("not all epic). Fitting to naked test accounts pulls the model the wrong way.")
	if reals.is_empty():
		print("No geared characters to fit against — play a character before trusting this.")
		print("=====================================================================
")
		return
	print("Median sim/real per knob combination. Target: all three near 1.00.")
	print("%-6s %-7s %8s %8s %8s %8s" % ["ItmLvl", "Empty", "HP", "ATK", "POOL", "|err|"])
	var save_ratio := _gear_avg_level_ratio
	var save_empty := _gear_avg_empty_chance
	var best := {}
	for ratio in [0.7, 0.85, 1.0, 1.15, 1.3]:
		for empty in [0.0, 0.15, 0.30]:
			_gear_avg_level_ratio = ratio
			_gear_avg_empty_chance = empty
			var cols := [[], [], []]
			for real in reals:
				var acc := _ratios_vs(real, "average")
				for i in range(3):
					cols[i].append(acc[i])
			var meds := []
			var err := 0.0
			for i in range(3):
				var m: float = _median(cols[i])
				meds.append(m)
				err += absf(m - 1.0)
			print("%-6.2f %-7.2f %7.2fx %7.2fx %7.2fx %8.2f" % [ratio, empty, meds[0], meds[1], meds[2], err])
			if best.is_empty() or err < float(best.get("err", 1e9)):
				best = {"ratio": ratio, "empty": empty, "err": err, "meds": meds}
	_gear_avg_level_ratio = save_ratio
	_gear_avg_empty_chance = save_empty
	# PER-CHARACTER solve. A single best-fit ratio can be wrong in two very different ways:
	# the constant is off (every character wants the same different ratio) or the SHAPE is
	# off (each character wants a different ratio, trending with level). Only the second
	# needs a level-dependent model, so measure which one it is instead of assuming.
	print("")
	print("Per-character best ratio — if these trend with level, the model shape is wrong,")
	print("not just its constant, and no single ratio will ever fit the whole game.")
	print("%-11s %-5s %-9s %8s %8s" % ["Name", "Lvl", "BestRatio", "ATKratio", "|err|"])
	_gear_avg_empty_chance = 0.0
	for real in reals:
		var best_r := 0.0
		var best_e := 1e9
		var best_atk := 0.0
		for ri in range(1, 41):
			var ratio2: float = 0.2 + 0.1 * float(ri)
			_gear_avg_level_ratio = ratio2
			var acc := _ratios_vs(real, "average")
			var e: float = absf(acc[0] - 1.0) + absf(acc[1] - 1.0) + absf(acc[2] - 1.0)
			if e < best_e:
				best_e = e
				best_r = ratio2
				best_atk = acc[1]
		print("%-11s %-5d %8.2f %8.2fx %8.2f" % [String(real.name).substr(0, 11), int(real.level), best_r, best_atk, best_e])
	_gear_avg_level_ratio = save_ratio
	_gear_avg_empty_chance = save_empty
	print("")
	print("BEST: item-level ratio=%.2f empty=%.2f -> HP %.2fx ATK %.2fx POOL %.2fx (total error %.2f)" % [
		float(best.get("ratio", 1.0)), float(best.get("empty", 0.0)),
		float(best.get("meds")[0]), float(best.get("meds")[1]), float(best.get("meds")[2]), float(best.get("err", 0.0))])
	print("Set _gear_avg_level_ratio / _gear_avg_empty_chance to these if they beat the current values.")
	print("=====================================================================
")

func _pool_for_path(ch, path: String) -> int:
	match path:
		"mage": return int(ch.get_total_max_mana())
		"trickster": return int(ch.get_total_max_energy())
		_: return int(ch.get_total_max_stamina())

func run_race_audit():
	# #5 — make_char hardcoded Human, so every balance number ever produced by this sim
	# was a Human number. Item 6 wants race compared against class; this is the input.
	var N := 60
	print("\n===== #5 RACE AUDIT (%d fights/cell, AVERAGE gear, L30 elite) =====" % N)
	print("One row per race x archetype representative. Win%% / avg turns / lowest HP%% reached.")
	print("%-10s %s" % ["Race", "Fighter            Wizard             Thief"])
	for race in ALL_RACES:
		var row := "%-10s" % race
		for klass in ["Fighter", "Wizard", "Thief"]:
			var wins := 0
			var turns := 0
			var mhp := 0.0
			for i in range(N):
				var r = run_fight(30, "average", "elite", 1.0, 1.0, 1.0, klass, -1, race)
				if r.win:
					wins += 1
				turns += int(r.turns)
				mhp += float(r.get("min_hp_pct", 0.0))
			row += "   %3d%% %4.1ft H%2.0f%%" % [int(100.0 * wins / N), float(turns) / N, mhp / N]
		print(row)
	print("=====================================================================\n")

func run_difficulty_audit():
	# Measures combat feel across level × gear × enemy-tier AFTER the #55 player changes.
	# Per cell: Win% / avg Turns / avg lowest-HP% reached / avg lowest-resource% reached.
	# Goal: normal = quick + fairly safe; elite = a real fight; boss = dangerous. And GEAR
	# should matter — an under-geared player should struggle where a bis one is comfortable.
	var N := 70
	var levels := [3, 6, 10, 50, 200]  # #70 — added low levels (L3/L6) to expose low-level trivialization
	var gears := ["under", "average", "bis"]
	var enemies := ["normal", "elite", "boss"]
	var classes := [["Fighter", "War"], ["Wizard", "Mag"], ["Thief", "Trk"]]
	print("\n===== MONSTER-CHALLENGE AUDIT (%d fights/cell) =====" % N)
	print("cell = Win%% Turns MinHP%% (per gear: under | average | bis). MinHP%% = lowest HP reached.")
	for lvl in levels:
		for c in classes:
			for et in enemies:
				var row := "L%-4d %-4s %-7s" % [lvl, c[1], et]
				for gear in gears:
					var wins := 0
					var tt := 0.0
					var mhp := 0.0
					for i in range(N):
						var r = run_fight(lvl, gear, et, 1.0, 1.0, 1.0, c[0])
						if r.win:
							wins += 1
						tt += float(r.turns)
						mhp += float(r.get("min_hp_pct", 0.0))
					row += "| %3d%% %4.1ft H%2.0f " % [int(100.0 * wins / N), tt / N, mhp / N]
				print(row)
	print("=====================================================================\n")

func run_proposal_read():
	# Combined proposal: REAL dumps (Devastate + Outsmart in combat_manager) + capped regen,
	# with mage cost still emulated at 2x (until cost_percent is raised for real). Shows the
	# gear-investment gradient (avg = pressured, bis = comfortable) across levels to L1000.
	_dump_pct = 0.0   # dumps are real now — no emulation
	_cost_mult = 1.0  # mage cost is now REAL (raised cost_percent) — no emulation
	run_resource_audit()

func run_hp_solve():
	# #29 — sweep an extra monster-HP multiplier (War+Trk = accurate classes) to find
	# what lands "real" fights at ~8-12t with a healthy win-rate. L50, elite/boss.
	var N := 60
	var mults := [2.0, 3.0, 4.0, 5.0]
	print("\n===== #29 MONSTER-HP SOLVE (L50, War+Trk) — avgTurns@win%% per HP mult =====")
	for c in [["Fighter", "War"], ["Thief", "Trk"]]:
		for gear in ["average", "bis"]:
			for et in ["elite", "boss"]:
				var row := "%s %-8s %-5s" % [c[1], gear, et]
				for hm in mults:
					var wins := 0
					var tt := 0
					for i in range(N):
						var r = run_fight(50, gear, et, hm, 1.0, 1.0, c[0])
						if r.win:
							wins += 1
						tt += r.turns
					row += "   %.0fx: %4.1ft@%d%%" % [hm, float(tt) / N, int(100.0 * wins / N)]
				print(row)
	print("=================================================================\n")

func run_resource_audit():
	# Resource-economy audit (2026-08-25). Answers: does the combat resource ever
	# actually BIND, and does it stay pegged high as level/gear scale (= management
	# is dead)? Headline column = MinRes% (avg lowest pool% reached in a fight). If
	# MinRes% stays high (esp. at high lvl / bis gear), the pool is never a real
	# constraint → the exact "resources stop mattering" problem. Pool = avg max pool.
	# Casts/t = ability casts per turn (near 1.0 + high MinRes% = casting freely).
	var N := 40
	var levels := [10, 50, 200, 1000]  # include EXTREME level — system must hold to L1000+
	var gears := ["average", "bis"]
	var enemies := ["elite", "boss"]
	var classes := [["Fighter", "War"], ["Thief", "Trk"], ["Wizard", "Mag"]]
	print("\n===== RESOURCE AUDIT (%d fights/cell) — does the pool ever bind? =====" % N)
	print("MinRes%% high = pool never pressured (management dead). Watch it RISE with lvl/gear.")
	print("%-4s %-4s %-8s %-6s %6s %7s %8s %8s %8s %7s" % ["Cls", "Lvl", "Gear", "Enemy", "Win%", "Turns", "Casts/t", "MinRes%", "EndRes%", "Pool"])
	for c in classes:
		for lvl in levels:
			for gear in gears:
				for et in enemies:
					var wins := 0
					var tt := 0.0
					var tc := 0.0
					var tmin := 0.0
					var tend := 0.0
					var tpool := 0.0
					for i in range(N):
						var r = run_fight(lvl, gear, et, 1.0, 1.0, 1.0, c[0])
						if r.win:
							wins += 1
						tt += r.turns
						tc += float(r.get("casts", 0)) / maxf(1.0, float(r.turns))
						tmin += float(r.get("min_res_pct", 0.0))
						tend += float(r.get("end_res_pct", 0.0))
						tpool += float(r.get("max_res", 0))
					print("%-4s %-4d %-8s %-6s %5.0f%% %7.1f %8.2f %7.0f%% %7.0f%% %7.0f" % [
						c[1], lvl, gear, et, 100.0 * wins / N, tt / N, tc / N, tmin / N, tend / N, tpool / N])
	print("=====================================================================\n")

func _force_hand(combat: Dictionary, ability: String) -> void:
	var hand: Array = combat.get("combat_hand", [])
	if not (ability in hand):
		hand.append(ability)
		combat["combat_hand"] = hand

func _measure_ability(level: int, gear: String, klass: String, ability: String) -> Dictionary:
	# #55 — single cast, ability forced into hand. Returns {damage, cost, pool}.
	# GROSS cost via the `path_last_ability_cost` meta stamped in apply_variable_cost
	# (only zeroed on a KILLING blow), read off an UN-KILLABLE dummy (50× HP) so no
	# kill-refund fires and the per-round mana/stam/energy REGEN can't mask the spend
	# (net-resource delta was the old confound). magic_bolt isn't on the variable path,
	# so use its intended spend (the arg). Engines (momentum/focus/read) start at 0.
	var ch = make_char(level, gear, klass)
	var monster = make_monster(level, "boss", 50.0)  # ultra-tanky: 1 cast never kills
	combat_mgr.start_combat(0, ch, monster)
	if not combat_mgr.active_combats.has(0):
		return {"damage": 0.0, "cost": 0.0, "pool": 0.0}
	var combat = combat_mgr.active_combats[0]
	_force_hand(combat, ability)
	var mhp0: int = int(monster.get("current_hp", 0))
	ch.set_meta("path_last_ability_cost", 0)  # clear before cast so we read THIS cast's spend
	var arg: String = str(maxi(1, int(ch.get_total_max_mana() * 0.25))) if ability == "magic_bolt" else ""
	combat_mgr.process_ability_command(0, ability, arg)
	var dmg: int = mhp0 - int(monster.get("current_hp", 0))
	var cost: int = int(ch.get_meta("path_last_ability_cost", 0))  # GROSS spend, regen-immune
	if ability == "magic_bolt":
		cost = int(arg) if arg.is_valid_int() else 0
	var pool: int = _class_max_resource(ch, klass)  # total pool (incl gear) to show casts/bar
	combat_mgr.end_combat(0, false, false)
	return {"damage": float(dmg), "cost": float(cost), "pool": float(pool)}

func _cast_at_scaled(ch, base_monster: Dictionary, ability: String, hp_mult: float) -> float:
	# One cast by an EXISTING character at a COPY of a given monster, scaled to hp_mult.
	# max_hp and current_hp are scaled together because combat_manager clamps current_hp to
	# max_hp — inflating current_hp alone is silently discarded and reads back as fake damage.
	var monster: Dictionary = base_monster.duplicate(true)
	var big: int = maxi(1, int(float(base_monster.get("max_hp", 1)) * hp_mult))
	monster["max_hp"] = big
	monster["current_hp"] = big
	# Full resources so the second cast of a pair is never cheaper or weaker than the first.
	ch.current_stamina = ch.get_total_max_stamina()
	ch.current_mana = ch.get_total_max_mana()
	ch.current_energy = ch.get_total_max_energy()
	ch.current_hp = ch.get_total_max_hp()
	ch.in_combat = false
	combat_mgr.start_combat(0, ch, monster)
	if not combat_mgr.active_combats.has(0):
		return 0.0
	var combat = combat_mgr.active_combats[0]
	_force_hand(combat, ability)
	var hp0: int = int(monster.get("current_hp", 0))
	# Magic Bolt is measured at a FULL DUMP. Its design is "commit the whole bar for a nuke",
	# and both the spend fraction and the efficiency curve scale off that commitment, so a
	# 25% cast reads ~6% of a health bar while a full one reads its actual weight. Measuring
	# the chip made the ability look broken-weak when it was the audit choosing a timid cast.
	var arg: String = str(maxi(1, int(ch.get_total_max_mana()))) if ability == "magic_bolt" else ""
	combat_mgr.process_ability_command(0, ability, arg)
	var dmg: int = hp0 - int(monster.get("current_hp", 0))
	combat_mgr.end_combat(0, false, false)
	return float(dmg)

func _ability_bar_fraction(level: int, gear: String, klass: String, ability: String, n: int) -> float:
	# One cast's damage as a FRACTION of a same-level normal monster's health bar, immune to
	# every way this particular measurement goes wrong (all four were hit while building it):
	#   1. A flat-damage ability measured on a true-size target is TRUNCATED when it one-shots,
	#      hiding exactly the early-game overkill we want to see.
	#   2. A %-max-HP ability (Exploit: 10-22% of max HP) measured on an oversized dummy is
	#      inflated by the whole dummy multiplier — this audit first claimed Exploit hits for
	#      46000% of a health bar when it is hard-capped at 22% of one.
	#   3. Comparing two casts by DIFFERENT randomly-geared characters measures gear variance
	#      instead of target size.
	#   4. Comparing two casts against DIFFERENT randomly-chosen monsters measures the gap
	#      between monster types (a same-level bar ranges ~26k to ~217k at L1000) instead of
	#      the scaling. This one produced negative and million-percent "fractions".
	# So: one character and one monster per sample, cast at two sizes of THAT monster, and read
	# the answer off the slope. Damage that grows with target size is proportional (the slope
	# is its fraction of any bar); damage that ignores target size is flat (divide by the real
	# bar). Nothing hardcodes which abilities are percentage-based, so it cannot rot.
	var m1 := 50.0
	var m2 := 100.0
	var acc := 0.0
	var samples := 0
	for i in range(n):
		var ch = make_char(level, gear, klass)
		var base_monster := make_monster(level, "normal", 1.0)
		var bar := float(maxi(1, int(base_monster.get("max_hp", 1))))
		var d1 := _cast_at_scaled(ch, base_monster, ability, m1)
		var d2 := _cast_at_scaled(ch, base_monster, ability, m2)
		if d1 <= 0.0 and d2 <= 0.0:
			continue
		var frac: float
		if d2 > 1.5 * maxf(d1, 1.0):
			frac = (d2 - d1) / maxf(1.0, bar * (m2 - m1))
		else:
			frac = d1 / bar
		acc += frac
		samples += 1
	if samples == 0:
		return 0.0
	return acc / float(samples)

func run_ability_vs_hp():
	# #6 (user hypothesis 2026-09-02: "Magic Bolt is extremely powerful early game, I'm
	# guessing it falls off"). Damage-per-resource alone cannot answer that — what matters is
	# damage RELATIVE TO THE HEALTH BAR IT HAS TO CHEW THROUGH. An ability whose damage grows
	# 10x while monster HP grows 100x has "gone up" and still fallen off a cliff.
	# Reported as: one cast's damage as a % of a same-level NORMAL monster's max HP.
	# >=100% one-shots trash. A flat-ish row holds its power; a falling row falls off.
	var N: int = maxi(25, _audit_n)
	var sets := [
		["Fighter", "War", ["power_strike", "cleave", "devastate"]],
		["Wizard", "Mag", ["magic_bolt", "blast", "meteor"]],
		["Thief", "Trk", ["ambush", "exploit", "gambit"]],
	]
	print("
===== #6 ABILITY POWER vs MONSTER HP ACROSS THE WHOLE GAME (%d casts/cell) =====" % N)
	print("One cast's damage as %% of a SAME-LEVEL NORMAL monster's max HP, AVERAGE gear.")
	print(">=100%% one-shots trash. Falling left-to-right = the ability falls off with level.")
	print("Magic Bolt is cast at a FULL mana dump (its design case); finishers read")
	print("LOW here because their engine (Momentum/Focus/Read) starts at 0 on a single cast.")
	print("Each cast is measured against two oversized targets and read off the SLOPE, so")
	print("flat abilities are not truncated by a one-shot and %%-max-HP abilities (Exploit)")
	print("are not inflated by the dummy's size. See _ability_bar_fraction.")
	var header := "%-4s %-13s" % ["Cls", "Ability"]
	for lvl in PROGRESSION_LEVELS:
		header += "%8s" % ("L%d" % lvl)
	print(header)
	for st in sets:
		for ab in st[2]:
			var row := "%-4s %-13s" % [st[1], ab]
			for lvl in PROGRESSION_LEVELS:
				row += "%7.0f%%" % (100.0 * _ability_bar_fraction(lvl, "average", String(st[0]), String(ab), N))
			print(row)
	print("=====================================================================
")

func run_ability_efficiency():
	# #55 — measure damage-per-resource for each damage ability across classes + levels/gear.
	# The flagship question (Bolt vs Blast) is a SIMPLE-ability comparison; finishers
	# (devastate/meteor/gambit) scale up with their engine so their number here is a FLOOR.
	var N := 300
	var cells := [[10, "average"], [50, "average"], [50, "bis"], [200, "average"], [1000, "average"]]
	var sets := [
		["Fighter", "War", ["power_strike", "shield_bash", "cleave", "devastate"]],
		["Wizard", "Mag", ["magic_bolt", "blast", "meteor"]],
		["Thief", "Trk", ["ambush", "exploit", "gambit"]],
	]
	print("\n===== #55 ABILITY DAMAGE-PER-RESOURCE AUDIT (%d casts/cell) =====" % N)
	print("Per-cast on a boss-HP target; finishers (devastate/meteor/gambit) = FLOOR (engines at 0).")
	for cell in cells:
		var lvl: int = int(cell[0])
		var gear: String = String(cell[1])
		print("--- L%d %s ---   %-4s %-13s %9s %8s %8s %9s" % [lvl, gear, "Cls", "Ability", "AvgDmg", "AvgCost", "Dmg/Res", "Casts/Bar"])
		for s in sets:
			for ab in s[2]:
				var td := 0.0
				var tc := 0.0
				var tp := 0.0
				var samples := 0
				for i in range(N):
					var r = _measure_ability(lvl, gear, String(s[0]), String(ab))
					if r.cost > 0.0:
						td += r.damage
						tc += r.cost
						tp += r.pool
						samples += 1
				if samples > 0:
					var avg_cost := tc / samples
					var casts := (tp / samples) / maxf(1.0, avg_cost)  # #55 pool ÷ cost = casts per full bar
					print("               %-4s %-13s %9.0f %8.1f %8.2f %9.1f" % [s[1], ab, td / samples, avg_cost, (td / samples) / maxf(1.0, avg_cost), casts])
				else:
					print("               %-4s %-13s   (no paid casts — free/utility or unaffordable)" % [s[1], ab])
	print("=====================================================================\n")

func run_cost_solve():
	# COST-CURVE SOLVE (2026-08-25). For each character level on AVERAGE gear, sweep a
	# cost multiplier and read the MinRes% it produces — i.e. "how much pricier must the
	# card tier be at this level to restore early-game resource pressure?" The mult that
	# lands MinRes% in the target band (elite ~40-60%, boss ~20-40%) at each level IS the
	# level→cost-tier curve. L10 baseline (mult 1.0) is the early-game feel we're matching.
	var N := 70
	var levels := [10, 25, 50, 80]
	var mults := [1.0, 1.5, 2.0, 3.0, 4.0, 6.0, 8.0]
	var classes := [["Fighter", "War"], ["Thief", "Trk"], ["Wizard", "Mag"]]
	print("\n===== COST-CURVE SOLVE (avg gear, %d fights/cell) — MinRes%% per cost mult =====" % N)
	print("Target: elite ~40-60%%, boss ~20-40%%. Read the mult that lands there per level.")
	for c in classes:
		for et in ["elite", "boss"]:
			var hdr := "%-4s %-6s " % [c[1], et]
			for m in mults:
				hdr += "%9s" % ("%.1fx" % m)
			print(hdr)
			for lvl in levels:
				var row := "  L%-3d      " % lvl
				for m in mults:
					_cost_mult = m
					var tmin := 0.0
					var wins := 0
					for i in range(N):
						var r = run_fight(lvl, "average", et, 1.0, 1.0, 1.0, c[0])
						tmin += float(r.get("min_res_pct", 0.0))
						if r.win:
							wins += 1
					_cost_mult = 1.0
					row += "%9s" % ("%.0f@%d" % [tmin / N, int(100.0 * wins / N)])
				print(row)
	print("(cell = MinRes%%@Win%%)  =============================================\n")

func run_flock_chain(level: int, gear: String, klass: String, chain_len: int, et: String) -> Dictionary:
	# Flock STRESS: `chain_len` back-to-back fights on ONE character, resources NOT
	# refilled between members (only in-combat regen), buffs + engine state (momentum/
	# combo-read/focus) carried via the real preserve path. Mirrors an overworld flock
	# where you don't return to safety between kills. Headline = chain MinRes% (the
	# lowest pool% reached across the WHOLE chain): after decoupling regen (fix A) this
	# must NOT bottom out to ~0 or a flock becomes an un-counterable resource death.
	var ch = make_char(level, gear, klass)  # full resources at chain START only
	var max_res: int = maxi(1, _class_max_resource(ch, klass))
	var chain_min_res: int = _class_resource(ch, klass)
	var total_turns := 0
	var total_casts := 0
	var cleared := 0
	for m_idx in range(chain_len):
		var monster = make_monster(level, et)
		combat_mgr.start_combat(0, ch, monster)
		if not combat_mgr.active_combats.has(0):
			break
		var combat = combat_mgr.active_combats[0]
		if m_idx > 0:  # carry engine state into the next flock member
			var snap = combat_mgr.get_last_combat_engines(0)
			for k in ["momentum", "combo", "focus"]:
				if snap.has(k):
					combat[k] = snap[k]
		var turns := 0
		while turns < 400:
			if ch.current_hp <= 0 or int(monster.get("current_hp", 0)) <= 0 or combat.get("combat_ended", false):
				break
			turns += 1
			if combat.get("player_can_act", true) and ch.current_hp > 0 and int(monster.get("current_hp", 0)) > 0:
				var res0: int = _class_resource(ch, klass)
				if klass == "Thief":
					_player_act_trickster(combat, ch)
				elif klass == "Wizard":
					_player_act_mage(combat, ch)
				else:
					_player_act(combat, ch)
				if _class_resource(ch, klass) < res0:
					total_casts += 1
					if _cost_mult > 1.0:
						_drain_resource(ch, klass, int((res0 - _class_resource(ch, klass)) * (_cost_mult - 1.0)))
				chain_min_res = mini(chain_min_res, _class_resource(ch, klass))
			if ch.current_hp <= 0 or int(monster.get("current_hp", 0)) <= 0 or combat.get("combat_ended", false):
				break
			combat_mgr.process_monster_turn(combat)
		total_turns += turns
		var mwin: bool = int(monster.get("current_hp", 0)) <= 0 and ch.current_hp > 0
		combat_mgr.end_combat(0, mwin, true)  # preserve buffs/engines across the flock
		if not mwin or ch.current_hp <= 0:
			break
		cleared += 1
		# resources deliberately NOT refilled here — they carry to the next member.
	return {
		"cleared": cleared, "chain_len": chain_len,
		"survived": ch.current_hp > 0 and cleared == chain_len,
		"min_res_pct": 100.0 * float(chain_min_res) / float(max_res),
		"turns": total_turns, "casts": total_casts,
	}

func run_flock_audit():
	# Flock-stress audit (2026-08-25). K back-to-back trash fights, resources carried.
	# ChainMin% = lowest pool% over the whole chain; Clear = avg members cleared of K;
	# Thru% = fraction of chains fully cleared (survival). After fix A, ChainMin% is the
	# SAFETY floor — it must stay high enough that a flock isn't a resource death spiral.
	var N := 60
	var K := 5
	var levels := [10, 50, 80]
	var gears := ["under", "average", "bis"]
	var classes := [["Fighter", "War"], ["Thief", "Trk"], ["Wizard", "Mag"]]
	var et := "plain"  # flocks are trash mobs
	print("\n===== FLOCK STRESS AUDIT (%d chains/cell, K=%d back-to-back, no refill) =====" % [N, K])
	print("ChainMin%% = lowest pool%% across the whole chain (the safety floor for fix A).")
	print("%-4s %-4s %-8s %6s %8s %8s %8s" % ["Cls", "Lvl", "Gear", "Thru%", "Clear/K", "ChainMin%", "Casts/t"])
	for c in classes:
		for lvl in levels:
			for gear in gears:
				var thru := 0
				var tclear := 0.0
				var tmin := 0.0
				var tct := 0.0
				for i in range(N):
					var r = run_flock_chain(lvl, gear, c[0], K, et)
					if r.survived:
						thru += 1
					tclear += float(r.cleared)
					tmin += float(r.get("min_res_pct", 0.0))
					tct += float(r.get("casts", 0)) / maxf(1.0, float(r.turns))
				print("%-4s %-4d %-8s %5.0f%% %8.1f %8.0f%% %8.2f" % [
					c[1], lvl, gear, 100.0 * thru / N, tclear / N, tmin / N, tct / N])
	print("=====================================================================\n")

func run_baseline():
	# #29 holistic rebalance baseline — measures win-rate, fight length, AND
	# casts-per-fight (the resource lever) across all three classes.
	var N := 60
	var levels := [10, 50, 80]
	var gears := ["under", "average", "bis"]
	var enemies := ["plain", "elite", "boss"]
	var classes := [["Fighter", "War"], ["Thief", "Trk"], ["Wizard", "Mag"]]
	print("\n===== #29 BASELINE (%d fights/cell) =====" % N)
	print("%-4s %-4s %-8s %-7s %6s %7s %7s" % ["Cls", "Lvl", "Gear", "Enemy", "Win%", "Turns", "Casts"])
	for c in classes:
		for lvl in levels:
			for gear in gears:
				for et in enemies:
					var wins := 0
					var tt := 0
					var tc := 0
					for i in range(N):
						var r = run_fight(lvl, gear, et, 1.0, 1.0, 1.0, c[0])
						if r.win:
							wins += 1
						tt += r.turns
						tc += int(r.get("casts", 0))
					print("%-4s %-4d %-8s %-7s %5.0f%% %7.1f %7.1f" % [c[1], lvl, gear, et, 100.0 * wins / N, float(tt) / N, float(tc) / N])
	print("=========================================\n")

func run_matrix():
	var levels := [10, 30, 50, 80]
	var gears := ["under", "average", "bis"]
	var enemies := ["plain", "empowered", "elite", "boss"]
	print("\n===== REAL-CODE COMBAT SIM (%d fights/cell, Fighter + companion) =====" % FIGHTS_PER_CELL)
	print("%-6s %-9s %-10s %8s %8s %10s" % ["Lvl", "Gear", "Enemy", "WinRate", "AvgTurns", "PlyrHP%%"])
	for lvl in levels:
		for gear in gears:
			for et in enemies:
				var wins := 0
				var total_turns := 0
				for i in range(FIGHTS_PER_CELL):
					var r = run_fight(lvl, gear, et, 1.0)
					if r.win:
						wins += 1
					total_turns += r.turns
				print("%-6d %-9s %-10s %7.0f%% %8.1f" % [lvl, gear, et, 100.0*float(wins)/FIGHTS_PER_CELL, float(total_turns)/FIGHTS_PER_CELL])
	print("=====================================================================\n")

func run_hp_sweep():
	# Reverse-solve: how much monster HP is needed to hit target fight lengths.
	# For well-geared players (BiS), sweep an extra HP multiplier per enemy tier.
	var mults := [1.0, 2.0, 3.0, 4.0, 6.0, 8.0, 12.0, 16.0]
	var N := 60
	print("\n===== REVERSE-SOLVE: monster HP mult -> fight length (BiS Fighter+companion, %d fights) =====" % N)
	print("Target lengths: plain ~2-3t, empowered/elite ~6-9t, boss ~10-14t. Read the mult that hits it.")
	print("(each cell = avgTurns @ winRate%%)")
	var header := "%-14s" % "Lvl / Enemy"
	for hm in mults:
		header += "%9s" % ("%.0fx" % hm)
	print(header)
	for lvl in [30, 50, 80]:
		for et in ["plain", "empowered", "elite", "boss"]:
			var row := "%-14s" % ("L%d %s" % [lvl, et])
			for hm in mults:
				var wins := 0
				var tt := 0
				for i in range(N):
					var r = run_fight(lvl, "bis", et, hm)
					if r.win: wins += 1
					tt += r.turns
				row += "%9s" % ("%.1f@%.0f" % [float(tt)/N, 100.0*float(wins)/N])
			print(row)
	print("=================================================================================================\n")

func run_trickster_matrix():
	# v0.9.697 — validate the Trickster Combo engine (build via setups → Gambit finisher).
	var levels := [10, 30, 50, 80]
	var gears := ["under", "average", "bis"]
	var enemies := ["plain", "empowered", "elite", "boss"]
	print("\n===== TRICKSTER COMBO SIM (%d fights/cell, Thief + companion) =====" % FIGHTS_PER_CELL)
	print("%-6s %-9s %-10s %8s %8s" % ["Lvl", "Gear", "Enemy", "WinRate", "AvgTurns"])
	for lvl in levels:
		for gear in gears:
			for et in enemies:
				var wins := 0
				var total_turns := 0
				for i in range(FIGHTS_PER_CELL):
					var r = run_fight(lvl, gear, et, 1.0, 1.0, 1.0, "Thief")
					if r.win:
						wins += 1
					total_turns += r.turns
				print("%-6d %-9s %-10s %7.0f%% %8.1f" % [lvl, gear, et, 100.0*float(wins)/FIGHTS_PER_CELL, float(total_turns)/FIGHTS_PER_CELL])
	print("=====================================================================\n")

func _player_act_trickster(combat: Dictionary, ch) -> void:
	var hand: Array = combat.get("combat_hand", [])
	# OUTWIT only when the odds are actually good (chance-gated, like a real player) AND
	# energy is stocked — Outsmart now DUMPS energy to sharpen the read (+~30% at a full
	# bar). Don't burn attempts on low-odds outwits vs higher-level bosses; damage instead.
	# #55 identity pass (2026-08-27) — a Trickster is a fast, fragile assassin: vs an
	# OVER-LEVEL foe it gambles Outsmart TURN 1 (acts first, takes the shot before it can
	# get hit) — its only real path to killing something far above its level. In a roughly
	# even fight it still waits for good odds (build Read, then Outsmart) rather than coin-
	# flipping away a winnable fight.
	var _mon: Dictionary = combat.get("monster", {})
	var base_os: int = combat_mgr._outsmart_chance(ch, _mon, combat)
	var full_en: bool = ch.current_energy > int(ch.get_total_max_energy() * 0.5)
	var _overlevel: bool = int(_mon.get("level", 0)) > ch.level + 8
	if full_en and ((_overlevel and base_os >= 3) or (base_os + 30 >= 55)):
		var r = combat_mgr.process_outsmart(combat)
		if r.get("combat_ended", false):
			combat["combat_ended"] = true
			if r.get("victory", false):
				if _mon:  # outsmart win leaves monster at full HP — mark dead for the win check
					_mon["current_hp"] = 0
		return
	# ASSASSINATE (perfect_heist) - the class's kill card, and the AI never played it. Owner
	# 2026-09-05: "I'd like to know your strategies on each character type to ensure the problem
	# isn't our strategy or ability and outsmart use." It was. The curated trickster deck is
	# Analyze / Distract / Sabotage / Ambush / Assassinate / Sabotage, and this policy used only
	# ambush, sabotage, distract and gambit - holding its win condition and never spending it.
	if "perfect_heist" in hand:
		if combat_mgr.process_ability_command(0, "perfect_heist", "").get("success", false):
			return
	# TURN DENIAL as survival. Owner 2026-09-04: Analyze / Distract / Sabotage "actually skip the
	# enemies turn... I like that they skip the enemy turn at the cost of resource to help the
	# trickster survive building up their Outsmart." That is the class's defensive mechanic and
	# it was being used only as filler AFTER the damage cards, never when it was needed.
	if float(ch.current_hp) / float(maxi(1, ch.get_total_max_hp())) < 0.60:
		for ab in ["analyze", "distract", "sabotage"]:
			if ab in hand:
				if combat_mgr.process_ability_command(0, ab, "").get("success", false):
					return
	# Build Read with damage setups (these spend energy + add Read).
	for ab in ["ambush", "exploit"]:
		if ab in hand:
			if combat_mgr.process_ability_command(0, ab, "").get("success", false):
				return
	# Filler builders (debuffs still add Read, and deny the monster its turn).
	for ab in ["sabotage", "distract", "analyze"]:
		if ab in hand:
			if combat_mgr.process_ability_command(0, ab, "").get("success", false):
				return
	# Low Read but Gambit in hand → chip damage.
	if "gambit" in hand:
		if combat_mgr.process_ability_command(0, "gambit", "").get("success", false):
			return
	combat_mgr.process_attack(combat)

func run_mage_matrix():
	# v0.9.697 — validate the Mage Focus ramp (spells build Focus → Meteor discharges).
	var levels := [10, 30, 50, 80]
	var gears := ["under", "average", "bis"]
	var enemies := ["plain", "empowered", "elite", "boss"]
	print("\n===== MAGE FOCUS SIM (%d fights/cell, Wizard + companion) =====" % FIGHTS_PER_CELL)
	print("%-6s %-9s %-10s %8s %8s" % ["Lvl", "Gear", "Enemy", "WinRate", "AvgTurns"])
	for lvl in levels:
		for gear in gears:
			for et in enemies:
				var wins := 0
				var total_turns := 0
				for i in range(FIGHTS_PER_CELL):
					var r = run_fight(lvl, gear, et, 1.0, 1.0, 1.0, "Wizard")
					if r.win:
						wins += 1
					total_turns += r.turns
				print("%-6d %-9s %-10s %7.0f%% %8.1f" % [lvl, gear, et, 100.0*float(wins)/FIGHTS_PER_CELL, float(total_turns)/FIGHTS_PER_CELL])
	print("=====================================================================\n")

func _player_act_mage(combat: Dictionary, ch) -> void:
	var hand: Array = combat.get("combat_hand", [])
	var focus: int = int(combat.get("focus", 0))
	# FORCEFIELD - the mage's shield, and this policy never cast it. A glass cannon that never
	# raises its guard measures as far more fragile than the class actually is, which is exactly
	# the kind of instrument fault that gets read as a balance problem.
	if "forcefield" in hand and ch.get_buff_value("shield") <= 0 and int(combat.get("forcefield_shield", 0)) <= 0 and ch.current_hp < int(ch.get_total_max_hp() * 0.70):
		if combat_mgr.process_ability_command(0, "forcefield", "").get("success", false):
			return
	# #36 — Overload before a burst when healthy (glass-cannon combo): sear HP to buff the
	# next spell. Gated on high HP + no active damage buff so it can't loop or suicide.
	if "overload" in hand and ch.get_buff_value("damage") <= 0 and ch.current_hp > int(ch.get_total_max_hp() * 0.55) and (("meteor" in hand and focus >= 2) or "magic_bolt" in hand):
		if combat_mgr.process_ability_command(0, "overload", "").get("success", false):
			return
	# #36 — Frost Nova as a Focus-builder + survival chill when the foe isn't chilled yet.
	if "frost_nova" in hand and int(combat.get("enemy_distracted", 0)) < 20 and focus < 3:
		if combat_mgr.process_ability_command(0, "frost_nova", "").get("success", false):
			return
	# Discharge the ramp with Meteor once Focus is built.
	if focus >= 3 and "meteor" in hand:
		if combat_mgr.process_ability_command(0, "meteor", "").get("success", false):
			return
	# #55 — Magic Bolt is now the mage's big burst nuke (rebuilt multiplier). A real
	# mage opens with it while mana is stocked (dumps ~25% pool for a huge hit), then
	# falls to Blast for efficient sustain. Meteor discharges the Focus ramp above.
	if "magic_bolt" in hand and ch.current_mana > int(ch.get_total_max_mana() * 0.25):
		var amt := str(max(1, int(ch.get_total_max_mana() * 0.25)))
		if combat_mgr.process_ability_command(0, "magic_bolt", amt).get("success", false):
			return
	# Efficient sustain / Focus ramp (each +1 Focus).
	if "blast" in hand:
		if combat_mgr.process_ability_command(0, "blast", "").get("success", false):
			return
	if "meteor" in hand:
		if combat_mgr.process_ability_command(0, "meteor", "").get("success", false):
			return
	combat_mgr.process_attack(combat)

func _tier_for_level(lvl: int) -> int:
	# Standard tier bands (mirror monster/world tiering) for picking gear bases.
	if lvl <= 5: return 1
	elif lvl <= 15: return 2
	elif lvl <= 30: return 3
	elif lvl <= 50: return 4
	elif lvl <= 100: return 5
	elif lvl <= 500: return 6
	elif lvl <= 2000: return 7
	elif lvl <= 5000: return 8
	return 9

# #5 CALIBRATION knobs for the "average" (representative-player) gear model. Solved
# against 11 real saved characters by `-- gear_solve`, not hand-picked.
# Vars, not consts, so `-- gear_solve` can sweep them and pick from data.
# #5 (2026-09-02): the old knob SUBTRACTED a fixed number of levels ("gear is 3 levels
# behind you"). Measured against real saved characters that is the wrong SHAPE, not just
# the wrong number — mean item level tracks character level PROPORTIONALLY (Sylvio L6:
# 0.62x, ABtest L4: 1.00x, Test001 L5: 1.47x, Dexto L45: 1.10x), and real players wear
# gear found ABOVE their level in higher-tier zones. A fixed lag of 3 is -50% at L6 and
# -7% at L45, so it distorted the low end and did nothing at the high end.
# Solved by `-- gear_solve` against the geared band AND independently confirmed by direct
# observation: mean(item level / character level) across the geared real characters is 0.86,
# and a "geared" character has 5+ slots filled, so the empty chance is ~0. The fit and the
# measurement agree, which is the only reason to trust a 2-character sample this far.
# CAVEAT: n=2 geared characters (L6 and L45). This is provisional — re-run `-- gear_solve`
# as more real characters accumulate. A second combination (ratio 1.30 / empty 0.30) scores
# identically and is pure overfit; it is rejected because nothing observed supports it.
var _gear_avg_level_ratio: float = 0.85  # item level as a fraction of character level
var _gear_avg_empty_chance: float = 0.0  # chance a slot is simply unfilled
# Companion modelling for the companion audit: none / l1 / match (companion level = char
# level) / x10 (a heavily over-levelled companion).
# 2026-09-04 — the REFERENCE PLAYER HAS NO COMPANION. Owner: "it should likely be removed from
# the sim power measurement as companions are the way players progress and eventually break the
# balance through their investment into their companions."
#
# That settles a tension the model carried all along. A companion is the INVESTMENT axis: it is
# MEANT to outgrow the curve, and the point of levelling one is that it eventually trivialises
# content. Calibrating monsters against a player who has one sizes the game against the reward
# rather than the baseline — and it is why every companion change so far forced a full
# recalibration.
#
# With the companion outside the measurement, monsters are sized against what a player brings on
# their own and a companion is straightforwardly a bonus on top. Companion changes stop
# invalidating the curve, which is what makes them shippable without the 25-minute chain.
#
# The audits that EXIST to measure companions opt back in explicitly — see the calls to
# `_use_companions_for_this_audit()` in each.
var _companion_mode: String = "none"

func _use_companions_for_this_audit(mode: String = "match") -> void:
	"""Opt this audit back into companions. The dispatcher resets the mode to the reference
	player's before every audit, so an opt-in cannot leak into the next one."""
	_companion_mode = mode
# Fights per cell for the progression/companion sweeps. Overridable as `-- n=200 progression`
# because conclusions about the whole game deserve tighter error bars than a spot check.
var _audit_n: int = 40
var _curve_cache: Dictionary = {}
# Calibration override: while set, make_monster stamps these stats onto the generated
# monster so a candidate can be tested in REAL fights before it is written to the curve.
var _cal_override: Dictionary = {}

func _roll_slot_rarity(tier: int) -> String:
	# Sample one slot's rarity from the game's OWN drop table for this tier, so the sim's
	# idea of "what a player is wearing" is the distribution the game actually produces.
	if randf() < _gear_avg_empty_chance:
		return ""
	var weights: Dictionary = drop_tables.RARITY_WEIGHTS.get(clampi(tier, 1, 9), {})
	if weights.is_empty():
		return "uncommon"
	var total := 0.0
	for k in weights.keys():
		total += float(weights[k])
	var pick := randf() * total
	for k in weights.keys():
		pick -= float(weights[k])
		if pick <= 0.0:
			return String(k)
	return "uncommon"

# How many drops a "focused" player is modelled as sifting through per slot. 8 is roughly the
# point where the best-of sample stops improving much for a 1-in-10 affix.
const FOCUS_ROLLS := 8

static func _focus_stats_for(klass: String) -> Array:
	"""Everything a player of this class would actually chase.

	Includes the CHASE affixes, not just the plain resource one: "of Refresh" (mana_on_hit) and
	the +ability-rank rolls are epic+ only, so they are exactly what a mage farms for. Owner:
	"What about the monsters that drop chase items for mages?" - drops are not class-targeted
	(nothing in drop_tables looks at class), but the chase POOL is rarity-gated, so a focused
	player reaches them by farming epic+ rather than by farming a particular monster."""
	if klass in ["Wizard", "Sorcerer", "Sage"]:
		return ["mana_bonus", "mana_on_hit", "ability_rank_mage_dmg", "ability_rank_magic_bolt"]
	if klass in ["Thief", "Ranger", "Ninja"]:
		return ["energy_bonus", "energy_on_hit", "ability_rank_trickster_dmg"]
	return ["stamina_bonus", "stamina_on_hit", "ability_rank_warrior_dmg"]

static func _affix_of(item: Dictionary, stat: String) -> int:
	var aff = item.get("affixes", {})
	if aff is Dictionary:
		return int(aff.get(stat, 0))
	return 0

static func _focus_score(item: Dictionary, wants: Array) -> float:
	"""How much a focused player wants THIS drop.

	2026-09-04 — the first version scored the target affix ALONE, and measured every class as
	WORSE with focused gear while casts/turn rose. That is not a finding, it is the signature of
	the model: "best mana roll" also means "throw away the attack and defence rolls", which no
	player does. A kit is only focused at the MARGIN.

	So: overall affix weight is the base score, and the wanted stats are counted a second time on
	top. A candidate wins by carrying what you want WITHOUT being a weaker item overall."""
	var total := 0.0
	var aff = item.get("affixes", {})
	if aff is Dictionary:
		for k in aff.keys():
			var v = aff[k]
			if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
				total += float(v)
	# The item's own base power matters as much as its affixes.
	total += float(item.get("attack", 0)) + float(item.get("defense", 0))
	for w in wants:
		total += float(_affix_of(item, String(w)))
	return total

func _apply_class_kit(ch, klass: String, glevel: int, best_of: int, max_pieces: int = 99) -> void:
	"""Equip the archetype's own kit, generated by the game's own Hoarder generators.

	These bases (ring_arcane / amulet_mystic / ring_shadow / boots_swift / amulet_evasion /
	weapon_warlord / shield_bulwark) are the ONLY source of mana_regen, energy_regen,
	stamina_regen, meditate_bonus and flee_bonus, and they exist in no ordinary drop table. A sim
	that models gear from EQUIPMENT_BASES alone therefore models a player who has never farmed
	their class - which is every class measurement taken before 2026-09-04.

	`best_of` > 1 sifts several real drops per slot, modelling a player who farms with a stat in
	mind. It never invents a roll: every candidate is one the drop system produced."""
	var wants := _focus_stats_for(klass)
	var path := "warrior"
	if klass in ["Wizard", "Sorcerer", "Sage"]:
		path = "mage"
	elif klass in ["Thief", "Ranger", "Ninja"]:
		path = "trickster"
	# Draw enough times to see each of the kit's bases, then keep the best per slot.
	var by_slot := {}
	for _i in range(maxi(6, best_of * 3)):
		var it
		match path:
			"mage": it = drop_tables.generate_mage_gear(glevel)
			"trickster": it = drop_tables.generate_trickster_gear(glevel)
			_: it = drop_tables.generate_warrior_gear(glevel)
		if not (it is Dictionary) or it.is_empty():
			continue
		var slot := String(it.get("type", "")).split("_")[0]
		if slot == "":
			continue
		if not by_slot.has(slot) or _focus_score(it, wants) > _focus_score(by_slot[slot], wants):
			by_slot[slot] = it
	# `max_pieces` caps how much of the kit the player actually has. The reference player farms a
	# piece or two; a "kit" player has finished the set. Which slots they got is left to the draw.
	#
	# 2026-09-04 — a kit piece is only WORN if it beats what is already in the slot. The first
	# version equipped it unconditionally, so an ordinary roll that happened to produce a rare or
	# epic in that slot was thrown away for an uncommon Warlord Blade. No player does that, and it
	# made the reference player erratically WEAKER by level rather than stronger — which the whole
	# curve was then calibrated against. It showed up as normals landing at 20% win at L250
	# against a 60% target while L1 and L10 were fine.
	#
	# Scored with the same `_focus_score` used for choosing between drops, so "better" means
	# better overall and not merely better at the one stat.
	var slots := by_slot.keys()
	slots.shuffle()
	var worn := 0
	for slot2 in slots:
		if worn >= max_pieces:
			break
		var cur = ch.equipped.get(slot2, null)
		if cur is Dictionary and not cur.is_empty():
			if _focus_score(cur, wants) >= _focus_score(by_slot[slot2], wants):
				continue   # what they already have is better; a player keeps it
		ch.equipped[slot2] = by_slot[slot2]
		worn += 1

func make_char(level: int, gear: String, klass: String = "Fighter", race: String = "Human"):
	var ch = CharacterScript.new()
	ch.initialize("SimChar", klass, race)
	for i in range(level - 1):
		ch.level_up()
	# #55 (2026-08-26) — allocate every level-up stat point into the class's primary
	# stat so NAKED resource pools (max_mana / max_stamina / max_energy, which drive
	# the new absolute cost model) scale with level like a real focused build. The sim
	# previously left points unspent, artificially flattening the pools.
	var _primary := "strength"
	if klass in ["Wizard", "Sorcerer", "Sage"]:
		_primary = "intelligence"
	elif klass in ["Thief", "Ranger", "Ninja"]:
		_primary = "dexterity"
	while ch.unspent_stat_points > 0:
		ch.spend_stat_point(_primary)
	# Gear model. #5 CALIBRATION (2026-09-02) — "average" no longer forces one hand-picked
	# rarity on all seven slots. A real player's kit is a MIX: some slots carry a lucky rare,
	# some a common they never replaced, some sit empty. Uniform rarity is what made the sim
	# hot (measured +44% ATK / +69% pool vs 11 real saved characters). "average" now ROLLS
	# each slot's rarity from the game's own RARITY_WEIGHTS for that tier, so the model
	# tracks the real drop distribution and follows it automatically when drop rates change.
	# "under" and "bis" stay deliberate uniform bookends (a poor kit / a chase kit).
	var rarity := "common"
	var glevel := level
	var roll_rarity := false
	match gear:
		"under":
			rarity = "uncommon"
			glevel = max(1, level - 8)
		"starter2", "starter4", "starter7", "starter7u", "starter7c":
			# Candidate STARTER KITS, to size the fix by measurement rather than by feel.
			# starter2 = weapon + armour; starter4 = + shield and helm; starter7 = every slot.
			# starter7u raises the kit to UNCOMMON; starter7c keeps common but adds a hatched
			# companion, which is what the starter egg becomes. Sized at the character's own level,
			# which is what a creation grant would realistically hand out.
			rarity = "uncommon" if gear == "starter7u" else "common"
		"gearless":
			# EVERY SLOT EMPTY. What a character created TODAY actually starts with: the
			# Pathfinder starter chain was retired 2026-09-03 and item 7, the tutorial meant to
			# replace it, is not built. Reported from live 2026-09-04: two players on new
			# characters, "death after death".
			pass
		"average", "average_nokit":
			roll_rarity = true
			glevel = max(1, int(round(level * _gear_avg_level_ratio)))
		"bis":
			rarity = "epic"
		# 2026-09-03 — an explicit RARITY LADDER, every slot filled at one rarity and at the
		# character's own level. The existing three are not a ladder and comparing them as one
		# gave a wrong answer: `average` deliberately leaves some slots EMPTY to model a real
		# player's patchy kit, so it carries fewer affixes than `under` (8.6 vs 18.8 at L10)
		# and measured as a downgrade. That is a difference of distribution, not of rung, and
		# reading it as "gear progression is flat" was unsound. These rungs differ in exactly
		# one variable, which is what a ladder has to do to be measurable.
		"common", "uncommon", "rare", "epic", "legendary":
			rarity = gear
		"kit", "focus":
			# 2026-09-04 — "average" draws only from EQUIPMENT_BASES, which does NOT contain the
			# class kit (ring_arcane, weapon_warlord, ...). Those come from Hoarder monsters alone,
			# so every class number the sim has ever produced was a player who had NEVER farmed
			# their own archetype's gear. Owner: "Ensure when looking at the sim it's accounting for
			# ALL equipment properly now from your audit as well as players being able to somewhat
			# focus on farming certain stats on their equipment."
			#   kit   = average roll PLUS the class kit, affixes unsorted
			#   focus = the same, but sifting several real drops per slot for the stats that class
			#           actually wants (see _focus_score - at the MARGIN, never at the cost of
			#           overall item power)
			roll_rarity = true
			glevel = max(1, int(round(level * _gear_avg_level_ratio)))
		"focus_epic":
			# Epic is the floor at which CHASE affixes ("of Refresh", +ability rank) can roll at
			# all, so this is the rung where "farming for mage chase items" is even possible.
			rarity = "epic"
	# #70 CALIBRATION — mirror the REAL drop path: use a TIER-APPROPRIATE base per slot
	# (weapon_rusty / armor_chain / …) instead of forcing "<slot>_artifact". The old artifact
	# bases gave artifact-tier stats even at "rare" rarity, inflating pools ~2.2x vs a real
	# character (test02 L6 mage: real 121 mana vs the sim's old 261). Ground-truth calibrated.
	var gtier: int = _tier_for_level(glevel)
	var starter_slots: Array = []
	if gear == "starter2":
		starter_slots = ["weapon", "armor"]
	elif gear == "starter4":
		starter_slots = ["weapon", "armor", "shield", "helm"]
	elif gear == "starter7" or gear == "starter7u" or gear == "starter7c":
		starter_slots = []   # every slot - a complete but basic kit
	for slot in SLOTS:
		# 2026-09-04 — "gearless" must actually leave every slot EMPTY. The first version only
		# `pass`ed in the match, so it fell through to the defaults (common, at level) and filled
		# all seven slots. It measured a fully-common-geared character and called it gearless,
		# which made the candidate starter kits look WORSE than having nothing. Third gear-model
		# rung to be wrong this session: check what a rung actually equips before believing it.
		if gear == "gearless":
			continue
		if not starter_slots.is_empty() and not (slot in starter_slots):
			continue   # a starter kit fills only the named slots; the rest stay empty
		var base_type := ""
		# Find this slot's base at the char's tier; fall back down tiers if the slot is
		# absent at that tier (e.g. amulet only appears from T3).
		for t in range(gtier, 0, -1):
			for entry in drop_tables.EQUIPMENT_BASES.get(t, []):
				if String(entry.get("item_type", "")).begins_with(slot):
					base_type = String(entry["item_type"])
					break
			if base_type != "":
				break
		if base_type == "":
			continue  # no base for this slot at/below tier → leave the slot empty (realistic)
		var slot_rarity: String = _roll_slot_rarity(gtier) if roll_rarity else rarity
		if slot_rarity == "":
			continue  # rolled an empty slot — a real player has gaps
		var item = drop_tables._generate_item({"item_type": base_type}, glevel, slot_rarity)
		# 2026-09-04 — "focus" models a player who FARMS FOR THE RIGHT AFFIX rather than wearing
		# whatever dropped. Owner: "I'd be suspicious of if your data on mages is accounting for
		# them focusing getting equipment with high MP and mp regen items or ignoring those."
		#
		# It was not: `_generate_item` rolls affixes at random, and the class's own resource is
		# only ~1 in 10 of the pool, so `average` measures an UNSORTED kit. Note also that there is
		# no mana_regen affix on general gear at all - regen comes from companions and set procs -
		# so "high MP and MP regen items" is only half-reachable through this path.
		#
		# Deliberately NOT hand-written stats: it generates several candidates the drop system
		# really produces and keeps the best for the target affix. Nothing here is a number the
		# game cannot roll.
		if gear == "focus" or gear == "focus_epic":
			var wants := _focus_stats_for(klass)
			var best_score := _focus_score(item, wants)
			for _try in range(FOCUS_ROLLS - 1):
				var alt = drop_tables._generate_item({"item_type": base_type}, glevel, slot_rarity)
				if alt is Dictionary and not alt.is_empty():
					var alt_score := _focus_score(alt, wants)
					if alt_score > best_score:
						best_score = alt_score
						item = alt
		if item is Dictionary and not item.is_empty():
			ch.equipped[slot] = item
	# The CLASS KIT, from the same generators the Hoarder monsters call. Nothing invented: these
	# are literally the items a Minotaur / Wraith / Mimic drops.
	if gear in ["kit", "focus", "focus_epic"]:
		_apply_class_kit(ch, klass, glevel, FOCUS_ROLLS if gear != "kit" else 1, 99)
	elif gear == "average":
		# THE REFERENCE PLAYER, defined by the owner 2026-09-04: "a player with a few pieces of
		# gear that are above average and a few below. Once we've made class specific gear
		# obtainable then we should expect that they target farm a piece or two of that every so
		# often."
		#
		# The first half was already true - `average` rolls each slot's rarity from the game's own
		# weights and leaves some slots empty, which is what "a few above, a few below" means. The
		# second half is new: A PIECE OR TWO of the class kit, not the whole set. That is the
		# difference between a player who farms occasionally and one who has finished farming.
		#
		# Changing what "average" MEANS rather than adding a fourth rung: 56 call sites use it, and
		# the reference player should be one definition that every audit inherits, not a flag each
		# one has to remember to pass. `average_nokit` keeps the old model so pre-2026-09-04
		# numbers stay comparable.
		_apply_class_kit(ch, klass, glevel, 1, 1 + (randi() % 2))

	# #5 CALIBRATION (2026-09-02) — the companion used to be INVENTED: a hand-written
	# bonus block {attack 10, hp 5, mana 3, wisdom 2, speed 5} that exists on no real
	# companion. Every real one carries 1-2 small bonuses from drop_tables.COMPANION_DATA
	# (Dexto's L45 Ogre: attack 5, hp_bonus 3). The sim was handing every character a
	# companion 2-4x stronger than the game can produce, on top of the gear inflation.
	# Now: draw a REAL companion of the tier a player would plausibly have, from the game's
	# own table. "under" gets none — a third of real saved characters have no companion.
	if gear != "under" and gear != "gearless" and (not gear.begins_with("starter") or gear == "starter7c") and _companion_mode != "none":
		var comp_tier: int = clampi(1 + int(level / 12.0), 1, 9)
		var candidates: Array = []
		for mtype in drop_tables.COMPANION_DATA.keys():
			var cd: Dictionary = drop_tables.COMPANION_DATA[mtype]
			if int(cd.get("tier", 1)) == comp_tier:
				candidates.append(mtype)
		if candidates.is_empty():
			candidates = ["Wolf"]
		var pick: String = String(candidates[randi() % candidates.size()])
		var pick_data: Dictionary = drop_tables.COMPANION_DATA.get(pick, {})
		ch.active_companion = {
			"id": "sim_comp", "monster_type": pick,
			"name": String(pick_data.get("companion_name", pick)),
			"tier": int(pick_data.get("tier", 1)),
			"level": (1 if _companion_mode == "l1" else (level * 10 if _companion_mode == "x10" else level)),
			"xp": 0,
			"bonuses": (pick_data.get("bonuses", {}) as Dictionary).duplicate(),
			"variant": "Normal", "sub_tier": 1, "border_tier": 1,
		}
	ch.current_hp = ch.get_total_max_hp()
	# Enter combat at FULL resources — in real play, out-of-combat regen tops the
	# pool between fights. (level_up/equip raise MAX but don't refill current, and
	# make_char only topped HP — leaving resources at the pre-gear base, which
	# distorted MinRes%/EndRes%.)
	ch.current_stamina = ch.get_total_max_stamina()
	ch.current_mana = ch.get_total_max_mana()
	ch.current_energy = ch.get_total_max_energy()
	return ch

func make_monster(level: int, et: String, extra_hp_mult: float = 1.0) -> Dictionary:
	# #5 (2026-09-02) — was hardcoded to "Orc" at every level. An Orc is a TIER-2 monster,
	# so at L500+ the sim was fighting a low-tier creature stretched far above its home tier
	# instead of the tier-appropriate content a real player meets there. That made the whole
	# high-level half of any sweep a measurement of the wrong monster. Now uses the game's
	# own selection (select_monster_type by level, inside generate_monster), so the enemy is
	# whatever the game would actually spawn at that level.
	var m = monster_db.generate_monster(level, level)
	# #6 (2026-09-02) — role multipliers come from monster_database.ROLE_TARGETS, the same
	# source the game uses, instead of being mirrored by hand here. The old mirrored constants
	# (2.2 / 3.5 / 5.0) drifted from the game whenever either side was tuned, and they encoded
	# the pre-reference-model inflation.
	if et in ["empowered", "elite", "boss"]:
		var rm: Dictionary = monster_db.role_multipliers(et)
		m["max_hp"] = int(m.get("max_hp", 1) * float(rm.hp_mult))
		m["strength"] = int(m.get("strength", 1) * float(rm.str_mult))
		m["defense"] = int(m.get("defense", 1) * maxf(1.0, float(rm.str_mult)))
		# 2026-09-03 — STAMP THE ROLE FLAG, not just the stats. The sim was building a monster
		# with elite numbers and normal flags, so anything the game keys off the flag rather
		# than the stat line was invisible here: the new per-role Outsmart penalty measured as
		# having no effect at all, and boss-only damage bonuses, empowered mod handling and
		# role-gated loot were all being measured against the wrong monster too.
		m["is_empowered"] = (et == "empowered")
		m["is_elite"] = (et == "elite")
		m["is_boss"] = (et == "boss")
	if extra_hp_mult != 1.0:
		m["max_hp"] = int(m.get("max_hp", 1) * extra_hp_mult)
	if not _cal_override.is_empty() and int(_cal_override.get("level", -1)) == level:
		m["max_hp"] = int(_cal_override.get("hp", m.get("max_hp", 1)))
		m["strength"] = int(_cal_override.get("str", m.get("strength", 1)))
	m["current_hp"] = m.get("max_hp", 1)
	return m

# Which warrior strategy to run. Owner 2026-09-05: "Attempt different strategies and find the
# most efficient and build on those." Hand-written policies are guesses; `polytest` runs these
# head to head on the SAME grown characters and lets the win rate choose.
var _warrior_policy := "buff_first"

func _player_act(combat: Dictionary, ch) -> void:
	match _warrior_policy:
		"damage_first": _warrior_damage_first(combat, ch)
		"defensive": _warrior_defensive(combat, ch)
		"momentum_hold": _warrior_momentum_hold(combat, ch)
		_: _warrior_buff_first(combat, ch)


func _warrior_damage_first(combat: Dictionary, ch) -> void:
	# No setup at all - biggest affordable hit every turn. The control: if buffs are not paying
	# for the turns they cost, this beats everything else.
	var hand: Array = combat.get("combat_hand", [])
	var mom: int = int(combat.get("momentum", 0))
	if mom >= 4 and "devastate" in hand:
		if combat_mgr.process_ability_command(0, "devastate", "").get("success", false):
			return
	for ab in ["cleave", "power_strike", "shield_bash"]:
		if ab in hand:
			if combat_mgr.process_ability_command(0, ab, "").get("success", false):
				return
	combat_mgr.process_attack(combat)


func _warrior_defensive(combat: Dictionary, ch) -> void:
	# Buff uptime PLUS a reaction: when the fight turns, spend the turn on mitigation rather
	# than trading. The buff_first policy never reacts to being hurt at all.
	var hand: Array = combat.get("combat_hand", [])
	var mom: int = int(combat.get("momentum", 0))
	var hurt: bool = ch.current_hp < int(ch.get_total_max_hp() * 0.50)
	if hurt:
		for ab in ["iron_skin", "fortify"]:
			if ab in hand and ch.get_buff_value("damage_reduction" if ab == "iron_skin" else "defense") <= 0:
				if combat_mgr.process_ability_command(0, ab, "").get("success", false):
					return
	if "iron_skin" in hand and ch.get_buff_value("damage_reduction") <= 0:
		if combat_mgr.process_ability_command(0, "iron_skin", "").get("success", false):
			return
	if "fortify" in hand and ch.get_buff_value("defense") <= 0:
		if combat_mgr.process_ability_command(0, "fortify", "").get("success", false):
			return
	if mom >= 4 and "devastate" in hand:
		if combat_mgr.process_ability_command(0, "devastate", "").get("success", false):
			return
	for ab in ["cleave", "shield_bash", "power_strike"]:
		if ab in hand:
			if combat_mgr.process_ability_command(0, ab, "").get("success", false):
				return
	combat_mgr.process_attack(combat)


func _warrior_momentum_hold(combat: Dictionary, ch) -> void:
	# Bank Momentum harder and cash a bigger Devastate, using the cheapest builder to get there.
	var hand: Array = combat.get("combat_hand", [])
	var mom: int = int(combat.get("momentum", 0))
	if "iron_skin" in hand and ch.get_buff_value("damage_reduction") <= 0:
		if combat_mgr.process_ability_command(0, "iron_skin", "").get("success", false):
			return
	if mom >= 6 and "devastate" in hand:
		if combat_mgr.process_ability_command(0, "devastate", "").get("success", false):
			return
	for ab in ["shield_bash", "power_strike", "cleave"]:
		if ab in hand:
			if combat_mgr.process_ability_command(0, ab, "").get("success", false):
				return
	if mom >= 1 and "devastate" in hand:
		if combat_mgr.process_ability_command(0, "devastate", "").get("success", false):
			return
	combat_mgr.process_attack(combat)


func _warrior_buff_first(combat: Dictionary, ch) -> void:
	var hand: Array = combat.get("combat_hand", [])
	var mom: int = int(combat.get("momentum", 0))
	# #55 identity pass (2026-08-27) — a real Warrior is a DEFENSIVE bruiser: keep its
	# mitigation buffs UP (Iron Skin = damage_reduction, Fortify = defense) so it's the
	# safest in long fights. Recast when they lapse (models buff uptime, which the old
	# sim ignored — it only cast damage buffs, so the audit under-rated Warrior tankiness).
	if "iron_skin" in hand and ch.get_buff_value("damage_reduction") <= 0:
		if combat_mgr.process_ability_command(0, "iron_skin", "").get("success", false):
			return
	if "fortify" in hand and ch.get_buff_value("defense") <= 0:
		if combat_mgr.process_ability_command(0, "fortify", "").get("success", false):
			return
	# Opportunistic damage buff (once per fight): buff early for uptime (also builds Momentum).
	if not combat.get("_sim_buffed", false):
		for b in WARRIOR_BUFFS:
			if b in hand:
				var rb = combat_mgr.process_ability_command(0, b, "")
				if rb.get("success", false):
					combat["_sim_buffed"] = true
					return
	# v0.9.696 — Momentum play: hold Devastate until Momentum is high, unleash the finisher.
	if mom >= 4 and "devastate" in hand:
		# Devastate is now a REAL dump in combat_manager (no sim emulation needed).
		if combat_mgr.process_ability_command(0, "devastate", "").get("success", false):
			return
	# Build with the best affordable BUILDER in hand (Devastate excluded here).
	for ab in ["cleave", "shield_bash", "power_strike"]:
		if ab in hand:
			if combat_mgr.process_ability_command(0, ab, "").get("success", false):
				return
	# If only Devastate is available and we have some Momentum, spend it (beats a basic hit).
	if mom >= 1 and "devastate" in hand:
		if combat_mgr.process_ability_command(0, "devastate", "").get("success", false):
			return
	# Out of resource / no castable card → basic attack (also regens + builds Momentum? no).
	combat_mgr.process_attack(combat)

func run_fight(level: int, gear: String, et: String, extra_hp_mult: float = 1.0, player_dmg_scale: float = 1.0, monster_dmg_scale: float = 1.0, klass: String = "Fighter", monster_level: int = -1, race: String = "Human") -> Dictionary:
	# player_dmg_scale/monster_dmg_scale < 1.0 simulate a rebalanced damage profile
	# (e.g. Momentum gating the burst → lower avg player DPS) by giving back a
	# fraction of the damage dealt/taken each turn — the reverse-solve knobs.
	# monster_level > 0 pits the player (at `level`) against an OVER/under-level monster.
	var ch = make_char(level, gear, klass, race)
	var monster = make_monster(monster_level if monster_level > 0 else level, et, extra_hp_mult)
	var max_hp: int = ch.get_total_max_hp()
	combat_mgr.start_combat(0, ch, monster)
	if not combat_mgr.active_combats.has(0):
		return {"win": false, "turns": 0}
	var combat = combat_mgr.active_combats[0]
	var turns := 0
	var casts := 0  # #29 — count ability casts (resource decreased this turn = a cast, not a basic attack)
	# Resource-economy telemetry: how far the pool is actually pushed over the fight.
	var max_res: int = maxi(1, _class_max_resource(ch, klass))
	var min_res: int = _class_resource(ch, klass)
	var min_hp_pct := 100.0  # #55 monster-challenge audit — lowest HP% reached (danger telemetry)
	while turns < 400:
		if ch.current_hp <= 0 or int(monster.get("current_hp", 0)) <= 0 or combat.get("combat_ended", false):
			break
		turns += 1
		if combat.get("player_can_act", true) and ch.current_hp > 0 and int(monster.get("current_hp", 0)) > 0:
			var mhp0: int = int(monster.get("current_hp", 0))
			var res0: int = _class_resource(ch, klass)
			match ch.get_class_path():
				"trickster": _player_act_trickster(combat, ch)
				"mage": _player_act_mage(combat, ch)
				_: _player_act(combat, ch)
			if _class_resource(ch, klass) < res0:
				casts += 1
				if _cost_mult > 1.0:
					_drain_resource(ch, klass, int((res0 - _class_resource(ch, klass)) * (_cost_mult - 1.0)))
			min_res = mini(min_res, _class_resource(ch, klass))
			if player_dmg_scale < 1.0:
				var dealt: int = mhp0 - int(monster.get("current_hp", 0))
				if dealt > 0:
					var giveback: int = int(dealt * (1.0 - player_dmg_scale))
					monster["current_hp"] = min(int(monster.get("max_hp", 1)), int(monster.get("current_hp", 0)) + giveback)
		if ch.current_hp <= 0 or int(monster.get("current_hp", 0)) <= 0 or combat.get("combat_ended", false):
			break
		var php0: int = ch.current_hp
		combat_mgr.process_monster_turn(combat)
		if monster_dmg_scale < 1.0:
			var taken: int = php0 - ch.current_hp
			if taken > 0:
				ch.current_hp = min(max_hp, ch.current_hp + int(taken * (1.0 - monster_dmg_scale)))
		min_hp_pct = minf(min_hp_pct, 100.0 * float(maxi(0, ch.current_hp)) / float(max_hp))
	var win: bool = int(monster.get("current_hp", 0)) <= 0 and ch.current_hp > 0
	var end_res: int = _class_resource(ch, klass)
	combat_mgr.end_combat(0, win, false)
	return {
		"win": win, "turns": turns, "casts": casts,
		"min_res_pct": 100.0 * float(min_res) / float(max_res),
		"end_res_pct": 100.0 * float(end_res) / float(max_res),
		"min_hp_pct": min_hp_pct,
		"max_res": max_res,
	}

# #5 (2026-09-02) — these three used to re-derive the archetype by string-matching the
# exact class ("Thief" / "Wizard", else stamina), so the other six classes silently read
# the WRONG pool: a Sorcerer's cast-count was measured against its stamina bar. They now
# ask the character, which is the one place the game itself decides (get_class_path).
# The `klass` argument is kept for call-site compatibility and deliberately unused.
func _class_resource(ch, _klass: String = "") -> int:
	match ch.get_class_path():
		"trickster": return int(ch.current_energy)
		"mage": return int(ch.current_mana)
		_: return int(ch.current_stamina)

func _drain_resource(ch, _klass: String, amt: int) -> void:
	# Subtract extra resource (cost-tier emulation), floored at 0.
	if amt <= 0:
		return
	match ch.get_class_path():
		"trickster": ch.current_energy = maxi(0, int(ch.current_energy) - amt)
		"mage": ch.current_mana = maxi(0, int(ch.current_mana) - amt)
		_: ch.current_stamina = maxi(0, int(ch.current_stamina) - amt)

func _class_max_resource(ch, _klass: String = "") -> int:
	match ch.get_class_path():
		"trickster": return int(ch.get_total_max_energy())
		"mage": return int(ch.get_total_max_mana())
		_: return int(ch.get_total_max_stamina())

func run_design_solve():
	# Reverse-solve the DESIGN numbers: what player-damage% × monster-damage% give
	# the target fight lengths + win-rates → tells us the avg per-turn damage
	# Momentum must produce (and how much monster damage must soften).
	var N := 80
	var pds := [1.0, 0.5, 0.33, 0.25]
	var mds := [1.0, 0.75, 0.5]
	print("\n===== DESIGN-SOLVE: player dmg%% × monster dmg%% -> avgTurns@win (L50 BiS Fighter) =====")
	print("Targets: elite ~6-9t, boss ~10-14t at ~85-90%% win. Find the combo that lands there.")
	for et in ["elite", "boss"]:
		print("-- %s (L50 BiS) --" % et)
		var hdr := "%-12s" % "plyDmg\\monDmg"
		for md in mds:
			hdr += "%13s" % ("mon %d%%" % int(md * 100))
		print(hdr)
		for pd in pds:
			var row := "%-12s" % ("ply %d%%" % int(pd * 100))
			for md in mds:
				var wins := 0
				var tt := 0
				for i in range(N):
					var r = run_fight(50, "bis", et, 1.0, pd, md)
					if r.win:
						wins += 1
					tt += r.turns
				row += "%13s" % ("%.1ft@%d%%" % [float(tt) / N, int(100.0 * wins / N)])
			print(row)
	print("==============================================================================\n")

# =====================================================================================
# GROWN CHARACTERS - measure a player's gear by EARNING it, not by inventing it
# =====================================================================================
# Owner 2026-09-04: "the game is very difficult right now. Most fights are a struggle because
# gear is scarce... you need to do it from the creation with starter gear and level it up like
# a player would have to." Plus two mechanics that make it harder than a naive model:
# "It's difficult to flee too as it is chance based. Fights can also flock causing difficulty
# and death." And the trap that closes the loop: "The xp seems to fall off dramatically when
# fighting things lower level than you but that's the only choice when undergeared."
#
# Every gear model above this line INVENTS a loadout, and `calibrate` shows the cost: the
# invented L6 player hits 2.09x as hard as a real one, the invented L45 player 0.45x. So the sim
# has flattered the early game and starved the late one, which is why it never showed the
# struggle being reported from live.

func _grow_new_character(klass: String, race: String):
	# Created exactly as the server does: one COMMON piece per slot at level 1 (searching UPWARD
	# for a tier that carries the slot, because tier 1 has no amulet), plus the tier-1 companion
	# the Home Stone registers. Mirrors server.gd's STARTER EQUIPMENT block.
	var ch = Character.new()
	ch.initialize("Grown", klass, race)
	for slot in ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]:
		var base := ""
		for tier_try in range(1, 10):
			for entry in drop_tables.EQUIPMENT_BASES.get(tier_try, []):
				if String(entry.get("item_type", "")).begins_with(slot):
					base = String(entry["item_type"])
					break
			if base != "":
				break
		if base == "":
			continue
		var piece = drop_tables._generate_item({"item_type": base}, 1, "common")
		if piece is Dictionary and not piece.is_empty():
			ch.equipped[slot] = piece
	var cands: Array = []
	for mtype in drop_tables.COMPANION_DATA.keys():
		if int((drop_tables.COMPANION_DATA[mtype] as Dictionary).get("tier", 1)) == 1:
			cands.append(mtype)
	if not cands.is_empty():
		var pick: String = String(cands[randi() % cands.size()])
		var pd: Dictionary = drop_tables.COMPANION_DATA.get(pick, {})
		ch.active_companion = {
			"id": "grown_comp", "monster_type": pick,
			"name": String(pd.get("companion_name", pick)),
			"tier": 1, "level": 1, "xp": 0,
			"bonuses": (pd.get("bonuses", {}) as Dictionary).duplicate(),
			"variant": "Normal", "sub_tier": 1, "border_tier": 1,
		}
	# The curated starter DECK. server.gd calls this at creation (v0.9.698); without it the
	# archetype AIs below have no cards to play and fall back to basic attacks, which is not
	# what any real player does. Owner 2026-09-04: "You'll need to use real methods for each
	# archetype too. The abilities warriors, mages and tricksters have at their disposal."
	ch.initialize_deck_collection_if_needed()
	_grow_spend_points(ch)
	ch.calculate_derived_stats()
	_grow_rest(ch)
	return ch


func _grow_spend_points(ch) -> void:
	# A player spends their level-up points; leaving them unspent flattens the pools and the
	# stat-driven damage term. Same primary-stat rule make_char uses, so the two are comparable.
	var primary := "strength"
	if ch.class_type in ["Wizard", "Sorcerer", "Sage"]:
		primary = "intelligence"
	elif ch.class_type in ["Thief", "Ranger", "Ninja"]:
		primary = "dexterity"
	var guard := 0
	while ch.unspent_stat_points > 0 and guard < 4000:
		guard += 1
		ch.spend_stat_point(primary)


func _grow_rest(ch) -> void:
	# Full top-up. Used ONLY at creation - between fights recovery goes through _grow_recover,
	# which is the one the game actually makes you live with.
	ch.current_hp = ch.get_total_max_hp()
	ch.current_mana = ch.get_total_max_mana()
	ch.current_stamina = ch.get_total_max_stamina()
	ch.current_energy = ch.get_total_max_energy()


func _grow_recover(ch) -> bool:
	# Healing up the way the game makes you: rest ticks of 10-25% max HP (handle_rest), each
	# carrying a 15% chance of being ambushed outside a safe zone. Returns true if the player was
	# jumped part-healed - the next encounter then starts from whatever HP they had.
	#
	# Owner 2026-09-04: "Random encounters are all over out of the posts and players often can't
	# heal up before the next one strikes either." That is not a modelling assumption, it is
	# arithmetic on the game's own numbers: climbing back from 30% takes ~5 ticks, and
	# 1 - 0.85^5 = 56%, so more than half of all heal-ups get interrupted.
	# A badly hurt player heads for a post, where healing is safe - but GETTING there is not.
	# Owner 2026-09-05: "Real players can't make it back to the post very often without getting
	# ambushed." So the trip is a gamble, not a free reset: several moves in the open, each
	# carrying the same 15% roll. At ~5 moves that is 0.85^5, so barely 44% of retreats land -
	# and a failed one means fighting at whatever HP drove the retreat in the first place.
	# The previous version handed out a free full heal here and made the harness too kind.
	if float(ch.current_hp) / float(maxi(1, ch.get_total_max_hp())) < 0.50:
		for _step in range(5):
			if (randi() % 100) < 15:
				return true
		ch.current_hp = ch.get_total_max_hp()
		ch.current_mana = ch.get_total_max_mana()
		ch.current_stamina = ch.get_total_max_stamina()
		ch.current_energy = ch.get_total_max_energy()
		return false
	var early: float = 2.0 - (float(clampi(ch.level, 1, 25) - 1) / 24.0)
	var guard := 0
	while ch.current_hp < ch.get_total_max_hp() and guard < 60:
		guard += 1
		if (randi() % 100) < 5:  # server.gd REST_AMBUSH_CHANCE
			return true
		ch.current_hp = mini(ch.get_total_max_hp(),
			ch.current_hp + maxi(1, int(float(ch.get_total_max_hp()) * randf_range(0.10, 0.25))))
		var rp: float = 0.30 * early
		ch.current_mana = mini(ch.get_total_max_mana(), ch.current_mana + maxi(1, int(float(ch.get_total_max_mana()) * rp)))
		ch.current_stamina = mini(ch.get_total_max_stamina(), ch.current_stamina + maxi(1, int(float(ch.get_total_max_stamina()) * rp)))
		ch.current_energy = mini(ch.get_total_max_energy(), ch.current_energy + maxi(1, int(float(ch.get_total_max_energy()) * rp)))
	return false


func _grow_power(ch) -> float:
	# One scalar for comparing two loadouts, read through the real aggregators so base-type
	# stats and affixes are both counted (reading either alone is how gear audits go wrong).
	return float(ch.get_total_attack()) * 2.0 + float(ch.get_total_defense()) + float(ch.get_total_max_hp()) * 0.1


func _grow_consider_item(ch, item: Dictionary) -> bool:
	# Wear the drop if it actually makes the character stronger - decided by EQUIPPING it and
	# measuring, not by comparing item levels on paper.
	var it := String(item.get("item_type", item.get("type", "")))
	var slot := ""
	for s in ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]:
		if it.begins_with(s):
			slot = s
			break
	if slot == "" or not ch.equipped.has(slot):
		return false
	var before := _grow_power(ch)
	var old = ch.equipped[slot]
	ch.equipped[slot] = item
	if _grow_power(ch) > before:
		return true
	ch.equipped[slot] = old
	return false


func _grow_gather(ch) -> Dictionary:
	# A gathering session, using the game's own catch rollers. Owner 2026-09-05: players
	# "gather about 20 percent of their movement in the 1st level or 2 then focus more on
	# combat" - and crucially "to gather they still have to be in danger", so a session carries
	# the same 15% ambush risk a rest tick does.
	#
	# Job XP converts to CHARACTER xp at taper 1.0 while the job is under level 20
	# (Character.add_job_xp), so for a new player it is one-for-one - which makes gathering the
	# efficient early route: a tier-1 catch pays 3-15 XP against 8 for a kill.
	var job: String = ["fishing", "mining", "logging"][randi() % 3]
	var xp := 0
	# A chain session awards several catches before it ends.
	for i in range(3 + (randi() % 3)):
		var c: Dictionary = {}
		match job:
			"fishing": c = drop_tables.roll_fishing_catch("river", int(ch.fishing_skill))
			"mining": c = drop_tables.roll_mining_catch(1, int(ch.mining_skill))
			_: c = drop_tables.roll_logging_catch(1, int(ch.logging_skill))
		xp += int(c.get("xp", 0))
	var res = ch.add_job_xp(job, xp)
	var char_xp := int(res.get("char_xp_gained", 0))
	if char_xp > 0:
		ch.add_experience(char_xp)
		_grow_spend_points(ch)
	# Gathering happens out in the world, so it can be interrupted the same way resting is.
	return {"xp": char_xp, "ambushed": (randi() % 100) < 15}


func _grow_gather_share(level: int) -> float:
	# 20% of actions at L1-2, tapering to ~5% by L10 as the player shifts to combat.
	if level <= 2:
		return 0.20
	return maxf(0.05, 0.20 - 0.019 * float(level - 2))


func _grow_xp_multiplier(ch, monster_level: int) -> float:
	# The real level-difference XP rule from process_attack, including the down-level penalty
	# that punishes the only fights an undergeared character can safely take.
	var diff: int = monster_level - ch.level
	if diff > 0:
		var reference_gap := 10.0 + float(ch.level) * 0.05
		return 1.0 + sqrt(float(diff) / reference_gap) * 2.0  # combat_manager: over-level bonus
	elif diff < 0:
		var under_gap := float(absi(diff))
		var threshold := 5.0 + float(ch.level) * 0.03
		if under_gap > threshold:
			var penalty: float = minf(0.6, (under_gap - threshold) * 0.03)
			return maxf(0.4, 1.0 - penalty)
	return 1.0


var _grow_immortal := false

func _grow_encounter(ch, hunt_level: int) -> Dictionary:
	# One encounter played the way a player must: fight, disengage when it turns, and follow the
	# flock chain WITHOUT resting between links - which is where the deaths come from. Flee is
	# the real chance-based process_flee; a failed attempt still costs the monster turn.
	var fights := 0
	var xp := 0
	var drops: Array = []
	var died := false
	var fled := false
	var worst := 1.0
	var wins := 0
	var link := 0
	while link < 5:
		link += 1
		fights += 1
		var monster = make_monster(maxi(1, hunt_level), "normal", 1.0)
		combat_mgr.start_combat(0, ch, monster)
		if not combat_mgr.active_combats.has(0):
			break
		var combat = combat_mgr.active_combats[0]
		var turns := 0
		var escaped := false
		var flee_tries := 0
		while turns < 400:
			if ch.current_hp <= 0 or int(monster.get("current_hp", 0)) <= 0 or combat.get("combat_ended", false):
				break
			turns += 1
			if combat.get("player_can_act", true) and ch.current_hp > 0:
				var hp_frac := float(ch.current_hp) / float(maxi(1, ch.get_total_max_hp()))
				worst = minf(worst, hp_frac)
				var m_frac := float(monster.get("current_hp", 0)) / float(maxi(1, int(monster.get("max_hp", 1))))
				# A player tries to disengage a losing fight - but only a couple of times. Flee is
				# chance-based, and someone whose escape keeps failing turns and fights rather
				# than standing there spamming it until they die. The first version of this
				# loop never went back to attacking, which killed characters the game would not
				# have killed: an instrument fault, not a difficulty finding.
				if hp_frac < 0.50 and m_frac > 0.33 and flee_tries < 3:
					flee_tries += 1
					var fr = combat_mgr.process_flee(combat)
					if fr.get("fled", false):
						escaped = true
						break
				else:
					match ch.get_class_path():
						"trickster": _player_act_trickster(combat, ch)
						"mage": _player_act_mage(combat, ch)
						_: _player_act(combat, ch)
			if ch.current_hp <= 0 or int(monster.get("current_hp", 0)) <= 0 or combat.get("combat_ended", false):
				break
			combat_mgr.process_monster_turn(combat)
		var won: bool = int(monster.get("current_hp", 0)) <= 0 and ch.current_hp > 0
		var flock: int = int(monster.get("flock_chance", 0))
		var mlvl: int = int(monster.get("level", hunt_level))
		combat_mgr.end_combat(0, won, false)
		if ch.current_hp <= 0:
			died = true
			if _grow_immortal:
				# Reference mode: a real L45 character is by definition someone who SURVIVED,
				# so the profile we want is the survivor's. Record the death and carry on
				# rather than throwing the run away.
				ch.current_hp = maxi(1, int(float(ch.get_total_max_hp()) * 0.25))
				died = false
				break
			break
		if escaped:
			fled = true
			break
		if not won:
			break
		wins += 1
		xp += int(round(float(monster.get("experience_reward", 0)) * _grow_xp_multiplier(ch, mlvl) * 1.10))
		for d in drop_tables.roll_drops(String(monster.get("drop_table_id", "tier1")),
				int(monster.get("drop_chance", 5)), mlvl):
			if d is Dictionary:
				drops.append(d)
		if flock <= 0 or (randi() % 100) >= flock:
			break
	return {"fights": fights, "xp": xp, "drops": drops, "died": died, "fled": fled, "worst": worst, "wins": wins}


func run_grow_audit():
	# Grow characters from creation to a target level, or until permadeath takes them.
	var TARGET := 20
	var RUNS := (_audit_n if _audit_n > 1 else 10)
	var CAP := 60000
	print("\n===== GROWN CHARACTERS - earned gear, real drops, real flee, real flocks =====")
	print("%d characters per class, from creation to L%d or death. Permadeath is final." % [RUNS, TARGET])
	print("The character hunts at the level it can SURVIVE, stepping down after a maul and back")
	print("up after a comfortable win - and eats the real down-level XP penalty for doing so.")
	print("%-9s %7s %7s %8s %6s %8s %7s %9s %6s" % ["class", "lived", "diedAt", "fights", "win%", "worstHP", "jumped", "upgrades", "slots"])
	for klass in ["Fighter", "Wizard", "Thief"]:
		var lived := 0
		var died_at: Array = []
		var f_sum := 0
		var gap_sum := 0.0
		var jump_sum := 0.0
		var jump_n := 0
		var gath_sum := 0
		var w_sum := 0
		var eh_sum := 0.0
		var eh_n := 0
		var upg_sum := 0
		var slot_sum := 0
		var atk_sum := 0
		var hp_sum := 0
		for r in range(RUNS):
			var ch = _grow_new_character(klass, "Human")
			var hunt: int = 1
			var upgrades := 0
			var fights := 0
			var gap_obs := 0.0
			var gap_n := 0
			var jumped := 0
			var heals := 0
			var gathers := 0
			var dead := false
			var wins_t := 0
			var endhp_t := 0.0
			var endhp_n := 0
			while ch.level < TARGET and fights < CAP:
				hunt = clampi(hunt, 1, ch.level + 20)
				# Some of the time the player is gathering, not hunting - still out in the
				# world, still ambushable, but paying better XP early than a kill does.
				if randf() < _grow_gather_share(ch.level):
					gathers += 1
					if not bool(_grow_gather(ch).ambushed):
						continue
				var enc = _grow_encounter(ch, hunt)
				fights += int(enc.fights)
				wins_t += int(enc.wins)
				if int(enc.wins) > 0:
					endhp_t += float(enc.worst)
					endhp_n += 1
				gap_obs += float(ch.level - hunt)
				gap_n += 1
				if bool(enc.died):
					dead = true
					break
				# A player who nearly died drops down a level; one who cruised pushes back up.
				if bool(enc.fled) or float(enc.worst) < 0.50:
					hunt = maxi(1, hunt - 1)
				elif float(enc.worst) > 0.75:
					hunt = mini(ch.level + 20, hunt + 1)
				if int(enc.xp) > 0:
					ch.add_experience(int(enc.xp))
					ch.add_companion_xp(int(round(float(enc.xp) * CombatManager.COMPANION_XP_SHARE)))
					_grow_spend_points(ch)
				for d in (enc.drops as Array):
					if _grow_consider_item(ch, d):
						upgrades += 1
				# Heal up - or get jumped part-healed and walk into the next fight wounded.
				if _grow_recover(ch):
					jumped += 1
				heals += 1
			f_sum += fights
			gath_sum += gathers
			w_sum += wins_t
			if endhp_n > 0:
				eh_sum += endhp_t / float(endhp_n)
				eh_n += 1
			if heals > 0:
				jump_sum += 100.0 * float(jumped) / float(heals)
				jump_n += 1
			if gap_n > 0:
				gap_sum += gap_obs / float(gap_n)
			if dead:
				died_at.append(ch.level)
			else:
				lived += 1
				var filled := 0
				for s in ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]:
					var e = ch.equipped.get(s, {})
					if e is Dictionary and not e.is_empty():
						filled += 1
				slot_sum += filled
				upg_sum += upgrades
				atk_sum += ch.get_total_attack()
				hp_sum += ch.get_total_max_hp()
		var avg_died := 0.0
		for l in died_at:
			avg_died += float(l)
		if died_at.size() > 0:
			avg_died /= float(died_at.size())
		print("%-9s %6d/%d %7.1f %8d %5.0f%% %7.0f%% %6.0f%% %9.1f %6.1f" % [
			klass, lived, RUNS, avg_died,
			int(float(f_sum) / float(maxi(1, RUNS))),
			100.0 * float(w_sum) / float(maxi(1, f_sum)),
			100.0 * eh_sum / float(maxi(1, eh_n)),
			jump_sum / float(maxi(1, jump_n)),
			float(upg_sum) / float(maxi(1, lived)),
			float(slot_sum) / float(maxi(1, lived))])
	print("\nlived    = reached the target without dying   diedAt = average level the dead reached")
	print("fights   = total encounters attempted         hunt-  = average levels BELOW own level hunted")
	print("win%     = share of individual FIGHTS won   worstHP = HP left at the low point of a won fight")
	print("jumped   = share of heal-ups interrupted by an ambush (walked into the next fight hurt)")
	print("upgrades = pieces actually found and worn over the whole climb (survivors only)")
	print("=====================================================================\n")

func run_grow_diag():
	# Instrument check for the grow harness. 12/12 grown characters dying at L1 disagrees with
	# `newplayer`, which measures 48% win at L1 on the same kit - so before believing the harness,
	# prove the character it builds is the character it claims to build.
	print("
===== GROW HARNESS INSTRUMENT CHECK =====")
	for klass in ["Fighter", "Wizard", "Thief"]:
		var g = _grow_new_character(klass, "Human")
		var m = make_char(1, "starter7", klass, "Human")
		var gs := 0
		var ms := 0
		for sl in ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]:
			var a = g.equipped.get(sl, {})
			if a is Dictionary and not a.is_empty():
				gs += 1
			var b = m.equipped.get(sl, {})
			if b is Dictionary and not b.is_empty():
				ms += 1
		print("%-8s grown     hp=%-5d atk=%-4d def=%-4d slots=%d deck=%d comp=%s" % [
			klass, g.get_total_max_hp(), g.get_total_attack(), g.get_total_defense(), gs,
			g.combat_deck_collection.size(), String(g.active_companion.get("name", "none"))])
		print("%-8s starter7  hp=%-5d atk=%-4d def=%-4d slots=%d deck=%d" % [
			"", m.get_total_max_hp(), m.get_total_attack(), m.get_total_defense(), ms,
			m.combat_deck_collection.size()])
	var mon = make_monster(1, "normal", 1.0)
	print("L1 normal monster: hp=%s str=%s def=%s xp=%s flock=%s%%" % [
		str(mon.get("max_hp")), str(mon.get("strength")), str(mon.get("defense")),
		str(mon.get("experience_reward")), str(mon.get("flock_chance"))])
	# Now run ONE grown Fighter through single encounters and report what actually happens.
	print("
One grown Fighter, encounter by encounter:")
	var ch = _grow_new_character("Fighter", "Human")
	for i in range(6):
		var hp0: int = ch.current_hp
		var enc = _grow_encounter(ch, 1)
		print("  enc%d  hp %d->%d/%d  fights=%s xp=%s drops=%s died=%s fled=%s worst=%d%%" % [
			i + 1, hp0, ch.current_hp, ch.get_total_max_hp(),
			str(enc.fights), str(enc.xp), str((enc.drops as Array).size()),
			str(enc.died), str(enc.fled), int(100.0 * float(enc.worst))])
		if bool(enc.died):
			print("  DIED at level %d after %d encounters" % [ch.level, i + 1])
			break
		var was_jumped := _grow_recover(ch)
		print("        recover -> hp %d/%d  interrupted=%s" % [ch.current_hp, ch.get_total_max_hp(), str(was_jumped)])
	print("=====================================================================
")

	# Is the starter companion actually DOING anything, or just attached? Owner 2026-09-05:
	# "Starter companion might help some if you're not using." Presence is not contribution -
	# measure it by running the same grown character with one and without one.
	print("Starter companion contribution (L1, 20 characters x 3 encounters per cell):")
	print("%-9s %14s %14s %10s" % ["class", "with companion", "without", "delta"])
	_grow_immortal = true
	for klass in ["Fighter", "Wizard", "Thief"]:
		var rates: Array = []
		for use_comp in [true, false]:
			var w := 0
			var f := 0
			for i in range(20):
				var c = _grow_new_character(klass, "Human")
				if not use_comp:
					c.active_companion = {}
					c.calculate_derived_stats()
					_grow_rest(c)
				for e in range(3):
					var r = _grow_encounter(c, 1)
					w += int(r.wins)
					f += int(r.fights)
			rates.append(100.0 * float(w) / float(maxi(1, f)))
		print("%-9s %13.0f%% %13.0f%% %9.0fpp" % [klass, rates[0], rates[1], rates[0] - rates[1]])
	_grow_immortal = false


func _grow_scaled_fight(ch, level: int, hp_mult: float, dmg_mult: float) -> bool:
	# One fight at FULL health against a monster scaled by hp_mult / dmg_mult. Damage is scaled
	# the same way run_fight does it - give back a fraction of what was actually dealt - so the
	# monster's real ability mix and hit rolls are preserved rather than replaced by a model.
	_grow_rest(ch)
	var monster = make_monster(level, "normal", hp_mult)
	combat_mgr.start_combat(0, ch, monster)
	if not combat_mgr.active_combats.has(0):
		return false
	var combat = combat_mgr.active_combats[0]
	var turns := 0
	while turns < 400:
		if ch.current_hp <= 0 or int(monster.get("current_hp", 0)) <= 0 or combat.get("combat_ended", false):
			break
		turns += 1
		if combat.get("player_can_act", true) and ch.current_hp > 0:
			match ch.get_class_path():
				"trickster": _player_act_trickster(combat, ch)
				"mage": _player_act_mage(combat, ch)
				_: _player_act(combat, ch)
		if ch.current_hp <= 0 or int(monster.get("current_hp", 0)) <= 0 or combat.get("combat_ended", false):
			break
		var hp0: int = ch.current_hp
		combat_mgr.process_monster_turn(combat)
		if dmg_mult < 1.0:
			var taken: int = hp0 - ch.current_hp
			if taken > 0:
				ch.current_hp = mini(ch.get_total_max_hp(), ch.current_hp + int(float(taken) * (1.0 - dmg_mult)))
	var won: bool = int(monster.get("current_hp", 0)) <= 0 and ch.current_hp > 0
	combat_mgr.end_combat(0, won, false)
	return won


func run_grow_tune():
	"""How much do monsters have to come down for a REALISTICALLY GEARED player to hit target?

	Owner 2026-09-05, after recovery and XP fixes failed to move survival: nerf monster damage
	"and possibly nerf their hp too... likely this will need to be done for more than just the
	early game."

	The player here is GROWN, not invented - it carries only gear it actually found, so the
	answer is not distorted by make_char's 2.09x-at-L6 / 0.45x-at-L45 slope. Win rate is
	measured at full health against a single normal monster, which is the cleanest read on
	whether a fight is winnable at all; the compounding (flocks, carried damage, failed
	retreats) sits on top of whatever this says."""
	# 2026-09-05 - CHARS per cell, not one. The first version grew a SINGLE character per cell,
	# so every number carried that character's gear luck rather than the level's difficulty. The
	# tell was unmissable once the nerf landed: Wizard L5 read 75% before and 50% after, and a
	# nerf cannot make a fight harder. Pooling several grown characters per cell costs more
	# growing but is the difference between a measurement and an anecdote.
	var LEVELS := [1, 5, 10, 20]
	var MULTS := [1.0, 0.75, 0.5, 0.35, 0.25]
	var CHARS := 4
	var N := 15
	print("
===== WHAT NERF DOES A GROWN PLAYER NEED? (target 60% at a normal fight) =====")
	print("Monster HP and damage both scaled by the same multiplier. %d grown characters x %d fights per cell." % [CHARS, N])
	var head := "%-9s %5s" % ["class", "lv"]
	for m in MULTS:
		head += "%9s" % ("x%.2f" % m)
	print(head)
	_grow_immortal = true
	for klass in ["Fighter", "Wizard", "Thief"]:
		for lvl in LEVELS:
			var pooled: Array = []
			for m in MULTS:
				pooled.append(0)
			for _c in range(CHARS):
				var ch = _grow_new_character(klass, "Human")
				var hunt := 1
				var guard := 0
				while ch.level < lvl and guard < 200000:
					hunt = clampi(hunt, 1, ch.level + 20)
					if randf() < _grow_gather_share(ch.level):
						if not bool(_grow_gather(ch).ambushed):
							continue
					var enc = _grow_encounter(ch, hunt)
					guard += int(enc.fights)
					if bool(enc.fled) or float(enc.worst) < 0.50:
						hunt = maxi(1, hunt - 1)
					elif float(enc.worst) > 0.75:
						hunt = mini(ch.level + 20, hunt + 1)
					if int(enc.xp) > 0:
						ch.add_experience(int(enc.xp))
						ch.add_companion_xp(int(round(float(enc.xp) * CombatManager.COMPANION_XP_SHARE)))
						_grow_spend_points(ch)
					for d in (enc.drops as Array):
						_grow_consider_item(ch, d)
					_grow_recover(ch)
				for mi in range(MULTS.size()):
					var w: int = pooled[mi]
					for i in range(N):
						if _grow_scaled_fight(ch, lvl, float(MULTS[mi]), float(MULTS[mi])):
							w += 1
					pooled[mi] = w
			var row := "%-9s %5d" % [klass, lvl]
			for mi2 in range(MULTS.size()):
				row += "%8d%%" % int(100.0 * float(pooled[mi2]) / float(CHARS * N))
			print(row)
	_grow_immortal = false
	print("
Read across each row for the first cell at or above 60%.")
	print("=====================================================================
")


func run_policy_test():
	"""Run each warrior strategy head to head and let the win rate choose.

	Owner 2026-09-05: "Attempt different strategies and find the most efficient and build on
	those." Hand-written policies are guesses, and this file has now produced four instrument
	defects that were really the AI failing to play the game (the Trickster never cast its kill
	card; the Mage never raised its shield). A tournament is the answer to that class of error:
	stop asserting which strategy is right and measure it.

	Every policy is tested on the SAME grown characters at the same levels, so gear luck cannot
	decide the winner - the only thing varying is the decision rule."""
	var LEVELS := [1, 5, 10, 20]
	var POLICIES := ["buff_first", "damage_first", "defensive", "momentum_hold"]
	var CHARS := 3
	var N := 20
	print("
===== WARRIOR STRATEGY TOURNAMENT =====")
	print("%d grown characters x %d fights per cell, same characters across every policy." % [CHARS, N])
	var head := "%-6s" % "lv"
	for pol in POLICIES:
		head += "%15s" % pol
	print(head)
	_grow_immortal = true
	for lvl in LEVELS:
		# Grow the cohort ONCE, then replay it through each policy.
		var cohort: Array = []
		for _c in range(CHARS):
			var ch = _grow_new_character("Fighter", "Human")
			var hunt := 1
			var guard := 0
			while ch.level < lvl and guard < 200000:
				hunt = clampi(hunt, 1, ch.level + 20)
				if randf() < _grow_gather_share(ch.level):
					if not bool(_grow_gather(ch).ambushed):
						continue
				var enc = _grow_encounter(ch, hunt)
				guard += int(enc.fights)
				if bool(enc.fled) or float(enc.worst) < 0.50:
					hunt = maxi(1, hunt - 1)
				elif float(enc.worst) > 0.75:
					hunt = mini(ch.level + 20, hunt + 1)
				if int(enc.xp) > 0:
					ch.add_experience(int(enc.xp))
					ch.add_companion_xp(int(round(float(enc.xp) * CombatManager.COMPANION_XP_SHARE)))
					_grow_spend_points(ch)
				for d in (enc.drops as Array):
					_grow_consider_item(ch, d)
				_grow_recover(ch)
			cohort.append(ch)
		var row := "%-6d" % lvl
		for pol in POLICIES:
			_warrior_policy = pol
			var w := 0
			var tot := 0
			for ch2 in cohort:
				for i in range(N):
					if _grow_scaled_fight(ch2, lvl, 1.0, 1.0):
						w += 1
					tot += 1
			row += "%14d%%" % int(100.0 * float(w) / float(maxi(1, tot)))
		print(row)
	_warrior_policy = "buff_first"
	_grow_immortal = false
	print("
Highest column wins. If buff_first is not it, the default policy has been")
	print("under-rating the Warrior in every measurement taken so far.")
	print("=====================================================================
")


func run_grow_reference():
	# Build the reference make_char SHOULD encode, by earning it instead of inventing it.
	#
	# Owner chose "fix the player model first" (2026-09-05). `calibrate` measures make_char at
	# 2.09x a real character's attack at L6 and 0.45x at L45, and only ONE real character exists
	# above L14, so there is nothing to fit a level-dependent gear model against. A grown
	# character supplies that reference at every level.
	#
	# Death is suppressed here on purpose: a real L45 character is by definition a SURVIVOR, so
	# the profile worth encoding is the survivor's, not the average of everyone who tried.
	var MILESTONES := [3, 6, 10, 15]
	var RUNS := (_audit_n if _audit_n > 1 else 3)
	print("
===== EARNED GEAR PROFILE - what a grown character actually carries =====")
	print("%d survivors per class. Death suppressed: real high-level characters ARE survivors." % RUNS)
	print("itemLv/lv = average equipped item level as a fraction of character level")
	print("%-9s %5s %6s %7s %9s %8s %8s %8s %8s" % ["class", "lv", "slots", "itemLv/lv", "rar(c/u/r/e+)", "ATK", "HP", "DEF", "fights"])
	_grow_immortal = true
	# Owner 2026-09-05: "you didn't mention tricksters, you should be testing them too."
	# All three trickster classes, not Thief as a stand-in - Ranger and Ninja have different
	# stat gains (Ninja DEX 1.25 vs Thief WITS 1.5) and 6k says that changes what levelling buys.
	for klass in ["Fighter", "Wizard", "Thief", "Ranger", "Ninja"]:
		for target in MILESTONES:
			var slots_a := 0.0
			var ilv_a := 0.0
			var atk_a := 0.0
			var hp_a := 0.0
			var def_a := 0.0
			var f_a := 0.0
			var rc := 0
			var ru := 0
			var rr := 0
			var re := 0
			for r in range(RUNS):
				var ch = _grow_new_character(klass, "Human")
				var hunt := 1
				var fights := 0
				while ch.level < target and fights < 200000:
					hunt = clampi(hunt, 1, ch.level + 20)
					if randf() < _grow_gather_share(ch.level):
						if not bool(_grow_gather(ch).ambushed):
							continue
					var enc = _grow_encounter(ch, hunt)
					fights += int(enc.fights)
					if bool(enc.fled) or float(enc.worst) < 0.50:
						hunt = maxi(1, hunt - 1)
					elif float(enc.worst) > 0.75:
						hunt = mini(ch.level + 20, hunt + 1)
					if int(enc.xp) > 0:
						ch.add_experience(int(enc.xp))
						ch.add_companion_xp(int(round(float(enc.xp) * CombatManager.COMPANION_XP_SHARE)))
						_grow_spend_points(ch)
					for d in (enc.drops as Array):
						_grow_consider_item(ch, d)
					_grow_recover(ch)
				var filled := 0
				var ilv := 0.0
				for sl in ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]:
					var e = ch.equipped.get(sl, {})
					if e is Dictionary and not e.is_empty():
						filled += 1
						ilv += float(e.get("level", 1))
						match String(e.get("rarity", "common")):
							"common": rc += 1
							"uncommon": ru += 1
							"rare": rr += 1
							_: re += 1
				slots_a += float(filled)
				if filled > 0:
					ilv_a += (ilv / float(filled)) / float(maxi(1, ch.level))
				atk_a += float(ch.get_total_attack())
				hp_a += float(ch.get_total_max_hp())
				def_a += float(ch.get_total_defense())
				f_a += float(fights)
			var n := float(maxi(1, RUNS))
			var tot := float(maxi(1, rc + ru + rr + re))
			print("%-9s %5d %6.1f %9.2f  %2.0f/%2.0f/%2.0f/%2.0f%s %8d %8d %8d %8d" % [
				klass, target, slots_a / n, ilv_a / n,
				100.0 * rc / tot, 100.0 * ru / tot, 100.0 * rr / tot, 100.0 * re / tot, "%",
				int(atk_a / n), int(hp_a / n), int(def_a / n), int(f_a / n)])
	_grow_immortal = false
	print("
Compare each row against make_char(level, \"average\") - the gap IS the model error.")
	print("=====================================================================
")
