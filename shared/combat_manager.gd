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

	# Hit chance: 95% base, -1% per 2 monster levels above player (minimum 70%)
	var player_level = character.level
	var monster_level = monster.level
	var level_diff = max(0, monster_level - player_level)
	var hit_chance = 95 - (level_diff / 2)
	hit_chance = max(70, hit_chance)  # Never below 70%

	var hit_roll = randi() % 100

	if hit_roll < hit_chance:
		# Hit!
		var damage = calculate_damage(character, monster)
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

	var hit_roll = randi() % 100

	if hit_roll < hit_chance:
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
	"""Calculate player damage to monster (includes equipment and buff bonuses)"""
	# Use total attack which includes equipment
	var base_damage = character.get_total_attack()

	# Add strength buff bonus
	var strength_buff = character.get_buff_value("strength")
	base_damage += strength_buff

	var damage_roll = (randi() % 6) + 1  # 1d6
	var raw_damage = base_damage + damage_roll

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
