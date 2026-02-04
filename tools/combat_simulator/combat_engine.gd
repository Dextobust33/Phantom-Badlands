# combat_engine.gd
# Combat damage formulas ported from shared/combat_manager.gd
# For combat simulation without network/server dependencies
extends RefCounted
class_name CombatEngine

# Balance configuration (from server/balance_config.json)
var balance_config: Dictionary = {
	"combat": {
		"player_str_multiplier": 0.02,
		"player_crit_base": 5,
		"player_crit_per_dex": 0.5,
		"player_crit_max": 25,
		"player_crit_damage": 1.5,
		"monster_level_diff_base": 1.035,
		"monster_level_diff_cap": 100,
		"defense_formula_constant": 100,
		"defense_max_reduction": 0.6,
		"equipment_defense_cap": 0.4,
		"equipment_defense_divisor": 400
	},
	"monster_abilities": {
		"corrosive_chance": 15,
		"sunder_chance": 20,
		"poison_damage_percent": 20,
		"life_steal_percent": 50,
		"regeneration_percent": 10,
		"damage_reflect_percent": 25,
		"thorns_percent": 25,
		"ethereal_dodge_chance": 50,
		"curse_defense_reduction": 25,
		"disarm_damage_reduction": 30,
		"disarm_duration": 3,
		"summoner_chance": 20,
		"ambusher_multiplier": 1.75,
		"enrage_per_round": 10,
		"berserker_bonus": 50,
		"death_curse_percent": 25,
		"glass_cannon_damage_mult": 3.0,
		"glass_cannon_hp_mult": 0.5,
		"multi_strike_min": 2,
		"multi_strike_max": 3,
		"blind_hit_reduction": 30,
		"bleed_damage_percent": 15,
		"bleed_chance": 40,
		"slow_aura_flee_reduction": 25,
		"weakness_chance": 30
	}
}

# Monster ability constants (from monster_database.gd)
const ABILITY_GLASS_CANNON = "glass_cannon"
const ABILITY_MULTI_STRIKE = "multi_strike"
const ABILITY_POISON = "poison"
const ABILITY_MANA_DRAIN = "mana_drain"
const ABILITY_STAMINA_DRAIN = "stamina_drain"
const ABILITY_ENERGY_DRAIN = "energy_drain"
const ABILITY_REGENERATION = "regeneration"
const ABILITY_DAMAGE_REFLECT = "damage_reflect"
const ABILITY_ETHEREAL = "ethereal"
const ABILITY_ARMORED = "armored"
const ABILITY_SUMMONER = "summoner"
const ABILITY_PACK_LEADER = "pack_leader"
const ABILITY_CURSE = "curse"
const ABILITY_DISARM = "disarm"
const ABILITY_UNPREDICTABLE = "unpredictable"
const ABILITY_DEATH_CURSE = "death_curse"
const ABILITY_BERSERKER = "berserker"
const ABILITY_COWARD = "coward"
const ABILITY_LIFE_STEAL = "life_steal"
const ABILITY_ENRAGE = "enrage"
const ABILITY_AMBUSHER = "ambusher"
const ABILITY_THORNS = "thorns"
const ABILITY_BLIND = "blind"
const ABILITY_BLEED = "bleed"
const ABILITY_SLOW_AURA = "slow_aura"
const ABILITY_WEAKNESS = "weakness"
const ABILITY_CHARM = "charm"
const ABILITY_GOLD_STEAL = "gold_steal"
const ABILITY_BUFF_DESTROY = "buff_destroy"
const ABILITY_SHIELD_SHATTER = "shield_shatter"
const ABILITY_XP_STEAL = "xp_steal"
const ABILITY_ITEM_STEAL = "item_steal"
const ABILITY_FLEE_ATTACK = "flee_attack"

# Undead/demon monster names for Paladin bonus
const UNDEAD_DEMON_NAMES = [
	"skeleton", "zombie", "wraith", "wight", "lich", "elder lich", "vampire", "nazgul", "death incarnate",
	"demon", "demon lord", "balrog", "succubus"
]

# Beast names for Ranger bonus
const BEAST_NAMES = [
	"giant rat", "wolf", "dire wolf", "giant spider", "bear", "dire bear",
	"wyvern", "gryphon", "chimaera", "cerberus", "hydra",
	"world serpent", "harpy", "minotaur"
]

# Combat state for a single fight
class CombatState:
	var round: int = 0
	var player_can_act: bool = true
	var enrage_stacks: int = 0
	var curse_applied: bool = false
	var disarm_applied: bool = false
	var ambusher_active: bool = true  # First attack
	var player_bleed_stacks: int = 0
	var player_bleed_damage: int = 0
	var player_charmed: bool = false
	var monster_fled: bool = false

	func reset():
		round = 0
		player_can_act = true
		enrage_stacks = 0
		curse_applied = false
		disarm_applied = false
		ambusher_active = true
		player_bleed_stacks = 0
		player_bleed_damage = 0
		player_charmed = false
		monster_fled = false

func _init():
	pass

func set_balance_config(cfg: Dictionary):
	"""Set custom balance configuration"""
	balance_config = cfg

