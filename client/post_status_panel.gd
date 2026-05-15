extends Control
class_name PostStatusPanel

# Audit #12 UI remediation — visual post status panel.
# Replaces the chat-command-only `/post` and `/feedall` interfaces (v0.9.328
# + v0.9.329) per the "no chat-command-first features" hard rule. Server
# pushes structured `post_status_data` messages; this panel renders them.
# /post and /feedall keep working as power-user shortcuts.

signal close_requested
signal feed_all_requested

var _root_panel: PanelContainer
var _vbox: VBoxContainer
var _header_label: RichTextLabel
var _bubble_label: RichTextLabel
var _empty_label: RichTextLabel
var _guards_section: VBoxContainer
var _guards_title: RichTextLabel
var _guards_list_vbox: VBoxContainer
var _threat_label: RichTextLabel
var _inactivity_label: RichTextLabel
var _feed_button: Button
var _feed_hint_label: RichTextLabel

var _last_data: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_layout()
	visible = false


func open(data: Dictionary) -> void:
	refresh(data)
	visible = true


func close() -> void:
	visible = false


func refresh(data: Dictionary) -> void:
	_last_data = data.duplicate() if data is Dictionary else {}
	_render()


func _build_layout() -> void:
	# Dim backdrop
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	# Centered panel
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)

	_root_panel = PanelContainer.new()
	_root_panel.custom_minimum_size = Vector2(540, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.08, 0.05, 0.97)
	sb.border_color = Color(0.55, 0.85, 0.45, 1)  # Green border (post / settlement)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 16
	sb.content_margin_top = 14
	sb.content_margin_right = 16
	sb.content_margin_bottom = 14
	_root_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_root_panel)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 8)
	_root_panel.add_child(_vbox)

	# Title row
	var title_hbox := HBoxContainer.new()
	title_hbox.add_theme_constant_override("separation", 8)
	_vbox.add_child(title_hbox)

	_header_label = RichTextLabel.new()
	_header_label.bbcode_enabled = true
	_header_label.fit_content = true
	_header_label.scroll_active = false
	_header_label.add_theme_font_size_override("normal_font_size", 18)
	_header_label.custom_minimum_size = Vector2(0, 26)
	_header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_hbox.add_child(_header_label)

	var close_btn := Button.new()
	close_btn.text = "✕ Close"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): close_requested.emit())
	title_hbox.add_child(close_btn)

	# Empty-state line (shown when not at any post)
	_empty_label = RichTextLabel.new()
	_empty_label.bbcode_enabled = true
	_empty_label.fit_content = true
	_empty_label.scroll_active = false
	_empty_label.add_theme_font_size_override("normal_font_size", 13)
	_empty_label.custom_minimum_size = Vector2(0, 24)
	_vbox.add_child(_empty_label)

	# Bubble info line
	_bubble_label = RichTextLabel.new()
	_bubble_label.bbcode_enabled = true
	_bubble_label.fit_content = true
	_bubble_label.scroll_active = false
	_bubble_label.add_theme_font_size_override("normal_font_size", 13)
	_bubble_label.custom_minimum_size = Vector2(0, 22)
	_vbox.add_child(_bubble_label)

	# Threat banner (visible only when threatened)
	_threat_label = RichTextLabel.new()
	_threat_label.bbcode_enabled = true
	_threat_label.fit_content = true
	_threat_label.scroll_active = false
	_threat_label.add_theme_font_size_override("normal_font_size", 13)
	_threat_label.custom_minimum_size = Vector2(0, 22)
	_vbox.add_child(_threat_label)

	# Audit #12 Slice 4 — inactivity line (always visible when at a post).
	# Shows "Last tended: Xd ago" plus an Inactive (7d) or Abandoned (30d) tag.
	_inactivity_label = RichTextLabel.new()
	_inactivity_label.bbcode_enabled = true
	_inactivity_label.fit_content = true
	_inactivity_label.scroll_active = false
	_inactivity_label.add_theme_font_size_override("normal_font_size", 12)
	_inactivity_label.custom_minimum_size = Vector2(0, 18)
	_vbox.add_child(_inactivity_label)

	# Guards section (visible only for owners with guards)
	_guards_section = VBoxContainer.new()
	_guards_section.add_theme_constant_override("separation", 4)
	_vbox.add_child(_guards_section)

	_guards_title = RichTextLabel.new()
	_guards_title.bbcode_enabled = true
	_guards_title.fit_content = true
	_guards_title.scroll_active = false
	_guards_title.add_theme_font_size_override("normal_font_size", 13)
	_guards_title.custom_minimum_size = Vector2(0, 20)
	_guards_section.add_child(_guards_title)

	_guards_list_vbox = VBoxContainer.new()
	_guards_list_vbox.add_theme_constant_override("separation", 2)
	_guards_section.add_child(_guards_list_vbox)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	_vbox.add_child(spacer)

	# Feed All button row
	var feed_hbox := HBoxContainer.new()
	feed_hbox.add_theme_constant_override("separation", 10)
	_vbox.add_child(feed_hbox)

	_feed_button = Button.new()
	_feed_button.text = "Feed All Guards"
	_feed_button.focus_mode = Control.FOCUS_NONE
	_feed_button.custom_minimum_size = Vector2(160, 36)
	_feed_button.pressed.connect(func(): feed_all_requested.emit())
	feed_hbox.add_child(_feed_button)

	_feed_hint_label = RichTextLabel.new()
	_feed_hint_label.bbcode_enabled = true
	_feed_hint_label.fit_content = true
	_feed_hint_label.scroll_active = false
	_feed_hint_label.add_theme_font_size_override("normal_font_size", 12)
	_feed_hint_label.custom_minimum_size = Vector2(0, 18)
	_feed_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	feed_hbox.add_child(_feed_hint_label)


