extends RefCounted
class_name CardUpgrades

# === CARD RANK-UP UPGRADES (2026-09-03, owner direction) ===
#
# Replaces the old milestone menu, which offered the SAME options at every rank-up of every
# card: "power" (+12% effect), "efficiency" (-10% cost), plus "rider" on damage cards or
# "duration" on buff cards. Two of the three were plain scalars and the menu never changed, so
# there was no decision to make. Owner: *"I don't care for the current options and they are
# uninteresting and the same thing over and over. There should be a good variety of interesting
# choices."*
#
# Two rules came out of that conversation and both are enforced here:
#
#  1. **Three are DRAWN from a large pool**, so repeats are rare — *"3 randomly drawn from a
#     large enough pool that you don't see repeats very often"*. Anything already taken and not
#     stackable is excluded, so the menu keeps freshening as you invest in a card.
#
#  2. **Trade-offs are gated to later milestones** — *"trade-offs only on later milestones"*.
#     Early picks are pure upside while you are still learning a card; the ones that ask you to
#     give something up unlock once you know what you are doing.
#
# The four legacy ids (power / efficiency / rider / duration) are KEPT in the pool so characters
# who already spent picks keep exactly what they earned.

# Which cards an upgrade can appear on.
#   "damage" — deals direct damage        "buff"    — applies a buff to you
#   "any"    — anything                   "control" — debuff/CC oriented
const KIND_ANY := "any"
const KIND_DAMAGE := "damage"
const KIND_BUFF := "buff"
const KIND_CONTROL := "control"

# Milestone index (1-based) from which trade-off picks may be offered.
const TRADEOFF_MIN_MILESTONE := 3

const UPGRADES := [
	# ---------------------------------------------------------------- legacy four -----------
	{"id": "power", "name": "Power", "kind": KIND_ANY, "stacks": true, "tradeoff": false,
	 "desc": "+12% effect."},
	{"id": "efficiency", "name": "Efficiency", "kind": KIND_ANY, "stacks": true, "tradeoff": false,
	 "desc": "-10% cost."},
	{"id": "rider", "name": "Rider", "kind": KIND_DAMAGE, "stacks": true, "tradeoff": false,
	 "desc": "Adds a bleed, then armour-break, then a chance to stun."},
	{"id": "duration", "name": "Duration", "kind": KIND_BUFF, "stacks": true, "tradeoff": false,
	 "desc": "+2 rounds."},

	# ---------------------------------------------------------------- damage, upside --------
	{"id": "executioner", "name": "Executioner", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": false,
	 "desc": "+40% damage against a foe below 30% health."},
	{"id": "opener", "name": "Opener", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": false,
	 "desc": "+50% damage on your FIRST use each fight."},
	{"id": "overkill", "name": "Overkill", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": false,
	 "desc": "Damage beyond a kill carries into the next foe of a flock."},
	{"id": "keen", "name": "Keen Edge", "kind": KIND_DAMAGE, "stacks": true, "tradeoff": false,
	 "desc": "+8% critical chance with this card."},
	{"id": "leeching", "name": "Leeching", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": false,
	 "desc": "Heals you for 10% of the damage dealt."},
	{"id": "momentum_feed", "name": "Building", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": false,
	 "desc": "Grants an extra point of your class engine (Momentum / Read / Focus)."},

	# ---------------------------------------------------------------- buff, upside ----------
	{"id": "preload", "name": "Preload", "kind": KIND_BUFF, "stacks": false, "tradeoff": false,
	 "desc": "The buff is already active on the first round of your NEXT fight."},
	{"id": "shared", "name": "Shared", "kind": KIND_BUFF, "stacks": false, "tradeoff": false,
	 "desc": "In a party, an ally also receives it at half strength."},
	{"id": "warding", "name": "Warding", "kind": KIND_BUFF, "stacks": false, "tradeoff": false,
	 "desc": "Also grants a small shield when cast."},

	# ---------------------------------------------------------------- control, upside -------
	{"id": "unsettling", "name": "Unsettling", "kind": KIND_CONTROL, "stacks": false, "tradeoff": false,
	 "desc": "The foe's next attack is less likely to land."},
	{"id": "lingering", "name": "Lingering", "kind": KIND_CONTROL, "stacks": true, "tradeoff": false,
	 "desc": "+1 round to any debuff this card applies."},

	# ---------------------------------------------------------------- any, upside -----------
	{"id": "refund", "name": "Closing Cost", "kind": KIND_ANY, "stacks": false, "tradeoff": false,
	 "desc": "Refunds its cost when it lands the killing blow."},
	{"id": "swift", "name": "Swift", "kind": KIND_ANY, "stacks": false, "tradeoff": false,
	 "desc": "Small chance to act again immediately."},

	# ---------------------------------------------------------------- TRADE-OFFS ------------
	# Gated to TRADEOFF_MIN_MILESTONE and beyond: these are the genuinely hard picks, and a
	# player meeting them on their first rank-up would be choosing blind.
	{"id": "overdraw", "name": "Overdraw", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": true,
	 "desc": "+30% damage, but it costs 25% more."},
	{"id": "reckless", "name": "Reckless", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": true,
	 "desc": "+35% damage, but you take 5% of your health as recoil."},
	{"id": "slow_burn", "name": "Slow Burn", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": true,
	 "desc": "-25% immediate damage, but leaves a burn worth far more over time."},
	{"id": "concentrated", "name": "Concentrated", "kind": KIND_BUFF, "stacks": false, "tradeoff": true,
	 "desc": "Double strength, half the duration."},
	{"id": "reckless_guard", "name": "Open Guard", "kind": KIND_BUFF, "stacks": false, "tradeoff": true,
	 "desc": "+50% to the buff, but -15% defence while it lasts."},
	{"id": "hair_trigger", "name": "Hair Trigger", "kind": KIND_ANY, "stacks": false, "tradeoff": true,
	 "desc": "Costs 40% less, but its effect varies wildly (50%-150%)."},
	# The trade-off sub-pool needs to be as deep as the main one, or the LATE milestones - the
	# ones that are supposed to be the interesting decisions - start repeating exactly where the
	# stakes are highest. Owner: "trade-offs should likely be a large enough pool that repeats
	# are rare as well."
	{"id": "wild_swing", "name": "Wild Swing", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": true,
	 "desc": "+45% damage, but a real chance to miss outright."},
	{"id": "bloodprice", "name": "Blood Price", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": true,
	 "desc": "Paid in health instead of your resource."},
	{"id": "brittle", "name": "Brittle Strike", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": true,
	 "desc": "+30% damage, but your guard is down until your next turn."},
	{"id": "all_in", "name": "All In", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": true,
	 "desc": "Hits far harder the EMPTIER your resource bar is, and weakly when it is full."},
	{"id": "greedy", "name": "Heavy Draw", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": true,
	 "desc": "+25% damage, but the card is slower to come back around."},
	{"id": "fragile_ward", "name": "Fragile Ward", "kind": KIND_BUFF, "stacks": false, "tradeoff": true,
	 "desc": "+60% to the buff, but it shatters on the first hit you take."},
	{"id": "slow_cast", "name": "Slow Cast", "kind": KIND_BUFF, "stacks": false, "tradeoff": true,
	 "desc": "+50% to the buff, but the foe acts before you this round."},
	{"id": "costly_vigil", "name": "Costly Vigil", "kind": KIND_BUFF, "stacks": false, "tradeoff": true,
	 "desc": "Lasts twice as long, but drains resource every round it holds."},
	{"id": "provoking", "name": "Provoking", "kind": KIND_CONTROL, "stacks": false, "tradeoff": true,
	 "desc": "A stronger debuff, but it turns the foe's attention onto you."},
	{"id": "unstable_hex", "name": "Unstable Hex", "kind": KIND_CONTROL, "stacks": false, "tradeoff": true,
	 "desc": "A stronger debuff, with a small chance it lands on you instead."},
	{"id": "overreach", "name": "Overreach", "kind": KIND_CONTROL, "stacks": false, "tradeoff": true,
	 "desc": "Hits harder, but wears off a round sooner."},
	{"id": "gamblers_cut", "name": "Gambler's Cut", "kind": KIND_ANY, "stacks": false, "tradeoff": true,
	 "desc": "Half cost, but a quarter of the time it does nothing at all."},
	{"id": "sacrificial", "name": "Sacrificial", "kind": KIND_ANY, "stacks": false, "tradeoff": true,
	 "desc": "Far stronger, but the card is spent for the rest of the fight."},
]


