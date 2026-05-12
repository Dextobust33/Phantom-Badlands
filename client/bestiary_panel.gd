extends Control
class_name BestiaryPanel

# Audit #13 Slice 2 — visual Bestiary. Account-level ledger of monster kills.
# Three reveal tiers via the `bestiary` house upgrade:
#   L1 — kill count
#   L2 — kill count + highest level killed
#   L3 — kill count + highest level + first/last killed dates
# When locked (L0), the panel shows a teaser + a hint pointing at the
# Sanctuary upgrade page.

signal close_requested

var _root_panel: PanelContainer
var _header_label: RichTextLabel
var _summary_label: RichTextLabel
var _body_scroll: ScrollContainer
var _body_vbox: VBoxContainer
var _empty_label: RichTextLabel

var _summary: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_layout()
	visible = false


func open(summary: Dictionary) -> void:
	refresh(summary)
	visible = true


func close() -> void:
	visible = false


func refresh(summary: Dictionary) -> void:
	_summary = summary.duplicate(true) if summary is Dictionary else {}
	_render_body()


func _build_layout() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)

	_root_panel = PanelContainer.new()
	_root_panel.custom_minimum_size = Vector2(620, 540)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.05, 0.04, 0.97)
	sb.border_color = Color(0.85, 0.65, 0.27, 1)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 16
	sb.content_margin_top = 14
	sb.content_margin_right = 16
	sb.content_margin_bottom = 14
	_root_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_root_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_root_panel.add_child(vbox)

	# Title row
	var title_hbox := HBoxContainer.new()
	title_hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(title_hbox)

	var title_label := Label.new()
	title_label.text = "Bestiary"
	title_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.27))
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_hbox.add_child(title_label)

	var close_btn := Button.new()
	close_btn.text = "✕ Close"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): close_requested.emit())
	title_hbox.add_child(close_btn)

	_header_label = RichTextLabel.new()
	_header_label.bbcode_enabled = true
	_header_label.fit_content = true
	_header_label.scroll_active = false
	_header_label.add_theme_font_size_override("normal_font_size", 13)
	_header_label.custom_minimum_size = Vector2(0, 22)
	vbox.add_child(_header_label)

	_summary_label = RichTextLabel.new()
	_summary_label.bbcode_enabled = true
	_summary_label.fit_content = true
	_summary_label.scroll_active = false
	_summary_label.add_theme_font_size_override("normal_font_size", 12)
	_summary_label.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(_summary_label)

	_empty_label = RichTextLabel.new()
	_empty_label.bbcode_enabled = true
	_empty_label.fit_content = true
	_empty_label.scroll_active = false
	_empty_label.add_theme_font_size_override("normal_font_size", 12)
	_empty_label.custom_minimum_size = Vector2(0, 60)
	_empty_label.visible = false
	vbox.add_child(_empty_label)

	_body_scroll = ScrollContainer.new()
	_body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_scroll.custom_minimum_size = Vector2(0, 400)
	vbox.add_child(_body_scroll)

	_body_vbox = VBoxContainer.new()
	_body_vbox.add_theme_constant_override("separation", 2)
	_body_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_scroll.add_child(_body_vbox)


func _render_body() -> void:
	for child in _body_vbox.get_children():
		child.queue_free()

	var level: int = int(_summary.get("level", 0))
	var entries: Array = _summary.get("entries", [])
	var unique_count: int = int(_summary.get("unique_count", 0))
	var total_kills: int = int(_summary.get("total_kills", 0))

	# Header line — total kills + unique species, gated by level.
	_header_label.clear()
	_header_label.append_text("[color=#FFD700]Account Hunting Ledger[/color]")

	_summary_label.clear()
	if level <= 0:
		_summary_label.append_text("[color=#FF8800]Bestiary upgrade not yet unlocked.[/color]  [color=#888888](Buy in Sanctuary → Upgrades → Base)[/color]")
	else:
		var tier_label = ["", "L1: kill counts", "L2: + highest level", "L3: + dates"][min(level, 3)]
		_summary_label.append_text("[color=#88FF88]Unlocked: %s[/color]   [color=#A0A0A0]%d species · %d total kills[/color]" % [tier_label, unique_count, total_kills])

	if level <= 0:
		# Locked teaser body
		_empty_label.visible = true
		_empty_label.clear()
		_empty_label.append_text("[color=#A0A0A0]Once unlocked, every monster you kill is recorded against your account and survives permadeath. Unlock to peek at the data you've already been accumulating.[/color]")
		return

	if entries.is_empty():
		_empty_label.visible = true
		_empty_label.clear()
		_empty_label.append_text("[color=#A0A0A0]No monsters killed yet. Get out there.[/color]")
		return

	_empty_label.visible = false

	for e_var in entries:
		if not (e_var is Dictionary):
			continue
		var entry: Dictionary = e_var
		_body_vbox.add_child(_make_row(entry, level))


func _make_row(entry: Dictionary, level: int) -> Control:
	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.08, 0.06, 0.85)
	sb.border_color = Color(0.30, 0.25, 0.18, 1)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 10
	sb.content_margin_top = 4
	sb.content_margin_right = 10
	sb.content_margin_bottom = 4
	row.add_theme_stylebox_override("panel", sb)

	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.add_theme_font_size_override("normal_font_size", 12)
	label.custom_minimum_size = Vector2(0, 18)

	var name: String = String(entry.get("name", "(unknown)"))
	var kills: int = int(entry.get("kills", 0))
	var parts: PackedStringArray = PackedStringArray()
	parts.append("[color=#DDDDDD]%s[/color]" % name)
	parts.append("[color=#FFD700]× %d[/color]" % kills)
	if level >= 2:
		parts.append("[color=#88B8FF]Lv %d top[/color]" % int(entry.get("highest_level", 0)))
	if level >= 3:
		var first_ts: int = int(entry.get("first_killed_at", 0))
		var last_ts: int = int(entry.get("last_killed_at", 0))
		parts.append("[color=#888888]first %s · last %s[/color]" % [_fmt_date(first_ts), _fmt_date(last_ts)])
	label.text = "  ".join(parts)
	row.add_child(label)
	return row


func _fmt_date(ts: int) -> String:
	if ts <= 0:
		return "—"
	var d = Time.get_datetime_dict_from_unix_time(ts)
	return "%04d-%02d-%02d" % [int(d.get("year", 0)), int(d.get("month", 0)), int(d.get("day", 0))]
