# admin_tool.gd
# Standalone admin tool for managing Phantasia Revival accounts
# Run with: godot --headless --script admin_tool.gd -- <command> [args]
extends SceneTree

const DATA_DIR = "user://data/"
const ACCOUNTS_FILE = "user://data/accounts.json"
const LEADERBOARD_FILE = "user://data/leaderboard.json"
const HOUSES_FILE = "user://data/houses.json"

var accounts_data: Dictionary = {}
var leaderboard_data: Dictionary = {}
var houses_data: Dictionary = {}

func _init():
	var args = OS.get_cmdline_user_args()

	if args.size() == 0:
		print_help()
		quit()
		return

	load_accounts()

	var command = args[0].to_lower()

	match command:
		"list":
			list_accounts()
		"info":
			if args.size() < 2:
				print("Usage: info <username>")
			else:
				show_account_info(args[1])
		"resetpassword", "reset":
			if args.size() < 3:
				print("Usage: resetpassword <username> <new_password>")
			else:
				reset_password(args[1], args[2])
		"removeleader", "removelb":
			if args.size() < 2:
				print("Usage: removeleader <character_name>")
			else:
				remove_leaderboard_entry(args[1])
		"leaderboard", "lb":
			show_leaderboard()
		"addcompanion":
			if args.size() < 3:
				print("Usage: addcompanion <username> <monster_type> [tier] [name]")
				print("Example: addcompanion Dextobust33 Chimaera 3 \"Chimaera Cub\"")
			else:
				var tier = int(args[3]) if args.size() > 3 else 3
				var comp_name = args[4] if args.size() > 4 else args[2] + " Cub"
				add_companion_to_storage(args[1], args[2], tier, comp_name)
		"storage":
			if args.size() < 2:
				print("Usage: storage <username>")
			else:
				show_storage(args[1])
		"help", "-h", "--help":
			print_help()
		_:
			print("Unknown command: %s" % command)
			print_help()

	quit()

func print_help():
	print("")
	print("========================================")
	print("Phantasia Revival Admin Tool")
	print("========================================")
	print("")
	print("Usage: godot --headless --script admin_tool.gd -- <command> [args]")
	print("")
	print("Commands:")
	print("  list                         - List all accounts")
	print("  info <username>              - Show account details")
	print("  resetpassword <user> <pass>  - Reset account password")
	print("  leaderboard                  - Show the leaderboard")
	print("  removeleader <name>          - Remove entry from leaderboard")
	print("  storage <username>           - Show house storage contents")
	print("  addcompanion <user> <type> [tier] [name]")
	print("                               - Add companion to house storage")
	print("  help                         - Show this help")
	print("")
	print("Examples:")
	print("  godot --headless --script admin_tool.gd -- list")
	print("  godot --headless --script admin_tool.gd -- resetpassword JohnDoe newpass123")
	print("  godot --headless --script admin_tool.gd -- addcompanion Dextobust33 Chimaera 3 \"Chimaera Cub\"")
	print("")

func load_accounts():
	if not FileAccess.file_exists(ACCOUNTS_FILE):
		print("ERROR: Accounts file not found at %s" % ACCOUNTS_FILE)
		print("Make sure the server has been run at least once.")
		return

	var file = FileAccess.open(ACCOUNTS_FILE, FileAccess.READ)
	if file:
		var json = JSON.new()
		var error = json.parse(file.get_as_text())
		file.close()

		if error == OK:
			accounts_data = json.data
		else:
			print("ERROR: Failed to parse accounts file")

func save_accounts():
	var file = FileAccess.open(ACCOUNTS_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(accounts_data, "\t"))
		file.close()

func list_accounts():
	if accounts_data.is_empty() or not accounts_data.has("accounts"):
		print("No accounts found.")
		return

	print("")
	print("========================================")
	print("Registered Accounts")
	print("========================================")
	print("")

	var count = 0
	for account_id in accounts_data.accounts.keys():
		var account = accounts_data.accounts[account_id]
		var created = account.get("created_at", 0)
		var created_str = Time.get_datetime_string_from_unix_time(created) if created > 0 else "Unknown"
		var chars = account.get("character_slots", [])

		print("%s: %s" % [account_id, account.username])
		print("  Created: %s" % created_str)
		print("  Characters (%d): %s" % [chars.size(), ", ".join(chars) if chars.size() > 0 else "(none)"])
		print("")
		count += 1

	print("Total accounts: %d" % count)
	print("")

