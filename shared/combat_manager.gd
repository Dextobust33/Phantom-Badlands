# combat_manager.gd
# Handles turn-based combat in Phantasia 4 style
class_name CombatManager
extends Node

# Combat actions
enum CombatAction {
	ATTACK,
	DEFEND,
	FLEE,
	SPECIAL
}

# Active combats (peer_id -> combat_state)
var active_combats = {}

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
		"started_at": Time.get_ticks_msec()
	}
	
	active_combats[peer_id] = combat_state
	
	# Mark character as in combat
	character.in_combat = true
	
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
	
	var action: CombatAction
	
	match command.to_lower():
		"attack", "a":
			action = CombatAction.ATTACK
		"defend", "d":
			action = CombatAction.DEFEND
		"flee", "f", "run":
			action = CombatAction.FLEE
		"special", "s":
			action = CombatAction.SPECIAL
		_:
			return {"success": false, "message": "Unknown combat command! Use: attack, defend, flee"}
	
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
			result.messages.append("[color=#FF0000]You have been defeated![/color]")
			end_combat(peer_id, false)
			return result
	
	# Increment round
	combat.round += 1
	combat.player_can_act = true
	
	return result

func process_attack(combat: Dictionary) -> Dictionary:
	"""Process player attack action"""
	var character = combat.character
	var monster = combat.monster
	var messages = []
	
	# Calculate hit chance
	var hit_roll = randi() % 20 + 1  # 1d20
	var hit_bonus = character.get_stat("strength") / 2
	var hit_total = hit_roll + hit_bonus
	var monster_ac = 10 + monster.defense / 2
	
	if hit_total >= monster_ac:
		# Hit!
		var damage = calculate_damage(character, monster)
		monster.current_hp -= damage
		monster.current_hp = max(0, monster.current_hp)
		
		messages.append("[color=#90EE90]You attack the %s![/color]" % monster.name)
		messages.append("[color=#FFD700]You deal %d damage![/color]" % damage)
		
		if monster.current_hp <= 0:
			# Monster defeated!
			messages.append("[color=#00FF00]The %s is defeated![/color]" % monster.name)
			messages.append("[color=#FFD700]You gain %d experience![/color]" % monster.experience_reward)
			messages.append("[color=#FFD700]You gain %d gold![/color]" % monster.gold_reward)
			
			# Award experience and gold
			character.add_experience(monster.experience_reward)
			character.gold += monster.gold_reward
			
			return {
				"success": true,
				"messages": messages,
				"combat_ended": true,
				"victory": true
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
	
	# Flee chance based on speed difference
	var flee_chance = 50 + (character.get_stat("dexterity") - monster.speed) * 5
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

func process_monster_turn(combat: Dictionary) -> Dictionary:
	"""Process the monster's attack"""
	var character = combat.character
	var monster = combat.monster
	
	# Calculate monster hit
	var hit_roll = randi() % 20 + 1
	var hit_bonus = monster.strength / 2
	var hit_total = hit_roll + hit_bonus
	
	# Calculate player AC (with defend bonus if defending)
	var defense_bonus = combat.get("defense_bonus", 0) if combat.get("defending", false) else 0
	var player_ac = 10 + (character.get_stat("constitution") / 2) + defense_bonus
	
	# Clear defend status
	combat.defending = false
	combat.defense_bonus = 0
	
	if hit_total >= player_ac:
		# Monster hits
		var damage = calculate_monster_damage(monster, character)
		character.current_hp -= damage
		character.current_hp = max(0, character.current_hp)
		
		var msg = "[color=#FF6B6B]The %s attacks and deals %d damage![/color]" % [monster.name, damage]
		return {"success": true, "message": msg}
	else:
		# Monster misses
		var msg = "[color=#90EE90]The %s attacks but misses![/color]" % monster.name
		return {"success": true, "message": msg}

func calculate_damage(character: Character, monster: Dictionary) -> int:
	"""Calculate player damage to monster"""
	var base_damage = character.get_stat("strength")
	var damage_roll = (randi() % 6) + 1  # 1d6
	var total = base_damage + damage_roll
	
	# Reduce by monster defense
	var defense_reduction = monster.defense / 4
	total -= defense_reduction
	
	return max(1, total)  # Minimum 1 damage

func calculate_monster_damage(monster: Dictionary, character: Character) -> int:
	"""Calculate monster damage to player"""
	var base_damage = monster.strength
	var damage_roll = (randi() % 6) + 1  # 1d6
	var total = base_damage + damage_roll
	
	# Reduce by character defense
	var defense_reduction = character.get_stat("constitution") / 4
	total -= defense_reduction
	
	return max(1, total)  # Minimum 1 damage

func end_combat(peer_id: int, victory: bool):
	"""End combat and clean up"""
	if active_combats.has(peer_id):
		var combat = active_combats[peer_id]
		var character = combat.character
		
		# Mark character as not in combat
		character.in_combat = false
		
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
		"monster_name": monster.name,
		"monster_hp": monster.current_hp,
		"monster_max_hp": monster.max_hp,
		"monster_hp_percent": int((float(monster.current_hp) / monster.max_hp) * 100),
		"can_act": combat.player_can_act
	}

func generate_combat_start_message(character: Character, monster: Dictionary) -> String:
	"""Generate the initial combat message"""
	var msg = ""
	msg += "[b][color=#FF6B6B]═══ COMBAT! ═══[/color][/b]\n"
	msg += "[color=#FFD700]You encounter a %s (Level %d)![/color]\n" % [monster.name, monster.level]
	msg += "%s\n" % monster.description
	msg += "\n"
	msg += "[color=#87CEEB]Your HP:[/color] %d/%d\n" % [character.current_hp, character.max_hp]
	msg += "[color=#FF6B6B]Enemy HP:[/color] %d/%d\n" % [monster.current_hp, monster.max_hp]
	msg += "\n"
	msg += "[b]Commands:[/b] attack, defend, flee\n"
	return msg

func to_dict() -> Dictionary:
	return {
		"active_combats": active_combats.size()
	}
