# combat_manager.gd
# Handles turn-based combat in Phantasia 4 style
class_name CombatManager
extends Node

# Combat actions
enum CombatAction {
	ATTACK,
	DEFEND,
	FLEE,
	SPECIAL,
	OUTSMART,
	ABILITY
}

# Ability lookup for parsing commands
const MAGE_ABILITY_COMMANDS = ["magic_bolt", "bolt", "shield", "cloak", "blast", "forcefield", "teleport", "meteor"]
const WARRIOR_ABILITY_COMMANDS = ["power_strike", "strike", "war_cry", "warcry", "shield_bash", "bash", "cleave", "berserk", "iron_skin", "ironskin", "devastate"]
const TRICKSTER_ABILITY_COMMANDS = ["analyze", "distract", "pickpocket", "ambush", "vanish", "exploit", "perfect_heist", "heist"]

# Active combats (peer_id -> combat_state)
var active_combats = {}

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
const ABILITY_GOLD_HOARDER = "gold_hoarder"
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

# New abilities from Phantasia 5 inspiration
const ABILITY_CHARM = "charm"                    # Player attacks themselves for 1 turn
const ABILITY_GOLD_STEAL = "gold_steal"          # Steals 5-15% of player gold on hit
const ABILITY_BUFF_DESTROY = "buff_destroy"      # Removes one random active buff
const ABILITY_SHIELD_SHATTER = "shield_shatter"  # Destroys forcefield/shield buffs instantly
const ABILITY_FLEE_ATTACK = "flee_attack"        # Deals damage then flees (no loot)
const ABILITY_DISGUISE = "disguise"              # Appears as weaker monster, reveals after 2 rounds
const ABILITY_XP_STEAL = "xp_steal"              # Steals 1-3% of player XP on hit (rare, punishing)
const ABILITY_ITEM_STEAL = "item_steal"          # 5% chance to steal random equipped item

# ASCII art display settings
const ASCII_ART_FONT_SIZE = 10  # Default is 14, smaller = less space

func get_monster_combat_bg_color(monster_name: String) -> String:
	"""Get the contrasting background color for a monster's combat screen"""
	var raw_art_array = _get_raw_monster_ascii_art(monster_name)
	var art_color = _extract_art_color(raw_art_array)
	return _get_contrasting_bg_color(art_color)

func _get_contrasting_bg_color(art_color: String) -> String:
	"""Generate a dark contrasting background color based on the art's foreground color"""
	# Parse the hex color (format: #RRGGBB)
	if not art_color.begins_with("#") or art_color.length() < 7:
		return "#1A1A1A"  # Default dark gray

	var r = art_color.substr(1, 2).hex_to_int()
	var g = art_color.substr(3, 2).hex_to_int()
	var b = art_color.substr(5, 2).hex_to_int()

	# Create a dark version of the color (25% brightness) for background
	# This creates a noticeable tinted background that complements the art color
	var bg_r = int(r * 0.25)
	var bg_g = int(g * 0.25)
	var bg_b = int(b * 0.25)

	# Ensure minimum visibility (not pure black)
	bg_r = max(bg_r, 20)
	bg_g = max(bg_g, 20)
	bg_b = max(bg_b, 20)

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
	"""Apply ±15% variance to damage to make combat less predictable"""
	# Variance range: 0.85 to 1.15 (±15%)
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

func _ready():
	print("Combat Manager initialized")

func start_combat(peer_id: int, character: Character, monster: Dictionary) -> Dictionary:
	"""Initialize a new combat encounter"""

	# Check for ambusher ability (first attack always crits)
	var monster_abilities = monster.get("abilities", [])
	var ambusher_active = ABILITY_AMBUSHER in monster_abilities

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
		"player_can_act": true,
		"combat_log": [],
		"started_at": Time.get_ticks_msec(),
		"outsmart_failed": false,  # Can only attempt outsmart once per combat
		# Monster ability tracking
		"ambusher_active": ambusher_active,  # Monster's first attack crits
		# Note: Poison is now tracked on character (poison_active, poison_damage, poison_turns_remaining)
		"enrage_stacks": 0,  # Damage bonus per round
		"thorns_damage": 0,  # Damage reflected on hit
		"curse_applied": false,  # Stat curse active
		"disarm_applied": false,  # Weapon damage reduced
		"summoner_triggered": false,  # Already called reinforcements
		# Disguise ability tracking
		"disguise_active": disguise_active,
		"disguise_true_stats": true_stats,
		"disguise_revealed": false
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

	# Generate initial combat message
	var msg = generate_combat_start_message(character, monster)
	combat_state.combat_log.append(msg)

	return {
		"success": true,
		"message": msg,
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
		"defend", "d":
			action = CombatAction.DEFEND
		"flee", "f", "run":
			action = CombatAction.FLEE
		"special", "s":
			action = CombatAction.SPECIAL
		"outsmart", "o":
			action = CombatAction.OUTSMART
		_:
			# Check if it's an ability command
			if cmd in MAGE_ABILITY_COMMANDS or cmd in WARRIOR_ABILITY_COMMANDS or cmd in TRICKSTER_ABILITY_COMMANDS:
				return process_ability_command(peer_id, cmd, arg)
			return {"success": false, "message": "Unknown combat command! Use: attack, defend, flee, outsmart"}

	return process_combat_action(peer_id, action)

func process_combat_action(peer_id: int, action: CombatAction) -> Dictionary:
	"""Process a player's combat action"""
	
	if not active_combats.has(peer_id):
		return {"success": false, "message": "You are not in combat!"}
	
	var combat = active_combats[peer_id]
	
	if not combat.player_can_act:
		return {"success": false, "message": "Wait for your turn!"}
	
	var result = {}
	
	match action:
		CombatAction.ATTACK:
			result = process_attack(combat)
		CombatAction.DEFEND:
			result = process_defend(combat)
		CombatAction.FLEE:
			result = process_flee(combat)
		CombatAction.SPECIAL:
			result = process_special(combat)
		CombatAction.OUTSMART:
			result = process_outsmart(combat)
	
	# Check if combat ended
	if result.has("combat_ended") and result.combat_ended:
		end_combat(peer_id, result.get("victory", false))
		return result
	
	# Monster's turn (if still alive)
	if combat.monster.current_hp > 0:
		var monster_result = process_monster_turn(combat)
		result.messages.append(monster_result.message)
		
		# Check if player died
		if combat.character.current_hp <= 0:
			result.combat_ended = true
			result.victory = false
			result.monster_name = "%s (Lvl %d)" % [combat.monster.name, combat.monster.level]
			result.monster_level = combat.monster.level
			result.messages.append("[color=#FF0000]You have been defeated![/color]")
			end_combat(peer_id, false)
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
	var bonuses = character.get_equipment_bonuses()
	var mana_regen = bonuses.get("mana_regen", 0)
	var energy_regen = bonuses.get("energy_regen", 0)

	if mana_regen > 0 and character.current_mana < character.get_total_max_mana():
		var old_mana = character.current_mana
		character.current_mana = mini(character.get_total_max_mana(), character.current_mana + mana_regen)
		var actual_regen = character.current_mana - old_mana
		if actual_regen > 0:
			messages.append("[color=#66CCFF]Arcane gear restores %d mana.[/color]" % actual_regen)

	if energy_regen > 0 and character.current_energy < character.max_energy:
		var old_energy = character.current_energy
		character.current_energy = mini(character.max_energy, character.current_energy + energy_regen)
		var actual_regen = character.current_energy - old_energy
		if actual_regen > 0:
			messages.append("[color=#66FF66]Shadow gear restores %d energy.[/color]" % actual_regen)

	var stamina_regen = bonuses.get("stamina_regen", 0)
	if stamina_regen > 0 and character.current_stamina < character.max_stamina:
		var old_stam = character.current_stamina
		character.current_stamina = mini(character.max_stamina, character.current_stamina + stamina_regen)
		var actual_regen = character.current_stamina - old_stam
		if actual_regen > 0:
			messages.append("[color=#FF6600]Warlord gear restores %d stamina.[/color]" % actual_regen)

	# === POISON TICK (at start of player turn) ===
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

	# === BLEED TICK (stacking DoT from Bleed ability) ===
	var bleed_stacks = combat.get("player_bleed_stacks", 0)
	if bleed_stacks > 0:
		var bleed_dmg_per_stack = combat.get("player_bleed_damage", 5)
		var total_bleed = bleed_stacks * bleed_dmg_per_stack
		character.current_hp -= total_bleed
		character.current_hp = max(1, character.current_hp)  # Bleed can't kill either
		messages.append("[color=#FF4444]Bleeding deals %d damage! (%d stacks)[/color]" % [total_bleed, bleed_stacks])

	# === CHARM EFFECT (player attacks themselves) ===
	if combat.get("player_charmed", false):
		combat["player_charmed"] = false  # Only lasts one turn
		var self_damage = max(1, int(character.get_total_attack() * 0.5))  # 50% of player attack
		character.current_hp -= self_damage
		character.current_hp = max(1, character.current_hp)  # Can't kill yourself
		messages.append("[color=#FF00FF]You are charmed and attack yourself for %d damage![/color]" % self_damage)
		combat.player_can_act = false
		return {"success": true, "messages": messages, "combat_ended": false}

	# Check for vanish (auto-crit from Trickster ability)
	var is_vanished = combat.get("vanished", false)
	if is_vanished:
		combat.erase("vanished")

	# Hit chance: 75% base + (player DEX - monster speed) per point
	# DEX makes it easier to hit enemies, Vanish guarantees hit
	var player_dex = character.get_effective_stat("dexterity")
	var monster_speed = monster.get("speed", 10)  # Use monster speed as DEX equivalent
	var dex_diff = player_dex - monster_speed
	var hit_chance = 75 + dex_diff

	# Apply blind debuff (from monster ability)
	var blind_penalty = combat.get("player_blind", 0)
	if blind_penalty > 0:
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
		var regen_amount = max(1, int(character.max_hp * effects.get("combat_regen_percent", 0)))
		var actual_heal = character.heal(regen_amount)
		if actual_heal > 0:
			messages.append("[color=#FFD700]Divine Favor heals %d HP.[/color]" % actual_heal)

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

		# Lifesteal from scroll/potion buff
		var lifesteal_percent = combat.get("lifesteal_percent", 0)
		if lifesteal_percent > 0:
			var heal_amount = max(1, int(damage * lifesteal_percent / 100.0))
			var actual_heal = character.heal(heal_amount)
			if actual_heal > 0:
				messages.append("[color=#00FF00]Lifesteal heals you for %d HP![/color]" % actual_heal)

		# Thorns ability: reflect damage back to attacker
		if ABILITY_THORNS in abilities:
			var thorn_damage = max(1, int(damage * 0.25))
			character.current_hp -= thorn_damage
			character.current_hp = max(1, character.current_hp)
			messages.append("[color=#FF4444]Thorns deal %d damage to you![/color]" % thorn_damage)

		# Damage reflect ability: reflect 25% of damage
		if ABILITY_DAMAGE_REFLECT in abilities:
			var reflect_damage = max(1, int(damage * 0.25))
			character.current_hp -= reflect_damage
			character.current_hp = max(1, character.current_hp)
			messages.append("[color=#FF00FF]The %s reflects %d damage![/color]" % [monster.name, reflect_damage])

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
	var character = combat.character
	var monster = combat.monster
	var abilities = monster.get("abilities", [])

	# Custom death message
	var death_msg = monster.get("death_message", "")
	if death_msg != "":
		messages.append("[color=#FFD700]%s[/color]" % death_msg)
	else:
		messages.append("[color=#00FF00]The %s is defeated![/color]" % monster.name)

	# Death curse ability: deal damage on death
	if ABILITY_DEATH_CURSE in abilities:
		var curse_damage = int(monster.max_hp * 0.25)
		character.current_hp -= curse_damage
		character.current_hp = max(1, character.current_hp)
		messages.append("[color=#FF00FF]The %s's death curse deals %d damage![/color]" % [monster.name, curse_damage])

	# Calculate XP with level difference bonus
	var base_xp = monster.experience_reward
	var xp_level_diff = monster.level - character.level
	var xp_multiplier = 1.0

	if xp_level_diff > 0:
		if xp_level_diff <= 50:
			xp_multiplier = 1.0 + (xp_level_diff * 0.10)
		else:
			xp_multiplier = 6.0 + ((xp_level_diff - 50) * 0.05)

	var final_xp = int(base_xp * xp_multiplier)

	# Gold calculation with gold hoarder bonus
	var gold = monster.gold_reward
	if ABILITY_GOLD_HOARDER in abilities:
		gold = gold * 3
		messages.append("[color=#FFD700]The gold hoarder drops a massive treasure![/color]")

	# Easy prey: reduced rewards
	if ABILITY_EASY_PREY in abilities:
		final_xp = int(final_xp * 0.5)
		gold = int(gold * 0.5)

	# === CLASS PASSIVE: Ranger Hunter's Mark ===
	# +30% gold and XP from kills
	var passive = character.get_class_passive()
	var passive_effects = passive.get("effects", {})
	if passive_effects.has("gold_bonus") or passive_effects.has("xp_bonus"):
		var gold_mult = 1.0 + passive_effects.get("gold_bonus", 0)
		var xp_mult = 1.0 + passive_effects.get("xp_bonus", 0)
		gold = int(gold * gold_mult)
		final_xp = int(final_xp * xp_mult)
		messages.append("[color=#228B22]Hunter's Mark: +%d%% gold & XP![/color]" % int(passive_effects.get("gold_bonus", 0) * 100))

	if xp_level_diff >= 10:
		messages.append("[color=#FFD700]You gain %d experience! [color=#00FFFF](+%d%% bonus!)[/color][/color]" % [final_xp, int((xp_multiplier - 1.0) * 100)])
	else:
		messages.append("[color=#FFD700]You gain %d experience![/color]" % final_xp)
	messages.append("[color=#FFD700]You gain %d gold![/color]" % gold)

	# Award experience and gold
	character.add_experience(final_xp)
	character.gold += gold

	# Gem drops with gem bearer bonus
	var gems_earned = roll_gem_drops(monster, character)
	if ABILITY_GEM_BEARER in abilities:
		gems_earned = max(1, gems_earned * 2) if gems_earned > 0 else randi_range(1, 3)
		messages.append("[color=#00FFFF]✧ The gem bearer's hoard glitters! ✧[/color]")

	if gems_earned > 0:
		character.gems += gems_earned
		messages.append("[color=#00FFFF]✦ ◆ [/color][color=#FF00FF]You found %d gem%s![/color][color=#00FFFF] ◆ ✦[/color]" % [gems_earned, "s" if gems_earned > 1 else ""])

	# Weapon Master ability: 35% chance to drop a weapon
	if ABILITY_WEAPON_MASTER in abilities and drop_tables != null:
		if randf() < 0.35:  # 35% chance
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
			messages.append("[color=#808080]The Weapon Master's weapon shatters on death...[/color]")

	# Shield Bearer ability: 35% chance to drop a shield
	if ABILITY_SHIELD_BEARER in abilities and drop_tables != null:
		if randf() < 0.35:  # 35% chance
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
			messages.append("[color=#808080]The Shield Guardian's shield crumbles to dust...[/color]")

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
			messages.append("[color=#808080]The Arcane Hoarder's magic dissipates...[/color]")

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
			messages.append("[color=#808080]The Cunning Prey's gear vanishes into shadow...[/color]")

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
			messages.append("[color=#808080]The Warrior Hoarder's armor crumbles...[/color]")

	# Wish granter ability: 10% chance to offer a wish
	if ABILITY_WISH_GRANTER in abilities:
		if randf() < 0.10:  # 10% chance
			var monster_lethality = monster.get("lethality", 100)
			var wish_options = generate_wish_options(character, monster.level, monster_lethality)
			combat["wish_pending"] = true
			combat["wish_options"] = wish_options
			messages.append("[color=#FFD700]★ The %s offers you a WISH! ★[/color]" % monster.name)
			messages.append("[color=#FFD700]Choose your reward wisely...[/color]")
		else:
			messages.append("[color=#808080]The %s's magic fades before granting a wish...[/color]" % monster.name)

	# Title item drops (Jarl's Ring, Unforged Crown)
	var title_item = roll_title_item_drop(monster.level)
	if not title_item.is_empty():
		messages.append("[color=#FFD700]═══════════════════════════════════════════════════════════════════════════[/color]")
		messages.append("[color=#FFD700]★★★ A LEGENDARY TITLE ITEM DROPS! ★★★[/color]")
		messages.append("[color=#C0C0C0]%s[/color]" % title_item.name)
		messages.append("[color=#808080]%s[/color]" % title_item.description)
		messages.append("[color=#FFD700]═══════════════════════════════════════════════════════════════════════════[/color]")
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
		"wish_options": combat.get("wish_options", [])
	}

func process_defend(combat: Dictionary) -> Dictionary:
	"""Process player defend action (legacy - not currently in action bar)"""
	var character = combat.character
	var messages = []

	# Defending gives temporary defense bonus and small HP recovery
	var defense_bonus = character.get_effective_stat("constitution") / 4
	var heal_amount = max(1, character.get_total_max_hp() / 20)

	character.current_hp = min(character.get_total_max_hp(), character.current_hp + heal_amount)

	messages.append("[color=#87CEEB]You take a defensive stance![/color]")
	messages.append("[color=#00FF00]You recover %d HP![/color]" % heal_amount)
	
	# Apply temporary defense for monster's attack
	combat.defending = true
	combat.defense_bonus = defense_bonus
	
	combat.player_can_act = false
	
	return {
		"success": true,
		"messages": messages,
		"combat_ended": false
	}