func calculate_player_damage(character, monster: Dictionary, combat_state: CombatState) -> Dictionary:
	"""Calculate player damage to monster
	Returns {damage: int, is_crit: bool, backfire_damage: int}
	Based on combat_manager.gd lines 3436-3606"""
	var cfg = balance_config.get("combat", {})
	var passive = character.get_class_passive()
	var effects = passive.get("effects", {})

	# Base damage from attack stat
	var base_damage = character.get_total_attack()

	# Apply STR percentage bonus (+2% per point)
	var str_stat = character.get_effective_stat("strength")
	var str_mult = cfg.get("player_str_multiplier", 0.02)
	var str_multiplier = 1.0 + (str_stat * str_mult)
	base_damage = int(base_damage * str_multiplier)

	# Add 1d6 roll
	var damage_roll = (randi() % 6) + 1
	var raw_damage = base_damage + damage_roll

	# Apply damage buff (War Cry, etc.)
	var damage_buff = character.get_buff_value("damage")
	if damage_buff > 0:
		raw_damage = int(raw_damage * (1.0 + damage_buff / 100.0))
	elif damage_buff < 0:  # Disarm debuff
		raw_damage = int(raw_damage * (1.0 + damage_buff / 100.0))

	# CLASS PASSIVE: Barbarian Blood Rage
	# +3% damage per 10% HP missing, max +30%
	if effects.has("damage_per_missing_hp"):
		var hp_percent = float(character.current_hp) / float(character.max_hp)
		var missing_hp_percent = 1.0 - hp_percent
		var rage_bonus = min(effects.get("max_rage_bonus", 0.30), missing_hp_percent * effects.get("damage_per_missing_hp", 0.03) * 10.0)
		if rage_bonus > 0.01:
			raw_damage = int(raw_damage * (1.0 + rage_bonus))

	# Critical hit calculation
	var dex_stat = character.get_effective_stat("dexterity")
	var crit_base = cfg.get("player_crit_base", 5)
	var crit_per_dex = cfg.get("player_crit_per_dex", 0.5)
	var crit_damage = cfg.get("player_crit_damage", 1.5)

	var crit_chance = crit_base + int(dex_stat * crit_per_dex)

	# CLASS PASSIVE: Thief Backstab (+10% crit chance)
	if effects.has("crit_chance_bonus"):
		crit_chance += int(effects.get("crit_chance_bonus", 0) * 100)

	crit_chance = min(crit_chance, 75)  # Cap at 75%
	var is_crit = (randi() % 100) < crit_chance

	# CLASS PASSIVE: Thief Backstab crit damage bonus (+35%)
	var final_crit_damage = crit_damage
	if is_crit and effects.has("crit_damage_bonus"):
		final_crit_damage += effects.get("crit_damage_bonus", 0)

	if is_crit:
		raw_damage = int(raw_damage * final_crit_damage)

	# CLASS PASSIVE: Sorcerer Chaos Magic
	var backfire_damage = 0
	if effects.has("double_damage_chance"):
		var chaos_roll = randf()
		if chaos_roll < effects.get("backfire_chance", 0.05):
			backfire_damage = int(raw_damage * 0.5)
			raw_damage = int(raw_damage * 0.5)
		elif chaos_roll < effects.get("backfire_chance", 0.05) + effects.get("double_damage_chance", 0.25):
			raw_damage = raw_damage * 2

	# CLASS PASSIVE: Wizard Arcane Precision (+15% spell damage)
	if effects.has("spell_damage_bonus"):
		raw_damage = int(raw_damage * (1.0 + effects.get("spell_damage_bonus", 0)))

	# Monster defense reduction
	var defense_constant = cfg.get("defense_formula_constant", 100)
	var defense_max = cfg.get("defense_max_reduction", 0.6)
	var defense_ratio = float(monster.defense) / (float(monster.defense) + defense_constant)
	var damage_reduction = defense_ratio * defense_max
	var total = int(raw_damage * (1.0 - damage_reduction))

	# Class advantage multiplier
	var affinity = monster.get("class_affinity", 0)
	var class_multiplier = _get_class_advantage_multiplier(affinity, character.class_type)
	total = int(total * class_multiplier)

	# Level difference penalty (1.5% per level, max 25%)
	var lvl_diff = monster.get("level", 1) - character.level
	if lvl_diff > 0:
		var lvl_penalty = min(0.25, lvl_diff * 0.015)
		total = int(total * (1.0 - lvl_penalty))

	# CLASS PASSIVE: Paladin Divine Favor (+25% vs undead/demons)
	if effects.has("bonus_vs_undead"):
		var monster_name = monster.get("name", "").to_lower()
		var monster_type = monster.get("type", "").to_lower()
		if "undead" in monster_type or "demon" in monster_type or monster_name in UNDEAD_DEMON_NAMES:
			total = int(total * (1.0 + effects.get("bonus_vs_undead", 0)))

	# CLASS PASSIVE: Ranger Hunter's Mark (+25% vs beasts)
	if effects.has("bonus_vs_beasts"):
		var monster_name = monster.get("name", "").to_lower()
		var monster_type = monster.get("type", "").to_lower()
		if "beast" in monster_type or "animal" in monster_type or monster_name in BEAST_NAMES:
			total = int(total * (1.0 + effects.get("bonus_vs_beasts", 0)))

	# Weakness debuff (-25% attack)
	var weakness_penalty = character.get_debuff_value("weakness")
	if weakness_penalty > 0:
		total = int(total * (1.0 - weakness_penalty / 100.0))

	return {"damage": max(1, total), "is_crit": is_crit, "backfire_damage": backfire_damage}

func _get_class_advantage_multiplier(affinity: int, character_class: String) -> float:
	"""Calculate damage multiplier based on class affinity
	Returns: 1.0 (neutral), 1.25 (advantage), 0.85 (disadvantage)"""
	var player_path = _get_player_class_path(character_class)

	match affinity:
		1:  # PHYSICAL - Warriors do +25%, Mages do -15%
			if player_path == "warrior":
				return 1.25
			elif player_path == "mage":
				return 0.85
		2:  # MAGICAL - Mages do +25%, Warriors do -15%
			if player_path == "mage":
				return 1.25
			elif player_path == "warrior":
				return 0.85
		3:  # CUNNING - Tricksters do +25%, others do -15%
			if player_path == "trickster":
				return 1.25
			else:
				return 0.85
	return 1.0  # Neutral

func _get_player_class_path(character_class: String) -> String:
	"""Determine the combat path of a character class"""
	match character_class.to_lower():
		"fighter", "barbarian", "paladin":
			return "warrior"
		"wizard", "sorcerer", "sage":
			return "mage"
		"thief", "ranger", "ninja":
			return "trickster"
		_:
			return "warrior"

func check_player_hit(character, monster: Dictionary, combat_state: CombatState) -> bool:
	"""Check if player hits the monster
	Based on combat_manager.gd lines 768-809"""
	var abilities = monster.get("abilities", [])

	# Hit chance: 75% base + (player DEX - monster speed)
	var player_dex = character.get_effective_stat("dexterity")
	var monster_speed = monster.get("speed", 10)
	var dex_diff = player_dex - monster_speed
	var hit_chance = 75 + dex_diff

	# Blind debuff (-30% hit chance)
	if character.blind_active:
		hit_chance -= 30

	hit_chance = clamp(hit_chance, 30, 95)

	# Ethereal ability: 50% dodge chance
	if ABILITY_ETHEREAL in abilities:
		if randi() % 100 < 50:
			return false  # Ethereal dodge

	return (randi() % 100) < hit_chance

func calculate_monster_damage(monster: Dictionary, character, combat_state: CombatState) -> int:
	"""Calculate monster damage to player
	Based on combat_manager.gd lines 3681-3730"""
	var cfg = balance_config.get("combat", {})
	var passive = character.get_class_passive()
	var effects = passive.get("effects", {})

	var base_damage = monster.strength
	var damage_roll = (randi() % 6) + 1
	var raw_damage = base_damage + damage_roll

	# Equipment defense provides flat reduction
	var equipment_defense = character.get_equipment_defense()
	var equip_cap = cfg.get("equipment_defense_cap", 0.4)
	var equip_divisor = cfg.get("equipment_defense_divisor", 400)
	var equipment_reduction = 0.0
	if equip_cap > 0 and equip_divisor > 0:
		equipment_reduction = min(equip_cap, float(equipment_defense) / equip_divisor)
	raw_damage = int(raw_damage * (1.0 - equipment_reduction))

	# Player defense percentage reduction
	var player_defense = character.get_total_defense()

	# CLASS PASSIVE: Fighter Tactical Discipline (+15% defense)
	if effects.has("defense_bonus_percent"):
		var defense_bonus = int(player_defense * effects.get("defense_bonus_percent", 0))
		player_defense += defense_bonus

	var defense_constant = cfg.get("defense_formula_constant", 100)
	var defense_max = cfg.get("defense_max_reduction", 0.6)
	var defense_ratio = float(player_defense) / (float(player_defense) + defense_constant)
	var damage_reduction = defense_ratio * defense_max
	var total = int(raw_damage * (1.0 - damage_reduction))

	# Level difference bonus: higher level monsters deal more damage
	var level_diff = monster.level - character.level
	if level_diff > 0:
		var level_base = cfg.get("monster_level_diff_base", 1.035)
		var level_cap = cfg.get("monster_level_diff_cap", 100)
		var level_multiplier = pow(level_base, min(level_diff, level_cap))
		total = int(total * level_multiplier)

	# Minimum damage based on monster level
	var min_damage = max(1, monster.level / 5)
	return max(min_damage, total)

