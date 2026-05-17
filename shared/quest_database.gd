# quest_database.gd
# Quest definitions and constants
class_name QuestDatabase
extends Node

const DungeonDatabaseScript = preload("res://shared/dungeon_database.gd")

# Audit #6 Slice 13 (supersedes Slice 12). The original audit signal said
# "daily stuff isn't engaging" — Slice 12 misread that as "daily kill-tasks
# are unengaging, kill them" and gated dailies entirely. User clarified
# (2026-05-15): the real complaint is the daily *cap* — "do a couple of
# quests then have to wait until the next day to continue. It's better to
# generate quests so they don't end." Slice 13 unblocks generation and makes
# the board *continuously regenerate* — completing a quest immediately fills
# its slot with a fresh procedural one. See _generate_dynamic_board_indices.
# Flag retained as a safety: setting false reverts to no procedural quests
# (chains-only), matching Slice 12's behavior.
const DYNAMIC_DAILIES_ENABLED: bool = true

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
	GATHER,             # 9 - Gather X materials through fishing/mining/logging/foraging
	DELIVER             # 10 - Audit #6 Slice 9: deliver X of an item (loot/craft/buy — any path)
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

# Audit #6 Slice 10 — Chain titles. Flair-only cosmetic titles awarded as a
# chain_bonus field on the final-stage quest. Independent of the unique
# realm titles (Jarl/High King/Elder/Eternal) in shared/titles.gd — those
# carry mechanical effects and uniqueness; these are pure identity flair.
# Storage: character.earned_titles array. Display: /titles command + optional
# active_chain_title (future slice).
const CHAIN_TITLES = {
	"goblin_bane":        {"name": "Goblin Bane",        "color": "#FF7F00"},
	"crypt_cleanser":     {"name": "Crypt Cleanser",     "color": "#C0C0C0"},
	"pack_hunter":        {"name": "Pack Hunter",        "color": "#8B4513"},
	"rat_slayer":         {"name": "Rat Slayer",         "color": "#7FBF3F"},
	"tunnel_crawler":     {"name": "Tunnel Crawler",     "color": "#A0522D"},
	"web_severer":        {"name": "Web Severer",        "color": "#A335EE"},
	"orc_slayer":         {"name": "Orc Slayer",         "color": "#660000"},
	"iron_breaker":       {"name": "Iron-Breaker",       "color": "#D8D8C8"},
	"mimic_hunter":       {"name": "Mimic Hunter",       "color": "#FFAA00"},
	"barrow_walker":      {"name": "Barrow Walker",      "color": "#9370DB"},
	"pack_master":        {"name": "Pack Master",        "color": "#3CB371"},
	"smiths_friend":      {"name": "Smith's Friend",     "color": "#FFA500"},
	"apothecarys_friend": {"name": "Apothecary's Friend", "color": "#00FF00"},
	"trappers_friend":    {"name": "Trapper's Friend",   "color": "#CD853F"},
	# Audit #6 Slice 14 — T3 chain titles.
	"troll_render":       {"name": "Troll Render",       "color": "#5D4037"},
	"stone_breaker":      {"name": "Stone Breaker",      "color": "#F0E68C"},
	# Audit #6 Slice 15 — T4 chain titles.
	"vampire_hunter":     {"name": "Vampire Hunter",     "color": "#8B0000"},
	"brood_breaker":      {"name": "Brood Breaker",      "color": "#FF8C00"},
	# Audit #6 Slice 16 — T5 chain titles.
	"lich_ender":         {"name": "Lich Ender",         "color": "#7755BB"},
	"demon_slayer":       {"name": "Demon Slayer",       "color": "#FF4500"},
	# Audit #6 Slice 17 — T6 chain titles.
	"hydra_slayer":       {"name": "Hydra Slayer",       "color": "#48D1CC"},
	"phoenix_ender":      {"name": "Phoenix Ender",      "color": "#FFA500"},
	# Audit #6 Slice 18 — T7 chain titles.
	"void_ender":         {"name": "Void Ender",         "color": "#4B0082"},
	"primordial_breaker": {"name": "Primordial Breaker", "color": "#9400D3"},
	# Audit #6 Slice 18 — T8 chain titles.
	"horror_sealer":      {"name": "Horror Sealer",      "color": "#191970"},
	"death_defier":       {"name": "Death Defier",       "color": "#2C0854"},
	# Audit #6 Slice 18 — T9 chain titles.
	"chaos_unmaker":      {"name": "Chaos Unmaker",      "color": "#800080"},
	"end_walker":         {"name": "End Walker",         "color": "#C5B358"},
}

static func get_chain_title(title_id: String) -> Dictionary:
	return CHAIN_TITLES.get(title_id, {})

