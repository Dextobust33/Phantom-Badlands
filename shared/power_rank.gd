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
## 8, and `get_sub_tier_level_range` divides each tier's band into 8 segments).
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


static func letter(tier: int) -> String:
	"""The tier's letter. Clamped rather than erroring: a bad tier must still print something."""
	return LADDER[clampi(tier - 1, 0, LADDER.size() - 1)]


static func label(tier: int, rank: int) -> String:
	"""'E5'. The compact form, for anywhere a name already carries context."""
	return "%s%d" % [letter(tier), clampi(rank, 1, RANKS)]


static func color(tier: int) -> String:
	return TIER_COLORS[clampi(tier - 1, 0, TIER_COLORS.size() - 1)]


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
