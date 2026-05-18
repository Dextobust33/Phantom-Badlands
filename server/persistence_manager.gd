# persistence_manager.gd
# Handles all file-based persistence for accounts, characters, and leaderboard
class_name PersistenceManager
extends Node

const DATA_DIR = "user://data/"
const ACCOUNTS_FILE = "user://data/accounts.json"
const LEADERBOARD_FILE = "user://data/leaderboard.json"
const REALM_STATE_FILE = "user://data/realm_state.json"
const CHARACTERS_DIR = "user://data/characters/"
const CORPSES_FILE = "user://data/corpses.json"
const HOUSES_FILE = "user://data/houses.json"
const PLAYER_TILES_FILE = "user://data/player_tiles.json"
const PLAYER_POSTS_FILE = "user://data/player_posts.json"
# Audit #12 v0.9.507 — Signpost text storage. Keyed by "x_y" world coord. Each
# entry: {text, owner_username, set_at}. Persisted across restarts; cleared
# on map wipe.
const SIGNPOST_TEXTS_FILE = "user://data/signpost_texts.json"
const SIGNPOST_TEXT_MAX = 60
const MARKET_FILE = "user://data/market_data.json"
# Audit #14 Slice 1 — clans persistence. {clans: {clan_id: {name, tag,
# leader_account_id, member_ids[], created_at}}, next_clan_id: int}.
const CLANS_FILE = "user://data/clans.json"
const CLAN_NAME_MIN = 3
const CLAN_NAME_MAX = 24
const CLAN_TAG_MIN = 2
const CLAN_TAG_MAX = 5
const CLAN_MAX_MEMBERS = 30
const CLAN_MOTTO_MAX = 50  # Audit #14 v0.9.510 — short tagline shown on clan panel.
const GUARDS_FILE = "user://data/guards.json"
const BAN_LIST_FILE = "user://data/ban_list.json"

const MAX_LEADERBOARD_ENTRIES = 100
const DEFAULT_MAX_CHARACTERS = 6

# Password policy
const MIN_PASSWORD_LENGTH = 6
const MAX_PASSWORD_LENGTH = 128

# House upgrade definitions - cost in Baddie Points per level
const HOUSE_UPGRADES = {
	"house_size": {"effect": 1, "max": 3, "costs": [5000, 15000, 50000]},  # Expands the house layout
	"storage_slots": {"effect": 10, "max": 8, "costs": [500, 1000, 2000, 4000, 8000, 16000, 32000, 64000]},
	"companion_slots": {"effect": 1, "max": 8, "costs": [2000, 5000, 10000, 15000, 25000, 40000, 60000, 80000]},
	"egg_slots": {"effect": 1, "max": 9, "costs": [500, 1000, 2000, 4000, 7000, 12000, 20000, 35000, 60000]},
	"flee_chance": {"effect": 2, "max": 5, "costs": [1000, 2500, 5000, 10000, 20000]},
	"starting_valor": {"effect": 50, "max": 10, "costs": [250, 500, 750, 1000, 1500, 2000, 3000, 5000, 6500, 8000]},
	"xp_bonus": {"effect": 1, "max": 10, "costs": [1500, 3000, 5000, 8000, 12000, 18000, 28000, 45000, 70000, 100000]},
	"gathering_bonus": {"effect": 5, "max": 4, "costs": [800, 2000, 5000, 12000]},
	"kennel_capacity": {"effect": 0, "max": 9, "costs": [1000, 3000, 6000, 12000, 20000, 35000, 50000, 70000, 100000]},
	# Combat bonuses (percentages)
	"hp_bonus": {"effect": 5, "max": 5, "costs": [2000, 5000, 12000, 30000, 75000]},  # +5% max HP per level
	"resource_max": {"effect": 5, "max": 5, "costs": [2000, 5000, 12000, 30000, 75000]},  # +5% max resource per level
	"resource_regen": {"effect": 5, "max": 5, "costs": [3000, 8000, 20000, 50000, 120000]},  # +5% resource regen per level
	# Stat bonuses (+1 per level, exponential costs)
	"str_bonus": {"effect": 1, "max": 10, "costs": [1000, 2000, 4000, 7000, 12000, 18000, 26000, 36000, 45000, 50000]},
	"con_bonus": {"effect": 1, "max": 10, "costs": [1000, 2000, 4000, 7000, 12000, 18000, 26000, 36000, 45000, 50000]},
	"dex_bonus": {"effect": 1, "max": 10, "costs": [1000, 2000, 4000, 7000, 12000, 18000, 26000, 36000, 45000, 50000]},
	"int_bonus": {"effect": 1, "max": 10, "costs": [1000, 2000, 4000, 7000, 12000, 18000, 26000, 36000, 45000, 50000]},
	"wis_bonus": {"effect": 1, "max": 10, "costs": [1000, 2000, 4000, 7000, 12000, 18000, 26000, 36000, 45000, 50000]},
	"wits_bonus": {"effect": 1, "max": 10, "costs": [1000, 2000, 4000, 7000, 12000, 18000, 26000, 36000, 45000, 50000]},
	"post_slots": {"effect": 1, "max": 5, "costs": [5000, 10000, 20000, 35000, 60000]},
	# Audit #13 Slice 1 / Audit #4 Sanctuary tier — Companion Sanctum.
	# Each level grants +1 free Home Stone (Companion) in every new
	# character's starting inventory. Lets veteran accounts bootstrap new
	# characters past the early-registration pain point without spending
	# Valor on the NPC vendor (#4 Slice 1). Costs scaled to early-mid
	# Sanctuary tier so 1-2 levels are reachable in the first few deaths.
	"companion_sanctum": {"effect": 1, "max": 5, "costs": [500, 1500, 4000, 10000, 25000]},
	# Audit #13 Slice 2 — Bestiary. Account-level monster kill ledger.
	# Level 1: names + kill counts; Level 2: + highest level killed; Level 3:
	# + first-kill / last-kill timestamps. Always tracks (kills always recorded)
	# but the UI is gated on upgrade level so unlocking reveals incrementally
	# more info about your account's hunting history.
	"bestiary": {"effect": 1, "max": 3, "costs": [800, 3000, 12000]},
	# Audit #13 Slice 3 — Compass. Account-level exploration aid. Points the
	# player at the nearest NPC post they have NOT yet visited (per-account
	# ledger keyed on post name). Tiers reveal progressively more info:
	#   L1: direction only (N/S/E/W/NE/NW/SE/SW)
	#   L2: + distance in tiles
	#   L3: + post name
	# Visits are always recorded so unlocking later still uses the full history.
	"compass": {"effect": 1, "max": 3, "costs": [1000, 4000, 15000]},
	# Audit #13 Slice 4 — Region Atlas. Account-level region ledger.
	# Level 1: count of regions visited; Level 2: + sorted list of region names;
	# Level 3: + completion ratio (visited / total regions in the world).
	# Always tracks (visits always recorded) but the UI is gated on upgrade level.
	"region_atlas": {"effect": 1, "max": 3, "costs": [800, 3000, 12000]}
}

# Kennel capacity by upgrade level: 0=30, 1=50, ... 9=500
const KENNEL_CAPACITY_TABLE = [30, 50, 80, 120, 175, 250, 325, 400, 450, 500]

# Cached data
var accounts_data: Dictionary = {}
var leaderboard_data: Dictionary = {}
var realm_state_data: Dictionary = {}
var corpses_data: Dictionary = {}  # {"corpses": [...]}
var houses_data: Dictionary = {}  # {"houses": {account_id: house_data}}
var player_tiles_data: Dictionary = {}  # {"tiles": {username: [{x, y, type}]}}
var player_posts_data: Dictionary = {}  # {"posts": {username: [{name, center_x, center_y, created_at}]}}
var signpost_texts_data: Dictionary = {}  # {"signposts": {"x_y": {text, owner_username, set_at}}}
var market_data: Dictionary = {}  # {"listings": {post_id: [...]}, "next_id": 1}
# Audit #14 Slice 1 — clans cache. Loaded on startup, saved on every mutation.
var clans_data: Dictionary = {}  # {"clans": {clan_id: clan_dict}, "next_clan_id": int}
var ban_list_data: Dictionary = {}  # {"banned_ips": {ip: {reason, banned_at, banned_by}}}

func _ready():
	ensure_data_directories()
	load_accounts()
	load_leaderboard()
	load_monster_kills()
	load_realm_state()
	load_corpses()
	load_houses()
	load_player_tiles()
	load_player_posts()
	load_signpost_texts()
	load_player_storage()
	load_market_data()
	load_clans()
	load_ban_list()

# ===== DIRECTORY SETUP =====

func ensure_data_directories():
	"""Create data directories if they don't exist"""
	var dir = DirAccess.open("user://")
	if dir:
		if not dir.dir_exists("data"):
			dir.make_dir("data")
		if not dir.dir_exists("data/characters"):
			dir.make_dir_recursive("data/characters")

# ===== SAFE FILE SAVE =====

func _safe_save(filepath: String, data: Dictionary):
	"""Write data to file with backup protection.
	Creates a .bak backup before writing. If the main file becomes corrupt,
	_safe_load() will fall back to the backup."""
	var json_string = JSON.stringify(data, "\t")
	if json_string.is_empty():
		print("ERROR: JSON stringify returned empty for %s" % filepath)
		return

	# Create backup of current file before overwriting
	if FileAccess.file_exists(filepath):
		var backup_path = filepath + ".bak"
		var existing = FileAccess.open(filepath, FileAccess.READ)
		if existing:
			var existing_content = existing.get_as_text()
			existing.close()
			if existing_content.length() > 2:  # Only back up non-empty files
				var backup = FileAccess.open(backup_path, FileAccess.WRITE)
				if backup:
					backup.store_string(existing_content)
					backup.close()

	# Write new data
	var file = FileAccess.open(filepath, FileAccess.WRITE)
	if not file:
		print("ERROR: Failed to open file for save: %s" % filepath)
		return
	file.store_string(json_string)
	file.close()

func _safe_load(filepath: String) -> Dictionary:
	"""Load JSON from file with backup fallback.
	If main file is missing or corrupt, tries loading from .bak backup."""
	var data = _try_load_json(filepath)
	if not data.is_empty():
		return data

	# Main file failed - try backup
	var backup_path = filepath + ".bak"
	if FileAccess.file_exists(backup_path):
		print("WARNING: Main file corrupt/missing, loading backup: %s" % backup_path)
		data = _try_load_json(backup_path)
		if not data.is_empty():
			# Restore backup to main file
			_safe_save(filepath, data)
			print("Restored %s from backup" % filepath)
			return data
		else:
			print("ERROR: Backup also corrupt: %s" % backup_path)

	return {}

func _try_load_json(filepath: String) -> Dictionary:
	"""Try to load and parse a JSON file. Returns empty dict on failure."""
	if not FileAccess.file_exists(filepath):
		return {}
	var file = FileAccess.open(filepath, FileAccess.READ)
	if not file:
		return {}
	var content = file.get_as_text()
	file.close()
	if content.is_empty():
		return {}
	var json = JSON.new()
	var error = json.parse(content)
	if error != OK:
		print("ERROR: JSON parse failed for %s: %s" % [filepath, json.get_error_message()])
		return {}
	if json.data is Dictionary:
		return json.data
	return {}

# ===== PASSWORD HASHING =====

func generate_salt() -> String:
	"""Generate a random salt for password hashing"""
	var crypto = Crypto.new()
	var salt_bytes = crypto.generate_random_bytes(32)
	return salt_bytes.hex_encode()

func hash_password(password: String, salt: String) -> String:
	"""Hash a password with SHA-256 and salt"""
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update((salt + password).to_utf8_buffer())
	var hash_bytes = ctx.finish()
	return hash_bytes.hex_encode()

func verify_password(password: String, password_hash: String, salt: String) -> bool:
	"""Verify a password against stored hash and salt"""
	var computed_hash = hash_password(password, salt)
	return computed_hash == password_hash

# ===== ACCOUNT MANAGEMENT =====

func load_accounts():
	"""Load accounts data from file"""
	var data = _safe_load(ACCOUNTS_FILE)
	if data.is_empty():
		accounts_data = {
			"accounts": {},
			"username_to_id": {},
			"next_account_id": 1
		}
		save_accounts()
	else:
		accounts_data = data

func save_accounts():
	"""Save accounts data to file"""
	_safe_save(ACCOUNTS_FILE, accounts_data)

# Audit #14 v0.9.539 — Trade history (focused project #3). Account-level
# rolling log capped at TRADE_HISTORY_CAP entries (newest first). Used by
# the /trades chat command to surface direct-trade + market-buy +
# market-sale events with timestamp + counterparty + items + valor.
const TRADE_HISTORY_CAP: int = 50

func add_trade_history_entry(account_id: String, entry: Dictionary) -> void:
	"""Push a trade history entry to the account, capped at the front. Adds
	a timestamp if the caller didn't supply one. Persists immediately so
	the log survives crash/restart even if no other account state changed."""
	if not accounts_data.accounts.has(account_id):
		return
	var account = accounts_data.accounts[account_id]
	if not account.has("trade_history"):
		account["trade_history"] = []
	var history: Array = account["trade_history"]
	if not entry.has("timestamp"):
		entry["timestamp"] = int(Time.get_unix_time_from_system())
	history.push_front(entry.duplicate(true))
	while history.size() > TRADE_HISTORY_CAP:
		history.pop_back()
	save_accounts()

func get_trade_history(account_id: String, limit: int = 10) -> Array:
	"""Return the newest N trade history entries for the account. limit <= 0
	returns everything. Returns [] if account missing."""
	if not accounts_data.accounts.has(account_id):
		return []
	var history: Array = accounts_data.accounts[account_id].get("trade_history", [])
	if limit <= 0:
		return history.duplicate(true)
	var out: Array = []
	for i in range(min(limit, history.size())):
		out.append(history[i].duplicate(true) if history[i] is Dictionary else history[i])
	return out

func create_account(username: String, password: String) -> Dictionary:
	"""Create a new account with hashed password"""
	# Validate username
	if username.is_empty():
		return {"success": false, "reason": "Username cannot be empty"}

	if username.length() < 3:
		return {"success": false, "reason": "Username must be at least 3 characters"}

	if username.length() > 20:
		return {"success": false, "reason": "Username cannot exceed 20 characters"}

	# Check for valid characters (alphanumeric and underscore only)
	var valid_regex = RegEx.new()
	valid_regex.compile("^[a-zA-Z0-9_]+$")
	if not valid_regex.search(username):
		return {"success": false, "reason": "Username can only contain letters, numbers, and underscores"}

	# Check if username already exists
	var username_lower = username.to_lower()
	if accounts_data.username_to_id.has(username_lower):
		return {"success": false, "reason": "Username already exists"}

	# Validate password
	if password.length() < MIN_PASSWORD_LENGTH:
		return {"success": false, "reason": "Password must be at least %d characters" % MIN_PASSWORD_LENGTH}
	if password.length() > MAX_PASSWORD_LENGTH:
		return {"success": false, "reason": "Password cannot exceed %d characters" % MAX_PASSWORD_LENGTH}

	# Generate salt and hash password
	var salt = generate_salt()
	var password_hash = hash_password(password, salt)

	# Create account
	var account_id = "acc_%d" % accounts_data.next_account_id
	accounts_data.next_account_id += 1

	accounts_data.accounts[account_id] = {
		"username": username,
		"password_hash": password_hash,
		"password_salt": salt,
		"created_at": int(Time.get_unix_time_from_system()),
		"character_slots": [],
		"max_characters": DEFAULT_MAX_CHARACTERS,
		"is_admin": false,
		"mastery_records": {},  # ability_name → highest rank ever achieved on any character (Slice 2)
		"pending_headstarts": {},  # ability_name → rank queued for next character (Slice 3)
		"clan_id": ""  # Audit #14 Slice 1 — empty until player joins/creates a clan
	}

	accounts_data.username_to_id[username_lower] = account_id

	save_accounts()

	print("Account created: %s (ID: %s)" % [username, account_id])

	return {"success": true, "account_id": account_id, "username": username}

