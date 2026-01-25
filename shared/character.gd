# character.gd
# Simple Character class - extends Resource so it can be easily serialized
class_name Character
extends Resource

# Basic Info
@export var character_id: int = 0
@export var name: String = ""
@export var race: String = "Human"  # Human, Elf, Dwarf, or Ogre
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
@export var wits: int = 10  # Renamed from charisma - used for outsmarting enemies

# Current State
@export var current_hp: int = 100
@export var max_hp: int = 100
@export var current_mana: int = 50
@export var max_mana: int = 50
@export var current_stamina: int = 80  # Warrior resource
@export var max_stamina: int = 80      # STR*4 + CON*4
@export var current_energy: int = 80   # Trickster resource
@export var max_energy: int = 80       # WITS*4 + DEX*4

# Location & Status (Phantasia 4 style coordinates)
@export var x: int = 0  # X coordinate
@export var y: int = 10  # Y coordinate (start at Sanctuary)
@export var gold: int = 100
@export var gems: int = 0  # Premium currency from high-level monsters

# Combat
@export var in_combat: bool = false
@export var last_stand_used: bool = false  # Dwarf racial - resets each combat

# Poison status (persists outside combat)
@export var poison_active: bool = false
@export var poison_damage: int = 0
@export var poison_turns_remaining: int = 0  # Decrements each combat turn

# Inventory System (stubs for future item drops)
@export var inventory: Array = []  # Array of item dictionaries
@export var equipped: Dictionary = {
	"weapon": null,
	"armor": null,
	"helm": null,
	"shield": null,
	"boots": null,
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

# Persistent buffs that last multiple battles - array of {type: String, value: int, battles_remaining: int}
@export var persistent_buffs: Array = []

# Quest System
# active_quests: Array of {quest_id: String, progress: int, target: int, started_at: int, origin_x: int, origin_y: int, accumulated_intensity: float, kills_in_hotzone: int}
@export var active_quests: Array = []
# completed_quests: Array of quest IDs that have been turned in
@export var completed_quests: Array = []
# daily_quest_cooldowns: {quest_id: unix_timestamp} - when daily quests can be accepted again
@export var daily_quest_cooldowns: Dictionary = {}
const MAX_ACTIVE_QUESTS = 5

func _init():
	# Constructor
	pass

func initialize(char_name: String, char_class: String, char_race: String = "Human"):
	"""Initialize a new character with starting values"""
	name = char_name
	race = char_race
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
	wits = starting_stats.wits

	# Calculate derived stats
	calculate_derived_stats()

	# Start with full resources
	current_hp = max_hp
	current_mana = max_mana
	current_stamina = max_stamina
	current_energy = max_energy

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
		# Warrior Path (STR > 10 for Stamina abilities)
		"Fighter": {"strength": 14, "constitution": 13, "dexterity": 11, "intelligence": 8, "wisdom": 8, "wits": 10},
		"Barbarian": {"strength": 17, "constitution": 12, "dexterity": 10, "intelligence": 7, "wisdom": 8, "wits": 10},
		# Mage Path (INT > 10 for Mana abilities)
		"Wizard": {"strength": 8, "constitution": 10, "dexterity": 10, "intelligence": 17, "wisdom": 12, "wits": 9},
		"Sage": {"strength": 8, "constitution": 12, "dexterity": 10, "intelligence": 13, "wisdom": 15, "wits": 9},
		# Trickster Path (WITS > 10 for Energy abilities)
		"Thief": {"strength": 9, "constitution": 9, "dexterity": 14, "intelligence": 9, "wisdom": 9, "wits": 16},
		"Ranger": {"strength": 12, "constitution": 11, "dexterity": 12, "intelligence": 9, "wisdom": 9, "wits": 14},
		# Legacy classes (for existing characters)
		"Paladin": {"strength": 13, "constitution": 14, "dexterity": 10, "intelligence": 9, "wisdom": 12, "wits": 12},
		"Sorcerer": {"strength": 8, "constitution": 9, "dexterity": 10, "intelligence": 17, "wisdom": 11, "wits": 11},
		"Ninja": {"strength": 11, "constitution": 10, "dexterity": 17, "intelligence": 12, "wisdom": 11, "wits": 10}
	}

	return stats.get(char_class, stats["Fighter"])

