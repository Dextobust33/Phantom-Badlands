# trading_post_art.gd
# Client-side ASCII art for trading posts
class_name TradingPostArt
extends RefCounted

# Trading post art uses smaller font size for compact display
const POST_FONT_SIZE = 5

# Colors for different post types
const POST_COLORS = {
	"haven": "#FFD700",      # Gold - safe haven
	"fortress": "#A0A0A0",   # Silver/gray - stone fortress
	"market": "#DAA520",     # Goldenrod - commerce
	"shrine": "#E6E6FA",     # Lavender - holy
	"farm": "#8FBC8F",       # Dark sea green - nature
	"mine": "#CD853F",       # Peru - earth
	"tower": "#B0C4DE",      # Light steel blue - watch
	"camp": "#DEB887",       # Burlywood - tents
	"exotic": "#9932CC",     # Dark orchid - mysterious
	"default": "#C4A484",    # Tan - generic
}

# Map trading post IDs to art categories
static func _get_post_category(post_id: String) -> String:
	# Haven/Fortress type
	if post_id in ["haven", "frostgate", "fortress_north", "fortress_south", "ironhold", "citadel", "bastion"]:
		return "haven"

	# Market/Crossroads type
	if post_id in ["crossroads", "east_market", "trade_hub", "merchant_row", "bazaar"]:
		return "market"

	# Shrine/Temple type
	if post_id in ["west_shrine", "shrine", "temple", "sanctuary", "primordial_sanctum", "chaos_refuge", "eternal_sanctuary"]:
		return "shrine"

	# Farm/Grove/Nature type
	if post_id in ["northeast_farm", "southwest_grove", "grove", "farm", "forest_edge", "verdant"]:
		return "farm"

	# Mine/Forge type
	if post_id in ["southeast_mine", "mine", "forge", "smelter", "inferno_outpost", "volcanic"]:
		return "mine"

	# Tower/Watch type
	if post_id in ["northwatch", "southern_watch", "northeast_tower", "tower", "watchtower", "eastwatch", "westhold", "peak"]:
		return "tower"

	# Camp/Outpost type
	if post_id in ["eastern_camp", "western_refuge", "camp", "outpost", "rest_stop", "waystation"]:
		return "camp"

	# Exotic/Mysterious type
	if post_id in ["shadowmere", "voids_edge", "nether_gate", "void", "shadow", "chaos", "apex", "terminus"]:
		return "exotic"

	# Gate type
	if post_id in ["south_gate", "gate", "highland_post", "southport"]:
		return "fortress"

	# Mill type
	if post_id in ["northwest_mill", "mill"]:
		return "farm"

	return "default"

static func get_trading_post_art(post_id: String) -> String:
	"""Get ASCII art for a specific trading post"""
	var category = _get_post_category(post_id)
	var art_lines: Array
	var color: String

	match category:
		"haven":
			art_lines = _get_haven_art()
			color = POST_COLORS["haven"]
		"market":
			art_lines = _get_market_art()
			color = POST_COLORS["market"]
		"shrine":
			art_lines = _get_shrine_art()
			color = POST_COLORS["shrine"]
		"farm":
			art_lines = _get_farm_art()
			color = POST_COLORS["farm"]
		"mine":
			art_lines = _get_mine_art()
			color = POST_COLORS["mine"]
		"tower":
			art_lines = _get_tower_art()
			color = POST_COLORS["tower"]
		"camp":
			art_lines = _get_camp_art()
			color = POST_COLORS["camp"]
		"exotic":
			art_lines = _get_exotic_art()
			color = POST_COLORS["exotic"]
		"fortress":
			art_lines = _get_fortress_art()
			color = POST_COLORS["fortress"]
		_:
			art_lines = _get_default_art()
			color = POST_COLORS["default"]

	# Build the art string with color
	var result = "[color=" + color + "]\n"
	for line in art_lines:
		result += line + "\n"
	result += "[/color]"

	# Wrap in font size
	return "[font_size=" + str(POST_FONT_SIZE) + "]" + result + "[/font_size]"

# ===== ART DEFINITIONS =====

