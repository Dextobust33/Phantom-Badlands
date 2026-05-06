class_name ClassAsciiArt
extends RefCounted

# Loader for per-class battle ASCII art. Drop a `<ClassName>.txt` into
# `res://client/sprites/ascii/` (e.g. `Fighter.txt`, `Wizard.txt`) and the
# combat scene panel will auto-render it in place of the LPC PNG sprite.
# Classes without a matching file fall back to the existing PNG flow.
#
# Per-class font_size and color overrides live in the maps below. Default
# is 2pt (tuned for the 100×52 Alt-Fighter art) on near-white #E8E8E8.

const ASCII_DIR := "res://client/sprites/ascii/"
const DEFAULT_FONT_SIZE := 3
const DEFAULT_COLOR := "#E8E8E8"

# Per-class font_size override. Add an entry when a class's art doesn't
# render well at the default size.
const FONT_SIZE_OVERRIDES := {
	# "Wizard": 3,
}

# Per-class color override (hex string). Add an entry to tint a class's
# art (e.g., a paladin in gold, a sorcerer in violet). Empty = default.
const COLOR_OVERRIDES := {
	# "Paladin": "#FFD86A",
}

static var _cache: Dictionary = {}


static func has_ascii_art(cls: String) -> bool:
	return get_ascii_art(cls) != ""


static func get_ascii_art(cls: String) -> String:
	"""Return the ASCII art text for a class, or empty string if none exists.
	Cached after first read."""
	if cls == "":
		return ""
	if _cache.has(cls):
		return _cache[cls]
	var path = ASCII_DIR + cls + ".txt"
	if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
		_cache[cls] = ""
		return ""
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		_cache[cls] = ""
		return ""
	var content = f.get_as_text()
	f.close()
	_cache[cls] = content
	return content


static func get_font_size(cls: String) -> int:
	return int(FONT_SIZE_OVERRIDES.get(cls, DEFAULT_FONT_SIZE))


static func get_color(cls: String) -> String:
	var override = COLOR_OVERRIDES.get(cls, "")
	if override == "":
		return DEFAULT_COLOR
	return str(override)


static func clear_cache() -> void:
	"""Useful in dev when iterating on art files without restarting."""
	_cache.clear()
