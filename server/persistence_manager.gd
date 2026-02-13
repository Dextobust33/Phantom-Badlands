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

const MAX_LEADERBOARD_ENTRIES = 100
const DEFAULT_MAX_CHARACTERS = 6

# House upgrade definitions - cost in Baddie Points per level
const HOUSE_UPGRADES = {
	"house_size": {"effect": 1, "max": 3, "costs": [5000, 15000, 50000]},  # Expands the house layout
	"storage_slots": {"effect": 10, "max": 8, "costs": [500, 1000, 2000, 4000, 8000, 16000, 32000, 64000]},
	"companion_slots": {"effect": 1, "max": 8, "costs": [2000, 5000, 10000, 15000, 25000, 40000, 60000, 80000]},
	"egg_slots": {"effect": 1, "max": 9, "costs": [500, 1000, 2000, 4000, 7000, 12000, 20000, 35000, 60000]},
	"flee_chance": {"effect": 2, "max": 5, "costs": [1000, 2500, 5000, 10000, 20000]},
	"starting_gold": {"effect": 50, "max": 10, "costs": [250, 500, 750, 1000, 1500, 2000, 3000, 5000, 6500, 8000]},
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
	"wits_bonus": {"effect": 1, "max": 10, "costs": [1000, 2000, 4000, 7000, 12000, 18000, 26000, 36000, 45000, 50000]}
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

func _ready():
	ensure_data_directories()
	load_accounts()
	load_leaderboard()
	load_monster_kills()
	load_realm_state()
	load_corpses()
	load_houses()
	load_player_tiles()

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
	if password.length() < 4:
		return {"success": false, "reason": "Password must be at least 4 characters"}

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
		"is_admin": false
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

func add_to_leaderboard(character: Character, cause_of_death: String, account_username: String) -> int:
	"""Add a deceased character to the leaderboard. Returns their rank."""
	# Admin accounts are excluded from leaderboards
	if is_admin_username(account_username):
		print("Admin account '%s' excluded from leaderboard" % account_username)
		return -1

	var entry = {
		"character_name": character.name,
		"class": character.class_type,
		"level": character.level,
		"experience": character.experience,
		"account_username": account_username,
		"cause_of_death": cause_of_death,
		"monsters_killed": character.monsters_killed,
		"died_at": int(Time.get_unix_time_from_system())
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
	"""Get top entries from leaderboard (excludes admin accounts)"""
	var result = []

	for entry in leaderboard_data.entries:
		if is_admin_username(entry.get("account_username", "")):
			continue
		result.append(entry)
		if result.size() >= limit:
			break

	return result

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
	if new_password.length() < 4:
		return {"success": false, "reason": "New password must be at least 4 characters"}

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

	if new_password.length() < 4:
		return {"success": false, "reason": "Password must be at least 4 characters"}

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

	# Scan all accounts and their characters (exclude admins)
	for account_id in accounts_data.accounts.keys():
		var account = accounts_data.accounts[account_id]
		if account.get("is_admin", false):
			continue
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

		"baddie_points": 0,
		"total_baddie_points_earned": 0,

		"upgrades": {
			"house_size": 0,
			"storage_slots": 0,
			"companion_slots": 0,
			"flee_chance": 0,
			"starting_gold": 0,
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
			"total_gold_earned": 0,
			"total_xp_earned": 0,
			"total_monsters_killed": 0
		}
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
		"starting_gold": 0,
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
	var bonus_ids = ["flee_chance", "starting_gold", "xp_bonus", "gathering_bonus",
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

	# Gold contribution: 1 BP per 500 gold
	points += int(character.gold / 500)

	# Gem contribution: 5 BP per gem
	points += character.gems * 5

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

func add_player_tile(username: String, x: int, y: int, tile_type: String):
	"""Track a player-placed tile."""
	if not player_tiles_data.has("tiles"):
		player_tiles_data["tiles"] = {}
	if not player_tiles_data.tiles.has(username):
		player_tiles_data.tiles[username] = []
	player_tiles_data.tiles[username].append({"x": x, "y": y, "type": tile_type})
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
