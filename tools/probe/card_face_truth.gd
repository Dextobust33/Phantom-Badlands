extends SceneTree
## Does every card's DAMAGE QUOTE match what the card actually does?
##
## The instrument `card_vs_server.gd` could not answer this: it re-implements the client's retired
## fallback formulas, so its "3-8x LIES" table describes a path combat cards no longer use. This one
## asks the question the player asks. For every class and every card in its deck that quotes damage,
## it compares the SERVER's quote (`_build_ability_effect_info`, the number on the card face) with
## the mean of real casts through `process_ability_command`.
##
## Held equal on purpose, because the quote deliberately omits them (every card's does): the
## monster has ZERO defence and is the player's own level (no level penalty). Variance is +-15%, so
## a mean over N casts is compared, and crits are counted separately rather than averaged in.
## Card faces lying was the most common fault in the 2026-09-15 live test.
##
## First real run (2026-09-15), after two defects IN THIS PROBE were fixed (the quote was taken from a
## different randomly-geared character than the one casting; kill-outright finishers were averaged as
## damage), 78 cells, and ONE card was genuinely wrong: Barbarian Rampage left out the Rage ramp and
## under-quoted by ~1.5x at 4 Rage. The Sorcerer's Chaos Magic doubles are a gamble the quote
## deliberately omits, like crits, and are excluded here for that reason.
const CM = preload("res://shared/combat_manager.gd")
const N := 30   # ~7 minutes for the whole sweep; do not raise casually, the tool cap is 10
const TOLERANCE := 0.15

var rows: Array = []


func _cast_mean(sim, cm, klass: String, level: int, card: String, engine: int) -> Dictionary:
	# PER-CAST quote. The first cut quoted once from the first character and then cast with a fresh
	# character each time - "average" gear is randomised, so quote and damage came from different
	# stat lines and the table swung 0.5x-1.6x on gear noise alone.
	var ratios: Array = []
	var crits := 0
	var kills := 0
	var quoted := false
	var quote_sum := 0.0
	var dealt_sum := 0.0
	for i in range(N):
		var ch = sim.make_char(level, "average", klass, "Human")
		var mon: Dictionary = sim.make_monster(level, "normal", 400.0)
		mon["defense"] = 0
		mon["level"] = level
		cm.start_combat(0, ch, mon)
		var c = cm.active_combats[0]
		c["combat_hand"] = [card]
		c["player_can_act"] = true
		c["suppress_monster_turn"] = true
		c["combo"] = engine
		c["focus"] = engine
		c["momentum"] = engine
		ch.current_mana = ch.get_total_max_mana()
		ch.current_stamina = ch.get_total_max_stamina()
		ch.current_energy = ch.get_total_max_energy()
		var q: Dictionary = cm._build_ability_effect_info(c).get(card, {})
		if String(q.get("kind", "")) != "damage" or int(q.get("value", 0)) <= 0:
			cm.active_combats.erase(0)
			if not quoted:
				return {"quote": -2}
			continue
		quoted = true
		var quote := int(q.get("value", 0))
		var hp0: int = int(c["monster"]["current_hp"])
		var res: Dictionary = cm.process_ability_command(0, card, "")
		var dealt: int = hp0 - int(c["monster"]["current_hp"])
		if bool(res.get("success", false)) and dealt > 0:
			var txt := " ".join(PackedStringArray(res.get("messages", []))).to_upper()
			if int(c["monster"]["current_hp"]) <= 0:
				kills += 1          # a lethal finisher ends the fight outright; not a damage sample
			elif txt.find("CRIT") >= 0 or txt.find("CHAOS MAGIC") >= 0 or txt.find("DOUBLE CAST") >= 0:
				# Gambles the quote deliberately leaves out (the on-hit number is the honest one):
				# crits, the Sorcerer's Chaos Magic double/backfire, and Arcane Surge double casts.
				crits += 1
			else:
				ratios.append(float(dealt) / float(quote))
				quote_sum += quote
				dealt_sum += dealt
		cm.active_combats.erase(0)
	if ratios.is_empty():
		return {"quote": -3}
	var mean := 0.0
	for r in ratios:
		mean += float(r)
	mean /= ratios.size()
	return {"quote": int(quote_sum / ratios.size()), "mean": dealt_sum / ratios.size(), "ratio": mean,
		"casts": ratios.size(), "crits": crits, "kills": kills}


func _init() -> void:
	var sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	get_root().add_child(sim)
	await process_frame
	var cm = sim.combat_mgr
	var bad := 0
	var checked := 0
	print("class      L    card               engine  quote(avg) dealt(avg)    ratio   casts crits kills")
	for cls in sim.ALL_CLASSES:
		var klass := String(cls[0])
		for level in [20, 200]:
			var probe_ch = sim.make_char(level, "average", klass, "Human")
			probe_ch.initialize_deck_collection_if_needed()
			var cards: Array = []
			for k in probe_ch.combat_deck_collection.keys():
				var b := Character.card_base(String(k))
				if not (b in cards):
					cards.append(b)
			for card in cards:
				for engine in [0, 4]:
					var r: Dictionary = _cast_mean(sim, cm, klass, level, card, engine)
					if int(r.get("quote", -1)) < 0:
						continue
					checked += 1
					var ratio: float = float(r["ratio"])
					var flag := ""
					if absf(ratio - 1.0) > TOLERANCE:
						flag = "  <-- OFF"
						bad += 1
					print("%-10s %-4d %-18s %-7d %-10d %-13.0f %-6.2fx %-5d %-5d %d%s" % [klass, level, card, engine,
						int(r["quote"]), float(r["mean"]), ratio, int(r["casts"]), int(r["crits"]), int(r["kills"]), flag])
	print("")
	print("[CARDFACE] checked %d card/level/engine cells, %d off by more than %d%%" % [checked, bad, int(TOLERANCE * 100)])
	print("[CARDFACE] %s" % ("PASS" if bad == 0 and checked > 0 else "FAIL"))
	quit(0 if bad == 0 and checked > 0 else 1)
