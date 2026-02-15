# combat_manager.gd
# Handles turn-based combat in Phantasia 4 style
class_name CombatManager
extends Node

# Combat actions
enum CombatAction {
	ATTACK,
	FLEE,
	SPECIAL,
	OUTSMART,
	ABILITY
}

# Ability lookup for parsing commands
const MAGE_ABILITY_COMMANDS = ["magic_bolt", "bolt", "cloak", "blast", "forcefield", "teleport", "meteor", "haste", "paralyze", "banish"]
const WARRIOR_ABILITY_COMMANDS = ["power_strike", "strike", "war_cry", "warcry", "shield_bash", "bash", "cleave", "berserk", "iron_skin", "ironskin", "devastate", "fortify", "rally"]
const TRICKSTER_ABILITY_COMMANDS = ["analyze", "distract", "pickpocket", "ambush", "vanish", "exploit", "perfect_heist", "heist", "sabotage", "gambit"]
const UNIVERSAL_ABILITY_COMMANDS = ["all_or_nothing"]

# Active combats (peer_id -> combat_state)
var active_combats = {}

# Active party combats (leader_peer_id -> party_combat_state)
var active_party_combats = {}
# Reverse lookup for party combat (peer_id -> leader_peer_id)
var party_combat_membership = {}

# Pending buff expiration notifications (peer_id -> array of expired buffs)
var _pending_buff_expirations = {}

# Drop tables reference (set by server when initialized)
# Using Node type to avoid compile-time dependency on DropTables class
var drop_tables: Node = null

# Monster database reference (for class affinity helpers)
var monster_database: Node = null

# Titles reference for title item drops
const TitlesScript = preload("res://shared/titles.gd")

# Balance configuration (set by server)
var balance_config: Dictionary = {}

func set_balance_config(cfg: Dictionary):
	"""Set balance configuration from server"""
	balance_config = cfg
	print("Combat Manager: Balance config loaded")

# Monster ability constants (duplicated from MonsterDatabase for easy access)
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
const ABILITY_GOLD_HOARDER = "gold_hoarder"  # Legacy — no effect (gold removed)
const ABILITY_GEM_BEARER = "gem_bearer"
const ABILITY_CURSE = "curse"
const ABILITY_DISARM = "disarm"
const ABILITY_UNPREDICTABLE = "unpredictable"
const ABILITY_WISH_GRANTER = "wish_granter"
const ABILITY_DEATH_CURSE = "death_curse"
const ABILITY_BERSERKER = "berserker"
const ABILITY_COWARD = "coward"
const ABILITY_LIFE_STEAL = "life_steal"
const ABILITY_ENRAGE = "enrage"
const ABILITY_AMBUSHER = "ambusher"
const ABILITY_EASY_PREY = "easy_prey"
const ABILITY_THORNS = "thorns"
const ABILITY_WEAPON_MASTER = "weapon_master"    # Guaranteed weapon drop
const ABILITY_SHIELD_BEARER = "shield_bearer"    # Guaranteed shield drop
const ABILITY_CORROSIVE = "corrosive"            # Chance to damage player's equipment on hit
const ABILITY_SUNDER = "sunder"                  # Specifically damages weapons/shields
const ABILITY_BLIND = "blind"                    # Reduces player hit chance
const ABILITY_BLEED = "bleed"                    # Stacking bleed DoT on player
const ABILITY_SLOW_AURA = "slow_aura"            # Reduces player flee chance
const ABILITY_ARCANE_HOARDER = "arcane_hoarder"  # 35% chance to drop mage gear
const ABILITY_CUNNING_PREY = "cunning_prey"      # 35% chance to drop trickster gear
const ABILITY_WARRIOR_HOARDER = "warrior_hoarder"  # 35% chance to drop warrior gear
const ABILITY_WEAKNESS = "weakness"              # Applies -25% attack debuff for 20 rounds

# New abilities from Phantasia 5 inspiration
const ABILITY_CHARM = "charm"                    # Player attacks themselves for 1 turn
const ABILITY_GOLD_STEAL = "gold_steal"          # Legacy — no effect (gold removed)
const ABILITY_BUFF_DESTROY = "buff_destroy"      # Removes one random active buff
const ABILITY_SHIELD_SHATTER = "shield_shatter"  # Destroys forcefield/shield buffs instantly
const ABILITY_FLEE_ATTACK = "flee_attack"        # Deals damage then flees (no loot)
const ABILITY_DISGUISE = "disguise"              # Appears as weaker monster, reveals after 2 rounds
const ABILITY_XP_STEAL = "xp_steal"              # Steals 1-3% of player XP on hit (rare, punishing)
const ABILITY_ITEM_STEAL = "item_steal"          # 5% chance to steal random equipped item

func get_monster_combat_bg_color(monster_name: String) -> String:
	"""Get the contrasting background color for a monster's combat screen"""
	var raw_art_array = _get_raw_monster_ascii_art(monster_name)
	var art_color = _extract_art_color(raw_art_array)
	return _get_contrasting_bg_color(art_color)

func get_flock_varied_colors(monster_name: String, flock_count: int) -> Dictionary:
	"""Get varied art and background colors for flock encounters to add visual variety"""
	# Use distinct color palette for big, noticeable changes between flock members
	var color_palette = [
		"#00FF00",  # Green
		"#00BFFF",  # Deep Sky Blue
		"#FF4500",  # Orange Red
		"#FFD700",  # Gold
		"#FF00FF",  # Magenta
		"#00FFFF",  # Cyan
		"#FF6347",  # Tomato
		"#ADFF2F",  # Green Yellow
		"#DA70D6",  # Orchid
		"#7FFF00",  # Chartreuse
		"#FF1493",  # Deep Pink
		"#1E90FF",  # Dodger Blue
	]

	# Pick color based on flock count to ensure each pack member looks different
	var varied_art_color = color_palette[flock_count % color_palette.size()]
	# Use contrasting background for the varied art color
	var varied_bg_color = _get_contrasting_bg_color(varied_art_color)

	return {
		"art_color": varied_art_color,
		"bg_color": varied_bg_color
	}

func get_random_varied_colors(monster_name: String) -> Dictionary:
	"""Get randomly varied art and background colors for visual variety on any encounter"""
	# Use distinct color palette for big, noticeable changes
	var color_palette = [
		"#00FF00",  # Green
		"#00BFFF",  # Deep Sky Blue
		"#FF4500",  # Orange Red
		"#FFD700",  # Gold
		"#FF00FF",  # Magenta
		"#00FFFF",  # Cyan
		"#FF6347",  # Tomato
		"#ADFF2F",  # Green Yellow
		"#DA70D6",  # Orchid
		"#7FFF00",  # Chartreuse
		"#FF1493",  # Deep Pink
		"#1E90FF",  # Dodger Blue
	]

	# Pick a random color from the palette
	var varied_art_color = color_palette[randi() % color_palette.size()]
	var varied_bg_color = _get_contrasting_bg_color(varied_art_color)

	return {
		"art_color": varied_art_color,
		"bg_color": varied_bg_color
	}

func _shift_color_hue(hex_color: String, degrees: int) -> String:
	"""Shift the hue of a hex color by the specified degrees (0-360)"""
	if not hex_color.begins_with("#") or hex_color.length() < 7:
		return hex_color

	var r = hex_color.substr(1, 2).hex_to_int() / 255.0
	var g = hex_color.substr(3, 2).hex_to_int() / 255.0
	var b = hex_color.substr(5, 2).hex_to_int() / 255.0

	# Convert RGB to HSV
	var max_c = max(r, max(g, b))
	var min_c = min(r, min(g, b))
	var delta = max_c - min_c

	var h = 0.0
	var s = 0.0 if max_c == 0 else delta / max_c
	var v = max_c

	if delta > 0:
		if max_c == r:
			h = 60.0 * fmod((g - b) / delta, 6.0)
		elif max_c == g:
			h = 60.0 * ((b - r) / delta + 2.0)
		else:
			h = 60.0 * ((r - g) / delta + 4.0)

	if h < 0:
		h += 360.0

	# Shift hue
	h = fmod(h + degrees, 360.0)

	# Convert HSV back to RGB
	var c = v * s
	var x = c * (1.0 - abs(fmod(h / 60.0, 2.0) - 1.0))
	var m = v - c

	var r2 = 0.0
	var g2 = 0.0
	var b2 = 0.0

	if h < 60:
		r2 = c; g2 = x; b2 = 0
	elif h < 120:
		r2 = x; g2 = c; b2 = 0
	elif h < 180:
		r2 = 0; g2 = c; b2 = x
	elif h < 240:
		r2 = 0; g2 = x; b2 = c
	elif h < 300:
		r2 = x; g2 = 0; b2 = c
	else:
		r2 = c; g2 = 0; b2 = x

	var new_r = int((r2 + m) * 255)
	var new_g = int((g2 + m) * 255)
	var new_b = int((b2 + m) * 255)

	return "#%02X%02X%02X" % [new_r, new_g, new_b]

func _get_contrasting_bg_color(art_color: String) -> String:
	"""Generate a dark complementary background for high contrast with art color"""
	# Parse the hex color (format: #RRGGBB)
	if not art_color.begins_with("#") or art_color.length() < 7:
		return "#0A0A0A"  # Default near-black

	var r = art_color.substr(1, 2).hex_to_int()
	var g = art_color.substr(3, 2).hex_to_int()
	var b = art_color.substr(5, 2).hex_to_int()

	# Use complementary color (opposite on color wheel) at low brightness
	# Invert the color then darken it significantly
	var inv_r = 255 - r
	var inv_g = 255 - g
	var inv_b = 255 - b

	# Dark version of complementary (20% brightness)
	var bg_r = int(inv_r * 0.15) + 5
	var bg_g = int(inv_g * 0.15) + 5
	var bg_b = int(inv_b * 0.15) + 5

	# Keep it dark but visible
	bg_r = min(bg_r, 50)
	bg_g = min(bg_g, 50)
	bg_b = min(bg_b, 50)

	return "#%02X%02X%02X" % [bg_r, bg_g, bg_b]

func _extract_art_color(art_array: Array) -> String:
	"""Extract the color hex code from an ASCII art array"""
	if art_array.size() == 0:
		return "#FFFFFF"

	var first_element = art_array[0]
	if first_element.begins_with("[color="):
		# Extract color from [color=#HEXCODE]
		var start = first_element.find("#")
		var end = first_element.find("]")
		if start != -1 and end != -1:
			return first_element.substr(start, end - start)

	return "#FFFFFF"  # Default white

func apply_damage_variance(base_damage: int) -> int:
	"""Apply Â±15% variance to damage to make combat less predictable"""
	# Variance range: 0.85 to 1.15 (Â±15%)
	var variance = 0.85 + (randf() * 0.30)
	return max(1, int(base_damage * variance))

func apply_ability_damage_modifiers(damage: int, char_level: int, monster: Dictionary) -> int:
	"""Apply 50% defense and level penalty to ability damage"""
	var mod_damage = damage
	var mon_def = monster.get("defense", 0)
	var def_ratio = float(mon_def) / (float(mon_def) + 100.0)
	var partial_red = (def_ratio * 0.6) * 0.5
	mod_damage = int(mod_damage * (1.0 - partial_red))
	var mon_level = monster.get("level", 1)
	var lvl_diff = mon_level - char_level
	if lvl_diff > 0:
		var lvl_penalty = min(0.40, lvl_diff * 0.015)
		mod_damage = int(mod_damage * (1.0 - lvl_penalty))
	return max(1, mod_damage)

func set_monster_database(db: Node):
	"""Set the monster database reference"""
	monster_database = db

func _process_status_ticks(character: Character, messages: Array) -> void:
	"""Process poison and blind ticks at the start of a player's turn.
	Called by all player combat actions."""
	# === POISON TICK ===
	if character.poison_active:
		var poison_dmg = character.tick_poison()
		if poison_dmg > 0:
			character.current_hp -= poison_dmg
			character.current_hp = max(1, character.current_hp)  # Poison can't kill
			var turns_left = character.poison_turns_remaining
			if turns_left > 0:
				messages.append("[color=#FF00FF]Poison deals %d damage! (%d turns remaining)[/color]" % [poison_dmg, turns_left])
			else:
				messages.append("[color=#FF00FF]Poison deals %d damage! The poison fades.[/color]" % poison_dmg)

	# === BLIND TICK ===
	if character.blind_active:
		var still_blind = character.tick_blind()
		if still_blind:
			messages.append("[color=#808080]You are blinded! (%d turns remaining)[/color]" % character.blind_turns_remaining)
		else:
			messages.append("[color=#00FF00]Your vision clears![/color]")

func _apply_gear_resource_regen(character: Character, messages: Array) -> void:
	"""Apply equipment-based and buff-based resource regeneration at start of player turn.
	Called by both regular attacks and ability usage."""
	var bonuses = character.get_equipment_bonuses()

	# Combine gear mana_regen with buff mana_regen (from crafted consumables like Enchanted Kindling)
	var mana_regen = bonuses.get("mana_regen", 0) + character.get_buff_value("mana_regen")
	if mana_regen > 0 and character.current_mana < character.get_total_max_mana():
		var old_mana = character.current_mana
		character.current_mana = mini(character.get_total_max_mana(), character.current_mana + mana_regen)
		var actual_regen = character.current_mana - old_mana
		if actual_regen > 0:
			if bonuses.get("mana_regen", 0) > 0 and character.get_buff_value("mana_regen") > 0:
				messages.append("[color=#66CCFF]Arcane power restores %d mana.[/color]" % actual_regen)
			elif character.get_buff_value("mana_regen") > 0:
				messages.append("[color=#66CCFF]Enchantment restores %d mana.[/color]" % actual_regen)
			else:
				messages.append("[color=#66CCFF]Arcane gear restores %d mana.[/color]" % actual_regen)

	# Combine gear energy_regen with buff energy_regen
	var energy_regen = bonuses.get("energy_regen", 0) + character.get_buff_value("energy_regen")
	if energy_regen > 0 and character.current_energy < character.get_total_max_energy():
		var old_energy = character.current_energy
		character.current_energy = mini(character.get_total_max_energy(), character.current_energy + energy_regen)
		var actual_regen = character.current_energy - old_energy
		if actual_regen > 0:
			if character.get_buff_value("energy_regen") > 0:
				messages.append("[color=#66FF66]Enchantment restores %d energy.[/color]" % actual_regen)
			else:
				messages.append("[color=#66FF66]Shadow gear restores %d energy.[/color]" % actual_regen)

	# Combine gear stamina_regen with buff stamina_regen
	var stamina_regen = bonuses.get("stamina_regen", 0) + character.get_buff_value("stamina_regen")
	if stamina_regen > 0 and character.current_stamina < character.get_total_max_stamina():
		var old_stam = character.current_stamina
		character.current_stamina = mini(character.get_total_max_stamina(), character.current_stamina + stamina_regen)
		var actual_regen = character.current_stamina - old_stam
		if actual_regen > 0:
			if character.get_buff_value("stamina_regen") > 0:
				messages.append("[color=#FF6600]Enchantment restores %d stamina.[/color]" % actual_regen)
			else:
				messages.append("[color=#FF6600]Warlord gear restores %d stamina.[/color]" % actual_regen)

func _apply_companion_resource_regen(combat: Dictionary, character: Character, messages: Array) -> void:
	"""Apply companion passive resource regeneration each turn.
	All resource regen (mana/stamina/energy) is pooled and applied to the player's primary resource."""
	var companion = character.get_active_companion() if character.has_active_companion() else null
	if companion == null:
		return

	# HP Regen from companion (all classes have HP)
	var hp_regen = combat.get("companion_hp_regen", 0)
	hp_regen += int(character.get_companion_bonus("hp_regen"))
	if hp_regen > 0 and character.current_hp < character.get_total_max_hp():
		var heal_amount = max(1, int(character.get_total_max_hp() * hp_regen / 100.0))
		var old_hp = character.current_hp
		character.current_hp = min(character.get_total_max_hp(), character.current_hp + heal_amount)
		var actual_heal = character.current_hp - old_hp
		if actual_heal > 0:
			messages.append("[color=#00FFFF]%s's presence heals you for %d HP.[/color]" % [companion.name, actual_heal])

	# Resource Regen: Pool ALL types (mana/stamina/energy) and apply to player's primary resource
	var resource_regen = 0
	resource_regen += combat.get("companion_mana_regen", 0)
	resource_regen += combat.get("companion_energy_regen", 0)
	resource_regen += combat.get("companion_stamina_regen", 0)
	resource_regen += int(character.get_companion_bonus("mana_regen"))
	resource_regen += int(character.get_companion_bonus("energy_regen"))
	resource_regen += int(character.get_companion_bonus("stamina_regen"))

	if resource_regen > 0:
		var regen_amount = max(1, resource_regen)
		var class_path = character.get_class_path()
		match class_path:
			"warrior":
				if character.current_stamina < character.get_total_max_stamina():
					var old_val = character.current_stamina
					character.current_stamina = min(character.get_total_max_stamina(), character.current_stamina + regen_amount)
					var actual_regen = character.current_stamina - old_val
					if actual_regen > 0:
						messages.append("[color=#00FFFF]%s restores %d stamina.[/color]" % [companion.name, actual_regen])
			"mage":
				if character.current_mana < character.get_total_max_mana():
					var old_val = character.current_mana
					character.current_mana = min(character.get_total_max_mana(), character.current_mana + regen_amount)
					var actual_regen = character.current_mana - old_val
					if actual_regen > 0:
						messages.append("[color=#00FFFF]%s restores %d mana.[/color]" % [companion.name, actual_regen])
			"trickster":
				if character.current_energy < character.get_total_max_energy():
					var old_val = character.current_energy
					character.current_energy = min(character.get_total_max_energy(), character.current_energy + regen_amount)
					var actual_regen = character.current_energy - old_val
					if actual_regen > 0:
						messages.append("[color=#00FFFF]%s restores %d energy.[/color]" % [companion.name, actual_regen])

func _process_monster_dots(combat: Dictionary, monster: Dictionary, messages: Array) -> void:
	"""Process companion DoT effects on the monster (poison only - bleed is handled in monster turn)."""

	# Poison damage
	var poison_damage = combat.get("monster_poison", 0)
	var poison_duration = combat.get("monster_poison_duration", 0)
	if poison_damage > 0 and poison_duration > 0:
		monster.current_hp -= poison_damage
		monster.current_hp = max(0, monster.current_hp)
		messages.append("[color=#00FF00]Poison deals %d damage to the %s![/color]" % [poison_damage, monster.name])
		combat["monster_poison_duration"] = poison_duration - 1
		if combat["monster_poison_duration"] <= 0:
			combat["monster_poison"] = 0

	# Decrement weakness duration
	var weakness_duration = combat.get("monster_weakness_duration", 0)
	if weakness_duration > 0:
		combat["monster_weakness_duration"] = weakness_duration - 1
		if combat["monster_weakness_duration"] <= 0:
			combat["monster_weakness"] = 0

	# Decrement slow duration
	var slow_duration = combat.get("monster_slow_duration", 0)
	if slow_duration > 0:
		combat["monster_slow_duration"] = slow_duration - 1
		if combat["monster_slow_duration"] <= 0:
			combat["monster_slowed"] = 0

func _apply_companion_passive_effect(combat_state: Dictionary, character: Character, effect: String, value: int) -> void:
	"""Apply a single companion passive effect to combat state or character."""
	match effect:
		"attack":
			combat_state["companion_attack_bonus"] = combat_state.get("companion_attack_bonus", 0) + value
		"defense":
			combat_state["companion_defense_bonus"] = combat_state.get("companion_defense_bonus", 0) + value
		"speed":
			combat_state["companion_speed_bonus"] = combat_state.get("companion_speed_bonus", 0) + value
		"crit_chance":
			combat_state["companion_crit_bonus"] = combat_state.get("companion_crit_bonus", 0) + value
		"lifesteal":
			combat_state["companion_lifesteal_bonus"] = combat_state.get("companion_lifesteal_bonus", 0) + value
		"hp_bonus":
			# Increase max HP for this combat (applied as temporary buff)
			combat_state["companion_hp_bonus"] = combat_state.get("companion_hp_bonus", 0) + value
		"mana_bonus":
			combat_state["companion_mana_bonus"] = combat_state.get("companion_mana_bonus", 0) + value
		"hp_regen":
			combat_state["companion_hp_regen"] = combat_state.get("companion_hp_regen", 0) + value
		"mana_regen":
			combat_state["companion_mana_regen"] = combat_state.get("companion_mana_regen", 0) + value
		"energy_regen":
			combat_state["companion_energy_regen"] = combat_state.get("companion_energy_regen", 0) + value
		"stamina_regen":
			combat_state["companion_stamina_regen"] = combat_state.get("companion_stamina_regen", 0) + value
		"gathering_bonus":
			combat_state["companion_gathering_bonus"] = combat_state.get("companion_gathering_bonus", 0) + value
		"flee_bonus":
			combat_state["companion_flee_bonus"] = combat_state.get("companion_flee_bonus", 0) + value
		"crit_damage":
			combat_state["companion_crit_damage"] = combat_state.get("companion_crit_damage", 0) + value
		"wisdom_bonus":
			combat_state["companion_wisdom_bonus"] = combat_state.get("companion_wisdom_bonus", 0) + value

func _process_companion_attack(combat: Dictionary, messages: Array) -> void:
	"""Process companion attack during player's turn.
	Called by both regular attacks and ability usage."""
	var character = combat.character
	var monster = combat.monster

	if monster.current_hp <= 0:
		return

	if not character.has_active_companion():
		return

	var companion = character.get_active_companion()
	var companion_tier = companion.get("tier", 1)
	var companion_level = companion.get("level", 1)
	var companion_bonuses = companion.get("bonuses", {})
	var companion_sub_tier = companion.get("sub_tier", 1)

	# Calculate companion damage (now scales with companion level and sub-tier)
	var companion_damage = 0
	if drop_tables:
		companion_damage = drop_tables.get_companion_attack_damage(companion_tier, character.level, companion_bonuses, companion_level, companion_sub_tier)
	else:
		# Fallback formula matching drop_tables
		companion_damage = companion_tier * 5 + int(character.level * 0.3) + int(companion_level * 0.5)

	# Apply variant multiplier
	var variant_mult = character.get_variant_stat_multiplier()
	companion_damage = int(companion_damage * variant_mult)

	# Apply some variance (80-120%)
	companion_damage = int(companion_damage * randf_range(0.8, 1.2))
	companion_damage = max(1, companion_damage)
	monster.current_hp -= companion_damage
	monster.current_hp = max(0, monster.current_hp)
	messages.append("[color=#00FFFF]Your %s attacks for %d damage![/color]" % [companion.name, companion_damage])

	# === COMPANION CHANCE ABILITIES ===
	# Use monster-specific abilities stored at combat start (pre-scaled by level + variant)
	var comp_abilities = combat.get("companion_abilities", {})
	if not comp_abilities.is_empty() and not comp_abilities.get("active", {}).is_empty() and monster.current_hp > 0:
		var ability = comp_abilities.active
		var trigger_chance = ability.get("chance", 0)
		if randi() % 100 < trigger_chance:
			var effect = ability.get("effect", "")
			var ability_name = ability.get("name", "ability")
			var ability_damage_dealt = 0  # Track damage for lifesteal calc
			if effect == "enemy_miss":
				combat["companion_distraction"] = true
				messages.append("[color=#FFAA00]%s's %s distracts the enemy![/color]" % [companion.name, ability_name])
			elif effect == "bonus_damage":
				var bonus_value = ability.get("damage", ability.get("value", 10))
				monster.current_hp -= bonus_value
				monster.current_hp = max(0, monster.current_hp)
				ability_damage_dealt = bonus_value
				messages.append("[color=#FFAA00]%s uses %s for %d bonus damage![/color]" % [companion.name, ability_name, bonus_value])
			elif effect == "stun":
				combat["monster_stunned"] = 1
				messages.append("[color=#FFAA00]%s's attack stuns the %s![/color]" % [companion.name, monster.name])
			elif effect == "crit":
				# Critical strike ability - crit_mult not level-scaled, variant already in companion_damage
				var crit_mult = ability.get("crit_mult", 1.5)
				var crit_damage = int(companion_damage * (crit_mult - 1.0))
				monster.current_hp -= crit_damage
				monster.current_hp = max(0, monster.current_hp)
				ability_damage_dealt = companion_damage + crit_damage
				messages.append("[color=#FFD700]%s lands a critical %s for %d bonus damage![/color]" % [companion.name, ability_name, crit_damage])
			elif effect == "bleed":
				# Apply bleed DoT to monster (damage is pre-scaled)
				var bleed_damage = ability.get("damage", ability.get("base_damage", 5))
				var bleed_duration = ability.get("duration", 3)
				combat["monster_bleed"] = combat.get("monster_bleed", 0) + bleed_damage
				combat["monster_bleed_duration"] = max(combat.get("monster_bleed_duration", 0), bleed_duration)
				messages.append("[color=#FF4444]%s's %s causes bleeding! (%d damage/turn)[/color]" % [companion.name, ability_name, bleed_damage])
			elif effect == "poison":
				# Apply poison DoT to monster (damage is pre-scaled)
				var poison_damage = ability.get("damage", ability.get("base_damage", 5))
				var poison_duration = ability.get("duration", 3)
				combat["monster_poison"] = combat.get("monster_poison", 0) + poison_damage
				combat["monster_poison_duration"] = max(combat.get("monster_poison_duration", 0), poison_duration)
				messages.append("[color=#00FF00]%s's %s poisons the enemy! (%d damage/turn)[/color]" % [companion.name, ability_name, poison_damage])
			elif effect == "charm":
				# Monster skips its turn
				var charm_duration = ability.get("duration", 1)
				combat["monster_charmed"] = charm_duration
				messages.append("[color=#FF69B4]%s's %s charms the %s! (Skips %d turn(s))[/color]" % [companion.name, ability_name, monster.name, charm_duration])
			elif effect == "multi_hit":
				# Multiple hits (damage is pre-scaled)
				var num_hits = ability.get("hits", 3)
				var hit_damage = ability.get("damage", ability.get("base_damage", 5))
				var total_multi_damage = hit_damage * num_hits
				monster.current_hp -= total_multi_damage
				monster.current_hp = max(0, monster.current_hp)
				ability_damage_dealt = total_multi_damage
				messages.append("[color=#FFAA00]%s uses %s! %d hits for %d total damage![/color]" % [companion.name, ability_name, num_hits, total_multi_damage])
			elif effect == "mana_drain":
				# Drain mana from monster (reduces magic effectiveness)
				var drain_amount = ability.get("base_amount", 10)
				combat["monster_mana_drained"] = combat.get("monster_mana_drained", 0) + drain_amount
				messages.append("[color=#9966FF]%s's %s drains the enemy's magical power![/color]" % [companion.name, ability_name])
			elif effect == "weakness":
				# Reduce monster's attack (value is pre-scaled)
				var weakness_value = ability.get("value", ability.get("base_reduction", 15))
				var weakness_duration = ability.get("duration", 3)
				combat["monster_weakness"] = weakness_value
				combat["monster_weakness_duration"] = weakness_duration
				messages.append("[color=#808080]%s's %s weakens the %s! (-%d%% attack for %d turns)[/color]" % [companion.name, ability_name, monster.name, weakness_value, weakness_duration])
			elif effect == "execute":
				# Execute enemies below threshold
				var execute_threshold = ability.get("execute_threshold", 20) / 100.0
				var monster_hp_pct = float(monster.current_hp) / float(monster.max_hp)
				if monster_hp_pct <= execute_threshold:
					monster.current_hp = 0
					messages.append("[color=#FF0000]%s's %s executes the %s![/color]" % [companion.name, ability_name, monster.name])
				else:
					# If not below threshold, deal bonus damage instead
					var exec_damage = int(companion_damage * 0.5)
					monster.current_hp -= exec_damage
					monster.current_hp = max(0, monster.current_hp)
					messages.append("[color=#FFAA00]%s's %s deals %d damage![/color]" % [companion.name, ability_name, exec_damage])
			elif effect == "lifesteal":
				# Direct lifesteal effect (percent is pre-scaled)
				var lifesteal_pct = ability.get("percent", ability.get("base_percent", 20))
				var steal_value = max(1, int(companion_damage * lifesteal_pct / 100.0))
				var actual_heal = character.heal(steal_value)
				if actual_heal > 0:
					messages.append("[color=#00FF00]%s's %s drains %d HP for you![/color]" % [companion.name, ability_name, actual_heal])

			# Check for secondary effects (lifesteal, stun, bleed, etc.)
			if ability.has("effect2"):
				# If chance2 is specified, roll for it; otherwise effect2 triggers with main effect
				var effect2_triggers = true
				if ability.has("chance2"):
					effect2_triggers = randi() % 100 < ability.get("chance2", 0)

				if effect2_triggers:
					var effect2 = ability.get("effect2", "")
					if effect2 == "stun":
						# Stun may have its own stun_chance (e.g., Giant's Ground Slam)
						var stun_triggers = true
						if ability.has("stun_chance"):
							stun_triggers = randi() % 100 < ability.get("stun_chance", 0)
						if stun_triggers:
							combat["monster_stunned"] = 1
							messages.append("[color=#FFAA00]The %s is stunned![/color]" % monster.name)
					elif effect2 == "lifesteal":
						# Use lifesteal_percent if available, otherwise value2
						var lifesteal_pct = ability.get("lifesteal_percent", ability.get("value2", 10))
						var base_damage = ability_damage_dealt if ability_damage_dealt > 0 else companion_damage
						var steal_value = max(1, int(base_damage * lifesteal_pct / 100.0))
						var actual_heal = character.heal(steal_value)
						if actual_heal > 0:
							messages.append("[color=#00FF00]%s drains %d HP for you![/color]" % [companion.name, actual_heal])
					elif effect2 == "bleed":
						var bleed_damage = ability.get("bleed_damage", 5)
						combat["monster_bleed"] = combat.get("monster_bleed", 0) + bleed_damage
						combat["monster_bleed_duration"] = max(combat.get("monster_bleed_duration", 0), 3)
						messages.append("[color=#FF4444]The %s is bleeding![/color]" % monster.name)
					elif effect2 == "mana_drain":
						var drain_amount = ability.get("drain_amount", 10)
						combat["monster_mana_drained"] = combat.get("monster_mana_drained", 0) + drain_amount
						messages.append("[color=#9966FF]%s drains the enemy's mana![/color]" % companion.name)
					elif effect2 == "poison":
						var poison_damage = ability.get("poison_damage", 5)
						combat["monster_poison"] = combat.get("monster_poison", 0) + poison_damage
						combat["monster_poison_duration"] = max(combat.get("monster_poison_duration", 0), 3)
						messages.append("[color=#00FF00]The %s is poisoned![/color]" % monster.name)
					elif effect2 == "heal":
						var heal_pct = ability.get("heal_percent", 10)
						var heal_amount = max(1, int(character.get_total_max_hp() * heal_pct / 100.0))
						var actual_heal = character.heal(heal_amount)
						if actual_heal > 0:
							messages.append("[color=#00FF00]%s heals you for %d HP![/color]" % [companion.name, actual_heal])
					elif effect2 == "weakness":
						var weakness_val = ability.get("weakness_value", ability.get("weakness_base", 15))
						var weakness_dur = ability.get("duration", 3)
						combat["monster_weakness"] = weakness_val
						combat["monster_weakness_duration"] = weakness_dur
						messages.append("[color=#808080]The %s is weakened! (-%d%% attack for %d turns)[/color]" % [monster.name, weakness_val, weakness_dur])
					elif effect2 == "random_debuff":
						# Apply a random debuff
						var debuffs = ["stun", "weakness", "slow"]
						var chosen = debuffs[randi() % debuffs.size()]
						if chosen == "stun":
							combat["monster_stunned"] = 1
							messages.append("[color=#FFAA00]The %s is stunned![/color]" % monster.name)
						elif chosen == "weakness":
							combat["monster_weakness"] = 15
							combat["monster_weakness_duration"] = 2
							messages.append("[color=#808080]The %s is weakened![/color]" % monster.name)
						elif chosen == "slow":
							combat["monster_slowed"] = 20
							combat["monster_slow_duration"] = 2
							messages.append("[color=#6699FF]The %s is slowed![/color]" % monster.name)

func _infer_tier_from_name(item_name: String) -> int:
	"""Infer consumable tier from item name for legacy items without tier field"""
	var name_lower = item_name.to_lower()
	if "divine" in name_lower: return 7
	if "master" in name_lower: return 6
	if "superior" in name_lower: return 5
	if "greater" in name_lower: return 4
	if "standard" in name_lower: return 3
	if "lesser" in name_lower: return 2
	if "minor" in name_lower: return 1
	# Default to tier 1 for consumables with no tier indicator
	return 1

func _is_tier_based_consumable(item_type: String) -> bool:
	"""Check if item type uses the tier system for scaling"""
	# Health, mana, stamina, energy potions and scrolls use tier-based values
	if item_type in ["health_potion", "mana_potion", "stamina_potion", "energy_potion"]:
		return true
	# Scrolls also use tier system
	if item_type.begins_with("scroll_"):
		return true
	return false

func _indent_new_messages(messages: Array, from_index: int, indent: String) -> void:
	"""Add indentation prefix to all messages added since from_index."""
	for i in range(from_index, messages.size()):
		if messages[i].strip_edges() != "":
			messages[i] = indent + messages[i]

func _indent_multiline(text: String, indent: String) -> String:
	"""Indent each non-empty line of a multi-line string."""
	var lines = text.split("\n")
	var result = []
	for line in lines:
		if line.strip_edges() != "":
			result.append(indent + line)
		else:
			result.append(line)
	return "\n".join(result)

func _apply_combat_wear(character, messages: Array):
	"""~30% chance per fight to apply 1-3 wear to one random equipped item."""
	if randf() >= 0.30:
		return
	var slots = ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]
	slots.shuffle()
	for slot in slots:
		var result = character.damage_equipment(slot, randi_range(1, 3))
		if result.success:
			if result.new_wear >= 75:
				messages.append("[color=#FFA500]Your %s is badly worn! (%d%%)[/color]" % [result.item_name, result.new_wear])
			elif result.new_wear >= 50:
				messages.append("[color=#FFFF00]Your %s took some wear. (%d%%)[/color]" % [result.item_name, result.new_wear])
			break  # Only 1 item per fight

func _ready():
	print("Combat Manager initialized")

