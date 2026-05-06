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

# Texture cache so we don't reload the same PNG repeatedly.
static var _texture_cache: Dictionary = {}

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
	"""Return an AtlasTexture pointing at the down-facing idle frame for the
	given class. Returns null if the class sheet is missing — caller should
	render a placeholder."""
	var tex := _get_full_texture(class_name_in)
	if tex == null:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(IDLE_X, IDLE_Y, CELL, CELL)
	return atlas


static func get_class_color(class_name_in: String) -> Color:
	var key := _normalize(class_name_in)
	return CLASS_COLORS.get(key, Color.WHITE)


static func has_sprite_for(class_name_in: String) -> bool:
	return _get_full_texture(class_name_in) != null


static func clear_cache() -> void:
	_texture_cache.clear()
