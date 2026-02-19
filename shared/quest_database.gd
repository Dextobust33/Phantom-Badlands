# quest_database.gd
# Quest definitions and constants
class_name QuestDatabase
extends Node

const DungeonDatabaseScript = preload("res://shared/dungeon_database.gd")

# Quest type constants
enum QuestType {
	KILL_ANY,           # 0 - Kill X monsters of any type
	KILL_TYPE,          # 1 - LEGACY: kept for saved quest data compatibility
	KILL_LEVEL,         # 2 - LEGACY: kept for saved quest data compatibility
	HOTZONE_KILL,       # 3 - Kill X monsters in a hotzone within Y distance
	EXPLORATION,        # 4 - Visit specific coordinates/locations
	BOSS_HUNT,          # 5 - Defeat a high-level monster
	DUNGEON_CLEAR,      # 6 - Clear a specific dungeon type (defeat boss)
	KILL_TIER,          # 7 - Kill X monsters of tier N or higher
	RESCUE,             # 8 - Rescue NPC from dungeon
	GATHER              # 9 - Gather X materials through fishing/mining/logging/foraging
}

# Quest data structure:
# {
#   "id": String,
#   "name": String,
#   "description": String,
#   "type": QuestType,
#   "trading_post": String (ID of origin trading post),
#   "target": int (kill count or level threshold),
#   "max_distance": float (for hotzone quests, distance from origin),
#   "min_intensity": float (for high-intensity hotzone quests),
#   "destination": Vector2i (for exploration quests),
#   "destination_post": String (for exploration quests targeting a Trading Post),
#   "rewards": {xp: int, gold: int, valor: int},
#   "is_daily": bool,
#   "prerequisite": String (quest_id that must be completed first, or empty)
# }

# Legacy static quests removed — all quests are now dynamically generated per-post per-day
const QUESTS = {}

# NOTE: ~780 lines of static quest definitions were removed. All quests now dynamically
# generated per-post per-day. Old enum values KILL_TYPE=1, KILL_LEVEL=2 preserved for
# saved quest backward compatibility. Old dynamic quest IDs (_dynamic_) still regenerated.

func get_quest(quest_id: String, player_level: int = -1, quests_completed_at_post: int = 0, character_name: String = "") -> Dictionary:
	"""Get quest data by ID. Returns empty dict if not found.
	For dynamic quests, pass player_level and quests_completed_at_post to get accurate scaling.
	For static quests with player_level provided, also applies requirement scaling to match display."""
	if QUESTS.has(quest_id):
		var quest = QUESTS[quest_id].duplicate(true)
		# Randomize target if quest has a range, using character-specific seed
		if quest.has("target_min") and quest.has("target_max"):
			var rng = RandomNumberGenerator.new()
			rng.seed = hash(quest_id + character_name)
			quest["target"] = rng.randi_range(quest.target_min, quest.target_max)
		# Format description with target count if it has %d placeholder
		if quest.has("description") and "%d" in quest.description:
			quest.description = quest.description % quest.target
		# Scale rewards based on trading post area level
		var area_level = _get_area_level_for_post(quest.trading_post)
		# If player_level provided, also scale requirements to match what was displayed
		if player_level > 0:
			quest = _scale_quest_for_player(quest, player_level, quests_completed_at_post, area_level, character_name)
		else:
			quest = _scale_quest_rewards(quest, area_level)
		return quest

	# Handle daily quest IDs (format: postid_daily_YYYYMMDD_index)
	if "_daily_" in quest_id:
		return _regenerate_daily_quest(quest_id, player_level, quests_completed_at_post, character_name)

	# Handle legacy dynamic quest IDs (format: postid_dynamic_tier_index)
	if "_dynamic_" in quest_id:
		return _regenerate_dynamic_quest(quest_id, player_level, quests_completed_at_post)

	# Handle progression quest IDs (format: progression_to_postid)
	if quest_id.begins_with("progression_to_"):
		return _regenerate_progression_quest(quest_id)

	return {}

func _regenerate_progression_quest(quest_id: String) -> Dictionary:
	"""Regenerate a progression quest from its ID."""
	# Parse ID: progression_to_postid
	var dest_post_id = quest_id.replace("progression_to_", "")

	if not TRADING_POST_COORDS.has(dest_post_id):
		return {}

	var dest_coords = TRADING_POST_COORDS.get(dest_post_id, Vector2i(0, 0))
	var distance = sqrt(dest_coords.x * dest_coords.x + dest_coords.y * dest_coords.y)
	var recommended_level = max(1, int(distance))

	# Get destination name from the key
	var dest_name = dest_post_id.replace("_", " ").capitalize()

	# Calculate rewards based on distance
	var base_xp = int(distance * 2)
	var valor = max(0, int(distance / 100))

	return {
		"id": quest_id,
		"name": "Journey to " + dest_name,
		"description": "Travel to %s to expand your horizons. (Recommended Level: %d)" % [dest_name, recommended_level],
		"type": QuestType.EXPLORATION,
		"trading_post": "",  # Origin unknown when regenerating
		"target": 1,
		"destinations": [dest_post_id],
		"rewards": {"xp": base_xp, "valor": valor},
		"is_daily": false,
		"prerequisite": "",
		"is_progression": true
	}

func _get_area_level_for_post(trading_post_id: String) -> int:
	"""Get the expected monster level for an area around a trading post."""
	var coords = TRADING_POST_COORDS.get(trading_post_id, Vector2i(0, 0))
	var distance = sqrt(coords.x * coords.x + coords.y * coords.y)
	# Distance-to-level formula: roughly distance * 0.5 for moderate zones
	# Haven (distance 10) = level 5, Northwatch (distance 75) = level 37
	return max(1, int(distance * 0.5))

func _scale_quest_rewards(quest: Dictionary, area_level: int) -> Dictionary:
	"""Scale quest rewards based on the trading post's area level using pow() scaling.

	This ensures quest XP scales the same way monster XP does, so quests remain
	competitive with grinding at all levels.
	"""
	# Base level for reward scaling (Haven area is ~level 5)
	const BASE_LEVEL = 5

	# Don't scale if we're at or below base level, but enforce minimum XP
	if area_level <= BASE_LEVEL:
		quest.rewards["xp"] = max(quest.rewards.get("xp", 0), 50)
		quest["area_level"] = area_level
		quest["reward_tier"] = "beginner"
		return quest

	# Calculate scaling factor using pow() to match monster XP progression
	# pow(level+1, 2.2) scaling ensures quest XP keeps pace with level requirements
	var base_factor = pow(BASE_LEVEL + 1, 2.2)
	var area_factor = pow(area_level + 1, 2.2)
	var scale_factor = area_factor / base_factor

	# Scale XP proportionally
	var original_xp = quest.rewards.get("xp", 0)
	var original_valor = quest.rewards.get("valor", 0)

	var scaled_rewards = {
		"xp": int(original_xp * scale_factor),
		"valor": original_valor + int(log(scale_factor + 1) * 2)  # Valor scales with log
	}

	quest.rewards = scaled_rewards
	quest["area_level"] = area_level
	quest["original_rewards"] = {"xp": original_xp, "valor": original_valor}

	# Determine reward tier for display based on area level
	if area_level < 15:
		quest["reward_tier"] = "beginner"
	elif area_level < 35:
		quest["reward_tier"] = "standard"
	elif area_level < 60:
		quest["reward_tier"] = "veteran"
	elif area_level < 100:
		quest["reward_tier"] = "elite"
	else:
		quest["reward_tier"] = "legendary"

	return quest