func calculate_derived_stats():
	"""Calculate HP, mana, stamina, energy from primary stats"""
	max_hp = (constitution * 10) + (level * 5)
	max_mana = (intelligence * 8) + (wisdom * 4)
	max_stamina = (strength * 4) + (constitution * 4)  # Warrior resource
	max_energy = (wits * 4) + (dexterity * 4)          # Trickster resource

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
		"wits", "wit":
			return wits
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
		"wits": 0,
		"max_hp": 0,
		"max_mana": 0,
		"speed": 0
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
			bonuses.wits += int(base_bonus * 0.2)
		elif "boots" in item_type:
			bonuses.speed += base_bonus  # Speed bonus for flee chance
			bonuses.dexterity += int(base_bonus * 0.3)
			bonuses.defense += int(base_bonus * 0.5)

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
		"wits", "wit":
			return base_stat + bonuses.wits
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
	"""Heal the character, return actual amount healed. Ogre racial applies 2x healing."""
	var old_hp = current_hp
	var heal_amount = int(amount * get_heal_multiplier())
	current_hp = min(current_hp + heal_amount, max_hp)
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
	wits += gains.wits
	
	# Recalculate derived stats
	calculate_derived_stats()
	
	# Full heal on level up
	current_hp = max_hp
	current_mana = max_mana

func get_stat_gains_for_class() -> Dictionary:
	"""Get stat increases per level based on class"""
	var gains = {
		# Warrior Path (primary: STR, secondary: CON)
		"Fighter": {"strength": 3, "constitution": 2, "dexterity": 1, "intelligence": 0, "wisdom": 0, "wits": 1},
		"Barbarian": {"strength": 4, "constitution": 2, "dexterity": 1, "intelligence": 0, "wisdom": 0, "wits": 0},
		# Mage Path (primary: INT, secondary: WIS)
		"Wizard": {"strength": 0, "constitution": 1, "dexterity": 1, "intelligence": 4, "wisdom": 2, "wits": 0},
		"Sage": {"strength": 0, "constitution": 2, "dexterity": 1, "intelligence": 2, "wisdom": 3, "wits": 0},
		# Trickster Path (primary: WITS, secondary: DEX)
		"Thief": {"strength": 1, "constitution": 1, "dexterity": 2, "intelligence": 0, "wisdom": 0, "wits": 4},
		"Ranger": {"strength": 2, "constitution": 2, "dexterity": 2, "intelligence": 0, "wisdom": 0, "wits": 2},
		# Legacy classes (for existing characters)
		"Paladin": {"strength": 2, "constitution": 3, "dexterity": 1, "intelligence": 1, "wisdom": 2, "wits": 2},
		"Sorcerer": {"strength": 0, "constitution": 1, "dexterity": 1, "intelligence": 5, "wisdom": 1, "wits": 1},
		"Ninja": {"strength": 2, "constitution": 1, "dexterity": 5, "intelligence": 2, "wisdom": 1, "wits": 1}
	}

	return gains.get(class_type, gains["Fighter"])

func to_dict() -> Dictionary:
	"""Convert character to dictionary for network transmission"""
	return {
		"id": character_id,
		"name": name,
		"race": race,
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
			"wits": wits
		},
		"current_hp": current_hp,
		"max_hp": max_hp,
		"current_mana": current_mana,
		"max_mana": max_mana,
		"current_stamina": current_stamina,
		"max_stamina": max_stamina,
		"current_energy": current_energy,
		"max_energy": max_energy,
		"x": x,
		"y": y,
		"health_state": get_health_state(),
		"gold": gold,
		"gems": gems,
		"in_combat": in_combat,
		"poison_active": poison_active,
		"poison_damage": poison_damage,
		"poison_turns_remaining": poison_turns_remaining,
		"inventory": inventory,
		"equipped": equipped,
		"created_at": created_at,
		"played_time_seconds": played_time_seconds,
		"monsters_killed": monsters_killed,
		"active_buffs": active_buffs,
		"persistent_buffs": persistent_buffs,
		"active_quests": active_quests,
		"completed_quests": completed_quests,
		"daily_quest_cooldowns": daily_quest_cooldowns
	}

