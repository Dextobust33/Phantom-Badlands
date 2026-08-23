class_name EquipmentMarkers
extends RefCounted

# v0.9.672 — per-equipped-piece visual markers on the character sprite.
#
# Each body-armor slot (helm / armor / boots) tints ITS region of the sprite a
# random (deterministic) colour when something is equipped there. Every equipped
# slot also has a rarity-scaled CHANCE of a small GLYPH — a random character, in a
# random colour, at a random orientation — placed on that slot's body anchor.
#
# Everything is seeded per-item so it's identical across sessions and every
# surface (combat / map / info / status / hover). markers_for() is the single
# source of truth; each surface renders the same data its own way.

# slot -> body region. band = normalized Y range for the region tint (empty =
# no region tint, e.g. weapon/ring — glyph only). anchor = normalized position
# for the glyph, in sprite-local space (0,0 top-left .. 1,1 bottom-right).
# Bands/anchors are tuned to the TF battler content, which sits ~y0.29..0.96 of
# the 48px frame (head starts ~29% down, feet ~96%), not the full 0..1 — so the
# top band lands on the helmet, not the empty headroom above it.
const SLOT_REGION := {
	"helm":   {"band": Vector2(0.28, 0.46), "anchor": Vector2(0.50, 0.36), "tint": true},
	"armor":  {"band": Vector2(0.46, 0.71), "anchor": Vector2(0.50, 0.58), "tint": true},
	"boots":  {"band": Vector2(0.71, 0.98), "anchor": Vector2(0.50, 0.85), "tint": true},
	"weapon": {"band": Vector2(0, 0), "anchor": Vector2(0.32, 0.62), "tint": false},
	"shield": {"band": Vector2(0, 0), "anchor": Vector2(0.68, 0.58), "tint": false},
	"amulet": {"band": Vector2(0, 0), "anchor": Vector2(0.50, 0.48), "tint": false},
	"ring":   {"band": Vector2(0, 0), "anchor": Vector2(0.36, 0.70), "tint": false},
}
# Render order for the 3 tintable body slots -> shader band index 0/1/2.
const TINT_SLOTS := ["helm", "armor", "boots"]

const GLYPH_POOL := "ABCDEFGHJKLMNPQRSTUVWXYZ0123456789@#$%&*+=?§"
const GLYPH_CHANCE_BY_RARITY := {
	"common": 0.08, "uncommon": 0.22, "rare": 0.42,
	"epic": 0.65, "legendary": 0.88, "mythic": 1.0, "unique": 1.0, "set": 1.0,
}
const REGION_TINT_STRENGTH := 0.45

const REGION_SHADER := preload("res://client/shaders/region_tint.gdshader")

static func build_tint_material(markers: Array) -> ShaderMaterial:
	"""ShaderMaterial with the region-tint bands set from the markers' tint
	entries (helm/armor/boots), or null if none are tinted. Assign to the sprite
	node's .material."""
	var bands := []
	for m in markers:
		if m.get("tint") != null:
			bands.append(m)
	if bands.is_empty():
		return null
	var mat := ShaderMaterial.new()
	mat.shader = REGION_SHADER
	for i in range(min(3, bands.size())):
		var m = bands[i]
		var band: Vector2 = m["region_band"]
		var col: Color = m["tint"]
		mat.set_shader_parameter("band%d" % i, Vector4(band.x, band.y, 0.0, 0.0))
		mat.set_shader_parameter("band%d_col" % i, Vector4(col.r, col.g, col.b, col.a))
	return mat

static func spawn_glyphs(parent: Control, markers: Array, font: Font, glyph_px: int) -> void:
	"""(Re)build glyph Labels as children of `parent`, positioned over the sprite
	by each marker's normalized anchor. Labels are NOT mirrored by TextureRect
	flip_h, so they read correctly. Call after `parent` has a size; re-call on
	resize. Idempotent — clears prior eq_glyph children first."""
	for ch in parent.get_children():
		if ch.has_meta("eq_glyph"):
			ch.queue_free()
	var sz: Vector2 = parent.size
	if sz.x <= 0.0 or sz.y <= 0.0:
		return
	var box := float(glyph_px) * 2.0
	for m in markers:
		if not m.get("has_glyph", false):
			continue
		var lbl := Label.new()
		lbl.set_meta("eq_glyph", true)
		lbl.text = str(m["glyph"])
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.size = Vector2(box, box)
		lbl.pivot_offset = Vector2(box, box) * 0.5
		lbl.rotation = float(m["glyph_rot"])
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.z_index = 6
		if font:
			lbl.add_theme_font_override("font", font)
		lbl.add_theme_font_size_override("font_size", glyph_px)
		lbl.add_theme_color_override("font_color", m["glyph_color"])
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		lbl.add_theme_constant_override("outline_size", maxi(2, glyph_px / 5))
		var anchor: Vector2 = m["anchor"]
		lbl.position = Vector2(anchor.x * sz.x, anchor.y * sz.y) - Vector2(box, box) * 0.5
		lbl.set_meta("eq_base_pos", lbl.position)  # for idle-bob sync
		parent.add_child(lbl)

static func _seed_for(item: Dictionary, slot: String) -> int:
	return abs(hash("%s|%s|%s|%s" % [
		str(item.get("name", "")), str(item.get("rarity", "")),
		slot, str(item.get("level", 0))]))

static func markers_for(equipped) -> Array:
	"""Returns a list of per-slot marker dicts:
	{ slot, anchor:Vector2, region_band:Vector2, tint (Color w/ a=strength) or null,
	  has_glyph:bool, glyph:String, glyph_color:Color, glyph_rot:float }"""
	var out := []
	if typeof(equipped) != TYPE_DICTIONARY:
		return out
	for slot in SLOT_REGION.keys():
		var item = equipped.get(slot, null)
		if item == null or not (item is Dictionary) or (item as Dictionary).is_empty():
			continue
		var reg = SLOT_REGION[slot]
		var rng := RandomNumberGenerator.new()
		rng.seed = _seed_for(item, slot)
		var entry := {
			"slot": slot,
			"anchor": reg["anchor"],
			"region_band": reg["band"],
			"tint": null,
			"has_glyph": false,
		}
		if reg["tint"]:
			var tc := Color.from_hsv(rng.randf(), rng.randf_range(0.55, 0.95), rng.randf_range(0.70, 1.0))
			tc.a = REGION_TINT_STRENGTH
			entry["tint"] = tc
		var rarity := str(item.get("rarity", "common")).to_lower()
		var chance := float(GLYPH_CHANCE_BY_RARITY.get(rarity, 0.08))
		if rng.randf() < chance:
			entry["has_glyph"] = true
			entry["glyph"] = GLYPH_POOL[rng.randi() % GLYPH_POOL.length()]
			entry["glyph_color"] = Color.from_hsv(rng.randf(), rng.randf_range(0.60, 1.0), rng.randf_range(0.85, 1.0))
			entry["glyph_rot"] = rng.randf_range(0.0, TAU)
		out.append(entry)
	return out
