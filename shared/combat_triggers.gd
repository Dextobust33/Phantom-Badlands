extends RefCounted
## COMBAT TRIGGERS (docs/design/combat_loop_variety.md section 3C, owner's pilot pick 2026-10-22).
##
## A trigger is an effect that fires on a combat EVENT: "when you crit, +1 engine stack", "after a setup card, your next hit deals +15%".
## It is what lets a piece of loot or a path node change how a deck PLAYS rather than how hard it hits - and it is the unit a persistent boon
## (section 10 of the design doc) will hand out later.
##
## THREE PARTS, all data:
##   TAGS      what kind of card each card is (strike, spell, finisher, setup, guard, buff, control, debuff)
##   TRIGGERS  id -> event, tag filter, chance, effect, per-fight cap
##   POWER     how strong a holder's copy is: `Character.trigger_power(id)` = the sum of the effect key "trg_<id>" over path nodes, unique items
##             and set bonuses (every one of them already flows through `get_path_effect_total`), plus a gear affix of the same key.
##             Power multiplies the effect's value and its chance, so a rank-3 node or a Supreme item is three times a Minor one.
##
## Events: on_cast (a card resolved), on_hit (it dealt damage), on_crit (that damage was a crit), on_kill, on_hurt (a monster's blow got through),
##         on_fight_start. The executor lives in combat_manager.gd (`_fire_triggers`) because every effect needs the live fight.

## What each card IS. A card can carry several tags. Unlisted cards (dungeon cards) get `default_tags`.
const TAGS := {
	"power_strike": ["strike"], "cleave": ["strike"], "shield_bash": ["strike", "control"], "devastate": ["strike", "finisher"],
	"war_cry": ["setup", "debuff"], "berserk": ["buff"], "iron_skin": ["guard"], "fortify": ["guard"], "rally": ["buff"],
	"magic_bolt": ["spell", "strike"], "blast": ["spell", "strike"], "meteor": ["spell", "strike", "finisher"],
	"forcefield": ["spell", "guard"], "haste": ["spell", "buff"], "paralyze": ["spell", "control"], "banish": ["spell", "control"],
	"frost_nova": ["spell", "strike", "control"], "analyze": ["setup"],
	"distract": ["setup", "debuff"], "pickpocket": ["setup"], "ambush": ["strike"], "vanish": ["setup", "buff"], "exploit": ["strike"],
	"perfect_heist": ["strike", "finisher"], "sabotage": ["setup", "debuff"], "gambit": ["strike"], "shadowstep": ["buff", "guard"],
}


## The 53 dungeon cards are tagged by what their `kind` DOES (drop_tables.DUNGEON_CARD_DATA[...].kind), so a new card costs one data field and a new KIND fails the probe
## `dungeon_cards_tagged` until it is placed here. Owner decision 2026-10-22: every dungeon card carries tags, so trigger gear and Ascendants work with them.
const DUNGEON_KIND_TAGS := {
	"poison": ["strike", "debuff"], "bleed": ["strike", "debuff"], "weaken": ["strike", "debuff"],
	"lifesteal": ["strike"], "tribute": ["strike"], "plunder": ["strike"], "reckless": ["strike"], "strike": ["strike"], "channel": ["strike"],
	"execute": ["strike", "finisher"],
	"blind": ["strike", "control"], "stun": ["strike", "control"], "charm": ["strike", "control"],
	"shield": ["guard"], "guard": ["guard"], "heal": ["guard"],
	"rage": ["buff"], "focus": ["buff"],
	"timestop": ["control"],
}


static func tags_for(card: String, damaging: bool = true) -> Array:
	if TAGS.has(card):
		return TAGS[card]
	if card.begins_with("dungeon_card_"):
		# loaded at call time, not preloaded: drop_tables preloads THIS script for gear rolls, and a preload each way is a cycle
		var data: Dictionary = load("res://shared/drop_tables.gd").DUNGEON_CARD_DATA.get(card.trim_prefix("dungeon_card_"), {})
		if not data.is_empty():
			return DUNGEON_KIND_TAGS.get(String(data.get("kind", "")), ["strike"] if damaging else [])
	return ["strike"] if damaging else []


