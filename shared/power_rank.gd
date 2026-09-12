class_name PowerRank
extends RefCounted
## ONE place that turns a (tier, rank) pair into something a player can read and order.
##
## Owner, 2026-09-09: *"the Tier and subtier are confusing, we should probably rename them Tier
## and rank."* `[T1-5]` is two numbers that look alike and mean different kinds of thing, and
## nothing on screen said which was which. The owner has twice misread a dungeon's depth from it.
##
## THE DATA IS NOT CHANGING. `tier: int` (1-9) and `sub_tier: int` (1-8) stay exactly as they are
## on disk and on the wire; this is a display layer over them. A 335-reference rename across 13
## files is precisely the shape CLAUDE.md's rename rule says half-lands, and a migration would put
## every saved companion and live dungeon instance at risk for a naming change. One formatter
## cannot half-land.
##
## TWO DECISIONS, both the owner's (2026-09-11):
##
## 1. The ladder is H G F E D C B A S - nine letters for nine tiers, and exactly ONE S. Owner:
##    *"too many S's, we need an alternative on that."* Extending DOWNWARD instead of stacking
##    SS/SSS gets nine distinct letters and leans on school-grade intuition, where F fails and A
##    is top; H and G sit below F as the two starter bands, S is the single apex above A.
##
## 2. BOTH halves ascend. The owner first asked for rank 1 to be the best within a tier (the
##    S-rank convention), then chose ascending when it was pointed out that a letter climbing
##    toward S beside a number falling toward 1 reproduces the exact "two numbers running opposite
##    ways" problem being fixed. So: later letter wins; same letter, HIGHER number wins.
##
##    That decision has a happy consequence - `sub_tier` is ALREADY 1-8 ascending (further from
##    origin = higher, see `get_sub_tier_for_distance`), so rank IS sub_tier. Nothing inverts,
##    nothing needs migrating, and no build can ever show a mix of the two directions.
##
## Owner's remaining condition: *"only if we can make it clear to the player what is better than
## what... Maybe even a star or symbols to help might work."* A letter ladder is not self-evident
## and must not be assumed - so the affordance is built, not hoped for: `color()` ramps the label
## by danger, `pips()` shows position on the ladder as a bar, and `hover()` spells the whole thing
## out in words with the current tier marked. Never render a bare label.

## Weakest to strongest. Index 0 = tier 1.
const LADDER: Array[String] = ["H", "G", "F", "E", "D", "C", "B", "A", "S"]
## Ranks within a tier, matching `sub_tier`'s existing domain.
##
## NINE, not eight, and the difference is real: COMPANIONS reach sub_tier 9 through fusion
## (`mini(current_sub_tier + 1, 9)` at server.gd L15594/L15863, and every stable panel's
## `max_sub_tier`), while DUNGEONS only ever generate 1-8 (`get_sub_tier_for_distance` clamps to
## 8, and `get_sub_tier_level_range` divided each tier's band into 8 segments - both since
## raised to 9, see dungeon_database.gd).
##
## Found while converting the call sites, and worth stating plainly: a cap of 8 here would have
## silently collapsed the single best companion rank in the game into the second best, on every
## surface at once. Two systems sharing a field name with different domains is exactly the
## "one value, two places" shape - the formatter takes the WIDER domain so neither is truncated,
## and the dungeon side simply never reaches the top of it.
##
## Whether dungeons SHOULD stop at 8 is a separate question, filed rather than assumed.
const RANKS: int = 9

## Danger ramp, deliberately the SAME vocabulary as POST_TIER_COLORS (green = safe, red =
## extreme, purple = world's edge). Players already read that on the map for exactly this
## question, so the label inherits a meaning they have rather than teaching a new one.
const TIER_COLORS: Array[String] = [
	"#00FF00",  # H - safe
	"#66FF00",  # G
	"#AAFF00",  # F
	"#FFFF00",  # E
	"#FFCC00",  # D
	"#FFAA00",  # C
	"#FF6600",  # B
	"#FF0000",  # A - extreme
	"#AA00FF",  # S - world's edge
]


