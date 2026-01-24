# character.gd
# Simple Character class - extends Resource so it can be easily serialized
class_name Character
extends Resource

# Basic Info
@export var character_id: int = 0
@export var name: String = ""
@export var class_type: String = ""
@export var level: int = 1
@export var experience: int = 0
@export var experience_to_next_level: int = 100

# Primary Stats
@export var strength: int = 10
@export var constitution: int = 10
@export var dexterity: int = 10
@export var intelligence: int = 10
@export var wisdom: int = 10
@export var charisma: int = 10

# Current State
@export var current_hp: int = 100
@export var max_hp: int = 100
@export var current_mana: int = 50
@export var max_mana: int = 50

# Location & Status (Phantasia 4 style coordinates)
@export var x: int = 0  # X coordinate
@export var y: int = 10  # Y coordinate (start at Sanctuary)
@export var gold: int = 100
@export var gems: int = 0  # Premium currency from high-level monsters

# Combat
@export var in_combat: bool = false

# Inventory System (stubs for future item drops)
@export var inventory: Array = []  # Array of item dictionaries
@export var equipped: Dictionary = {
	"weapon": null,
	"armor": null,
	"helm": null,
	"shield": null,
	"ring": null,
	"amulet": null
}
const MAX_INVENTORY_SIZE = 20

# Tracking / Persistence
@export var created_at: int = 0
@export var played_time_seconds: int = 0
@export var monsters_killed: int = 0

# Active combat buffs - array of {type: String, value: int, duration: int}
@export var active_buffs: Array = []

func _init():
	# Constructor
	pass

func initialize(char_name: String, char_class: String):
	"""Initialize a new character with starting values"""
	name = char_name
	class_type = char_class
	level = 1
	experience = 0

	# Set starting stats based on class
	var starting_stats = get_starting_stats_for_class(char_class)
	strength = starting_stats.strength
	constitution = starting_stats.constitution
	dexterity = starting_stats.dexterity
	intelligence = starting_stats.intelligence
	wisdom = starting_stats.wisdom
	charisma = starting_stats.charisma

	# Calculate derived stats
	calculate_derived_stats()

	# Start with full health and mana
	current_hp = max_hp
	current_mana = max_mana

	# Starting location - Sanctuary (0, 10) like Phantasia 4
	x = 0
	y = 10
	gold = 100

	# Tracking fields
	created_at = int(Time.get_unix_time_from_system())
	played_time_seconds = 0
	monsters_killed = 0

func get_starting_stats_for_class(char_class: String) -> Dictionary:
	"""Get starting stats based on character class"""
	var stats = {
		"Fighter": {"strength": 14, "constitution": 13, "dexterity": 11, "intelligence": 8, "wisdom": 8, "charisma": 10},
		"Barbarian": {"strength": 16, "constitution": 14, "dexterity": 10, "intelligence": 6, "wisdom": 8, "charisma": 8},
		"Paladin": {"strength": 13, "constitution": 14, "dexterity": 10, "intelligence": 9, "wisdom": 12, "charisma": 12},
		"Wizard": {"strength": 8, "constitution": 10, "dexterity": 11, "intelligence": 16, "wisdom": 13, "charisma": 10},
		"Sorcerer": {"strength": 8, "constitution": 9, "dexterity": 10, "intelligence": 17, "wisdom": 11, "charisma": 11},
		"Sage": {"strength": 8, "constitution": 11, "dexterity": 10, "intelligence": 12, "wisdom": 16, "charisma": 12},
		"Thief": {"strength": 10, "constitution": 10, "dexterity": 17, "intelligence": 11, "wisdom": 10, "charisma": 10},
		"Ranger": {"strength": 12, "constitution": 12, "dexterity": 15, "intelligence": 10, "wisdom": 12, "charisma": 10},
		"Ninja": {"strength": 11, "constitution": 10, "dexterity": 17, "intelligence": 12, "wisdom": 11, "charisma": 10}
	}
	
	return stats.get(char_class, stats["Fighter"])

func calculate_derived_stats():
	"""Calculate HP, mana, etc. from primary stats"""
	max_hp = (constitution * 10) + (level * 5)
	max_mana = (intelligence * 8) + (wisdom * 4)

func get_health_state() -> String:
	"""Get current health state description"""
	var percent = (float(current_hp) / float(max_hp)) * 100.0
	if percent >= 70:
		return "Healthy"
	elif percent >= 30:
		return "Wounded"
	elif percent >= 10:
		return "Bloodied"
	else:
		return "Critical"