func authenticate(username: String, password: String) -> Dictionary:
	"""Authenticate a user and return account data"""
	var username_lower = username.to_lower()

	if not accounts_data.username_to_id.has(username_lower):
		return {"success": false, "reason": "Invalid username or password"}

	var account_id = accounts_data.username_to_id[username_lower]
	var account = accounts_data.accounts[account_id]

	if not verify_password(password, account.password_hash, account.password_salt):
		return {"success": false, "reason": "Invalid username or password"}

	print("Account authenticated: %s" % username)

	return {
		"success": true,
		"account_id": account_id,
		"username": account.username,
		"character_slots": account.character_slots,
		"max_characters": account.max_characters
	}

# Audit #14 v0.9.540 — Friend list (focused project #4). Account-level
# friend graph with request/accept consent flow, plus account-level block
# list. All persistent across permadeath. Keyed by account_id throughout.
#
# Account structure additions:
#   "friends": [account_id, ...]                 — confirmed bidirectional
#   "friend_requests_incoming": [account_id]     — waiting for ME to accept
#   "friend_requests_outgoing": [account_id]     — I asked, waiting on them
#   "blocked": [account_id]                      — accounts I've blocked

func get_account_id_by_username(username: String) -> String:
	"""Case-insensitive username → account_id lookup. Used by friend/block
	commands so players can refer to each other by their login username."""
	if username == "":
		return ""
	var lower = username.to_lower()
	if not accounts_data.has("username_to_id"):
		return ""
	return String(accounts_data.username_to_id.get(lower, ""))

func _ensure_social_arrays(account_id: String) -> void:
	"""Lazy-initialize friends/requests/blocked arrays on accounts that
	predate the friend system (so legacy accounts work without migration)."""
	if not accounts_data.accounts.has(account_id):
		return
	var account = accounts_data.accounts[account_id]
	if not account.has("friends"):
		account["friends"] = []
	if not account.has("friend_requests_incoming"):
		account["friend_requests_incoming"] = []
	if not account.has("friend_requests_outgoing"):
		account["friend_requests_outgoing"] = []
	if not account.has("blocked"):
		account["blocked"] = []

func get_friends(account_id: String) -> Array:
	if not accounts_data.accounts.has(account_id):
		return []
	_ensure_social_arrays(account_id)
	return accounts_data.accounts[account_id].friends.duplicate()

func get_friend_requests_incoming(account_id: String) -> Array:
	if not accounts_data.accounts.has(account_id):
		return []
	_ensure_social_arrays(account_id)
	return accounts_data.accounts[account_id].friend_requests_incoming.duplicate()

func get_friend_requests_outgoing(account_id: String) -> Array:
	if not accounts_data.accounts.has(account_id):
		return []
	_ensure_social_arrays(account_id)
	return accounts_data.accounts[account_id].friend_requests_outgoing.duplicate()

func get_blocked(account_id: String) -> Array:
	if not accounts_data.accounts.has(account_id):
		return []
	_ensure_social_arrays(account_id)
	return accounts_data.accounts[account_id].blocked.duplicate()

func is_friend(account_a: String, account_b: String) -> bool:
	if not accounts_data.accounts.has(account_a):
		return false
	_ensure_social_arrays(account_a)
	return account_b in accounts_data.accounts[account_a].friends

func is_blocked(viewer_account: String, target_account: String) -> bool:
	"""True if viewer has blocked target. Asymmetric — viewer.blocked controls
	whether target's messages reach viewer."""
	if not accounts_data.accounts.has(viewer_account):
		return false
	_ensure_social_arrays(viewer_account)
	return target_account in accounts_data.accounts[viewer_account].blocked

func send_friend_request(from_account: String, to_account: String) -> Dictionary:
	"""Add to_account → from_account's outgoing and from_account → to_account's
	incoming. Validates: not self, accounts exist, not already friends, neither
	party has blocked the other, request not already pending."""
	if from_account == to_account:
		return {"success": false, "reason": "You cannot friend yourself."}
	if not accounts_data.accounts.has(from_account):
		return {"success": false, "reason": "Your account is invalid."}
	if not accounts_data.accounts.has(to_account):
		return {"success": false, "reason": "Target account not found."}
	_ensure_social_arrays(from_account)
	_ensure_social_arrays(to_account)
	if to_account in accounts_data.accounts[from_account].friends:
		return {"success": false, "reason": "Already friends."}
	if to_account in accounts_data.accounts[from_account].blocked:
		return {"success": false, "reason": "You have blocked this user. Unblock first."}
	if from_account in accounts_data.accounts[to_account].blocked:
		return {"success": false, "reason": "That user has blocked you."}
	if to_account in accounts_data.accounts[from_account].friend_requests_outgoing:
		return {"success": false, "reason": "Request already pending."}
	# Symmetric incoming request: auto-accept (both sides asked, easy win).
	if to_account in accounts_data.accounts[from_account].friend_requests_incoming:
		return accept_friend_request(from_account, to_account)
	accounts_data.accounts[from_account].friend_requests_outgoing.append(to_account)
	accounts_data.accounts[to_account].friend_requests_incoming.append(from_account)
	save_accounts()
	return {"success": true, "auto_accepted": false}

func accept_friend_request(my_account: String, requester_account: String) -> Dictionary:
	"""Move requester from my incoming → both sides' friends. Cleans up the
	matching outgoing entry on the requester side. Idempotent if the friend
	pair already exists."""
	if not accounts_data.accounts.has(my_account):
		return {"success": false, "reason": "Your account is invalid."}
	if not accounts_data.accounts.has(requester_account):
		return {"success": false, "reason": "Requester account not found."}
	_ensure_social_arrays(my_account)
	_ensure_social_arrays(requester_account)
	if requester_account in accounts_data.accounts[my_account].friends:
		return {"success": false, "reason": "Already friends."}
	# Allow accept even if the incoming entry is missing (could have been
	# cleared by a block/unblock cycle) — as long as outgoing on the
	# requester side has us, treat as a mutual ask.
	var had_request = requester_account in accounts_data.accounts[my_account].friend_requests_incoming
	if not had_request:
		# Mutual outgoing? Counts as auto-accept.
		if my_account not in accounts_data.accounts[requester_account].friend_requests_outgoing:
			return {"success": false, "reason": "No pending request from that user."}
	accounts_data.accounts[my_account].friend_requests_incoming.erase(requester_account)
	accounts_data.accounts[requester_account].friend_requests_outgoing.erase(my_account)
	# Also clean up mirror entries in case the symmetric pair has stale state.
	accounts_data.accounts[my_account].friend_requests_outgoing.erase(requester_account)
	accounts_data.accounts[requester_account].friend_requests_incoming.erase(my_account)
	if requester_account not in accounts_data.accounts[my_account].friends:
		accounts_data.accounts[my_account].friends.append(requester_account)
	if my_account not in accounts_data.accounts[requester_account].friends:
		accounts_data.accounts[requester_account].friends.append(my_account)
	save_accounts()
	return {"success": true}

func reject_friend_request(my_account: String, requester_account: String) -> Dictionary:
	if not accounts_data.accounts.has(my_account):
		return {"success": false, "reason": "Your account is invalid."}
	_ensure_social_arrays(my_account)
	if requester_account not in accounts_data.accounts[my_account].friend_requests_incoming:
		return {"success": false, "reason": "No pending request from that user."}
	accounts_data.accounts[my_account].friend_requests_incoming.erase(requester_account)
	if accounts_data.accounts.has(requester_account):
		_ensure_social_arrays(requester_account)
		accounts_data.accounts[requester_account].friend_requests_outgoing.erase(my_account)
	save_accounts()
	return {"success": true}

func cancel_outgoing_request(my_account: String, target_account: String) -> Dictionary:
	if not accounts_data.accounts.has(my_account):
		return {"success": false, "reason": "Your account is invalid."}
	_ensure_social_arrays(my_account)
	if target_account not in accounts_data.accounts[my_account].friend_requests_outgoing:
		return {"success": false, "reason": "No outgoing request to that user."}
	accounts_data.accounts[my_account].friend_requests_outgoing.erase(target_account)
	if accounts_data.accounts.has(target_account):
		_ensure_social_arrays(target_account)
		accounts_data.accounts[target_account].friend_requests_incoming.erase(my_account)
	save_accounts()
	return {"success": true}

func remove_friend(my_account: String, target_account: String) -> Dictionary:
	"""Bidirectional friend removal. Either side can initiate; both sides'
	friend lists are scrubbed."""
	if not accounts_data.accounts.has(my_account):
		return {"success": false, "reason": "Your account is invalid."}
	_ensure_social_arrays(my_account)
	if target_account not in accounts_data.accounts[my_account].friends:
		return {"success": false, "reason": "Not friends."}
	accounts_data.accounts[my_account].friends.erase(target_account)
	if accounts_data.accounts.has(target_account):
		_ensure_social_arrays(target_account)
		accounts_data.accounts[target_account].friends.erase(my_account)
	save_accounts()
	return {"success": true}

func block_account(my_account: String, target_account: String) -> Dictionary:
	"""Add target to blocked. Also bidirectionally removes any friend relation
	and cancels any pending requests in either direction so the social state
	is consistent post-block."""
	if my_account == target_account:
		return {"success": false, "reason": "You cannot block yourself."}
	if not accounts_data.accounts.has(my_account):
		return {"success": false, "reason": "Your account is invalid."}
	if not accounts_data.accounts.has(target_account):
		return {"success": false, "reason": "Target account not found."}
	_ensure_social_arrays(my_account)
	_ensure_social_arrays(target_account)
	if target_account in accounts_data.accounts[my_account].blocked:
		return {"success": false, "reason": "Already blocked."}
	accounts_data.accounts[my_account].blocked.append(target_account)
	# Strip friendship + requests in both directions.
	accounts_data.accounts[my_account].friends.erase(target_account)
	accounts_data.accounts[target_account].friends.erase(my_account)
	accounts_data.accounts[my_account].friend_requests_incoming.erase(target_account)
	accounts_data.accounts[my_account].friend_requests_outgoing.erase(target_account)
	accounts_data.accounts[target_account].friend_requests_incoming.erase(my_account)
	accounts_data.accounts[target_account].friend_requests_outgoing.erase(my_account)
	save_accounts()
	return {"success": true}

func unblock_account(my_account: String, target_account: String) -> Dictionary:
	if not accounts_data.accounts.has(my_account):
		return {"success": false, "reason": "Your account is invalid."}
	_ensure_social_arrays(my_account)
	if target_account not in accounts_data.accounts[my_account].blocked:
		return {"success": false, "reason": "Not blocked."}
	accounts_data.accounts[my_account].blocked.erase(target_account)
	save_accounts()
	return {"success": true}

func get_username_for_account(account_id: String) -> String:
	"""Resolve account_id → username (display name). Audit #14 v0.9.539 trade
	history uses this for the counterparty label when the trader is offline."""
	if not accounts_data.accounts.has(account_id):
		return ""
	return String(accounts_data.accounts[account_id].get("username", ""))

func get_account_characters(account_id: String) -> Array:
	"""Get list of character summaries for an account"""
	if not accounts_data.accounts.has(account_id):
		return []

	var account = accounts_data.accounts[account_id]
	var characters = []

	for char_name in account.character_slots:
		var char_data = load_character(account_id, char_name)
		if char_data:
			characters.append({
				"name": char_data.get("name", char_name),
				"class": char_data.get("class", "Unknown"),
				"race": char_data.get("race", "Human"),
				"level": char_data.get("level", 1),
				"experience": char_data.get("experience", 0)
			})

	return characters

func can_create_character(account_id: String) -> bool:
	"""Check if account can create another character"""
	if not accounts_data.accounts.has(account_id):
		return false

	var account = accounts_data.accounts[account_id]
	return account.character_slots.size() < account.max_characters

func is_first_character_ever(account_id: String) -> bool:
	"""Check if this account has never had a character before (for tutorial)."""
	if not accounts_data.accounts.has(account_id):
		return true
	var account = accounts_data.accounts[account_id]
	if account.character_slots.size() > 0:
		return false
	# Check if they've earned baddie points (means a previous character died)
	var house = get_house(account_id)
	if house and house.get("total_baddie_points_earned", 0) > 0:
		return false
	return true

func find_account_for_character(char_name: String) -> String:
	"""Return the account_id whose character_slots contains char_name, or
	"" if no current account owns this character. Used for backfilling
	account_id on player posts at server start (Slice 5 — spawn at post).
	Posts owned by characters who have since died (and been cleared from
	character_slots) won't be findable here and remain orphaned."""
	if not accounts_data.has("accounts"):
		return ""
	for acc_id in accounts_data.accounts:
		var slots = accounts_data.accounts[acc_id].get("character_slots", [])
		if char_name in slots:
			return acc_id
	return ""

func get_pending_headstarts(account_id: String) -> Dictionary:
	"""Headstart ranks queued for the next character creation (Slice 3).
	Returns a duplicate of {ability_name → target_rank}."""
	if not accounts_data.accounts.has(account_id):
		return {}
	var account = accounts_data.accounts[account_id]
	return account.get("pending_headstarts", {}).duplicate()

# Slice 3 — mirrored from shared/constants.gd. Index = rank, value = BP cost
# for that step. Cumulative cost to rank 3 = 25 + 100 + 500 = 625 BP.
const MASTERY_HEADSTART_BP_PER_RANK: Array = [0, 25, 100, 500]
const MASTERY_HEADSTART_MAX_RANK: int = 3

func _headstart_cumulative_cost(target_rank: int) -> int:
	"""Sum of MASTERY_HEADSTART_BP_PER_RANK from rank 1 up to target_rank."""
	if target_rank <= 0:
		return 0
	var total = 0
	for i in range(1, min(target_rank + 1, MASTERY_HEADSTART_BP_PER_RANK.size())):
		total += int(MASTERY_HEADSTART_BP_PER_RANK[i])
	return total

func set_pending_headstart_rank(account_id: String, ability_name: String, target_rank: int) -> Dictionary:
	"""Set the queued headstart rank for an ability (Slice 3). Charges or
	refunds baddie points based on the difference vs the current pending rank.
	Validates target_rank ≤ recorded mastery, target_rank ≤ HEADSTART_MAX_RANK,
	and account has enough baddie points for any net charge.
	Returns {success, message, current_rank, baddie_points}."""
	if not accounts_data.accounts.has(account_id):
		return {"success": false, "message": "Account not found"}
	if ability_name == "":
		return {"success": false, "message": "No ability specified"}
	target_rank = clampi(target_rank, 0, MASTERY_HEADSTART_MAX_RANK)

	var account = accounts_data.accounts[account_id]
	if not account.has("pending_headstarts"):
		account["pending_headstarts"] = {}
	if not account.has("mastery_records"):
		account["mastery_records"] = {}

	var recorded_rank = int(account.mastery_records.get(ability_name, 0))
	if recorded_rank <= 0:
		return {"success": false, "message": "No mastery record for this ability"}
	if target_rank > recorded_rank:
		return {"success": false, "message": "Cannot exceed recorded rank (R%d)" % recorded_rank}

	var current_pending = int(account.pending_headstarts.get(ability_name, 0))
	if current_pending == target_rank:
		return {"success": true, "message": "No change", "current_rank": current_pending, "baddie_points": _get_house_baddie_points(account_id)}

	var current_cost = _headstart_cumulative_cost(current_pending)
	var target_cost = _headstart_cumulative_cost(target_rank)
	var delta_bp = target_cost - current_cost  # positive = pay; negative = refund

	if delta_bp > 0:
		var bp_available = _get_house_baddie_points(account_id)
		if bp_available < delta_bp:
			return {"success": false, "message": "Not enough baddie points (need %d, have %d)" % [delta_bp, bp_available]}
		spend_baddie_points(account_id, delta_bp)
	elif delta_bp < 0:
		add_baddie_points(account_id, -delta_bp)

	if target_rank == 0:
		account.pending_headstarts.erase(ability_name)
	else:
		account.pending_headstarts[ability_name] = target_rank
	save_accounts()

	return {"success": true, "message": "Headstart rank updated", "current_rank": target_rank, "baddie_points": _get_house_baddie_points(account_id)}