func check_monster_hit(monster: Dictionary, character, combat_state: CombatState) -> bool:
	"""Check if monster hits the player
	Based on combat_manager.gd lines 2977-3005"""
	var abilities = monster.get("abilities", [])

	# Monster hit chance: 85% base + level difference
	var level_diff = monster.level - character.level
	var hit_chance = 85 + level_diff

	# DEX provides dodge: -1% per 5 DEX (max -20%)
	var player_dex = character.get_effective_stat("dexterity")
	var dex_dodge = min(20, int(player_dex / 5))
	hit_chance -= dex_dodge

	# Equipment speed helps dodge
	hit_chance -= int(character.equipment_speed / 3)

	# Ethereal monsters are less precise
	if ABILITY_ETHEREAL in abilities:
		hit_chance -= 10

	hit_chance = clamp(hit_chance, 40, 95)

	return (randi() % 100) < hit_chance

func process_monster_turn(monster: Dictionary, character, combat_state: CombatState) -> Dictionary:
	"""Process a full monster turn including abilities and attacks
	Returns {damage_dealt: int, effects: Array, monster_healed: int}"""
	var abilities = monster.get("abilities", [])
	var ability_cfg = balance_config.get("monster_abilities", {})
	var results = {
		"damage_dealt": 0,
		"effects": [],
		"monster_healed": 0
	}

	combat_state.round += 1

	# Pre-attack abilities

	# Regeneration: heal 10% max HP
	if ABILITY_REGENERATION in abilities:
		var heal_amount = max(1, int(monster.max_hp * 0.10))
		monster.current_hp = min(monster.max_hp, monster.current_hp + heal_amount)
		results.monster_healed += heal_amount
		results.effects.append("regeneration")

	# Enrage: +10% damage per round
	if ABILITY_ENRAGE in abilities:
		combat_state.enrage_stacks += 1
		if combat_state.enrage_stacks > 1:
			results.effects.append("enrage_%d" % (combat_state.enrage_stacks * 10))

	# CLASS PASSIVE: Paladin Divine Favor - heal 3% per round
	var passive = character.get_class_passive()
	var effects = passive.get("effects", {})
	if effects.has("combat_regen_percent"):
		var regen_amount = max(1, int(character.max_hp * effects.get("combat_regen_percent", 0)))
		character.heal(regen_amount)

	# Process bleed damage
	if combat_state.player_bleed_stacks > 0:
		var bleed_dmg = combat_state.player_bleed_damage * combat_state.player_bleed_stacks
		character.current_hp -= bleed_dmg
		results.effects.append("bleed_%d" % bleed_dmg)

	# Determine number of attacks
	var num_attacks = 1
	if ABILITY_MULTI_STRIKE in abilities:
		num_attacks = randi_range(ability_cfg.get("multi_strike_min", 2), ability_cfg.get("multi_strike_max", 3))
		results.effects.append("multi_strike_%d" % num_attacks)

	var total_damage = 0
	var hits = 0

	for attack_num in range(num_attacks):
		if not check_monster_hit(monster, character, combat_state):
			continue  # Miss

		var damage = calculate_monster_damage(monster, character, combat_state)

		# Ambusher: first attack bonus damage
		if combat_state.ambusher_active and ABILITY_AMBUSHER in abilities:
			combat_state.ambusher_active = false
			if randi() % 100 < 75:  # 75% chance
				damage = int(damage * ability_cfg.get("ambusher_multiplier", 1.75))
				results.effects.append("ambush")

		# Berserker: +50% damage below 50% HP
		if ABILITY_BERSERKER in abilities:
			var hp_percent = float(monster.current_hp) / float(monster.max_hp)
			if hp_percent <= 0.5:
				damage = int(damage * 1.5)
				if attack_num == 0:
					results.effects.append("berserker")

		# Enrage stacks
		if combat_state.enrage_stacks > 0:
			damage = int(damage * (1.0 + combat_state.enrage_stacks * 0.10))

		# Unpredictable: wild variance
		if ABILITY_UNPREDICTABLE in abilities:
			var variance = randf_range(0.5, 2.5)
			damage = int(damage * variance)
			if variance > 1.8:
				results.effects.append("unpredictable_high")
			elif variance < 0.7:
				results.effects.append("unpredictable_low")

		total_damage += damage
		hits += 1

		# Life steal
		if ABILITY_LIFE_STEAL in abilities:
			var heal = int(damage * 0.5)
			monster.current_hp = min(monster.max_hp, monster.current_hp + heal)
			results.monster_healed += heal
			results.effects.append("life_steal")

	if hits > 0:
		# Thorns reflect
		if ABILITY_THORNS in abilities:
			var thorn_damage = max(1, int(total_damage * 0.25))
			character.current_hp -= thorn_damage
			total_damage += thorn_damage  # Add to total for tracking

		# Damage reflect
		if ABILITY_DAMAGE_REFLECT in abilities:
			var reflect_damage = max(1, int(total_damage * 0.25))
			character.current_hp -= reflect_damage

		character.current_hp -= total_damage
		results.damage_dealt = total_damage

	# Post-attack abilities (on hit)
	if hits > 0:
		# Poison (40% chance, WIS reduces)
		if ABILITY_POISON in abilities and not character.poison_active:
			var player_wis = character.get_effective_stat("wisdom")
			var wis_resist = min(0.50, float(player_wis) / 200.0)
			var poison_chance = int(40 * (1.0 - wis_resist))
			if randi() % 100 < poison_chance:
				var base_poison_dmg = max(1, int(monster.strength * 0.30))
				var poison_dmg = max(1, int(base_poison_dmg * (1.0 - wis_resist)))
				character.apply_poison(poison_dmg, 50)
				results.effects.append("poison_%d" % poison_dmg)

		# Mana/Stamina/Energy drain
		if ABILITY_MANA_DRAIN in abilities:
			var player_wis = character.get_effective_stat("wisdom")
			var wis_resist = min(0.50, float(player_wis) / 200.0)
			var drain = max(1, int((randi_range(5, 20) + monster.level / 10) * (1.0 - wis_resist)))
			match character.class_type:
				"Wizard", "Sage", "Sorcerer":
					character.current_mana = max(0, character.current_mana - drain)
				"Fighter", "Barbarian", "Paladin":
					character.current_stamina = max(0, character.current_stamina - drain)
				"Thief", "Ranger", "Ninja":
					character.current_energy = max(0, character.current_energy - drain)
			results.effects.append("mana_drain_%d" % drain)

		# Curse (30% chance, once per combat)
		if ABILITY_CURSE in abilities and not combat_state.curse_applied:
			var player_wis = character.get_effective_stat("wisdom")
			var wis_resist = min(0.50, float(player_wis) / 200.0)
			var curse_chance = int(30 * (1.0 - wis_resist))
			if randi() % 100 < curse_chance:
				combat_state.curse_applied = true
				var curse_penalty = int(-25 * (1.0 - wis_resist))
				character.add_buff("defense_penalty", curse_penalty, 999)
				results.effects.append("curse")

		# Disarm (25% chance, once per combat)
		if ABILITY_DISARM in abilities and not combat_state.disarm_applied:
			if randi() % 100 < 25:
				combat_state.disarm_applied = true
				character.add_buff("damage", -30, 3)
				results.effects.append("disarm")

		# Blind (40% chance)
		if ABILITY_BLIND in abilities and not character.blind_active:
			if randi() % 100 < 40:
				character.apply_blind(15)
				results.effects.append("blind")

		# Bleed (40% chance, stacks to 3)
		if ABILITY_BLEED in abilities:
			var bleed_chance = ability_cfg.get("bleed_chance", 40)
			if randi() % 100 < bleed_chance and combat_state.player_bleed_stacks < 3:
				combat_state.player_bleed_stacks += 1
				combat_state.player_bleed_damage = max(1, int(monster.strength * ability_cfg.get("bleed_damage_percent", 15) / 100.0))
				results.effects.append("bleed_stack")

		# Weakness (30% chance)
		if ABILITY_WEAKNESS in abilities and not character.has_debuff("weakness"):
			if randi() % 100 < ability_cfg.get("weakness_chance", 30):
				character.apply_debuff("weakness", 25, 20)
				results.effects.append("weakness")

		# Charm (25% chance, once per combat)
		if ABILITY_CHARM in abilities and not combat_state.player_charmed:
			if randi() % 100 < 25:
				combat_state.player_charmed = true
				results.effects.append("charm")

	# Coward flee check
	if ABILITY_COWARD in abilities:
		var hp_percent = float(monster.current_hp) / float(monster.max_hp)
		if hp_percent < 0.25 and randi() % 100 < 50:
			combat_state.monster_fled = true
			results.effects.append("coward_flee")

	# Flee attack
	if ABILITY_FLEE_ATTACK in abilities:
		var hp_percent = float(monster.current_hp) / float(monster.max_hp)
		if hp_percent < 0.5 and randi() % 100 < 30:
			combat_state.monster_fled = true
			results.effects.append("flee_attack")

	return results