func start_combat(peer_id: int, character: Character, monster: Dictionary) -> Dictionary:
	"""Initialize a new combat encounter"""

	# Check for ambusher ability (first attack always crits)
	var monster_abilities = monster.get("abilities", [])
	var ambusher_active = ABILITY_AMBUSHER in monster_abilities

	# === INITIATIVE CHECK ===
	# Base: 5-25% from monster speed (static, doesn't scale with level)
	# Beyond-optimal bonus: when player fights past their optimal XP zone, initiative rises
	# Tier bonus: fighting above your tier is very dangerous (+10% per tier)
	# DEX penalty: logarithmic reduction from player dexterity
	var player_dex = character.get_effective_stat("dexterity")
	var companion_speed = int(character.get_companion_bonus("speed")) if character.has_active_companion() else 0
	var monster_speed = monster.get("speed", 10)
	var speed_rating = clampf(float(monster_speed) / 50.0, 0.0, 1.0)
	var base_initiative = 5.0 + speed_rating * 20.0
	# Beyond-optimal zone bonus: initiative rises when player pushes past their XP sweet spot
	var init_level_diff = monster.get("level", 1) - character.level
	if init_level_diff > 0:
		# Optimal ceiling matches the same-tier XP bonus cap formula
		var reference_gap = 10.0 + float(character.level) * 0.05
		var optimal_ceiling = reference_gap * 2.0
		if init_level_diff > optimal_ceiling:
			base_initiative += minf(15.0, (init_level_diff - optimal_ceiling) * 0.5)
	# Cross-tier bonus: fighting above your tier is very dangerous
	var init_player_tier = _get_tier_for_level(character.level)
	var init_monster_tier = _get_tier_for_level(monster.get("level", 1))
	var init_tier_diff = max(0, init_monster_tier - init_player_tier)
	if init_tier_diff > 0:
		base_initiative += init_tier_diff * 10.0
	var effective_dex = float(player_dex) + float(companion_speed) / 2.0
	var dex_penalty = 2.0 * log(maxf(1.0, effective_dex / 10.0)) / log(2.0)
	var monster_initiative_chance = int(base_initiative - dex_penalty)
	if ambusher_active:
		monster_initiative_chance += 8
	monster_initiative_chance = clampi(monster_initiative_chance, 5, 55)

	var init_roll = randi() % 100
	var monster_goes_first = monster_initiative_chance > 0 and init_roll < monster_initiative_chance

	# Handle disguise ability - monster appears weaker initially
	var disguise_active = ABILITY_DISGUISE in monster_abilities
	var true_stats = {}
	if disguise_active:
		# Store true stats for reveal later
		true_stats = {
			"max_hp": monster.max_hp,
			"current_hp": monster.current_hp,
			"strength": monster.strength,
			"defense": monster.defense,
			"name": monster.name
		}
		# Show weakened stats initially (50%)
		monster.max_hp = max(10, int(monster.max_hp * 0.5))
		monster.current_hp = monster.max_hp
		monster.strength = max(5, int(monster.strength * 0.5))
		monster.defense = max(3, int(monster.defense * 0.5))

	# Create combat state
	var combat_state = {
		"peer_id": peer_id,
		"character": character,
		"monster": monster,
		"round": 1,
		"player_can_act": not monster_goes_first,  # Monster may act first!
		"combat_log": [],
		"started_at": Time.get_ticks_msec(),
		"outsmart_failed": false,  # Can only attempt outsmart once per combat
		# Monster ability tracking
		"ambusher_active": ambusher_active,  # Monster's first attack crits
		"monster_went_first": monster_goes_first,  # Track for display
		# Note: Poison is now tracked on character (poison_active, poison_damage, poison_turns_remaining)
		"cc_resistance": 0,  # Increases each time CC (stun/paralyze) lands on monster
		"enrage_stacks": 0,  # Damage bonus per round
		"thorns_damage": 0,  # Damage reflected on hit
		"curse_applied": false,  # Stat curse active
		"disarm_applied": false,  # Weapon damage reduced
		"summoner_triggered": false,  # Already called reinforcements
		# Disguise ability tracking
		"disguise_active": disguise_active,
		"disguise_true_stats": true_stats,
		"disguise_revealed": false,
		# Damage tracking for death screen
		"total_damage_dealt": 0,
		"total_damage_taken": 0,
		"player_hp_at_start": character.current_hp,
		"pickpocket_count": 0,
		"pickpocket_max": randi_range(1, 3)  # Monster has 1-3 pockets of salvage essence
	}

	active_combats[peer_id] = combat_state

	# Mark character as in combat and reset per-combat flags
	character.in_combat = true
	character.reset_combat_flags()  # Reset Dwarf Last Stand etc.

	# Check for forcefield persistent buff (from scrolls) and apply it
	var forcefield_buff = character.get_buff_value("forcefield")
	if forcefield_buff > 0:
		combat_state["forcefield_shield"] = forcefield_buff

	# Check for other scroll buffs that affect combat
	var lifesteal_buff = character.get_buff_value("lifesteal")
	if lifesteal_buff > 0:
		combat_state["lifesteal_percent"] = lifesteal_buff

	var thorns_buff = character.get_buff_value("thorns")
	if thorns_buff > 0:
		combat_state["player_thorns"] = thorns_buff

	var crit_buff = character.get_buff_value("crit_chance")
	if crit_buff > 0:
		combat_state["crit_bonus"] = crit_buff

	# === COMPANION PASSIVE ABILITIES ===
	# Apply passive companion abilities at combat start (using monster-specific abilities)
	if character.has_active_companion() and drop_tables:
		var companion = character.get_active_companion()
		var companion_level = companion.get("level", 1)
		var monster_type = companion.get("monster_type", "")
		var variant_mult = character.get_variant_stat_multiplier()
		var companion_sub_tier = companion.get("sub_tier", 1)
		var companion_abilities = drop_tables.get_monster_companion_abilities(monster_type, companion_level, variant_mult, companion_sub_tier)
		# Store for use by active/threshold handlers later
		combat_state["companion_abilities"] = companion_abilities

		# Apply passive abilities (values already scaled by level + variant + sub-tier)
		if not companion_abilities.passive.is_empty():
			var passive = companion_abilities.passive
			if passive.has("effect") and passive.has("value"):
				_apply_companion_passive_effect(combat_state, character, passive.effect, passive.value)
			if passive.has("effect2") and passive.has("value2"):
				_apply_companion_passive_effect(combat_state, character, passive.effect2, passive.value2)
			if passive.has("effect3") and passive.has("value3"):
				_apply_companion_passive_effect(combat_state, character, passive.effect3, passive.value3)

		# Track that threshold ability hasn't triggered yet
		combat_state["companion_threshold_triggered"] = false

	# === APPLY COMPANION HP/MANA BONUSES ===
	# Base companion bonuses + passive ability bonuses, applied as temporary max HP/mana boost
	if character.has_active_companion():
		var comp_hp_bonus = int(character.get_companion_bonus("hp_bonus")) + combat_state.get("companion_hp_bonus", 0)
		if comp_hp_bonus > 0:
			var hp_boost = max(1, int(character.get_total_max_hp() * comp_hp_bonus / 100.0))
			character.max_hp += hp_boost
			character.current_hp += hp_boost
			combat_state["companion_hp_boost_applied"] = hp_boost

		# Resource bonus: Apply mana_bonus to player's primary resource (not just mana)
		var comp_resource_bonus = int(character.get_companion_bonus("mana_bonus")) + combat_state.get("companion_mana_bonus", 0)
		if comp_resource_bonus > 0:
			var class_path = character.get_class_path()
			match class_path:
				"warrior":
					var boost = max(1, int(character.get_total_max_stamina() * comp_resource_bonus / 100.0))
					character.max_stamina += boost
					character.current_stamina = mini(character.current_stamina + boost, character.get_total_max_stamina())
					combat_state["companion_resource_boost_applied"] = boost
					combat_state["companion_resource_boost_type"] = "stamina"
				"mage":
					var boost = max(1, int(character.get_total_max_mana() * comp_resource_bonus / 100.0))
					character.max_mana += boost
					character.current_mana = mini(character.current_mana + boost, character.get_total_max_mana())
					combat_state["companion_resource_boost_applied"] = boost
					combat_state["companion_resource_boost_type"] = "mana"
				"trickster":
					var boost = max(1, int(character.get_total_max_energy() * comp_resource_bonus / 100.0))
					character.max_energy += boost
					character.current_energy = mini(character.current_energy + boost, character.get_total_max_energy())
					combat_state["companion_resource_boost_applied"] = boost
					combat_state["companion_resource_boost_type"] = "energy"

		# Store base wisdom bonus for use in resist checks
		var comp_wisdom_bonus = int(character.get_companion_bonus("wisdom_bonus")) + combat_state.get("companion_wisdom_bonus", 0)
		if comp_wisdom_bonus > 0:
			combat_state["companion_wisdom_bonus"] = comp_wisdom_bonus

	# Generate initial combat message
	var msg = generate_combat_start_message(character, monster)

	# Add XP zone hint - shows the player where they stand relative to optimal XP range
	var hint_level_diff = monster.get("level", 1) - character.level
	var hint_player_tier = _get_tier_for_level(character.level)
	var hint_monster_tier = _get_tier_for_level(monster.get("level", 1))
	var hint_tier_diff = hint_monster_tier - hint_player_tier
	if hint_tier_diff > 0:
		var tier_xp_mult = int(pow(2.0, hint_tier_diff))
		msg += "\n[color=#FF00FF]⚠ TIER +%d — Extreme danger! (%dx XP if you survive)[/color]" % [hint_tier_diff, tier_xp_mult]
	elif hint_level_diff > 0 and hint_tier_diff == 0:
		# Calculate same-tier XP bonus to show the player
		var hint_ref_gap = 10.0 + float(character.level) * 0.05
		var hint_gap_ratio = float(hint_level_diff) / hint_ref_gap
		var hint_xp_mult = 1.0 + minf(1.0, sqrt(hint_gap_ratio) * 0.7)
		var hint_bonus_pct = int((hint_xp_mult - 1.0) * 100)
		var hint_optimal_ceiling = hint_ref_gap * 2.0
		if hint_level_diff > hint_optimal_ceiling:
			# Past optimal zone - XP bonus is capped, danger increases
			msg += "\n[color=#FF6600]⚠ Beyond optimal range (+%d%% XP cap) — beware![/color]" % hint_bonus_pct
		elif hint_bonus_pct >= 10:
			msg += "\n[color=#FFD700]Worthy challenge (+%d%% XP bonus)[/color]" % hint_bonus_pct
	elif hint_level_diff < -5 and hint_tier_diff == 0:
		# Fighting below level
		var under_gap = abs(hint_level_diff)
		var penalty_threshold = 5.0 + float(character.level) * 0.03
		if under_gap > penalty_threshold:
			var excess = under_gap - penalty_threshold
			var penalty = minf(0.6, excess * 0.03)
			var penalty_pct = int(penalty * 100)
			if penalty_pct >= 10:
				msg += "\n[color=#808080]Weak foe (-%d%% XP)[/color]" % penalty_pct

	combat_state.combat_log.append(msg)

	# === MONSTER FIRST STRIKE ===
	# If monster won initiative, they attack immediately
	var first_strike_msg = ""
	if monster_goes_first:
		first_strike_msg = "\n[color=#444444]─────────────────────────────[/color]"
		first_strike_msg += "\n         [color=#FF4444][b]⚔ The %s strikes first! ⚔[/b][/color]" % monster.name
		var monster_result = process_monster_turn(combat_state)
		first_strike_msg += "\n" + _indent_multiline(monster_result.get("message", ""), "         ")
		first_strike_msg += "\n[color=#444444]─────────────────────────────[/color]"

		# Check if player died from first strike
		if character.current_hp <= 0:
			var death_extra = ""
			var death_base_end = msg.find("![/color]")
			if death_base_end != -1:
				death_extra = msg.substr(death_base_end + 9)
			death_extra += first_strike_msg + "\n[color=#FF0000]You have been defeated![/color]"
			return {
				"success": true,
				"message": msg + first_strike_msg + "\n[color=#FF0000]You have been defeated![/color]",
				"extra_combat_text": death_extra,
				"combat_state": get_combat_display(peer_id),
				"combat_ended": true,
				"victory": false
			}

		# Player can now act
		combat_state.player_can_act = true

	# Build extra text (XP hints + first strike) for client-side art rendering
	# The client rebuilds the encounter text locally, so these get sent separately
	var extra_combat_text = ""
	# Extract XP hint from msg (everything after the base encounter line)
	var base_encounter_end = msg.find("![/color]")
	if base_encounter_end != -1:
		var after_encounter = msg.substr(base_encounter_end + 9)  # Skip past "![/color]"
		if after_encounter.strip_edges() != "":
			extra_combat_text += after_encounter
	if first_strike_msg != "":
		extra_combat_text += first_strike_msg

	return {
		"success": true,
		"message": msg + first_strike_msg,
		"extra_combat_text": extra_combat_text,
		"combat_state": get_combat_display(peer_id)
	}

func get_active_combat(peer_id: int) -> Dictionary:
	"""Get the active combat state for a peer, or empty dict if not in combat"""
	if active_combats.has(peer_id):
		return active_combats[peer_id]
	return {}

func process_combat_command(peer_id: int, command: String) -> Dictionary:
	"""Process a combat command from player"""

	if not active_combats.has(peer_id):
		return {"success": false, "message": "You are not in combat!"}

	var parts = command.to_lower().split(" ", false)
	var cmd = parts[0] if parts.size() > 0 else ""
	var arg = parts[1] if parts.size() > 1 else ""

	var action: CombatAction

	match cmd:
		"attack", "a":
			action = CombatAction.ATTACK
		"flee", "f", "run":
			action = CombatAction.FLEE
		"special", "s":
			action = CombatAction.SPECIAL
		"outsmart", "o":
			action = CombatAction.OUTSMART
		_:
			# Check if it's an ability command
			if cmd in MAGE_ABILITY_COMMANDS or cmd in WARRIOR_ABILITY_COMMANDS or cmd in TRICKSTER_ABILITY_COMMANDS or cmd in UNIVERSAL_ABILITY_COMMANDS:
				return process_ability_command(peer_id, cmd, arg)
			return {"success": false, "message": "Unknown combat command! Use: attack, flee, outsmart, or abilities"}

	return process_combat_action(peer_id, action)

func process_combat_action(peer_id: int, action: CombatAction) -> Dictionary:
	"""Process a player's combat action"""
	
	if not active_combats.has(peer_id):
		return {"success": false, "message": "You are not in combat!"}
	
	var combat = active_combats[peer_id]
	
	if not combat.player_can_act:
		return {"success": false, "message": "Wait for your turn!"}
	
	var result = {}

	# Track monster HP before player action for damage tracking
	var monster_hp_before = combat.monster.current_hp
	var player_hp_before = combat.character.current_hp

	match action:
		CombatAction.ATTACK:
			result = process_attack(combat)
		CombatAction.FLEE:
			result = process_flee(combat)
		CombatAction.SPECIAL:
			result = process_special(combat)
		CombatAction.OUTSMART:
			result = process_outsmart(combat)

	# Track damage dealt to monster this turn
	var damage_dealt_this_turn = max(0, monster_hp_before - combat.monster.current_hp)
	combat["total_damage_dealt"] = combat.get("total_damage_dealt", 0) + damage_dealt_this_turn
	# Track any self-damage from player action (backfire, thorns reflection)
	var self_damage = max(0, player_hp_before - combat.character.current_hp)
	combat["total_damage_taken"] = combat.get("total_damage_taken", 0) + self_damage

	# Check if combat ended
	if result.has("combat_ended") and result.combat_ended:
		end_combat(peer_id, result.get("victory", false))
		return result

	# Monster's turn (if still alive)
	if combat.monster.current_hp > 0:
		var player_hp_before_monster = combat.character.current_hp
		var monster_hp_before_turn = combat.monster.current_hp
		var monster_result = process_monster_turn(combat)
		result.messages.append("[color=#444444]─────────────────────────────[/color]")
		var monster_msg = monster_result.get("message", "")
		result.messages.append(_indent_multiline(monster_msg, "         "))
		result.messages.append("[color=#444444]─────────────────────────────[/color]")
		# Track damage taken from monster
		var damage_taken_this_turn = max(0, player_hp_before_monster - combat.character.current_hp)
		combat["total_damage_taken"] = combat.get("total_damage_taken", 0) + damage_taken_this_turn
		# Track any damage dealt by reflect/thorns during monster turn
		var reflect_damage = max(0, monster_hp_before_turn - combat.monster.current_hp)
		combat["total_damage_dealt"] = combat.get("total_damage_dealt", 0) + reflect_damage

		# Check if monster fled (Coward, Flee Attack, or Shrieker summon)
		if monster_result.get("monster_fled", false):
			result.combat_ended = true
			result.victory = false
			result["monster_fled"] = true
			result["summon_next_fight"] = monster_result.get("summon_next_fight", "")
			result["monster_level"] = monster_result.get("monster_level", combat.monster.level)
			end_combat(peer_id, false)
			return result

		# Check if player died
		# Note: Don't call end_combat here - let server check eternal status first
		if combat.character.current_hp <= 0:
			result.combat_ended = true
			result.victory = false
			result.monster_name = "%s (Lvl %d)" % [combat.monster.name, combat.monster.level]
			result.monster_level = combat.monster.level
			result.messages.append("[color=#FF0000]You have been defeated![/color]")
			return result
	
	# Increment round
	combat.round += 1
	combat.player_can_act = true

	# === DISGUISE REVEAL (after 2 rounds) ===
	if combat.get("disguise_active", false) and not combat.get("disguise_revealed", false) and combat.round >= 3:
		var true_stats = combat.get("disguise_true_stats", {})
		if not true_stats.is_empty():
			combat["disguise_revealed"] = true
			var monster = combat.monster
			# Calculate how much damage was dealt to disguised form
			var damage_dealt = combat.get("disguise_true_stats", {}).get("max_hp", monster.max_hp) * 0.5 - monster.current_hp
			# Restore true stats
			monster.max_hp = true_stats.max_hp
			monster.strength = true_stats.strength
			monster.defense = true_stats.defense
			# Set current HP to true max minus proportional damage
			monster.current_hp = max(1, true_stats.max_hp - int(damage_dealt * 2))
			result.messages.append("[color=#FF0000]The %s reveals its true form![/color]" % monster.name)
			result.messages.append("[color=#FF4444]It was much stronger than it appeared![/color]")

	# Tick buff durations at end of round and notify of expired buffs
	var expired_buffs = combat.character.tick_buffs()
	for buff in expired_buffs:
		var buff_name = buff.type.capitalize()
		result.messages.append("[color=#808080]Your %s buff has worn off.[/color]" % buff_name)

	return result

func process_attack(combat: Dictionary) -> Dictionary:
	"""Process player attack action with monster ability interactions"""
	var character = combat.character
	var monster = combat.monster
	var abilities = monster.get("abilities", [])
	var messages = []

	# === EQUIPMENT-BASED RESOURCE REGENERATION (at start of player turn) ===
	_apply_gear_resource_regen(character, messages)

	# === BASE MANA REGENERATION FOR MAGES ===
	# Mages regenerate 2% max mana per round (Sage gets 3%)
	var is_mage_class = character.class_type in ["Wizard", "Sorcerer", "Sage"]
	if is_mage_class and character.current_mana < character.get_total_max_mana():
		var base_mana_regen_pct = 0.02
		if character.class_type == "Sage":
			base_mana_regen_pct = 0.03
		var base_regen = max(1, int(character.get_total_max_mana() * base_mana_regen_pct))
		var old_mana = character.current_mana
		character.current_mana = mini(character.get_total_max_mana(), character.current_mana + base_regen)
		var actual_regen = character.current_mana - old_mana
		if actual_regen > 0:
			messages.append("[color=#9999FF]Arcane focus restores %d mana.[/color]" % actual_regen)

	# === COMPANION RESOURCE REGENERATION ===
	var _cr = messages.size()
	_apply_companion_resource_regen(combat, character, messages)
	_indent_new_messages(messages, _cr, "   ")

	# === MONSTER DOT EFFECTS (bleed/poison from companion abilities) ===
	var _cd = messages.size()
	_process_monster_dots(combat, monster, messages)
	_indent_new_messages(messages, _cd, "   ")

	# === POISON & BLIND TICK (at start of player turn) ===
	_process_status_ticks(character, messages)

	# === BLEED TICK (stacking DoT from Bleed ability) ===
	var bleed_stacks = combat.get("player_bleed_stacks", 0)
	if bleed_stacks > 0:
		var bleed_dmg_per_stack = combat.get("player_bleed_damage", 5)
		var total_bleed = bleed_stacks * bleed_dmg_per_stack
		character.current_hp -= total_bleed
		character.current_hp = max(1, character.current_hp)  # Bleed can't kill either
		messages.append("[color=#FF4444]Bleeding deals [color=#FF8800]%d[/color] damage! (%d stacks)[/color]" % [total_bleed, bleed_stacks])

	# === CHARM EFFECT (player attacks themselves) ===
	if combat.get("player_charmed", false):
		combat["player_charmed"] = false  # Only lasts one turn
		var self_damage = max(1, int(character.get_total_attack() * 0.5))  # 50% of player attack
		character.current_hp -= self_damage
		character.current_hp = max(1, character.current_hp)  # Can't kill yourself
		messages.append("[color=#FF00FF]You are charmed and attack yourself for [color=#FF8800]%d[/color] damage![/color]" % self_damage)
		combat.player_can_act = false
		return {"success": true, "messages": messages, "combat_ended": false}

	# Check for vanish (auto-crit from Trickster ability)
	var is_vanished = combat.get("vanished", false)
	if is_vanished:
		combat.erase("vanished")

	# Hit chance: 75% base + (player DEX - monster speed/2) per point
	# Monster speed halved so higher speeds don't tank early-game accuracy
	# DEX makes it easier to hit enemies, Vanish guarantees hit
	var player_dex = character.get_effective_stat("dexterity")
	var monster_speed = monster.get("speed", 10)  # Use monster speed as DEX equivalent
	var dex_diff = player_dex - int(monster_speed / 2.0)
	var hit_chance = 75 + dex_diff
	# Companion speed bonus improves hit chance
	var comp_speed_hit = int(character.get_companion_bonus("speed")) if character.has_active_companion() else 0
	comp_speed_hit += combat.get("companion_speed_bonus", 0)
	hit_chance += int(comp_speed_hit / 3.0)

	# Apply blind debuff (persistent status effect)
	if character.blind_active:
		var blind_penalty = 30  # 30% hit chance reduction when blinded
		hit_chance -= blind_penalty

	hit_chance = clamp(hit_chance, 30, 95)  # 30% minimum (can be reduced by blind), 95% maximum

	# Ethereal ability: 50% dodge chance for monster
	var ethereal_dodge = ABILITY_ETHEREAL in abilities and not is_vanished
	if ethereal_dodge and randi() % 100 < 50:
		messages.append("[color=#FF00FF]Your attack passes through the ethereal %s![/color]" % monster.name)
		combat.player_can_act = false
		return {"success": true, "messages": messages, "combat_ended": false}

	var hit_roll = randi() % 100

	# === CLASS PASSIVE: Paladin Divine Favor ===
	# Heal 3% max HP per combat round
	var passive = character.get_class_passive()
	var effects = passive.get("effects", {})
	if effects.has("combat_regen_percent"):
		var regen_amount = max(1, int(character.get_total_max_hp() * effects.get("combat_regen_percent", 0)))
		var actual_heal = character.heal(regen_amount)
		if actual_heal > 0:
			messages.append("[color=#FFD700]Divine Favor heals %d HP.[/color]" % actual_heal)

	# === COMPANION BONUS: HP regeneration ===
	var companion_regen = character.get_companion_bonus("hp_regen")
	if companion_regen > 0:
		var regen_amount = max(1, int(character.get_total_max_hp() * companion_regen / 100.0))
		var actual_heal = character.heal(regen_amount)
		if actual_heal > 0:
			messages.append("[color=#00FFFF]Companion heals %d HP.[/color]" % actual_heal)

	if is_vanished or hit_roll < hit_chance:
		# Hit!
		var damage_result = calculate_damage(character, monster, combat)
		var damage = damage_result.damage
		var is_crit = damage_result.is_crit
		var passive_messages = damage_result.get("passive_messages", [])
		var backfire_damage = damage_result.get("backfire_damage", 0)

		# Apply analyze bonus (+10% from Analyze ability)
		var analyze_bonus = combat.get("analyze_bonus", 0)
		if analyze_bonus > 0:
			damage = int(damage * (1.0 + analyze_bonus / 100.0))

		# Apply vanish bonus (extra 1.5x on top of any crit)
		if is_vanished:
			damage = int(damage * 1.5)
			messages.append("[color=#FFD700]You strike from the shadows![/color]")

		# Show passive messages (Blood Rage, Chaos Magic, etc.)
		for msg in passive_messages:
			messages.append(msg)

		# Handle Sorcerer backfire damage
		if backfire_damage > 0:
			character.current_hp -= backfire_damage
			character.current_hp = max(1, character.current_hp)
			messages.append("[color=#9400D3]Wild magic burns you for %d damage![/color]" % backfire_damage)

		monster.current_hp -= damage
		monster.current_hp = max(0, monster.current_hp)

		# Use class-specific attack description
		var attack_desc = character.get_class_attack_description(damage, monster.name, is_crit)
		messages.append(attack_desc)

		# === TRICKSTER DOUBLE STRIKE ===
		# Tricksters have 25% chance for a bonus attack at 50% damage
		var is_trickster = character.class_type in ["Thief", "Ranger", "Ninja"]
		if is_trickster and monster.current_hp > 0 and randi() % 100 < 25:
			var second_damage = int(damage * 0.5)
			monster.current_hp -= second_damage
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#66FF66]Quick Strike! +%d bonus damage![/color]" % second_damage)

		# Lifesteal from scroll/potion buff
		var lifesteal_percent = combat.get("lifesteal_percent", 0)
		if lifesteal_percent > 0:
			var heal_amount = max(1, int(damage * lifesteal_percent / 100.0))
			var actual_heal = character.heal(heal_amount)
			if actual_heal > 0:
				messages.append("[color=#00FF00]Lifesteal heals you for %d HP![/color]" % actual_heal)

		# === EQUIPMENT PROC EFFECTS ===
		var procs = character.get_equipment_procs()

		# Lifesteal from equipment
		if procs.lifesteal > 0:
			var proc_heal = max(1, int(damage * procs.lifesteal / 100.0))
			var actual_proc_heal = character.heal(proc_heal)
			if actual_proc_heal > 0:
				messages.append("[color=#FF00FF]Vampiric gear drains %d HP![/color]" % actual_proc_heal)

		# Lifesteal from companion bonus (Vampire, Death Incarnate, Entropy, etc.)
		var companion_lifesteal = character.get_companion_bonus("lifesteal")
		# Also check for companion passive lifesteal from abilities
		companion_lifesteal += combat.get("companion_lifesteal_bonus", 0)
		# Also check for companion lifesteal buff from threshold abilities
		var lifesteal_buff = combat.get("companion_lifesteal_buff", 0)
		if lifesteal_buff > 0:
			companion_lifesteal += lifesteal_buff
			# Decrement duration
			var buff_duration = combat.get("companion_lifesteal_buff_duration", 0)
			if buff_duration > 0:
				combat["companion_lifesteal_buff_duration"] = buff_duration - 1
				if buff_duration - 1 <= 0:
					combat["companion_lifesteal_buff"] = 0
		if companion_lifesteal > 0:
			var companion_heal = max(1, int(damage * companion_lifesteal / 100.0))
			var actual_companion_heal = character.heal(companion_heal)
			if actual_companion_heal > 0:
				var companion = character.get_active_companion()
				var comp_name = companion.get("name", "Companion") if companion else "Companion"
				messages.append("[color=#00FFFF]%s drains %d HP for you![/color]" % [comp_name, actual_companion_heal])

		# Shocking proc (bonus lightning damage on hit)
		if procs.shocking.chance > 0 and procs.shocking.value > 0:
			if randi() % 100 < procs.shocking.chance:
				var lightning_damage = max(1, int(damage * procs.shocking.value / 100.0))
				monster.current_hp -= lightning_damage
				monster.current_hp = max(0, monster.current_hp)
				messages.append("[color=#00FFFF]>> Shocking strikes for %d bonus damage![/color]" % lightning_damage)

		# Execute proc (bonus damage when enemy below 30% HP)
		if procs.execute.chance > 0 and procs.execute.value > 0:
			var monster_hp_percent = float(monster.current_hp) / float(monster.max_hp)
			if monster_hp_percent <= 0.30 and randi() % 100 < procs.execute.chance:
				var execute_damage = max(1, int(damage * procs.execute.value / 100.0))
				monster.current_hp -= execute_damage
				monster.current_hp = max(0, monster.current_hp)
				messages.append("[color=#FF4444]ðŸ’€ Execute strikes for %d bonus damage![/color]" % execute_damage)

		# === COMPANION ATTACK ===
		var _ca = messages.size()
		_process_companion_attack(combat, messages)
		_indent_new_messages(messages, _ca, "   ")

		# Thorns ability: reflect damage back to attacker
		if ABILITY_THORNS in abilities:
			var thorn_damage = max(1, int(damage * 0.25))
			character.current_hp -= thorn_damage
			character.current_hp = max(1, character.current_hp)
			messages.append("[color=#FF4444]Thorns deal [color=#FF8800]%d[/color] damage to you![/color]" % thorn_damage)

		# Damage reflect ability: reflect 25% of damage
		if ABILITY_DAMAGE_REFLECT in abilities:
			var reflect_damage = max(1, int(damage * 0.25))
			character.current_hp -= reflect_damage
			character.current_hp = max(1, character.current_hp)
			messages.append("[color=#FF00FF]The %s reflects [color=#FF8800]%d[/color] damage![/color]" % [monster.name, reflect_damage])

		if monster.current_hp <= 0:
			# Monster defeated - process victory with ability bonuses
			return _process_victory_with_abilities(combat, messages)
	else:
		# Miss
		messages.append("[color=#FF4444]You swing at the %s but miss![/color]" % monster.name)

	combat.player_can_act = false

	return {
		"success": true,
		"messages": messages,
		"combat_ended": false
	}