func consume_pending_headstarts(account_id: String) -> Dictionary:
	"""Read and clear the queued headstarts (Slice 3). Called when a new
	character is created so the queue applies to that character only."""
	if not accounts_data.accounts.has(account_id):
		return {}
	var account = accounts_data.accounts[account_id]
	var queued = account.get("pending_headstarts", {}).duplicate()
	if queued.size() > 0:
		account["pending_headstarts"] = {}
		save_accounts()
	return queued

func _get_house_baddie_points(account_id: String) -> int:
	"""Helper for Slice 3 — read the house's baddie points balance."""
	var house = get_house(account_id)
	if house == null:
		return 0
	return int(house.get("baddie_points", 0))

func get_account_mastery_records(account_id: String) -> Dictionary:
	"""Return account's highest-ever mastery ranks (Slice 2). Survives permadeath.
	Empty dict for new accounts or unknown account_id."""
	if not accounts_data.accounts.has(account_id):
		return {}
	var account = accounts_data.accounts[account_id]
	return account.get("mastery_records", {}).duplicate()

func update_account_mastery_record(account_id: String, ability_name: String, new_rank: int) -> bool:
	"""Bump the account's highest-ever rank for an ability if new_rank exceeds the
	stored value. Returns true if the record was updated, false if no change.
	Called by the server when a character ranks up an ability in combat."""
	if not accounts_data.accounts.has(account_id):
		return false
	var account = accounts_data.accounts[account_id]
	if not account.has("mastery_records"):
		account["mastery_records"] = {}
	var current = int(account["mastery_records"].get(ability_name, 0))
	if new_rank <= current:
		return false
	account["mastery_records"][ability_name] = new_rank
	save_accounts()
	return true

# ===== PENDING MARKET DELIVERIES (Audit #9 Slice 2b) =====
# When a seller fulfills a buy order and the buyer is offline (or their
# inventory is full), the items land here. Drained into the next character
# the account logs in with — no items are lost. Account-level so any of
# the player's characters can collect.

func get_account_pending_deliveries(account_id: String) -> Array:
	"""Return the queued deliveries for this account. Empty array if none."""
	if not accounts_data.accounts.has(account_id):
		return []
	var account = accounts_data.accounts[account_id]
	return account.get("pending_market_deliveries", []).duplicate(true)

func append_account_pending_delivery(account_id: String, delivery: Dictionary):
	"""Add one delivery entry to the queue. delivery shape:
	{item_type, item_name, quantity, order_id, fulfilled_by, timestamp}"""
	if not accounts_data.accounts.has(account_id):
		return
	var account = accounts_data.accounts[account_id]
	if not account.has("pending_market_deliveries"):
		account["pending_market_deliveries"] = []
	account["pending_market_deliveries"].append(delivery)
	save_accounts()

func clear_account_pending_deliveries(account_id: String):
	"""Wipe the queue (called after the items have been delivered to a character)."""
	if not accounts_data.accounts.has(account_id):
		return
	var account = accounts_data.accounts[account_id]
	account["pending_market_deliveries"] = []
	save_accounts()

func add_character_to_account(account_id: String, char_name: String):
	"""Add character name to account's character slots"""
	if not accounts_data.accounts.has(account_id):
		return

	var account = accounts_data.accounts[account_id]
	if char_name not in account.character_slots:
		account.character_slots.append(char_name)
		save_accounts()

func remove_character_from_account(account_id: String, char_name: String):
	"""Remove character name from account's character slots"""
	if not accounts_data.accounts.has(account_id):
		return

	var account = accounts_data.accounts[account_id]
	var idx = account.character_slots.find(char_name)
	if idx >= 0:
		account.character_slots.remove_at(idx)
		save_accounts()

# ===== CHARACTER PERSISTENCE =====

func get_character_filepath(account_id: String, char_name: String) -> String:
	"""Get filepath for a character file"""
	var safe_name = char_name.to_lower().replace(" ", "_")
	return CHARACTERS_DIR + account_id + "_" + safe_name + ".json"

func save_character(account_id: String, character: Character):
	"""Save a character to file"""
	var filepath = get_character_filepath(account_id, character.name)
	var data = character.to_dict()
	data["account_id"] = account_id
	_safe_save(filepath, data)

func load_character(account_id: String, char_name: String) -> Dictionary:
	"""Load character data from file"""
	var filepath = get_character_filepath(account_id, char_name)
	var data = _safe_load(filepath)
	if data.is_empty():
		return {}
	# Migrate legacy items to new tiered format
	if data.has("inventory"):
		data["inventory"] = _migrate_legacy_items(data["inventory"])
	return data

# ===== LEGACY ITEM MIGRATION =====

# Mapping from legacy types to new normalized types with tier
const LEGACY_ITEM_MIGRATIONS = {
	# Health potions
	"potion_minor": {"type": "health_potion", "tier": 1},
	"potion_lesser": {"type": "health_potion", "tier": 2},
	"potion_standard": {"type": "health_potion", "tier": 3},
	"potion_greater": {"type": "health_potion", "tier": 4},
	"potion_superior": {"type": "health_potion", "tier": 5},
	"potion_master": {"type": "health_potion", "tier": 6},
	# Mana potions
	"mana_minor": {"type": "mana_potion", "tier": 1},
	"mana_lesser": {"type": "mana_potion", "tier": 2},
	"mana_standard": {"type": "mana_potion", "tier": 3},
	"mana_greater": {"type": "mana_potion", "tier": 4},
	"mana_superior": {"type": "mana_potion", "tier": 5},
	"mana_master": {"type": "mana_potion", "tier": 6},
	# Stamina potions
	"stamina_minor": {"type": "stamina_potion", "tier": 1},
	"stamina_lesser": {"type": "stamina_potion", "tier": 2},
	"stamina_standard": {"type": "stamina_potion", "tier": 3},
	"stamina_greater": {"type": "stamina_potion", "tier": 4},
	# Energy potions
	"energy_minor": {"type": "energy_potion", "tier": 1},
	"energy_lesser": {"type": "energy_potion", "tier": 2},
	"energy_standard": {"type": "energy_potion", "tier": 3},
	"energy_greater": {"type": "energy_potion", "tier": 4},
	# Elixirs
	"elixir_minor": {"type": "elixir", "tier": 1},
	"elixir_greater": {"type": "elixir", "tier": 4},
	"elixir_divine": {"type": "elixir", "tier": 7},
}

func _migrate_legacy_items(inventory: Array) -> Array:
	"""Migrate legacy item types to new tiered format"""
	var migrated = false
	for item in inventory:
		if not item is Dictionary:
			continue
		var item_type = item.get("type", "")
		if LEGACY_ITEM_MIGRATIONS.has(item_type):
			var migration = LEGACY_ITEM_MIGRATIONS[item_type]
			item["type"] = migration["type"]
			item["tier"] = migration["tier"]
			migrated = true
	if migrated:
		print("Migrated legacy items in inventory")
	return inventory

func load_character_as_object(account_id: String, char_name: String) -> Character:
	"""Load character data and return a Character object"""
	var data = load_character(account_id, char_name)
	if data.is_empty():
		return null

	var character = Character.new()
	character.from_dict(data)

	# Safety check: ensure HP is at least 1 (unless character is dead via permadeath)
	# This prevents loading characters with 0 HP due to edge cases like combat disconnects
	if character.current_hp <= 0:
		print("WARNING: Character %s loaded with %d HP, resetting to 1" % [char_name, character.current_hp])
		character.current_hp = 1
		# Clear any saved combat state - they effectively lost that fight
		character.saved_combat_state = {}

	return character

func delete_character(account_id: String, char_name: String) -> bool:
	"""Delete a character file"""
	var filepath = get_character_filepath(account_id, char_name)

	if FileAccess.file_exists(filepath):
		var dir = DirAccess.open(CHARACTERS_DIR)
		if dir:
			var filename = filepath.get_file()
			dir.remove(filename)
			print("Character deleted: %s" % char_name)

			# Remove from account
			remove_character_from_account(account_id, char_name)
			return true

	return false

func character_name_exists(char_name: String) -> bool:
	"""Check if a character name already exists (across all accounts)"""
	var dir = DirAccess.open(CHARACTERS_DIR)
	if not dir:
		return false

	var safe_name = char_name.to_lower().replace(" ", "_")

	dir.list_dir_begin()
	var filename = dir.get_next()
	while filename != "":
		if not dir.current_is_dir() and filename.ends_with(".json"):
			# Check if filename contains the character name
			if filename.contains("_" + safe_name + ".json"):
				dir.list_dir_end()
				return true
		filename = dir.get_next()
	dir.list_dir_end()

	return false

# ===== LEADERBOARD =====

func load_leaderboard():
	"""Load leaderboard data from file"""
	var data = _safe_load(LEADERBOARD_FILE)
	if data.is_empty():
		leaderboard_data = {"entries": []}
		save_leaderboard()
	else:
		leaderboard_data = data

func save_leaderboard():
	"""Save leaderboard data to file"""
	_safe_save(LEADERBOARD_FILE, leaderboard_data)

func add_to_leaderboard(character: Character, cause_of_death: String, account_username: String, death_snapshot: Dictionary = {}) -> int:
	"""Add a deceased character to the leaderboard. Returns their rank.
	death_snapshot: Full character snapshot for viewing the death screen later."""
	var entry = {
		"character_name": character.name,
		"class": character.class_type,
		"level": character.level,
		"experience": character.experience,
		"account_username": account_username,
		"cause_of_death": cause_of_death,
		"monsters_killed": character.monsters_killed,
		"died_at": int(Time.get_unix_time_from_system()),
		"death_data": death_snapshot
	}

	# Add to entries
	leaderboard_data.entries.append(entry)

	# Sort by experience (descending)
	leaderboard_data.entries.sort_custom(func(a, b): return a.experience > b.experience)

	# Find rank of new entry
	var rank = 1
	for i in range(leaderboard_data.entries.size()):
		if leaderboard_data.entries[i].character_name == character.name and \
		   leaderboard_data.entries[i].died_at == entry.died_at:
			rank = i + 1
			break

	# Trim to max entries
	if leaderboard_data.entries.size() > MAX_LEADERBOARD_ENTRIES:
		leaderboard_data.entries.resize(MAX_LEADERBOARD_ENTRIES)

	# Update ranks
	for i in range(leaderboard_data.entries.size()):
		leaderboard_data.entries[i]["rank"] = i + 1

	save_leaderboard()

	print("Added to leaderboard: %s (Level %d, Rank %d)" % [character.name, character.level, rank])

	return rank

func get_leaderboard(limit: int = 10) -> Array:
	"""Get top entries from leaderboard (excludes bulky death_data for bandwidth)"""
	var result = []

	for entry in leaderboard_data.entries:
		var entry_copy = entry.duplicate()
		entry_copy.erase("death_data")
		result.append(entry_copy)
		if result.size() >= limit:
			break

	return result

func get_leaderboard_death_data(character_name: String, died_at: int = 0) -> Dictionary:
	"""Get death screen data for a specific leaderboard entry."""
	for entry in leaderboard_data.entries:
		if entry.get("character_name", "") == character_name:
			if died_at > 0 and entry.get("died_at", 0) != died_at:
				continue
			return entry.get("death_data", {})
	return {}

func remove_from_leaderboard(character_name: String) -> bool:
	"""Remove a specific entry from the leaderboard by character name. Returns true if found and removed."""
	var entries = leaderboard_data.get("entries", [])
	var found_index = -1
	for i in range(entries.size()):
		if entries[i].get("character_name", "") == character_name:
			found_index = i
			break

	if found_index == -1:
		print("Leaderboard: '%s' not found" % character_name)
		return false

	entries.remove_at(found_index)

	# Recalculate ranks
	for i in range(entries.size()):
		entries[i]["rank"] = i + 1

	save_leaderboard()
	print("Leaderboard: Removed '%s', ranks renumbered (%d entries remain)" % [character_name, entries.size()])
	return true

func reset_leaderboard():
	"""Reset the leaderboard - clears all entries"""
	leaderboard_data = {"entries": []}
	save_leaderboard()
	print("Leaderboard has been reset!")

# ===== REALM STATE PERSISTENCE =====

func load_realm_state():
	"""Load realm state (treasury, etc.) from file"""
	var data = _safe_load(REALM_STATE_FILE)
	if data.is_empty():
		realm_state_data = {"treasury": 0}
		save_realm_state()
	else:
		realm_state_data = data

func save_realm_state():
	"""Save realm state to file"""
	_safe_save(REALM_STATE_FILE, realm_state_data)

func get_realm_treasury() -> int:
	"""Get the current realm treasury balance"""
	return realm_state_data.get("treasury", 0)

func add_to_realm_treasury(amount: int):
	"""Add gold to the realm treasury"""
	realm_state_data["treasury"] = realm_state_data.get("treasury", 0) + amount
	save_realm_state()

func withdraw_from_realm_treasury(amount: int) -> int:
	"""Withdraw gold from the realm treasury. Returns actual amount withdrawn."""
	var current = realm_state_data.get("treasury", 0)
	var withdraw_amount = min(amount, current)
	realm_state_data["treasury"] = current - withdraw_amount
	save_realm_state()
	return withdraw_amount

# ===== PASSWORD CHANGE =====

func change_password(account_id: String, old_password: String, new_password: String) -> Dictionary:
	"""Change password for an account (requires old password verification)"""
	if not accounts_data.accounts.has(account_id):
		return {"success": false, "reason": "Account not found"}

	var account = accounts_data.accounts[account_id]

	# Verify old password
	if not verify_password(old_password, account.password_hash, account.password_salt):
		return {"success": false, "reason": "Current password is incorrect"}

	# Validate new password
	if new_password.length() < MIN_PASSWORD_LENGTH:
		return {"success": false, "reason": "New password must be at least %d characters" % MIN_PASSWORD_LENGTH}
	if new_password.length() > MAX_PASSWORD_LENGTH:
		return {"success": false, "reason": "New password cannot exceed %d characters" % MAX_PASSWORD_LENGTH}

	if old_password == new_password:
		return {"success": false, "reason": "New password must be different from current password"}

	# Generate new salt and hash
	var new_salt = generate_salt()
	var new_hash = hash_password(new_password, new_salt)

	# Update account
	account.password_hash = new_hash
	account.password_salt = new_salt

	save_accounts()

	print("Password changed for account: %s" % account.username)

	return {"success": true, "message": "Password changed successfully"}

# ===== ADMIN FUNCTIONS =====

func admin_reset_password(username: String, new_password: String) -> Dictionary:
	"""Admin function to reset a user's password"""
	var username_lower = username.to_lower()

	if not accounts_data.username_to_id.has(username_lower):
		return {"success": false, "reason": "Account not found: %s" % username}

	if new_password.length() < MIN_PASSWORD_LENGTH:
		return {"success": false, "reason": "Password must be at least %d characters" % MIN_PASSWORD_LENGTH}
	if new_password.length() > MAX_PASSWORD_LENGTH:
		return {"success": false, "reason": "Password cannot exceed %d characters" % MAX_PASSWORD_LENGTH}

	var account_id = accounts_data.username_to_id[username_lower]
	var account = accounts_data.accounts[account_id]

	# Generate new salt and hash
	var new_salt = generate_salt()
	var new_hash = hash_password(new_password, new_salt)

	# Update account
	account.password_hash = new_hash
	account.password_salt = new_salt

	save_accounts()

	print("[ADMIN] Password reset for account: %s" % username)

	return {"success": true, "message": "Password reset for %s" % username}

func admin_list_accounts() -> Array:
	"""Admin function to list all accounts"""
	var result = []

	for account_id in accounts_data.accounts.keys():
		var account = accounts_data.accounts[account_id]
		result.append({
			"account_id": account_id,
			"username": account.username,
			"created_at": account.get("created_at", 0),
			"character_count": account.character_slots.size(),
			"characters": account.character_slots
		})

	return result

