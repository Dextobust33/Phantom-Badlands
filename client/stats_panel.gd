extends Control
class_name StatsPanel

# Audit #3 Slice 1 / UI remediation — visual stat allocation panel.
# Replaces the chat-command-only `/stats` + `/spendstat <stat>` interface
# (v0.9.335) which was un-discoverable per the "no chat-command-first
# features" hard rule.
#
# Pattern mirrors stones_panel.gd: dim backdrop + centered PanelContainer,
# header row (level / XP / unspent bank), 6 stat rows with [+1] button.
# Click a [+1] button → emits spend_requested(stat_name) which client.gd
# dispatches via the existing spend_stat_point server message.
# /stats and /spendstat keep working as power-user shortcuts.

signal close_requested
signal spend_requested(stat_name: String)
signal paths_requested  # ⚜ Paths button — opens the Path of the Badlands panel

const STAT_ORDER: Array = ["strength", "constitution", "dexterity", "intelligence", "wisdom", "wits"]
# 2026-09-04 — these read from the code, not from intent. The old DEX line said "Trickster
# damage", which is simply false: DEX appears nowhere in any damage formula. Trickster ability
# damage scales on WITS (_ability_anchored_damage is called with "wits" for ambush and gambit,
# with "strength" for the five warrior cards and "intelligence" for the four mage ones —
# "dexterity" is never passed). The old WIS line promised "mana efficiency"; no wisdom-based
# cost reduction exists anywhere in the codebase. Players were being pointed at the wrong stat.
const STAT_INFO: Dictionary = {
	"strength": {"label": "Strength", "abbr": "STR", "desc": "Attack power, all classes. Warrior abilities. Stamina.", "color": "#FF6B5A"},
	"constitution": {"label": "Constitution", "abbr": "CON", "desc": "Maximum HP and defense. Boosts stamina pool.", "color": "#6BFF6B"},
	"dexterity": {"label": "Dexterity", "abbr": "DEX", "desc": "Hit chance, crit, dodge, initiative, flee. Energy.", "color": "#6BD5FF"},
	"intelligence": {"label": "Intelligence", "abbr": "INT", "desc": "Mage ability damage. Boosts mana pool.", "color": "#A56BFF"},
	"wisdom": {"label": "Wisdom", "abbr": "WIS", "desc": "Backs INT for mage damage. Mana pool. Resistance.", "color": "#FFD56B"},
	"wits": {"label": "Wits", "abbr": "WITS", "desc": "Trickster ability damage. Outsmart. Energy pool.", "color": "#FF9ECB"},
}

var _root_panel: PanelContainer
var _vbox: VBoxContainer
var _header_label: RichTextLabel

# v0.9.503 — reusable HelpPanel attached to the header ? Help button.
var _help_panel: Control = null
var _bank_label: RichTextLabel
var _row_container: VBoxContainer

var _level: int = 1
var _experience: int = 0
var _experience_to_next: int = 100
var _stats: Dictionary = {}
var _unspent: int = 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_layout()
	visible = false


func open(level: int, xp: int, xp_to_next: int, stats: Dictionary, unspent: int) -> void:
	refresh(level, xp, xp_to_next, stats, unspent)
	visible = true


func close() -> void:
	visible = false