## effect kinds (executed in combat_manager._fire_triggers):
##   engine         + `value` x power stacks of the class engine (Momentum / Read / Focus)
##   resource_pct   restore `value` x power % of the class's own resource pool
##   heal_pct       heal `value` x power % of max HP
##   next_damage    the next DAMAGING card deals +`value` x power %
##   echo_hit       bonus damage equal to `value`% of the triggering hit (never lethal)
##   bleed          a bleed worth `value`% of the triggering hit, 3 rounds
##   slow           slow the monster `value` x power %, `rounds` rounds (it then hits less - see monster_slowed)
##   guard          `value` x power % damage reduction for `rounds` rounds (its own buff, multiplies with everything)
## `chance` is a base percent, multiplied by power and capped at 100. `per_fight` caps how often it can fire in one fight.
## `when` is an extra condition read by the executor: "hurt_15" (the blow took 15%+ of max HP), "low_hp" (under 35% HP after the blow),
##   "variety" (the last three cards were three different cards).
const TRIGGERS := {
	"killing_rhythm": {"name": "Killing Rhythm", "event": "on_crit", "tags": [], "chance": 100, "effect": "engine", "value": 1, "per_fight": 4,
		"text": "A critical hit builds +1 of your class engine (Momentum, Read or Focus). Up to 4 times a fight."},
	"finishing_flourish": {"name": "Finishing Flourish", "event": "on_cast", "tags": ["finisher"], "chance": 100, "effect": "resource_pct", "value": 8, "per_fight": 3,
		"text": "A finisher restores 8% of your pool."},
	"setup_edge": {"name": "Setup Edge", "event": "on_cast", "tags": ["setup"], "chance": 100, "effect": "next_damage", "value": 15, "per_fight": 6,
		"text": "A setup card makes your next damaging card hit 15% harder."},
	"steady_hands": {"name": "Steady Hands", "event": "on_cast", "tags": ["guard"], "chance": 100, "effect": "heal_pct", "value": 3, "per_fight": 4,
		"text": "A guard card heals 3% of your max HP."},
	"echo_bolt": {"name": "Echo Bolt", "event": "on_hit", "tags": ["spell"], "chance": 12, "effect": "echo_hit", "value": 50, "per_fight": 6,
		"text": "12% chance a spell echoes for 50% of its damage."},
	"barbed_strikes": {"name": "Barbed Strikes", "event": "on_hit", "tags": ["strike"], "chance": 15, "effect": "bleed", "value": 25, "per_fight": 5,
		"text": "15% chance a strike leaves a bleed worth 25% of the hit."},
	"chilling_touch": {"name": "Chilling Touch", "event": "on_cast", "tags": ["control"], "chance": 30, "effect": "slow", "value": 20, "rounds": 2, "per_fight": 4,
		"text": "30% chance a control card slows the monster 20% for 2 rounds."},
	"warding_buff": {"name": "Warding Buff", "event": "on_cast", "tags": ["buff"], "chance": 100, "effect": "guard", "value": 8, "rounds": 2, "per_fight": 4,
		"text": "A buff card also grants 8% damage reduction for 2 rounds."},
	"pain_fuel": {"name": "Pain Fuel", "event": "on_hurt", "tags": [], "when": "hurt_15", "chance": 100, "effect": "engine", "value": 1, "per_fight": 3,
		"text": "A blow that takes 15% or more of your max HP builds +1 of your class engine. Up to 3 times a fight."},
	"last_gasp": {"name": "Last Gasp", "event": "on_hurt", "tags": [], "when": "low_hp", "chance": 100, "effect": "heal_pct", "value": 12, "per_fight": 1,
		"text": "Once a fight, a blow that leaves you under 35% HP heals 12% of your max HP."},
	"variety_burst": {"name": "Full Repertoire", "event": "on_cast", "tags": [], "when": "variety", "chance": 100, "effect": "next_damage", "value": 25, "per_fight": 3,
		"text": "Cast three different cards in a row and your next damaging card hits 25% harder."},
	"kill_vigor": {"name": "Kill Vigor", "event": "on_kill", "tags": [], "chance": 100, "effect": "resource_pct", "value": 6, "per_fight": 1,
		"text": "A kill restores 6% of your pool."},
	# --- the Ascendant tier's own triggers (class flavour; see PathDatabase.ASCENDANTS) ---
	"bulwark_drive": {"name": "Bulwark Drive", "event": "on_cast", "tags": ["guard"], "chance": 100, "effect": "engine", "value": 2, "per_fight": 4,
		"text": "A guard card builds +2 Momentum. Up to 4 times a fight."},
	"rampage_feast": {"name": "Rampage Feast", "event": "on_cast", "tags": ["finisher"], "chance": 100, "effect": "heal_pct", "value": 10, "per_fight": 3,
		"text": "A finisher heals 10% of your max HP."},
	"judgement_mend": {"name": "Judgement's Mantle", "event": "on_cast", "tags": ["finisher"], "chance": 100, "effect": "guard", "value": 15, "rounds": 3, "per_fight": 3,
		"text": "A finisher wraps you in 15% damage reduction for 3 rounds."},
	"meteor_ember": {"name": "Meteor Ember", "event": "on_hit", "tags": [], "cards": ["meteor"], "chance": 100, "effect": "burn", "value": 40, "per_fight": 4,
		"text": "Meteor leaves a burn worth 40% of its damage over 3 rounds."},
	"stormsurge": {"name": "Stormsurge", "event": "on_cast", "tags": ["spell"], "chance": 20, "effect": "next_damage", "value": 30, "per_fight": 5,
		"text": "20% chance a spell makes your next damaging card hit 30% harder."},
	"seer_flow": {"name": "Seer's Flow", "event": "on_cast", "tags": ["setup", "control"], "chance": 100, "effect": "engine", "value": 1, "per_fight": 4,
		"text": "A setup or control card builds +1 Focus. Up to 4 times a fight."},
	"cash_out_refund": {"name": "Cash Out", "event": "on_cast", "tags": ["finisher"], "chance": 100, "effect": "resource_pct", "value": 25, "per_fight": 2,
		"text": "A finisher restores 25% of your pool. Twice a fight."},
	"hunters_mark": {"name": "Hunter's Mark", "event": "on_cast", "tags": ["setup"], "chance": 100, "effect": "next_damage", "value": 20, "per_fight": 4,
		"text": "A setup card marks the quarry: your next damaging card hits 20% harder."},
	"shadow_gift": {"name": "Shadow's Gift", "event": "on_cast", "tags": ["buff"], "chance": 100, "effect": "engine", "value": 2, "per_fight": 3,
		"text": "A buff card builds +2 Read. Up to 3 times a fight."},
	"opening_surge": {"name": "Opening Surge", "event": "on_fight_start", "tags": [], "chance": 100, "effect": "engine", "value": 1, "per_fight": 1,
		"text": "You begin every fight with +1 of your class engine already built."},
}

