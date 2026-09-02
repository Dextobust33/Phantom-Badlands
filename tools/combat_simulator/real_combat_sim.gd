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
		"races": ["all 8 races on one class", run_race_audit],
		"calibrate": ["make_char vs REAL saved characters", run_calibration_audit],
		"gear_solve": ["solve the average-gear model against real characters", run_gear_solve],
		"progression": ["does difficulty hold from L1 to L10000?", run_progression_audit],
		"underlevel": ["what fighting below your level is worth (post pull-down)", run_underlevel_audit],
		"selection": ["why the curve is jagged: tier bands vs monster base levels", run_selection_audit],
		"refcurve": ["measure the reference-player curve the monster model anchors to", run_reference_curve],
		"refval": ["validate the reference model: predicted vs actual fight length", run_reference_validate],
		"refcal": ["calibrate monster stats against REAL fights until they hit target", run_reference_calibrate],
		"roles": ["elite/boss fights vs their ROLE_TARGETS", run_role_audit],
		"xp": ["how many fights to level, and what is the best way", run_xp_audit],
		"risk": ["over-level gambles: kill/escape/death and what the reward is worth", run_risk_reward_audit],
		"companion": ["does levelling a companion keep paying?", run_companion_audit],
		"comp_unlock": ["what a companion actually does: survival, soak, unlock boundaries", run_companion_unlock_audit],
		"resource": ["resource-economy telemetry", run_resource_audit],
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

