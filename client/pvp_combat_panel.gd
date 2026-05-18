extends Control
class_name PvPCombatPanel

# Audit #14 PvP Slice B.2 (v0.9.563) — Combat-scene PvP panel.
#
# Modal that opens on `pvp_combat_start` and stays open until `pvp_combat_end`.
# Shows opponent name + HP bar, own name + HP bar, action log, and three
# action buttons (Attack / Special / Defend). Both players submit their
# action per round; server resolves simultaneously and pushes a fresh
# `pvp_combat_state` to both clients.
#
# Buttons disable while waiting for the opponent to submit. Combat is closed
# remotely by the server's `pvp_combat_end` message (KO routes into the
# existing Slice D.2 sack-drop + respawn flow).

signal action_submitted(action: String)

var _root_panel: PanelContainer
var _vbox: VBoxContainer
var _opponent_header: RichTextLabel
var _opponent_hp_bar: ProgressBar
var _opponent_hp_label: RichTextLabel
var _log_label: RichTextLabel
var _self_hp_bar: ProgressBar
var _self_hp_label: RichTextLabel
var _self_header: RichTextLabel
var _btn_attack: Button
var _btn_special: Button
var _btn_defend: Button
var _status_label: RichTextLabel

var _waiting_for_resolve: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_layout()
	visible = false


func open_combat(data: Dictionary) -> void:
	_apply_state(data, true)
	_waiting_for_resolve = false
	_set_buttons_enabled(true)
	_status_label.clear()
	_status_label.append_text("[color=#88FF88]Pick an action.[/color]")
	visible = true


func update_state(data: Dictionary) -> void:
	_apply_state(data, false)
	_waiting_for_resolve = false
	_set_buttons_enabled(true)
	_status_label.clear()
	_status_label.append_text("[color=#88FF88]Round %d — pick an action.[/color]" % int(data.get("round", 1)))


func note_self_submitted(action: String) -> void:
	_waiting_for_resolve = true
	_set_buttons_enabled(false)
	_status_label.clear()
	_status_label.append_text("[color=#FFAA00]You picked %s. Waiting on opponent…[/color]" % action.capitalize())


func note_opponent_submitted() -> void:
	if _waiting_for_resolve:
		return
	_status_label.clear()
	_status_label.append_text("[color=#FFAA00]Opponent has picked. Choose your action.[/color]")


func end_combat(data: Dictionary) -> void:
	_set_buttons_enabled(false)
	var reason = String(data.get("reason", ""))
	var winner_name = String(data.get("winner_name", ""))
	var summary: String = ""
	match reason:
		"ko":
			summary = "[color=#FFD700]⚔ KO — %s wins.[/color]" % winner_name
		"mutual_p2_wins":
			summary = "[color=#FFD700]Mutual KO — defender (%s) wins the last stand.[/color]" % winner_name
		"round_cap":
			summary = "[color=#FFAA00]Round cap reached — %s wins on remaining HP.[/color]" % winner_name
		"disconnect":
			summary = "[color=#888888]Opponent disconnected — %s wins by forfeit.[/color]" % winner_name
		"abandoned":
			summary = "[color=#888888]Fight abandoned.[/color]"
		_:
			summary = "[color=#88FF88]Fight ended.[/color]"
	_status_label.clear()
	_status_label.append_text(summary)
	# Auto-close after 4 seconds; user can also click anywhere outside the
	# panel (no-op for now) or wait for the loot sack flow to take over.
	await get_tree().create_timer(4.0).timeout
	visible = false


func _apply_state(data: Dictionary, full: bool) -> void:
	if full:
		_opponent_header.clear()
		_opponent_header.append_text("[color=#FF8888]⚔ %s[/color]" % String(data.get("opponent_name", "?")))
		_self_header.clear()
		_self_header.append_text("[color=#88B8FF]%s[/color]" % String(data.get("my_name", "?")))
	var op_max = int(data.get("opponent_max_hp", 1))
	var op_hp = int(data.get("opponent_hp", 0))
	_opponent_hp_bar.max_value = max(1, op_max)
	_opponent_hp_bar.value = op_hp
	_opponent_hp_label.clear()
	_opponent_hp_label.append_text("[color=#FFFFFF]%d / %d[/color]" % [op_hp, op_max])
	var my_max = int(data.get("my_max_hp", 1))
	var my_hp = int(data.get("my_hp", 0))
	_self_hp_bar.max_value = max(1, my_max)
	_self_hp_bar.value = my_hp
	_self_hp_label.clear()
	_self_hp_label.append_text("[color=#FFFFFF]%d / %d[/color]" % [my_hp, my_max])
	var log: Array = data.get("log", [])
	_log_label.clear()
	if log.is_empty():
		_log_label.append_text("[color=#888888]Combat begins. Both players pick an action — they reveal simultaneously.[/color]")
	else:
		for line in log:
			_log_label.append_text(String(line) + "\n")


func _set_buttons_enabled(enabled: bool) -> void:
	_btn_attack.disabled = not enabled
	_btn_special.disabled = not enabled
	_btn_defend.disabled = not enabled


func _on_action_pressed(action: String) -> void:
	if _waiting_for_resolve:
		return
	_set_buttons_enabled(false)
	action_submitted.emit(action)


