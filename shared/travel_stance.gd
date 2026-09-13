extends RefCounted
class_name TravelStance
## How a character is MOVING through the world, and what that trades away.
##
## Owner direction 2026-09-13: *"I was debating having different stances or something where you
## can toggle between like an evasive stance where you don't get as much back each step or from
## rests but you're much less likely to hit random encounters, we would need a couple more like
## this and it would have to be an obvious toggle likely just under their over world map with
## multiple different colored selections, and explanation for the player."*
##
## WHY THIS IS NEWLY POSSIBLE. A regen penalty was meaningless until v0.9.779, when ability costs
## doubled and the resource bar started actually binding - before that "you get less back each
## step" cost nobody anything. The two changes hold each other up.
##
## WHY IT IS NEEDED. Measured after the world reshape (tools/probe/travel_encounters.gd): a
## player at their OWN level meets about 94 fights per 500 tiles walked - one every five steps.
## Removing the over-levelled encounter floor fixed crossing country beneath you; it does nothing
## for crossing country AT your level, which is most of a journey. A stance is the player's own
## answer to that, chosen deliberately, rather than the game quietly deciding for them.
##
## ONE TABLE, read by both sides. The server applies the numbers and the client draws the
## buttons from the same rows, so a stance cannot say one thing and do another - which is this
## repo's single most common class of bug.

const WARY := "wary"
const TRAVELLING := "travelling"
const HUNTING := "hunting"
const SCOUTING := "scouting"

## `encounter` multiplies the chance of a random encounter per step.
## `regen` multiplies what a step and a rest give back.
## `vision` adds to the map radius.
## Colour is the button's, and is also what the status line uses, so the two always agree.
const STANCES := {
	WARY: {
		"name": "Wary",
		"color": "#9ACD32",
		"encounter": 1.0,
		"regen": 1.0,
		"vision": 0,
		"blurb": "Balanced. What you have always done.",
	},
	TRAVELLING: {
		"name": "Travelling",
		"color": "#4DA6FF",
		"encounter": 0.18,
		"regen": 0.35,
		"vision": 0,
		"blurb": "Cover ground. Far fewer encounters, but you recover much less as you walk and rest.",
	},
	HUNTING: {
		"name": "Hunting",
		"color": "#FF6644",
		"encounter": 2.2,
		# Hunting COSTS something too. Without this it gave up only safety, which a player who
		# wants fights is not giving up at all - so it was a free switch rather than a choice.
		# Caught by `tools/probe/travel_stances.gd`, which asserts no stance is strictly better
		# than Wary; it was right and the first version of this table was wrong.
		"regen": 0.85,
		"vision": 0,
		"blurb": "Look for trouble. Encounters come thick and fast, and staying alert wears on you.",
	},
	SCOUTING: {
		"name": "Scouting",
		"color": "#C9A0FF",
		"encounter": 0.75,
		"regen": 0.7,
		"vision": 2,
		"blurb": "See further across the map. Slightly fewer encounters, slower recovery.",
	},
}

## The order the buttons appear in, left to right: cross, default, explore, fight.
const ORDER := [TRAVELLING, WARY, SCOUTING, HUNTING]


static func is_valid(id: String) -> bool:
	return STANCES.has(id)


static func get_stance(id: String) -> Dictionary:
	"""Never returns empty: an unknown id resolves to Wary, so a bad save or an older client
	cannot leave a character in a stance that has no numbers."""
	return STANCES.get(id, STANCES[WARY])


static func encounter_mult(id: String) -> float:
	return float(get_stance(id).get("encounter", 1.0))


static func regen_mult(id: String) -> float:
	return float(get_stance(id).get("regen", 1.0))


static func vision_bonus(id: String) -> int:
	return int(get_stance(id).get("vision", 0))


static func display(id: String) -> String:
	var s: Dictionary = get_stance(id)
	return "[color=%s]%s[/color]" % [s.get("color", "#FFFFFF"), s.get("name", "Wary")]
