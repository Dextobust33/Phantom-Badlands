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

# Drop tables reference (set by server when initialized)
# Using Node type to avoid compile-time dependency on DropTables class
var drop_tables: Node = null

func _ready():
	print("Combat Manager initialized")

func start_combat(peer_id: int, character: Character, monster: Dictionary) -> Dictionary:
	"""Initialize a new combat encounter"""
	
	# Create combat state
	var combat_state = {
		"peer_id": peer_id,
		"character": character,
		"monster": monster,
		"round": 1,
		"player_can_act": true,
		"combat_log": [],
		"started_at": Time.get_ticks_msec(),
		"outsmart_failed": false  # Can only attempt outsmart once per combat
	}
	
	active_combats[peer_id] = combat_state

	# Mark character as in combat and reset per-combat flags
	character.in_combat = true
	character.reset_combat_flags()  # Reset Dwarf Last Stand etc.
	
	# Generate initial combat message
	var msg = generate_combat_start_message(character, monster)
	combat_state.combat_log.append(msg)
	
	return {
		"success": true,
		"message": msg,
		"combat_state": get_combat_display(peer_id)
	}

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

	# Tick buff durations at end of round
	combat.character.tick_buffs()

	return result

func process_attack(combat: Dictionary) -> Dictionary:
	"""Process player attack action"""
	var character = combat.character
	var monster = combat.monster
	var messages = []

	# Check for vanish (auto-crit from Trickster ability)
	var is_vanished = combat.get("vanished", false)
	if is_vanished:
		combat.erase("vanished")

	# Hit chance: 95% base, -1% per 2 monster levels above player (minimum 70%)
	# Vanish guarantees hit
	var player_level = character.level
	var monster_level = monster.level
	var level_diff = max(0, monster_level - player_level)
	var hit_chance = 95 - (level_diff / 2)
	hit_chance = max(70, hit_chance)  # Never below 70%

	var hit_roll = randi() % 100

	if is_vanished or hit_roll < hit_chance:
		# Hit!
		var damage = calculate_damage(character, monster)

		# Apply vanish crit (1.5x damage) or regular crit
		var is_crit = is_vanished or (randi() % 100 < 10)  # 10% base crit chance
		if is_crit:
			damage = int(damage * 1.5)
			if is_vanished:
				messages.append("[color=#FFD700]You strike from the shadows![/color]")
			messages.append("[color=#FFD700]CRITICAL HIT![/color]")

		monster.current_hp -= damage
		monster.current_hp = max(0, monster.current_hp)

		messages.append("[color=#90EE90]You attack the %s![/color]" % monster.name)
		messages.append("You deal [color=#FFFF00]%d[/color] damage!" % damage)

		if monster.current_hp <= 0:
			# Monster defeated!
			messages.append("[color=#00FF00]The %s is defeated![/color]" % monster.name)

			# Calculate XP with level difference bonus
			var base_xp = monster.experience_reward
			var xp_level_diff = monster.level - character.level
			var xp_multiplier = 1.0

			# Bonus XP for fighting stronger monsters (risk vs reward)
			if xp_level_diff > 0:
				# +10% per level above, up to +500% at 50 levels above
				# Then +5% per level beyond 50, uncapped
				if xp_level_diff <= 50:
					xp_multiplier = 1.0 + (xp_level_diff * 0.10)
				else:
					xp_multiplier = 6.0 + ((xp_level_diff - 50) * 0.05)

			var final_xp = int(base_xp * xp_multiplier)

			if xp_level_diff >= 10:
				messages.append("[color=#FFD700]You gain %d experience! [color=#00FFFF](+%d%% bonus!)[/color][/color]" % [final_xp, int((xp_multiplier - 1.0) * 100)])
			else:
				messages.append("[color=#FFD700]You gain %d experience![/color]" % final_xp)
			messages.append("[color=#FFD700]You gain %d gold![/color]" % monster.gold_reward)

			# Award experience and gold
			character.add_experience(final_xp)
			character.gold += monster.gold_reward

			# Roll for gem drops (from high-level monsters)
			var gems_earned = roll_gem_drops(monster, character)
			if gems_earned > 0:
				character.gems += gems_earned
				messages.append("[color=#00FFFF]You found %d gem%s![/color]" % [gems_earned, "s" if gems_earned > 1 else ""])

			# Roll for item drops
			var dropped_items = roll_combat_drops(monster, character)
			for item in dropped_items:
				messages.append("[color=%s]%s dropped: %s![/color]" % [
					_get_rarity_color(item.get("rarity", "common")),
					monster.name,
					item.get("name", "Unknown Item")
				])

			return {
				"success": true,
				"messages": messages,
				"combat_ended": true,
				"victory": true,
				"monster_name": monster.name,
				"monster_level": monster.level,
				"flock_chance": monster.get("flock_chance", 0),
				"dropped_items": dropped_items,
				"gems_earned": gems_earned
			}
	else:
		# Miss
		messages.append("[color=#FF6B6B]You swing at the %s but miss![/color]" % monster.name)
	
	combat.player_can_act = false
	
	return {
		"success": true,
		"messages": messages,
		"combat_ended": false
	}