func get_stat(stat_name: String) -> int:
	"""Get a stat value by name"""
	match stat_name.to_lower():
		"strength", "str":
			return strength
		"constitution", "con":
			return constitution
		"dexterity", "dex":
			return dexterity
		"intelligence", "int":
			return intelligence
		"wisdom", "wis":
			return wisdom
		"charisma", "cha":
			return charisma
		_:
			return 0

func get_equipment_bonuses() -> Dictionary:
	"""Calculate total bonuses from all equipped items"""
	var bonuses = {
		"attack": 0,
		"defense": 0,
		"strength": 0,
		"constitution": 0,
		"dexterity": 0,
		"intelligence": 0,
		"wisdom": 0,
		"charisma": 0,
		"max_hp": 0,
		"max_mana": 0
	}

	for slot in equipped.keys():
		var item = equipped[slot]
		if item == null or not item is Dictionary:
			continue

		var item_level = item.get("level", 1)
		var item_type = item.get("type", "")
		var rarity_mult = _get_rarity_multiplier(item.get("rarity", "common"))

		# Base bonus scales with item level and rarity
		var base_bonus = int(item_level * rarity_mult)

		# Apply bonuses based on item type
		if "weapon" in item_type:
			bonuses.attack += base_bonus * 2  # Weapons give attack
			bonuses.strength += int(base_bonus * 0.3)
		elif "armor" in item_type:
			bonuses.defense += base_bonus * 2  # Armor gives defense
			bonuses.constitution += int(base_bonus * 0.3)
			bonuses.max_hp += base_bonus * 3
		elif "helm" in item_type:
			bonuses.defense += base_bonus
			bonuses.wisdom += int(base_bonus * 0.2)
		elif "shield" in item_type:
			bonuses.defense += int(base_bonus * 1.5)
			bonuses.constitution += int(base_bonus * 0.2)
		elif "ring" in item_type:
			bonuses.attack += int(base_bonus * 0.5)
			bonuses.dexterity += int(base_bonus * 0.3)
			bonuses.intelligence += int(base_bonus * 0.2)
		elif "amulet" in item_type:
			bonuses.max_mana += base_bonus * 2
			bonuses.wisdom += int(base_bonus * 0.3)
			bonuses.charisma += int(base_bonus * 0.2)

		# Apply affix bonuses
		var affixes = item.get("affixes", {})
		if affixes.has("hp_bonus"):
			bonuses.max_hp += affixes.hp_bonus
		if affixes.has("attack_bonus"):
			bonuses.attack += affixes.attack_bonus
		if affixes.has("defense_bonus"):
			bonuses.defense += affixes.defense_bonus
		if affixes.has("dex_bonus"):
			bonuses.dexterity += affixes.dex_bonus
		if affixes.has("wis_bonus"):
			bonuses.wisdom += affixes.wis_bonus

	return bonuses

func _get_rarity_multiplier(rarity: String) -> float:
	"""Get multiplier for item rarity"""
	match rarity:
		"common": return 1.0
		"uncommon": return 1.5
		"rare": return 2.0
		"epic": return 3.0
		"legendary": return 4.5
		"artifact": return 6.0
		_: return 1.0

func get_total_attack() -> int:
	"""Get total attack power including equipment"""
	var bonuses = get_equipment_bonuses()
	return strength + bonuses.strength + bonuses.attack

func get_total_defense() -> int:
	"""Get total defense including equipment"""
	var bonuses = get_equipment_bonuses()
	return (constitution / 2) + bonuses.defense

func get_effective_stat(stat_name: String) -> int:
	"""Get stat value including equipment bonuses"""
	var base_stat = get_stat(stat_name)
	var bonuses = get_equipment_bonuses()

	match stat_name.to_lower():
		"strength", "str":
			return base_stat + bonuses.strength
		"constitution", "con":
			return base_stat + bonuses.constitution
		"dexterity", "dex":
			return base_stat + bonuses.dexterity
		"intelligence", "int":
			return base_stat + bonuses.intelligence
		"wisdom", "wis":
			return base_stat + bonuses.wisdom
		"charisma", "cha":
			return base_stat + bonuses.charisma
		_:
			return base_stat

func get_attack_damage() -> Dictionary:
	"""Calculate attack damage range including equipment"""
	var bonuses = get_equipment_bonuses()
	var total_str = strength + bonuses.strength
	var base_damage = total_str + bonuses.attack
	var min_damage = int(base_damage * 0.8)
	var max_damage = int(base_damage * 1.2)

	return {
		"min": min_damage,
		"max": max_damage,
		"base": base_damage,
		"from_equipment": bonuses.attack
	}

