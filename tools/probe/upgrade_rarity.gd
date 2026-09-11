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
	"""Everything this kind could EVER be offered at this milestone, split by rarity."""
	var out := {"common": {}, "rare": {}}
	for u in CU.eligible(kind, milestone, []):
		var b: String = "rare" if bool(u.get("rare", false)) else "common"
		out[b][String(u.get("id", ""))] = true
	return out


func _seen_after(kind: String, milestones: int) -> Dictionary:
	"""Fraction of the eligible pool a player has LAID EYES ON after N rank-ups, by rarity."""
	var c_tot := 0.0
	var r_tot := 0.0
	for run in range(RUNS):
		var seen := {}
		var taken: Array = []
		for m in range(1, milestones + 1):
			for u in CU.draw_choices(kind, m, taken):
				seen[String(u.get("id", ""))] = true
			# a player takes one each milestone, which removes it from later draws
			var offer := CU.draw_choices(kind, m, taken)
			if offer.size() > 0:
				taken.append(String(offer[0].get("id", "")))
		var el := _eligible_ids(kind, milestones)
		var cs := 0
		var rs := 0
		for id in el["common"]:
			if seen.has(id):
				cs += 1
		for id in el["rare"]:
			if seen.has(id):
				rs += 1
		c_tot += float(cs) / maxf(1.0, float(el["common"].size()))
		r_tot += float(rs) / maxf(1.0, float(el["rare"].size()))
	return {"common": c_tot / float(RUNS), "rare": r_tot / float(RUNS)}


func _init() -> void:
	print("--- the pool now HAS two rarities ---")
	var rares := 0
	for u in CU.UPGRADES:
		if bool(u.get("rare", false)):
			rares += 1
	ck(rares > 0, "%d of %d upgrades are marked rare" % [rares, CU.UPGRADES.size()])
	ck(CU.WEIGHT_RARE < CU.WEIGHT_COMMON, "and a rare one is drawn less often (%.0f vs %.0f)" % [
		CU.WEIGHT_RARE, CU.WEIGHT_COMMON])
	# The legacy four must stay COMMON: draw_choices falls back to power/efficiency when the pool
	# runs dry, so making either rare would make the safety net itself unreliable.
	for id in ["power", "efficiency", "rider", "duration"]:
		ck(not CU.is_rare(id), "the legacy pick '%s' stays common (it is also the fallback)" % id)

	print("\n--- what a player actually SEES, measured over %d runs ---" % RUNS)
	print("    %-9s %-10s %-8s %-8s" % ["kind", "milestones", "common", "rare"])
	var rare_at_5 := {}
	for kind in ["damage", "buff", "control"]:
		for m in [1, 3, 5]:
			var r := _seen_after(kind, m)
			print("    %-9s %-10d %6.0f%%   %6.0f%%" % [kind, m, r["common"] * 100.0, r["rare"] * 100.0])
			if m == 5:
				rare_at_5[kind] = r["rare"]
		print("")

	print("--- and that is actually rare, not just labelled rare ---")
	for kind in rare_at_5:
		var pct: float = rare_at_5[kind] * 100.0
		# The uniform draw showed 93-97% of everything after five milestones. Anything near that
		# is not rare. The 2026-09-10 simulation put a workable band around 15-35%.
		ck(pct < 60.0, "%s: a player has seen %.0f%% of the rare pool after 5 milestones (was ~95%%)" % [kind, pct])
		ck(pct > 5.0, "...%s: but they are not UNREACHABLE either (%.0f%%)" % [kind, pct])

	print("\n--- an offer is still full, and still never repeats itself ---")
	for kind in ["damage", "buff", "control"]:
		var offer := CU.draw_choices(kind, 1, [])
		ck(offer.size() == CU.OFFER_SIZE, "%s offers %d" % [kind, offer.size()])
		var ids := {}
		for u in offer:
			ids[String(u.get("id", ""))] = true
		ck(ids.size() == offer.size(), "%s: no upgrade appears twice in one offer" % kind)

	print("
--- and the player can SEE that it is rare ---")
	# A rare pick that renders identically to a common one cannot be told a friend about. Two
	# halves, and the FIRST one is the one that nearly shipped broken:
	# 1. the field has to cross the wire. `_build_upgrade_offer` rebuilds each upgrade as a
	#    four-field subset, so a new field on the table does NOT travel unless it is named.
	var cm := FileAccess.get_file_as_string("res://shared/combat_manager.gd")
	ck(cm.contains('"rare": bool(u.get("rare", false)),'),
		"the offer sent to the client carries `rare` - it is a SUBSET, not the whole dict")
	# 2. and the card face has to draw it.
	var cli := FileAccess.get_file_as_string("res://client/client.gd")
	ck(cli.contains('var rare: bool = bool(up.get("rare", false))'),
		"the rank-up card reads it")
	ck(cli.contains("rarely offered"), "...and says so on the card")
	ck(cli.contains("most players will not have seen this one"), "...and in the hover")
	# A rare TRADE-OFF must still read as a trade-off: orange is a warning, gold is decoration,
	# and decoration must never overwrite a warning.
	ck(cli.contains('Color("#E0902A") if tradeoff else (Color("#FFD24A") if rare'),
		"a rare trade-off still shows the trade-off colour, not the rare colour")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
