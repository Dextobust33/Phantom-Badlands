class_name BattlerSprite
extends RefCounted

# Shared source of truth for a character's combat BATTLER sprite, so the map
# avatar / player info / status screen / cursor hover all show the SAME sprite
# the combat scene uses (combat_scene_panel.gd delegates here).
#
# v0.9.670 — the sprite is now STORED per character (character.battler_id, rolled
# at creation from BattlerPools.EXPANDED_POOLS) instead of derived live. Prefer
# the stored id via *_by_id / *_from_data. The legacy (cls, char_name) helpers
# derive from BattlerPools.LEGACY_POOLS and remain as a fallback for any data
# dict that predates / lacks a battler_id.

const BATTLER_DIR := "res://client/sprites/battlers/tf/"
const OVERWORLD_DIR := "res://client/sprites/battlers/overworld/"

# v0.9.671 — per-character identity tint. Two characters can share a battler id,
# so we wash each sprite with a gentle multiply tint derived from the character's
# already-rolled appearance_color (Crimson/Sunset/etc). Strength kept low so the
# sprite stays clearly readable — it's a cast, not a full recolor. Applied via
# self_modulate on sprite nodes (multiplies UNDER combat FX modulate) and via
# [img color=...] on the info/status/hover panels.
const TINT_STRENGTH := 0.35

static func tint_color(appearance_color: String) -> Color:
	"""Gentle multiply-tint for a sprite from the character's appearance_color.
	Empty/invalid/white -> Color.WHITE (no visible change)."""
	if appearance_color == "" or not appearance_color.is_valid_html_color():
		return Color.WHITE
	return Color.WHITE.lerp(Color.html(appearance_color), TINT_STRENGTH)

static func tint_hex(appearance_color: String) -> String:
	"""'#RRGGBB' form of tint_color, for [img color=#..] BBCode."""
	return "#" + tint_color(appearance_color).to_html(false)

static func has_battler(cls: String) -> bool:
	return BattlerPools.LEGACY_POOLS.has(cls) and not (BattlerPools.LEGACY_POOLS[cls] as Array).is_empty()

static func id_for(cls: String, char_name: String) -> String:
	"""Legacy live-derived id (frozen LEGACY_POOLS). Fallback only — prefer the
	stored character.battler_id via id_from_data()."""
	return BattlerPools.legacy_id_for(cls, char_name)

static func id_from_data(data) -> String:
	"""Resolve a character's battler id from a data dict: the STORED battler_id if
	present, else the legacy derivation from class+name."""
	if typeof(data) != TYPE_DICTIONARY:
		return ""
	var bid := str(data.get("battler_id", ""))
	if bid != "":
		return bid
	var cls := str(data.get("class", data.get("class_type", "")))
	return id_for(cls, str(data.get("name", "")))

# --- Idle textures / paths --------------------------------------------------

static func idle_path_by_id(id: String) -> String:
	if id == "":
		return ""
	return BATTLER_DIR + id + "/idle_0.png"

static func idle_path_resolved(battler_id: String, cls: String, char_name: String) -> String:
	"""idle_0 path preferring an explicit stored id, else legacy derivation."""
	var id := battler_id
	if id == "":
		id = id_for(cls, char_name)
	return idle_path_by_id(id)

static func idle_path(cls: String, char_name: String) -> String:
	return idle_path_by_id(id_for(cls, char_name))

static func idle_texture_by_id(id: String) -> Texture2D:
	var p := idle_path_by_id(id)
	if p == "" or not ResourceLoader.exists(p):
		return null
	return load(p) as Texture2D

static func idle_texture(cls: String, char_name: String) -> Texture2D:
	return idle_texture_by_id(id_for(cls, char_name))

# --- Overworld (4-direction) map avatars -----------------------------------
# Only battler ids on TimeFantasy sheets 2-5 have a matching top-down overworld
# sprite (tf/N_M == chara N_M). Ids on sheets 1/6/7 fall back to the side-view
# battler. Facing is "up"/"down"/"left"/"right"; overworld frames are native to
# each direction (no flip_h needed, unlike the side-view battlers).

static func has_overworld_by_id(id: String) -> bool:
	return id != "" and ResourceLoader.exists(OVERWORLD_DIR + id + "/down_stand.png")

static func has_overworld(cls: String, char_name: String) -> bool:
	return has_overworld_by_id(id_for(cls, char_name))

static func overworld_texture_by_id(id: String, facing: String, walk_frame: int = 0) -> Texture2D:
	"""Directional overworld sprite for an explicit id. walk_frame: 0 = stand,
	1/2 = walk cycle. Returns null if this id has no overworld twin."""
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

static func overworld_texture(cls: String, char_name: String, facing: String, walk_frame: int = 0) -> Texture2D:
	return overworld_texture_by_id(id_for(cls, char_name), facing, walk_frame)
