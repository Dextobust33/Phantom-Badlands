# quest_manager.gd
# Quest progress tracking, completion validation, and reward calculation
class_name QuestManager
extends Node

const QuestDatabaseScript = preload("res://shared/quest_database.gd")
const TradingPostDatabaseScript = preload("res://shared/trading_post_database.gd")

var quest_db: Node = null
var trading_post_db: Node = null

func _ready():
	quest_db = QuestDatabaseScript.new()
	add_child(quest_db)
	trading_post_db = TradingPostDatabaseScript.new()
	add_child(trading_post_db)

# ===== QUEST ACCEPTANCE =====

func can_accept_quest(character: Character, quest_id: String) -> Dictionary:
	"""Check if character can accept a quest. Returns {can_accept: bool, reason: String}"""
	if not character.can_accept_quest():
		return {"can_accept": false, "reason": "You have too many active quests (max %d)" % Character.MAX_ACTIVE_QUESTS}

	if character.has_quest(quest_id):
		return {"can_accept": false, "reason": "You already have this quest"}

	var quest = quest_db.get_quest(quest_id)
	if quest.is_empty():
		return {"can_accept": false, "reason": "Quest not found"}

	if not quest.is_daily and character.has_completed_quest(quest_id):
		return {"can_accept": false, "reason": "You have already completed this quest"}

	if quest.is_daily and not character.can_accept_daily_quest(quest_id):
		return {"can_accept": false, "reason": "This daily quest is on cooldown"}

	if quest.prerequisite != "" and not character.has_completed_quest(quest.prerequisite):
		var prereq = quest_db.get_quest(quest.prerequisite)
		var prereq_name = prereq.get("name", quest.prerequisite)
		return {"can_accept": false, "reason": "You must complete '%s' first" % prereq_name}

	return {"can_accept": true, "reason": ""}

func accept_quest(character: Character, quest_id: String, origin_x: int, origin_y: int, description: String = "", player_level: int = 1, completed_at_post: int = 0) -> Dictionary:
	"""Accept a quest for the character. Returns {success: bool, message: String}"""
	var check = can_accept_quest(character, quest_id)
	if not check.can_accept:
		return {"success": false, "message": check.reason}

	var quest = quest_db.get_quest(quest_id, player_level, completed_at_post, character.name)
	var quest_type = quest.get("type", -1)
	var target = quest.get("target", 1)

	# For kill count quests with separate kill_count field
	if quest.has("kill_count"):
		target = quest.kill_count
	# KILL_LEVEL and BOSS_HUNT use target for level threshold, default to 1 kill
	elif quest_type == QuestDatabaseScript.QuestType.KILL_LEVEL or quest_type == QuestDatabaseScript.QuestType.BOSS_HUNT:
		target = 1  # Kill 1 monster of the required level

	# Use scaled description if provided, otherwise use quest's base description
	var quest_description = description if not description.is_empty() else quest.get("description", "")

	# Build extra data to store with quest (prevents regeneration issues for random quests)
	var extra_data = {
		"quest_name": quest.get("name", "Unknown Quest"),
		"quest_type": quest_type
	}
	# Store rewards at accept time so they don't change on turn-in
	var base_rewards = quest.get("rewards", {"xp": 0, "valor": 0})
	extra_data["stored_rewards"] = {
		"xp": base_rewards.get("xp", 0),
		"valor": base_rewards.get("valor", 0)
	}
	# For dungeon quests, store the specific dungeon type
	if quest_type == QuestDatabaseScript.QuestType.DUNGEON_CLEAR:
		extra_data["dungeon_type"] = quest.get("dungeon_type", "")
	# For monster type quests, store the specific monster type and level requirement
	if quest_type == QuestDatabaseScript.QuestType.KILL_TYPE:
		extra_data["monster_type"] = quest.get("monster_type", "")
		if quest.has("min_monster_level"):
			extra_data["min_monster_level"] = quest.get("min_monster_level", 0)
	# For KILL_TIER quests, store the required tier
	if quest_type == QuestDatabaseScript.QuestType.KILL_TIER:
		extra_data["required_tier"] = quest.get("required_tier", 1)
	# For exploration quests, store destinations for turn-in at destination
	if quest_type == QuestDatabaseScript.QuestType.EXPLORATION:
		extra_data["destinations"] = quest.get("destinations", [])
	# For BOSS_HUNT quests with named bounty, store bounty fields
	if quest_type == QuestDatabaseScript.QuestType.BOSS_HUNT:
		if quest.has("bounty_name"):
			extra_data["bounty_name"] = quest.get("bounty_name", "")
			extra_data["bounty_monster_type"] = quest.get("bounty_monster_type", "")
			extra_data["bounty_level"] = quest.get("bounty_level", 1)
			extra_data["bounty_x"] = quest.get("bounty_x", 0)
			extra_data["bounty_y"] = quest.get("bounty_y", 0)
	# For RESCUE quests, store NPC type, dungeon type, and rescue floor
	if quest_type == QuestDatabaseScript.QuestType.RESCUE:
		extra_data["rescue_npc_type"] = quest.get("rescue_npc_type", "merchant")
		extra_data["dungeon_type"] = quest.get("dungeon_type", "")
		extra_data["rescue_floor"] = quest.get("rescue_floor", 1)

	# For GATHER quests, store gathering job type
	if quest_type == QuestDatabaseScript.QuestType.GATHER:
		extra_data["gather_job"] = quest.get("gather_job", "")

	# Store character name for per-character quest regeneration
	extra_data["character_name"] = character.name

	if character.add_quest(quest_id, target, origin_x, origin_y, quest_description, player_level, completed_at_post, extra_data):
		return {"success": true, "message": "Quest '%s' accepted!" % quest.name}

	return {"success": false, "message": "Failed to accept quest"}

