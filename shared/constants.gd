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

# Character Classes (9 classes: 3 Warrior, 3 Mage, 3 Trickster)
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

# Character Races
const RACE_HUMAN = "Human"
const RACE_ELF = "Elf"
const RACE_DWARF = "Dwarf"

const AVAILABLE_RACES = [
	RACE_HUMAN,
	RACE_ELF,
	RACE_DWARF
]

# Race Descriptions
const RACE_DESCRIPTIONS = {
	RACE_HUMAN: "Adaptable and ambitious. Gains +10% bonus experience from all sources.",
	RACE_ELF: "Ancient and resilient. 50% reduced poison damage, immune to poison debuffs.",
	RACE_DWARF: "Sturdy and determined. 25% chance to survive lethal damage with 1 HP (once per combat)."
}

# Race Passive Abilities
const RACE_PASSIVES = {
	RACE_HUMAN: "xp_bonus",      # +10% XP gain
	RACE_ELF: "poison_resist",   # 50% poison damage reduction, immune to poison debuffs
	RACE_DWARF: "last_stand"     # 25% chance to survive lethal with 1 HP (once per combat)
}

# ===== ABILITY SYSTEM =====

# Mage Abilities (INT-based, use Mana)
const MAGE_ABILITIES = {
	"magic_bolt": {"level": 1, "cost": 0, "name": "Magic Bolt", "desc": "Deal damage equal to mana spent"},
	"shield": {"level": 10, "cost": 20, "name": "Shield", "desc": "+50% defense for 3 rounds"},
	"cloak": {"level": 25, "cost": 30, "name": "Cloak", "desc": "50% chance enemy misses next attack"},
	"blast": {"level": 40, "cost": 50, "name": "Blast", "desc": "Deal INT * 2 damage"},
	"forcefield": {"level": 60, "cost": 75, "name": "Forcefield", "desc": "Block next 2 attacks completely"},
	"teleport": {"level": 80, "cost": 40, "name": "Teleport", "desc": "Guaranteed flee (always succeeds)"},
	"meteor": {"level": 100, "cost": 100, "name": "Meteor", "desc": "Deal INT * 5 damage"}
}

# Warrior Abilities (STR-based, use Stamina)
const WARRIOR_ABILITIES = {
	"power_strike": {"level": 1, "cost": 10, "name": "Power Strike", "desc": "Deal STR * 1.5 damage"},
	"war_cry": {"level": 10, "cost": 15, "name": "War Cry", "desc": "+25% damage for 3 rounds"},
	"shield_bash": {"level": 25, "cost": 20, "name": "Shield Bash", "desc": "STR damage + stun enemy 1 turn"},
	"cleave": {"level": 40, "cost": 30, "name": "Cleave", "desc": "Deal STR * 2 damage"},
	"berserk": {"level": 60, "cost": 40, "name": "Berserk", "desc": "+100% damage, -50% defense 3 rounds"},
	"iron_skin": {"level": 80, "cost": 35, "name": "Iron Skin", "desc": "Block 50% damage for 3 rounds"},
	"devastate": {"level": 100, "cost": 50, "name": "Devastate", "desc": "Deal STR * 4 damage"}
}

# Trickster Abilities (WITS-based, use Energy)
const TRICKSTER_ABILITIES = {
	"analyze": {"level": 1, "cost": 5, "name": "Analyze", "desc": "Reveal monster HP, damage, intelligence"},
	"distract": {"level": 10, "cost": 15, "name": "Distract", "desc": "Enemy -50% accuracy next attack"},
	"pickpocket": {"level": 25, "cost": 20, "name": "Pickpocket", "desc": "Steal WITS*10 gold (fail = attacked)"},
	"ambush": {"level": 40, "cost": 30, "name": "Ambush", "desc": "WITS*1.5 damage + 50% crit chance"},
	"vanish": {"level": 60, "cost": 40, "name": "Vanish", "desc": "Go invisible, next attack crits"},
	"exploit": {"level": 80, "cost": 35, "name": "Exploit", "desc": "Deal 10% of monster's current HP"},
	"perfect_heist": {"level": 100, "cost": 50, "name": "Perfect Heist", "desc": "Instant win + double rewards"}
}

# Path thresholds (which path is active based on highest stat)
const PATH_STAT_THRESHOLD = 10  # Stat must be > 10 to unlock path abilities

# Class Descriptions
const CLASS_DESCRIPTIONS = {
	# Warrior Path (STR-focused, use Stamina)
	CLASS_FIGHTER: "Balanced warrior with good STR and CON. Uses Stamina for powerful melee abilities.",
	CLASS_BARBARIAN: "Offensive warrior with high STR but low defense. Devastating Stamina attacks.",
	# Mage Path (INT-focused, use Mana)
	CLASS_WIZARD: "Offensive spellcaster with high INT. Powerful Mana-based damage spells.",
	CLASS_SAGE: "Utility mage with balanced INT/WIS. Support spells and high mana pool.",
	# Trickster Path (WITS-focused, use Energy)
	CLASS_THIEF: "Cunning trickster with high WITS and DEX. Energy abilities and outsmart tactics.",
	CLASS_RANGER: "Versatile hybrid with STR/WITS. Mix of combat and trickster Energy abilities.",
	# Legacy classes (for existing characters)
	CLASS_PALADIN: "[Legacy] Holy warrior - no longer available for new characters",
	CLASS_SORCERER: "[Legacy] Pure mage - no longer available for new characters",
	CLASS_NINJA: "[Legacy] Shadow assassin - no longer available for new characters"
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
