extends Control
class_name StonesPanel

# Audit #4 Slice 1 / UI remediation — visual NPC Home Stone Vendor.
# Replaces the chat-command-only `/stones` + `/buystone <type>` interface
# (v0.9.332) which was un-discoverable per the "no chat-command-first
# features" hard rule.
#
# Pattern follows admin_panel.gd: dim backdrop + centered PanelContainer,
# vertical button column. Each stone type is one row with name, price,
# owned/cap, [Buy] button. Click [Buy] emits buy_requested(stone_type)
# which client.gd dispatches via the existing buy_home_stone server msg.
# /stones and /buystone keep working as power-user shortcuts.

signal close_requested
signal buy_requested(stone_type: String)

# Stone catalog — kept in sync with server NPC_STONE_PRICES/CAPS/DISPLAY
# (server is authoritative; this is just for label rendering).
const STONE_ORDER: Array = ["egg", "supplies", "equipment", "companion"]
const STONE_INFO: Dictionary = {
	"egg": {
		"name": "Home Stone (Egg)",
		"desc": "Sends one incubating egg to your Sanctuary.",
		"price": 500,
		"cap": 3,
		"color": "#A335EE",
	},
	"supplies": {
		"name": "Home Stone (Supplies)",
		"desc": "Sends up to 10 consumables to Sanctuary storage.",
		"price": 800,
		"cap": 5,
		"color": "#9ACD32",
	},
	"equipment": {
		"name": "Home Stone (Equipment)",
		"desc": "Sends one equipped item to Sanctuary storage.",
		"price": 1500,
		"cap": 2,
		"color": "#FFD700",
	},
	"companion": {
		"name": "Home Stone (Companion)",
		"desc": "Registers your active companion to Sanctuary — survives permadeath.",
		"price": 3000,
		"cap": 2,
		"color": "#FF6347",
	},
}

var _root_panel: PanelContainer
var _vbox: VBoxContainer
var _valor_label: RichTextLabel
var _location_label: RichTextLabel
var _row_container: VBoxContainer

# Snapshot pushed from client.gd on every refresh.
var _current_valor: int = 0
var _bought: Dictionary = {}
var _at_npc_post: bool = false

# Audit #15 v0.9.516 — reusable HelpPanel attached to the header ? Help button.
var _help_panel: HelpPanel


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_layout()
	visible = false


func open(valor: int, bought: Dictionary, at_npc_post: bool) -> void:
	refresh(valor, bought, at_npc_post)
	visible = true


func close() -> void:
	visible = false


func refresh(valor: int, bought: Dictionary, at_npc_post: bool) -> void:
	"""Re-render with fresh data. Called on open() and after each successful
	buy (server pushes character_update which triggers client to call this)."""
	_current_valor = valor
	_bought = bought.duplicate() if bought is Dictionary else {}
	_at_npc_post = at_npc_post
	_render_rows()


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
	sb.bg_color = Color(0.06, 0.05, 0.04, 0.97)
	sb.border_color = Color(0.85, 0.65, 0.27, 1)  # Gold border (vendor)
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

	# Title row with close button
	var title_hbox := HBoxContainer.new()
	title_hbox.add_theme_constant_override("separation", 8)
	_vbox.add_child(title_hbox)

	var title_label := Label.new()
	title_label.text = "NPC Home Stone Vendor"
	title_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.27))
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_hbox.add_child(title_label)

	# Audit #15 v0.9.516 — Help button.
	var HelpPanelScript = load("res://client/help_panel.gd")
	_help_panel = HelpPanelScript.new()
	add_child(_help_panel)
	var help_btn = HelpPanelScript.make_help_button("stones_panel", _help_panel)
	title_hbox.add_child(help_btn)

	var close_btn := Button.new()
	close_btn.text = "✕ Close"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): close_requested.emit())
	title_hbox.add_child(close_btn)

	# Valor + location status line
	_valor_label = RichTextLabel.new()
	_valor_label.bbcode_enabled = true
	_valor_label.fit_content = true
	_valor_label.scroll_active = false
	_valor_label.add_theme_font_size_override("normal_font_size", 13)
	_valor_label.custom_minimum_size = Vector2(0, 22)
	_vbox.add_child(_valor_label)

	_location_label = RichTextLabel.new()
	_location_label.bbcode_enabled = true
	_location_label.fit_content = true
	_location_label.scroll_active = false
	_location_label.add_theme_font_size_override("normal_font_size", 12)
	_location_label.custom_minimum_size = Vector2(0, 20)
	_vbox.add_child(_location_label)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	_vbox.add_child(spacer)

	# Row container — refilled on each refresh
	_row_container = VBoxContainer.new()
	_row_container.add_theme_constant_override("separation", 6)
	_vbox.add_child(_row_container)


func _render_rows() -> void:
	# Update header lines
	_valor_label.clear()
	_valor_label.append_text("Your Valor: [color=#FFD700]%d[/color]" % _current_valor)
	_location_label.clear()
	if _at_npc_post:
		_location_label.append_text("[color=#88FF88]At NPC post — purchases enabled.[/color]")
	else:
		_location_label.append_text("[color=#FF8800]Stand at an NPC post to purchase.[/color]")

	# Rebuild rows
	for child in _row_container.get_children():
		child.queue_free()

	for stone_type in STONE_ORDER:
		var info: Dictionary = STONE_INFO[stone_type]
		var owned: int = int(_bought.get(stone_type, 0))
		var cap: int = int(info["cap"])
		var price: int = int(info["price"])
		var remaining: int = max(0, cap - owned)

		var row := PanelContainer.new()
		var row_sb := StyleBoxFlat.new()
		row_sb.bg_color = Color(0.10, 0.08, 0.06, 0.85)
		row_sb.border_color = Color(0.35, 0.30, 0.20, 1)
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

		# Left side: name + description + owned/cap (expand)
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
		name_label.text = "[color=%s][b]%s[/b][/color]   [color=#FFD700]%d V[/color]   [color=#888888]%d/%d bought[/color]" % [info["color"], info["name"], price, owned, cap]
		text_vbox.add_child(name_label)

		var desc_label := RichTextLabel.new()
		desc_label.bbcode_enabled = true
		desc_label.fit_content = true
		desc_label.scroll_active = false
		desc_label.add_theme_font_size_override("normal_font_size", 11)
		desc_label.custom_minimum_size = Vector2(0, 16)
		desc_label.text = "[color=#A0A0A0]%s[/color]" % info["desc"]
		text_vbox.add_child(desc_label)

		# Right side: Buy button
		var buy_btn := Button.new()
		buy_btn.focus_mode = Control.FOCUS_NONE
		buy_btn.custom_minimum_size = Vector2(110, 36)
		if remaining <= 0:
			buy_btn.text = "SOLD OUT"
			buy_btn.disabled = true
		elif not _at_npc_post:
			buy_btn.text = "Buy"
			buy_btn.disabled = true
		elif _current_valor < price:
			buy_btn.text = "Need %d V" % (price - _current_valor)
			buy_btn.disabled = true
		else:
			buy_btn.text = "Buy (-%d V)" % price
			buy_btn.disabled = false
			# Capture the stone_type into the closure
			var st = stone_type
			buy_btn.pressed.connect(func(): buy_requested.emit(st))
		row_hbox.add_child(buy_btn)