func _regenerate_dynamic_quest(quest_id: String, player_level: int = -1, quests_completed_at_post: int = 0) -> Dictionary:
	"""Regenerate a dynamic quest from its ID.
	If player_level is provided, uses _generate_quest_for_tier_scaled for accurate scaling."""
	# Parse ID: postid_dynamic_tier_index
	var parts = quest_id.split("_dynamic_")
	if parts.size() != 2:
		return {}

	var trading_post_id = parts[0]
	var tier_parts = parts[1].split("_")
	if tier_parts.size() != 2:
		return {}

	var tier = int(tier_parts[0])
	var index = int(tier_parts[1])
	var quest_tier = tier + index

	# Get trading post coordinates
	var post_coords = TRADING_POST_COORDS.get(trading_post_id, Vector2i(0, 0))
	var post_distance = sqrt(post_coords.x * post_coords.x + post_coords.y * post_coords.y)

	# If player_level is provided, use the scaled version (matches what was displayed to player)
	if player_level > 0:
		# Calculate progression modifier based on completed quests
		var progression_modifier = min(0.5, quests_completed_at_post * 0.05)
		return _generate_quest_for_tier_scaled(trading_post_id, quest_id, quest_tier, post_distance, player_level, progression_modifier)

	# Fallback to unscaled version (for backward compatibility)
	return _generate_quest_for_tier(trading_post_id, quest_id, quest_tier, post_distance)

func get_quests_for_trading_post(trading_post_id: String) -> Array:
	"""Get all quests offered at a specific Trading Post (with scaled rewards)."""
	var quests = []
	var area_level = _get_area_level_for_post(trading_post_id)
	for quest_id in QUESTS:
		var quest = QUESTS[quest_id]
		if quest.trading_post == trading_post_id:
			var scaled_quest = _scale_quest_rewards(quest.duplicate(true), area_level)
			quests.append(scaled_quest)
	return quests

func get_available_quests_for_player(trading_post_id: String, completed_quests: Array, active_quest_ids: Array, daily_cooldowns: Dictionary, player_level: int = 1, character_name: String = "") -> Array:
	"""Get quests available for a player at a Trading Post.
	All quests are now dynamically generated per-post per-day."""
	var available = []

	# Count completed daily quests at this post for progression scaling
	var completed_at_post = 0
	for quest_id in completed_quests:
		if quest_id.begins_with(trading_post_id + "_daily_") or quest_id.begins_with(trading_post_id + "_dynamic_"):
			completed_at_post += 1

	# Also count cooldown quests for progression
	for quest_id in daily_cooldowns:
		if quest_id.begins_with(trading_post_id + "_daily_") or quest_id.begins_with(trading_post_id + "_dynamic_"):
			completed_at_post += 1

	# Generate the daily quest board (date-seeded, per character at this post today)
	var daily_quests = generate_dynamic_quests(trading_post_id, completed_quests, active_quest_ids, player_level, completed_at_post, daily_cooldowns, character_name)
	available.append_array(daily_quests)

	return available

func get_locked_quests_for_player(trading_post_id: String, completed_quests: Array, active_quest_ids: Array, daily_cooldowns: Dictionary) -> Array:
	"""Get quests that are locked due to unmet prerequisites at a Trading Post."""
	var locked = []
	var current_time = Time.get_unix_time_from_system()

	for quest_id in QUESTS:
		var quest = QUESTS[quest_id]

		# Must be at this Trading Post
		if quest.trading_post != trading_post_id:
			continue

		# Can't be already active
		if quest_id in active_quest_ids:
			continue

		# Check if non-daily quest is already completed
		if not quest.is_daily and quest_id in completed_quests:
			continue

		# Check daily cooldown - skip if on cooldown (not locked, just unavailable)
		if quest.is_daily:
			if daily_cooldowns.has(quest_id):
				if current_time < daily_cooldowns[quest_id]:
					continue

		# Only include quests with unmet prerequisites
		if quest.prerequisite != "" and quest.prerequisite not in completed_quests:
			var locked_quest = quest.duplicate(true)
			locked_quest["quest_id"] = quest_id
			# Get the prerequisite quest name for display
			var prereq_quest = QUESTS.get(quest.prerequisite, {})
			locked_quest["prerequisite_name"] = prereq_quest.get("name", quest.prerequisite)
			locked.append(locked_quest)

	return locked

func _scale_quest_for_player(quest: Dictionary, player_level: int, quests_completed_at_post: int, area_level: int, character_name: String = "") -> Dictionary:
	"""Scale quest requirements and rewards based on player level and progression.
	Quests get progressively harder as player completes more at the same post."""

	# Calculate difficulty modifier based on progression (0.0 to 0.5 bonus)
	# More completed quests = harder requirements, pushing toward next post
	var progression_modifier = min(0.5, quests_completed_at_post * 0.05)

	# Effective difficulty level: use the higher of area level and half the player's level
	# This ensures quests at low-level posts still give reasonable rewards for higher-level players
	var effective_area_level = max(area_level, int(player_level * 0.4))

	# Scale rewards based on effective difficulty, not just static area level
	quest = _scale_quest_rewards(quest, effective_area_level)

	# Additional reward scaling for progression - harder quests give more
	if progression_modifier > 0:
		var bonus_mult = 1.0 + progression_modifier * 0.5  # Up to 25% bonus
		quest.rewards["xp"] = int(quest.rewards.get("xp", 0) * bonus_mult)

	# Base target level on player level with progression
	var base_level = player_level
	var target_level = int(base_level * (1.0 + progression_modifier))

	# Scale kill requirements based on quest type
	var quest_type = quest.get("type", -1)

	# Randomize target for KILL_TYPE quests with ranges using character-specific seed
	if quest.has("target_min") and quest.has("target_max"):
		var rng = RandomNumberGenerator.new()
		rng.seed = hash(quest.get("id", "") + character_name)
		quest["target"] = rng.randi_range(quest.target_min, quest.target_max)
	if quest.has("description") and "%d" in quest.description:
		quest.description = quest.description % quest.target

	match quest_type:
		QuestType.KILL_ANY:
			# Scale kill count: base + (player_level / 10) + progression bonus
			var base_target = quest.get("target", 5)
			var scaled_target = base_target + int(player_level / 10) + quests_completed_at_post
			quest["target"] = max(base_target, min(scaled_target, base_target * 3))  # Cap at 3x original
			quest["description"] = "Defeat %d monsters." % quest["target"]

		QuestType.KILL_TYPE:
			# Scale monster level requirement based on player progression
			# Early quests: no level req. After a few completions: require higher-level monsters
			if quests_completed_at_post >= 2:
				var min_monster_level = max(1, int(player_level * (0.5 + progression_modifier)))
				quest["min_monster_level"] = min_monster_level
				quest["description"] = quest.get("description", "").rstrip(".")
				quest["description"] += " (Lv%d+)." % min_monster_level

		QuestType.KILL_LEVEL:
			# Monster level requirement scales with player level + progression
			var min_level = max(1, int(target_level * 0.8))  # 80% of target level
			quest["target"] = min_level
			if quest.has("kill_count"):
				var base_count = quest.get("kill_count", 1)
				quest["kill_count"] = base_count + int(quests_completed_at_post / 2)
			quest["description"] = "Defeat monsters of level %d or higher." % min_level

		QuestType.HOTZONE_KILL:
			# Scale both monster level and kill count
			var min_monster_level = max(1, int(target_level * 0.7))
			quest["min_monster_level"] = min_monster_level
			var base_target = quest.get("target", 3)
			quest["target"] = base_target + int(quests_completed_at_post / 2)
			quest["description"] = "Kill %d monsters (Lv%d+) in hotzones." % [quest["target"], min_monster_level]

		QuestType.BOSS_HUNT:
			if quest.has("bounty_name"):
				# Named bounty - target is always 1, description already set
				pass
			else:
				# Legacy boss hunt format
				var boss_level = int(target_level * (1.0 + progression_modifier * 0.5))
				quest["target"] = boss_level
				quest["description"] = "Defeat a powerful monster of level %d or higher." % boss_level

		QuestType.RESCUE:
			# Rescue quests don't scale - target is always 1
			pass

	# Mark quest as scaled
	quest["player_level_scaled"] = player_level
	quest["difficulty_tier"] = quests_completed_at_post

	return quest

