class_name BattlerSprite
extends RefCounted

# v0.9.669 — shared source of truth for a character's combat BATTLER sprite, so
# the map avatar / player info / status screen / cursor hover all show the SAME
# sprite the combat scene uses. Mirrors combat_scene_panel.gd's CLASS_SPRITE_POOLS
# + stable per-name pick (kept in sync — combat_scene_panel now delegates here).

const BATTLER_DIR := "res://client/sprites/battlers/tf/"
const OVERWORLD_DIR := "res://client/sprites/battlers/overworld/"

const CLASS_SPRITE_POOLS := {
	"Fighter": ["1_1", "2_1", "6_4"],
	"Barbarian": ["6_2", "5_3", "7_8"],
	"Paladin": ["4_7", "2_8", "3_8"],
	"Wizard": ["1_6", "5_6", "2_6"],
	"Sorcerer": ["4_5", "3_6", "1_5"],
	"Sage": ["3_3", "5_7", "5_8"],
	"Thief": ["5_7", "6_3", "7_5"],
	"Ranger": ["3_4", "2_4", "6_1"],
	"Ninja": ["4_5", "1_8", "7_3"],
}

static func has_battler(cls: String) -> bool:
	return CLASS_SPRITE_POOLS.has(cls) and not (CLASS_SPRITE_POOLS[cls] as Array).is_empty()

static func id_for(cls: String, char_name: String) -> String:
	"""Stable per-character pick from the class pool. Same name -> same sprite."""
	var pool: Array = CLASS_SPRITE_POOLS.get(cls, [])
	if pool.is_empty():
		return ""
	var idx: int = abs(char_name.hash()) % pool.size()
	return String(pool[idx])

static func idle_path(cls: String, char_name: String) -> String:
	"""res:// path to the idle_0 frame for this character, or '' if the class has
	no battler pool."""
	var id := id_for(cls, char_name)
	if id == "":
		return ""
	return BATTLER_DIR + id + "/idle_0.png"

static func idle_texture(cls: String, char_name: String) -> Texture2D:
	var p := idle_path(cls, char_name)
	if p == "" or not ResourceLoader.exists(p):
		return null
	return load(p) as Texture2D

# --- Overworld (4-direction) map avatars -----------------------------------
# Only battler ids on TimeFantasy sheets 2-5 have a matching top-down overworld
# sprite (tf/N_M == chara N_M). Ids on sheets 1/6/7 fall back to the side-view
# battler. Facing is "up"/"down"/"left"/"right"; overworld frames are native to
# each direction (no flip_h needed, unlike the side-view battlers).

static func has_overworld(cls: String, char_name: String) -> bool:
	var id := id_for(cls, char_name)
	if id == "":
		return false
	return ResourceLoader.exists(OVERWORLD_DIR + id + "/down_stand.png")

static func overworld_texture(cls: String, char_name: String, facing: String, walk_frame: int = 0) -> Texture2D:
	"""Directional overworld sprite. walk_frame: 0 = stand, 1/2 = walk cycle.
	Returns null if this character has no overworld twin."""
	var id := id_for(cls, char_name)
	if id == "":
		return null
	var dir := facing
	if not (dir in ["up", "down", "left", "right"]):
		dir = "down"
	var suffix := "_stand"
	if walk_frame == 1:
		suffix = "_walk1"
	elif walk_frame == 2:
		suffix = "_walk2"
	var p := OVERWORLD_DIR + id + "/" + dir + suffix + ".png"
	if not ResourceLoader.exists(p):
		p = OVERWORLD_DIR + id + "/" + dir + "_stand.png"
	if not ResourceLoader.exists(p):
		return null
	return load(p) as Texture2D