func show_account_info(username: String):
	var username_lower = username.to_lower()

	if not accounts_data.has("username_to_id") or not accounts_data.username_to_id.has(username_lower):
		print("Account not found: %s" % username)
		return

	var account_id = accounts_data.username_to_id[username_lower]
	var account = accounts_data.accounts[account_id]

	var created = account.get("created_at", 0)
	var created_str = Time.get_datetime_string_from_unix_time(created) if created > 0 else "Unknown"
	var chars = account.get("character_slots", [])

	print("")
	print("========================================")
	print("Account: %s" % account.username)
	print("========================================")
	print("Account ID: %s" % account_id)
	print("Created: %s" % created_str)
	print("Max Characters: %d" % account.get("max_characters", 3))
	print("Characters: %s" % (", ".join(chars) if chars.size() > 0 else "(none)"))
	print("")

func reset_password(username: String, new_password: String):
	var username_lower = username.to_lower()

	if not accounts_data.has("username_to_id") or not accounts_data.username_to_id.has(username_lower):
		print("ERROR: Account not found: %s" % username)
		return

	if new_password.length() < 4:
		print("ERROR: Password must be at least 4 characters")
		return

	var account_id = accounts_data.username_to_id[username_lower]
	var account = accounts_data.accounts[account_id]

	# Generate new salt and hash
	var new_salt = generate_salt()
	var new_hash = hash_password(new_password, new_salt)

	# Update account
	account.password_hash = new_hash
	account.password_salt = new_salt

	save_accounts()

	print("")
	print("SUCCESS: Password reset for account '%s'" % account.username)
	print("New password: %s" % new_password)
	print("")

func generate_salt() -> String:
	var crypto = Crypto.new()
	var salt_bytes = crypto.generate_random_bytes(32)
	return salt_bytes.hex_encode()

func hash_password(password: String, salt: String) -> String:
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update((salt + password).to_utf8_buffer())
	var hash_bytes = ctx.finish()
	return hash_bytes.hex_encode()

func load_leaderboard():
	if not FileAccess.file_exists(LEADERBOARD_FILE):
		print("ERROR: Leaderboard file not found at %s" % LEADERBOARD_FILE)
		return
	var file = FileAccess.open(LEADERBOARD_FILE, FileAccess.READ)
	if file:
		var json = JSON.new()
		var error = json.parse(file.get_as_text())
		file.close()
		if error == OK:
			leaderboard_data = json.data
		else:
			print("ERROR: Failed to parse leaderboard file")

func save_leaderboard():
	var file = FileAccess.open(LEADERBOARD_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(leaderboard_data, "\t"))
		file.close()

func show_leaderboard():
	load_leaderboard()
	var entries = leaderboard_data.get("entries", [])
	if entries.is_empty():
		print("Leaderboard is empty.")
		return
	print("")
	print("========================================")
	print("Leaderboard (%d entries)" % entries.size())
	print("========================================")
	print("")
	for entry in entries:
		var rank = entry.get("rank", 0)
		var name = entry.get("character_name", "???")
		var level = entry.get("level", 0)
		var cls = entry.get("class", "???")
		var xp = entry.get("experience", 0)
		var cod = entry.get("cause_of_death", "Unknown")
		print("#%d  %s  Lv%d %s  XP:%d  CoD: %s" % [rank, name, level, cls, xp, cod])
	print("")

func remove_leaderboard_entry(character_name: String):
	load_leaderboard()
	var entries = leaderboard_data.get("entries", [])
	var found_index = -1
	for i in range(entries.size()):
		if entries[i].get("character_name", "") == character_name:
			found_index = i
			break
	if found_index == -1:
		print("ERROR: '%s' not found on leaderboard." % character_name)
		print("Use 'leaderboard' command to see all entries.")
		return
	var removed = entries[found_index]
	entries.remove_at(found_index)
	# Recalculate ranks
	for i in range(entries.size()):
		entries[i]["rank"] = i + 1
	save_leaderboard()
	print("")
	print("SUCCESS: Removed '%s' (was rank #%d, Lv%d %s)" % [
		character_name,
		removed.get("rank", 0),
		removed.get("level", 0),
		removed.get("class", "???")
	])
	print("Ranks renumbered. %d entries remain." % entries.size())
	print("")