# ===== DYNAMIC QUEST GENERATION =====

# ===== DATE + DIRECTION HELPERS =====

static func _get_date_string() -> String:
	"""Returns YYYYMMDD string from system time for daily quest seeding."""
	var dt = Time.get_datetime_dict_from_system()
	return "%04d%02d%02d" % [dt.year, dt.month, dt.day]

static func _get_direction_text(from: Vector2i, to: Vector2i) -> String:
	"""Get compass direction from one point to another (e.g. 'north', 'southeast')."""
	var dx = to.x - from.x
	var dy = to.y - from.y
	if abs(dx) < 3 and abs(dy) < 3:
		return "nearby"
	var ns = ""
	var ew = ""
	if dy > abs(dx) * 0.4:
		ns = "north"
	elif dy < -abs(dx) * 0.4:
		ns = "south"
	if dx > abs(dy) * 0.4:
		ew = "east"
	elif dx < -abs(dy) * 0.4:
		ew = "west"
	if ns == "" and ew == "":
		return "nearby"
	return ns + ew  # e.g. "north", "southeast", "west"

static func _get_distance_text(from: Vector2i, to: Vector2i) -> String:
	"""Get a distance + direction description like 'far to the south (~95 tiles)'."""
	var dx = to.x - from.x
	var dy = to.y - from.y
	var dist = sqrt(dx * dx + dy * dy)
	var direction = _get_direction_text(from, to)
	if dist < 15:
		return "nearby (~%d tiles)" % int(dist)
	elif dist < 50:
		return "to the %s (~%d tiles)" % [direction, int(dist)]
	elif dist < 150:
		return "far to the %s (~%d tiles)" % [direction, int(dist)]
	else:
		return "very far to the %s (~%d tiles)" % [direction, int(dist)]

static func _get_tier_name(tier: int) -> String:
	"""Human-readable tier name for quest descriptions."""
	match tier:
		1: return "Tier 1 (Goblin/Rat)"
		2: return "Tier 2 (Orc/Spider)"
		3: return "Tier 3 (Troll/Wyvern)"
		4: return "Tier 4 (Giant/Demon)"
		5: return "Tier 5 (Dragon/Lich)"
		6: return "Tier 6 (Golem/Hydra)"
		7: return "Tier 7 (Void Walker)"
		8: return "Tier 8 (Cosmic Horror)"
		9: return "Tier 9 (Avatar)"
	return "Tier %d" % tier

# Trading post locations for distance calculations
const TRADING_POST_COORDS = {
	# Core Zone (0-30 distance)
	"haven": Vector2i(0, 10),
	"crossroads": Vector2i(0, 0),
	"south_gate": Vector2i(0, -25),
	"east_market": Vector2i(25, 10),
	"west_shrine": Vector2i(-25, 10),
	# Inner Zone (30-75 distance)
	"northeast_farm": Vector2i(40, 40),
	"northwest_mill": Vector2i(-40, 40),
	"southeast_mine": Vector2i(45, -35),
	"southwest_grove": Vector2i(-45, -35),
	"northwatch": Vector2i(0, 75),
	"eastern_camp": Vector2i(75, 0),
	"western_refuge": Vector2i(-75, 0),
	"southern_watch": Vector2i(0, -65),
	"northeast_tower": Vector2i(55, 55),
	"northwest_inn": Vector2i(-55, 55),
	"southeast_bridge": Vector2i(60, -50),
	"southwest_temple": Vector2i(-60, -50),
	# Mid Zone (75-200 distance)
	"frostgate": Vector2i(0, -100),
	"highland_post": Vector2i(0, 150),
	"eastwatch": Vector2i(150, 0),
	"westhold": Vector2i(-150, 0),
	"southport": Vector2i(0, -150),
	"northeast_bastion": Vector2i(120, 120),
	"northwest_lodge": Vector2i(-120, 120),
	"southeast_outpost": Vector2i(120, -120),
	"southwest_camp": Vector2i(-120, -120),
	# Outer Zone (200-350 distance)
	"far_east_station": Vector2i(250, 0),
	"far_west_haven": Vector2i(-250, 0),
	"deep_south_port": Vector2i(0, -275),
	"high_north_peak": Vector2i(0, 250),
	"northeast_frontier": Vector2i(200, 200),
	"northwest_citadel": Vector2i(-200, 200),
	"southeast_garrison": Vector2i(200, -200),
	"southwest_fortress": Vector2i(-200, -200),
	# Remote Zone (350-500 distance)
	"shadowmere": Vector2i(300, 300),
	"inferno_outpost": Vector2i(-350, 0),
	"voids_edge": Vector2i(350, 0),
	"frozen_reach": Vector2i(0, -400),
	"abyssal_depths": Vector2i(-300, -300),
	"celestial_spire": Vector2i(-300, 300),
	"storm_peak": Vector2i(0, 350),
	"dragons_rest": Vector2i(300, -300),
	# Extreme Zone (500-700 distance)
	"primordial_sanctum": Vector2i(0, 500),
	"nether_gate": Vector2i(0, -550),
	"eastern_terminus": Vector2i(500, 0),
	"western_terminus": Vector2i(-500, 0),
	"chaos_refuge": Vector2i(400, 400),
	"entropy_station": Vector2i(-400, -400),
	"oblivion_watch": Vector2i(-450, 400),
	"genesis_point": Vector2i(450, -400),
	# World's Edge (700+ distance)
	"world_spine_north": Vector2i(0, 700),
	"world_spine_south": Vector2i(0, -700),
	"eternal_east": Vector2i(700, 0),
	"eternal_west": Vector2i(-700, 0),
	"apex_northeast": Vector2i(550, 550),
	"apex_southeast": Vector2i(550, -550),
	"apex_northwest": Vector2i(-550, 550),
	"apex_southwest": Vector2i(-550, -550)
}

# Monster names by tier for KILL_TYPE quests
# Matches monster_database.gd tier system
const TIER_MONSTERS = {
	1: ["Goblin", "Giant Rat", "Kobold", "Skeleton", "Wolf"],
	2: ["Orc", "Hobgoblin", "Gnoll", "Zombie", "Giant Spider", "Wight", "Siren", "Kelpie", "Mimic"],
	3: ["Ogre", "Troll", "Wraith", "Wyvern", "Minotaur", "Gargoyle", "Harpy", "Shrieker"],
	4: ["Giant", "Dragon Wyrmling", "Demon", "Vampire", "Gryphon", "Chimaera", "Succubus"],
	5: ["Ancient Dragon", "Demon Lord", "Lich", "Titan", "Balrog", "Cerberus", "Jabberwock"],
	6: ["Elemental", "Iron Golem", "Sphinx", "Hydra", "Phoenix", "Nazgul"],
	7: ["Void Walker", "World Serpent", "Elder Lich", "Primordial Dragon"],
	8: ["Cosmic Horror", "Time Weaver", "Death Incarnate"],
	9: ["Avatar of Chaos", "The Nameless One", "God Slayer", "Entropy"]
}

# Level ranges for each monster tier
const TIER_LEVEL_RANGES = {
	1: {"min": 1, "max": 5},
	2: {"min": 6, "max": 15},
	3: {"min": 16, "max": 30},
	4: {"min": 31, "max": 50},
	5: {"min": 51, "max": 100},
	6: {"min": 101, "max": 500},
	7: {"min": 501, "max": 2000},
	8: {"min": 2001, "max": 5000},
	9: {"min": 5001, "max": 10000}
}

func _get_tier_for_area_level(area_level: int) -> int:
	"""Get the appropriate monster tier for an area level."""
	for tier in range(9, 0, -1):
		if area_level >= TIER_LEVEL_RANGES[tier].min:
			return tier
	return 1

func _get_random_monster_for_tier(tier: int) -> String:
	"""Get a random monster name from the specified tier."""
	var monsters = TIER_MONSTERS.get(tier, TIER_MONSTERS[1])
	return monsters[randi() % monsters.size()]