func _process_victory_with_abilities(combat: Dictionary, messages: Array) -> Dictionary:
	"""Process monster defeat with all ability effects (death message, bonuses, curses)"""
	var victory_msg_start = messages.size()
	var character = combat.character
	var monster = combat.monster
	var abilities = monster.get("abilities", [])

	# Custom death message
	var death_msg = monster.get("death_message", "")
	if death_msg != "":
		messages.append("[color=#FFD700]%s[/color]" % death_msg)
	else:
		messages.append("[color=#00FF00]The %s is defeated![/color]" % monster.name)

	# Death curse ability: deal damage on death (nerfed from 25% to 10%, reduced by WIS)
	# Undead racial: immune to death curses
	if ABILITY_DEATH_CURSE in abilities:
		if character.is_immune_to_death_curse():
			messages.append("[color=#708090]The %s's death curse has no effect on your undead form![/color]" % monster.name)
		else:
			var base_curse_damage = int(monster.max_hp * 0.10)  # Reduced from 25% to 10%
			# WIS provides ability resistance: reduces damage by min(50%, WIS/200)
			var player_wis = character.get_effective_stat("wisdom") + combat.get("companion_wisdom_bonus", 0)
			var wis_reduction = minf(0.50, float(player_wis) / 200.0)  # Max 50% reduction at WIS 100+
			var curse_damage = int(base_curse_damage * (1.0 - wis_reduction))
			curse_damage = max(1, curse_damage)
			character.current_hp -= curse_damage
			character.current_hp = max(1, character.current_hp)
			if wis_reduction > 0:
				messages.append("[color=#FF00FF]The %s's death curse deals [color=#FF8800]%d[/color] damage! (WIS resists %d%%)[/color]" % [monster.name, curse_damage, int(wis_reduction * 100)])
			else:
				messages.append("[color=#FF00FF]The %s's death curse deals [color=#FF8800]%d[/color] damage![/color]" % [monster.name, curse_damage])

	# Calculate XP with smooth level-based scaling (no tier cliffs)
	var base_xp = monster.experience_reward
	var xp_level_diff = monster.level - character.level
	var xp_multiplier = 1.0

	# Tier info for display flavor
	var xp_player_tier = _get_tier_for_level(character.level)
	var xp_monster_tier = _get_tier_for_level(monster.level)
	var xp_tier_diff = xp_monster_tier - xp_player_tier

	# Unified XP scaling: smooth sqrt curve based on level difference
	# No tier cliffs — bonus grows continuously with level gap
	# reference_gap scales with player level: 10 at lv1, 15 at lv100, 35 at lv500
	if xp_level_diff > 0:
		var reference_gap = 10.0 + float(character.level) * 0.05
		var gap_ratio = float(xp_level_diff) / reference_gap
		# sqrt provides diminishing returns: +70% at gap_ratio 1, +140% at 4, +210% at 9
		xp_multiplier = 1.0 + sqrt(gap_ratio) * 0.7
		var bonus_pct = int((xp_multiplier - 1.0) * 100)
		if xp_tier_diff > 0:
			messages.append("[color=#FF00FF]* TIER CHALLENGE: +%d%% XP! *[/color]" % bonus_pct)
		elif bonus_pct >= 5:
			messages.append("[color=#FFD700]Challenge bonus: +%d%% XP[/color]" % bonus_pct)
	elif xp_level_diff < 0:
		# Downlevel penalty — small grace zone, then gradual reduction
		var under_gap = abs(xp_level_diff)
		var penalty_threshold = 5.0 + float(character.level) * 0.03  # Grace zone grows with level
		if under_gap > penalty_threshold:
			var excess = under_gap - penalty_threshold
			var penalty = minf(0.6, excess * 0.03)  # -3% per level beyond threshold
			xp_multiplier = maxf(0.4, 1.0 - penalty)  # Floor at 40% XP
			var penalty_pct = int((1.0 - xp_multiplier) * 100)
			if penalty_pct >= 10:
				messages.append("[color=#808080]Weak foe: -%d%% XP[/color]" % penalty_pct)

	var final_xp = int(base_xp * xp_multiplier * 1.10)  # +10% XP boost

	# Gambit kill bonus: +1 gem awarded later
	var gambit_kill = combat.get("gambit_kill", false)

	# Easy prey: reduced XP
	if ABILITY_EASY_PREY in abilities:
		final_xp = int(final_xp * 0.5)

	# === CLASS PASSIVE: Ranger Hunter's Mark ===
	# +30% XP from kills
	var passive = character.get_class_passive()
	var passive_effects = passive.get("effects", {})
	if passive_effects.has("xp_bonus"):
		var xp_mult = 1.0 + passive_effects.get("xp_bonus", 0)
		final_xp = int(final_xp * xp_mult)
		messages.append("[color=#228B22]Hunter's Mark: +%d%% XP![/color]" % int(passive_effects.get("xp_bonus", 0) * 100))

	var effective_bonus_pct = int((xp_multiplier - 1.0) * 100)
	if effective_bonus_pct > 0:
		messages.append("[color=#FFD700]You gain %d experience! [color=#00FFFF](+%d%% bonus)[/color][/color]" % [final_xp, effective_bonus_pct])
	else:
		messages.append("[color=#FFD700]You gain %d experience![/color]" % final_xp)

	# Award experience
	character.add_experience(final_xp)

	# === COMPANION XP DISTRIBUTION ===
	# Active companions gain 10% of monster XP
	if character.has_active_companion():
		var companion_xp = max(1, int(base_xp * 0.10))
		var companion_result = character.add_companion_xp(companion_xp)
		character.increment_companion_battles()
		if companion_result.leveled_up:
			var companion = character.get_active_companion()
			messages.append("[color=#00FFFF]* %s leveled up to %d! *[/color]" % [companion.get("name", "Companion"), companion_result.new_level])
			# Notify of unlocked abilities
			for ability_level in companion_result.abilities_unlocked:
				if drop_tables:
					var tier = companion.get("tier", 1)
					var ability = drop_tables.get_companion_ability(tier, ability_level)
					if not ability.is_empty():
						messages.append("[color=#FFD700]* New ability unlocked: %s! *[/color]" % ability.get("name", "Unknown"))

	# Normal gem drops (from high-level monsters) → Monster Gem material
	var gems_earned = roll_gem_drops(monster, character)
	if gems_earned > 0:
		character.add_crafting_material("monster_gem", gems_earned)
		messages.append("[color=#00FFFF]+ + [/color][color=#FF00FF]You found %d Monster Gem%s![/color][color=#00FFFF] + +[/color]" % [gems_earned, "s" if gems_earned > 1 else ""])

	# Gambit kill bonus: +1 Monster Gem
	if gambit_kill:
		character.add_crafting_material("monster_gem", 1)
		messages.append("[color=#FFD700]+ Gambit bonus: +1 Monster Gem! +[/color]")

	# Gem Bearer bonus (separate from normal drops, scales with monster level)
	if ABILITY_GEM_BEARER in abilities:
		var monster_level = monster.get("level", 1)
		# Calculate tier bonus based on monster level - scales generously
		var tier_bonus = 0
		if monster_level >= 5000:
			tier_bonus = 15
		elif monster_level >= 2000:
			tier_bonus = 10
		elif monster_level >= 1000:
			tier_bonus = 8
		elif monster_level >= 500:
			tier_bonus = 6
		elif monster_level >= 250:
			tier_bonus = 4
		elif monster_level >= 100:
			tier_bonus = 3
		elif monster_level >= 50:
			tier_bonus = 2
		elif monster_level >= 25:
			tier_bonus = 1

		# Gem Bearer always drops: 2-5 base + tier bonus → Monster Gems
		var bearer_gems = randi_range(2, 5) + tier_bonus
		character.add_crafting_material("monster_gem", bearer_gems)
		gems_earned += bearer_gems
		messages.append("[color=#00FFFF]* The gem bearer's hoard glitters! [/color][color=#FF00FF]+%d Monster Gem%s![/color][color=#00FFFF] *[/color]" % [bearer_gems, "s" if bearer_gems > 1 else ""])

	# Weapon Master ability: 50% chance to drop a weapon with attack bonuses
	if ABILITY_WEAPON_MASTER in abilities and drop_tables != null:
		if randf() < 0.50:  # 50% chance
			var weapon = drop_tables.generate_weapon(monster.level)
			if not weapon.is_empty():
				messages.append("[color=#FF8000]The Weapon Master drops a powerful weapon![/color]")
				messages.append("[color=%s]Dropped: %s (Level %d)[/color]" % [
					_get_rarity_color(weapon.get("rarity", "common")),
					weapon.get("name", "Unknown Weapon"),
					weapon.get("level", 1)
				])
				if not combat.has("extra_drops"):
					combat.extra_drops = []
				combat.extra_drops.append(weapon)
		else:
			messages.append("[color=#AA6666]- The Weapon Master's weapon shatters on death...[/color]")

	# Shield Bearer ability: 50% chance to drop a shield with HP bonuses
	if ABILITY_SHIELD_BEARER in abilities and drop_tables != null:
		if randf() < 0.50:  # 50% chance
			var shield = drop_tables.generate_shield(monster.level)
			if not shield.is_empty():
				messages.append("[color=#00FFFF]The Shield Guardian drops a sturdy shield![/color]")
				messages.append("[color=%s]Dropped: %s (Level %d)[/color]" % [
					_get_rarity_color(shield.get("rarity", "common")),
					shield.get("name", "Unknown Shield"),
					shield.get("level", 1)
				])
				if not combat.has("extra_drops"):
					combat.extra_drops = []
				combat.extra_drops.append(shield)
		else:
			messages.append("[color=#AA6666]- The Shield Guardian's shield crumbles to dust...[/color]")

	# Arcane Hoarder ability: 35% chance to drop mage gear
	if ABILITY_ARCANE_HOARDER in abilities and drop_tables != null:
		if randf() < 0.35:  # 35% chance
			var mage_item = drop_tables.generate_mage_gear(monster.level)
			if not mage_item.is_empty():
				messages.append("[color=#66CCCC]The Arcane Hoarder drops magical equipment![/color]")
				messages.append("[color=%s]Dropped: %s (Level %d)[/color]" % [
					_get_rarity_color(mage_item.get("rarity", "common")),
					mage_item.get("name", "Unknown Item"),
					mage_item.get("level", 1)
				])
				if not combat.has("extra_drops"):
					combat.extra_drops = []
				combat.extra_drops.append(mage_item)
		else:
			messages.append("[color=#AA66AA]- The Arcane Hoarder's magic dissipates...[/color]")

	# Cunning Prey ability: 35% chance to drop trickster gear
	if ABILITY_CUNNING_PREY in abilities and drop_tables != null:
		if randf() < 0.35:  # 35% chance
			var trick_item = drop_tables.generate_trickster_gear(monster.level)
			if not trick_item.is_empty():
				messages.append("[color=#66FF66]The Cunning Prey drops elusive equipment![/color]")
				messages.append("[color=%s]Dropped: %s (Level %d)[/color]" % [
					_get_rarity_color(trick_item.get("rarity", "common")),
					trick_item.get("name", "Unknown Item"),
					trick_item.get("level", 1)
				])
				if not combat.has("extra_drops"):
					combat.extra_drops = []
				combat.extra_drops.append(trick_item)
		else:
			messages.append("[color=#66AA66]- The Cunning Prey's gear vanishes into shadow...[/color]")

	# Warrior Hoarder ability: 35% chance to drop warrior gear
	if ABILITY_WARRIOR_HOARDER in abilities and drop_tables != null:
		if randf() < 0.35:
			var war_item = drop_tables.generate_warrior_gear(monster.level)
			if not war_item.is_empty():
				messages.append("[color=#FF6600]The Warrior Hoarder drops battle-worn gear![/color]")
				messages.append("[color=%s]Dropped: %s (Level %d)[/color]" % [
					_get_rarity_color(war_item.get("rarity", "common")),
					war_item.get("name", "Unknown Item"),
					war_item.get("level", 1)
				])
				if not combat.has("extra_drops"):
					combat.extra_drops = []
				combat.extra_drops.append(war_item)
		else:
			messages.append("[color=#AA8866]- The Warrior Hoarder's armor crumbles...[/color]")

	# Wish granter ability: 10% chance to offer a wish (100% if GM-guaranteed)
	if ABILITY_WISH_GRANTER in abilities:
		var wish_chance = 1.0 if combat.get("gm_wish_guaranteed", false) else 0.10
		if randf() < wish_chance:
			var monster_lethality = monster.get("lethality", 100)
			var wish_options = generate_wish_options(character, monster.level, monster_lethality)
			combat["wish_pending"] = true
			combat["wish_options"] = wish_options
			messages.append("[color=#FFD700]* The %s offers you a WISH! *[/color]" % monster.name)
			messages.append("[color=#FFD700]Choose your reward wisely...[/color]")
		else:
			messages.append("[color=#808080]The %s's magic fades before granting a wish...[/color]" % monster.name)

	# Trophy drops - rare collectibles from powerful monsters
	if drop_tables != null:
		var trophy = drop_tables.roll_trophy_drop(monster.name)
		if not trophy.is_empty():
			var trophy_id = trophy.get("id", "")
			var trophy_name = trophy.get("name", "Unknown Trophy")
			var trophy_desc = trophy.get("description", "")
			var is_first = not character.has_trophy(trophy_id)
			var trophy_count = character.add_trophy(trophy_id, monster.name, monster.level)
			messages.append("[color=#A335EE]===========================================================================[/color]")
			if is_first:
				messages.append("[color=#A335EE]*** NEW TROPHY COLLECTED! ***[/color]")
			else:
				messages.append("[color=#A335EE]* TROPHY DROP! *[/color]")
			messages.append("[color=#FFD700]%s[/color]" % trophy_name)
			messages.append("[color=#808080]%s[/color]" % trophy_desc)
			if trophy_count > 1:
				messages.append("[color=#00FF00]Trophy added! (x%d of this type, %d total)[/color]" % [trophy_count, character.get_trophy_count()])
			else:
				messages.append("[color=#00FF00]Trophy added to your collection! (%d total)[/color]" % character.get_trophy_count())
			messages.append("[color=#A335EE]===========================================================================[/color]")

	# Soul Gem drops - companions (Tier 7+)
	if drop_tables != null:
		var monster_tier = drop_tables.get_tier_for_level(monster.level)
		if monster_tier >= 7:
			var soul_gem = drop_tables.roll_soul_gem_drop(monster_tier)
			if not soul_gem.is_empty():
				var gem_id = soul_gem.get("id", "")
				var gem_name = soul_gem.get("name", "Unknown Soul Gem")
				var gem_desc = soul_gem.get("description", "")
				var gem_bonuses = soul_gem.get("bonuses", {})
				if character.has_soul_gem(gem_id):
					messages.append("[color=#00FFFF]===========================================================================[/color]")
					messages.append("[color=#00FFFF]* SOUL GEM DROP: %s *[/color]" % gem_name)
					messages.append("[color=#808080]%s[/color]" % gem_desc)
					messages.append("[color=#FFFF00](You already have this soul gem!)[/color]")
					messages.append("[color=#00FFFF]===========================================================================[/color]")
				else:
					character.add_soul_gem(gem_id, gem_name, gem_bonuses)
					messages.append("[color=#00FFFF]===========================================================================[/color]")
					messages.append("[color=#00FFFF]*** NEW SOUL GEM ACQUIRED! ***[/color]")
					messages.append("[color=#FFD700]%s[/color]" % gem_name)
					messages.append("[color=#808080]%s[/color]" % gem_desc)
					# Show bonuses
					var bonus_text = []
					for bonus_type in gem_bonuses:
						var val = gem_bonuses[bonus_type]
						match bonus_type:
							"attack": bonus_text.append("+%d%% attack" % val)
							"hp_regen": bonus_text.append("+%d%% HP/round" % val)
							"flee_bonus": bonus_text.append("+%d%% flee chance" % val)
							"crit_chance": bonus_text.append("+%d%% crit chance" % val)
							"hp_bonus": bonus_text.append("+%d%% max HP" % val)
							"defense": bonus_text.append("+%d%% defense" % val)
							"lifesteal": bonus_text.append("+%d%% lifesteal" % val)
					messages.append("[color=#00FF00]Bonuses: %s[/color]" % ", ".join(bonus_text))
					messages.append("[color=#808080]Use /companion to activate this companion![/color]")
					messages.append("[color=#00FFFF]===========================================================================[/color]")

	# Title item drops (Jarl's Ring, Unforged Crown)
	var title_item = roll_title_item_drop(monster.level)
	if not title_item.is_empty():
		messages.append("[color=#FFD700]===========================================================================[/color]")
		messages.append("[color=#FFD700]*** A LEGENDARY TITLE ITEM DROPS! ***[/color]")
		messages.append("[color=#C0C0C0]%s[/color]" % title_item.name)
		messages.append("[color=#808080]%s[/color]" % title_item.description)
		messages.append("[color=#FFD700]===========================================================================[/color]")
		if not combat.has("extra_drops"):
			combat.extra_drops = []
		combat.extra_drops.append(title_item)

	# Roll for item drops
	var dropped_items = roll_combat_drops(monster, character)
	for item in dropped_items:
		messages.append("[color=%s]%s dropped: %s![/color]" % [
			_get_rarity_color(item.get("rarity", "common")),
			monster.name,
			item.get("name", "Unknown Item")
		])

	# Pack leader: higher flock chance
	var flock = monster.get("flock_chance", 0)
	if ABILITY_PACK_LEADER in abilities:
		flock = min(75, flock + 25)

	# Combine regular drops with extra drops from abilities
	var all_drops = dropped_items.duplicate()
	if combat.has("extra_drops"):
		all_drops.append_array(combat.extra_drops)

	# Combat durability wear (~30% chance per fight, 1 random item takes 1-3 wear)
	_apply_combat_wear(character, messages)

	# Indent all victory/reward messages
	var victory_indent = "          "  # 10 spaces
	messages.insert(victory_msg_start, "[color=#444444]─────────────────────────────[/color]")
	_indent_new_messages(messages, victory_msg_start + 1, victory_indent)

	return {
		"success": true,
		"messages": messages,
		"combat_ended": true,
		"victory": true,
		"monster_name": monster.name,
		"monster_base_name": monster.get("base_name", monster.name),  # For flock generation
		"monster_level": monster.level,
		"flock_chance": flock,
		"dropped_items": all_drops,
		"gems_earned": gems_earned,
		"summon_next_fight": combat.get("summon_next_fight", ""),
		"is_rare_variant": monster.get("is_rare_variant", false),
		"wish_pending": combat.get("wish_pending", false),
		"wish_options": combat.get("wish_options", []),
		"is_dungeon_combat": combat.get("is_dungeon_combat", false),
		"is_boss_fight": combat.get("is_boss_fight", false),
		"dungeon_monster_id": combat.get("dungeon_monster_id", -1)
	}

func process_flee(combat: Dictionary) -> Dictionary:
	"""Process flee attempt"""
	var character = combat.character
	var monster = combat.monster
	var messages = []

	# Process status effects (poison/blind tick)
	_process_status_ticks(character, messages)

	# Get class passive for flee bonuses
	var passive = character.get_class_passive()
	var passive_effects = passive.get("effects", {})

	# Flee chance based on level difference, DEX, and equipment speed
	# Base 40% + DEX + equipment_speed + speed_buff + flee_bonus - (level_diff Ã— 3)
	var equipment_bonuses = character.get_equipment_bonuses()
	var player_dex = character.get_effective_stat("dexterity")
	var speed_buff = character.get_buff_value("speed")
	var equipment_speed = equipment_bonuses.speed  # Boots provide speed bonus
	var flee_bonus = equipment_bonuses.get("flee_bonus", 0)  # Evasion gear provides flee bonus
	var monster_level = monster.get("level", 1)
	var player_level = character.level
	var level_diff = max(0, monster_level - player_level)  # Only penalize if monster is higher level

	# Base 40%, +1% per DEX, +equipment speed (boots!), +speed buffs, +flee bonus
	# -1% per level the monster is above you (diminishing — high-level fights still escapable)
	var flee_chance = 40 + player_dex + equipment_speed + speed_buff + flee_bonus - level_diff

	# === CLASS PASSIVE: Ninja Shadow Step ===
	# +40% flee success chance
	if passive_effects.has("flee_bonus"):
		var ninja_flee_bonus = int(passive_effects.get("flee_bonus", 0) * 100)
		flee_chance += ninja_flee_bonus
		messages.append("[color=#191970]Shadow Step: +%d%% flee chance![/color]" % ninja_flee_bonus)

	# === COMPANION BONUS: Flee chance ===
	var companion_flee = character.get_companion_bonus("flee_bonus")
	# Companion speed also helps flee
	var companion_speed_flee = int(character.get_companion_bonus("speed"))
	companion_speed_flee += combat.get("companion_speed_bonus", 0)
	companion_flee += companion_speed_flee / 2.0
	if companion_flee > 0:
		flee_chance += int(companion_flee)
		messages.append("[color=#00FFFF]Companion: +%d%% flee chance![/color]" % int(companion_flee))
	# Add companion flee from passive abilities
	var companion_flee_ability = combat.get("companion_flee_bonus", 0)
	if companion_flee_ability > 0:
		flee_chance += companion_flee_ability
	# Add companion flee from threshold ability buff
	var companion_flee_buff = combat.get("companion_flee_buff", 0)
	if companion_flee_buff > 0:
		flee_chance += companion_flee_buff
		messages.append("[color=#00FFFF]Companion ability: +%d%% flee chance![/color]" % companion_flee_buff)
		# Decrement duration
		var flee_duration = combat.get("companion_flee_duration", 0)
		if flee_duration > 0:
			combat["companion_flee_duration"] = flee_duration - 1
			if flee_duration - 1 <= 0:
				combat["companion_flee_buff"] = 0

	# Apply slow aura debuff (from monster ability)
	var slow_penalty = combat.get("player_slow", 0)
	if slow_penalty > 0:
		flee_chance -= slow_penalty

	# === FLOCK FLEE BONUS ===
	# Each monster fought in a flock increases flee chance by 15%
	var flock_count = combat.get("flock_count", 0)
	if flock_count > 0:
		var flock_flee_bonus = flock_count * 15
		flee_chance += flock_flee_bonus
		messages.append("[color=#FFD700]Flock fatigue: +%d%% flee chance![/color]" % flock_flee_bonus)

	flee_chance = clamp(flee_chance, 10, 95)  # Hardcap 10-95%

	var roll = randi() % 100

	if roll < flee_chance:
		# Successful flee
		messages.append("[color=#FFD700]You successfully flee from combat![/color]")
		return {
			"success": true,
			"messages": messages,
			"combat_ended": true,
			"victory": false,
			"fled": true
		}
	else:
		# Failed flee
		messages.append("[color=#FF4444]You fail to escape![/color]")
		# === CLASS PASSIVE: Ninja Shadow Step ===
		# Take no damage when fleeing fails
		if passive_effects.get("flee_no_damage", false):
			combat["ninja_flee_protection"] = true
			messages.append("[color=#191970]Shadow Step: You evade the counterattack![/color]")
		combat.player_can_act = false
		return {
			"success": true,
			"messages": messages,
			"combat_ended": false
		}

func process_special(combat: Dictionary) -> Dictionary:
	"""Process special action (class-specific)"""
	var character = combat.character
	var messages = []

	# Process status effects (poison/blind tick)
	_process_status_ticks(character, messages)

	messages.append("[color=#808080]Special abilities coming soon![/color]")

	return {
		"success": false,
		"messages": messages,
		"combat_ended": false
	}

func process_outsmart(combat: Dictionary) -> Dictionary:
	"""Process outsmart action (Trickster ability).
	Success = instant win with full rewards.
	Failure = monster gets free attack, can't outsmart again this combat.
	Tricksters get +20% bonus. High wits helps, high monster INT hurts."""
	var character = combat.character
	var monster = combat.monster
	var messages = []

	# Process status effects (poison/blind tick)
	_process_status_ticks(character, messages)

	# Check if already failed outsmart this combat
	if combat.get("outsmart_failed", false):
		messages.append("[color=#FF4444]You already failed to outsmart this enemy![/color]")
		return {
			"success": false,
			"messages": messages,
			"combat_ended": false
		}

	# Calculate outsmart chance - WIT vs monster INT and LEVEL DIFFERENCE are key factors
	# Dumb monsters are easy to fool, smart ones nearly impossible
	# Higher level monsters are harder to outsmart - it's risky to fight above your level
	var player_wits = character.get_effective_stat("wits")
	var monster_intelligence = monster.get("intelligence", 15)
	var player_level = character.level
	var monster_level = monster.level

	# Base chance is very low - outsmart is situational
	var base_chance = 5

	# WIT bonus: logarithmic scaling for diminishing returns
	# Formula: 18 * log2(WITS/10) = ~18% at WITS 20, ~36% at WITS 40, ~54% at WITS 80
	var wits_bonus = 0
	if player_wits > 10:
		wits_bonus = int(18.0 * log(float(player_wits) / 10.0) / log(2.0))

	# Trickster class bonus (+20%)
	var class_type = character.class_type
	var is_trickster = class_type in ["Thief", "Ranger", "Ninja"]
	var trickster_bonus = 20 if is_trickster else 0

	# Dumb monster bonus: +3% per INT below 10
	var dumb_bonus = max(0, (10 - monster_intelligence) * 3)

	# Smart monster penalty: -1% per INT above 10 (reduced from -2% for better balance)
	var smart_penalty = max(0, monster_intelligence - 10)

	# Additional penalty if monster INT exceeds your wits (-2% per point)
	var int_vs_wits_penalty = max(0, (monster_intelligence - player_wits) * 2)

	# LEVEL DIFFERENCE PENALTY - This is the big balancing factor
	# Fighting monsters much higher level is risky for Outsmart
	var level_diff = monster_level - player_level
	var level_penalty = 0
	if level_diff > 0:
		# Scaling penalty: -2% per level for first 10 levels, -1% per level after
		if level_diff <= 10:
			level_penalty = level_diff * 2  # -2% to -20% for 1-10 levels above
		elif level_diff <= 50:
			level_penalty = 20 + (level_diff - 10)  # -21% to -60% for 11-50 levels above
		else:
			# Severe penalty for extreme level differences
			level_penalty = 60 + int((level_diff - 50) * 0.5)  # -60%+ for 51+ levels above

	# Level BONUS for fighting weaker monsters (small bonus)
	var level_bonus = 0
	if level_diff < 0:
		level_bonus = min(15, abs(level_diff))  # Up to +15% for fighting weaker monsters

	var outsmart_chance = base_chance + wits_bonus + trickster_bonus + dumb_bonus + level_bonus - smart_penalty - int_vs_wits_penalty - level_penalty

	# INT-based cap: High monster INT reduces maximum success chance
	# Base max: 85% for tricksters, 70% for others. Reduced by monster INT/3
	var base_max_chance = 85 if is_trickster else 70
	var max_chance = max(30, base_max_chance - int(monster_intelligence / 3))  # Min 30% cap
	outsmart_chance = clampi(outsmart_chance, 2, max_chance)

	messages.append("[color=#FFA500]You attempt to outsmart the %s...[/color]" % monster.name)
	var bonus_text = ""
	if is_trickster:
		bonus_text = " [Trickster]"
	var level_text = ""
	if level_diff > 10:
		level_text = " [color=#FF4444]Lv%+d[/color]" % level_diff
	elif level_diff > 0:
		level_text = " [color=#FFA500]Lv%+d[/color]" % level_diff
	messages.append("[color=#808080](Wits: %d vs INT: %d, %d%% chance%s%s)[/color]" % [player_wits, monster_intelligence, outsmart_chance, bonus_text, level_text])

	var roll = randi() % 100

	if roll < outsmart_chance:
		# SUCCESS! Instant victory
		messages.append("[color=#00FF00][b]SUCCESS![/b] You outwit the %s![/color]" % monster.name)
		messages.append("[color=#FFD700]The enemy falls for your trick and you claim victory![/color]")

		# Process death curse (monster curses you as it falls)
		var monster_abilities = monster.get("abilities", [])
		if ABILITY_DEATH_CURSE in monster_abilities:
			if character.is_immune_to_death_curse():
				messages.append("[color=#708090]The %s's death curse has no effect on your undead form![/color]" % monster.name)
			else:
				var base_curse_damage = int(monster.max_hp * 0.10)
				var player_wis_stat = character.get_effective_stat("wisdom") + combat.get("companion_wisdom_bonus", 0)
				var wis_reduction = minf(0.50, float(player_wis_stat) / 200.0)
				var curse_damage = int(base_curse_damage * (1.0 - wis_reduction))
				curse_damage = max(1, curse_damage)
				character.current_hp -= curse_damage
				character.current_hp = max(1, character.current_hp)
				if wis_reduction > 0:
					messages.append("[color=#FF00FF]The %s's death curse deals [color=#FF8800]%d[/color] damage! (WIS resists %d%%)[/color]" % [monster.name, curse_damage, int(wis_reduction * 100)])
				else:
					messages.append("[color=#FF00FF]The %s's death curse deals [color=#FF8800]%d[/color] damage![/color]" % [monster.name, curse_damage])

		# Give full rewards as if monster was killed
		var base_xp = monster.experience_reward
		var xp_level_diff = monster.level - character.level
		var xp_multiplier = 1.0

		# Get tier difference - big rewards for fighting above your tier!
		var player_tier = _get_tier_for_level(character.level)
		var monster_tier = _get_tier_for_level(monster.level)
		var tier_diff = monster_tier - player_tier

		# TIER BONUS: Fighting higher tier monsters is very rewarding!
		var xp_tier_bonus = 1.0
		if tier_diff > 0:
			xp_tier_bonus = pow(2.0, tier_diff)  # 2x per tier
			messages.append("[color=#FF00FF]* TIER CHALLENGE: +%dx XP bonus! *[/color]" % int(xp_tier_bonus))

		# Small level difference bonus (within same tier)
		if xp_level_diff > 0 and tier_diff == 0:
			xp_multiplier = 1.0 + min(0.5, xp_level_diff * 0.02)

		var final_xp = int(base_xp * xp_multiplier * xp_tier_bonus * 1.10)  # +10% XP boost

		# Add XP
		var old_level = character.level
		var level_result = character.add_experience(final_xp)

		messages.append("[color=#FF00FF]+%d XP[/color]" % final_xp)

		if level_result.leveled_up:
			messages.append("[color=#FFD700][b]LEVEL UP![/b] You are now level %d![/color]" % level_result.new_level)

			# Check for newly unlocked abilities
			var new_abilities = character.get_newly_unlocked_abilities(old_level, level_result.new_level)
			if new_abilities.size() > 0:
				messages.append("")
				messages.append("[color=#00FFFF]+======================================+[/color]")
				messages.append("[color=#00FFFF]|[/color]  [color=#FFFF00][b]NEW ABILITY UNLOCKED![/b][/color]")
				for ability in new_abilities:
					var ability_type = "Universal" if ability.get("universal", false) else "Class"
					messages.append("[color=#00FFFF]|[/color]  [color=#00FF00]*[/color] [color=#FFFFFF]%s[/color] [color=#808080](%s)[/color]" % [ability.display, ability_type])
				messages.append("[color=#00FFFF]|[/color]  [color=#808080]Check Abilities menu to equip![/color]")
				messages.append("[color=#00FFFF]+======================================+[/color]")

		# === COMPANION XP DISTRIBUTION ===
		# Active companions gain 10% of monster XP (same as normal victory)
		if character.has_active_companion():
			var companion_xp = max(1, int(base_xp * 0.10))
			var companion_result = character.add_companion_xp(companion_xp)
			character.increment_companion_battles()
			if companion_result.leveled_up:
				var companion = character.get_active_companion()
				messages.append("[color=#00FFFF]* %s leveled up to %d! *[/color]" % [companion.get("name", "Companion"), companion_result.new_level])
				# Notify of unlocked abilities
				for ability_level in companion_result.abilities_unlocked:
					if drop_tables:
						var tier = companion.get("tier", 1)
						var ability = drop_tables.get_companion_ability(tier, ability_level)
						if not ability.is_empty():
							messages.append("[color=#FFD700]* New ability unlocked: %s! *[/color]" % ability.get("name", "Unknown"))

		# Roll for item drops
		var dropped_items = []
		var gems_earned = 0
		var extra_drops = []
		var abilities = monster.get("abilities", [])
		var wish_pending = false
		var wish_options = []

		if drop_tables:
			var drops_result = drop_tables.roll_drops(
				monster.get("drop_table_id", "tier1"),
				monster.get("drop_chance", 5),
				monster.level
			)
			dropped_items = drops_result

				# Weapon Master ability: 50% chance to drop a weapon with attack bonuses
			if ABILITY_WEAPON_MASTER in abilities:
				if randf() < 0.50:  # 50% chance
					var weapon = drop_tables.generate_weapon(monster.level)
					if not weapon.is_empty():
						messages.append("[color=#FF8000]The Weapon Master drops a powerful weapon![/color]")
						messages.append("[color=%s]Dropped: %s (Level %d)[/color]" % [
							_get_rarity_color(weapon.get("rarity", "common")),
							weapon.get("name", "Unknown Weapon"),
							weapon.get("level", 1)
						])
						extra_drops.append(weapon)
				else:
					messages.append("[color=#AA6666]- The Weapon Master's weapon shatters on death...[/color]")

			# Shield Bearer ability: 50% chance to drop a shield with HP bonuses
			if ABILITY_SHIELD_BEARER in abilities:
				if randf() < 0.50:  # 50% chance
					var shield = drop_tables.generate_shield(monster.level)
					if not shield.is_empty():
						messages.append("[color=#00FFFF]The Shield Guardian drops a sturdy shield![/color]")
						messages.append("[color=%s]Dropped: %s (Level %d)[/color]" % [
							_get_rarity_color(shield.get("rarity", "common")),
							shield.get("name", "Unknown Shield"),
							shield.get("level", 1)
						])
						extra_drops.append(shield)
				else:
					messages.append("[color=#AA6666]- The Shield Guardian's shield crumbles to dust...[/color]")

			# Arcane Hoarder ability: 35% chance to drop mage gear
			if ABILITY_ARCANE_HOARDER in abilities:
				if randf() < 0.35:  # 35% chance
					var mage_item = drop_tables.generate_mage_gear(monster.level)
					if not mage_item.is_empty():
						messages.append("[color=#66CCCC]The Arcane Hoarder drops magical equipment![/color]")
						messages.append("[color=%s]Dropped: %s (Level %d)[/color]" % [
							_get_rarity_color(mage_item.get("rarity", "common")),
							mage_item.get("name", "Unknown Item"),
							mage_item.get("level", 1)
						])
						extra_drops.append(mage_item)
				else:
					messages.append("[color=#AA66AA]- The Arcane Hoarder's magic dissipates...[/color]")

			# Cunning Prey ability: 35% chance to drop trickster gear
			if ABILITY_CUNNING_PREY in abilities:
				if randf() < 0.35:  # 35% chance
					var trick_item = drop_tables.generate_trickster_gear(monster.level)
					if not trick_item.is_empty():
						messages.append("[color=#66FF66]The Cunning Prey drops elusive equipment![/color]")
						messages.append("[color=%s]Dropped: %s (Level %d)[/color]" % [
							_get_rarity_color(trick_item.get("rarity", "common")),
							trick_item.get("name", "Unknown Item"),
							trick_item.get("level", 1)
						])
						extra_drops.append(trick_item)
				else:
					messages.append("[color=#66AA66]- The Cunning Prey's gear vanishes into shadow...[/color]")

			# Warrior Hoarder ability: 35% chance to drop warrior gear
			if ABILITY_WARRIOR_HOARDER in abilities:
				if randf() < 0.35:
					var war_item = drop_tables.generate_warrior_gear(monster.level)
					if not war_item.is_empty():
						messages.append("[color=#FF6600]The Warrior Hoarder drops battle-worn gear![/color]")
						messages.append("[color=%s]Dropped: %s (Level %d)[/color]" % [
							_get_rarity_color(war_item.get("rarity", "common")),
							war_item.get("name", "Unknown Item"),
							war_item.get("level", 1)
						])
						extra_drops.append(war_item)
				else:
					messages.append("[color=#AA8866]- The Warrior Hoarder's armor crumbles...[/color]")

			# Roll for gem drops → Monster Gems
			gems_earned = roll_gem_drops(monster, character)
			if gems_earned > 0:
				character.add_crafting_material("monster_gem", gems_earned)
				messages.append("[color=#00FFFF]+ + [/color][color=#FF00FF]+%d Monster Gem%s![/color][color=#00FFFF] + +[/color]" % [gems_earned, "s" if gems_earned > 1 else ""])

		# Wish granter ability: 10% chance to offer a wish (100% if GM-guaranteed)
		if ABILITY_WISH_GRANTER in abilities:
			var wish_chance_f = 1.0 if combat.get("gm_wish_guaranteed", false) else 0.10
			if randf() < wish_chance_f:
				var monster_lethality = monster.get("lethality", 100)
				wish_options = generate_wish_options(character, monster.level, monster_lethality)
				wish_pending = true
				messages.append("[color=#FFD700]* The %s offers you a WISH! *[/color]" % monster.name)
				messages.append("[color=#FFD700]Choose your reward wisely...[/color]")
			else:
				messages.append("[color=#808080]The %s's magic fades before granting a wish...[/color]" % monster.name)

		# Combine regular drops with extra drops (like normal victory)
		var all_drops = dropped_items.duplicate()
		all_drops.append_array(extra_drops)

		return {
			"success": true,
			"messages": messages,
			"combat_ended": true,
			"victory": true,
			"victory_type": "outsmart",  # For pilgrimage tracking
			"monster_name": monster.name,
			"monster_level": monster.level,
			"monster_base_name": monster.get("base_name", monster.name),
			"flock_chance": monster.get("flock_chance", 0),
			"dropped_items": all_drops,
			"gems_earned": gems_earned,
			"wish_pending": wish_pending,
			"wish_options": wish_options,
			"is_dungeon_combat": combat.get("is_dungeon_combat", false),
			"is_boss_fight": combat.get("is_boss_fight", false)
		}
	else:
		# FAILURE! Monster gets free attack
		combat.outsmart_failed = true
		messages.append("[color=#FF4444][b]FAILED![/b] The %s sees through your trick![/color]" % monster.name)

		# Companion still attacks even when outsmart fails - they're loyal!
		var _ca2 = messages.size()
		_process_companion_attack(combat, messages)
		_indent_new_messages(messages, _ca2, "   ")

		# Check if companion killed the monster
		if monster.current_hp <= 0:
			messages.append("[color=#00FF00]Your companion saved you by finishing off the %s![/color]" % monster.name)
			# Give rewards as if outsmart succeeded (companion clutch kill)
			var base_xp = monster.experience_reward
			var xp_result = character.add_experience(base_xp)
			messages.append("[color=#FFD700]+%d XP[/color]" % base_xp)
			return {
				"success": true,
				"messages": messages,
				"combat_ended": true,
				"victory": true,
				"victory_type": "companion_clutch",
				"monster_name": monster.name,
				"monster_level": monster.level,
				"monster_base_name": monster.get("base_name", monster.name),
				"flock_chance": monster.get("flock_chance", 0),
				"dropped_items": [],
				"gems_earned": 0,
				"is_dungeon_combat": combat.get("is_dungeon_combat", false),
				"is_boss_fight": combat.get("is_boss_fight", false)
			}

		# Monster gets a free attack
		var monster_result = process_monster_turn(combat)
		messages.append("[color=#444444]─────────────────────────────[/color]")
		messages.append(_indent_multiline(monster_result.message, "         "))
		messages.append("[color=#444444]─────────────────────────────[/color]")

		# Check if player died
		if character.current_hp <= 0:
			return {
				"success": true,
				"messages": messages,
				"combat_ended": true,
				"victory": false,
				"monster_name": "%s (Lvl %d)" % [monster.name, monster.level],
				"monster_level": monster.level
			}

		# Combat continues normally
		combat.round += 1
		combat.player_can_act = true
		var expired_buffs = character.tick_buffs()
		for buff in expired_buffs:
			var buff_name = buff.type.capitalize()
			messages.append("[color=#808080]Your %s buff has worn off.[/color]" % buff_name)

		return {
			"success": true,
			"messages": messages,
			"combat_ended": false,
			"outsmart_failed": true  # Tell client outsmart can't be used again
		}

# ===== ABILITY SYSTEM =====

func process_ability_command(peer_id: int, ability_name: String, arg: String) -> Dictionary:
	"""Process an ability command from player"""
	if not active_combats.has(peer_id):
		return {"success": false, "message": "You are not in combat!"}

	var combat = active_combats[peer_id]

	if not combat.player_can_act:
		return {"success": false, "message": "Wait for your turn!"}

	var character = combat.character
	var result: Dictionary

	# Track HP/monster HP before ability for damage tracking
	var monster_hp_before = combat.monster.current_hp
	var player_hp_before = combat.character.current_hp

	# Normalize ability names
	match ability_name:
		"bolt": ability_name = "magic_bolt"
		"strike": ability_name = "power_strike"
		"warcry": ability_name = "war_cry"
		"bash": ability_name = "shield_bash"
		"ironskin": ability_name = "iron_skin"
		"heist": ability_name = "perfect_heist"
		"shield": ability_name = "forcefield"  # Shield is now an alias for Forcefield

	# Universal abilities (available to all classes, use class resource)
	if ability_name == "cloak" or ability_name == "all_or_nothing":
		result = _process_universal_ability(combat, ability_name)
	# Mage abilities (use mana)
	elif ability_name in ["magic_bolt", "blast", "forcefield", "teleport", "meteor", "haste", "paralyze", "banish"]:
		result = _process_mage_ability(combat, ability_name, arg)
	# Warrior abilities (use stamina)
	elif ability_name in ["power_strike", "war_cry", "shield_bash", "cleave", "berserk", "iron_skin", "devastate", "fortify", "rally"]:
		result = _process_warrior_ability(combat, ability_name)
	# Trickster abilities (use energy)
	elif ability_name in ["analyze", "distract", "pickpocket", "ambush", "vanish", "exploit", "perfect_heist", "sabotage", "gambit"]:
		result = _process_trickster_ability(combat, ability_name)
	else:
		return {"success": false, "message": "Unknown ability!"}

	# Track damage dealt/taken by the ability itself (backfire, thorns, etc.)
	var ability_damage_dealt = max(0, monster_hp_before - combat.monster.current_hp)
	combat["total_damage_dealt"] = combat.get("total_damage_dealt", 0) + ability_damage_dealt
	var ability_self_damage = max(0, player_hp_before - combat.character.current_hp)
	combat["total_damage_taken"] = combat.get("total_damage_taken", 0) + ability_self_damage

	# Check if combat ended
	if result.has("combat_ended") and result.combat_ended:
		end_combat(peer_id, result.get("victory", false))
		return result

	# === GEAR RESOURCE REGEN (skipped on CC ability turns to prevent spend/regen loops) ===
	var cc_abilities = ["shield_bash", "paralyze"]
	if ability_name not in cc_abilities:
		_apply_gear_resource_regen(combat.character, result.messages)

	# === COMPANION ATTACK (only if ability takes a combat turn) ===
	# Don't attack on free actions like Analyze, Pickpocket success, etc.
	if not result.get("skip_monster_turn", false):
		var _ca3 = result.messages.size()
		_process_companion_attack(combat, result.messages)
		_indent_new_messages(result.messages, _ca3, "   ")

	# Track companion damage to monster
	var companion_damage = max(0, monster_hp_before - combat.monster.current_hp) - ability_damage_dealt
	if companion_damage > 0:
		combat["total_damage_dealt"] = combat.get("total_damage_dealt", 0) + companion_damage

	# Check if companion killed the monster
	if combat.monster.current_hp <= 0:
		# Process full victory with rewards (XP, items, etc.)
		result.messages.append("[color=#00FF00]Your companion finishes off the %s![/color]" % combat.monster.name)
		var victory_result = _process_victory_with_abilities(combat, result.messages)
		end_combat(peer_id, true)
		return victory_result

	# Monster's turn (if still alive and ability didn't end turn specially)
	# Buff abilities only give monster 25% chance to attack (player is being defensive/cautious)
	var monster_attacks = true
	if result.get("buff_ability", false):
		monster_attacks = randi() % 100 < 25  # 25% chance monster still attacks
		if not monster_attacks:
			result.messages.append("[color=#00FF00]You act quickly, avoiding the %s's attack![/color]" % combat.monster.name)

	if not result.get("skip_monster_turn", false) and monster_attacks and combat.monster.current_hp > 0:
		var player_hp_before_monster = combat.character.current_hp
		var monster_hp_before_turn = combat.monster.current_hp
		var monster_result = process_monster_turn(combat)
		result.messages.append("[color=#444444]─────────────────────────────[/color]")
		var monster_msg = monster_result.get("message", "")
		result.messages.append(_indent_multiline(monster_msg, "         "))
		result.messages.append("[color=#444444]─────────────────────────────[/color]")
		# Track damage taken from monster
		var damage_taken_this_turn = max(0, player_hp_before_monster - combat.character.current_hp)
		combat["total_damage_taken"] = combat.get("total_damage_taken", 0) + damage_taken_this_turn
		# Track any damage dealt by reflect/thorns during monster turn
		var reflect_damage = max(0, monster_hp_before_turn - combat.monster.current_hp)
		combat["total_damage_dealt"] = combat.get("total_damage_dealt", 0) + reflect_damage

		# Check if player died
		# Note: Don't call end_combat here - let server check eternal status first
		if combat.character.current_hp <= 0:
			result.combat_ended = true
			result.victory = false
			result.monster_name = "%s (Lvl %d)" % [combat.monster.name, combat.monster.level]
			result.monster_level = combat.monster.level
			result.messages.append("[color=#FF0000]You have been defeated![/color]")
			return result

	# Increment round
	combat.round += 1
	combat.player_can_act = true

	# Tick buff durations and regenerate energy
	var expired_buffs = combat.character.tick_buffs()
	for buff in expired_buffs:
		var buff_name = buff.type.capitalize()
		result.messages.append("[color=#808080]Your %s buff has worn off.[/color]" % buff_name)
	# Note: Resources do not auto-regenerate in combat
	# Resource regen comes from gear (Shadow/Warlord/Mystic) or out-of-combat rest/meditate

	return result

