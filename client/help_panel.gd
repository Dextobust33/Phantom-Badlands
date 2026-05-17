extends Control
class_name HelpPanel

# Audit #4 Slice 1A (v0.9.485) — reusable in-place help overlay. Distinct from
# TutorialHintPanel (which is a one-shot, server-pushed teaching modal): this
# panel is reopenable from any screen via a small Help button, drawing topic
# content from a static registry below. New screens add a `help_topic_key`
# and we expand this file as the help-button-everywhere UX rolls out.
#
# Usage:
#   var hp := HelpPanel.new()
#   add_child(hp)
#   hp.show_topic("companion_stable")
#
# Topics live in HELP_TOPICS below. Each entry is {title, body} BBCode strings.

signal dismissed

const HELP_TOPICS := {
	"companion_stable": {
		"title": "[color=#FFD700]Companion Stable[/color]",
		"body": (
			"A [color=#FFD700]Companion Stable[/color] (the magenta [color=#FF80FF]C[/color] tile at Tier 5+ trading posts) is a living link to your Sanctuary's companion storage. Bump the tile to open it.\n\n"
			+ "[color=#FFD700]MANAGE TAB[/color]\n"
			+ "[color=#A335EE]✦ Deposit[/color] — non-registered active companion → kennel. Frees a roster slot.\n"
			+ "[color=#A335EE]✦ Return to Slot[/color] — a [color=#FF80FF][REGISTERED][/color] companion goes back to its registered slot (still registered).\n"
			+ "[color=#A335EE]✦ Withdraw[/color] — pull a kennel companion into your roster.\n"
			+ "[color=#A335EE]✦ Check Out[/color] (v0.9.493) — pull a Sanctuary-registered companion onto your character as the new active. Closes the death-and-respawn detour. Requires no current active.\n\n"
			+ "[color=#FFD700]FUSE TAB (v0.9.489)[/color]\n"
			+ "Mid-character fusion. Pick 3 companions of the same monster type AND sub-tier from either the kennel or registered slots, then press Fuse. The result is auto-registered if any input was registered (slot-preserving), or added to the kennel otherwise.\n"
			+ "[color=#888888]Currently supports Same Type fusion. Mixed T9 + Hybrid will land in a follow-up.[/color]\n\n"
			+ "[color=#FF8888]Notes[/color]:\n"
			+ "  • Deposit and registration are independent operations. Depositing never changes registration status.\n"
			+ "  • Registered companions that are currently your active companion are NOT fuseable — deposit them first (use 'Return to Slot') to make them available.\n"
			+ "  • Kennel must have space (upgrade at the Sanctuary if full)."
		),
	},
	"home_stone_companion": {
		"title": "[color=#FFD700]Home Stone (Companion) — Register vs Kennel[/color]",
		"body": (
			"You're holding a [color=#FFD700]Home Stone (Companion)[/color]. It binds your active companion to your Sanctuary — but [b]how[/b] it binds depends on your choice.\n\n"
			+ "[color=#00FF00]✦ REGISTER[/color] — death-resistant slot.\n"
			+ "  • Companion is locked into one of your account's [color=#FF80FF]Registered slots[/color] in the Sanctuary.\n"
			+ "  • [b]Survives permadeath.[/b] On character death, the companion's current state (XP, level, sub-tier) is saved.\n"
			+ "  • You can check it out as your active companion on any future character.\n"
			+ "  • Registered slots are limited (default 2; upgrade in Sanctuary). Use them for your [color=#FFD700]most valuable[/color] long-term companions.\n"
			+ "  • Cannot be directly fused while registered — deposit it back to its slot via a Companion Stable to make it a fusion input.\n\n"
			+ "[color=#A335EE]✦ KENNEL[/color] — bulk storage.\n"
			+ "  • Companion is dismissed from active and stored in the Sanctuary kennel.\n"
			+ "  • [b]NOT death-resistant.[/b] Kenneled companions are gone if you have no surviving registered slot when the character dies.\n"
			+ "  • Designed for [color=#FFD700]fusion inputs[/color] — stockpile candidates for combining at the Companion Stable's Fuse tab.\n"
			+ "  • Kennel capacity is much larger than registered slots (default 30; also upgradeable).\n\n"
			+ "[color=#87CEEB]Decision rule[/color]: If it's your main pet you want to keep across deaths → Register. If it's a stockpile companion you'll feed into fusion → Kennel."
		),
	},
	"fusion_overview": {
		"title": "[color=#FFD700]Fusion[/color]",
		"body": (
			"At the [color=#FFD700]Fusion Station[/color] in your Sanctuary, you can combine kennel companions in three ways:\n\n"
			+ "[color=#A335EE]✦ Same Type[/color] — 3 companions of the same monster type and the same sub-tier → 1 companion of the next sub-tier. Path to maxing within a tier.\n\n"
			+ "[color=#A335EE]✦ Mixed T9[/color] — 8 companions of mixed types, all at sub-tier 8 → 1 random Tier 9 companion. The endgame catch path.\n\n"
			+ "[color=#A335EE]✦ Hybrid[/color] — 2 companions of [b]different[/b] monster types, both at sub-tier 5+, plus 1 [color=#FFD700]Hybrid Catalyst[/color] → a hybrid companion that blends both parents' bonuses and inherits the second parent's threshold ability.\n\n"
			+ "[color=#FFD700]Hybrid Catalysts[/color] drop from Tier 5+ dungeon chests.\n\n"
			+ "[color=#87CEEB]Walk to a Companion Stable (Tier 5+ NPC posts) to deposit/withdraw without needing to die.[/color]"
		),
	},
}

