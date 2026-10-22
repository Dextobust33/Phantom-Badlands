extends RefCounted
## PERSISTENT BOONS (docs/design/combat_loop_variety.md sections 7 and 10; owner 2026-10-22).
##
## A survivor-style build that grows across fights instead of being thrown away: after some fights the player is offered a pick of three boons. A LIFE boon lasts as long as the character does and is lost with
## it; a DUNGEON boon is stronger and ends when the dungeon does. There is no slot cap, so the budget is the weakening: every boon is a PATH EFFECT (the same keys the Paths use, including `trg_<id>` trigger
## power), added to the character's totals through `Character.get_path_effect_total`, and for each effect key the contributions are sorted strongest first and the i-th counts `curve^i` of its value. The total
## for a key therefore approaches `value / (1 - curve)` and can never run away, and spreading across different keys beats stacking one - which is the point of a pick.
##
## HOW MANY: not a fixed chance per fight. A character is offered boons up to a BUDGET that follows its level (`budget_for_level`, the Path point curve, so it is a known function and the simulator can
## model it); within the budget, a fight's own weight decides whether to offer now (a hard fight always, an ordinary one sometimes). Ahead of budget the chance falls to a trickle. That keeps the count bounded
## and makes "boons by level" a decision, not a side effect of how many fights a player grinds.
const PathPointsScript = preload("res://shared/path_points.gd")
const CombatTriggersScript = preload("res://shared/combat_triggers.gd")

const LIFE_CURVE := 0.85
const DUNGEON_CURVE := 0.92
const DUNGEON_VALUE_MULT := 1.6   # a dungeon boon is worth more per pick, because it is temporary
const OFFER_SIZE := 3

## chance per fight to offer, by how hard the fight was (before the budget scales it)
const CHANCE_NORMAL := 0.10
const CHANCE_MODIFIED := 0.30        # one Empowered modifier
const BUDGET_SLACK := 3.0            # how far a character can be behind budget before the chance is at full strength
const AHEAD_FLOOR := 0.15            # a character ahead of budget still sees this share of the chance