func process_defend(combat: Dictionary) -> Dictionary:
	"""Process player defend action"""
	var character = combat.character
	var messages = []
	
	# Defending gives temporary defense bonus and small HP recovery
	var defense_bonus = character.get_stat("constitution") / 4
	var heal_amount = max(1, character.max_hp / 20)
	
	character.current_hp = min(character.max_hp, character.current_hp + heal_amount)
	
	messages.append("[color=#87CEEB]You take a defensive stance![/color]")
	messages.append("[color=#90EE90]You recover %d HP![/color]" % heal_amount)
	
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

	# Flee chance based on speed difference (includes speed buff)
	var player_speed = character.get_stat("dexterity") + character.get_buff_value("speed")
	var flee_chance = 50 + (player_speed - monster.speed) * 5
	flee_chance = clamp(flee_chance, 10, 95)  # 10-95% chance
	
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
		messages.append("[color=#FF6B6B]You fail to escape![/color]")
		combat.player_can_act = false
		return {
			"success": true,
			"messages": messages,
			"combat_ended": false
		}

func process_special(combat: Dictionary) -> Dictionary:
	"""Process special action (class-specific)"""
	var messages = []
	messages.append("[color=#95A5A6]Special abilities coming soon![/color]")

	return {
		"success": false,
		"messages": messages,
		"combat_ended": false
	}

