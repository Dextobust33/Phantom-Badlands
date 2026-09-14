extends SceneTree
## Dungeon rarity, axis one: does a higher RANK actually drop better gear?
##
## Owner 2026-09-13 chose all three axes of dungeon rarity - loot quality, rolled modifiers, rarer
## monsters - and put loot quality first because it rides existing machinery.
##
## Before this, rank bought xp, valor, material quantity and egg rank, and had NO effect on the
## quality of what you picked up. A rank-1 and a rank-9 dungeon of the same tier drew gear from an
## identical table. This measures the distribution rather than asserting the formula: the risk
## here is not that nothing changes, it is that tiers 8-9 already FLOOR every drop at epic, so an
## upgrade that looks modest on paper can turn the whole endgame to artifacts.
const ServerScript = preload("res://server/server.gd")
const DropTablesScript = preload("res://shared/drop_tables.gd")

const LADDER := ["common", "uncommon", "rare", "epic", "legendary", "artifact"]

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _dist(srv, dt, tier: int, rank: int, n: int) -> Dictionary:
	var out := {}
	for r in LADDER:
		out[r] = 0
	var got := 0
	for i in range(n):
		var eq: Dictionary = dt.roll_dungeon_chest_equipment(tier, 50, srv._dungeon_loot_rarity_upgrade(rank))
		if eq.is_empty():
			continue          # the 55% drop gate, unchanged by rank
		got += 1
		var r := String(eq.get("rarity", "common"))
		out[r] = int(out.get(r, 0)) + 1
	out["_n"] = got
	return out


func _row(label: String, d: Dictionary) -> String:
	var n := maxi(1, int(d.get("_n", 1)))
	var parts: Array = []
	for r in LADDER:
		parts.append("%s %4.1f%%" % [r.substr(0, 4), float(int(d.get(r, 0))) / float(n) * 100.0])
	return "  %-10s %s" % [label, "  ".join(parts)]


func _at_least(d: Dictionary, rarity: String) -> float:
	var idx := LADDER.find(rarity)
	var n := maxi(1, int(d.get("_n", 1)))
	var c := 0
	for i in range(idx, LADDER.size()):
		c += int(d.get(LADDER[i], 0))
	return float(c) / float(n)


func _mean_rank(d: Dictionary) -> float:
	"""Average position on the rarity ladder. Unlike an "X or better" share this cannot saturate,
	so it stays meaningful at tiers whose floor is already epic."""
	var n := maxi(1, int(d.get("_n", 1)))
	var total := 0.0
	for i in range(LADDER.size()):
		total += float(int(d.get(LADDER[i], 0))) * float(i)
	return total / float(n)


func _init() -> void:
	var srv = ServerScript.new()
	var dt = DropTablesScript.new()
	get_root().add_child(dt)
	var n := 6000

	print("===== THE UPGRADE CURVE ITSELF =====")
	# One roll per rank, many times, so the shape is visible rather than argued about.
	print("  %-6s %8s %8s %8s" % ["rank", "+0", "+1", "+2"])
	var rank1_any := 0.0
	var rank9_any := 0.0
	for rank in [1, 3, 5, 7, 9]:
		var c := [0, 0, 0]
		for i in range(20000):
			c[clampi(srv._dungeon_loot_rarity_upgrade(rank), 0, 2)] += 1
		print("  %-6d %7.1f%% %7.1f%% %7.1f%%" % [rank,
			float(c[0]) / 200.0, float(c[1]) / 200.0, float(c[2]) / 200.0])
		if rank == 1:
			rank1_any = float(c[1] + c[2]) / 20000.0
		if rank == 9:
			rank9_any = float(c[1] + c[2]) / 20000.0
	ck(rank1_any == 0.0, "a rank-1 dungeon never upgrades - the bottom of the ladder is the baseline")
	# Bounds sit either side of RANK_LOOT_UPGRADE_MAX rather than ON it - the first version used
	# `> 0.40` against a constant of exactly 0.40 and passed only on sampling noise.
	ck(rank9_any > 0.30 and rank9_any < 0.60,
		"a rank-9 dungeon upgrades %.0f%% of drops - felt, but not every drop" % (rank9_any * 100.0))

	print("")
	print("===== WHAT THAT DOES TO REAL GEAR =====")
	for tier in [1, 5, 9]:
		print("")
		print("  tier %d" % tier)
		var d1 := _dist(srv, dt, tier, 1, n)
		var d9 := _dist(srv, dt, tier, 9, n)
		print(_row("rank 1", d1))
		print(_row("rank 9", d9))
		# MEAN LADDER POSITION, not "rare or better". The first version of this probe used the
		# rare-or-better share and FAILED at tier 9 - not because rank did nothing, but because
		# TIER_MIN_RARITY already floors tier 9 at epic, so that share is 100% at every rank. A
		# saturated measure reads identically to a broken feature. The mean never saturates.
		var lo := _mean_rank(d1)
		var hi := _mean_rank(d9)
		print("    mean rarity: %.2f -> %.2f  (0=common .. 5=artifact)" % [lo, hi])
		print("    rare or better: %.1f%% -> %.1f%%" % [_at_least(d1, "rare") * 100.0, _at_least(d9, "rare") * 100.0])
		ck(hi > lo + 0.10, "    tier %d: rank 9 drops measurably better gear" % tier)

	print("")
	print("===== THE GUARD: THE ENDGAME MUST NOT GO ALL-ARTIFACT =====")
	# Tiers 8-9 floor every drop at epic already (TIER_MIN_RARITY), so this is where a rarity
	# bump does its damage. If artifacts stop being remarkable the ladder this is meant to
	# stretch has instead been collapsed from the top.
	var t9r9 := _dist(srv, dt, 9, 9, n)
	var art := float(int(t9r9.get("artifact", 0))) / float(maxi(1, int(t9r9.get("_n", 1))))
	print("  a tier-9 rank-9 dungeon drops artifacts %.1f%% of the time" % (art * 100.0))
	ck(art < 0.25, "artifacts stay rare even at the very top (%.1f%%)" % (art * 100.0))
	var leg_plus := _at_least(t9r9, "legendary")
	print("  legendary or better: %.1f%%" % (leg_plus * 100.0))
	ck(leg_plus < 0.55, "and legendary-or-better is not the default outcome (%.1f%%)" % (leg_plus * 100.0))

	print("")
	print("===== AND THE DROP RATE ITSELF IS UNCHANGED =====")
	# Rank changes QUALITY, not how much falls out. If the count moved too, this would be two
	# buffs stacked and the tuning above would be measuring the wrong thing.
	var c1 := int(_dist(srv, dt, 5, 1, n).get("_n", 0))
	var c9 := int(_dist(srv, dt, 5, 9, n).get("_n", 0))
	print("  tier 5: %d pieces at rank 1, %d at rank 9 (of %d rolls each)" % [c1, c9, n])
	ck(abs(c1 - c9) < n / 20, "rank does not quietly change HOW MUCH drops, only how good it is")

	print("")
	if fails == 0:
		print("PASS - rank buys better gear, and the top of the ladder still means something")
	else:
		print("FAIL - %d check(s) failed" % fails)
	quit(1 if fails > 0 else 0)