# ===== PROGRESS TRACKING =====

func check_kill_progress(character: Character, monster_level: int, player_x: int, player_y: int,
						 hotzone_intensity: float, world_system: WorldSystem, killed_monster_name: String = "") -> Array:
	"""Check and update all kill-based quest progress. Returns array of {quest_id, progress, target, completed, message}"""
	var updates = []

	for quest_data in character.active_quests:
		var quest_id = quest_data.quest_id
		# Use stored player level for proper dynamic quest regeneration
		var player_level_at_accept = quest_data.get("player_level_at_accept", 1)
		var completed_at_post = quest_data.get("completed_at_post", 0)
		var char_name = quest_data.get("character_name", "")
		var quest = quest_db.get_quest(quest_id, player_level_at_accept, completed_at_post, char_name)
		if quest.is_empty():
			continue

		var quest_type = quest.get("type", -1)
		var should_update = false
		var intensity_to_add = 0.0

		match quest_type:
			QuestDatabaseScript.QuestType.KILL_ANY:
				should_update = true

			QuestDatabaseScript.QuestType.KILL_TYPE:
				# Must kill specific monster type, and optionally meet level requirement
				var required_type = quest.get("monster_type", "")
				var min_type_level = quest.get("min_monster_level", 0)
				if required_type != "" and killed_monster_name == required_type:
					# Check stored min_monster_level (from quest accept extra_data)
					var stored_min_level = quest_data.get("min_monster_level", min_type_level)
					if stored_min_level > 0 and monster_level < stored_min_level:
						pass  # Monster too low level
					else:
						should_update = true

			QuestDatabaseScript.QuestType.KILL_LEVEL:
				var min_level = quest.get("target", 1)
				if monster_level >= min_level:
					should_update = true

			QuestDatabaseScript.QuestType.BOSS_HUNT:
				# Named bounty: check monster name matches bounty_name
				var bounty_name = quest_data.get("bounty_name", quest.get("bounty_name", ""))
				if bounty_name != "":
					if killed_monster_name == bounty_name:
						should_update = true
				else:
					# Legacy boss hunt: check level threshold
					var min_level_bh = quest.get("target", 1)
					if monster_level >= min_level_bh:
						should_update = true

			QuestDatabaseScript.QuestType.KILL_TIER:
				# Must kill a monster whose tier is >= required_tier
				var required_tier = quest_data.get("required_tier", quest.get("required_tier", 1))
				var killed_tier = _get_tier_from_level(monster_level)
				if killed_tier >= required_tier:
					should_update = true

			QuestDatabaseScript.QuestType.HOTZONE_KILL:
				# Must be in a hotzone within max_distance of quest origin
				var max_distance = quest.get("max_distance", 50.0)
				var min_intensity = quest.get("min_intensity", 0.0)
				var min_monster_level = quest.get("min_monster_level", 1)
				var origin_x = quest_data.get("origin_x", 0)
				var origin_y = quest_data.get("origin_y", 0)

				# Check if monster meets minimum level requirement
				if monster_level < min_monster_level:
					continue

				# Check if in a hotzone
				if hotzone_intensity > 0:
					# Check distance from quest origin
					var dist = sqrt(float((player_x - origin_x) * (player_x - origin_x) +
										   (player_y - origin_y) * (player_y - origin_y)))
					if dist <= max_distance and hotzone_intensity >= min_intensity:
						should_update = true
						intensity_to_add = hotzone_intensity

		if should_update:
			var result = character.update_quest_progress(quest_id, 1, intensity_to_add)
			if result.updated:
				var message = "Quest '%s': %d/%d" % [quest.name, result.progress, result.target]
				if result.completed:
					message = "[color=#00FF00]Quest '%s' complete! Return to turn in.[/color]" % quest.name
				updates.append({
					"quest_id": quest_id,
					"progress": result.progress,
					"target": result.target,
					"completed": result.completed,
					"message": message
				})

	return updates

