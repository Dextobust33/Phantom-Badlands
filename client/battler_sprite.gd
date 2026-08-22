class_name BattlerSprite
extends RefCounted

# v0.9.669 — shared source of truth for a character's combat BATTLER sprite, so
# the map avatar / player info / status screen / cursor hover all show the SAME
# sprite the combat scene uses. Mirrors combat_scene_panel.gd's CLASS_SPRITE_POOLS
# + stable per-name pick (kept in sync — combat_scene_panel now delegates here).

const BATTLER_DIR := "res://client/sprites/battlers/tf/"

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