func from_dict(data: Dictionary):
	"""Load character from dictionary"""
	character_id = data.get("id", 0)
	name = data.get("name", "")
	race = data.get("race", "Human")  # Default to Human for legacy characters
	class_type = data.get("class", "Fighter")
	level = data.get("level", 1)
	experience = data.get("experience", 0)

	var stats = data.get("stats", {})
	strength = stats.get("strength", 10)
	constitution = stats.get("constitution", 10)
	dexterity = stats.get("dexterity", 10)
	intelligence = stats.get("intelligence", 10)
	wisdom = stats.get("wisdom", 10)
	wits = stats.get("wits", stats.get("charisma", 10))  # Support legacy save files with charisma

	current_hp = data.get("current_hp", 100)
	max_hp = data.get("max_hp", 100)
	current_mana = data.get("current_mana", 50)
	max_mana = data.get("max_mana", 50)

	# Calculate max stamina/energy from stats for legacy characters, then load current values
	var calc_max_stamina = (strength * 4) + (constitution * 4)
	var calc_max_energy = (wits * 4) + (dexterity * 4)
	max_stamina = data.get("max_stamina", calc_max_stamina)
	max_energy = data.get("max_energy", calc_max_energy)
	current_stamina = data.get("current_stamina", max_stamina)
	current_energy = data.get("current_energy", max_energy)

	x = data.get("x", 0)
	y = data.get("y", 10)
	gold = data.get("gold", 100)
	gems = data.get("gems", 0)
	in_combat = data.get("in_combat", false)
	experience_to_next_level = data.get("experience_to_next_level", 100)

	# Poison status
	poison_active = data.get("poison_active", false)
	poison_damage = data.get("poison_damage", 0)
	poison_turns_remaining = data.get("poison_turns_remaining", 0)

	# Inventory system
	inventory = data.get("inventory", [])
	var loaded_equipped = data.get("equipped", {})
	for slot in equipped.keys():
		equipped[slot] = loaded_equipped.get(slot, null)

	# Tracking fields
	created_at = data.get("created_at", 0)
	played_time_seconds = data.get("played_time_seconds", 0)
	monsters_killed = data.get("monsters_killed", 0)

	# Active buffs (clear on load - combat buffs don't persist between sessions)
	active_buffs = []

	# Persistent buffs DO persist between sessions (battle-based potions)
	persistent_buffs = data.get("persistent_buffs", [])

	# Quest system
	active_quests = data.get("active_quests", [])
	completed_quests = data.get("completed_quests", [])
	daily_quest_cooldowns = data.get("daily_quest_cooldowns", {})

func add_experience(amount: int) -> Dictionary:
	"""Add experience and check for level up. Applies Human racial XP bonus."""
	# Apply Human racial XP bonus (+10%)
	var final_amount = int(amount * get_xp_multiplier())
	experience += final_amount
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
		wits += 1
		
		# Increase HP, Mana, Stamina, Energy
		max_hp += 10 + (constitution / 2)
		max_mana += 5 + (intelligence / 2)
		max_stamina = (strength * 4) + (constitution * 4)  # Recalculate from new stats
		max_energy = (wits * 4) + (dexterity * 4)         # Recalculate from new stats

		# Fully restore resources on level up
		current_hp = max_hp
		current_mana = max_mana
		current_stamina = max_stamina
		current_energy = max_energy

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
	"""Add or refresh a combat buff (lasts rounds). If buff already exists, refreshes duration and uses higher value."""
	for buff in active_buffs:
		if buff.type == buff_type:
			buff.value = max(buff.value, value)
			buff.duration = max(buff.duration, duration)
			return
	active_buffs.append({"type": buff_type, "value": value, "duration": duration})

func add_persistent_buff(buff_type: String, value: int, battles: int):
	"""Add or refresh a persistent buff (lasts multiple battles). If buff already exists, refreshes battles and uses higher value."""
	for buff in persistent_buffs:
		if buff.type == buff_type:
			buff.value = max(buff.value, value)
			buff.battles_remaining = max(buff.battles_remaining, battles)
			return
	persistent_buffs.append({"type": buff_type, "value": value, "battles_remaining": battles})

