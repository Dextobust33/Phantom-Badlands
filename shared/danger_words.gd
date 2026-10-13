extends RefCounted
## One vocabulary for "how dangerous is that ground, compared to me".
##
## ⚑ WHY THIS EXISTS (owner sheet 2026-10-13). The danger-step confirmation and the Area readout beside
## it described the SAME ground in different words: the guard asks from 1.15x your level (measured -
## at the old 2x players died 50-100% of the time before the game asked anything) and called all of it
## "far above you", while the readout said "about your level" until 1.35x. At 1.2x the screen told you
## the ground was both. They each owned a copy of the thresholds and the words, which is the shape
## CLAUDE.md names: one value, two places. Both now read this.
##
## The thresholds are the verdict EDGES, in one place. `DANGER_STEP_RATIO` on the server is defined
## from `ABOVE`, so the point where the guard starts asking and the point where the readout turns red
## are the same number by construction.
##
## Wording varies on purpose (owner: "more variety") - a guard that says the same sentence every time
## is one the eye learns to skip, and this is the last thing between a player and a walk they may
## not come back from. Every variant still contains the verdict's own phrase, so the words a player
## sees in the confirmation are always the words the readout uses for that ground.

const TRIVIAL := 0.6      # below this: "trivial"
const ABOUT := 0.85       # from here: "about your level"
const ABOVE := 1.15       # from here: "above you" - and where the step guard starts asking
const FAR := 2.0          # from here: "far above you"
const LETHAL := 3.0       # from here: "LETHAL"


static func verdict(ratio: float) -> String:
	"""The verdict KEY for a (ground level / your level) ratio."""
	if ratio >= LETHAL:
		return "lethal"
	if ratio >= FAR:
		return "far"
	if ratio >= ABOVE:
		return "above"
	if ratio >= ABOUT:
		return "about"
	if ratio < TRIVIAL:
		return "trivial"
	return "beneath"


static func phrase(key: String) -> String:
	"""The plain words for a verdict - the ones every surface must use."""
	match key:
		"lethal": return "LETHAL"
		"far": return "far above you"
		"above": return "above you"
		"about": return "about your level"
		"beneath": return "beneath you"
		_: return "trivial"


static func color(key: String) -> String:
	match key:
		"lethal", "far": return "#FF2A2A"
		"above": return "#FF5555"
		"about": return "#FF8800"
		"beneath": return "#7FD4A0"
		_: return "#9ACD32"


static func bbcode(key: String) -> String:
	"""The verdict as the readout draws it: coloured, and bold for the one that can kill you."""
	var body := phrase(key)
	if key == "lethal":
		body = "[b]%s[/b]" % body
	return "[color=%s]%s[/color]" % [color(key), body]


## Opening word of the refusal. Short, and none of them is a question - the step was refused.
const OPENERS := ["Wait.", "Hold on.", "Careful.", "Easy now."]

## How to go on anyway. Every one keeps the words "to go anyway" so the instruction is findable.
const TAILS := [
	"Step again to go anyway.",
	"Step the same way again to go anyway.",
	"Press that direction again to go anyway.",
]

# {there} and {me} are the two levels; {phrase} is the readout's own wording for the verdict.
const _TEMPLATES := {
	"above": [
		"The ground ahead runs about [b]Lv {there}[/b] - {phrase} (you are {me}).",
		"Monsters out there are around [b]Lv {there}[/b], and that is {phrase} (you are {me}).",
		"Careful: this country is about [b]Lv {there}[/b] - {phrase}, at Lv {me}.",
		"Past this point the monsters run near [b]Lv {there}[/b]: {phrase} (you are {me}).",
	],
	"far": [
		"The ground ahead runs about [b]Lv {there}[/b] - {phrase} (you are {me}).",
		"Whatever lives out there is around [b]Lv {there}[/b], {phrase} at Lv {me}.",
		"This is {phrase}: monsters near [b]Lv {there}[/b], and you are {me}.",
		"Out there is about [b]Lv {there}[/b] - {phrase}. You are Lv {me}.",
	],
	"lethal": [
		"The ground ahead runs about [b]Lv {there}[/b] - {phrase} to you (you are {me}).",
		"Monsters out there are near [b]Lv {there}[/b]. That is {phrase} at Lv {me}.",
		"Turn back if you can: about [b]Lv {there}[/b], {phrase} to a Lv {me}.",
		"Nothing out there is a fair fight: around [b]Lv {there}[/b], {phrase} (you are {me}).",
	],
}


static func warning(there: int, me: int, pick: int = -1) -> String:
	"""The refusal text for stepping onto ground at level `there` as a level-`me` character.

	`pick` selects the variant (any non-negative number, taken modulo the count); -1 means random.
	The verdict - and so the words - come from the ratio alone, never from the guard's own band, so
	the confirmation can never describe the ground differently from the readout."""
	var ratio: float = float(maxi(1, there)) / float(maxi(1, me))
	var key: String = verdict(ratio)
	if not _TEMPLATES.has(key):
		key = "above"     # the guard only asks from ABOVE up; a lower verdict still gets a sane line
	var pick_n: int = pick if pick >= 0 else randi()
	var variants: Array = _TEMPLATES[key]
	var body: String = String(variants[pick_n % variants.size()])
	body = body.replace("{there}", str(there)).replace("{me}", str(me)).replace("{phrase}", "[b]%s[/b]" % phrase(key))
	# Once it is three times your level, say how many - the number is more arresting than the adjective.
	if ratio >= LETHAL:
		body += " That is about %dx your level." % int(round(ratio))
	var opener: String = String(OPENERS[(pick_n / 7) % OPENERS.size()])
	var tail: String = String(TAILS[(pick_n / 3) % TAILS.size()])
	return "[color=#FF2A2A][b]%s[/b][/color] %s\n%s" % [opener, body, tail]