func _get_max_monster_level_for_area(area_level: int) -> int:
	"""Get the maximum appropriate monster level for an area, with some stretch room."""
	var tier = _get_tier_for_area_level(area_level)
	# Allow up to 20% above the tier's max, but cap at area level + 20
	var tier_max = TIER_LEVEL_RANGES[tier].max
	return min(tier_max, area_level + 20)

# Dungeon types by monster tier (matches dungeon_database.gd)
# Multiple dungeons per tier - randomly selected for variety
const TIER_DUNGEONS = {
	1: [
		{"type": "goblin_caves", "name": "Goblin Caves", "boss": "Goblin King"},
		{"type": "wolf_den", "name": "Wolf Den", "boss": "Alpha Wolf"}
	],
	2: [
		{"type": "orc_stronghold", "name": "Orc Stronghold", "boss": "Orc Warlord"},
		{"type": "spider_nest", "name": "Spider Nest", "boss": "Spider Queen"}
	],
	3: [
		{"type": "troll_den", "name": "Troll's Den", "boss": "Troll"},
		{"type": "wyvern_roost", "name": "Wyvern's Roost", "boss": "Wyvern"}
	],
	4: [
		{"type": "giant_keep", "name": "Giant's Keep", "boss": "Giant"},
		{"type": "vampire_crypt", "name": "Vampire's Crypt", "boss": "Vampire"}
	],
	5: [
		{"type": "lich_sanctum", "name": "Lich's Sanctum", "boss": "Lich"},
		{"type": "cerberus_pit", "name": "Cerberus's Pit", "boss": "Cerberus"},
		{"type": "balrog_depths", "name": "Balrog's Depths", "boss": "Balrog"}
	],
	6: [
		{"type": "ancient_dragon_lair", "name": "Ancient Dragon's Lair", "boss": "Ancient Dragon"},
		{"type": "hydra_swamp", "name": "Hydra's Swamp", "boss": "Hydra"},
		{"type": "phoenix_nest", "name": "Phoenix's Nest", "boss": "Phoenix"}
	],
	7: [
		{"type": "void_walker_rift", "name": "Void Walker's Rift", "boss": "Void Walker"},
		{"type": "primordial_dragon_domain", "name": "Primordial Dragon's Domain", "boss": "Primordial Dragon"}
	],
	8: [
		{"type": "cosmic_horror_realm", "name": "Cosmic Horror's Realm", "boss": "Cosmic Horror"}
	],
	9: [
		{"type": "chaos_sanctum", "name": "Avatar of Chaos's Sanctum", "boss": "Avatar of Chaos"}
	]
}

# Named bounty prefixes per monster type for BOSS_HUNT quests
const BOUNTY_PREFIXES = {
	# Tier 1
	"Goblin": ["Grimtooth", "Skullcrusher", "Vileblood", "Ironjaw"],
	"Giant Rat": ["Plaguebearer", "Sewerfang", "Rotclaw", "Gnashteeth"],
	"Kobold": ["Trapmaster", "Tunnelking", "Sharpfang", "Minelord"],
	"Skeleton": ["Bonelord", "Deathgrip", "Hollowgaze", "Duskrattle"],
	"Wolf": ["Bloodfang", "Shadowmane", "Ironpelt", "Howlstorm"],
	# Tier 2
	"Orc": ["Ironhide", "Skullsplitter", "Warchief", "Goreclaw"],
	"Hobgoblin": ["Warmaster", "Ironfist", "Bloodhelm", "Shieldbreaker"],
	"Gnoll": ["Packmaster", "Bonecruncher", "Ragehowl", "Deathfang"],
	"Zombie": ["Plaguelord", "Rotking", "Gravecrawler", "Deathstench"],
	"Giant Spider": ["Webmother", "Venomfang", "Shadowweaver", "Deathsilk"],
	"Wight": ["Soulreaver", "Doomshade", "Gravewarden", "Nightterror"],
	"Siren": ["Deathsinger", "Wailstorm", "Heartbreaker", "Doomcaller"],
	"Kelpie": ["Deepdrown", "Tidecrusher", "Darkwater", "Riptide"],
	"Mimic": ["Goldmaw", "Trapjaw", "Greedmaw", "Deceiver"],
	# Tier 3
	"Ogre": ["Boulderfist", "Skullcrusher", "Gutripper", "Mountainbane"],
	"Troll": ["Ironhide", "Regenerator", "Stoneblood", "Bridgebreaker"],
	"Wraith": ["Soulstealer", "Dreadshade", "Nightwail", "Voidtouch"],
	"Wyvern": ["Skyscourge", "Stormwing", "Venomtail", "Cloudpiercer"],
	"Minotaur": ["Labyrinthkeeper", "Hornbreaker", "Bloodrager", "Mazewarden"],
	"Gargoyle": ["Stonewing", "Nightguard", "Dusksentry", "Greyterror"],
	"Harpy": ["Stormscreech", "Talonclaw", "Windshrieker", "Featherbane"],
	"Shrieker": ["Doomcry", "Echoblight", "Sporeshroud", "Rotscream"],
	# Tier 4
	"Giant": ["Earthshaker", "Mountaincrusher", "Thunderstrider", "Worldbreaker"],
	"Dragon Wyrmling": ["Flamescale", "Emberfang", "Ashwing", "Sparkjaw"],
	"Demon": ["Hellrend", "Soulburner", "Doomcaller", "Chaosborn"],
	"Vampire": ["Bloodlord", "Nightthirst", "Crimsonbite", "Shadowfeast"],
	"Gryphon": ["Stormtalon", "Skyterror", "Goldenwing", "Cloudrazor"],
	"Chimaera": ["Threemaw", "Beastlord", "Nightcurse", "Primalfury"],
	"Succubus": ["Dreamweaver", "Soulbinder", "Heartrender", "Darkcharm"],
	# Tier 5
	"Ancient Dragon": ["Worldburner", "Eternaflame", "Doomscale", "Ashbringer"],
	"Demon Lord": ["Hellsovereign", "Doomlord", "Abyssking", "Chaosreign"],
	"Lich": ["Deathlord", "Soulkeeper", "Doomweaver", "Eternaldread"],
	"Titan": ["Worldshaper", "Mountainking", "Eternalmight", "Doomstrider"],
	"Balrog": ["Flametyrant", "Shadowfire", "Doomwhip", "Hellforge"],
	"Cerberus": ["Gateguard", "Tripledevour", "Hellhound", "Soulwarden"],
	"Jabberwock": ["Madnessmaw", "Chaosjaw", "Dreamripper", "Vorpalfoe"],
	# Tier 6
	"Elemental": ["Primordial", "Stormcore", "Worldspark", "Eternaforce"],
	"Iron Golem": ["Unbreakable", "Steelknight", "Forgeborn", "Ironeterna"],
	"Sphinx": ["Riddlelord", "Enigmabane", "Truthseeker", "Doomriddle"],
	"Hydra": ["Thousandmaw", "Regenscourge", "Deathsprout", "Venomtide"],
	"Phoenix": ["Eternaflame", "Ashreborn", "Dawnfire", "Solarbane"],
	"Nazgul": ["Doomrider", "Shadowking", "Wraithlord", "Nightsovereign"],
	# Tier 7
	"Void Walker": ["Realmsunder", "Nullbringer", "Voidlord", "Dimensionrend"],
	"World Serpent": ["Worldcoil", "Eternajaw", "Cosmicscale", "Realmbinder"],
	"Elder Lich": ["Eternadread", "Deathsovereign", "Soultyrant", "Doomlich"],
	"Primordial Dragon": ["Genesisflame", "Worldforge", "Eternascale", "Cosmicfire"],
	# Tier 8
	"Cosmic Horror": ["Maddener", "Stargaze", "Voidmind", "Realmblight"],
	"Time Weaver": ["Chronobane", "Eternashift", "Paradoxlord", "Timesunder"],
	"Death Incarnate": ["Finality", "Endwalker", "Doomabsolute", "Eternaend"],
	# Tier 9
	"Avatar of Chaos": ["Entropylord", "Worldunmaker", "Chaossovereign", "Realmscar"],
	"The Nameless One": ["Voidwhisper", "Forgottenbane", "Eternasilence", "Doomless"],
	"God Slayer": ["Divinebane", "Celestialkiller", "Pantheonfall", "Heavenrend"],
	"Entropy": ["Decayabsolute", "Worldrot", "Eternacrumble", "Realmdeath"]
}