var _root_panel: PanelContainer
var _title_label: RichTextLabel
var _body_label: RichTextLabel
var _close_button: Button


func _ready() -> void:
	# top_level=true so this overlay never perturbs sibling layout (v0.9.487
	# fix). Without it, a hidden modal can still shrink the map area via
	# nested CenterContainer+PRESET_FULL_RECT pressure on the parent.
	top_level = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_layout()
	visible = false


func show_topic(topic_key: String) -> void:
	var topic = HELP_TOPICS.get(topic_key, null)
	if topic == null:
		# Fallback: render the key itself so missing topics are at least visible.
		_set_content("[color=#FF6644]Help topic missing[/color]", "No content registered for '%s'." % topic_key)
	else:
		_set_content(str(topic.get("title", "")), str(topic.get("body", "")))
	visible = true
	if _close_button:
		_close_button.grab_focus()


func _set_content(title_bb: String, body_bb: String) -> void:
	if _title_label:
		_title_label.clear()
		_title_label.append_text(title_bb)
	if _body_label:
		_body_label.clear()
		_body_label.append_text(body_bb)


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key = event.keycode
		if key == KEY_ESCAPE or key == KEY_ENTER or key == KEY_KP_ENTER:
			get_viewport().set_input_as_handled()
			_on_close()


func _build_layout() -> void:
	# Dim backdrop.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	# CenterContainer for reliable on-screen centering (see v0.9.478 hotfix).
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)

	_root_panel = PanelContainer.new()
	_root_panel.custom_minimum_size = Vector2(560, 0)

	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = Color(0.08, 0.10, 0.16, 0.98)
	panel_sb.border_color = Color(0.53, 0.81, 0.92, 1.0)  # skyblue border — distinct from TutorialHintPanel's gold
	panel_sb.set_border_width_all(2)
	panel_sb.set_corner_radius_all(8)
	panel_sb.content_margin_left = 22
	panel_sb.content_margin_right = 22
	panel_sb.content_margin_top = 18
	panel_sb.content_margin_bottom = 18
	_root_panel.add_theme_stylebox_override("panel", panel_sb)
	center.add_child(_root_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_root_panel.add_child(vbox)

	_title_label = RichTextLabel.new()
	_title_label.bbcode_enabled = true
	_title_label.fit_content = true
	_title_label.scroll_active = false
	_title_label.add_theme_font_size_override("normal_font_size", 18)
	_title_label.custom_minimum_size = Vector2(0, 26)
	vbox.add_child(_title_label)

	_body_label = RichTextLabel.new()
	_body_label.bbcode_enabled = true
	_body_label.fit_content = true
	_body_label.scroll_active = true
	_body_label.add_theme_font_size_override("normal_font_size", 14)
	_body_label.custom_minimum_size = Vector2(516, 280)
	vbox.add_child(_body_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	vbox.add_child(spacer)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	_close_button = Button.new()
	_close_button.text = "Close  (Esc / Enter)"
	_close_button.custom_minimum_size = Vector2(220, 32)
	_close_button.focus_mode = Control.FOCUS_ALL
	_close_button.pressed.connect(_on_close)
	btn_row.add_child(_close_button)


func _on_close() -> void:
	visible = false
	dismissed.emit()


static func make_help_button(topic_key: String, help_panel: HelpPanel) -> Button:
	"""Convenience: returns a small '?' Help button that opens help_panel
	on the given topic_key. Caller is responsible for adding to a layout."""
	var btn := Button.new()
	btn.text = "?  Help"
	btn.tooltip_text = "Open help for this screen"
	btn.custom_minimum_size = Vector2(72, 26)
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(func(): help_panel.show_topic(topic_key))
	return btn