func _process_universal_ability(combat: Dictionary, ability_name: String) -> Dictionary:
	"""Process universal abilities available to all classes (use class resource)"""
	var character = combat.character
	var monster = combat.monster
	var messages = []

	match ability_name:
		"cloak":
			# Check level requirement for cloak (level 20)
			if character.level < 20:
				return {"success": false, "messages": ["[color=#FF4444]Cloak requires level 20![/color]"], "combat_ended": false}

			# Determine cost based on class path (8% of max resource)
			var cost = character.get_cloak_cost()
			var resource_name = character.get_primary_resource()
			var current_resource = character.get_primary_resource_current()

			# In combat, cloak lets you avoid one monster attack and escape
			if current_resource < cost:
				return {"success": false, "messages": ["[color=#FF4444]Not enough %s! Need %d.[/color]" % [resource_name, cost]], "combat_ended": false}

			# Drain the resource
			character.drain_cloak_cost()

			# 75% chance to escape combat successfully
			if randf() < 0.75:
				messages.append("[color=#9932CC]You cloak yourself in shadows and slip away from combat![/color]")
				return {
					"success": true,
					"messages": messages,
					"combat_ended": true,
					"victory": false,
					"fled": true,
					"skip_monster_turn": true
				}
			else:
				messages.append("[color=#FF4444]You try to cloak but the %s sees through your disguise![/color]" % monster.name)
				return {"success": true, "messages": messages, "combat_ended": false}

		"all_or_nothing":
			# Universal desperation ability - very low chance to instant kill
			# Costs 1 mana/stamina/energy (uses whatever resource the class has)
			var has_resource = false
			if character.current_mana >= 1:
				character.current_mana -= 1
				has_resource = true
			elif character.current_stamina >= 1:
				character.current_stamina -= 1
				has_resource = true
			elif character.current_energy >= 1:
				character.current_energy -= 1
				has_resource = true

			if not has_resource:
				return {"success": false, "messages": ["[color=#FF4444]You need at least 1 resource to attempt this![/color]"], "combat_ended": false, "skip_monster_turn": true}

			# Track usage (for "gets better over time" mechanic)
			character.all_or_nothing_uses += 1

			# Calculate success chance:
			# Base: 3%
			# +0.1% per use (max +25% from uses, so caps at 250 uses)
			# -0.5% per monster level above player (heavily penalized vs high level)
			# +0.5% per monster level below player
			var base_chance = 3.0
			var use_bonus = min(25.0, character.all_or_nothing_uses * 0.1)
			var level_diff = monster.level - character.level
			var level_modifier = -level_diff * 0.5  # Negative if monster higher, positive if lower

			var success_chance = base_chance + use_bonus + level_modifier
			success_chance = clamp(success_chance, 1.0, 34.0)  # Min 1%, max 34%

			messages.append("[color=#FF00FF][b]ALL OR NOTHING![/b][/color]")
			messages.append("[color=#808080](Success chance: %.1f%%)[/color]" % success_chance)

			if randf() * 100.0 < success_chance:
				# SUCCESS - instant kill!
				var killing_blow = monster.current_hp
				monster.current_hp = 0
				messages.append("[color=#00FF00][b]MIRACULOUS SUCCESS![/b][/color]")
				messages.append("[color=#FFD700]Against all odds, you strike the %s's vital point for %d damage![/color]" % [monster.name, killing_blow])
			else:
				# FAILURE - monster gets enraged (double strength and speed)
				monster.strength = monster.strength * 2
				monster.speed = monster.speed * 2
				# Wake up paralyzed monsters faster
				if combat.get("monster_stunned", 0) > 0:
					combat["monster_stunned"] = max(0, combat["monster_stunned"] - 2)
					messages.append("[color=#FF4444]The monster snaps out of paralysis![/color]")
				messages.append("[color=#FF0000][b]CATASTROPHIC FAILURE![/b][/color]")
				messages.append("[color=#FF4444]The %s becomes ENRAGED! Its strength and speed DOUBLE![/color]" % monster.name)

			# Check if monster died
			if monster.current_hp <= 0:
				return _process_victory(combat, messages)

			return {"success": true, "messages": messages, "combat_ended": false}

	return {"success": false, "messages": ["[color=#FF4444]Unknown universal ability![/color]"], "combat_ended": false}

func _process_mage_ability(combat: Dictionary, ability_name: String, arg: String) -> Dictionary:
	"""Process mage abilities (use mana)"""
	var character = combat.character
	var monster = combat.monster
	var messages = []
	var is_buff_ability = false  # Buff abilities only give monster 25% chance to attack

	# Check INT requirement for mage path
	if character.get_stat("intelligence") <= 10:
		return {"success": false, "messages": ["[color=#FF4444]You need INT > 10 to use mage abilities![/color]"], "combat_ended": false}

	# Get ability info
	var ability_info = _get_ability_info("mage", ability_name)
	if ability_info.is_empty():
		return {"success": false, "messages": ["[color=#FF4444]Unknown mage ability![/color]"], "combat_ended": false}

	# Check level requirement
	if character.level < ability_info.level:
		return {"success": false, "messages": ["[color=#FF4444]%s requires level %d![/color]" % [ability_info.name, ability_info.level]], "combat_ended": false}

	# Calculate mana cost - use percentage of max mana or base cost, whichever is higher
	# This ensures abilities scale with late-game mana pools
	var base_cost = ability_info.cost
	var cost_percent = ability_info.get("cost_percent", 0)
	var percent_cost = int(character.get_total_max_mana() * cost_percent / 100.0)
	var mana_cost = max(base_cost, percent_cost)

	# Get class passive for spell modifications
	var passive = character.get_class_passive()
	var passive_effects = passive.get("effects", {})

	match ability_name:
		"magic_bolt":
			# Variable mana cost - damage scales with INT
			# Formula: damage = mana * (1 + INT/50), reduced by monster WIS
			var bolt_amount = arg.to_int() if arg.is_valid_int() else 0
			if bolt_amount <= 0:
				return {"success": false, "messages": ["[color=#808080]Usage: bolt <amount> - deals mana Ã— INT damage[/color]"], "combat_ended": false, "skip_monster_turn": true}
			bolt_amount = mini(bolt_amount, character.current_mana)
			if bolt_amount <= 0:
				return {"success": false, "messages": ["[color=#FF4444]Not enough mana![/color]"], "combat_ended": false, "skip_monster_turn": true}

			# === RACIAL/CLASS COST REDUCTIONS ===
			# Gnome racial: -15% ability costs, Sage: -25% mana costs
			var actual_mana_cost = bolt_amount
			var gnome_mult = character.get_ability_cost_multiplier()
			if gnome_mult < 1.0:
				actual_mana_cost = int(actual_mana_cost * gnome_mult)
			if passive_effects.has("mana_cost_reduction"):
				actual_mana_cost = int(actual_mana_cost * (1.0 - passive_effects.get("mana_cost_reduction", 0)))
			actual_mana_cost = max(1, actual_mana_cost)
			if actual_mana_cost < bolt_amount:
				messages.append("[color=#20B2AA]Cost reduced to %d mana![/color]" % actual_mana_cost)
			character.current_mana -= actual_mana_cost

			# Calculate INT-based damage (based on intended bolt_amount, not reduced cost)
			# Hybrid scaling: max of sqrt and linear for better high-level scaling
			# sqrt(INT)/5: INT 25=2x, INT 100=3x, INT 225=4x (diminishing returns)
			# INT/75: INT 75=2x, INT 150=3x, INT 225=4x (linear, better at high INT)
			var int_stat = character.get_effective_stat("intelligence")
			var int_multiplier = 1.0 + max(sqrt(float(int_stat)) / 5.0, float(int_stat) / 75.0)
			var base_damage = int(bolt_amount * int_multiplier)

			# Apply damage buff (from War Cry, potions, etc.)
			var damage_buff = character.get_buff_value("damage")
			if damage_buff > 0:
				base_damage = int(base_damage * (1.0 + damage_buff / 100.0))

			# Apply skill enhancement damage bonus
			var enhanced_damage = apply_skill_damage_bonus(character, "magic_bolt", base_damage)
			if enhanced_damage > base_damage:
				messages.append("[color=#00FFFF]Skill Enhancement: +%d%% damage![/color]" % int(character.get_skill_damage_bonus("magic_bolt")))
				base_damage = enhanced_damage

			# === CLASS PASSIVE: Wizard Arcane Precision ===
			# +15% spell damage
			if passive_effects.has("spell_damage_bonus"):
				base_damage = int(base_damage * (1.0 + passive_effects.get("spell_damage_bonus", 0)))
				messages.append("[color=#4169E1]Arcane Precision: +%d%% spell damage![/color]" % int(passive_effects.get("spell_damage_bonus", 0) * 100))

			# === CLASS PASSIVE: Sorcerer Chaos Magic ===
			# 25% double damage, 5% backfire
			if passive_effects.has("double_damage_chance"):
				var chaos_roll = randf()
				if chaos_roll < passive_effects.get("backfire_chance", 0.10):
					# Backfire: damage yourself (capped at 15% max HP)
					var backfire_dmg = mini(int(base_damage * 0.5), int(character.get_total_max_hp() * 0.15))
					character.current_hp -= backfire_dmg
					character.current_hp = max(1, character.current_hp)
					base_damage = int(base_damage * 0.5)
					messages.append("[color=#9400D3]Chaos Magic backfires for %d damage![/color]" % backfire_dmg)
				elif chaos_roll < passive_effects.get("backfire_chance", 0.10) + passive_effects.get("double_damage_chance", 0.25):
					base_damage = base_damage * 2
					messages.append("[color=#9400D3]Chaos Magic: DOUBLE DAMAGE![/color]")

			# === CLASS PASSIVE: Wizard Spell Crit ===
			# +10% spell crit chance (1.5x damage)
			if passive_effects.has("spell_crit_bonus"):
				var spell_crit_chance = int(passive_effects.get("spell_crit_bonus", 0) * 100)
				if randi() % 100 < spell_crit_chance:
					base_damage = int(base_damage * 1.5)
					messages.append("[color=#4169E1]Spell Critical! +50%% damage![/color]")

			# Monster WIS reduces damage (up to 30% reduction)
			var monster_wis = monster.get("wisdom", monster.get("intelligence", 15))
			var wis_reduction = min(0.30, float(monster_wis) / 300.0)  # WIS 90 = 30% reduction
			var pre_mod_dmg = max(1, int(base_damage * (1.0 - wis_reduction)))

			# Apply class affinity bonus (Mages deal +25% to Magical affinity monsters)
			var affinity = monster.get("class_affinity", 0)
			var class_multiplier = _get_class_advantage_multiplier(affinity, character.class_type)
			pre_mod_dmg = int(pre_mod_dmg * class_multiplier)
			if class_multiplier > 1.0:
				messages.append("[color=#00BFFF]Class advantage! +%d%% damage![/color]" % [int((class_multiplier - 1.0) * 100)])
			elif class_multiplier < 1.0:
				messages.append("[color=#FF6666]Class disadvantage: -%d%% damage[/color]" % [int((1.0 - class_multiplier) * 100)])

			var final_damage = apply_damage_variance(apply_ability_damage_modifiers(pre_mod_dmg, character.level, monster))

			monster.current_hp -= final_damage
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#FF00FF]You cast Magic Bolt for %d mana![/color]" % actual_mana_cost)
			messages.append("[color=#00FFFF]The bolt strikes for %d damage![/color]" % final_damage)

		"cloak":
			if not character.use_mana(mana_cost):
				return {"success": false, "messages": ["[color=#FF4444]Not enough mana! (Need %d)[/color]" % mana_cost], "combat_ended": false, "skip_monster_turn": true}
			combat["cloak_active"] = true  # 50% miss chance for enemy
			messages.append("[color=#FF00FF]You cast Cloak! (50%% chance enemy misses next attack)[/color]" % [])
			is_buff_ability = true

		"blast":
			# Apply Gnome racial and Sage mana cost reduction
			var blast_cost = mana_cost
			var gnome_mult = character.get_ability_cost_multiplier()
			if gnome_mult < 1.0:
				blast_cost = int(blast_cost * gnome_mult)
			if passive_effects.has("mana_cost_reduction"):
				blast_cost = int(blast_cost * (1.0 - passive_effects.get("mana_cost_reduction", 0)))
			blast_cost = max(1, blast_cost)
			if not character.use_mana(blast_cost):
				return {"success": false, "messages": ["[color=#FF4444]Not enough mana! (Need %d)[/color]" % blast_cost], "combat_ended": false, "skip_monster_turn": true}
			if blast_cost < mana_cost:
				messages.append("[color=#20B2AA]Cost reduced to %d mana![/color]" % blast_cost)
			# Base damage 50, scaled by INT (+4% per point) and multiplied by 2
			var int_stat = character.get_effective_stat("intelligence")
			var int_multiplier = 1.0 + (int_stat * 0.04)  # +4% per INT point
			var base_damage = int(50 * int_multiplier * 2)  # Blast = Magic Ã— 2
			var damage_buff = character.get_buff_value("damage")
			base_damage = int(base_damage * (1.0 + damage_buff / 100.0))

			# === CLASS PASSIVE: Wizard Arcane Precision ===
			if passive_effects.has("spell_damage_bonus"):
				base_damage = int(base_damage * (1.0 + passive_effects.get("spell_damage_bonus", 0)))

			# === CLASS PASSIVE: Sorcerer Chaos Magic ===
			if passive_effects.has("double_damage_chance"):
				var chaos_roll = randf()
				if chaos_roll < passive_effects.get("backfire_chance", 0.10):
					var backfire_dmg = mini(int(base_damage * 0.5), int(character.get_total_max_hp() * 0.15))
					character.current_hp -= backfire_dmg
					character.current_hp = max(1, character.current_hp)
					base_damage = int(base_damage * 0.5)
					messages.append("[color=#9400D3]Chaos Magic backfires for %d damage![/color]" % backfire_dmg)
				elif chaos_roll < passive_effects.get("backfire_chance", 0.10) + passive_effects.get("double_damage_chance", 0.25):
					base_damage = base_damage * 2
					messages.append("[color=#9400D3]Chaos Magic: DOUBLE DAMAGE![/color]")

			# === CLASS PASSIVE: Wizard Spell Crit ===
			if passive_effects.has("spell_crit_bonus"):
				var spell_crit_chance = int(passive_effects.get("spell_crit_bonus", 0) * 100)
				if randi() % 100 < spell_crit_chance:
					base_damage = int(base_damage * 1.5)
					messages.append("[color=#4169E1]Spell Critical![/color]")

			var damage = apply_damage_variance(base_damage)
			monster.current_hp -= damage
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#FF00FF]You cast Blast![/color]")
			messages.append("[color=#00FFFF]The explosion deals %d damage![/color]" % damage)
			# Apply burn DoT (20% of INT per round for 3 rounds)
			var burn_damage = max(1, int(int_stat * 0.2))
			combat["monster_burn"] = burn_damage
			combat["monster_burn_duration"] = 3
			messages.append("[color=#FF6600]The target is burning! (%d damage/round for 3 rounds)[/color]" % burn_damage)

		"forcefield":
			if not character.use_mana(mana_cost):
				return {"success": false, "messages": ["[color=#FF4444]Not enough mana! (Need %d)[/color]" % mana_cost], "combat_ended": false, "skip_monster_turn": true}
			# Forcefield provides flat damage absorption = 100 + INT Ã— 8 (high scaling)
			var int_stat = character.get_effective_stat("intelligence")
			var shield_value = 100 + (int_stat * 8)
			combat["forcefield_shield"] = shield_value
			messages.append("[color=#FF00FF]You cast Forcefield! (Absorbs next %d damage)[/color]" % shield_value)
			is_buff_ability = true

		"teleport":
			if not character.use_mana(mana_cost):
				return {"success": false, "messages": ["[color=#FF4444]Not enough mana! (Need %d)[/color]" % mana_cost], "combat_ended": false, "skip_monster_turn": true}
			messages.append("[color=#FF00FF]You cast Teleport and vanish![/color]")
			return {
				"success": true,
				"messages": messages,
				"combat_ended": true,
				"fled": true,
				"skip_monster_turn": true
			}

		"meteor":
			# Apply Gnome racial and Sage mana cost reduction
			var meteor_cost = mana_cost
			var gnome_mult = character.get_ability_cost_multiplier()
			if gnome_mult < 1.0:
				meteor_cost = int(meteor_cost * gnome_mult)
			if passive_effects.has("mana_cost_reduction"):
				meteor_cost = int(meteor_cost * (1.0 - passive_effects.get("mana_cost_reduction", 0)))
			meteor_cost = max(1, meteor_cost)
			if not character.use_mana(meteor_cost):
				return {"success": false, "messages": ["[color=#FF4444]Not enough mana! (Need %d)[/color]" % meteor_cost], "combat_ended": false, "skip_monster_turn": true}
			if meteor_cost < mana_cost:
				messages.append("[color=#20B2AA]Cost reduced to %d mana![/color]" % meteor_cost)
			# Base damage 100, scaled by INT (+4% per point), multiplied by 3-4x (random)
			var int_stat = character.get_effective_stat("intelligence")
			var int_multiplier = 1.0 + (int_stat * 0.04)  # +4% per INT point
			var meteor_mult = 3.0 + randf()  # 3.0 to 4.0x random multiplier
			var base_damage = int(100 * int_multiplier * meteor_mult)
			var damage_buff = character.get_buff_value("damage")
			base_damage = int(base_damage * (1.0 + damage_buff / 100.0))

			# === CLASS PASSIVE: Wizard Arcane Precision ===
			if passive_effects.has("spell_damage_bonus"):
				base_damage = int(base_damage * (1.0 + passive_effects.get("spell_damage_bonus", 0)))

			# === CLASS PASSIVE: Sorcerer Chaos Magic ===
			if passive_effects.has("double_damage_chance"):
				var chaos_roll = randf()
				if chaos_roll < passive_effects.get("backfire_chance", 0.10):
					var backfire_dmg = mini(int(base_damage * 0.5), int(character.get_total_max_hp() * 0.15))
					character.current_hp -= backfire_dmg
					character.current_hp = max(1, character.current_hp)
					base_damage = int(base_damage * 0.5)
					messages.append("[color=#9400D3]Chaos Magic backfires for %d damage![/color]" % backfire_dmg)
				elif chaos_roll < passive_effects.get("backfire_chance", 0.10) + passive_effects.get("double_damage_chance", 0.25):
					base_damage = base_damage * 2
					messages.append("[color=#9400D3]Chaos Magic: DOUBLE DAMAGE![/color]")

			# === CLASS PASSIVE: Wizard Spell Crit ===
			if passive_effects.has("spell_crit_bonus"):
				var spell_crit_chance = int(passive_effects.get("spell_crit_bonus", 0) * 100)
				if randi() % 100 < spell_crit_chance:
					base_damage = int(base_damage * 1.5)
					messages.append("[color=#4169E1]Spell Critical![/color]")

			var damage = apply_damage_variance(base_damage)
			monster.current_hp -= damage
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#FFD700][b]METEOR![/b][/color]")
			messages.append("[color=#FF4444]A massive meteor crashes down for %d damage![/color]" % damage)

		"haste":
			# Speed buff - reduces monster attacks and increases player dodge
			if not character.use_mana(mana_cost):
				return {"success": false, "messages": ["[color=#FF4444]Not enough mana! (Need %d)[/color]" % mana_cost], "combat_ended": false, "skip_monster_turn": true}
			var speed_bonus = 20 + int(character.get_effective_stat("intelligence") / 5)
			character.add_buff("speed", speed_bonus, 5)
			combat["haste_active"] = true
			messages.append("[color=#00FFFF]You cast Haste! (+%d%% speed for 5 rounds)[/color]" % speed_bonus)
			is_buff_ability = true

		"paralyze":
			# Attempt to stun monster for 1-2 turns, with diminishing returns
			if not character.use_mana(mana_cost):
				return {"success": false, "messages": ["[color=#FF4444]Not enough mana! (Need %d)[/color]" % mana_cost], "combat_ended": false, "skip_monster_turn": true}
			var int_stat = character.get_effective_stat("intelligence")
			var cc_resist = combat.get("cc_resistance", 0)
			var resist_penalty = cc_resist * 20  # -20% per prior CC
			var success_chance = mini(85, 50 + int(int_stat / 2)) - resist_penalty
			success_chance = maxi(10, success_chance)  # 10% floor for Paralyze
			if randf() * 100 < success_chance:
				var stun_duration = 1 + (randi() % 2)  # 1-2 turns
				combat["monster_stunned"] = stun_duration
				combat["cc_resistance"] = cc_resist + 1
				messages.append("[color=#FFFF00]You paralyze the %s for %d turn(s)![/color]" % [monster.name, stun_duration])
				is_buff_ability = true  # 75% chance to avoid monster's retaliation while casting
			else:
				messages.append("[color=#FF4444]The %s resists your paralysis![/color]" % monster.name)
			if cc_resist > 0:
				messages.append("[color=#808080](Enemy CC resistance: %d%%)[/color]" % (cc_resist * 20))

		"banish":
			# Attempt to remove monster from combat with 50% loot chance
			if not character.use_mana(mana_cost):
				return {"success": false, "messages": ["[color=#FF4444]Not enough mana! (Need %d)[/color]" % mana_cost], "combat_ended": false, "skip_monster_turn": true}
			var int_stat = character.get_effective_stat("intelligence")
			var success_chance = 40 + int(int_stat / 3)  # 40% base + 0.33% per INT
			success_chance = min(75, success_chance)  # Cap at 75%
			if randf() * 100 < success_chance:
				messages.append("[color=#FF00FF]You banish the %s to another dimension![/color]" % monster.name)
				# 50% chance to get loot from banished monster
				if randf() < 0.5:
					messages.append("[color=#FFD700]The creature drops something as it vanishes![/color]")
					return _process_victory_with_abilities(combat, messages)
				else:
					messages.append("[color=#808080]The creature vanishes without a trace...[/color]")
					return {
						"success": true,
						"messages": messages,
						"combat_ended": true,
						"victory": false,
						"fled": true,
						"skip_monster_turn": true
					}
			else:
				messages.append("[color=#FF4444]The %s resists being banished![/color]" % monster.name)

	# Check if monster died
	if monster.current_hp <= 0:
		return _process_victory(combat, messages)

	return {"success": true, "messages": messages, "combat_ended": false, "buff_ability": is_buff_ability}

func _process_warrior_ability(combat: Dictionary, ability_name: String) -> Dictionary:
	"""Process warrior abilities (use stamina)"""
	var character = combat.character
	var monster = combat.monster
	var messages = []
	var is_buff_ability = false  # Buff abilities only give monster 25% chance to attack

	# Check STR requirement for warrior path
	if character.get_stat("strength") <= 10:
		return {"success": false, "messages": ["[color=#FF4444]You need STR > 10 to use warrior abilities![/color]"], "combat_ended": false}

	# Get ability info
	var ability_info = _get_ability_info("warrior", ability_name)
	if ability_info.is_empty():
		return {"success": false, "messages": ["[color=#FF4444]Unknown warrior ability![/color]"], "combat_ended": false}

	# Check level requirement
	if character.level < ability_info.level:
		return {"success": false, "messages": ["[color=#FF4444]%s requires level %d![/color]" % [ability_info.name, ability_info.level]], "combat_ended": false}

	var base_stamina_cost = ability_info.cost
	var stamina_cost = apply_skill_cost_reduction(character, ability_name, base_stamina_cost)

	# Show skill enhancement message only if player has skill enhancement (not just racial)
	var skill_reduction = character.get_skill_cost_reduction(ability_name)
	if skill_reduction > 0:
		messages.append("[color=#00FFFF]Skill Enhancement: -%d%% cost![/color]" % int(skill_reduction))

	var passive = character.get_class_passive()
	var passive_effects = passive.get("effects", {})

	# === CLASS PASSIVE: Fighter Tactical Discipline ===
	# 20% reduced stamina costs
	if passive_effects.has("stamina_cost_reduction"):
		stamina_cost = max(1, int(stamina_cost * (1.0 - passive_effects.get("stamina_cost_reduction", 0))))
		messages.append("[color=#C0C0C0]Tactical Discipline: Only costs %d stamina![/color]" % stamina_cost)

	# === CLASS PASSIVE: Barbarian Blood Rage ===
	# Abilities cost 25% more
	if passive_effects.has("stamina_cost_increase"):
		stamina_cost = int(stamina_cost * (1.0 + passive_effects.get("stamina_cost_increase", 0)))

	if not character.use_stamina(stamina_cost):
		return {"success": false, "messages": ["[color=#FF4444]Not enough stamina! (Need %d)[/color]" % stamina_cost], "combat_ended": false, "skip_monster_turn": true}

	# Use total attack (includes weapon) for physical abilities
	var total_attack = character.get_total_attack()

	# Get damage buff (War Cry, Berserk) to apply to ability damage
	var damage_buff = character.get_buff_value("damage")
	var damage_multiplier = 1.0 + (damage_buff / 100.0)

	match ability_name:
		"power_strike":
			# Buffed: 2Ã— damage multiplier (was 1.5Ã—), sqrt STR scaling
			var str_stat = character.get_effective_stat("strength")
			var str_mult = 1.0 + (sqrt(float(str_stat)) / 10.0)  # Sqrt scaling
			var base_dmg = int(total_attack * 2.0 * damage_multiplier * str_mult)  # 2Ã— (was 1.5Ã—)
			# Apply skill enhancement damage bonus
			var enhanced_dmg = apply_skill_damage_bonus(character, "power_strike", base_dmg)
			if enhanced_dmg > base_dmg:
				messages.append("[color=#00FFFF]Skill Enhancement: +%d%% damage![/color]" % int(character.get_skill_damage_bonus("power_strike")))
				base_dmg = enhanced_dmg
			var mod_dmg = apply_ability_damage_modifiers(base_dmg, character.level, monster)
			var damage = apply_damage_variance(mod_dmg)
			monster.current_hp -= damage
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#FF4444]POWER STRIKE![/color]")
			messages.append("[color=#FFFF00]You deal %d damage![/color]" % damage)

		"war_cry":
			# Buffed: +35% damage (was +25%) for 4 rounds (was 3)
			character.add_buff("damage", 35, 4)
			messages.append("[color=#FF4444]WAR CRY![/color]")
			messages.append("[color=#FFD700]+35%% damage for 4 rounds![/color]" % [])
			is_buff_ability = true

		"shield_bash":
			# 1.5x damage multiplier, sqrt STR scaling, diminishing stun chance
			var str_stat = character.get_effective_stat("strength")
			var str_mult = 1.0 + (sqrt(float(str_stat)) / 10.0)
			var base_dmg = int(total_attack * 1.5 * damage_multiplier * str_mult)
			var mod_dmg = apply_ability_damage_modifiers(base_dmg, character.level, monster)
			var damage = apply_damage_variance(mod_dmg)
			monster.current_hp -= damage
			monster.current_hp = max(0, monster.current_hp)
			# Diminishing stun chance: 100% → 75% → 50% → 25% → 20% floor
			var cc_resist = combat.get("cc_resistance", 0)
			var stun_chance = maxi(20, 100 - cc_resist * 25)
			messages.append("[color=#FF4444]SHIELD BASH![/color]")
			if randi() % 100 < stun_chance:
				combat["monster_stunned"] = 1  # Enemy skips next turn
				combat["cc_resistance"] = cc_resist + 1
				messages.append("[color=#FFFF00]You deal %d damage and stun the enemy![/color]" % damage)
			else:
				messages.append("[color=#FFFF00]You deal %d damage but the enemy resists the stun![/color]" % damage)
			if cc_resist > 0:
				messages.append("[color=#808080](Enemy CC resistance: %d%%)[/color]" % (cc_resist * 25))

		"cleave":
			# Buffed: 2.5Ã— damage multiplier (was 2Ã—), sqrt STR scaling
			var str_stat = character.get_effective_stat("strength")
			var str_mult = 1.0 + (sqrt(float(str_stat)) / 10.0)
			var base_dmg = int(total_attack * 2.5 * damage_multiplier * str_mult)  # 2.5Ã— (was 2Ã—)
			var mod_dmg = apply_ability_damage_modifiers(base_dmg, character.level, monster)
			var damage = apply_damage_variance(mod_dmg)
			monster.current_hp -= damage
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#FF4444]CLEAVE![/color]")
			messages.append("[color=#FFFF00]Your massive swing deals %d damage![/color]" % damage)
			# Apply bleed DoT (20% of STR per round for 4 rounds)
			var bleed_damage = max(1, int(str_stat * 0.20))  # Buffed from 15%
			combat["monster_bleed"] = bleed_damage
			combat["monster_bleed_duration"] = 4
			messages.append("[color=#FF4444]The target is bleeding! (%d damage/round for 4 rounds)[/color]" % bleed_damage)

		"berserk":
			# Buffed: +75% to +200% damage (was +50% to +150%)
			var hp_percent = float(character.current_hp) / float(character.get_total_max_hp())
			var missing_hp_percent = 1.0 - hp_percent
			var damage_bonus = int(75 + (missing_hp_percent * 125))  # 75-200% (was 50-150%)
			character.add_buff("damage", damage_bonus, 4)  # 4 rounds (was 3)
			character.add_buff("defense_penalty", -40, 4)  # Reduced penalty from -50%
			messages.append("[color=#FF0000][b]BERSERK![/b][/color]")
			messages.append("[color=#FFD700]+%d%% damage (scales with missing HP), -40%% defense for 4 rounds![/color]" % damage_bonus)

		"iron_skin":
			# Buffed: 60% damage reduction (was 50%) for 4 rounds (was 3)
			character.add_buff("damage_reduction", 60, 4)
			messages.append("[color=#AAAAAA]IRON SKIN![/color]")
			messages.append("[color=#00FF00]Block 60%% damage for 4 rounds![/color]" % [])
			is_buff_ability = true

		"devastate":
			# Buffed: 5Ã— damage (was 4Ã—), sqrt STR scaling
			var str_stat = character.get_effective_stat("strength")
			var str_mult = 1.0 + (sqrt(float(str_stat)) / 10.0)
			var base_dmg = int(total_attack * 5.0 * damage_multiplier * str_mult)  # 5Ã— (was 4Ã—)
			var mod_dmg = apply_ability_damage_modifiers(base_dmg, character.level, monster)
			var damage = apply_damage_variance(mod_dmg)
			monster.current_hp -= damage
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#FF0000][b]DEVASTATE![/b][/color]")
			messages.append("[color=#FFFF00]A catastrophic blow deals %d damage![/color]" % damage)

		"fortify":
			# Buffed: Higher base defense, sqrt STR scaling
			var str_stat = character.get_effective_stat("strength")
			var defense_bonus = 30 + int(sqrt(float(str_stat)) * 3)  # 30% base + sqrt(STR)Ã—3
			character.add_buff("defense", defense_bonus, 5)
			messages.append("[color=#00FFFF]You fortify your defenses! (+%d%% defense for 5 rounds)[/color]" % defense_bonus)
			is_buff_ability = true

		"rally":
			# Buffed: Better heal scaling with sqrt CON
			var con_stat = character.get_effective_stat("constitution")
			var heal_amount = 30 + int(sqrt(float(con_stat)) * 10)  # 30 base + sqrt(CON)Ã—10
			var actual_heal = character.heal(heal_amount)
			var str_bonus = 10 + int(character.get_effective_stat("strength") / 5)
			character.add_buff("strength", str_bonus, 3)
			messages.append("[color=#00FF00]You rally your strength! Healed %d HP, +%d STR for 3 rounds![/color]" % [actual_heal, str_bonus])
			is_buff_ability = true

	# Check if monster died
	if monster.current_hp <= 0:
		return _process_victory(combat, messages)

	return {"success": true, "messages": messages, "combat_ended": false, "buff_ability": is_buff_ability}

