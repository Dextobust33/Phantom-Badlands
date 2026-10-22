# path_points.gd
# The Path point economy in one place (docs/design/paths_revamp.md 3.2, 3.3, 3.7).
#
# Everything here is a pure function of numbers so the character, the server, the client panel and the
# simulator all read ONE copy - a panel that re-derived "level / 5" itself is how the display and the
# server drift apart. Every number is a guess (G) until `pathcurve` / `pathgap` measure it.
class_name PathPoints

const GoldEconomyScript = preload("res://shared/gold_economy.gd")

## 1 point per 5 levels up to this level, then 1 per LATE_STEP levels. Early play feels exactly as it did.
const EARLY_LEVELS := 100
const EARLY_STEP := 5
const LATE_STEP := 50

## A plain node can be bought up to this many times; rank r costs r points (1, 2, 3, 4, 5 = 15 for the node).
const DEFAULT_MAX_RANK := 5

## Respecs: refund ONE branch at a time. Price is gold, in the economy's own unit (kills' worth at the level).
const RESPEC_KILLS_PER_POINT := 40
const RESPEC_BASE_ALLOWANCE := 3
const RESPEC_BONUS_LEVELS := [1000, 5000]   # one extra respec at each


static func from_level(level: int) -> int:
	"""Points the LEVEL alone has paid. Matches the old `level / 5` exactly through L100."""
	var lv: int = maxi(0, level)
	if lv <= EARLY_LEVELS:
		return lv / EARLY_STEP
	return EARLY_LEVELS / EARLY_STEP + (lv - EARLY_LEVELS) / LATE_STEP


static func legacy_bonus(ranks: Dictionary, legacy_free: Array) -> int:
	"""Points that make a grandfathered node cost what it cost when it was one point: a node bought before ranks existed is held at its
	full rank, and the difference between that rank's price and one point comes back as earned points - for as long as the node is held."""
	var bonus := 0
	for id in legacy_free:
		var r: int = int(ranks.get(String(id), 0))
		if r >= 1:
			bonus += total_cost(r) - 1
	return bonus


static func rank_cost(next_rank: int) -> int:
	"""What buying rank `next_rank` (1-based) costs."""
	return maxi(1, next_rank)


static func total_cost(rank: int) -> int:
	"""What a node held at `rank` has cost in all: 1 + 2 + ... + rank."""
	var r: int = maxi(0, rank)
	return r * (r + 1) / 2


static func respec_allowance(level: int) -> int:
	var n: int = RESPEC_BASE_ALLOWANCE
	for lv in RESPEC_BONUS_LEVELS:
		if level >= int(lv):
			n += 1
	return n


static func respec_price(level: int, points_refunded: int) -> int:
	return maxi(0, points_refunded) * RESPEC_KILLS_PER_POINT * GoldEconomyScript.kill_gold(level)
