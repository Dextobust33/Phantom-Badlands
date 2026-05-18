extends Control
class_name CraftRevealPanel

# Audit #4 Slice 3.5 — Unified Craft Summary panel.
# Replaces both the old reveal animation panel AND the trailing
# crafting-success text page. Shows the full transparent chain:
#   1. Boost commitment (None / Refined / Master) + material cost
#   2. Scratch-off reveals you actually pulled
#   3. How those reveals translated into a success-chance bonus
#   4. Final crafted item + quality + stats + XP gained
# Keeps a short quality-color flash on open as a feel beat but the
# substance is the readable breakdown.

signal dismissed
signal craft_again_requested

const MIN_HOLD_SEC := 0.4   # Brief feel-hold; substance is the focus.

const QUALITY_COLORS := {
	"Poor": Color(1, 1, 1),
	"Standard": Color(0, 1, 0),
	"Fine": Color(0, 0.44, 0.87),
	"Masterwork": Color(0.64, 0.21, 0.93),
}
const QUALITY_MULT_LABEL := {
	"Poor": "×0.5 stats",
	"Standard": "×1.0 stats",
	"Fine": "×1.25 stats",
	"Masterwork": "×1.5 stats",
}
const BOOST_TIER_DISPLAY := {
	"none":    {"label": "",                 "color": Color(0.75, 0.75, 0.75), "mult_pct": 0},
	"refined": {"label": "✦ REFINED ✦",      "color": Color(1.0, 0.67, 0.40),  "mult_pct": 50},
	"master":  {"label": "✦ MASTER ✦",       "color": Color(0.64, 0.21, 0.93), "mult_pct": 150},
}

var _root_panel: PanelContainer
var _root_stylebox: StyleBoxFlat
var _content: VBoxContainer
var _craft_again_button: Button
var _continue_button: Button

var _quality_color: Color = Color(0, 1, 0)
var _opened_at: float = 0.0
var _payload: Dictionary = {}
var _can_craft_again: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	_build_layout()
	visible = false


func _build_layout() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.65)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_root_panel = PanelContainer.new()
	_root_panel.custom_minimum_size = Vector2(560, 0)
	_root_stylebox = StyleBoxFlat.new()
	_root_stylebox.bg_color = Color(0.08, 0.06, 0.05, 0.99)
	_root_stylebox.border_color = Color(0.55, 0.45, 0.33, 1)
	_root_stylebox.set_border_width_all(2)
	_root_stylebox.set_corner_radius_all(8)
	_root_stylebox.content_margin_left = 18
	_root_stylebox.content_margin_top = 14
	_root_stylebox.content_margin_right = 18
	_root_stylebox.content_margin_bottom = 14
	_root_panel.add_theme_stylebox_override("panel", _root_stylebox)
	center.add_child(_root_panel)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 8)
	_root_panel.add_child(_content)

	# Button row built once; content body is rebuilt per-craft.
	# (We rebuild children of _content on each open() so the body can grow
	# / shrink based on which sections apply.)


func open(payload: Dictionary, can_craft_again: bool = false) -> void:
	"""Show the panel with the full craft breakdown.

	Reads the 'summary' sub-dict from the craft_result message:
	  boost_tier, boost_mat_mult, consumed_materials, scratch_awarded,
	  scratch_missed, best_score, score_bonus_pct,
	  effective_success_chance, refund_pct, duplicate_count,
	  tool_durability_pct, tool_efficiency_tier, is_tempered, temper_target
	plus the top-level fields (quality_name, quality_color, recipe_name,
	crafted_item, xp_gained, char_xp_gained, leveled_up, new_level,
	skill_name, specialist_save).
	"""
	_payload = payload
	_can_craft_again = can_craft_again
	_opened_at = Time.get_ticks_msec() / 1000.0
	visible = true
	modulate.a = 0.0

	# Resolve quality color (server hex wins).
	var qname := String(payload.get("quality_name", "Standard"))
	_quality_color = QUALITY_COLORS.get(qname, Color(0, 1, 0))
	var hex := String(payload.get("quality_color", ""))
	if hex.begins_with("#"):
		var parsed := Color(hex)
		if parsed != Color(0, 0, 0, 1) or hex.to_upper() == "#000000":
			_quality_color = parsed

	# Border tint matches the final quality.
	_root_stylebox.border_color = _quality_color

	_rebuild_content()

	# Brief fade-in tween — kept short because substance is what carries the
	# moment, not animation.
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 1.0, 0.20)