## id -> {name, text, effect {key: value}, for: "any" | class archetype ("warrior" | "mage" | "trickster") | class name, needs_tag: a card tag the deck must hold ("" = none), weight}
## Effect values are for ONE boon; a duplicate pick stacks through the curve.
const BOONS := {
	# --- offence ---
	"keen_edge":      {"name": "Keen Edge",      "text": "+2% damage on your attacks and cards.", "effect": {"attack_damage_pct": 2}, "for": "non_mage", "weight": 10},
	"arcane_edge":    {"name": "Arcane Edge",    "text": "+2% spell damage.", "effect": {"spell_damage_pct": 2}, "for": "mage", "weight": 10},
	"opening_blow":   {"name": "Opening Blow",   "text": "Your first damaging card each fight hits 3% harder.", "effect": {"first_card_damage_pct": 3}, "for": "any", "weight": 7},
	"finisher":       {"name": "Finisher",       "text": "Cards deal 3% more to monsters under 30% HP.", "effect": {"vs_low_hp_damage_pct": 3}, "for": "any", "weight": 6},
	"sundering":      {"name": "Sundering",      "text": "Each card that hits makes the monster take 0.5% more from your cards, up to 5 times.", "effect": {"sunder_pct": 0.5}, "for": "any", "weight": 5},
	"repertoire":     {"name": "Repertoire",     "text": "Your cards deal 1% more for each different card cast this fight (up to 3).", "effect": {"variety_damage_pct": 1}, "for": "any", "weight": 6},
	# --- defence and sustain ---
	"thick_skin":     {"name": "Thick Skin",     "text": "Take 1% less damage from every hit.", "effect": {"damage_reduction_pct": 1}, "for": "any", "weight": 10},
	"hardy":          {"name": "Hardy",          "text": "+2% max HP.", "effect": {"max_hp_pct": 2}, "for": "any", "weight": 10},
	"light_step":     {"name": "Light Step",     "text": "Monsters are 1% less likely to hit you.", "effect": {"dodge_pct": 1}, "for": "any", "weight": 7},
	"second_wind":    {"name": "Second Wind",    "text": "Recover 0.2% of your max HP at the start of each round.", "effect": {"round_heal_pct": 0.2}, "for": "any", "weight": 7},
	"grit":           {"name": "Grit",           "text": "Below half HP, recover 0.5% of your max HP each round.", "effect": {"low_hp_regen_pct": 0.5}, "for": "any", "weight": 5},
	"brace_up":       {"name": "Brace Up",       "text": "Hits over a quarter of your max HP are reduced by 3%.", "effect": {"big_hit_reduction_pct": 3}, "for": "any", "weight": 5},
	"scavenger":      {"name": "Scavenger",      "text": "Killing blows heal 0.5% of your max HP.", "effect": {"kill_heal_pct": 0.5}, "for": "any", "weight": 5},
	# --- resource and tempo ---
	"focus_pool":     {"name": "Deep Reserves",  "text": "+2% max resource.", "effect": {"max_resource_pct": 2}, "for": "any", "weight": 8},
	"kill_surge":     {"name": "Kill Surge",     "text": "Killing blows restore 1.5% of your resource.", "effect": {"kill_resource_pct": 1.5}, "for": "any", "weight": 7},
	"steady_flow":    {"name": "Steady Flow",    "text": "Each card you cast restores 0.5% of your resource.", "effect": {"cast_resource_pct": 0.5}, "for": "any", "weight": 6},
	"thrifty":        {"name": "Thrifty",        "text": "1.5% chance a card refunds its whole cost.", "effect": {"card_refund_pct": 1.5}, "for": "any", "weight": 6},
	"quick_start":    {"name": "Quick Start",    "text": "Your first card each fight costs 5% less.", "effect": {"first_card_cost_pct": 5}, "for": "any", "weight": 5},
	"quickened":      {"name": "Quickened",      "text": "1% chance after a damaging card to act again.", "effect": {"extra_turn_pct": 1}, "for": "any", "weight": 4},
	# --- triggers (a boon can hand out the same triggers gear and the Ascendants do) ---
	"rhythm":         {"name": "Killing Rhythm", "text": "Trigger: a critical hit builds your class engine.", "effect": {"trg_killing_rhythm": 1}, "for": "crit", "weight": 3},
	"flourish":       {"name": "Finishing Flourish", "text": "Trigger: a finisher restores part of your pool.", "effect": {"trg_finishing_flourish": 1}, "for": "any", "needs_tag": "finisher", "weight": 3},
	"edge_setup":     {"name": "Setup Edge",     "text": "Trigger: a setup card sharpens your next card.", "effect": {"trg_setup_edge": 1}, "for": "any", "needs_tag": "setup", "weight": 3},
	"steady":         {"name": "Steady Hands",   "text": "Trigger: a guard card heals a little.", "effect": {"trg_steady_hands": 1}, "for": "any", "needs_tag": "guard", "weight": 3},
	"echo":           {"name": "Echo Bolt",      "text": "Trigger: a spell sometimes echoes.", "effect": {"trg_echo_bolt": 1}, "for": "mage", "weight": 3},
	"barbs":          {"name": "Barbed Strikes", "text": "Trigger: a strike sometimes leaves a bleed.", "effect": {"trg_barbed_strikes": 1}, "for": "any", "needs_tag": "strike", "weight": 3},
	"chill":          {"name": "Chilling Touch", "text": "Trigger: a control card sometimes slows the monster.", "effect": {"trg_chilling_touch": 1}, "for": "any", "needs_tag": "control", "weight": 3},
	"ward_buff":      {"name": "Warding Buff",   "text": "Trigger: a buff card also guards you briefly.", "effect": {"trg_warding_buff": 1}, "for": "any", "needs_tag": "buff", "weight": 3},
	"pain":           {"name": "Pain Fuel",      "text": "Trigger: a heavy blow builds your engine.", "effect": {"trg_pain_fuel": 1}, "for": "any", "weight": 3},
	"gasp":           {"name": "Last Gasp",      "text": "Trigger: once a fight, a blow that leaves you low heals you.", "effect": {"trg_last_gasp": 1}, "for": "any", "weight": 2},
	"repertoire_t":   {"name": "Full Repertoire", "text": "Trigger: three different cards in a row sharpen the next.", "effect": {"trg_variety_burst": 1}, "for": "any", "weight": 3},
	"vigor":          {"name": "Kill Vigor",     "text": "Trigger: a kill restores part of your pool.", "effect": {"trg_kill_vigor": 1}, "for": "any", "weight": 3},
	"surge_open":     {"name": "Opening Surge",  "text": "Trigger: begin each fight with engine already built.", "effect": {"trg_opening_surge": 1}, "for": "any", "weight": 2},
}

## Classes that cannot crit with cards (Steady Hand), so a crit trigger would be dead for them.
const NO_CRIT_CLASSES := ["Ranger"]


static func archetype_of(class_type: String) -> String:
	match class_type:
		"Fighter", "Barbarian", "Paladin":
			return "warrior"
		"Wizard", "Sorcerer", "Sage":
			return "mage"
		"Grifter", "Ranger", "Ninja":
			return "trickster"
	return ""


static func eligible(boon_id: String, class_type: String, deck_tags: Array) -> bool:
	"""Whether this class may be offered this boon, given the tags its deck actually holds."""
	var b: Dictionary = BOONS.get(boon_id, {})
	if b.is_empty():
		return false
	var scope: String = String(b.get("for", "any"))
	var arch: String = archetype_of(class_type)
	match scope:
		"any":
			pass
		"mage":
			if arch != "mage":
				return false
		"non_mage":
			if arch == "mage":
				return false
		"crit":
			if class_type in NO_CRIT_CLASSES:
				return false
		_:
			if scope != class_type and scope != arch:
				return false
	var need: String = String(b.get("needs_tag", ""))
	if need != "" and not (need in deck_tags):
		return false
	return true