func process_death_effects(monster: Dictionary, character) -> Dictionary:
	"""Process monster death effects (death curse, etc.)
	Returns {damage: int, effects: Array}"""
	var abilities = monster.get("abilities", [])
	var ability_cfg = balance_config.get("monster_abilities", {})
	var results = {"damage": 0, "effects": []}

	# Death curse: deal damage on death (WIS resists)
	if ABILITY_DEATH_CURSE in abilities:
		var player_wis = character.get_effective_stat("wisdom")
		var wis_resist = min(0.50, float(player_wis) / 200.0)
		var curse_damage = int(monster.max_hp * ability_cfg.get("death_curse_percent", 0.25) / 100.0)
		curse_damage = max(1, int(curse_damage * (1.0 - wis_resist)))
		character.current_hp -= curse_damage
		results.damage = curse_damage
		results.effects.append("death_curse")

	return results

func process_trickster_double_strike(character, damage_dealt: int, monster: Dictionary) -> int:
	"""Process trickster's 25% chance for bonus attack at 50% damage"""
	if character.is_trickster() and monster.current_hp > 0:
		if randi() % 100 < 25:
			var second_damage = int(damage_dealt * 0.5)
			monster.current_hp -= second_damage
			return second_damage
	return 0

# =============================================================================
# PLAYER ABILITY CALCULATIONS
# =============================================================================

# Ability level requirements
const MAGE_ABILITIES = {
	"magic_bolt": {"level": 1, "cost": 0},
	"forcefield": {"level": 10, "cost": 20},
	"haste": {"level": 30, "cost": 35},
	"blast": {"level": 40, "cost": 50},
	"paralyze": {"level": 50, "cost": 60},
	"meteor": {"level": 100, "cost": 100}
}

const TRICKSTER_ABILITIES = {
	"analyze": {"level": 1, "cost": 5},
	"distract": {"level": 10, "cost": 15},
	"sabotage": {"level": 30, "cost": 25},
	"ambush": {"level": 40, "cost": 30},
	"gambit": {"level": 50, "cost": 35},
	"vanish": {"level": 60, "cost": 40}
}

func calculate_magic_bolt_damage(character, monster: Dictionary, mana_to_spend: int) -> Dictionary:
	"""Calculate Magic Bolt damage (primary mage ability)
	Formula: mana × (1 + sqrt(INT)/5), reduced by monster WIS
	Returns {damage: int, mana_cost: int, backfire_damage: int}"""
	var passive = character.get_class_passive()
	var effects = passive.get("effects", {})

	# Clamp to available mana
	var mana_spent = mini(mana_to_spend, character.current_mana)
	if mana_spent <= 0:
		return {"damage": 0, "mana_cost": 0, "backfire_damage": 0}

	# Calculate actual mana cost (Sage gets -25% mana costs)
	var actual_mana_cost = mana_spent
	if effects.has("mana_cost_reduction"):
		actual_mana_cost = max(1, int(actual_mana_cost * (1.0 - effects.get("mana_cost_reduction", 0))))

	# INT scaling: 1 + sqrt(INT)/5
	# INT 25 = 2×, INT 100 = 3×, INT 225 = 4×
	var int_stat = character.get_effective_stat("intelligence")
	var int_multiplier = 1.0 + (sqrt(float(int_stat)) / 5.0)
	var base_damage = int(mana_spent * int_multiplier)

	# Apply damage buff
	var damage_buff = character.get_buff_value("damage")
	if damage_buff != 0:
		base_damage = int(base_damage * (1.0 + damage_buff / 100.0))

	# Wizard Arcane Precision: +15% spell damage
	if effects.has("spell_damage_bonus"):
		base_damage = int(base_damage * (1.0 + effects.get("spell_damage_bonus", 0)))

	# Sorcerer Chaos Magic: 25% double damage, 5% backfire
	var backfire_damage = 0
	if effects.has("double_damage_chance"):
		var chaos_roll = randf()
		if chaos_roll < effects.get("backfire_chance", 0.05):
			backfire_damage = int(base_damage * 0.5)
			base_damage = int(base_damage * 0.5)
		elif chaos_roll < effects.get("backfire_chance", 0.05) + effects.get("double_damage_chance", 0.25):
			base_damage = base_damage * 2

	# Wizard Spell Crit: +10% spell crit chance (1.5x damage)
	if effects.has("spell_crit_bonus"):
		var spell_crit_chance = int(effects.get("spell_crit_bonus", 0) * 100)
		if randi() % 100 < spell_crit_chance:
			base_damage = int(base_damage * 1.5)

	# Monster WIS reduces damage (up to 30% reduction)
	var monster_wis = monster.get("wisdom", monster.get("intelligence", 15))
	var wis_reduction = min(0.30, float(monster_wis) / 300.0)
	base_damage = max(1, int(base_damage * (1.0 - wis_reduction)))

	# Class affinity bonus
	var affinity = monster.get("class_affinity", 0)
	var class_multiplier = _get_class_advantage_multiplier(affinity, character.class_type)
	base_damage = int(base_damage * class_multiplier)

	return {
		"damage": max(1, base_damage),
		"mana_cost": actual_mana_cost,
		"backfire_damage": backfire_damage
	}

