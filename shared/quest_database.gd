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
	"haven_first_steps": {
		"id": "haven_first_steps",
		"name": "First Steps",
		"description": "Defeat your first monster to begin your adventure.",
		"type": QuestType.KILL_ANY,
		"trading_post": "haven",
		"target": 1,
		"rewards": {"xp": 25, "gold": 15, "gems": 0},
		"is_daily": false,
		"prerequisite": ""
	},
	"haven_first_blood": {
		"id": "haven_first_blood",
		"name": "First Blood",
		"description": "Kill 3 monsters to prove your worth as an adventurer.",
		"type": QuestType.KILL_ANY,
		"trading_post": "haven",
		"target": 3,
		"rewards": {"xp": 50, "gold": 30, "gems": 0},
		"is_daily": false,
		"prerequisite": ""
	},
	"haven_getting_started": {
		"id": "haven_getting_started",
		"name": "Getting Started",
		"description": "Explore the area by defeating 5 monsters.",
		"type": QuestType.KILL_ANY,
		"trading_post": "haven",
		"target": 5,
		"rewards": {"xp": 75, "gold": 40, "gems": 0},
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
		"prerequisite": ""
	},
	"haven_stronger_foes": {
		"id": "haven_stronger_foes",
		"name": "Stronger Foes",
		"description": "Prove your courage by defeating 2 monsters of level 5 or higher.",
		"type": QuestType.KILL_LEVEL,
		"trading_post": "haven",
		"target": 5,
		"kill_count": 2,
		"rewards": {"xp": 200, "gold": 100, "gems": 0},
		"is_daily": false,
		"prerequisite": ""
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
		"prerequisite": ""
	},
	"haven_daily_patrol": {
		"id": "haven_daily_patrol",
		"name": "Daily Patrol",
		"description": "Defeat 5 monsters to protect Haven. Can be completed daily.",
		"type": QuestType.KILL_ANY,
		"trading_post": "haven",
		"target": 5,
		"rewards": {"xp": 50, "gold": 25, "gems": 0},
		"is_daily": true,
		"prerequisite": ""
	},

	# ===== CROSSROADS (0, 0) - Royal Herald - Mixed Quests =====
	"crossroads_patrol": {
		"id": "crossroads_patrol",
		"name": "Crossroads Patrol",
		"description": "Help patrol the area by defeating 8 monsters.",
		"type": QuestType.KILL_ANY,
		"trading_post": "crossroads",
		"target": 8,
		"rewards": {"xp": 100, "gold": 50, "gems": 0},
		"is_daily": false,
		"prerequisite": ""
	},
	"crossroads_danger_zone": {
		"id": "crossroads_danger_zone",
		"name": "Into the Danger Zone",
		"description": "Kill 3 monsters (level 3+) in a hotzone within 50 tiles. The Royal Herald offers this bounty daily.",
		"type": QuestType.HOTZONE_KILL,
		"trading_post": "crossroads",
		"target": 3,
		"max_distance": 50.0,
		"min_intensity": 0.0,
		"min_monster_level": 3,
		"rewards": {"xp": 150, "gold": 75, "gems": 0},
		"is_daily": true,
		"prerequisite": ""
	},
	"crossroads_danger_seeker": {
		"id": "crossroads_danger_seeker",
		"name": "Danger Seeker",
		"description": "Kill 5 monsters (level 8+) in hotzones within 75 tiles of Crossroads.",
		"type": QuestType.HOTZONE_KILL,
		"trading_post": "crossroads",
		"target": 5,
		"max_distance": 75.0,
		"min_intensity": 0.0,
		"min_monster_level": 8,
		"rewards": {"xp": 300, "gold": 150, "gems": 1},
		"is_daily": false,
		"prerequisite": "crossroads_patrol"
	},
	"crossroads_risk_reward": {
		"id": "crossroads_risk_reward",
		"name": "Risk and Reward",
		"description": "Kill 10 monsters (level 20+) in hotzones within 150 tiles. Greater risk, greater reward.",
		"type": QuestType.HOTZONE_KILL,
		"trading_post": "crossroads",
		"target": 10,
		"max_distance": 150.0,
		"min_intensity": 0.0,
		"min_monster_level": 20,
		"rewards": {"xp": 600, "gold": 300, "gems": 2},
		"is_daily": false,
		"prerequisite": "crossroads_danger_seeker"
	},
	"crossroads_extreme": {
		"id": "crossroads_extreme",
		"name": "Extreme Challenge",
		"description": "Kill 5 monsters (level 50+) in high-intensity hotzones (0.5+) within 250 tiles. Only for the brave.",
		"type": QuestType.HOTZONE_KILL,
		"trading_post": "crossroads",
		"target": 5,
		"max_distance": 250.0,
		"min_intensity": 0.5,
		"min_monster_level": 50,
		"rewards": {"xp": 1200, "gold": 600, "gems": 4},
		"is_daily": false,
		"prerequisite": "crossroads_risk_reward"
	},

	# ===== SOUTH GATE (0, -25) - Gate Warden - Beginner Quests =====
	"south_gate_watch": {
		"id": "south_gate_watch",
		"name": "South Watch",
		"description": "Help the Gate Warden by defeating 4 monsters near the southern gate.",
		"type": QuestType.KILL_ANY,
		"trading_post": "south_gate",
		"target": 4,
		"rewards": {"xp": 40, "gold": 20, "gems": 0},
		"is_daily": false,
		"prerequisite": ""
	},
	"south_gate_guardian": {
		"id": "south_gate_guardian",
		"name": "Gate Guardian",
		"description": "Protect the gate by slaying 10 monsters.",
		"type": QuestType.KILL_ANY,
		"trading_post": "south_gate",
		"target": 10,
		"rewards": {"xp": 125, "gold": 60, "gems": 0},
		"is_daily": false,
		"prerequisite": "south_gate_watch"
	},
	"south_gate_daily": {
		"id": "south_gate_daily",
		"name": "Gate Duty",
		"description": "Complete your daily gate duty by defeating 4 monsters.",
		"type": QuestType.KILL_ANY,
		"trading_post": "south_gate",
		"target": 4,
		"rewards": {"xp": 35, "gold": 20, "gems": 0},
		"is_daily": true,
		"prerequisite": ""
	},

	# ===== EAST MARKET (25, 10) - Market Master - Collection Quests =====
	"east_market_supply": {
		"id": "east_market_supply",
		"name": "Supply Run",
		"description": "Clear the roads by defeating 6 monsters so merchants can travel safely.",
		"type": QuestType.KILL_ANY,
		"trading_post": "east_market",
		"target": 6,
		"rewards": {"xp": 60, "gold": 35, "gems": 0},
		"is_daily": false,
		"prerequisite": ""
	},
	"east_market_crossroads": {
		"id": "east_market_crossroads",
		"name": "Road to Crossroads",
		"description": "Visit Crossroads to establish a trade route.",
		"type": QuestType.EXPLORATION,
		"trading_post": "east_market",
		"target": 1,
		"destinations": ["crossroads"],
		"rewards": {"xp": 75, "gold": 40, "gems": 0},
		"is_daily": false,
		"prerequisite": "east_market_supply"
	},
	"east_market_daily": {
		"id": "east_market_daily",
		"name": "Merchant Guard",
		"description": "Escort duty - defeat 5 monsters along trade routes.",
		"type": QuestType.KILL_ANY,
		"trading_post": "east_market",
		"target": 5,
		"rewards": {"xp": 45, "gold": 30, "gems": 0},
		"is_daily": true,
		"prerequisite": ""
	},

	# ===== WEST SHRINE (-25, 10) - Shrine Keeper - Beginner Quests =====
	"west_shrine_cleanse": {
		"id": "west_shrine_cleanse",
		"name": "Shrine Cleansing",
		"description": "Clear 5 monsters that threaten the sacred shrine.",
		"type": QuestType.KILL_ANY,
		"trading_post": "west_shrine",
		"target": 5,
		"rewards": {"xp": 50, "gold": 25, "gems": 0},
		"is_daily": false,
		"prerequisite": ""
	},
	"west_shrine_pilgrimage": {
		"id": "west_shrine_pilgrimage",
		"name": "Pilgrimage",
		"description": "Visit Haven to complete your pilgrimage.",
		"type": QuestType.EXPLORATION,
		"trading_post": "west_shrine",
		"target": 1,
		"destinations": ["haven"],
		"rewards": {"xp": 50, "gold": 25, "gems": 0},
		"is_daily": false,
		"prerequisite": "west_shrine_cleanse"
	},
	"west_shrine_daily": {
		"id": "west_shrine_daily",
		"name": "Sacred Duty",
		"description": "Protect the shrine by defeating 4 monsters.",
		"type": QuestType.KILL_ANY,
		"trading_post": "west_shrine",
		"target": 4,
		"rewards": {"xp": 35, "gold": 20, "gems": 0},
		"is_daily": true,
		"prerequisite": ""
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
	},

	# ===== WESTHOLD (-150, 0) - Veteran Warrior - Survival Quests =====
	"westhold_endurance": {
		"id": "westhold_endurance",
		"name": "Test of Endurance",
		"description": "Prove your stamina by defeating 20 monsters without returning to town.",
		"type": QuestType.KILL_ANY,
		"trading_post": "westhold",
		"target": 20,
		"rewards": {"xp": 400, "gold": 200, "gems": 1},
		"is_daily": false,
		"prerequisite": ""
	},
	"westhold_western_wilds": {
		"id": "westhold_western_wilds",
		"name": "Western Wilds",
		"description": "Venture to Far West Haven and report back.",
		"type": QuestType.EXPLORATION,
		"trading_post": "westhold",
		"target": 1,
		"destinations": ["far_west_haven"],
		"rewards": {"xp": 800, "gold": 400, "gems": 2},
		"is_daily": false,
		"prerequisite": "westhold_endurance"
	},

	# ===== SOUTHPORT (0, -150) - Sea Captain - Collection/Exploration =====
	"southport_southern_seas": {
		"id": "southport_southern_seas",
		"name": "Southern Expedition",
		"description": "Chart a course to the Deep South Port.",
		"type": QuestType.EXPLORATION,
		"trading_post": "southport",
		"target": 1,
		"destinations": ["deep_south_port"],
		"rewards": {"xp": 600, "gold": 300, "gems": 1},
		"is_daily": false,
		"prerequisite": ""
	},
	"southport_sea_monsters": {
		"id": "southport_sea_monsters",
		"name": "Sea Monster Bounty",
		"description": "Defeat 15 monsters level 40+ in the southern regions.",
		"type": QuestType.KILL_LEVEL,
		"trading_post": "southport",
		"target": 40,
		"kill_count": 15,
		"rewards": {"xp": 1000, "gold": 500, "gems": 2},
		"is_daily": false,
		"prerequisite": "southport_southern_seas"
	},

	# ===== NORTHWATCH (0, 75) - Scout Leader - Scouting =====
	"northwatch_scout_training": {
		"id": "northwatch_scout_training",
		"name": "Scout Training",
		"description": "Complete basic scout training by defeating 8 monsters.",
		"type": QuestType.KILL_ANY,
		"trading_post": "northwatch",
		"target": 8,
		"rewards": {"xp": 100, "gold": 50, "gems": 0},
		"is_daily": false,
		"prerequisite": ""
	},
	"northwatch_highland_recon": {
		"id": "northwatch_highland_recon",
		"name": "Highland Reconnaissance",
		"description": "Scout the Highland Post to the north.",
		"type": QuestType.EXPLORATION,
		"trading_post": "northwatch",
		"target": 1,
		"destinations": ["highland_post"],
		"rewards": {"xp": 300, "gold": 150, "gems": 1},
		"is_daily": false,
		"prerequisite": "northwatch_scout_training"
	},

	# ===== EASTERN_CAMP (75, 0) - Camp Commander - Combat =====
	"eastern_camp_drill": {
		"id": "eastern_camp_drill",
		"name": "Combat Drill",
		"description": "Defeat 12 monsters to complete your combat drill.",
		"type": QuestType.KILL_ANY,
		"trading_post": "eastern_camp",
		"target": 12,
		"rewards": {"xp": 150, "gold": 75, "gems": 0},
		"is_daily": false,
		"prerequisite": ""
	},
	"eastern_camp_eastwatch_run": {
		"id": "eastern_camp_eastwatch_run",
		"name": "Eastwatch Run",
		"description": "Deliver supplies to Eastwatch fortress.",
		"type": QuestType.EXPLORATION,
		"trading_post": "eastern_camp",
		"target": 1,
		"destinations": ["eastwatch"],
		"rewards": {"xp": 350, "gold": 175, "gems": 1},
		"is_daily": false,
		"prerequisite": "eastern_camp_drill"
	},

	# ===== WESTERN_REFUGE (-75, 0) - Hermit Sage - Wisdom =====
	"western_refuge_meditation": {
		"id": "western_refuge_meditation",
		"name": "Meditation Journey",
		"description": "Seek wisdom by visiting Westhold.",
		"type": QuestType.EXPLORATION,
		"trading_post": "western_refuge",
		"target": 1,
		"destinations": ["westhold"],
		"rewards": {"xp": 250, "gold": 125, "gems": 0},
		"is_daily": false,
		"prerequisite": ""
	},

	# ===== HIGHLAND_POST (0, 150) - Mountain Guide - Climbing =====
	"highland_climbing": {
		"id": "highland_climbing",
		"name": "Mountain Trials",
		"description": "Defeat 25 monsters in the highland regions.",
		"type": QuestType.KILL_ANY,
		"trading_post": "highland_post",
		"target": 25,
		"rewards": {"xp": 500, "gold": 250, "gems": 1},
		"is_daily": false,
		"prerequisite": ""
	},
	"highland_peak_journey": {
		"id": "highland_peak_journey",
		"name": "Journey to High North Peak",
		"description": "Climb to the High North Peak trading post.",
		"type": QuestType.EXPLORATION,
		"trading_post": "highland_post",
		"target": 1,
		"destinations": ["high_north_peak"],
		"rewards": {"xp": 1200, "gold": 600, "gems": 3},
		"is_daily": false,
		"prerequisite": "highland_climbing"
	},

	# ===== FAR_EAST_STATION (250, 0) - Station Master - Expeditions =====
	"far_east_expedition": {
		"id": "far_east_expedition",
		"name": "Eastern Frontier",
		"description": "Push to Void's Edge at the edge of the world.",
		"type": QuestType.EXPLORATION,
		"trading_post": "far_east_station",
		"target": 1,
		"destinations": ["voids_edge"],
		"rewards": {"xp": 2000, "gold": 1000, "gems": 5},
		"is_daily": false,
		"prerequisite": ""
	},
	"far_east_elite_hunt": {
		"id": "far_east_elite_hunt",
		"name": "Elite Eastern Hunt",
		"description": "Defeat a monster of level 150 or higher.",
		"type": QuestType.BOSS_HUNT,
		"trading_post": "far_east_station",
		"target": 150,
		"rewards": {"xp": 3000, "gold": 1500, "gems": 7},
		"is_daily": false,
		"prerequisite": ""
	},

	# ===== FAR_WEST_HAVEN (-250, 0) - Haven Watcher - Vigilance =====
	"far_west_vigilance": {
		"id": "far_west_vigilance",
		"name": "Vigilant Watch",
		"description": "Eliminate 30 monsters threatening the western frontier.",
		"type": QuestType.KILL_ANY,
		"trading_post": "far_west_haven",
		"target": 30,
		"rewards": {"xp": 1500, "gold": 750, "gems": 3},
		"is_daily": false,
		"prerequisite": ""
	},
	"far_west_inferno_path": {
		"id": "far_west_inferno_path",
		"name": "Path to the Inferno",
		"description": "Journey to the Inferno Outpost near Fire Mountain.",
		"type": QuestType.EXPLORATION,
		"trading_post": "far_west_haven",
		"target": 1,
		"destinations": ["inferno_outpost"],
		"rewards": {"xp": 2500, "gold": 1250, "gems": 6},
		"is_daily": false,
		"prerequisite": "far_west_vigilance"
	},

	# ===== SHADOWMERE (300, 300) - Dark Warden - Challenge =====
	"shadowmere_worthy": {
		"id": "shadowmere_worthy",
		"name": "Prove Your Worth",
		"description": "Defeat a monster of level 250 or higher.",
		"type": QuestType.BOSS_HUNT,
		"trading_post": "shadowmere",
		"target": 250,
		"rewards": {"xp": 5000, "gold": 2500, "gems": 10},
		"is_daily": false,
		"prerequisite": ""
	},
	"shadowmere_ultimate": {
		"id": "shadowmere_ultimate",
		"name": "Ultimate Challenge",
		"description": "Defeat a monster of level 500 or higher. Only legends attempt this.",
		"type": QuestType.BOSS_HUNT,
		"trading_post": "shadowmere",
		"target": 500,
		"rewards": {"xp": 15000, "gold": 7500, "gems": 25},
		"is_daily": false,
		"prerequisite": "shadowmere_worthy"
	},

	# ===== DRAGONS_REST (300, -300) - Dragon Sage - Legendary =====
	"dragons_rest_legacy": {
		"id": "dragons_rest_legacy",
		"name": "Dragon's Legacy",
		"description": "Defeat 50 monsters level 200+ to honor the dragon's memory.",
		"type": QuestType.KILL_LEVEL,
		"trading_post": "dragons_rest",
		"target": 200,
		"kill_count": 50,
		"rewards": {"xp": 10000, "gold": 5000, "gems": 15},
		"is_daily": false,
		"prerequisite": ""
	},

	# ===== STORM_PEAK (0, 350) - Storm Caller - Elemental =====
	"storm_peak_ascent": {
		"id": "storm_peak_ascent",
		"name": "Storm Ascent",
		"description": "Prove yourself by defeating 40 monsters in the storm regions.",
		"type": QuestType.KILL_ANY,
		"trading_post": "storm_peak",
		"target": 40,
		"rewards": {"xp": 3500, "gold": 1750, "gems": 8},
		"is_daily": false,
		"prerequisite": ""
	},

	# ===== FROZEN_REACH (0, -400) - Frost Hermit - Extreme =====
	"frozen_extreme": {
		"id": "frozen_extreme",
		"name": "Frozen Extremity",
		"description": "Survive 10 encounters with monsters (level 150+) in high-intensity hotzones within 100 tiles.",
		"type": QuestType.HOTZONE_KILL,
		"trading_post": "frozen_reach",
		"target": 10,
		"max_distance": 100.0,
		"min_intensity": 0.5,
		"min_monster_level": 150,
		"rewards": {"xp": 8000, "gold": 4000, "gems": 15},
		"is_daily": false,
		"prerequisite": ""
	}
}