func process_flee(combat: Dictionary) -> Dictionary:
	"""Process flee attempt"""
	var character = combat.character
	var monster = combat.monster
	var messages = []

	# Get class passive for flee bonuses
	var passive = character.get_class_passive()
	var passive_effects = passive.get("effects", {})

	# Flee chance based on level difference, DEX, and equipment speed
	# Base 50% + (DEX × 2) + equipment_speed + speed_buff + flee_bonus - (level_diff × 3)
	var equipment_bonuses = character.get_equipment_bonuses()
	var player_dex = character.get_effective_stat("dexterity")
	var speed_buff = character.get_buff_value("speed")
	var equipment_speed = equipment_bonuses.speed  # Boots provide speed bonus
	var flee_bonus = equipment_bonuses.get("flee_bonus", 0)  # Evasion gear provides flee bonus
	var monster_level = monster.get("level", 1)
	var player_level = character.level
	var level_diff = max(0, monster_level - player_level)  # Only penalize if monster is higher level

	# Base 50%, +2% per DEX, +equipment speed (boots!), +speed buffs, +flee bonus
	# -3% per level the monster is above you (fighting +20 level = -60%)
	var flee_chance = 50 + (player_dex * 2) + equipment_speed + speed_buff + flee_bonus - (level_diff * 3)

	# === CLASS PASSIVE: Ninja Shadow Step ===
	# +40% flee success chance
	if passive_effects.has("flee_bonus"):
		var ninja_flee_bonus = int(passive_effects.get("flee_bonus", 0) * 100)
		flee_chance += ninja_flee_bonus
		messages.append("[color=#191970]Shadow Step: +%d%% flee chance![/color]" % ninja_flee_bonus)

	# Apply slow aura debuff (from monster ability)
	var slow_penalty = combat.get("player_slow", 0)
	if slow_penalty > 0:
		flee_chance -= slow_penalty

	flee_chance = clamp(flee_chance, 5, 95)  # Hardcap 5-95%

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
	var messages = []
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

	# Check if already failed outsmart this combat
	if combat.get("outsmart_failed", false):
		messages.append("[color=#FF4444]You already failed to outsmart this enemy![/color]")
		return {
			"success": false,
			"messages": messages,
			"combat_ended": false
		}

	# Calculate outsmart chance - WIT vs monster INT is the key factor
	# Dumb monsters are easy to fool, smart ones nearly impossible
	var player_wits = character.get_effective_stat("wits")
	var monster_intelligence = monster.get("intelligence", 15)

	# Base chance is very low - outsmart is situational
	var base_chance = 5

	# WIT bonus: +5% per point above 10 (high wits = main factor)
	var wits_bonus = max(0, (player_wits - 10) * 5)

	# Trickster class bonus (+15%)
	var class_type = character.class_type
	var is_trickster = class_type in ["Thief", "Ranger", "Ninja"]
	var trickster_bonus = 15 if is_trickster else 0

	# Dumb monster bonus: +8% per INT below 10 (dumb = easy to trick)
	var dumb_bonus = max(0, (10 - monster_intelligence) * 8)

	# Smart monster penalty: -8% per INT above 10 (smart = hard to trick)
	var smart_penalty = max(0, (monster_intelligence - 10) * 8)

	# Additional penalty if monster INT exceeds your wits (-5% per point)
	var int_vs_wits_penalty = max(0, (monster_intelligence - player_wits) * 5)

	var outsmart_chance = base_chance + wits_bonus + trickster_bonus + dumb_bonus - smart_penalty - int_vs_wits_penalty
	var max_chance = 95 if is_trickster else 85  # Tricksters can reach 95%
	outsmart_chance = clampi(outsmart_chance, 2, max_chance)

	messages.append("[color=#FFA500]You attempt to outsmart the %s...[/color]" % monster.name)
	var bonus_text = ""
	if is_trickster:
		bonus_text = " [Trickster +20%%]"
	messages.append("[color=#808080](Wits: %d, Monster INT: %d = %d%% chance%s)[/color]" % [player_wits, monster_intelligence, outsmart_chance, bonus_text])

	var roll = randi() % 100

	if roll < outsmart_chance:
		# SUCCESS! Instant victory
		messages.append("[color=#00FF00][b]SUCCESS![/b] You outwit the %s![/color]" % monster.name)
		messages.append("[color=#FFD700]The enemy falls for your trick and you claim victory![/color]")

		# Give full rewards as if monster was killed
		var base_xp = monster.experience_reward
		var xp_level_diff = monster.level - character.level
		var xp_multiplier = 1.0

		# XP bonus for fighting stronger monsters
		if xp_level_diff > 0:
			if xp_level_diff <= 50:
				xp_multiplier = 1.0 + (xp_level_diff * 0.10)
			else:
				xp_multiplier = 6.0 + ((xp_level_diff - 50) * 0.05)

		var final_xp = int(base_xp * xp_multiplier)
		var gold = monster.gold_reward

		# Add XP and gold
		var level_result = character.add_experience(final_xp)
		character.gold += gold

		messages.append("[color=#FF00FF]+%d XP[/color] | [color=#FFD700]+%d gold[/color]" % [final_xp, gold])

		if level_result.leveled_up:
			messages.append("[color=#FFD700][b]LEVEL UP![/b] You are now level %d![/color]" % level_result.new_level)

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

				# Weapon Master ability: 35% chance to drop a weapon
			if ABILITY_WEAPON_MASTER in abilities:
				if randf() < 0.35:  # 35% chance
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
					messages.append("[color=#808080]The Weapon Master's weapon shatters on death...[/color]")

			# Shield Bearer ability: 35% chance to drop a shield
			if ABILITY_SHIELD_BEARER in abilities:
				if randf() < 0.35:  # 35% chance
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
					messages.append("[color=#808080]The Shield Guardian's shield crumbles to dust...[/color]")

			# Roll for gem drops
			gems_earned = roll_gem_drops(monster, character)
			if gems_earned > 0:
				character.gems += gems_earned
				messages.append("[color=#00FFFF]✦ ◆ [/color][color=#FF00FF]+%d gem%s![/color][color=#00FFFF] ◆ ✦[/color]" % [gems_earned, "s" if gems_earned > 1 else ""])

		# Wish granter ability: 10% chance to offer a wish
		if ABILITY_WISH_GRANTER in abilities:
			if randf() < 0.10:  # 10% chance
				var monster_lethality = monster.get("lethality", 100)
				wish_options = generate_wish_options(character, monster.level, monster_lethality)
				wish_pending = true
				messages.append("[color=#FFD700]★ The %s offers you a WISH! ★[/color]" % monster.name)
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
			"monster_name": monster.name,
			"monster_level": monster.level,
			"monster_base_name": monster.get("base_name", monster.name),
			"flock_chance": monster.get("flock_chance", 0),
			"dropped_items": all_drops,
			"gems_earned": gems_earned,
			"wish_pending": wish_pending,
			"wish_options": wish_options
		}
	else:
		# FAILURE! Monster gets free attack
		combat.outsmart_failed = true
		messages.append("[color=#FF4444][b]FAILED![/b] The %s sees through your trick![/color]" % monster.name)

		# Monster gets a free attack
		var monster_result = process_monster_turn(combat)
		messages.append(monster_result.message)

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

	# Normalize ability names
	match ability_name:
		"bolt": ability_name = "magic_bolt"
		"strike": ability_name = "power_strike"
		"warcry": ability_name = "war_cry"
		"bash": ability_name = "shield_bash"
		"ironskin": ability_name = "iron_skin"
		"heist": ability_name = "perfect_heist"

	# Universal abilities (available to all classes, use class resource)
	if ability_name == "cloak":
		result = _process_universal_ability(combat, ability_name)
	# Mage abilities (use mana)
	elif ability_name in ["magic_bolt", "shield", "blast", "forcefield", "teleport", "meteor", "haste", "paralyze", "banish"]:
		result = _process_mage_ability(combat, ability_name, arg)
	# Warrior abilities (use stamina)
	elif ability_name in ["power_strike", "war_cry", "shield_bash", "cleave", "berserk", "iron_skin", "devastate", "fortify", "rally"]:
		result = _process_warrior_ability(combat, ability_name)
	# Trickster abilities (use energy)
	elif ability_name in ["analyze", "distract", "pickpocket", "ambush", "vanish", "exploit", "perfect_heist", "sabotage", "gambit"]:
		result = _process_trickster_ability(combat, ability_name)
	else:
		return {"success": false, "message": "Unknown ability!"}

	# Check if combat ended
	if result.has("combat_ended") and result.combat_ended:
		end_combat(peer_id, result.get("victory", false))
		return result

	# Monster's turn (if still alive and ability didn't end turn specially)
	if not result.get("skip_monster_turn", false) and combat.monster.current_hp > 0:
		var monster_result = process_monster_turn(combat)
		result.messages.append(monster_result.message)

		# Check if player died
		if combat.character.current_hp <= 0:
			result.combat_ended = true
			result.victory = false
			result.monster_name = "%s (Lvl %d)" % [combat.monster.name, combat.monster.level]
			result.monster_level = combat.monster.level
			result.messages.append("[color=#FF0000]You have been defeated![/color]")
			end_combat(peer_id, false)
			return result

	# Increment round
	combat.round += 1
	combat.player_can_act = true

	# Tick buff durations and regenerate energy
	var expired_buffs = combat.character.tick_buffs()
	for buff in expired_buffs:
		var buff_name = buff.type.capitalize()
		result.messages.append("[color=#808080]Your %s buff has worn off.[/color]" % buff_name)
	# Note: Energy no longer regenerates automatically each round
	# Stamina regenerates when defending (10%), Mana doesn't auto-regen
	# Energy is the Trickster's precious resource - use it wisely!

	return result

func _process_universal_ability(combat: Dictionary, ability_name: String) -> Dictionary:
	"""Process universal abilities available to all classes (use class resource)"""
	var character = combat.character
	var messages = []

	# Check level requirement for cloak (level 20)
	if character.level < 20:
		return {"success": false, "messages": ["[color=#FF4444]Cloak requires level 20![/color]"], "combat_ended": false}

	# Determine cost based on class path (8% of max resource)
	var cost = character.get_cloak_cost()
	var resource_name = character.get_primary_resource()
	var current_resource = character.get_primary_resource_current()

	match ability_name:
		"cloak":
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
				messages.append("[color=#FF4444]You try to cloak but the %s sees through your disguise![/color]" % combat.monster.name)
				return {"success": true, "messages": messages, "combat_ended": false}

	return {"success": false, "messages": ["[color=#FF4444]Unknown universal ability![/color]"], "combat_ended": false}

func _process_mage_ability(combat: Dictionary, ability_name: String, arg: String) -> Dictionary:
	"""Process mage abilities (use mana)"""
	var character = combat.character
	var monster = combat.monster
	var messages = []

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

	var mana_cost = ability_info.cost

	# Get class passive for spell modifications
	var passive = character.get_class_passive()
	var passive_effects = passive.get("effects", {})

	match ability_name:
		"magic_bolt":
			# Variable mana cost - damage scales with INT
			# Formula: damage = mana * (1 + INT/50), reduced by monster WIS
			var bolt_amount = arg.to_int() if arg.is_valid_int() else 0
			if bolt_amount <= 0:
				return {"success": false, "messages": ["[color=#808080]Usage: bolt <amount> - deals mana × INT damage[/color]"], "combat_ended": false, "skip_monster_turn": true}
			bolt_amount = mini(bolt_amount, character.current_mana)
			if bolt_amount <= 0:
				return {"success": false, "messages": ["[color=#FF4444]Not enough mana![/color]"], "combat_ended": false, "skip_monster_turn": true}

			# === CLASS PASSIVE: Sage Mana Mastery ===
			# 25% reduced mana costs - apply to actual mana spent
			var actual_mana_cost = bolt_amount
			if passive_effects.has("mana_cost_reduction"):
				actual_mana_cost = int(bolt_amount * (1.0 - passive_effects.get("mana_cost_reduction", 0)))
				actual_mana_cost = max(1, actual_mana_cost)
				messages.append("[color=#20B2AA]Mana Mastery: Only costs %d mana![/color]" % actual_mana_cost)
			character.current_mana -= actual_mana_cost

			# Calculate INT-based damage (based on intended bolt_amount, not reduced cost)
			var int_stat = character.get_effective_stat("intelligence")
			var int_multiplier = 1.0 + (float(int_stat) / 50.0)  # INT 50 = 2x, INT 100 = 3x
			var base_damage = int(bolt_amount * int_multiplier)

			# Apply damage buff (from War Cry, potions, etc.)
			var damage_buff = character.get_buff_value("damage")
			if damage_buff > 0:
				base_damage = int(base_damage * (1.0 + damage_buff / 100.0))

			# === CLASS PASSIVE: Wizard Arcane Precision ===
			# +15% spell damage
			if passive_effects.has("spell_damage_bonus"):
				base_damage = int(base_damage * (1.0 + passive_effects.get("spell_damage_bonus", 0)))
				messages.append("[color=#4169E1]Arcane Precision: +%d%% spell damage![/color]" % int(passive_effects.get("spell_damage_bonus", 0) * 100))

			# === CLASS PASSIVE: Sorcerer Chaos Magic ===
			# 25% double damage, 10% backfire
			if passive_effects.has("double_damage_chance"):
				var chaos_roll = randf()
				if chaos_roll < passive_effects.get("backfire_chance", 0.10):
					# Backfire: damage yourself
					var backfire_dmg = int(base_damage * 0.5)
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
			var final_damage = apply_damage_variance(apply_ability_damage_modifiers(pre_mod_dmg, character.level, monster))

			monster.current_hp -= final_damage
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#FF00FF]You cast Magic Bolt for %d mana![/color]" % bolt_amount)
			messages.append("[color=#00FFFF]The bolt strikes for %d damage![/color]" % final_damage)

		"shield":
			if not character.use_mana(mana_cost):
				return {"success": false, "messages": ["[color=#FF4444]Not enough mana! (Need %d)[/color]" % mana_cost], "combat_ended": false, "skip_monster_turn": true}
			character.add_buff("defense", 50, 3)  # +50% defense for 3 rounds
			messages.append("[color=#FF00FF]You cast Shield! (+50%% defense for 3 rounds)[/color]" % [])

		"cloak":
			if not character.use_mana(mana_cost):
				return {"success": false, "messages": ["[color=#FF4444]Not enough mana! (Need %d)[/color]" % mana_cost], "combat_ended": false, "skip_monster_turn": true}
			combat["cloak_active"] = true  # 50% miss chance for enemy
			messages.append("[color=#FF00FF]You cast Cloak! (50%% chance enemy misses next attack)[/color]" % [])

		"blast":
			# Apply Sage mana cost reduction
			var blast_cost = mana_cost
			if passive_effects.has("mana_cost_reduction"):
				blast_cost = max(1, int(mana_cost * (1.0 - passive_effects.get("mana_cost_reduction", 0))))
			if not character.use_mana(blast_cost):
				return {"success": false, "messages": ["[color=#FF4444]Not enough mana! (Need %d)[/color]" % blast_cost], "combat_ended": false, "skip_monster_turn": true}
			if blast_cost < mana_cost:
				messages.append("[color=#20B2AA]Mana Mastery: Only costs %d mana![/color]" % blast_cost)
			# Base damage 50, scaled by INT (+3% per point) and multiplied by 2
			var int_stat = character.get_effective_stat("intelligence")
			var int_multiplier = 1.0 + (int_stat * 0.03)  # +3% per INT point
			var base_damage = int(50 * int_multiplier * 2)  # Blast = Magic × 2
			var damage_buff = character.get_buff_value("damage")
			base_damage = int(base_damage * (1.0 + damage_buff / 100.0))

			# === CLASS PASSIVE: Wizard Arcane Precision ===
			if passive_effects.has("spell_damage_bonus"):
				base_damage = int(base_damage * (1.0 + passive_effects.get("spell_damage_bonus", 0)))

			# === CLASS PASSIVE: Sorcerer Chaos Magic ===
			if passive_effects.has("double_damage_chance"):
				var chaos_roll = randf()
				if chaos_roll < passive_effects.get("backfire_chance", 0.10):
					var backfire_dmg = int(base_damage * 0.5)
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
			combat["monster_burn"] = {"damage": burn_damage, "rounds": 3}
			messages.append("[color=#FF6600]The target is burning! (%d damage/round for 3 rounds)[/color]" % burn_damage)

		"forcefield":
			if not character.use_mana(mana_cost):
				return {"success": false, "messages": ["[color=#FF4444]Not enough mana! (Need %d)[/color]" % mana_cost], "combat_ended": false, "skip_monster_turn": true}
			# Forcefield provides flat damage reduction = 50 + INT
			var int_stat = character.get_effective_stat("intelligence")
			var shield_value = 50 + int_stat
			combat["forcefield_shield"] = shield_value
			messages.append("[color=#FF00FF]You cast Forcefield! (Absorbs next %d damage)[/color]" % shield_value)

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
			# Apply Sage mana cost reduction
			var meteor_cost = mana_cost
			if passive_effects.has("mana_cost_reduction"):
				meteor_cost = max(1, int(mana_cost * (1.0 - passive_effects.get("mana_cost_reduction", 0))))
			if not character.use_mana(meteor_cost):
				return {"success": false, "messages": ["[color=#FF4444]Not enough mana! (Need %d)[/color]" % meteor_cost], "combat_ended": false, "skip_monster_turn": true}
			if meteor_cost < mana_cost:
				messages.append("[color=#20B2AA]Mana Mastery: Only costs %d mana![/color]" % meteor_cost)
			# Base damage 100, scaled by INT (+3% per point), multiplied by 3-4x (random)
			var int_stat = character.get_effective_stat("intelligence")
			var int_multiplier = 1.0 + (int_stat * 0.03)  # +3% per INT point
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
					var backfire_dmg = int(base_damage * 0.5)
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

		"paralyze":
			# Attempt to stun monster for 1-2 turns
			if not character.use_mana(mana_cost):
				return {"success": false, "messages": ["[color=#FF4444]Not enough mana! (Need %d)[/color]" % mana_cost], "combat_ended": false, "skip_monster_turn": true}
			var int_stat = character.get_effective_stat("intelligence")
			var success_chance = 50 + int(int_stat / 2)  # 50% base + 0.5% per INT
			success_chance = min(85, success_chance)  # Cap at 85%
			if randf() * 100 < success_chance:
				var stun_duration = 1 + (randi() % 2)  # 1-2 turns
				combat["monster_stunned"] = stun_duration
				messages.append("[color=#FFFF00]You paralyze the %s for %d turn(s)![/color]" % [monster.name, stun_duration])
			else:
				messages.append("[color=#FF4444]The %s resists your paralysis![/color]" % monster.name)

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

	return {"success": true, "messages": messages, "combat_ended": false}

func _process_warrior_ability(combat: Dictionary, ability_name: String) -> Dictionary:
	"""Process warrior abilities (use stamina)"""
	var character = combat.character
	var monster = combat.monster
	var messages = []

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

	var stamina_cost = ability_info.cost
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
			var str_stat = character.get_effective_stat("strength")
			var str_mult = 1.0 + (str_stat * 0.02)  # +2% per STR
			var base_dmg = int(total_attack * 1.5 * damage_multiplier * str_mult)
			var mod_dmg = apply_ability_damage_modifiers(base_dmg, character.level, monster)
			var damage = apply_damage_variance(mod_dmg)
			monster.current_hp -= damage
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#FF4444]POWER STRIKE![/color]")
			messages.append("[color=#FFFF00]You deal %d damage![/color]" % damage)

		"war_cry":
			character.add_buff("damage", 25, 3)  # +25% damage for 3 rounds
			messages.append("[color=#FF4444]WAR CRY![/color]")
			messages.append("[color=#FFD700]+25%% damage for 3 rounds![/color]" % [])

		"shield_bash":
			var str_stat = character.get_effective_stat("strength")
			var str_mult = 1.0 + (str_stat * 0.02)  # +2% per STR
			var base_dmg = int(total_attack * damage_multiplier * str_mult)
			var mod_dmg = apply_ability_damage_modifiers(base_dmg, character.level, monster)
			var damage = apply_damage_variance(mod_dmg)
			monster.current_hp -= damage
			monster.current_hp = max(0, monster.current_hp)
			combat["monster_stunned"] = true  # Enemy skips next turn
			messages.append("[color=#FF4444]SHIELD BASH![/color]")
			messages.append("[color=#FFFF00]You deal %d damage and stun the enemy![/color]" % damage)

		"cleave":
			var str_stat = character.get_effective_stat("strength")
			var str_mult = 1.0 + (str_stat * 0.02)  # +2% per STR
			var base_dmg = int(total_attack * 2 * damage_multiplier * str_mult)
			var mod_dmg = apply_ability_damage_modifiers(base_dmg, character.level, monster)
			var damage = apply_damage_variance(mod_dmg)
			monster.current_hp -= damage
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#FF4444]CLEAVE![/color]")
			messages.append("[color=#FFFF00]Your massive swing deals %d damage![/color]" % damage)
			# Apply bleed DoT (15% of STR per round for 4 rounds)
			var bleed_damage = max(1, int(str_stat * 0.15))
			combat["monster_bleed"] = {"damage": bleed_damage, "rounds": 4}
			messages.append("[color=#FF4444]The target is bleeding! (%d damage/round for 4 rounds)[/color]" % bleed_damage)

		"berserk":
			# Berserk scales with missing HP: +50% to +150% damage based on HP missing
			# At full HP: +50% damage. At 1% HP: +150% damage
			var hp_percent = float(character.current_hp) / float(character.max_hp)
			var missing_hp_percent = 1.0 - hp_percent
			var damage_bonus = int(50 + (missing_hp_percent * 100))  # 50-150%
			character.add_buff("damage", damage_bonus, 3)
			character.add_buff("defense_penalty", -50, 3)  # -50% defense for 3 rounds
			messages.append("[color=#FF0000][b]BERSERK![/b][/color]")
			messages.append("[color=#FFD700]+%d%% damage (scales with missing HP), -50%% defense for 3 rounds![/color]" % damage_bonus)

		"iron_skin":
			character.add_buff("damage_reduction", 50, 3)  # Block 50% damage for 3 rounds
			messages.append("[color=#AAAAAA]IRON SKIN![/color]")
			messages.append("[color=#00FF00]Block 50%% damage for 3 rounds![/color]" % [])

		"devastate":
			var str_stat = character.get_effective_stat("strength")
			var str_mult = 1.0 + (str_stat * 0.02)  # +2% per STR
			var base_dmg = int(total_attack * 4 * damage_multiplier * str_mult)
			var mod_dmg = apply_ability_damage_modifiers(base_dmg, character.level, monster)
			var damage = apply_damage_variance(mod_dmg)
			monster.current_hp -= damage
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#FF0000][b]DEVASTATE![/b][/color]")
			messages.append("[color=#FFFF00]A catastrophic blow deals %d damage![/color]" % damage)

		"fortify":
			# Defense buff - reduces incoming damage
			var str_stat = character.get_effective_stat("strength")
			var defense_bonus = 25 + int(str_stat / 4)  # 25% base + 0.25% per STR
			character.add_buff("defense", defense_bonus, 5)
			messages.append("[color=#00FFFF]You fortify your defenses! (+%d%% defense for 5 rounds)[/color]" % defense_bonus)

		"rally":
			# Heal + minor strength buff - warrior sustain ability
			var con_stat = character.get_effective_stat("constitution")
			var heal_amount = 20 + int(con_stat * 2)  # 20 base + 2 per CON
			var actual_heal = character.heal(heal_amount)
			var str_bonus = 10 + int(character.get_effective_stat("strength") / 5)
			character.add_buff("strength", str_bonus, 3)
			messages.append("[color=#00FF00]You rally your strength! Healed %d HP, +%d STR for 3 rounds![/color]" % [actual_heal, str_bonus])

	# Check if monster died
	if monster.current_hp <= 0:
		return _process_victory(combat, messages)

	return {"success": true, "messages": messages, "combat_ended": false}