## ===== LEVEL BANDS - the ONE table =====
##
## 2026-09-11, owner's decision. The same 5 / 15 / 30 / 50 / 100 / 500 / 2000 / 5000 ladder was
## typed out in SEVEN places (monster_database twice, combat_manager, quest_database,
## quest_manager, server twice), and an EIGHTH copy in dungeon_database disagreed with all of
## them below tier 6 (1-12 / 6-22 / 16-40 / 31-60 / 51-120). Nothing tied them together, so a
## retune of one would have silently split monsters from quests from eggs from dungeons.
##
## `TIER_LEVEL_BANDS` is the canonical monster band. Dungeons deliberately reach ABOVE it: a
## tier-1 dungeon at rank 9 runs to L12, into the overworld's tier 2, because a dungeon's top
## rank is meant to be harder than the wilderness that surrounds it. That overlap was not a
## drift - it was chosen, then hand-copied - so it is kept and NAMED here as `DUNGEON_REACH`
## rather than living as a second table whose numbers happen to differ. `dungeon_band()` yields
## exactly the numbers the old dungeon table held (asserted by tools/probe/tier_bands.gd).
const TIER_LEVEL_BANDS := {
	1: {"min": 1, "max": 5},
	2: {"min": 6, "max": 15},
	3: {"min": 16, "max": 30},
	4: {"min": 31, "max": 50},
	5: {"min": 51, "max": 100},
	6: {"min": 101, "max": 500},
	7: {"min": 501, "max": 2000},
	8: {"min": 2001, "max": 5000},
	9: {"min": 5001, "max": 10000},
}
## How far ABOVE the monster band a dungeon of that tier reaches at its top rank. Zero from
## tier 6 up: the two ladders have always agreed there.
const DUNGEON_REACH := {1: 7, 2: 7, 3: 10, 4: 10, 5: 20, 6: 0, 7: 0, 8: 0, 9: 0}


static func tier_for_level(level: int) -> int:
	"""Monster tier (1-9) for a level. Anything at or below the first band is tier 1."""
	for t in range(LADDER.size(), 0, -1):
		if level >= int(TIER_LEVEL_BANDS[t]["min"]):
			return t
	return 1


static func band(tier: int) -> Dictionary:
	"""{min, max} of the monster band. Clamped, like every other lookup in this file."""
	return TIER_LEVEL_BANDS[clampi(tier, 1, LADDER.size())]


static func tier_progress(level: int) -> float:
	"""0.0-1.0 through the level's tier, as `MonsterDatabase._get_tier_info` always computed it:
	(level - previous band's max) / band width. The top tier reports 1.0 - it has no ceiling to
	measure against, and that is the value the blend code has always been handed for it."""
	var t := tier_for_level(level)
	if t >= LADDER.size():
		return 1.0
	var b: Dictionary = band(t)
	var floor_level: int = int(b["min"]) - 1
	return float(level - floor_level) / float(int(b["max"]) - floor_level)


static func dungeon_band(tier: int) -> Dictionary:
	"""{min, max} a dungeon of this tier spans across its nine ranks: the monster band plus
	the tier's named reach. These are the numbers `DungeonDatabase.TIER_LEVEL_RANGES` used to
	hold; the dungeon side reads them from here now."""
	var t := clampi(tier, 1, LADDER.size())
	var b: Dictionary = band(t)
	return {"min": int(b["min"]), "max": int(b["max"]) + int(DUNGEON_REACH.get(t, 0))}


static func rank_for_level(tier: int, level: int) -> int:
	"""Which of the nine RANKS of `tier` a level sits in.

	The inverse of `DungeonDatabase.get_sub_tier_level_range`, and the reason it lives here: from
	2026-09-11 a dungeon's grade is decided by the LAND it stands in rather than by a number
	hardcoded on its type, so something has to turn a level back into (tier, rank). Doing that
	from distance, as the old `get_sub_tier_for_distance` did, bakes in an assumption about where
	tiers live - which was exactly the fault the owner reported."""
	var b: Dictionary = dungeon_band(tier)
	var lo: int = int(b["min"])
	var hi: int = int(b["max"])
	var span: int = maxi(1, hi - lo + 1)
	return clampi(1 + int(float(level - lo) / float(span) * float(RANKS)), 1, RANKS)


static func grade_for_level(level: int) -> Dictionary:
	"""The {tier, rank} a monster level belongs to. One call, so nothing has to know that the
	tier comes from the MONSTER band and the rank from the wider DUNGEON band."""
	var t: int = tier_for_level(level)
	return {"tier": t, "rank": rank_for_level(t, level)}


static func letter(tier: int) -> String:
	"""The tier's letter. Clamped rather than erroring: a bad tier must still print something."""
	return LADDER[clampi(tier - 1, 0, LADDER.size() - 1)]


static func label(tier: int, rank: int) -> String:
	"""'E5'. The compact form, for anywhere a name already carries context."""
	return "%s%d" % [letter(tier), clampi(rank, 1, RANKS)]


