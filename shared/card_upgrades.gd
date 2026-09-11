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
# 2026-09-08 - KIND is what stops an upgrade being offered on a card it cannot help. Four were
# marked KIND_ANY while their wiring requires DAMAGE DEALT or a KILL, so they were offered on
# Iron Skin, War Cry, Fortify, Rally, Forcefield, Haste, Analyze and Paralyze, where taking one
# was a wasted pick:
#   swift        rides the extra-turn roll, gated on `imprint_damage_dealt > 0`
#   sacrificial  doubles the damage - of which a buff card has none
#   vindication  heals when THIS lands a killing blow
#   refund       refunds the cost when THIS lands the killing blow
# Found by `-- upgradefit`, which casts every card with and without every upgrade it can be
# offered and compares the results, rather than trusting a hand-kept table of requirements.
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
	{"id": "rider", "trigger": "chance", "wired": true, "name": "Rider", "kind": KIND_DAMAGE, "stacks": true, "tradeoff": false,
	 "desc": "Adds a bleed, then armour-break, then a chance to stun."},
	{"id": "duration", "wired": true, "name": "Duration", "kind": KIND_BUFF, "stacks": true, "tradeoff": false,
	 "desc": "+2 rounds."},

	# ---------------------------------------------------------------- damage, upside --------
	{"id": "executioner", "trigger": "foe_hp_below", "at": 0.30, "rarity": "uncommon", "wired": true, "name": "Executioner", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": false,
	 "desc": "+40% damage against a foe below 30% health."},
	{"id": "opener", "trigger": "first_use", "rarity": "uncommon", "wired": true, "name": "Opener", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": false,
	 "desc": "+50% damage on your FIRST use each fight."},
	# "Overkill" (excess damage carries to the next flock member) was designed and then CUT
	# before it shipped: every ability body clamps the monster's HP at zero, so by the time any
	# hook can see the result the excess has already been discarded, and reconstructing it would
	# mean touching ten ability bodies. Offering a choice that silently does nothing is exactly
	# the defect this redesign exists to fix, so it is not in the pool. Revisit if the damage
	# path ever reports pre-clamp damage.
	{"id": "keen", "trigger": "chance", "wired": true, "name": "Keen Edge", "kind": KIND_DAMAGE, "stacks": true, "tradeoff": false,
	 "desc": "+8% critical chance with this card."},
	{"id": "leeching", "wired": true, "name": "Leeching", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": false,
	 "desc": "Heals you for 10% of the damage dealt."},
	{"id": "momentum_feed", "wired": true, "name": "Building", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": false,
	 "desc": "Grants an extra point of your class engine (Momentum, Rage, Conviction, Focus or Read)."},


	# ---------------------------------------------------------------- 2026-09-11 pool widening
	# Step 3 of the variety work, and authored AGAINST THE MEASUREMENT rather than by taste.
	# `tools/probe/upgrade_variety.gd` said damage held 13 entries while crit, mitigation, the
	# extra turn and chip-from-discard held ONE EACH, and that the thin RARITY cells were
	# buff-uncommon and epic for buff and control. So: nothing here moves the damage number, and
	# three of the five are KIND_ANY, which is the only way to lift buff and control at once.
	#
	# Every one declares a trigger, so it arrives legible instead of becoming another invisible
	# pick - the whole point of steps 1 and 2.
	{"id": "sure_strike", "rarity": "rare", "trigger": "first_use", "wired": true,
	 "name": "Sure Strike", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": false,
	 "desc": "Your FIRST cast each fight is a guaranteed critical."},
	{"id": "last_stand", "rarity": "epic", "trigger": "self_hp_below", "at": 0.25, "wired": true,
	 "name": "Last Stand", "kind": KIND_ANY, "stacks": false, "tradeoff": false,
	 "desc": "Below a quarter health, playing this also cuts incoming damage by 25% for 2 rounds."},
	{"id": "second_look", "rarity": "epic", "trigger": "on_cycle", "wired": true,
	 "name": "Second Look", "kind": KIND_ANY, "stacks": false, "tradeoff": false,
	 "desc": "REVEAL: when you do NOT play this card, it gives part of your bar back as it cycles."},
	{"id": "slow_mend", "rarity": "uncommon", "trigger": "on_cycle", "wired": true,
	 "name": "Slow Mend", "kind": KIND_ANY, "stacks": false, "tradeoff": false,
	 "desc": "REVEAL: when you do NOT play this card, it knits a little health as it cycles."},
	{"id": "rally_point", "rarity": "uncommon", "trigger": "foe_hp_below", "at": 0.50, "wired": true,
	 "name": "Rally Point", "kind": KIND_ANY, "stacks": false, "tradeoff": false,
	 "desc": "Once the foe is wounded, this also feeds your class engine (Momentum, Rage, Conviction, Focus or Read)."},

	# ------------------------------------------------------- REVEAL (the cycle value) --------
	# Owner 2026-09-10: *"we could take advantage of card upgrades and make these types of reveal
	# options show up in that pool as well."* Right, and it is the better half of the opt-in:
	# a dungeon card has to DROP, whereas an upgrade is something a player chooses to build
	# toward on a card they already run - and it costs a milestone, which is a real price.
	#
	# KIND_ANY because EVERY card can be discarded unplayed; there is no card shape this cannot
	# apply to. That also makes them the first upgrades whose effect fires when the card is NOT
	# used, which is why the wiring lives in `_cycle_unplayed` rather than in a cast path.
	{"id": "reveal_engine", "trigger": "on_cycle", "rarity": "rare", "wired": true, "name": "Foretold", "kind": KIND_ANY, "stacks": false, "tradeoff": false,
	 "desc": "REVEAL: when you do NOT play this card, it feeds 1 point of your class engine as it cycles."},
	{"id": "reveal_ward", "trigger": "on_cycle", "rarity": "rare", "wired": true, "name": "Held in Reserve", "kind": KIND_ANY, "stacks": false, "tradeoff": false,
	 "desc": "REVEAL: when you do NOT play this card, it leaves a small ward (3% of your max health) as it cycles."},
	{"id": "reveal_spark", "trigger": "on_cycle", "rarity": "rare", "wired": true, "name": "Smouldering", "kind": KIND_ANY, "stacks": false, "tradeoff": false,
	 "desc": "REVEAL: when you do NOT play this card, it still stings the enemy for a little damage as it cycles."},

	# ---------------------------------------------------------------- buff, upside ----------
	{"id": "preload", "rarity": "epic", "wired": true, "name": "Preload", "kind": KIND_BUFF, "stacks": false, "tradeoff": false,
	 "desc": "The buff is already active on the first round of your NEXT fight."},
	{"id": "shared", "rarity": "rare", "wired": true, "name": "Shared", "kind": KIND_BUFF, "stacks": false, "tradeoff": false,
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
	{"id": "refund", "trigger": "on_kill", "rarity": "uncommon", "wired": true, "name": "Closing Cost", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": false,
	 "desc": "Refunds its cost when it lands the killing blow."},
	{"id": "swift", "trigger": "chance", "rarity": "epic", "wired": true, "name": "Swift", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": false,
	 "desc": "12% chance the enemy loses its turn, so you act again. Damaging cards only."},

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
	{"id": "bulwark", "trigger": "self_hp_below", "at": 0.50, "wired": true, "name": "Bulwark", "kind": KIND_ANY, "stacks": false, "tradeoff": false,
	 "desc": "Shields you for 9% of your health — but only while you are below half."},
	{"id": "steadfast", "wired": true, "name": "Steadfast", "kind": KIND_ANY, "stacks": false, "tradeoff": false,
	 "desc": "Take 10% less damage for 2 rounds after playing this."},
	{"id": "kindling", "trigger": "resource_full", "rarity": "uncommon", "wired": true, "name": "Kindling", "kind": KIND_ANY, "stacks": false, "tradeoff": false,
	 "desc": "Cast it on a FULL resource bar and it grants a point of your class engine (Momentum, Rage, Conviction, Focus or Read) instead of wasting the cast."},
	{"id": "desperate", "trigger": "self_hp_below", "at": 0.34, "rarity": "uncommon", "wired": true, "name": "Desperation", "kind": KIND_ANY, "stacks": false, "tradeoff": false,
	 "desc": "Grants TWO points of your class engine (Momentum, Rage, Conviction, Focus or Read) while you are below a third health."},
	{"id": "opening_act", "trigger": "first_use", "rarity": "epic", "wired": true, "name": "Opening Act", "kind": KIND_ANY, "stacks": false, "tradeoff": false,
	 "desc": "The FIRST time you play this in a fight, it costs nothing."},
	{"id": "relentless", "trigger": "cast_cadence", "every": 3, "rarity": "uncommon", "wired": true, "name": "Relentless", "kind": KIND_ANY, "stacks": false, "tradeoff": false,
	 "desc": "Every third cast of this card gives back a third of your mana / stamina / energy."},
	{"id": "vindication", "trigger": "on_kill", "rarity": "uncommon", "wired": true, "name": "Vindication", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": false,
	 "desc": "Heals you for 6% of your health when this lands a killing blow."},
	{"id": "disorienting", "trigger": "chance", "wired": true, "name": "Disorienting", "kind": KIND_CONTROL, "stacks": false, "tradeoff": false,
	 "desc": "One cast in four leaves the enemy swinging wide."},
	{"id": "pinning", "trigger": "chance", "wired": true, "name": "Pinning", "kind": KIND_CONTROL, "stacks": false, "tradeoff": false,
	 "desc": "12% chance to stun the enemy outright."},
	{"id": "harrying", "trigger": "foe_stunned", "rarity": "uncommon", "wired": true, "name": "Harrying", "kind": KIND_CONTROL, "stacks": false, "tradeoff": false,
	 "desc": "Grants a point of your class engine (Momentum, Rage, Conviction, Focus or Read) whenever the enemy is stunned or distracted."},
	{"id": "demoralising", "trigger": "foe_stunned", "rarity": "uncommon", "wired": true, "name": "Demoralising", "kind": KIND_CONTROL, "stacks": false, "tradeoff": false,
	 "desc": "Shields you for 5% of your health while the enemy is stunned or rattled."},
	{"id": "entrenched", "wired": true, "name": "Entrenched", "kind": KIND_BUFF, "stacks": false, "tradeoff": false,
	 "desc": "Also shields you for 7% of your health when the buff goes up."},
	{"id": "renewing", "wired": true, "name": "Renewing", "kind": KIND_BUFF, "stacks": false, "tradeoff": false,
	 "desc": "Heals you for 5% of your health when the buff goes up."},

	{"id": "overdraw", "wired": true, "name": "Overdraw", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": true,
	 "desc": "+30% damage, but it costs 25% more."},
	{"id": "reckless", "wired": true, "name": "Reckless", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": true,
	 "desc": "+35% damage, but you take 5% of your health as recoil."},
	{"id": "slow_burn", "rarity": "uncommon", "wired": true, "name": "Slow Burn", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": true,
	 "desc": "-25% immediate damage, but leaves a burn worth far more over time."},
	{"id": "concentrated", "rarity": "rare", "wired": true, "name": "Concentrated", "kind": KIND_BUFF, "stacks": false, "tradeoff": true,
	 "desc": "Double strength, half the duration."},
	{"id": "reckless_guard", "wired": true, "name": "Open Guard", "kind": KIND_BUFF, "stacks": false, "tradeoff": true,
	 "desc": "+50% to the buff, but -15% defence while it lasts."},
	{"id": "hair_trigger", "trigger": "chance", "rarity": "uncommon", "wired": true, "name": "Hair Trigger", "kind": KIND_ANY, "stacks": false, "tradeoff": true,
	 "desc": "Costs 40% less, but its effect varies wildly (50%-150%)."},
	# The trade-off sub-pool needs to be as deep as the main one, or the LATE milestones - the
	# ones that are supposed to be the interesting decisions - start repeating exactly where the
	# stakes are highest. Owner: "trade-offs should likely be a large enough pool that repeats
	# are rare as well."
	{"id": "wild_swing", "trigger": "chance", "rarity": "uncommon", "wired": true, "name": "Wild Swing", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": true,
	 "desc": "+45% damage, but a real chance to miss outright."},
	{"id": "bloodprice", "rarity": "rare", "wired": true, "name": "Blood Price", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": true,
	 "desc": "Paid in health instead of your resource."},
	{"id": "brittle", "wired": true, "name": "Brittle Strike", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": true,
	 "desc": "+30% damage, but your guard is down until your next turn."},
	{"id": "all_in", "trigger": "resource_low", "rarity": "epic", "wired": true, "name": "All In", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": true,
	 "desc": "Hits far harder the EMPTIER your resource bar is, and weakly when it is full."},
	{"id": "greedy", "wired": true, "name": "Heavy Draw", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": true,
	 "desc": "+25% damage, but the card is slower to come back around."},
	{"id": "fragile_ward", "wired": true, "name": "Fragile Ward", "kind": KIND_BUFF, "stacks": false, "tradeoff": true,
	 "desc": "+60% to the buff, but it shatters on the first hit you take."},
	{"id": "slow_cast", "wired": true, "name": "Slow Cast", "kind": KIND_BUFF, "stacks": false, "tradeoff": true,
	 "desc": "+50% to the buff, but the foe acts before you this round."},
	{"id": "costly_vigil", "wired": true, "name": "Costly Vigil", "kind": KIND_BUFF, "stacks": false, "tradeoff": true,
	 "desc": "Lasts twice as long, but drains resource every round it holds."},
	{"id": "provoking", "rarity": "epic", "wired": true, "name": "Provoking", "kind": KIND_CONTROL, "stacks": false, "tradeoff": true,
	 "desc": "A stronger debuff, and the foe turns off your companion and onto YOU."},
	{"id": "unstable_hex", "trigger": "chance", "rarity": "rare", "wired": true, "name": "Unstable Hex", "kind": KIND_CONTROL, "stacks": false, "tradeoff": true,
	 "desc": "A stronger debuff, with a small chance it lands on you instead."},
	{"id": "gamblers_cut", "trigger": "chance", "rarity": "rare", "wired": true, "name": "Gambler's Cut", "kind": KIND_ANY, "stacks": false, "tradeoff": true,
	 "desc": "Half cost, but a quarter of the time it does nothing at all."},
	{"id": "sacrificial", "rarity": "epic", "wired": true, "name": "Sacrificial", "kind": KIND_DAMAGE, "stacks": false, "tradeoff": true,
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

# === RARITY (2026-09-11) ===
#
# Owner's goal for the chase loop: *"wide enough that some players are telling their friends about
# ones they found that their friends have probably never seen."* That is a statement about
# RARITY, and a uniform draw is incapable of it AT ANY POOL SIZE.
#
# Measured 2026-09-10: `draw_choices` shuffled and took the first OFFER_SIZE, so with 22 eligible
# and 9 shown, a damage card revealed **41% of everything it could ever be offered at its FIRST
# rank-up**, and after five milestones the chance a given upgrade had never appeared was 7%.
# Doubling the pool does not help - it still shows 9 at once and still converges. So the fix is a
# weight, not more content, and it has to land BEFORE more upgrades are authored or the new ones
# dissolve into the same uniform draw.
#
# RARE MEANS DISTINCTIVE, NOT STRONGER. Tying rarity to power would make luck decide how strong a
# card ends up; tying it to how UNUSUAL the effect is gives the "you found THAT?" moment while
# leaving the power curve flat. The rare set is the upgrades that break a rule the player has
# learned - pay off from the discard, act before the fight starts, reach an ally, take another
# turn, cost health, or sometimes do nothing at all.
# FOUR TIERS, not two. Owner 2026-09-11: *"If we are going to have rarity with cards we may want
# to add more than just rare, maybe uncommon as well."* Two tiers gives a player one bit of
# information - special or not - and a chase loop wants a gradient.
#
# The NAMES and the COLOURS are the ones the game already uses for loot
# (`DropTables.RARITY_COLORS`). Reusing them rather than inventing a scale means a player reads
# a purple upgrade the same way they already read a purple item, with nothing new to learn -
# the same reasoning that settled the tier-vocabulary sweep earlier the same day.
const RARITY_COMMON := "common"
const RARITY_UNCOMMON := "uncommon"
const RARITY_RARE := "rare"
const RARITY_EPIC := "epic"

## Weakest to strongest presence. Index is also the gauge fill, so ORDER IS MEANINGFUL.
const RARITY_ORDER: Array[String] = [RARITY_COMMON, RARITY_UNCOMMON, RARITY_RARE, RARITY_EPIC]

## Draw weight per tier. Tuned against the measured curve in tools/probe/upgrade_rarity.gd
## rather than picked - see that probe's table for what a player actually ends up seeing.
const RARITY_WEIGHTS := {
	RARITY_COMMON: 10.0,
	RARITY_UNCOMMON: 2.5,
	RARITY_RARE: 0.8,
	RARITY_EPIC: 0.30,
}


# === WHEN IS AN UPGRADE ACTUALLY LIVE? (2026-09-11) ===
#
# Owner: *"Situational can be good but only if there is a clear answer to how to use them
# properly and make it easily apparent in combat when it's worth using. If not it all becomes
# micro-management and feels like dead options."*
#
# Audited first (`tools/probe/upgrade_variety.gd`), and the finding was not what it looked like:
# only 15 of 51 upgrades are genuinely conditional, and NINE OF THOSE FIFTEEN already key off
# something the combat screen shows - foe HP, your HP, the resource bar, the monster's status
# chips. The triggers were never the hidden part.
#
# What was missing is any LINK between that visible state and the card. The condition existed
# only in the English `desc`, so nothing downstream could know when an upgrade was live; and a
# card in hand did not show which upgrades it carried at all. A player picked Executioner and it
# vanished into the card's invisible state - the foe would drop to 25%, the most visible number
# on screen, and they still had to remember which of five cards had it.
#
# So: the trigger becomes DATA, and one function answers "is it live right now". Both halves live
# here rather than in the client, because the server rolls the real effect against the same
# facts - a client-side copy of "below 30%" is the shape that drifts.
const TRIGGER_NONE := "none"          ## fires on every cast
const TRIGGER_CHANCE := "chance"      ## fires on a dice roll - no decision to time
const TRIGGER_FOE_HP := "foe_hp_below"
const TRIGGER_SELF_HP := "self_hp_below"
const TRIGGER_FIRST_USE := "first_use"
const TRIGGER_RESOURCE_FULL := "resource_full"
const TRIGGER_RESOURCE_LOW := "resource_low"
const TRIGGER_FOE_STUNNED := "foe_stunned"
const TRIGGER_ON_KILL := "on_kill"
const TRIGGER_CADENCE := "cast_cadence"
const TRIGGER_ON_CYCLE := "on_cycle"


static func trigger_of(u: Dictionary) -> String:
	"""An upgrade with no `trigger` is always-on. Omission is the default because 27 of the 51
	are, and tagging them all to say 'no condition' would be noise that drifts."""
	return String(u.get("trigger", TRIGGER_NONE))


static func trigger_live(u: Dictionary, s: Dictionary) -> bool:
	"""Is this upgrade's condition satisfied RIGHT NOW, given the combat state `s`?

	`s` keys, all optional - a missing key means "cannot tell", which reads as NOT live, so a
	caller that knows less simply lights up less. It must never claim live on a guess.
	  foe_hp_pct / self_hp_pct / resource_pct : 0.0-1.0
	  foe_stunned : bool
	  card_casts  : times THIS card has been cast this fight

	ALWAYS-ON and CHANCE both return false on purpose. Neither is a thing a player times, and
	lighting up an upgrade that is always on would make the indicator meaningless - if everything
	glows, nothing does."""
	match trigger_of(u):
		TRIGGER_FOE_HP:
			return s.has("foe_hp_pct") and float(s["foe_hp_pct"]) < float(u.get("at", 0.30))
		TRIGGER_SELF_HP:
			return s.has("self_hp_pct") and float(s["self_hp_pct"]) < float(u.get("at", 0.50))
		TRIGGER_RESOURCE_FULL:
			return s.has("resource_pct") and float(s["resource_pct"]) >= 0.999
		TRIGGER_RESOURCE_LOW:
			# All In scales continuously, so there is no true/false moment - call it live once
			# it is beating an average cast, which is the point a player should notice it.
			return s.has("resource_pct") and float(s["resource_pct"]) <= 0.50
		TRIGGER_FOE_STUNNED:
			return bool(s.get("foe_stunned", false))
		TRIGGER_FIRST_USE:
			return s.has("card_casts") and int(s["card_casts"]) == 0
		TRIGGER_CADENCE:
			var every: int = maxi(2, int(u.get("every", 3)))
			# Live on the cast that WILL complete the cycle, not the one after it.
			return s.has("card_casts") and (int(s["card_casts"]) + 1) % every == 0
		TRIGGER_ON_KILL:
			# Cannot be known before the hit lands. Treated as a HINT rather than a live state:
			# see trigger_hint(). Claiming it live would be a guess about damage.
			return false
		TRIGGER_ON_CYCLE:
			# Pays off only if you DON'T play this card, so "live" would be backwards.
			return false
	return false


static func trigger_hint(u: Dictionary) -> String:
	"""A SHORT plain-language note of when this upgrade pays, for the card face. Empty for
	always-on, because a note on every card is noise a player learns to ignore."""
	match trigger_of(u):
		TRIGGER_FOE_HP:    return "foe under %d%%" % int(round(float(u.get("at", 0.30)) * 100.0))
		TRIGGER_SELF_HP:   return "you under %d%%" % int(round(float(u.get("at", 0.50)) * 100.0))
		TRIGGER_RESOURCE_FULL: return "full bar"
		TRIGGER_RESOURCE_LOW:  return "low bar"
		TRIGGER_FOE_STUNNED:   return "foe stunned"
		TRIGGER_FIRST_USE:     return "first use"
		TRIGGER_CADENCE:       return "every %d casts" % int(u.get("every", 3))
		TRIGGER_ON_KILL:       return "on a kill"
		TRIGGER_ON_CYCLE:      return "if NOT played"
		TRIGGER_CHANCE:        return "by chance"
	return ""


static func rarity_of(u: Dictionary) -> String:
	"""An upgrade with no `rarity` field is COMMON. Omission is the default on purpose: the
	majority of the table is common, and tagging 25 entries to say 'ordinary' would be noise
	that drifts."""
	var r := String(u.get("rarity", RARITY_COMMON))
	return r if r in RARITY_ORDER else RARITY_COMMON


static func weight_of(u: Dictionary) -> float:
	return float(RARITY_WEIGHTS.get(rarity_of(u), 10.0))


static func rarity_rank(rarity: String) -> int:
	"""0-3. Drives the visual gauge, so it must match RARITY_ORDER."""
	var i := RARITY_ORDER.find(rarity)
	return i if i >= 0 else 0


static func rarity_by_id(id: String) -> String:
	return rarity_of(upgrade_by_id(id))
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
	# WEIGHTED draw without replacement. The old `pool.shuffle()` + take-the-first-N was uniform,
	# which is why nothing could be rare: see the RARITY block above for the measurement.
	# Still without replacement, so an offer never shows the same upgrade twice.
	var bag: Array = pool.duplicate()
	var out: Array = []
	while out.size() < count and not bag.is_empty():
		var total: float = 0.0
		for u in bag:
			total += weight_of(u)
		var roll: float = randf() * total
		var acc: float = 0.0
		var picked: int = bag.size() - 1
		for i in range(bag.size()):
			acc += weight_of(bag[i])
			if roll < acc:
				picked = i
				break
		out.append(bag[picked])
		bag.remove_at(picked)
	return out


# === DAMAGE-SIDE MULTIPLIERS — ONE TABLE, TWO READERS (2026-09-07) ===
#
# `combat_manager._apply_card_upgrade_damage` rolls these for real; the client card estimate
# reads the same table for its EXPECTED value. Before this table existed the two disagreed
# badly: the estimate counted only `power`, so a card carrying Slow Burn showed its old number
# while hitting 25% softer, and Overdraw / Reckless / Brittle / Greedy each added 25-35% that
# never appeared anywhere the player could see it. Five upgrades that silently moved the
# number the card was printing.
#
#   mult      the multiplier applied when it fires
#   chance    probability of firing (absent = always)
#   miss      probability the card does NOTHING at all instead
#   estimate  true if the card face can honestly fold it into one number. Conditional
#             upgrades are false: their trigger is a fact about the FIGHT, not the card, so
#             they are listed as a separate "when" note rather than averaged into a lie.
const DAMAGE_MULTS := {
	"overdraw":     {"mult": 1.30, "estimate": true},
	"reckless":     {"mult": 1.35, "estimate": true},
	"brittle":      {"mult": 1.30, "estimate": true},
	"greedy":       {"mult": 1.25, "estimate": true},
	"slow_burn":    {"mult": 0.75, "estimate": true},
	"wild_swing":   {"mult": 1.45, "miss": 0.20, "estimate": true},
	"gamblers_cut": {"mult": 1.00, "miss": 0.25, "estimate": true},
	"hair_trigger": {"mult": 1.00, "estimate": true},   # uniform 0.50-1.50, mean 1.0
	"keen":         {"mult": 1.50, "chance": 0.08, "stacks": true, "estimate": true},
	"executioner":  {"mult": 1.40, "estimate": false, "when": "foe under 30%"},
	"opener":       {"mult": 1.50, "estimate": false, "when": "first use each fight"},
	"sacrificial":  {"mult": 2.00, "estimate": false, "when": "once per fight"},
	"all_in":       {"mult": 1.60, "estimate": false, "when": "on a near-empty bar"},
	"sure_strike":  {"mult": 1.50, "estimate": false, "when": "first use each fight"},
}


static func damage_mult_for(id: String) -> float:
	"""The multiplier `id` applies when it fires. Single lookup so combat_manager never
	hard-codes a constant the estimate cannot see."""
	var e = DAMAGE_MULTS.get(id, null)
	if e == null:
		return 1.0
	return float(e.get("mult", 1.0))


static func damage_miss_chance(id: String) -> float:
	"""Probability `id` makes the card do nothing at all (Wild Swing, Gambler's Cut)."""
	var e = DAMAGE_MULTS.get(id, null)
	if e == null:
		return 0.0
	return float(e.get("miss", 0.0))


static func estimate_damage_mult(picks: Array) -> float:
	"""Expected damage multiplier from every upgrade a card carries whose effect does not
	depend on the state of the fight. Used by the client's card estimate so the printed
	number matches what the card actually hits for."""
	if picks == null or picks.is_empty():
		return 1.0
	var counts := {}
	for p in picks:
		var k := String(p)
		counts[k] = int(counts.get(k, 0)) + 1
	var total := 1.0
	for id in counts.keys():
		var e = DAMAGE_MULTS.get(id, null)
		if e == null or not bool(e.get("estimate", false)):
			continue
		var n: int = int(counts[id])
		var mult := float(e.get("mult", 1.0))
		var miss := float(e.get("miss", 0.0))
		var chance := float(e.get("chance", 1.0))
		var per := 0.0
		if chance < 1.0:
			# Stacking proc (Keen Edge): n stacks share one roll at n x chance.
			per = 1.0 + minf(1.0, chance * float(n)) * (mult - 1.0)
			total *= per
			continue
		per = (1.0 - miss) * mult
		# Non-stacking upgrades are held once even if the array somehow repeats them.
		total *= per if not bool(e.get("stacks", false)) else pow(per, float(n))
	return total


static func conditional_damage_notes(picks: Array) -> Array:
	"""The upgrades deliberately LEFT OUT of `estimate_damage_mult`, as short
	"x1.4 when foe under 30%" strings, so the card can show them honestly instead of
	burying them in an average that is wrong in both directions."""
	var out: Array = []
	var seen := {}
	for p in picks:
		var id := String(p)
		if seen.has(id):
			continue
		seen[id] = true
		var e = DAMAGE_MULTS.get(id, null)
		if e == null or bool(e.get("estimate", false)):
			continue
		# 2026-09-08 - was "%.2g", which GDScript's format operator does not support (it knows
		# %s %d %f %x %o %c, not %g), so the line rendered with the specifier still in it.
		# Reported from play: "it also said Situation with some formatting text after it %2".
		# Built by hand instead: two decimals, trailing zeros and a bare point trimmed, so 1.40
		# reads "1.4" and 2.00 reads "2".
		var mtxt: String = ("%.2f" % float(e.get("mult", 1.0)))
		while mtxt.ends_with("0"):
			mtxt = mtxt.substr(0, mtxt.length() - 1)
		if mtxt.ends_with("."):
			mtxt = mtxt.substr(0, mtxt.length() - 1)
		out.append("x%s %s" % [mtxt, String(e.get("when", ""))])
	return out