# Audit #6 Slice 1 — Quest chains. Each chain is a sequence of static quest
# definitions linked by `next_in_chain`. Stage 1 quests are offered at the
# named trading post; later stages are auto-added to active_quests when the
# previous stage is turned in. Chains are one-shot per character: completing
# the final stage marks the chain as done in completed_chains.
#
# Schema additions for chain quests:
#   chain_id:    String — chain identifier
#   chain_stage: int — current stage (1-indexed)
#   chain_total: int — total stages in the chain
#   next_in_chain: String — quest_id of the next stage (empty on final)
#   chain_bonus: Dictionary — extra rewards on top of base, granted only on
#                final-stage turn-in. Currently {valor, gold, item_type, ...}
const QUESTS = {
	"goblin_menace_1": {
		"id": "goblin_menace_1",
		"name": "The Goblin Menace I — Cull the Pests",
		"description": "Goblin scouts have been spotted near Haven. Cull 5 of them to send a message.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 300 valor + Goblin Egg[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "haven",
		"target": 5,
		"monster_type": "Goblin",
		"rewards": {"xp": 150, "valor": 25},
		"is_daily": false,
		"prerequisite": "",
		"chain_id": "goblin_menace",
		"chain_stage": 1,
		"chain_total": 3,
		"next_in_chain": "goblin_menace_2",
		"chain_bonus": {}
	},
	"goblin_menace_2": {
		"id": "goblin_menace_2",
		"name": "The Goblin Menace II — Break the Vanguard",
		"description": "The goblins have called in their hobgoblin lieutenants. Defeat 3 hobgoblins to break their vanguard.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 300 valor + Goblin Egg[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "haven",
		"target": 3,
		"monster_type": "Hobgoblin",
		"rewards": {"xp": 280, "valor": 40},
		"is_daily": false,
		"prerequisite": "goblin_menace_1",
		"chain_id": "goblin_menace",
		"chain_stage": 2,
		"chain_total": 3,
		"next_in_chain": "goblin_menace_3",
		"chain_bonus": {}
	},
	"goblin_menace_3": {
		"id": "goblin_menace_3",
		"name": "The Goblin Menace III — Slay the King",
		"description": "Their king rallies the warbands from the Goblin Caves. Find the dungeon and slay the Goblin King to end the threat.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 300 valor + Goblin Egg + Home Stones (Egg + Companion)[/color]",
		"type": QuestType.BOSS_HUNT,
		"trading_post": "haven",
		"target": 1,
		"bounty_name": "Goblin King",
		"rewards": {"xp": 500, "valor": 60},
		"is_daily": false,
		"prerequisite": "goblin_menace_2",
		"chain_id": "goblin_menace",
		"chain_stage": 3,
		"chain_total": 3,
		"next_in_chain": "",
		# Audit #6 v0.9.517 — Repeatable starter chain. 24h cooldown after turn-in,
		# then the goblin_menace_1 starter reappears at Haven.
		"repeatable": true,
		# Bonus dispensed on top of base rewards on final-stage turn-in
		"chain_bonus": {"valor": 240, "egg": "Goblin", "home_stones": ["home_stone_egg", "home_stone_companion"], "chain_title": "goblin_bane"}
	},
	# ===== "The Skeleton Lord's Curse" — Haven, 2 stages =====
	"skeleton_lord_1": {
		"id": "skeleton_lord_1",
		"name": "The Skeleton Lord's Curse I — Restless Bones",
		"description": "An old curse stirs the dead in nearby crypts. Defeat 5 Skeletons to thin the rising horde.\n\n[color=#FFAA00]CHAIN: 2 stages | Final reward: 200 valor + Skeleton Egg[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "haven",
		"target": 5,
		"monster_type": "Skeleton",
		"rewards": {"xp": 200, "valor": 30},
		"is_daily": false,
		"prerequisite": "",
		"chain_id": "skeleton_lord",
		"chain_stage": 1,
		"chain_total": 2,
		"next_in_chain": "skeleton_lord_2",
		"chain_bonus": {}
	},
	"skeleton_lord_2": {
		"id": "skeleton_lord_2",
		"name": "The Skeleton Lord's Curse II — End the Lord",
		"description": "The curse's anchor walks the Forgotten Crypt. Find the dungeon and put the Skeleton Lord to rest — for good this time.\n\n[color=#FFAA00]CHAIN: 2 stages | Final reward: 200 valor + Skeleton Egg + Home Stones (Egg + Companion)[/color]",
		"type": QuestType.BOSS_HUNT,
		"trading_post": "haven",
		"target": 1,
		"bounty_name": "Skeleton Lord",
		"rewards": {"xp": 450, "valor": 50},
		"is_daily": false,
		"prerequisite": "skeleton_lord_1",
		"chain_id": "skeleton_lord",
		"chain_stage": 2,
		"chain_total": 2,
		"next_in_chain": "",
		# Audit #6 v0.9.517 — Repeatable T1 starter chain.
		"repeatable": true,
		"chain_bonus": {"valor": 150, "egg": "Skeleton", "home_stones": ["home_stone_egg", "home_stone_companion"], "chain_title": "crypt_cleanser"}
	},
	# ===== "The Wolf Pack" — Crossroads, 3 stages =====
	"wolf_pack_1": {
		"id": "wolf_pack_1",
		"name": "The Wolf Pack I — Wolves at the Door",
		"description": "Wolves are circling the Crossroads at night. Cull 4 of them to drive the pack back.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 250 valor + Wolf Egg[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "crossroads",
		"target": 4,
		"monster_type": "Wolf",
		"rewards": {"xp": 150, "valor": 25},
		"is_daily": false,
		"prerequisite": "",
		"chain_id": "wolf_pack",
		"chain_stage": 1,
		"chain_total": 3,
		"next_in_chain": "wolf_pack_2",
		"chain_bonus": {}
	},
	"wolf_pack_2": {
		"id": "wolf_pack_2",
		"name": "The Wolf Pack II — Clear the Vermin",
		"description": "The wolves were drawn by carrion — and the rats followed. Clear 3 Giant Rats from the area to break the chain.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 250 valor + Wolf Egg[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "crossroads",
		"target": 3,
		"monster_type": "Giant Rat",
		"rewards": {"xp": 220, "valor": 35},
		"is_daily": false,
		"prerequisite": "wolf_pack_1",
		"chain_id": "wolf_pack",
		"chain_stage": 2,
		"chain_total": 3,
		"next_in_chain": "wolf_pack_3",
		"chain_bonus": {}
	},
	"wolf_pack_3": {
		"id": "wolf_pack_3",
		"name": "The Wolf Pack III — The Alpha",
		"description": "The pack's alpha leads them from the Wolf Den. Find the dungeon and slay the Alpha Wolf to scatter the pack permanently.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 250 valor + Wolf Egg + Home Stones (Egg + Companion)[/color]",
		"type": QuestType.BOSS_HUNT,
		"trading_post": "crossroads",
		"target": 1,
		"bounty_name": "Alpha Wolf",
		"rewards": {"xp": 500, "valor": 60},
		"is_daily": false,
		"prerequisite": "wolf_pack_2",
		"chain_id": "wolf_pack",
		"chain_stage": 3,
		"chain_total": 3,
		"next_in_chain": "",
		# Audit #6 v0.9.517 — Repeatable T1 starter chain.
		"repeatable": true,
		"chain_bonus": {"valor": 200, "egg": "Wolf", "home_stones": ["home_stone_egg", "home_stone_companion"], "chain_title": "pack_hunter"}
	},
	# ===== "The Web Spreads" — East Market, 2 stages, T2 =====
	"web_spreads_1": {
		"id": "web_spreads_1",
		"name": "The Web Spreads I — Crawling Threats",
		"description": "Giant Spiders have begun nesting in the woods east of the market. Cull 4 of them before the infestation reaches town.\n\n[color=#FFAA00]CHAIN: 2 stages | Final reward: 350 valor + Giant Spider Egg[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "east_market",
		"target": 4,
		"monster_type": "Giant Spider",
		"rewards": {"xp": 320, "valor": 45},
		"is_daily": false,
		"prerequisite": "",
		"chain_id": "web_spreads",
		"chain_stage": 1,
		"chain_total": 2,
		"next_in_chain": "web_spreads_2",
		"chain_bonus": {}
	},
	"web_spreads_2": {
		"id": "web_spreads_2",
		"name": "The Web Spreads II — Sever the Queen",
		"description": "The brood-mother lairs in the Spider Nest. Find the dungeon, push through her webs, and slay the Spider Queen.\n\n[color=#FFAA00]CHAIN: 2 stages | Final reward: 350 valor + Giant Spider Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.BOSS_HUNT,
		"trading_post": "east_market",
		"target": 1,
		"bounty_name": "Spider Queen",
		"rewards": {"xp": 600, "valor": 75},
		"is_daily": false,
		"prerequisite": "web_spreads_1",
		"chain_id": "web_spreads",
		"chain_stage": 2,
		"chain_total": 2,
		"next_in_chain": "",
		"chain_bonus": {"valor": 275, "egg": "Giant Spider", "home_stones": ["home_stone_egg", "home_stone_equipment"], "chain_title": "web_severer"}
	},
	# ===== "Rat Plague" — Haven, 2 stages, T1 =====
	"rat_plague_1": {
		"id": "rat_plague_1",
		"name": "Rat Plague I — Cull the Vermin",
		"description": "Giant Rats have overrun Haven's grain stores. Kill 6 of them before the harvest is ruined.\n\n[color=#FFAA00]CHAIN: 2 stages | Final reward: 200 valor + Giant Rat Egg[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "haven",
		"target": 6,
		"monster_type": "Giant Rat",
		"rewards": {"xp": 180, "valor": 28},
		"is_daily": false,
		"prerequisite": "",
		"chain_id": "rat_plague",
		"chain_stage": 1,
		"chain_total": 2,
		"next_in_chain": "rat_plague_2",
		"chain_bonus": {}
	},
	"rat_plague_2": {
		"id": "rat_plague_2",
		"name": "Rat Plague II — The King of Wretches",
		"description": "The swarm answers to a single bloated lord nesting in the Rat Warrens. Find the dungeon and slay the Rat King to scatter what remains.\n\n[color=#FFAA00]CHAIN: 2 stages | Final reward: 200 valor + Giant Rat Egg + Home Stones (Egg + Companion)[/color]",
		"type": QuestType.BOSS_HUNT,
		"trading_post": "haven",
		"target": 1,
		"bounty_name": "Rat King",
		"rewards": {"xp": 425, "valor": 50},
		"is_daily": false,
		"prerequisite": "rat_plague_1",
		"chain_id": "rat_plague",
		"chain_stage": 2,
		"chain_total": 2,
		"next_in_chain": "",
		# Audit #6 v0.9.517 — Repeatable T1 starter chain.
		"repeatable": true,
		"chain_bonus": {"valor": 150, "egg": "Giant Rat", "home_stones": ["home_stone_egg", "home_stone_companion"], "chain_title": "rat_slayer"}
	},
	# ===== "Kobold Trouble" — Crossroads, 2 stages, T1 =====
	"kobold_trouble_1": {
		"id": "kobold_trouble_1",
		"name": "Kobold Trouble I — Trap-Happy Pests",
		"description": "Kobolds keep raiding caravans on the road. Cull 5 of them and reclaim what they've stolen.\n\n[color=#FFAA00]CHAIN: 2 stages | Final reward: 200 valor + Kobold Egg[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "crossroads",
		"target": 5,
		"monster_type": "Kobold",
		"rewards": {"xp": 175, "valor": 28},
		"is_daily": false,
		"prerequisite": "",
		"chain_id": "kobold_trouble",
		"chain_stage": 1,
		"chain_total": 2,
		"next_in_chain": "kobold_trouble_2",
		"chain_bonus": {}
	},
	"kobold_trouble_2": {
		"id": "kobold_trouble_2",
		"name": "Kobold Trouble II — Trap the Trapper",
		"description": "The chieftain commands the raiders from the Kobold Tunnels. Find the dungeon, navigate his snares, and slay the Kobold Chieftain.\n\n[color=#FFAA00]CHAIN: 2 stages | Final reward: 200 valor + Kobold Egg + Home Stones (Egg + Companion)[/color]",
		"type": QuestType.BOSS_HUNT,
		"trading_post": "crossroads",
		"target": 1,
		"bounty_name": "Kobold Chieftain",
		"rewards": {"xp": 425, "valor": 50},
		"is_daily": false,
		"prerequisite": "kobold_trouble_1",
		"chain_id": "kobold_trouble",
		"chain_stage": 2,
		"chain_total": 2,
		"next_in_chain": "",
		# Audit #6 v0.9.517 — Repeatable T1 starter chain.
		"repeatable": true,
		"chain_bonus": {"valor": 150, "egg": "Kobold", "home_stones": ["home_stone_egg", "home_stone_companion"], "chain_title": "tunnel_crawler"}
	},
	# ===== "Orc Threat" — East Market, 3 stages, T2 =====
	"orc_threat_1": {
		"id": "orc_threat_1",
		"name": "Orc Threat I — Raid Wardens",
		"description": "Orcs have been spotted east of the market preparing for a raid. Defeat 5 Orcs to disrupt their formation.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 400 valor + Orc Egg[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "east_market",
		"target": 5,
		"monster_type": "Orc",
		"rewards": {"xp": 350, "valor": 50},
		"is_daily": false,
		"prerequisite": "",
		"chain_id": "orc_threat",
		"chain_stage": 1,
		"chain_total": 3,
		"next_in_chain": "orc_threat_2",
		"chain_bonus": {}
	},
	"orc_threat_2": {
		"id": "orc_threat_2",
		"name": "Orc Threat II — Break the Lieutenants",
		"description": "Hobgoblin lieutenants are drilling the orc warbands. Defeat 4 Hobgoblins to leave the Warlord without his command structure.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 400 valor + Orc Egg[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "east_market",
		"target": 4,
		"monster_type": "Hobgoblin",
		"rewards": {"xp": 480, "valor": 60},
		"is_daily": false,
		"prerequisite": "orc_threat_1",
		"chain_id": "orc_threat",
		"chain_stage": 2,
		"chain_total": 3,
		"next_in_chain": "orc_threat_3",
		"chain_bonus": {}
	},
	"orc_threat_3": {
		"id": "orc_threat_3",
		"name": "Orc Threat III — Slay the Warlord",
		"description": "The Warlord rallies his last warriors in the Orc Stronghold. Find the dungeon and end his campaign permanently — beware his Bloodied Fury when his strength wanes.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 400 valor + Orc Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.BOSS_HUNT,
		"trading_post": "east_market",
		"target": 1,
		"bounty_name": "Orc Warlord",
		"rewards": {"xp": 750, "valor": 90},
		"is_daily": false,
		"prerequisite": "orc_threat_2",
		"chain_id": "orc_threat",
		"chain_stage": 3,
		"chain_total": 3,
		"next_in_chain": "",
		"chain_bonus": {"valor": 310, "egg": "Orc", "home_stones": ["home_stone_egg", "home_stone_equipment"], "chain_title": "orc_slayer"}
	},
	# ===== "Hobgoblin Discipline" — South Gate, 3 stages, T2 =====
	"hobgoblin_discipline_1": {
		"id": "hobgoblin_discipline_1",
		"name": "Hobgoblin Discipline I — Drill Wreckers",
		"description": "Hobgoblin warbands drill openly south of here. Defeat 5 of them to disrupt their training.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 400 valor + Hobgoblin Egg[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "south_gate",
		"target": 5,
		"monster_type": "Hobgoblin",
		"rewards": {"xp": 360, "valor": 50},
		"is_daily": false,
		"prerequisite": "",
		"chain_id": "hobgoblin_discipline",
		"chain_stage": 1,
		"chain_total": 3,
		"next_in_chain": "hobgoblin_discipline_2",
		"chain_bonus": {}
	},
	"hobgoblin_discipline_2": {
		"id": "hobgoblin_discipline_2",
		"name": "Hobgoblin Discipline II — Goblin Outriders",
		"description": "Goblin scouts ride ahead of the hobgoblin lines. Cull 6 Goblins to blind their forward eyes.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 400 valor + Hobgoblin Egg[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "south_gate",
		"target": 6,
		"monster_type": "Goblin",
		"rewards": {"xp": 320, "valor": 45},
		"is_daily": false,
		"prerequisite": "hobgoblin_discipline_1",
		"chain_id": "hobgoblin_discipline",
		"chain_stage": 2,
		"chain_total": 3,
		"next_in_chain": "hobgoblin_discipline_3",
		"chain_bonus": {}
	},
	"hobgoblin_discipline_3": {
		"id": "hobgoblin_discipline_3",
		"name": "Hobgoblin Discipline III — Break the Commander",
		"description": "The Commander drills his elite from the Hobgoblin Fortress. Find the dungeon and break him — but expect Iron Discipline: every fifth round he heals back and shrugs off your debuffs. Burst him down fast.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 400 valor + Hobgoblin Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.BOSS_HUNT,
		"trading_post": "south_gate",
		"target": 1,
		"bounty_name": "Hobgoblin Commander",
		"rewards": {"xp": 750, "valor": 90},
		"is_daily": false,
		"prerequisite": "hobgoblin_discipline_2",
		"chain_id": "hobgoblin_discipline",
		"chain_stage": 3,
		"chain_total": 3,
		"next_in_chain": "",
		"chain_bonus": {"valor": 310, "egg": "Hobgoblin", "home_stones": ["home_stone_egg", "home_stone_equipment"], "chain_title": "iron_breaker"}
	},
	# ===== "Mimic Hunt" — West Shrine, 2 stages, T2 =====
	"mimic_hunt_1": {
		"id": "mimic_hunt_1",
		"name": "Mimic Hunt I — False Treasures",
		"description": "Travelers report chests biting back along the western roads. Defeat 4 Mimics to reclaim the trade route.\n\n[color=#FFAA00]CHAIN: 2 stages | Final reward: 400 valor + Mimic Egg[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "west_shrine",
		"target": 4,
		"monster_type": "Mimic",
		"rewards": {"xp": 380, "valor": 55},
		"is_daily": false,
		"prerequisite": "",
		"chain_id": "mimic_hunt",
		"chain_stage": 1,
		"chain_total": 2,
		"next_in_chain": "mimic_hunt_2",
		"chain_bonus": {}
	},
	"mimic_hunt_2": {
		"id": "mimic_hunt_2",
		"name": "Mimic Hunt II — The Grand Mimic",
		"description": "The mother of mimics squats in the Mimic Treasury. Find the dungeon and slay the Grand Mimic — beware its Treasure Decoy: a guaranteed crit on its first attack.\n\n[color=#FFAA00]CHAIN: 2 stages | Final reward: 400 valor + Mimic Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.BOSS_HUNT,
		"trading_post": "west_shrine",
		"target": 1,
		"bounty_name": "Grand Mimic",
		"rewards": {"xp": 700, "valor": 80},
		"is_daily": false,
		"prerequisite": "mimic_hunt_1",
		"chain_id": "mimic_hunt",
		"chain_stage": 2,
		"chain_total": 2,
		"next_in_chain": "",
		"chain_bonus": {"valor": 320, "egg": "Mimic", "home_stones": ["home_stone_egg", "home_stone_equipment"], "chain_title": "mimic_hunter"}
	},
	# ===== "Barrow's Curse" — South Gate, 2 stages, T2 =====
	"barrow_curse_1": {
		"id": "barrow_curse_1",
		"name": "Barrow's Curse I — Restless Dead",
		"description": "Wights and zombies have been crawling out of the southern barrows at night. Defeat 5 Wights to thin their numbers before they reach Haven.\n\n[color=#FFAA00]CHAIN: 2 stages | Final reward: 400 valor + Wight Egg[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "south_gate",
		"target": 5,
		"monster_type": "Wight",
		"rewards": {"xp": 400, "valor": 55},
		"is_daily": false,
		"prerequisite": "",
		"chain_id": "barrow_curse",
		"chain_stage": 1,
		"chain_total": 2,
		"next_in_chain": "barrow_curse_2",
		"chain_bonus": {}
	},
	"barrow_curse_2": {
		"id": "barrow_curse_2",
		"name": "Barrow's Curse II — The Barrow Wight",
		"description": "An ancient barrow lord commands the dead from Wight's Vault. Find the dungeon and lay it to rest. Bring healing — every third round its Soul Siphon will drain 8% of your max HP and heal the wight for the same. Plan your bursts around the timer.\n\n[color=#FFAA00]CHAIN: 2 stages | Final reward: 400 valor + Wight Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.BOSS_HUNT,
		"trading_post": "south_gate",
		"target": 1,
		"bounty_name": "Barrow Wight",
		"rewards": {"xp": 720, "valor": 85},
		"is_daily": false,
		"prerequisite": "barrow_curse_1",
		"chain_id": "barrow_curse",
		"chain_stage": 2,
		"chain_total": 2,
		"next_in_chain": "",
		"chain_bonus": {"valor": 315, "egg": "Wight", "home_stones": ["home_stone_egg", "home_stone_equipment"], "chain_title": "barrow_walker"}
	},
	# ===== "Gnoll Pack Hunt" — West Shrine, 3 stages, T2 =====
	"gnoll_pack_hunt_1": {
		"id": "gnoll_pack_hunt_1",
		"name": "Gnoll Pack Hunt I — Cull the Scouts",
		"description": "Gnoll raiding parties have been pressing in from the western marches. Defeat 5 Gnolls to thin their forward scouts before they reach the shrine.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 400 valor + Gnoll Egg[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "west_shrine",
		"target": 5,
		"monster_type": "Gnoll",
		"rewards": {"xp": 380, "valor": 55},
		"is_daily": false,
		"prerequisite": "",
		"chain_id": "gnoll_pack_hunt",
		"chain_stage": 1,
		"chain_total": 3,
		"next_in_chain": "gnoll_pack_hunt_2",
		"chain_bonus": {}
	},
	"gnoll_pack_hunt_2": {
		"id": "gnoll_pack_hunt_2",
		"name": "Gnoll Pack Hunt II — Their Hounds",
		"description": "Wolves run with the pack, flanking ambushes and harrying stragglers. Bring down 4 Wolves to leave the gnolls without their teeth.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 400 valor + Gnoll Egg[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "west_shrine",
		"target": 4,
		"monster_type": "Wolf",
		"rewards": {"xp": 340, "valor": 50},
		"is_daily": false,
		"prerequisite": "gnoll_pack_hunt_1",
		"chain_id": "gnoll_pack_hunt",
		"chain_stage": 2,
		"chain_total": 3,
		"next_in_chain": "gnoll_pack_hunt_3",
		"chain_bonus": {}
	},
	"gnoll_pack_hunt_3": {
		"id": "gnoll_pack_hunt_3",
		"name": "Gnoll Pack Hunt III — Break the Packmaster",
		"description": "The Packmaster rules the Gnoll Pack Den at the heart of the marches. Find the dungeon and bring the beast down — but strike fast. Pack Frenzy escalates every round: by round 10 the Packmaster hits 45% harder, by round 20 it's nearly double. Stall and die slow.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 400 valor + Gnoll Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.BOSS_HUNT,
		"trading_post": "west_shrine",
		"target": 1,
		"bounty_name": "Gnoll Packmaster",
		"rewards": {"xp": 750, "valor": 90},
		"is_daily": false,
		"prerequisite": "gnoll_pack_hunt_2",
		"chain_id": "gnoll_pack_hunt",
		"chain_stage": 3,
		"chain_total": 3,
		"next_in_chain": "",
		"chain_bonus": {"valor": 305, "egg": "Gnoll", "home_stones": ["home_stone_egg", "home_stone_equipment"], "chain_title": "pack_master"}
	},

	# Audit #6 Slice 9 — DELIVER chains (multi-path completability).
	# These quests don't care HOW you get the items: kill + salvage, buy off the
	# market, fulfill a buy order, find in chests, get someone to trade them in.
	# The quest cares about delivery, not method — opens crafting/economy/social
	# paths as legitimate quest verbs.

	"forge_iron_supplies_1": {
		"id": "forge_iron_supplies_1",
		"name": "Forge Supplies I — Iron for the Smith",
		"description": "The Haven smith is restocking. Deliver [b]8 Iron Ore[/b] to her workshop.\n\n[color=#888888]Any path works: mine it, buy it off the market, fulfill a buy order, or find it in dungeon chests.[/color]\n\n[color=#FFAA00]CHAIN: 2 stages | Final reward: 250 valor + Iron Longsword[/color]",
		"type": QuestType.DELIVER,
		"trading_post": "haven",
		"target": 8,
		"delivery_item_name": "iron_ore",
		"delivery_item_type": "material",
		"rewards": {"xp": 180, "valor": 30},
		"is_daily": false,
		"prerequisite": "",
		"chain_id": "forge_iron_supplies",
		"chain_stage": 1,
		"chain_total": 2,
		"next_in_chain": "forge_iron_supplies_2",
		"chain_bonus": {}
	},
	"forge_iron_supplies_2": {
		"id": "forge_iron_supplies_2",
		"name": "Forge Supplies II — Oak Hilts",
		"description": "The smith needs hilt material to finish her run. Deliver [b]4 Oak Wood[/b].\n\n[color=#888888]Crafters chop it from dense forests. Or buy it from a market that specializes in wood.[/color]\n\n[color=#FFAA00]CHAIN: 2 stages | Final reward: 250 valor + Iron Longsword[/color]",
		"type": QuestType.DELIVER,
		"trading_post": "haven",
		"target": 4,
		"delivery_item_name": "oak_wood",
		"delivery_item_type": "material",
		"rewards": {"xp": 220, "valor": 40},
		"is_daily": false,
		"prerequisite": "forge_iron_supplies_1",
		"chain_id": "forge_iron_supplies",
		"chain_stage": 2,
		"chain_total": 2,
		"next_in_chain": "",
		"chain_bonus": {"valor": 210, "home_stones": ["home_stone_equipment"], "chain_title": "smiths_friend"}
	},

	"apothecary_restock_1": {
		"id": "apothecary_restock_1",
		"name": "Apothecary Restock I — Healing Stores",
		"description": "Crossroads' apothecary has run low on healing draughts. Deliver [b]5 Health Potions[/b].\n\n[color=#888888]Find them in chests, buy from the market, or place a buy order if you don't want to brew.[/color]\n\n[color=#FFAA00]CHAIN: 2 stages | Final reward: 220 valor + Wolf Egg[/color]",
		"type": QuestType.DELIVER,
		"trading_post": "crossroads",
		"target": 5,
		"delivery_item_name": "Health Potion",
		"delivery_item_type": "consumable",
		"rewards": {"xp": 160, "valor": 28},
		"is_daily": false,
		"prerequisite": "",
		"chain_id": "apothecary_restock",
		"chain_stage": 1,
		"chain_total": 2,
		"next_in_chain": "apothecary_restock_2",
		"chain_bonus": {}
	},
	"apothecary_restock_2": {
		"id": "apothecary_restock_2",
		"name": "Apothecary Restock II — Herb Gathering",
		"description": "The apothecary now needs herbs for the next batch. Deliver [b]6 Healing Herb[/b].\n\n[color=#888888]Forage them in forest biomes, or buy from a farm-specialty market for a discount.[/color]\n\n[color=#FFAA00]CHAIN: 2 stages | Final reward: 220 valor + Wolf Egg[/color]",
		"type": QuestType.DELIVER,
		"trading_post": "crossroads",
		"target": 6,
		"delivery_item_name": "healing_herb",
		"delivery_item_type": "material",
		"rewards": {"xp": 200, "valor": 38},
		"is_daily": false,
		"prerequisite": "apothecary_restock_1",
		"chain_id": "apothecary_restock",
		"chain_stage": 2,
		"chain_total": 2,
		"next_in_chain": "",
		"chain_bonus": {"valor": 180, "egg": "Wolf", "chain_title": "apothecarys_friend"}
	},

	"trapper_pelts_1": {
		"id": "trapper_pelts_1",
		"name": "The Trapper's Trade I — Ragged Pelts",
		"description": "East Market's trapper is buying pelts in bulk. Deliver [b]6 Ragged Leather[/b].\n\n[color=#888888]Wolves and beasts drop them. Or buy / buy-order from hunters — your call.[/color]\n\n[color=#FFAA00]CHAIN: 2 stages | Final reward: 240 valor + Hobgoblin Egg[/color]",
		"type": QuestType.DELIVER,
		"trading_post": "east_market",
		"target": 6,
		"delivery_item_name": "ragged_leather",
		"delivery_item_type": "material",
		"rewards": {"xp": 170, "valor": 30},
		"is_daily": false,
		"prerequisite": "",
		"chain_id": "trapper_pelts",
		"chain_stage": 1,
		"chain_total": 2,
		"next_in_chain": "trapper_pelts_2",
		"chain_bonus": {}
	},
	"trapper_pelts_2": {
		"id": "trapper_pelts_2",
		"name": "The Trapper's Trade II — Stronger Hides",
		"description": "The trapper wants tougher leather now. Deliver [b]4 Leather Scraps[/b] (the tanned variety).\n\n[color=#888888]Crafted from rough hide if you have a Tanner's specialty. Or buy off the market — leather's common at fortresses.[/color]\n\n[color=#FFAA00]CHAIN: 2 stages | Final reward: 240 valor + Hobgoblin Egg[/color]",
		"type": QuestType.DELIVER,
		"trading_post": "east_market",
		"target": 4,
		"delivery_item_name": "leather_scraps",
		"delivery_item_type": "material",
		"rewards": {"xp": 210, "valor": 40},
		"is_daily": false,
		"prerequisite": "trapper_pelts_1",
		"chain_id": "trapper_pelts",
		"chain_stage": 2,
		"chain_total": 2,
		"next_in_chain": "",
		"chain_bonus": {"valor": 200, "egg": "Hobgoblin", "chain_title": "trappers_friend"}
	},
	# ===== "Trollish Tide" — Eastwatch, 3 stages, T3 (Audit #6 Slice 14) =====
	"trolltide_1": {
		"id": "trolltide_1",
		"name": "Trollish Tide I — Cull the Brutes",
		"description": "Trolls have been crashing out of the eastern crags, smashing pack-trains and scattering livestock. Defeat 6 Trolls to put the brakes on their advance.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 500 valor + Troll Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "eastwatch",
		"target": 6,
		"monster_type": "Troll",
		"rewards": {"xp": 450, "valor": 65},
		"is_daily": false,
		"prerequisite": "",
		"chain_id": "trolltide",
		"chain_stage": 1,
		"chain_total": 3,
		"next_in_chain": "trolltide_2",
		"chain_bonus": {}
	},
	"trolltide_2": {
		"id": "trolltide_2",
		"name": "Trollish Tide II — Their Brutish Cousins",
		"description": "Ogres are following the trolls down from the high crags, scavenging what the trolls leave behind. Cut down 5 Ogres before they get a taste for the road.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 500 valor + Troll Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "eastwatch",
		"target": 5,
		"monster_type": "Ogre",
		"rewards": {"xp": 600, "valor": 85},
		"is_daily": false,
		"prerequisite": "trolltide_1",
		"chain_id": "trolltide",
		"chain_stage": 2,
		"chain_total": 3,
		"next_in_chain": "trolltide_3",
		"chain_bonus": {}
	},
	"trolltide_3": {
		"id": "trolltide_3",
		"name": "Trollish Tide III — Crown the King",
		"description": "The Troll King leads the migration from the Troll Den. Find the dungeon and break his crown. Beware Trollish Regrowth — once he drops below half health, he heals 8% max HP at the start of every monster turn. Burst him down through the threshold instead of trading blows.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 500 valor + Troll Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.BOSS_HUNT,
		"trading_post": "eastwatch",
		"target": 1,
		"bounty_name": "Troll King",
		"rewards": {"xp": 900, "valor": 100},
		"is_daily": false,
		"prerequisite": "trolltide_2",
		"chain_id": "trolltide",
		"chain_stage": 3,
		"chain_total": 3,
		"next_in_chain": "",
		"chain_bonus": {"valor": 400, "egg": "Troll", "home_stones": ["home_stone_egg", "home_stone_equipment"], "chain_title": "troll_render"}
	},
	# ===== "Stone Vigil" — Highland Post, 3 stages, T3 (Audit #6 Slice 14) =====
	"stonevigil_1": {
		"id": "stonevigil_1",
		"name": "Stone Vigil I — Crumbling Watchers",
		"description": "Gargoyles have been peeling off the highland cliffs and stalking travelers on the mountain roads. Bring down 5 Gargoyles before their flight expands.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 500 valor + Gargoyle Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "highland_post",
		"target": 5,
		"monster_type": "Gargoyle",
		"rewards": {"xp": 450, "valor": 65},
		"is_daily": false,
		"prerequisite": "",
		"chain_id": "stonevigil",
		"chain_stage": 1,
		"chain_total": 3,
		"next_in_chain": "stonevigil_2",
		"chain_bonus": {}
	},
	"stonevigil_2": {
		"id": "stonevigil_2",
		"name": "Stone Vigil II — Clear the Skies",
		"description": "Harpies have moved into the gaps left by the gargoyle exodus, and they're worse for travelers — fast and screaming. Drop 4 Harpies to clear the air lanes back open.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 500 valor + Gargoyle Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "highland_post",
		"target": 4,
		"monster_type": "Harpy",
		"rewards": {"xp": 600, "valor": 85},
		"is_daily": false,
		"prerequisite": "stonevigil_1",
		"chain_id": "stonevigil",
		"chain_stage": 2,
		"chain_total": 3,
		"next_in_chain": "stonevigil_3",
		"chain_bonus": {}
	},
	"stonevigil_3": {
		"id": "stonevigil_3",
		"name": "Stone Vigil III — Break the Sentinel",
		"description": "The Gargoyle Sentinel anchors the flight from the Gargoyle Cathedral. Find the dungeon and end its watch. Beware Stoneform — on even rounds the sentinel takes only 30% damage. Save big hits for odd rounds and let the petals of light from any Sacred Ground tiles bless your strikes.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 500 valor + Gargoyle Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.BOSS_HUNT,
		"trading_post": "highland_post",
		"target": 1,
		"bounty_name": "Gargoyle Sentinel",
		"rewards": {"xp": 900, "valor": 100},
		"is_daily": false,
		"prerequisite": "stonevigil_2",
		"chain_id": "stonevigil",
		"chain_stage": 3,
		"chain_total": 3,
		"next_in_chain": "",
		"chain_bonus": {"valor": 400, "egg": "Gargoyle", "home_stones": ["home_stone_egg", "home_stone_equipment"], "chain_title": "stone_breaker"}
	},
	# ===== "Vampire's Hunger" — Southport, 3 stages, T4 (Audit #6 Slice 15) =====
	"vampirehunger_1": {
		"id": "vampirehunger_1",
		"name": "Vampire's Hunger I — Walking Dead",
		"description": "Wights are stirring from the southern barrows, drawn by a hunger that isn't their own. Defeat 6 Wights to break the procession before it reaches the port.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 600 valor + Vampire Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "southport",
		"target": 6,
		"monster_type": "Wight",
		"rewards": {"xp": 550, "valor": 75},
		"is_daily": false,
		"prerequisite": "",
		"chain_id": "vampirehunger",
		"chain_stage": 1,
		"chain_total": 3,
		"next_in_chain": "vampirehunger_2",
		"chain_bonus": {}
	},
	"vampirehunger_2": {
		"id": "vampirehunger_2",
		"name": "Vampire's Hunger II — The Court Stirs",
		"description": "Wraiths follow in the wights' wake — closer to the vampire, sharper of will. Cut down 5 Wraiths to break the inner court before the master appears.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 600 valor + Vampire Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "southport",
		"target": 5,
		"monster_type": "Wraith",
		"rewards": {"xp": 700, "valor": 100},
		"is_daily": false,
		"prerequisite": "vampirehunger_1",
		"chain_id": "vampirehunger",
		"chain_stage": 2,
		"chain_total": 3,
		"next_in_chain": "vampirehunger_3",
		"chain_bonus": {}
	},
	"vampirehunger_3": {
		"id": "vampirehunger_3",
		"name": "Vampire's Hunger III — End the Master",
		"description": "The Vampire holds court in the Vampire's Crypt. Find the dungeon and put an end to the bloodletting. Beware Blood Frenzy — every hit you land heals the vampire for 30% of damage dealt. Burst rotations work better than steady chip damage; healing breaks the loop.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 600 valor + Vampire Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.BOSS_HUNT,
		"trading_post": "southport",
		"target": 1,
		"bounty_name": "Vampire",
		"rewards": {"xp": 1100, "valor": 120},
		"is_daily": false,
		"prerequisite": "vampirehunger_2",
		"chain_id": "vampirehunger",
		"chain_stage": 3,
		"chain_total": 3,
		"next_in_chain": "",
		"chain_bonus": {"valor": 480, "egg": "Vampire", "home_stones": ["home_stone_egg", "home_stone_equipment"], "chain_title": "vampire_hunter"}
	},
	# ===== "Dragon Brood" — Frostgate, 3 stages, T4 (Audit #6 Slice 15) =====
	"dragonbrood_1": {
		"id": "dragonbrood_1",
		"name": "Dragon Brood I — Scaled Skies",
		"description": "Wyverns have been raiding caravans north of Frostgate, dragging horses and supplies up to whatever lair has them rallying. Down 6 Wyverns to break their flight before more wing in.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 600 valor + Dragon Wyrmling Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "frostgate",
		"target": 6,
		"monster_type": "Wyvern",
		"rewards": {"xp": 550, "valor": 75},
		"is_daily": false,
		"prerequisite": "",
		"chain_id": "dragonbrood",
		"chain_stage": 1,
		"chain_total": 3,
		"next_in_chain": "dragonbrood_2",
		"chain_bonus": {}
	},
	"dragonbrood_2": {
		"id": "dragonbrood_2",
		"name": "Dragon Brood II — Hatchling Surge",
		"description": "The wyverns were running supplies for the Dragon Hatchery — and the hatchlings are already crawling out to feed. Cut down 5 Dragon Wyrmlings before they reach full size.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 600 valor + Dragon Wyrmling Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "frostgate",
		"target": 5,
		"monster_type": "Dragon Wyrmling",
		"rewards": {"xp": 700, "valor": 100},
		"is_daily": false,
		"prerequisite": "dragonbrood_1",
		"chain_id": "dragonbrood",
		"chain_stage": 2,
		"chain_total": 3,
		"next_in_chain": "dragonbrood_3",
		"chain_bonus": {}
	},
	"dragonbrood_3": {
		"id": "dragonbrood_3",
		"name": "Dragon Brood III — Crush the Broodmother",
		"description": "The Broodmother Wyrmling guards the Dragon Hatchery and lays the eggs that fuel the brood. Find the dungeon and end her line. Beware Hatchling Swarm — every four rounds she calls in a burst of damage as fresh hatchlings throw themselves at you. Plan your burns and cooldowns around her timer.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 600 valor + Dragon Wyrmling Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.BOSS_HUNT,
		"trading_post": "frostgate",
		"target": 1,
		"bounty_name": "Broodmother Wyrmling",
		"rewards": {"xp": 1100, "valor": 120},
		"is_daily": false,
		"prerequisite": "dragonbrood_2",
		"chain_id": "dragonbrood",
		"chain_stage": 3,
		"chain_total": 3,
		"next_in_chain": "",
		"chain_bonus": {"valor": 480, "egg": "Dragon Wyrmling", "home_stones": ["home_stone_egg", "home_stone_equipment"], "chain_title": "brood_breaker"}
	},
	# ===== "Lich's Curse" — Far West Haven, 3 stages, T5 (Audit #6 Slice 16) =====
	"lichscurse_1": {
		"id": "lichscurse_1",
		"name": "Lich's Curse I — Shambling Vanguard",
		"description": "Zombies have been pouring out of the western dust, all walking eastward in eerie unison. Defeat 6 Zombies before they swarm the haven.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 750 valor + Lich Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "far_west_haven",
		"target": 6,
		"monster_type": "Zombie",
		"rewards": {"xp": 700, "valor": 95},
		"is_daily": false,
		"prerequisite": "",
		"chain_id": "lichscurse",
		"chain_stage": 1,
		"chain_total": 3,
		"next_in_chain": "lichscurse_2",
		"chain_bonus": {}
	},
	"lichscurse_2": {
		"id": "lichscurse_2",
		"name": "Lich's Curse II — Wraiths in the Dust",
		"description": "The zombies were bait — wraiths now boil out of the western tomb-lanes, bound to the lich's will. Bring down 5 Wraiths to break the binding before the lich himself appears.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 750 valor + Lich Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "far_west_haven",
		"target": 5,
		"monster_type": "Wraith",
		"rewards": {"xp": 900, "valor": 125},
		"is_daily": false,
		"prerequisite": "lichscurse_1",
		"chain_id": "lichscurse",
		"chain_stage": 2,
		"chain_total": 3,
		"next_in_chain": "lichscurse_3",
		"chain_bonus": {}
	},
	"lichscurse_3": {
		"id": "lichscurse_3",
		"name": "Lich's Curse III — Burn the Sanctum",
		"description": "The Lich rules from his sanctum, anchoring the western necrosis. Find the dungeon and end him. Beware Soul Burn — every hit he lands drains 5% of your primary resource max. Cast / strike at full mana or stamina before the fight; mid-fight regen barely keeps up.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 750 valor + Lich Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.BOSS_HUNT,
		"trading_post": "far_west_haven",
		"target": 1,
		"bounty_name": "Lich",
		"rewards": {"xp": 1400, "valor": 150},
		"is_daily": false,
		"prerequisite": "lichscurse_2",
		"chain_id": "lichscurse",
		"chain_stage": 3,
		"chain_total": 3,
		"next_in_chain": "",
		"chain_bonus": {"valor": 600, "egg": "Lich", "home_stones": ["home_stone_egg", "home_stone_equipment"], "chain_title": "lich_ender"}
	},
	# ===== "Demon Lord's Heir" — Deep South Port, 3 stages, T5 (Audit #6 Slice 16) =====
	"demonlordheir_1": {
		"id": "demonlordheir_1",
		"name": "Demon Lord's Heir I — Infernal Foot Soldiers",
		"description": "Demons have been hauling themselves up from the southern reefs, scarring the port walls with infernal claws. Cut down 6 Demons to thin the vanguard.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 750 valor + Demon Lord Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "deep_south_port",
		"target": 6,
		"monster_type": "Demon",
		"rewards": {"xp": 700, "valor": 95},
		"is_daily": false,
		"prerequisite": "",
		"chain_id": "demonlordheir",
		"chain_stage": 1,
		"chain_total": 3,
		"next_in_chain": "demonlordheir_2",
		"chain_bonus": {}
	},
	"demonlordheir_2": {
		"id": "demonlordheir_2",
		"name": "Demon Lord's Heir II — The Queen's Court",
		"description": "The Demon Lord's succubus courtiers have moved up the chain, charming sailors and dragging them down into the deep. Bring down 5 Succubi to break the spell before more dock crews fall.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 750 valor + Demon Lord Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "deep_south_port",
		"target": 5,
		"monster_type": "Succubus",
		"rewards": {"xp": 900, "valor": 125},
		"is_daily": false,
		"prerequisite": "demonlordheir_1",
		"chain_id": "demonlordheir",
		"chain_stage": 2,
		"chain_total": 3,
		"next_in_chain": "demonlordheir_3",
		"chain_bonus": {}
	},
	"demonlordheir_3": {
		"id": "demonlordheir_3",
		"name": "Demon Lord's Heir III — Topple the Throne",
		"description": "The Demon Lord holds his throne deep below. Find the dungeon and end his reign. Beware Soul Forge — every five rounds the Demon Lord heals himself for 15% of his max HP. Burst him through the threshold before the forge fires; if you let the fight stall, he'll outlast every burn you have.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 750 valor + Demon Lord Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.BOSS_HUNT,
		"trading_post": "deep_south_port",
		"target": 1,
		"bounty_name": "Demon Lord",
		"rewards": {"xp": 1400, "valor": 150},
		"is_daily": false,
		"prerequisite": "demonlordheir_2",
		"chain_id": "demonlordheir",
		"chain_stage": 3,
		"chain_total": 3,
		"next_in_chain": "",
		"chain_bonus": {"valor": 600, "egg": "Demon Lord", "home_stones": ["home_stone_egg", "home_stone_equipment"], "chain_title": "demon_slayer"}
	},
	# ===== "Hydra Hunt" — Far East Station, 3 stages, T6 (Audit #6 Slice 17) =====
	"hydrahunt_1": {
		"id": "hydrahunt_1",
		"name": "Hydra Hunt I — Bog's Vanguard",
		"description": "Sirens have been luring caravan crews off the eastern road, dragging them into the bog. Down 6 Sirens to clear the song-trap before more crews vanish.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 900 valor + Hydra Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "far_east_station",
		"target": 6,
		"monster_type": "Siren",
		"rewards": {"xp": 900, "valor": 120},
		"is_daily": false,
		"prerequisite": "",
		"chain_id": "hydrahunt",
		"chain_stage": 1,
		"chain_total": 3,
		"next_in_chain": "hydrahunt_2",
		"chain_bonus": {}
	},
	"hydrahunt_2": {
		"id": "hydrahunt_2",
		"name": "Hydra Hunt II — Spinners in the Reeds",
		"description": "Giant Spiders nest in the bog's reed-banks, fattened on hydra-leavings. Cut down 5 Giant Spiders to clear the approach to the hydra's pool.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 900 valor + Hydra Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "far_east_station",
		"target": 5,
		"monster_type": "Giant Spider",
		"rewards": {"xp": 1200, "valor": 160},
		"is_daily": false,
		"prerequisite": "hydrahunt_1",
		"chain_id": "hydrahunt",
		"chain_stage": 2,
		"chain_total": 3,
		"next_in_chain": "hydrahunt_3",
		"chain_bonus": {}
	},
	"hydrahunt_3": {
		"id": "hydrahunt_3",
		"name": "Hydra Hunt III — Sever Every Head",
		"description": "The Hydra coils at the center of the swamp, regenerating from anything you don't outright kill. Find the dungeon and end her. Beware Hydra Regen — any hit landing for more than 10%% of her max HP heals her for 10%% of max HP. Spread your burst across multiple hits or break the threshold once cleanly — chip damage works in your favor.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 900 valor + Hydra Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.BOSS_HUNT,
		"trading_post": "far_east_station",
		"target": 1,
		"bounty_name": "Hydra",
		"rewards": {"xp": 1800, "valor": 200},
		"is_daily": false,
		"prerequisite": "hydrahunt_2",
		"chain_id": "hydrahunt",
		"chain_stage": 3,
		"chain_total": 3,
		"next_in_chain": "",
		"chain_bonus": {"valor": 750, "egg": "Hydra", "home_stones": ["home_stone_egg", "home_stone_equipment"], "chain_title": "hydra_slayer"}
	},
	# ===== "Phoenix's Final Flight" — High North Peak, 3 stages, T6 (Audit #6 Slice 17) =====
	"phoenixflight_1": {
		"id": "phoenixflight_1",
		"name": "Phoenix's Final Flight I — Skies of Ash",
		"description": "Harpies have been wheeling above the northern peaks, scattering when the heat-thermal that lifts them surges. Bring down 6 Harpies to clear the air for the climb above.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 900 valor + Phoenix Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "high_north_peak",
		"target": 6,
		"monster_type": "Harpy",
		"rewards": {"xp": 900, "valor": 120},
		"is_daily": false,
		"prerequisite": "",
		"chain_id": "phoenixflight",
		"chain_stage": 1,
		"chain_total": 3,
		"next_in_chain": "phoenixflight_2",
		"chain_bonus": {}
	},
	"phoenixflight_2": {
		"id": "phoenixflight_2",
		"name": "Phoenix's Final Flight II — Sentinels of the Peak",
		"description": "Gryphons patrol the highest ledges, keeping all lesser flyers from the phoenix's flame. Bring down 5 Gryphons to break the cordon and reach the summit.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 900 valor + Phoenix Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "high_north_peak",
		"target": 5,
		"monster_type": "Gryphon",
		"rewards": {"xp": 1200, "valor": 160},
		"is_daily": false,
		"prerequisite": "phoenixflight_1",
		"chain_id": "phoenixflight",
		"chain_stage": 2,
		"chain_total": 3,
		"next_in_chain": "phoenixflight_3",
		"chain_bonus": {}
	},
	"phoenixflight_3": {
		"id": "phoenixflight_3",
		"name": "Phoenix's Final Flight III — End the Eternal",
		"description": "The Phoenix nests at the peak, and the only way to put her down for good is to break her on her own coals. Find the dungeon and end the rebirth. Beware Phoenix Rebirth — when first killed, the Phoenix rises again at 75%% HP. Save your biggest cooldowns for the second life; the first kill is the warm-up.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 900 valor + Phoenix Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.BOSS_HUNT,
		"trading_post": "high_north_peak",
		"target": 1,
		"bounty_name": "Phoenix",
		"rewards": {"xp": 1800, "valor": 200},
		"is_daily": false,
		"prerequisite": "phoenixflight_2",
		"chain_id": "phoenixflight",
		"chain_stage": 3,
		"chain_total": 3,
		"next_in_chain": "",
		"chain_bonus": {"valor": 750, "egg": "Phoenix", "home_stones": ["home_stone_egg", "home_stone_equipment"], "chain_title": "phoenix_ender"}
	},
	# ===== "Void Walker's Pact" — Void's Edge, 3 stages, T7 (Audit #6 Slice 18) =====
	"voidpact_1": {
		"id": "voidpact_1",
		"name": "Void Walker's Pact I — Echoes Beyond",
		"description": "The Shadow Watcher reports Wraiths phasing through the boundary at Void's Edge — drawn by something the Walker is doing on the other side. Cut 6 Wraiths down before the breach widens.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 900 valor + Void Walker Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "voids_edge",
		"target": 6,
		"monster_type": "Wraith",
		"rewards": {"xp": 1080, "valor": 145},
		"is_daily": false,
		"prerequisite": "",
		"chain_id": "voidpact",
		"chain_stage": 1,
		"chain_total": 3,
		"next_in_chain": "voidpact_2",
		"chain_bonus": {}
	},
	"voidpact_2": {
		"id": "voidpact_2",
		"name": "Void Walker's Pact II — Riders of the Tear",
		"description": "Nazgul ride the dimensional bleed, hunting any survivors who linger too close to the rift. Bring down 5 Nazgul to clear the path to the Walker himself.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 900 valor + Void Walker Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "voids_edge",
		"target": 5,
		"monster_type": "Nazgul",
		"rewards": {"xp": 1440, "valor": 195},
		"is_daily": false,
		"prerequisite": "voidpact_1",
		"chain_id": "voidpact",
		"chain_stage": 2,
		"chain_total": 3,
		"next_in_chain": "voidpact_3",
		"chain_bonus": {}
	},
	"voidpact_3": {
		"id": "voidpact_3",
		"name": "Void Walker's Pact III — Close the Rift",
		"description": "The Void Walker steps between dimensions at will. Enter the Rift, corner him, end him. Beware Dimensional Prison — he can pull a single target out of the fight for two rounds; the rest of your party must hold the line alone. If you fight solo, time your defensives for the freeze.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 900 valor + Void Walker Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.BOSS_HUNT,
		"trading_post": "voids_edge",
		"target": 1,
		"bounty_name": "Void Walker",
		"rewards": {"xp": 2160, "valor": 240},
		"is_daily": false,
		"prerequisite": "voidpact_2",
		"chain_id": "voidpact",
		"chain_stage": 3,
		"chain_total": 3,
		"next_in_chain": "",
		"chain_bonus": {"valor": 900, "egg": "Void Walker", "home_stones": ["home_stone_egg", "home_stone_equipment"], "chain_title": "void_ender"}
	},
	# ===== "Primordial Awakening" — Dragon's Rest, 3 stages, T7 (Audit #6 Slice 18) =====
	"primordialwake_1": {
		"id": "primordialwake_1",
		"name": "Primordial Awakening I — Wyrmling Stir",
		"description": "Dragon Wyrmlings are hatching ahead of schedule, drawn from torpor by something deeper in the mountain. The Dragon Sage says this only happens when something far older stirs below. Cull 6 Dragon Wyrmlings before the flight grows.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 900 valor + Primordial Dragon Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "dragons_rest",
		"target": 6,
		"monster_type": "Dragon Wyrmling",
		"rewards": {"xp": 1080, "valor": 145},
		"is_daily": false,
		"prerequisite": "",
		"chain_id": "primordialwake",
		"chain_stage": 1,
		"chain_total": 3,
		"next_in_chain": "primordialwake_2",
		"chain_bonus": {}
	},
	"primordialwake_2": {
		"id": "primordialwake_2",
		"name": "Primordial Awakening II — The Elders Rise",
		"description": "Ancient Dragons have broken from the upper caves and are scouting for the Sage. Down 5 Ancient Dragons before they map his sanctum.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 900 valor + Primordial Dragon Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "dragons_rest",
		"target": 5,
		"monster_type": "Ancient Dragon",
		"rewards": {"xp": 1440, "valor": 195},
		"is_daily": false,
		"prerequisite": "primordialwake_1",
		"chain_id": "primordialwake",
		"chain_stage": 2,
		"chain_total": 3,
		"next_in_chain": "primordialwake_3",
		"chain_bonus": {}
	},
	"primordialwake_3": {
		"id": "primordialwake_3",
		"name": "Primordial Awakening III — Dawn-Time Dragon",
		"description": "The dragon from the dawn of time has woken. Walk into his Domain and end the age. Beware Cataclysm and World Shaker — wide AoE damage hits every party member every few rounds; bring healing for sustain, not burst. Save offensive cooldowns for the windows between blasts.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 900 valor + Primordial Dragon Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.BOSS_HUNT,
		"trading_post": "dragons_rest",
		"target": 1,
		"bounty_name": "Primordial Dragon",
		"rewards": {"xp": 2160, "valor": 240},
		"is_daily": false,
		"prerequisite": "primordialwake_2",
		"chain_id": "primordialwake",
		"chain_stage": 3,
		"chain_total": 3,
		"next_in_chain": "",
		"chain_bonus": {"valor": 900, "egg": "Primordial Dragon", "home_stones": ["home_stone_egg", "home_stone_equipment"], "chain_title": "primordial_breaker"}
	},
	# ===== "The Cosmic Veil" — Primordial Sanctum, 3 stages, T8 (Audit #6 Slice 18) =====
	"cosmicveil_1": {
		"id": "cosmicveil_1",
		"name": "The Cosmic Veil I — Walkers at the Edge",
		"description": "The Ancient One says the veil is thinning. Void Walkers cross at the edge of the sanctum, pulled toward something deeper. End 5 Void Walkers to slow the bleed.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 1080 valor + Cosmic Horror Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "primordial_sanctum",
		"target": 5,
		"monster_type": "Void Walker",
		"rewards": {"xp": 1300, "valor": 175},
		"is_daily": false,
		"prerequisite": "",
		"chain_id": "cosmicveil",
		"chain_stage": 1,
		"chain_total": 3,
		"next_in_chain": "cosmicveil_2",
		"chain_bonus": {}
	},
	"cosmicveil_2": {
		"id": "cosmicveil_2",
		"name": "The Cosmic Veil II — Threads of Then",
		"description": "Time Weavers have begun unspooling moments from the Ancient One's memory, looking for the path beneath. Cut down 4 Time Weavers before they finish the map.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 1080 valor + Cosmic Horror Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "primordial_sanctum",
		"target": 4,
		"monster_type": "Time Weaver",
		"rewards": {"xp": 1730, "valor": 235},
		"is_daily": false,
		"prerequisite": "cosmicveil_1",
		"chain_id": "cosmicveil",
		"chain_stage": 2,
		"chain_total": 3,
		"next_in_chain": "cosmicveil_3",
		"chain_bonus": {}
	},
	"cosmicveil_3": {
		"id": "cosmicveil_3",
		"name": "The Cosmic Veil III — Seal What Watches Back",
		"description": "Step through the veil. The Cosmic Horror dwells in the realm behind sanity. Find it. Seal it. Beware Madness Aura — passive every round, your defenses warp; rage and precision scrolls help shrug it off. Reality Warp can swap your turn order without warning — assume nothing about who moves next.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 1080 valor + Cosmic Horror Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.BOSS_HUNT,
		"trading_post": "primordial_sanctum",
		"target": 1,
		"bounty_name": "Cosmic Horror",
		"rewards": {"xp": 2600, "valor": 290},
		"is_daily": false,
		"prerequisite": "cosmicveil_2",
		"chain_id": "cosmicveil",
		"chain_stage": 3,
		"chain_total": 3,
		"next_in_chain": "",
		"chain_bonus": {"valor": 1080, "egg": "Cosmic Horror", "home_stones": ["home_stone_egg", "home_stone_equipment"], "chain_title": "horror_sealer"}
	},
	# ===== "Death's Threshold" — Nether Gate, 3 stages, T8 (Audit #6 Slice 18) =====
	"deaththreshold_1": {
		"id": "deaththreshold_1",
		"name": "Death's Threshold I — Phylactery Riders",
		"description": "Elder Liches drift in from beyond the Gate, half-here and half-not. The Gate Keeper says they're scouting for a master who never finished dying. End 5 Elder Liches to break the relay.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 1080 valor + Death Incarnate Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "nether_gate",
		"target": 5,
		"monster_type": "Elder Lich",
		"rewards": {"xp": 1300, "valor": 175},
		"is_daily": false,
		"prerequisite": "",
		"chain_id": "deaththreshold",
		"chain_stage": 1,
		"chain_total": 3,
		"next_in_chain": "deaththreshold_2",
		"chain_bonus": {}
	},
	"deaththreshold_2": {
		"id": "deaththreshold_2",
		"name": "Death's Threshold II — Walkers of the Gate",
		"description": "Void Walkers have taken position at the Gate's other side, as if guarding it from us. Down 4 Void Walkers to clear the approach.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 1080 valor + Death Incarnate Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "nether_gate",
		"target": 4,
		"monster_type": "Void Walker",
		"rewards": {"xp": 1730, "valor": 235},
		"is_daily": false,
		"prerequisite": "deaththreshold_1",
		"chain_id": "deaththreshold",
		"chain_stage": 2,
		"chain_total": 3,
		"next_in_chain": "deaththreshold_3",
		"chain_bonus": {}
	},
	"deaththreshold_3": {
		"id": "deaththreshold_3",
		"name": "Death's Threshold III — Defy the End",
		"description": "Death Incarnate waits in his Domain, on the line between life and what's after. Walk past him alive. Beware Reaper's Touch and Final Judgment — Final Judgment is a single execute strike that lands hard around 30%% HP; do not let any party member sit in that band. Standard Health Potions stabilise the window.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 1080 valor + Death Incarnate Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.BOSS_HUNT,
		"trading_post": "nether_gate",
		"target": 1,
		"bounty_name": "Death Incarnate",
		"rewards": {"xp": 2600, "valor": 290},
		"is_daily": false,
		"prerequisite": "deaththreshold_2",
		"chain_id": "deaththreshold",
		"chain_stage": 3,
		"chain_total": 3,
		"next_in_chain": "",
		"chain_bonus": {"valor": 1080, "egg": "Death Incarnate", "home_stones": ["home_stone_egg", "home_stone_equipment"], "chain_title": "death_defier"}
	},
	# ===== "Avatar of Ruin" — Apex Northeast, 3 stages, T9 (Audit #6 Slice 18) =====
	"avatarruin_1": {
		"id": "avatarruin_1",
		"name": "Avatar of Ruin I — Horrors at the Hunt",
		"description": "The Apex Hunter has tracked Cosmic Horrors leaking out of the Sanctum, drawn by the gravity of what waits at the center. End 4 Cosmic Horrors before they recruit.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 1300 valor + Avatar of Chaos Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "apex_northeast",
		"target": 4,
		"monster_type": "Cosmic Horror",
		"rewards": {"xp": 1560, "valor": 210},
		"is_daily": false,
		"prerequisite": "",
		"chain_id": "avatarruin",
		"chain_stage": 1,
		"chain_total": 3,
		"next_in_chain": "avatarruin_2",
		"chain_bonus": {}
	},
	"avatarruin_2": {
		"id": "avatarruin_2",
		"name": "Avatar of Ruin II — Reapers on Patrol",
		"description": "Death Incarnates are now patrolling the perimeter of the Sanctum. End 3 of them to open the door.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 1300 valor + Avatar of Chaos Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "apex_northeast",
		"target": 3,
		"monster_type": "Death Incarnate",
		"rewards": {"xp": 2080, "valor": 280},
		"is_daily": false,
		"prerequisite": "avatarruin_1",
		"chain_id": "avatarruin",
		"chain_stage": 2,
		"chain_total": 3,
		"next_in_chain": "avatarruin_3",
		"chain_bonus": {}
	},
	"avatarruin_3": {
		"id": "avatarruin_3",
		"name": "Avatar of Ruin III — Unmake the Avatar",
		"description": "Walk into the Sanctum. The Avatar of Chaos is entropy in person. End him. Beware Reality Shatter and Ultimate Destruction — Ultimate Destruction is a fight-ending burst, but it has a long tell; the round before, every action is bigger. Burn defensives the moment the Avatar's next attack is named.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 1300 valor + Avatar of Chaos Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.BOSS_HUNT,
		"trading_post": "apex_northeast",
		"target": 1,
		"bounty_name": "Avatar of Chaos",
		"rewards": {"xp": 3120, "valor": 350},
		"is_daily": false,
		"prerequisite": "avatarruin_2",
		"chain_id": "avatarruin",
		"chain_stage": 3,
		"chain_total": 3,
		"next_in_chain": "",
		"chain_bonus": {"valor": 1300, "egg": "Avatar of Chaos", "home_stones": ["home_stone_egg", "home_stone_equipment"], "chain_title": "chaos_unmaker"}
	},
	# ===== "The End of All Things" — Apex Southwest, 3 stages, T9 (Audit #6 Slice 18) =====
	"endofall_1": {
		"id": "endofall_1",
		"name": "The End of All Things I — Avatars of Decay",
		"description": "The Doom Prophet has foreseen the final undoing. Avatars of Chaos have appeared in the wastes around his temple — entropy's outriders. End 4 of them.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 1300 valor + Entropy Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "apex_southwest",
		"target": 4,
		"monster_type": "Avatar of Chaos",
		"rewards": {"xp": 1560, "valor": 210},
		"is_daily": false,
		"prerequisite": "",
		"chain_id": "endofall",
		"chain_stage": 1,
		"chain_total": 3,
		"next_in_chain": "endofall_2",
		"chain_bonus": {}
	},
	"endofall_2": {
		"id": "endofall_2",
		"name": "The End of All Things II — Those Without Name",
		"description": "The Nameless Ones drift in behind the Avatars, erasing what their masters merely consume. End 3 of them — leave nothing to be unremembered.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 1300 valor + Entropy Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.KILL_TYPE,
		"trading_post": "apex_southwest",
		"target": 3,
		"monster_type": "The Nameless One",
		"rewards": {"xp": 2080, "valor": 280},
		"is_daily": false,
		"prerequisite": "endofall_1",
		"chain_id": "endofall",
		"chain_stage": 2,
		"chain_total": 3,
		"next_in_chain": "endofall_3",
		"chain_bonus": {}
	},
	"endofall_3": {
		"id": "endofall_3",
		"name": "The End of All Things III — Outlast Entropy",
		"description": "Entropy itself waits at the end. Walk in. Outlast it. Beware Heat Death and Universe Collapse — Final Entropy is a stacking decay that grows every round; you cannot turtle. Press the kill. Burst, do not chip.\n\n[color=#FFAA00]CHAIN: 3 stages | Final reward: 1300 valor + Entropy Egg + Home Stones (Egg + Equipment)[/color]",
		"type": QuestType.BOSS_HUNT,
		"trading_post": "apex_southwest",
		"target": 1,
		"bounty_name": "Entropy",
		"rewards": {"xp": 3120, "valor": 350},
		"is_daily": false,
		"prerequisite": "endofall_2",
		"chain_id": "endofall",
		"chain_stage": 3,
		"chain_total": 3,
		"next_in_chain": "",
		"chain_bonus": {"valor": 1300, "egg": "Entropy", "home_stones": ["home_stone_egg", "home_stone_equipment"], "chain_title": "end_walker"}
	}
}

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

	# Audit #11 Slice 12 — threat-relief quest IDs (format:
	# threat_<post_id>@<dungeon_type>). Server-side handle_trading_post_quests
	# generates the rich variant from live threat state; this regen path
	# rebuilds the minimal fields downstream code needs (trading_post + type
	# + dungeon_type) so turn-in works after the live threat clears.
	if quest_id.begins_with("threat_") and "@" in quest_id:
		return _regenerate_threat_relief_quest(quest_id)

	return {}