func _rebuild_content() -> void:
	# Clear and rebuild — sections vary per craft (no scratch reveals on
	# auto-skip, no temper banner unless tempered, etc.).
	for child in _content.get_children():
		child.queue_free()

	var summary: Dictionary = _payload.get("summary", {})
	var boost_tier: String = String(summary.get("boost_tier", "none"))
	var boost_info: Dictionary = BOOST_TIER_DISPLAY.get(boost_tier, BOOST_TIER_DISPLAY["none"])
	var recipe_name := String(_payload.get("recipe_name", "item"))
	var quality_name := String(_payload.get("quality_name", "Standard"))
	var crafted_item: Dictionary = _payload.get("crafted_item", {})

	# Header — boost tag + title.
	if boost_info["label"] != "":
		var boost_label := Label.new()
		boost_label.text = boost_info["label"]
		boost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		boost_label.add_theme_color_override("font_color", boost_info["color"])
		boost_label.add_theme_font_size_override("font_size", 14)
		_content.add_child(boost_label)

	var title := RichTextLabel.new()
	title.bbcode_enabled = true
	title.fit_content = true
	title.scroll_active = false
	title.add_theme_font_size_override("normal_font_size", 22)
	title.text = "[center][color=%s]%s %s[/color][/center]" % [_quality_color.to_html(false), quality_name, recipe_name]
	_content.add_child(title)

	# Quality multiplier subtitle (×0.5 / ×1.0 / ×1.25 / ×1.5).
	var mult_label := Label.new()
	mult_label.text = QUALITY_MULT_LABEL.get(quality_name, "")
	mult_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mult_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	mult_label.add_theme_font_size_override("font_size", 13)
	_content.add_child(mult_label)

	# Specialist save flourish (gold).
	if bool(_payload.get("specialist_save", false)):
		var save_label := Label.new()
		save_label.text = "★ Specialist Save — one tier higher! ★"
		save_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		save_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
		save_label.add_theme_font_size_override("font_size", 13)
		_content.add_child(save_label)

	# Separator.
	_content.add_child(_make_separator())

	# === Section 1: Materials Paid ===
	var consumed: Dictionary = summary.get("consumed_materials", {})
	var boost_mat_mult: float = float(summary.get("boost_mat_mult", 1.0))
	if not consumed.is_empty():
		var mat_header := Label.new()
		var mat_header_text := "Materials Paid"
		if boost_mat_mult > 1.0:
			mat_header_text += "  (×%.1f boost cost — +%d%%)" % [boost_mat_mult, int(round((boost_mat_mult - 1.0) * 100))]
		mat_header.text = mat_header_text
		mat_header.add_theme_color_override("font_color", Color(0.55, 0.81, 0.92))
		mat_header.add_theme_font_size_override("font_size", 13)
		_content.add_child(mat_header)

		var mat_lines: Array = []
		for mat_id in consumed.keys():
			var qty := int(consumed[mat_id])
			var nice := _format_material_name(String(mat_id))
			mat_lines.append("  • %s ×%d" % [nice, qty])
		var mat_body := Label.new()
		mat_body.text = "\n".join(mat_lines)
		mat_body.add_theme_color_override("font_color", Color(0.85, 0.75, 0.65))
		mat_body.add_theme_font_size_override("font_size", 12)
		_content.add_child(mat_body)

	# === Section 2: Scratch-off Reveals ===
	var is_tool_recipe: bool = bool(summary.get("is_tool_recipe", false))
	var awarded: Array = summary.get("scratch_awarded", [])
	var missed: Array = summary.get("scratch_missed", [])
	if not awarded.is_empty() or not missed.is_empty():
		_content.add_child(_make_separator())
		var sc_header := Label.new()
		sc_header.text = "Scratch-Off Reveals"
		sc_header.add_theme_color_override("font_color", Color(0.55, 0.81, 0.92))
		sc_header.add_theme_font_size_override("font_size", 13)
		_content.add_child(sc_header)

		if awarded.is_empty():
			var none_label := Label.new()
			none_label.text = "  (no slots revealed — pure base roll)"
			none_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
			none_label.add_theme_font_size_override("font_size", 12)
			_content.add_child(none_label)
		else:
			var sc_body := RichTextLabel.new()
			sc_body.bbcode_enabled = true
			sc_body.fit_content = true
			sc_body.scroll_active = false
			sc_body.add_theme_font_size_override("normal_font_size", 12)
			sc_body.text = _format_reveal_lines(awarded, is_tool_recipe)
			_content.add_child(sc_body)

	# === Section 3: Roll math — show the actual roll vs threshold bands ===
	var best_score := int(summary.get("best_score", -1))
	var distribution: Dictionary = summary.get("distribution", {})
	var bands: Dictionary = summary.get("bands", {})
	var roll_value := int(summary.get("roll", -1))
	if best_score >= 0 or not distribution.is_empty():
		_content.add_child(_make_separator())
		var chain_header := Label.new()
		chain_header.text = "How the Roll Worked"
		chain_header.add_theme_color_override("font_color", Color(0.55, 0.81, 0.92))
		chain_header.add_theme_font_size_override("font_size", 13)
		_content.add_child(chain_header)

		var bonus_pct := int(summary.get("score_bonus_pct", 0))
		var success_chance := int(summary.get("effective_success_chance", 50))
		var score_label := "no reveals (score 0)"
		if best_score > 0:
			score_label = "best score %d from your reveals" % best_score

		var chain_body := RichTextLabel.new()
		chain_body.bbcode_enabled = true
		chain_body.fit_content = true
		chain_body.scroll_active = false
		chain_body.add_theme_font_size_override("normal_font_size", 12)
		var lines: Array = []
		lines.append("  • Reveal score: [color=#FFFFFF]%s[/color] → adds [color=#FFFFFF]+%d%%[/color] to base success chance" % [score_label, bonus_pct])
		lines.append("  • Effective success chance after skill/boost/score: [color=#FFFFFF]%d%%[/color]" % success_chance)
		# Threshold bands (only show populated ones).
		if not distribution.is_empty():
			var band_parts: Array = []
			for k in ["poor", "standard", "fine", "masterwork"]:
				var pct := int(distribution.get(k, 0))
				if pct <= 0:
					continue
				var color := "#FFFFFF"
				match k:
					"poor": color = "#FFFFFF"
					"standard": color = "#00FF00"
					"fine": color = "#0070DD"
					"masterwork": color = "#A335EE"
				if bands.has(k):
					var lh: Array = bands[k]
					if lh.size() >= 2 and int(lh[0]) >= 0:
						band_parts.append("[color=%s]%s %d%% (rolls %d–%d)[/color]" % [color, k.capitalize(), pct, int(lh[0]), int(lh[1])])
						continue
				band_parts.append("[color=%s]%s %d%%[/color]" % [color, k.capitalize(), pct])
			if not band_parts.is_empty():
				lines.append("  • Quality bands: %s" % "  ".join(band_parts))
		# Actual roll outcome.
		if roll_value >= 0:
			lines.append("  • Rolled [color=#FFD700]%d[/color] out of 100 → lands in [color=%s]%s[/color] band" % [roll_value, _quality_color.to_html(false), quality_name])
		else:
			lines.append("  • Result: [color=%s]%s[/color]" % [_quality_color.to_html(false), quality_name])
		chain_body.text = "\n".join(lines)
		_content.add_child(chain_body)

	# === Section 4: Bonus effects applied (refund / duplicate / tool bonuses) ===
	# Concrete descriptions only — abstract numbers like "efficiency tier 1"
	# get unpacked into "rhythm bar X% slower, hit zone X% wider".
	var bonus_lines: Array = []
	var refund_pct := int(summary.get("refund_pct", 0))
	var duplicate_count := int(summary.get("duplicate_count", 0))
	var tool_dur := int(summary.get("tool_durability_pct", 0))
	var tool_eff := int(summary.get("tool_efficiency_tier", 0))
	if refund_pct > 0:
		bonus_lines.append("  [color=#88FF88]• %d%% of consumed materials refunded to your pouch[/color]" % refund_pct)
	if duplicate_count > 0:
		bonus_lines.append("  [color=#88FF88]• +%d extra copies crafted[/color]" % duplicate_count)
	if tool_dur > 0 and is_tool_recipe:
		bonus_lines.append("  [color=#88FF88]• +%d%% durability on the tool — lasts longer before breaking[/color]" % tool_dur)
	if tool_eff > 0 and is_tool_recipe:
		var spd_pct := 5 if tool_eff == 1 else 10
		var wid_pct := 15 if tool_eff == 1 else 30
		bonus_lines.append("  [color=#88FF88]• Gathering minigame easier when using this tool — −%d%% rhythm bar speed, +%d%% wider hit zone[/color]" % [spd_pct, wid_pct])
	if not bonus_lines.is_empty():
		_content.add_child(_make_separator())
		var bonus_body := RichTextLabel.new()
		bonus_body.bbcode_enabled = true
		bonus_body.fit_content = true
		bonus_body.scroll_active = false
		bonus_body.add_theme_font_size_override("normal_font_size", 12)
		bonus_body.text = "[color=#87CEEB]Bonuses Applied:[/color]\n%s" % "\n".join(bonus_lines)
		_content.add_child(bonus_body)

	# === Section 5: Item stats ===
	if not crafted_item.is_empty():
		var stat_parts: Array = []
		if crafted_item.has("attack"): stat_parts.append("[color=#FF4444]ATK %d[/color]" % int(crafted_item.attack))
		if crafted_item.has("defense"): stat_parts.append("[color=#4444FF]DEF %d[/color]" % int(crafted_item.defense))
		if crafted_item.has("hp"): stat_parts.append("[color=#00FF00]HP %d[/color]" % int(crafted_item.hp))
		if crafted_item.has("speed"): stat_parts.append("[color=#FFFF00]SPD %d[/color]" % int(crafted_item.speed))
		if crafted_item.has("mana"): stat_parts.append("[color=#00BFFF]MP %d[/color]" % int(crafted_item.mana))
		if not stat_parts.is_empty():
			_content.add_child(_make_separator())
			var stats := RichTextLabel.new()
			stats.bbcode_enabled = true
			stats.fit_content = true
			stats.scroll_active = false
			stats.add_theme_font_size_override("normal_font_size", 13)
			stats.text = "[color=#87CEEB]Stats:[/color]  " + "    ".join(stat_parts)
			_content.add_child(stats)

	# === Section 6: XP ===
	var xp_gained := int(_payload.get("xp_gained", 0))
	var char_xp := int(_payload.get("char_xp_gained", 0))
	var skill_name := String(_payload.get("skill_name", "crafting"))
	if xp_gained > 0 or char_xp > 0:
		_content.add_child(_make_separator())
		var xp := RichTextLabel.new()
		xp.bbcode_enabled = true
		xp.fit_content = true
		xp.scroll_active = false
		xp.add_theme_font_size_override("normal_font_size", 12)
		var xp_parts: Array = []
		if xp_gained > 0:
			xp_parts.append("[color=#00BFFF]+%d %s XP[/color]" % [xp_gained, skill_name.capitalize()])
		if char_xp > 0:
			xp_parts.append("[color=#FF00FF]+%d XP[/color]" % char_xp)
		if bool(_payload.get("leveled_up", false)):
			xp_parts.append("[color=#FFFF00]★ %s Lv %d[/color]" % [skill_name.capitalize(), int(_payload.get("new_level", 0))])
		xp.text = "    ".join(xp_parts)
		_content.add_child(xp)

	# === Buttons ===
	_content.add_child(_make_separator())
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	_content.add_child(btn_row)

	if _can_craft_again:
		_craft_again_button = Button.new()
		_craft_again_button.text = "Craft Again (Q)"
		_craft_again_button.focus_mode = Control.FOCUS_NONE
		_craft_again_button.custom_minimum_size = Vector2(160, 32)
		_craft_again_button.pressed.connect(_on_craft_again_pressed)
		btn_row.add_child(_craft_again_button)

	_continue_button = Button.new()
	_continue_button.text = "Continue (Space)"
	_continue_button.focus_mode = Control.FOCUS_NONE
	_continue_button.custom_minimum_size = Vector2(160, 32)
	_continue_button.pressed.connect(_on_continue_pressed)
	btn_row.add_child(_continue_button)