const KEY_PREFIX := "trg_"


static func key_for(id: String) -> String:
	return KEY_PREFIX + id


static func ids() -> Array:
	return TRIGGERS.keys()


static func describe(id: String, power: float = 1.0) -> String:
	"""The trigger's own text at `power` (1 = one node rank / a Minor roll). Scales the numbers the text states."""
	var t: Dictionary = TRIGGERS.get(id, {})
	if t.is_empty():
		return ""
	var txt: String = String(t.get("text", ""))
	if power <= 1.0:
		return txt
	return "%s (x%s)" % [txt, str(snappedf(power, 0.1))]


# ---- trigger GEAR -------------------------------------------------------------------------------------------------------------------------------------
## An epic+ chase roll can land a trigger instead of a number. It is stored as the affix "trg_<id>" with a power of 1 / 2 / 3 by item level, and wears with
## the item like every other affix (Character.trigger_power sums it through `_sum_affix_across_equipped`).
const CardGearScript = preload("res://shared/card_gear.gd")


static func roll(item_level: int) -> Array:
	"""[affix_key, power] for one random trigger. Power by the same item-level tiers card gear uses."""
	var all: Array = TRIGGERS.keys()
	var id: String = all[randi() % all.size()]
	return [key_for(id), float(1 + CardGearScript.tier_for_level(item_level))]


static func item_triggers(item) -> Array:
	"""Every trigger an item carries, as [{id, power}], wear applied."""
	var out: Array = []
	if not item is Dictionary:
		return out
	var affixes = item.get("affixes", {})
	if not affixes is Dictionary:
		return out
	var wear_mult: float = 1.0 - float(item.get("wear", 0)) / 100.0
	for k in affixes:
		var ks := String(k)
		if ks.begins_with(KEY_PREFIX) and TRIGGERS.has(ks.substr(KEY_PREFIX.length())):
			out.append({"id": ks.substr(KEY_PREFIX.length()), "power": float(affixes[k]) * wear_mult})
	return out


static func item_line(id: String, power: float) -> String:
	"""One line of item text: the trigger's name and what it does, with its strength tier."""
	var t: Dictionary = TRIGGERS.get(id, {})
	if t.is_empty():
		return ""
	var tier: String = ["Minor", "Greater", "Supreme"][clampi(int(round(power)) - 1, 0, 2)]
	return "%s (%s): %s" % [String(t.get("name", id)), tier, String(t.get("text", ""))]