func load_houses():
	if not FileAccess.file_exists(HOUSES_FILE):
		print("ERROR: Houses file not found at %s" % HOUSES_FILE)
		return
	var file = FileAccess.open(HOUSES_FILE, FileAccess.READ)
	if file:
		var json = JSON.new()
		var error = json.parse(file.get_as_text())
		file.close()
		if error == OK:
			houses_data = json.data
		else:
			print("ERROR: Failed to parse houses file")

func save_houses():
	var file = FileAccess.open(HOUSES_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(houses_data, "\t"))
		file.close()

func _get_account_id_for_username(username: String) -> String:
	"""Look up account_id from username"""
	var username_lower = username.to_lower()
	if not accounts_data.has("username_to_id") or not accounts_data.username_to_id.has(username_lower):
		return ""
	return accounts_data.username_to_id[username_lower]

func show_storage(username: String):
	var account_id = _get_account_id_for_username(username)
	if account_id.is_empty():
		print("ERROR: Account not found: %s" % username)
		return

	load_houses()
	if not houses_data.has("houses") or not houses_data.houses.has(account_id):
		print("No house found for %s" % username)
		return

	var house = houses_data.houses[account_id]
	var items = house.get("storage", {}).get("items", [])
	var companions = house.get("registered_companions", {}).get("companions", [])

	print("")
	print("========================================")
	print("House Storage: %s" % username)
	print("========================================")
	print("")

	if items.is_empty():
		print("  Storage: (empty)")
	else:
		print("  Storage (%d items):" % items.size())
		for i in range(items.size()):
			var item = items[i]
			var item_name = item.get("name", item.get("monster_type", "Unknown"))
			var item_type = item.get("type", "???")
			var tier = item.get("tier", 0)
			print("    [%d] %s (type: %s, tier: %d)" % [i, item_name, item_type, tier])

	print("")
	if companions.is_empty():
		print("  Kennel: (empty)")
	else:
		print("  Kennel (%d companions):" % companions.size())
		for i in range(companions.size()):
			var comp = companions[i]
			var comp_name = comp.get("name", "Unknown")
			var checked_out = comp.get("checked_out_by", null)
			var status = " [checked out by %s]" % checked_out if checked_out != null else ""
			print("    [%d] %s (Lv%d, Tier %d)%s" % [i, comp_name, comp.get("level", 1), comp.get("tier", 1), status])
	print("")

func add_companion_to_storage(username: String, monster_type: String, tier: int, companion_name: String):
	var account_id = _get_account_id_for_username(username)
	if account_id.is_empty():
		print("ERROR: Account not found: %s" % username)
		return

	load_houses()
	if not houses_data.has("houses") or not houses_data.houses.has(account_id):
		print("ERROR: No house found for %s. Player must log in first." % username)
		return

	var house = houses_data.houses[account_id]

	# Check storage capacity
	var base_slots = house.get("storage", {}).get("slots", 20)
	var upgrade_level = house.get("upgrades", {}).get("storage_slots", 0)
	var capacity = int(base_slots) + (int(upgrade_level) * 10)
	var items = house.get("storage", {}).get("items", [])
	if items.size() >= capacity:
		print("ERROR: House storage is full (%d/%d)" % [items.size(), capacity])
		return

	# Create stored companion
	var companion = {
		"type": "stored_companion",
		"id": "companion_" + monster_type.to_lower().replace(" ", "_") + "_admin_" + str(randi()),
		"monster_type": monster_type,
		"name": companion_name,
		"tier": tier,
		"bonuses": {},
		"obtained_at": int(Time.get_unix_time_from_system()),
		"battles_fought": 0,
		"variant": "Normal",
		"variant_color": "#FFFFFF",
		"variant_color2": "",
		"variant_pattern": "solid",
		"level": 1,
		"xp": 0
	}

	items.append(companion)
	house["storage"]["items"] = items
	save_houses()

	print("")
	print("SUCCESS: Added %s (Tier %d, %s) to %s's house storage." % [companion_name, tier, monster_type, username])
	print("Storage: %d/%d items" % [items.size(), capacity])
	print("")