func check_exploration_progress(character: Character, player_x: int, player_y: int,
								world_system: WorldSystem) -> Array:
	"""Check and update exploration quest progress. Returns array of updates."""
	var updates = []

	# Check if player is at a Trading Post
	if not world_system.is_trading_post_tile(player_x, player_y):
		return updates

	var tp = world_system.get_trading_post_at(player_x, player_y)
	if tp.is_empty():
		return updates

	var tp_id = tp.get("id", "")

	for quest_data in character.active_quests:
		var quest_id = quest_data.quest_id
		var char_name = quest_data.get("character_name", "")
		var quest = quest_db.get_quest(quest_id, -1, 0, char_name)
		if quest.is_empty():
			continue

		if quest.get("type", -1) != QuestDatabaseScript.QuestType.EXPLORATION:
			continue

		var destinations = quest.get("destinations", [])
		if tp_id in destinations:
			# Check if already visited (using a visited tracking)
			# Store visited in quest_data dynamically
			var visited = quest_data.get("visited", [])
			if tp_id not in visited:
				visited.append(tp_id)
				quest_data["visited"] = visited

				var result = character.update_quest_progress(quest_id, 1)
				if result.updated:
					var message = "Discovered %s! Quest '%s': %d/%d" % [tp.name, quest.name, result.progress, result.target]
					if result.completed:
						message = "[color=#00FF00]Quest '%s' complete! Return to turn in.[/color]" % quest.name
					updates.append({
						"quest_id": quest_id,
						"progress": result.progress,
						"target": result.target,
						"completed": result.completed,
						"message": message
					})

	return updates

func check_dungeon_progress(character: Character, dungeon_type: String) -> Array:
	"""Check and update dungeon quest progress when a dungeon is completed. Returns array of updates."""
	var updates = []

	for quest_data in character.active_quests:
		var quest_id = quest_data.quest_id
		# Use stored player level for proper dynamic quest regeneration
		var player_level_at_accept = quest_data.get("player_level_at_accept", 1)
		var completed_at_post = quest_data.get("completed_at_post", 0)
		var char_name = quest_data.get("character_name", "")
		var quest = quest_db.get_quest(quest_id, player_level_at_accept, completed_at_post, char_name)

		# Get quest type from stored data (fallback) or regenerated quest
		var quest_type = quest_data.get("quest_type", quest.get("type", -1))
		if quest_type != QuestDatabaseScript.QuestType.DUNGEON_CLEAR:
			continue

		# Check if this dungeon type matches the quest requirement
		# Get dungeon_type from stored quest_data first (prevents regeneration issues),
		# then fall back to quest definition
		var required_dungeon = quest_data.get("dungeon_type", quest.get("dungeon_type", ""))
		# Empty dungeon_type means any dungeon counts
		if required_dungeon == "" or required_dungeon == dungeon_type:
			var result = character.update_quest_progress(quest_id, 1)
			if result.updated:
				# Use stored quest name if available
				var quest_name = quest_data.get("quest_name", quest.get("name", "Unknown Quest"))
				var message = "Dungeon cleared! Quest '%s': %d/%d" % [quest_name, result.progress, result.target]
				if result.completed:
					message = "[color=#00FF00]Quest '%s' complete! Return to turn in.[/color]" % quest_name
				updates.append({
					"quest_id": quest_id,
					"progress": result.progress,
					"target": result.target,
					"completed": result.completed,
					"message": message
				})

	return updates

# ===== COMPLETION & REWARDS =====

func is_quest_complete(character: Character, quest_id: String) -> bool:
	"""Check if quest objectives are met"""
	var quest_data = character.get_quest_progress(quest_id)
	if quest_data.is_empty():
		return false
	return quest_data.progress >= quest_data.target