func take_damage(damage: int) -> Dictionary:
	"""Apply damage and return result"""
	current_hp -= damage
	
	var result = {
		"damage": damage,
		"current_hp": current_hp,
		"max_hp": max_hp,
		"health_state": get_health_state(),
		"died": false
	}
	
	if current_hp <= 0:
		current_hp = 0
		result.died = true
	
	return result

func heal(amount: int) -> int:
	"""Heal the character, return actual amount healed"""
	var old_hp = current_hp
	current_hp = min(current_hp + amount, max_hp)
	return current_hp - old_hp

func check_level_up():
	"""Check if character should level up"""
	var exp_table = {
		2: 100, 3: 250, 4: 500, 5: 1000,
		10: 10000, 20: 50000, 50: 500000
	}
	var required_exp = exp_table.get(level + 1, int(pow(level + 1, 2.5) * 100))
	
	if experience >= required_exp:
		level_up()

func level_up():
	"""Increase level and stats"""
	level += 1
	
	# Get stat gains for class
	var gains = get_stat_gains_for_class()
	
	strength += gains.strength
	constitution += gains.constitution
	dexterity += gains.dexterity
	intelligence += gains.intelligence
	wisdom += gains.wisdom
	charisma += gains.charisma
	
	# Recalculate derived stats
	calculate_derived_stats()
	
	# Full heal on level up
	current_hp = max_hp
	current_mana = max_mana

func get_stat_gains_for_class() -> Dictionary:
	"""Get stat increases per level based on class"""
	var gains = {
		"Fighter": {"strength": 3, "constitution": 2, "dexterity": 1, "intelligence": 0, "wisdom": 0, "charisma": 1},
		"Barbarian": {"strength": 4, "constitution": 2, "dexterity": 1, "intelligence": 0, "wisdom": 0, "charisma": 0},
		"Paladin": {"strength": 2, "constitution": 3, "dexterity": 1, "intelligence": 1, "wisdom": 2, "charisma": 2},
		"Wizard": {"strength": 0, "constitution": 1, "dexterity": 1, "intelligence": 4, "wisdom": 2, "charisma": 1},
		"Sorcerer": {"strength": 0, "constitution": 1, "dexterity": 1, "intelligence": 5, "wisdom": 1, "charisma": 1},
		"Sage": {"strength": 0, "constitution": 2, "dexterity": 1, "intelligence": 2, "wisdom": 4, "charisma": 2},
		"Thief": {"strength": 1, "constitution": 1, "dexterity": 5, "intelligence": 1, "wisdom": 1, "charisma": 1},
		"Ranger": {"strength": 2, "constitution": 2, "dexterity": 4, "intelligence": 1, "wisdom": 2, "charisma": 1},
		"Ninja": {"strength": 2, "constitution": 1, "dexterity": 5, "intelligence": 2, "wisdom": 1, "charisma": 1}
	}
	
	return gains.get(class_type, gains["Fighter"])

func to_dict() -> Dictionary:
	"""Convert character to dictionary for network transmission"""
	return {
		"id": character_id,
		"name": name,
		"class": class_type,
		"level": level,
		"experience": experience,
		"experience_to_next_level": experience_to_next_level,
		"stats": {
			"strength": strength,
			"constitution": constitution,
			"dexterity": dexterity,
			"intelligence": intelligence,
			"wisdom": wisdom,
			"charisma": charisma
		},
		"current_hp": current_hp,
		"max_hp": max_hp,
		"current_mana": current_mana,
		"max_mana": max_mana,
		"x": x,
		"y": y,
		"health_state": get_health_state(),
		"gold": gold,
		"gems": gems,
		"in_combat": in_combat,
		"inventory": inventory,
		"equipped": equipped,
		"created_at": created_at,
		"played_time_seconds": played_time_seconds,
		"monsters_killed": monsters_killed,
		"active_buffs": active_buffs
	}