# NPC types for RESCUE quests with area level thresholds
const RESCUE_NPC_TYPES = ["merchant", "healer", "blacksmith", "scholar", "breeder"]

# Gathering job types for GATHER quests
const GATHER_QUEST_TYPES = ["fishing", "mining", "logging", "foraging"]

func _get_dungeon_for_area(area_level: int) -> Dictionary:
	"""Get an appropriate dungeon type for the area level. Returns empty dict if none suitable.
	Randomly selects from available dungeons at the appropriate tier."""
	var tier = _get_tier_for_area_level(area_level)
	# Try the exact tier first, then lower tiers
	for t in range(tier, 0, -1):  # Dungeons available from tier 1
		if TIER_DUNGEONS.has(t):
			var dungeons = TIER_DUNGEONS[t]
			# Randomly select from available dungeons at this tier
			return dungeons[randi() % dungeons.size()]
	return {}

func generate_dynamic_quests(trading_post_id: String, completed_quests: Array, active_quest_ids: Array, player_level: int = 1, quests_completed_at_post: int = 0, daily_cooldowns: Dictionary = {}, character_name: String = "") -> Array:
	"""Generate daily quest board for a trading post. Seeded by date + post ID + character name
	so each character sees different quests at the same post on the same day."""
	var quests = []
	var date_str = _get_date_string()

	# Get this trading post's coordinates and area level
	var post_coords = TRADING_POST_COORDS.get(trading_post_id, Vector2i(0, 0))
	var post_distance = sqrt(post_coords.x * post_coords.x + post_coords.y * post_coords.y)
	var area_level = max(1, int(post_distance * 0.5))
	var monster_tier = _get_tier_for_area_level(area_level)

	# Quest count scales with area level: starter 3-4, mid 5-6, endgame 6-8
	var daily_seed = hash(trading_post_id + date_str + character_name)
	var rng = RandomNumberGenerator.new()
	rng.seed = daily_seed
	var quest_count: int
	if area_level < 10:
		quest_count = rng.randi_range(3, 4)
	elif area_level < 100:
		quest_count = rng.randi_range(5, 6)
	else:
		quest_count = rng.randi_range(6, 8)

	# Calculate difficulty modifier from progression
	var progression_modifier = min(0.5, quests_completed_at_post * 0.05)

	# Available quest types for cycling (weighted by what makes sense for the area)
	var quest_types = [QuestType.KILL_ANY, QuestType.KILL_TIER, QuestType.HOTZONE_KILL,
		QuestType.BOSS_HUNT, QuestType.EXPLORATION, QuestType.DUNGEON_CLEAR, QuestType.RESCUE, QuestType.GATHER]

	# Featured quest is index 0 (seeded by date across all posts)
	var featured_index = hash(date_str) % quest_count

	for i in range(quest_count):
		var quest_id = "%s_daily_%s_%d" % [trading_post_id, date_str, i]

		# Skip if already active, completed, or on cooldown
		if quest_id in active_quest_ids or quest_id in completed_quests:
			continue
		if daily_cooldowns.has(quest_id):
			var current_time = Time.get_unix_time_from_system()
			if current_time < daily_cooldowns[quest_id]:
				continue

		var quest = _generate_daily_quest(trading_post_id, quest_id, i, post_distance,
			player_level, progression_modifier, quest_types, rng, post_coords)
		if quest.is_empty():
			continue

		# Mark featured quest with bonus rewards
		if i == featured_index:
			quest["is_featured"] = true
			quest.rewards["xp"] = int(quest.rewards.get("xp", 0) * 1.5)
			quest.rewards["valor"] = max(quest.rewards.get("valor", 0), int(quest.rewards.get("valor", 0) * 1.5))

		quests.append(quest)

	# Restore randomness
	randomize()
	return quests