static func _get_haven_art() -> Array:
	return [
		"                                            ",
		"              .---^---.                     ",
		"             /   ||   \\                    ",
		"            |  .-||--.  |                   ",
		"       _____|==|    |==|_____              ",
		"      |  ___|  |    |  |___  |             ",
		"      | |   |  |    |  |   | |             ",
		"     _| |___|__|    |__|___| |_            ",
		"    |___|###|__|====|__|###|___|           ",
		"        |   |  |    |  |   |               ",
		"   _____|   |  |    |  |   |_____          ",
		"  |  ___    |  |    |  |    ___  |         ",
		"  | |   |   |  |    |  |   |   | |         ",
		"  | |   |   |  |    |  |   |   | |         ",
		" _| |___|___|__|    |__|___|___| |_        ",
		"|___|###|###|__|====|__|###|###|___|       ",
		"    |:::|:::|  |    |  |:::|:::|           ",
		"    |:::|:::|  |    |  |:::|:::|           ",
		"____|:::|:::|__|____|__|:::|:::|____       ",
		"    Welcome to the Haven                   ",
		"                                            ",
	]

static func _get_market_art() -> Array:
	return [
		"                                            ",
		"    _____     _____     _____               ",
		"   /     \\   /     \\   /     \\          ",
		"  /  ___  \\ /  ___  \\ /  ___  \\         ",
		" |  |   |  |  |   |  |  |   |  |           ",
		" |  | $ |  |  | @ |  |  | & |  |           ",
		" |  |___|  |  |___|  |  |___|  |           ",
		" |__|   |__|__|   |__|__|   |__|           ",
		"    |   |      |   |      |   |            ",
		" ___|___|______|___|______|___|___         ",
		"|   GOODS   |  WARES  |  TRADE   |         ",
		"|___________|_________|__________|         ",
		"   ||   ||     ||   ||     ||              ",
		"   ||   ||     ||   ||     ||              ",
		"  _||___||_   _||___||_   _||___||_        ",
		" |  OPEN  |  | FRESH  |  | DEALS  |        ",
		" |________|  |________|  |________|        ",
		"                                            ",
		"      The Market is Bustling!              ",
		"                                            ",
	]

static func _get_shrine_art() -> Array:
	return [
		"                                            ",
		"                  /\\                       ",
		"                 /  \\                      ",
		"                / ** \\                     ",
		"               / *  * \\                    ",
		"              /   **   \\                   ",
		"             /    ||    \\                  ",
		"            /     ||     \\                 ",
		"           /______|______\\                 ",
		"              |      |                      ",
		"         _____|  oo  |_____                 ",
		"        |     |      |     |                ",
		"        |  o  |  /\\  |  o  |               ",
		"        |     | /  \\ |     |               ",
		"        |_____|/    \\|_____|               ",
		"            |   ~~~~   |                    ",
		"        ____|__________|____                ",
		"                                            ",
		"        A Sacred Place of Rest              ",
		"                                            ",
	]

static func _get_farm_art() -> Array:
	return [
		"                                            ",
		"          \\|/                              ",
		"           |      ___                       ",
		"      _____|_____/   \\____                 ",
		"     /           \\___/    \\               ",
		"    /   _____             \\                ",
		"   /   /     \\     ^^     |               ",
		"  |   |  |||  |   /||\\    |               ",
		"  |   |  |||  |   ||||    |                ",
		"  |   |__|__|_|___|__|____|                 ",
		"  |      |    |    |      |                 ",
		" _|______|____|____|______|_                ",
		" ~^~^~^~^~^~^~^~^~^~^~^~^~^~               ",
		"  \\|/ \\|/ \\|/ \\|/ \\|/ \\|/            ",
		"   Y   Y   Y   Y   Y   Y                    ",
		"   |   |   |   |   |   |                    ",
		" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~          ",
		"                                            ",
		"       The Fields are Peaceful              ",
		"                                            ",
	]

static func _get_mine_art() -> Array:
	return [
		"                                            ",
		"        /\\      /\\      /\\               ",
		"       /  \\    /  \\    /  \\              ",
		"      / /\\ \\  / /\\ \\  / /\\ \\          ",
		"     /_/  \\_\\/_/  \\_\\/_/  \\_\\         ",
		"    |   MINE ENTRANCE    |                  ",
		"    |____________________|                  ",
		"         |        |                         ",
		"     ____|   ||   |____                     ",
		"    |    |   ||   |    |                    ",
		"    | [] |   ||   | [] |                    ",
		"    |____|   ||   |____|                    ",
		"         |   ||   |                         ",
		"    _____|   \\/   |_____                   ",
		"   /                     \\                 ",
		"  /   o    o    o    o    \\                ",
		" /_________________________\\               ",
		"                                            ",
		"     Echoes from the Depths                 ",
		"                                            ",
	]