func calculate_rewards(character: Character, quest_id: String) -> Dictionary:
	"""Calculate quest rewards including hotzone multiplier. Returns {xp, valor, multiplier}"""
	# Use stored rewards if available (stored at accept time to prevent regeneration mismatch)
	var quest_data = character.get_quest_progress(quest_id)
	var stored_rewards = quest_data.get("stored_rewards", {})

	var base_rewards: Dictionary
	var quest_type: int = -1

	if not stored_rewards.is_empty():
		# Use rewards locked in at accept time
		base_rewards = stored_rewards
		quest_type = quest_data.get("quest_type", -1)
		# Migration: old quests stored "gems" — convert to "valor"
		if not base_rewards.has("valor") and base_rewards.has("gems"):
			base_rewards["valor"] = base_rewards["gems"]
	else:
		# Fallback for quests accepted before this fix: regenerate with stored params
		var player_level_at_accept = quest_data.get("player_level_at_accept", 1)
		var completed_at_post = quest_data.get("completed_at_post", 0)
		var char_name = quest_data.get("character_name", "")
		var quest = quest_db.get_quest(quest_id, player_level_at_accept, completed_at_post, char_name)
		if quest.is_empty():
			return {"xp": 0, "valor": 0, "multiplier": 1.0}
		base_rewards = quest.get("rewards", {"xp": 0, "valor": 0})
		quest_type = quest.get("type", -1)

	var multiplier = 1.0

	# Apply hotzone intensity multiplier for hotzone quests
	if quest_type == QuestDatabaseScript.QuestType.HOTZONE_KILL:
		var avg_intensity = character.get_average_hotzone_intensity(quest_id)
		# Multiplier: 1.5x at edge (intensity 0), up to 2.5x at center (intensity 1.0)
		multiplier = 1.5 + avg_intensity

	return {
		"xp": int(base_rewards.get("xp", 0) * multiplier),
		"valor": int(base_rewards.get("valor", 0) * multiplier),
		"multiplier": multiplier
	}

func turn_in_quest(character: Character, quest_id: String) -> Dictionary:
	"""Turn in a completed quest and grant rewards. Returns {success, message, rewards}"""
	if not is_quest_complete(character, quest_id):
		return {"success": false, "message": "Quest objectives not yet complete", "rewards": {}}

	# Get stored quest data for name and is_daily
	var quest_data = character.get_quest_progress(quest_id)
	var quest_name = quest_data.get("quest_name", "")
	var is_daily = false

	# Regenerate quest with stored params for metadata (is_daily, etc.)
	var player_level_at_accept = quest_data.get("player_level_at_accept", 1)
	var completed_at_post = quest_data.get("completed_at_post", 0)
	var char_name = quest_data.get("character_name", "")
	var quest = quest_db.get_quest(quest_id, player_level_at_accept, completed_at_post, char_name)
	if quest.is_empty() and quest_name.is_empty():
		return {"success": false, "message": "Quest not found", "rewards": {}}
	if quest_name.is_empty():
		quest_name = quest.get("name", "Unknown Quest")
	is_daily = quest.get("is_daily", false)

	# Calculate and grant rewards (uses stored rewards if available)
	var rewards = calculate_rewards(character, quest_id)

	# Apply rewards — XP directly, valor awarded by server via persistence
	var level_result = character.add_experience(rewards.xp)

	# Complete the quest
	character.complete_quest(quest_id, is_daily)

	var message = "Quest '%s' complete!" % quest_name
	if rewards.multiplier > 1.0:
		message += " (%.1fx hotzone bonus!)" % rewards.multiplier

	return {
		"success": true,
		"message": message,
		"rewards": rewards,
		"leveled_up": level_result.leveled_up,
		"new_level": level_result.new_level
	}

# ===== QUEST LOG DISPLAY =====