func _process_trickster_ability(combat: Dictionary, ability_name: String) -> Dictionary:
	"""Process trickster abilities (use energy)"""
	var character = combat.character
	var monster = combat.monster
	var messages = []
	var is_buff_ability = false  # Buff/debuff abilities only give monster 25% chance to attack

	# Check WITS requirement for trickster path
	if character.get_stat("wits") <= 10:
		return {"success": false, "messages": ["[color=#FF4444]You need WITS > 10 to use trickster abilities![/color]"], "combat_ended": false}

	# Get ability info
	var ability_info = _get_ability_info("trickster", ability_name)
	if ability_info.is_empty():
		return {"success": false, "messages": ["[color=#FF4444]Unknown trickster ability![/color]"], "combat_ended": false}

	# Check level requirement
	if character.level < ability_info.level:
		return {"success": false, "messages": ["[color=#FF4444]%s requires level %d![/color]" % [ability_info.name, ability_info.level]], "combat_ended": false}

	var base_energy_cost = ability_info.cost
	var energy_cost = apply_skill_cost_reduction(character, ability_name, base_energy_cost)

	if energy_cost < base_energy_cost and energy_cost > 0:
		messages.append("[color=#00FFFF]Skill Enhancement: -%d%% cost![/color]" % int(character.get_skill_cost_reduction(ability_name)))
	elif energy_cost == 0 and base_energy_cost > 0:
		messages.append("[color=#00FFFF]Skill Enhancement: FREE![/color]")

	if not character.use_energy(energy_cost):
		return {"success": false, "messages": ["[color=#FF4444]Not enough energy! (Need %d)[/color]" % energy_cost], "combat_ended": false, "skip_monster_turn": true}

	match ability_name:
		"analyze":
			messages.append("[color=#00FF00]ANALYZE![/color]")
			messages.append("[color=#808080]%s (Level %d)[/color]" % [monster.name, monster.level])
			messages.append("[color=#FF4444]HP:[/color] %d/%d" % [monster.current_hp, monster.max_hp])
			messages.append("[color=#FFFF00]Damage:[/color] ~%d" % monster.strength)
			var monster_int = monster.get("intelligence", 15)
			messages.append("[color=#FFA500]Intelligence:[/color] %d" % monster_int)

			# Calculate and show outsmart chance (must match process_outsmart formula)
			var player_wits = character.get_effective_stat("wits")
			var is_trickster = character.class_type in ["Thief", "Ranger", "Ninja"]
			var player_level = character.level
			var monster_level = monster.level
			var base_chance = 5
			# Logarithmic WITS scaling
			var wits_bonus = 0
			if player_wits > 10:
				wits_bonus = int(18.0 * log(float(player_wits) / 10.0) / log(2.0))
			var trickster_bonus = 20 if is_trickster else 0
			var dumb_bonus = max(0, (10 - monster_int) * 3)
			var smart_penalty = max(0, monster_int - 10)  # -1% per INT above 10
			var int_vs_wits_penalty = max(0, (monster_int - player_wits) * 2)
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
			var level_bonus = 0
			if level_diff < 0:
				level_bonus = min(15, abs(level_diff))
			var outsmart_chance = base_chance + wits_bonus + trickster_bonus + dumb_bonus + level_bonus - smart_penalty - int_vs_wits_penalty - level_penalty
			# INT-based cap
			var base_max_chance = 85 if is_trickster else 70
			var max_chance = max(30, base_max_chance - int(monster_int / 3))
			outsmart_chance = clampi(outsmart_chance, 2, max_chance)
			var level_warning = ""
			if level_diff > 10:
				level_warning = " [color=#FF4444](Lv%+d penalty!)[/color]" % level_diff
			elif level_diff > 0:
				level_warning = " [color=#FFA500](Lv%+d)[/color]" % level_diff
			messages.append("[color=#00FFFF]Outsmart Chance:[/color] %d%%%s" % [outsmart_chance, level_warning])

			# Grant +10% damage bonus for rest of combat
			combat["analyze_bonus"] = 10
			messages.append("[color=#00FF00]+10%% damage bonus for this combat![/color]" % [])
			# Skip monster turn for analyze (information only)
			# Include revealed HP data for client health bar update
			return {
				"success": true,
				"messages": messages,
				"combat_ended": false,
				"skip_monster_turn": true,
				"revealed_enemy_hp": monster.max_hp,
				"revealed_enemy_current_hp": monster.current_hp
			}

		"distract":
			combat["enemy_distracted"] = true  # -50% accuracy next attack
			messages.append("[color=#00FF00]DISTRACT![/color]")
			messages.append("[color=#808080]The enemy is distracted! (-50%% accuracy)[/color]" % [])
			is_buff_ability = true

		"pickpocket":
			# Check if monster has anything left to steal
			var pp_count = combat.get("pickpocket_count", 0)
			var pp_max = combat.get("pickpocket_max", 2)
			if pp_count >= pp_max:
				messages.append("[color=#808080]The enemy has nothing left to steal![/color]")
				return {"success": true, "messages": messages, "combat_ended": false, "skip_monster_turn": false}
			var wits = character.get_effective_stat("wits")
			var success_chance = 50 + wits - monster.get("intelligence", 15)
			success_chance = clampi(success_chance, 10, 90)
			var roll = randi() % 100
			if roll < success_chance:
				combat["pickpocket_count"] = pp_count + 1
				# Steal salvage essence based on monster tier
				var monster_tier = monster.get("tier", 1)
				var stolen_essence = 5 + (monster_tier * 3) + (wits / 10)
				character.salvage_essence = character.get("salvage_essence", 0) + stolen_essence
				messages.append("[color=#00FF00]PICKPOCKET SUCCESS![/color]")
				messages.append("[color=#FFD700]You steal %d salvage essence![/color]" % stolen_essence)
				return {"success": true, "messages": messages, "combat_ended": false, "skip_monster_turn": true}
			else:
				messages.append("[color=#FF4444]PICKPOCKET FAILED![/color]")
				messages.append("[color=#808080]The enemy catches you![/color]")
				# Enemy gets free attack
				var monster_result = process_monster_turn(combat)
				messages.append("[color=#444444]─────────────────────────────[/color]")
				messages.append(_indent_multiline(monster_result.message, "         "))
				messages.append("[color=#444444]─────────────────────────────[/color]")
				if character.current_hp <= 0:
					return {
						"success": true,
						"messages": messages,
						"combat_ended": true,
						"victory": false,
						"monster_name": "%s (Lvl %d)" % [monster.name, monster.level]
					}
				return {"success": true, "messages": messages, "combat_ended": false, "skip_monster_turn": true}

		"ambush":
			# Ambush: 3Ã— multiplier, 50% crit chance, sqrt WITS scaling
			var wits_stat = character.get_effective_stat("wits")
			var wits_mult = 1.0 + (sqrt(float(wits_stat)) / 10.0)  # Sqrt scaling for WITS
			var base_damage = character.get_total_attack()
			var damage_buff = character.get_buff_value("damage")
			var damage_multiplier = 1.0 + (damage_buff / 100.0)
			var base_dmg = int(base_damage * 3.0 * damage_multiplier * wits_mult)  # 3Ã— multiplier
			var mod_dmg = apply_ability_damage_modifiers(base_dmg, character.level, monster)
			var damage = apply_damage_variance(mod_dmg)
			# 50% crit chance
			if randi() % 100 < 50:
				damage = int(damage * 1.5)
				messages.append("[color=#FFD700]CRITICAL AMBUSH![/color]")
			else:
				messages.append("[color=#00FF00]AMBUSH![/color]")
			monster.current_hp -= damage
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#FFFF00]You deal %d damage![/color]" % damage)

		"vanish":
			# Auto-crit on next attack, skips monster turn
			combat["vanished"] = true  # Next attack auto-crits
			messages.append("[color=#00FF00]VANISH![/color]")
			messages.append("[color=#808080]You fade into shadow... Next attack will crit![/color]")
			return {"success": true, "messages": messages, "combat_ended": false, "skip_monster_turn": true}

		"exploit":
			# FIXED: Uses monster's MAX HP, not current HP. Scales with WIT.
			var wits = character.get_effective_stat("wits")
			var base_percent = 15 + int(wits / 4)  # 15% base + 0.25% per WIT
			base_percent = min(35, base_percent)  # Cap at 35%
			var damage = int(monster.max_hp * (base_percent / 100.0))
			damage = max(10, damage)  # Minimum 10 damage
			monster.current_hp -= damage
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#00FF00]EXPLOIT WEAKNESS![/color]")
			messages.append("[color=#FFFF00]You exploit a weakness for %d damage! (%d%% of max HP)[/color]" % [damage, base_percent])

		"perfect_heist":
			# Chance-based instant win with slight bonus rewards
			# NERFED: Much harder against higher level monsters, smaller rewards
			var wits = character.get_effective_stat("wits")
			var monster_int = monster.get("intelligence", 15)
			var level_diff = monster.level - character.level

			# Base 30% success, +1.5% per wits over monster intelligence
			var success_chance = 30 + int((wits - monster_int) * 1.5)
			# Heavy penalty for fighting above your level: -2% per level difference
			if level_diff > 0:
				success_chance -= level_diff * 2
			# Cap at 5-60% (was 20-90%)
			success_chance = clampi(success_chance, 5, 60)

			var roll = randi() % 100
			if roll < success_chance:
				messages.append("[color=#FFD700][b]PERFECT HEIST![/b][/color]")
				messages.append("[color=#00FF00]You execute a flawless heist![/color]")

				# Slight bonus XP (1.25x, was 2x)
				var base_xp = int(monster.experience_reward * 1.25)
				# Small bonus for level difference, capped at 1.5x max
				var xp_multiplier = 1.0
				if level_diff > 0:
					xp_multiplier = 1.0 + min(0.5, level_diff * 0.02)  # +2% per level, max +50%

				var final_xp = int(base_xp * xp_multiplier * 1.10)  # +10% XP boost

				var heist_old_level = character.level
				var level_result = character.add_experience(final_xp)

				messages.append("[color=#FF00FF]+%d XP[/color]" % final_xp)

				if level_result.leveled_up:
					messages.append("[color=#FFD700][b]LEVEL UP![/b] You are now level %d![/color]" % level_result.new_level)

					# Check for newly unlocked abilities
					var new_abilities = character.get_newly_unlocked_abilities(heist_old_level, level_result.new_level)
					if new_abilities.size() > 0:
						messages.append("")
						messages.append("[color=#00FFFF]+======================================+[/color]")
						messages.append("[color=#00FFFF]|[/color]  [color=#FFFF00][b]NEW ABILITY UNLOCKED![/b][/color]")
						for ability in new_abilities:
							var ability_type = "Universal" if ability.get("universal", false) else "Class"
							messages.append("[color=#00FFFF]|[/color]  [color=#00FF00]*[/color] [color=#FFFFFF]%s[/color] [color=#808080](%s)[/color]" % [ability.display, ability_type])
						messages.append("[color=#00FFFF]|[/color]  [color=#808080]Check Abilities menu to equip![/color]")
						messages.append("[color=#00FFFF]+======================================+[/color]")

				# Roll for item drops (normal chance, was doubled)
				var dropped_items = []
				var gems_earned = 0
				if drop_tables:
					var drops_result = drop_tables.roll_drops(
						monster.get("drop_table_id", "tier1"),
						monster.get("drop_chance", 5),
						monster.level
					)
					dropped_items = drops_result
					gems_earned = roll_gem_drops(monster, character)
					if gems_earned > 0:
						character.add_crafting_material("monster_gem", gems_earned)
						messages.append("[color=#00FFFF]+ + [/color][color=#FF00FF]+%d Monster Gem%s![/color][color=#00FFFF] + +[/color]" % [gems_earned, "s" if gems_earned > 1 else ""])

				return {
					"success": true,
					"messages": messages,
					"combat_ended": true,
					"victory": true,
					"monster_name": monster.name,
					"monster_level": monster.level,
					"flock_chance": 0,  # No flock after perfect heist
					"dropped_items": dropped_items,
					"gems_earned": gems_earned,
					"skip_monster_turn": true,
					"is_dungeon_combat": combat.get("is_dungeon_combat", false),
					"is_boss_fight": combat.get("is_boss_fight", false)
				}
			else:
				# Failed heist - take damage and combat continues
				messages.append("[color=#FF4444][b]HEIST FAILED![/b][/color]")
				messages.append("[color=#FF4444]You're caught mid-heist![/color]")
				# Monster gets a free attack
				var monster_result = process_monster_turn(combat)
				messages.append("[color=#444444]─────────────────────────────[/color]")
				messages.append(_indent_multiline(monster_result.message, "         "))
				messages.append("[color=#444444]─────────────────────────────[/color]")
				if character.current_hp <= 0:
					return {
						"success": true,
						"messages": messages,
						"combat_ended": true,
						"victory": false,
						"monster_name": "%s (Lvl %d)" % [monster.name, monster.level]
					}
				return {"success": true, "messages": messages, "combat_ended": false, "skip_monster_turn": true}

		"sabotage":
			# Weaken monster - reduce strength and defense
			var wits = character.get_effective_stat("wits")
			var debuff_amount = 15 + int(wits / 3)  # 15% base + 0.33% per WITS
			# Store debuffs in combat state
			var existing_sabotage = combat.get("monster_sabotaged", 0)
			combat["monster_sabotaged"] = min(50, existing_sabotage + debuff_amount)  # Cap at 50%
			messages.append("[color=#FFA500]You sabotage the %s! (-%d%% strength/defense)[/color]" % [monster.name, debuff_amount])
			is_buff_ability = true

		"gambit":
			# High-risk, high-reward ability - big damage with WITS scaling, bonus loot on kill
			var wits = character.get_effective_stat("wits")
			var success_chance = 55 + int(wits / 4)  # 55% base + 0.25% per WITS
			success_chance = min(80, success_chance)  # Cap at 80%

			if randf() * 100 < success_chance:
				# Success - deal big damage with WITS scaling (4.5Ã— multiplier)
				var wits_mult = 1.0 + (sqrt(float(wits)) / 10.0)  # Same scaling as Ambush
				var total_attack = character.get_total_attack() + character.get_buff_value("strength")
				var damage_buff = character.get_buff_value("damage")
				var damage_multiplier = 1.0 + (damage_buff / 100.0)
				var base_dmg = int(total_attack * 4.5 * damage_multiplier * wits_mult)
				var mod_dmg = apply_ability_damage_modifiers(base_dmg, character.level, monster)
				var damage = apply_damage_variance(mod_dmg)
				monster.current_hp -= damage
				monster.current_hp = max(0, monster.current_hp)
				messages.append("[color=#FFD700][b]GAMBIT SUCCESS![/b][/color]")
				messages.append("[color=#00FF00]Your risky gambit pays off for %d damage![/color]" % damage)
				# Mark for bonus loot if this kills the monster
				if monster.current_hp <= 0:
					combat["gambit_kill"] = true
			else:
				# Failure - take damage yourself
				var self_damage = max(5, int(character.get_total_max_hp() * 0.15))  # 15% max HP
				character.current_hp -= self_damage
				character.current_hp = max(1, character.current_hp)  # Can't kill yourself
				messages.append("[color=#FF4444][b]GAMBIT FAILED![/b][/color]")
				messages.append("[color=#FF4444]Your gambit backfires for %d self-damage![/color]" % self_damage)

	# Check if monster died
	if monster.current_hp <= 0:
		return _process_victory(combat, messages)

	return {"success": true, "messages": messages, "combat_ended": false, "buff_ability": is_buff_ability}

func _get_ability_info(path: String, ability_name: String) -> Dictionary:
	"""Get ability info from constants"""
	# Universal abilities (available to all paths)
	match ability_name:
		"cloak": return {"level": 20, "cost": 0, "name": "Cloak", "universal": true}
		"all_or_nothing": return {"level": 1, "cost": 1, "name": "All or Nothing", "universal": true}

	match path:
		"mage":
			# Mage abilities use percentage-based mana costs for late-game scaling
			match ability_name:
				"magic_bolt": return {"level": 1, "cost": 0, "cost_percent": 0, "name": "Magic Bolt"}
				# Shield removed - use Forcefield instead
				"haste": return {"level": 30, "cost": 35, "cost_percent": 3, "name": "Haste"}
				"blast": return {"level": 40, "cost": 50, "cost_percent": 5, "name": "Blast"}
				"paralyze": return {"level": 50, "cost": 60, "cost_percent": 6, "name": "Paralyze"}
				"forcefield": return {"level": 10, "cost": 20, "cost_percent": 2, "name": "Forcefield"}
				"banish": return {"level": 70, "cost": 80, "cost_percent": 10, "name": "Banish"}
				"teleport": return {"level": 80, "cost": 40, "cost_percent": 0, "name": "Teleport"}  # Uses distance-based cost
				"meteor": return {"level": 100, "cost": 100, "cost_percent": 8, "name": "Meteor"}
		"warrior":
			match ability_name:
				"power_strike": return {"level": 1, "cost": 10, "name": "Power Strike"}
				"war_cry": return {"level": 10, "cost": 15, "name": "War Cry"}
				"shield_bash": return {"level": 25, "cost": 20, "name": "Shield Bash"}
				"fortify": return {"level": 35, "cost": 25, "name": "Fortify"}
				"cleave": return {"level": 40, "cost": 30, "name": "Cleave"}
				"rally": return {"level": 55, "cost": 35, "name": "Rally"}
				"berserk": return {"level": 60, "cost": 40, "name": "Berserk"}
				"iron_skin": return {"level": 80, "cost": 35, "name": "Iron Skin"}
				"devastate": return {"level": 100, "cost": 50, "name": "Devastate"}
		"trickster":
			match ability_name:
				"analyze": return {"level": 1, "cost": 5, "name": "Analyze"}
				"distract": return {"level": 10, "cost": 15, "name": "Distract"}
				"pickpocket": return {"level": 25, "cost": 20, "name": "Pickpocket"}
				"sabotage": return {"level": 30, "cost": 25, "name": "Sabotage"}
				"ambush": return {"level": 40, "cost": 30, "name": "Ambush"}
				"gambit": return {"level": 50, "cost": 35, "name": "Gambit"}
				"vanish": return {"level": 60, "cost": 40, "name": "Vanish"}
				"exploit": return {"level": 80, "cost": 35, "name": "Exploit"}
				"perfect_heist": return {"level": 100, "cost": 50, "name": "Perfect Heist"}
	return {}

func _process_victory(combat: Dictionary, messages: Array) -> Dictionary:
	"""Process monster defeat and return victory result - redirects to ability-aware version"""
	return _process_victory_with_abilities(combat, messages)

func apply_skill_cost_reduction(character: Character, ability_name: String, base_cost: int) -> int:
	"""Apply skill enhancement cost reduction and racial bonuses to an ability's cost.
	Returns the reduced cost (minimum 1 unless reduction is 100%)."""
	var cost = base_cost

	# Gnome racial: -15% ability costs
	var racial_mult = character.get_ability_cost_multiplier()
	if racial_mult < 1.0:
		cost = int(cost * racial_mult)

	# Skill enhancement cost reduction
	var cost_reduction = character.get_skill_cost_reduction(ability_name)
	if cost_reduction >= 100:
		return 0  # Free ability!
	if cost_reduction > 0:
		cost = int(cost * (1.0 - cost_reduction / 100.0))

	return max(1, cost)

func apply_skill_damage_bonus(character: Character, ability_name: String, base_damage: int) -> int:
	"""Apply skill enhancement damage bonus to an ability's damage.
	Returns the boosted damage."""
	var damage_bonus = character.get_skill_damage_bonus(ability_name)
	if damage_bonus <= 0:
		return base_damage
	return int(base_damage * (1.0 + damage_bonus / 100.0))

func process_use_item(peer_id: int, item_index: int) -> Dictionary:
	"""Process using an item during combat. Returns result with messages."""
	if not active_combats.has(peer_id):
		return {"success": false, "message": "You are not in combat!"}

	var combat = active_combats[peer_id]

	if not combat.player_can_act:
		return {"success": false, "message": "Wait for your turn!"}

	var character = combat.character
	var inventory = character.inventory

	if item_index < 0 or item_index >= inventory.size():
		return {"success": false, "message": "Invalid item!"}

	var item = inventory[item_index]
	var item_type = item.get("type", "")

	# Normalize item type for consumables (e.g., mana_minor -> mana_potion)
	var normalized_type = drop_tables._normalize_consumable_type(item_type)
	if normalized_type != item_type:
		item_type = normalized_type

	# Check if item is usable in combat
	if drop_tables == null:
		return {"success": false, "message": "Item system not available!"}

	var effect = drop_tables.get_potion_effect(item_type)
	if effect.is_empty():
		return {"success": false, "message": "This item cannot be used in combat!"}

	var messages = []
	var item_name = item.get("name", "item")
	var item_level = item.get("level", 1)
	var item_tier = int(item.get("tier", 0))  # int() ensures proper dict key lookup (JSON may store as float)

	# Infer tier from item name for legacy tier-based consumables
	if item_tier == 0 and _is_tier_based_consumable(item_type):
		item_tier = _infer_tier_from_name(item_name)

	# Get tier data for proper healing values
	var tier_data = {}
	if item_tier > 0 and drop_tables.CONSUMABLE_TIERS.has(item_tier):
		tier_data = drop_tables.CONSUMABLE_TIERS[item_tier]

	# Apply effect
	if effect.has("heal"):
		# Healing potion - hybrid flat + % max HP
		var heal_amount: int
		if effect.get("heal_pct_only", false):
			# Elixir: pure % max HP heal
			var elixir_pct = effect.get("elixir_pct", drop_tables.ELIXIR_HEAL_PCT.get(item_tier, 50))
			heal_amount = int(character.get_total_max_hp() * elixir_pct / 100.0)
		elif tier_data.has("healing"):
			# Tier-based: flat + % max HP
			heal_amount = tier_data.healing + int(character.get_total_max_hp() * tier_data.get("heal_pct", 0) / 100.0)
		else:
			heal_amount = effect.get("base", 0) + (effect.get("per_level", 0) * item_level)
		var actual_heal = character.heal(heal_amount)
		var heal_verb = "use" if "scroll" in item_type else "drink"
		messages.append("[color=#00FF00]You %s %s and restore %d HP![/color]" % [heal_verb, item_name, actual_heal])
	elif effect.has("mana") or effect.has("stamina") or effect.has("energy") or effect.has("resource"):
		# Resource potion - restores the player's PRIMARY resource based on class path
		var primary_resource = character.get_primary_resource()
		var max_resource: int
		match primary_resource:
			"mana": max_resource = character.get_total_max_mana()
			"stamina": max_resource = character.get_total_max_stamina()
			"energy": max_resource = character.get_total_max_energy()
			_: max_resource = character.get_total_max_mana()

		# Hybrid flat + % max resource
		var resource_amount: int
		if tier_data.has("resource"):
			resource_amount = tier_data.resource + int(max_resource * tier_data.get("resource_pct", 0) / 100.0)
		elif tier_data.has("healing"):
			resource_amount = int(tier_data.healing * 0.6)
		else:
			resource_amount = effect.get("base", 0) + (effect.get("per_level", 0) * item_level)

		var old_value: int
		var actual_restore: int
		var color: String

		match primary_resource:
			"mana":
				old_value = character.current_mana
				character.current_mana = min(character.get_total_max_mana(), character.current_mana + resource_amount)
				actual_restore = character.current_mana - old_value
				color = "#00FFFF"
			"stamina":
				old_value = character.current_stamina
				character.current_stamina = min(character.get_total_max_stamina(), character.current_stamina + resource_amount)
				actual_restore = character.current_stamina - old_value
				color = "#FFCC00"
			"energy":
				old_value = character.current_energy
				character.current_energy = min(character.get_total_max_energy(), character.current_energy + resource_amount)
				actual_restore = character.current_energy - old_value
				color = "#66FF66"
			_:
				old_value = character.current_mana
				character.current_mana = min(character.get_total_max_mana(), character.current_mana + resource_amount)
				actual_restore = character.current_mana - old_value
				color = "#00FFFF"
				primary_resource = "mana"

		var resource_verb = "use" if "scroll" in item_type else "drink"
		messages.append("[color=%s]You %s %s and restore %d %s![/color]" % [color, resource_verb, item_name, actual_restore, primary_resource])
	elif effect.has("buff"):
		# Buff scroll - tier-based values
		var buff_type = effect.buff
		var buff_value: int
		var duration: int

		if effect.get("tier_forcefield", false):
			# Forcefield: use forcefield_value from tier, duration from scroll_duration
			buff_value = tier_data.get("forcefield_value", 1500)
			duration = tier_data.get("scroll_duration", 1)
		elif effect.get("stat_pct", false):
			# Stat scroll: % of character's base stat
			var stat_pct = tier_data.get("scroll_stat_pct", 10)
			match buff_type:
				"strength": buff_value = maxi(1, int(character.get_total_strength() * stat_pct / 100.0))
				"defense": buff_value = maxi(1, int(character.get_total_defense() * stat_pct / 100.0))
				"speed": buff_value = maxi(1, int(character.get_total_speed() * stat_pct / 100.0))
				_: buff_value = maxi(1, int(character.get_total_strength() * stat_pct / 100.0))
			duration = tier_data.get("scroll_duration", 1)
		elif effect.get("tier_value", false):
			# Percentage scroll: use buff_value directly (lifesteal, thorns, crit %)
			buff_value = tier_data.get("buff_value", 3)
			duration = tier_data.get("scroll_duration", 1)
		elif tier_data.has("buff_value"):
			# Legacy tier-based fallback
			if buff_type == "forcefield" and tier_data.has("forcefield_value"):
				buff_value = tier_data.forcefield_value
			else:
				buff_value = tier_data.buff_value
			var base_duration = effect.get("base_duration", 5)
			var duration_per_10 = effect.get("duration_per_10_levels", 1)
			duration = base_duration + (item_level / 10) * duration_per_10
		else:
			buff_value = effect.get("base", 0) + (effect.get("per_level", 0) * item_level)
			var base_duration = effect.get("base_duration", 5)
			var duration_per_10 = effect.get("duration_per_10_levels", 1)
			duration = base_duration + (item_level / 10) * duration_per_10

		var buff_verb = "use" if "scroll" in item_type else "drink"
		var value_suffix = "%%" if buff_type in ["lifesteal", "thorns", "crit_chance"] else ""

		if effect.get("battles", false):
			character.add_persistent_buff(buff_type, buff_value, duration)
			messages.append("[color=#00FFFF]You %s %s! +%d%s %s for %d battle%s![/color]" % [buff_verb, item_name, buff_value, value_suffix, buff_type, duration, "s" if duration != 1 else ""])
		else:
			character.add_buff(buff_type, buff_value, duration)
			messages.append("[color=#00FFFF]You %s %s! +%d%s %s for %d rounds![/color]" % [buff_verb, item_name, buff_value, value_suffix, buff_type, duration])

	# Remove item from inventory (use stack method for consumables)
	if item.get("is_consumable", false) and item.get("quantity", 1) > 0:
		character.use_consumable_stack(item_index)
	else:
		character.remove_item(item_index)

	# Item use is a FREE ACTION - player can still act this turn
	# No monster turn, no round increment, no buff tick
	messages.append("[color=#808080](Free action - you may still act)[/color]")

	return {
		"success": true,
		"messages": messages,
		"combat_ended": false
	}