func get_quest(quest_id: String, player_level: int = -1, quests_completed_at_post: int = 0) -> Dictionary:
	"""Get quest data by ID. Returns empty dict if not found.
	For dynamic quests, pass player_level and quests_completed_at_post to get accurate scaling."""
	if QUESTS.has(quest_id):
		var quest = QUESTS[quest_id].duplicate(true)
		# Scale rewards based on trading post area level
		var area_level = _get_area_level_for_post(quest.trading_post)
		return _scale_quest_rewards(quest, area_level)

	# Handle dynamic quest IDs (format: postid_dynamic_tier_index)
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
	var base_gold = int(distance)
	var gems = max(0, int(distance / 100))

	return {
		"id": quest_id,
		"name": "Journey to " + dest_name,
		"description": "Travel to %s to expand your horizons. (Recommended Level: %d)" % [dest_name, recommended_level],
		"type": QuestType.EXPLORATION,
		"trading_post": "",  # Origin unknown when regenerating
		"target": 1,
		"destinations": [dest_post_id],
		"rewards": {"xp": base_xp, "gold": base_gold, "gems": gems},
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
	"""Scale quest rewards based on the trading post's area level.

	This ensures that quests at higher-level trading posts give appropriate rewards.
	For example, 'Scout Training' at Northwatch (level 37 area) will give ~700 XP
	instead of the base 100 XP designed for Haven (level 5 area).
	"""
	# Base level for reward scaling (Haven area is ~level 5)
	const BASE_LEVEL = 5.0

	# Don't scale if we're at or below base level
	if area_level <= BASE_LEVEL:
		quest["area_level"] = area_level
		quest["reward_tier"] = "beginner"
		return quest

	# Calculate scaling factor based on area level
	# Level 37 area (Northwatch) = 37/5 = 7.4x multiplier
	# Cap at 200x for extremely high-level areas
	var scale_factor = min(200.0, float(area_level) / BASE_LEVEL)

	# Scale XP and gold proportionally
	var original_xp = quest.rewards.get("xp", 0)
	var original_gold = quest.rewards.get("gold", 0)
	var original_gems = quest.rewards.get("gems", 0)

	var scaled_rewards = {
		"xp": int(original_xp * scale_factor),
		"gold": int(original_gold * scale_factor),
		"gems": original_gems + int((scale_factor - 1) / 5)  # Gems scale slower
	}

	quest.rewards = scaled_rewards
	quest["area_level"] = area_level
	quest["original_rewards"] = {"xp": original_xp, "gold": original_gold, "gems": original_gems}

	# Determine reward tier for display
	if scale_factor < 2.0:
		quest["reward_tier"] = "beginner"
	elif scale_factor < 5.0:
		quest["reward_tier"] = "standard"
	elif scale_factor < 15.0:
		quest["reward_tier"] = "veteran"
	elif scale_factor < 50.0:
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

func get_available_quests_for_player(trading_post_id: String, completed_quests: Array, active_quest_ids: Array, daily_cooldowns: Dictionary, player_level: int = 1) -> Array:
	"""Get quests available for a player at a Trading Post, considering prerequisites, cooldowns, and player level.
	Quests are scaled to player level with progressive difficulty."""
	var available = []
	var current_time = Time.get_unix_time_from_system()
	var area_level = _get_area_level_for_post(trading_post_id)

	# Count completed quests at this post to determine difficulty progression
	var completed_at_post = 0
	for quest_id in QUESTS:
		if QUESTS[quest_id].trading_post == trading_post_id and quest_id in completed_quests:
			completed_at_post += 1

	# Get static quests for this trading post
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

		# Scale quest rewards AND requirements based on player level and progression
		var scaled_quest = _scale_quest_for_player(quest.duplicate(true), player_level, completed_at_post, area_level)
		available.append(scaled_quest)

	# If no static quests available, generate dynamic quests scaled to player
	if available.is_empty():
		var dynamic_quests = generate_dynamic_quests(trading_post_id, completed_quests, active_quest_ids, player_level, completed_at_post)
		available.append_array(dynamic_quests)

	return available

func _scale_quest_for_player(quest: Dictionary, player_level: int, quests_completed_at_post: int, area_level: int) -> Dictionary:
	"""Scale quest requirements and rewards based on player level and progression.
	Quests get progressively harder as player completes more at the same post."""

	# First scale rewards
	quest = _scale_quest_rewards(quest, area_level)

	# Calculate difficulty modifier based on progression (0.0 to 0.5 bonus)
	# More completed quests = harder requirements, pushing toward next post
	var progression_modifier = min(0.5, quests_completed_at_post * 0.05)

	# Base target level on player level with progression
	var base_level = player_level
	var target_level = int(base_level * (1.0 + progression_modifier))

	# Scale kill requirements based on quest type
	var quest_type = quest.get("type", -1)

	match quest_type:
		QuestType.KILL_ANY:
			# Scale kill count: base + (player_level / 10) + progression bonus
			var base_target = quest.get("target", 5)
			var scaled_target = base_target + int(player_level / 10) + quests_completed_at_post
			quest["target"] = max(base_target, min(scaled_target, base_target * 3))  # Cap at 3x original
			quest["description"] = "Defeat %d monsters." % quest["target"]

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
			# Boss level scales with player level + significant progression bonus
			var boss_level = int(target_level * (1.0 + progression_modifier * 0.5))
			quest["target"] = boss_level
			quest["description"] = "Defeat a powerful monster of level %d or higher." % boss_level

	# Mark quest as scaled
	quest["player_level_scaled"] = player_level
	quest["difficulty_tier"] = quests_completed_at_post

	return quest

# ===== DYNAMIC QUEST GENERATION =====

# Trading post locations for distance calculations
const TRADING_POST_COORDS = {
	"haven": Vector2i(0, 10),
	"crossroads": Vector2i(0, 0),
	"south_gate": Vector2i(0, -25),
	"east_market": Vector2i(25, 10),
	"west_shrine": Vector2i(-25, 10),
	"northwatch": Vector2i(0, 75),
	"eastern_camp": Vector2i(75, 0),
	"western_refuge": Vector2i(-75, 0),
	"frostgate": Vector2i(0, -100),
	"highland_post": Vector2i(0, 150),
	"eastwatch": Vector2i(150, 0),
	"westhold": Vector2i(-150, 0),
	"southport": Vector2i(0, -150),
	"northeast_bastion": Vector2i(120, 120),
	"northwest_lodge": Vector2i(-120, 120),
	"southeast_outpost": Vector2i(120, -120),
	"southwest_camp": Vector2i(-120, -120),
	"far_east_station": Vector2i(250, 0),
	"far_west_haven": Vector2i(-250, 0),
	"deep_south_port": Vector2i(0, -275),
	"high_north_peak": Vector2i(0, 250),
	"northeast_frontier": Vector2i(200, 200),
	"northwest_citadel": Vector2i(-200, 200),
	"southeast_garrison": Vector2i(200, -200),
	"southwest_fortress": Vector2i(-200, -200),
	"shadowmere": Vector2i(300, 300),
	"inferno_outpost": Vector2i(-350, 0),
	"voids_edge": Vector2i(350, 0),
	"frozen_reach": Vector2i(0, -400),
	"abyssal_depths": Vector2i(-300, -300),
	"celestial_spire": Vector2i(-300, 300),
	"storm_peak": Vector2i(0, 350),
	"dragons_rest": Vector2i(300, -300)
}

func generate_dynamic_quests(trading_post_id: String, completed_quests: Array, active_quest_ids: Array, player_level: int = 1, quests_completed_at_post: int = 0) -> Array:
	"""Generate procedural quests scaled to player level when all static quests are completed."""
	var quests = []

	# Count completed dynamic quests from this post
	var dynamic_completed = 0
	for quest_id in completed_quests:
		if quest_id.begins_with(trading_post_id + "_dynamic_"):
			dynamic_completed += 1

	# Calculate tier based on completions
	var tier = dynamic_completed + 1

	# Get this trading post's coordinates
	var post_coords = TRADING_POST_COORDS.get(trading_post_id, Vector2i(0, 0))
	var post_distance = sqrt(post_coords.x * post_coords.x + post_coords.y * post_coords.y)

	# Calculate difficulty modifier based on progression
	var progression_modifier = min(0.5, (quests_completed_at_post + dynamic_completed) * 0.05)

	# Generate 2-3 quests of increasing difficulty, scaled to player level
	for i in range(3):
		var quest_tier = tier + i
		var quest_id = "%s_dynamic_%d_%d" % [trading_post_id, tier, i]

		# Skip if already active or completed
		if quest_id in active_quest_ids or quest_id in completed_quests:
			continue

		var quest = _generate_quest_for_tier_scaled(trading_post_id, quest_id, quest_tier, post_distance, player_level, progression_modifier)
		if not quest.is_empty():
			quests.append(quest)

	return quests

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
	var base_gold = int(50 + (75 * tier * tier_multiplier))
	var gems = max(0, int((tier - 2) * tier_multiplier))  # Gems start at tier 3

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
		"rewards": {"xp": base_xp, "gold": base_gold, "gems": gems},
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
	"""Generate a single quest based on tier, scaled to player level and progression."""

	# Base difficulty on player level instead of just post distance
	var effective_level = player_level * (1.0 + progression_modifier)

	# Tier multiplier for progressive difficulty within the post
	var tier_multiplier: float
	if tier <= 3:
		tier_multiplier = 0.8 + (tier - 1) * 0.1  # 0.8, 0.9, 1.0
	elif tier <= 7:
		tier_multiplier = 1.0 + (tier - 3) * 0.15   # 1.0, 1.15, 1.3, 1.45
	else:
		tier_multiplier = 1.45 + (tier - 7) * 0.2  # 1.45, 1.65, 1.85...

	# Scale requirements to player level
	var kill_count = int(5 + (tier * 2) + (player_level / 20))  # Scales slowly with level
	var min_monster_level = int(effective_level * 0.7 * tier_multiplier)  # 70-100%+ of player level
	var hotzone_distance = 30.0 + (tier * 20.0) + (player_level / 5)  # Distance increases with level
	var hotzone_kills = int(3 + tier + (player_level / 30))
	var hotzone_min_level = int(effective_level * 0.6 * tier_multiplier)  # 60%+ of player level

	# Rewards scale with player level and tier
	var level_reward_mult = 1.0 + (player_level / 50.0)  # +2% per level
	var base_xp = int((80 + (100 * tier)) * level_reward_mult * tier_multiplier)
	var base_gold = int((40 + (50 * tier)) * level_reward_mult * tier_multiplier)
	var gems = max(0, int((tier - 2 + player_level / 50) * tier_multiplier))  # Gems scale with level too

	# Quest type varies by tier - simpler quests early
	var quest_type: int
	var quest_name: String
	var quest_desc: String
	var target: int

	# Early tiers prefer simpler KILL_ANY quests
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
			quest_desc = "Defeat a monster of level %d or higher." % min_monster_level
			target = min_monster_level
		2:  # Hotzone quest
			quest_type = QuestType.HOTZONE_KILL
			quest_name = "Danger Zone Bounty %d" % tier
			quest_desc = "Kill %d monsters (level %d+) in hotzones within %.0f tiles." % [hotzone_kills, hotzone_min_level, hotzone_distance]
			target = hotzone_kills
		3:  # Boss hunt - scale to push player toward next post
			var boss_level = int(effective_level * (1.1 + progression_modifier))  # 10%+ above player level
			quest_type = QuestType.BOSS_HUNT
			quest_name = "Elite Hunt %d" % tier
			quest_desc = "Track down and defeat a monster of level %d or higher." % boss_level
			target = boss_level

	# Calculate area level for display
	var area_level = max(1, int(post_distance * 0.5))

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
		"rewards": {"xp": base_xp, "gold": base_gold, "gems": gems},
		"is_daily": false,
		"prerequisite": "",
		"is_dynamic": true,
		"area_level": area_level,
		"reward_tier": reward_tier,
		"player_level_scaled": player_level,
		"difficulty_tier": tier
	}

	# Add hotzone-specific fields
	if quest_type == QuestType.HOTZONE_KILL:
		quest["max_distance"] = hotzone_distance
		quest["min_intensity"] = 0.0 if tier < 5 else 0.3
		quest["min_monster_level"] = hotzone_min_level

	return quest

func get_all_quest_ids() -> Array:
	"""Get array of all quest IDs."""
	return QUESTS.keys()

func is_quest_type_kill(quest_type: int) -> bool:
	"""Check if quest type involves killing monsters."""
	return quest_type in [QuestType.KILL_ANY, QuestType.KILL_TYPE, QuestType.KILL_LEVEL, QuestType.HOTZONE_KILL, QuestType.BOSS_HUNT]

func is_quest_type_exploration(quest_type: int) -> bool:
	"""Check if quest type involves exploration."""
	return quest_type == QuestType.EXPLORATION
