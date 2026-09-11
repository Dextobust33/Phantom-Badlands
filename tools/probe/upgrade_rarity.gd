extends SceneTree
## Can the upgrade pool make anything RARE?
##
## Owner's goal for the chase loop: *"wide enough that some players are telling their friends about
## ones they found that their friends have probably never seen."*
##
## Measured 2026-09-10, before this: a damage card showed 41% of everything it could ever be
## offered at its FIRST rank-up, and after five milestones the chance a given upgrade had never
## appeared was 7%. `draw_choices` shuffled and took the first 9 - uniform, so nothing could be
## rare at any pool size. This measures the real draw rather than reasoning about the weight.
const CU := preload("res://shared/card_upgrades.gd")

const RUNS := 4000

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _eligible_ids(kind: String, milestone: int) -> Dictionary:
	"""Everything this kind could EVER be offered at this milestone, split by rarity tier."""
	var out := {}
	for r in CU.RARITY_ORDER:
		out[r] = {}
	for u in CU.eligible(kind, milestone, []):
		out[CU.rarity_of(u)][String(u.get("id", ""))] = true
	return out


func _seen_after(kind: String, milestones: int) -> Dictionary:
	"""Fraction of each rarity tier a player has LAID EYES ON after N rank-ups."""
	var tot := {}
	for r in CU.RARITY_ORDER:
		tot[r] = 0.0
	var el := _eligible_ids(kind, milestones)
	for run in range(RUNS):
		var seen := {}
		var taken: Array = []
		for m in range(1, milestones + 1):
			var offer := CU.draw_choices(kind, m, taken)
			for u in offer:
				seen[String(u.get("id", ""))] = true
			# a player TAKES one each milestone, which removes it from later draws
			if offer.size() > 0:
				taken.append(String(offer[0].get("id", "")))
		for r in CU.RARITY_ORDER:
			var hit := 0
			for id in el[r]:
				if seen.has(id):
					hit += 1
			tot[r] += float(hit) / maxf(1.0, float(el[r].size()))
	var out := {}
	for r in CU.RARITY_ORDER:
		out[r] = tot[r] / float(RUNS)
	return out


func _init() -> void:
	print("--- the pool has FOUR rarities, using the vocabulary loot already uses ---")
	var counts := {}
	for r in CU.RARITY_ORDER:
		counts[r] = 0
	for u in CU.UPGRADES:
		counts[CU.rarity_of(u)] += 1
	var line := ""
	for r in CU.RARITY_ORDER:
		line += "%s %d   " % [r, counts[r]]
	print("    " + line.strip_edges())
	ck(CU.RARITY_ORDER.size() == 4, "four tiers: %s" % str(CU.RARITY_ORDER))
	for r in CU.RARITY_ORDER:
		ck(counts[r] > 0, "'%s' is not an empty tier (%d upgrades)" % [r, counts[r]])
	# The names must be the LOOT names, not a second scale invented here.
	var DT = load("res://shared/drop_tables.gd")
	for r in CU.RARITY_ORDER:
		ck(DT.RARITY_COLORS.has(r), "'%s' is a rarity the loot table already knows" % r)
	# Weight must fall as rarity rises, or the ladder is decoration.
	var falling := true
	for i in range(1, CU.RARITY_ORDER.size()):
		if float(CU.RARITY_WEIGHTS[CU.RARITY_ORDER[i]]) >= float(CU.RARITY_WEIGHTS[CU.RARITY_ORDER[i - 1]]):
			falling = false
	ck(falling, "each tier is drawn strictly less often than the one below it")
	# The legacy four must stay COMMON: draw_choices falls back to power/efficiency when the
	# pool runs dry, so a rarer fallback would make the safety net itself unreliable.
	for id in ["power", "efficiency", "rider", "duration"]:
		ck(CU.rarity_by_id(id) == CU.RARITY_COMMON,
			"the legacy pick '%s' stays common (it is also the fallback)" % id)

	print("")
	print("--- and the player can SEE which tier it is, at a glance ---")
	# Owner: *"They should also be visually distinct, colored by [rarity] or have a visual gauge
	# so they can be differentiated from commons at a glance during the upgrade offer."*
	# Two halves, and the FIRST is the one that silently breaks: the field must cross the wire.
	# `_build_upgrade_offer` rebuilds each upgrade as a SUBSET, so a new field does not travel
	# unless it is named there - that already cost one no-op-that-looked-finished today.
	var cm := FileAccess.get_file_as_string("res://shared/combat_manager.gd")
	ck(cm.contains('"rarity": CU.rarity_of(u),'),
		"the offer carries the rarity TIER - the payload is a subset, not the whole dict")
	var cli := FileAccess.get_file_as_string("res://client/client.gd")
	ck(cli.contains("func _upgrade_rarity_color("), "the card resolves a rarity COLOUR")
	ck(cli.contains("RARITY_COLORS"),
		"...from the same table loot uses, not a second palette invented for upgrades")
	ck(cli.contains("func _upgrade_rarity_gauge("), "and a GAUGE, so the tier is a shape too")
	# Colour alone is not enough: green and blue are the pair most often confused, and they are
	# exactly uncommon and rare.
	ck(cli.contains("CardUpgrades.RARITY_ORDER.size()"),
		"...sized off RARITY_ORDER, so adding a tier cannot leave the gauge behind")
	ck(cli.contains("sb.border_color = _rc.lerp("),
		"the tile BORDER takes the rarity colour, dimmed so common does not shout")
	# The trade-off warning must survive the decoration.
	ck(cli.contains('sb.bg_color = Color("#2A1F14") if tradeoff'),
		"a trade-off still marks itself on the BACKGROUND - rarity took the border, not the warning")

	print("")
	print("--- an offer is still FULL, and still never repeats itself ---")
	# The weighted draw replaced a shuffle-and-take-N. Weighting must not cost the player
	# choices, and a weighted draw WITH replacement would happily offer the same upgrade twice.
	for kind in ["damage", "buff", "control"]:
		var offer := CU.draw_choices(kind, 1, [])
		ck(offer.size() == CU.OFFER_SIZE, "%s offers %d of %d" % [kind, offer.size(), CU.OFFER_SIZE])
		var ids := {}
		for u in offer:
			ids[String(u.get("id", ""))] = true
		ck(ids.size() == offer.size(), "%s: no upgrade appears twice in one offer" % kind)

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