func process_monster_turn(combat: Dictionary) -> Dictionary:
	"""Process the monster's attack with all ability effects"""
	var character = combat.character
	var monster = combat.monster
	var abilities = monster.get("abilities", [])
	var messages = []

	# Check if monster is stunned (Shield Bash, Paralyze, or companion)
	var stun_turns = int(combat.get("monster_stunned", 0))
	if stun_turns > 0:
		combat["monster_stunned"] = stun_turns - 1
		if stun_turns - 1 <= 0:
			combat.erase("monster_stunned")
		if stun_turns == 1:
			return {"success": true, "message": "[color=#808080]The %s is stunned and cannot act![/color]" % monster.name}
		else:
			return {"success": true, "message": "[color=#808080]The %s is paralyzed and cannot act! (%d turn(s) remaining)[/color]" % [monster.name, max(0, stun_turns - 1)]}

	# Check for Time Stop scroll buff (monster skips turn)
	if character.has_buff("time_stop"):
		character.remove_buff("time_stop")
		return {"success": true, "message": "[color=#9932CC]Time freezes around the %s! It cannot move or act this turn![/color]" % monster.name}

	# Check for companion charm effect (monster skips turn)
	var charmed_turns = combat.get("monster_charmed", 0)
	if charmed_turns > 0:
		combat["monster_charmed"] = charmed_turns - 1
		return {"success": true, "message": "[color=#FF69B4]The %s is charmed and stands motionless![/color]" % monster.name}

	# Check for companion enemy_miss effect (guaranteed miss)
	var enemy_miss_turns = combat.get("companion_enemy_miss", 0)
	if enemy_miss_turns > 0:
		combat["companion_enemy_miss"] = enemy_miss_turns - 1
		return {"success": true, "message": "[color=#FFAA00]The %s attacks but misses completely![/color]" % monster.name}

	# === PRE-ATTACK ABILITIES ===

	# Coward ability: flee at 20% HP (no loot)
	if ABILITY_COWARD in abilities:
		var hp_percent = float(monster.current_hp) / float(monster.max_hp)
		if hp_percent <= 0.2:
			return {
				"success": true,
				"message": "[color=#FFD700]The %s flees in terror! It escapes with its loot...[/color]" % monster.name,
				"monster_fled": true
			}

	# Process burn DoT on monster (from Blast)
	var burn_raw = combat.get("monster_burn", 0)
	if burn_raw is Dictionary:
		# Legacy dict format: convert to unified format
		combat["monster_burn"] = int(burn_raw.get("damage", 0))
		combat["monster_burn_duration"] = int(burn_raw.get("rounds", 0))
		burn_raw = combat["monster_burn"]
	var m_burn_damage = int(burn_raw)
	var m_burn_duration = int(combat.get("monster_burn_duration", 0))
	if m_burn_damage > 0 and m_burn_duration > 0:
		monster.current_hp -= m_burn_damage
		monster.current_hp = max(0, monster.current_hp)
		combat["monster_burn_duration"] = m_burn_duration - 1
		messages.append("[color=#FF6600]The %s burns for %d damage![/color]" % [monster.name, m_burn_damage])
		if combat["monster_burn_duration"] <= 0:
			combat["monster_burn"] = 0
			messages.append("[color=#808080]The flames die out.[/color]")
		# Check if burn killed the monster
		if monster.current_hp <= 0:
			return _process_victory(combat, messages)

	# Process bleed DoT on monster (from Cleave and companions)
	# Unified int format: monster_bleed = damage per tick, monster_bleed_duration = rounds left
	var bleed_raw = combat.get("monster_bleed", 0)
	if bleed_raw is Dictionary:
		# Legacy dict format: convert to unified format
		combat["monster_bleed"] = int(bleed_raw.get("damage", 0))
		combat["monster_bleed_duration"] = int(bleed_raw.get("rounds", 0))
		bleed_raw = combat["monster_bleed"]
	var m_bleed_damage = int(bleed_raw)
	var m_bleed_duration = int(combat.get("monster_bleed_duration", 0))
	if m_bleed_damage > 0 and m_bleed_duration > 0:
		monster.current_hp -= m_bleed_damage
		monster.current_hp = max(0, monster.current_hp)
		combat["monster_bleed_duration"] = m_bleed_duration - 1
		messages.append("[color=#FF4444]The %s bleeds for %d damage![/color]" % [monster.name, m_bleed_damage])
		if combat["monster_bleed_duration"] <= 0:
			combat["monster_bleed"] = 0
			messages.append("[color=#808080]The bleeding stops.[/color]")
		if monster.current_hp <= 0:
			return _process_victory(combat, messages)

	# Regeneration ability: heal 10% HP per turn
	if ABILITY_REGENERATION in abilities:
		var heal_amount = max(1, int(monster.max_hp * 0.10))
		monster.current_hp = min(monster.max_hp, monster.current_hp + heal_amount)
		messages.append("[color=#00FF00]The %s regenerates %d HP![/color]" % [monster.name, heal_amount])

	# Enrage ability: +10% damage per round, capped at 10 stacks (100%)
	if ABILITY_ENRAGE in abilities:
		if combat.get("enrage_stacks", 0) < 10:
			combat["enrage_stacks"] = combat.get("enrage_stacks", 0) + 1
			if combat.enrage_stacks > 1:
				messages.append("[color=#FF4444]The %s grows more furious! (+%d%% damage)[/color]" % [monster.name, combat.enrage_stacks * 10])

	# === ATTACK CALCULATION ===

	# Monster hit chance: 85% base, +1% per monster level above player (cap 95%)
	var player_level = character.level
	var monster_level = monster.level
	var level_diff = monster_level - player_level
	var hit_chance = 85 + level_diff

	# DEX provides dodge chance: -1% hit chance per 5 DEX (max -30%)
	var player_dex = character.get_effective_stat("dexterity")
	var dex_dodge = min(30, int(player_dex / 5))
	hit_chance -= dex_dodge

	# WITS provides additional dodge for tricksters: -1% per 50 WITS (max -15%)
	var is_trickster = character.class_type in ["Thief", "Ranger", "Ninja"]
	if is_trickster:
		var player_wits = character.get_effective_stat("wits")
		var wits_dodge = min(15, int(player_wits / 50))
		hit_chance -= wits_dodge

	# Speed buff (from Haste, equipment, etc.) reduces monster hit chance
	var speed_buff = character.get_buff_value("speed")
	if speed_buff > 0:
		# Speed buff directly reduces hit chance (e.g., +20 speed = -10% hit chance)
		hit_chance -= int(speed_buff / 2)

	# Equipment speed bonus also helps dodge
	var equipment_bonuses = character.get_equipment_bonuses()
	var equipment_speed = equipment_bonuses.get("speed", 0)
	if equipment_speed > 0:
		hit_chance -= int(equipment_speed / 3)

	# Companion speed bonus helps dodge
	if character.has_active_companion():
		var comp_speed_dodge = int(character.get_companion_bonus("speed"))
		comp_speed_dodge += combat.get("companion_speed_bonus", 0)
		if comp_speed_dodge > 0:
			hit_chance -= int(comp_speed_dodge / 3)

	# Halfling racial: +10% dodge chance (reduces monster hit chance)
	var racial_dodge = character.get_dodge_bonus()
	if racial_dodge > 0:
		hit_chance -= int(racial_dodge * 100)

	# Companion dodge buff (from threshold ability)
	var companion_dodge = combat.get("companion_dodge_buff", 0)
	if companion_dodge > 0:
		hit_chance -= companion_dodge
		# Decrement duration
		var dodge_duration = combat.get("companion_dodge_duration", 0)
		if dodge_duration > 0:
			combat["companion_dodge_duration"] = dodge_duration - 1
			if dodge_duration - 1 <= 0:
				combat["companion_dodge_buff"] = 0

	# Armor rarity dodge bonus (from all equipped armor pieces)
	var armor_dodge_total = 0
	var armor_dr_total = 0.0
	var char_equipped = character.equipped if character else {}
	if char_equipped is Dictionary:
		for slot_name in ["armor", "helm", "shield", "boots"]:
			var armor_piece = char_equipped.get(slot_name, {})
			if armor_piece is Dictionary:
				var arb = armor_piece.get("rarity_bonuses", {})
				armor_dodge_total += int(arb.get("dodge", 0))
				armor_dr_total += float(arb.get("damage_reduction", 0))
	if armor_dodge_total > 0:
		hit_chance -= armor_dodge_total

	hit_chance = clamp(hit_chance, 40, 95)  # 40% minimum (can dodge well), 95% maximum

	# Ethereal ability: 50% chance for player attacks to miss (handled elsewhere)
	# but ethereal monsters also have lower hit chance
	if ABILITY_ETHEREAL in abilities:
		hit_chance -= 10  # Ethereal creatures are less precise

	# === CLASS PASSIVE: Ninja Shadow Step ===
	# Take no damage after failed flee attempt
	if combat.get("ninja_flee_protection", false):
		combat.erase("ninja_flee_protection")
		messages.append("[color=#191970]You slip away from the %s's counterattack![/color]" % monster.name)
		return {"success": true, "message": "\n".join(messages)}

	# Cloak: 50% miss chance (one time)
	if combat.get("cloak_active", false):
		combat.erase("cloak_active")
		if randi() % 100 < 50:
			messages.append("[color=#FF00FF]Your Cloak causes the %s to miss![/color]" % monster.name)
			return {"success": true, "message": "\n".join(messages)}

	# Distract: -50% accuracy (one time)
	if combat.get("enemy_distracted", false):
		combat.erase("enemy_distracted")
		hit_chance = int(hit_chance * 0.5)

	# Companion Distraction ability: causes monster to miss (one time)
	if combat.get("companion_distraction", false):
		combat.erase("companion_distraction")
		messages.append("[color=#00FFFF]The %s is distracted by your companion and misses![/color]" % monster.name)
		return {"success": true, "message": "\n".join(messages)}

	# === DETERMINE NUMBER OF ATTACKS ===
	var num_attacks = 1
	if ABILITY_MULTI_STRIKE in abilities:
		num_attacks = randi_range(2, 3)
		messages.append("[color=#FF4444]The %s attacks multiple times![/color]" % monster.name)

	var total_damage = 0
	var hits = 0

	for attack_num in range(num_attacks):
		var hit_roll = randi() % 100

		if hit_roll < hit_chance:
			# Monster hits
			var damage = calculate_monster_damage(monster, character, combat)

			# Sabotage debuff: reduce monster damage
			var sabotage_reduction = combat.get("monster_sabotaged", 0)
			if sabotage_reduction > 0:
				damage = int(damage * (1.0 - sabotage_reduction / 100.0))
				damage = max(1, damage)

			# Monster weakness (from companion ability): reduce monster damage
			var monster_weakness = combat.get("monster_weakness", 0)
			if monster_weakness > 0:
				damage = int(damage * (1.0 - monster_weakness / 100.0))
				damage = max(1, damage)

			# Companion absorb (from threshold ability): reduce damage taken
			var companion_absorb = combat.get("companion_absorb", 0)
			if companion_absorb > 0:
				var absorbed = int(damage * companion_absorb / 100.0)
				damage = max(1, damage - absorbed)
				# Decrement duration
				var absorb_duration = combat.get("companion_absorb_duration", 0)
				if absorb_duration > 0:
					combat["companion_absorb_duration"] = absorb_duration - 1
					if absorb_duration - 1 <= 0:
						combat["companion_absorb"] = 0

			# Ambusher ability: first attack deals bonus damage (75% chance to trigger)
			if combat.get("ambusher_active", false):
				combat["ambusher_active"] = false
				if randi() % 100 < 75:  # 75% chance to ambush
					damage = int(damage * 1.75)  # 1.75x damage (nerfed from 2x)
					messages.append("[color=#FF0000]AMBUSH! The %s strikes from the shadows![/color]" % monster.name)

			# Berserker ability: +50% damage when below 50% HP
			if ABILITY_BERSERKER in abilities:
				var hp_percent = float(monster.current_hp) / float(monster.max_hp)
				if hp_percent <= 0.5:
					damage = int(damage * 1.5)
					if attack_num == 0:
						messages.append("[color=#FF4444]The %s enters a berserker rage![/color]" % monster.name)

			# Enrage stacks
			var enrage = combat.get("enrage_stacks", 0)
			if enrage > 0:
				damage = int(damage * (1.0 + enrage * 0.10))

			# Unpredictable ability: wild damage variance (0.5x to 2.5x)
			if ABILITY_UNPREDICTABLE in abilities:
				var variance = randf_range(0.5, 2.5)
				damage = int(damage * variance)
				if variance > 1.8:
					messages.append("[color=#FF0000]The %s strikes with unexpected ferocity![/color]" % monster.name)
				elif variance < 0.7:
					messages.append("[color=#00FF00]The %s's attack is feeble this time.[/color]" % monster.name)

			# Apply damage reduction buff (Iron Skin)
			var damage_reduction = character.get_buff_value("damage_reduction")
			if damage_reduction > 0:
				damage = int(damage * (1.0 - damage_reduction / 100.0))
				damage = max(1, damage)

			# Apply armor rarity damage reduction (percentage)
			if armor_dr_total > 0:
				damage = int(damage * (1.0 - armor_dr_total / 100.0))
				damage = max(1, damage)

			# Apply defense buff (Shield spell)
			var defense_buff = character.get_buff_value("defense")
			if defense_buff > 0:
				var reduction = 1.0 - (defense_buff / 100.0)
				damage = int(damage * reduction)
				damage = max(1, damage)

			total_damage += damage
			hits += 1

			# Life steal ability: heal for 50% of damage dealt
			if ABILITY_LIFE_STEAL in abilities:
				var heal = int(damage * 0.5)
				monster.current_hp = min(monster.max_hp, monster.current_hp + heal)
				messages.append("[color=#FF4444]The %s drains %d life from you![/color]" % [monster.name, heal])

	if hits > 0:
		# Check for Forcefield shield (absorbs damage)
		var forcefield_shield = combat.get("forcefield_shield", 0)
		if forcefield_shield > 0:
			if total_damage <= forcefield_shield:
				combat["forcefield_shield"] = forcefield_shield - total_damage
				messages.append("[color=#FF00FF]Your Forcefield absorbs %d damage! (%d shield remaining)[/color]" % [total_damage, combat.forcefield_shield])
				total_damage = 0
			else:
				total_damage -= forcefield_shield
				combat.erase("forcefield_shield")
				messages.append("[color=#FF00FF]Your Forcefield absorbs %d damage before breaking![/color]" % forcefield_shield)

		# GM godmode: negate all damage
		if character.get_meta("gm_godmode", false):
			messages.append("[color=#00FF00][GM] Godmode: %d damage negated[/color]" % total_damage)
			total_damage = 0

		character.current_hp -= total_damage

		# Player thorns from scroll/potion buff (reflect damage back to monster)
		var player_thorns = combat.get("player_thorns", 0)
		if player_thorns > 0 and total_damage > 0:
			var thorns_damage = max(1, int(total_damage * player_thorns / 100.0))
			monster.current_hp -= thorns_damage
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#FF00FF]Thorns reflect %d damage back![/color]" % thorns_damage)

		# Equipment damage reflect proc
		var procs = character.get_equipment_procs()
		if procs.damage_reflect > 0 and total_damage > 0:
			var reflect_dmg = max(1, int(total_damage * procs.damage_reflect / 100.0))
			monster.current_hp -= reflect_dmg
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#9932CC]Retribution gear reflects %d damage![/color]" % reflect_dmg)
			# Check if reflection killed monster
			if monster.current_hp <= 0:
				return _process_victory(combat, messages)

		# Check for Dwarf Last Stand (survive lethal damage with 1 HP)
		if character.current_hp <= 0:
			if character.try_last_stand():
				character.current_hp = 1
				messages.append("[color=#FF4444]The %s attacks and deals [color=#FF8800]%d[/color] damage![/color]" % [monster.name, total_damage])
				messages.append("[color=#FFD700][b]LAST STAND![/b] Your dwarven resilience saves you![/color]")
				return {"success": true, "message": "\n".join(messages), "last_stand": true}

		# Check for Resurrect scroll buff (survive lethal damage and revive at % HP)
		if character.current_hp <= 0:
			var resurrect_percent = character.get_buff_value("resurrect")
			if resurrect_percent > 0:
				character.remove_buff("resurrect")
				var revive_hp = max(1, int(character.get_total_max_hp() * resurrect_percent / 100.0))
				character.current_hp = revive_hp
				messages.append("[color=#FF4444]The %s attacks and deals a lethal blow![/color]" % monster.name)
				messages.append("[color=#FFD700][b]RESURRECTION![/b] Divine magic pulls you back from death![/color]")
				messages.append("[color=#00FF00]You are revived with %d HP![/color]" % revive_hp)
				return {"success": true, "message": "\n".join(messages), "resurrected": true}

		# Check for companion revive (from threshold ability like Lich King's Phylactery)
		if character.current_hp <= 0:
			var companion_revive = combat.get("companion_revive", 0)
			if companion_revive > 0:
				combat.erase("companion_revive")  # One-time use
				var revive_hp = max(1, int(character.get_total_max_hp() * companion_revive / 100.0))
				character.current_hp = revive_hp
				var companion = character.get_active_companion()
				var comp_name = companion.get("name", "Your companion") if companion else "Your companion"
				messages.append("[color=#FF4444]The %s attacks and deals a lethal blow![/color]" % monster.name)
				messages.append("[color=#FFD700][b]COMPANION REVIVE![/b] %s pulls you back from death![/color]" % comp_name)
				messages.append("[color=#00FF00]You are revived with %d HP![/color]" % revive_hp)
				return {"success": true, "message": "\n".join(messages), "companion_revived": true}

		character.current_hp = max(0, character.current_hp)

		# === COMPANION THRESHOLD ABILITY ===
		# Check if companion's threshold ability should trigger (once per combat)
		# Uses monster-specific abilities stored at combat start (pre-scaled by level + variant)
		if character.current_hp > 0 and character.has_active_companion() and not combat.get("companion_threshold_triggered", false):
			var threshold_abilities = combat.get("companion_abilities", {})
			if not threshold_abilities.is_empty() and not threshold_abilities.get("threshold", {}).is_empty():
				var companion = character.get_active_companion()
				var ability = threshold_abilities.threshold
				var hp_threshold = ability.get("hp_percent", 50) / 100.0
				var current_hp_percent = float(character.current_hp) / float(character.get_total_max_hp())

				if current_hp_percent <= hp_threshold:
					combat["companion_threshold_triggered"] = true
					var effect = ability.get("effect", "")
					var ability_name = ability.get("name", "ability")

					if effect == "defense_buff":
						var buff_value = ability.get("value", 10)
						var duration = ability.get("duration", 3)
						character.add_buff("defense", buff_value, duration)
						messages.append("[color=#00FFFF]%s uses %s! (+%d%% defense for %d rounds)[/color]" % [companion.name, ability_name, buff_value, duration])
					elif effect == "attack_buff":
						var buff_value = ability.get("value", 10)
						var duration = ability.get("duration", 3)
						character.add_buff("strength", buff_value, duration)
						messages.append("[color=#FF6600]%s uses %s! (+%d%% attack for %d rounds)[/color]" % [companion.name, ability_name, buff_value, duration])
					elif effect == "speed_buff":
						var buff_value = ability.get("value", 10)
						var duration = ability.get("duration", 3)
						character.add_buff("speed", buff_value, duration)
						messages.append("[color=#00FFFF]%s uses %s! (+%d%% speed for %d rounds)[/color]" % [companion.name, ability_name, buff_value, duration])
					elif effect == "all_buff":
						var buff_value = ability.get("value", 10)
						var duration = ability.get("duration", 3)
						character.add_buff("strength", buff_value, duration)
						character.add_buff("defense", buff_value, duration)
						character.add_buff("speed", buff_value, duration)
						messages.append("[color=#FFD700]%s uses %s! (+%d%% to all stats for %d rounds)[/color]" % [companion.name, ability_name, buff_value, duration])
					elif effect == "dodge_buff":
						var buff_value = ability.get("value", 15)
						var duration = ability.get("duration", 3)
						combat["companion_dodge_buff"] = buff_value
						combat["companion_dodge_duration"] = duration
						messages.append("[color=#00FFFF]%s uses %s! (+%d%% dodge for %d rounds)[/color]" % [companion.name, ability_name, buff_value, duration])
					elif effect == "absorb":
						var absorb_value = ability.get("value", 10)
						var duration = ability.get("duration", 3)
						combat["companion_absorb"] = absorb_value
						combat["companion_absorb_duration"] = duration
						messages.append("[color=#8888FF]%s uses %s! (Absorbs %d%% damage for %d rounds)[/color]" % [companion.name, ability_name, absorb_value, duration])
					elif effect == "heal":
						var heal_percent = ability.get("value", 10)
						var heal_amount = max(1, int(character.get_total_max_hp() * heal_percent / 100.0))
						character.current_hp = min(character.get_total_max_hp(), character.current_hp + heal_amount)
						messages.append("[color=#00FF00]%s uses %s and heals you for %d HP![/color]" % [companion.name, ability_name, heal_amount])
					elif effect == "full_heal":
						character.current_hp = character.get_total_max_hp()
						messages.append("[color=#FFD700]%s uses %s! You are fully healed![/color]" % [companion.name, ability_name])
					elif effect == "flee_bonus":
						var flee_value = ability.get("value", 20)
						var duration = ability.get("duration", 2)
						combat["companion_flee_buff"] = flee_value
						combat["companion_flee_duration"] = duration
						messages.append("[color=#AAAAAA]%s uses %s! (+%d%% flee chance for %d rounds)[/color]" % [companion.name, ability_name, flee_value, duration])
					elif effect == "slow_enemy":
						var slow_value = ability.get("value", 20)
						var duration = ability.get("duration", 2)
						combat["monster_slowed"] = slow_value
						combat["monster_slow_duration"] = duration
						messages.append("[color=#6699FF]%s uses %s! The %s is slowed![/color]" % [companion.name, ability_name, monster.name])
					elif effect == "enemy_miss":
						var duration = ability.get("duration", 2)
						combat["companion_enemy_miss"] = duration
						messages.append("[color=#FFAA00]%s uses %s! The %s will miss its next %d attack(s)![/color]" % [companion.name, ability_name, monster.name, duration])
					elif effect == "lifesteal_buff":
						var lifesteal_value = ability.get("value", 20)
						var duration = ability.get("duration", 3)
						combat["companion_lifesteal_buff"] = lifesteal_value
						combat["companion_lifesteal_buff_duration"] = duration
						messages.append("[color=#00FF00]%s uses %s! (+%d%% lifesteal for %d rounds)[/color]" % [companion.name, ability_name, lifesteal_value, duration])
					elif effect == "lifesteal":
						# Immediate lifesteal heal (percent is pre-scaled)
						var lifesteal_pct = ability.get("percent", ability.get("base_percent", 20))
						var heal_amount = max(1, int(character.get_total_max_hp() * lifesteal_pct / 100.0))
						character.current_hp = min(character.get_total_max_hp(), character.current_hp + heal_amount)
						messages.append("[color=#00FF00]%s uses %s and drains %d HP![/color]" % [companion.name, ability_name, heal_amount])
					elif effect == "mana_restore":
						# Restore player's primary resource based on class
						var restore_percent = ability.get("value", 20)
						var class_path = character.get_class_path()
						match class_path:
							"warrior":
								var amount = max(1, int(character.get_total_max_stamina() * restore_percent / 100.0))
								character.current_stamina = min(character.get_total_max_stamina(), character.current_stamina + amount)
								messages.append("[color=#6699FF]%s uses %s and restores %d stamina![/color]" % [companion.name, ability_name, amount])
							"mage":
								var amount = max(1, int(character.get_total_max_mana() * restore_percent / 100.0))
								character.current_mana = min(character.get_total_max_mana(), character.current_mana + amount)
								messages.append("[color=#6699FF]%s uses %s and restores %d mana![/color]" % [companion.name, ability_name, amount])
							"trickster":
								var amount = max(1, int(character.get_total_max_energy() * restore_percent / 100.0))
								character.current_energy = min(character.get_total_max_energy(), character.current_energy + amount)
								messages.append("[color=#6699FF]%s uses %s and restores %d energy![/color]" % [companion.name, ability_name, amount])
					elif effect == "poison":
						var poison_damage = ability.get("damage", ability.get("base_damage", 10))
						var duration = ability.get("duration", 3)
						combat["monster_poison"] = combat.get("monster_poison", 0) + poison_damage
						combat["monster_poison_duration"] = max(combat.get("monster_poison_duration", 0), duration)
						messages.append("[color=#00FF00]%s uses %s! The %s is poisoned![/color]" % [companion.name, ability_name, monster.name])
					elif effect == "bonus_damage":
						var bonus_damage = ability.get("damage", ability.get("base_damage", 20))
						monster.current_hp -= bonus_damage
						monster.current_hp = max(0, monster.current_hp)
						messages.append("[color=#FF4444]%s uses %s for %d damage![/color]" % [companion.name, ability_name, bonus_damage])
					elif effect == "execute":
						var execute_threshold = ability.get("execute_threshold", 20) / 100.0
						var monster_hp_pct = float(monster.current_hp) / float(monster.max_hp)
						if monster_hp_pct <= execute_threshold:
							monster.current_hp = 0
							messages.append("[color=#FF0000]%s uses %s and executes the %s![/color]" % [companion.name, ability_name, monster.name])
						else:
							var exec_damage = int(monster.max_hp * 0.15)
							monster.current_hp -= exec_damage
							monster.current_hp = max(0, monster.current_hp)
							messages.append("[color=#FF4444]%s uses %s for %d damage![/color]" % [companion.name, ability_name, exec_damage])
					elif effect == "revive":
						# Store revive for if player dies
						var revive_percent = ability.get("revive_percent", 50)
						combat["companion_revive"] = revive_percent
						messages.append("[color=#FFD700]%s prepares %s! (Will revive at %d%% HP if killed)[/color]" % [companion.name, ability_name, revive_percent])

					# Check for secondary threshold effects (values pre-scaled where applicable)
					if ability.has("effect2"):
						var effect2 = ability.get("effect2", "")
						if effect2 == "attack_buff":
							var buff_value = ability.get("value2", ability.get("attack_base", 20))
							var duration = ability.get("duration", 3)
							character.add_buff("strength", buff_value, duration)
						elif effect2 == "speed_buff":
							var buff_value = ability.get("value2", ability.get("base2", 15))
							var duration = ability.get("duration", 3)
							character.add_buff("speed", buff_value, duration)
						elif effect2 == "heal":
							var heal_pct = ability.get("heal_percent", 20)
							var heal_amount = max(1, int(character.get_total_max_hp() * heal_pct / 100.0))
							character.current_hp = min(character.get_total_max_hp(), character.current_hp + heal_amount)
							messages.append("[color=#00FF00]%s also heals you for %d HP![/color]" % [companion.name, heal_amount])
						elif effect2 == "poison":
							var poison_damage = ability.get("poison_damage", 10)
							combat["monster_poison"] = combat.get("monster_poison", 0) + poison_damage
							combat["monster_poison_duration"] = max(combat.get("monster_poison_duration", 0), 3)
						elif effect2 == "stun":
							combat["monster_stunned"] = 1
							messages.append("[color=#FFAA00]The %s is stunned![/color]" % monster.name)
						elif effect2 == "crit_buff":
							var crit_value = ability.get("value2", ability.get("crit_base", 20))
							var duration = ability.get("duration", 3)
							combat["companion_crit_buff"] = crit_value
							combat["companion_crit_buff_duration"] = duration
						elif effect2 == "all_buff":
							var buff_value = ability.get("value2", ability.get("buff_base", 20))
							var duration = ability.get("duration", 3)
							character.add_buff("strength", buff_value, duration)
							character.add_buff("defense", buff_value, duration)
							character.add_buff("speed", buff_value, duration)
						elif effect2 == "reset_cooldowns":
							# Reset companion threshold so it can trigger again
							combat["companion_threshold_triggered"] = false
							messages.append("[color=#FFD700]Cooldowns reset![/color]")

		if num_attacks > 1:
			messages.append("[color=#FF4444]The %s hits %d times for [color=#FF8800]%d[/color] total damage![/color]" % [monster.name, hits, total_damage])
		else:
			messages.append("[color=#FF4444]The %s attacks and deals [color=#FF8800]%d[/color] damage![/color]" % [monster.name, total_damage])
	else:
		messages.append("[color=#00FF00]The %s attacks but misses![/color]" % monster.name)

	# === POST-ATTACK ABILITIES ===

	# Poison ability: apply poison if not already active (lasts 50 turns, persists outside combat)
	# WIS reduces poison chance and damage
	if ABILITY_POISON in abilities and not character.poison_active:
		var player_wis = character.get_effective_stat("wisdom") + combat.get("companion_wisdom_bonus", 0)
		var wis_resist = minf(0.50, float(player_wis) / 200.0)  # Max 50% resistance at WIS 100+
		var poison_chance = int(40 * (1.0 - wis_resist))  # Base 40%, reduced by WIS
		if randi() % 100 < poison_chance:
			var base_poison_dmg = max(1, int(monster.strength * 0.30))
			var poison_dmg = max(1, int(base_poison_dmg * (1.0 - wis_resist)))  # WIS also reduces damage
			character.apply_poison(poison_dmg, 50)
			if wis_resist > 0:
				messages.append("[color=#FF00FF]You have been poisoned! (-[color=#FF8800]%d[/color] HP/round for 50 turns, WIS resists %d%%)[/color]" % [poison_dmg, int(wis_resist * 100)])
			else:
				messages.append("[color=#FF00FF]You have been poisoned! (-[color=#FF8800]%d[/color] HP/round for 50 turns)[/color]" % poison_dmg)

	# Mana drain ability - drains the character's primary resource based on class path
	# WIS reduces drain amount
	if ABILITY_MANA_DRAIN in abilities and hits > 0:
		var player_wis = character.get_effective_stat("wisdom") + combat.get("companion_wisdom_bonus", 0)
		var wis_resist = minf(0.50, float(player_wis) / 200.0)  # Max 50% resistance
		var base_drain = randi_range(5, 20) + int(monster_level / 10)
		var drain = max(1, int(base_drain * (1.0 - wis_resist)))
		var resource_name = ""
		# Determine primary resource based on class type
		match character.class_type:
			"Wizard", "Sage", "Sorcerer":
				character.current_mana = max(0, character.current_mana - drain)
				resource_name = "mana"
			"Fighter", "Barbarian", "Paladin":
				character.current_stamina = max(0, character.current_stamina - drain)
				resource_name = "stamina"
			"Thief", "Ranger", "Ninja":
				character.current_energy = max(0, character.current_energy - drain)
				resource_name = "energy"
			_:
				character.current_mana = max(0, character.current_mana - drain)
				resource_name = "mana"
		if wis_resist > 0:
			messages.append("[color=#FF00FF]The %s drains [color=#FF8800]%d[/color] %s! (WIS resists %d%%)[/color]" % [monster.name, drain, resource_name, int(wis_resist * 100)])
		else:
			messages.append("[color=#FF00FF]The %s drains [color=#FF8800]%d[/color] %s![/color]" % [monster.name, drain, resource_name])

	# Stamina drain ability
	if ABILITY_STAMINA_DRAIN in abilities and hits > 0:
		var drain = randi_range(5, 15) + int(monster_level / 10)
		character.current_stamina = max(0, character.current_stamina - drain)
		messages.append("[color=#FF4444]The %s drains %d stamina![/color]" % [monster.name, drain])

	# Energy drain ability
	if ABILITY_ENERGY_DRAIN in abilities and hits > 0:
		var drain = randi_range(5, 15) + int(monster_level / 10)
		character.current_energy = max(0, character.current_energy - drain)
		messages.append("[color=#FFA500]The %s drains %d energy![/color]" % [monster.name, drain])

	# Curse ability: reduce defense for rest of combat (once)
	# WIS reduces curse chance and effect
	if ABILITY_CURSE in abilities and not combat.get("curse_applied", false):
		var player_wis = character.get_effective_stat("wisdom") + combat.get("companion_wisdom_bonus", 0)
		var wis_resist = minf(0.50, float(player_wis) / 200.0)  # Max 50% resistance
		var curse_chance = int(30 * (1.0 - wis_resist))  # Base 30%, reduced by WIS
		if randi() % 100 < curse_chance:
			combat["curse_applied"] = true
			var curse_penalty = int(-25 * (1.0 - wis_resist))  # WIS reduces penalty too
			character.add_buff("defense_penalty", curse_penalty, 999)  # Lasts entire combat
			if wis_resist > 0:
				messages.append("[color=#FF00FF]The %s curses you! (%d%% defense, WIS resists %d%%)[/color]" % [monster.name, curse_penalty, int(wis_resist * 100)])
			else:
				messages.append("[color=#FF00FF]The %s curses you! (-25%% defense)[/color]" % monster.name)

	# Disarm ability: reduce weapon damage temporarily (once)
	if ABILITY_DISARM in abilities and not combat.get("disarm_applied", false):
		if randi() % 100 < 25:  # 25% chance
			combat["disarm_applied"] = true
			character.add_buff("damage", -30, 3)  # -30% damage for 3 rounds
			messages.append("[color=#FF4444]The %s disarms you! (-30%% damage for 3 rounds)[/color]" % monster.name)

	# Corrosive ability: chance to damage random equipment on hit (configurable)
	var ability_cfg = balance_config.get("monster_abilities", {})
	if ABILITY_CORROSIVE in abilities and hits > 0:
		var corrosive_chance = ability_cfg.get("corrosive_chance", 15)
		if randi() % 100 < corrosive_chance:
			# Damage one random piece of equipment (all slots including ring/amulet)
			var all_slots = ["weapon", "shield", "armor", "helm", "boots", "ring", "amulet"]
			all_slots.shuffle()
			for slot in all_slots:
				var result = character.damage_equipment(slot, randi_range(5, 15))
				if result.success:
					if result.is_broken:
						messages.append("[color=#FF0000]The %s's acid BREAKS your %s! Replace it immediately![/color]" % [monster.name, result.item_name])
					else:
						messages.append("[color=#FFA500]The %s's acid corrodes your %s! (%d%% worn)[/color]" % [monster.name, result.item_name, result.new_wear])
					break

	# Sunder ability: specifically damages weapons and shields (configurable)
	if ABILITY_SUNDER in abilities and hits > 0:
		var sunder_chance = ability_cfg.get("sunder_chance", 20)
		if randi() % 100 < sunder_chance:
			# 50/50 weapon or shield
			var target_slot = "weapon" if randf() < 0.5 else "shield"
			var result = character.damage_equipment(target_slot, randi_range(10, 25))
			if result.success:
				if result.is_broken:
					messages.append("[color=#FF0000]The %s SHATTERS your %s! You need a new one![/color]" % [monster.name, result.item_name])
				else:
					messages.append("[color=#FF4444]The %s sunders your %s! (%d%% worn)[/color]" % [monster.name, result.item_name, result.new_wear])

	# Blind ability: persistent debuff that reduces hit chance, hides monster HP, reduces map vision
	if ABILITY_BLIND in abilities and not character.blind_active:
		if randi() % 100 < 40:  # 40% chance
			var blind_duration = ability_cfg.get("blind_duration", 15)
			character.apply_blind(blind_duration)
			messages.append("[color=#808080]The %s blinds you! (-%d%% hit chance, reduced vision for %d turns)[/color]" % [monster.name, ability_cfg.get("blind_hit_reduction", 30), blind_duration])

	# Bleed ability: stacking bleed DoT (can stack up to 3 times)
	if ABILITY_BLEED in abilities and hits > 0:
		var bleed_chance = ability_cfg.get("bleed_chance", 40)
		if randi() % 100 < bleed_chance:
			var bleed_stacks = combat.get("player_bleed_stacks", 0)
			if bleed_stacks < 3:  # Max 3 stacks
				bleed_stacks += 1
				combat["player_bleed_stacks"] = bleed_stacks
				var bleed_damage = max(1, int(monster.strength * ability_cfg.get("bleed_damage_percent", 15) / 100.0))
				combat["player_bleed_damage"] = bleed_damage
				messages.append("[color=#FF4444]The %s causes you to bleed! (%d stacks)[/color]" % [monster.name, bleed_stacks])

	# Slow aura ability: reduces player flee chance (passive)
	if ABILITY_SLOW_AURA in abilities and not combat.get("slow_aura_applied", false):
		combat["slow_aura_applied"] = true
		var slow_reduction = ability_cfg.get("slow_aura_flee_reduction", 25)
		combat["player_slow"] = slow_reduction
		messages.append("[color=#808080]The %s's aura slows you! (-%d%% flee chance)[/color]" % [monster.name, slow_reduction])

	# Weakness ability: applies -25% attack debuff for 20 rounds (persists outside combat)
	if ABILITY_WEAKNESS in abilities and hits > 0 and not character.has_debuff("weakness"):
		var weakness_chance = ability_cfg.get("weakness_chance", 30)  # 30% chance
		if randi() % 100 < weakness_chance:
			character.apply_debuff("weakness", 25, 20)  # 25% reduction, 20 rounds
			messages.append("[color=#FFA500]The %s's attack weakens you! (-25%% attack damage for 20 turns)[/color]" % monster.name)

	# Summoner ability: call reinforcements (once per combat)
	if ABILITY_SUMMONER in abilities and not combat.get("summoner_triggered", false):
		if randi() % 100 < 20:  # 20% chance
			combat["summoner_triggered"] = true
			var base_name = monster.get("base_name", monster.name)
			# Shrieker summons higher-tier monsters with weighted probability
			if base_name == "Shrieker":
				var summon_tier = _get_shrieker_summon_tier()
				var summoned_name = monster_database.get_random_monster_name_from_tier(summon_tier)
				combat["summon_next_fight"] = summoned_name
				combat["monster_fled"] = true  # Shrieker flees after summoning
				messages.append("[color=#FF4444]The %s's shriek echoes through the realm, summoning a %s![/color]" % [monster.name, summoned_name])
				messages.append("[color=#FFA500]The %s scurries away as its call is answered![/color]" % monster.name)
			else:
				# Normal summoner: summons same monster type
				combat["summon_next_fight"] = base_name
				messages.append("[color=#FF4444]The %s calls for reinforcements![/color]" % monster.name)

	# Charm ability: player attacks themselves next turn (once per combat)
	if ABILITY_CHARM in abilities and not combat.get("charm_applied", false):
		if randi() % 100 < 25:  # 25% chance
			combat["charm_applied"] = true
			combat["player_charmed"] = true
			messages.append("[color=#FF00FF]The %s charms you! You will attack yourself next turn![/color]" % monster.name)

	# Buff destroy ability: removes one random active buff
	if ABILITY_BUFF_DESTROY in abilities and hits > 0:
		if randi() % 100 < 30:  # 30% chance
			var active_buffs = character.get_active_buff_names()
			if active_buffs.size() > 0:
				var buff_to_remove = active_buffs[randi() % active_buffs.size()]
				character.remove_buff(buff_to_remove)
				messages.append("[color=#FF00FF]The %s dispels your %s![/color]" % [monster.name, buff_to_remove])

	# Shield shatter ability: destroys forcefield/shield buffs instantly
	if ABILITY_SHIELD_SHATTER in abilities and hits > 0:
		if combat.get("forcefield_shield", 0) > 0:
			combat["forcefield_shield"] = 0
			messages.append("[color=#FF0000]The %s shatters your Forcefield![/color]" % monster.name)
		if character.has_buff("defense"):
			character.remove_buff("defense")
			messages.append("[color=#FF4444]The %s shatters your defensive shields![/color]" % monster.name)

	# XP steal ability: steals 1-3% of player XP on hit (rare but punishing)
	if ABILITY_XP_STEAL in abilities and hits > 0:
		if randi() % 100 < 20:  # 20% chance
			var steal_percent = randi_range(1, 3)
			var xp_stolen = max(1, int(character.experience * steal_percent / 100.0))
			character.experience = max(0, character.experience - xp_stolen)
			messages.append("[color=#FF00FF]The %s drains [color=#FF8800]%d[/color] experience from you![/color]" % [monster.name, xp_stolen])

	# Item steal ability: 5% chance to steal random equipped item
	if ABILITY_ITEM_STEAL in abilities and hits > 0:
		if randi() % 100 < 5:  # 5% chance
			var equip_slots = ["weapon", "shield", "armor", "helm", "boots", "ring", "amulet"]
			equip_slots.shuffle()
			for slot in equip_slots:
				var equipped_item = character.get_equipped_item(slot)
				if equipped_item != null and not equipped_item.is_empty():
					character.unequip_item(slot)
					combat["stolen_item"] = equipped_item
					messages.append("[color=#FF0000]The %s steals your %s![/color]" % [monster.name, equipped_item.get("name", slot)])
					break

	# Flee attack ability: monster deals damage then flees (no loot)
	if ABILITY_FLEE_ATTACK in abilities and not combat.get("flee_attack_used", false):
		if randi() % 100 < 30 and monster.current_hp < monster.max_hp * 0.5:  # 30% chance when below 50% HP
			combat["flee_attack_used"] = true
			combat["monster_fled"] = true
			messages.append("[color=#FFA500]The %s strikes one last time and flees into the shadows![/color]" % monster.name)

	# Build return result - include monster_fled and summon_next_fight if set
	var result = {"success": true, "message": "\n".join(messages)}
	if combat.get("monster_fled", false):
		result["monster_fled"] = true
		result["summon_next_fight"] = combat.get("summon_next_fight", "")
		result["monster_level"] = monster.level
	return result