static func color(tier: int) -> String:
	return TIER_COLORS[clampi(tier - 1, 0, TIER_COLORS.size() - 1)]


## How much stronger each GRADE is than the one below it. One number, and the whole ladder
## follows from it: a rank is a ninth of the way from one grade to the next, so nine ranks of
## climbing is worth exactly one grade and the weakest of a grade always beats the strongest of
## the one below.
##
## 2026-09-11. Before this, tier was very nearly decorative for companions: HP never read it at
## all and damage gave it +0.06 against a rank's +0.05, so eight ranks outweighed eight grades.
## An H9 companion carried about 3.1x the HP of a G1 and handed its owner 2.0x bonuses against
## 1.0x. The owner asked for the comparison and then chose the fix: *"1 sounds like the right
## path"* - make tier real - with the condition that players can understand the result, which is
## why it is one rule rather than two tables.
const GRADE_POWER_STEP := 1.30


static func power_mult(tier: int, rank: int) -> float:
	"""The quality multiplier for a companion at this grade and rank.

	Geometric in `power_index`, so it is monotonic over all 81 cells by construction - there is
	no ordering for a future edit to break, because there is only one ladder. Spans 1.0 at H1 to
	about 8.2 at S9.

	This multiplies QUALITY, not the base: a companion's HP and damage are built from its LEVEL,
	and this sits on top."""
	return pow(GRADE_POWER_STEP, float(power_index(tier, rank)) / float(RANKS))


static func tag(tier: int, rank: int) -> String:
	"""The label in its danger colour, no hover. For BBCode surfaces with no meta handler wired -
	most panel rows. The colour alone still answers "is this better than that one" without the
	player knowing a single letter, which is the point."""
	return "[color=%s]%s[/color]" % [color(tier), label(tier, rank)]


static func _url_safe(s: String) -> String:
	"""BBCode `[url=VALUE]` ends at the first `]`, so a value containing one truncates the tag
	and dumps the rest of the hover into the visible text. Every hover string this file produces
	goes through here rather than relying on each of them being written carefully."""
	return s.replace("[", "").replace("]", "")


static func rich_label(tier: int, rank: int) -> String:
	"""The label in its danger colour, wrapped in the hover that explains the ladder.

	This is what callers should use. A bare `label()` tells a new player nothing about whether
	E beats C, which is the owner's one condition on the whole change."""
	return "[url=%s][color=%s]%s[/color][/url]" % [
		_url_safe(hover(tier, rank)), color(tier), label(tier, rank)]


static func power_index(tier: int, rank: int) -> int:
	"""0-71, weakest to strongest. For SORTING and comparing - lists ordered by this teach the
	ladder by position, which is the cheapest affordance there is."""
	return clampi(tier - 1, 0, LADDER.size() - 1) * RANKS + clampi(rank, 1, RANKS) - 1


static func pips(tier: int) -> String:
	"""Position on the ladder as a bar: 'E' -> '▰▰▰▰▱▱▱▱▱'. Nine cells, one per tier.

	The owner asked for 'a star or symbols to help'. Stars cannot enumerate 72 steps, but a
	filled-fraction bar answers the actual question at a glance - how far along am I - without
	the player having to know the letters at all."""
	var n: int = clampi(tier, 1, LADDER.size())
	return "▰".repeat(n) + "▱".repeat(LADDER.size() - n)


static func hover(tier: int, rank: int) -> String:
	"""The ladder, in words, with this tier marked. Never assume the letters are obvious."""
	var t: int = clampi(tier, 1, LADDER.size())
	var r: int = clampi(rank, 1, RANKS)
	var chain := ""
	for i in range(LADDER.size()):
		if i > 0:
			chain += " "
		# NO SQUARE BRACKETS. This string is used as the VALUE of a `[url=...]` tag, and a `]`
		# inside it terminates the tag early - the whole hover then spills into the visible
		# line as plain text. Caught while rendering the companion inspect screen, where the
		# header read "...any G beats every H.]G5  Level 12" with the ladder printed in front
		# of the label it was supposed to explain. Angle brackets read as a marker and are safe.
		chain += (">%s<" % LADDER[i]) if i == t - 1 else LADDER[i]
	return "Tier %s, rank %d of %d — %s  (weakest → strongest)  %s  Higher rank is stronger within a tier; any %s beats every %s." % [
		letter(t), r, RANKS, chain, pips(t), letter(t),
		letter(maxi(1, t - 1)) if t > 1 else "lower tier"]