func _process_trickster_ability(combat: Dictionary, ability_name: String) -> Dictionary:
	"""Process trickster abilities (use energy)"""
	var character = combat.character
	var monster = combat.monster
	var messages = []

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

	var energy_cost = ability_info.cost

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

			# Calculate and show outsmart chance
			var player_wits = character.get_effective_stat("wits")
			var is_trickster = character.class_type in ["Thief", "Ranger", "Ninja"]
			var base_chance = 5
			var wits_bonus = max(0, (player_wits - 10) * 5)
			var trickster_bonus = 15 if is_trickster else 0
			var dumb_bonus = max(0, (10 - monster_int) * 8)
			var smart_penalty = max(0, (monster_int - 10) * 8)
			var int_vs_wits_penalty = max(0, (monster_int - player_wits) * 5)
			var outsmart_chance = base_chance + wits_bonus + trickster_bonus + dumb_bonus - smart_penalty - int_vs_wits_penalty
			var max_chance = 95 if is_trickster else 85
			outsmart_chance = clampi(outsmart_chance, 2, max_chance)
			messages.append("[color=#00FFFF]Outsmart Chance:[/color] %d%%" % outsmart_chance)

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

		"pickpocket":
			var wits = character.get_effective_stat("wits")
			var success_chance = 50 + wits - monster.get("intelligence", 15)
			success_chance = clampi(success_chance, 10, 90)
			var roll = randi() % 100
			if roll < success_chance:
				# More gold: base * wits multiplier + monster level bonus
				var base_gold = 50 + (monster.level * 2)
				var stolen_gold = int(base_gold * (1.0 + wits * 0.05))  # +5% per wits
				character.gold += stolen_gold
				messages.append("[color=#00FF00]PICKPOCKET SUCCESS![/color]")
				messages.append("[color=#FFD700]You steal %d gold![/color]" % stolen_gold)
				return {"success": true, "messages": messages, "combat_ended": false, "skip_monster_turn": true}
			else:
				messages.append("[color=#FF4444]PICKPOCKET FAILED![/color]")
				messages.append("[color=#808080]The enemy catches you![/color]")
				# Enemy gets free attack
				var monster_result = process_monster_turn(combat)
				messages.append(monster_result.message)
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
			# Ambush uses weapon damage + WITS multiplier, affected by damage buffs
			var wits_stat = character.get_effective_stat("wits")
			var wits_mult = 1.0 + (wits_stat * 0.02)  # +2% per WITS
			var base_damage = character.get_total_attack()
			var damage_buff = character.get_buff_value("damage")
			var damage_multiplier = 1.0 + (damage_buff / 100.0)
			var base_dmg = int(base_damage * 1.5 * damage_multiplier * wits_mult)
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
			combat["vanished"] = true  # Next attack auto-crits
			messages.append("[color=#00FF00]VANISH![/color]")
			messages.append("[color=#808080]You fade into shadow... Next attack will crit![/color]")
			return {"success": true, "messages": messages, "combat_ended": false, "skip_monster_turn": true}

		"exploit":
			var damage = int(monster.current_hp * 0.10)  # 10% of current HP
			damage = max(1, damage)
			monster.current_hp -= damage
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#00FF00]EXPLOIT WEAKNESS![/color]")
			messages.append("[color=#FFFF00]You exploit a weakness for %d damage![/color]" % damage)

		"perfect_heist":
			# Chance-based instant win with double rewards
			var wits = character.get_effective_stat("wits")
			var monster_int = monster.get("intelligence", 15)
			# Base 40% success, +2% per wits over monster intelligence
			var success_chance = 40 + ((wits - monster_int) * 2)
			success_chance = clampi(success_chance, 15, 85)

			var roll = randi() % 100
			if roll < success_chance:
				messages.append("[color=#FFD700][b]PERFECT HEIST![/b][/color]")
				messages.append("[color=#00FF00]You execute a flawless heist![/color]")

				# Double XP and gold
				var base_xp = monster.experience_reward * 2
				var xp_level_diff = monster.level - character.level
				var xp_multiplier = 1.0
				if xp_level_diff > 0:
					if xp_level_diff <= 50:
						xp_multiplier = 1.0 + (xp_level_diff * 0.10)
					else:
						xp_multiplier = 6.0 + ((xp_level_diff - 50) * 0.05)

				var final_xp = int(base_xp * xp_multiplier)
				var gold = monster.gold_reward * 2

				var level_result = character.add_experience(final_xp)
				character.gold += gold

				messages.append("[color=#FF00FF]+%d XP (doubled!)[/color]" % final_xp)
				messages.append("[color=#FFD700]+%d gold (doubled!)[/color]" % gold)

				if level_result.leveled_up:
					messages.append("[color=#FFD700][b]LEVEL UP![/b] You are now level %d![/color]" % level_result.new_level)

				# Roll for item drops (double chance)
				var dropped_items = []
				var gems_earned = 0
				if drop_tables:
					var drops_result = drop_tables.roll_drops(
						monster.get("drop_table_id", "tier1"),
						monster.get("drop_chance", 5) * 2,
						monster.level
					)
					dropped_items = drops_result
					gems_earned = roll_gem_drops(monster, character) * 2
					if gems_earned > 0:
						character.gems += gems_earned
						messages.append("[color=#00FFFF]✦ ◆ [/color][color=#FF00FF]+%d gems (doubled!)![/color][color=#00FFFF] ◆ ✦[/color]" % gems_earned)

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
					"skip_monster_turn": true
				}
			else:
				# Failed heist - take damage and combat continues
				messages.append("[color=#FF4444][b]HEIST FAILED![/b][/color]")
				messages.append("[color=#FF4444]You're caught mid-heist![/color]")
				# Monster gets a free attack
				var monster_result = process_monster_turn(combat)
				messages.append(monster_result.message)
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

		"gambit":
			# High risk/reward - big damage but chance of backfire
			var wits = character.get_effective_stat("wits")
			var success_chance = 55 + int(wits / 4)  # 55% base + 0.25% per WITS
			success_chance = min(80, success_chance)  # Cap at 80%

			if randf() * 100 < success_chance:
				# Success - deal big damage (2.5x normal)
				var total_attack = character.get_total_attack() + character.get_buff_value("strength")
				var damage_buff = character.get_buff_value("damage")
				var damage_multiplier = 1.0 + (damage_buff / 100.0)
				var damage = apply_damage_variance(int(total_attack * 2.5 * damage_multiplier))
				monster.current_hp -= damage
				monster.current_hp = max(0, monster.current_hp)
				messages.append("[color=#FFD700][b]GAMBIT SUCCESS![/b][/color]")
				messages.append("[color=#00FF00]Your risky gambit pays off for %d damage![/color]" % damage)
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

	return {"success": true, "messages": messages, "combat_ended": false}

func _get_ability_info(path: String, ability_name: String) -> Dictionary:
	"""Get ability info from constants"""
	match path:
		"mage":
			match ability_name:
				"magic_bolt": return {"level": 1, "cost": 0, "name": "Magic Bolt"}
				"shield": return {"level": 10, "cost": 20, "name": "Shield"}
				"haste": return {"level": 30, "cost": 35, "name": "Haste"}
				"blast": return {"level": 40, "cost": 50, "name": "Blast"}
				"paralyze": return {"level": 50, "cost": 60, "name": "Paralyze"}
				"forcefield": return {"level": 60, "cost": 75, "name": "Forcefield"}
				"banish": return {"level": 70, "cost": 80, "name": "Banish"}
				"teleport": return {"level": 80, "cost": 40, "name": "Teleport"}
				"meteor": return {"level": 100, "cost": 100, "name": "Meteor"}
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

	# Check if item is usable in combat
	if drop_tables == null:
		return {"success": false, "message": "Item system not available!"}

	var effect = drop_tables.get_potion_effect(item_type)
	if effect.is_empty():
		return {"success": false, "message": "This item cannot be used in combat!"}

	var messages = []
	var item_name = item.get("name", "item")
	var item_level = item.get("level", 1)

	# Apply effect
	if effect.has("heal"):
		# Healing potion
		var heal_amount = effect.base + (effect.per_level * item_level)
		var actual_heal = character.heal(heal_amount)
		messages.append("[color=#00FF00]You drink %s and restore %d HP![/color]" % [item_name, actual_heal])
	elif effect.has("mana"):
		# Mana potion
		var mana_amount = effect.base + (effect.per_level * item_level)
		var old_mana = character.current_mana
		character.current_mana = min(character.get_total_max_mana(), character.current_mana + mana_amount)
		var actual_restore = character.current_mana - old_mana
		messages.append("[color=#00FFFF]You drink %s and restore %d mana![/color]" % [item_name, actual_restore])
	elif effect.has("buff"):
		# Buff potion - can be round-based or battle-based
		var buff_type = effect.buff
		var buff_value = effect.base + (effect.per_level * item_level)
		var base_duration = effect.get("base_duration", 5)
		var duration_per_10 = effect.get("duration_per_10_levels", 1)
		var duration = base_duration + (item_level / 10) * duration_per_10

		if effect.get("battles", false):
			# Battle-based buff (persists across combats)
			character.add_persistent_buff(buff_type, buff_value, duration)
			messages.append("[color=#00FFFF]You drink %s! +%d %s for %d battles![/color]" % [item_name, buff_value, buff_type, duration])
		else:
			# Round-based buff (single combat only)
			character.add_buff(buff_type, buff_value, duration)
			messages.append("[color=#00FFFF]You drink %s! +%d %s for %d rounds![/color]" % [item_name, buff_value, buff_type, duration])

	# Remove item from inventory
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

	# Check if monster is stunned (Shield Bash or Paralyze)
	var stun_turns = combat.get("monster_stunned", 0)
	if stun_turns is bool:
		# Legacy boolean stun (Shield Bash)
		if stun_turns:
			combat.erase("monster_stunned")
			return {"success": true, "message": "[color=#808080]The %s is stunned and cannot act![/color]" % monster.name}
	elif stun_turns > 0:
		# Multi-turn stun (Paralyze)
		combat["monster_stunned"] = stun_turns - 1
		if stun_turns - 1 <= 0:
			combat.erase("monster_stunned")
		return {"success": true, "message": "[color=#808080]The %s is paralyzed and cannot act! (%d turn(s) remaining)[/color]" % [monster.name, max(0, stun_turns - 1)]}

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
	var burn_data = combat.get("monster_burn", {})
	if burn_data.get("rounds", 0) > 0:
		var burn_dmg = burn_data.damage
		monster.current_hp -= burn_dmg
		monster.current_hp = max(0, monster.current_hp)
		burn_data.rounds -= 1
		combat["monster_burn"] = burn_data
		messages.append("[color=#FF6600]The %s burns for %d damage![/color]" % [monster.name, burn_dmg])
		if burn_data.rounds == 0:
			combat.erase("monster_burn")
			messages.append("[color=#808080]The flames die out.[/color]")
		# Check if burn killed the monster
		if monster.current_hp <= 0:
			return _process_victory(combat, messages)

	# Process bleed DoT on monster (from Cleave)
	var bleed_data = combat.get("monster_bleed", {})
	if bleed_data.get("rounds", 0) > 0:
		var bleed_dmg = bleed_data.damage
		monster.current_hp -= bleed_dmg
		monster.current_hp = max(0, monster.current_hp)
		bleed_data.rounds -= 1
		combat["monster_bleed"] = bleed_data
		messages.append("[color=#FF4444]The %s bleeds for %d damage![/color]" % [monster.name, bleed_dmg])
		if bleed_data.rounds == 0:
			combat.erase("monster_bleed")
			messages.append("[color=#808080]The bleeding stops.[/color]")
		# Check if bleed killed the monster
		if monster.current_hp <= 0:
			return _process_victory(combat, messages)

	# Regeneration ability: heal 10% HP per turn
	if ABILITY_REGENERATION in abilities:
		var heal_amount = max(1, int(monster.max_hp * 0.10))
		monster.current_hp = min(monster.max_hp, monster.current_hp + heal_amount)
		messages.append("[color=#00FF00]The %s regenerates %d HP![/color]" % [monster.name, heal_amount])

	# Enrage ability: +10% damage per round
	if ABILITY_ENRAGE in abilities:
		combat["enrage_stacks"] = combat.get("enrage_stacks", 0) + 1
		if combat.enrage_stacks > 1:
			messages.append("[color=#FF4444]The %s grows more furious! (+%d%% damage)[/color]" % [monster.name, combat.enrage_stacks * 10])

	# === ATTACK CALCULATION ===

	# Monster hit chance: 85% base, +1% per monster level above player (cap 95%)
	var player_level = character.level
	var monster_level = monster.level
	var level_diff = monster_level - player_level
	var hit_chance = 85 + level_diff
	hit_chance = clamp(hit_chance, 60, 95)

	# Ethereal ability: 50% chance for player attacks to miss (handled elsewhere)
	# but ethereal monsters also have lower hit chance
	if ABILITY_ETHEREAL in abilities:
		hit_chance -= 10  # Ethereal creatures are less precise

	# Defending reduces monster hit chance
	var is_defending = combat.get("defending", false)
	if is_defending:
		hit_chance -= 15

	# Clear defend status
	combat.defending = false
	combat.defense_bonus = 0

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
			var damage = calculate_monster_damage(monster, character)

			# Sabotage debuff: reduce monster damage
			var sabotage_reduction = combat.get("monster_sabotaged", 0)
			if sabotage_reduction > 0:
				damage = int(damage * (1.0 - sabotage_reduction / 100.0))
				damage = max(1, damage)

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

		character.current_hp -= total_damage

		# Player thorns from scroll/potion buff (reflect damage back to monster)
		var player_thorns = combat.get("player_thorns", 0)
		if player_thorns > 0 and total_damage > 0:
			var thorns_damage = max(1, int(total_damage * player_thorns / 100.0))
			monster.current_hp -= thorns_damage
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#FF00FF]Thorns reflect %d damage back![/color]" % thorns_damage)

		# Check for Dwarf Last Stand (survive lethal damage with 1 HP)
		if character.current_hp <= 0:
			if character.try_last_stand():
				character.current_hp = 1
				messages.append("[color=#FF4444]The %s attacks and deals %d damage![/color]" % [monster.name, total_damage])
				messages.append("[color=#FFD700][b]LAST STAND![/b] Your dwarven resilience saves you![/color]")
				return {"success": true, "message": "\n".join(messages), "last_stand": true}

		character.current_hp = max(0, character.current_hp)

		if num_attacks > 1:
			messages.append("[color=#FF4444]The %s hits %d times for %d total damage![/color]" % [monster.name, hits, total_damage])
		else:
			messages.append("[color=#FF4444]The %s attacks and deals %d damage![/color]" % [monster.name, total_damage])
	else:
		messages.append("[color=#00FF00]The %s attacks but misses![/color]" % monster.name)

	# === POST-ATTACK ABILITIES ===

	# Poison ability: apply poison if not already active (lasts 20 turns, persists outside combat)
	if ABILITY_POISON in abilities and not character.poison_active:
		if randi() % 100 < 40:  # 40% chance to poison
			var poison_dmg = max(1, int(monster.strength * 0.2))
			character.apply_poison(poison_dmg, 20)  # 20 combat turns
			messages.append("[color=#FF00FF]You have been poisoned! (-%d HP/round for 20 turns)[/color]" % poison_dmg)

	# Mana drain ability - drains the character's primary resource based on class path
	if ABILITY_MANA_DRAIN in abilities and hits > 0:
		var drain = randi_range(5, 20) + int(monster_level / 10)
		var resource_name = ""
		# Determine primary resource based on class type
		match character.class_type:
			"Wizard", "Sage", "Sorcerer":
				# Mage path - uses Mana
				character.current_mana = max(0, character.current_mana - drain)
				resource_name = "mana"
			"Fighter", "Barbarian", "Paladin":
				# Warrior path - uses Stamina
				character.current_stamina = max(0, character.current_stamina - drain)
				resource_name = "stamina"
			"Thief", "Ranger", "Ninja":
				# Trickster path - uses Energy
				character.current_energy = max(0, character.current_energy - drain)
				resource_name = "energy"
			_:
				# Default to mana for unknown classes
				character.current_mana = max(0, character.current_mana - drain)
				resource_name = "mana"
		messages.append("[color=#FF00FF]The %s drains %d %s![/color]" % [monster.name, drain, resource_name])

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

	# Curse ability: reduce a random stat for rest of combat (once)
	if ABILITY_CURSE in abilities and not combat.get("curse_applied", false):
		if randi() % 100 < 30:  # 30% chance
			combat["curse_applied"] = true
			character.add_buff("defense_penalty", -25, 999)  # Lasts entire combat
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
			# Damage a random piece of equipment
			var slots_to_damage = ["weapon", "shield", "armor", "helm", "boots"]
			slots_to_damage.shuffle()
			for slot in slots_to_damage:
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

	# Blind ability: reduces player hit chance (applied once per combat)
	if ABILITY_BLIND in abilities and not combat.get("blind_applied", false):
		if randi() % 100 < 40:  # 40% chance
			combat["blind_applied"] = true
			var blind_reduction = ability_cfg.get("blind_hit_reduction", 30)
			combat["player_blind"] = blind_reduction  # Reduces hit chance
			messages.append("[color=#808080]The %s blinds you! (-%d%% hit chance)[/color]" % [monster.name, blind_reduction])

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

	# Summoner ability: call reinforcements (once per combat)
	if ABILITY_SUMMONER in abilities and not combat.get("summoner_triggered", false):
		if randi() % 100 < 20:  # 20% chance
			combat["summoner_triggered"] = true
			# Use base_name so flock generates correct monster type (may still roll variant)
			combat["summon_next_fight"] = monster.get("base_name", monster.name)
			messages.append("[color=#FF4444]The %s calls for reinforcements![/color]" % monster.name)

	# Charm ability: player attacks themselves next turn (once per combat)
	if ABILITY_CHARM in abilities and not combat.get("charm_applied", false):
		if randi() % 100 < 25:  # 25% chance
			combat["charm_applied"] = true
			combat["player_charmed"] = true
			messages.append("[color=#FF00FF]The %s charms you! You will attack yourself next turn![/color]" % monster.name)

	# Gold steal ability: steals 5-15% of player gold on hit
	if ABILITY_GOLD_STEAL in abilities and hits > 0:
		if randi() % 100 < 35:  # 35% chance
			var steal_percent = randi_range(5, 15)
			var gold_stolen = max(1, int(character.gold * steal_percent / 100.0))
			character.gold = max(0, character.gold - gold_stolen)
			messages.append("[color=#FFD700]The %s steals %d gold from you![/color]" % [monster.name, gold_stolen])

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
			messages.append("[color=#FF00FF]The %s drains %d experience from you![/color]" % [monster.name, xp_stolen])

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

	return {"success": true, "message": "\n".join(messages)}

func calculate_damage(character: Character, monster: Dictionary, combat: Dictionary = {}) -> Dictionary:
	"""Calculate player damage to monster (includes equipment, buffs, crits, class passives, and class advantage)
	Returns dictionary with 'damage', 'is_crit', and 'passive_messages' keys"""
	var cfg = balance_config.get("combat", {})
	var passive_messages = []
	var passive = character.get_class_passive()
	var effects = passive.get("effects", {})

	# Use total attack which includes equipment
	var base_damage = character.get_total_attack()

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

	# === CLASS PASSIVE: Barbarian Blood Rage ===
	# +3% damage per 10% HP missing, max +30%
	if effects.has("damage_per_missing_hp"):
		var hp_percent = float(character.current_hp) / float(character.max_hp)
		var missing_hp_percent = 1.0 - hp_percent
		var rage_bonus = min(effects.get("max_rage_bonus", 0.30), missing_hp_percent * effects.get("damage_per_missing_hp", 0.03) * 10.0)
		if rage_bonus > 0.01:
			raw_damage = int(raw_damage * (1.0 + rage_bonus))
			passive_messages.append("[color=#8B0000]Blood Rage: +%d%% damage![/color]" % int(rage_bonus * 100))

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

	if is_crit:
		raw_damage = int(raw_damage * final_crit_damage)

	# === CLASS PASSIVE: Sorcerer Chaos Magic ===
	# 25% chance for double damage, 10% chance to backfire
	var backfire_damage = 0
	if effects.has("double_damage_chance"):
		var chaos_roll = randf()
		if chaos_roll < effects.get("backfire_chance", 0.10):
			# Backfire: deal damage to self instead
			backfire_damage = int(raw_damage * 0.5)
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

	# Apply level difference penalty (3% per level, max 50%)
	var lvl_diff = monster.get("level", 1) - character.level
	if lvl_diff > 0:
		var lvl_penalty = min(0.50, lvl_diff * 0.03)
		total = int(total * (1.0 - lvl_penalty))

	# === CLASS PASSIVE: Paladin Divine Favor ===
	# +25% damage vs undead/demons
	if effects.has("bonus_vs_undead"):
		var monster_type = monster.get("type", "").to_lower()
		if "undead" in monster_type or "demon" in monster_type or monster.name.to_lower() in ["skeleton", "zombie", "wraith", "lich", "elder lich", "vampire", "demon"]:
			total = int(total * (1.0 + effects.get("bonus_vs_undead", 0)))
			passive_messages.append("[color=#FFD700]Divine Favor: +%d%% vs undead![/color]" % int(effects.get("bonus_vs_undead", 0) * 100))

	# === CLASS PASSIVE: Ranger Hunter's Mark ===
	# +25% damage vs beasts
	if effects.has("bonus_vs_beasts"):
		var monster_type = monster.get("type", "").to_lower()
		if "beast" in monster_type or "animal" in monster_type or monster.name.to_lower() in ["giant rat", "wolf", "dire wolf", "giant spider", "bear", "dire bear", "wyvern"]:
			total = int(total * (1.0 + effects.get("bonus_vs_beasts", 0)))
			passive_messages.append("[color=#228B22]Hunter's Mark: +%d%% vs beasts![/color]" % int(effects.get("bonus_vs_beasts", 0) * 100))

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

func calculate_monster_damage(monster: Dictionary, character: Character) -> int:
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

	# Level difference bonus: monsters higher level deal extra damage (configurable)
	var level_diff = monster.level - character.level
	if level_diff > 0:
		var level_base = cfg.get("monster_level_diff_base", 1.04)
		var level_cap = cfg.get("monster_level_diff_cap", 75)
		var level_multiplier = pow(level_base, min(level_diff, level_cap))
		total = int(total * level_multiplier)

	# Minimum damage based on monster level (higher level = higher floor)
	var min_damage = max(1, monster.level / 5)
	return max(min_damage, total)

