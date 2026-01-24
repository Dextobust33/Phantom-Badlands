# quest_database.gd
# Quest definitions and constants
class_name QuestDatabase
extends Node

# Quest type constants
enum QuestType {
	KILL_ANY,           # Kill X monsters of any type
	KILL_TYPE,          # Kill X monsters of specific type (not implemented yet)
	KILL_LEVEL,         # Kill a monster of level X or higher
	HOTZONE_KILL,       # Kill X monsters in a hotzone within Y distance
	EXPLORATION,        # Visit specific coordinates/locations
	BOSS_HUNT           # Defeat a monster of level X or higher (same as KILL_LEVEL but labeled differently)
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
#   "rewards": {xp: int, gold: int, gems: int},
#   "is_daily": bool,
#   "prerequisite": String (quest_id that must be completed first, or empty)
# }

# All quests in the game
const QUESTS = {
	# ===== HAVEN (0, 10) - Guard Captain - Beginner Quests =====
	"haven_first_blood": {
		"id": "haven_first_blood",
		"name": "First Blood",
		"description": "Kill 3 monsters to prove your worth as an adventurer.",
		"type": QuestType.KILL_ANY,
		"trading_post": "haven",
		"target": 3,
		"rewards": {"xp": 50, "gold": 25, "gems": 0},
		"is_daily": false,
		"prerequisite": ""
	},
	"haven_pest_control": {
		"id": "haven_pest_control",
		"name": "Pest Control",
		"description": "Help keep the area safe by eliminating 10 monsters.",
		"type": QuestType.KILL_ANY,
		"trading_post": "haven",
		"target": 10,
		"rewards": {"xp": 150, "gold": 75, "gems": 0},
		"is_daily": false,
		"prerequisite": "haven_first_blood"
	},
	"haven_stronger_foes": {
		"id": "haven_stronger_foes",
		"name": "Stronger Foes",
		"description": "Prove your courage by defeating a monster of level 10 or higher.",
		"type": QuestType.KILL_LEVEL,
		"trading_post": "haven",
		"target": 10,
		"rewards": {"xp": 200, "gold": 100, "gems": 0},
		"is_daily": false,
		"prerequisite": "haven_pest_control"
	},
	"haven_local_hero": {
		"id": "haven_local_hero",
		"name": "Local Hero",
		"description": "Become a hero of Haven by slaying 25 monsters.",
		"type": QuestType.KILL_ANY,
		"trading_post": "haven",
		"target": 25,
		"rewards": {"xp": 500, "gold": 250, "gems": 1},
		"is_daily": false,
		"prerequisite": "haven_stronger_foes"
	},

	# ===== CROSSROADS (0, 0) - Royal Herald - Hotzone Focus =====
	"crossroads_danger_zone": {
		"id": "crossroads_danger_zone",
		"name": "Into the Danger Zone",
		"description": "Kill 3 monsters in a hotzone within 50 tiles. The Royal Herald offers this bounty daily.",
		"type": QuestType.HOTZONE_KILL,
		"trading_post": "crossroads",
		"target": 3,
		"max_distance": 50.0,
		"min_intensity": 0.0,
		"rewards": {"xp": 150, "gold": 100, "gems": 1},
		"is_daily": true,
		"prerequisite": ""
	},
	"crossroads_danger_seeker": {
		"id": "crossroads_danger_seeker",
		"name": "Danger Seeker",
		"description": "Kill 5 monsters in hotzones within 100 tiles of Crossroads.",
		"type": QuestType.HOTZONE_KILL,
		"trading_post": "crossroads",
		"target": 5,
		"max_distance": 100.0,
		"min_intensity": 0.0,
		"rewards": {"xp": 300, "gold": 200, "gems": 1},
		"is_daily": false,
		"prerequisite": ""
	},
	"crossroads_risk_reward": {
		"id": "crossroads_risk_reward",
		"name": "Risk and Reward",
		"description": "Kill 10 monsters in hotzones within 200 tiles. Greater risk, greater reward.",
		"type": QuestType.HOTZONE_KILL,
		"trading_post": "crossroads",
		"target": 10,
		"max_distance": 200.0,
		"min_intensity": 0.0,
		"rewards": {"xp": 750, "gold": 500, "gems": 2},
		"is_daily": false,
		"prerequisite": "crossroads_danger_seeker"
	},
	"crossroads_extreme": {
		"id": "crossroads_extreme",
		"name": "Extreme Challenge",
		"description": "Kill 5 monsters in high-intensity hotzones (0.5+) within 300 tiles. Only for the brave.",
		"type": QuestType.HOTZONE_KILL,
		"trading_post": "crossroads",
		"target": 5,
		"max_distance": 300.0,
		"min_intensity": 0.5,
		"rewards": {"xp": 1500, "gold": 1000, "gems": 5},
		"is_daily": false,
		"prerequisite": "crossroads_risk_reward"
	},

	# ===== FROSTGATE (0, -100) - Guild Master - Exploration/Boss =====
	"frostgate_know_world": {
		"id": "frostgate_know_world",
		"name": "Know Your World",
		"description": "Visit both Haven and Crossroads Trading Posts to learn the lay of the land.",
		"type": QuestType.EXPLORATION,
		"trading_post": "frostgate",
		"target": 2,  # Visit 2 locations
		"destinations": ["haven", "crossroads"],  # Trading post IDs to visit
		"rewards": {"xp": 200, "gold": 100, "gems": 0},
		"is_daily": false,
		"prerequisite": ""
	},
	"frostgate_eastern_expedition": {
		"id": "frostgate_eastern_expedition",
		"name": "Eastern Expedition",
		"description": "Journey to Eastwatch Trading Post at (150, 0). A long but rewarding trip.",
		"type": QuestType.EXPLORATION,
		"trading_post": "frostgate",
		"target": 1,
		"destinations": ["eastwatch"],
		"rewards": {"xp": 500, "gold": 250, "gems": 1},
		"is_daily": false,
		"prerequisite": "frostgate_know_world"
	},
	"frostgate_champions_trial": {
		"id": "frostgate_champions_trial",
		"name": "Champion's Trial",
		"description": "Defeat a monster of level 50 or higher to prove your might.",
		"type": QuestType.BOSS_HUNT,
		"trading_post": "frostgate",
		"target": 50,
		"rewards": {"xp": 1000, "gold": 500, "gems": 2},
		"is_daily": false,
		"prerequisite": ""
	},
	"frostgate_legendary_hunt": {
		"id": "frostgate_legendary_hunt",
		"name": "Legendary Hunt",
		"description": "Defeat a monster of level 200 or higher. Only legends attempt this feat.",
		"type": QuestType.BOSS_HUNT,
		"trading_post": "frostgate",
		"target": 200,
		"rewards": {"xp": 5000, "gold": 2500, "gems": 10},
		"is_daily": false,
		"prerequisite": "frostgate_champions_trial"
	},

	# ===== EASTWATCH (150, 0) - Bounty Hunter - Mid-level Kill Quests =====
	"eastwatch_wilderness_threat": {
		"id": "eastwatch_wilderness_threat",
		"name": "Bounty: Wilderness Threat",
		"description": "Eliminate 15 monsters of level 30 or higher in the eastern wilds.",
		"type": QuestType.KILL_LEVEL,
		"trading_post": "eastwatch",
		"target": 30,
		"kill_count": 15,  # Special: need to kill 15 monsters at this level
		"rewards": {"xp": 800, "gold": 400, "gems": 2},
		"is_daily": false,
		"prerequisite": ""
	},
	"eastwatch_elite_target": {
		"id": "eastwatch_elite_target",
		"name": "Bounty: Elite Target",
		"description": "Track down and eliminate a single monster of level 100 or higher.",
		"type": QuestType.BOSS_HUNT,
		"trading_post": "eastwatch",
		"target": 100,
		"rewards": {"xp": 2000, "gold": 1000, "gems": 5},
		"is_daily": false,
		"prerequisite": "eastwatch_wilderness_threat"
	},
	"eastwatch_mass_culling": {
		"id": "eastwatch_mass_culling",
		"name": "Bounty: Mass Culling",
		"description": "Thin the monster population by eliminating 50 creatures.",
		"type": QuestType.KILL_ANY,
		"trading_post": "eastwatch",
		"target": 50,
		"rewards": {"xp": 1500, "gold": 750, "gems": 3},
		"is_daily": false,
		"prerequisite": ""
	},
	"eastwatch_long_road": {
		"id": "eastwatch_long_road",
		"name": "The Long Road",
		"description": "Make the dangerous journey to Shadowmere Trading Post at (300, 300).",
		"type": QuestType.EXPLORATION,
		"trading_post": "eastwatch",
		"target": 1,
		"destinations": ["shadowmere"],
		"rewards": {"xp": 3000, "gold": 1500, "gems": 5},
		"is_daily": false,
		"prerequisite": "eastwatch_elite_target"
	}
}

func get_quest(quest_id: String) -> Dictionary:
	"""Get quest data by ID. Returns empty dict if not found."""
	if QUESTS.has(quest_id):
		return QUESTS[quest_id].duplicate(true)
	return {}

func get_quests_for_trading_post(trading_post_id: String) -> Array:
	"""Get all quests offered at a specific Trading Post."""
	var quests = []
	for quest_id in QUESTS:
		var quest = QUESTS[quest_id]
		if quest.trading_post == trading_post_id:
			quests.append(quest.duplicate(true))
	return quests

func get_available_quests_for_player(trading_post_id: String, completed_quests: Array, active_quest_ids: Array, daily_cooldowns: Dictionary) -> Array:
	"""Get quests available for a player at a Trading Post, considering prerequisites and cooldowns."""
	var available = []
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

		# Check daily cooldown
		if quest.is_daily:
			if daily_cooldowns.has(quest_id):
				if current_time < daily_cooldowns[quest_id]:
					continue

		# Check prerequisite
		if quest.prerequisite != "" and quest.prerequisite not in completed_quests:
			continue

		available.append(quest.duplicate(true))

	return available

func get_all_quest_ids() -> Array:
	"""Get array of all quest IDs."""
	return QUESTS.keys()

func is_quest_type_kill(quest_type: int) -> bool:
	"""Check if quest type involves killing monsters."""
	return quest_type in [QuestType.KILL_ANY, QuestType.KILL_TYPE, QuestType.KILL_LEVEL, QuestType.HOTZONE_KILL, QuestType.BOSS_HUNT]

func is_quest_type_exploration(quest_type: int) -> bool:
	"""Check if quest type involves exploration."""
	return quest_type == QuestType.EXPLORATION