func admin_get_account_info(username: String) -> Dictionary:
	"""Admin function to get detailed account info"""
	var username_lower = username.to_lower()

	if not accounts_data.username_to_id.has(username_lower):
		return {"success": false, "reason": "Account not found"}

	var account_id = accounts_data.username_to_id[username_lower]
	var account = accounts_data.accounts[account_id]

	return {
		"success": true,
		"account_id": account_id,
		"username": account.username,
		"created_at": account.get("created_at", 0),
		"max_characters": account.max_characters,
		"characters": account.character_slots,
		"is_admin": account.get("is_admin", false)
	}

# ===== ADMIN STATUS =====

func is_admin_account(account_id: String) -> bool:
	"""Check if an account has admin privileges"""
	if not accounts_data.accounts.has(account_id):
		return false
	return accounts_data.accounts[account_id].get("is_admin", false)

func is_admin_username(username: String) -> bool:
	"""Check if a username belongs to an admin account"""
	var username_lower = username.to_lower()
	if not accounts_data.username_to_id.has(username_lower):
		return false
	var account_id = accounts_data.username_to_id[username_lower]
	return is_admin_account(account_id)

func set_admin_status(username: String, is_admin: bool) -> Dictionary:
	"""Set admin status for an account by username"""
	var username_lower = username.to_lower()
	if not accounts_data.username_to_id.has(username_lower):
		return {"success": false, "message": "Account not found: %s" % username}
	var account_id = accounts_data.username_to_id[username_lower]
	accounts_data.accounts[account_id]["is_admin"] = is_admin
	save_accounts()
	return {"success": true, "message": "Admin status set to %s for %s" % [str(is_admin), username]}

# ===== MONSTER KILLS LEADERBOARD =====

const MONSTER_KILLS_FILE = "user://data/monster_kills_leaderboard.json"

var monster_kills_data: Dictionary = {}

func load_monster_kills():
	"""Load monster kills leaderboard from file"""
	var data = _safe_load(MONSTER_KILLS_FILE)
	if data.is_empty():
		monster_kills_data = {"monsters": {}}
		save_monster_kills()
	else:
		monster_kills_data = data
		_migrate_monster_kills_data()

func _migrate_monster_kills_data():
	"""Migrate old monster kill entries that have level info to base names"""
	if not monster_kills_data.has("monsters"):
		return

	var migrated = false
	var new_monsters = {}

	for monster_name in monster_kills_data.monsters.keys():
		var kills = monster_kills_data.monsters[monster_name]
		var base_name = monster_name

		# Strip level info (format: "Monster Name (Lvl X)")
		var lvl_pos = monster_name.find(" (Lvl ")
		if lvl_pos > 0:
			base_name = monster_name.substr(0, lvl_pos)
			migrated = true

		# Combine kills for same base monster
		if new_monsters.has(base_name):
			new_monsters[base_name] += kills
		else:
			new_monsters[base_name] = kills

	if migrated:
		monster_kills_data.monsters = new_monsters
		save_monster_kills()
		print("Migrated monster kills data to use base names")

func save_monster_kills():
	"""Save monster kills leaderboard to file"""
	_safe_save(MONSTER_KILLS_FILE, monster_kills_data)

func record_monster_kill(monster_name: String):
	"""Record a player kill by a monster (strips level info to group by base name)"""
	if not monster_kills_data.has("monsters"):
		monster_kills_data["monsters"] = {}

	# Strip level info from monster name (format: "Monster Name (Lvl X)")
	var base_name = monster_name
	var lvl_pos = monster_name.find(" (Lvl ")
	if lvl_pos > 0:
		base_name = monster_name.substr(0, lvl_pos)

	if not monster_kills_data.monsters.has(base_name):
		monster_kills_data.monsters[base_name] = 0

	monster_kills_data.monsters[base_name] += 1
	save_monster_kills()
	print("Monster kill recorded: %s (total: %d)" % [base_name, monster_kills_data.monsters[base_name]])

func get_monster_kills_leaderboard(limit: int = 20) -> Array:
	"""Get top monster killers sorted by kill count"""
	if not monster_kills_data.has("monsters"):
		return []

	var entries = []
	for monster_name in monster_kills_data.monsters.keys():
		entries.append({
			"monster_name": monster_name,
			"kills": monster_kills_data.monsters[monster_name]
		})

	# Sort by kills descending
	entries.sort_custom(func(a, b): return a.kills > b.kills)

	# Limit results
	if entries.size() > limit:
		entries.resize(limit)

	return entries

func reset_monster_kills():
	"""Reset the monster kills leaderboard - clears all entries"""
	monster_kills_data = {"monsters": {}}
	save_monster_kills()
	print("Monster kills leaderboard has been reset!")

func get_trophy_leaderboard() -> Dictionary:
	"""Get trophy hall of fame - first collector of each trophy type AND top collectors by count.
	Returns {first_discoveries: Array, top_collectors: Array}"""
	# Dictionary to track first collector of each trophy type
	# Format: {trophy_id: {name, collector, collected_at, monster_name, total_collectors}}
	var trophy_first_collectors: Dictionary = {}
	var trophy_total_counts: Dictionary = {}
	# Track per-character trophy counts for "most collected" ranking
	var char_trophy_counts: Dictionary = {}  # char_name -> count

	# Scan all accounts and their characters
	for account_id in accounts_data.accounts.keys():
		var account = accounts_data.accounts[account_id]
		for char_name in account.character_slots:
			var char_data = load_character(account_id, char_name)
			if char_data.is_empty():
				continue

			var trophies = char_data.get("trophies", [])
			var display_name = char_data.get("name", char_name)

			# Track this character's total trophy count
			if trophies.size() > 0:
				if not char_trophy_counts.has(display_name):
					char_trophy_counts[display_name] = 0
				char_trophy_counts[display_name] += trophies.size()

			for trophy in trophies:
				var trophy_id = trophy.get("id", "")
				if trophy_id.is_empty():
					continue

				var collected_at = trophy.get("obtained_at", 0)

				# Count total collectors
				if not trophy_total_counts.has(trophy_id):
					trophy_total_counts[trophy_id] = 0
				trophy_total_counts[trophy_id] += 1

				# Track first collector
				if not trophy_first_collectors.has(trophy_id):
					trophy_first_collectors[trophy_id] = {
						"trophy_id": trophy_id,
						"trophy_name": trophy.get("name", trophy_id),
						"collector": display_name,
						"collected_at": collected_at,
						"monster_name": trophy.get("monster_name", "Unknown")
					}
				elif collected_at > 0 and collected_at < trophy_first_collectors[trophy_id].get("collected_at", 999999999999):
					# Earlier collection found
					trophy_first_collectors[trophy_id] = {
						"trophy_id": trophy_id,
						"trophy_name": trophy.get("name", trophy_id),
						"collector": display_name,
						"collected_at": collected_at,
						"monster_name": trophy.get("monster_name", "Unknown")
					}

	# Build first discoveries array with total counts
	var first_discoveries = []
	for trophy_id in trophy_first_collectors.keys():
		var entry = trophy_first_collectors[trophy_id]
		entry["total_collectors"] = trophy_total_counts.get(trophy_id, 1)
		first_discoveries.append(entry)

	# Sort by collected_at (earliest first)
	first_discoveries.sort_custom(func(a, b): return a.get("collected_at", 0) < b.get("collected_at", 0))

	# Build top collectors array
	var top_collectors = []
	for char_name in char_trophy_counts.keys():
		top_collectors.append({"name": char_name, "trophy_count": char_trophy_counts[char_name]})
	top_collectors.sort_custom(func(a, b): return a.trophy_count > b.trophy_count)
	# Limit to top 10
	if top_collectors.size() > 10:
		top_collectors.resize(10)

	return {"first_discoveries": first_discoveries, "top_collectors": top_collectors}

# ===== CORPSE PERSISTENCE =====

func load_corpses():
	"""Load corpses data from file"""
	var data = _safe_load(CORPSES_FILE)
	if data.is_empty():
		corpses_data = {"corpses": []}
		save_corpses()
	else:
		corpses_data = data

func save_corpses():
	"""Save corpses data to file"""
	_safe_save(CORPSES_FILE, corpses_data)

func add_corpse(corpse: Dictionary):
	"""Add a corpse to persistence and save"""
	if not corpses_data.has("corpses"):
		corpses_data["corpses"] = []
	corpses_data.corpses.append(corpse)
	save_corpses()
	print("Corpse added: %s at (%d, %d)" % [corpse.get("character_name", "Unknown"), corpse.get("x", 0), corpse.get("y", 0)])

func remove_corpse(corpse_id: String) -> Dictionary:
	"""Remove a corpse by ID and return its data"""
	if not corpses_data.has("corpses"):
		return {}

	for i in range(corpses_data.corpses.size()):
		if corpses_data.corpses[i].get("id", "") == corpse_id:
			var corpse = corpses_data.corpses[i]
			corpses_data.corpses.remove_at(i)
			save_corpses()
			print("Corpse removed: %s" % corpse_id)
			return corpse

	return {}

func get_corpses() -> Array:
	"""Return all corpses"""
	return corpses_data.get("corpses", [])

func get_corpse_at(x: int, y: int) -> Dictionary:
	"""Get oldest corpse at a specific location (FIFO)"""
	if not corpses_data.has("corpses"):
		return {}

	var oldest_corpse = {}
	var oldest_time = 9999999999

	for corpse in corpses_data.corpses:
		if corpse.get("x", -9999) == x and corpse.get("y", -9999) == y:
			var created_at = corpse.get("created_at", 0)
			if created_at < oldest_time:
				oldest_time = created_at
				oldest_corpse = corpse

	return oldest_corpse

func get_visible_corpses(center_x: int, center_y: int, radius: int) -> Array:
	"""Get all corpses within the specified radius for map rendering"""
	var visible = []
	if not corpses_data.has("corpses"):
		return visible

	for corpse in corpses_data.corpses:
		var cx = corpse.get("x", -9999)
		var cy = corpse.get("y", -9999)
		if abs(cx - center_x) <= radius and abs(cy - center_y) <= radius:
			visible.append(corpse)

	return visible

# ===== HOUSE (SANCTUARY) PERSISTENCE =====

func load_houses():
	"""Load houses data from file"""
	var data = _safe_load(HOUSES_FILE)
	if data.is_empty():
		houses_data = {"houses": {}}
		save_houses()
	else:
		houses_data = data

func save_houses():
	"""Save houses data to file"""
	_safe_save(HOUSES_FILE, houses_data)

func get_house(account_id: String) -> Dictionary:
	"""Get a house by account ID, creating it if it doesn't exist"""
	if not houses_data.has("houses"):
		houses_data["houses"] = {}

	if not houses_data.houses.has(account_id):
		# Auto-create house for account
		return create_house(account_id)

	var house = houses_data.houses[account_id]

	# Migration: add valor fields if missing
	if not house.has("valor"):
		house["valor"] = 0
		house["total_valor_earned"] = 0
		save_house(account_id, house)

	# Migration: rename starting_gold → starting_valor
	if house.get("upgrades", {}).has("starting_gold"):
		house.upgrades["starting_valor"] = house.upgrades["starting_gold"]
		house.upgrades.erase("starting_gold")
		save_house(account_id, house)

	# Migration: add companion_kennel if missing
	if not house.has("companion_kennel"):
		house["companion_kennel"] = {"slots": 30, "companions": []}
		# Migrate stored_companions from storage to kennel
		var storage_items = house.get("storage", {}).get("items", [])
		var to_remove = []
		for i in range(storage_items.size()):
			if storage_items[i] is Dictionary and storage_items[i].get("type") == "stored_companion":
				var comp = storage_items[i].duplicate()
				comp.erase("type")
				house.companion_kennel.companions.append(comp)
				to_remove.append(i)
		if to_remove.size() > 0:
			to_remove.reverse()
			for idx in to_remove:
				storage_items.remove_at(idx)
		save_house(account_id, house)

	# Migration: add kennel_capacity upgrade if missing
	if not house.get("upgrades", {}).has("kennel_capacity"):
		if not house.has("upgrades"):
			house["upgrades"] = {}
		house.upgrades["kennel_capacity"] = 0
		save_house(account_id, house)

	# Migration: fix kennel slots to match new capacity table
	var kennel_level = int(house.get("upgrades", {}).get("kennel_capacity", 0))
	var expected_slots = KENNEL_CAPACITY_TABLE[clampi(kennel_level, 0, KENNEL_CAPACITY_TABLE.size() - 1)]
	if house.companion_kennel.slots < expected_slots:
		house.companion_kennel.slots = expected_slots
		save_house(account_id, house)

	return house

func create_house(account_id: String) -> Dictionary:
	"""Create a new house for an account"""
	if not houses_data.has("houses"):
		houses_data["houses"] = {}

	# Get username from account
	var username = "Unknown"
	if accounts_data.accounts.has(account_id):
		username = accounts_data.accounts[account_id].get("username", "Unknown")

	var house = {
		"owner_account_id": account_id,
		"owner_username": username,
		"created_at": int(Time.get_unix_time_from_system()),

		"storage": {
			"slots": 20,
			"items": []
		},

		"registered_companions": {
			"slots": 2,
			"companions": []
		},

		"companion_kennel": {
			"slots": 30,
			"companions": []
		},

		"valor": 0,
		"total_valor_earned": 0,

		"baddie_points": 0,
		"total_baddie_points_earned": 0,

		# Audit #3 Slice 6 — account-level tutorial nudge. Set to true after
		# the player has been shown the Sanctuary teaching overlay. Persists
		# across permadeath (account-level, not character-level).
		"seen_sanctuary_hint": false,

		"upgrades": {
			"house_size": 0,
			"storage_slots": 0,
			"companion_slots": 0,
			"flee_chance": 0,
			"starting_valor": 0,
			"xp_bonus": 0,
			"gathering_bonus": 0,
			"kennel_capacity": 0,
			"hp_bonus": 0,
			"resource_max": 0,
			"resource_regen": 0,
			"str_bonus": 0,
			"con_bonus": 0,
			"dex_bonus": 0,
			"int_bonus": 0,
			"wis_bonus": 0,
			"wits_bonus": 0
		},

		"stats": {
			"characters_lost": 0,
			"highest_level_reached": 0,
			"total_valor_earned": 0,
			"total_xp_earned": 0,
			"total_monsters_killed": 0
		},

		# Audit #13 Slice 2 — Bestiary ledger. Always recorded; UI is gated by
		# the bestiary house upgrade level. Each entry:
		#   monster_name → {kills, highest_level, first_killed_at, last_killed_at}
		"bestiary": {},

		# Audit #13 Slice 3 — Compass ledger. Always recorded; the compass
		# direction-finder ignores any post present in this dict. Each entry:
		#   post_name → first_visited_at (unix ts). Keyed by post name because
		# procedural NPC post identity is its name (npc_post_database.gd:235).
		"visited_posts": {},

		# Audit #13 Slice 4 (v0.9.444) — Region Atlas ledger. Always recorded;
		# the atlas count/list is gated by the region_atlas house upgrade.
		# Each entry: region_name → first_visited_at (unix ts).
		"visited_regions": {}
	}

	houses_data.houses[account_id] = house
	save_houses()

	print("House created for account: %s" % account_id)
	return house

func save_house(account_id: String, house: Dictionary):
	"""Save a specific house"""
	if not houses_data.has("houses"):
		houses_data["houses"] = {}

	houses_data.houses[account_id] = house
	save_houses()

func get_house_storage_capacity(account_id: String) -> int:
	"""Get total storage slots for a house (base + upgrades)"""
	var house = get_house(account_id)
	var base_slots = house.storage.slots
	var upgrade_level = house.upgrades.get("storage_slots", 0)
	return base_slots + (upgrade_level * HOUSE_UPGRADES.storage_slots.effect)

func get_house_companion_capacity(account_id: String) -> int:
	"""Get total registered companion slots for a house"""
	var house = get_house(account_id)
	var base_slots = house.registered_companions.slots
	var upgrade_level = house.upgrades.get("companion_slots", 0)
	return base_slots + (upgrade_level * HOUSE_UPGRADES.companion_slots.effect)

func get_egg_capacity(account_id: String) -> int:
	"""Get total egg incubation slots (base 3 + egg_slots upgrade)"""
	var house = get_house(account_id)
	var upgrade_level = house.upgrades.get("egg_slots", 0)
	return 3 + (upgrade_level * HOUSE_UPGRADES.egg_slots.effect)