func _build_layout() -> void:
	# Dim backdrop
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)

	_root_panel = PanelContainer.new()
	_root_panel.custom_minimum_size = Vector2(560, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.05, 0.05, 0.98)
	sb.border_color = Color(0.85, 0.2, 0.2, 1)  # Red border (PvP)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 18
	sb.content_margin_top = 14
	sb.content_margin_right = 18
	sb.content_margin_bottom = 14
	_root_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_root_panel)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 10)
	_root_panel.add_child(_vbox)

	# Opponent header + HP
	_opponent_header = RichTextLabel.new()
	_opponent_header.bbcode_enabled = true
	_opponent_header.fit_content = true
	_opponent_header.scroll_active = false
	_opponent_header.add_theme_font_size_override("normal_font_size", 18)
	_opponent_header.custom_minimum_size = Vector2(0, 26)
	_vbox.add_child(_opponent_header)

	var op_hp_box := HBoxContainer.new()
	op_hp_box.add_theme_constant_override("separation", 8)
	_vbox.add_child(op_hp_box)

	_opponent_hp_bar = ProgressBar.new()
	_opponent_hp_bar.custom_minimum_size = Vector2(420, 22)
	_opponent_hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var op_sb := StyleBoxFlat.new()
	op_sb.bg_color = Color(0.85, 0.2, 0.2, 1)
	_opponent_hp_bar.add_theme_stylebox_override("fill", op_sb)
	op_hp_box.add_child(_opponent_hp_bar)

	_opponent_hp_label = RichTextLabel.new()
	_opponent_hp_label.bbcode_enabled = true
	_opponent_hp_label.fit_content = true
	_opponent_hp_label.scroll_active = false
	_opponent_hp_label.add_theme_font_size_override("normal_font_size", 12)
	_opponent_hp_label.custom_minimum_size = Vector2(110, 22)
	op_hp_box.add_child(_opponent_hp_label)

	# Separator
	var sep := HSeparator.new()
	_vbox.add_child(sep)

	# Action log
	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.fit_content = true
	_log_label.scroll_active = false
	_log_label.add_theme_font_size_override("normal_font_size", 13)
	_log_label.custom_minimum_size = Vector2(0, 140)
	_vbox.add_child(_log_label)

	# Status line (own pick / waiting / etc.)
	_status_label = RichTextLabel.new()
	_status_label.bbcode_enabled = true
	_status_label.fit_content = true
	_status_label.scroll_active = false
	_status_label.add_theme_font_size_override("normal_font_size", 13)
	_status_label.custom_minimum_size = Vector2(0, 22)
	_vbox.add_child(_status_label)

	# Buttons
	var btn_box := HBoxContainer.new()
	btn_box.add_theme_constant_override("separation", 10)
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_vbox.add_child(btn_box)

	_btn_attack = Button.new()
	_btn_attack.text = "Attack"
	_btn_attack.tooltip_text = "Basic melee — STR × 2 + weapon. ±25% variance."
	_btn_attack.focus_mode = Control.FOCUS_NONE
	_btn_attack.custom_minimum_size = Vector2(140, 40)
	_btn_attack.pressed.connect(func(): _on_action_pressed("attack"))
	btn_box.add_child(_btn_attack)

	_btn_special = Button.new()
	_btn_special.text = "Special"
	_btn_special.tooltip_text = "Caster strike — max(INT,DEX) × 3 + weapon/2. Mostly ignores defense."
	_btn_special.focus_mode = Control.FOCUS_NONE
	_btn_special.custom_minimum_size = Vector2(140, 40)
	_btn_special.pressed.connect(func(): _on_action_pressed("special"))
	btn_box.add_child(_btn_special)

	_btn_defend = Button.new()
	_btn_defend.text = "Defend"
	_btn_defend.tooltip_text = "Halve incoming damage this round; deal none."
	_btn_defend.focus_mode = Control.FOCUS_NONE
	_btn_defend.custom_minimum_size = Vector2(140, 40)
	_btn_defend.pressed.connect(func(): _on_action_pressed("defend"))
	btn_box.add_child(_btn_defend)

	# Separator
	var sep2 := HSeparator.new()
	_vbox.add_child(sep2)

	# Self header + HP
	_self_header = RichTextLabel.new()
	_self_header.bbcode_enabled = true
	_self_header.fit_content = true
	_self_header.scroll_active = false
	_self_header.add_theme_font_size_override("normal_font_size", 14)
	_self_header.custom_minimum_size = Vector2(0, 22)
	_vbox.add_child(_self_header)

	var self_hp_box := HBoxContainer.new()
	self_hp_box.add_theme_constant_override("separation", 8)
	_vbox.add_child(self_hp_box)

	_self_hp_bar = ProgressBar.new()
	_self_hp_bar.custom_minimum_size = Vector2(420, 20)
	_self_hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var self_sb := StyleBoxFlat.new()
	self_sb.bg_color = Color(0.2, 0.7, 0.85, 1)
	_self_hp_bar.add_theme_stylebox_override("fill", self_sb)
	self_hp_box.add_child(_self_hp_bar)

	_self_hp_label = RichTextLabel.new()
	_self_hp_label.bbcode_enabled = true
	_self_hp_label.fit_content = true
	_self_hp_label.scroll_active = false
	_self_hp_label.add_theme_font_size_override("normal_font_size", 12)
	_self_hp_label.custom_minimum_size = Vector2(110, 20)
	self_hp_box.add_child(_self_hp_label)