func format_quest_log(character: Character, extra_info: Dictionary = {}) -> String:
	"""Format the quest log for display. extra_info is optional dict mapping quest_id to additional text."""
	var output = "[color=#FFD700]===== Active Quests (%d/%d) =====[/color]\n\n" % [
		character.get_active_quest_count(), Character.MAX_ACTIVE_QUESTS]

	if character.active_quests.is_empty():
		output += "[color=#808080]No active quests. Visit a Trading Post to accept quests.[/color]\n"
		return output

	var index = 1
	for quest_data in character.active_quests:
		var quest_id = quest_data.quest_id
		# Use stored player level and completion count for proper dynamic quest regeneration
		var player_level_at_accept = quest_data.get("player_level_at_accept", 1)
		var completed_at_post = quest_data.get("completed_at_post", 0)
		var char_name = quest_data.get("character_name", "")
		var quest = quest_db.get_quest(quest_id, player_level_at_accept, completed_at_post, char_name)
		if quest.is_empty():
			continue

		var progress = quest_data.progress
		var target = quest_data.target
		var is_complete = progress >= target

		# Quest header - use stored quest_name if available (prevents regeneration mismatch)
		var quest_name = quest_data.get("quest_name", "")
		if quest_name.is_empty():
			quest_name = quest.get("name", "Unknown Quest")
		var daily_tag = " [color=#00FFFF][DAILY][/color]" if quest.get("is_daily", false) else ""
		output += "[%d] [color=#FFD700]%s[/color]%s\n" % [index, quest_name, daily_tag]

		# Description - use stored description if available (scaled at accept time)
		var description = quest_data.get("description", "")
		if description.is_empty():
			description = quest.get("description", "")
		output += "    %s\n" % description

		# Add any extra info for this quest (e.g., dungeon directions)
		if extra_info.has(quest_id):
			output += "    %s\n" % extra_info[quest_id]

		# Progress bar
		var progress_pct = min(1.0, float(progress) / float(target))
		var filled = int(progress_pct * 10)
		var empty = 10 - filled
		var bar = "[color=#00FF00]%s[/color][color=#444444]%s[/color]" % ["#".repeat(filled), "-".repeat(empty)]
		var status_color = "#00FF00" if is_complete else "#FFFFFF"
		output += "    Progress: [color=%s]%d/%d[/color] [%s]\n" % [status_color, progress, target, bar]

		# Rewards - use stored rewards if available, fall back to regenerated quest
		var stored_rewards = quest_data.get("stored_rewards", {})
		var rewards = stored_rewards if not stored_rewards.is_empty() else quest.get("rewards", {})
		var reward_parts = []
		if rewards.get("xp", 0) > 0:
			reward_parts.append("[color=#FF00FF]%d XP[/color]" % rewards.xp)
		# Migration: support old "gems" key from pre-existing quests
		var valor_amount = rewards.get("valor", rewards.get("gems", 0))
		if valor_amount > 0:
			reward_parts.append("[color=#00FFFF]%d Valor[/color]" % valor_amount)
		if not reward_parts.is_empty():
			output += "    Rewards: %s\n" % ", ".join(reward_parts)

		# Turn-in location
		var origin_x = quest_data.get("origin_x", 0)
		var origin_y = quest_data.get("origin_y", 0)
		var turn_in_post = trading_post_db.get_trading_post_at(origin_x, origin_y)
		if not turn_in_post.is_empty():
			output += "    Turn in: [color=#00FFFF]%s[/color] (%d, %d)\n" % [turn_in_post.get("name", "Unknown"), origin_x, origin_y]

		# Hotzone requirements and bonus note
		if quest.get("type", -1) == QuestDatabaseScript.QuestType.HOTZONE_KILL:
			var min_monster_level = quest.get("min_monster_level", 1)
			if min_monster_level > 1:
				output += "    [color=#FFA500]Requires monsters level %d+[/color]\n" % min_monster_level
			output += "    [color=#FF6600](1.5x-2.5x hotzone intensity bonus)[/color]\n"

		# Bounty location info
		var bounty_name = quest_data.get("bounty_name", quest.get("bounty_name", ""))
		if bounty_name != "":
			var bx = quest_data.get("bounty_x", quest.get("bounty_x", 0))
			var by = quest_data.get("bounty_y", quest.get("bounty_y", 0))
			output += "    [color=#FF4500]Target: %s — near (%d, %d)[/color]\n" % [bounty_name, bx, by]

		# Rescue quest info
		if quest.get("type", -1) == QuestDatabaseScript.QuestType.RESCUE:
			var rescue_npc = quest_data.get("rescue_npc_type", quest.get("rescue_npc_type", ""))
			var rescue_floor = quest_data.get("rescue_floor", quest.get("rescue_floor", 0))
			if rescue_npc != "":
				output += "    [color=#00FF00]Rescue: %s on floor %d[/color]\n" % [rescue_npc.capitalize(), rescue_floor + 1]

		if is_complete:
			output += "    [color=#00FF00][Ready to turn in!][/color]\n"

		output += "\n"
		index += 1

	return output