func _generate_daily_quest(trading_post_id: String, quest_id: String, index: int,
	post_distance: float, player_level: int, progression_modifier: float,
	quest_types: Array, rng: RandomNumberGenerator, post_coords: Vector2i) -> Dictionary:
	"""Generate a single daily quest. Uses rng (already seeded by caller) for determinism."""

	# Seed the global random for deterministic monster/dungeon picks using quest_id
	seed(quest_id.hash())

	var area_level = max(1, int(post_distance * 0.5))
	var monster_tier = _get_tier_for_area_level(area_level)
	var max_monster_level = _get_max_monster_level_for_area(area_level)
	var capped_level = min(player_level, max_monster_level)
	var effective_level = capped_level * (1.0 + progression_modifier * 0.5)

	# Tier multiplier: index 0 is easiest, later indices are harder
	var tier_mult: float = 0.9 + index * 0.15  # 0.9, 1.05, 1.2, 1.35, ...

	# Scale requirements
	var kill_count = max(3, int(5 + (index * 2) + (capped_level / 20)))
	var min_monster_level = min(int(effective_level * 0.7 * tier_mult), max_monster_level)

	# Rewards scale with area level using pow() to match monster XP
	var level_factor = pow(area_level + 1, 2.2)
	var tier_base_xp = 3 + index * 2
	var base_xp = int(tier_base_xp * level_factor * tier_mult)
	# Minimum XP floor so starter post quests aren't near-zero
	var min_xp = int((40 + index * 20) * tier_mult)
	base_xp = max(base_xp, min_xp)
	var valor = max(0, int((index - 1 + area_level / 50) * tier_mult))

	# Pick quest type, cycling through available types
	var type_index = rng.randi() % quest_types.size()
	var picked_type = quest_types[type_index]

	# Some types need features to exist - fall back to KILL_ANY/KILL_TIER if not
	var dungeon_info = _get_dungeon_for_area(area_level)
	if picked_type == QuestType.DUNGEON_CLEAR and dungeon_info.is_empty():
		picked_type = QuestType.KILL_TIER
	if picked_type == QuestType.RESCUE and dungeon_info.is_empty():
		picked_type = QuestType.BOSS_HUNT
	if picked_type == QuestType.EXPLORATION:
		# Need a different post to explore to
		var nearby_posts = _find_nearby_posts(post_coords, 50, 300)
		if nearby_posts.is_empty():
			picked_type = QuestType.KILL_ANY

	var quest_name: String
	var quest_desc: String
	var target: int
	var extra_fields: Dictionary = {}

	match picked_type:
		QuestType.KILL_ANY:
			quest_name = "Bounty: Monster Cull"
			quest_desc = "Eliminate %d monsters in the area." % kill_count
			target = kill_count

		QuestType.KILL_TIER:
			var req_tier = monster_tier
			var tier_kill_count = max(3, int(kill_count * 0.7))
			quest_name = "Bounty: %s Hunt" % _get_tier_name(req_tier).split("(")[0].strip_edges()
			var tier_range = TIER_LEVEL_RANGES.get(req_tier, {"min": 1, "max": 5})
			quest_desc = "Kill %d %s monsters (Lv%d-%d)." % [tier_kill_count, _get_tier_name(req_tier), tier_range.min, tier_range.max]
			target = tier_kill_count
			extra_fields["required_tier"] = req_tier
			extra_fields["monster_tier"] = req_tier

		QuestType.HOTZONE_KILL:
			var hz_kills = max(3, int(3 + index + (capped_level / 30)))
			var hz_min_level = min(int(effective_level * 0.6 * tier_mult), max_monster_level)
			var hz_distance = 30.0 + (index * 20.0) + (capped_level / 5)
			quest_name = "Danger Zone Bounty"
			quest_desc = "Kill %d monsters (Lv%d+) in hotzones within %.0f tiles." % [hz_kills, hz_min_level, hz_distance]
			target = hz_kills
			extra_fields["max_distance"] = hz_distance
			extra_fields["min_intensity"] = 0.0 if area_level < 50 else 0.3
			extra_fields["min_monster_level"] = hz_min_level

		QuestType.BOSS_HUNT:
			var boss_level = min(int(effective_level * 1.1), max_monster_level)
			boss_level = max(boss_level, area_level)
			var bounty_monster = _pick_bounty_monster_type(area_level, rng)
			var bounty_prefix = _pick_bounty_prefix(bounty_monster, rng)
			var bounty_name = "%s the %s" % [bounty_prefix, bounty_monster]
			var bounty_loc = _pick_bounty_location(post_coords, rng)
			quest_name = "Bounty: %s" % bounty_name
			quest_desc = "Hunt %s — last spotted near (%d, %d)." % [bounty_name, bounty_loc.x, bounty_loc.y]
			target = 1
			extra_fields["bounty_name"] = bounty_name
			extra_fields["bounty_monster_type"] = bounty_monster
			extra_fields["bounty_level"] = boss_level
			extra_fields["bounty_x"] = bounty_loc.x
			extra_fields["bounty_y"] = bounty_loc.y
			# Named bounties give better rewards
			base_xp = int(base_xp * 1.5)
			valor = max(valor + 1, int(valor * 1.5))

		QuestType.RESCUE:
			var rescue_npc = RESCUE_NPC_TYPES[rng.randi() % RESCUE_NPC_TYPES.size()]
			var rescue_dungeon = _get_dungeon_for_area(area_level)
			var rescue_dungeon_data = DungeonDatabaseScript.get_dungeon(rescue_dungeon.get("type", "goblin_caves")) if not rescue_dungeon.is_empty() else {}
			var total_floors = rescue_dungeon_data.get("floors", 3) if not rescue_dungeon_data.is_empty() else 3
			var rescue_floor = rng.randi_range(1, max(1, total_floors - 2))
			quest_name = "Rescue the %s" % rescue_npc.capitalize()
			var dungeon_name = rescue_dungeon.get("name", "a dungeon")
			quest_desc = "A %s is trapped in %s on floor %d! Look for the dungeon entrance (D) near this trading post." % [rescue_npc, dungeon_name, rescue_floor + 1]
			target = 1
			extra_fields["rescue_npc_type"] = rescue_npc
			extra_fields["dungeon_type"] = rescue_dungeon.get("type", "")
			extra_fields["rescue_floor"] = rescue_floor
			# Rescue quests give enhanced rewards
			base_xp = int(base_xp * 2.5)
			valor = max(valor + 2, int(valor * 2.0))

		QuestType.EXPLORATION:
			var nearby_posts = _find_nearby_posts(post_coords, 50, 300)
			if nearby_posts.size() > 0:
				var dest_idx = rng.randi() % nearby_posts.size()
				var dest_id = nearby_posts[dest_idx]
				var dest_coords = TRADING_POST_COORDS.get(dest_id, Vector2i(0, 0))
				var dest_name = dest_id.replace("_", " ").capitalize()
				var dist_text = _get_distance_text(post_coords, dest_coords)
				quest_name = "Journey to %s" % dest_name
				quest_desc = "Travel to %s. It lies %s." % [dest_name, dist_text]
				target = 1
				extra_fields["destinations"] = [dest_id]
			else:
				# Fallback
				quest_name = "Bounty: Monster Cull"
				quest_desc = "Eliminate %d monsters in the area." % kill_count
				target = kill_count
				picked_type = QuestType.KILL_ANY

		QuestType.DUNGEON_CLEAR:
			quest_name = "Conquer the %s" % dungeon_info.name
			quest_desc = "Venture into a %s and defeat %s." % [dungeon_info.name, dungeon_info.boss]
			target = 1
			extra_fields["dungeon_type"] = dungeon_info.type
			# Dungeon quests give bonus rewards
			base_xp = int(base_xp * 2.0)
			valor = max(valor + 2, int(valor * 1.5))

		QuestType.GATHER:
			var gather_job = GATHER_QUEST_TYPES[rng.randi() % GATHER_QUEST_TYPES.size()]
			var gather_count = max(3, int(3 + index + (area_level / 15)))
			quest_name = "%s Supplies" % gather_job.capitalize()
			quest_desc = "Gather %d materials through %s." % [gather_count, gather_job]
			target = gather_count
			extra_fields["gather_job"] = gather_job
			base_xp = int(base_xp * 1.3)

	# Determine reward tier for display tag
	var reward_tier: String
	if area_level < 15:
		reward_tier = "beginner"
	elif area_level < 35:
		reward_tier = "standard"
	elif area_level < 60:
		reward_tier = "veteran"
	elif area_level < 100:
		reward_tier = "elite"
	else:
		reward_tier = "legendary"

	var quest = {
		"id": quest_id,
		"name": quest_name,
		"description": quest_desc,
		"type": picked_type,
		"trading_post": trading_post_id,
		"target": target,
		"rewards": {"xp": base_xp, "valor": valor},
		"is_daily": true,
		"prerequisite": "",
		"is_dynamic": true,
		"area_level": area_level,
		"reward_tier": reward_tier,
		"player_level_scaled": player_level,
		"difficulty_tier": index
	}
	quest.merge(extra_fields)

	# Restore randomness
	randomize()
	return quest

func _regenerate_daily_quest(quest_id: String, player_level: int = -1, quests_completed_at_post: int = 0, character_name: String = "") -> Dictionary:
	"""Regenerate a daily quest from its ID for quest lookup/turn-in.
	Daily IDs have format: postid_daily_YYYYMMDD_index"""
	var parts = quest_id.split("_daily_")
	if parts.size() != 2:
		return {}
	var trading_post_id = parts[0]
	var date_parts = parts[1].split("_")
	if date_parts.size() != 2:
		return {}
	var index = int(date_parts[1])

	var post_coords = TRADING_POST_COORDS.get(trading_post_id, Vector2i(0, 0))
	var post_distance = sqrt(post_coords.x * post_coords.x + post_coords.y * post_coords.y)

	var progression_modifier = min(0.5, quests_completed_at_post * 0.05)
	var effective_player_level = max(1, player_level)

	# Re-seed RNG the same way generate_dynamic_quests does (includes character_name)
	var date_str = date_parts[0]
	var daily_seed = hash(trading_post_id + date_str + character_name)
	var rng = RandomNumberGenerator.new()
	rng.seed = daily_seed
	# Advance rng state to match the index (each quest consumes some rng calls)
	# We need to regenerate all quests up to and including this index
	var quest_types = [QuestType.KILL_ANY, QuestType.KILL_TIER, QuestType.HOTZONE_KILL,
		QuestType.BOSS_HUNT, QuestType.EXPLORATION, QuestType.DUNGEON_CLEAR, QuestType.RESCUE, QuestType.GATHER]

	# Determine quest count (same logic as generate_dynamic_quests)
	var area_level = max(1, int(post_distance * 0.5))
	if area_level < 10:
		var _count = rng.randi_range(3, 4)
	elif area_level < 100:
		var _count = rng.randi_range(5, 6)
	else:
		var _count = rng.randi_range(6, 8)

	# Generate quests 0..index to advance RNG state correctly
	var result = {}
	for i in range(index + 1):
		var qid = "%s_daily_%s_%d" % [trading_post_id, date_str, i]
		var quest = _generate_daily_quest(trading_post_id, qid, i, post_distance,
			effective_player_level, progression_modifier, quest_types, rng, post_coords)
		if i == index:
			result = quest
	randomize()
	return result

