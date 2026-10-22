extends RefCounted
## `dungeoncardswap` (docs/design/variety_item11.md section 2.4; owner 2026-10-22: "every class has 2+ dungeon cards worth swapping in").
##
## For each class and each tier the audit (1) finds the class's WEAKEST deck slot - the card whose removal costs the least - and (2) swaps each dungeon card of that tier into that slot, measuring
## win and death rates against the unswapped deck on the SAME fights (fight i is the same character and monster in both arms, per-fight seeds). A card is WORTH SWAPPING for a class when it raises the
## win rate by SIGNIFICANT_PP or more; the goal is two or more per class. A dungeon card is universal, so "worth swapping" is a per-class question and the answer is the per-class buff list.
##
## THE POLICY ASSUMPTION, stated because it is the weakest part: the simulator's class policies only know the class's own cards, so a dungeon card is played by a generic rule - guard / shield / heal
## cards when under 65% HP, Execute under 40% monster HP, rage / focus / timestop at most once per four rounds, everything else whenever it is in hand and affordable. That models a competent, not a
## perfect, player. Cards whose value is a rider the fight does not measure (plunder, tribute: loot and valor) are UNDER-reported, as `compcards` already says of the companion cards.
const DT = preload("res://shared/drop_tables.gd")
const PR = preload("res://shared/power_rank.gd")
const ALL := ["Fighter", "Barbarian", "Paladin", "Wizard", "Sorcerer", "Sage", "Grifter", "Ranger", "Ninja"]
const SIGNIFICANT_PP := 6.0
const WANT_PER_CLASS := 2


static func level_for_tier(t: int) -> int:
	"""A representative character level for a tier's cards: 40% up the band (tiers 1-5 by the monster band; above that a fixed mid-band level)."""
	if t >= 6:
		return {6: 250, 7: 1000, 8: 3000, 9: 7000}.get(t, 250)
	var b: Dictionary = PR.TIER_LEVEL_BANDS[t]
	return int(b["min"]) + int(round((int(b["max"]) - int(b["min"])) * 0.4))


## A card cannot raise a win rate that is already 97%, so the fights are made FAIR first: the monster's HP is scaled, per class and level, until the unswapped deck wins about 60% of them
## (the design target for a normal fight). The same monster strength is then used for every arm. A card is measured where a card can matter: in a fight that is in doubt.
const HP_MULTS := [1.0, 2.0, 4.0, 8.0, 16.0]
const TARGET_WIN := 62.0


static func _fair_hp_mult(sim, klass: String, level: int, n: int) -> float:
	for m in HP_MULTS:
		var base: Dictionary = _arm(sim, klass, level, "", "", n, "fair", m)
		if float(base["win"]) <= TARGET_WIN:
			return float(m)
	return float(HP_MULTS[HP_MULTS.size() - 1])


static func _arm(sim, klass: String, level: int, remove: String, add: String, n: int, tag: String, hp_mult: float = 1.0) -> Dictionary:
	var w := 0
	var d := 0
	var casts := 0
	for i in range(n):
		seed(hash("dcswap|%s|%d|%s|%d" % [klass, level, tag, i]))
		sim._dc_remove = remove
		sim._dc_card = add
		var r = sim.run_fight(level, "average", "normal", hp_mult, 1.0, 1.0, klass)
		sim._dc_remove = ""
		sim._dc_card = ""
		if bool(r.get("win", false)):
			w += 1
		if bool(r.get("died", false)):
			d += 1
		casts += int(r.get("dc_casts", 0))
	return {"win": 100.0 * w / n, "death": 100.0 * d / n, "casts": float(casts) / float(n)}


static func _deck_of(sim, klass: String) -> Array:
	var ch = sim.make_char(10, "average", klass, "Human")
	ch.initialize_deck_collection_if_needed()
	return ch.combat_deck_collection.keys()


static func audit(sim) -> void:
	var classes: Array = ALL
	var tiers: Array = [1, 3, 5]
	var n := 30
	for a in OS.get_cmdline_user_args():
		var sa := String(a)
		if sa.begins_with("--class="):
			classes = [sa.substr(8)]
		elif sa.begins_with("--tiers="):
			tiers = Array(sa.substr(8).split(",")).map(func(x): return int(x))
		elif sa.begins_with("--n="):
			n = int(sa.substr(4))
	print("\n===== DUNGEON CARD SWAP (dungeoncardswap) =====")
	print("a card is WORTH SWAPPING for a class when swapped into its weakest deck slot it raises the win rate by >= %.0fpp over the same deck on the same fights (%d paired fights). Goal: %d+ per class." % [SIGNIFICANT_PP, n, WANT_PER_CLASS])
	var by_tier: Dictionary = {}
	for slug in DT.DUNGEON_CARD_DATA:
		var t: int = int(DT.DUNGEON_CARD_DATA[slug].get("tier", 1))
		if not by_tier.has(t):
			by_tier[t] = []
		by_tier[t].append(String(slug))
	var worth: Dictionary = {}
	var measured_cards := 0
	for k in classes:
		worth[k] = []
		var deck: Array = _deck_of(sim, k)
		# The weakest slot is decided ONCE per class, at a mid reference level, and reused for every tier: it is a property of the deck, and re-deciding it per tier cost most of the run.
		var ref_level: int = level_for_tier(3)
		var ref_hp: float = _fair_hp_mult(sim, k, ref_level, n)
		var weakest := ""
		var best_win := -1.0
		for c in deck:
			var arm: Dictionary = _arm(sim, k, ref_level, String(c), "", n, "base", ref_hp)
			if float(arm["win"]) > best_win:
				best_win = float(arm["win"])
				weakest = String(c)
		for t in tiers:
			if not by_tier.has(t):
				continue
			var lvl: int = level_for_tier(t)
			# the weakest slot: the card whose REMOVAL costs the least
			var hpm: float = _fair_hp_mult(sim, k, lvl, n)
			var base: Dictionary = _arm(sim, k, lvl, "", "", n, "base", hpm)
			var line := "%-9s T%d L%-5d hp x%.1f base %3.0f%% weakest slot: %-12s |" % [k, t, lvl, hpm, base["win"], weakest]
			for slug in by_tier[t]:
				var cid: String = "dungeon_card_" + String(slug)
				var sw: Dictionary = _arm(sim, k, lvl, weakest, cid, n, "base", hpm)
				var dw: float = float(sw["win"]) - float(base["win"])
				measured_cards += 1
				var mark := " "
				if dw >= SIGNIFICANT_PP:
					mark = "+"
					worth[k].append(String(slug))
				elif dw <= -SIGNIFICANT_PP:
					mark = "-"
				line += " %s%s %+.0f" % [String(slug).substr(0, 9), mark, dw]
			print(line)
	print("\nPER CLASS - cards worth swapping in (+), at the tiers measured:")
	var fails := 0
	for k in classes:
		var cnt: int = worth[k].size()
		var ok: bool = cnt >= WANT_PER_CLASS
		if not ok:
			fails += 1
		print("  %s %-9s %2d  %s" % ["PASS" if ok else "FAIL", k, cnt, ", ".join(worth[k])])
	print("(%d card/class cells measured. A class below %d needs per-class buffs on its best candidates; see the doc.)" % [measured_cards, WANT_PER_CLASS])
	print("PASS" if fails == 0 else "FAIL (%d classes under %d)" % [fails, WANT_PER_CLASS])
