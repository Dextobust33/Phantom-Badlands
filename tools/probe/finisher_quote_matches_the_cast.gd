extends SceneTree
## Owner sheet 2026-10-13, item 16: "Double cross card face damage doesn't match how much it does."
## `card_face_truth` could not see this: it only checks cards whose server quote has kind "damage", and
## the Trickster finisher (Grifter Double Cross / Ranger Killing Shot / Ninja Assassinate, one card
## `perfect_heist`) is quoted through `_finisher_damage` / `_finisher_value` instead, so it was silently
## skipped. Measured on real casts with crits excluded, the face under-quoted by 1.2-1.4x at 4 stacks
## (and 2x before the first fix) for two reasons: it left out the damage bonus + buff pipeline every other
## card's quote carries, and it sized the strike on the stacks BANKED rather than the stacks it resolves
## on (the cast feeds the engine +1 first). The Ninja's KILL CHANCE had the same stack error. Both fixed;
## this pins the face to the cast.
const DAMAGE_TOLERANCE := 0.20      # casts carry +-15% variance; a mean of ~20 is within this
const CASTS := 40
const KILL_CASTS := 220

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _init() -> void:
	seed(20261013)
	var sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	get_root().add_child(sim)
	await process_frame
	var cm = sim.combat_mgr

	print("--- the finisher's DAMAGE quote equals what the cast deals (crits and kills excluded) ---")
	var worst := 0.0
	var cells := 0
	for klass in ["Grifter", "Ranger", "Ninja"]:
		for level in [20, 200]:
			for engine in [0, 2, 4, 7]:
				var ratios: Array = []
				for i in range(CASTS):
					var ch = sim.make_char(level, "average", klass, "Human")
					var mon: Dictionary = sim.make_monster(level, "normal", 400.0)
					mon["defense"] = 0
					mon["level"] = level
					mon["max_hp"] = 1000000000     # a kill would drop the high rolls and bias the mean down
					mon["current_hp"] = 1000000000
					cm.start_combat(0, ch, mon)
					var c = cm.active_combats[0]
					c["combat_hand"] = ["perfect_heist"]
					c["player_can_act"] = true
					c["suppress_monster_turn"] = true
					c["combo"] = engine
					ch.current_energy = ch.get_total_max_energy()
					var quote: int = int(cm._finisher_damage(ch, c))
					var hp0: int = int(c["monster"]["current_hp"])
					var res: Dictionary = cm.process_ability_command(0, "perfect_heist", "")
					var dealt: int = hp0 - int(c["monster"]["current_hp"])
					var txt := " ".join(PackedStringArray(res.get("messages", []))).to_upper()
					if bool(res.get("success", false)) and txt.find("CRIT") < 0 and dealt < quote * 3:   # an execute is the kill-chance half's business
						ratios.append(float(dealt) / float(maxi(1, quote)))
					cm.active_combats.erase(0)
				if ratios.size() >= 4:
					ratios.sort()
					cells += 1
					var med: float = float(ratios[ratios.size() / 2])
					worst = maxf(worst, absf(med - 1.0))
					if absf(med - 1.0) > DAMAGE_TOLERANCE:
						print("      %s L%d engine %d: median dealt/quote %.2fx over %d casts" % [klass, level, engine, med, ratios.size()])
	ck(cells >= 18, "compared %d class x level x engine cells" % cells)
	ck(worst <= DAMAGE_TOLERANCE, "every cell within %d%% (worst %.0f%% off)" % [int(DAMAGE_TOLERANCE * 100.0), worst * 100.0])

	print("\n--- the Ninja's quoted KILL CHANCE equals the real kill rate ---")
	var bad_kill := 0
	var kill_cells := 0
	for engine in [0, 4, 7]:
		var kills := 0
		var quote_pct := 0.0
		for i in range(KILL_CASTS):
			var ch = sim.make_char(20, "average", "Ninja", "Human")
			var mon: Dictionary = sim.make_monster(20, "normal", 400.0)
			mon["level"] = 20
			cm.start_combat(0, ch, mon)
			var c = cm.active_combats[0]
			c["combat_hand"] = ["perfect_heist"]
			c["player_can_act"] = true
			c["suppress_monster_turn"] = true
			c["combo"] = engine
			ch.current_energy = ch.get_total_max_energy()
			if i == 0:
				quote_pct = float(cm._finisher_value(ch, c))
			cm.process_ability_command(0, "perfect_heist", "")
			if int(c["monster"]["current_hp"]) <= 0:
				kills += 1
			cm.active_combats.erase(0)
		var p: float = quote_pct / 100.0
		var tol: float = 3.0 * sqrt(maxf(0.01, p * (1.0 - p)) / float(KILL_CASTS)) + 0.02
		var emp: float = float(kills) / float(KILL_CASTS)
		kill_cells += 1
		if absf(emp - p) > tol:
			bad_kill += 1
			print("      engine %d: face says %.0f%%, real kill rate %.1f%% (tolerance +-%.1f%%)" % [engine, quote_pct, emp * 100.0, tol * 100.0])
	ck(kill_cells == 3 and bad_kill == 0, "the kill chance on the face is the chance the cast rolls (%d of %d cells off)" % [bad_kill, kill_cells])

	print("\n[FINISHERQUOTE] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