func _find_nearby_posts(from_coords: Vector2i, min_dist: float, max_dist: float) -> Array:
	"""Find trading post IDs within a distance range from given coordinates."""
	var result = []
	for post_id in TRADING_POST_COORDS:
		var coords = TRADING_POST_COORDS[post_id]
		var dx = coords.x - from_coords.x
		var dy = coords.y - from_coords.y
		var dist = sqrt(dx * dx + dy * dy)
		if dist >= min_dist and dist <= max_dist:
			result.append(post_id)
	return result

func _generate_quest_for_tier(trading_post_id: String, quest_id: String, tier: int, post_distance: float) -> Dictionary:
	"""Generate a single quest based on tier and trading post location."""

	# Gentler scaling for early tiers - starts easier and ramps up gradually
	# Tier 1-3: Easy quests, Tier 4-7: Medium, Tier 8+: Hard
	var tier_multiplier: float
	if tier <= 3:
		tier_multiplier = 0.5 + (tier - 1) * 0.25  # 0.5, 0.75, 1.0
	elif tier <= 7:
		tier_multiplier = 1.0 + (tier - 3) * 0.5   # 1.0, 1.5, 2.0, 2.5
	else:
		tier_multiplier = 2.5 + (tier - 7) * 0.75  # 2.5, 3.25, 4.0...

	# Base values with gentler scaling
	var kill_count = int(5 + (tier * 3 * tier_multiplier))  # 5, 8, 11, 17, 27...
	var min_level = int((post_distance * 0.3) + (tier * 10 * tier_multiplier))  # Scales slower
	var hotzone_distance = 30.0 + (tier * 25.0 * tier_multiplier)  # 30, 55, 80...
	var hotzone_kills = int(3 + (tier * 2 * tier_multiplier))  # 3, 5, 7, 11...
	var hotzone_min_monster_level = max(3, int(post_distance * 0.2) + int(tier * 8 * tier_multiplier))  # Starts lower

	# Rewards scale with tier - more generous for early tiers
	var base_xp = int(100 + (150 * tier * tier_multiplier))
	var valor = max(0, int((tier - 2) * tier_multiplier))  # Valor starts at tier 3

	# Quest type varies by tier - simpler quests early on
	var quest_type: int
	var quest_name: String
	var quest_desc: String
	var target: int

	# For very early tiers (1-2), prefer simpler KILL_ANY quests
	var effective_tier_type = tier if tier > 2 else 0

	match effective_tier_type % 4:
		0:  # Kill any monsters
			quest_type = QuestType.KILL_ANY
			quest_name = "Slayer's Contract %d" % tier
			quest_desc = "Eliminate %d monsters to prove your continued valor." % kill_count
			target = kill_count
		1:  # Kill high-level monsters
			quest_type = QuestType.KILL_LEVEL
			quest_name = "Veteran's Challenge %d" % tier
			quest_desc = "Defeat a monster of level %d or higher." % min_level
			target = min_level
		2:  # Hotzone quest
			quest_type = QuestType.HOTZONE_KILL
			quest_name = "Danger Zone Bounty %d" % tier
			quest_desc = "Kill %d monsters (level %d+) in hotzones within %.0f tiles." % [hotzone_kills, hotzone_min_monster_level, hotzone_distance]
			target = hotzone_kills
		3:  # Boss hunt
			quest_type = QuestType.BOSS_HUNT
			quest_name = "Elite Hunt %d" % tier
			quest_desc = "Track down and defeat a monster of level %d or higher." % (min_level + int(25 * tier_multiplier))
			target = min_level + int(25 * tier_multiplier)

	# Calculate area level for display consistency
	var area_level = max(1, int(post_distance * 0.5))

	# Determine reward tier based on tier multiplier
	var reward_tier: String
	if tier_multiplier < 2.0:
		reward_tier = "standard"
	elif tier_multiplier < 3.0:
		reward_tier = "veteran"
	elif tier_multiplier < 4.0:
		reward_tier = "elite"
	else:
		reward_tier = "legendary"

	var quest = {
		"id": quest_id,
		"name": quest_name,
		"description": quest_desc,
		"type": quest_type,
		"trading_post": trading_post_id,
		"target": target,
		"rewards": {"xp": base_xp, "valor": valor},
		"is_daily": false,
		"prerequisite": "",
		"is_dynamic": true,  # Flag for dynamic quests
		"area_level": area_level,
		"reward_tier": reward_tier
	}

	# Add hotzone-specific fields
	if quest_type == QuestType.HOTZONE_KILL:
		quest["max_distance"] = hotzone_distance
		quest["min_intensity"] = 0.0 if tier < 5 else 0.3
		quest["min_monster_level"] = hotzone_min_monster_level

	return quest