func process_outsmart(combat: Dictionary) -> Dictionary:
	"""Process outsmart action (Trickster ability).
	Success = instant win with full rewards.
	Failure = monster gets free attack, can't outsmart again this combat.
	Success chance = (player_wits - monster_intelligence) * 5 + 30%, clamped 5-95%."""
	var character = combat.character
	var monster = combat.monster
	var messages = []

	# Check if already failed outsmart this combat
	if combat.get("outsmart_failed", false):
		messages.append("[color=#FF6B6B]You already failed to outsmart this enemy![/color]")
		return {
			"success": false,
			"messages": messages,
			"combat_ended": false
		}

	# Calculate outsmart chance
	var player_wits = character.get_stat("wits")
	var monster_intelligence = monster.get("intelligence", 15)
	var wits_diff = player_wits - monster_intelligence
	var outsmart_chance = (wits_diff * 5) + 30
	outsmart_chance = clampi(outsmart_chance, 5, 95)  # Min 5%, max 95%

	messages.append("[color=#FFA500]You attempt to outsmart the %s...[/color]" % monster.name)
	messages.append("[color=#95A5A6](Your Wits: %d vs Monster Intelligence: %d = %d%% chance)[/color]" % [player_wits, monster_intelligence, outsmart_chance])

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

		messages.append("[color=#9B59B6]+%d XP[/color] | [color=#FFD700]+%d gold[/color]" % [final_xp, gold])

		if level_result.leveled_up:
			messages.append("[color=#FFD700][b]LEVEL UP![/b] You are now level %d![/color]" % level_result.new_level)

		# Roll for item drops
		var dropped_items = []
		var gems_earned = 0
		if drop_tables:
			var drops_result = drop_tables.roll_drops(
				monster.get("drop_table_id", "tier1"),
				monster.get("drop_chance", 5),
				monster.level
			)
			dropped_items = drops_result

			# Roll for gem drops
			gems_earned = roll_gem_drops(monster, character)
			if gems_earned > 0:
				character.gems += gems_earned
				messages.append("[color=#00FFFF]+%d gem%s![/color]" % [gems_earned, "s" if gems_earned > 1 else ""])

		return {
			"success": true,
			"messages": messages,
			"combat_ended": true,
			"victory": true,
			"monster_name": monster.name,
			"monster_level": monster.level,
			"flock_chance": monster.get("flock_chance", 0),
			"dropped_items": dropped_items,
			"gems_earned": gems_earned
		}
	else:
		# FAILURE! Monster gets free attack
		combat.outsmart_failed = true
		messages.append("[color=#FF6B6B][b]FAILED![/b] The %s sees through your trick![/color]" % monster.name)

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
		character.tick_buffs()

		return {
			"success": true,
			"messages": messages,
			"combat_ended": false
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

	# Mage abilities (use mana)
	if ability_name in ["magic_bolt", "shield", "cloak", "blast", "forcefield", "teleport", "meteor"]:
		result = _process_mage_ability(combat, ability_name, arg)
	# Warrior abilities (use stamina)
	elif ability_name in ["power_strike", "war_cry", "shield_bash", "cleave", "berserk", "iron_skin", "devastate"]:
		result = _process_warrior_ability(combat, ability_name)
	# Trickster abilities (use energy)
	elif ability_name in ["analyze", "distract", "pickpocket", "ambush", "vanish", "exploit", "perfect_heist"]:
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
	combat.character.tick_buffs()
	combat.character.regenerate_energy()  # Energy regenerates each round

	return result

func _process_mage_ability(combat: Dictionary, ability_name: String, arg: String) -> Dictionary:
	"""Process mage abilities (use mana)"""
	var character = combat.character
	var monster = combat.monster
	var messages = []

	# Check INT requirement for mage path
	if character.get_stat("intelligence") <= 10:
		return {"success": false, "messages": ["[color=#FF6B6B]You need INT > 10 to use mage abilities![/color]"], "combat_ended": false}

	# Get ability info
	var ability_info = _get_ability_info("mage", ability_name)
	if ability_info.is_empty():
		return {"success": false, "messages": ["[color=#FF6B6B]Unknown mage ability![/color]"], "combat_ended": false}

	# Check level requirement
	if character.level < ability_info.level:
		return {"success": false, "messages": ["[color=#FF6B6B]%s requires level %d![/color]" % [ability_info.name, ability_info.level]], "combat_ended": false}

	var mana_cost = ability_info.cost

	match ability_name:
		"magic_bolt":
			# Variable mana cost - damage equals mana spent
			var bolt_amount = arg.to_int() if arg.is_valid_int() else 0
			if bolt_amount <= 0:
				return {"success": false, "messages": ["[color=#95A5A6]Usage: bolt <amount> - deals damage equal to mana spent[/color]"], "combat_ended": false, "skip_monster_turn": true}
			bolt_amount = mini(bolt_amount, character.current_mana)
			if bolt_amount <= 0:
				return {"success": false, "messages": ["[color=#FF6B6B]Not enough mana![/color]"], "combat_ended": false, "skip_monster_turn": true}
			character.current_mana -= bolt_amount
			monster.current_hp -= bolt_amount
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#9B59B6]You cast Magic Bolt for %d mana![/color]" % bolt_amount)
			messages.append("[color=#00FFFF]The bolt strikes for %d damage![/color]" % bolt_amount)

		"shield":
			if not character.use_mana(mana_cost):
				return {"success": false, "messages": ["[color=#FF6B6B]Not enough mana! (Need %d)[/color]" % mana_cost], "combat_ended": false, "skip_monster_turn": true}
			character.add_buff("defense", 50, 3)  # +50% defense for 3 rounds
			messages.append("[color=#9B59B6]You cast Shield! (+50%% defense for 3 rounds)[/color]" % [])

		"cloak":
			if not character.use_mana(mana_cost):
				return {"success": false, "messages": ["[color=#FF6B6B]Not enough mana! (Need %d)[/color]" % mana_cost], "combat_ended": false, "skip_monster_turn": true}
			combat["cloak_active"] = true  # 50% miss chance for enemy
			messages.append("[color=#9B59B6]You cast Cloak! (50%% chance enemy misses next attack)[/color]" % [])

		"blast":
			if not character.use_mana(mana_cost):
				return {"success": false, "messages": ["[color=#FF6B6B]Not enough mana! (Need %d)[/color]" % mana_cost], "combat_ended": false, "skip_monster_turn": true}
			var damage = character.get_stat("intelligence") * 2
			monster.current_hp -= damage
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#9B59B6]You cast Blast![/color]")
			messages.append("[color=#00FFFF]The explosion deals %d damage![/color]" % damage)

		"forcefield":
			if not character.use_mana(mana_cost):
				return {"success": false, "messages": ["[color=#FF6B6B]Not enough mana! (Need %d)[/color]" % mana_cost], "combat_ended": false, "skip_monster_turn": true}
			combat["forcefield_charges"] = 2  # Block next 2 attacks
			messages.append("[color=#9B59B6]You cast Forcefield! (Blocks next 2 attacks)[/color]")

		"teleport":
			if not character.use_mana(mana_cost):
				return {"success": false, "messages": ["[color=#FF6B6B]Not enough mana! (Need %d)[/color]" % mana_cost], "combat_ended": false, "skip_monster_turn": true}
			messages.append("[color=#9B59B6]You cast Teleport and vanish![/color]")
			return {
				"success": true,
				"messages": messages,
				"combat_ended": true,
				"fled": true,
				"skip_monster_turn": true
			}

		"meteor":
			if not character.use_mana(mana_cost):
				return {"success": false, "messages": ["[color=#FF6B6B]Not enough mana! (Need %d)[/color]" % mana_cost], "combat_ended": false, "skip_monster_turn": true}
			var damage = character.get_stat("intelligence") * 5
			monster.current_hp -= damage
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#FFD700][b]METEOR![/b][/color]")
			messages.append("[color=#FF6B6B]A massive meteor crashes down for %d damage![/color]" % damage)

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
		return {"success": false, "messages": ["[color=#FF6B6B]You need STR > 10 to use warrior abilities![/color]"], "combat_ended": false}

	# Get ability info
	var ability_info = _get_ability_info("warrior", ability_name)
	if ability_info.is_empty():
		return {"success": false, "messages": ["[color=#FF6B6B]Unknown warrior ability![/color]"], "combat_ended": false}

	# Check level requirement
	if character.level < ability_info.level:
		return {"success": false, "messages": ["[color=#FF6B6B]%s requires level %d![/color]" % [ability_info.name, ability_info.level]], "combat_ended": false}

	var stamina_cost = ability_info.cost

	if not character.use_stamina(stamina_cost):
		return {"success": false, "messages": ["[color=#FF6B6B]Not enough stamina! (Need %d)[/color]" % stamina_cost], "combat_ended": false, "skip_monster_turn": true}

	match ability_name:
		"power_strike":
			var damage = int(character.get_stat("strength") * 1.5)
			monster.current_hp -= damage
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#FF6B6B]POWER STRIKE![/color]")
			messages.append("[color=#FFFF00]You deal %d damage![/color]" % damage)

		"war_cry":
			character.add_buff("damage", 25, 3)  # +25% damage for 3 rounds
			messages.append("[color=#FF6B6B]WAR CRY![/color]")
			messages.append("[color=#FFD700]+25%% damage for 3 rounds![/color]" % [])

		"shield_bash":
			var damage = character.get_stat("strength")
			monster.current_hp -= damage
			monster.current_hp = max(0, monster.current_hp)
			combat["monster_stunned"] = true  # Enemy skips next turn
			messages.append("[color=#FF6B6B]SHIELD BASH![/color]")
			messages.append("[color=#FFFF00]You deal %d damage and stun the enemy![/color]" % damage)

		"cleave":
			var damage = character.get_stat("strength") * 2
			monster.current_hp -= damage
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#FF6B6B]CLEAVE![/color]")
			messages.append("[color=#FFFF00]Your massive swing deals %d damage![/color]" % damage)

		"berserk":
			character.add_buff("damage", 100, 3)  # +100% damage for 3 rounds
			character.add_buff("defense_penalty", -50, 3)  # -50% defense for 3 rounds
			messages.append("[color=#FF0000][b]BERSERK![/b][/color]")
			messages.append("[color=#FFD700]+100%% damage, -50%% defense for 3 rounds![/color]" % [])

		"iron_skin":
			character.add_buff("damage_reduction", 50, 3)  # Block 50% damage for 3 rounds
			messages.append("[color=#AAAAAA]IRON SKIN![/color]")
			messages.append("[color=#90EE90]Block 50%% damage for 3 rounds![/color]" % [])

		"devastate":
			var damage = character.get_stat("strength") * 4
			monster.current_hp -= damage
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#FF0000][b]DEVASTATE![/b][/color]")
			messages.append("[color=#FFFF00]A catastrophic blow deals %d damage![/color]" % damage)

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
		return {"success": false, "messages": ["[color=#FF6B6B]You need WITS > 10 to use trickster abilities![/color]"], "combat_ended": false}

	# Get ability info
	var ability_info = _get_ability_info("trickster", ability_name)
	if ability_info.is_empty():
		return {"success": false, "messages": ["[color=#FF6B6B]Unknown trickster ability![/color]"], "combat_ended": false}

	# Check level requirement
	if character.level < ability_info.level:
		return {"success": false, "messages": ["[color=#FF6B6B]%s requires level %d![/color]" % [ability_info.name, ability_info.level]], "combat_ended": false}

	var energy_cost = ability_info.cost

	if not character.use_energy(energy_cost):
		return {"success": false, "messages": ["[color=#FF6B6B]Not enough energy! (Need %d)[/color]" % energy_cost], "combat_ended": false, "skip_monster_turn": true}

	match ability_name:
		"analyze":
			messages.append("[color=#90EE90]ANALYZE![/color]")
			messages.append("[color=#95A5A6]%s (Level %d)[/color]" % [monster.name, monster.level])
			messages.append("[color=#FF6B6B]HP:[/color] %d/%d" % [monster.current_hp, monster.max_hp])
			messages.append("[color=#FFFF00]Damage:[/color] ~%d" % monster.strength)
			messages.append("[color=#FFA500]Intelligence:[/color] %d" % monster.get("intelligence", 15))
			# Skip monster turn for analyze (information only)
			return {"success": true, "messages": messages, "combat_ended": false, "skip_monster_turn": true}

		"distract":
			combat["enemy_distracted"] = true  # -50% accuracy next attack
			messages.append("[color=#90EE90]DISTRACT![/color]")
			messages.append("[color=#95A5A6]The enemy is distracted! (-50%% accuracy)[/color]" % [])

		"pickpocket":
			var wits = character.get_stat("wits")
			var success_chance = 50 + wits - monster.get("intelligence", 15)
			success_chance = clampi(success_chance, 10, 90)
			var roll = randi() % 100
			if roll < success_chance:
				var stolen_gold = wits * 10
				character.gold += stolen_gold
				messages.append("[color=#90EE90]PICKPOCKET SUCCESS![/color]")
				messages.append("[color=#FFD700]You steal %d gold![/color]" % stolen_gold)
				return {"success": true, "messages": messages, "combat_ended": false, "skip_monster_turn": true}
			else:
				messages.append("[color=#FF6B6B]PICKPOCKET FAILED![/color]")
				messages.append("[color=#95A5A6]The enemy catches you![/color]")
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
			var wits = character.get_stat("wits")
			var damage = int(wits * 1.5)
			# 50% crit chance
			if randi() % 100 < 50:
				damage = int(damage * 1.5)
				messages.append("[color=#FFD700]CRITICAL AMBUSH![/color]")
			else:
				messages.append("[color=#90EE90]AMBUSH![/color]")
			monster.current_hp -= damage
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#FFFF00]You deal %d damage![/color]" % damage)

		"vanish":
			combat["vanished"] = true  # Next attack auto-crits
			messages.append("[color=#90EE90]VANISH![/color]")
			messages.append("[color=#95A5A6]You fade into shadow... Next attack will crit![/color]")
			return {"success": true, "messages": messages, "combat_ended": false, "skip_monster_turn": true}

		"exploit":
			var damage = int(monster.current_hp * 0.10)  # 10% of current HP
			damage = max(1, damage)
			monster.current_hp -= damage
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#90EE90]EXPLOIT WEAKNESS![/color]")
			messages.append("[color=#FFFF00]You exploit a weakness for %d damage![/color]" % damage)

		"perfect_heist":
			# Instant win + double rewards
			messages.append("[color=#FFD700][b]PERFECT HEIST![/b][/color]")
			messages.append("[color=#90EE90]You execute a flawless heist![/color]")

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

			messages.append("[color=#9B59B6]+%d XP (doubled!)[/color]" % final_xp)
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
					messages.append("[color=#00FFFF]+%d gems (doubled!)![/color]" % gems_earned)

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
				"cloak": return {"level": 25, "cost": 30, "name": "Cloak"}
				"blast": return {"level": 40, "cost": 50, "name": "Blast"}
				"forcefield": return {"level": 60, "cost": 75, "name": "Forcefield"}
				"teleport": return {"level": 80, "cost": 40, "name": "Teleport"}
				"meteor": return {"level": 100, "cost": 100, "name": "Meteor"}
		"warrior":
			match ability_name:
				"power_strike": return {"level": 1, "cost": 10, "name": "Power Strike"}
				"war_cry": return {"level": 10, "cost": 15, "name": "War Cry"}
				"shield_bash": return {"level": 25, "cost": 20, "name": "Shield Bash"}
				"cleave": return {"level": 40, "cost": 30, "name": "Cleave"}
				"berserk": return {"level": 60, "cost": 40, "name": "Berserk"}
				"iron_skin": return {"level": 80, "cost": 35, "name": "Iron Skin"}
				"devastate": return {"level": 100, "cost": 50, "name": "Devastate"}
		"trickster":
			match ability_name:
				"analyze": return {"level": 1, "cost": 5, "name": "Analyze"}
				"distract": return {"level": 10, "cost": 15, "name": "Distract"}
				"pickpocket": return {"level": 25, "cost": 20, "name": "Pickpocket"}
				"ambush": return {"level": 40, "cost": 30, "name": "Ambush"}
				"vanish": return {"level": 60, "cost": 40, "name": "Vanish"}
				"exploit": return {"level": 80, "cost": 35, "name": "Exploit"}
				"perfect_heist": return {"level": 100, "cost": 50, "name": "Perfect Heist"}
	return {}

func _process_victory(combat: Dictionary, messages: Array) -> Dictionary:
	"""Process monster defeat and return victory result"""
	var character = combat.character
	var monster = combat.monster

	messages.append("[color=#00FF00]The %s is defeated![/color]" % monster.name)

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
	var gold = monster.gold_reward

	var level_result = character.add_experience(final_xp)
	character.gold += gold

	messages.append("[color=#9B59B6]+%d XP[/color] | [color=#FFD700]+%d gold[/color]" % [final_xp, gold])

	if level_result.leveled_up:
		messages.append("[color=#FFD700][b]LEVEL UP![/b] You are now level %d![/color]" % level_result.new_level)

	# Roll for item drops
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
			character.gems += gems_earned
			messages.append("[color=#00FFFF]+%d gem%s![/color]" % [gems_earned, "s" if gems_earned > 1 else ""])

	return {
		"success": true,
		"messages": messages,
		"combat_ended": true,
		"victory": true,
		"monster_name": monster.name,
		"monster_level": monster.level,
		"flock_chance": monster.get("flock_chance", 0),
		"dropped_items": dropped_items,
		"gems_earned": gems_earned
	}

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
		messages.append("[color=#90EE90]You drink %s and restore %d HP![/color]" % [item_name, actual_heal])
	elif effect.has("buff"):
		# Buff potion
		var buff_type = effect.buff
		var buff_value = effect.base + (effect.per_level * item_level)
		var duration = effect.get("duration", 5)
		character.add_buff(buff_type, buff_value, duration)
		messages.append("[color=#00FFFF]You drink %s! +%d %s for %d rounds![/color]" % [item_name, buff_value, buff_type, duration])

	# Remove item from inventory
	character.remove_item(item_index)

	# Item use is a FREE ACTION - player can still act this turn
	# No monster turn, no round increment, no buff tick
	messages.append("[color=#95A5A6](Free action - you may still act)[/color]")

	return {
		"success": true,
		"messages": messages,
		"combat_ended": false
	}

func process_monster_turn(combat: Dictionary) -> Dictionary:
	"""Process the monster's attack"""
	var character = combat.character
	var monster = combat.monster

	# Check if monster is stunned (Shield Bash)
	if combat.get("monster_stunned", false):
		combat.erase("monster_stunned")
		return {"success": true, "message": "[color=#95A5A6]The %s is stunned and cannot act![/color]" % monster.name}

	# Check for Forcefield (blocks attacks completely)
	var forcefield = combat.get("forcefield_charges", 0)
	if forcefield > 0:
		combat["forcefield_charges"] = forcefield - 1
		var charges_left = forcefield - 1
		if charges_left > 0:
			return {"success": true, "message": "[color=#9B59B6]Your Forcefield absorbs the attack! (%d charge%s left)[/color]" % [charges_left, "s" if charges_left > 1 else ""]}
		else:
			return {"success": true, "message": "[color=#9B59B6]Your Forcefield absorbs the attack! (Shield breaks)[/color]"}

	# Monster hit chance: 85% base, +1% per monster level above player (cap 95%)
	# Defending reduces hit chance by 15%
	var player_level = character.level
	var monster_level = monster.level
	var level_diff = monster_level - player_level
	var hit_chance = 85 + level_diff
	hit_chance = clamp(hit_chance, 60, 95)

	# Defending reduces monster hit chance
	var is_defending = combat.get("defending", false)
	if is_defending:
		hit_chance -= 15

	# Clear defend status
	combat.defending = false
	combat.defense_bonus = 0

	# Cloak: 50% miss chance (one time)
	if combat.get("cloak_active", false):
		combat.erase("cloak_active")
		if randi() % 100 < 50:
			return {"success": true, "message": "[color=#9B59B6]Your Cloak causes the %s to miss![/color]" % monster.name}

	# Distract: -50% accuracy (one time)
	if combat.get("enemy_distracted", false):
		combat.erase("enemy_distracted")
		hit_chance = int(hit_chance * 0.5)

	var hit_roll = randi() % 100

	if hit_roll < hit_chance:
		# Monster hits
		var damage = calculate_monster_damage(monster, character)

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

		character.current_hp -= damage

		# Check for Dwarf Last Stand (survive lethal damage with 1 HP)
		if character.current_hp <= 0:
			if character.try_last_stand():
				# Last Stand triggered! Survive with 1 HP
				var msg = "[color=#FF6B6B]The %s attacks and deals %d damage![/color]\n" % [monster.name, damage]
				msg += "[color=#FFD700][b]LAST STAND![/b] Your dwarven resilience saves you![/color]"
				return {"success": true, "message": msg, "last_stand": true}

		character.current_hp = max(0, character.current_hp)

		var msg = "[color=#FF6B6B]The %s attacks and deals %d damage![/color]" % [monster.name, damage]
		return {"success": true, "message": msg}
	else:
		# Monster misses
		var msg = "[color=#90EE90]The %s attacks but misses![/color]" % monster.name
		return {"success": true, "message": msg}

func calculate_damage(character: Character, monster: Dictionary) -> int:
	"""Calculate player damage to monster (includes equipment and buff bonuses)"""
	# Use total attack which includes equipment
	var base_damage = character.get_total_attack()

	# Add strength buff bonus
	var strength_buff = character.get_buff_value("strength")
	base_damage += strength_buff

	var damage_roll = (randi() % 6) + 1  # 1d6
	var raw_damage = base_damage + damage_roll

	# Apply damage buff (War Cry, Berserk)
	var damage_buff = character.get_buff_value("damage")
	if damage_buff > 0:
		raw_damage = int(raw_damage * (1.0 + damage_buff / 100.0))

	# Monster defense reduces damage by a percentage (not flat)
	# Defense 10 = 5% reduction, Defense 100 = 33% reduction, Defense 500 = 50% reduction
	var defense_ratio = float(monster.defense) / (float(monster.defense) + 100.0)
	var damage_reduction = defense_ratio * 0.6  # Max 60% reduction at very high defense
	var total = int(raw_damage * (1.0 - damage_reduction))

	return max(1, total)  # Minimum 1 damage

func calculate_monster_damage(monster: Dictionary, character: Character) -> int:
	"""Calculate monster damage to player (reduced by equipment defense and buffs)"""
	var base_damage = monster.strength
	var damage_roll = (randi() % 6) + 1  # 1d6
	var raw_damage = base_damage + damage_roll

	# Player defense reduces damage by percentage (not flat)
	# Defense 10 = 9% reduction, Defense 50 = 33% reduction, Defense 200 = 50% reduction
	var player_defense = character.get_total_defense()

	# Add defense buff bonus
	var defense_buff = character.get_buff_value("defense")
	player_defense += defense_buff

	var defense_ratio = float(player_defense) / (float(player_defense) + 100.0)
	var damage_reduction = defense_ratio * 0.6  # Max 60% reduction at very high defense
	var total = int(raw_damage * (1.0 - damage_reduction))

	# Level difference bonus: monsters higher level deal extra damage
	var level_diff = monster.level - character.level
	if level_diff > 0:
		# +5% damage per level above player, compounding
		var level_multiplier = pow(1.05, min(level_diff, 50))  # Cap at 50 level diff
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

		# Clear combat buffs
		character.clear_buffs()

		# Remove from active combats
		active_combats.erase(peer_id)

		print("Combat ended for peer %d - Victory: %s" % [peer_id, victory])

func is_in_combat(peer_id: int) -> bool:
	"""Check if a player is in combat"""
	return active_combats.has(peer_id)

func get_combat_display(peer_id: int) -> Dictionary:
	"""Get formatted combat state for display"""
	if not active_combats.has(peer_id):
		return {}
	
	var combat = active_combats[peer_id]
	var character = combat.character
	var monster = combat.monster
	
	return {
		"round": combat.round,
		"player_name": character.name,
		"player_hp": character.current_hp,
		"player_max_hp": character.max_hp,
		"player_hp_percent": int((float(character.current_hp) / character.max_hp) * 100),
		"player_mana": character.current_mana,
		"player_max_mana": character.max_mana,
		"player_stamina": character.current_stamina,
		"player_max_stamina": character.max_stamina,
		"player_energy": character.current_energy,
		"player_max_energy": character.max_energy,
		"monster_name": monster.name,
		"monster_level": monster.level,
		"monster_hp": monster.current_hp,
		"monster_max_hp": monster.max_hp,
		"monster_hp_percent": int((float(monster.current_hp) / monster.max_hp) * 100),
		"can_act": combat.player_can_act
	}

func get_monster_ascii_art(monster_name: String) -> String:
	"""Return ASCII art for the monster, properly formatted for centering"""
	# Map monster names to ASCII art - each line will be centered individually
	var art_map = {
		# Tier 1 - Small creatures
		"Goblin": ["[color=#90EE90]",
"      ,,,",
"    /(o.o)\\",
"   _| === |_",
"  / |  |  | \\",
"    |  |  |",
"   _|  |  |_",
"  (__/   \\__)","[/color]"],

		"Giant Rat": ["[color=#8B4513]",
"    (\\,/)",
"    oo   '''//,",
"  ,(~)_______/",
"  \\(@)/ '''''",
"    U '''''' U","[/color]"],

		"Kobold": ["[color=#DAA520]",
"      /\\  /\\",
"     ( o  o )",
"    /   <>   \\",
"   /  | -- |  \\",
"      | || |",
"     /| || |\\",
"    (_/    \\_)","[/color]"],

		"Skeleton": ["[color=#FFFFFF]",
"      .---.   ",
"     / o o \\ ",
"    (   ^   )",
"     \\ --- /",
"    __|   |__",
"   /__|   |__\\",
"      |   |",
"     _|   |_","[/color]"],

		"Wolf": ["[color=#808080]",
"   /\\       /\\",
"  /  \\_____/  \\",
"  |  o     o  |",
"  \\     W     /",
"   \\  '---'  /",
"    \\__| |__/",
"       | |","[/color]"],

		# Tier 2 - Medium creatures
		"Orc": ["[color=#228B22]",
"     \\\\|||//",
"     ( O O )",
"      \\ = /",
"    __|===|__",
"   /  |   |  \\",
"   |  |   |  |",
"   |__|   |__|","[/color]"],

		"Hobgoblin": ["[color=#FF6347]",
"      /|||\\",
"     ( o_o )",
"      \\ - /",
"    __|===|__",
"   /  |   |  \\",
"      |   |",
"     _|   |_","[/color]"],

		"Gnoll": ["[color=#D2691E]",
"     /\\   /\\",
"    (  \\ /  )",
"    | o   o |",
"     \\ === /",
"   __|     |__",
"  /  |     |  \\",
"     ||   ||","[/color]"],

		"Zombie": ["[color=#556B2F]",
"     ~~~~~~~",
"    (  o    )",
"     \\ --- /",
"   __|     |__",
"  /   |   |   \\",
"       |  |",
"       |  |","[/color]"],

		"Giant Spider": ["[color=#4B0082]",
"    /\\    /\\",
"   //\\\\  //\\\\",
"  // (o  o) \\\\",
"  \\\\  \\--/  //",
"   \\\\  ||  //",
"    \\\\_||_//",
"     //  \\\\","[/color]"],

		"Wight": ["[color=#778899]",
"     .oOOo.",
"    (  O O )",
"     \\ ~~ /",
"   __|    |__",
"  /  ~~~~~~  \\",
"  \\          /",
"   ~~~~~~~~~~","[/color]"],

		# Tier 3 - Large creatures
		"Ogre": ["[color=#6B8E23]",
"    \\======/",
"    ( O  O )",
"     \\ == /",
"   __|====|__",
"  /  |    |  \\",
"  |  |    |  |",
"  |__|    |__|","[/color]"],

		"Troll": ["[color=#2F4F4F]",
"     .-----.",
"    /  o o  \\",
"    \\   =   /",
"   __|-----|__",
"  /  |     |  \\",
"  |__|     |__|",
"     |     |","[/color]"],

		"Wraith": ["[color=#9370DB]",
"    .oOOOOo.",
"   (  ~  ~  )",
"    \\      /",
"     \\    /",
"      \\  /",
"       \\/",
"      ~~~~","[/color]"],

		"Wyvern": ["[color=#8FBC8F]",
"    /\\     /\\",
"   /  \\___/  \\",
"  <==(o   o)==>",
"     /) ^ (\\",
"    //     \\\\",
"   //   |   \\\\",
"  ~~   / \\   ~~","[/color]"],

		"Minotaur": ["[color=#8B0000]",
"   (\\       /)",
"    \\\\     //",
"     (o   o)",
"      \\ = /",
"    __|===|__",
"   /  |   |  \\",
"   |__|   |__|","[/color]"],

		# Tier 4 - Powerful creatures
		"Giant": ["[color=#A0522D]",
"    __|===|__",
"   /  O   O  \\",
"   \\    =    /",
"  __|=======|__",
" /  |       |  \\",
" |  |       |  |",
" |__|       |__|","[/color]"],

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

		"Vampire": ["[color=#8B008B]",
"     .-----.",
"    / o   o \\",
"    \\   V   /",
"     \\_____/",
"       |=|",
"      /| |\\",
"     / | | \\","[/color]"],

		# Tier 5 - Epic creatures
		"Ancient Dragon": ["[color=#FF6600]",
"   <\\_______/>",
"   /  O   O  \\",
"  <     ^     >",
"   \\  ~~~~  /",
"  //)^^^^^^(\\\\",
" // |      | \\\\",
"<~~ |      | ~~>","[/color]"],

		"Demon Lord": ["[color=#B22222]",
"  \\\\\\     ///",
"   \\\\\\   ///",
"    ( O^O )",
"   <|~~~~~|>",
"  __|#####|__",
" <  |     |  >",
"   /|     |\\","[/color]"],

		"Lich": ["[color=#9932CC]",
"     .====.",
"    / X  X \\",
"    \\  ^^  /",
"   __|####|__",
"  /  |    |  \\",
"  \\  |    |  /",
"     ~~~~~~","[/color]"],

		"Titan": ["[color=#FFD700]",
"   ___|=|___",
"  /  O   O  \\",
"  \\    =    /",
" __|=======|__",
"/  |       |  \\",
"|  |       |  |",
"|__|       |__|","[/color]"],

		# Tier 6 - Legendary
		"Elemental": ["[color=#00CED1]",
"    *  /\\  *",
"   * /    \\ *",
"  * (  ~~  ) *",
"   * \\    / *",
"    * \\||/ *",
"     * || *",
"      ~~~~","[/color]"],

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

		"Entropy": ["[color=#888888]",
"    .......",
"   .       .",
"  .         .",
"   .       .",
"    .......",
"      ...",
"     .....","[/color]"]
	}

	# Return matching art - pad with spaces to push right
	var padding = "                              "  # 30 spaces to push art right
	if art_map.has(monster_name):
		var lines = art_map[monster_name]
		var result = ""
		for line in lines:
			if line.begins_with("[color=") or line == "[/color]":
				result += line
			else:
				result += padding + line + "\n"
		return result
	else:
		# Generic monster fallback
		return padding + "[color=#888888]     ?????[/color]\n" + padding + "[color=#888888]    ( o.o )[/color]\n" + padding + "[color=#888888]     \\ = /[/color]\n" + padding + "[color=#888888]    /|   |\\[/color]\n" + padding + "[color=#888888]      ~~~[/color]\n"

func generate_combat_start_message(character: Character, monster: Dictionary) -> String:
	"""Generate the initial combat message with ASCII art"""
	var ascii_art = get_monster_ascii_art(monster.name)
	var msg = ascii_art + "\n[color=#FFD700]You encounter a %s (Lvl %d)![/color]" % [monster.name, monster.level]
	return msg

func to_dict() -> Dictionary:
	return {
		"active_combats": active_combats.size()
	}

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

	# Gem quantity formula: scales with monster lethality and level
	var lethality = monster.get("lethality", 0)
	var gem_count = max(1, int(lethality / 1000) + int(monster_level / 100))

	return gem_count
