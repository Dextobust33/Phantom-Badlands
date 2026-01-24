# quest_manager.gd
# Quest progress tracking, completion validation, and reward calculation
class_name QuestManager
extends Node

const QuestDatabaseScript = preload("res://shared/quest_database.gd")

var quest_db: Node = null

func _ready():
	quest_db = QuestDatabaseScript.new()
	add_child(quest_db)

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

func accept_quest(character: Character, quest_id: String, origin_x: int, origin_y: int) -> Dictionary:
	"""Accept a quest for the character. Returns {success: bool, message: String}"""
	var check = can_accept_quest(character, quest_id)
	if not check.can_accept:
		return {"success": false, "message": check.reason}

	var quest = quest_db.get_quest(quest_id)
	var target = quest.get("target", 1)

	# For kill count quests with separate kill_count field
	if quest.has("kill_count"):
		target = quest.kill_count

	if character.add_quest(quest_id, target, origin_x, origin_y):
		return {"success": true, "message": "Quest '%s' accepted!" % quest.name}

	return {"success": false, "message": "Failed to accept quest"}

# ===== PROGRESS TRACKING =====

func check_kill_progress(character: Character, monster_level: int, player_x: int, player_y: int,
						 hotzone_intensity: float, world_system: WorldSystem) -> Array:
	"""Check and update all kill-based quest progress. Returns array of {quest_id, progress, target, completed, message}"""
	var updates = []

	for quest_data in character.active_quests:
		var quest_id = quest_data.quest_id
		var quest = quest_db.get_quest(quest_id)
		if quest.is_empty():
			continue

		var quest_type = quest.get("type", -1)
		var should_update = false
		var intensity_to_add = 0.0

		match quest_type:
			QuestDatabaseScript.QuestType.KILL_ANY:
				should_update = true

			QuestDatabaseScript.QuestType.KILL_LEVEL, QuestDatabaseScript.QuestType.BOSS_HUNT:
				var min_level = quest.get("target", 1)
				if monster_level >= min_level:
					should_update = true

			QuestDatabaseScript.QuestType.HOTZONE_KILL:
				# Must be in a hotzone within max_distance of quest origin
				var max_distance = quest.get("max_distance", 50.0)
				var min_intensity = quest.get("min_intensity", 0.0)
				var origin_x = quest_data.get("origin_x", 0)
				var origin_y = quest_data.get("origin_y", 0)

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
		var quest = quest_db.get_quest(quest_id)
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

# ===== COMPLETION & REWARDS =====

func is_quest_complete(character: Character, quest_id: String) -> bool:
	"""Check if quest objectives are met"""
	var quest_data = character.get_quest_progress(quest_id)
	if quest_data.is_empty():
		return false
	return quest_data.progress >= quest_data.target

func calculate_rewards(character: Character, quest_id: String) -> Dictionary:
	"""Calculate quest rewards including hotzone multiplier. Returns {xp, gold, gems, multiplier}"""
	var quest = quest_db.get_quest(quest_id)
	if quest.is_empty():
		return {"xp": 0, "gold": 0, "gems": 0, "multiplier": 1.0}

	var base_rewards = quest.get("rewards", {"xp": 0, "gold": 0, "gems": 0})
	var multiplier = 1.0

	# Apply hotzone intensity multiplier for hotzone quests
	if quest.get("type", -1) == QuestDatabaseScript.QuestType.HOTZONE_KILL:
		var avg_intensity = character.get_average_hotzone_intensity(quest_id)
		# Multiplier: 1.5x at edge (intensity 0), up to 2.5x at center (intensity 1.0)
		multiplier = 1.5 + avg_intensity

	return {
		"xp": int(base_rewards.get("xp", 0) * multiplier),
		"gold": int(base_rewards.get("gold", 0) * multiplier),
		"gems": int(base_rewards.get("gems", 0) * multiplier),
		"multiplier": multiplier
	}