# Audit #13 Slice 2 — Bestiary helpers.

func bestiary_level(account_id: String) -> int:
	"""Return the bestiary upgrade level (0 = locked, 1-3 = unlocked tiers)."""
	var house = get_house(account_id)
	if house == null or not house.has("upgrades"):
		return 0
	return int(house.upgrades.get("bestiary", 0))

func record_bestiary_kill(account_id: String, monster_name: String, monster_level: int) -> void:
	"""Increment the account's bestiary ledger for this monster type. Tracked
	even when the upgrade is locked — unlocking later reveals the history.
	Cheap no-op for missing accounts (rare race condition during character
	creation / disconnect)."""
	if account_id == "" or monster_name == "":
		return
	var house = get_house(account_id)
	if house == null:
		return
	# Legacy houses created before Slice 2 ship may not have the bestiary key.
	if not house.has("bestiary") or typeof(house.bestiary) != TYPE_DICTIONARY:
		house["bestiary"] = {}
	var now_ts = int(Time.get_unix_time_from_system())
	if house.bestiary.has(monster_name):
		var entry: Dictionary = house.bestiary[monster_name]
		entry["kills"] = int(entry.get("kills", 0)) + 1
		entry["highest_level"] = max(int(entry.get("highest_level", 0)), monster_level)
		entry["last_killed_at"] = now_ts
		house.bestiary[monster_name] = entry
	else:
		house.bestiary[monster_name] = {
			"kills": 1,
			"highest_level": monster_level,
			"first_killed_at": now_ts,
			"last_killed_at": now_ts,
		}
	save_house(account_id, house)

func get_bestiary(account_id: String) -> Dictionary:
	"""Return the raw bestiary dict (monster_name → entry). Empty if account
	has no house or has never killed anything."""
	var house = get_house(account_id)
	if house == null or not house.has("bestiary"):
		return {}
	return house.bestiary.duplicate(true)

# Audit #13 Slice 3 — Compass helpers.

func compass_level(account_id: String) -> int:
	"""Return the compass upgrade level (0 = locked, 1-3 = unlocked tiers)."""
	var house = get_house(account_id)
	if house == null or not house.has("upgrades"):
		return 0
	return int(house.upgrades.get("compass", 0))

func record_post_visit(account_id: String, post_name: String) -> bool:
	"""Mark a post as visited by this account. Returns true if this was the
	first visit (new entry), false if already recorded. Always tracked even
	when the compass upgrade is locked — unlocking later uses the full ledger."""
	if account_id == "" or post_name == "":
		return false
	var house = get_house(account_id)
	if house == null:
		return false
	# Legacy houses created before Slice 3 ship may not have visited_posts.
	if not house.has("visited_posts") or typeof(house.visited_posts) != TYPE_DICTIONARY:
		house["visited_posts"] = {}
	if house.visited_posts.has(post_name):
		return false
	house.visited_posts[post_name] = int(Time.get_unix_time_from_system())
	save_house(account_id, house)
	return true

func is_post_visited(account_id: String, post_name: String) -> bool:
	"""Cheap check for use in the compass direction-finder. False when account
	has no house or hasn't visited that post."""
	if account_id == "" or post_name == "":
		return false
	var house = get_house(account_id)
	if house == null or not house.has("visited_posts"):
		return false
	return house.visited_posts.has(post_name)

func get_visited_posts(account_id: String) -> Dictionary:
	"""Return the raw visited_posts dict (post_name → first_visit_ts). Empty
	if the account has no house or has never visited a post."""
	var house = get_house(account_id)
	if house == null or not house.has("visited_posts"):
		return {}
	return house.visited_posts.duplicate(true)


# Audit #13 Slice 4 (v0.9.444) — Region Atlas helpers. Mirror the Compass
# pattern: always-track ledger + tier-gated UI.

func region_atlas_level(account_id: String) -> int:
	"""Return the region_atlas house-upgrade level (0 = locked / 1-3 = tiers
	revealing progressively more atlas detail)."""
	var house = get_house(account_id)
	if house == null or not house.has("upgrades"):
		return 0
	return int(house.upgrades.get("region_atlas", 0))


func record_region_visit(account_id: String, region_name: String) -> bool:
	"""Mark a region as visited by this account. Returns true if this was
	the first visit (new entry), false if already recorded. Always tracked
	even when the upgrade is locked — unlocking later uses the full ledger."""
	if account_id == "" or region_name == "":
		return false
	# Cheap canonical filter — when no NPC posts are reachable we hand back
	# "Wilderness" from chunk_manager. That's a fallback, not a discoverable
	# region; don't pollute the ledger with it.
	if region_name == "Wilderness":
		return false
	var house = get_house(account_id)
	if house == null:
		return false
	# Legacy houses created before Slice 4 ship may not have visited_regions.
	if not house.has("visited_regions") or typeof(house.visited_regions) != TYPE_DICTIONARY:
		house["visited_regions"] = {}
	if house.visited_regions.has(region_name):
		return false
	house.visited_regions[region_name] = int(Time.get_unix_time_from_system())
	save_house(account_id, house)
	return true


func get_visited_regions(account_id: String) -> Dictionary:
	"""Return the raw visited_regions dict (region_name → first_visit_ts).
	Empty if the account has no house or has never visited a region."""
	var house = get_house(account_id)
	if house == null or not house.has("visited_regions"):
		return {}
	return house.visited_regions.duplicate(true)

func get_bestiary_summary(account_id: String) -> Dictionary:
	"""Return a summary blob suitable for sending to the client: entries list
	sorted by kill count desc, total kills, unique species count, and the
	upgrade level (so the client can decide which fields to render)."""
	var raw = get_bestiary(account_id)
	var entries: Array = []
	var total_kills: int = 0
	for monster_name in raw.keys():
		var entry: Dictionary = raw[monster_name]
		var kills = int(entry.get("kills", 0))
		entries.append({
			"name": monster_name,
			"kills": kills,
			"highest_level": int(entry.get("highest_level", 0)),
			"first_killed_at": int(entry.get("first_killed_at", 0)),
			"last_killed_at": int(entry.get("last_killed_at", 0)),
		})
		total_kills += kills
	entries.sort_custom(func(a, b): return a.kills > b.kills)
	return {
		"entries": entries,
		"unique_count": entries.size(),
		"total_kills": total_kills,
		"level": bestiary_level(account_id),
	}

func add_item_to_house_storage(account_id: String, item: Dictionary) -> bool:
	"""Add an item to house storage. Stacks consumables with matching type/tier. Returns true if successful."""
	var house = get_house(account_id)
	var capacity = get_house_storage_capacity(account_id)

	# Try to stack with existing consumable items
	if item.get("is_consumable", false):
		for existing in house.storage.items:
			if existing.get("is_consumable", false) and existing.get("type", "") == item.get("type", "") and int(existing.get("tier", 0)) == int(item.get("tier", 0)):
				existing["quantity"] = existing.get("quantity", 1) + item.get("quantity", 1)
				save_house(account_id, house)
				return true

	if house.storage.items.size() >= capacity:
		return false

	house.storage.items.append(item)
	save_house(account_id, house)
	return true

func remove_item_from_house_storage(account_id: String, index: int) -> Dictionary:
	"""Remove an item from house storage by index. Returns the item."""
	var house = get_house(account_id)

	if index < 0 or index >= house.storage.items.size():
		return {}

	var item = house.storage.items[index]
	house.storage.items.remove_at(index)
	save_house(account_id, house)
	return item

func register_companion_to_house(account_id: String, companion: Dictionary, checked_out_by = null) -> int:
	"""Register a companion to the house. Returns slot index or -1 if full."""
	var house = get_house(account_id)
	var capacity = get_house_companion_capacity(account_id)

	if house.registered_companions.companions.size() >= capacity:
		return -1

	# Add registration metadata
	companion["registered_at"] = int(Time.get_unix_time_from_system())
	companion["checked_out_by"] = checked_out_by
	companion["checkout_time"] = null

	house.registered_companions.companions.append(companion)
	save_house(account_id, house)
	return house.registered_companions.companions.size() - 1

func checkout_companion_from_house(account_id: String, slot: int, character_name: String) -> Dictionary:
	"""Check out a companion from house. Returns the companion or empty dict."""
	var house = get_house(account_id)

	if slot < 0 or slot >= house.registered_companions.companions.size():
		return {}

	var companion = house.registered_companions.companions[slot]
	if companion.get("checked_out_by") != null:
		return {}  # Already checked out

	companion["checked_out_by"] = character_name
	companion["checkout_time"] = int(Time.get_unix_time_from_system())
	save_house(account_id, house)
	return companion

func return_companion_to_house(account_id: String, slot: int, updated_companion: Dictionary) -> bool:
	"""Return a companion to house storage with updated stats."""
	var house = get_house(account_id)

	if slot < 0 or slot >= house.registered_companions.companions.size():
		return false

	# Update companion data but keep registration info
	var registered_at = house.registered_companions.companions[slot].get("registered_at", 0)
	updated_companion["registered_at"] = registered_at
	updated_companion["checked_out_by"] = null
	updated_companion["checkout_time"] = null

	house.registered_companions.companions[slot] = updated_companion
	save_house(account_id, house)
	return true

func unregister_companion_from_house(account_id: String, slot: int) -> Dictionary:
	"""Remove a companion from house registration. Returns the companion."""
	var house = get_house(account_id)

	if slot < 0 or slot >= house.registered_companions.companions.size():
		return {}

	var companion = house.registered_companions.companions[slot]
	if companion.get("checked_out_by") != null:
		return {}  # Can't unregister while checked out

	house.registered_companions.companions.remove_at(slot)
	save_house(account_id, house)
	return companion

func get_kennel_capacity(account_id: String) -> int:
	"""Get total kennel slots for a house based on upgrade level."""
	var house = get_house(account_id)
	var level = house.get("upgrades", {}).get("kennel_capacity", 0)
	return KENNEL_CAPACITY_TABLE[clampi(level, 0, KENNEL_CAPACITY_TABLE.size() - 1)]

func add_companion_to_kennel(account_id: String, companion: Dictionary) -> int:
	"""Add companion to kennel. Returns index or -1 if full."""
	var house = get_house(account_id)
	var capacity = get_kennel_capacity(account_id)
	if house.companion_kennel.companions.size() >= capacity:
		return -1
	companion["stored_at"] = int(Time.get_unix_time_from_system())
	house.companion_kennel.companions.append(companion)
	save_house(account_id, house)
	return house.companion_kennel.companions.size() - 1

func remove_companion_from_kennel(account_id: String, index: int) -> Dictionary:
	"""Remove companion from kennel. Returns companion or empty dict."""
	var house = get_house(account_id)
	if index < 0 or index >= house.companion_kennel.companions.size():
		return {}
	var companion = house.companion_kennel.companions[index]
	house.companion_kennel.companions.remove_at(index)
	save_house(account_id, house)
	return companion

func fuse_companions(account_id: String, indices: Array, output_companion: Dictionary) -> bool:
	"""Remove companions at indices from kennel and add output_companion."""
	var house = get_house(account_id)
	var kennel = house.companion_kennel.companions
	for idx in indices:
		if idx < 0 or idx >= kennel.size():
			return false
	# Remove in reverse order to preserve indices
	var sorted_indices = indices.duplicate()
	sorted_indices.sort()
	sorted_indices.reverse()
	for idx in sorted_indices:
		kennel.remove_at(idx)
	output_companion["stored_at"] = int(Time.get_unix_time_from_system())
	kennel.append(output_companion)
	save_house(account_id, house)
	return true

func add_baddie_points(account_id: String, points: int):
	"""Add baddie points to a house"""
	var house = get_house(account_id)
	house["baddie_points"] = house.get("baddie_points", 0) + points
	house["total_baddie_points_earned"] = house.get("total_baddie_points_earned", 0) + points
	save_house(account_id, house)

func spend_baddie_points(account_id: String, amount: int) -> bool:
	"""Spend baddie points. Returns true if successful."""
	var house = get_house(account_id)
	if house.get("baddie_points", 0) < amount:
		return false

	house["baddie_points"] = house.get("baddie_points", 0) - amount
	save_house(account_id, house)
	return true

func purchase_house_upgrade(account_id: String, upgrade_id: String) -> Dictionary:
	"""Purchase a house upgrade. Returns {success: bool, message: String}"""
	var house = get_house(account_id)

	if not HOUSE_UPGRADES.has(upgrade_id):
		return {"success": false, "message": "Unknown upgrade: %s" % upgrade_id}

	var upgrade_def = HOUSE_UPGRADES[upgrade_id]
	var current_level = house.upgrades.get(upgrade_id, 0)

	if current_level >= upgrade_def.max:
		return {"success": false, "message": "Upgrade already at maximum level."}

	var cost = upgrade_def.costs[current_level]
	if house.get("baddie_points", 0) < cost:
		return {"success": false, "message": "Not enough Baddie Points. Need %d, have %d." % [cost, house.get("baddie_points", 0)]}

	# Purchase successful
	house["baddie_points"] = house.get("baddie_points", 0) - cost
	house.upgrades[upgrade_id] = current_level + 1

	# Special handling: update kennel capacity
	if upgrade_id == "kennel_capacity":
		var new_level = current_level + 1
		house.companion_kennel.slots = KENNEL_CAPACITY_TABLE[clampi(new_level, 0, KENNEL_CAPACITY_TABLE.size() - 1)]

	save_house(account_id, house)

	return {"success": true, "message": "Upgrade purchased! %s is now level %d." % [upgrade_id, current_level + 1]}

func update_house_stats(account_id: String, stat_updates: Dictionary):
	"""Update house lifetime stats"""
	var house = get_house(account_id)

	for stat_name in stat_updates.keys():
		var current = house.stats.get(stat_name, 0)
		var update_type = "add"  # Default: add to existing
		var value = stat_updates[stat_name]

		if stat_name == "highest_level_reached":
			# Take maximum
			house.stats[stat_name] = maxi(current, value)
		else:
			# Add to total
			house.stats[stat_name] = current + value

	save_house(account_id, house)

func get_house_bonuses(account_id: String) -> Dictionary:
	"""Calculate all bonuses from house upgrades"""
	var house = get_house(account_id)
	var bonuses = {
		"flee_chance": 0,
		"starting_valor": 0,
		"xp_bonus": 0,
		"gathering_bonus": 0,
		"hp_bonus": 0,
		"resource_max": 0,
		"resource_regen": 0,
		"str_bonus": 0,
		"con_bonus": 0,
		"dex_bonus": 0,
		"int_bonus": 0,
		"wis_bonus": 0,
		"wits_bonus": 0,
		"egg_slots": 0
	}

	var upgrades = house.get("upgrades", {})
	var bonus_ids = ["flee_chance", "starting_valor", "xp_bonus", "gathering_bonus",
					 "hp_bonus", "resource_max", "resource_regen",
					 "str_bonus", "con_bonus", "dex_bonus", "int_bonus", "wis_bonus", "wits_bonus",
					 "egg_slots"]
	for upgrade_id in bonus_ids:
		var level = upgrades.get(upgrade_id, 0)
		if level > 0 and HOUSE_UPGRADES.has(upgrade_id):
			bonuses[upgrade_id] = level * HOUSE_UPGRADES[upgrade_id].effect

	return bonuses

func calculate_baddie_points(character: Character) -> int:
	"""Calculate baddie points earned from a character on death"""
	var points = 0

	# XP contribution: 1 BP per 100 XP
	points += int(character.experience / 100)

	# Monster Gem contribution: 5 BP per gem
	points += character.crafting_materials.get("monster_gem", 0) * 5

	# Kill contribution: 1 BP per 10 kills
	points += int(character.monsters_killed / 10)

	# Quest contribution: 10 BP per completed quest
	points += character.completed_quests.size() * 10

	# Level milestones
	if character.level >= 10:
		points += 50
	if character.level >= 25:
		points += 150
	if character.level >= 50:
		points += 400
	if character.level >= 100:
		points += 1000

	return points