func refresh(level: int, xp: int, xp_to_next: int, stats: Dictionary, unspent: int) -> void:
	_level = level
	_experience = xp
	_experience_to_next = xp_to_next
	_stats = stats.duplicate() if stats is Dictionary else {}
	_unspent = unspent
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
	_root_panel.custom_minimum_size = Vector2(520, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.09, 0.97)
	sb.border_color = Color(0.40, 0.65, 0.85, 1)  # Blue border (character / progression)
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

	var title_label := Label.new()
	title_label.text = "Character Stats"
	title_label.add_theme_color_override("font_color", Color(0.55, 0.82, 0.97))
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_hbox.add_child(title_label)

	# Paths (ARPG pillar 3) — entry point to the skill tree panel. Lives here
	# because the Stats panel is the character-building surface (UI-buttons-
	# over-hotkeys rule; More menu is full).
	var paths_btn := Button.new()
	paths_btn.text = "⚜ Paths"
	paths_btn.focus_mode = Control.FOCUS_NONE
	paths_btn.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
	paths_btn.tooltip_text = "Path of the Badlands — spend Path points on permanent talents"
	paths_btn.pressed.connect(func(): paths_requested.emit())
	title_hbox.add_child(paths_btn)

	# v0.9.503 — Help button before Close, opens stats_page topic.
	var HelpPanelScript = load("res://client/help_panel.gd")
	_help_panel = HelpPanelScript.new()
	add_child(_help_panel)
	var help_btn = HelpPanelScript.make_help_button("stats_page", _help_panel)
	title_hbox.add_child(help_btn)

	var close_btn := Button.new()
	close_btn.text = "✕ Close"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): close_requested.emit())
	title_hbox.add_child(close_btn)

	# Header line (level + xp)
	_header_label = RichTextLabel.new()
	_header_label.bbcode_enabled = true
	_header_label.fit_content = true
	_header_label.scroll_active = false
	_header_label.add_theme_font_size_override("normal_font_size", 13)
	_header_label.custom_minimum_size = Vector2(0, 20)
	_vbox.add_child(_header_label)

	# Unspent points line
	_bank_label = RichTextLabel.new()
	_bank_label.bbcode_enabled = true
	_bank_label.fit_content = true
	_bank_label.scroll_active = false
	_bank_label.add_theme_font_size_override("normal_font_size", 13)
	_bank_label.custom_minimum_size = Vector2(0, 22)
	_vbox.add_child(_bank_label)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	_vbox.add_child(spacer)

	# Row container
	_row_container = VBoxContainer.new()
	_row_container.add_theme_constant_override("separation", 6)
	_vbox.add_child(_row_container)


func _render() -> void:
	_header_label.clear()
	_header_label.append_text("Level: [color=#FFD700]%d[/color]   XP: %d / %d" % [_level, _experience, _experience_to_next])
	_bank_label.clear()
	if _unspent > 0:
		_bank_label.append_text("[color=#00FF00]Unspent stat points: %d[/color]  [color=#888888](click [+1] to allocate)[/color]" % _unspent)
	else:
		_bank_label.append_text("[color=#888888]No unspent stat points — earn 1 per level-up.[/color]")

	for child in _row_container.get_children():
		child.queue_free()

	for stat_name in STAT_ORDER:
		var info: Dictionary = STAT_INFO[stat_name]
		var value: int = int(_stats.get(stat_name, 0))

		var row := PanelContainer.new()
		var row_sb := StyleBoxFlat.new()
		row_sb.bg_color = Color(0.08, 0.10, 0.12, 0.85)
		row_sb.border_color = Color(0.25, 0.35, 0.45, 1)
		row_sb.set_border_width_all(1)
		row_sb.set_corner_radius_all(4)
		row_sb.content_margin_left = 10
		row_sb.content_margin_top = 6
		row_sb.content_margin_right = 10
		row_sb.content_margin_bottom = 6
		row.add_theme_stylebox_override("panel", row_sb)
		_row_container.add_child(row)

		var row_hbox := HBoxContainer.new()
		row_hbox.add_theme_constant_override("separation", 10)
		row.add_child(row_hbox)

		# Left: label + abbr + value (expand)
		var text_vbox := VBoxContainer.new()
		text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_vbox.add_theme_constant_override("separation", 2)
		row_hbox.add_child(text_vbox)

		var name_label := RichTextLabel.new()
		name_label.bbcode_enabled = true
		name_label.fit_content = true
		name_label.scroll_active = false
		name_label.add_theme_font_size_override("normal_font_size", 14)
		name_label.custom_minimum_size = Vector2(0, 20)
		name_label.text = "[color=%s][b]%s[/b][/color]  [color=#A0A0A0]%s[/color]   [color=#FFFFFF]= %d[/color]" % [info["color"], info["label"], info["abbr"], value]
		text_vbox.add_child(name_label)

		var desc_label := RichTextLabel.new()
		desc_label.bbcode_enabled = true
		desc_label.fit_content = true
		desc_label.scroll_active = false
		desc_label.add_theme_font_size_override("normal_font_size", 11)
		desc_label.custom_minimum_size = Vector2(0, 16)
		desc_label.text = "[color=#A0A0A0]%s[/color]" % info["desc"]
		text_vbox.add_child(desc_label)

		# Right: [+1] button
		var spend_btn := Button.new()
		spend_btn.focus_mode = Control.FOCUS_NONE
		spend_btn.custom_minimum_size = Vector2(60, 36)
		spend_btn.text = "+1"
		if _unspent <= 0:
			spend_btn.disabled = true
		else:
			var sn = stat_name
			spend_btn.pressed.connect(func(): spend_requested.emit(sn))
		row_hbox.add_child(spend_btn)
