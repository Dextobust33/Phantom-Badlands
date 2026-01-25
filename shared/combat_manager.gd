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

func apply_damage_variance(base_damage: int) -> int:
	"""Apply ±15% variance to damage to make combat less predictable"""
	# Variance range: 0.85 to 1.15 (±15%)
	var variance = 0.85 + (randf() * 0.30)
	return max(1, int(base_damage * variance))

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
		"summoner_triggered": false  # Already called reinforcements
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

	# Ethereal ability: 50% dodge chance for monster
	var ethereal_dodge = ABILITY_ETHEREAL in abilities and not is_vanished
	if ethereal_dodge and randi() % 100 < 50:
		messages.append("[color=#FF00FF]Your attack passes through the ethereal %s![/color]" % monster.name)
		combat.player_can_act = false
		return {"success": true, "messages": messages, "combat_ended": false}

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

		messages.append("[color=#00FF00]You attack the %s![/color]" % monster.name)
		messages.append("You deal [color=#FFFF00]%d[/color] damage!" % damage)

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
		messages.append("[color=#00FFFF]The gem bearer's hoard glitters![/color]")

	if gems_earned > 0:
		character.gems += gems_earned
		messages.append("[color=#00FFFF]You found %d gem%s![/color]" % [gems_earned, "s" if gems_earned > 1 else ""])

	# Wish granter ability: grant a powerful buff
	if ABILITY_WISH_GRANTER in abilities:
		# Grant a random powerful buff for several battles
		var wish_type = randi() % 4
		match wish_type:
			0:
				character.add_persistent_buff("damage", 50, 10)
				messages.append("[color=#FFD700]WISH GRANTED: +50%% damage for 10 battles![/color]")
			1:
				character.add_persistent_buff("defense", 50, 10)
				messages.append("[color=#FFD700]WISH GRANTED: +50%% defense for 10 battles![/color]")
			2:
				character.add_persistent_buff("speed", 30, 10)
				messages.append("[color=#FFD700]WISH GRANTED: +30 speed for 10 battles![/color]")
			3:
				# Heal to full and bonus max HP
				character.current_hp = character.max_hp
				messages.append("[color=#FFD700]WISH GRANTED: Full HP restored![/color]")

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

	return {
		"success": true,
		"messages": messages,
		"combat_ended": true,
		"victory": true,
		"monster_name": monster.name,
		"monster_level": monster.level,
		"flock_chance": flock,
		"dropped_items": dropped_items,
		"gems_earned": gems_earned,
		"summon_next_fight": combat.get("summon_next_fight", "")
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

	# Flee chance based on speed difference (includes speed buff and equipment bonus)
	var equipment_bonuses = character.get_equipment_bonuses()
	var player_speed = character.get_stat("dexterity") + character.get_buff_value("speed") + equipment_bonuses.speed
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
		messages.append("[color=#FF4444]You fail to escape![/color]")
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
	var player_wits = character.get_stat("wits")
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
	var expired_buffs = combat.character.tick_buffs()
	for buff in expired_buffs:
		var buff_name = buff.type.capitalize()
		result.messages.append("[color=#808080]Your %s buff has worn off.[/color]" % buff_name)
	combat.character.regenerate_energy()  # Energy regenerates each round

	return result

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
			character.current_mana -= bolt_amount

			# Calculate INT-based damage
			var int_stat = character.get_effective_stat("intelligence")
			var int_multiplier = 1.0 + (float(int_stat) / 50.0)  # INT 50 = 2x, INT 100 = 3x
			var base_damage = int(bolt_amount * int_multiplier)

			# Apply damage buff (from War Cry, potions, etc.)
			var damage_buff = character.get_buff_value("damage")
			if damage_buff > 0:
				base_damage = int(base_damage * (1.0 + damage_buff / 100.0))

			# Monster WIS reduces damage (up to 30% reduction)
			var monster_wis = monster.get("wisdom", monster.get("intelligence", 15))
			var wis_reduction = min(0.30, float(monster_wis) / 500.0)  # WIS 150 = 30% reduction
			var final_damage = apply_damage_variance(max(1, int(base_damage * (1.0 - wis_reduction))))

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
			if not character.use_mana(mana_cost):
				return {"success": false, "messages": ["[color=#FF4444]Not enough mana! (Need %d)[/color]" % mana_cost], "combat_ended": false, "skip_monster_turn": true}
			var base_damage = character.get_effective_stat("intelligence") * 2
			var damage_buff = character.get_buff_value("damage")
			var damage = apply_damage_variance(int(base_damage * (1.0 + damage_buff / 100.0)))
			monster.current_hp -= damage
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#FF00FF]You cast Blast![/color]")
			messages.append("[color=#00FFFF]The explosion deals %d damage![/color]" % damage)

		"forcefield":
			if not character.use_mana(mana_cost):
				return {"success": false, "messages": ["[color=#FF4444]Not enough mana! (Need %d)[/color]" % mana_cost], "combat_ended": false, "skip_monster_turn": true}
			combat["forcefield_charges"] = 2  # Block next 2 attacks
			messages.append("[color=#FF00FF]You cast Forcefield! (Blocks next 2 attacks)[/color]")

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
			if not character.use_mana(mana_cost):
				return {"success": false, "messages": ["[color=#FF4444]Not enough mana! (Need %d)[/color]" % mana_cost], "combat_ended": false, "skip_monster_turn": true}
			var base_damage = character.get_effective_stat("intelligence") * 5
			var damage_buff = character.get_buff_value("damage")
			var damage = apply_damage_variance(int(base_damage * (1.0 + damage_buff / 100.0)))
			monster.current_hp -= damage
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#FFD700][b]METEOR![/b][/color]")
			messages.append("[color=#FF4444]A massive meteor crashes down for %d damage![/color]" % damage)

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

	if not character.use_stamina(stamina_cost):
		return {"success": false, "messages": ["[color=#FF4444]Not enough stamina! (Need %d)[/color]" % stamina_cost], "combat_ended": false, "skip_monster_turn": true}

	# Use total attack (includes weapon) for physical abilities
	var total_attack = character.get_total_attack()

	# Get damage buff (War Cry, Berserk) to apply to ability damage
	var damage_buff = character.get_buff_value("damage")
	var damage_multiplier = 1.0 + (damage_buff / 100.0)

	match ability_name:
		"power_strike":
			var damage = apply_damage_variance(int(total_attack * 1.5 * damage_multiplier))
			monster.current_hp -= damage
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#FF4444]POWER STRIKE![/color]")
			messages.append("[color=#FFFF00]You deal %d damage![/color]" % damage)

		"war_cry":
			character.add_buff("damage", 25, 3)  # +25% damage for 3 rounds
			messages.append("[color=#FF4444]WAR CRY![/color]")
			messages.append("[color=#FFD700]+25%% damage for 3 rounds![/color]" % [])

		"shield_bash":
			var damage = apply_damage_variance(int(total_attack * damage_multiplier))
			monster.current_hp -= damage
			monster.current_hp = max(0, monster.current_hp)
			combat["monster_stunned"] = true  # Enemy skips next turn
			messages.append("[color=#FF4444]SHIELD BASH![/color]")
			messages.append("[color=#FFFF00]You deal %d damage and stun the enemy![/color]" % damage)

		"cleave":
			var damage = apply_damage_variance(int(total_attack * 2 * damage_multiplier))
			monster.current_hp -= damage
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#FF4444]CLEAVE![/color]")
			messages.append("[color=#FFFF00]Your massive swing deals %d damage![/color]" % damage)

		"berserk":
			character.add_buff("damage", 100, 3)  # +100% damage for 3 rounds
			character.add_buff("defense_penalty", -50, 3)  # -50% defense for 3 rounds
			messages.append("[color=#FF0000][b]BERSERK![/b][/color]")
			messages.append("[color=#FFD700]+100%% damage, -50%% defense for 3 rounds![/color]" % [])

		"iron_skin":
			character.add_buff("damage_reduction", 50, 3)  # Block 50% damage for 3 rounds
			messages.append("[color=#AAAAAA]IRON SKIN![/color]")
			messages.append("[color=#00FF00]Block 50%% damage for 3 rounds![/color]" % [])

		"devastate":
			var damage = apply_damage_variance(int(total_attack * 4 * damage_multiplier))
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
			messages.append("[color=#FFA500]Intelligence:[/color] %d" % monster.get("intelligence", 15))
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
				var stolen_gold = wits * 10
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
			# Ambush uses weapon damage + wits bonus, affected by damage buffs
			var base_damage = character.get_total_attack()
			var wits_bonus = character.get_stat("wits") / 2
			var damage_buff = character.get_buff_value("damage")
			var damage_multiplier = 1.0 + (damage_buff / 100.0)
			var damage = apply_damage_variance(int((base_damage + wits_bonus) * 1.5 * damage_multiplier))
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
			# Instant win + double rewards
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
		character.current_mana = min(character.max_mana, character.current_mana + mana_amount)
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

	# Check if monster is stunned (Shield Bash)
	if combat.get("monster_stunned", false):
		combat.erase("monster_stunned")
		return {"success": true, "message": "[color=#808080]The %s is stunned and cannot act![/color]" % monster.name}

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

	# Check for Forcefield (blocks attacks completely)
	var forcefield = combat.get("forcefield_charges", 0)
	if forcefield > 0:
		combat["forcefield_charges"] = forcefield - 1
		var charges_left = forcefield - 1
		if charges_left > 0:
			messages.append("[color=#FF00FF]Your Forcefield absorbs the attack! (%d charge%s left)[/color]" % [charges_left, "s" if charges_left > 1 else ""])
		else:
			messages.append("[color=#FF00FF]Your Forcefield absorbs the attack! (Shield breaks)[/color]")
		return {"success": true, "message": "\n".join(messages)}

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
		character.current_hp -= total_damage

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

	# Summoner ability: call reinforcements (once per combat)
	if ABILITY_SUMMONER in abilities and not combat.get("summoner_triggered", false):
		if randi() % 100 < 20:  # 20% chance
			combat["summoner_triggered"] = true
			combat["summon_next_fight"] = monster.name  # Server will handle spawning
			messages.append("[color=#FF4444]The %s calls for reinforcements![/color]" % monster.name)

	return {"success": true, "message": "\n".join(messages)}

func calculate_damage(character: Character, monster: Dictionary) -> int:
	"""Calculate player damage to monster (includes equipment, buffs, and class advantage)"""
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

	# Apply class advantage multiplier
	var affinity = monster.get("class_affinity", 0)
	var class_multiplier = _get_class_advantage_multiplier(affinity, character.class_type)
	total = int(total * class_multiplier)

	return max(1, total)  # Minimum 1 damage

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
		"monster_name_color": name_color,  # Color based on class affinity
		"monster_affinity": affinity,
		"can_act": combat.player_can_act,
		# Combat status effects (now tracked on character for persistence)
		"poison_active": character.poison_active,
		"poison_damage": character.poison_damage,
		"poison_turns_remaining": character.poison_turns_remaining,
		# Outsmart tracking
		"outsmart_failed": combat.get("outsmart_failed", false)
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
		var lines = art_map[monster_name]
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

	# Get class affinity color
	var affinity = monster.get("class_affinity", 0)  # 0 = NEUTRAL
	var name_color = _get_affinity_color(affinity)

	# Build encounter message with colored monster name (color indicates class affinity)
	var msg = bordered_art + "\n[color=#FFD700]You encounter a [/color][color=%s]%s[/color][color=#FFD700] (Lvl %d)![/color]" % [name_color, monster.name, monster.level]

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
