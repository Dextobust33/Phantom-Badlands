# constants.gd
# Shared constants used by both server and client
extends Node

# Network Configuration
const SERVER_PORT = 9080
const SERVER_ADDRESS = "127.0.0.1"  # localhost for testing
const MAX_PLAYERS = 100

# Game Version
const GAME_VERSION = "0.1.0"

# Message Types (Client → Server)
const MSG_CONNECT = "connect"
const MSG_REGISTER = "register"
const MSG_LOGIN = "login"
const MSG_LIST_CHARACTERS = "list_characters"
const MSG_SELECT_CHARACTER = "select_character"
const MSG_CREATE_CHARACTER = "create_character"
const MSG_DELETE_CHARACTER = "delete_character"
const MSG_MOVE = "move"
const MSG_ACTION = "action"
const MSG_COMBAT_ACTION = "combat_action"
const MSG_CHAT = "chat"
const MSG_HEARTBEAT = "heartbeat"
const MSG_GET_LEADERBOARD = "get_leaderboard"
const MSG_LOGOUT_CHARACTER = "logout_character"
const MSG_LOGOUT_ACCOUNT = "logout_account"

# Message Types (Server → Client)
const MSG_WELCOME = "welcome"
const MSG_REGISTER_SUCCESS = "register_success"
const MSG_REGISTER_FAILED = "register_failed"
const MSG_LOGIN_SUCCESS = "login_success"
const MSG_LOGIN_FAILED = "login_failed"
const MSG_CHARACTER_LIST = "character_list"
const MSG_CHARACTER_LOADED = "character_loaded"
const MSG_CHAR_CREATED = "character_created"
const MSG_CHAR_DELETED = "character_deleted"
const MSG_LOCATION_UPDATE = "location_update"
const MSG_COMBAT_START = "combat_start"
const MSG_COMBAT_UPDATE = "combat_update"
const MSG_COMBAT_END = "combat_end"
const MSG_CHAT_MESSAGE = "chat_message"
const MSG_PERMADEATH = "permadeath"
const MSG_LEADERBOARD = "leaderboard"
const MSG_ERROR = "error"

# Character Classes
const CLASS_FIGHTER = "Fighter"
const CLASS_BARBARIAN = "Barbarian"
const CLASS_PALADIN = "Paladin"
const CLASS_WIZARD = "Wizard"
const CLASS_SORCERER = "Sorcerer"
const CLASS_SAGE = "Sage"
const CLASS_THIEF = "Thief"
const CLASS_RANGER = "Ranger"
const CLASS_NINJA = "Ninja"

const AVAILABLE_CLASSES = [
	CLASS_FIGHTER,
	CLASS_BARBARIAN,
	CLASS_PALADIN,
	CLASS_WIZARD,
	CLASS_SORCERER,
	CLASS_SAGE,
	CLASS_THIEF,
	CLASS_RANGER,
	CLASS_NINJA
]

# Class Descriptions
const CLASS_DESCRIPTIONS = {
	CLASS_FIGHTER: "Balanced melee combatant with good defense and offense",
	CLASS_BARBARIAN: "High damage warrior with low defense but devastating attacks",
	CLASS_PALADIN: "Holy warrior with defense and healing magic",
	CLASS_WIZARD: "Powerful offensive spellcaster",
	CLASS_SORCERER: "Glass cannon mage with incredible magical power",
	CLASS_SAGE: "Support caster focused on healing and buffs",
	CLASS_THIEF: "Fast and agile, strikes from the shadows",
	CLASS_RANGER: "Ranged fighter with tracking abilities",
	CLASS_NINJA: "Master of evasion and critical strikes"
}

# Starting Locations
const LOCATION_TOWN_SQUARE = "town_square"

# Combat Actions
const ACTION_ATTACK = "attack"
const ACTION_POWER_ATTACK = "power_attack"
const ACTION_DEFEND = "defend"
const ACTION_CAST_SPELL = "cast_spell"
const ACTION_USE_ITEM = "use_item"
const ACTION_FLEE = "flee"

# Health States
const HEALTH_HEALTHY = "Healthy"
const HEALTH_WOUNDED = "Wounded"
const HEALTH_BLOODIED = "Bloodied"
const HEALTH_CRITICAL = "Critical"

# Experience Table (simplified)
const EXPERIENCE_FOR_LEVEL = {
	1: 0,
	2: 100,
	3: 250,
	4: 500,
	5: 1000,
	10: 10000,
	20: 50000,
	50: 500000,
	100: 5000000
}

# Colors for UI (can be used in RichTextLabel with BBCode)
const COLOR_PLAYER = "#4A90E2"
const COLOR_NPC = "#50C878"
const COLOR_ENEMY = "#E74C3C"
const COLOR_DAMAGE = "#E74C3C"
const COLOR_HEAL = "#2ECC71"
const COLOR_GOLD = "#F39C12"
const COLOR_EXPERIENCE = "#9B59B6"
const COLOR_SYSTEM = "#95A5A6"
const COLOR_COMBAT = "#E67E22"
const COLOR_WARNING = "#F39C12"
const COLOR_ERROR = "#C0392B"

# Helper Functions
static func get_experience_for_level(level: int) -> int:
	"""Get experience required for a specific level"""
	if EXPERIENCE_FOR_LEVEL.has(level):
		return EXPERIENCE_FOR_LEVEL[level]
	# Formula for levels beyond the table
	return int(pow(level, 2.5) * 100)

static func get_health_state(current_hp: int, max_hp: int) -> String:
	"""Get health state description from HP values"""
	if max_hp <= 0:
		return HEALTH_CRITICAL
	
	var percent = (float(current_hp) / float(max_hp)) * 100.0
	
	if percent >= 70:
		return HEALTH_HEALTHY
	elif percent >= 30:
		return HEALTH_WOUNDED
	elif percent >= 10:
		return HEALTH_BLOODIED
	else:
		return HEALTH_CRITICAL

static func format_colored_text(text: String, color: String) -> String:
	"""Format text with BBCode color tags for RichTextLabel"""
	return "[color=%s]%s[/color]" % [color, text]

static func format_bold_text(text: String) -> String:
	"""Format text with BBCode bold tags"""
	return "[b]%s[/b]" % text
