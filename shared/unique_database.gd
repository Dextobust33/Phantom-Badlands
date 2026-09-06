# unique_database.gd
# Uniques (ARPG pillar 4, design 2026-06-10) — hand-authored named items.
#
# Anatomy: numeric stats come from the normal artifact-rarity generator at the
# DROP level (uniques scale forever); the SIGNATURE effect is fixed and lives
# in item.unique_effect — summed by character.get_path_effect_total alongside
# Path talent nodes, so every wired Path/build effect key works on gear with
# zero extra combat code. bonus_affixes merge into the regular affix dict
# (chase keys like extra_turn_chance live there).
#
# Drop roll (server victory): 0.25% base + 0.75% per Empowered modifier on the
# kill + 2.5% on boss kills. Any class can find any unique — market trading is
# part of the loop.
class_name UniqueDatabase

const UNIQUES = {
	# === WEAPONS ===
	"bloodletters_hook": {
		"name": "Bloodletter's Hook", "item_type": "weapon_artifact",
		"lore": "It does not cut. It unseams.",
		"unique_effect": {"bleed_power_pct": 100, "attack_damage_pct": 5},
	},
	"cinderheart_staff": {
		"name": "Cinderheart Staff", "item_type": "weapon_artifact",
		"lore": "The ember at its core has never agreed to go out.",
		"unique_effect": {"burn_power_pct": 100, "spell_damage_pct": 5},
	},
	"fang_of_the_unseen": {
		"name": "Fang of the Unseen", "item_type": "weapon_artifact",
		"lore": "Found buried in a victim no one remembers killing.",
		"unique_effect": {"crit_chance_pct": 8, "crit_bleed_wit_pct": 20, "crit_bleed_rounds": 3},
	},
	# === SHIELDS ===
	"wall_of_the_fallen": {
		"name": "Wall of the Fallen", "item_type": "shield_artifact",
		"lore": "Every dent is a name.",
		"unique_effect": {"melee_reflect_pct": 25, "defense_pct": 8},
	},
	"aegis_of_the_archon": {
		"name": "Aegis of the Archon", "item_type": "shield_artifact",
		"lore": "The Archon needed no armor. The Aegis disagreed.",
		"unique_effect": {"forcefield_power_pct": 50, "defense_pct": 5},
	},
	# === HELMS ===
	"warbringers_crown": {
		"name": "Warbringer's Crown", "item_type": "helm_artifact",
		"lore": "Armies followed the voice beneath it into fire.",
		"unique_effect": {"buff_value_pct": 15, "buff_duration_bonus": 1},
	},
	# === ARMOR ===
	"phantom_shroud": {
		"name": "Phantom Shroud", "item_type": "armor_artifact",
		"lore": "Wear it loosely. It remembers being free.",
		"unique_effect": {"first_strike_autocrit": true, "flee_chance_pct": 10},
	},
	"avarice_golden_burden": {
		"name": "Avarice, the Golden Burden", "item_type": "armor_artifact",
		"lore": "Heavy with everything it has ever been promised.",
		"unique_effect": {"loot_reveal_bonus": 1, "xp_pct": -10},
	},
	# === BOOTS ===
	"gravewhisper_boots": {
		"name": "Gravewhisper Boots", "item_type": "boots_artifact",
		"lore": "They make exactly one sound, and you will never hear it.",
		"unique_effect": {"failed_flee_dodge_pct": 40, "flee_chance_pct": 8},
	},
	"worldbreaker_greaves": {
		"name": "Worldbreaker Greaves", "item_type": "boots_artifact",
		"lore": "Stand your ground. The ground will not enjoy it.",
		"unique_effect": {"low_hp_damage_pct": 25, "max_hp_pct": -5},
	},
	# === RINGS ===
	"the_long_con": {
		"name": "The Long Con", "item_type": "ring_artifact",
		"lore": "Its first owner sold it twice. Its second owner was its first owner.",
		"unique_effect": {"assassinate_pct": 20, "valor_pct": 10},
	},
	"sevenfold_die": {
		"name": "The Sevenfold Die", "item_type": "ring_artifact",
		"lore": "Six faces show numbers. The seventh shows you.",
		"bonus_affixes": {"extra_turn_chance": 7},
	},
	# === AMULETS ===
	"juggernauts_heart": {
		"name": "Juggernaut's Heart", "item_type": "amulet_artifact",
		"lore": "It beats four times a day. Nothing interrupts it.",
		"unique_effect": {"stun_immune": true, "defense_pct": 10},
	},
	"the_second_sun": {
		"name": "The Second Sun", "item_type": "amulet_artifact",
		"lore": "Every spell casts a shadow. This is where they land.",
		"unique_effect": {"double_cast_pct": 10},
	},
	"hourglass_unbroken": {
		"name": "The Hourglass, Unbroken", "item_type": "amulet_artifact",
		"lore": "The sand ran out once. Once.",
		"unique_effect": {"clutch_time_stop_per_combat": 1},
	},
}


