extends RefCounted
## COMPANION PERKS (docs/design/variety_item11.md, item 11c; owner 2026-10-22: "inherit one, roll one" and "same idea, companion-sized").
##
## A companion carries up to two perks. ONE is inherited from the monster the egg came from (the monster's trait, mapped to what it means for an ally), ONE is rolled when the egg is made.
## An egg from an untraited monster has just the rolled one. A perk is a multiplier on stats the companion already has; the result is BAKED into the egg's `bonuses` when it is created, so every
## reader of a companion's bonuses (combat, the team, the stable, the market) sees it without a code change, and `perks` is kept beside it only so the player can read what it is.
const PERKS := {
	"sturdy":    {"name": "Sturdy",    "desc": "more health and defence",  "keys": {"hp_bonus": 1.25, "defense": 1.25}},
	"fierce":    {"name": "Fierce",    "desc": "hits harder",              "keys": {"attack": 1.25}},
	"quick":     {"name": "Quick",     "desc": "faster",                   "keys": {"speed": 1.40}},
	"regrowing": {"name": "Regrowing", "desc": "heals between rounds",     "keys": {"hp_regen": 1.50}},
	"leeching":  {"name": "Leeching",  "desc": "drinks from what it hits", "keys": {"lifesteal": 1.50}},
	"keen":      {"name": "Keen",      "desc": "lands more critical blows", "keys": {"crit_chance": 1.50}},
}

## What each monster trait (an Empowered modifier id) means for an ally. Traits with no entry roll the inherited slot instead.
const TRAIT_PERK := {
	"thickhided": "sturdy", "stalwart": "sturdy", "juggernaut": "sturdy", "warded": "sturdy", "thorned": "sturdy",
	"giant": "fierce", "ponderous": "fierce", "frenzied": "fierce", "venomous": "fierce",
	"swift": "quick", "skittish": "quick",
	"regenerating": "regrowing",
	"vampiric": "leeching",
	"gilded": "keen", "broodcalling": "keen",
}

## A perk on a stat the species does not have must still be worth something: it adds this much per companion TIER (a tier-5 Sturdy on a companion with no defence gets +5 defence).
const FLOOR_PER_TIER := {"hp_bonus": 2.0, "defense": 1.0, "attack": 2.0, "speed": 1.0, "hp_regen": 0.4, "lifesteal": 0.3, "crit_chance": 0.5}


static func roll(source_traits: Array, rng: RandomNumberGenerator = null) -> Array:
	"""[inherited?, rolled]: the inherited perk from the first of the monster's traits that maps to one, then one rolled that differs from it."""
	var r: RandomNumberGenerator = rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		r.randomize()
	var out: Array = []
	for t in source_traits:
		if TRAIT_PERK.has(String(t)):
			out.append(String(TRAIT_PERK[String(t)]))
			break
	var ids: Array = PERKS.keys()
	ids.sort()
	var pick: String = String(ids[r.randi() % ids.size()])
	var guard := 0
	while pick in out and guard < 20:
		pick = String(ids[r.randi() % ids.size()])
		guard += 1
	out.append(pick)
	return out


static func bake(bonuses: Dictionary, perks: Array, tier: int) -> Dictionary:
	"""`bonuses` with each perk's multipliers applied (a stat the companion lacks gets the per-tier floor instead). Returns a new dictionary."""
	var out: Dictionary = bonuses.duplicate()
	for p in perks:
		var perk: Dictionary = PERKS.get(String(p), {})
		for key in perk.get("keys", {}):
			var mult: float = float(perk["keys"][key])
			var cur: float = float(out.get(key, 0.0))
			if cur > 0.0:
				var v: float = snappedf(cur * mult, 0.1)
				out[key] = int(v) if absf(v - round(v)) < 0.0001 else v
			else:
				out[key] = snappedf(float(FLOOR_PER_TIER.get(key, 1.0)) * float(maxi(1, tier)), 0.1)
	return out


static func label(perks: Array) -> String:
	var names: Array = []
	for p in perks:
		names.append(String(PERKS.get(String(p), {}).get("name", p)))
	return ", ".join(PackedStringArray(names))


static func describe(perks: Array) -> String:
	var parts: Array = []
	for p in perks:
		var perk: Dictionary = PERKS.get(String(p), {})
		if not perk.is_empty():
			parts.append("%s (%s)" % [String(perk["name"]), String(perk["desc"])])
	return ", ".join(PackedStringArray(parts))
