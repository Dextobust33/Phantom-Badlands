class_name PhantomModel
extends RefCounted
## ⚑ WHAT A PHANTOM IS AND HOW DEEP IT GOES — the numbers behind the outward loop.
##
## Pure functions over a post's investment record. No server state, no scene, nothing player-facing:
## the whole model can be measured before a single tile is generated, which is the point of putting
## it here rather than inside the dungeon builder.
##
## THE FOUR DECISIONS THIS ENCODES (owner, 2026-09-19):
##   1. a Phantom has its OWN difficulty band, scaled by investment — the calibrated overworld
##      curve is never consulted and never affected
##   2. the laundering pump is gated by DEPTH AND SURVIVAL RISK and by nothing else
##   3. eggs: a GUARANTEED one deep in, with quality as the variable part
##   4. the ACCOUNT owns the post and its investment
##
## ⚡ DECISION 2 IS THE LOAD-BEARING ONE, and it shapes every function here. The owner rejected
## diminishing returns, a lossy exchange and a cooldown, so **volume must buy nothing that depth
## does not also demand**. Feeding a post twice as much may not hand a player twice as much at the
## same depth — it moves the good things FURTHER DOWN, where survival is the price. Every reward
## below is therefore a function of DEPTH first and investment second, never the other way round.

## How far down a Phantom can go, before investment. The design: *"`max_depth` scaling to how far
## out the post is. A frontier Phantom is automatically longer because it has further to bridge —
## 'near endless' is really 'as long as the gap it closes'."*
const MIN_DEPTH := 4
const MAX_DEPTH := 20
## The distance at which a post reaches MAX_DEPTH. The world is radius ~2828 and posts now spread
## to 2600, so a Phantom stops deepening a little before the true edge — the last stretch is about
## danger, not length.
const DEPTH_REACH := 2200.0

## Investment is counted in EGGS by species and in COMPANIONS in total. Both are consumed.
## Format: {"eggs": {species: count}, "companions": int}


## How deep this post's Phantom can go, from how far out it sits.
static func max_depth_for(distance_from_origin: float) -> int:
	var t: float = clampf(distance_from_origin / DEPTH_REACH, 0.0, 1.0)
	return int(round(lerpf(float(MIN_DEPTH), float(MAX_DEPTH), t)))


## The monster level on a given floor.
##
## ⚑ "ITS OWN BAND" MEANS ITS OWN CHOICE OF **LEVELS**, NOT A PARALLEL STAT CURVE — and that
## distinction is the whole safety of this feature. Established by auditing the five surfaces that
## read a monster's level, 2026-09-19, BEFORE any generation was written:
##
##   `generate_monster_by_name(name, level)` derives stats from `compute_anchored_stats(base, level)`
##   AND xp from `_calculate_experience_reward(..., level)`. So a monster generated at level 73 IS
##   a level-73 monster in every respect - correct stats, correct XP, correctly dangerous.
##
## So a Phantom is dangerous by putting HIGHER-LEVEL monsters in front of you than the country
## outside would, not by inventing stats the curve has never seen. The consequences, all checked:
##
##   XP payout          correct - it really is a level-73 kill
##   threat / hotzones  never sees it; those are functions of world POSITION
##   post anchoring     same - `get_post_anchored_level(x, y)` is positional
##   death-log gap      correct - the player really did die 43 levels above themselves
##   quest "kill a N"   correct
##
## ⚡ SO THE DANGER IS NOT HERE. It is on the REWARD side: eggs and gear "beyond the normal
## tier/sub-tier ceiling" are player power outside anything the curve knows, and that is what needs
## watching. This function is safe precisely because it only ever picks a level and lets the
## ordinary generator do the rest.
##
## ⛑ WHICH MAKES ONE RULE ABSOLUTE FOR GENERATION: phantom floors must spawn through
## `generate_monster_by_name` at the level this returns. Hand-building a monster's stats to "make
## it phantom-ish" would break every line of the table above at once.
##
## The shape is the archived design's: bridge from the local wilderness level at the top to
## something well beyond it at the bottom, with INVESTMENT deciding how far beyond. So a barely
## stocked Phantom is a slightly harder local dungeon, and a heavily stocked one is a different
## proposition entirely — at the bottom, which is the only place it pays.
static func floor_level(depth: int, max_depth: int, local_level: int, investment: Dictionary) -> int:
	if max_depth <= 0:
		return maxi(1, local_level)
	# ⚡ (depth - 1) / (max_depth - 1), NOT depth / max_depth. The first spelling put floor ONE
	# five percent of the way up the ramp, so a heavily stocked Phantom was already harder than an
	# empty one the moment the player stepped in - contradicting the comment below it, which is
	# the whole reason the probe asserts it. A player has to be able to learn what they are in by
	# DESCENDING; if the first floor already carries the investment, the only way to find out is
	# to have been told beforehand.
	var span: float = maxf(1.0, float(max_depth - 1))
	var d: float = clampf(float(depth - 1) / span, 0.0, 1.0)
	# Investment stretches the CEILING, never the floor: the top of a Phantom is always about the
	# country it sits in, so a player can tell how bad it will get by descending rather than by
	# reading a number.
	var ceiling: float = float(local_level) * (1.0 + 1.5 * investment_weight(investment))
	return maxi(1, int(round(lerpf(float(local_level), ceiling, d))))


## 0.0 to 1.0 — how heavily stocked this post is, as one number.
##
## ⛑ SATURATING, NOT LINEAR. A linear weight would make the hundredth egg worth as much as the
## first and hand the pump a volume lever the owner deliberately did not grant. The curve is steep
## early (a modest investment is clearly felt) and flat late (a hoard is not a shortcut).
static func investment_weight(investment: Dictionary) -> float:
	var eggs: int = total_eggs(investment)
	var comps: int = int(investment.get("companions", 0))
	# 40 eggs and 10 companions reach roughly 0.75; the remaining quarter costs far more than the
	# first three, which is what keeps volume from being the answer.
	var raw: float = float(eggs) / 40.0 + float(comps) / 10.0
	return clampf(raw / (1.0 + raw), 0.0, 1.0)