# ===== PLAYER TILES (Building System) =====

func load_player_tiles():
	"""Load player-placed tile tracking data."""
	var data = _safe_load(PLAYER_TILES_FILE)
	if data.is_empty():
		player_tiles_data = {"tiles": {}}
	else:
		player_tiles_data = data

func save_player_tiles():
	"""Save player-placed tile tracking data."""
	_safe_save(PLAYER_TILES_FILE, player_tiles_data)

func get_player_tiles(username: String) -> Array:
	"""Get all tiles placed by a player. Returns [{x, y, type}, ...]."""
	if not player_tiles_data.has("tiles"):
		player_tiles_data["tiles"] = {}
	return player_tiles_data.tiles.get(username, [])

func add_player_tile(username: String, x: int, y: int, tile_type: String, meta: Dictionary = {}):
	"""Track a player-placed tile. Optional meta dict merged into tile data."""
	if not player_tiles_data.has("tiles"):
		player_tiles_data["tiles"] = {}
	if not player_tiles_data.tiles.has(username):
		player_tiles_data.tiles[username] = []
	var entry = {"x": x, "y": y, "type": tile_type}
	entry.merge(meta)
	player_tiles_data.tiles[username].append(entry)
	save_player_tiles()

func remove_player_tile(username: String, x: int, y: int):
	"""Remove a tracked player tile at position."""
	if not player_tiles_data.has("tiles"):
		return
	if not player_tiles_data.tiles.has(username):
		return
	var tiles = player_tiles_data.tiles[username]
	for i in range(tiles.size() - 1, -1, -1):
		if int(tiles[i].get("x", 0)) == x and int(tiles[i].get("y", 0)) == y:
			tiles.remove_at(i)
			break
	save_player_tiles()

func get_all_player_tiles() -> Dictionary:
	"""Get all player tiles. Returns {username: [{x, y, type}, ...]}."""
	if not player_tiles_data.has("tiles"):
		player_tiles_data["tiles"] = {}
	return player_tiles_data.tiles

func clear_all_player_tiles():
	"""Clear all player tile data (called on map wipe)."""
	player_tiles_data = {"tiles": {}}
	save_player_tiles()

# ===== PLAYER POSTS (Named Enclosures) =====

func load_player_posts():
	"""Load player post naming data."""
	var data = _safe_load(PLAYER_POSTS_FILE)
	if data.is_empty():
		player_posts_data = {"posts": {}}
	else:
		player_posts_data = data

func save_player_posts():
	"""Save player post naming data."""
	_safe_save(PLAYER_POSTS_FILE, player_posts_data)

func get_player_posts(username: String) -> Array:
	"""Get all posts for a player. Returns [{name, center_x, center_y, created_at}, ...]."""
	if not player_posts_data.has("posts"):
		player_posts_data["posts"] = {}
	return player_posts_data.posts.get(username, [])

func set_player_post(username: String, index: int, data: Dictionary):
	"""Set or update a player post at given index."""
	if not player_posts_data.has("posts"):
		player_posts_data["posts"] = {}
	if not player_posts_data.posts.has(username):
		player_posts_data.posts[username] = []
	while player_posts_data.posts[username].size() <= index:
		player_posts_data.posts[username].append({})
	player_posts_data.posts[username][index] = data
	save_player_posts()

func remove_player_post(username: String, index: int):
	"""Remove a player post at given index."""
	if not player_posts_data.has("posts"):
		return
	if not player_posts_data.posts.has(username):
		return
	var posts = player_posts_data.posts[username]
	if index >= 0 and index < posts.size():
		posts.remove_at(index)
	save_player_posts()

func clear_all_player_posts():
	"""Clear all player post data (called on map wipe)."""
	player_posts_data = {"posts": {}}
	save_player_posts()

# ===== SIGNPOST TEXTS (v0.9.507) =====

func load_signpost_texts():
	"""Load signpost text data."""
	var data = _safe_load(SIGNPOST_TEXTS_FILE)
	if data.is_empty():
		signpost_texts_data = {"signposts": {}}
	else:
		signpost_texts_data = data
	if not signpost_texts_data.has("signposts"):
		signpost_texts_data["signposts"] = {}

func save_signpost_texts():
	"""Save signpost text data."""
	_safe_save(SIGNPOST_TEXTS_FILE, signpost_texts_data)

func _signpost_key(x: int, y: int) -> String:
	return "%d_%d" % [x, y]

func get_signpost_text(x: int, y: int) -> Dictionary:
	"""Get the signpost entry at world coord. Returns {} if not set."""
	if not signpost_texts_data.has("signposts"):
		return {}
	var key = _signpost_key(x, y)
	return signpost_texts_data.signposts.get(key, {})

func set_signpost_text(x: int, y: int, text: String, owner_username: String):
	"""Store signpost text at world coord. Truncates text to SIGNPOST_TEXT_MAX."""
	if not signpost_texts_data.has("signposts"):
		signpost_texts_data["signposts"] = {}
	var clean = text.strip_edges().substr(0, SIGNPOST_TEXT_MAX)
	var key = _signpost_key(x, y)
	signpost_texts_data.signposts[key] = {
		"text": clean,
		"owner_username": owner_username,
		"set_at": Time.get_unix_time_from_system()
	}
	save_signpost_texts()

func remove_signpost_text(x: int, y: int):
	"""Remove signpost text (called when signpost is demolished)."""
	if not signpost_texts_data.has("signposts"):
		return
	var key = _signpost_key(x, y)
	if signpost_texts_data.signposts.has(key):
		signpost_texts_data.signposts.erase(key)
		save_signpost_texts()

func clear_all_signpost_texts():
	"""Clear all signpost text data (called on map wipe)."""
	signpost_texts_data = {"signposts": {}}
	save_signpost_texts()

# ===== VALOR (Account-Level Currency) =====

func get_valor(account_id: String) -> int:
	"""Get valor balance for an account."""
	var house = get_house(account_id)
	return house.get("valor", 0)

func add_valor(account_id: String, amount: int):
	"""Add valor to an account. Also increments total_valor_earned."""
	var house = get_house(account_id)
	house["valor"] = house.get("valor", 0) + amount
	house["total_valor_earned"] = house.get("total_valor_earned", 0) + amount
	save_house(account_id, house)

func spend_valor(account_id: String, amount: int) -> bool:
	"""Spend valor from an account. Returns false if insufficient."""
	var house = get_house(account_id)
	if house.get("valor", 0) < amount:
		return false
	house["valor"] = house.get("valor", 0) - amount
	save_house(account_id, house)
	return true

func set_valor(account_id: String, amount: int):
	"""Set valor to a specific amount (admin use)."""
	var house = get_house(account_id)
	house["valor"] = amount
	save_house(account_id, house)

func clear_all_valor():
	"""Reset all house valor to 0 (used during full wipe)."""
	var houses = _safe_load(HOUSES_FILE)
	for account_id in houses:
		if houses[account_id] is Dictionary:
			houses[account_id]["valor"] = 0
	_safe_save(HOUSES_FILE, houses)

# ===== OPEN MARKET DATA =====

func load_market_data():
	"""Load market data from file."""
	var data = _safe_load(MARKET_FILE)
	if data.is_empty():
		market_data = {"listings": {}, "orders": {}, "next_id": 1, "next_order_id": 1}
		save_market_data()
	else:
		market_data = data
		if not market_data.has("next_id"):
			market_data["next_id"] = 1
		# Audit #9 Slice 2 — backfill buy-order fields for pre-existing market files.
		if not market_data.has("orders"):
			market_data["orders"] = {}
		if not market_data.has("next_order_id"):
			market_data["next_order_id"] = 1

func save_market_data():
	"""Save market data to file."""
	_safe_save(MARKET_FILE, market_data)

func get_market_listings(post_id: String) -> Array:
	"""Get all listings at a specific post."""
	if not market_data.has("listings"):
		market_data["listings"] = {}
	return market_data.listings.get(post_id, [])

func add_market_listing(post_id: String, listing: Dictionary) -> String:
	"""Add a listing to a post. Merges with existing same-seller same-item listing if possible. Returns listing_id."""
	if not market_data.has("listings"):
		market_data["listings"] = {}
	if not market_data.listings.has(post_id):
		market_data.listings[post_id] = []

	# Try to merge with existing listing from same seller + same item (non-unique only)
	var seller = listing.get("seller_name", "")
	var item_name = listing.get("item", {}).get("name", "")
	var supply_cat = listing.get("supply_category", "")
	var is_unique = supply_cat in ["equipment", "egg"]

	if not is_unique and seller != "" and item_name != "":
		for existing in market_data.listings[post_id]:
			if existing.get("seller_name", "") == seller and \
			   existing.get("item", {}).get("name", "") == item_name:
				existing["quantity"] = int(existing.get("quantity", 1)) + int(listing.get("quantity", 1))
				existing["base_valor"] = int(existing.get("base_valor", 0)) + int(listing.get("base_valor", 0))
				save_market_data()
				return existing.get("listing_id", "")

	var listing_id = "mkt_%d" % int(market_data.get("next_id", 1))
	listing["listing_id"] = listing_id
	market_data["next_id"] = int(market_data.get("next_id", 1)) + 1
	market_data.listings[post_id].append(listing)
	save_market_data()
	return listing_id

func remove_market_listing(post_id: String, listing_id: String) -> Dictionary:
	"""Remove a listing by ID. Returns the removed listing or empty dict."""
	if not market_data.has("listings"):
		return {}
	if not market_data.listings.has(post_id):
		return {}

	var listings = market_data.listings[post_id]
	for i in range(listings.size()):
		if listings[i].get("listing_id", "") == listing_id:
			var removed = listings[i]
			listings.remove_at(i)
			save_market_data()
			return removed
	return {}

func update_market_listing_quantity(post_id: String, listing_id: String, new_qty: int, new_base_valor: int):
	"""Update a listing's quantity and base valor after a partial purchase."""
	if not market_data.has("listings") or not market_data.listings.has(post_id):
		return
	for listing in market_data.listings[post_id]:
		if listing.get("listing_id", "") == listing_id:
			listing["quantity"] = new_qty
			listing["base_valor"] = new_base_valor
			save_market_data()
			return

func get_all_listings_by_account(account_id: String) -> Array:
	"""Get all listings across all posts for an account (for 'My Listings')."""
	var result = []
	if not market_data.has("listings"):
		return result
	for post_id in market_data.listings.keys():
		for listing in market_data.listings[post_id]:
			if listing.get("account_id", "") == account_id:
				var entry = listing.duplicate()
				entry["post_id"] = post_id
				result.append(entry)
	return result

func get_all_market_listings_with_post() -> Array:
	# Audit #9 Slice 1 — flat list of every market listing across every post,
	# annotated with post_id. Server pairs with TRADING_POSTS lookup to add
	# display name + center, and applies per-post markup.
	var result = []
	if not market_data.has("listings"):
		return result
	for post_id in market_data.listings.keys():
		for listing in market_data.listings[post_id]:
			var entry = listing.duplicate()
			entry["post_id"] = post_id
			result.append(entry)
	return result

func get_supply_count(post_id: String, category: String) -> int:
	"""Count listings in a supply category at a post."""
	var listings = get_market_listings(post_id)
	var count = 0
	for listing in listings:
		if listing.get("supply_category", "") == category:
			count += 1
	return count

func calculate_markup(post_id: String, category: String) -> float:
	"""Calculate dynamic markup based on local supply. 1.15x (abundant) to 1.50x (scarce)."""
	var count = get_supply_count(post_id, category)
	if count >= 20:
		return 1.15
	if count <= 2:
		return 1.50
	# Linear interpolation between 1.50x and 1.15x
	var ratio = float(count - 2) / 18.0
	return 1.50 - (ratio * 0.35)

func clear_all_market_data():
	"""Clear all market data (for wipes)."""
	market_data = {"listings": {}, "orders": {}, "next_id": 1, "next_order_id": 1}
	save_market_data()

# ===== CLANS (Audit #14 Slice 1) =====
# Each clan: {clan_id, name, tag, leader_account_id, member_ids[], created_at}.
# Names + tags are case-insensitive-unique. Leader leaves → clan disbands
# (members get clan_id reset). Future slices: officer ranks, storage, posts,
# wars. This slice ships create/leave/info only.

func load_clans():
	"""Load clans data from file."""
	var data = _safe_load(CLANS_FILE)
	if data.is_empty():
		clans_data = {"clans": {}, "next_clan_id": 1, "invitations": {}}
		save_clans()
	else:
		clans_data = data
		if not clans_data.has("clans"):
			clans_data["clans"] = {}
		if not clans_data.has("next_clan_id"):
			clans_data["next_clan_id"] = 1
		if not clans_data.has("invitations"):
			clans_data["invitations"] = {}

func save_clans():
	"""Save clans data to file."""
	_safe_save(CLANS_FILE, clans_data)

func get_clan(clan_id: String) -> Dictionary:
	"""Return clan dict by id, or {} if missing."""
	if clan_id == "":
		return {}
	return clans_data.get("clans", {}).get(clan_id, {})

func get_account_clan_id(account_id: String) -> String:
	"""Return the clan_id this account belongs to, or "" if unaffiliated."""
	var account = accounts_data.get("accounts", {}).get(account_id, {})
	return String(account.get("clan_id", ""))

func get_clan_by_account(account_id: String) -> Dictionary:
	"""Return the clan dict the account belongs to, or {} if unaffiliated."""
	var clan_id = get_account_clan_id(account_id)
	return get_clan(clan_id)

func get_clan_by_username(username: String) -> Dictionary:
	"""Audit #14 v0.9.518 — Lookup clan by account username (case-insensitive).
	Used by player-post panels where the owner is identified by username (not
	a live peer/account_id). Returns {} if no account / no clan."""
	if username == "":
		return {}
	var username_lower = username.to_lower()
	var account_id = accounts_data.get("username_to_id", {}).get(username_lower, "")
	if account_id == "":
		return {}
	return get_clan_by_account(account_id)

func _normalize_clan_key(text: String) -> String:
	return text.strip_edges().to_lower()

func find_clan_by_name(name: String) -> String:
	"""Case-insensitive name lookup → clan_id or ""."""
	var key = _normalize_clan_key(name)
	for clan_id in clans_data.get("clans", {}):
		var clan = clans_data["clans"][clan_id]
		if _normalize_clan_key(String(clan.get("name", ""))) == key:
			return String(clan_id)
	return ""

func find_clan_by_tag(tag: String) -> String:
	"""Case-insensitive tag lookup → clan_id or ""."""
	var key = _normalize_clan_key(tag)
	for clan_id in clans_data.get("clans", {}):
		var clan = clans_data["clans"][clan_id]
		if _normalize_clan_key(String(clan.get("tag", ""))) == key:
			return String(clan_id)
	return ""