func calculate_power_strike_damage(character, monster: Dictionary) -> Dictionary:
	"""Calculate Power Strike damage (primary warrior ability)
	Formula: total_attack × 2.0 × (1 + sqrt(STR)/10)
	Returns {damage: int, stamina_cost: int}"""
	var cfg = balance_config.get("combat", {})
	var passive = character.get_class_passive()
	var effects = passive.get("effects", {})

	# Base stamina cost: 10
	var stamina_cost = 10

	# Fighter Tactical Discipline: -20% stamina costs
	if effects.has("stamina_cost_reduction"):
		stamina_cost = max(1, int(stamina_cost * (1.0 - effects.get("stamina_cost_reduction", 0))))

	# Barbarian Blood Rage: +25% stamina costs
	if effects.has("stamina_cost_increase"):
		stamina_cost = int(stamina_cost * (1.0 + effects.get("stamina_cost_increase", 0)))

	if character.current_stamina < stamina_cost:
		return {"damage": 0, "stamina_cost": stamina_cost}

	# Get total attack and damage buff
	var total_attack = character.get_total_attack()
	var damage_buff = character.get_buff_value("damage")
	var damage_multiplier = 1.0 + (damage_buff / 100.0)

	# STR scaling: 1 + sqrt(STR)/10
	var str_stat = character.get_effective_stat("strength")
	var str_mult = 1.0 + (sqrt(float(str_stat)) / 10.0)

	# Power Strike: 2× attack multiplier
	var base_damage = int(total_attack * 2.0 * damage_multiplier * str_mult)

	# Apply defense reduction from monster
	var defense_constant = cfg.get("defense_formula_constant", 100)
	var defense_max = cfg.get("defense_max_reduction", 0.6)
	var defense_ratio = float(monster.defense) / (float(monster.defense) + defense_constant)
	var damage_reduction = defense_ratio * defense_max
	var final_damage = int(base_damage * (1.0 - damage_reduction))

	# Class advantage multiplier
	var affinity = monster.get("class_affinity", 0)
	var class_multiplier = _get_class_advantage_multiplier(affinity, character.class_type)
	final_damage = int(final_damage * class_multiplier)

	# Level difference penalty
	var lvl_diff = monster.get("level", 1) - character.level
	if lvl_diff > 0:
		var lvl_penalty = min(0.25, lvl_diff * 0.015)
		final_damage = int(final_damage * (1.0 - lvl_penalty))

	return {
		"damage": max(1, final_damage),
		"stamina_cost": stamina_cost
	}

func calculate_outsmart_chance(character, monster: Dictionary) -> int:
	"""Calculate Outsmart success chance
	Success = instant win, Failure = free monster attack
	Returns: chance percentage (2-85)"""
	var player_wits = character.get_effective_stat("wits")
	var monster_intelligence = monster.get("intelligence", 15)
	var player_level = character.level
	var monster_level = monster.level

	# Base chance is low
	var base_chance = 5

	# Wits bonus: 15 × log2(WITS/10)
	var wits_bonus = 0
	if player_wits > 10:
		wits_bonus = int(15.0 * log(float(player_wits) / 10.0) / log(2.0))

	# Trickster class bonus (+15%)
	var is_trickster = character.is_trickster()
	var trickster_bonus = 15 if is_trickster else 0

	# Dumb monster bonus: +3% per INT below 10
	var dumb_bonus = max(0, (10 - monster_intelligence) * 3)

	# Smart monster penalty: -1% per INT above 10
	var smart_penalty = max(0, monster_intelligence - 10)

	# INT vs wits penalty: -2% per point monster INT exceeds player wits
	var int_vs_wits_penalty = max(0, (monster_intelligence - player_wits) * 2)

	# Level difference penalty
	var level_diff = monster_level - player_level
	var level_penalty = 0
	if level_diff > 0:
		if level_diff <= 10:
			level_penalty = level_diff * 2
		elif level_diff <= 50:
			level_penalty = 20 + (level_diff - 10)
		else:
			level_penalty = 60 + int((level_diff - 50) * 0.5)

	# Level bonus for weaker monsters
	var level_bonus = 0
	if level_diff < 0:
		level_bonus = min(15, abs(level_diff))

	var outsmart_chance = base_chance + wits_bonus + trickster_bonus + dumb_bonus + level_bonus - smart_penalty - int_vs_wits_penalty - level_penalty

	# INT-based cap
	var base_max_chance = 85 if is_trickster else 70
	var max_chance = max(30, base_max_chance - int(monster_intelligence / 2))
	outsmart_chance = clampi(outsmart_chance, 2, max_chance)

	return outsmart_chance

func apply_war_cry(character) -> bool:
	"""Apply War Cry buff (+35% damage for 4 rounds)
	Returns true if successfully applied"""
	var passive = character.get_class_passive()
	var effects = passive.get("effects", {})

	# Base stamina cost: 15
	var stamina_cost = 15

	# Fighter Tactical Discipline: -20% stamina costs
	if effects.has("stamina_cost_reduction"):
		stamina_cost = max(1, int(stamina_cost * (1.0 - effects.get("stamina_cost_reduction", 0))))

	# Barbarian Blood Rage: +25% stamina costs
	if effects.has("stamina_cost_increase"):
		stamina_cost = int(stamina_cost * (1.0 + effects.get("stamina_cost_increase", 0)))

	if character.current_stamina < stamina_cost:
		return false

	character.current_stamina -= stamina_cost
	character.add_buff("damage", 35, 4)
	return true

# =============================================================================
# ADDITIONAL MAGE ABILITIES
# =============================================================================