# === SETS (pillar 4 slice 2) ===
# Set pieces generate like uniques (artifact stats at drop level, fixed name +
# lore + set_id) but carry NO individual signature — the chase is the set
# bonus, which activates by equipped-piece count. Bonus effect dicts use the
# same Path/unique key vocabulary and are summed by get_path_effect_total.
const SETS = {
	"gravewalkers_vigil": {
		"name": "The Gravewalker's Vigil",
		"bonuses": {
			2: {"defense_pct": 10, "kill_cleanse": true},
			3: {"death_save_per_combat": 1, "low_hp_damage_pct": 20},
		},
		"bonus_desc": {
			2: "+10% defense; killing blows cleanse your poison and bleed",
			3: "Once per combat, survive a lethal hit at 1 HP; +20% damage below half HP",
		},
		"pieces": {
			"gravewalkers_cleaver": {"name": "Gravewalker's Cleaver", "item_type": "weapon_artifact", "lore": "It remembers every grave it dug."},
			"gravewalkers_bulwark": {"name": "Gravewalker's Bulwark", "item_type": "shield_artifact", "lore": "Coffin-lid oak, iron-banded twice."},
			"gravewalkers_visage": {"name": "Gravewalker's Visage", "item_type": "helm_artifact", "lore": "The dead do not yield. Neither will you."},
		},
	},
	"stormcallers_regalia": {
		"name": "Regalia of the Stormcaller",
		"bonuses": {
			2: {"spell_damage_pct": 10, "combat_regen_bonus_pct": 25},
			3: {"double_cast_pct": 10, "burn_power_pct": 50},
		},
		"bonus_desc": {
			2: "+10% spell damage; in-combat mana regen 25% stronger",
			3: "+10% chance to cast spells twice; your burns tick 50% harder",
		},
		"pieces": {
			"stormcallers_rod": {"name": "Stormcaller's Rod", "item_type": "weapon_artifact", "lore": "The sky answers. It does not ask why."},
			"stormcallers_robes": {"name": "Stormcaller's Robes", "item_type": "armor_artifact", "lore": "Woven during the storm, from the storm."},
			"stormcallers_eye": {"name": "Stormcaller's Eye", "item_type": "amulet_artifact", "lore": "It blinked once, in the year of the drowned sun."},
		},
	},
	"magpies_hoard": {
		"name": "The Magpie's Hoard",
		"bonuses": {
			2: {"valor_pct": 15, "flee_chance_pct": 8},
			3: {"loot_reveal_bonus": 1, "crit_chance_pct": 5},
		},
		"bonus_desc": {
			2: "+15% Valor from kills; +8% flee chance",
			3: "+1 loot reveal on every victory; +5% critical hit chance",
		},
		"pieces": {
			"magpies_steps": {"name": "Magpie's Steps", "item_type": "boots_artifact", "lore": "Always one hop ahead of the owner."},
			"magpies_claw": {"name": "Magpie's Claw", "item_type": "ring_artifact", "lore": "It holds what it likes. It likes everything."},
			"magpies_mantle": {"name": "Magpie's Mantle", "item_type": "armor_artifact", "lore": "Lined with a hundred shining little thefts."},
		},
	},
}


static func get_unique(unique_id: String) -> Dictionary:
	return UNIQUES.get(unique_id, {})


static func get_set(set_id: String) -> Dictionary:
	return SETS.get(set_id, {})


static func find_set_piece(piece_id: String) -> Dictionary:
	"""Locate a set piece by id. Returns the piece dict + 'set_id' + 'set_name',
	or {} when unknown."""
	for set_id in SETS:
		var pieces: Dictionary = SETS[set_id].get("pieces", {})
		if pieces.has(piece_id):
			var out: Dictionary = pieces[piece_id].duplicate()
			out["set_id"] = set_id
			out["set_name"] = String(SETS[set_id].get("name", set_id))
			return out
	return {}


static func random_unique_id() -> String:
	var keys: Array = UNIQUES.keys()
	return String(keys[randi() % keys.size()])


static func random_named_drop_id() -> String:
	"""Uniform pool of all named drops: 15 uniques + 9 set pieces. The server
	victory roll picks from this — set pieces are 9/24 of named drops, so a
	3-piece set is a real chase."""
	var pool: Array = UNIQUES.keys()
	for set_id in SETS:
		pool.append_array(SETS[set_id].get("pieces", {}).keys())
	return String(pool[randi() % pool.size()])