func from_dict(data: Dictionary):
	"""Load character from dictionary"""
	character_id = data.get("id", 0)
	name = data.get("name", "")
	class_type = data.get("class", "Fighter")
	level = data.get("level", 1)
	experience = data.get("experience", 0)

	var stats = data.get("stats", {})
	strength = stats.get("strength", 10)
	constitution = stats.get("constitution", 10)
	dexterity = stats.get("dexterity", 10)
	intelligence = stats.get("intelligence", 10)
	wisdom = stats.get("wisdom", 10)
	charisma = stats.get("charisma", 10)

	current_hp = data.get("current_hp", 100)
	max_hp = data.get("max_hp", 100)
	current_mana = data.get("current_mana", 50)
	max_mana = data.get("max_mana", 50)

	x = data.get("x", 0)
	y = data.get("y", 10)
	gold = data.get("gold", 100)
	gems = data.get("gems", 0)
	in_combat = data.get("in_combat", false)
	experience_to_next_level = data.get("experience_to_next_level", 100)

	# Inventory system
	inventory = data.get("inventory", [])
	var loaded_equipped = data.get("equipped", {})
	for slot in equipped.keys():
		equipped[slot] = loaded_equipped.get(slot, null)

	# Tracking fields
	created_at = data.get("created_at", 0)
	played_time_seconds = data.get("played_time_seconds", 0)
	monsters_killed = data.get("monsters_killed", 0)

	# Active buffs (clear on load - buffs don't persist between sessions)
	active_buffs = []

func add_experience(amount: int) -> Dictionary:
	"""Add experience and check for level up"""
	experience += amount
	var leveled_up = false
	var levels_gained = 0
	
	# Check for level ups (can gain multiple levels)
	while experience >= experience_to_next_level:
		experience -= experience_to_next_level
		level += 1
		levels_gained += 1
		leveled_up = true
		
		# Increase stats on level up
		strength += 1
		constitution += 1
		dexterity += 1
		intelligence += 1
		wisdom += 1
		charisma += 1
		
		# Increase HP and Mana
		max_hp += 10 + (constitution / 2)
		max_mana += 5 + (intelligence / 2)
		
		# Fully heal on level up
		current_hp = max_hp
		current_mana = max_mana
		
		# Calculate next level requirement (increases by 50% each level)
		experience_to_next_level = int(experience_to_next_level * 1.5)
	
	return {
		"leveled_up": leveled_up,
		"levels_gained": levels_gained,
		"new_level": level
	}

func get_experience_progress() -> int:
	"""Get experience progress as percentage"""
	if experience_to_next_level <= 0:
		return 100
	return int((float(experience) / experience_to_next_level) * 100)

# Inventory System Stubs

func can_add_item() -> bool:
	"""Check if inventory has space for another item"""
	return inventory.size() < MAX_INVENTORY_SIZE

func add_item(item: Dictionary) -> bool:
	"""Add an item to inventory. Returns true if successful."""
	if not can_add_item():
		return false
	inventory.append(item)
	return true

func remove_item(index: int) -> Dictionary:
	"""Remove and return item at index. Returns empty dict if invalid."""
	if index < 0 or index >= inventory.size():
		return {}
	return inventory.pop_at(index)

func get_inventory_count() -> int:
	"""Get current number of items in inventory"""
	return inventory.size()

func equip_item(item: Dictionary, slot: String) -> Dictionary:
	"""Equip an item to a slot. Returns previously equipped item or empty dict."""
	if not equipped.has(slot):
		return {}
	var old_item = equipped[slot]
	equipped[slot] = item
	if old_item != null:
		return old_item
	return {}

func unequip_slot(slot: String) -> Dictionary:
	"""Unequip item from slot. Returns the item or empty dict."""
	if not equipped.has(slot) or equipped[slot] == null:
		return {}
	var item = equipped[slot]
	equipped[slot] = null
	return item

# ===== BUFF SYSTEM =====

func add_buff(buff_type: String, value: int, duration: int):
	"""Add or refresh a buff. If buff already exists, refreshes duration and uses higher value."""
	for buff in active_buffs:
		if buff.type == buff_type:
			buff.value = max(buff.value, value)
			buff.duration = max(buff.duration, duration)
			return
	active_buffs.append({"type": buff_type, "value": value, "duration": duration})

func get_buff_value(buff_type: String) -> int:
	"""Get the current value of a buff type. Returns 0 if not active."""
	for buff in active_buffs:
		if buff.type == buff_type:
			return buff.value
	return 0

func tick_buffs():
	"""Decrement buff durations by 1. Call at end of each combat round."""
	var expired = []
	for i in range(active_buffs.size()):
		active_buffs[i].duration -= 1
		if active_buffs[i].duration <= 0:
			expired.append(i)
	# Remove expired buffs (reverse order to preserve indices)
	for i in range(expired.size() - 1, -1, -1):
		active_buffs.remove_at(expired[i])

func clear_buffs():
	"""Clear all active buffs. Call when combat ends."""
	active_buffs.clear()

func get_active_buff_names() -> Array:
	"""Get list of active buff type names for display."""
	var names = []
	for buff in active_buffs:
		names.append(buff.type)
	return names