func calculate_damage(character: Character, monster: Dictionary, combat: Dictionary = {}) -> Dictionary:
	"""Calculate player damage to monster (includes equipment, buffs, crits, class passives, and class advantage)
	Returns dictionary with 'damage', 'is_crit', and 'passive_messages' keys"""
	var cfg = balance_config.get("combat", {})
	var passive_messages = []
	var passive = character.get_class_passive()
	var effects = passive.get("effects", {})

	# Use total attack which includes equipment
	var base_damage = character.get_total_attack()

	# Mage INT-based attack: use INT/5 as minimum base damage when STR is low
	var is_mage_class = character.class_type in ["Wizard", "Sorcerer", "Sage"]
	if is_mage_class:
		var int_attack = int(character.get_effective_stat("intelligence") / 5.0)
		base_damage = max(base_damage, int_attack)

	# Add strength buff bonus
	var strength_buff = character.get_buff_value("strength")
	base_damage += strength_buff

	# Apply STR percentage bonus (configurable, default +2% per point)
	var str_stat = character.get_effective_stat("strength")
	var str_mult = cfg.get("player_str_multiplier", 0.02)
	var str_multiplier = 1.0 + (str_stat * str_mult)
	base_damage = int(base_damage * str_multiplier)

	var damage_roll = (randi() % 6) + 1  # 1d6
	var raw_damage = base_damage + damage_roll

	# Apply damage buff (War Cry, Berserk)
	var damage_buff = character.get_buff_value("damage")
	if damage_buff > 0:
		raw_damage = int(raw_damage * (1.0 + damage_buff / 100.0))

	# === COMPANION BONUS: Attack damage ===
	var companion_attack = character.get_companion_bonus("attack")
	# Also add attack bonus from companion passive abilities (stored in combat state)
	companion_attack += combat.get("companion_attack_bonus", 0)
	if companion_attack > 0:
		raw_damage = int(raw_damage * (1.0 + companion_attack / 100.0))
		passive_messages.append("[color=#00FFFF]Companion: +%d%% damage![/color]" % int(companion_attack))

	# === CLASS PASSIVE: Barbarian Blood Rage ===
	# +3% damage per 10% HP missing, max +30%
	if effects.has("damage_per_missing_hp"):
		var hp_percent = float(character.current_hp) / float(character.get_total_max_hp())
		var missing_hp_percent = 1.0 - hp_percent
		var rage_bonus = min(effects.get("max_rage_bonus", 0.30), missing_hp_percent * effects.get("damage_per_missing_hp", 0.03) * 10.0)
		if rage_bonus > 0.01:
			raw_damage = int(raw_damage * (1.0 + rage_bonus))
			passive_messages.append("[color=#8B0000]Blood Rage: +%d%% damage![/color]" % int(rage_bonus * 100))

	# === RACIAL PASSIVE: Orc Low HP Damage ===
	# +20% damage when below 50% HP
	var orc_damage_bonus = character.get_low_hp_damage_bonus()
	if orc_damage_bonus > 0:
		raw_damage = int(raw_damage * (1.0 + orc_damage_bonus))
		passive_messages.append("[color=#556B2F]Orcish Fury: +%d%% damage![/color]" % int(orc_damage_bonus * 100))

	# Critical hit check (configurable base, per-dex, max, and damage multiplier)
	var dex_stat = character.get_effective_stat("dexterity")
	var crit_base = cfg.get("player_crit_base", 5)
	var crit_per_dex = cfg.get("player_crit_per_dex", 0.5)
	var crit_max = cfg.get("player_crit_max", 25)
	var crit_damage = cfg.get("player_crit_damage", 1.5)

	var crit_chance = crit_base + int(dex_stat * crit_per_dex)
	# Add crit bonus from scrolls/potions
	var crit_bonus = combat.get("crit_bonus", 0)
	crit_chance += crit_bonus

	# Add crit bonus from equipment rarity (weapon rarity_bonuses)
	var crit_equipped = character.equipped if character else {}
	var weapon_rb = {}
	if crit_equipped is Dictionary:
		var wpn = crit_equipped.get("weapon", {})
		if wpn is Dictionary:
			weapon_rb = wpn.get("rarity_bonuses", {})
	if weapon_rb.has("crit_chance"):
		crit_chance += int(weapon_rb["crit_chance"])

	# Add companion crit bonus (from base bonus)
	var companion_crit = character.get_companion_bonus("crit_chance")
	if companion_crit > 0:
		crit_chance += int(companion_crit)
	# Add companion crit from passive abilities
	var companion_crit_bonus = combat.get("companion_crit_bonus", 0)
	if companion_crit_bonus > 0:
		crit_chance += companion_crit_bonus
	# Add companion crit from threshold ability buff
	var companion_crit_buff = combat.get("companion_crit_buff", 0)
	if companion_crit_buff > 0:
		crit_chance += companion_crit_buff
		# Decrement duration
		var crit_buff_duration = combat.get("companion_crit_buff_duration", 0)
		if crit_buff_duration > 0:
			combat["companion_crit_buff_duration"] = crit_buff_duration - 1
			if crit_buff_duration - 1 <= 0:
				combat["companion_crit_buff"] = 0

	# === CLASS PASSIVE: Thief Backstab ===
	# +15% base crit chance
	if effects.has("crit_chance_bonus"):
		crit_chance += int(effects.get("crit_chance_bonus", 0) * 100)

	crit_chance = min(crit_chance, 75)  # Cap at 75% even with bonuses
	var is_crit = (randi() % 100) < crit_chance

	# === CLASS PASSIVE: Thief Backstab crit damage bonus ===
	# +50% crit damage multiplier (1.5x becomes 2.0x)
	var final_crit_damage = crit_damage
	if is_crit and effects.has("crit_damage_bonus"):
		final_crit_damage += effects.get("crit_damage_bonus", 0)
	# Weapon rarity crit damage bonus (percentage points, e.g., 10 = +10%)
	if is_crit and weapon_rb.has("crit_damage"):
		final_crit_damage += weapon_rb["crit_damage"] / 100.0
	# Companion crit damage bonus (base bonus + passive abilities like Godslayer)
	var companion_crit_damage = int(character.get_companion_bonus("crit_damage")) + combat.get("companion_crit_damage", 0)
	if is_crit and companion_crit_damage > 0:
		final_crit_damage += companion_crit_damage / 100.0

	if is_crit:
		raw_damage = int(raw_damage * final_crit_damage)

	# === CLASS PASSIVE: Sorcerer Chaos Magic ===
	# 25% chance for double damage, 5% chance to backfire
	var backfire_damage = 0
	if effects.has("double_damage_chance"):
		var chaos_roll = randf()
		if chaos_roll < effects.get("backfire_chance", 0.10):
			# Backfire: deal damage to self (capped at 15% max HP)
			backfire_damage = mini(int(raw_damage * 0.5), int(character.get_total_max_hp() * 0.15))
			raw_damage = int(raw_damage * 0.5)  # Halve the attack damage
			passive_messages.append("[color=#9400D3]Chaos Magic backfires![/color]")
		elif chaos_roll < effects.get("backfire_chance", 0.10) + effects.get("double_damage_chance", 0.25):
			# Double damage
			raw_damage = raw_damage * 2
			passive_messages.append("[color=#9400D3]Chaos Magic surges: DOUBLE DAMAGE![/color]")

	# === CLASS PASSIVE: Wizard Arcane Precision ===
	# +15% spell damage (applied to all attacks for Wizards)
	if effects.has("spell_damage_bonus"):
		raw_damage = int(raw_damage * (1.0 + effects.get("spell_damage_bonus", 0)))

	# Monster defense reduces damage by a percentage (not flat)
	var defense_constant = cfg.get("defense_formula_constant", 100)
	var defense_max = cfg.get("defense_max_reduction", 0.6)
	var defense_ratio = float(monster.defense) / (float(monster.defense) + defense_constant)
	var damage_reduction = defense_ratio * defense_max
	var total = int(raw_damage * (1.0 - damage_reduction))

	# Apply class advantage multiplier
	var affinity = monster.get("class_affinity", 0)
	var class_multiplier = _get_class_advantage_multiplier(affinity, character.class_type)
	total = int(total * class_multiplier)

	# Apply level difference penalty (1.5% per level, max 25%)
	# At 25 level gap: 37.5% penalty, at 50 level gap: 75% penalty (capped at 25%)
	# Good gear should help bridge ~15-20 level gaps, not infinite
	var lvl_diff = monster.get("level", 1) - character.level
	if lvl_diff > 0:
		var lvl_penalty = min(0.25, lvl_diff * 0.015)
		total = int(total * (1.0 - lvl_penalty))

	# === CLASS PASSIVE: Paladin Divine Favor ===
	# +25% damage vs undead/demons
	if effects.has("bonus_vs_undead"):
		var monster_type = monster.get("type", "").to_lower()
		var undead_demon_names = [
			"skeleton", "zombie", "wraith", "wight", "lich", "elder lich", "vampire", "nazgul", "death incarnate",  # Undead
			"demon", "demon lord", "balrog", "succubus"  # Demons
		]
		if "undead" in monster_type or "demon" in monster_type or monster.name.to_lower() in undead_demon_names:
			total = int(total * (1.0 + effects.get("bonus_vs_undead", 0)))
			passive_messages.append("[color=#FFD700]Divine Favor: +%d%% vs undead![/color]" % int(effects.get("bonus_vs_undead", 0) * 100))

	# === CLASS PASSIVE: Ranger Hunter's Mark ===
	# +25% damage vs beasts (natural creatures, animals, monsters with animal forms)
	if effects.has("bonus_vs_beasts"):
		var monster_type = monster.get("type", "").to_lower()
		var beast_names = [
			"giant rat", "wolf", "dire wolf", "giant spider", "bear", "dire bear",  # Basic beasts
			"wyvern", "gryphon", "chimaera", "cerberus", "hydra",  # Mythical beasts
			"world serpent", "harpy", "minotaur"  # Part-beast creatures
		]
		if "beast" in monster_type or "animal" in monster_type or monster.name.to_lower() in beast_names:
			total = int(total * (1.0 + effects.get("bonus_vs_beasts", 0)))
			passive_messages.append("[color=#228B22]Hunter's Mark: +%d%% vs beasts![/color]" % int(effects.get("bonus_vs_beasts", 0) * 100))

	# === MONSTER BANE POTIONS ===
	# Check for monster_bane_<type> buffs that give +damage% vs specific monster types
	var bane_types = ["dragon", "undead", "beast", "demon", "elemental"]
	for bane_type in bane_types:
		var bane_buff_key = "monster_bane_" + bane_type
		var bane_bonus = character.get_buff_value(bane_buff_key)
		if bane_bonus > 0:
			# Check if monster matches this type using drop_tables lookup
			if drop_tables and drop_tables.get_monster_type(monster.name) == bane_type:
				total = int(total * (1.0 + bane_bonus / 100.0))
				passive_messages.append("[color=#FF4500]%s Bane: +%d%% damage![/color]" % [bane_type.capitalize(), bane_bonus])

	# === WEAKNESS DEBUFF ===
	# Apply -25% damage if the player has the Weakness debuff
	var weakness_penalty = character.get_debuff_value("weakness")
	if weakness_penalty > 0:
		total = int(total * (1.0 - weakness_penalty / 100.0))
		passive_messages.append("[color=#FFA500]Weakness: -%d%% damage![/color]" % weakness_penalty)

	return {"damage": max(1, total), "is_crit": is_crit, "passive_messages": passive_messages, "backfire_damage": backfire_damage}

func _get_class_advantage_multiplier(affinity: int, character_class: String) -> float:
	"""Calculate damage multiplier based on class affinity.
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
			return "warrior"  # Default

func _get_shrieker_summon_tier() -> int:
	"""Get a weighted random tier for Shrieker summons (4-9, lower tiers more likely)"""
	var roll = randi() % 100
	# Tier 4: 40%, Tier 5: 25%, Tier 6: 15%, Tier 7: 10%, Tier 8: 7%, Tier 9: 3%
	if roll < 40:
		return 4
	elif roll < 65:
		return 5
	elif roll < 80:
		return 6
	elif roll < 90:
		return 7
	elif roll < 97:
		return 8
	else:
		return 9

func _get_tier_for_level(level: int) -> int:
	"""Get monster/player tier based on level (matches monster_database tier ranges)"""
	if level <= 5:
		return 1
	elif level <= 15:
		return 2
	elif level <= 30:
		return 3
	elif level <= 50:
		return 4
	elif level <= 100:
		return 5
	elif level <= 500:
		return 6
	elif level <= 2000:
		return 7
	elif level <= 5000:
		return 8
	else:
		return 9

func calculate_monster_damage(monster: Dictionary, character: Character, combat: Dictionary = {}) -> int:
	"""Calculate monster damage to player (reduced by equipment defense, buffs, and class passives)"""
	var cfg = balance_config.get("combat", {})
	var passive = character.get_class_passive()
	var effects = passive.get("effects", {})

	var base_damage = monster.strength
	var damage_roll = (randi() % 6) + 1  # 1d6
	var raw_damage = base_damage + damage_roll

	# Equipment defense provides flat reduction BEFORE defense formula
	# This makes gear meaningful against higher-level monsters
	var equipment_defense = character.get_equipment_defense()
	var equip_cap = cfg.get("equipment_defense_cap", 0.3)
	var equip_divisor = cfg.get("equipment_defense_divisor", 500)
	var equipment_reduction = 0.0
	if equip_cap > 0 and equip_divisor > 0:
		equipment_reduction = min(equip_cap, float(equipment_defense) / equip_divisor)
	raw_damage = int(raw_damage * (1.0 - equipment_reduction))

	# Player defense reduces damage by percentage (not flat)
	var player_defense = character.get_total_defense()

	# Add defense buff bonus
	var defense_buff = character.get_buff_value("defense")
	player_defense += defense_buff

	# === COMPANION BONUS: Defense ===
	if character.has_active_companion():
		var companion_defense = int(character.get_companion_bonus("defense"))
		companion_defense += combat.get("companion_defense_bonus", 0)
		player_defense += companion_defense

	# === CLASS PASSIVE: Fighter Tactical Discipline ===
	# +15% defense bonus
	if effects.has("defense_bonus_percent"):
		var defense_bonus = int(player_defense * effects.get("defense_bonus_percent", 0))
		player_defense += defense_bonus

	var defense_constant = cfg.get("defense_formula_constant", 100)
	var defense_max = cfg.get("defense_max_reduction", 0.6)
	var defense_ratio = float(player_defense) / (float(player_defense) + defense_constant)
	var damage_reduction = defense_ratio * defense_max
	var total = int(raw_damage * (1.0 - damage_reduction))

	# Level difference bonus: monsters higher level deal extra damage (exponential)
	var level_diff = monster.level - character.level
	if level_diff > 0:
		var level_base = cfg.get("monster_level_diff_base", 1.04)
		var level_cap = cfg.get("monster_level_diff_cap", 75)
		var level_multiplier = pow(level_base, min(level_diff, level_cap))
		total = int(total * level_multiplier)

	# Minimum damage based on monster level (higher level = higher floor)
	var min_damage = max(1, monster.level / 5)
	return max(min_damage, total)

func get_combat_summary(peer_id: int) -> Dictionary:
	"""Extract combat summary data before end_combat erases it."""
	if not active_combats.has(peer_id):
		return {}
	var combat = active_combats[peer_id]
	return {
		"rounds": combat.round,
		"combat_log": combat.combat_log.duplicate(),
		"monster_name": combat.monster.name,
		"monster_base_name": combat.monster.get("base_name", combat.monster.name),
		"monster_level": combat.monster.level,
		"monster_max_hp": combat.monster.max_hp,
		"total_damage_dealt": combat.get("total_damage_dealt", 0),
		"total_damage_taken": combat.get("total_damage_taken", 0),
		"player_hp_at_start": combat.get("player_hp_at_start", 0),
	}

func end_combat(peer_id: int, victory: bool):
	"""End combat and clean up"""
	if active_combats.has(peer_id):
		var combat = active_combats[peer_id]
		var character = combat.character

		# Restore temporary companion HP/mana boosts
		var hp_boost = combat.get("companion_hp_boost_applied", 0)
		if hp_boost > 0:
			character.max_hp = max(1, character.max_hp - hp_boost)
			# Cap to total max HP (including equipment), not just base max_hp
			character.current_hp = mini(character.current_hp, character.get_total_max_hp())

		var resource_boost = combat.get("companion_resource_boost_applied", 0)
		if resource_boost > 0:
			var boost_type = combat.get("companion_resource_boost_type", "mana")
			match boost_type:
				"stamina":
					character.max_stamina = max(1, character.max_stamina - resource_boost)
					character.current_stamina = mini(character.current_stamina, character.get_total_max_stamina())
				"mana":
					character.max_mana = max(1, character.max_mana - resource_boost)
					character.current_mana = mini(character.current_mana, character.get_total_max_mana())
				"energy":
					character.max_energy = max(1, character.max_energy - resource_boost)
					character.current_energy = mini(character.current_energy, character.get_total_max_energy())
		# Legacy fallback for old combat states
		var mana_boost = combat.get("companion_mana_boost_applied", 0)
		if mana_boost > 0 and resource_boost == 0:
			character.max_mana = max(1, character.max_mana - mana_boost)
			character.current_mana = mini(character.current_mana, character.get_total_max_mana())

		# Mark character as not in combat
		character.in_combat = false

		# Clear combat buffs (round-based)
		character.clear_buffs()

		# Tick persistent buffs (battle-based) - reduces remaining battles by 1
		var expired_persistent = character.tick_persistent_buffs()

		# Store expired persistent buffs for the server to notify about
		if not expired_persistent.is_empty():
			_pending_buff_expirations[peer_id] = expired_persistent

		# Remove from active combats
		active_combats.erase(peer_id)

		print("Combat ended for peer %d - Victory: %s" % [peer_id, victory])

func get_expired_persistent_buffs(peer_id: int) -> Array:
	"""Get and clear any pending persistent buff expiration notifications for a peer."""
	if _pending_buff_expirations.has(peer_id):
		var expired = _pending_buff_expirations[peer_id]
		_pending_buff_expirations.erase(peer_id)
		return expired
	return []

func is_in_combat(peer_id: int) -> bool:
	"""Check if a player is in combat (solo or party)"""
	return active_combats.has(peer_id) or party_combat_membership.has(peer_id)

func get_analyze_bonus(peer_id: int) -> int:
	"""Get the analyze bonus for a player's current combat"""
	if not active_combats.has(peer_id):
		return 0
	return active_combats[peer_id].get("analyze_bonus", 0)

func set_analyze_bonus(peer_id: int, bonus: int):
	"""Set the analyze bonus for a player's current combat (used for flock carry-over)"""
	if active_combats.has(peer_id):
		active_combats[peer_id]["analyze_bonus"] = bonus

func get_combat_display(peer_id: int) -> Dictionary:
	"""Get formatted combat state for display"""
	if not active_combats.has(peer_id):
		return {}

	var combat = active_combats[peer_id]
	var character = combat.character
	var monster = combat.monster

	# Get monster's class affinity for color coding
	var affinity = monster.get("class_affinity", 0)
	var name_color = _get_affinity_color(affinity)

	# Check if player knows this monster (has killed it at or above this level)
	# Use base_name so killing any variant teaches you about the base monster type
	# If unknown OR player is blinded, send -1 for HP values so client shows "???"
	var monster_base = monster.get("base_name", monster.name)
	var knows_monster = character.knows_monster(monster_base, monster.level)
	var can_see_hp = knows_monster and not character.blind_active
	var display_hp = monster.current_hp if can_see_hp else -1
	var display_max_hp = monster.max_hp if can_see_hp else -1
	var display_hp_percent = int((float(monster.current_hp) / monster.max_hp) * 100) if can_see_hp else -1

	return {
		"round": combat.round,
		"player_name": character.name,
		"player_hp": character.current_hp,
		"player_max_hp": character.get_total_max_hp(),
		"player_hp_percent": int((float(character.current_hp) / character.get_total_max_hp()) * 100),
		"player_mana": character.current_mana,
		"player_max_mana": character.get_total_max_mana(),
		"player_stamina": character.current_stamina,
		"player_max_stamina": character.max_stamina,
		"player_energy": character.current_energy,
		"player_max_energy": character.max_energy,
		"monster_name": monster.name,
		"monster_base_name": monster.get("base_name", monster.name),  # Original name for art lookup
		"monster_level": monster.level,
		"monster_hp": display_hp,
		"monster_max_hp": display_max_hp,
		"monster_hp_percent": display_hp_percent,
		"monster_name_color": name_color,  # Color based on class affinity
		"monster_affinity": affinity,
		"monster_abilities": monster.get("abilities", []),  # For client-side trait display
		"monster_known": knows_monster,  # Let client know if HP is real or estimated
		"is_rare_variant": monster.get("is_rare_variant", false),  # For visual indicator
		"can_act": combat.player_can_act,
		# Combat status effects (now tracked on character for persistence)
		"poison_active": character.poison_active,
		"poison_damage": character.poison_damage,
		"poison_turns_remaining": character.poison_turns_remaining,
		# Outsmart tracking
		"outsmart_failed": combat.get("outsmart_failed", false),
		# Forcefield/shield for visual display
		"forcefield_shield": combat.get("forcefield_shield", 0)
	}

func get_monster_ascii_art(monster_name: String) -> String:
	# Server-side ASCII art removed - all art is now rendered client-side via monster_art.gd
	return ""

func _get_raw_monster_ascii_art(monster_name: String) -> Array:
	"""Return the raw ASCII art array for color extraction"""
	# This is a simplified lookup - just need the first element for color
	var color_map = {
		"Goblin": ["[color=#00FF00]"],
		"Giant Rat": ["[color=#8B4513]"],
		"Skeleton": ["[color=#FFFFFF]"],
		"Wolf": ["[color=#808080]"],
		"Kobold": ["[color=#CD853F]"],
		"Orc": ["[color=#228B22]"],
		"Hobgoblin": ["[color=#228B22]"],
		"Gnoll": ["[color=#DAA520]"],
		"Zombie": ["[color=#556B2F]"],
		"Giant Spider": ["[color=#2F4F4F]"],
		"Wight": ["[color=#708090]"],
		"Ogre": ["[color=#556B2F]"],
		"Troll": ["[color=#556B2F]"],
		"Wraith": ["[color=#4B0082]"],
		"Minotaur": ["[color=#8B4513]"],
		"Giant": ["[color=#8B4513]"],
		"Vampire": ["[color=#8B0000]"],
		"Demon Lord": ["[color=#FF0000]"],
		"Lich": ["[color=#9400D3]"],
		"Titan": ["[color=#FFD700]"],
		"Wyvern": ["[color=#8FBC8F]"],
		"Ghost": ["[color=#778899]"],
		"Specter": ["[color=#B8B8B8]"],
		"Banshee": ["[color=#E6E6FA]"],
		"Basilisk": ["[color=#2E8B57]"],
		"Chimera": ["[color=#DC143C]"],
		"Manticore": ["[color=#CD5C5C]"],
		"Hydra": ["[color=#006400]"],
		"Phoenix": ["[color=#FF8C00]"],
		"Primordial Dragon": ["[color=#8B0000]"],
		"Ancient Wyrm": ["[color=#4169E1]"],
		"Void Walker": ["[color=#191970]"],
		"Chaos Spawn": ["[color=#800080]"],
		"World Eater": ["[color=#2F4F4F]"],
		"Entropy": ["[color=#000080]"],
	}
	return color_map.get(monster_name, ["[color=#555555]"])

func generate_combat_start_message(character: Character, monster: Dictionary) -> String:
	"""Generate the initial combat message (text only - art is rendered client-side)"""
	return generate_encounter_text(monster)

func generate_encounter_text(monster: Dictionary) -> String:
	"""Generate encounter text WITHOUT ASCII art (for client-side art rendering)"""
	# Get class affinity color
	var affinity = monster.get("class_affinity", 0)  # 0 = NEUTRAL
	var name_color = _get_affinity_color(affinity)

	# Build encounter message with colored monster name (color indicates class affinity)
	var msg = "[color=#FFD700]You encounter a [/color][color=%s]%s[/color][color=#FFD700] (Lvl %d)![/color]" % [name_color, monster.name, monster.level]

	# Show notable abilities
	var abilities = monster.get("abilities", [])
	var notable_abilities = []
	if ABILITY_GLASS_CANNON in abilities:
		notable_abilities.append("[color=#FF4444]Glass Cannon[/color]")
	if ABILITY_REGENERATION in abilities:
		notable_abilities.append("[color=#00FF00]Regenerates[/color]")
	if ABILITY_POISON in abilities:
		notable_abilities.append("[color=#FF00FF]Venomous[/color]")
	if ABILITY_LIFE_STEAL in abilities:
		notable_abilities.append("[color=#FF4444]Life Stealer[/color]")
	if ABILITY_GEM_BEARER in abilities:
		notable_abilities.append("[color=#00FFFF]Gem Bearer[/color]")
	if ABILITY_WISH_GRANTER in abilities:
		notable_abilities.append("[color=#FFD700]Wish Granter[/color]")
	if ABILITY_WEAPON_MASTER in abilities:
		notable_abilities.append("[color=#FF8000]* WEAPON MASTER *[/color]")
	if ABILITY_SHIELD_BEARER in abilities:
		notable_abilities.append("[color=#00FFFF]* SHIELD GUARDIAN *[/color]")
	if ABILITY_CORROSIVE in abilities:
		notable_abilities.append("[color=#FFFF00]! CORROSIVE ![/color]")
	if ABILITY_SUNDER in abilities:
		notable_abilities.append("[color=#FF4444]! SUNDERING ![/color]")
	if ABILITY_CHARM in abilities:
		notable_abilities.append("[color=#FF00FF]Enchanting[/color]")
	if ABILITY_BUFF_DESTROY in abilities:
		notable_abilities.append("[color=#808080]Dispeller[/color]")
	if ABILITY_SHIELD_SHATTER in abilities:
		notable_abilities.append("[color=#FF4444]Shield Breaker[/color]")
	if ABILITY_XP_STEAL in abilities:
		notable_abilities.append("[color=#FF00FF]! XP DRAINER ![/color]")
	if ABILITY_ITEM_STEAL in abilities:
		notable_abilities.append("[color=#FF0000]! PICKPOCKET ![/color]")
	if ABILITY_DISGUISE in abilities:
		notable_abilities.append("[color=#808080]Deceptive[/color]")
	if ABILITY_FLEE_ATTACK in abilities:
		notable_abilities.append("[color=#FFA500]Skirmisher[/color]")

	if notable_abilities.size() > 0:
		msg += "\n[color=#808080]Traits: %s[/color]" % ", ".join(notable_abilities)

	return msg

func _get_affinity_color(affinity: int) -> String:
	"""Get the color code for a class affinity"""
	match affinity:
		1:  # PHYSICAL
			return "#FFFF00"  # Yellow - weak to Warriors
		2:  # MAGICAL
			return "#00BFFF"  # Blue - weak to Mages
		3:  # CUNNING
			return "#00FF00"  # Green - weak to Tricksters
		_:
			return "#FFFFFF"  # White - neutral

# Item Drop System Hooks

func set_drop_tables(tables: Node):
	"""Set the drop tables reference for item drops"""
	drop_tables = tables

func roll_combat_drops(monster: Dictionary, character: Character) -> Array:
	"""Roll for item drops after defeating a monster. Returns array of items.
	NOTE: Does NOT add items to inventory - server handles that to avoid duplication.
	TIER BONUS: Fighting higher tier monsters gives +50% drop chance per tier above."""
	# If drop tables not initialized, return empty
	if drop_tables == null:
		return []

	var drop_table_id = monster.get("drop_table_id", "common")
	var drop_chance = monster.get("drop_chance", 5)
	var monster_level = monster.get("level", 1)

	# Apply tier bonus to drop chance - fighting above your tier is rewarding!
	var player_tier = _get_tier_for_level(character.level)
	var monster_tier = _get_tier_for_level(monster_level)
	var tier_diff = monster_tier - player_tier
	if tier_diff > 0:
		# +50% drop chance per tier above (multiplicative)
		var tier_mult = pow(1.5, tier_diff)  # T+1=1.5x, T+2=2.25x, T+3=3.4x
		drop_chance = int(drop_chance * tier_mult)

	# Roll for drops - server will handle adding to inventory
	return drop_tables.roll_drops(drop_table_id, drop_chance, monster_level)

func _get_rarity_color(rarity: String) -> String:
	"""Get display color for item rarity"""
	var colors = {
		"common": "#FFFFFF",
		"uncommon": "#1EFF00",
		"rare": "#0070DD",
		"epic": "#A335EE",
		"legendary": "#FF8000",
		"artifact": "#E6CC80"
	}
	return colors.get(rarity, "#FFFFFF")

func roll_gem_drops(monster: Dictionary, character: Character) -> int:
	"""Roll for gem drops. Returns number of gems earned.
	   Gems are the primary high-level currency - drop more often at high monster levels."""
	var monster_level = monster.get("level", 1)
	var player_level = character.level
	var level_diff = monster_level - player_level

	# Base gem chance from high monster levels (regardless of player level)
	var level_gem_chance = 0
	if monster_level >= 500:
		level_gem_chance = 40  # L500+ monsters always have good gem chance
	elif monster_level >= 200:
		level_gem_chance = 25
	elif monster_level >= 100:
		level_gem_chance = 15
	elif monster_level >= 50:
		level_gem_chance = 5

	# Bonus gem chance from fighting higher-level monsters
	var diff_gem_chance = 0
	if level_diff >= 100:
		diff_gem_chance = 50
	elif level_diff >= 75:
		diff_gem_chance = 35
	elif level_diff >= 50:
		diff_gem_chance = 25
	elif level_diff >= 30:
		diff_gem_chance = 18
	elif level_diff >= 20:
		diff_gem_chance = 12
	elif level_diff >= 15:
		diff_gem_chance = 8
	elif level_diff >= 10:
		diff_gem_chance = 5
	elif level_diff >= 5:
		diff_gem_chance = 2

	# Combined chance (capped at 80%)
	var gem_chance = mini(80, level_gem_chance + diff_gem_chance)

	if gem_chance <= 0:
		return 0

	# Roll for gem drop
	var roll = randi() % 100
	if roll >= gem_chance:
		return 0

	# Gem quantity formula: scales with monster level
	var cfg = balance_config.get("rewards", {})
	var lethality = monster.get("lethality", 0)
	var lethality_divisor = cfg.get("gem_lethality_divisor", 1000)
	var level_divisor = cfg.get("gem_level_divisor", 50)  # Reduced from 100 for more gems
	var gem_count = max(1, int(lethality / lethality_divisor) + int(monster_level / level_divisor))

	return gem_count

# ===== TITLE ITEM DROPS =====

func roll_title_item_drop(monster_level: int) -> Dictionary:
	"""Roll for title item drops. Returns item dictionary or empty if no drop.
	- Jarl's Ring: 0.5% chance from level 100+ monsters
	- Unforged Crown: 0.2% chance from level 200+ monsters
	"""
	var title_items = TitlesScript.TITLE_ITEMS

	# Check Unforged Crown first (rarer, higher level requirement)
	if monster_level >= 200:
		var crown_info = title_items.get("unforged_crown", {})
		var crown_chance = crown_info.get("drop_chance", 0.2)
		if randf() * 100 < crown_chance:
			return {
				"type": "unforged_crown",
				"name": crown_info.get("name", "Unforged Crown"),
				"rarity": crown_info.get("rarity", "legendary"),
				"description": crown_info.get("description", ""),
				"is_title_item": true
			}

	# Check Jarl's Ring
	if monster_level >= 50:
		var ring_info = title_items.get("jarls_ring", {})
		var ring_chance = ring_info.get("drop_chance", 0.5)
		if randf() * 100 < ring_chance:
			return {
				"type": "jarls_ring",
				"name": ring_info.get("name", "Jarl's Ring"),
				"rarity": ring_info.get("rarity", "legendary"),
				"description": ring_info.get("description", ""),
				"is_title_item": true
			}

	return {}

# ===== WISH GRANTER SYSTEM =====

func generate_wish_options(character: Character, monster_level: int, monster_lethality: int = 100) -> Array:
	"""Generate 3 wish options for player to choose from after defeating a wish granter.
	Options include: gear upgrades, gems, equipment upgrade, or rare permanent stat upgrades."""
	var options = []
	var player_level = character.level
	var level_diff = max(0, monster_level - player_level)

	# Option 1: Always a good option (experience or gear)
	if randf() < 0.5:
		options.append(_generate_experience_wish(monster_level, player_level))
	else:
		options.append(_generate_gear_wish(player_level, monster_level))

	# Option 2: Another good option (different from option 1)
	if options[0].type == "experience":
		options.append(_generate_gear_wish(player_level, monster_level))
	else:
		options.append(_generate_experience_wish(monster_level, player_level))

	# Option 3: Special option - small chance for permanent stats, otherwise buff or equipment upgrade
	if randf() < 0.10:  # 10% chance for permanent stat boost
		options.append(_generate_stat_wish())
	elif randf() < 0.5:
		options.append(_generate_buff_wish())
	else:
		options.append(_generate_upgrade_wish(monster_lethality, level_diff))

	return options

func _generate_experience_wish(monster_level: int, player_level: int) -> Dictionary:
	"""Generate an experience windfall wish option.
	Targets ~50% of a level (roughly 22 kills worth).
	XP to next level = pow(L+1, 2.5) * 100, so 50% = pow(L+1, 2.5) * 50."""
	var effective_level = max(monster_level, player_level)
	var base_xp = int(pow(effective_level + 1, 2.5) * 50)
	var xp_amount = max(1000, base_xp + randi_range(0, int(base_xp * 0.25)))
	return {
		"type": "experience",
		"amount": xp_amount,
		"label": "Windfall of Experience",
		"description": "Gain %d bonus XP" % xp_amount,
		"color": "#00FF00"
	}

func _generate_gear_wish(player_level: int, monster_level: int) -> Dictionary:
	"""Generate a gear reward wish option"""
	var gear_level = max(player_level, monster_level) + randi_range(5, 15)
	var rarity = "rare" if randf() < 0.7 else "epic"
	if randf() < 0.1:
		rarity = "legendary"
	return {
		"type": "gear",
		"level": gear_level,
		"rarity": rarity,
		"label": "%s Lv%d Gear" % [rarity.capitalize(), gear_level],
		"description": "Receive a %s quality item at level %d" % [rarity, gear_level],
		"color": _get_rarity_color(rarity)
	}

func _generate_buff_wish() -> Dictionary:
	"""Generate a powerful temporary buff wish option"""
	var buff_types = [
		{"stat": "damage", "value": 75, "battles": 15, "label": "+75% Damage (15 battles)"},
		{"stat": "defense", "value": 75, "battles": 15, "label": "+75% Defense (15 battles)"},
		{"stat": "speed", "value": 50, "battles": 15, "label": "+50 Speed (15 battles)"},
		{"stat": "crit", "value": 25, "battles": 20, "label": "+25% Crit Chance (20 battles)"}
	]
	var chosen = buff_types[randi() % buff_types.size()]
	return {
		"type": "buff",
		"stat": chosen.stat,
		"value": chosen.value,
		"battles": chosen.battles,
		"label": chosen.label,
		"description": "Powerful combat enhancement",
		"color": "#FFD700"
	}

func _generate_upgrade_wish(monster_lethality: int, level_diff: int) -> Dictionary:
	"""Generate an equipment upgrade wish option.
	Number of upgrades scales with monster lethality and level difference.
	Harder fights = more upgrades."""
	# Base upgrades: 3-5
	# Lethality bonus: +1 per 500 lethality (max +5)
	# Level diff bonus: +1 per 10 levels above player (max +5)
	var base_upgrades = randi_range(3, 5)
	var lethality_bonus = mini(5, int(monster_lethality / 500))
	var level_bonus = mini(5, int(level_diff / 10))
	var total_upgrades = base_upgrades + lethality_bonus + level_bonus

	return {
		"type": "upgrade",
		"upgrades": total_upgrades,
		"label": "Equipment Upgrade (x%d)" % total_upgrades,
		"description": "Upgrade a random equipped item %d time%s" % [total_upgrades, "s" if total_upgrades > 1 else ""],
		"color": "#FF8000"
	}

func _generate_stat_wish() -> Dictionary:
	"""Generate a permanent stat increase wish option (rare!)"""
	var stats = ["strength", "constitution", "dexterity", "intelligence", "wisdom", "wits"]
	var chosen_stat = stats[randi() % stats.size()]
	var boost = randi_range(1, 3)
	return {
		"type": "stats",
		"stat": chosen_stat,
		"amount": boost,
		"label": "+%d %s (PERMANENT)" % [boost, chosen_stat.capitalize()],
		"description": "Permanently increase your %s by %d!" % [chosen_stat, boost],
		"color": "#FF00FF"
	}

func apply_wish_choice(character: Character, wish: Dictionary) -> String:
	"""Apply the chosen wish reward to the character. Returns result message."""
	match wish.type:
		"experience":
			character.add_experience(wish.amount)
			return "[color=#00FF00]+ + [/color][color=#FF00FF]WISH GRANTED: +%d XP![/color][color=#00FF00] + +[/color]" % wish.amount
		"essence":
			character.salvage_essence = character.salvage_essence + wish.amount
			return "[color=#FFD700]WISH GRANTED: +%d salvage essence![/color]" % wish.amount
		"buff":
			character.add_persistent_buff(wish.stat, wish.value, wish.battles)
			return "[color=#FFD700]WISH GRANTED: %s![/color]" % wish.label
		"stats":
			# Permanent stat increase
			match wish.stat:
				"strength": character.strength += wish.amount
				"constitution": character.constitution += wish.amount
				"dexterity": character.dexterity += wish.amount
				"intelligence": character.intelligence += wish.amount
				"wisdom": character.wisdom += wish.amount
				"wits": character.wits += wish.amount
			return "[color=#FF00FF]WISH GRANTED: Permanent +%d %s![/color]" % [wish.amount, wish.stat.capitalize()]
		"gear":
			# Server will handle gear generation
			return "[color=%s]WISH GRANTED: Generating %s gear...[/color]" % [wish.color, wish.rarity]
		"upgrade":
			# Server will handle equipment upgrades
			return "[color=#FF8000]WISH GRANTED: Upgrading equipment %d time%s...[/color]" % [wish.upgrades, "s" if wish.upgrades > 1 else ""]
	return "[color=#FFD700]WISH GRANTED![/color]"

# ===== COMBAT PERSISTENCE (for disconnect recovery) =====

func serialize_combat_state(peer_id: int) -> Dictionary:
	"""Serialize combat state for saving when player disconnects.
	Returns empty dict if not in combat."""
	if not active_combats.has(peer_id):
		return {}

	var combat = active_combats[peer_id]
	var monster = combat.monster

	# Serialize only what's needed to restore combat
	return {
		"monster": {
			"name": monster.get("name", ""),
			"base_name": monster.get("base_name", monster.get("name", "")),
			"level": monster.get("level", 1),
			"current_hp": monster.get("current_hp", 1),
			"max_hp": monster.get("max_hp", 1),
			"strength": monster.get("strength", 10),
			"defense": monster.get("defense", 0),
			"speed": monster.get("speed", 10),
			"abilities": monster.get("abilities", []),
			"is_rare_variant": monster.get("is_rare_variant", false),
			"variant_name": monster.get("variant_name", ""),
			"experience_reward": monster.get("experience_reward", 10),
			"class_affinity": monster.get("class_affinity", 0),
			"is_dungeon_monster": monster.get("is_dungeon_monster", false),
			"is_boss": monster.get("is_boss", false)
		},
		"round": combat.get("round", 1),
		"player_can_act": combat.get("player_can_act", true),
		"outsmart_failed": combat.get("outsmart_failed", false),
		"analyze_bonus": combat.get("analyze_bonus", 0),
		"ambusher_active": combat.get("ambusher_active", false),
		"is_dungeon_combat": combat.get("is_dungeon_combat", false),
		"is_boss_fight": combat.get("is_boss_fight", false),
		"dungeon_monster_id": combat.get("dungeon_monster_id", -1),
		"flock_remaining": combat.get("flock_remaining", 0),
		"cc_resistance": combat.get("cc_resistance", 0)
	}