func format_available_quests(quests: Array, character: Character) -> String:
	"""Format available quests for display at a Trading Post"""
	if quests.is_empty():
		return "[color=#808080]No quests available at this time.[/color]\n"

	var output = ""
	var index = 1
	for quest in quests:
		var daily_tag = " [color=#00FFFF][DAILY][/color]" if quest.get("is_daily", false) else ""
		output += "[%d] [color=#FFD700]%s[/color]%s\n" % [index, quest.name, daily_tag]
		output += "    %s\n" % quest.description

		# Rewards preview
		var rewards = quest.get("rewards", {})
		var base_xp = rewards.get("xp", 0)
		# Migration: support old "gems" key
		var base_valor = rewards.get("valor", rewards.get("gems", 0))

		var reward_parts = []
		if base_xp > 0:
			reward_parts.append("%d XP" % base_xp)
		if base_valor > 0:
			reward_parts.append("%d Valor" % base_valor)
		if not reward_parts.is_empty():
			output += "    [color=#00FF00]Rewards: %s[/color]\n" % ", ".join(reward_parts)

		# Show hotzone requirements and bonus potential for hotzone quests
		if quest.get("type", -1) == QuestDatabaseScript.QuestType.HOTZONE_KILL:
			var min_monster_level = quest.get("min_monster_level", 1)
			if min_monster_level > 1:
				output += "    [color=#FFA500]Requires monsters level %d+[/color]\n" % min_monster_level
			var max_xp = int(base_xp * 2.5)
			var max_valor = int(base_valor * 2.5) if base_valor > 0 else 0
			var bonus_parts = []
			if max_xp > base_xp:
				bonus_parts.append("up to %d XP" % max_xp)
			if max_valor > base_valor:
				bonus_parts.append("up to %d Valor" % max_valor)
			if not bonus_parts.is_empty():
				output += "    [color=#FF6600]Hotzone Bonus: %s[/color]\n" % ", ".join(bonus_parts)

		output += "\n"
		index += 1

	return output

# ===== HELPERS =====

func check_rescue_progress(character: Character, quest_id: String) -> Dictionary:
	"""Mark a rescue quest as complete when NPC is found. Returns {updated, progress, target, completed, message}."""
	var quest_data = character.get_quest_progress(quest_id)
	if quest_data.is_empty():
		return {"updated": false}

	var quest_type = quest_data.get("quest_type", -1)
	if quest_type != QuestDatabaseScript.QuestType.RESCUE:
		return {"updated": false}

	var result = character.update_quest_progress(quest_id, 1)
	if result.updated:
		var quest_name = quest_data.get("quest_name", "Rescue Quest")
		var message = "[color=#00FF00]Quest '%s' complete! Return to turn in.[/color]" % quest_name
		return {
			"updated": true,
			"quest_id": quest_id,
			"progress": result.progress,
			"target": result.target,
			"completed": result.completed,
			"message": message
		}
	return {"updated": false}

func check_gathering_progress(character: Character, gather_job: String) -> Array:
	"""Check and update gathering quest progress. Returns array of {quest_id, progress, target, completed, message}"""
	var updates = []

	for quest_data in character.active_quests:
		var quest_id = quest_data.quest_id
		var quest_type = quest_data.get("quest_type", -1)
		if quest_type != QuestDatabaseScript.QuestType.GATHER:
			continue

		var required_job = quest_data.get("gather_job", "")
		if required_job != "" and required_job != gather_job:
			continue

		var result = character.update_quest_progress(quest_id, 1)
		if result.updated:
			var quest_name = quest_data.get("quest_name", "Gathering Quest")
			var message = "Quest '%s': %d/%d" % [quest_name, result.progress, result.target]
			if result.completed:
				message = "[color=#00FF00]Quest '%s' complete! Return to turn in.[/color]" % quest_name
			updates.append({
				"quest_id": quest_id,
				"progress": result.progress,
				"target": result.target,
				"completed": result.completed,
				"message": message
			})

	return updates

func _get_tier_from_level(level: int) -> int:
	"""Map a monster level to its tier using TIER_LEVEL_RANGES from quest_database."""
	for tier in range(9, 0, -1):
		var range_data = QuestDatabaseScript.TIER_LEVEL_RANGES.get(tier, {})
		if level >= range_data.get("min", 99999):
			return tier
	return 1
