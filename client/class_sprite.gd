extends RefCounted
class_name ClassSprite

# Loads LPC class spritesheets and slices specific frames out of them.
# Sheets live in res://client/sprites/classes/<lowercase_class>.png and follow
# the LPC universal layout: 64x64 cells. We only need the down-facing idle
# frame for the A1 scene (no animations yet).

const SPRITE_DIR := "res://client/sprites/classes/"
const CELL := 64

# Standard LPC universal layout — walk animation occupies rows 8-11.
# Row 11 is the "walk right" direction; column 0 is the standing/idle frame.
# We use this so the player figure faces the monster (which is on the right
# half of the battle scene), per JRPG convention.
const IDLE_X := 0
const IDLE_Y := 11 * CELL  # 704 — walk-right row, idle column

# LPC walk-row layout — column 0 of each row is the idle/standing pose
# for that facing.
const ROW_UP := 8
const ROW_LEFT := 9
const ROW_DOWN := 10
const ROW_RIGHT := 11

# Direction string constants — used by callers to ask for a specific facing.
const DIR_UP := "up"
const DIR_DOWN := "down"
const DIR_LEFT := "left"
const DIR_RIGHT := "right"

# Texture cache so we don't reload the same PNG repeatedly.
static var _texture_cache: Dictionary = {}
# Per-direction atlas cache so we don't construct new AtlasTexture objects
# every frame for the same class+direction.
static var _atlas_cache: Dictionary = {}

# Class display colors used for HP-bar tinting and accent highlights on the
# combat scene panel. Tunable later — these are first-pass.
const CLASS_COLORS := {
	"fighter": Color("#C0C0C0"),
	"barbarian": Color("#FF4444"),
	"paladin": Color("#FFD700"),
	"wizard": Color("#4488FF"),
	"sorcerer": Color("#9966FF"),
	"sage": Color("#88EEAA"),
	"thief": Color("#888888"),
	"ranger": Color("#44AA44"),
	"ninja": Color("#9966CC"),
}


static func _normalize(class_name_in: String) -> String:
	return class_name_in.to_lower().strip_edges()


static func _get_full_texture(class_name_in: String) -> Texture2D:
	var key := _normalize(class_name_in)
	if _texture_cache.has(key):
		return _texture_cache[key]
	var path := SPRITE_DIR + key + ".png"
	if not ResourceLoader.exists(path):
		_texture_cache[key] = null
		return null
	var tex := load(path) as Texture2D
	_texture_cache[key] = tex
	return tex


static func get_idle_atlas(class_name_in: String) -> AtlasTexture:
	"""Return an AtlasTexture pointing at the right-facing idle frame for
	the given class. Used by the combat scene panel where the player
	always faces the monster on the right. For map use, prefer
	get_idle_atlas_for_direction() so the sprite rotates to the
	movement direction."""
	return get_idle_atlas_for_direction(class_name_in, DIR_RIGHT)


static func get_idle_atlas_for_direction(class_name_in: String, direction: String) -> AtlasTexture:
	"""Return an AtlasTexture for the given class facing the given direction.
	Cached per (class, direction) so repeated calls in _process don't churn."""
	var key := _normalize(class_name_in) + "|" + direction
	if _atlas_cache.has(key):
		return _atlas_cache[key]
	var tex := _get_full_texture(class_name_in)
	if tex == null:
		_atlas_cache[key] = null
		return null
	var row: int = ROW_RIGHT
	match direction:
		DIR_UP: row = ROW_UP
		DIR_LEFT: row = ROW_LEFT
		DIR_DOWN: row = ROW_DOWN
		DIR_RIGHT: row = ROW_RIGHT
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(IDLE_X, row * CELL, CELL, CELL)
	_atlas_cache[key] = atlas
	return atlas


static func get_class_color(class_name_in: String) -> Color:
	var key := _normalize(class_name_in)
	return CLASS_COLORS.get(key, Color.WHITE)


static func has_sprite_for(class_name_in: String) -> bool:
	return _get_full_texture(class_name_in) != null


static func clear_cache() -> void:
	_texture_cache.clear()
	_atlas_cache.clear()