func _regenerate_threat_relief_quest(quest_id: String) -> Dictionary:
	"""Reconstruct a threat-relief quest from its ID. The live (rich) variant
	is built server-side in _generate_threat_relief_quest; this regen path
	supplies only the static fields needed once the quest is in
	character.active_quests (trading_post + type + dungeon_type). Rewards
	come from extra_data.stored_rewards on turn-in."""
	# Strip prefix and split on '@' separator.
	var rest = quest_id.substr(len("threat_"))
	var at_idx = rest.find("@")
	if at_idx < 0:
		return {}
	var post_id = rest.substr(0, at_idx)
	var dungeon_type = rest.substr(at_idx + 1)
	if post_id == "" or dungeon_type == "":
		return {}
	return {
		"id": quest_id,
		"name": "Drive Off the threat",
		"description": "Threat-relief bounty.",
		"type": QuestType.DUNGEON_CLEAR,
		"trading_post": post_id,
		"target": 1,
		"dungeon_type": dungeon_type,
		"rewards": {"xp": 0, "valor": 0},  # Real rewards come from extra_data.stored_rewards
		"is_daily": false,
		"prerequisite": "",
		"is_threat_relief": true,
	}

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

func get_chain_starters_for_post(trading_post_id: String, completed_chains: Array, active_quest_ids: Array, completed_quests: Array, chain_cooldowns: Dictionary = {}) -> Array:
	"""Audit #6 Slice 1 — return chain stage-1 quests available at this post.
	Filters out chains the character has already completed or already started
	(i.e., is currently doing some stage of the chain).

	Audit #6 v0.9.517 — `chain_cooldowns` (chain_id → unix_timestamp_ready) lets
	repeatable chains reappear after their cooldown elapses. If the final stage
	is marked `repeatable: true` and the cooldown has passed, the stage-1
	starter is offered again. Chains never marked repeatable stay one-shot."""
	var now: int = int(Time.get_unix_time_from_system())
	var available: Array = []
	for quest_id in QUESTS:
		var quest = QUESTS[quest_id]
		if quest.get("chain_stage", 0) != 1:
			continue
		if quest.get("trading_post", "") != trading_post_id:
			continue
		var chain_id = String(quest.get("chain_id", ""))
		if chain_id in completed_chains:
			# Repeatable check: chain must be marked repeatable AND cooldown elapsed.
			var is_repeatable = _chain_is_repeatable(chain_id)
			if not is_repeatable:
				continue
			var ready_at = int(chain_cooldowns.get(chain_id, 0))
			if ready_at > now:
				continue
		# Skip if any stage of this chain is currently active or already completed
		var chain_in_progress = false
		for other_id in QUESTS:
			var other = QUESTS[other_id]
			if String(other.get("chain_id", "")) != chain_id:
				continue
			if other_id in active_quest_ids or other_id in completed_quests:
				chain_in_progress = true
				break
		if chain_in_progress:
			continue
		available.append(quest.duplicate(true))
	return available

