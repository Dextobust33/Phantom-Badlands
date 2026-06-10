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
		"unique_effect": {"outsmart_pct": 20, "valor_pct": 10},
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


static func get_unique(unique_id: String) -> Dictionary:
	return UNIQUES.get(unique_id, {})


static func random_unique_id() -> String:
	var keys: Array = UNIQUES.keys()
	return String(keys[randi() % keys.size()])