func _make_separator() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	return sep


func _format_reveal_lines(awarded: Array, is_tool_recipe: bool) -> String:
	"""Render each awarded slot with its concrete gameplay effect.
	Quality cards: granted score (feeds success_chance, fed roll bands).
	Tool bonus cards: only meaningful on tool recipes — describe the
	specific gathering-minigame change so 'Efficiency Tier +1' isn't
	an abstract number."""
	var lines: Array = []
	for slot in awarded:
		var kind := String(slot.get("kind", "BASE"))
		var name := String(slot.get("name", ""))
		var effect := ""
		match kind:
			"DURABILITY_UP_1":
				if is_tool_recipe:
					effect = "[color=#88FF88]+25% durability — tool lasts longer before breaking[/color]"
				else:
					effect = "[color=#888888]+25% durability (no effect on non-tool recipes)[/color]"
			"DURABILITY_UP_2":
				if is_tool_recipe:
					effect = "[color=#88FF88]+50% durability — tool lasts much longer before breaking[/color]"
				else:
					effect = "[color=#888888]+50% durability (no effect on non-tool recipes)[/color]"
			"EFFICIENCY_UP_1":
				if is_tool_recipe:
					effect = "[color=#88FF88]Easier gathering minigame — −5% rhythm bar speed, +15% wider hit zone when you use this tool[/color]"
				else:
					effect = "[color=#888888]Easier minigame (no effect on non-tool recipes)[/color]"
			"EFFICIENCY_UP_2":
				if is_tool_recipe:
					effect = "[color=#88FF88]Much easier gathering minigame — −10% rhythm bar speed, +30% wider hit zone when you use this tool[/color]"
				else:
					effect = "[color=#888888]Much easier minigame (no effect on non-tool recipes)[/color]"
			"REFUND":
				effect = "[color=#88FF88]+25% of consumed materials refunded to your pouch[/color]"
			"DUPLICATE":
				effect = "[color=#88FF88]+1 extra copy of this craft[/color]"
			"DUPLICATE_2":
				effect = "[color=#88FF88]+2 extra copies of this craft[/color]"
			"DUPLICATE_3":
				effect = "[color=#88FF88]+3 extra copies of this craft[/color]"
			"BASE":
				effect = "[color=#FFFFFF]Standard slot → score 1 (+15% success chance)[/color]"
			"QUALITY_UP_1":
				effect = "[color=#00FF00]Refined slot → score 1 (+15% success chance)[/color]"
			"QUALITY_UP_2":
				effect = "[color=#0070DD]Polished slot → score 2 (+30% success chance)[/color]"
			"QUALITY_UP_3":
				effect = "[color=#A335EE]Masterful slot → score 3 (+45% success chance)[/color]"
			"DUD":
				effect = "[color=#666666]Empty slot — no effect[/color]"
			_:
				effect = "[color=#888888]%s[/color]" % name
		lines.append("  ✓ %s" % effect)
	return "\n".join(lines)


func _format_material_name(mat_id: String) -> String:
	if mat_id.begins_with("@"):
		# Group key like @attack:minor — display the readable form.
		var parts := mat_id.substr(1).split(":")
		if parts.size() >= 1:
			return parts[0].capitalize() + " parts"
		return mat_id
	return mat_id.capitalize().replace("_", " ")


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventKey):
		return
	if not event.pressed:
		return
	# Q = Craft Again (if available), Space/Enter/Escape = Continue.
	if event.keycode == KEY_Q and _can_craft_again:
		_try_craft_again()
		get_viewport().set_input_as_handled()
		return
	if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
		_try_continue()
		get_viewport().set_input_as_handled()


func _on_continue_pressed() -> void:
	_try_continue()


func _on_craft_again_pressed() -> void:
	_try_craft_again()


func _try_continue() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _opened_at < MIN_HOLD_SEC:
		return
	close()


func _try_craft_again() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _opened_at < MIN_HOLD_SEC:
		return
	visible = false
	emit_signal("craft_again_requested")


func close() -> void:
	visible = false
	emit_signal("dismissed")