func create_clan(leader_account_id: String, name: String, tag: String) -> Dictionary:
	"""Create a new clan led by the named account. Validates length, unique
	name/tag, and that the leader isn't already in a clan. Returns
	{success, clan_id, clan, reason} where `reason` is set on failure."""
	if get_account_clan_id(leader_account_id) != "":
		return {"success": false, "reason": "Already in a clan — leave first."}
	var nm = name.strip_edges()
	var tg = tag.strip_edges()
	if nm.length() < CLAN_NAME_MIN or nm.length() > CLAN_NAME_MAX:
		return {"success": false, "reason": "Clan name must be %d-%d characters." % [CLAN_NAME_MIN, CLAN_NAME_MAX]}
	if tg.length() < CLAN_TAG_MIN or tg.length() > CLAN_TAG_MAX:
		return {"success": false, "reason": "Clan tag must be %d-%d characters." % [CLAN_TAG_MIN, CLAN_TAG_MAX]}
	# Restrict to alphanumeric + space for names; alphanumeric only for tags.
	var name_re = RegEx.new()
	name_re.compile("^[a-zA-Z0-9 ]+$")
	if not name_re.search(nm):
		return {"success": false, "reason": "Clan name: letters / numbers / spaces only."}
	var tag_re = RegEx.new()
	tag_re.compile("^[a-zA-Z0-9]+$")
	if not tag_re.search(tg):
		return {"success": false, "reason": "Clan tag: letters / numbers only."}
	if find_clan_by_name(nm) != "":
		return {"success": false, "reason": "A clan with that name already exists."}
	if find_clan_by_tag(tg) != "":
		return {"success": false, "reason": "A clan with that tag already exists."}

	var clan_id = "clan_%d" % int(clans_data.get("next_clan_id", 1))
	clans_data["next_clan_id"] = int(clans_data.get("next_clan_id", 1)) + 1
	clans_data["clans"][clan_id] = {
		"clan_id": clan_id,
		"name": nm,
		"tag": tg,
		"leader_account_id": leader_account_id,
		"member_ids": [leader_account_id],
		# Audit #14 Slice 4 — officer rank. Officers can invite + kick regular
		# members but cannot kick each other or the leader and cannot promote.
		# Leader is implicitly above all officers (NOT in this list).
		"officer_ids": [],
		# Audit #14 Slice 5 (v0.9.446) — Clan Vault. Shared item storage owned
		# by the clan. Any member can deposit/withdraw; capacity capped at
		# CLAN_VAULT_CAPACITY. Items are full item dicts (same shape as
		# inventory entries: type, name, etc.).
		"storage": [],
		# Audit #14 Slice 7 — clan identity polish. Description is a leader-set
		# public blurb (max 240 chars, basic charset). Empty by default; legacy
		# clans read it as "" via .get(... , "").
		"description": "",
		# Audit #14 Slice 8 — banner color used to render the [TAG] marker in
		# chat / whispers / player list / clan panel. Defaults to the legacy
		# purple (#A335EE) so existing chat surfaces don't change.
		"banner_color": CLAN_DEFAULT_BANNER_COLOR,
		"created_at": int(Time.get_unix_time_from_system()),
	}
	accounts_data["accounts"][leader_account_id]["clan_id"] = clan_id
	save_clans()
	save_accounts()
	return {"success": true, "clan_id": clan_id, "clan": clans_data["clans"][clan_id]}

# Audit #14 Slice 7 — leader-only clan description setter.
const CLAN_DESCRIPTION_MAX: int = 240
# Audit #14 Slice 8 — leader-set banner color for the [TAG] marker.
const CLAN_DEFAULT_BANNER_COLOR: String = "#A335EE"

func set_clan_description(account_id: String, text: String) -> Dictionary:
	"""Leader-only. Sets clans_data.clans[clan_id].description after basic
	validation. Empty string clears the description. Returns
	{success, reason, description}."""
	var clan_id = get_account_clan_id(account_id)
	if clan_id == "":
		return {"success": false, "reason": "You are not in a clan."}
	var clan = clans_data.get("clans", {}).get(clan_id, {})
	if clan.is_empty():
		return {"success": false, "reason": "Clan not found."}
	if String(clan.get("leader_account_id", "")) != account_id:
		return {"success": false, "reason": "Only the clan leader can set the description."}
	var trimmed = text.strip_edges()
	if trimmed.length() > CLAN_DESCRIPTION_MAX:
		return {"success": false, "reason": "Description max %d characters (got %d)." % [CLAN_DESCRIPTION_MAX, trimmed.length()]}
	# Allow letters/digits/spaces and common punctuation; reject control chars
	# and BBCode brackets (which would let a leader inject formatting into other
	# players' clan view).
	var bad_re = RegEx.new()
	bad_re.compile("[\\[\\]<>]")
	if bad_re.search(trimmed) != null:
		return {"success": false, "reason": "Description cannot contain [ ] < or > characters."}
	clans_data["clans"][clan_id]["description"] = trimmed
	save_clans()
	return {"success": true, "description": trimmed}

func mark_sanctuary_hint_seen(account_id: String) -> bool:
	"""Audit #3 Slice 6 — flip the account-level flag so the Sanctuary
	tutorial overlay only fires once. Returns true if the flag was newly
	set (i.e., should fire), false if already seen or no house."""
	if not houses_data.has("houses") or not houses_data["houses"].has(account_id):
		return false
	if bool(houses_data["houses"][account_id].get("seen_sanctuary_hint", false)):
		return false
	houses_data["houses"][account_id]["seen_sanctuary_hint"] = true
	save_houses()
	return true

func set_clan_motto(account_id: String, text: String) -> Dictionary:
	"""Audit #14 v0.9.510 — leader-only clan motto setter. Short tagline (max
	50 chars) shown on the clan panel below the description. Empty string
	clears. Same charset rules as description (no BBCode brackets to prevent
	injection)."""
	var clan_id = get_account_clan_id(account_id)
	if clan_id == "":
		return {"success": false, "reason": "You are not in a clan."}
	var clan = clans_data.get("clans", {}).get(clan_id, {})
	if clan.is_empty():
		return {"success": false, "reason": "Clan not found."}
	if String(clan.get("leader_account_id", "")) != account_id:
		return {"success": false, "reason": "Only the clan leader can set the motto."}
	var trimmed = text.strip_edges()
	if trimmed.length() > CLAN_MOTTO_MAX:
		return {"success": false, "reason": "Motto max %d characters (got %d)." % [CLAN_MOTTO_MAX, trimmed.length()]}
	var bad_re = RegEx.new()
	bad_re.compile("[\\[\\]<>]")
	if bad_re.search(trimmed) != null:
		return {"success": false, "reason": "Motto cannot contain [ ] < or > characters."}
	clans_data["clans"][clan_id]["motto"] = trimmed
	save_clans()
	return {"success": true, "motto": trimmed}

func set_clan_banner_color(account_id: String, hex_color: String) -> Dictionary:
	"""Audit #14 Slice 8 — leader-only banner color setter. Validates
	`#RRGGBB` hex format. Returns {success, reason, banner_color}."""
	var clan_id = get_account_clan_id(account_id)
	if clan_id == "":
		return {"success": false, "reason": "You are not in a clan."}
	var clan = clans_data.get("clans", {}).get(clan_id, {})
	if clan.is_empty():
		return {"success": false, "reason": "Clan not found."}
	if String(clan.get("leader_account_id", "")) != account_id:
		return {"success": false, "reason": "Only the clan leader can set the banner color."}
	var trimmed = hex_color.strip_edges()
	# Accept #RRGGBB only — case-insensitive.
	var hex_re = RegEx.new()
	hex_re.compile("^#[0-9A-Fa-f]{6}$")
	if hex_re.search(trimmed) == null:
		return {"success": false, "reason": "Banner color must be a #RRGGBB hex code (e.g., #FFD700)."}
	# Normalize to uppercase for consistency.
	trimmed = "#" + trimmed.substr(1).to_upper()
	clans_data["clans"][clan_id]["banner_color"] = trimmed
	save_clans()
	return {"success": true, "banner_color": trimmed}

func leave_clan(account_id: String) -> Dictionary:
	"""Remove account from its clan. If account is the leader, the clan is
	disbanded (all members reset to clan_id ""). Returns {success, disbanded,
	clan_name, reason}."""
	var clan_id = get_account_clan_id(account_id)
	if clan_id == "":
		return {"success": false, "reason": "You're not in a clan."}
	if not clans_data.get("clans", {}).has(clan_id):
		# Stale account state — clean up.
		accounts_data["accounts"][account_id]["clan_id"] = ""
		save_accounts()
		return {"success": true, "disbanded": false, "clan_name": ""}
	var clan = clans_data["clans"][clan_id]
	var clan_name = String(clan.get("name", ""))
	var was_leader = (String(clan.get("leader_account_id", "")) == account_id)
	if was_leader:
		# Disband — reset every member's clan_id and remove the clan record.
		for member_id in clan.get("member_ids", []):
			if accounts_data["accounts"].has(member_id):
				accounts_data["accounts"][member_id]["clan_id"] = ""
		clans_data["clans"].erase(clan_id)
		# Drop pending invites referencing this clan (Audit #14 Slice 2).
		var inv_map: Dictionary = clans_data.get("invitations", {})
		for target_id in inv_map.keys():
			_remove_invite_record(target_id, clan_id)
		save_clans()
		save_accounts()
		return {"success": true, "disbanded": true, "clan_name": clan_name}
	# Regular member — just remove from roster.
	var members: Array = clan.get("member_ids", [])
	members.erase(account_id)
	clan["member_ids"] = members
	# Audit #14 Slice 4 — officer-rank members lose their rank on leaving.
	if clan.has("officer_ids") and typeof(clan.officer_ids) == TYPE_ARRAY:
		var officers: Array = clan["officer_ids"]
		if officers.has(account_id):
			officers.erase(account_id)
			clan["officer_ids"] = officers
	accounts_data["accounts"][account_id]["clan_id"] = ""
	save_clans()
	save_accounts()
	return {"success": true, "disbanded": false, "clan_name": clan_name}

func get_clan_member_summary(clan_id: String) -> Array:
	"""Return a list of {account_id, username, is_leader, is_officer, rank} for
	each member of the clan, in roster order. Used by the visual panel."""
	var clan = get_clan(clan_id)
	if clan.is_empty():
		return []
	var leader_id = String(clan.get("leader_account_id", ""))
	# Audit #14 Slice 4 — officer list. Legacy clans (Slice 1-3) may lack it.
	var officers: Array = clan.get("officer_ids", [])
	var out: Array = []
	for member_id in clan.get("member_ids", []):
		var member_account = accounts_data.get("accounts", {}).get(member_id, {})
		var is_leader = member_id == leader_id
		var is_officer = officers.has(member_id)
		var rank: String = "leader" if is_leader else ("officer" if is_officer else "member")
		out.append({
			"account_id": member_id,
			"username": String(member_account.get("username", "(unknown)")),
			"is_leader": is_leader,
			"is_officer": is_officer,
			"rank": rank,
		})
	return out

# ===== CLAN VAULT HELPERS (Audit #14 Slice 5) =====
# Shared item storage owned by the clan. Any clan member can deposit / withdraw.
# Items are full item dicts (mirroring inventory entries). Capacity is a hard
# cap; deposits beyond it are rejected. Withdrawals shift the array in place.
# v0.9.446 — chat-command MVP; no UI yet.

const CLAN_VAULT_CAPACITY: int = 30

func get_clan_storage(clan_id: String) -> Array:
	"""Return a duplicate of the clan's storage array. Empty if the clan
	doesn't exist or its storage field is missing/legacy."""
	var clan = get_clan(clan_id)
	if clan.is_empty():
		return []
	var raw = clan.get("storage", [])
	if typeof(raw) != TYPE_ARRAY:
		return []
	return raw.duplicate(true)

func clan_storage_count(clan_id: String) -> int:
	"""Cheap count helper for capacity checks."""
	var clan = get_clan(clan_id)
	if clan.is_empty():
		return 0
	var raw = clan.get("storage", [])
	if typeof(raw) != TYPE_ARRAY:
		return 0
	return raw.size()

func clan_deposit_item(clan_id: String, item: Dictionary) -> Dictionary:
	"""Append an item to the clan vault. Returns {success, reason?, vault_size}."""
	if clan_id == "":
		return {"success": false, "reason": "Not in a clan."}
	if not clans_data.get("clans", {}).has(clan_id):
		return {"success": false, "reason": "Clan not found."}
	if item == null or item.is_empty():
		return {"success": false, "reason": "Empty item."}
	var clan: Dictionary = clans_data["clans"][clan_id]
	# Legacy clans created pre-Slice 5 won't have the storage field.
	if not clan.has("storage") or typeof(clan.storage) != TYPE_ARRAY:
		clan["storage"] = []
	if clan.storage.size() >= CLAN_VAULT_CAPACITY:
		return {"success": false, "reason": "Vault full (%d/%d)." % [clan.storage.size(), CLAN_VAULT_CAPACITY]}
	clan.storage.append(item.duplicate(true))
	save_clans()
	return {"success": true, "vault_size": clan.storage.size()}

func clan_withdraw_item(clan_id: String, vault_index: int) -> Dictionary:
	"""Remove + return the item at `vault_index`. Returns {success, item?, reason?}."""
	if clan_id == "":
		return {"success": false, "reason": "Not in a clan."}
	if not clans_data.get("clans", {}).has(clan_id):
		return {"success": false, "reason": "Clan not found."}
	var clan: Dictionary = clans_data["clans"][clan_id]
	if not clan.has("storage") or typeof(clan.storage) != TYPE_ARRAY:
		return {"success": false, "reason": "Vault is empty."}
	if vault_index < 0 or vault_index >= clan.storage.size():
		return {"success": false, "reason": "Invalid vault slot."}
	var taken: Dictionary = clan.storage[vault_index]
	clan.storage.remove_at(vault_index)
	save_clans()
	return {"success": true, "item": taken}


# ===== CLAN RANK HELPERS (Audit #14 Slice 4) =====

func is_clan_leader(account_id: String) -> bool:
	"""True if account is the leader of their current clan."""
	var clan_id = get_account_clan_id(account_id)
	if clan_id == "":
		return false
	var clan = get_clan(clan_id)
	return String(clan.get("leader_account_id", "")) == account_id

func is_clan_officer(account_id: String) -> bool:
	"""True if account is in their clan's officer_ids list. Leader is NOT an
	officer for this check — use is_clan_leader_or_officer when the call site
	wants either rank."""
	var clan_id = get_account_clan_id(account_id)
	if clan_id == "":
		return false
	var clan = get_clan(clan_id)
	var officers: Array = clan.get("officer_ids", [])
	return officers.has(account_id)

func is_clan_leader_or_officer(account_id: String) -> bool:
	"""Convenience: either rank passes the permission check (e.g., invite)."""
	return is_clan_leader(account_id) or is_clan_officer(account_id)

func promote_to_officer(leader_account_id: String, target_account_id: String) -> Dictionary:
	"""Leader-only promote a member to officer. Validates same clan, target is
	not already officer/leader. Returns {success, reason, clan_id, target_username}."""
	if leader_account_id == "" or target_account_id == "":
		return {"success": false, "reason": "Invalid account."}
	if leader_account_id == target_account_id:
		return {"success": false, "reason": "You're already the leader."}
	var clan_id = get_account_clan_id(leader_account_id)
	if clan_id == "":
		return {"success": false, "reason": "You're not in a clan."}
	var clan: Dictionary = clans_data.get("clans", {}).get(clan_id, {})
	if clan.is_empty():
		return {"success": false, "reason": "Clan no longer exists."}
	if String(clan.get("leader_account_id", "")) != leader_account_id:
		return {"success": false, "reason": "Only the clan leader can promote."}
	var members: Array = clan.get("member_ids", [])
	if not members.has(target_account_id):
		return {"success": false, "reason": "That player is not in your clan."}
	if not clan.has("officer_ids") or typeof(clan.officer_ids) != TYPE_ARRAY:
		clan["officer_ids"] = []
	var officers: Array = clan["officer_ids"]
	if officers.has(target_account_id):
		return {"success": false, "reason": "That player is already an officer."}
	officers.append(target_account_id)
	clan["officer_ids"] = officers
	save_clans()
	var target_username: String = String(accounts_data.get("accounts", {}).get(target_account_id, {}).get("username", "(unknown)"))
	return {"success": true, "clan_id": clan_id, "target_username": target_username, "target_account_id": target_account_id}

func demote_from_officer(leader_account_id: String, target_account_id: String) -> Dictionary:
	"""Leader-only demote an officer back to regular member."""
	if leader_account_id == "" or target_account_id == "":
		return {"success": false, "reason": "Invalid account."}
	var clan_id = get_account_clan_id(leader_account_id)
	if clan_id == "":
		return {"success": false, "reason": "You're not in a clan."}
	var clan: Dictionary = clans_data.get("clans", {}).get(clan_id, {})
	if clan.is_empty():
		return {"success": false, "reason": "Clan no longer exists."}
	if String(clan.get("leader_account_id", "")) != leader_account_id:
		return {"success": false, "reason": "Only the clan leader can demote."}
	var officers: Array = clan.get("officer_ids", [])
	if not officers.has(target_account_id):
		return {"success": false, "reason": "That player is not an officer."}
	officers.erase(target_account_id)
	clan["officer_ids"] = officers
	save_clans()
	var target_username: String = String(accounts_data.get("accounts", {}).get(target_account_id, {}).get("username", "(unknown)"))
	return {"success": true, "clan_id": clan_id, "target_username": target_username, "target_account_id": target_account_id}