func _render() -> void:
	var at_post: bool = bool(_last_data.get("at_post", false))

	if not at_post:
		_header_label.clear()
		_header_label.append_text("[color=#88AA88]Post Status[/color]")
		_empty_label.visible = true
		_empty_label.clear()
		_empty_label.append_text("[color=#888888]Stand inside a player post to view its status. Walking onto the center of one of your own posts also auto-displays this panel.[/color]")
		_bubble_label.visible = false
		_threat_label.visible = false
		_inactivity_label.visible = false
		_guards_section.visible = false
		_feed_button.visible = false
		_feed_hint_label.visible = false
		return

	_empty_label.visible = false
	var post_name: String = String(_last_data.get("post_name", "[unnamed]"))
	var owner: String = String(_last_data.get("owner", ""))
	var is_owner: bool = bool(_last_data.get("is_owner", false))
	var bubble_radius: int = int(_last_data.get("bubble_radius", 0))
	var eff_tier: int = int(_last_data.get("effective_tier", 1))
	var wild_tier: int = int(_last_data.get("wilderness_tier", 1))
	var guard_count: int = int(_last_data.get("guard_count", 0))
	var tower_count: int = int(_last_data.get("tower_count", 0))
	var guards: Array = _last_data.get("guards", [])
	var threat: Dictionary = _last_data.get("threat", {})
	var feedall: Dictionary = _last_data.get("feedall", {})

	# Header
	_header_label.clear()
	if is_owner:
		_header_label.append_text("[color=#9AFF9A]─── %s ───[/color]" % post_name)
	else:
		_header_label.append_text("[color=#A0C8E0]─── %s ───[/color]   [color=#888888](owner: %s)[/color]" % [post_name, owner])

	# Bubble line
	_bubble_label.visible = true
	_bubble_label.clear()
	var tier_part: String = "T%d" % eff_tier
	if eff_tier < wild_tier:
		tier_part = "T%d  [color=#888888](wild T%d)[/color]" % [eff_tier, wild_tier]
	var guard_summary: String = "Guards: %d" % guard_count
	if tower_count > 0:
		guard_summary += "  [color=#A0C8E0](%d towered)[/color]" % tower_count
	_bubble_label.append_text("Bubble: r=%d   %s   %s" % [bubble_radius, tier_part, guard_summary])

	# Threat banner
	if threat.get("threatened", false):
		_threat_label.visible = true
		_threat_label.clear()
		var threat_color: String = String(threat.get("color", "#FF6644"))
		_threat_label.append_text("[color=%s]⚠ Under Threat: %s (T%d, %d tiles %s)[/color]" % [
			threat_color,
			String(threat.get("dungeon_name", "?")),
			int(threat.get("tier", 0)),
			int(threat.get("distance", 0)),
			String(threat.get("direction", "nearby")),
		])
		# Audit #11 Slice 11 — threat weakens bubble suppression by 1.
		if bool(threat.get("suppression_weakened", false)):
			_threat_label.append_text("\n[color=#FFAA44]    Bubble suppression weakened (-1) while threatened[/color]")
	else:
		_threat_label.visible = false

	# Audit #12 Slice 4 — inactivity line (always visible at a post).
	_inactivity_label.visible = true
	_inactivity_label.clear()
	var days_inactive: float = float(_last_data.get("days_inactive", 0.0))
	var inactivity_state: String = String(_last_data.get("inactivity_state", "active"))
	var tend_color: String = "#88FF88"
	var tend_tag: String = ""
	match inactivity_state:
		"abandoned":
			tend_color = "#FF4444"
			tend_tag = "   [color=#FF4444]⚠⚠ ABANDONED[/color]"
		"inactive":
			tend_color = "#FFAA44"
			tend_tag = "   [color=#FFAA44]⚠ Inactive[/color]"
	_inactivity_label.append_text("[color=%s]Last tended: %.1f days ago[/color]%s" % [tend_color, days_inactive, tend_tag])

	# Per-guard list (owner only)
	if is_owner and guards.size() > 0:
		_guards_section.visible = true
		_guards_title.clear()
		_guards_title.append_text("[color=#A0C8E0]Guards (food days remaining):[/color]")
		for child in _guards_list_vbox.get_children():
			child.queue_free()
		for g in guards:
			var compass: String = String(g.get("compass", "·"))
			var in_tower: bool = bool(g.get("in_tower", false))
			var days: float = float(g.get("food_days", 0.0))
			var tower_tag: String = "  [color=#A0C8E0](tower)[/color]" if in_tower else ""
			var food_tag: String = ""
			if days < 2.0:
				food_tag = "  [color=#FF6644][LOW][/color]"
			elif days < 4.0:
				food_tag = "  [color=#FFAA44][thin][/color]"
			var line := RichTextLabel.new()
			line.bbcode_enabled = true
			line.fit_content = true
			line.scroll_active = false
			line.add_theme_font_size_override("normal_font_size", 12)
			line.custom_minimum_size = Vector2(0, 18)
			line.append_text("    [color=#C0C0C0]%s[/color]%s   food: [color=#FFFFFF]%.1f days[/color]%s" % [compass, tower_tag, days, food_tag])
			_guards_list_vbox.add_child(line)
	else:
		_guards_section.visible = false

	# Feed All button + hint (owner only)
	if is_owner and not feedall.is_empty():
		var feedable: int = int(feedall.get("feedable", 0))
		var food_needed: int = int(feedall.get("food_needed", 0))
		var food_on_hand: int = int(feedall.get("food_on_hand", 0))
		if feedable > 0:
			_feed_button.visible = true
			_feed_hint_label.visible = true
			_feed_button.disabled = food_on_hand < food_needed
			_feed_button.text = "Feed All (%d guard%s)" % [feedable, "" if feedable == 1 else "s"]
			_feed_hint_label.clear()
			var afford_color: String = "#88FF88" if food_on_hand >= food_needed else "#FF8800"
			_feed_hint_label.append_text("  [color=%s]need %d food, have %d[/color]" % [afford_color, food_needed, food_on_hand])
		else:
			_feed_button.visible = false
			_feed_hint_label.visible = true
			_feed_hint_label.clear()
			_feed_hint_label.append_text("[color=#888888]All guards at food cap.[/color]")
	else:
		_feed_button.visible = false
		_feed_hint_label.visible = false