func _fight_stats_at(level: int, samples: int) -> Dictionary:
	# Run real same-level fights across all three archetypes and report what actually
	# happened: mean turns, mean share of the player's health bar spent, win rate.
	# This is the ground truth the calibration drives toward.
	var turns_tot := 0.0
	var cost_tot := 0.0
	var wins := 0
	var n := 0
	for klass in ["Fighter", "Wizard", "Thief"]:
		for i in range(samples):
			var ch = make_char(level, "average", klass)
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
			cost_tot += float(php0 - maxi(0, ch.current_hp)) / float(maxi(1, php0))
			n += 1
			combat_mgr.end_combat(0, false, false)
	if n == 0:
		return {}
	return {"turns": turns_tot / float(n), "cost": cost_tot / float(n), "win": float(wins) / float(n)}

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
	var passes := 4
	var samples := 8
	print("\n===== #6 MONSTER MODEL CALIBRATION (target %.0f turns, %.0f%% HP cost) =====" % [TARGET_TURNS_NORMAL_SIM, DANGER_NORMAL_SIM * 100.0])
	var table: Array = []
	for lvl in REF_ANCHOR_LEVELS:
		# Seed from the model's current output for this level so calibration starts from
		# wherever the model is now rather than from an arbitrary guess.
		var seed_m := make_monster(lvl, "normal", 1.0)
		var hp := float(seed_m.get("max_hp", 100))
		var st := float(seed_m.get("strength", 10))
		var last := {}
		for pass_i in range(passes):
			_cal_override = {"level": lvl, "hp": int(round(hp)), "str": int(round(st))}
			var r := _fight_stats_at(lvl, samples)
			_cal_override = {}
			if r.is_empty():
				break
			last = r
			# Correct toward target. Damped (sqrt) so a noisy sample cannot send the
			# next pass wildly off; converges in a handful of passes either way.
			var turn_err: float = TARGET_TURNS_NORMAL_SIM / maxf(0.5, float(r["turns"]))
			hp *= sqrt(clampf(turn_err, 0.15, 6.0))
			var cost_err: float = DANGER_NORMAL_SIM / maxf(0.01, float(r["cost"]))
			st *= sqrt(clampf(cost_err, 0.15, 6.0))
		table.append({"level": lvl, "hp": int(round(hp)), "str": int(round(st))})
		if last.is_empty():
			print("L%-6d  (no data)" % lvl)
		else:
			print("L%-6d hp=%12d str=%10d   -> %5.1f turns, %3.0f%% HP cost, %3.0f%% win" % [
				lvl, int(round(hp)), int(round(st)),
				float(last["turns"]), 100.0 * float(last["cost"]), 100.0 * float(last["win"])])
	var out := {"generated": "sim run_reference_calibrate", "target_turns": TARGET_TURNS_NORMAL_SIM, "anchors": table}
	var f = FileAccess.open("res://shared/reference_monster_curve.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out, "\t"))
		f.close()
		print("\nWrote shared/reference_monster_curve.json (%d anchors)." % table.size())
	print("Re-run `-- refval` to confirm the model lands on target with these anchors.")
	print("=====================================================================\n")

func run_role_audit():
	# #6 — do elite and boss fights actually feel like their ROLE_TARGETS say they should?
	# Reports measured turns / share of the player's health bar spent / win rate against the
	# target for each role, so the derived multipliers can be checked rather than assumed.
	var samples := 10
	print("
===== #6 ROLE AUDIT (measured vs ROLE_TARGETS) =====")
	print("Each role states a target fight length and cost; multipliers are derived from them.")
	print("%-10s %-8s %10s %10s %10s %10s %8s" % ["Role", "Level", "turns", "target", "HPcost", "target", "win%"])
	for role in ["normal", "empowered", "elite", "boss"]:
		var tgt: Dictionary = monster_db.ROLE_TARGETS.get(role, {})
		for lvl in [1, 10, 50, 250, 1000, 5000]:
			var turns_tot := 0.0
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
					cost_tot += 100.0 * float(php0 - maxi(0, ch.current_hp)) / float(maxi(1, php0))
					n += 1
					combat_mgr.end_combat(0, false, false)
			if n == 0:
				continue
			print("%-10s %-8d %10.1f %10.1f %9.0f%% %9.0f%% %7d%%" % [
				role, lvl, turns_tot / n, float(tgt.get("turns", 0.0)),
				cost_tot / n, 100.0 * float(tgt.get("danger", 0.0)), int(100.0 * wins / n)])
	print("=====================================================================
")

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
	var samples := 12
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
	var samples := 24
	print("\\n===== #6b COMPANION: what does it actually do? =====")
	print("Same-level ELITE, Fighter, AVERAGE gear, %d fights/cell." % samples)
	print("compHP is the companion's max combat HP: 30 + level*5 + sub_tier*10 + hp_bonus.")
	print("survived = rounds up before KO (capped at fight length). soaked = hits taken FOR you.")
	print("%-7s %-9s %8s %9s %8s %8s %7s" % ["PlyrL", "compL", "compHP", "survived", "soaked", "dealt%", "win%"])
	for lvl in [5, 50, 250, 1000, 10000]:
		for comp_mode in ["none", "1", "5", "15", "match"]:
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
					var cl: int = lvl if comp_mode == "match" else int(comp_mode)
					ch.active_companion["level"] = cl
					ch.active_companion["combat_hp"] = ch.get_companion_max_hp()
				comp_hp = ch.get_companion_max_hp() if comp_mode != "none" else 0
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
				lvl, comp_mode, comp_hp, surv / n, soak / n, "-", int(100.0 * wins / n)])
	print("")
	print("If `survived` collapses to ~1 round at high level, the companion is not a sponge or")
	print("an attacker — it is a one-hit casualty, and no amount of ability unlocking fixes it.")
	print("=====================================================================\\n")

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
	var arg: String = str(maxi(1, int(ch.get_total_max_mana() * 0.25))) if ability == "magic_bolt" else ""
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
	var N := 25
	var sets := [
		["Fighter", "War", ["power_strike", "cleave", "devastate"]],
		["Wizard", "Mag", ["magic_bolt", "blast", "meteor"]],
		["Thief", "Trk", ["ambush", "exploit", "gambit"]],
	]
	print("
===== #6 ABILITY POWER vs MONSTER HP ACROSS THE WHOLE GAME (%d casts/cell) =====" % N)
	print("One cast's damage as %% of a SAME-LEVEL NORMAL monster's max HP, AVERAGE gear.")
	print(">=100%% one-shots trash. Falling left-to-right = the ability falls off with level.")
	print("Magic Bolt is cast at its usual sim spend (25%% of the mana pool); finishers read")
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
	# Build Read with damage setups (these spend energy + add Read).
	for ab in ["ambush", "exploit"]:
		if ab in hand:
			if combat_mgr.process_ability_command(0, ab, "").get("success", false):
				return
	# Filler builders (debuffs still add Read).
	for ab in ["sabotage", "distract"]:
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
var _companion_mode: String = "match"
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
		"average":
			roll_rarity = true
			glevel = max(1, int(round(level * _gear_avg_level_ratio)))
		"bis":
			rarity = "epic"
	# #70 CALIBRATION — mirror the REAL drop path: use a TIER-APPROPRIATE base per slot
	# (weapon_rusty / armor_chain / …) instead of forcing "<slot>_artifact". The old artifact
	# bases gave artifact-tier stats even at "rare" rarity, inflating pools ~2.2x vs a real
	# character (test02 L6 mage: real 121 mana vs the sim's old 261). Ground-truth calibrated.
	var gtier: int = _tier_for_level(glevel)
	for slot in SLOTS:
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
		if item is Dictionary and not item.is_empty():
			ch.equipped[slot] = item
	# #5 CALIBRATION (2026-09-02) — the companion used to be INVENTED: a hand-written
	# bonus block {attack 10, hp 5, mana 3, wisdom 2, speed 5} that exists on no real
	# companion. Every real one carries 1-2 small bonuses from drop_tables.COMPANION_DATA
	# (Dexto's L45 Ogre: attack 5, hp_bonus 3). The sim was handing every character a
	# companion 2-4x stronger than the game can produce, on top of the gear inflation.
	# Now: draw a REAL companion of the tier a player would plausibly have, from the game's
	# own table. "under" gets none — a third of real saved characters have no companion.
	if gear != "under" and _companion_mode != "none":
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
	if extra_hp_mult != 1.0:
		m["max_hp"] = int(m.get("max_hp", 1) * extra_hp_mult)
	if not _cal_override.is_empty() and int(_cal_override.get("level", -1)) == level:
		m["max_hp"] = int(_cal_override.get("hp", m.get("max_hp", 1)))
		m["strength"] = int(_cal_override.get("str", m.get("strength", 1)))
	m["current_hp"] = m.get("max_hp", 1)
	return m

func _player_act(combat: Dictionary, ch) -> void:
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