static func budget_for_level(level: int) -> int:
	"""How many life boons a character of this level is entitled to: the Path point curve (1 per 5 levels to L100, then 1 per 50), so the count by level is a known function."""
	return PathPointsScript.from_level(level)


static func fight_kind(info: Dictionary) -> String:
	"""'hard' (always offers), 'modified' or 'normal', from what the victory result says about the monster."""
	if bool(info.get("is_boss_fight", false)) or bool(info.get("is_apex_variant", false)) or bool(info.get("is_rare_variant", false)):
		return "hard"
	if String(info.get("monster_variant_type", "")) == "elite":
		return "hard"
	var mods = info.get("empowered_mods", [])
	var n: int = (mods as Array).size() if mods is Array else 0
	if n >= 2:
		return "hard"
	if n == 1:
		return "modified"
	return "normal"


static func offer_chance(kind: String, level: int, taken_total: int) -> float:
	"""Probability a fight offers a boon NOW. Hard fights always offer unless the character is far ahead of budget; the rest scale with how far BEHIND budget it is."""
	var deficit: float = float(budget_for_level(level) - taken_total)
	if kind == "hard":
		return 1.0 if deficit > -BUDGET_SLACK else 0.0
	var base: float = CHANCE_MODIFIED if kind == "modified" else CHANCE_NORMAL
	var scale: float = clampf(deficit / BUDGET_SLACK, AHEAD_FLOOR, 1.0) if deficit > 0.0 else AHEAD_FLOOR * 0.5
	return base * scale


static func roll_options(class_type: String, deck_tags: Array, held: Dictionary, rng: RandomNumberGenerator) -> Array:
	"""Three different eligible boons, weighted; a boon the character already holds is a little LESS likely (the curve already makes a repeat worth less)."""
	var pool: Array = []
	for id in BOONS:
		if eligible(String(id), class_type, deck_tags):
			var w: float = float(BOONS[id].get("weight", 5))
			w *= 1.0 / (1.0 + 0.5 * float(int(held.get(String(id), 0))))
			pool.append([String(id), w])
	var out: Array = []
	while out.size() < OFFER_SIZE and not pool.is_empty():
		var total := 0.0
		for p in pool:
			total += float(p[1])
		var roll: float = rng.randf() * total
		var idx := 0
		for i in range(pool.size()):
			roll -= float(pool[i][1])
			if roll <= 0.0:
				idx = i
				break
		out.append(String(pool[idx][0]))
		pool.remove_at(idx)
	return out


static func _contributions(counts: Dictionary, value_mult: float) -> Dictionary:
	"""key -> list of values, one entry per boon instance."""
	var out: Dictionary = {}
	for id in counts:
		var b: Dictionary = BOONS.get(String(id), {})
		if b.is_empty():
			continue
		for key in b.get("effect", {}):
			if not out.has(key):
				out[key] = []
			for i in range(int(counts[id])):
				out[key].append(float(b["effect"][key]) * value_mult)
	return out


static func _curve_sum(values: Array, curve: float) -> float:
	var v: Array = values.duplicate()
	v.sort()
	v.reverse()
	var total := 0.0
	for i in range(v.size()):
		total += float(v[i]) * pow(curve, float(i))
	return total


static func effect_totals(life: Dictionary, dungeon: Dictionary) -> Dictionary:
	"""key -> total contributed by held boons: strongest first, each next one counting `curve` times less. Life and dungeon boons each follow their own curve."""
	var out: Dictionary = {}
	var lc: Dictionary = _contributions(life, 1.0)
	for key in lc:
		out[key] = float(out.get(key, 0.0)) + _curve_sum(lc[key], LIFE_CURVE)
	var dc: Dictionary = _contributions(dungeon, DUNGEON_VALUE_MULT)
	for key in dc:
		out[key] = float(out.get(key, 0.0)) + _curve_sum(dc[key], DUNGEON_CURVE)
	return out


static func ceiling_for(effect_key: String, boon_ids: Array) -> float:
	"""The most a key can ever receive from LIFE boons if every boon that carries it were held infinitely: the geometric limit of the strongest value."""
	var best := 0.0
	for id in boon_ids:
		var b: Dictionary = BOONS.get(String(id), {})
		if b.get("effect", {}).has(effect_key):
			best = maxf(best, float(b["effect"][effect_key]))
	return best / (1.0 - LIFE_CURVE)


static func name_of(boon_id: String) -> String:
	return String(BOONS.get(boon_id, {}).get("name", boon_id))


static func text_of(boon_id: String) -> String:
	return String(BOONS.get(boon_id, {}).get("text", ""))