static func total_eggs(investment: Dictionary) -> int:
	var eggs = investment.get("eggs", {})
	if not (eggs is Dictionary):
		return 0
	var n := 0
	for k in eggs.keys():
		n += int(eggs[k])
	return n


## Spawn weighting by species: *"more harpy eggs than goblin means harpies roam more, goblins
## remain but rarer."* Returns {species: weight}; an empty result means "use the ordinary table".
##
## ⛑ NOTHING IS EVER DRIVEN TO ZERO. The fiction is that the ground remembers what it was fed, not
## that it forgets everything else — and a Phantom that spawns exactly one species is a worse place
## to play than one with a strong theme.
static func species_weights(investment: Dictionary) -> Dictionary:
	var eggs = investment.get("eggs", {})
	if not (eggs is Dictionary) or eggs.is_empty():
		return {}
	var total: int = total_eggs(investment)
	if total <= 0:
		return {}
	var out: Dictionary = {}
	for k in eggs.keys():
		# Share of the investment, softened so a single species cannot own the whole floor.
		var share: float = float(int(eggs[k])) / float(total)
		out[String(k)] = 1.0 + 3.0 * share
	return out


## The depth at which an egg becomes CERTAIN. Owner's decision 3: a deterministic floor, so effort
## always pays something and a dry run is a smaller reward rather than nothing.
##
## ⚡ AND IT IS DEEP ON PURPOSE. Decision 2 made depth the only guard on the pump, so the guaranteed
## egg has to sit where the danger is - put it shallow and the loop can be farmed in safety, which
## is precisely the failure the owner's choice leaves no other defence against.
static func guaranteed_egg_depth(max_depth: int) -> int:
	return maxi(1, int(ceil(float(max_depth) * 0.7)))


## How much better an egg found at this depth is, beyond the normal tier/sub-tier ceiling.
## 0.0 means "an ordinary egg for its tier".
##
## ⛑ DEPTH FIRST, INVESTMENT SECOND - and the multiplication is the pump guard. At shallow depth
## the investment term is multiplied by nearly zero, so no amount of stocking makes a safe descent
## lucrative. The two have to be bought together.
static func egg_quality_bonus(depth: int, max_depth: int, investment: Dictionary) -> float:
	if max_depth <= 0:
		return 0.0
	var d: float = clampf(float(depth) / float(max_depth), 0.0, 1.0)
	# Cubed: the top half of a Phantom is worth very little, which is what makes the bottom worth
	# the walk.
	return clampf(d * d * d * investment_weight(investment) * 2.0, 0.0, 2.0)


## ⚑ WHAT MAKES A PHANTOM-BORN COMPANION DIFFERENT. Owner 2026-09-19, rejecting all three of my
## proposals: *"Eggs/companions that hatch out of them should have an additional multiplier or
## something that makes them unique and stronger than a duplicate you would find out in a normal
## dungeon, ie an e4 in a dungeon is not as strong as an e4 from a phantom."*
##
## ⚡ THIS IS A FOURTH AXIS, AND THE OTHER THREE WERE DEAD ENDS - measured, not guessed:
##   * RANK is nearly flat. The whole spread from rank 1 to rank 9 inside a tier is **1.26x**, and
##     `power_index` already does `clampi(rank, 1, RANKS)`, so ranks above 9 return IDENTICAL
##     power. Pushing rank past the ceiling buys literally nothing.
##   * TIER is where the power is (**8.16x** from H to S), but raising it would collide with the
##     grade ladder and every surface that reads a letter.
##   * RARITY alone abandons the design's "far stronger than an identical-tier egg" promise.
## So the multiplier rides ALONGSIDE the grade rather than inside it: the letter stays honest, and
## a phantom E4 is simply worth more than a dungeon E4.
##
## ⛑ BOUNDED AT 1.35x, AND THE NUMBER IS CHOSEN AGAINST THE LADDER. One full grade step is
## **1.30x**, so 1.35 makes a phantom-born companion worth *about one grade above its letter* -
## a prize a player can state in a sentence, and the most this can be without quietly becoming a
## tenth grade. It is uncapped player power by construction, so the cap is the whole design.
##
## Returns 0.0 .. 0.35; the multiplier is 1.0 + this.
const PHANTOM_POWER_CAP := 0.35


static func companion_power_bonus(depth: int, max_depth: int, investment: Dictionary) -> float:
	if max_depth <= 0:
		return 0.0
	var d: float = clampf(float(depth) / float(max_depth), 0.0, 1.0)
	# Depth SQUARED times investment, the same shape as the gear axis: the prize belongs at the
	# bottom, because depth-risk is the only brake the owner chose on the loop.
	return clampf(d * d * investment_weight(investment) * PHANTOM_POWER_CAP * 1.3, 0.0, PHANTOM_POWER_CAP)


## How much better the GEAR is at this depth. Companions are the gearing axis: *"companions the
## player no longer wants are consumed to make the equipment found in the Phantom stronger."*
static func gear_bonus(depth: int, max_depth: int, investment: Dictionary) -> float:
	if max_depth <= 0:
		return 0.0
	var d: float = clampf(float(depth) / float(max_depth), 0.0, 1.0)
	var comps: int = int(investment.get("companions", 0))
	var w: float = clampf(float(comps) / 12.0, 0.0, 1.0)
	return clampf(d * d * w * 1.5, 0.0, 1.5)