func calculate_blast_damage(character, monster: Dictionary) -> Dictionary:
	"""Calculate Blast damage (level 40 mage ability)
	Formula: 50 × (1 + INT × 0.03) × 2, plus burn DoT
	Returns {damage: int, mana_cost: int, burn_damage: int, backfire_damage: int}"""
	var passive = character.get_class_passive()
	var effects = passive.get("effects", {})

	# Base cost: 50 mana (or 5% of max, whichever is higher)
	var base_cost = 50
	var percent_cost = int(character.max_mana * 0.05)
	var mana_cost = max(base_cost, percent_cost)

	# Sage mana cost reduction
	if effects.has("mana_cost_reduction"):
		mana_cost = max(1, int(mana_cost * (1.0 - effects.get("mana_cost_reduction", 0))))

	if character.current_mana < mana_cost:
		return {"damage": 0, "mana_cost": mana_cost, "burn_damage": 0, "backfire_damage": 0}

	# INT scaling: 50 × (1 + INT × 0.03) × 2
	var int_stat = character.get_effective_stat("intelligence")
	var int_multiplier = 1.0 + (int_stat * 0.03)
	var base_damage = int(50 * int_multiplier * 2)

	# Apply damage buff
	var damage_buff = character.get_buff_value("damage")
	if damage_buff != 0:
		base_damage = int(base_damage * (1.0 + damage_buff / 100.0))

	# Wizard Arcane Precision: +15% spell damage
	if effects.has("spell_damage_bonus"):
		base_damage = int(base_damage * (1.0 + effects.get("spell_damage_bonus", 0)))

	# Sorcerer Chaos Magic
	var backfire_damage = 0
	if effects.has("double_damage_chance"):
		var chaos_roll = randf()
		if chaos_roll < effects.get("backfire_chance", 0.05):
			backfire_damage = int(base_damage * 0.5)
			base_damage = int(base_damage * 0.5)
		elif chaos_roll < effects.get("backfire_chance", 0.05) + effects.get("double_damage_chance", 0.25):
			base_damage = base_damage * 2

	# Wizard Spell Crit
	if effects.has("spell_crit_bonus"):
		var spell_crit_chance = int(effects.get("spell_crit_bonus", 0) * 100)
		if randi() % 100 < spell_crit_chance:
			base_damage = int(base_damage * 1.5)

	# Burn DoT: 20% of INT per round for 3 rounds
	var burn_damage = max(1, int(int_stat * 0.2))

	return {
		"damage": max(1, base_damage),
		"mana_cost": mana_cost,
		"burn_damage": burn_damage,
		"backfire_damage": backfire_damage
	}

func calculate_forcefield_shield(character) -> Dictionary:
	"""Calculate Forcefield shield value (level 10 mage ability)
	Returns {shield_value: int, mana_cost: int}"""
	var passive = character.get_class_passive()
	var effects = passive.get("effects", {})

	var mana_cost = 20
	if effects.has("mana_cost_reduction"):
		mana_cost = max(1, int(mana_cost * (1.0 - effects.get("mana_cost_reduction", 0))))

	if character.current_mana < mana_cost:
		return {"shield_value": 0, "mana_cost": mana_cost}

	# Shield = 100 + INT × 2
	var int_stat = character.get_effective_stat("intelligence")
	var shield_value = 100 + (int_stat * 2)

	return {"shield_value": shield_value, "mana_cost": mana_cost}

func calculate_meteor_damage(character, monster: Dictionary) -> Dictionary:
	"""Calculate Meteor damage (level 100 mage ability)
	Formula: 100 × (1 + INT × 0.03) × 3-4x random
	Returns {damage: int, mana_cost: int, backfire_damage: int}"""
	var passive = character.get_class_passive()
	var effects = passive.get("effects", {})

	# Base cost: 100 mana (or 12% of max)
	var base_cost = 100
	var percent_cost = int(character.max_mana * 0.12)
	var mana_cost = max(base_cost, percent_cost)

	if effects.has("mana_cost_reduction"):
		mana_cost = max(1, int(mana_cost * (1.0 - effects.get("mana_cost_reduction", 0))))

	if character.current_mana < mana_cost:
		return {"damage": 0, "mana_cost": mana_cost, "backfire_damage": 0}

	# INT scaling: 100 × (1 + INT × 0.03) × 3-4x
	var int_stat = character.get_effective_stat("intelligence")
	var int_multiplier = 1.0 + (int_stat * 0.03)
	var meteor_mult = 3.0 + randf()  # 3.0 to 4.0x
	var base_damage = int(100 * int_multiplier * meteor_mult)

	var damage_buff = character.get_buff_value("damage")
	if damage_buff != 0:
		base_damage = int(base_damage * (1.0 + damage_buff / 100.0))

	if effects.has("spell_damage_bonus"):
		base_damage = int(base_damage * (1.0 + effects.get("spell_damage_bonus", 0)))

	var backfire_damage = 0
	if effects.has("double_damage_chance"):
		var chaos_roll = randf()
		if chaos_roll < effects.get("backfire_chance", 0.05):
			backfire_damage = int(base_damage * 0.5)
			base_damage = int(base_damage * 0.5)
		elif chaos_roll < effects.get("backfire_chance", 0.05) + effects.get("double_damage_chance", 0.25):
			base_damage = base_damage * 2

	if effects.has("spell_crit_bonus"):
		var spell_crit_chance = int(effects.get("spell_crit_bonus", 0) * 100)
		if randi() % 100 < spell_crit_chance:
			base_damage = int(base_damage * 1.5)

	return {
		"damage": max(1, base_damage),
		"mana_cost": mana_cost,
		"backfire_damage": backfire_damage
	}

# =============================================================================
# TRICKSTER ABILITIES
# =============================================================================

func use_analyze(character) -> bool:
	"""Use Analyze ability - grants +10% damage buff, costs 5 energy
	Returns true if successful"""
	if character.current_energy < 5:
		return false
	character.current_energy -= 5
	character.add_buff("damage", 10, 999)  # Lasts rest of combat
	return true

func calculate_ambush_damage(character, monster: Dictionary) -> Dictionary:
	"""Calculate Ambush damage (level 40 trickster ability)
	Formula: total_attack × 3.0 × (1 + sqrt(WITS)/10), 50% crit chance
	Returns {damage: int, energy_cost: int, is_crit: bool}"""
	var energy_cost = 30

	if character.current_energy < energy_cost:
		return {"damage": 0, "energy_cost": energy_cost, "is_crit": false}

	var wits_stat = character.get_effective_stat("wits")
	var wits_mult = 1.0 + (sqrt(float(wits_stat)) / 10.0)
	var total_attack = character.get_total_attack()
	var damage_buff = character.get_buff_value("damage")
	var damage_multiplier = 1.0 + (damage_buff / 100.0)

	var base_damage = int(total_attack * 3.0 * damage_multiplier * wits_mult)

	# Apply defense reduction
	var cfg = balance_config.get("combat", {})
	var defense_constant = cfg.get("defense_formula_constant", 100)
	var defense_max = cfg.get("defense_max_reduction", 0.6)
	var defense_ratio = float(monster.defense) / (float(monster.defense) + defense_constant)
	var damage_reduction = defense_ratio * defense_max
	base_damage = int(base_damage * (1.0 - damage_reduction))

	# 50% crit chance
	var is_crit = randi() % 100 < 50
	if is_crit:
		base_damage = int(base_damage * 1.5)

	return {
		"damage": max(1, base_damage),
		"energy_cost": energy_cost,
		"is_crit": is_crit
	}

