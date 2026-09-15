extends RefCounted
## CARD-SPECIFIC GEAR - the one definition of what an item or tome can do for a single card.
##
## Owner 2026-09-15, retiring the "+N to abilities" rank affixes: *"We should probably do away with +1
## as it isn't clear. There should instead be equipment that increases specific skills (ensuring it
## actually benefits the skill and doesn't give like + damage to a skill with no damage)."* And on the
## details: magnitudes 15/30/45%, an old archetype-wide item becomes ONE random card of its archetype,
## the affixes drop where rank affixes did (the epic+ chase pool), and tomes are generated from the same
## table - one per eligible card and kind.
##
## Three kinds, each read by the funnel that already carries it:
##   power    - % more of whatever the card does: damage (apply_skill_damage_bonus) or the size of its
##              shield / buff / debuff (_apply_buff_value_modifiers). Same key tomes write.
##   cost     - % off the card's cost (apply_skill_cost_reduction)
##   duration - extra rounds on a card that applies a timed buff (_buff_duration)
## Wear scales an item's bonus smoothly; nothing truncates to zero the way a +1 rank did at 1% wear.

## Which kinds DO something for each card. MEASURED, not written: tools/probe/card_bonus_fit.gd casts
## every card each class can hold with a power bonus, a cost cut and a duration pick, and FAILS if a
## card's measured kinds stop matching this table. (The result is identical across every class that
## can hold a card, which is why it is keyed by card.) Examples of what it rules out: Paralyze, Banish
## and Pickpocket have nothing a power bonus changes; Magic Bolt costs what you pour in; Devastate
## spends a share of your current stamina; only timed-buff cards have a duration to extend.
const KINDS := {
	"ambush": ["power", "cost"], "blast": ["power", "cost"], "cleave": ["power", "cost"],
	"distract": ["power", "cost"], "exploit": ["power", "cost"], "forcefield": ["power", "cost"],
	"frost_nova": ["power", "cost"], "gambit": ["power", "cost"], "meteor": ["power", "cost"],
	"perfect_heist": ["power", "cost"], "power_strike": ["power", "cost"], "sabotage": ["power", "cost"],
	"shield_bash": ["power", "cost"], "vanish": ["power", "cost"], "war_cry": ["power", "cost"],
	"berserk": ["power", "cost", "duration"], "fortify": ["power", "cost", "duration"],
	"haste": ["power", "cost", "duration"], "iron_skin": ["power", "cost", "duration"],
	"rally": ["power", "cost", "duration"], "shadowstep": ["power", "cost", "duration"],
	"analyze": ["power"], "devastate": ["power"], "magic_bolt": ["power"],
	"banish": ["cost"], "paralyze": ["cost"], "pickpocket": ["cost"],
}

## Minor / Greater / Supreme. Owner: 15/30/45%. Duration steps a round per tier.
const TIER_VALUES := {"power": [15, 30, 45], "cost": [15, 30, 45], "duration": [1, 2, 3]}
## A tome's permanent bonus is one Minor step.
const TOME_VALUES := {"power": 15, "cost": 15, "duration": 1}
## Gear and tomes together can never make a card cost less than a quarter of its price. Three Supreme
## items would otherwise stack past 100%, which the cost funnel reads as FREE.
const COST_REDUCTION_CAP := 75.0

## What "power" means on each non-damage card, for the item text. A damage card says "damage".
const POWER_WORDS := {
	"forcefield": "shield", "iron_skin": "damage reduction", "fortify": "defense", "berserk": "damage buff",
	"rally": "strength buff", "haste": "surge", "shadowstep": "evasion", "distract": "distraction",
	"war_cry": "distraction", "sabotage": "weakening", "analyze": "insight",
}

## Class-neutral card names for text written on an ITEM (a viewer's class may name the card
## differently on the card itself - the client can re-label).
const CARD_NAMES := {
	"power_strike": "Power Strike", "war_cry": "War Cry", "shield_bash": "Shield Bash", "cleave": "Cleave",
	"berserk": "Berserk", "iron_skin": "Iron Skin", "devastate": "Devastate", "fortify": "Fortify",
	"rally": "Rally", "magic_bolt": "Magic Bolt", "blast": "Blast", "forcefield": "Forcefield",
	"meteor": "Meteor", "haste": "Arcane Surge", "paralyze": "Paralyze", "banish": "Banish",
	"frost_nova": "Frost Nova", "analyze": "Analyze", "distract": "Distract", "pickpocket": "Pickpocket",
	"ambush": "Ambush", "vanish": "Phantom Strike", "exploit": "Exploit", "perfect_heist": "Assassinate",
	"sabotage": "Sabotage", "gambit": "Gambit", "shadowstep": "Shadowstep",
}

## The retired rank affixes' archetype lists (character.gd _*_DAMAGE_ABILITIES) - an old archetype item
## becomes one card from its list, all of which a power bonus measurably changes.
const LEGACY_ARCHETYPES := {
	"ability_rank_warrior_dmg": ["power_strike", "shield_bash", "cleave", "devastate"],
	"ability_rank_mage_dmg": ["magic_bolt", "blast", "meteor"],
	"ability_rank_trickster_dmg": ["ambush", "exploit"],
}
## A retired "+1 rank" was worth about +12% damage; it converts at one Minor power step per rank.
const LEGACY_RANK_TO_POWER := 15