func end_combat(peer_id: int, victory: bool):
	"""End combat and clean up"""
	if active_combats.has(peer_id):
		var combat = active_combats[peer_id]
		var character = combat.character

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
	"""Check if a player is in combat"""
	return active_combats.has(peer_id)

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
	# If unknown, send -1 for HP values so client shows "???"
	var knows_monster = character.knows_monster(monster.name, monster.level)
	var display_hp = monster.current_hp if knows_monster else -1
	var display_max_hp = monster.max_hp if knows_monster else -1
	var display_hp_percent = int((float(monster.current_hp) / monster.max_hp) * 100) if knows_monster else -1

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
	"""Return ASCII art for the monster, properly formatted for centering"""
	# Map monster names to ASCII art - each line will be centered individually
	var art_map = {
		# Tier 1 - Small creatures
		"Goblin": ["[color=#00FF00]",
"                                   xxXx                                    ",
"                             +xxXXXXX$$$XXxxx+                             ",
"                          ++xXXX$$$$$$$&&$$XXXxx+                          ",
"                       ;;+xXXX$$$&&&&&&&&&&$$XXxxx+                        ",
"                      ;+xxxxXX$$&&&&&&&&&&&&&$$XXXXx                       ",
"                    .:;++xxXX$$$&&&&&&&&&&&&&&&$XXXXx+                     ",
"                    :;+;x+xX$$$$&&&&&&&&&&&&&$X$$$XXx+;                    ",
"  ++               .:;;;x+xX$$&&&&&&&&&&&&&&&$$$$XXxx+;                 x  ",
"  .:+xxxxx         :::;;;xxxX$XX$&&&&$&&&&&&$$$$XXx++++           xXXx+:.  ",
"   ....:+XXXXXx    ::::;;+XXXX$xX$&&&&&&&&&$X$$$$X++x+;;    xxXX$$X:..;:   ",
"    .;::...+X$$XX+::;::;xXX$$&$X&$$&$$&$$$&&&$$&&X+;++;:+xX$$$$x:...:+;    ",
"      :;::::.;xxXXX;:::+X$$X$&&&&&&$&$$&&&&$$&&&&$$x++;x$$$&X+:::+:+;.     ",
"      :++;:;;:.:+x+x;;;;:+x$&$&X&&&$&&X&&&$$&XXx;+;++++$&$x:.;XX;+;x;      ",
"       :x+;;;....:;;;;::....:+xX$X+xxXx+XX+x;......:;X+xX: .++X+;XX;       ",
"         ;;;;;::..;:;xx::.;;......+$&&&+.  .;::x;:+x$Xx+;..:.++;++:        ",
"          .:+;+;::+::+$Xx+;;;::;;+X&&&&$xx+;:;++;X&&$X+:x::x+x;x;          ",
"           .;++;+x;:.:;X$XXx$$x+++$&&&&$XXxx&XxX&$$X+;:;.+$++;+:           ",
"             ..;x;;;::.:;+X$$:;X$x$$&&&$$$$;;X&$$x;;:.:xXXXxx:             ",
"                :;;;.:;::++x;X;.;+xX&&$$x;.xX;x$x+::;;:+Xx;.               ",
"                  . .::;:+;;+$x;..;xxXx+.;+&$XX+xx;+x+:....                ",
"                    .;;;;+;;xxXx+:.;;++:X$&$$Xxx;Xx+++:                    ",
"                    .;;;;:+;:X&::;;:.:xxx;:.&$:+xxx+;x:                    ",
"                    ..;;;:...+XxX++...;++$;xXx:;:++;;:.                    ",
"                      .;;x++;+;+xxxxxxX$$$$X+xXXxx++..                     ",
"                       ..:;:;+++++++;;;+xxX$XX++x+:.                       ",
"                         ..;;;:;;;xxXX$$Xxx+++x+:.                         ",
"                           .:++x+XX$$$&&$&$XX+:..                          ",
"                            ..;+;xXXx+$x$X+x;..                            ",
"                              ..::;+;;+;;:;..                              ",
"                                 ..... ...                                 ","[/color]"],

		"Giant Rat": ["[color=#8B4513]",
"                                    ...........                            ",
"                               ......:X&X:.........                        ",
"          ..;             ;:..;.:xx;.+&&&$:......;...                      ",
"          .::x.   .......+;.:+$+.:..:x&&&&&&$$;........                    ",
"          :X.$&.......:x&&::&&$$.....:x&&&&$+..:........                   ",
"          ;x.+.:x:.+x:..:x...X&.;;:...;$&&&&&&X+..........                 ",
"      ..   .:.;:..X;+$;+.:;x&x..;&&x:.::&&&&;...:.........                 ",
"         . ..X..::X&&...;+.:x:.;$&&$:..X&&.$:;:;:$;........                ",
"           .+.:+X&x...Xx&++Xx:.;+$x;xX..x;.....;&xX$;x;.....               ",
"   :...   ..:..+XX&+.x&+:...;...:&&$X:;:$:..;&&&&&XXx..:.....              ",
"      ......X+&&&&&$;:;;...:...x&&&X;...+..;&&&&&$;+........               ",
"  .   ......X$&$+&&&+:::+x;:..&&&&;x:;:+;:&&&&&&+............              ",
"        . ...:.;&&$+;::.:;:.:&&&xx;..+...:$&&$++;............              ",
"      .  .   ..xx;...:..::x.$&&&x:.::;....:xXx;+;.............             ",
"               .........+:&&&&+:...xXX:X:....x++............+:..           ",
"                ...x+....Xxxx..x&&&X:....++...............:;;;$x+..        ",
"                 ............X&&&xX......+::....::..;:.........:;$&&;..    ",
"                 .++:........&&;.:...+..:..::.;;...:.:.............:&X+.   ",
"             ..&:&.$:.  :xxX&x&.......+;&x&x&;;:.......          ..:&$X..  ",
"              . .. .   ..;.;.;..     ..:.:.:....             .:;;X&xx....  ",
"                                         ..:;;;+;;+xX++++++;+x+.:......    ",
"                                    ...............................        ",
"                                 ....                                      ","[/color]"],

		"Kobold": ["[color=#CD853F]",
"                                     :+:                                   ",
"            ;x              ;:    :x$+.                                    ",
"            xX;           ;x.   :+&X+.     :++:                            ",
"            ;$x;     :   :x;:.::X&X::...:$&+.                       ;x$+.  ",
"             ;xXx+; $;  ..:;+++;;;..:x+++;&X;::               ++x$x. ...   ",
"             +xxXXx:X+.;;+xXXxxX$x++xX;&&x::x++::...   ++xxX&X. ...;::     ",
"             .xx.x..;+++X$&&x$$X$$$&:$&xx:..;;;;;:.:+x$&$;.  ..:++xx+      ",
"             .::++++;x$X$&X&&&$x&X;.:x$xXx;XX+::xx&&&&+  ..;;++xxX++:      ",
"            :;+;+Xx+xxx&&&&&x$:+X$$X&&XX$$++;&X&&X&X. .:;++;$$&XXXx:.      ",
"          :;x+X$X+X&xXXXxx&&&&&&&&&x&XX;;;;X$&$&$X...:;..:x&&&$$+:         ",
"          .;XX&XxxXx$xX+&&&&&$&$+:;:;:.:;X+&$X;++;. :xX+;;X$&&&$;:         ",
"           ..:;:;x+X&;&X&&$&x;..:...::;+++X$:;+.   ...+X$&X&X:;.           ",
"           ::.;X$$&&$X:;:;:..+;:&;;.;x$x+$&$$XxxX;:..xX&$XX$X.             ",
"         ::+xXXX&&&&x+XX;;.:::x$$&x+x&&&&&&&&+x:xX:.:$&&x&&.               ",
"      ;xxXX&&&&$$$&$$&x+$$X&Xx+++X&&&&&&&$XX;x+xx;+&$XX::+.::              ",
"      .xx&X$&&X.+x+&&$&&$$$$&&&&&&&&$$+++;+++:+;&&&&&&&: ..:               ",
"      .;xxxX&;:xx$&&&&&&&&&$&$XXxx+x;.:+++;x+x;:.&+:+. .+;:xX+:            ",
"      ::;xXX&&&&&&&&&&&X&$X+xXx::;+:XxXX+&$$&&x$+....:;+x+;::.:;           ",
"      .:;++&&&&&&&$x&xx;x;:.:+;....:+:$X&X&$&&x::;;:+X+X&;;:;+             ",
"      ..;;:+;Xx;:::..;x:;:::....;+&X$x$$&X&&+:;+:;xx:+;;+xx                ",
"       :x..:..::x& ..:X ..x&:$+&&&&&$$$x&$;:x&.:;&X&$+++                   ",
"        .;: ;....;.&:.;X;&;x&&&&+&XxX;+X.. ..:;+x&xxx+$                    ",
"          :+....;:;&&.;X&&&&&$+;;;+;:;:....:;;+XX&+;+                      ",
"         .::;:.++X$&&&&X$XXx+;+:. ..::++:;$:+x$xx+                         ",
"          ..::++xXxx+xX++;...... .+++xxx:Xxx;+&x                           ",
"           .:;+XxXXX+:........::+;:$X+;:XX;+$$                             ",
"           ...:x+;.;.   .:;:.:::::+XX+x:$&                                 ",
"              ..:.        ...::;;+++xX++&                                  ",
"                :          :;;;+;+X$&X                                     ",
"                                X X                                        ","[/color]"],

		"Skeleton": ["[color=#FFFFFF]",
"                                   ++xxx                                   ",
"                            :;+xxXXX$$&$$$$XXxx                            ",
"                         :;++xX$$$&&&&&&&&&&&&$$Xx+                        ",
"                      .:;++xX$$$&&&&&&&&&&&&&&&&&$$X+                      ",
"                    .:;++xxX&&&&&&&&&&&&&&&&&&&&&&&$$Xx                    ",
"                  .::;xxxX$&&&&&&&&&&&&&&&&&&&&&&&&&&$$X;                  ",
"                 .:;;+xxXX&&&&&&&&&&&&&&&&&&&&&&&&&&&&&XX+                 ",
"                .::++;xx$&$&&&&&&&&&&&&&&&&&&&&&&&&&&&&&$x+                ",
"                ::;;++++X$$&&&&&&&&&&&&&&&&&&&&&&&&&&&$$&$+                ",
"               ..;;+;:;+xxX$&&&&&&&&&&&&&&&&&&&&&&&$&&X$$$x;               ",
"               .:;;;:xx+xXXX$$&&&&&&&&&&&&&&&&&&&&&&&$XxXxX;               ",
"               .:;:..:+X+xX&&&&&&&&&&&&&&&&&&&&&&&&&&;x+;xX;               ",
"               .:;+;...&&&$&&&&&&&&&&&$$&&&&&&&&&&&&+;;;$XX:               ",
"               ..::::.x&&&&&$&&&&&&&&&&&&&&&&&&&&&&&&;:++x+:               ",
"               .:...:$xXX;Xx$X+X&&&&$&X&&&$&$X&&$+X&&&x:xx;.               ",
"                ::;..::      ...xxx;:+;:XXx;..      .++:x;:.               ",
"                ....:;:..        ..;&&&+:.        ...XX:.::                ",
"                 .: ;x;..:....   .;;&&&$$; .  .......&$....                ",
"                ;. ;;$$;;:::. ..+x+X...&&&X.....:;x:;&$X.:X:               ",
"                ;xx++x&&x;:;Xx&&$X+. :  $&&&&&X+xxX&&&$$&$x:               ",
"                .:;+;$$$$+xx$X$$+X;. ;  :&&&X$$XXxX$&&&$+:.                ",
"                  ..;;:+$X+;:.+x+$...+...$&&$;;+x&&X&$x:.                  ",
"                   ..:+:..;;x:;X$xX.:&x::$&&Xx&X:...;:.:.                  ",
"                   ....::  .:+x$x&$$&X&&&&&&&&+:. :;.:..                   ",
"                     ..:;  .:+$&x&$&&&&&&&&&&&x;  ;+::.                    ",
"                     .::+...::;X+Xx$&X$&$$x&+;:.  xx;;.                    ",
"                     .::+;..:;+$+&$&&$&&&&x&x$;:.:$;;+.                    ",
"                     :++;X; :::;;++xX+XX++x+:+;:x&X;x+:                    ",
"                     :xx;+X+;:;+&+&;&X&$$X&X+xx$X&x$Xx;                    ",
"                     .:++XX;+++x$X$$$$X&&&&$$$X+&Xxx;:                     ",
"                        .;+x;++x+xX$Xx$xX$XX$$&&$;:.                       ",
"                          .;$$&&+&X$&&&&$$$$&&&X;.                         ",
"                           .:;+$&$&&&&&&&&&&$x;.                           ",
"                             .:;Xx$&$xX&&&XX:.                             ",
"                                ...........                                ","[/color]"],

		"Wolf": ["[color=#808080]",
"              .=           %@@@@@@@@@@@@@@ @               =               ",
"                +#+    %%%@#%#@%#@@@@@@@@@@@@@@ @@       += ..             ",
"              .:-.++*%#@#*+=----+*-+@+-=*+%@@@@@@@@@#+=--.:::-.            ",
"             :=.:=:.+:--**-.:**=-*==:=*%%@@@#+-+++-.. :.:#+.==-            ",
"             .+- :##. ==--:%#**#%%@#*:-:+*%@@@*..::::..#@*.:*++            ",
"             -+=::%@@*: .:*%#@%--##*--=+##+##%**%=.  *@@@%.-%*#            ",
"             =*#+::@@#-  :+++--*#%#=:-++**##=.:=#:. :%@@@-.#@##            ",
"             -=*=+. =-  :-=.:*#%#=+=. -=-=*%@%*++%%*-=%+..==+*#            ",
"             =.+@@#-::--:.-+#-+#%#*=-.==*#=#%@@@%**@@+.--@@@++@            ",
"             =  ==..==: :=#@@@#*#==-.:-:**##%%@@@%*-+@@#.=*@=#@            ",
"            *+:  :#%+---==*@@#**=--=. :==**#@@@@@%@#=%%@@#-. *@@           ",
"          **+:  =+=:-=+=. .-#%@#-+=+.  -+==#@@**+-=#%%*=#@@+:+@@@@         ",
"          =-.-#%#:.:-::   .:=#@@#:-++.:=-.=@@%*-:. .+*@#--#@@##@@@         ",
"         =-=##===-.::   :*##*@@@@+-=-..-.=@@@@*@@@+..:-++-#@@@@@@@@        ",
"        *#=+*=:.. .:.       .=@@@@.-- :#=#@@@%..     ::==-+%@@@@@@@@       ",
"       *--*=:::.      -:*@:+@* :+:-+* -#.+#- *@@-@@+*:     =.  +@@@@@      ",
"     %*--+%@=.::   :-:+*=@@@%+:.+*==- -+--%::*#@@@*#@**%#+.-++=+*@@@@      ",
"    **=+%#*+%+-.  -#@=:=-.=%#--*#@@*%:==%*%@%+@@@-+@=:%@@@*%%*@@@@@@@@@    ",
"    =-..*@%*==@@@%*@@@-.=+*=*@@@@@@##:%@@@@@@@#**%=::%@@@@@@+*@@@@@@@@     ",
"    =-=+==@*=*@@@@#@@@%+@@@@@@@@@@#@#=%@#@@@@@@@@@@*@@@@@@@@@%@@@@@@@@@    ",
"    =:. +%+:+@@#@@#*%@%#*%%%%@@@@@+-=++#@@@@@@@@@@%%@@@@@@@@=--:*@@@@@@    ",
"    =-::. =-%%*#*+:=*+*=+#=-%@@@%: .-+=-:=@@@@@%#@@*%#*@@@@@@+@@%=@@@@     ",
"    -:.  . .@- .-++=--===+. +@@@#.        @@@@*.:%%#*+%%+-- =- .%#=%%@     ",
"    ===-.   - .@@@%@@*+*%#- .=*%#=      .%@@@+  +@@@@@@@@#:      =###      ",
"    *+--.     : .***@@#=#%*   .-....   :-..*-   @@@@@@@@@@%-*-::-#@@@      ",
"    =+--=:...     :*=.=++*%=  .@+++-:::=#**@*  =@@%%*%@=*-.:-=:-%@@@@      ",
"      -==+.:-=:    . =-*+=**=: %-   :-:   =@ .+@@@@@@-+=   ::-*##@@@@@     ",
"       ++-...-:-=      -**-+*. :       :: .-:.%@:.-@@#.  . .==:%@@@@@      ",
"       =---. ... ...  .     :#  @::--:=#+-@: %+ :-*#:=.:.=+:--.*+*@@       ",
"         =::..   :+.-=:=:.   -+ +@@:##*.#@@.*@ :**#@-  =**%#.:++%@@        ",
"          =-:=:  .  :*--+=-   *:  ++@%%#*::-@+:-*%@:. :+#%+-+-=%@@@        ",
"            =++=. .   :.*:+-  -@=   .++--.=@@:.+*.= .::*@%+- .:@@@         ",
"               +:::.     -+#-  -%#=:..:=#@@#. :*+: +*##-:*  ::=+@@         ",
"                =+--=:-- -+::.  ..##@@@@@-:   .===:%##@#:.  :++#*          ",
"                    =-+=:.  -:-    . :..: .=-:-=#*%*@*:#+.:-:-+            ",
"                       *--.:=-+-=-.      ..:.+@:##=+%-.:-:-+=*             ",
"                          -=+=--+.-:.  :-:+-==++=+-:=*===++ *              ",
"                              =*+====-:=-=++*+**** =+    =                 ",
"                                   =  -=                                   ","[/color]"],

		# Tier 2 - Medium creatures
		"Orc": ["[color=#228B22]",
"                                 $$$$&&&&                                  ",
"                            &&$$$$$$$$$$$$&&&&                             ",
"                         &&&$XX$$&&&&&&&&&&&$&&&&                          ",
"                       &&&XxXX$&&&&&&&&&&&&&&$$$$&&                        ",
"                      &&XXxXX$&&&&&&&&&&&&&&&&&&$&&&                       ",
"                     &&Xx+xXX$&&&&&&&&&&&&&&&&&&&&&&&&                     ",
"                    &&$x+xxx$$&&&&&&&&&&&&&&&&&X$&$$&&                     ",
"                    $Xx++XxxX$&&&&&&&&&&&&&&&&&&&&$$$&&                    ",
"                   $XxX++XxXX$$&&&&&&&&&&&&&&&&&&&$XX$$                    ",
"           X       Xx+;;+X$X$$&$&&&&&&&&&&&&&&&&&$$$XXX        &           ",
"           ::xXXX  Xx+x+$x$&&&&&&&&&&$&&&&&&&&&&&&$$$Xxx  &&&$+;           ",
"            ;::x$X++xx$&X&&&&&&&&&&&&&&&&&&&&&&&&&&$$Xxx$&&&;;+            ",
"            +++:;XX;+x++;xx+$&&$&&&&&&&&&&&&&&&XxXXX$$X&&&x+;+X            ",
"             +;xx.+;Xx;:.:...:+&&$$X&&$&&&$X:.:;+++x$$X$X:x&xX             ",
"             x++;..+&x;:...;... ..:+&&X;...:::x::;xx$$$x.:;xx+             ",
"             :;x+;x;xxXXx+;;;;;;;+x&&&&&&$+;+xxx&&&&&$x$;++$x+             ",
"              ;:;x;;;;+x&&$XX$$XXX$&&&&&&&$&&&&&&&&&&x+x+&;;+              ",
"               +X+;++;;;xxXX&&+;;++X&&&&XXx$&&&&XXXX+++xxXX+:;             ",
"                XX+$X+::;;+x$xX;::.:;+;:xX&&&&&&$++++XX+$$X.:              ",
"                ;;:$X++;;;&x+xXxXx++;:X&&&&&&$$&$XXxX$X+:;;                ",
"                  &&X;;+;+&&+XxX$X$&&&&&&&&&&$&&&&&X$$$x;;                 ",
"                  &$x;;X+x&&&;;::.:;$x;;:::++x&&&&&$$$Xx++                 ",
"                  &x+;++;;x&&&x&:..:.:;: .&&:X$$Xx&$XXX+xx                 ",
"                 &&x+;+;:.:+Xx;XXxXXxX$&&+Xx:;X+;+&$XXx;xx$                ",
"                &&&X;;;;+x;;+xxxX&$$$&&&&&&&&$XX$&$XXx;xX+X$&&             ",
"              &$$+X++:;;+;;::;;:;;;;;;;+xXxXX$XXX$X+x;+$XX$$&&&&           ",
"             &$Xx;++;;.:;;:::;::+X&&&&&&&&&XXx++Xx+;;+$$x$&&&&&            ",
"              $&Xxx++;;:.:::;++xxX&&&&&&&&&&&$Xx;;:x$$$X$&&&&&             ",
"                &$Xx;+;+;..:;;;xxxX$XxXX$$$Xx++..;+$&&$&&&                 ",
"                  $$xx+;x;:...::::::+;:;+++;;..;xx$$&$&&                   ",
"                     Xxx+++;.:.  ...::::::..:;+x+X$$&&&                    ",
"                      X$&$xxx;;:.......::;+++XXxx$$&                       ",
"                          &xX$x++;:;;+;+xxxX$$XX                           ",
"                             $  XXxxxxXX$$X&                               ",
"                                  $  X$&                                   ","[/color]"],

		"Hobgoblin": ["[color=#228B22]",
"                              ;;++++xxxx++++                               ",
"                          ::;+++++xxXXXxxxxxx+++                           ",
"                        ::;;++xxxxXXXXXX$$XXXxxx++                         ",
"                      .::;;++xxXxxXXX$$$$$XXXXXXxx++                       ",
"                     :::;++xxXXXXXX$$$$$$$$$$$XXxxx+;                      ",
"                    .:;;+;++xXXxXX$$$$$$$$$$$XXXxxxx+;                     ",
"                   ..:;;;;;+xxxxxX$$$$$$&&$&$XXXxXXx++;                    ",
"                   ..::;+;;+;xXXXX$$$&&&&&$$$XXXxXXxx+;                    ",
"                   ..::;;;;+x+xXX$$$&&&&&&$$$XxXXXxx++;:                   ",
"      ;+;          ..:::;:++xxXxXX$X$$$$$$XXXx+xXxxx+;;:          +++::    ",
"       .:;++;;     ..::;;;;;+++XXX$$$$$$$XX$XxxXx++++;;:     ;++xx;..      ",
"       ....:xx++;: .:;:;;xx;+xxXx+x$XXXX$$XXX$$Xx+++;;;: ;+xxXX+..::.      ",
"         ::...+X+;..::;+xxx+xXX$XxXXxX$&&&$$$$$$Xx+++;:;xXX$x.:;:++:       ",
"         .;:.:..+:...::+XXX$x$x$&$$x$&$$$$&$&Xx;+++x+;xXXXX:;+x;x+:        ",
"          ;;.::. .........;xxXX$XX&;XX$X$$X;.:+;:;++x;++x. .xX++;.         ",
"           ::::....::.. .:...::;::+;:++;:..:;...:;xxx;;:..::+x++;          ",
"            ::;:.:::;;:.:;;:. ..+x$X+....:+x+;:+X$$Xx;+X.::+x+;:           ",
"             :::;..:;x++++;:;:;;+X$$xxx+x;+xxx$&$Xx+;:+.;Xx;++;            ",
"              :;::..:;++xx+xx:;;xX&Xx$XX$&$XXXXXXx;:::+xx+;+x;             ",
"                ;;:...:;;+xx:+++xX&$XX$x;x$$Xx+;;:::+:xx:++.;;             ",
"                ........;;+;.:;;X$&$XX;;xxxXXx+:.;;++:;;:x+.::             ",
"                   .::::;;;+;..:+xx+::+X$$X+xx+;x++++. . ::                ",
"                   .:::::;;;+;:.....xX$$$xXXx+x;++xx+:.....                ",
"                    :::;:;X:;+x::::+$x$XX+&Xxxx+x;+++:..                   ",
"                    :::;::Xx.;..:++;::;;:xX;:xx++++;:;:.                   ",
"                     ..::::::;+xxxxx$$XX+;;:+;;;x+:.;;::;:                 ",
"                      ..:;:;:::.....:++xxx++Xx;;;..;x+:+;;                 ",
"                      ..:...:.:+++++x+;;;;;;++:..;++x+;++                  ",
"                       ...::;+;+XXX$&$XxXx;+:...:x+++++                    ",
"                       .....::;+x++x$Xxx+;:...:x+++++;                     ",
"                        ......:;;;+x+;;;....:;xxx+;                        ",
"                         ::..  .......  .::;x++xx+                         ",
"                           ::.. .......;;::xxx+                            ",
"                            ::::.:..:+++;:;+                               ",
"                               ::..::;++                                   ",
"                                 ::::                                      ","[/color]"],

		"Gnoll": ["[color=#DAA520]",
"                               ::   ;                                      ",
"                                :.::.; ::.                        .        ",
"        .::                  : :::...::.:...:  .               .;;.        ",
"        ..;::                :..:.;:.:::..:.::...  .         :xx....       ",
"       ....;xx:            ...:..:;+:;::::...;..... .    ::+X; ....        ",
"      ...:...+Xxx:        ... ..;;X;+.:+x:+;x;;..  .::.+x$&&...:::;:       ",
"       :;+;...&X&&+:.   .....::.+;+;;;&+:x;;;.;.+..:;X&&&&.  ..:;+x+.      ",
"      .+xx+:...XXXx;+:: .:::;.;:;+::X$$x+:.;+X.;.:X&&$x&::...:+;++++       ",
"      .:+xXx:..x&+x;:.;;:;:;+:..;:;;+X$Xx&$X$+$x+&&&&+XX.  .;+x++;+;.      ",
"      .+xx++;. ;Xx;;..:;:+;;++.;::x:;Xx$$X+X&&&x&$$$XX$:. .:::;+$X+..      ",
"      .;XXx+;;.  :..;:;+x;+x+;;x.;++X$xx&&&$$&$X$+;;xx: ...:;xx$$$$$;      ",
"       ..::x;;:. :;.:;+::;x$X$x.;X&&&&&$X&XXXx+X&&x+X;. ....;X$$+:+;.      ",
"        ::xX++;...+;;;+&$&&&&&+;&&&&&&&&&XxX&+x$$XX+. :+x.:+xX$$$X.        ",
"        .+++:.::..:;X$&&Xx&&&$X&&&$&&&&&&&&$&&X&&&$&X;.x..:$Xx:.;x.        ",
"          .....;.:x&&&&&&&&&&+xXX&x+&&&&&&&&&&X$XX+x$&&x::xx$+:..          ",
"             .:.:;X&&x&&&&&&&X+X&&&&&&&&&&&&&&X:;x;$x$X$xx$$:              ",
"              ..+;X$&X&&&&&&&X+&X&&&&X$&&;;;+XX++&&&&&xX:    ...:          ",
"             :.:.. .:$X&&:&x;:X&&&&$&X+.::. ::&&&&&$&$x$X: .:...:          ",
"             .:+++.:&X.::;+$Xxxx+:;:. +X&+;;+&&&&$x+;&&&&X..:.::.;;        ",
"            :.:;x$x:..:+x+$x&$$&&&X;;;.;:;$$&$&Xx+:x&&&&&&&x;;::.          ",
"            .:.;.+$+;x$+Xx:;x$$x&$&&$+&X$&&&&X::.xX&&&&&x$+.:::::          ",
"            ::.:;..Xx;:::;;+xX+&&&&&&&&&&Xxx::.;x&&&$&&&&X:x:+::::         ",
"             ...;.&++.x$;X&&+:;:+&&&&X+$$Xx:.:+$&$&&+&$xx;:+..;.:          ",
"            . ...:X.:  :...  . .x&&&x+x::+xX:$+X+$$&&&&.:;..:::;.          ",
"             : ..:::.::..:.;X;:X+$Xx;.... .;x&$$&X$&$&$$..:;...            ",
"                ....:.:.. ...+++:;;::$;. ..+x&&&$x&;$::+::;;;:             ",
"                :..:......;:::::.+&x:x... ..+X$x+XX;..::.:; ;              ",
"                 ..xx+xXX&X&+&+&.$&&.:.&x..:;xx$X;;:.:.::::;               ",
"                   .+X. .. :.. ..+&&;x&...;XxxXXX. .;;;:. ;                ",
"                    .;&..:;:.;::&x:;xx;;:;;;:.. ....:;;                    ",
"                     :X&X.x+x:+:&&;X.::xx+:;:  .::.: ;;.                   ",
"                     ..x:;&XX&X;&&:.:.Xxx:  ..:+..:.                       ",
"                     .:.:......:.;..:.:.. .:.;;+: ;                        ",
"                     ..;:..:.:.:++x:;:  ..::;;;                            ",
"                      :.. :.:+.;:..   .::..;;                              ",
"                       ... ...  ......:. :                                 ",
"                          .....    :::;                                    ",
"                                    :                                      ","[/color]"],

		"Zombie": ["[color=#556B2F]",
"                                :::;++xxX$&$                               ",
"                          :::..::;x$$&&&&&&&&&&&&                          ",
"                       ::....:::;:+x&&&&&&&&&&&&&&$$                       ",
"                    :::...:.:+xx$XX&&&&&&&&&&&&&&&&$$X$                    ",
"                 ::::...::;;::+x$&$&&&&&&&&&&&&&&&&&$$$$                   ",
"                 ::..:.:x+X::+:;X&&&&&&&&&&&&&&&&&&$XX$$XX                 ",
"                ;:..:.:x+XXx..;:&&&&&&&&&&&&&&&&&&X$$+&$XXX                ",
"              :+;...:.;+;::.;;+;xxX&&&&&&&&&&&&&&$&$&xx$xxx                ",
"            ;.:..::.:.::+::;+x;:+$X&&&&&&&&&&&&&&&$&X$x+xx+x               ",
"              :.::;;::+;.;Xxx+:;;$XX&&&&&&&&&&&&&&X&&$;+;++++              ",
"             :..::;;.;+;:.+;+XX+X+&&&&&&&&&&&&&&&Xxx$$X+++;++              ",
"             :..::.;:::xxx.+;+XX$x&&&&&&&&&$&&&&&&X$x$$+++;;x              ",
"            ..  .;;:...x:+x::;xXX$X$$&XXXxx$$X&&$+&&&&xx;;;+X              ",
"             ..:..:....xx$;$$XxX&&&&&&$$X$$&$&&&X&&&&&Xx.:;+x              ",
"              : :;;..:.++XX+$&$$&&&&&&&&&&&&&&&$&&&&&&&+.:;:+              ",
"            ;x+:.::+:.xx$Xx&$&&$&&&$$x&+$&&&&&$&&&&$X&&$+:::.x$X           ",
"            :.;+:..;;;;;....;;Xx$$$&+$X;+XX&&$&x+:::;;+xx;::x$x::          ",
"            ;..:;::.;;:.  .:+;...;;;.x$++;+x::.;xx:. ..;X;xx$+;;;          ",
"           :;:;+::::;;.  .;X&&x.  ..;&&&x+. .:x&&&+. ..;$xXx.x$++          ",
"            ;;;. :Xxxx::.:..::...:;+x&&&&xx:...::;::::++&&XX..:Xx          ",
"            :;:  ;:+$$++x;+:;X;;xXXx:...&&&$XX;+++xx+x&$&++x;.:+           ",
"             .;+:.;:+x$$+xX+++$$XxX...;..&&&;$X&$X&&&&X$x+;;:++:           ",
"              .::+:.;xXx$+Xx:xx+$;;...:: :xX$+$X$&$&$+:X;.:;xx;            ",
"               ;++::..;x.+.;:+;X$+x.:.$:::$XX&X&x.X;+:::.:xXx+;            ",
"               .:;...;:::.:.:+;;++;$++$x$xx&&X&;::: +.:::.:;:+             ",
"                :.:::::..:.+:;:x:x$&xXX&xX&x$+$+x...+;+;+.                 ",
"                 ::.::;;...: .;+.:.;;;;;X+&:;.;X;:;.:x+;+:                 ",
"                 .:.;x;;;:;:.:.::x;Xx$X&&$&;Xx;:+.+:;xx+x;                 ",
"                 .: ++;++:;:.... +.  ...  .:x.. ;.+;:XX;+:                 ",
"                  :.;;;++x;+. :.. .:...... :..:++++xX$x:.:;                ",
"                     ;.;+;;;...+X;+:.:+x+xx$+X:++:xX&;x..+                 ",
"                    .:.:x:;+x:;;:;x;xx$$$xxx;;xXX+XXX:.. ::                ",
"                   ::.:..;;+;+;+::+xX$XxX$X$:;:+x$X+...;+:                 ",
"                  ++:.::: .+x:x;.+::+x;:x+++:$:$x;; ..: ;                  ",
"                +;:;:::;:; .:;+x:++X&$&&&&&&$$&+; .::.;;                   ",
"                  :+:;:;+;:: :+x;xX&&$&X&$&XXx+..::;;: ;                   ",
"                   .;;;:+x;x:.::.+x+;+xX;;+&+..:;:+;:.;                    ",
"                    :;:.:;:+;:::..;:...... ..:.+:;x;x;                     ",
"                      ;;:x::x;;+......::.:+;:.;+::x;++                     ",
"                         .;.;::  ;...;;+xx+:.+x::.+                        ",
"                          +:;;:.:;+;::..::;.+x+: ;;                        ",
"                              +;;;;;+;::.::;+x+  ;                         ",
"                                ; ;; ;+; :;: +                             ","[/color]"],

		"Giant Spider": ["[color=#2F4F4F]",
"                              x    :    +                                  ",
"                  :x+         ;;;++;+++;;X++::x       xX:                  ",
"                   .x++  ::;;;;;;;;+;:&xx++xXxx:;;; .+;.                   ",
"          ++X   ::   +;:.:;;:;;+;+xx;;&&Xx$X$X$X++;+..   ;    x+           ",
"            .x$;:     .:;:;;:;++X$X$Xx&&$&&&&$&$Xx;;+..:..;+$x.            ",
"        +  :.  $x+:..::::x:::+Xx$&$&&+&&&&&&&&$$&xX$x+;:xx&+  .            ",
"        +;:.       :x;;x.:;+;+xX$&&&&x&&&&&&&&&$+++x$X$& ; . .:;:          ",
"       ::::.        :xX$;;X::;X&x&&&&&&&&&&&&&&&&&&&X&: :;+:.. ::;+;.      ",
"   +   ;:      :+x; :; +&X&&xx$x&&&&&$&&&&&&&&&&&&&&xX$&X&&&+:::...:       ",
"x   ...::        :&$&&&&&&&&&XxX$X&&&X&&&&&&&&&&&&&&&&&&&+::   .:;:;+:.    ",
":x+:..      .   :&+:;&X&&&&&&&&$X$$&&x+&&&&&&+&&&&&&&&+ +&+.. ;+::+  :::+xx",
"...:::.   ...    ;  ;   +&+X&&&XX&&&&xX&&&&&&&X&:+&x:.x :;    +X$x . .;;x++",
"      .       .         ;+  X$x+x&&&&&$&&&&X$&&. ;+.   .      +x+;   ;:    ",
":       :; : .:    . .     .+  ;&&:&&&&Xx +&&; ;      .      :;X.::...    ;",
"x++        :;X:.Xx:++  .        .   &;x&           :  XxxX&&.X+&+  :   +$$&",
"&&++;      .    + xX$+:XX.  ;:     + ;: +     .::.;&$xx&&: :   ..    :;x$x&",
"+Xxx:+             .   X+++&;.   .X$&&&&XX    +&&$$$X    .  : .::   .+X&$$$",
"+;;:: :;            :xx+.X;&&Xx&$&$&$&&:&&&&$&&&&+&:&&&;.    ::    :.::;+$+",
". ..  :;x;.  .    x;:        . &;X;x&;:&&$xx&      .  .+xX;      ;;.:.+;.$+",
" .   .::;X+:          ;x;x. .    +; ;: . ;+.   . .+xX+:  +;     ;::.  ;.++&",
" ..  . .x$X++;.     ;$&&&&X.  ;x&&&&.   x&&&&$: :;X&&&$X:   .;$xX;..;   :+.",
". .    .;;X++:;;:  :+$&&&&:; .++&&&XX  &;&&&&&+ ;;&&&&&$$+ :Xx:X;;:      +$",
": :    :.:+; +::  +:;X&&&x+: :. +x+;.  ::XX&&$; .x$&&&&&;X  + ;;::+     ; +",
" . .     .. +::; . ++;x&&;x:x ::+  ;x  Xx+:xX++ ;;$&&&&&X;x ;+++.;      ::;",
"       .:.:. .    :X;X$&Xx:. . ;+.X     +.::+.  ::x&&&&;X;; x::        . ; ",
" ..         ;     ;.:Xx&$++   X x. +    + :&:X  ;X+X&&x;Xx  ...  .        .",
". +  .       ..   ::  ;&&& x    ::. .  . +&;:   x ;&&x.++.  .       :  ;. +",
".:   +::.   ..    . . ;;&x.      xx;     x+.      ;&; . ; :+     ;:+ &  :;.",
" ;     + ;::::.:    .;  .& .      .     .:    :   ;;.       :..;+  $     .:",
"::;        Xx; ;:.. .:    :      :.. .    ..:     &    ..:+;;;+         ...",
":  ;            :; ;::;   +   :..:.   :  ....    X:  .:;; X  X          ; .",
"::              ;+   X ;.  ; .   &&     x;xXX  ..   .+        $           ;",
";                 $     x.   x:           &&  x:  ::+                    X ",
":                         ..+ xx             .  . ;                        ",
":;                         &;+. ::         ;:  +x X                        ",
"  ;                         &&           .    &&                           ",
"                             &$               &&                           ",
"                                              &                            ","[/color]"],

		"Wight": ["[color=#708090]",
"                              *    *#####*                                 ",
"                           ******#*******#####                             ",
"                         ###***++++++*********##*                          ",
"                        ##*+++++==+**######*#******                        ",
"                      ##*+++=====+**#######*********                       ",
"                     #*+=======+++**#########****+++**                     ",
"                  *#**+===--====+***#####%#####*+*++=**                    ",
"                 *##*+=-=---====+***##%%#%%#####*+++=+**                   ",
"                 ##**=-==--==+=+*#***+##%%%#*##**+====+**                  ",
"                 #**+-=---=++++*#*=--:--+##*#***++=====+##                 ",
"                 #*+=-=--+++++=-*=-::::--=***#+*+++==-=+**#                ",
"                 **+--=--*+**=---:::---:---=*-**+**+=-==+**                ",
"                 *+==---=***--:::------------=-+*+*+===-=*##               ",
"               ##*+=----=**+--------==-===------=***====-=###              ",
"              ##*++=-=-==--::-====+=+==+++===+=--=*#*+===-+###             ",
"             ##*++=--===+:-:--=+****+++**##**+=--:++***++==+##             ",
"         # ###**+==+=====:--=+=--+*++==++**==+++-:--=**=++==*##            ",
"         #####*+====++==-:::=#%%*-:--+*=-:-*%%%+-::--+#+=+==*##            ",
"       # ##*#**=====+*------:----:--=*#+=-:--=--:-----**=+==+*##           ",
"      ## ##**+==++==*+:----==--===+=+-*##***==+=+===---*==+=+**##          ",
"       ####*++==*+=+-=:--:-=***+*+++-:--#**##%%#*+---=-=*++=**###          ",
"       ##*#*+==+=*+-:-:----===+++++-::::+*+****+==--==--#**++*####         ",
"        ##*+=+=-++-:-----::---======-:--==**+==-----+----*#****##%##       ",
"        #*++*=-===-::--==:--::--===-----==++=-------*-----+#***####%##     ",
"      ####*++==-------=+=---::-==-=:::::--+-==-----=+------++**++#%####    ",
"     ###+++===------=--++=-----=---:::::::=:--==--=-=--=----=-+***#####    ",
"    #***++===-==---==-==*+=----=-:::::::::-:--+=-==-=--==----===+*%###     ",
"   #*####++====+=======-**==---==-:::::::::-==+-=---===++-----++**#%%#     ",
"   ######*+==++=-+*====--=*==-====--::::::--*++----=+*+++===--++*#####     ",
"    ######***+++--+++=-=-=-++---+==----:--+=*=-----+##+**+====+*##%##      ",
"      ########++=+==+*+=-=--==---===+=--++*=+---===+##*=#==+++**#%##       ",
"        ###*****+++==++*+===--+--=-**++*#*+==--=+==*##==+==+++**###        ",
"         ####******+==++*+==+=-+=---===+++----==+==#*=-==+=+*#**###        ",
"           #####%#*++===+*++++=-++--=--==----===++**+==+*++*##*####        ",
"            ####%%##+*===*+=++*+=+===--=----===****+==+****#######         ",
"               ######*+++#++===**+=-==--==-===*++#+==++***##### #          ",
"                 #%%##*+**+=+*==***=-====-=+=+*#*#===+***#####             ","[/color]"],

		# Tier 3 - Large creatures
		"Ogre": ["[color=#556B2F]",
"                                *+*#****++                                 ",
"                           +****##%@%%%%#**==-                             ",
"                         +***#%@@@@@@@@@%#**++==:                          ",
"                       =+**#%@@@@@@@@@@@@@###*+++=:                        ",
"                      -+*+*#%%@@@@@@@@@@@@@%%#*+**+:                       ",
"                     -+++*#*%@@@@@@@@@@@@@%@%***#**+                       ",
"                    .:-=++*%%@@@@@@@@@@@@@%%#**+++*+--   =**.              ",
"           *+       +=-:=###**#@@@@@@@@@@%%#*%%**-=+-:-*%*                 ",
"             :=*%%#:=#+=-##@@%#@@@@@@@@@@@@@@%%%##*===#%-  :               ",
"            .:  :*@@*+=*+@@@@@@@@@@@@@@@@@@%#@@***#%*-= ::--               ",
"             +* :  +-*#==-:-@@@%@@@@@@@@@%#@#-.. .+@@%   +.                ",
"              :-=   -*@#:     :-==.-%%=::        =+%@*-:#:= =+             ",
"                .=*:-#@#=-   -:  .=#@@#=-...::=#@%%+- -#-**+=-=+=          ",
"                -+=..=#%%@@@%+##*##@@@@*#%=%@@#%*+=. :-#%. +*+:==+*=       ",
"         .     .:-=+: :-##**@@*.  -+%#*:   +#@@#=  :-*%#+#+:=%==*#*#*+     ",
"       :.--..::- :=**=-=:*@@@+#@*:.     .=#%%%**#*=#=%#*###%=+%+*#=+#@#*=  ",
"     .:===--*=-:--****%@##@+%@**%@@*---**#***@%+#@**+*#**#**::#+=#++++#**#%",
"  ..:==-==:+++-.:*=**#%%@@*+%@@:@-. .     @-@@+--#@@@#*+++-==*+:=*#*++-=++%",
"=-:---===::*+-- =+*=#%#%%***.+*-*-:-+-+%%#*-::   =%#%+-=*::-==+-+%%%%*++=+#",
"++=+*==**-:++-. =**:+*+**@-   .##@%#+=---==*%**=+.=*----*=-+-:++-@######*%%",
" *##****+-:=+.-.-+*+-=+====#*=++=:.-+*#**=::.:=+=--:. :#*+== :=:+@@%%%%%#% ",
"  ***++*+=.-= :..=:++=.. +#-=:-.:+#@@@@@@@%++--:==:  =%+++=. -:=@@%*%#%### ",
"  ##=*+##*-.= ..*#+-%%+=#+=+=.-#%%%@@#*@@@%*++=#==..*%#++-: : :#@@%######% ",
"   #%%=**@%:-: .--*-=#%+:=+::=*#*+*#*.=*#*+-:--.  :##=+*:  .::%%%#+##+*#%  ",
"   ***%##%@#:=  =-==-*%%%+.-:  .:::-.:+::. .    :#%@*==:   ::#**==***#%%   ",
"   #*++*%##++-: . ---=*%%%@#--:      ::.      :*%%+**:     -*%*::#*=*%%    ",
"     *%*##**#*=  . :--=+##@@%@*+:         :=+%%**#+- .    .**-.+*####@     ",
"     *****+#%#*-.  . :---=**#%@%**===+*#***%%#*++-:..     =-:***##%@       ",
"     ###+###*#+*=-   :: .::-+*##**#%@@@@#*+*++=:.:.     --==+++**###       ",
"        *####*##*+-:      :::=-==**=+*++++===:        -+*=+-+=***#%        ",
"         %*#%##@@%*#+.      ..:-::-=-:-...         -=*%%%*=+=*%%%*         ",
"          ###%@@@%+%%**-          --::-         -==+#%%++*##*##            ",
"           @@@%@@@@@@%%#*+:.                ...:=+##%%@%#*+                ",
"             %@@@%@@%@@@*#*=---.         ::--=++*%***@@@%@%%               ",
"                @%@@@%%@@@%#%*=-=::.. .-:::--++%%@##**%%%%                 ",
"                   %@%%@%#%@%#**=---. .---=+=*#%*%*++*#%                   ",
"                       @##+##*+++===..::==:++**#**#+                       ",
"                          #+**++*#=+:::-:=+*+#  +                          ",
"                                 =+*+::=--=                                ",
"                                     -=                                    ","[/color]"],

		"Troll": ["[color=#556B2F]",
"                             Xx      xX    XX+   ;                         ",
"                        x;   x+++xxX+x x+x ;+x xx    x                     ",
"                   ; +   Xxx +;.;x++xxx+;++;;;;xx xXxXx                    ",
"                  :+  ;;:;;;++: .::.:;++:.:::+x++++x+;+x  +                ",
"                x  ++;+;::..:;...::;++:.;;x++++;x;;;;++x++                 ",
"          +   :;:;;.::+;:...:.::;;;:;+;+x;+::+;+;..:++++;+ X               ",
"          x+;   ;;;::..:.::;+;++x;:;+$&Xx+;:::::.:...:+:;Xxxx  ;           ",
"           ;;++++;:;.. ...;.;+:+x ;:;$&$+x+:::::+;+;x;;++++x+;xX           ",
"          ;  :.:;:;... .:;;;: :+x+XxxX&&&&&&&XX++:;+;+x+:::++x             ",
"        X++;::...  .;;:...;;;;X&&&&&&&&&&&&&&&&&X;::..: .::++ x      x     ",
"            +;:.  ....:. :;++xX&&&&&&&&&&&&&&&&&$$+;;:...::+xxx  X   x     ",
"    xx  + ++;;: .......  .::;XX$&$&&&&&&&&&&&&&&&$x;:;x:;;+;;::;++xXx      ",
"      ;;::.:::.  .:. ..  .:++xXXX&&&&&&&&&&&$x&&$xX+:..;:::.::;+;;x        ",
"   +Xx+  ;: ..   .  .  :.:X$$$&&&&&&$&&&&&&&&&&&&xX+;.;:   ..::;+x$&&&&x:  ",
"       :+xx:..    .;.   +X$&$X$$&&&&&&&&&&&$&&&&X&X+x:++.  ;X$&&&&$:  :    ",
"      :    ;;;;xx;:    ;+..;+&X&&x+x$X;&&&$&&;;:+$x+x:.;;;+&&$&:  .;+.     ",
"     ;:;:;;: .xx+;: . :. .    ..: +&&&&&;:..     ;+xX+;::x&Xx  :++:+:      ",
"     ; :.;;;+;  ;:  :+++:  .;.  ;xX&&&&&&x: ;Xx;;x$&&&;:;x+ :X$&x+X+       ",
"        ::::;  .  . :;Xx$+Xx;+;+:;$$&&&&&&&$&&$&&&&&&X;..+   :+;X&;+X      ",
"        :::.::   ;.  ;:xX$X&$+&:xXX$&&&&&&x&&&&&$&&X+: .;x::+&xX+:  x      ",
"         ;:..:.:x.     .;;x;X$$x:xX&&&&&&&&&&&:&&$;:.: .:+&&;;+;:;+        ",
"       +x;:..:+:;:..  ; :x; : :++;X&&&&&&&&$;xx:$$:;+.::;:+X$$  :+         ",
"     ;;+ ;:::. ::;+.   :+: .   .:;+x$&&&$$+  :&&;$&XxX+::+&&+ :.:;++       ",
"         +;;...     ;::;+ X&+.  ;.:+xx&$X;.x$x&&&+&$X&$+:::.  :;;+x        ",
"          ;.:.     .;:+::+x&+:+.  . .::+.+&&&&$&$&$&xXX+       .++         ",
"         +::::     .;;::;.:$&.      .  .+:+xX;$&&&&X$&xx;.  :.::.;+        ",
"        ;;;:::  . ....:;: :;x$.&..:;::$$X+:& X&&X;x$$+x+:: .:. ;;:X        ",
"         + ;:   .     .:.  ::+..;;:;. .x&:$x:$+x: ;XxXx:    .::::          ",
"           ;: ...    . ;.;++++++xxxX$&&&&&X&$x:x&$x:x+:.    :; :;+         ",
"           ;.....    ..:;..:.;;:. :;.+:X$$&&$++x;$+X::    .:.:::  x        ",
"          ;;. ::   ...;..::..  :$$&&&&&&&xx:+;:+&$;:.:.:  ; ::;:           ",
"            .  :....    :+;x:+x+x$&&&&&&&$&$$$xXX+. ;:;:..: ::.:;          ",
"            +;:;..:..:    .;+X:;$X&&xXx&&&&$x$x:   :+;:.:: :   ;:          ",
"              ;:;;:  :.     .:++:;xx$$x;++x;x+  .+;+x+ ;       :           ",
"              ;+      ;:..    .;:..:;:::;..    .;;:;                       ",
"                       .::::.               . ::: +                        ",
"                           ::...        ...::.:                            ",
"                              .:.;.... ::                                  ",
"                                  .: :.                                    ","[/color]"],

		"Wraith": ["[color=#4B0082]",
"                                     +                                     ",
"                                     +                                     ",
"                                    .;:                                    ",
"                                 +  .x;  x                                 ",
"                           x    :++;.X+;;+;                                ",
"                           ;::;;;::::$X+;;++;;xx                           ",
"                    ;     :.:;++x+:;:$$$+$$$$$+:      x                    ",
"                    ;&  +::::;xx+x;.:$&:x&&&&&&x;xx  +$                    ",
"                    :+$+...:;xxx$&$::&&x&&&&&&$Xx;:; $+                    ",
"                    ::x...:::+X&&&Xx;&&&&&&&&&Xx+;::x+;                    ",
"                    :..;.:...+x$&&+++&&&&&&&&&&+:x.X$::                    ",
"                     . .+;;:..+x$$&;+&&&&&&&&&++++&x.:+                    ",
"                   ::.  .:;+::;x+++x+&&&&&&&$&X$&x+::xX:                   ",
"                     . ..;::;:;++;+x;&&&&&&&&xXx::::.:.                    ",
"                     :....:.:..++;:;:X&$&&&&$XX;+::;:.:                    ",
"                    ::  ::.::;.::+++:xXX&&&&XXxxxXx  :X                    ",
"                     :.      :;;;;x+:xxX$&&&x;. . ...:.                    ",
"                    :.   .:      :x+;x&&&$.     +;.: :.                    ",
"                    .....;;+       :+x&+      .$&X;:..:                    ",
"           +     .  :.   ..::+;:. . .x; . .+$&&$+   ..:  +     X           ",
"          .;+    :.:....     ;+++;+  ;  &&&&&x... ;.::::.:.   :+;          ",
"          .:+   . ........ ..   ::+.    &&&; .:. ;;::::.:..   :+;          ",
"         ..:;.:..  ::.: .    .:  ::;    &&.:;;... +;::;:....:.:x:;         ",
"      ;x:...;: ..  .::.::  . .:...;+   xX;X;+;::. ;;++: ..::.:.x::XX:      ",
"    $x:.:..::.  :    . :; ....;.; ;+   xX;+;+;.;; xx::..  ;...:+::x:;X&    ",
"  &&X;:..::.X::.:. ..  :+  :..:.;.::.  Xx;++x+;+. X+  :. :;.::Xx+;;;;x&&&  ",
"  &&x:::.:;:++;.:; ...  :    .;.;:...  ;;;x+X..   ; .:.. +; ;+$x++:;+X&&&  ",
"   &&x;;;+;xxxx$;:x .. ..     .:;:::. .:+xXx.     .;;.. $+:&+&&Xx&$XXX$&&  ",
"   &&Xx+X&&&X&&&x;;+..:..:.      :.:: .x+;  ....::;;:..Xxx$&&&&&&&&&&&&&&  ",
"    &&xX$&&&$&&X$$+x. .:: .        ;: .;.  .:X; :.;;+.:$x&&&&&&&&&&&$&&&   ",
"    &&&&$XXxxx&X++ :  . ;.    .     ; :  .:...: :;X:;. ; +&&&&&&&&&&&&&&   ",
"      &&XX+;.::;x:.+ . ....:...  .       ....:x$++x::.:;.;Xx+::&&&&$&&     ",
"       &X++:+X:;Xx:::......::.:+;:     ..+$&+;+x++::::+;;X$X$&X;xxX&&      ",
"        &&x;;;;+;&.:::;:......::;:..:.++;x&&xx+;;:;++;;..&XXXxx+$&&&       ",
"         &Xx+;+;x::  .x;:$;;:.:+:..::x$xxX+;+X+x&&x;X:  ;+XX$$xx&&&        ",
"         &&x:  :;  :.;:::x..;+:;:x+;;xXX$&&&&&Xxx$+;+.:;  +x..:X&&         ",
"           &x+. ...::;:.;;.::;Xx+;+++&&&&&&&&$&$X&&x+++x..; :;$&&          ",
"            &&x+::::x..;:xx+++xxXXx:;&&&&&&&&&&&&&&Xx;$x+;:;x$&            ","[/color]"],

		"Wyvern": ["[color=#8FBC8F]",
"    /\\     /\\",
"   /  \\___/  \\",
"  <==(o   o)==>",
"     /) ^ (\\",
"    //     \\\\",
"   //   |   \\\\",
"  ~~   / \\   ~~","[/color]"],

		"Minotaur": ["[color=#8B4513]",
"           ;+                                                 :+           ",
"         .+:                                                   .X+         ",
"       .:x:                                                      +X+       ",
"      .:X::                                                     ..x$;      ",
"    ..;X::                    xx;;:;+   x                        ..$$;;    ",
"   ..:x:.;                   +++;;;::;;;:: XX                    :..Xx;:   ",
"  .:.:;;:+                ;+;::...:.::..;;+;;;+    X             :..:X;;:  ",
"  ;. :+++x            $$X++:;+;:..+x;;:+X$xx+;;++X+;             ;:.:;x;;  ",
"  +: .;;X&X        $Xx;.;;:;;;;..;;+;.x&$x$x+x$x+;.:+$X         +++::.;.;  ",
"  x: .::X&&&&&&&&$x;+;++::+;+:::;;x;xX$++XxXX$X+;xx&:$+X&&&&&&&&&&+;....;  ",
"  $+. .;.x$&&&&&&&&&&&X&&$;.;+:::xx++:x+x;x;+::;;&&&&X&&&&&&&&&&&$;;:;..;  ",
"  XXx.:::xx&&&&&&&&&$$&;&;::.;x:++++x:;;+X$x$X+++X$+&x$&&&&&&&&x;;;;...;+  ",
"   +x;;..:;xxx$$&&&&+x+:. :.;x++xXx;;:;&&&&&&&$X:.::;;x+$XxxXXX$+;+:..;;   ",
"     ;+:;;::.:;::::.:..  .;+xxX$$+X&X$&&&&&&&&&Xx;+..:.::::::::.::::;;     ",
"       :+:.::.  .    . ..+:$+;&&&&&x&$&&&&&&&&&&X+:.   .   ..::;;:+        ",
"           ::..:;;:.    .   .;x&&&x+&X&&&&&&&+; .;.;.;.+xx++::;::          ",
"     XXx+;;   ..:::;:  .. .:&X ..:X&;$&X+..:;&X:.&$;+;:&&X&X. :+xxX$$      ",
"       x;;:;:;....   .::&&+:;+.;X&&&&&&&&&$+xX+X&&&+.:..:..:::;+;+xx       ",
"        $+;;+++::;++:::.:xX++xxx$&&&&&&&&&&&&&&&&$++:+::xx++x$X+x+         ",
"            X :+::. :;;:...:.:+;$&&&&&&$&&$&&x&+..xxx+;:.; ::+XX           ",
"             +;;::.:;:..::...;;: :x&&$&&: .x&&;.;$xxXxx: . .+xX$$          ",
"         &&&X++;..:.:;+++..::xx:x;:;;:+.;&+&&&:x$X$$x+..;;;:x+x            ",
"          x+x+;;.:.:...x;;::x;;;&;:.:;;x;&+&&$;X&&$X;;::::+;;+X            ",
"           $x+++:.:;.:;:.+::+ . +&;    ;&x;..$&+xxx:X;:X+:::;xx$&          ",
"             x;:.:::.. ;..:+: :$ ;:;&&&;& Xx :$+x;.: ;+;+.:++XX            ",
"            &x++:;;: .:; ....  ; ..    ...&  .X$X+.:;;x :.:;+X&&           ",
"          &$$$+;X:..:.+.. .:: .$.: ...;+.:+X+;xx;++:++;.:.xXxX&            ",
"            X ++x::.::::...;...x&;Xx;xx:&x&X;:&;x.:x;;;.;:+ +$             ",
"             X$Xx++;;.::..+....:::;;++Xx+;:.x:;;.+;+;.::;+x$X              ",
"              $X X+++;:..:.  .x;;;:....:x$&&X  :.:x:;:+x X &               ",
"                  x;:;;:... ..::.:;;;xx&&x:$;:...:.:;xx $&                 ",
"                   $+;;;:;:;. x:;X:&$&&&&XX+x .;.+:+x;X                    ",
"                     &X x+;;::.:.;:X:;&X+x;:;::.;;+X +                     ",
"                        xx;;:+;..;. :.+x+.:.+;+;;X&&$&                     ",
"                         X$;;Xx;;x:  :;;...;$XX+&                          ",
"                           xX XX+X::.:::.;+X &$$                           ",
"                             $  xX;;.::+X&X  &&                            ",
"                                   x+++ $&                                 ",
"                                     Xx                                    ","[/color]"],

		# Tier 4 - Powerful creatures
		"Giant": ["[color=#8B4513]",
"                         ;;:..  .  . .......:::;+++                        ",
"                    ++;:.......    .   ..   .....:::;;+                    ",
"                +;+:....    ...::..  .  ..:...:. :.::::;++                 ",
"               x;.... .  ........ .  :;;;;.+XXXx;.:. .: :;++               ",
"             +;:....      ....  :...;:+$$+;$&&$$$X++...::.:;++             ",
"            ;;.  ..   ..:.. ....::::$Xx&&&x&&&&&&&Xx::. .;:.:;x            ",
"           ;.  ..    . .. ..:..+..;x&&+&&&&&&&&&&&XX;x;:...:..;+           ",
"          :.    ..   ..  ...:;++:.;&&&&&&&&&&&&&&&&&$&X;:......:;+         ",
"        ++:           . ....:;X+;+x&&&$&&&&&&&&&&&&&$&X+;.: .. ..x;        ",
"       ; :             ... ;;X$;$$$&&&&&&&&&&&&&&&&&&&&X;... . : .:;       ",
"       ++: .           .:;.+X;;&&$&&&&&&&&&&&&&&&&&&&&&$$;:....  .:;+      ",
"       x;.        .   .+;:++X;+&&$&&&&&&&&&&&$$xx;::;;xX&x;.::...x$&&$X    ",
"        .. .      ;. .:++++x$$&&&$&&x$&&&$xx+....:+xxxx+x$X:::  +&;  :$X   ",
"       ;.. .     ... :+$xXX$$$&&&xx&X:+x;.   .:;+++xxXX+xxX+:. .:+.+..:X   ",
"     xx+..      .;+:.:++x$$$&&XX&$::::         . .   .:+&$&x+:.:.X&&$X+xx  ",
"     X;;:.      ;+x+;+x;;$$x$xx;:+X+..     .;xX+;$+:.:X&&&&&$+::  :$&&$$X  ",
"     x;..      :+;;;:+;+.:+:+:;$&&&&&&$:;;.::;xXx+:+X&&&&&&&$x:x  ..+&X$x  ",
"    x:::        :;;...: .:   .+$&&&&&&&&&&&x;++++x+x&&&&&&&X++:X$:$+x&x&;  ",
"   ;+;..      . .     :.     .;x$&&&&&&&$&&&&&+;;+x&&&&&&&$+:;:xxXxx$X$++  ",
"  + ;:.      ..    ...   ....;$&&&&&&&&&&&x&&&&&&&&&&&&$$X+::;:+;;&&x+$.;x ",
" xX  ;.       .       .;:::..;$$&&&&&&&$&&&:+&&&&&&&Xxxxx+::xx:;$&$XX$::.  ",
"    x;: .  .   .     .::+x;:;.;xX$XXXX;  :+&$+x&&&&&$X++;;;XXx+;X$X&X..:++ ",
"    x ;::  : :. ..::: .+x+.    ..::;;::+;;&&&&x;xX$&$x;;+:xXXx+:x&$X: :;+  ",
"       +.:..  . :.:+:.;++...        .x&&&&&&&&&&&xXX$x+X$;X$Xxx: ::   :++  ",
"         ;..  .:  ::..:;: ........;x;+&&&&&&&&&&&&$X&&xX&+X$XXx;      .:x  ",
"          ::...;.   :::. ..:.:::;+&&;X&$Xxx$&&&$&$$x$&$xX$xX$x+;.      ;+  ",
"            :.:.;:: .;; ...::::..:::::.x$:;.:;+X$$$&$$$xX$$X$xx;:;:.:  :x  ",
"             :...;;..::..:. :.   :+:   ;: .     .;:X&$&$xxx$X+;:;x;+x..:   ",
"                ..;:..:..;.    ; :.     .:;+x. +$&$$x&&$+xxx++: +X++x.;+   ",
"                 ::;.::..:.        .:xx$xX&;$+$$X$&&XxX+;XX+;:..xX+;;.;    ",
"                 ::;..;::;:. .;;xx$$$&&&&&&&&&$X$$$&XxxX;++::. ;+x;:;:;    ",
"                  :::.:;.::.;:.;+xxX&&&&$$$$Xx$&$$XX++xx;;;:  +x+x:::;:    ",
"                   .:.;:.:.:.::: :.....:;+;xx+xXxxxxx+++:.   :++;x+::      ",
"                    :..:: ..:.. :.::X$$&&&&$&&&&&&&x++;..   :;+;+x;:       ",
"                     ;:.:.   ...:;++X$$$$&&&&&&&&$X+;.    .;+++;++         ",
"                        ... ...;+::+X$$XX&&&&&$$X+;:     .;++++x+          ",
"                          ....;:;.;+x$x++x;+Xx+x+:.    .::+++x+            ",
"                            . .:;..;;+;+:::::::.      .:;+++               ",
"                              .. .....:.    .    ..  :;;;++                ",
"                                :.              ::.  ;+++                  ",
"                                            . .::::.;;                     ","[/color]"],

		"Dragon Wyrmling": ["[color=#FF4500]",
"     /\\_/\\",
"    / o o \\",
"   <   ^   >",
"    \\ ~~~ /",
"   //)   (\\\\",
"  // |   | \\\\",
" ~~  |   |  ~~","[/color]"],

		"Demon": ["[color=#DC143C]",
"   \\\\     //",
"    \\\\   //",
"    ( o^o )",
"     \\~~~/",
"   __|===|__",
"  <  |   |  >",
"    /|   |\\","[/color]"],

		"Vampire": ["[color=#8B0000]",
"                              .:;;;+xxxxxx++;                              ",
"                           .:;++xxX$&&&&&&$$$Xx+                           ",
"                        .::;;+xX$&&&&&&&&&&&&&&$x+;                        ",
"                      ..:;++xX$$&&&&&&&&&&&&&&&&&$Xx;                      ",
"                     ..:;++xX$$&&&&&&&&&&&&&&&&&&&&$x+;                    ",
"                    ..:::;xXX$$&&&&&&&&&&&&&&&&&&&&&&$x;                   ",
"                    .:;++xX&$&&&&&&&&&&&&&&&&&&&&&&&&&X+;                  ",
"                   .::+xxxx$&&&&&&&&&&&&&&&&&&&&&&&&&&&X;                  ",
"       :.         ..:;;xx&$$&&&&&&&&&&&&&&&&&&&&&&&&&&&$x:         +       ",
"        ;;       ...::;x$X$&&&&&&&&&&&&&&&&&&&&&&&&&&&&$x:       :++       ",
"         :+.    . ....;$X$X&&&&&&&&&&&&&&&&&&&&&&&&&&&$$x;.+    +x:.       ",
"          .X;:  . . . ;X++$&X&&&&&&&&&&&&&&&&&&&&&&&&&XXx:.+ :+x$.;        ",
"         .  x++     .:::$xX&&&&&&&&&&&&&&&&&&&&&&&&&&&$X+::.xX&x.+;        ",
"             ;Xx;   ..:;XX&&&&&&&&&&&&&&&&&&&&&&&&&&&&$$x::&&&:.+X         ",
"          ::   +;;   ..X&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&$X;x&&&;x+xx         ",
"          ::..  ++. .: :x&&&&&&&&&&&&&&&&&&&&&&&&&&&$$&xxX&&:X$+Xx         ",
"          .:.:.  :. .;:  .x&&$&&&&&&&&&&&&&&&&&&$;:+X$&$X&X .xxX:          ",
"           :.::   .::..     :XX&&&&&&&&&&&&&&&;    .:+X&x: x;Xxx           ",
"            ..;. . ;..    x++. :x$$;&&&x$&X+ .$$&:.:+$&&Xx::&xX;           ",
"             :..; .X;x+.  .:.     .x&&&$x.  .;++x;+x&&&&+++&Xx             ",
"              ::. :+;:x&&X++++$xXx;&&&&&&&&&&&&&&&&&&&&x:&&+X+             ",
"               ;::.::::;x$&$&&&$::x&&&&&&&X&&&&&&&&&&x;:&&$Xxx             ",
"                 : ;;    ;xX&$;;+$$X&&&&&&&$+&&&&&X;:;x+x&X                ",
"                  :;;   . :x+;+x.  ;&&&&X.+&&$&&&X;:x$x:::                 ",
"                   ;+::   :; +xx+;  .;+;X&&&&&+&&$;x&$x;;                  ",
"                   ;.+:;..;:::::.++;: +&&&$x$&&X&x$$&X++:                  ",
"                  ::.::;; :;:  ++.   ...;$&&:.$&&x&$$++.;;                 ",
"                   :. : :..+   ;&;+$$$&&&&&&  X$X&&++. .:                  ",
"                    .  . . ;.  .&         &.  +&X$&+:.:..                  ",
"                   .:   .:.:;.        .... . ;;X$&x..++:                   ",
"                    ..   :..+:. .  ::.:x+.;:+&+X&x:.$xx:                   ",
"                  .  ...  .:.;:..x  ::;; x&;X&x$+ .x&$;.;.                 ",
"                 .   :     ..;;. $&&.::x&&X$&&$+  +&&$;;++:.               ",
"              . ..   ...:   ;:;.;;.:.;:;+x&$&&x .xX&$x;+X;;:.              ",
"                . ..   :;:.  ;;:. :x++xX$+;x&$.:;x&&X+x+x++:               ",
"                   ...  .;    :+;::;+xx&$&&&X::+X&&xx+X&XX+                ",
"                   .::   ::.   :++X&&&&&&&&$:.+;&&Xxx+$$$;                 ",
"                    ...  .:;.   ..;;x+x&XX+  ;+&&&+;$$+.+                  ",
"                      ....;;:;.            .:;$&$+x;x$x                    ",
"                       . .:;::: .      .;+X+;x$$:++x.+                     ",
"                        .  .::+:  .   .:+Xx+xX$X++::                       ",
"                              :;+    :.:;+x;X&x:.:                         ",
"                              :;x+;..  ..x;x+.:.;                          ",
"                                 ... ...;+;.. .                            ",
"                                    .  .                                   ","[/color]"],

		# Tier 5 - Epic creatures
		"Ancient Dragon": ["[color=#FF6600]",
"   <\\_______/>",
"   /  O   O  \\",
"  <     ^     >",
"   \\  ~~~~  /",
"  //)^^^^^^(\\\\",
" // |      | \\\\",
"<~~ |      | ~~>","[/color]"],

		"Demon Lord": ["[color=#FF0000]",
"                   ::.                               .::                   ",
"                .:;                                    .+:.                ",
"              .:x:.                                    ...+..              ",
"            ..;+..                                       :.+;..            ",
"          .:.+;..:                                       ;::+;::           ",
"          :::x+.:                                         :;;X...          ",
"         ;:.:$+::                                         ;++X..::         ",
"        ..:.:$xx;.                                       .;:x$:.::.        ",
"         .:::x$+X:                   +                   ;+X&X.;.          ",
"        .:;...$$xx;;                :X.                ;;xx$$. ..:..       ",
"         ..:..:&$$&+:.            +;:&.;+            :;x$$$&....::.        ",
"           ..::.X$$XX::;  .;+ ;+;;x;;&..:;::: +:   ;+XX$$&x..:..           ",
"         .::;;.;::&x&&xx::: .;:;+$++;$ . ::..;. :;+xx&&&&:.. .:::.         ",
"              ;::.:+&$&&X;;+X++xxX; :$  ::+::+X;x$&&&&&;. .::   .          ",
"           ..   +:....&&&&xx.&XX&$:;X&.. +xxX&.;x&&&&.  ..+  ...           ",
"             .. . x:.;  :$x&; &X&&&X+$.;;&&X& +&X&;. .  ;   ..             ",
"              ... . .;.  : +&+xX&&&.:;  $&&x;;X+ :. .:.   ...              ",
"            .:::. .    ;; :::++&&&&&.: X&&$$;;..: ;;      .:::             ",
"              : .;+:    .X:;X&&&&&&&&;XX&&&&&XX:.X. .  :++:.:              ",
"               ;:..;x;.  .:X$&&&&&&&&&&&&&&&&&X;.   .:;:::;:               ",
"                ;:+;.;+. :...;x&&&&&&&&&&&&&;..... .:. ;;:;                ",
"                 :;:. .:.;:      ::.;X;:;.     .;: .   :+:                 ",
"                  ::x: :;xX$;;.. ..;&&$.. .::;X&+; : ;+::                  ",
"                    ::Xx. ;X&&&X&&$$&&$+x&&X&&$x. .+&+:.                   ",
"                     .X$ :  :;X&&&X$&&&xX&&&$+.  :.&$.                     ",
"                  ...    :::.++&$&x$&&&x;&$$...:.:    .:.                  ",
"                       . +++;;x$&&&..;..X&&x:.:;;;    .                    ",
"                  .:;..: ++++:x$X&&&X.x$&XX;+.;;;; : .:::                  ",
"                .:.. .::  :;::X::;xXx+x+;:..::::.  :. ...:.                ",
"                    :: .:   :;:++X+....:;;;;.:.  : :;..                    ",
"                   ;:...; :. :;:x:x&&+&++.:::  .;;:. :::                   ",
"                      :.;+.;. ..X$&&x+;&&+.    :;...                       ",
"                        :+.;x:.  :&;$x;:&:;   :+..                         ",
"                          ;:x;.  .+ +x. ;   : ;;.                          ",
"                            :+::;.  .+   . ;:..                            ",
"                              :::::..   .:. :                              ",
"                                  ;+;...:.                                 ",
"                                    ;:.                                    ",
"                                     .                                     ","[/color]"],

		"Lich": ["[color=#9400D3]",
"                                     $                                     ",
"                                     X                                     ",
"                         +          +$:          x                         ",
"                         ;$         X&;;        &x                         ",
"                    +x   :&    ;;;;X&&+;::..    &+   ++                    ",
"                    ;X  ..$ :.;++xx&&&xx++++;.. $x.  X;                    ",
"                    :x+  :$;.:;+Xx&&X&;XXxxx;::;&+.  &.                    ",
"                    .:X .:X:..+&;+X$&&.X+;.+X:..$+: :X.                    ",
"                    ..: ..::xxx&&&$+$&;;X$&&+xx::;  .::                    ",
"                     .....:;+$&&&&&.:X .+x&Xx+;::; : .                     ",
"                    ....:.;+xxX&&&X&X&+X;&&&&&+x+::;..:                    ",
"                     :.. :.:; ..:.+&X&X$+...::+;.x..:.:                    ",
"                    ..  :;xx ;x$$&&;&xX:X&&X$x.:+::  .:                    ",
"                     . .;$+:+X&&&&&&Xx+&&&&&&X&x:x+:.                      ",
"                     . :+&.+$&&&&&&&&&&&&&&&&&&x;+x+: .                    ",
"                    ...++x.   ..$&&&X&x$&&$..   . :X:.                     ",
"                    ..;X: ;  .&&+  .&&&;  .&&:  ; .$+;.:                   ",
"                   ..:X+ ;X$:;:::.X&&X&XX;::::;x&x.:x+::                   ",
"                  :.;;X;:$&&&&&&&&&&. .&$&&&&&&&&$+ ;x;::                  ",
"                 ..:+$+. +$&X$:x&&&: ; .x$&;:+Xx++   .+;::                 ",
"                 .:+xXX.      :+X&&&;&;&&&;x.       :  +:;:                ",
"                .:.+X:;.  ..+  +$&&&&&&&&&+;  ::.  .:.. +x;:               ",
"              :;;.:x$;     +:: ;X&$&&&&X&&&: :;;.  .x+;. xx+;              ",
"             :;+:.:xx+ .: .xxX.:.X;&&&&&.X . xXx:  +$x++::X +:             ",
"           ::::;::.x:.;.: ;XxX$;x+:     :.x:+&+xx  x&&x$;;.: :             ",
"             ..:;: ;. +X:.  .X$+&X&X&&&&$X:+X$:  .:+&&$x  :. .;.           ",
"                .;:+ ..xX:.. .x$+&&&&&&&Xx;$x:  .+::&:$..:::::             ",
"                :.:::++::XX+.  :$&&&&&&&&&&:  :+$+;;$.:: ;:                ",
"                  ::..;:;;X&X    x&&&&&&&x.  :$+xX+ x  . ;                 ",
"                   ::  .x$$&&&X . ;&.::&; .+x+x$+.: :.:.                   ",
"                    .:..::X;&X&XX;      ::.X$XXx+.  .::;;                  ",
"                        :..+$x.;xX&&x    :xx;::   . ::                     ",
"                          :. :&xxx$x;+Xx;.:.  ;; :. ;:                     ",
"                          .::  .x$&X++;:..:.::+:.                          ",
"                             ::.::;+xx:.;;.::.                             ",
"                               . :;:;;::..                                 ",
"                                  :; x;::                                  ",
"                                     ;;                                    ","[/color]"],

		"Titan": ["[color=#FFD700]",
"                             $$$$$&&&&&&&&&&&&                             ",
"                        XXXX$$$$&&&&&&&&&&&&&&&&&&&                        ",
"                     +xxXxXX$X$$$&&&&&&&&&&&&&&&&&&&&&                     ",
"                   x++xxXXXX$X$&&&&&&&&&&&&&&&&&&&&&&&&&                   ",
"                 ++++++xxXXXXX$&&&&&&&&&&&&&&&&&&&&&&&&&&&                 ",
"                ++++++++xxXX$$$$&&&&&&&&&&&&&&&&&&&&&$&&&&$                ",
"               ;++++++xxx+XXX$$&&&&&&&&&&&&&&&&&&&&&&&&&&&$X               ",
"             +;;++;x++xxXx;X$$$&&&&&&&&&&&&&&&&&&&&&&&&&&&$$X+             ",
"            +;;;+;+xxxXxXXxXxx&&&&&&&&&&&&&&&&&&&&&&&$&$&$$$xx             ",
"             ;;++;;xxxx+xxXX$&$&&&&&&&&&&&&&&&&&&&&$&&&$&&$Xxxx            ",
"            ;;;;++++xxx++xxXx$&$&&&&&&&&&&&&&&&&&&$$&&$X&$XXXxx            ",
"            ;;:;+:;;+xx++XXXX$$XX$&&&&&&&&&&&&&&$$&&&&x$$XX$Xxxx           ",
"           ;;::;;;;:+xxxxXxXx$X&&&&&&&&$&&&&&&&$$&$&$+x$XxXXxx++x          ",
"          ;;::;::::;:xxXXxX+x$&$&x$&&&$$&&$&&$&&&XX&&;X$+XX$+x++x          ",
"          +::;;+;.;;;x+XX&$$$&&&$&&$&&&&&&&&&&&&&&&&$&&++xxx+++++x         ",
"         +;;:::;;;:;+XXXX$$X$&&&&&&$&&&$$&&&&&&&&&&&&&&+;+xx;+;+x          ",
"        +xxx;::;;::+$X+$&X$$X$&&$&&$&X&&&&&&&&&&&&&&&&&&x+xX++;$&&X        ",
"        ;::xx;:::::++Xx;xX+x&$$$&&&$&&$&&&&&&&$$$X$XXx$&X+xX+xX$+:;        ",
"         :::;;:::.;;;:.....:+xx$$xX$x&&x&$&&X$X;:....:;x$+xXx+X;x:X        ",
"        ;.:+::;:::;;:.  +$&&X:...:;:X&Xx::::.:X&&&X. .:X$&xxxx+$XXX        ",
"        ;:::..;+xx;+....:x&&$+....;+&&&$x:. .:X&$x;:::XX&&$&x+.+Xxx        ",
"       +;:::..;+xxXX+:;::::::::.;;+x$$x&&X$;.:::;;+;xX&&&&&X+x:;X+         ",
"       ++;:::;;:+xXXx$Xxx;;;+x+++x++.: X&&&&$$+xX$Xx&&&&&$X:;;x+;+         ",
"        +;::::;::+xX$$$X$X$&XXXxxx+ .;. +&$$&&&&&&&&&$&&XX+:+Xx++xx        ",
"         +:::;;;..++xxXxxx++++;X+;...+...x&$&XX$&$X&$Xxx+;::++++++X        ",
"         +;:.;+;:.:::;;::;::x;+x;x...Xx.:+x$&xxX$:;$+::::;:+++;;x X        ",
"        ++;:.:..:.;.: :+;.::xxxxX++x++$xXX$&$$$:::x;.:.++;;x;+;;XXX        ",
"        +x+;;...:.;::...:+:;+++XxXxxXX$&&$&&&$XX:x+.;;+XX:..;;;;XX         ",
"         +++:.:.:.+;;+..; ;;;$+x;X+x$+x$xx$;$;&x++.:x;++X::;;;+xX          ",
"         x+;:::.:.++;;;:;.:;::++x;x;x+$xxx$;X:+;+;:;$xxXX.:;;;;xX          ",
"          +;;::::::+++;+;.;:..x+X;xX$x$XX;$+$;.;;:+XXxX$$:;;+;++X          ",
"          +;;::;.:.++;++;:;: .:.;     ...  :;..;+X+$X$X$X:;;+;+xxX         ",
"         x++;;:;...++xx;+x:;..:::;..;.:.;+;;:+:+x$+xx$XX;:;;+ ;x X         ",
"           + ;+:...:;+x+;.+++;:+;X+$+x+xXXXx;;;x$$X$$$X;::;;+ ++  X        ",
"           x ;;:::.:::+++;++x;+;x+++x+XX+X++X+xxX&X$X;:;:::;;xx   X        ",
"            +++::;.:;:::;xx;x+;;xX;X$xx&xX+$$&x$&X$;:.+x:::;+xx            ",
"            +++;;;::;;;:.xx+X:;+XX$$&&&&&$Xx$&&&$;::x;XX:;++xxx            ",
"            x ;;;;;;++x;::;;++;+XX&$&&&&&&$X&XXX:.:+xxxx;;+x+xx            ",
"             x++;+x ;;x::::..+;XxX$&XXX&$&&X$x.::;+$X++x;;+Xx              ",
"              x++    :;+;;;:...+x+XXxx+xX&$++:.:++xX+x x ;+xx              ",
"              + ++     x;:;;.:..:.......::..::;Xx;x+x  x  X                ",
"               ++x      ;:;;;.;...:;...:;;.:xxx+;++      xx                ",
"                x       xx ;;;;:;..;;:::;;:+x;+++x      xxx                ",
"                            ;;; :;;;;;;x;+xx;++                            ",
"                              ;; :;;+++  +xx++                             ",
"                                  ;;++   +                                 ",
"                                    xX                                     ","[/color]"],

		# Tier 6 - Legendary
		# Elemental has variants - randomly selected in get_monster_ascii_art()
		"Elemental_Fire": ["[color=#FF4500]",
"                                  @@                                       ",
"                                  @                                        ",
"                                @@@                                        ",
"                                @@@@                                       ",
"                               @@@.@@@                                     ",
"                                @@..+@@ @@@                                ",
"                             @   @@...@@@@@@                               ",
"                             @@  @@@..-:%=-=@ @                            ",
"                            @@@@ @@@...+::.:@@@@                           ",
"                          @ @@*@@@@=..:+#:..%@@@                           ",
"                   @      @@@=+@@*@-..:@@-:.@@@*@@                         ",
"                 @@       @@@%=*@++=::#@@#=.*@#*@@@                        ",
"                @@@@@   @@+@@@%..+@=*+%@@@==-%+*@@@@@    @                 ",
"                @#@@@   @#:#@@#:..:+@@@@@@@*:-+@@@@@@@   @@                ",
"                @@+@@@ @@=..=+%...:+@@@@@@+#-:@@@@@#*@@ @@@@@@             ",
"              @@@:.*@@@@@@=....#=.:*@@@@@@@@*-@@@@:-=@@ @@@:@@             ",
"           @@  @@+.=@@@@@##....*=+-*%@@@@@@@@*@@@=..@@@ @@-.@@@ @          ",
"             @ @@@:-..=@@=...=--+@**@@@@@@@@@@@@+..*@*@@@+..@@@@           ",
"            @@ @@@:*...:-@+..:@@@%@%@@@@@@@@@@@--.+@@:%@@+=..#@@           ",
"           @@@ @@@=+:.:+*..-:.+@++@@@@@@@@@@@@@:==*@=.:+%*.:.*@ @@         ",
"          @@@@@@@@@%-..:.#+%-+*%@%*@@@@@@@@@@@#-@-@=:.:+%:.:*@@ @@         ",
"          @@@##@@@=:#+...=@@+%@@@%@@@@@@@@@@-#@@#*@=.:+-@.=@@@@@@@         ",
"          @@**-#@@@#%:+..*@@@@@@@@@@@@@@@@%*%@@@@=+:.-:.::#@@@@+@@         ",
"          @@@-..*%::-......#@+=@@@@@%@@@%@@@@@@@*==-...:#@@@@@::@@         ",
"          @@@*...:#+::....-+-:=@@@@#*#@@%##@@@@%+-..-.:#@@=--:.-@@         ",
"          @@@#-+...-@@--...+%=-@@@-=-%%@=-.*%@*+......@#=+=.:.-%@@         ",
"          @@@@@%-:..=:=-....-*:.*%+:--+*=:-.::@.......-@+:.-@:*@@          ",
"          @@@@@@@:.......::..................+...:...::...-*@@@@@          ",
"          @@@*@@@@=.....:#@@@@*.............-=*@@@@#....--@@@@@@@          ",
"           @@@@@@@@#.....+@@@@@@*-.........-@@@@@@@:...*@@=+@%%@           ",
"          @ @@@@@-:.:...:-%@@@@@@@........:@@@@@@@=::..::.:*@@@@           ",
"             @@@@%=-...:..--@@@@@#:.......=#@@@*-....-:@-+%@@@@            ",
"              @@@%#+-@@:=+..........................@+%@@@@@ @@            ",
"              @@@@@@@@%:*@@#.....................--@@@@@#@@@@@             ",
"               @@@@@@%.:**=...................:.:**@#+=-#=@@@              ",
"               @@@@@@#*+:.#@*.:-............=..=+:+:.:-%@@@@               ",
"                @@@@@@#@#=--.-:*..:.-:......:@*+.+=:.#@@@@@                ",
"                @@@@@@@@@--.-.-+:..:%:-:.=@%@#.+-..--@@@@@@                ",
"                 @@@@@@@#+--=....=-:+*-=%#@@@-=*::@%@@@@@@@                ",
"                   @@@@@@@++*-.:..-%@@=#@@@@@#+--@@@@@@@@@                 ",
"                    @@@@@#**--.:-.=#*@@@@@@*:.=@*-+@@@@@@                  ",
"                   @@@@@@%+++@@-%=.=@@@@@@@%==#@#+@@@@@@                   ",
"                    @@@@@@@*-+=#%@=-+@@@@@@@=@@@@@@@@@@                    ",
"                     @@@@@@@@#===*@@@@@@@@@@@@@@@@@@@@@                    ",
"                       @@@@@@@##+:-@%@@@@@@@@@@@@@@@@                      ",
"                        @@@@@@@%@@#+#@@@@@@@@@@@@@@                        ",
"                           @@@@@@@@@@@@@@@@@@@@@@@@                        ",
"                              @@@@@@@@@@@@@@@@@@@                          ",
"                               @@@@@@@@@@@@@@@                             ",
"                                @@@@@@@@@@@                                ",
"                                    @@@@@                                  ",
"                                     @@                                    ",
"                                      @                                    ","[/color]"],

		"Elemental_Water": ["[color=#00BFFF]",
"                                                         %#                ",
"                              %%                        +##                ",
"                         .*%@**                    #@@@%#*                 ",
"                       +*#=-+                 *  -#@@@@:%+                 ",
"                    .*@#.+- #               -  *%@@*  .  *                 ",
"                    =*@.-+-           %+   :**%@@@@..                      ",
"               += =:+#*  @-:-+---+=++#%+==#**@@@@@  =       *+             ",
"               =.-.**+      :: --*:::@%**-@@@%     :=@-#=#==::             ",
"            -  -+.=@      .  -*.::--*@@@@@@- % .  : --+=@@@#:              ",
"            =  +:**@ +   .  -:==+#*@%#@@#....  #@@   :+@@=                 ",
"           --=== +@@# +   =.:=*@@@@@@@ @@  .*#@@   +%@@% :.%#              ",
"            :. .. %%#+  -%=-#%@#@@@@@-*--:#@@@@@@@@@@:   :. =*@*           ",
"             +*   =+@@..:+@@@@@@@@@@@@@@@%@@@@@*@@@ + . *@%@               ",
"             =-=    #+@=.-=%@@@@@@@@@@@@@@@@% . .@+..-==.  . +             ",
"             - .::   @+++#*%%@@@@@@@%@@@@= .  .  *@@@*@  ::                ",
"             #- -+.=.-%*:=@#@@@@@@@%@@@#==:--:*#@@-    +*%@#               ",
"                : + :: *##%@@@@@@@@@@@@%*#@#*#:.  -:.@#-:  =:              ",
"                .  +*=+#:*@%%@@@@@@@@@@@@@@.:=-  .+#@:                     ",
"                .- +:-:*@+@@@@@@@@@@@@@@@**=.  -%.#-   .+= ==              ",
"                 :       .++@@@@@@@@@@+     :==.@=    :  %%                ",
"                  .=+:      :%@@@@#:       .*@@%      :@-                  ",
"                  .*%*:      @@@@@=       #@@-   - . .:==#+                ",
"                  =::+*===: *%@@@@@@#%@@@@#:   ++  .%..+@:                 ",
"                   :: --:=#@@@@@@@@@@@@@#    =+*@-  -@=:                   ",
"                        .-+*@@@@@@@@@@*@: - *@-      -@==                  ",
"                    = =: +:*+%@@@@@@@*#*:*:@@*@  -   :--@@-                ",
"                   --  +=-=:*%%@@@@@@@%-++@*=@  .     :.-+:                ",
"                   -.:  .@.-:-%@@@@@@%**@@%=   :#..%. .*--                 ",
"                     -   -= **+%@@@%@=*@# *  #-#%+. .%-:+@+=               ",
"                   = :   +=:.#*#%@@%%@ ::    +#*@+-#%@-.-*: :              ",
"                    -:    =-.@:@%#@@++    :: @@*@: +% =+*%:+*-             ",
"                  :=.:  .   =% =+ +     -.@@@@%@.=-:.*%=%@@@@@             ",
"               .+.  :. .=    =: % =    *.*#@@@#. *#@=*@%  %                ",
"              :-.  =:.+ #.         :=+  %@@@#%@@*@##*#+                    ",
"                 *+-- +.@*= .     .+@.=@%=@@@#*@%@%-                       ",
"                %@ @**:.*@=:::     ==@@@@@@#@%**=                          ",
"                   ==+-:#@--*    .#@#*@@@##@#*%+                           ",
"                     *+##@%-.@. @*#*@%+@@-=+ #                             ",
"                     +#-+@@*=+.@@#=%%#@   -                                ",
"                       **+@*@%%@%=:=@=                                     ",
"                         =*@%@#@**-                                        ",
"                           @%@%%                                           ",
"                            %%                                             ",
"                             @                                             ","[/color]"],

		"Elemental_Earth": ["[color=#8B4513]",
"                                      ;:                                   ",
"                    &&&&&           .&&+.                                  ",
"                    &&&           $$&&&::.          &&                     ",
"                 & &&&&&& &     &&&&&&++:::     &&&&&     x;               ",
"                    x&$&&&&&  X&&&&&&&&+;+ :.   &&&&&  X&&x.               ",
"             +x    ;+X&&x&XX+X$&&&&&&&&&;. .;x&X:.&&$$&&&+:.               ",
"             :&$&$ :;;$x+;xx;xX&&&&&&&&&;X.+X&;;.:X$&&&&;::.               ",
"             .;&&&&&x.+$X:X&&&x&$&&&&&&&&+;.x;+;&&:X&xx::x..               ",
"             ;+;&&&$&X++;+X&&&&X&&&&&&&&XX+.x&&&&;.;$&+:;::  X$:           ",
"              ++++&&&&&&:;x$X&&&$&&&&&&&$+x&&&&&++.+$;:...;$&x.            ",
"              .:x$x&&&&&X&&&X+&&&&&&&&&&X&&&&&&Xx;: +..+&xX&;:.            ",
"          :X$x: ;$$xxxx$$&&&&&xX$&&&&&&&&&&&&X;x+;X&$+;X+;x:::.            ",
"           :;&$+.;; .:$&&&&&&&XX&&&&&&&&X&&&&x$&&&&&$X+&+::+;.             ",
"            :;+Xx..+$x&&&&&&&&&&&&&&&&&&&&&&&&&&&&Xx+:;.; . .              ",
"             ..x&+;$$&&$&&&&&&&&&&&&&&&&&&&&&&&&&$XX:: :;::.x+:            ",
"           :XX; :+..::++$xx&&&&&&&&&&&&&&&&X&&&&++..;..:...X&:.            ",
"             :x+  +.:    ::;:+X&&$&&&&&&&$&xx::;;:    .;.:x;:.             ",
"             .;::::$X;:;:&&  x..;x$&&&$x+; .:   $X..+;+$$..                ",
"               :;:+:X&&$Xx$&$x+;+&&&&&&$x;;.:xXXx+XXX;;;: ;:               ",
"               .+x;+;$&$X&&&&&&&X&&&&&&$&&&&++&&&X$&:   :: +:              ",
"                .:+:..++;X$&&&&&&&&&&&&&&&&$+&&&X;;:. .;...                ",
"                     .x+x;xxx$$&&&&&&&&&&Xx:+&X;:X;..  .::                 ",
"                  .:.: x+x:X&&&$&&&&&&&$xX;$x::.;;:.:. ;.                  ",
"                 xx++:+. Xx++$&&&$&&&&&$Xxxx;+&+.. .                       ",
"                 :+&X.+xx+;+:X&&&&&&&&&X$++;x&+;: ..;;xx                   ",
"                  .:x$x:;.&&XX+&&&&$&&&&XX&++xX:  .xX+;X;                  ",
"                  . .;&X:;++&$++$&$&$&&x&&+;:;: :x&:xX. .                  ",
"                 +X;   :$x&X:x&&$x+xx&&$X+:+: :+x&X++  :;:                 ",
"                ;XX+::  .x;$&&$&&&X&&&&xxXX$++;X;+    :x++                 ",
"                X$;::;+.   ;x&&x&X&&&&&X+x$x+X;:.   ..::x;.                ",
"                ;:;xx+XX; . .++&$$&&&&+X+&$.x    ;:+x++::.                 ",
"                   x;x&&x ;;:. .&$X&X;xX++;    :x.:+$::                    ",
"                     ;x+$:;$&+; .;.x$;X;:.  .;xx+ X;..                     ",
"                        x +x$X.+.  .;. :  .:.:$;;+;                        ",
"                           XXx;;$+;    ..:+xx::.                           ",
"                            ;:;+&&xx.  :+.:x++                             ",
"                               x$$+:::x..:;+                               ",
"                                 :x;:;;:                                   ",
"                                     .                                     ","[/color]"],

		"Elemental": "VARIANT:Elemental_Fire,Elemental_Water,Elemental_Earth",

		"Iron Golem": ["[color=#708090]",
"    [=====]",
"    [O   O]",
"    [  =  ]",
"   _[=====]_",
"  | |     | |",
"  | |     | |",
"  |_|     |_|","[/color]"],

		"Sphinx": ["[color=#DAA520]",
"       /\\",
"      /  \\",
"     ( oo )___",
"     /      __\\",
"    /   /\\/\\   \\",
"   /___/    \\___\\",
"      ||    ||","[/color]"],

		"Hydra": ["[color=#006400]",
"   \\|/  \\|/",
"   (o)  (o)",
"    \\\\  //",
"     \\\\//",
"      ||",
"     /||\\",
"    / || \\","[/color]"],

		"Phoenix": ["[color=#FF8C00]",
"    ,/|\\,",
"   / /|\\ \\",
"  ( ( o o ) )",
"   \\ \\|// /",
"    \\ ~~ /",
"     \\||/",
"    ~~||~~","[/color]"],

		# Tier 7 - Mythical
		"Void Walker": ["[color=#483D8B]",
"    .:::::.   ",
"   ::     ::  ",
"  :: o   o :: ",
"   ::  ~  ::  ",
"    :: | ::   ",
"     ::|::    ",
"     ~~~~~    ","[/color]"],

		"World Serpent": ["[color=#2E8B57]",
"     _______",
"    /  o o  \\~~~~",
"   (    =    )",
"    \\       /",
"     )     (",
"    /       \\",
"   ~~~~~~~~~~~","[/color]"],

		"Elder Lich": ["[color=#800080]",
"     .=====.",
"    / X ^ X \\",
"    \\  ~~~  /",
"   __|#####|__",
"  /  |     |  \\",
"  \\~~|     |~~/",
"     ~~~~~~~","[/color]"],

		"Primordial Dragon": ["[color=#FF0000]",
"  <\\________/>",
"  /   O  O   \\",
" <      ^     >",
"  \\  ~~~~~~  /",
" //)^^^^^^^^(\\\\",
"// |        | \\\\",
"<~~|        |~~>","[/color]"],

		# Tier 8 - Cosmic
		"Cosmic Horror": ["[color=#4B0082]",
"   @\\ | | /@",
"    \\\\|^|//",
"    (o ? o)",
"   /|\\~~~/|\\",
"    \\|   |/",
"     |~~~|",
"    ~~~~~~","[/color]"],

		"Time Weaver": ["[color=#00FFFF]",
"    *--@--*",
"   /   @   \\",
"  (  @   @  )",
"   \\   @   /",
"    *--@--*",
"      |||",
"     ~~~~~","[/color]"],

		"Death Incarnate": ["[color=#AAAAAA]",
"     .===.",
"    / X X \\",
"    \\ ___ /",
"   __|---|__",
"  /  |   |  \\",
"  \\__|   |__/",
"     ~~~~~","[/color]"],

		# Tier 9 - Godlike
		"Avatar of Chaos": ["[color=#FF00FF]",
"   * \\|/ *",
"  * =(!)= *",
"   * /|\\ *",
"    *|||*",
"   */|||\\*",
"    ~~~~~",
"   *******","[/color]"],

		"The Nameless One": ["[color=#696969]",
"    ???????",
"   ?       ?",
"  ?  ?   ?  ?",
"   ?   ?   ?",
"    ???????",
"      ???",
"     ?????","[/color]"],

		"God Slayer": ["[color=#FFD700]",
"   \\\\\\|///",
"    \\\\|//",
"    (O=O)",
"   <|###|>",
"    |   |",
"   /|   |\\",
"    ~~~~~","[/color]"],

		"Entropy": ["[color=#555555]",
"    .......",
"   .       .",
"  .         .",
"   .       .",
"    .......",
"      ...",
"     .....","[/color]"]
	}

	# Return matching art - extract color and center properly
	if art_map.has(monster_name):
		var entry = art_map[monster_name]

		# Handle variant monsters (randomly select from available variants)
		if entry is String and entry.begins_with("VARIANT:"):
			var variants = entry.substr(8).split(",")
			var selected_variant = variants[randi() % variants.size()]
			if art_map.has(selected_variant):
				entry = art_map[selected_variant]
			else:
				entry = ["[color=#555555]", "????", "[/color]"]

		var lines = entry
		var color_tag = "[color=#555555]"
		var art_lines = []

		# Extract color tag and art content
		for line in lines:
			if line.begins_with("[color="):
				color_tag = line
			elif line == "[/color]":
				continue
			else:
				art_lines.append(line)

		# Find max width for centering
		var max_width = 0
		for line in art_lines:
			max_width = max(max_width, line.length())

		# Wide art (>50 chars) is pre-formatted - return as-is with newlines
		if max_width > 50:
			var result = color_tag + "\n"
			for line in art_lines:
				result += line + "\n"
			result += "[/color]"
			return result

		# Small art - center with padding
		var result = color_tag
		var target_width = 20  # Fixed art width for consistency
		for line in art_lines:
			# Center the line within target width, then add padding
			var stripped = line.strip_edges(true, true)
			var padding_needed = max(0, (target_width - stripped.length()) / 2)
			var centered_line = " ".repeat(padding_needed) + stripped
			result += "                         " + centered_line + "\n"  # 25 space base padding
		result += "[/color]"
		return result
	else:
		# Generic monster fallback
		var padding = "                         "
		return "[color=#555555]" + padding + "    ?????\n" + padding + "   ( o.o )\n" + padding + "    \\ = /\n" + padding + "   /|   |\\\n" + padding + "     ~~~\n[/color]"

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