func get_buff_value(buff_type: String) -> int:
	"""Get the current value of a buff type (combines combat and persistent buffs). Returns 0 if not active."""
	var total = 0
	for buff in active_buffs:
		if buff.type == buff_type:
			total += buff.value
	for buff in persistent_buffs:
		if buff.type == buff_type:
			total += buff.value
	return total

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

func tick_persistent_buffs():
	"""Decrement persistent buff battles by 1. Call when combat ends."""
	var expired = []
	for i in range(persistent_buffs.size()):
		persistent_buffs[i].battles_remaining -= 1
		if persistent_buffs[i].battles_remaining <= 0:
			expired.append(i)
	# Remove expired buffs (reverse order to preserve indices)
	for i in range(expired.size() - 1, -1, -1):
		persistent_buffs.remove_at(expired[i])

func clear_buffs():
	"""Clear all active combat buffs. Call when combat ends. Does NOT clear persistent buffs."""
	active_buffs.clear()

func get_active_buff_names() -> Array:
	"""Get list of active buff type names for display (combines combat and persistent)."""
	var names = []
	for buff in active_buffs:
		names.append(buff.type)
	for buff in persistent_buffs:
		if buff.type not in names:
			names.append(buff.type)
	return names

func get_persistent_buff_display() -> String:
	"""Get display string for persistent buffs."""
	if persistent_buffs.is_empty():
		return ""
	var parts = []
	for buff in persistent_buffs:
		parts.append("+%d %s (%d battles)" % [buff.value, buff.type, buff.battles_remaining])
	return "[color=#00FFFF]Buffs: %s[/color]" % ", ".join(parts)

# ===== RACIAL PASSIVE ABILITIES =====

func get_xp_multiplier() -> float:
	"""Get XP multiplier from racial passive. Human gets +10%."""
	if race == "Human":
		return 1.10
	return 1.0

func has_poison_resistance() -> bool:
	"""Check if character is resistant to poison (Elf racial)."""
	return race == "Elf"

func get_poison_damage_multiplier() -> float:
	"""Get poison damage multiplier. Elf takes 50% poison damage."""
	if race == "Elf":
		return 0.5
	return 1.0

func cure_poison():
	"""Cure poison status effect."""
	poison_active = false
	poison_damage = 0
	poison_turns_remaining = 0

func apply_poison(damage: int, duration: int = 20):
	"""Apply poison to the character. Duration is in combat turns."""
	poison_active = true
	poison_damage = damage
	poison_turns_remaining = duration

func tick_poison() -> int:
	"""Process one turn of poison. Returns damage dealt. Called each combat turn."""
	if not poison_active or poison_turns_remaining <= 0:
		return 0

	poison_turns_remaining -= 1
	if poison_turns_remaining <= 0:
		cure_poison()
		return 0

	# Apply racial resistance
	var final_damage = int(poison_damage * get_poison_damage_multiplier())
	return max(1, final_damage)

func try_last_stand() -> bool:
	"""Dwarf racial: 25% chance to survive lethal damage with 1 HP.
	Returns true if Last Stand triggered, false otherwise.
	Can only trigger once per combat."""
	if race != "Dwarf":
		return false
	if last_stand_used:
		return false

	# 25% chance to trigger
	var roll = randi() % 100
	if roll < 25:
		last_stand_used = true
		current_hp = 1
		return true
	return false

func reset_combat_flags():
	"""Reset per-combat flags. Call at start of each combat."""
	last_stand_used = false

func get_heal_multiplier() -> float:
	"""Get healing multiplier from racial passive. Ogre gets 2x healing."""
	if race == "Ogre":
		return 2.0
	return 1.0

# ===== RESOURCE MANAGEMENT =====

func use_stamina(amount: int) -> bool:
	"""Attempt to use stamina. Returns true if successful, false if insufficient."""
	if current_stamina < amount:
		return false
	current_stamina -= amount
	return true

func use_energy(amount: int) -> bool:
	"""Attempt to use energy. Returns true if successful, false if insufficient."""
	if current_energy < amount:
		return false
	current_energy -= amount
	return true

func use_mana(amount: int) -> bool:
	"""Attempt to use mana. Returns true if successful, false if insufficient."""
	if current_mana < amount:
		return false
	current_mana -= amount
	return true