func _generate_quest_for_tier_scaled(trading_post_id: String, quest_id: String, tier: int, post_distance: float, player_level: int, progression_modifier: float) -> Dictionary:
	"""Generate a single quest based on tier, scaled to player level and area appropriateness."""

	# IMPORTANT: Seed the random generator with the quest_id hash to ensure
	# the same quest_id always produces the same random choices (monster type, dungeon, etc.)
	# This prevents the description from changing when regenerating the quest
	seed(quest_id.hash())

	# Calculate area level FIRST - this determines what monsters are appropriate
	var area_level = max(1, int(post_distance * 0.5))
	var monster_tier = _get_tier_for_area_level(area_level)
	var max_monster_level = _get_max_monster_level_for_area(area_level)

	# Effective level is the lower of player level and what the area supports
	# This prevents quests requiring level 50 monsters in a level 10 area
	var capped_level = min(player_level, max_monster_level)
	var effective_level = capped_level * (1.0 + progression_modifier * 0.5)

	# Tier multiplier for progressive difficulty within the post
	var tier_multiplier: float
	if tier <= 3:
		tier_multiplier = 0.8 + (tier - 1) * 0.1  # 0.8, 0.9, 1.0
	elif tier <= 7:
		tier_multiplier = 1.0 + (tier - 3) * 0.15   # 1.0, 1.15, 1.3, 1.45
	else:
		tier_multiplier = 1.45 + (tier - 7) * 0.2  # 1.45, 1.65, 1.85...

	# Scale requirements - capped to area-appropriate levels
	var kill_count = int(5 + (tier * 2) + (capped_level / 20))
	var min_monster_level = min(int(effective_level * 0.7 * tier_multiplier), max_monster_level)
	var hotzone_distance = 30.0 + (tier * 20.0) + (capped_level / 5)
	var hotzone_kills = int(3 + tier + (capped_level / 30))
	var hotzone_min_level = min(int(effective_level * 0.6 * tier_multiplier), max_monster_level)

	# Rewards scale with area level using pow() to match monster XP scaling
	# This ensures quest rewards remain competitive with grinding at all levels
	var level_factor = pow(area_level + 1, 2.2)
	var tier_base_xp = 3 + tier * 2  # 5 for tier 1, up to 13+ for tier 5
	var base_xp = int(tier_base_xp * level_factor * tier_multiplier)
	var valor = max(0, int((tier - 2 + area_level / 50) * tier_multiplier))

	# Quest type varies by tier - includes KILL_TYPE and DUNGEON_CLEAR
	var quest_type: int
	var quest_name: String
	var quest_desc: String
	var target: int
	var monster_type: String = ""
	var dungeon_type: String = ""
	var bounty_name: String = ""
	var bounty_level: int = 0
	var bounty_loc: Vector2i = Vector2i.ZERO

	# Early tiers prefer simpler KILL_ANY quests
	var effective_tier_type = tier if tier > 2 else 0

	# Check if dungeon quests are available for this area
	var dungeon_info = _get_dungeon_for_area(area_level)
	var can_have_dungeon_quest = not dungeon_info.is_empty() and tier >= 1

	# Use mod 6 if dungeons available, otherwise mod 5
	var quest_mod = 6 if can_have_dungeon_quest else 5

	match effective_tier_type % quest_mod:
		0:  # Kill any monsters
			quest_type = QuestType.KILL_ANY
			quest_name = "Slayer's Contract %d" % tier
			quest_desc = "Eliminate %d monsters to prove your continued valor." % kill_count
			target = kill_count
		1:  # Kill specific monster type
			quest_type = QuestType.KILL_TYPE
			monster_type = _get_random_monster_for_tier(monster_tier)
			var type_kill_count = int(kill_count * 0.6)  # Fewer kills for specific type
			quest_name = "%s Hunt %d" % [monster_type, tier]
			quest_desc = "Hunt down and slay %d %ss in this region." % [type_kill_count, monster_type]
			target = type_kill_count
		2:  # Kill high-level monsters (capped to area)
			quest_type = QuestType.KILL_LEVEL
			quest_name = "Veteran's Challenge %d" % tier
			quest_desc = "Defeat a monster of level %d or higher." % min_monster_level
			target = min_monster_level
		3:  # Hotzone quest
			quest_type = QuestType.HOTZONE_KILL
			quest_name = "Danger Zone Bounty %d" % tier
			quest_desc = "Kill %d monsters (level %d+) in hotzones within %.0f tiles." % [hotzone_kills, hotzone_min_level, hotzone_distance]
			target = hotzone_kills
		4:  # Boss hunt - named bounty at specific location
			bounty_level = min(int(effective_level * 1.1), max_monster_level)
			quest_type = QuestType.BOSS_HUNT
			var b_monster = _pick_bounty_monster_type_seeded(area_level)
			var b_prefix = _pick_bounty_prefix_seeded(b_monster)
			bounty_name = "%s the %s" % [b_prefix, b_monster]
			var post_coords_for_bounty = TRADING_POST_COORDS.get(trading_post_id, Vector2i(0, 0))
			bounty_loc = _pick_bounty_location_seeded(post_coords_for_bounty)
			quest_name = "Bounty: %s" % bounty_name
			quest_desc = "Hunt %s — last spotted near (%d, %d)." % [bounty_name, bounty_loc.x, bounty_loc.y]
			target = 1
			monster_type = b_monster
			dungeon_type = ""
		5:  # Dungeon clear quest (only if dungeons available)
			quest_type = QuestType.DUNGEON_CLEAR
			dungeon_type = dungeon_info.type
			quest_name = "Conquer the %s" % dungeon_info.name
			quest_desc = "Venture into a %s and defeat %s. Dungeons may spawn in the wilderness - explore to find one!" % [dungeon_info.name, dungeon_info.boss]
			target = 1  # Complete 1 dungeon of this type
			# Dungeon quests give bonus rewards (companion eggs from dungeon)
			base_xp = int(base_xp * 2.0)
			valor = max(valor + 2, int(valor * 1.5))

	# Determine reward tier
	var reward_tier: String
	if tier_multiplier < 1.1:
		reward_tier = "standard"
	elif tier_multiplier < 1.4:
		reward_tier = "veteran"
	elif tier_multiplier < 1.7:
		reward_tier = "elite"
	else:
		reward_tier = "legendary"

	var quest = {
		"id": quest_id,
		"name": quest_name,
		"description": quest_desc,
		"type": quest_type,
		"trading_post": trading_post_id,
		"target": target,
		"rewards": {"xp": base_xp, "valor": valor},
		"is_daily": false,
		"prerequisite": "",
		"is_dynamic": true,
		"area_level": area_level,
		"reward_tier": reward_tier,
		"player_level_scaled": player_level,
		"difficulty_tier": tier
	}

	# Add type-specific fields
	if quest_type == QuestType.HOTZONE_KILL:
		quest["max_distance"] = hotzone_distance
		quest["min_intensity"] = 0.0 if tier < 5 else 0.3
		quest["min_monster_level"] = hotzone_min_level
	elif quest_type == QuestType.KILL_TYPE:
		quest["monster_type"] = monster_type
	elif quest_type == QuestType.DUNGEON_CLEAR:
		quest["dungeon_type"] = dungeon_type
	elif quest_type == QuestType.BOSS_HUNT:
		# Reuse values computed in the initial generation above
		quest["bounty_name"] = bounty_name
		quest["bounty_monster_type"] = monster_type
		quest["bounty_level"] = bounty_level
		quest["bounty_x"] = bounty_loc.x
		quest["bounty_y"] = bounty_loc.y

	# Restore randomness after using seeded generation
	randomize()

	return quest

func get_all_quest_ids() -> Array:
	"""Get array of all quest IDs."""
	return QUESTS.keys()

func is_quest_type_kill(quest_type: int) -> bool:
	"""Check if quest type involves killing monsters."""
	return quest_type in [QuestType.KILL_ANY, QuestType.KILL_TYPE, QuestType.KILL_LEVEL, QuestType.HOTZONE_KILL, QuestType.BOSS_HUNT, QuestType.KILL_TIER]

func is_quest_type_exploration(quest_type: int) -> bool:
	"""Check if quest type involves exploration."""
	return quest_type == QuestType.EXPLORATION

func is_quest_type_dungeon(quest_type: int) -> bool:
	"""Check if quest type involves dungeon completion."""
	return quest_type == QuestType.DUNGEON_CLEAR

func is_quest_type_rescue(quest_type: int) -> bool:
	"""Check if quest type involves rescuing an NPC."""
	return quest_type == QuestType.RESCUE

func is_quest_type_gather(quest_type: int) -> bool:
	"""Check if quest type involves gathering materials."""
	return quest_type == QuestType.GATHER

# ===== BOUNTY & RESCUE HELPER FUNCTIONS =====

func _pick_bounty_monster_type(area_level: int, rng: RandomNumberGenerator) -> String:
	"""Pick an area-appropriate monster type for a bounty quest using provided RNG."""
	var tier = _get_tier_for_area_level(area_level)
	var monsters = TIER_MONSTERS.get(tier, TIER_MONSTERS[1])
	return monsters[rng.randi() % monsters.size()]

func _pick_bounty_prefix(monster_type: String, rng: RandomNumberGenerator) -> String:
	"""Pick a random prefix from BOUNTY_PREFIXES using provided RNG."""
	var prefixes = BOUNTY_PREFIXES.get(monster_type, ["Dread", "Vile", "Dark", "Cursed"])
	return prefixes[rng.randi() % prefixes.size()]

func _pick_bounty_location(post_coords: Vector2i, rng: RandomNumberGenerator) -> Vector2i:
	"""Pick a random location 15-40 tiles from the trading post using provided RNG."""
	var distance = rng.randi_range(15, 40)
	var angle_deg = rng.randi_range(0, 359)
	var angle_rad = deg_to_rad(float(angle_deg))
	var x = int(post_coords.x + cos(angle_rad) * distance)
	var y = int(post_coords.y + sin(angle_rad) * distance)
	return Vector2i(x, y)

func _pick_bounty_monster_type_seeded(area_level: int) -> String:
	"""Pick an area-appropriate monster type using the current global seed (for quest_id seeded generation)."""
	var tier = _get_tier_for_area_level(area_level)
	var monsters = TIER_MONSTERS.get(tier, TIER_MONSTERS[1])
	return monsters[randi() % monsters.size()]

func _pick_bounty_prefix_seeded(monster_type: String) -> String:
	"""Pick a random prefix using the current global seed."""
	var prefixes = BOUNTY_PREFIXES.get(monster_type, ["Dread", "Vile", "Dark", "Cursed"])
	return prefixes[randi() % prefixes.size()]

func _pick_bounty_location_seeded(post_coords: Vector2i) -> Vector2i:
	"""Pick a random location 15-40 tiles from the trading post using the current global seed."""
	var distance = 15 + randi() % 26  # 15-40
	var angle_deg = randi() % 360
	var angle_rad = deg_to_rad(float(angle_deg))
	var x = int(post_coords.x + cos(angle_rad) * distance)
	var y = int(post_coords.y + sin(angle_rad) * distance)
	return Vector2i(x, y)