static func key(kind: String, card: String) -> String:
	return "card_%s_%s" % [kind, card]


static func parse(affix_key: String) -> Array:
	"""[kind, card] for a card-gear affix key, else []."""
	if not affix_key.begins_with("card_"):
		return []
	for kind in TIER_VALUES:
		var p := "card_%s_" % kind
		if affix_key.begins_with(p):
			var card := affix_key.substr(p.length())
			if KINDS.has(card):
				return [kind, card]
	return []


static func tier_for_level(item_level: int) -> int:
	"""0/1/2 = Minor/Greater/Supreme, on the curve the rank affixes rolled (+1 at L1, +2 by ~L50,
	+3 by ~L100)."""
	return clampi(int(item_level * 0.02), 0, 2)


static func roll(item_level: int) -> Array:
	"""[affix_key, value] for one random card and one of its measured kinds."""
	var cards: Array = KINDS.keys()
	var card: String = cards[randi() % cards.size()]
	var kinds: Array = KINDS[card]
	var kind: String = kinds[randi() % kinds.size()]
	return [key(kind, card), TIER_VALUES[kind][tier_for_level(item_level)]]


static func item_bonuses(item: Dictionary) -> Array:
	"""Every card bonus an item carries, as [{card, kind, value}] with wear applied - including the
	retired rank affixes, converted on read so no stored item has to be rewritten (they live in
	inventories, houses and market listings)."""
	var out: Array = []
	if not item is Dictionary:
		return out
	var affixes = item.get("affixes", {})
	if not affixes is Dictionary:
		return out
	var wear_mult: float = 1.0 - float(item.get("wear", 0)) / 100.0
	for k in affixes:
		var ks := String(k)
		var parsed := parse(ks)
		if not parsed.is_empty():
			out.append({"card": parsed[1], "kind": parsed[0], "value": float(affixes[k]) * wear_mult})
		elif ks.begins_with("ability_rank_"):
			var ranks := float(affixes[k])
			if LEGACY_ARCHETYPES.has(ks):
				# One card, chosen from the item's identity so it never changes between reads.
				var pool: Array = LEGACY_ARCHETYPES[ks]
				# The id as a whole number where it is one: JSON (saves, and everything the client
				# receives) turns 3238168405 into 3238168405.0, and hashing the two spellings would pick
				# a different card on the server before and after a save, and on the client.
				var raw_id = item.get("id", "")
				var id_text := str(int(raw_id)) if (raw_id is int or raw_id is float) else str(raw_id)
				var seed_text := "%s|%s|%s" % [id_text, str(item.get("name", "")), ks]
				var card: String = pool[absi(hash(seed_text)) % pool.size()]
				out.append({"card": card, "kind": "power", "value": ranks * LEGACY_RANK_TO_POWER * wear_mult})
			else:
				var card2 := ks.trim_prefix("ability_rank_")
				if KINDS.has(card2) and "power" in KINDS[card2]:
					out.append({"card": card2, "kind": "power", "value": ranks * LEGACY_RANK_TO_POWER * wear_mult})
	return out


static func describe(card: String, kind: String, value: float, card_name: String = "") -> String:
	"""'+30% Cleave damage', '-15% Blast cost', '+2 rounds Rally'."""
	var n := card_name if card_name != "" else String(CARD_NAMES.get(card, card.capitalize()))
	match kind:
		"power":
			return "+%d%% %s %s" % [int(round(value)), n, String(POWER_WORDS.get(card, "damage"))]
		"cost":
			return "-%d%% %s cost" % [int(round(value)), n]
		"duration":
			var r := int(round(value))
			return "+%d round%s %s" % [r, "" if r == 1 else "s", n]
	return ""


static func describe_effect(card: String, kind: String, value: float) -> String:
	"""The bonus without the card's name: '+15% damage', '-15% cost', '+1 round'."""
	match kind:
		"power":
			return "+%d%% %s" % [int(round(value)), String(POWER_WORDS.get(card, "damage"))]
		"cost":
			return "-%d%% cost" % int(round(value))
		"duration":
			var r := int(round(value))
			return "+%d round%s" % [r, "" if r == 1 else "s"]
	return ""


static func tome_for(card: String, kind: String) -> Dictionary:
	"""A card tome as an inventory item."""
	var v: int = int(TOME_VALUES[kind])
	return {
		"id": randi(),
		"created_at": int(Time.get_unix_time_from_system()),
		"type": "card_tome",
		"card": card,
		"card_kind": kind,
		"card_value": v,
		"rarity": "legendary",
		"level": 1,
		"name": "Tome of %s: %s" % [String(CARD_NAMES.get(card, card.capitalize())), describe_effect(card, kind, v)],
		"is_consumable": true,
		"quantity": 1,
		"value": 2500,
	}


static func random_tome() -> Dictionary:
	var cards: Array = KINDS.keys()
	var card: String = cards[randi() % cards.size()]
	var kinds: Array = KINDS[card]
	return tome_for(card, kinds[randi() % kinds.size()])