func kick_from_clan(actor_account_id: String, target_account_id: String) -> Dictionary:
	"""Leader or officer kicks a member from the clan. Rules:
	  - Leader can kick anyone except self.
	  - Officer can kick non-officer non-leader members only.
	  - You cannot kick yourself (use leave_clan).
	Returns {success, reason, clan_id, clan_name, target_username, target_account_id, was_officer}."""
	if actor_account_id == "" or target_account_id == "":
		return {"success": false, "reason": "Invalid account."}
	if actor_account_id == target_account_id:
		return {"success": false, "reason": "You can't kick yourself — leave instead."}
	var clan_id = get_account_clan_id(actor_account_id)
	if clan_id == "":
		return {"success": false, "reason": "You're not in a clan."}
	if get_account_clan_id(target_account_id) != clan_id:
		return {"success": false, "reason": "That player is not in your clan."}
	var clan: Dictionary = clans_data.get("clans", {}).get(clan_id, {})
	if clan.is_empty():
		return {"success": false, "reason": "Clan no longer exists."}
	var leader_id: String = String(clan.get("leader_account_id", ""))
	var officers: Array = clan.get("officer_ids", [])
	var actor_is_leader: bool = leader_id == actor_account_id
	var actor_is_officer: bool = officers.has(actor_account_id)
	if not actor_is_leader and not actor_is_officer:
		return {"success": false, "reason": "Only the leader and officers can kick."}
	if target_account_id == leader_id:
		return {"success": false, "reason": "You can't kick the leader."}
	# Officers can only kick regular members.
	var target_is_officer: bool = officers.has(target_account_id)
	if not actor_is_leader and target_is_officer:
		return {"success": false, "reason": "Officers can't kick other officers — the leader has to demote them first."}
	# Apply the kick.
	var members: Array = clan.get("member_ids", [])
	members.erase(target_account_id)
	clan["member_ids"] = members
	if target_is_officer:
		officers.erase(target_account_id)
		clan["officer_ids"] = officers
	if accounts_data.get("accounts", {}).has(target_account_id):
		accounts_data["accounts"][target_account_id]["clan_id"] = ""
	save_clans()
	save_accounts()
	var target_username: String = String(accounts_data.get("accounts", {}).get(target_account_id, {}).get("username", "(unknown)"))
	return {
		"success": true,
		"clan_id": clan_id,
		"clan_name": String(clan.get("name", "")),
		"target_username": target_username,
		"target_account_id": target_account_id,
		"was_officer": target_is_officer,
	}

# ===== CLAN INVITATIONS (Audit #14 Slice 2) =====
# Stored as clans_data.invitations[target_account_id] = [
#   {clan_id, inviter_account_id, inviter_username, created_at},
#   ...
# ]
# Slice 2 keeps invites per-clan (target may receive invites from many clans).
# Invites for a clan are pruned when the target joins any clan, when they
# decline, or when the inviting clan is disbanded.

func find_account_id_by_username(username: String) -> String:
	"""Lookup account_id by username (case-sensitive match against stored
	username). Returns "" if not found. Used to resolve invite targets."""
	if username == "":
		return ""
	for account_id in accounts_data.get("accounts", {}):
		var acc = accounts_data["accounts"][account_id]
		if String(acc.get("username", "")) == username:
			return account_id
	return ""

func get_clan_invitations(account_id: String) -> Array:
	"""Return list of pending invitations for the account. Each entry has
	clan_id + clan name/tag + inviter_username + created_at."""
	if account_id == "":
		return []
	var raw: Array = clans_data.get("invitations", {}).get(account_id, [])
	var out: Array = []
	for invite_var in raw:
		if not (invite_var is Dictionary):
			continue
		var invite: Dictionary = invite_var
		var clan_id = String(invite.get("clan_id", ""))
		var clan = get_clan(clan_id)
		if clan.is_empty():
			# Stale invite — clan disbanded. Skip rendering; pruned on next write.
			continue
		out.append({
			"clan_id": clan_id,
			"clan_name": String(clan.get("name", "")),
			"clan_tag": String(clan.get("tag", "")),
			"inviter_account_id": String(invite.get("inviter_account_id", "")),
			"inviter_username": String(invite.get("inviter_username", "")),
			"created_at": int(invite.get("created_at", 0)),
		})
	return out

func _prune_stale_invitations_for(account_id: String) -> void:
	"""Drop invitations referencing disbanded clans. Called opportunistically."""
	if not clans_data.get("invitations", {}).has(account_id):
		return
	var raw: Array = clans_data["invitations"][account_id]
	var kept: Array = []
	for invite_var in raw:
		if not (invite_var is Dictionary):
			continue
		var invite: Dictionary = invite_var
		if get_clan(String(invite.get("clan_id", ""))).is_empty():
			continue
		kept.append(invite)
	if kept.is_empty():
		clans_data["invitations"].erase(account_id)
	else:
		clans_data["invitations"][account_id] = kept

func add_clan_invitation(target_account_id: String, clan_id: String, inviter_account_id: String) -> Dictionary:
	"""Add an invitation. Validates target not in clan, clan exists + has seats,
	no duplicate invite from same clan. Returns {success, reason, target_username,
	inviter_username, clan_name, clan_tag}."""
	if target_account_id == "" or target_account_id == inviter_account_id:
		return {"success": false, "reason": "Invalid invitation target."}
	var clan = get_clan(clan_id)
	if clan.is_empty():
		return {"success": false, "reason": "Clan no longer exists."}
	if not accounts_data.get("accounts", {}).has(target_account_id):
		return {"success": false, "reason": "Player not found."}
	if get_account_clan_id(target_account_id) != "":
		return {"success": false, "reason": "Player is already in a clan."}
	var members: Array = clan.get("member_ids", [])
	if members.size() >= CLAN_MAX_MEMBERS:
		return {"success": false, "reason": "Clan is full (%d/%d)." % [members.size(), CLAN_MAX_MEMBERS]}
	# Prune stale + check for duplicate invite from same clan
	_prune_stale_invitations_for(target_account_id)
	var inv_list: Array = clans_data.get("invitations", {}).get(target_account_id, [])
	for invite_var in inv_list:
		if not (invite_var is Dictionary):
			continue
		var invite: Dictionary = invite_var
		if String(invite.get("clan_id", "")) == clan_id:
			return {"success": false, "reason": "That player already has a pending invite from this clan."}
	# Resolve usernames for the notification payload
	var inviter_acc = accounts_data["accounts"].get(inviter_account_id, {})
	var target_acc = accounts_data["accounts"].get(target_account_id, {})
	var inviter_username = String(inviter_acc.get("username", ""))
	var target_username = String(target_acc.get("username", ""))
	# Store
	var new_invite = {
		"clan_id": clan_id,
		"inviter_account_id": inviter_account_id,
		"inviter_username": inviter_username,
		"created_at": int(Time.get_unix_time_from_system()),
	}
	if not clans_data.has("invitations"):
		clans_data["invitations"] = {}
	if not clans_data["invitations"].has(target_account_id):
		clans_data["invitations"][target_account_id] = []
	clans_data["invitations"][target_account_id].append(new_invite)
	save_clans()
	return {
		"success": true,
		"target_account_id": target_account_id,
		"target_username": target_username,
		"inviter_username": inviter_username,
		"clan_id": clan_id,
		"clan_name": String(clan.get("name", "")),
		"clan_tag": String(clan.get("tag", "")),
	}

func _remove_invite_record(target_account_id: String, clan_id: String) -> bool:
	"""Drop a specific clan invite for target. Returns true if removed."""
	if not clans_data.get("invitations", {}).has(target_account_id):
		return false
	var inv_list: Array = clans_data["invitations"][target_account_id]
	for i in range(inv_list.size()):
		if not (inv_list[i] is Dictionary):
			continue
		if String(inv_list[i].get("clan_id", "")) == clan_id:
			inv_list.remove_at(i)
			if inv_list.is_empty():
				clans_data["invitations"].erase(target_account_id)
			else:
				clans_data["invitations"][target_account_id] = inv_list
			return true
	return false

func decline_clan_invitation(account_id: String, clan_id: String) -> Dictionary:
	"""Player rejects an invite. Just drops the record."""
	var clan = get_clan(clan_id)
	var clan_name = String(clan.get("name", "(disbanded)"))
	var clan_tag = String(clan.get("tag", ""))
	var removed = _remove_invite_record(account_id, clan_id)
	if removed:
		save_clans()
		return {"success": true, "clan_name": clan_name, "clan_tag": clan_tag}
	return {"success": false, "reason": "Invitation not found."}

func accept_clan_invitation(account_id: String, clan_id: String) -> Dictionary:
	"""Player accepts an invite. Adds to clan members, clears every pending
	invite for this account (joining one clan voids all others), persists.
	Returns {success, clan, reason}."""
	if get_account_clan_id(account_id) != "":
		return {"success": false, "reason": "You're already in a clan."}
	var clan = get_clan(clan_id)
	if clan.is_empty():
		# Stale — clean up any reference and report failure
		_remove_invite_record(account_id, clan_id)
		save_clans()
		return {"success": false, "reason": "Clan no longer exists."}
	# Verify the invite still exists
	var inv_list: Array = clans_data.get("invitations", {}).get(account_id, [])
	var has_invite = false
	for invite_var in inv_list:
		if invite_var is Dictionary and String(invite_var.get("clan_id", "")) == clan_id:
			has_invite = true
			break
	if not has_invite:
		return {"success": false, "reason": "No invitation from that clan."}
	# Check seats again (someone may have joined since the invite)
	var members: Array = clan.get("member_ids", [])
	if members.size() >= CLAN_MAX_MEMBERS:
		return {"success": false, "reason": "Clan is full (%d/%d)." % [members.size(), CLAN_MAX_MEMBERS]}
	# Join
	members.append(account_id)
	clan["member_ids"] = members
	accounts_data["accounts"][account_id]["clan_id"] = clan_id
	# Drop ALL pending invitations for this account — they're moot now.
	if clans_data.get("invitations", {}).has(account_id):
		clans_data["invitations"].erase(account_id)
	save_clans()
	save_accounts()
	return {
		"success": true,
		"clan_id": clan_id,
		"clan_name": String(clan.get("name", "")),
		"clan_tag": String(clan.get("tag", "")),
	}

# ===== BUY ORDERS (Audit #9 Slice 2) =====
# Demand-side mirror of listings. Buyer escrows Valor at creation; sellers
# fulfill from inventory or crafting_materials and receive the per-unit Valor.
# Server takes no spread on orders — incentivizes filling demand.
# Orders are stored at market_data.orders[post_id] = [order, order, ...].
# Each order:
#   order_id, account_id (buyer), buyer_name,
#   item_type (material|consumable|rune|monster_part),
#   item_name (display + match key, case-sensitive),
#   supply_category (material_t<N> | consumable | rune | monster_part — for filter parity),
#   per_unit_valor (int),
#   quantity_wanted (int), quantity_filled (int),  # remaining = wanted - filled
#   listed_at (unix_t)

func get_market_orders(post_id: String) -> Array:
	"""Get all open buy orders at a specific post."""
	if not market_data.has("orders"):
		market_data["orders"] = {}
	return market_data.orders.get(post_id, [])

func add_market_order(post_id: String, order: Dictionary) -> String:
	"""Add a buy order. Caller must have already escrowed the Valor.
	Returns order_id. Does NOT merge with existing orders — each is independent."""
	if not market_data.has("orders"):
		market_data["orders"] = {}
	if not market_data.orders.has(post_id):
		market_data.orders[post_id] = []
	var order_id = "ord_%d" % int(market_data.get("next_order_id", 1))
	order["order_id"] = order_id
	market_data["next_order_id"] = int(market_data.get("next_order_id", 1)) + 1
	market_data.orders[post_id].append(order)
	save_market_data()
	return order_id

func remove_market_order(post_id: String, order_id: String) -> Dictionary:
	"""Remove a buy order by ID. Returns the removed order or empty dict."""
	if not market_data.has("orders"):
		return {}
	if not market_data.orders.has(post_id):
		return {}
	var orders = market_data.orders[post_id]
	for i in range(orders.size()):
		if orders[i].get("order_id", "") == order_id:
			var removed = orders[i]
			orders.remove_at(i)
			save_market_data()
			return removed
	return {}

func update_market_order_filled(post_id: String, order_id: String, new_filled: int):
	"""Update a buy order's filled count after a partial fulfillment."""
	if not market_data.has("orders") or not market_data.orders.has(post_id):
		return
	for order in market_data.orders[post_id]:
		if order.get("order_id", "") == order_id:
			order["quantity_filled"] = new_filled
			save_market_data()
			return

func get_all_orders_by_account(account_id: String) -> Array:
	"""All open buy orders placed by this account across all posts (for 'My Orders')."""
	var result: Array = []
	if not market_data.has("orders"):
		return result
	for post_id in market_data.orders.keys():
		for order in market_data.orders[post_id]:
			if order.get("account_id", "") == account_id:
				var entry = order.duplicate()
				entry["post_id"] = post_id
				result.append(entry)
	return result

func get_all_market_orders_with_post() -> Array:
	"""Flat array of every open buy order across every post, tagged with post_id.
	Companion to get_all_market_listings_with_post. For future network-orders view."""
	var result: Array = []
	if not market_data.has("orders"):
		return result
	for post_id in market_data.orders.keys():
		for order in market_data.orders[post_id]:
			var entry = order.duplicate()
			entry["post_id"] = post_id
			result.append(entry)
	return result

# ===== PLAYER STORAGE (Building System - Storage Chests) =====

const PLAYER_STORAGE_FILE = "user://data/player_storage.json"
var player_storage_data: Dictionary = {}

func load_player_storage():
	"""Load player storage data."""
	var data = _safe_load(PLAYER_STORAGE_FILE)
	if data.is_empty():
		player_storage_data = {}
	else:
		player_storage_data = data

func save_player_storage_file():
	"""Save player storage data."""
	_safe_save(PLAYER_STORAGE_FILE, player_storage_data)

func get_player_storage(username: String) -> Array:
	"""Get storage items for a player. Returns array of item dicts."""
	return player_storage_data.get(username, [])

func set_player_storage(username: String, items: Array):
	"""Set storage items for a player."""
	player_storage_data[username] = items
	save_player_storage_file()

# ===== GUARD SYSTEM PERSISTENCE =====

func load_guards() -> Dictionary:
	"""Load active guards from file."""
	var data = _safe_load(GUARDS_FILE)
	if data.is_empty():
		return {}
	return data.get("guards", {})

func save_guards(guards: Dictionary):
	"""Save active guards to file."""
	_safe_save(GUARDS_FILE, {"guards": guards})

# ===== IP BAN LIST =====

func load_ban_list():
	"""Load IP ban list from file."""
	var data = _safe_load(BAN_LIST_FILE)
	if data.is_empty():
		ban_list_data = {"banned_ips": {}}
	else:
		ban_list_data = data
		if not ban_list_data.has("banned_ips"):
			ban_list_data["banned_ips"] = {}
	print("Loaded %d banned IPs" % ban_list_data.banned_ips.size())

func save_ban_list():
	"""Save IP ban list to file."""
	_safe_save(BAN_LIST_FILE, ban_list_data)

func ban_ip(ip: String, reason: String, banned_by: String):
	"""Add an IP to the ban list."""
	ban_list_data.banned_ips[ip] = {
		"reason": reason,
		"banned_at": int(Time.get_unix_time_from_system()),
		"banned_by": banned_by
	}
	save_ban_list()

func unban_ip(ip: String) -> bool:
	"""Remove an IP from the ban list. Returns true if IP was banned."""
	if ban_list_data.banned_ips.has(ip):
		ban_list_data.banned_ips.erase(ip)
		save_ban_list()
		return true
	return false

func is_ip_banned(ip: String) -> bool:
	"""Check if an IP is banned."""
	return ban_list_data.banned_ips.has(ip)