static func _get_tower_art() -> Array:
	return [
		"                                            ",
		"              [###]                         ",
		"              |:::|                         ",
		"           ___|:::|___                      ",
		"          |   |:::|   |                     ",
		"          |   |:::|   |                     ",
		"          |___|:::|___|                     ",
		"              |:::|                         ",
		"           ___|:::|___                      ",
		"          |   |:::|   |                     ",
		"          | []|:::| []|                     ",
		"          |___|:::|___|                     ",
		"              |:::|                         ",
		"           ___|:::|___                      ",
		"          |   |===|   |                     ",
		"          | []|   |[] |                     ",
		"       ___|___|___|___|___                  ",
		"      |___________________|                 ",
		"                                            ",
		"     The Watchtower Stands Vigilant         ",
		"                                            ",
	]

static func _get_camp_art() -> Array:
	return [
		"                                            ",
		"                  /\\                       ",
		"       /\\       /  \\       /\\            ",
		"      /  \\     / || \\     /  \\          ",
		"     / || \\   /  ||  \\   / || \\         ",
		"    /  ||  \\ /   ||   \\ /  ||  \\        ",
		"   /___|____|/___|____|\\/___|____|\\       ",
		"       ||       ||         ||              ",
		"       ||       ||         ||              ",
		"                                            ",
		"         \\   |   /                        ",
		"          \\  |  /                         ",
		"       -----(*)-----     FIRE              ",
		"          /  |  \\                         ",
		"         /   |   \\                        ",
		"                                            ",
		"   ~~~~  ~~~~  ~~~~  ~~~~  ~~~~            ",
		"                                            ",
		"       Rest by the Campfire                 ",
		"                                            ",
	]

static func _get_exotic_art() -> Array:
	return [
		"                                            ",
		"       *  .  *  .  *  .  *                  ",
		"    .    *    .    *    .                   ",
		"       _______________                      ",
		"      /               \\                    ",
		"     /   ~~~     ~~~   \\                   ",
		"    |  /   \\   /   \\  |                   ",
		"    | (  o  ) (  o  ) |                     ",
		"    |  \\___/   \\___/  |                   ",
		"    |       \\ /       |                    ",
		"    |        V        |                     ",
		"     \\   ~~~~~~~   /                       ",
		"      \\___________/                        ",
		"           |||                              ",
		"        ~~~|||~~~                           ",
		"       ~  ~|||~  ~                          ",
		"    .    *    .    *    .                   ",
		"       *  .  *  .  *  .  *                  ",
		"                                            ",
		"    Strange Energies Swirl Here             ",
		"                                            ",
	]

static func _get_fortress_art() -> Array:
	return [
		"                                            ",
		"    [#]                           [#]       ",
		"    |:|___________________________|:|       ",
		"    |:|                           |:|       ",
		"    |:|   ___________________     |:|       ",
		"    |:|  |                   |    |:|       ",
		"    |:|  |  []    ||    []  |    |:|       ",
		"    |:|  |        ||        |    |:|       ",
		"    |:|  |________|_________|    |:|       ",
		"    |:|         |    |           |:|       ",
		"    |:|_________|    |___________|:|       ",
		"    |:::::::::::      :::::::::::|:|       ",
		"    |:::::::::::      :::::::::::|:|       ",
		" ___|:::::::::::|    |:::::::::::|:|___    ",
		"|___            |    |            ___|     ",
		"    |___________|    |___________|         ",
		"                                            ",
		"        The Gates Stand Strong              ",
		"                                            ",
	]

static func _get_default_art() -> Array:
	return [
		"                                            ",
		"           _______                          ",
		"          /       \\                        ",
		"         /   ___   \\                       ",
		"        |   /   \\   |                      ",
		"        |  | ~~~ |  |                       ",
		"        |  |     |  |                       ",
		"        |  |_____|  |                       ",
		"        |     |     |                       ",
		"     ___|_____|_____|___                    ",
		"    |                   |                   ",
		"    |   []         []   |                   ",
		"    |                   |                   ",
		"    |_______     _______|                   ",
		"            |   |                           ",
		"    ________|   |________                   ",
		"   |_________|_|_________|                  ",
		"                                            ",
		"        A Place of Rest                     ",
		"                                            ",
	]