func _chain_is_repeatable(chain_id: String) -> bool:
	"""Audit #6 v0.9.517 — true if any quest in `chain_id` has `repeatable: true`
	on its definition. Conventionally placed on the final stage so the cooldown
	stamp aligns with chain completion."""
	for qid in QUESTS:
		var q = QUESTS[qid]
		if String(q.get("chain_id", "")) != chain_id:
			continue
		if bool(q.get("repeatable", false)):
			return true
	return false

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
	"""Audit #6 Slice 13 — regenerating quest board.

	Replaces the prior daily-refresh model: instead of a fixed daily-board
	that exhausts after N completions and waits 24h, the board now slides
	forward as quests are completed. The slot a completed quest occupied
	gets filled immediately by a new procedural quest at the next index.
	Players never have to wait for a daily reset.

	Board size is bumped: starter 5-6 / mid 7-8 / endgame 8-10 quests
	visible at all times (was 3-4 / 5-6 / 6-8).

	Determinism: each quest's data is keyed off (trading_post_id, date_str,
	character_name, index). _regenerate_daily_quest walks 0..index linearly
	to advance the shared RNG, so we do the same here. Quest at index N
	is the same whichever function generates it.

	active_quest_ids: quests the player has already accepted. Their slots
	are skipped (not double-shown) but rng advances over them.
	completed_quests / daily_cooldowns: count toward the sliding-window
	floor so completed indices never reappear."""
	if not DYNAMIC_DAILIES_ENABLED:
		return []
	# `daily_cooldowns` is dead state with Slice 13 but kept on the signature
	# so existing callers don't break; the upstream completed_at_post counter
	# already folds pre-Slice-13 cooldown entries into the sliding window.
	var quests = []
	var date_str = _get_date_string()

	# Get this trading post's coordinates and area level
	var post_coords = TRADING_POST_COORDS.get(trading_post_id, Vector2i(0, 0))
	var post_distance = sqrt(post_coords.x * post_coords.x + post_coords.y * post_coords.y)
	var area_level = max(1, int(post_distance * 0.5))

	# Board size — bumped per Slice 13 so players see "a few more" quests.
	var daily_seed = hash(trading_post_id + date_str + character_name)
	var rng = RandomNumberGenerator.new()
	rng.seed = daily_seed
	var board_size: int
	if area_level < 10:
		board_size = rng.randi_range(5, 6)
	elif area_level < 100:
		board_size = rng.randi_range(7, 8)
	else:
		board_size = rng.randi_range(8, 10)

	# Calculate difficulty modifier from progression
	var progression_modifier = min(0.5, quests_completed_at_post * 0.05)

	# Available quest types for cycling (weighted by what makes sense for the area)
	var quest_types = [QuestType.KILL_ANY, QuestType.KILL_TIER, QuestType.HOTZONE_KILL,
		QuestType.BOSS_HUNT, QuestType.EXPLORATION, QuestType.DUNGEON_CLEAR, QuestType.RESCUE, QuestType.GATHER]

	# Sliding-window loop: walk indices from 0, skipping below the floor,
	# yielding until we have board_size visible quests. Active and completed
	# slots are skipped (their quests are elsewhere — log or history) but
	# rng still advances over them so quest content per index stays stable.
	var board_floor: int = quests_completed_at_post
	var visible_count: int = 0
	var safety_cap: int = board_floor + board_size * 4
	var i: int = 0
	while i <= safety_cap and visible_count < board_size:
		var quest_id = "%s_daily_%s_%d" % [trading_post_id, date_str, i]
		# Always generate to keep RNG state in lockstep with
		# _regenerate_daily_quest's linear walk.
		var quest = _generate_daily_quest(trading_post_id, quest_id, i, post_distance,
			player_level, progression_modifier, quest_types, rng, post_coords)
		if i < board_floor:
			i += 1
			continue
		if quest_id in active_quest_ids or quest_id in completed_quests:
			i += 1
			continue
		if quest.is_empty():
			i += 1
			continue
		# First visible quest is the daily featured pick (was a hash-based
		# slot before; the sliding window makes "slot 0" the natural fit
		# since later slots can change as completions advance the floor).
		if visible_count == 0:
			quest["is_featured"] = true
			quest.rewards["xp"] = int(quest.rewards.get("xp", 0) * 1.5)
			quest.rewards["valor"] = max(quest.rewards.get("valor", 0), int(quest.rewards.get("valor", 0) * 1.5))
		quests.append(quest)
		visible_count += 1
		i += 1

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

	# Rewards scale with effective level (area + player) using pow() to match monster XP
	# Player-level scaling: high-level players at low-level posts still get reasonable quest XP
	var effective_reward_level = max(area_level, int(capped_level * 0.8))
	var level_factor = pow(effective_reward_level + 1, 2.2)
	var tier_base_xp = 3 + index * 2
	# Distance bonus: further posts give better rewards to incentivize exploration
	var distance_bonus_mult = 1.0 + clampf((post_distance - 50.0) / 600.0, 0.0, 0.30)
	var base_xp = int(tier_base_xp * level_factor * tier_mult * distance_bonus_mult)
	# Minimum XP floor so starter post quests aren't near-zero
	var min_xp = int((40 + index * 20) * tier_mult)
	base_xp = max(base_xp, min_xp)
	var valor = max(0, int((index - 1 + area_level / 50) * tier_mult * distance_bonus_mult))

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
			# v0.9.271 — added "any 'D' tile near this post will route you in"
			# clarification + "R" glyph hint, after a player report of the
			# merchant being unfindable in the wrong dungeon type.
			quest_desc = "A %s is trapped in %s on floor %d! Walk into any dungeon (D) near this trading post — you'll be routed to the right one. Look for the [color=#4DD0FF]R[/color] glyph inside." % [rescue_npc, dungeon_name, rescue_floor + 1]
			target = 1
			extra_fields["rescue_npc_type"] = rescue_npc
			extra_fields["dungeon_type"] = rescue_dungeon.get("type", "")
			extra_fields["rescue_floor"] = rescue_floor
			# Rescue quests: match dungeon clear rewards (equalized)
			base_xp = int(base_xp * 2.0)
			valor = max(valor + 2, int(valor * 1.5))

		QuestType.EXPLORATION:
			var nearby_posts = _find_nearby_posts(post_coords, 50, 300)
			if nearby_posts.size() > 0:
				var dest_idx = rng.randi() % nearby_posts.size()
				var dest_id = nearby_posts[dest_idx]
				var dest_coords = TRADING_POST_COORDS.get(dest_id, Vector2i(0, 0))
				var dest_name = dest_id.replace("_", " ").capitalize()
				var origin_name = trading_post_id.replace("_", " ").capitalize()
				var dist_text = _get_distance_text(post_coords, dest_coords)
				quest_name = "Journey to %s" % dest_name
				quest_desc = "Travel to %s, located %s from %s (%d, %d)." % [dest_name, dist_text, origin_name, post_coords.x, post_coords.y]
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

	# Determine board size — must match generate_dynamic_quests exactly so
	# the rng state stays in lockstep when we walk indices below. (Slice 13
	# bumped the ranges; pre-Slice-13 quest_ids no longer regenerate
	# bit-identical content because the rng state shifts, but the quest
	# data on already-accepted dailies lives in character.active_quests so
	# turn-in still works — _regenerate_daily_quest is only called when the
	# server needs to look up a quest that ISN'T in the player's log.)
	var area_level = max(1, int(post_distance * 0.5))
	if area_level < 10:
		var _count = rng.randi_range(5, 6)
	elif area_level < 100:
		var _count = rng.randi_range(7, 8)
	else:
		var _count = rng.randi_range(8, 10)

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
