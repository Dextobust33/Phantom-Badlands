extends RefCounted
## How fast an auto-skipping reveal minigame clicks - ONE rule for the combat loot panel and the
## gather/craft scratch-offs.
##
## A fixed gap per pick is fine at 3 reveals and miserable at 45: the late-game combat budget is
## (base + flock + soldier) x5, and auto-skip's whole purpose is that a veteran does not sit through
## it. Owner 2026-10-14 (playtest sheet item 30): *"the auto-skip should play that animation much
## faster"* for the later ones. So the gap shrinks as the pick count grows, such that the WHOLE run
## takes about TARGET_TOTAL seconds - never slower than the base gap, never faster than the floor
## (below which a click and its reveal animation start to overlap).
const TARGET_TOTAL: float = 3.0
const FLOOR: float = 0.05

static func interval(base: float, picks: int) -> float:
	if picks <= 0:
		return base
	return clampf(TARGET_TOTAL / float(picks), FLOOR, base)