func calculate_gambit_damage(character, monster: Dictionary) -> Dictionary:
	"""Calculate Gambit damage (level 50 trickster ability)
	55%+ success for 4.5× damage, failure = 15% max HP self-damage
	Returns {damage: int, energy_cost: int, success: bool, self_damage: int}"""
	var energy_cost = 35

	if character.current_energy < energy_cost:
		return {"damage": 0, "energy_cost": energy_cost, "success": false, "self_damage": 0}

	var wits_stat = character.get_effective_stat("wits")
	var success_chance = 55 + int(wits_stat / 4)
	success_chance = min(80, success_chance)

	if randf() * 100 < success_chance:
		# Success - 4.5× damage
		var wits_mult = 1.0 + (sqrt(float(wits_stat)) / 10.0)
		var total_attack = character.get_total_attack()
		var damage_buff = character.get_buff_value("damage")
		var damage_multiplier = 1.0 + (damage_buff / 100.0)
		var base_damage = int(total_attack * 4.5 * damage_multiplier * wits_mult)

		# Apply defense reduction
		var cfg = balance_config.get("combat", {})
		var defense_constant = cfg.get("defense_formula_constant", 100)
		var defense_max = cfg.get("defense_max_reduction", 0.6)
		var defense_ratio = float(monster.defense) / (float(monster.defense) + defense_constant)
		var damage_reduction = defense_ratio * defense_max
		base_damage = int(base_damage * (1.0 - damage_reduction))

		return {
			"damage": max(1, base_damage),
			"energy_cost": energy_cost,
			"success": true,
			"self_damage": 0
		}
	else:
		# Failure - 15% max HP self damage
		var self_damage = max(5, int(character.max_hp * 0.15))
		return {
			"damage": 0,
			"energy_cost": energy_cost,
			"success": false,
			"self_damage": self_damage
		}

func apply_sabotage(character, monster: Dictionary) -> Dictionary:
	"""Apply Sabotage debuff to monster (level 30 trickster ability)
	Reduces monster STR/DEF by 15% + WITS/3
	Returns {debuff_percent: int, energy_cost: int, success: bool}"""
	var energy_cost = 25

	if character.current_energy < energy_cost:
		return {"debuff_percent": 0, "energy_cost": energy_cost, "success": false}

	var wits_stat = character.get_effective_stat("wits")
	var debuff_amount = 15 + int(wits_stat / 3)
	debuff_amount = min(50, debuff_amount)  # Cap at 50%

	return {
		"debuff_percent": debuff_amount,
		"energy_cost": energy_cost,
		"success": true
	}