static func upgrade_by_id(id: String) -> Dictionary:
	for u in UPGRADES:
		if String(u.get("id", "")) == id:
			return u
	return {}


static func card_kind(ability_name: String, is_damage: bool, is_buff: bool, is_control: bool) -> String:
	"""What sort of card this is, for eligibility. Callers know their own ability better than a
	table here would, so they pass the flags rather than this file duplicating a card list that
	would drift the moment a card is re-roled — the exact failure that produced War Cry sitting
	in the damage-buff slot for months."""
	if is_damage:
		return KIND_DAMAGE
	if is_buff:
		return KIND_BUFF
	if is_control:
		return KIND_CONTROL
	return KIND_ANY


static func eligible(kind: String, milestone: int, taken: Array) -> Array:
	"""Upgrades that may be OFFERED for a card of `kind` at this milestone."""
	var out: Array = []
	for u in UPGRADES:
		var u_kind := String(u.get("kind", KIND_ANY))
		if u_kind != KIND_ANY and u_kind != kind:
			continue
		if bool(u.get("tradeoff", false)) and milestone < TRADEOFF_MIN_MILESTONE:
			continue
		if not bool(u.get("stacks", false)) and String(u.get("id", "")) in taken:
			continue
		out.append(u)
	return out


static func draw_choices(kind: String, milestone: int, taken: Array, count: int = 3) -> Array:
	"""Three (or `count`) distinct upgrades for this rank-up.

	Drawn rather than fixed, so successive milestones on the same card do not repeat — the
	owner's requirement. If the eligible pool has run dry (a heavily-invested card that has
	taken every non-stacking option), the stackable ones remain, so a menu is always offered."""
	var pool := eligible(kind, milestone, taken)
	if pool.is_empty():
		# Nothing left is a bug in the pool, not a state a player should reach. Fall back to
		# the always-stackable pair rather than handing back an empty menu.
		for id in ["power", "efficiency"]:
			var u := upgrade_by_id(id)
			if not u.is_empty():
				pool.append(u)
	pool.shuffle()
	var out: Array = []
	for u in pool:
		out.append(u)
		if out.size() >= count:
			break
	return out
