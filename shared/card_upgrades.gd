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

# 2026-09-04 — WORDING RULE, learned from a player report: "some of the upgrades need reviewed
# as they don't make sense like get more of your class resource if used with a full bar?"
#
# The game has TWO things a card can give back and the descriptions were calling both of them
# "your class resource":
#   * the SPENDABLE BAR   — mana / stamina / energy. Say it by those names.
#   * the CLASS ENGINE    — Momentum (warrior) / Read (trickster) / Focus (mage), fed by
#                           `_feed_class_engine`. Always name the three explicitly.
# Conflating them makes an upgrade read as nonsense ("more resource while already full"), when
# what it actually does — convert a wasted cast on a capped bar into engine progress — is one of
# the better picks in the pool.
const UPGRADES := [
	# ---------------------------------------------------------------- legacy four -----------
	{"id": "power", "wired": true, "name": "Power", "kind": KIND_ANY, "stacks": true, "tradeoff": false,
	 "desc": "+12% effect."},
	{"id": "efficiency", "wired": true, "name": "Efficiency", "kind": KIND_ANY, "stacks": true, "tradeoff": false,
	 "desc": "-10% cost."},
	{"id": "rider", "wired": true, "name": "Rider", "kind": KIND_DAMAGE, "stacks": true, "tradeoff": false,
	 "desc": "Adds a bleed, then armour-break, then a chance to stun."},
	{"id": "duration", "wired": true, "name": "Duration", "kind": KIND_BUFF, "stacks": true, "tradeoff": false,
	 "desc": "+2 rounds."},

	# ---------------------------------------------------------------- damage, upside --------
	{"id": "executioner", "wired": true, "name": "Executioner", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": false,
	 "desc": "+40% damage against a foe below 30% health."},
	{"id": "opener", "wired": true, "name": "Opener", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": false,
	 "desc": "+50% damage on your FIRST use each fight."},
	# "Overkill" (excess damage carries to the next flock member) was designed and then CUT
	# before it shipped: every ability body clamps the monster's HP at zero, so by the time any
	# hook can see the result the excess has already been discarded, and reconstructing it would
	# mean touching ten ability bodies. Offering a choice that silently does nothing is exactly
	# the defect this redesign exists to fix, so it is not in the pool. Revisit if the damage
	# path ever reports pre-clamp damage.
	{"id": "keen", "wired": true, "name": "Keen Edge", "kind": KIND_DAMAGE, "stacks": true, "tradeoff": false,
	 "desc": "+8% critical chance with this card."},
	{"id": "leeching", "wired": true, "name": "Leeching", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": false,
	 "desc": "Heals you for 10% of the damage dealt."},
	{"id": "momentum_feed", "wired": true, "name": "Building", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": false,
	 "desc": "Grants an extra point of your class engine (Momentum, Rage, Conviction, Focus or Read)."},

	# ---------------------------------------------------------------- buff, upside ----------
	{"id": "preload", "wired": true, "name": "Preload", "kind": KIND_BUFF, "stacks": false, "tradeoff": false,
	 "desc": "The buff is already active on the first round of your NEXT fight."},
	{"id": "shared", "wired": true, "name": "Shared", "kind": KIND_BUFF, "stacks": false, "tradeoff": false,
	 "desc": "In a party, an ally also receives it at half strength."},
	{"id": "warding", "wired": true, "name": "Warding", "kind": KIND_BUFF, "stacks": false, "tradeoff": false,
	 "desc": "Also grants a small shield when cast."},

	# ---------------------------------------------------------------- control, upside -------
	{"id": "unsettling", "wired": true, "name": "Unsettling", "kind": KIND_CONTROL, "stacks": false, "tradeoff": false,
	 "desc": "The foe's next attack is less likely to land."},
	# "Lingering" (+1 round to a debuff) and "Overreach" (harder but a round shorter) were both
	# CUT after implementation was attempted. They describe a duration mechanic that debuffs in
	# this game do not have: `monster_sabotaged` is a persistent combat value with no rounds at
	# all, and `enemy_distracted` is consumed by the next attack rather than ticking down. There
	# is no round counter for either to modify. Adding one purely so two upgrades could exist
	# would be inventing a mechanic to justify a name - so they are out, like Overkill before
	# them. Revisit if debuffs ever gain real durations.

	# ---------------------------------------------------------------- any, upside -----------
	{"id": "refund", "wired": true, "name": "Closing Cost", "kind": KIND_ANY, "stacks": false, "tradeoff": false,
	 "desc": "Refunds its cost when it lands the killing blow."},
	{"id": "swift", "wired": true, "name": "Swift", "kind": KIND_ANY, "stacks": false, "tradeoff": false,
	 "desc": "Small chance to act again immediately."},

	# ---------------------------------------------------------------- TRADE-OFFS ------------
	# Gated to TRADEOFF_MIN_MILESTONE and beyond: these are the genuinely hard picks, and a
	# player meeting them on their first rank-up would be choosing blind.
	# ------------------------------------------------- pool widening (2026-09-03) ------------
	# Reported from play: a buff card's rank-up offered only EIGHT choices, and the whole
	# premise was *"a large enough pool that you don't see repeats very often"*. Measured, the
	# UPSIDE-ONLY pools were damage 10 / buff 8 / control 5 against an OFFER_SIZE of 9 — so a
	# milestone-1 damage offer showed nine of the ten that exist, buff could not fill the
	# offer at all, and control showed the same five every time. The "repeats are rare" figure
	# quoted earlier was measured on the FULL pool at late milestones, which is not where a
	# player meets this.
	#
	# These are differentiated by CONDITION rather than by magnitude. The game has a modest set
	# of levers — heal, resource, shield, distract, stun, damage reduction, the class engines —
	# and fourteen re-scalings of "gain a small thing" would be the same non-choice the old
	# three-option menu was. WHEN an upgrade pays changes how a card is played; how much it
	# pays does not. Every one below fires through a lever that already exists; nothing here
	# invents a mechanic, which is why Overkill and Lingering were cut rather than faked.
	{"id": "mending", "wired": true, "name": "Mending", "kind": KIND_ANY, "stacks": false, "tradeoff": false,
	 "desc": "Heals you for 4% of your health each time you play this."},
	{"id": "second_wind", "wired": true, "name": "Second Wind", "kind": KIND_ANY, "stacks": false, "tradeoff": false,
	 "desc": "Gives back 8% of your mana / stamina / energy on cast."},
	{"id": "bulwark", "wired": true, "name": "Bulwark", "kind": KIND_ANY, "stacks": false, "tradeoff": false,
	 "desc": "Shields you for 9% of your health — but only while you are below half."},
	{"id": "steadfast", "wired": true, "name": "Steadfast", "kind": KIND_ANY, "stacks": false, "tradeoff": false,
	 "desc": "Take 10% less damage for 2 rounds after playing this."},
	{"id": "kindling", "wired": true, "name": "Kindling", "kind": KIND_ANY, "stacks": false, "tradeoff": false,
	 "desc": "Cast it on a FULL resource bar and it grants a point of your class engine (Momentum, Rage, Conviction, Focus or Read) instead of wasting the cast."},
	{"id": "desperate", "wired": true, "name": "Desperation", "kind": KIND_ANY, "stacks": false, "tradeoff": false,
	 "desc": "Grants TWO points of your class engine (Momentum, Rage, Conviction, Focus or Read) while you are below a third health."},
	{"id": "opening_act", "wired": true, "name": "Opening Act", "kind": KIND_ANY, "stacks": false, "tradeoff": false,
	 "desc": "The FIRST time you play this in a fight, it costs nothing."},
	{"id": "relentless", "wired": true, "name": "Relentless", "kind": KIND_ANY, "stacks": false, "tradeoff": false,
	 "desc": "Every third cast of this card gives back a third of your mana / stamina / energy."},
	{"id": "vindication", "wired": true, "name": "Vindication", "kind": KIND_ANY, "stacks": false, "tradeoff": false,
	 "desc": "Heals you for 6% of your health when this lands a killing blow."},
	{"id": "disorienting", "wired": true, "name": "Disorienting", "kind": KIND_CONTROL, "stacks": false, "tradeoff": false,
	 "desc": "One cast in four leaves the enemy swinging wide."},
	{"id": "pinning", "wired": true, "name": "Pinning", "kind": KIND_CONTROL, "stacks": false, "tradeoff": false,
	 "desc": "12% chance to stun the enemy outright."},
	{"id": "harrying", "wired": true, "name": "Harrying", "kind": KIND_CONTROL, "stacks": false, "tradeoff": false,
	 "desc": "Grants a point of your class engine (Momentum, Rage, Conviction, Focus or Read) whenever the enemy is stunned or distracted."},
	{"id": "demoralising", "wired": true, "name": "Demoralising", "kind": KIND_CONTROL, "stacks": false, "tradeoff": false,
	 "desc": "Shields you for 5% of your health while the enemy is stunned or rattled."},
	{"id": "entrenched", "wired": true, "name": "Entrenched", "kind": KIND_BUFF, "stacks": false, "tradeoff": false,
	 "desc": "Also shields you for 7% of your health when the buff goes up."},
	{"id": "renewing", "wired": true, "name": "Renewing", "kind": KIND_BUFF, "stacks": false, "tradeoff": false,
	 "desc": "Heals you for 5% of your health when the buff goes up."},

	{"id": "overdraw", "wired": true, "name": "Overdraw", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": true,
	 "desc": "+30% damage, but it costs 25% more."},
	{"id": "reckless", "wired": true, "name": "Reckless", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": true,
	 "desc": "+35% damage, but you take 5% of your health as recoil."},
	{"id": "slow_burn", "wired": true, "name": "Slow Burn", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": true,
	 "desc": "-25% immediate damage, but leaves a burn worth far more over time."},
	{"id": "concentrated", "wired": true, "name": "Concentrated", "kind": KIND_BUFF, "stacks": false, "tradeoff": true,
	 "desc": "Double strength, half the duration."},
	{"id": "reckless_guard", "wired": true, "name": "Open Guard", "kind": KIND_BUFF, "stacks": false, "tradeoff": true,
	 "desc": "+50% to the buff, but -15% defence while it lasts."},
	{"id": "hair_trigger", "wired": true, "name": "Hair Trigger", "kind": KIND_ANY, "stacks": false, "tradeoff": true,
	 "desc": "Costs 40% less, but its effect varies wildly (50%-150%)."},
	# The trade-off sub-pool needs to be as deep as the main one, or the LATE milestones - the
	# ones that are supposed to be the interesting decisions - start repeating exactly where the
	# stakes are highest. Owner: "trade-offs should likely be a large enough pool that repeats
	# are rare as well."
	{"id": "wild_swing", "wired": true, "name": "Wild Swing", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": true,
	 "desc": "+45% damage, but a real chance to miss outright."},
	{"id": "bloodprice", "wired": true, "name": "Blood Price", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": true,
	 "desc": "Paid in health instead of your resource."},
	{"id": "brittle", "wired": true, "name": "Brittle Strike", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": true,
	 "desc": "+30% damage, but your guard is down until your next turn."},
	{"id": "all_in", "wired": true, "name": "All In", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": true,
	 "desc": "Hits far harder the EMPTIER your resource bar is, and weakly when it is full."},
	{"id": "greedy", "wired": true, "name": "Heavy Draw", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": true,
	 "desc": "+25% damage, but the card is slower to come back around."},
	{"id": "fragile_ward", "wired": true, "name": "Fragile Ward", "kind": KIND_BUFF, "stacks": false, "tradeoff": true,
	 "desc": "+60% to the buff, but it shatters on the first hit you take."},
	{"id": "slow_cast", "wired": true, "name": "Slow Cast", "kind": KIND_BUFF, "stacks": false, "tradeoff": true,
	 "desc": "+50% to the buff, but the foe acts before you this round."},
	{"id": "costly_vigil", "wired": true, "name": "Costly Vigil", "kind": KIND_BUFF, "stacks": false, "tradeoff": true,
	 "desc": "Lasts twice as long, but drains resource every round it holds."},
	{"id": "provoking", "wired": true, "name": "Provoking", "kind": KIND_CONTROL, "stacks": false, "tradeoff": true,
	 "desc": "A stronger debuff, and the foe turns off your companion and onto YOU."},
	{"id": "unstable_hex", "wired": true, "name": "Unstable Hex", "kind": KIND_CONTROL, "stacks": false, "tradeoff": true,
	 "desc": "A stronger debuff, with a small chance it lands on you instead."},
	{"id": "gamblers_cut", "wired": true, "name": "Gambler's Cut", "kind": KIND_ANY, "stacks": false, "tradeoff": true,
	 "desc": "Half cost, but a quarter of the time it does nothing at all."},
	{"id": "sacrificial", "wired": true, "name": "Sacrificial", "kind": KIND_ANY, "stacks": false, "tradeoff": true,
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
		# An upgrade whose effect is not yet consumed by combat must never be OFFERED. Shipping
		# a choice that silently does nothing is the defect this whole redesign exists to
		# remove, so the gate is here rather than in a reviewer's memory. Flip `wired` to true
		# in the same change that implements the effect.
		if not bool(u.get("wired", false)):
			continue
		var u_kind := String(u.get("kind", KIND_ANY))
		if u_kind != KIND_ANY and u_kind != kind:
			continue
		if bool(u.get("tradeoff", false)) and milestone < TRADEOFF_MIN_MILESTONE:
			continue
		if not bool(u.get("stacks", false)) and String(u.get("id", "")) in taken:
			continue
		out.append(u)
	return out


# How many upgrades are laid out at a rank-up. The player previews all of them, they are then
# hidden and shuffled, and the player REVEALS a few before committing to one — the owner's
# design: *"it would be nice if it showed a random 9 of them that players get to see for a
# moment then they get hidden and placed in a random spot so the players get to 'reveal' 3 of
# them then choose 1 out of those."* Mirrors the Prize Shuffle loot flow, so it is an idiom
# players already know rather than a second one to learn.
const OFFER_SIZE := 9
const REVEALS_ALLOWED := 3

static func draw_choices(kind: String, milestone: int, taken: Array, count: int = OFFER_SIZE, exclude: Array = []) -> Array:
	"""Three (or `count`) distinct upgrades for this rank-up.

	Drawn rather than fixed, so successive milestones on the same card do not repeat — the
	owner's requirement. If the eligible pool has run dry (a heavily-invested card that has
	taken every non-stacking option), the stackable ones remain, so a menu is always offered."""
	var pool := eligible(kind, milestone, taken)
	# 2026-09-05 — drop upgrades that cannot do anything for THIS card, before the draw rather
	# than after, so the offer still fills to `count` instead of quietly shrinking. Reported:
	# "I've got a Duration upgrade option for forcefield. I don't think that's viable" — correct,
	# Forcefield's shield has a CAPACITY, not a duration; it lasts until it is spent.
	if not exclude.is_empty():
		var filtered: Array = []
		for u in pool:
			if not (String(u.get("id", "")) in exclude):
				filtered.append(u)
		if not filtered.is_empty():
			pool = filtered
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