func simulate_single_combat(character, monster: Dictionary) -> Dictionary:
	"""Simulate a single combat encounter with intelligent ability usage
	Returns {victory: bool, rounds: int, damage_taken: int, hp_remaining: int, death_effects: Array}"""
	character.reset_for_combat()
	monster.current_hp = monster.max_hp
	var combat_state = CombatState.new()

	var total_damage_taken = 0
	var max_rounds = 200  # Safety limit

	# Combat state tracking
	var outsmart_attempted = false
	var war_cry_used = false
	var analyze_used = false
	var forcefield_active = 0  # Shield HP remaining
	var sabotage_applied = false
	var monster_sabotage_debuff = 0  # % reduction to monster STR/DEF
	var burn_dot_damage = 0
	var burn_dot_rounds = 0

	while character.current_hp > 0 and monster.current_hp > 0 and combat_state.round < max_rounds:
		var player_dealt_damage = false
		var damage_to_monster = 0
		var skip_monster_turn = false

		# Apply burn DoT to monster at start of turn
		if burn_dot_rounds > 0:
			monster.current_hp -= burn_dot_damage
			burn_dot_rounds -= 1

		# Check if monster died from burn
		if monster.current_hp <= 0:
			var death_results = process_death_effects(monster, character)
			total_damage_taken += death_results.damage
			return {
				"victory": character.current_hp > 0,
				"rounds": combat_state.round + 1,
				"damage_taken": total_damage_taken,
				"hp_remaining": max(0, character.current_hp),
				"death_effects": death_results.effects
			}

		# =================================================================
		# INTELLIGENT ABILITY SELECTION BY CLASS PATH
		# =================================================================

		var class_path = _get_player_class_path(character.class_type)

		match class_path:
			"mage":
				# MAGE STRATEGY:
				# 1. Turn 1: Forcefield if available (level 10+) for protection
				# 2. Use Meteor (level 100) or Blast (level 40) if available
				# 3. Otherwise dump remaining mana into Magic Bolt
				var used_ability = false

				# Forcefield on first turn if available
				if combat_state.round == 0 and character.level >= 10 and forcefield_active == 0:
					var ff_result = calculate_forcefield_shield(character)
					if ff_result.shield_value > 0:
						character.current_mana -= ff_result.mana_cost
						forcefield_active = ff_result.shield_value
						used_ability = true
						skip_monster_turn = randi() % 100 >= 25  # Buff ability - 75% chance monster attacks

				# Try Meteor if level 100+
				if not used_ability and character.level >= 100 and character.current_mana >= 100:
					var meteor_result = calculate_meteor_damage(character, monster)
					if meteor_result.damage > 0:
						character.current_mana -= meteor_result.mana_cost
						monster.current_hp -= meteor_result.damage
						damage_to_monster = meteor_result.damage
						player_dealt_damage = true
						used_ability = true
						if meteor_result.backfire_damage > 0:
							character.current_hp -= meteor_result.backfire_damage
							total_damage_taken += meteor_result.backfire_damage

				# Try Blast if level 40+ and have enough mana
				if not used_ability and character.level >= 40 and character.current_mana >= 50:
					var blast_result = calculate_blast_damage(character, monster)
					if blast_result.damage > 0:
						character.current_mana -= blast_result.mana_cost
						monster.current_hp -= blast_result.damage
						damage_to_monster = blast_result.damage
						player_dealt_damage = true
						used_ability = true
						burn_dot_damage = blast_result.burn_damage
						burn_dot_rounds = 3
						if blast_result.backfire_damage > 0:
							character.current_hp -= blast_result.backfire_damage
							total_damage_taken += blast_result.backfire_damage

				# Magic Bolt with remaining mana
				if not used_ability and character.current_mana > 0:
					var bolt_result = calculate_magic_bolt_damage(character, monster, character.current_mana)
					if bolt_result.damage > 0:
						character.current_mana -= bolt_result.mana_cost
						monster.current_hp -= bolt_result.damage
						damage_to_monster = bolt_result.damage
						player_dealt_damage = true
						used_ability = true
						if bolt_result.backfire_damage > 0:
							character.current_hp -= bolt_result.backfire_damage
							total_damage_taken += bolt_result.backfire_damage

				# Fall back to basic attack if out of mana
				if not used_ability:
					if check_player_hit(character, monster, combat_state):
						var damage_result = calculate_player_damage(character, monster, combat_state)
						monster.current_hp -= damage_result.damage
						damage_to_monster = damage_result.damage
						player_dealt_damage = true
						if damage_result.backfire_damage > 0:
							character.current_hp -= damage_result.backfire_damage
							total_damage_taken += damage_result.backfire_damage

			"trickster":
				# TRICKSTER STRATEGY:
				# 1. Turn 1: Analyze for +10% damage buff (skips monster turn!)
				# 2. Turn 2: Outsmart if reasonable chance (>25%)
				# 3. If Outsmart fails: Use Ambush (40+) or Gambit (50+)
				# 4. Sabotage tough monsters before big attacks
				# 5. Fall back to basic attacks
				var used_ability = false

				# Turn 1: Analyze for damage buff (FREE action - skips monster turn)
				if not analyze_used and character.current_energy >= 5:
					if use_analyze(character):
						analyze_used = true
						used_ability = true
						skip_monster_turn = true  # Analyze skips monster turn
						character.tick_status_effects()
						continue  # Next turn

				# Turn 2: Try Outsmart
				if not outsmart_attempted:
					outsmart_attempted = true
					var outsmart_chance = calculate_outsmart_chance(character, monster)

					# Only attempt if reasonable chance (>25%)
					if outsmart_chance >= 25:
						if randi() % 100 < outsmart_chance:
							# OUTSMART SUCCESS - Instant victory!
							return {
								"victory": true,
								"rounds": combat_state.round + 1,
								"damage_taken": total_damage_taken,
								"hp_remaining": character.current_hp,
								"death_effects": ["outsmart_success"]
							}
						else:
							# OUTSMART FAILED - Monster gets free attack
							var monster_result = process_monster_turn(monster, character, combat_state)
							total_damage_taken += monster_result.damage_dealt

							if character.current_hp <= 0:
								return {
									"victory": false,
									"rounds": combat_state.round + 1,
									"damage_taken": total_damage_taken,
									"hp_remaining": 0,
									"death_effects": ["outsmart_failed"]
								}
							character.tick_status_effects()
							continue

				# Sabotage tough monsters (if not already done and level 30+)
				if not sabotage_applied and character.level >= 30 and character.current_energy >= 25:
					# Sabotage if monster is higher level or has high stats
					if monster.level >= character.level or monster.strength > character.get_total_attack():
						var sab_result = apply_sabotage(character, monster)
						if sab_result.success:
							character.current_energy -= sab_result.energy_cost
							sabotage_applied = true
							monster_sabotage_debuff = sab_result.debuff_percent
							# Reduce monster stats (temporary for this combat)
							monster.strength = int(monster.strength * (1.0 - monster_sabotage_debuff / 100.0))
							monster.defense = int(monster.defense * (1.0 - monster_sabotage_debuff / 100.0))
							used_ability = true
							skip_monster_turn = randi() % 100 >= 25  # Buff ability

				# Use Gambit if level 50+ and have energy (high risk high reward)
				if not used_ability and character.level >= 50 and character.current_energy >= 35:
					var gambit_result = calculate_gambit_damage(character, monster)
					character.current_energy -= gambit_result.energy_cost
					if gambit_result.success:
						monster.current_hp -= gambit_result.damage
						damage_to_monster = gambit_result.damage
						player_dealt_damage = true
					else:
						character.current_hp -= gambit_result.self_damage
						total_damage_taken += gambit_result.self_damage
					used_ability = true

				# Use Ambush if level 40+ and have energy
				if not used_ability and character.level >= 40 and character.current_energy >= 30:
					var ambush_result = calculate_ambush_damage(character, monster)
					if ambush_result.damage > 0:
						character.current_energy -= ambush_result.energy_cost
						monster.current_hp -= ambush_result.damage
						damage_to_monster = ambush_result.damage
						player_dealt_damage = true
						used_ability = true

				# Fall back to basic attack
				if not used_ability:
					if check_player_hit(character, monster, combat_state):
						var damage_result = calculate_player_damage(character, monster, combat_state)
						monster.current_hp -= damage_result.damage
						damage_to_monster = damage_result.damage
						player_dealt_damage = true

						# Trickster double strike
						var bonus = process_trickster_double_strike(character, damage_result.damage, monster)
						damage_to_monster += bonus

			"warrior":
				# WARRIOR STRATEGY: War Cry first (if not used), then Power Strike
				if not war_cry_used and character.current_stamina >= 15:
					# First turn: War Cry for +35% damage buff
					if apply_war_cry(character):
						war_cry_used = true
						# War Cry is a buff ability - 25% chance monster doesn't attack
						if randi() % 100 >= 25:
							var monster_result = process_monster_turn(monster, character, combat_state)
							total_damage_taken += monster_result.damage_dealt
						character.tick_status_effects()
						continue
				elif character.current_stamina >= 10:
					# Use Power Strike
					var strike_result = calculate_power_strike_damage(character, monster)
					if strike_result.damage > 0:
						character.current_stamina -= strike_result.stamina_cost
						monster.current_hp -= strike_result.damage
						damage_to_monster = strike_result.damage
						player_dealt_damage = true
				else:
					# Out of stamina - basic attack
					if check_player_hit(character, monster, combat_state):
						var damage_result = calculate_player_damage(character, monster, combat_state)
						monster.current_hp -= damage_result.damage
						damage_to_monster = damage_result.damage
						player_dealt_damage = true

						if damage_result.backfire_damage > 0:
							character.current_hp -= damage_result.backfire_damage
							total_damage_taken += damage_result.backfire_damage

		# =================================================================
		# PROCESS THORNS/REFLECT IF PLAYER DEALT DAMAGE
		# =================================================================
		if player_dealt_damage and damage_to_monster > 0:
			var abilities = monster.get("abilities", [])
			if ABILITY_THORNS in abilities and monster.current_hp > 0:
				var thorn_damage = max(1, int(damage_to_monster * 0.25))
				character.current_hp -= thorn_damage
				total_damage_taken += thorn_damage

			if ABILITY_DAMAGE_REFLECT in abilities and monster.current_hp > 0:
				var reflect_damage = max(1, int(damage_to_monster * 0.25))
				character.current_hp -= reflect_damage
				total_damage_taken += reflect_damage

		# Check victory
		if monster.current_hp <= 0:
			var death_results = process_death_effects(monster, character)
			total_damage_taken += death_results.damage

			return {
				"victory": character.current_hp > 0,
				"rounds": combat_state.round + 1,
				"damage_taken": total_damage_taken,
				"hp_remaining": max(0, character.current_hp),
				"death_effects": death_results.effects
			}

		# Monster turn (unless skipped)
		if not skip_monster_turn:
			var monster_result = process_monster_turn(monster, character, combat_state)
			var monster_damage = monster_result.damage_dealt

			# Forcefield absorbs damage
			if forcefield_active > 0 and monster_damage > 0:
				if monster_damage <= forcefield_active:
					forcefield_active -= monster_damage
					monster_damage = 0
				else:
					monster_damage -= forcefield_active
					forcefield_active = 0
				# Re-apply reduced damage to character
				character.current_hp += monster_result.damage_dealt  # Undo the damage from process_monster_turn
				character.current_hp -= monster_damage  # Apply reduced damage

			total_damage_taken += monster_damage

			# Check monster fled
			if combat_state.monster_fled:
				return {
					"victory": false,
					"rounds": combat_state.round,
					"damage_taken": total_damage_taken,
					"hp_remaining": character.current_hp,
					"death_effects": ["monster_fled"]
				}

		# Tick status effects
		character.tick_status_effects()

	# Determine outcome
	var victory = monster.current_hp <= 0 and character.current_hp > 0

	# Process death effects if victory
	var death_effects = []
	if victory:
		var death_results = process_death_effects(monster, character)
		total_damage_taken += death_results.damage
		death_effects = death_results.effects
		victory = character.current_hp > 0

	return {
		"victory": victory,
		"rounds": combat_state.round,
		"damage_taken": total_damage_taken,
		"hp_remaining": max(0, character.current_hp),
		"death_effects": death_effects
	}