func add_border_to_ascii_art(ascii_art: String, monster_name: String) -> String:
	"""Add a simple border around ASCII art"""
	var border_width = 50  # Total width including border chars

	# Parse out the color tag and content lines
	var lines = ascii_art.split("\n")
	var content_lines = []
	var color_tag = "[color=#555555]"

	for line in lines:
		var stripped = line.strip_edges()
		if stripped == "" or stripped == "[/color]":
			continue
		if stripped.begins_with("[color="):
			var end_bracket = stripped.find("]")
			if end_bracket > 0:
				color_tag = stripped.substr(0, end_bracket + 1)
				var after_tag = stripped.substr(end_bracket + 1).strip_edges()
				if after_tag != "" and after_tag != "[/color]":
					content_lines.append(after_tag)
			continue
		# Remove [/color] from end if present
		var clean_line = stripped.replace("[/color]", "").rstrip(" ")
		if clean_line != "":
			content_lines.append(clean_line)

	if content_lines.is_empty():
		return ascii_art

	# Find max width to check if art is too wide for border
	var max_art_width = 0
	for line in content_lines:
		max_art_width = max(max_art_width, line.length())

	# If art is wider than border, return it without border (pre-formatted art like goblin)
	if max_art_width > border_width:
		return ascii_art

	# Build bordered art
	var result = ""
	var color_end = "[/color]"

	# Top border
	result += "[color=#AAAAAA]╔" + "═".repeat(border_width) + "╗[/color]\n"

	# Content lines centered within the border
	for line in content_lines:
		var left_pad = (border_width - line.length()) / 2
		var right_pad = border_width - line.length() - left_pad
		result += "[color=#AAAAAA]║[/color]" + " ".repeat(left_pad) + color_tag + line + color_end + " ".repeat(right_pad) + "[color=#AAAAAA]║[/color]\n"

	# Bottom border
	result += "[color=#AAAAAA]╚" + "═".repeat(border_width) + "╝[/color]"

	return result

