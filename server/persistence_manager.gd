# persistence_manager.gd
# Handles all file-based persistence for accounts, characters, and leaderboard
class_name PersistenceManager
extends Node

const DATA_DIR = "user://data/"
const ACCOUNTS_FILE = "user://data/accounts.json"
const LEADERBOARD_FILE = "user://data/leaderboard.json"
const CHARACTERS_DIR = "user://data/characters/"

const MAX_LEADERBOARD_ENTRIES = 100
const DEFAULT_MAX_CHARACTERS = 6

# Cached data
var accounts_data: Dictionary = {}
var leaderboard_data: Dictionary = {}

func _ready():
	ensure_data_directories()
	load_accounts()
	load_leaderboard()

# ===== DIRECTORY SETUP =====

func ensure_data_directories():
	"""Create data directories if they don't exist"""
	var dir = DirAccess.open("user://")
	if dir:
		if not dir.dir_exists("data"):
			dir.make_dir("data")
		if not dir.dir_exists("data/characters"):
			dir.make_dir_recursive("data/characters")

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
	if not FileAccess.file_exists(ACCOUNTS_FILE):
		accounts_data = {
			"accounts": {},
			"username_to_id": {},
			"next_account_id": 1
		}
		save_accounts()
		return

	var file = FileAccess.open(ACCOUNTS_FILE, FileAccess.READ)
	if file:
		var json = JSON.new()
		var error = json.parse(file.get_as_text())
		file.close()

		if error == OK:
			accounts_data = json.data
		else:
			print("Error parsing accounts file: ", json.get_error_message())
			accounts_data = {
				"accounts": {},
				"username_to_id": {},
				"next_account_id": 1
			}

func save_accounts():
	"""Save accounts data to file"""
	var file = FileAccess.open(ACCOUNTS_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(accounts_data, "\t"))
		file.close()

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
		"max_characters": DEFAULT_MAX_CHARACTERS
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
	var file = FileAccess.open(filepath, FileAccess.WRITE)
	if file:
		var data = character.to_dict()
		data["account_id"] = account_id
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
		#print("Character saved: %s" % character.name)

func load_character(account_id: String, char_name: String) -> Dictionary:
	"""Load character data from file"""
	var filepath = get_character_filepath(account_id, char_name)

	if not FileAccess.file_exists(filepath):
		return {}

	var file = FileAccess.open(filepath, FileAccess.READ)
	if file:
		var json = JSON.new()
		var error = json.parse(file.get_as_text())
		file.close()

		if error == OK:
			var data = json.data
			# Migrate legacy items to new tiered format
			if data.has("inventory"):
				data["inventory"] = _migrate_legacy_items(data["inventory"])
			return data

	return {}

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
	if not FileAccess.file_exists(LEADERBOARD_FILE):
		leaderboard_data = {"entries": []}
		save_leaderboard()
		return

	var file = FileAccess.open(LEADERBOARD_FILE, FileAccess.READ)
	if file:
		var json = JSON.new()
		var error = json.parse(file.get_as_text())
		file.close()

		if error == OK:
			leaderboard_data = json.data
		else:
			leaderboard_data = {"entries": []}

func save_leaderboard():
	"""Save leaderboard data to file"""
	var file = FileAccess.open(LEADERBOARD_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(leaderboard_data, "\t"))
		file.close()

func add_to_leaderboard(character: Character, cause_of_death: String, account_username: String) -> int:
	"""Add a deceased character to the leaderboard. Returns their rank."""
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
	"""Get top entries from leaderboard"""
	var result = []
	var count = min(limit, leaderboard_data.entries.size())

	for i in range(count):
		result.append(leaderboard_data.entries[i])

	return result

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
		"characters": account.character_slots
	}