func restore_combat(peer_id: int, character: Character, saved_state: Dictionary) -> Dictionary:
	"""Restore combat from saved state after reconnection.
	Returns result similar to start_combat."""
	if saved_state.is_empty():
		return {"success": false, "message": "No saved combat state"}

	var monster = saved_state.get("monster", {})
	if monster.is_empty():
		return {"success": false, "message": "Invalid monster data"}

	# Migrate old xp_reward key to experience_reward
	if not monster.has("experience_reward") and monster.has("xp_reward"):
		monster["experience_reward"] = monster["xp_reward"]
	elif not monster.has("experience_reward"):
		monster["experience_reward"] = 10

	# Build combat state from saved data
	# Always set player_can_act = true on restore so the player can act immediately
	# (they may have disconnected during the monster's turn phase)
	var combat_state = {
		"peer_id": peer_id,
		"character": character,
		"monster": monster,
		"round": saved_state.get("round", 1),
		"player_can_act": true,
		"combat_log": [],
		"started_at": Time.get_ticks_msec(),
		"outsmart_failed": saved_state.get("outsmart_failed", false),
		"ambusher_active": saved_state.get("ambusher_active", false),
		"analyze_bonus": saved_state.get("analyze_bonus", 0),
		"is_dungeon_combat": saved_state.get("is_dungeon_combat", false),
		"is_boss_fight": saved_state.get("is_boss_fight", false),
		"dungeon_monster_id": saved_state.get("dungeon_monster_id", -1),
		"flock_remaining": saved_state.get("flock_remaining", 0),
		"cc_resistance": saved_state.get("cc_resistance", 0)
	}

	active_combats[peer_id] = combat_state

	# Mark character as in combat
	character.in_combat = true

	# Re-apply companion passives if character has active companion (using monster-specific abilities)
	if character.has_active_companion() and drop_tables:
		var companion = character.get_active_companion()
		var companion_level = companion.get("level", 1)
		var monster_type = companion.get("monster_type", "")
		var variant_mult = character.get_variant_stat_multiplier()
		var companion_sub_tier = companion.get("sub_tier", 1)
		var companion_abilities = drop_tables.get_monster_companion_abilities(monster_type, companion_level, variant_mult, companion_sub_tier)
		combat_state["companion_abilities"] = companion_abilities

		if not companion_abilities.passive.is_empty():
			var passive = companion_abilities.passive
			if passive.has("effect") and passive.has("value"):
				_apply_companion_passive_effect(combat_state, character, passive.effect, passive.value)
			if passive.has("effect2") and passive.has("value2"):
				_apply_companion_passive_effect(combat_state, character, passive.effect2, passive.value2)
			if passive.has("effect3") and passive.has("value3"):
				_apply_companion_passive_effect(combat_state, character, passive.effect3, passive.value3)

		combat_state["companion_threshold_triggered"] = false

	# Generate restoration message
	var msg = "[color=#FFFF00]Combat restored![/color]\n"
	msg += "[color=#FF4444]You are fighting: %s (Lvl %d)[/color]\n" % [monster.name, monster.level]
	msg += "[color=#808080]Round %d - Your HP: %d/%d | Enemy HP: %d/%d[/color]" % [
		combat_state.round,
		character.current_hp, character.get_total_max_hp(),
		monster.current_hp, monster.max_hp
	]

	return {
		"success": true,
		"message": msg,
		"combat_state": get_combat_display(peer_id),
		"restored": true
	}

# ===== PARTY COMBAT SYSTEM =====

func start_party_combat(party_members: Array, characters: Dictionary, monster: Dictionary) -> Dictionary:
	"""Start a party combat encounter.
	party_members: Array of peer_ids (leader first)
	characters: Dictionary of peer_id -> Character
	monster: Generated monster dictionary
	Returns: {success, messages, combat_state}
	"""
	if party_members.is_empty():
		return {"success": false, "message": "No party members"}

	var leader_id = party_members[0]
	var party_size = party_members.size()

	# Scale monster HP by party size
	monster["original_max_hp"] = monster.get("max_hp", 100)
	monster.max_hp = int(monster.get("max_hp", 100) * party_size)
	monster.current_hp = monster.max_hp

	# Initiative: use leader's stats
	var leader_char = characters[leader_id]
	var init_roll = randi() % 100
	var monster_speed = monster.get("speed", 10)
	var player_dex = leader_char.get_effective_stat("dexterity")
	var equipment_speed = leader_char.get_equipment_bonuses().get("speed", 0)
	var monster_initiative = clamp(5 + int(monster_speed * 0.15) - int(log(max(1, player_dex + equipment_speed)) * 3.0), 5, 55)
	var monster_goes_first = init_roll < monster_initiative

	# Build per-member combat states
	var member_states = {}
	for pid in party_members:
		var ch = characters[pid]
		ch.in_combat = true
		ch.last_stand_used = false
		member_states[pid] = {
			"total_damage_dealt": 0,
			"total_damage_taken": 0,
			"outsmart_failed": false,
			"companion_threshold_triggered": false,
			"player_hp_at_start": ch.current_hp,
			"analyze_bonus": 0,
			"fled": false,
			"dead": false,
			# Companion buffs applied per member
			"companion_hp_boost_applied": 0,
			"companion_resource_boost_applied": 0,
			"companion_resource_boost_type": "mana",
			"companion_abilities": {},
			"forcefield_shield": 0
		}

	# Create party combat state
	var combat = {
		"leader_peer_id": leader_id,
		"members": party_members.duplicate(),
		"characters": characters,
		"monster": monster,
		"round": 1,
		"current_turn_index": 0 if not monster_goes_first else -1,
		"monster_actions_remaining": 0,
		"fled_members": [],
		"dead_members": [],
		"combat_log": [],
		"started_at": Time.get_ticks_msec(),
		"member_states": member_states,
		"monster_went_first": monster_goes_first,
		"cc_resistance": 0,
		"enrage_stacks": 0,
		"target_weights": {},
		# Monster DOT effects
		"monster_poison": 0,
		"monster_poison_duration": 0,
		"monster_burn": 0,
		"monster_burn_duration": 0,
		"monster_bleed": 0,
		"monster_bleed_duration": 0,
		"monster_stunned": 0,
		"monster_charmed": 0,
	}

	# Initialize equal targeting weights
	for pid in party_members:
		combat.target_weights[pid] = 1.0 / float(party_size)

	# Store in tracking dicts
	active_party_combats[leader_id] = combat
	for pid in party_members:
		party_combat_membership[pid] = leader_id

	# Apply companion passives for each member
	for pid in party_members:
		_apply_party_member_companion(combat, pid)

	# Build start messages
	var messages = []
	var xp_zone = _get_xp_zone_text(leader_char.level, monster)
	messages.append("[color=#FF4444]%s%s appears! (Lv%d, HP: %d)[/color]" % [
		monster.get("name", "Monster"), xp_zone, monster.get("level", 1), monster.max_hp])
	messages.append("[color=#00BFFF]Party combat! %d members vs 1 monster.[/color]" % party_size)

	if monster_goes_first:
		messages.append("[color=#FF8800]The %s strikes first![/color]" % monster.get("name", "monster"))
		# Process monster's first strike - limited to 1 action to prevent instant kills
		var first_results = _process_party_monster_phase(combat, 1)
		messages.append_array(first_results.get("messages", []))
		# After first strike, check for deaths
		_check_party_deaths(combat)
		# Set up first player turn
		combat.current_turn_index = 0
		_skip_inactive_members(combat)

	return {
		"success": true,
		"messages": messages,
		"leader_id": leader_id,
		"first_turn_peer_id": _get_current_turn_peer_id(combat)
	}

func _apply_party_member_companion(combat: Dictionary, peer_id: int):
	"""Apply companion passives for a party member in party combat."""
	var character = combat.characters[peer_id]
	var ms = combat.member_states[peer_id]
	var companion = character.active_companion
	if companion.is_empty():
		return
	# Get companion abilities
	if drop_tables and drop_tables.has_method("get_companion_abilities"):
		var abilities = drop_tables.get_companion_abilities(companion)
		ms["companion_abilities"] = abilities

func _get_xp_zone_text(player_level: int, monster: Dictionary) -> String:
	"""Get XP zone indicator for combat start message."""
	var monster_level = monster.get("level", 1)
	var level_diff = monster_level - player_level
	if level_diff >= 10:
		return " [color=#FF00FF]*TIER CHALLENGE*[/color]"
	elif level_diff >= 5:
		return " [color=#FFD700]*CHALLENGE*[/color]"
	return ""

func process_party_combat_action(leader_id: int, acting_peer_id: int, action: CombatAction) -> Dictionary:
	"""Process a party member's combat action.
	Returns: {success, messages[], combat_ended, victory, next_turn_peer_id, monster_phase_results}
	"""
	if not active_party_combats.has(leader_id):
		return {"success": false, "message": "No active party combat"}

	var combat = active_party_combats[leader_id]
	var current_pid = _get_current_turn_peer_id(combat)

	if acting_peer_id != current_pid:
		return {"success": false, "message": "Not your turn"}

	var character = combat.characters[acting_peer_id]
	var monster = combat.monster
	var ms = combat.member_states[acting_peer_id]
	var messages = []

	var monster_hp_before = monster.current_hp
	var player_hp_before = character.current_hp

	# Process player action using EXISTING solo combat logic adapted for party
	match action:
		CombatAction.ATTACK:
			var result = _party_process_attack(combat, acting_peer_id)
			messages.append_array(result.get("messages", []))
		CombatAction.FLEE:
			var result = _party_process_flee(combat, acting_peer_id)
			messages.append_array(result.get("messages", []))
			if result.get("fled", false):
				combat.fled_members.append(acting_peer_id)
				ms["fled"] = true
				messages.append("[color=#FFAA00]%s flees from battle![/color]" % character.name)
		CombatAction.OUTSMART:
			var result = _party_process_outsmart(combat, acting_peer_id)
			messages.append_array(result.get("messages", []))

	# Track damage
	var damage_dealt = max(0, monster_hp_before - monster.current_hp)
	ms["total_damage_dealt"] = ms.get("total_damage_dealt", 0) + damage_dealt
	var self_damage = max(0, player_hp_before - character.current_hp)
	ms["total_damage_taken"] = ms.get("total_damage_taken", 0) + self_damage

	# Check if monster died
	if monster.current_hp <= 0:
		var victory_result = _process_party_victory(combat)
		messages.append_array(victory_result.get("messages", []))
		return {
			"success": true,
			"messages": messages,
			"combat_ended": true,
			"victory": true,
			"member_rewards": victory_result.get("member_rewards", {})
		}

	# Check if all members fled/dead
	if _all_members_inactive(combat):
		messages.append("[color=#FF4444]The party has been defeated![/color]")
		_end_party_combat(leader_id, false)
		return {"success": true, "messages": messages, "combat_ended": true, "victory": false}

	# Advance to next player or monster phase
	combat.current_turn_index += 1
	_skip_inactive_members(combat)

	if combat.current_turn_index >= combat.members.size():
		# All players acted - monster phase
		var monster_results = _process_party_monster_phase(combat)
		messages.append_array(monster_results.get("messages", []))

		# Check for deaths
		_check_party_deaths(combat)

		# Check if all members dead/fled after monster phase
		if _all_members_inactive(combat):
			messages.append("[color=#FF4444]The party has been wiped out![/color]")
			_end_party_combat(leader_id, false)
			return {"success": true, "messages": messages, "combat_ended": true, "victory": false}

		# Next round
		combat.round += 1
		combat.current_turn_index = 0
		_skip_inactive_members(combat)

	return {
		"success": true,
		"messages": messages,
		"combat_ended": false,
		"victory": false,
		"next_turn_peer_id": _get_current_turn_peer_id(combat)
	}

func process_party_combat_ability(leader_id: int, acting_peer_id: int, ability_name: String, arg: String) -> Dictionary:
	"""Process an ability command from a player in party combat.
	Creates an adapter dict so existing ability functions can be reused."""
	if not active_party_combats.has(leader_id):
		return {"success": false, "message": "No active party combat"}

	var combat = active_party_combats[leader_id]
	var current_pid = _get_current_turn_peer_id(combat)

	if acting_peer_id != current_pid:
		return {"success": false, "message": "Not your turn"}

	var character = combat.characters[acting_peer_id]
	var monster = combat.monster
	var ms = combat.member_states[acting_peer_id]

	var monster_hp_before = monster.current_hp
	var player_hp_before = character.current_hp

	# Normalize ability names (same as solo)
	match ability_name:
		"bolt": ability_name = "magic_bolt"
		"strike": ability_name = "power_strike"
		"warcry": ability_name = "war_cry"
		"bash": ability_name = "shield_bash"
		"ironskin": ability_name = "iron_skin"
		"heist": ability_name = "perfect_heist"
		"shield": ability_name = "forcefield"

	# Build adapter dict that mimics solo combat structure
	var adapter = {
		"character": character,
		"monster": monster,
		"round": combat.round,
		"player_can_act": true,
		"messages": [],
		"total_damage_dealt": ms.get("total_damage_dealt", 0),
		"total_damage_taken": ms.get("total_damage_taken", 0),
		# Per-member buff/debuff state (stored in member_states)
		"outsmart_failed": ms.get("outsmart_failed", false),
		"analyze_bonus": ms.get("analyze_bonus", 0),
		"forcefield_shield": ms.get("forcefield_shield", 0),
		"cloak_active": ms.get("cloak_active", false),
		"haste_active": ms.get("haste_active", false),
		"vanished": ms.get("vanished", false),
		"ninja_flee_protection": ms.get("ninja_flee_protection", false),
		"pickpocket_count": ms.get("pickpocket_count", 0),
		"pickpocket_max": ms.get("pickpocket_max", 2),
		"gambit_kill": ms.get("gambit_kill", false),
		# Shared monster state (stored on combat dict)
		"monster_stunned": combat.get("monster_stunned", 0),
		"monster_burn": combat.get("monster_burn", 0),
		"monster_burn_duration": combat.get("monster_burn_duration", 0),
		"monster_bleed": combat.get("monster_bleed", 0),
		"monster_bleed_duration": combat.get("monster_bleed_duration", 0),
		"monster_poison": combat.get("monster_poison", 0),
		"monster_poison_duration": combat.get("monster_poison_duration", 0),
		"monster_weakness": combat.get("monster_weakness", 0),
		"monster_weakness_duration": combat.get("monster_weakness_duration", 0),
		"monster_slowed": combat.get("monster_slowed", 0),
		"monster_slow_duration": combat.get("monster_slow_duration", 0),
		"monster_mana_drained": combat.get("monster_mana_drained", 0),
		"monster_charmed": combat.get("monster_charmed", 0),
		"monster_sabotaged": combat.get("monster_sabotaged", 0),
		"enemy_distracted": combat.get("enemy_distracted", false),
		"cc_resistance": combat.get("cc_resistance", 0),
		"enrage_stacks": combat.get("enrage_stacks", 0),
		"damage_buff": ms.get("damage_buff", 0),
		"defense_buff": ms.get("defense_buff", 0),
		"disguise_active": combat.get("disguise_active", false),
		"disguise_revealed": combat.get("disguise_revealed", false),
		"disguise_true_stats": combat.get("disguise_true_stats", {}),
		# Companion state
		"companion_hp_regen": ms.get("companion_hp_regen", 0),
		"companion_mana_regen": ms.get("companion_mana_regen", 0),
		"companion_energy_regen": ms.get("companion_energy_regen", 0),
		"companion_stamina_regen": ms.get("companion_stamina_regen", 0),
		"companion_wisdom_bonus": ms.get("companion_wisdom_bonus", 0),
		"companion_speed_bonus": ms.get("companion_speed_bonus", 0),
		"companion_abilities": ms.get("companion_abilities", {}),
		"companion_distraction": combat.get("companion_distraction", false),
		# Dungeon state
		"is_dungeon_combat": combat.get("is_dungeon_combat", false),
		"is_boss_fight": combat.get("is_boss_fight", false),
	}

	# Process the ability using existing solo ability functions
	var result: Dictionary
	if ability_name == "cloak" or ability_name == "all_or_nothing":
		result = _process_universal_ability(adapter, ability_name)
	elif ability_name in ["magic_bolt", "blast", "forcefield", "teleport", "meteor", "haste", "paralyze", "banish"]:
		result = _process_mage_ability(adapter, ability_name, arg)
	elif ability_name in ["power_strike", "war_cry", "shield_bash", "cleave", "berserk", "iron_skin", "devastate", "fortify", "rally"]:
		result = _process_warrior_ability(adapter, ability_name)
	elif ability_name in ["analyze", "distract", "pickpocket", "ambush", "vanish", "exploit", "perfect_heist", "sabotage", "gambit"]:
		result = _process_trickster_ability(adapter, ability_name)
	else:
		return {"success": false, "message": "Unknown ability!"}

	# Copy modified state back from adapter to party combat structures
	# Per-member state
	ms["analyze_bonus"] = adapter.get("analyze_bonus", 0)
	ms["forcefield_shield"] = adapter.get("forcefield_shield", 0)
	ms["cloak_active"] = adapter.get("cloak_active", false)
	ms["haste_active"] = adapter.get("haste_active", false)
	ms["vanished"] = adapter.get("vanished", false)
	ms["ninja_flee_protection"] = adapter.get("ninja_flee_protection", false)
	ms["pickpocket_count"] = adapter.get("pickpocket_count", 0)
	ms["gambit_kill"] = adapter.get("gambit_kill", false)
	ms["damage_buff"] = adapter.get("damage_buff", 0)
	ms["defense_buff"] = adapter.get("defense_buff", 0)
	# Shared monster state — copy back to combat dict
	combat["monster_stunned"] = adapter.get("monster_stunned", 0)
	combat["monster_burn"] = adapter.get("monster_burn", 0)
	combat["monster_burn_duration"] = adapter.get("monster_burn_duration", 0)
	combat["monster_bleed"] = adapter.get("monster_bleed", 0)
	combat["monster_bleed_duration"] = adapter.get("monster_bleed_duration", 0)
	combat["monster_poison"] = adapter.get("monster_poison", 0)
	combat["monster_poison_duration"] = adapter.get("monster_poison_duration", 0)
	combat["monster_weakness"] = adapter.get("monster_weakness", 0)
	combat["monster_weakness_duration"] = adapter.get("monster_weakness_duration", 0)
	combat["monster_slowed"] = adapter.get("monster_slowed", 0)
	combat["monster_slow_duration"] = adapter.get("monster_slow_duration", 0)
	combat["monster_mana_drained"] = adapter.get("monster_mana_drained", 0)
	combat["monster_charmed"] = adapter.get("monster_charmed", 0)
	combat["monster_sabotaged"] = adapter.get("monster_sabotaged", 0)
	combat["enemy_distracted"] = adapter.get("enemy_distracted", false)
	combat["cc_resistance"] = adapter.get("cc_resistance", 0)
	combat["enrage_stacks"] = adapter.get("enrage_stacks", 0)
	combat["disguise_active"] = adapter.get("disguise_active", false)
	combat["disguise_revealed"] = adapter.get("disguise_revealed", false)
	combat["companion_distraction"] = adapter.get("companion_distraction", false)

	# Party CC resistance: each CC used by any party member increases resistance faster
	# This prevents multiple players from perma-stunning/paralyzing
	if ability_name in ["shield_bash", "paralyze"]:
		combat["cc_resistance"] = combat.get("cc_resistance", 0) + 2  # Extra +2 per CC in party

	var messages = result.get("messages", [])

	# Track damage
	var damage_dealt = max(0, monster_hp_before - monster.current_hp)
	ms["total_damage_dealt"] = ms.get("total_damage_dealt", 0) + damage_dealt
	var self_damage = max(0, player_hp_before - character.current_hp)
	ms["total_damage_taken"] = ms.get("total_damage_taken", 0) + self_damage

	# Check if monster died
	if monster.current_hp <= 0:
		var victory_result = _process_party_victory(combat)
		messages.append_array(victory_result.get("messages", []))
		return {
			"success": true,
			"messages": messages,
			"combat_ended": true,
			"victory": true,
			"member_rewards": victory_result.get("member_rewards", {})
		}

	# Check if player died from ability self-damage (backfire etc.)
	if character.current_hp <= 0:
		combat.dead_members.append(acting_peer_id)
		ms["dead"] = true
		messages.append("[color=#FF0000]%s has fallen![/color]" % character.name)

	# Check if all members fled/dead
	if _all_members_inactive(combat):
		messages.append("[color=#FF4444]The party has been defeated![/color]")
		_end_party_combat(leader_id, false)
		return {"success": true, "messages": messages, "combat_ended": true, "victory": false}

	# Check if ability already ended combat (e.g., teleport = flee)
	if result.get("combat_ended", false):
		# Treat as this member fleeing
		if acting_peer_id not in combat.fled_members:
			combat.fled_members.append(acting_peer_id)
			ms["fled"] = true
		if _all_members_inactive(combat):
			_end_party_combat(leader_id, false)
			return {"success": true, "messages": messages, "combat_ended": true, "victory": false}

	# Advance turn (same logic as process_party_combat_action)
	# Free actions (analyze, pickpocket success, etc.) don't advance turns
	var is_free_action = result.get("free_action", false)
	if not is_free_action:
		combat.current_turn_index += 1
		_skip_inactive_members(combat)

		if combat.current_turn_index >= combat.members.size():
			var monster_results = _process_party_monster_phase(combat)
			messages.append_array(monster_results.get("messages", []))
			_check_party_deaths(combat)
			if _all_members_inactive(combat):
				messages.append("[color=#FF4444]The party has been wiped out![/color]")
				_end_party_combat(leader_id, false)
				return {"success": true, "messages": messages, "combat_ended": true, "victory": false}
			combat.round += 1
			combat.current_turn_index = 0
			_skip_inactive_members(combat)

	return {
		"success": true,
		"messages": messages,
		"combat_ended": false,
		"victory": false,
		"next_turn_peer_id": _get_current_turn_peer_id(combat)
	}

func _party_process_attack(combat: Dictionary, peer_id: int) -> Dictionary:
	"""Simplified attack logic for party combat member."""
	var character = combat.characters[peer_id]
	var monster = combat.monster
	var ms = combat.member_states[peer_id]
	var messages = []

	# Resource regen
	var mage_classes = ["Wizard", "Sorcerer", "Sage"]
	if character.class_type in mage_classes:
		var regen_pct = 0.03 if character.class_type == "Sage" else 0.02
		character.current_mana = min(character.get_total_max_mana(), character.current_mana + max(1, int(character.get_total_max_mana() * regen_pct)))

	# Hit chance
	var player_dex = character.get_effective_stat("dexterity")
	var equipment_speed = character.get_equipment_bonuses().get("speed", 0)
	var monster_speed = monster.get("speed", 10)
	var hit_chance = clamp(75 + (player_dex + equipment_speed - monster_speed / 2), 30, 95)
	if character.blind_active:
		hit_chance = max(10, hit_chance - 30)

	var hit_roll = randi() % 100
	if hit_roll >= hit_chance:
		messages.append("[color=#808080]%s's attack misses![/color]" % character.name)
		return {"messages": messages}

	# Damage calculation
	var weapon_damage = character.get_equipment_bonuses().get("attack", 0)
	var base_damage = max(1, character.get_effective_stat("strength") + weapon_damage)

	# Critical hit
	var crit_chance = 5
	if character.class_type == "Thief":
		crit_chance = 15
	elif character.class_type == "Ninja":
		crit_chance = 12
	var is_crit = (randi() % 100) < crit_chance
	if is_crit:
		base_damage = int(base_damage * 1.5)

	# Apply variance
	base_damage = apply_damage_variance(base_damage)

	# Analyze bonus
	var analyze = ms.get("analyze_bonus", 0)
	if analyze > 0:
		base_damage = int(base_damage * (1.0 + analyze / 100.0))

	# Apply damage to monster
	monster.current_hp -= base_damage

	var crit_text = " [color=#FFD700]CRITICAL![/color]" if is_crit else ""
	messages.append("[color=#00FF00]%s attacks for %d damage!%s[/color]" % [character.name, base_damage, crit_text])

	# Process companion attack if applicable
	if not character.active_companion.is_empty() and ms.get("companion_abilities", {}).size() > 0:
		var comp = character.active_companion
		var comp_level = comp.get("level", 1)
		var comp_tier = comp.get("tier", 1)
		var comp_damage = max(1, int(comp_tier * 3 + comp_level * 0.5))
		comp_damage = apply_damage_variance(comp_damage)
		monster.current_hp -= comp_damage
		messages.append("[color=#00FFAA]  %s's companion attacks for %d![/color]" % [character.name, comp_damage])

	return {"messages": messages}

func _party_process_flee(combat: Dictionary, peer_id: int) -> Dictionary:
	"""Process flee attempt for a party member."""
	var character = combat.characters[peer_id]
	var monster = combat.monster
	var messages = []

	var player_dex = character.get_effective_stat("dexterity")
	var equipment_speed = character.get_equipment_bonuses().get("speed", 0)
	var level_diff = max(0, monster.get("level", 1) - character.level)
	var flee_chance = clamp(40 + player_dex + equipment_speed - level_diff, 10, 95)

	# Ninja bonus
	if character.class_type == "Ninja":
		flee_chance = min(95, flee_chance + 40)

	var roll = randi() % 100
	if roll < flee_chance:
		messages.append("[color=#FFAA00]%s escapes from battle![/color]" % character.name)
		return {"messages": messages, "fled": true}
	else:
		messages.append("[color=#FF4444]%s fails to flee![/color]" % character.name)
		return {"messages": messages, "fled": false}

func _party_process_outsmart(combat: Dictionary, peer_id: int) -> Dictionary:
	"""Process outsmart attempt for a party member."""
	var character = combat.characters[peer_id]
	var monster = combat.monster
	var ms = combat.member_states[peer_id]
	var messages = []

	if ms.get("outsmart_failed", false):
		messages.append("[color=#808080]%s already failed to outsmart this enemy.[/color]" % character.name)
		return {"messages": messages}

	var player_wits = character.wits + character.wits_training_bonus
	var monster_int = monster.get("intelligence", 10)
	var outsmart_chance = clamp(30 + (player_wits - monster_int) * 2, 5, 75)

	var roll = randi() % 100
	if roll < outsmart_chance:
		# Victory by outsmarting
		messages.append("[color=#FFD700]%s outsmarts the %s![/color]" % [character.name, monster.get("name", "monster")])
		monster.current_hp = 0
		return {"messages": messages}
	else:
		ms["outsmart_failed"] = true
		messages.append("[color=#FF4444]%s fails to outsmart the %s![/color]" % [character.name, monster.get("name", "monster")])
		return {"messages": messages}

func _process_party_monster_phase(combat: Dictionary, max_actions: int = 0) -> Dictionary:
	"""Process the monster's actions against party members.
	max_actions: If > 0, limits the number of actions (used for first strike to prevent instant kills)."""
	var monster = combat.monster
	var messages = []

	# Check if monster is stunned
	var stun_turns = int(combat.get("monster_stunned", 0))
	if stun_turns > 0:
		combat["monster_stunned"] = stun_turns - 1
		messages.append("[color=#808080]The %s is stunned![/color]" % monster.get("name", "monster"))
		return {"messages": messages}

	# Monster gets N actions where N = active members (or capped by max_actions)
	var active_members = _get_active_members(combat)
	if active_members.is_empty():
		return {"messages": messages}

	var num_actions = active_members.size()
	if max_actions > 0:
		num_actions = min(num_actions, max_actions)
	var targets = _select_monster_targets(combat, active_members, num_actions)

	messages.append("[color=#FF8800]── %s's Turn ──[/color]" % monster.get("name", "monster"))

	# Tick enrage
	if "enrage" in monster.get("abilities", []):
		combat["enrage_stacks"] = min(10, combat.get("enrage_stacks", 0) + 1)

	for i in range(targets.size()):
		var target_pid = targets[i]
		var target_char = combat.characters[target_pid]
		var target_ms = combat.member_states[target_pid]

		# Calculate damage
		var base_str = monster.get("strength", 10)
		var enrage_bonus = 1.0 + combat.get("enrage_stacks", 0) * 0.1
		var raw_damage = max(1, int(float(base_str) * enrage_bonus))

		# Apply defense
		var player_def = target_char.get_equipment_bonuses().get("defense", 0)
		var damage = max(1, raw_damage - int(player_def * 0.5))

		# Apply variance
		damage = apply_damage_variance(damage)

		# Dodge check (DEX-based)
		var dodge_chance = min(30, target_char.dexterity / 5)
		if (randi() % 100) < dodge_chance:
			messages.append("         [color=#808080]%s dodges the attack![/color]" % target_char.name)
			continue

		# Forcefield check
		var shield = target_ms.get("forcefield_shield", 0)
		if shield > 0:
			var absorbed = min(shield, damage)
			target_ms["forcefield_shield"] = shield - absorbed
			damage -= absorbed
			if damage <= 0:
				messages.append("         [color=#9932CC]%s's forcefield absorbs the hit![/color]" % target_char.name)
				continue

		# Apply damage
		target_char.current_hp -= damage
		target_ms["total_damage_taken"] = target_ms.get("total_damage_taken", 0) + damage

		# Dwarf Last Stand
		if target_char.current_hp <= 0 and target_char.race == "Dwarf" and not target_char.last_stand_used:
			target_char.last_stand_used = true
			target_char.current_hp = max(1, int(target_char.get_total_max_hp() * 0.1))
			messages.append("         [color=#FF8800]%s takes %d damage! [color=#FFD700]LAST STAND! Dwarf resilience![/color][/color]" % [target_char.name, damage])
		else:
			messages.append("         [color=#FF8800]%s takes %d damage! (%d/%d HP)[/color]" % [target_char.name, damage, max(0, target_char.current_hp), target_char.get_total_max_hp()])

	return {"messages": messages}

func _select_monster_targets(combat: Dictionary, active_members: Array, num_actions: int) -> Array:
	"""Select targets for monster actions using weighted random."""
	var targets = []
	var weights = {}

	for pid in active_members:
		weights[pid] = combat.target_weights.get(pid, 1.0 / float(active_members.size()))

	# Normalize weights
	var total_weight = 0.0
	for pid in active_members:
		total_weight += weights.get(pid, 0.0)
	if total_weight <= 0:
		total_weight = 1.0
	for pid in active_members:
		weights[pid] = weights.get(pid, 0.0) / total_weight

	for _i in range(num_actions):
		var roll = randf()
		var cumulative = 0.0
		var chosen = active_members[0]
		for pid in active_members:
			cumulative += weights.get(pid, 0.0)
			if roll <= cumulative:
				chosen = pid
				break
		targets.append(chosen)

		# Halve chosen target's weight, redistribute
		if active_members.size() > 1:
			var halved = weights[chosen] / 2.0
			var redistributed = halved / float(active_members.size() - 1)
			weights[chosen] = halved
			for pid in active_members:
				if pid != chosen:
					weights[pid] = weights.get(pid, 0.0) + redistributed

	# Save updated weights
	combat.target_weights = weights
	return targets

func _check_party_deaths(combat: Dictionary):
	"""Check for newly dead party members."""
	for pid in combat.members:
		if pid in combat.dead_members or pid in combat.fled_members:
			continue
		var ch = combat.characters[pid]
		if ch.current_hp <= 0:
			combat.dead_members.append(pid)
			combat.member_states[pid]["dead"] = true

func _get_active_members(combat: Dictionary) -> Array:
	"""Get list of active (alive and not fled) member peer_ids."""
	var active = []
	for pid in combat.members:
		if pid not in combat.dead_members and pid not in combat.fled_members:
			active.append(pid)
	return active

func _all_members_inactive(combat: Dictionary) -> bool:
	"""Check if all party members have fled or died."""
	return _get_active_members(combat).is_empty()

func _get_current_turn_peer_id(combat: Dictionary) -> int:
	"""Get the peer_id of the member whose turn it is, or -1 if none."""
	if combat.current_turn_index < 0 or combat.current_turn_index >= combat.members.size():
		return -1
	var pid = combat.members[combat.current_turn_index]
	if pid in combat.dead_members or pid in combat.fled_members:
		return -1
	return pid

func _skip_inactive_members(combat: Dictionary):
	"""Skip dead/fled members in the turn order."""
	while combat.current_turn_index < combat.members.size():
		var pid = combat.members[combat.current_turn_index]
		if pid not in combat.dead_members and pid not in combat.fled_members:
			break
		combat.current_turn_index += 1

func _process_party_victory(combat: Dictionary) -> Dictionary:
	"""Process victory for all surviving party members."""
	var monster = combat.monster
	var messages = []
	var member_rewards = {}

	messages.append("[color=#00FF00]══════ VICTORY! ══════[/color]")
	messages.append("[color=#00FF00]The party defeated %s![/color]" % monster.get("name", "monster"))

	# Each surviving member gets FULL rewards (not split)
	for pid in combat.members:
		if pid in combat.dead_members:
			continue
		var character = combat.characters[pid]

		# XP calculation (per member, based on their level)
		var base_xp = monster.get("experience_reward", 10)
		var monster_level = monster.get("level", 1)
		var xp_level_diff = monster_level - character.level
		var xp_multiplier = 1.0
		if xp_level_diff > 0:
			var reference_gap = 10.0 + float(character.level) * 0.05
			var gap_ratio = float(xp_level_diff) / reference_gap
			xp_multiplier = 1.0 + sqrt(gap_ratio) * 0.7
		elif xp_level_diff < 0:
			var under_gap = abs(xp_level_diff)
			var penalty_threshold = 5.0 + float(character.level) * 0.03
			if under_gap > penalty_threshold:
				var excess = under_gap - penalty_threshold
				var penalty = minf(0.6, excess * 0.03)
				xp_multiplier = maxf(0.4, 1.0 - penalty)

		# House XP bonus
		var house_xp_mult = 1.0 + (character.house_bonuses.get("xp_bonus", 0) / 100.0)
		var final_xp = int(base_xp * xp_multiplier * house_xp_mult)

		# Gem drops
		var gems = 0
		if drop_tables and drop_tables.has_method("roll_gem_drops"):
			gems = drop_tables.roll_gem_drops(monster, character)

		member_rewards[pid] = {
			"xp": final_xp,
			"gems": gems,
			"drops": []
		}

		# Loot drops
		if drop_tables and drop_tables.has_method("roll_monster_drops"):
			var drops = drop_tables.roll_monster_drops(monster, character)
			member_rewards[pid]["drops"] = drops

		# Apply rewards
		character.experience += final_xp
		if gems > 0:
			character.add_crafting_material("monster_gem", gems)

		# Level up check
		while character.experience >= character.experience_to_next_level:
			character.experience -= character.experience_to_next_level
			character.level_up()

		messages.append("[color=#00BFFF]%s[/color]: +%d XP%s" % [
			character.name, final_xp,
			", +%d gems" % gems if gems > 0 else ""])

		# Combat durability wear for each surviving party member
		var wear_msgs: Array = []
		_apply_combat_wear(character, wear_msgs)
		for wm in wear_msgs:
			messages.append("[color=#00BFFF]%s[/color] - %s" % [character.name, wm])

	return {"messages": messages, "member_rewards": member_rewards}

func _end_party_combat(leader_id: int, victory: bool):
	"""Clean up party combat state."""
	if not active_party_combats.has(leader_id):
		return
	var combat = active_party_combats[leader_id]

	for pid in combat.members:
		var character = combat.characters.get(pid)
		if character:
			character.in_combat = false
			# Restore companion boosts
			var ms = combat.member_states.get(pid, {})
			var hp_boost = ms.get("companion_hp_boost_applied", 0)
			if hp_boost > 0:
				character.max_hp = max(1, character.max_hp - hp_boost)
				character.current_hp = min(character.current_hp, character.get_total_max_hp())
		party_combat_membership.erase(pid)

	active_party_combats.erase(leader_id)

func get_party_combat_state(leader_id: int) -> Dictionary:
	"""Get party combat state for client display."""
	if not active_party_combats.has(leader_id):
		return {}
	var combat = active_party_combats[leader_id]
	var monster = combat.monster
	var members_info = []
	for pid in combat.members:
		var ch = combat.characters.get(pid)
		if not ch:
			continue
		members_info.append({
			"peer_id": pid,
			"name": ch.name,
			"current_hp": max(0, ch.current_hp),
			"max_hp": ch.get_total_max_hp(),
			"current_mana": ch.current_mana,
			"max_mana": ch.get_total_max_mana(),
			"current_stamina": ch.current_stamina,
			"max_stamina": ch.get_total_max_stamina(),
			"current_energy": ch.current_energy,
			"max_energy": ch.get_total_max_energy(),
			"class_type": ch.class_type,
			"is_dead": pid in combat.dead_members,
			"is_fled": pid in combat.fled_members
		})
	return {
		"monster_name": monster.get("name", "Monster"),
		"monster_level": monster.get("level", 1),
		"monster_hp": max(0, monster.current_hp),
		"monster_max_hp": monster.max_hp,
		"round": combat.round,
		"members": members_info,
		"current_turn_peer_id": _get_current_turn_peer_id(combat)
	}