func turn_in_quest(character: Character, quest_id: String) -> Dictionary:
	"""Turn in a completed quest and grant rewards. Returns {success, message, rewards}"""
	if not is_quest_complete(character, quest_id):
		return {"success": false, "message": "Quest objectives not yet complete", "rewards": {}}

	var quest = quest_db.get_quest(quest_id)
	if quest.is_empty():
		return {"success": false, "message": "Quest not found", "rewards": {}}

	# Calculate and grant rewards
	var rewards = calculate_rewards(character, quest_id)

	# Apply rewards
	character.gold += rewards.gold
	character.gems += rewards.gems
	var level_result = character.add_experience(rewards.xp)

	# Complete the quest
	character.complete_quest(quest_id, quest.get("is_daily", false))

	var message = "Quest '%s' complete!" % quest.name
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

func format_quest_log(character: Character) -> String:
	"""Format the quest log for display"""
	var output = "[color=#FFD700]===== Active Quests (%d/%d) =====[/color]\n\n" % [
		character.get_active_quest_count(), Character.MAX_ACTIVE_QUESTS]

	if character.active_quests.is_empty():
		output += "[color=#888888]No active quests. Visit a Trading Post to accept quests.[/color]\n"
		return output

	var index = 1
	for quest_data in character.active_quests:
		var quest_id = quest_data.quest_id
		var quest = quest_db.get_quest(quest_id)
		if quest.is_empty():
			continue

		var progress = quest_data.progress
		var target = quest_data.target
		var is_complete = progress >= target

		# Quest header
		var daily_tag = " [color=#00FFFF][DAILY][/color]" if quest.get("is_daily", false) else ""
		output += "[%d] [color=#FFD700]%s[/color]%s\n" % [index, quest.name, daily_tag]

		# Description
		output += "    %s\n" % quest.description

		# Progress bar
		var progress_pct = min(1.0, float(progress) / float(target))
		var filled = int(progress_pct * 10)
		var empty = 10 - filled
		var bar = "[color=#00FF00]%s[/color][color=#444444]%s[/color]" % ["#".repeat(filled), "-".repeat(empty)]
		var status_color = "#00FF00" if is_complete else "#FFFFFF"
		output += "    Progress: [color=%s]%d/%d[/color] [%s]\n" % [status_color, progress, target, bar]

		# Rewards
		var rewards = quest.get("rewards", {})
		var reward_parts = []
		if rewards.get("xp", 0) > 0:
			reward_parts.append("[color=#9B59B6]%d XP[/color]" % rewards.xp)
		if rewards.get("gold", 0) > 0:
			reward_parts.append("[color=#FFD700]%d Gold[/color]" % rewards.gold)
		if rewards.get("gems", 0) > 0:
			reward_parts.append("[color=#00FFFF]%d Gems[/color]" % rewards.gems)
		if not reward_parts.is_empty():
			output += "    Rewards: %s\n" % ", ".join(reward_parts)

		# Hotzone bonus note
		if quest.get("type", -1) == QuestDatabaseScript.QuestType.HOTZONE_KILL:
			output += "    [color=#FF6600](1.5x-2.5x hotzone intensity bonus)[/color]\n"

		if is_complete:
			output += "    [color=#00FF00][Ready to turn in!][/color]\n"

		output += "\n"
		index += 1

	return output

func format_available_quests(quests: Array, character: Character) -> String:
	"""Format available quests for display at a Trading Post"""
	if quests.is_empty():
		return "[color=#888888]No quests available at this time.[/color]\n"

	var output = ""
	var index = 1
	for quest in quests:
		var daily_tag = " [color=#00FFFF][DAILY][/color]" if quest.get("is_daily", false) else ""
		output += "[%d] [color=#FFD700]%s[/color]%s\n" % [index, quest.name, daily_tag]
		output += "    %s\n" % quest.description

		# Rewards preview
		var rewards = quest.get("rewards", {})
		var reward_parts = []
		if rewards.get("xp", 0) > 0:
			reward_parts.append("%d XP" % rewards.xp)
		if rewards.get("gold", 0) > 0:
			reward_parts.append("%d Gold" % rewards.gold)
		if rewards.get("gems", 0) > 0:
			reward_parts.append("%d Gems" % rewards.gems)
		if not reward_parts.is_empty():
			output += "    [color=#90EE90]Rewards: %s[/color]\n" % ", ".join(reward_parts)

		output += "\n"
		index += 1

	return output