func generate_combat_start_message(character: Character, monster: Dictionary) -> String:
	"""Generate the initial combat message with ASCII art and color-coded name"""
	var ascii_art = get_monster_ascii_art(monster.name)
	var bordered_art = add_border_to_ascii_art(ascii_art, monster.name)

	# Wrap ASCII art with smaller font size
	bordered_art = "[font_size=%d]%s[/font_size]" % [ASCII_ART_FONT_SIZE, bordered_art]

	# Get encounter text without art
	var encounter_text = generate_encounter_text(monster)

	return bordered_art + "\n" + encounter_text

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
		notable_abilities.append("[color=#FF8000]★ WEAPON MASTER ★[/color]")
	if ABILITY_SHIELD_BEARER in abilities:
		notable_abilities.append("[color=#00FFFF]★ SHIELD GUARDIAN ★[/color]")
	if ABILITY_CORROSIVE in abilities:
		notable_abilities.append("[color=#FFFF00]⚠ CORROSIVE ⚠[/color]")
	if ABILITY_SUNDER in abilities:
		notable_abilities.append("[color=#FF4444]⚠ SUNDERING ⚠[/color]")
	if ABILITY_CHARM in abilities:
		notable_abilities.append("[color=#FF00FF]Enchanting[/color]")
	if ABILITY_GOLD_STEAL in abilities:
		notable_abilities.append("[color=#FFD700]⚠ THIEF ⚠[/color]")
	if ABILITY_BUFF_DESTROY in abilities:
		notable_abilities.append("[color=#808080]Dispeller[/color]")
	if ABILITY_SHIELD_SHATTER in abilities:
		notable_abilities.append("[color=#FF4444]Shield Breaker[/color]")
	if ABILITY_XP_STEAL in abilities:
		notable_abilities.append("[color=#FF00FF]⚠ XP DRAINER ⚠[/color]")
	if ABILITY_ITEM_STEAL in abilities:
		notable_abilities.append("[color=#FF0000]⚠ PICKPOCKET ⚠[/color]")
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