func regenerate_stamina_defending() -> int:
	"""Regenerate 10% stamina while defending. Returns amount regenerated."""
	var regen = int(max_stamina * 0.10)
	regen = max(1, regen)  # At least 1
	current_stamina = min(max_stamina, current_stamina + regen)
	return regen

func regenerate_energy() -> int:
	"""Regenerate 15% energy each combat round automatically. Returns amount regenerated."""
	var regen = int(max_energy * 0.15)
	regen = max(1, regen)  # At least 1
	current_energy = min(max_energy, current_energy + regen)
	return regen

func restore_all_resources():
	"""Restore all resources to full (for resting or sanctuaries)."""
	current_hp = max_hp
	current_mana = max_mana
	current_stamina = max_stamina
	current_energy = max_energy

# ===== QUEST SYSTEM =====

func can_accept_quest() -> bool:
	"""Check if player can accept another quest"""
	return active_quests.size() < MAX_ACTIVE_QUESTS

func has_quest(quest_id: String) -> bool:
	"""Check if player has an active quest with this ID"""
	for quest in active_quests:
		if quest.quest_id == quest_id:
			return true
	return false

func has_completed_quest(quest_id: String) -> bool:
	"""Check if player has completed this quest"""
	return quest_id in completed_quests

func can_accept_daily_quest(quest_id: String) -> bool:
	"""Check if daily quest cooldown has expired"""
	if not daily_quest_cooldowns.has(quest_id):
		return true
	var cooldown_end = daily_quest_cooldowns[quest_id]
	return Time.get_unix_time_from_system() >= cooldown_end

func get_quest_progress(quest_id: String) -> Dictionary:
	"""Get progress for an active quest. Returns empty dict if not found."""
	for quest in active_quests:
		if quest.quest_id == quest_id:
			return quest
	return {}

func add_quest(quest_id: String, target: int, origin_x: int = 0, origin_y: int = 0) -> bool:
	"""Add a new quest to active quests. Returns false if at max or already has quest."""
	if not can_accept_quest() or has_quest(quest_id):
		return false

	active_quests.append({
		"quest_id": quest_id,
		"progress": 0,
		"target": target,
		"started_at": int(Time.get_unix_time_from_system()),
		"origin_x": origin_x,
		"origin_y": origin_y,
		"accumulated_intensity": 0.0,  # For hotzone quests
		"kills_in_hotzone": 0  # Track kills specifically in hotzones
	})
	return true

func update_quest_progress(quest_id: String, amount: int = 1, hotzone_intensity: float = 0.0) -> Dictionary:
	"""Increment quest progress. Returns {updated: bool, completed: bool, progress: int, target: int}"""
	for quest in active_quests:
		if quest.quest_id == quest_id:
			quest.progress += amount
			if hotzone_intensity > 0:
				quest.kills_in_hotzone += amount
				quest.accumulated_intensity += hotzone_intensity * amount
			return {
				"updated": true,
				"completed": quest.progress >= quest.target,
				"progress": quest.progress,
				"target": quest.target
			}
	return {"updated": false, "completed": false, "progress": 0, "target": 0}

func complete_quest(quest_id: String, is_daily: bool = false) -> bool:
	"""Mark quest as completed and remove from active. Returns false if quest not found."""
	for i in range(active_quests.size()):
		if active_quests[i].quest_id == quest_id:
			var quest = active_quests[i]
			active_quests.remove_at(i)
			if not is_daily:
				completed_quests.append(quest_id)
			else:
				# Daily quests have 24 hour cooldown
				daily_quest_cooldowns[quest_id] = int(Time.get_unix_time_from_system()) + 86400
			return true
	return false

func abandon_quest(quest_id: String) -> bool:
	"""Remove quest from active without completing. Returns false if quest not found."""
	for i in range(active_quests.size()):
		if active_quests[i].quest_id == quest_id:
			active_quests.remove_at(i)
			return true
	return false

func get_active_quest_count() -> int:
	"""Get number of active quests"""
	return active_quests.size()

func get_average_hotzone_intensity(quest_id: String) -> float:
	"""Get average hotzone intensity for a quest (for reward multiplier)"""
	for quest in active_quests:
		if quest.quest_id == quest_id:
			if quest.kills_in_hotzone > 0:
				return quest.accumulated_intensity / quest.kills_in_hotzone
			return 0.0
	return 0.0