func roll_combat_drops(monster: Dictionary, _character: Character) -> Array:
	"""Roll for item drops after defeating a monster. Returns array of items.
	NOTE: Does NOT add items to inventory - server handles that to avoid duplication."""
	# If drop tables not initialized, return empty
	if drop_tables == null:
		return []

	var drop_table_id = monster.get("drop_table_id", "common")
	var drop_chance = monster.get("drop_chance", 5)
	var monster_level = monster.get("level", 1)

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
	"""Roll for gem drops. Returns number of gems earned."""
	var monster_level = monster.get("level", 1)
	var player_level = character.level
	var level_diff = monster_level - player_level

	# No gem chance unless monster is higher level than player
	if level_diff < 5:
		return 0

	# Gem drop chance based on level difference
	var gem_chance = 0
	if level_diff >= 100:
		gem_chance = 50
	elif level_diff >= 75:
		gem_chance = 35
	elif level_diff >= 50:
		gem_chance = 25
	elif level_diff >= 30:
		gem_chance = 18
	elif level_diff >= 20:
		gem_chance = 12
	elif level_diff >= 15:
		gem_chance = 8
	elif level_diff >= 10:
		gem_chance = 5
	else:  # level_diff >= 5
		gem_chance = 2

	# Roll for gem drop
	var roll = randi() % 100
	if roll >= gem_chance:
		return 0

	# Gem quantity formula: scales with monster lethality and level (configurable)
	var cfg = balance_config.get("rewards", {})
	var lethality = monster.get("lethality", 0)
	var lethality_divisor = cfg.get("gem_lethality_divisor", 1000)
	var level_divisor = cfg.get("gem_level_divisor", 100)
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
	if monster_level >= 100:
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

	# Option 1: Always a good option (gems or gear)
	if randf() < 0.5:
		options.append(_generate_gem_wish(monster_level))
	else:
		options.append(_generate_gear_wish(player_level, monster_level))

	# Option 2: Another good option (different from option 1)
	if options[0].type == "gems":
		options.append(_generate_gear_wish(player_level, monster_level))
	else:
		options.append(_generate_gem_wish(monster_level))

	# Option 3: Special option - small chance for permanent stats, otherwise buff or equipment upgrade
	if randf() < 0.10:  # 10% chance for permanent stat boost
		options.append(_generate_stat_wish())
	elif randf() < 0.5:
		options.append(_generate_buff_wish())
	else:
		options.append(_generate_upgrade_wish(monster_lethality, level_diff))

	return options

func _generate_gem_wish(monster_level: int) -> Dictionary:
	"""Generate a gem reward wish option"""
	var gem_amount = max(5, int(monster_level / 10) + randi_range(3, 8))
	return {
		"type": "gems",
		"amount": gem_amount,
		"label": "%d Gems" % gem_amount,
		"description": "Receive %d precious gems" % gem_amount,
		"color": "#00FFFF"
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
	# Base upgrades: 1-2
	# Lethality bonus: +1 per 500 lethality (max +5)
	# Level diff bonus: +1 per 10 levels above player (max +5)
	var base_upgrades = randi_range(1, 2)
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
		"gems":
			character.gems += wish.amount
			return "[color=#00FFFF]✦ ◆ [/color][color=#FF00FF]WISH GRANTED: +%d gems![/color][color=#00FFFF] ◆ ✦[/color]" % wish.amount
		"gold":
			character.gold += wish.amount
			return "[color=#FFD700]WISH GRANTED: +%d gold![/color]" % wish.amount
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
