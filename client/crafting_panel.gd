extends Control
class_name CraftingPanel

# Visual crafting surface: recipe list on the left, detail + Craft on the right.
# Mirrors the inventory_panel pattern (one container, no separate card scenes).

signal close_requested
signal recipe_selected(recipe_index: int)
signal craft_pressed(recipe_index: int, quantity: int)
signal quantity_changed(quantity: int)
signal skill_changed(skill: String)
signal boost_tier_changed(tier: String)

# Audit #4 Slice 2 — Boost selector (None / Refined / Master).
# Server enforces mutual exclusion with Tempered and forces quantity=1
# when boost != none; panel mirrors both rules visually.
const BOOST_TIERS := [
	{"id": "none",    "label": "None",     "color": Color(0.75, 0.75, 0.75)},
	{"id": "refined", "label": "Refined",  "color": Color(1.0, 0.67, 0.40)},
	{"id": "master",  "label": "Master",   "color": Color(0.64, 0.21, 0.93)},
]

const SKILL_CHIPS := [
	{"id": "blacksmithing", "label": "Forge", "color": Color(1.0, 0.4, 0.0)},
	{"id": "alchemy", "label": "Alch", "color": Color(0.0, 1.0, 0.0)},
	{"id": "enchanting", "label": "Ench", "color": Color(0.64, 0.21, 0.93)},
	{"id": "scribing", "label": "Scribe", "color": Color(0.53, 0.81, 0.92)},
	{"id": "construction", "label": "Build", "color": Color(0.67, 0.47, 0.27)},
]

var client_ref = null
var _current_skill: String = ""
var _recipes: Array = []
var _materials: Dictionary = {}
var _selected_index: int = -1
var _upcoming_unlocks: Array = []  # Audit #8 Layer 7: next 3 locked recipes preview
var _craft_quantity: int = 1
var _allow_skill_switch: bool = true

# Audit #4 Slice 2 — Boost selector state.
# _boost_tier is the currently-active tier for the selected recipe.
# _boost_memory persists the last-picked tier per recipe across selections
# (client-side only; resets on app restart per the locked design).
var _boost_tier: String = "none"
var _boost_memory: Dictionary = {}  # recipe_id -> "none" / "refined" / "master"
var _boost_row: HBoxContainer
var _boost_buttons: Dictionary = {}  # tier_id -> Button
var _boost_label: Label

var _root_panel: PanelContainer
var _title_label: Label

# v0.9.503 — reusable HelpPanel attached to the header ? Help button.
var _help_panel: Control = null
var _skill_label: Label
var _bonus_label: RichTextLabel
var _skill_chip_row: HBoxContainer

## Which question the recipe list is answering. Measured before designing: blacksmithing is 68
## recipes = 14 pages, and a level-1 blacksmith has ONE recipe at their skill.
const FILTER_CHIPS := [
	{"id": "ready", "label": "Can Make", "help": "Recipes you can act on right now — you have the materials, or it can be commissioned."},
	{"id": "skill", "label": "At My Skill", "help": "Everything your skill allows, whether or not you have the materials."},
	{"id": "wanted", "label": "Wanted", "help": "Recipes another player is paying for right now."},
	{"id": "all", "label": "All", "help": "Every recipe for this trade, including ones you cannot reach yet."},
]
var _filter_row: HBoxContainer
var _filter_buttons: Dictionary = {}
var _filter: String = "ready"
var _recipes_all: Array = []
## Filtered row -> its position in the unfiltered list the client holds.
var _src_index: Array = []
var _skill_chip_buttons: Dictionary = {}
var _recipe_list_vbox: VBoxContainer
var _detail_root: VBoxContainer
var _detail_title: Label
var _detail_meta: RichTextLabel
var _detail_materials: RichTextLabel
var _qty_row: HBoxContainer
var _qty_label: Label
var _qty_minus: Button
var _qty_plus: Button
var _qty_max: Button
var _craft_button: Button
var _post_job_button: Button
var _detail_scroll: ScrollContainer
var _commission_row: HBoxContainer
var _commission_amount: LineEdit
var _commission_hint: Label
var _detail_empty: Label
var _status_label: RichTextLabel

var _recipe_buttons: Array = []  # Buttons in left list, parallel to _recipes


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = true
	_build_layout()
	visible = false


func _build_layout() -> void:
	_root_panel = PanelContainer.new()
	_root_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.055, 0.045, 0.97)
	sb.border_color = Color(0.55, 0.45, 0.33, 1)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8
	sb.content_margin_top = 8
	sb.content_margin_right = 8
	sb.content_margin_bottom = 8
	_root_panel.add_theme_stylebox_override("panel", sb)
	add_child(_root_panel)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 6)
	_root_panel.add_child(root_vbox)

	# Header row
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	root_vbox.add_child(header)

	_title_label = Label.new()
	_title_label.text = "Crafting"
	_title_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
	_title_label.add_theme_font_size_override("font_size", 18)
	header.add_child(_title_label)

	_skill_label = Label.new()
	_skill_label.text = ""
	_skill_label.add_theme_font_size_override("font_size", 13)
	header.add_child(_skill_label)

	_bonus_label = RichTextLabel.new()
	_bonus_label.bbcode_enabled = true
	_bonus_label.fit_content = true
	_bonus_label.scroll_active = false
	_bonus_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bonus_label.custom_minimum_size = Vector2(0, 20)
	_bonus_label.add_theme_font_size_override("normal_font_size", 12)
	header.add_child(_bonus_label)

	# v0.9.503 — Help button on the Crafting header. Opens crafting_page
	# topic (7 transparency layers, specialty lock-in, quality scaling).
	var HelpPanelScript = load("res://client/help_panel.gd")
	_help_panel = HelpPanelScript.new()
	add_child(_help_panel)
	var help_btn = HelpPanelScript.make_help_button("crafting_page", _help_panel)
	header.add_child(help_btn)

	# Skill chips (only visible when we're allowed to switch — i.e., not station-locked)
	_skill_chip_row = HBoxContainer.new()
	_skill_chip_row.add_theme_constant_override("separation", 4)
	root_vbox.add_child(_skill_chip_row)
	for chip in SKILL_CHIPS:
		var btn := Button.new()
		btn.text = chip["label"]
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 11)
		btn.custom_minimum_size = Vector2(0, 24)
		var col: Color = chip["color"]
		btn.add_theme_color_override("font_color", col)
		btn.pressed.connect(_on_skill_chip_pressed.bind(chip["id"]))
		_skill_chip_row.add_child(btn)
		_skill_chip_buttons[chip["id"]] = btn

	# ⚑ THE FILTER ROW — owner 2026-09-18: *"Action bar buttons? They should be UI buttons."*
	#
	# ⛑ AND THE FIRST VERSION OF THIS SHIPPED INTO THE WRONG SURFACE ENTIRELY. The filters, the
	# detail stats and the commission labels were all written into `client.gd`'s TEXT renderers -
	# `display_craft_recipe_list` / `display_craft_recipe_details` / the action bar - which this
	# panel replaced. The probe grepped client.gd, found every string, and passed. The player saw
	# none of it. **When this project has a panel for a screen, the panel IS the screen.**
	_filter_row = HBoxContainer.new()
	_filter_row.add_theme_constant_override("separation", 4)
	root_vbox.add_child(_filter_row)
	for f in FILTER_CHIPS:
		var fb := Button.new()
		fb.toggle_mode = true
		fb.focus_mode = Control.FOCUS_NONE
		fb.add_theme_font_size_override("font_size", 11)
		fb.custom_minimum_size = Vector2(0, 24)
		fb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# ⛑ LABELLED AT BIRTH. `_refresh_filter_chips()` fills in the counts, but it only runs on
		# populate - so before the first list arrives the row drew as four BLANK boxes. The capture
		# showed exactly that, and a blank button is indistinguishable from a broken one.
		fb.text = String(f["label"])
		fb.tooltip_text = String(f["help"])
		fb.pressed.connect(_on_filter_pressed.bind(String(f["id"])))
		_filter_row.add_child(fb)
		_filter_buttons[String(f["id"])] = fb

	# Body: recipe list (left) + detail (right)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	root_vbox.add_child(body)

	# Left: recipe list inside a scroll container
	var list_panel := _make_subpanel()
	list_panel.custom_minimum_size = Vector2(360, 0)
	list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(list_panel)

	var list_scroll := ScrollContainer.new()
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_panel.add_child(list_scroll)

	_recipe_list_vbox = VBoxContainer.new()
	_recipe_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recipe_list_vbox.add_theme_constant_override("separation", 2)
	list_scroll.add_child(_recipe_list_vbox)

	# Right: detail
	var detail_panel := _make_subpanel()
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(detail_panel)

	_detail_root = VBoxContainer.new()
	_detail_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_root.add_theme_constant_override("separation", 6)
	detail_panel.add_child(_detail_root)

	_detail_title = Label.new()
	_detail_title.text = ""
	_detail_title.add_theme_color_override("font_color", Color(1, 0.84, 0))
	_detail_title.add_theme_font_size_override("font_size", 20)
	_detail_root.add_child(_detail_title)

	# ⚡ THE BUTTONS HAVE TO STAY ON SCREEN. Owner 2026-09-18, on the third time of asking about
	# commissions: *"How do I even get to it?"*
	#
	# ⛑ THEY COULD NOT. `_detail_root` was a plain VBox and both text blocks below are
	# `fit_content`, so a recipe with a long materials list simply pushed [b]Craft[/b] and
	# [b]Post Job for a Player[/b] off the bottom of the pane - there was no scrollbar and nothing
	# to say anything was down there. Exactly the fault the tutorial hint panel had the same day:
	# a container that grows to its content inside a box that does not.
	#
	# The text scrolls; the buttons are pinned under it.
	_detail_scroll = ScrollContainer.new()
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_root.add_child(_detail_scroll)

	var detail_text_col := VBoxContainer.new()
	detail_text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_text_col.add_theme_constant_override("separation", 6)
	_detail_scroll.add_child(detail_text_col)

	_detail_meta = RichTextLabel.new()
	_detail_meta.bbcode_enabled = true
	_detail_meta.fit_content = true
	_detail_meta.scroll_active = false
	_detail_meta.add_theme_font_size_override("normal_font_size", 15)
	_detail_meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_text_col.add_child(_detail_meta)

	_detail_materials = RichTextLabel.new()
	_detail_materials.bbcode_enabled = true
	_detail_materials.fit_content = true
	_detail_materials.scroll_active = false
	_detail_materials.add_theme_font_size_override("normal_font_size", 16)
	_detail_materials.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_text_col.add_child(_detail_materials)

	# Audit #4 Slice 2 — Boost selector row.
	# Live preview: clicking a tier redraws odds + material costs immediately.
	_boost_row = HBoxContainer.new()
	_boost_row.add_theme_constant_override("separation", 6)
	_detail_root.add_child(_boost_row)

	_boost_label = Label.new()
	_boost_label.text = "Boost:"
	_boost_label.add_theme_color_override("font_color", Color(0.55, 0.81, 0.92))
	_boost_label.add_theme_font_size_override("font_size", 14)
	_boost_row.add_child(_boost_label)

	for tier_def in BOOST_TIERS:
		var btn := Button.new()
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 13)
		btn.custom_minimum_size = Vector2(0, 28)
		btn.add_theme_color_override("font_color", tier_def["color"])
		btn.pressed.connect(_on_boost_tier_pressed.bind(tier_def["id"]))
		_boost_row.add_child(btn)
		_boost_buttons[tier_def["id"]] = btn

	# Quantity stepper
	_qty_row = HBoxContainer.new()
	_qty_row.add_theme_constant_override("separation", 6)
	_detail_root.add_child(_qty_row)

	var qty_title := Label.new()
	qty_title.text = "Qty:"
	qty_title.add_theme_color_override("font_color", Color(0.55, 0.81, 0.92))
	qty_title.add_theme_font_size_override("font_size", 15)
	_qty_row.add_child(qty_title)

	_qty_minus = _make_action_btn(" - ", _on_qty_minus_pressed)
	_qty_minus.custom_minimum_size = Vector2(40, 30)
	_qty_minus.add_theme_font_size_override("font_size", 15)
	_qty_row.add_child(_qty_minus)

	_qty_label = Label.new()
	_qty_label.text = "1"
	_qty_label.custom_minimum_size = Vector2(48, 0)
	_qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_qty_label.add_theme_font_size_override("font_size", 15)
	_qty_row.add_child(_qty_label)

	_qty_plus = _make_action_btn(" + ", _on_qty_plus_pressed)
	_qty_plus.custom_minimum_size = Vector2(40, 30)
	_qty_plus.add_theme_font_size_override("font_size", 15)
	_qty_row.add_child(_qty_plus)

	_qty_max = _make_action_btn("Max", _on_qty_max_pressed)
	_qty_max.add_theme_font_size_override("font_size", 15)
	_qty_row.add_child(_qty_max)

	# Craft button
	_craft_button = Button.new()
	_craft_button.text = "Craft"
	_craft_button.focus_mode = Control.FOCUS_NONE
	_craft_button.add_theme_font_size_override("font_size", 18)
	_craft_button.custom_minimum_size = Vector2(0, 44)
	_craft_button.pressed.connect(_on_craft_pressed)
	_detail_root.add_child(_craft_button)

	# ⛑ THE SECOND ROUTE NEEDS ITS OWN BUTTON, IN THE PANEL. Both ways through a gated recipe are
	# offered together or the other one is undiscoverable - and the first attempt at this put the
	# button on the ACTION BAR, which this panel replaced.
	_post_job_button = Button.new()
	_post_job_button.text = "Post Job for a Player"
	_post_job_button.focus_mode = Control.FOCUS_NONE
	_post_job_button.add_theme_font_size_override("font_size", 13)
	_post_job_button.custom_minimum_size = Vector2(0, 30)
	_post_job_button.tooltip_text = "Offer this to other crafters. They supply the materials and their own quality — a good crafter beats the NPC job, which is always Standard."
	_post_job_button.pressed.connect(_on_post_job_pressed)
	_post_job_button.visible = false
	_detail_root.add_child(_post_job_button)

	# ⚡ AND THE PRICE IS ASKED HERE, NOT IN THE CHAT BOX. Pressing Post Job used to print
	# "How much Valor will you pay? Type an amount" with `display_game` and focus the chat field -
	# and this panel is COVERING the surface that text goes to. So the button appeared to do
	# nothing: the question was behind the panel and the only cue was a placeholder in a text box
	# at the bottom of the screen. Owner's standing rule, from the start of this arc: *"the answers
	# should be UI based where possible."*
	_commission_row = HBoxContainer.new()
	_commission_row.add_theme_constant_override("separation", 6)
	_commission_row.visible = false
	_detail_root.add_child(_commission_row)

	var _c_lbl := Label.new()
	_c_lbl.text = "Pay:"
	_c_lbl.add_theme_color_override("font_color", Color(0.78, 0.64, 0.29))
	_c_lbl.add_theme_font_size_override("font_size", 15)
	_commission_row.add_child(_c_lbl)

	_commission_amount = LineEdit.new()
	_commission_amount.placeholder_text = "Valor"
	_commission_amount.custom_minimum_size = Vector2(110, 30)
	_commission_amount.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_commission_amount.text_submitted.connect(func(_t): _on_commission_confirm())
	_commission_row.add_child(_commission_amount)

	var _c_ok := _make_action_btn("Post", _on_commission_confirm)
	_c_ok.add_theme_font_size_override("font_size", 14)
	_commission_row.add_child(_c_ok)

	var _c_no := _make_action_btn("Cancel", _on_commission_cancel)
	_c_no.add_theme_font_size_override("font_size", 14)
	_commission_row.add_child(_c_no)

	_commission_hint = Label.new()
	_commission_hint.text = ""
	_commission_hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.58))
	_commission_hint.add_theme_font_size_override("font_size", 12)
	_commission_hint.visible = false
	_detail_root.add_child(_commission_hint)

	_detail_empty = Label.new()
	_detail_empty.text = "Select a recipe on the left."
	_detail_empty.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	_detail_empty.add_theme_font_size_override("font_size", 15)
	_detail_root.add_child(_detail_empty)

	# Spacer pushes status row to bottom
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_root.add_child(spacer)

	# Status row
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	root_vbox.add_child(action_row)

	_status_label = RichTextLabel.new()
	_status_label.bbcode_enabled = true
	_status_label.fit_content = true
	_status_label.scroll_active = false
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_label.add_theme_font_size_override("normal_font_size", 13)
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.text = ""
	action_row.add_child(_status_label)

	action_row.add_child(_make_action_btn("Close (Space)", _on_close_pressed))

	_show_detail_empty(true)


func _make_subpanel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.045, 0.035, 0.025, 0.7)
	sb.border_color = Color(0.4, 0.34, 0.25, 0.6)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6
	sb.content_margin_top = 6
	sb.content_margin_right = 6
	sb.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", sb)
	return p


func _make_action_btn(label: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 12)
	b.custom_minimum_size = Vector2(0, 28)
	b.pressed.connect(callback)
	return b


# === Public API ===

func show_panel() -> void:
	visible = true


func hide_panel() -> void:
	visible = false


func set_status(text: String) -> void:
	if _status_label:
		_status_label.text = text


func set_allow_skill_switch(allow: bool) -> void:
	_allow_skill_switch = allow
	if _skill_chip_row:
		_skill_chip_row.visible = allow


# Audit #8 Layer 7 — next 3 locked recipes shown as a "Coming Up" footer in
# the recipe list. Call right after populate() so _rebuild_recipe_list sees it.
func set_upcoming_unlocks(unlocks: Array) -> void:
	_upcoming_unlocks = unlocks


# Called by client.gd whenever the recipe list / materials change (server craft_list response,
# materials update, character_update, etc.).
func _on_post_job_pressed() -> void:
	"""Open the inline price row. The order is sent by `_on_commission_confirm`."""
	if client_ref == null or _selected_index < 0 or _selected_index >= _recipes.size():
		return
	var recipe = _recipes[_selected_index]
	_commission_row.visible = true
	_commission_hint.visible = true
	# A starting figure the player can just accept: what the post NPC would charge. A real crafter
	# is better than the NPC (which is always Standard), so this is a floor, not a recommendation.
	var fee := int(recipe.get("commission_fee", 0))
	_commission_amount.text = str(fee) if fee > 0 else ""
	_commission_hint.text = ("A crafter who takes this supplies the materials and their own quality."
		+ ("  The post NPC would charge %d." % fee if fee > 0 else ""))
	_post_job_button.visible = false
	_commission_amount.grab_focus()
	_commission_amount.select_all()


func _on_commission_cancel() -> void:
	_commission_row.visible = false
	_commission_hint.visible = false
	_refresh_detail()


func _on_commission_confirm() -> void:
	if client_ref == null or _selected_index < 0 or _selected_index >= _recipes.size():
		return
	var amount := int(_commission_amount.text.strip_edges()) if _commission_amount.text.strip_edges().is_valid_int() else 0
	if amount <= 0:
		_commission_hint.text = "Enter an amount of Valor."
		_commission_hint.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
		return
	var recipe = _recipes[_selected_index]
	client_ref.post_commission_order(String(recipe.get("id", "")), String(recipe.get("name", "item")), amount)
	_commission_row.visible = false
	_commission_hint.visible = false
	_refresh_detail()


func _on_filter_pressed(filter_id: String) -> void:
	_filter = filter_id
	_selected_index = -1
	_apply_filter()
	_rebuild_recipe_list()
	_refresh_filter_chips()
	_refresh_detail()


func _apply_filter() -> void:
	"""Narrow the full list to the question being asked.

	⛑ THE PREDICATE IS SHARED with the server-side notion of what each field means -
	`CraftingDatabase.recipe_matches_filter` - so the panel, the text fallback and the probe all
	agree. Three copies of a filter is how one of them starts showing a recipe the others hide."""
	var CD = preload("res://shared/crafting_database.gd")
	var out: Array = []
	_src_index.clear()
	for i in range(_recipes_all.size()):
		var r = _recipes_all[i]
		if r is Dictionary and CD.recipe_matches_filter(r, _filter):
			# ⛑ WHERE THIS ROW CAME FROM. The panel shows a FILTERED list and the client indexes
			# the UNFILTERED one, so emitting the filtered position would craft a different recipe
			# than the one clicked - silently, and only when a filter is active. The map is kept
			# rather than the index recomputed, because a recomputation is a second rule.
			_src_index.append(i)
			out.append(r)
	_recipes = out


func _filter_counts() -> Dictionary:
	var CD = preload("res://shared/crafting_database.gd")
	var c := {}
	for f in FILTER_CHIPS:
		var fid := String(f["id"])
		var n := 0
		for r in _recipes_all:
			if r is Dictionary and CD.recipe_matches_filter(r, fid):
				n += 1
		c[fid] = n
	return c


func _refresh_filter_chips() -> void:
	"""Every chip carries its COUNT, so the player can see where their options are without
	pressing each one to find out."""
	var counts := _filter_counts()
	for f in FILTER_CHIPS:
		var fid := String(f["id"])
		var btn: Button = _filter_buttons.get(fid)
		if btn == null:
			continue
		var n := int(counts.get(fid, 0))
		btn.text = "%s (%d)" % [String(f["label"]), n]
		btn.button_pressed = (fid == _filter)
		# A filter with nothing behind it is dimmed rather than hidden - a chip that vanishes
		# makes the row jump about, and "Wanted 0" is itself information.
		btn.add_theme_color_override("font_color",
			Color(1, 0.84, 0) if fid == _filter else (Color(0.45, 0.45, 0.45) if n == 0 else Color(0.8, 0.8, 0.8)))


func populate(skill: String, recipes: Array, materials: Dictionary, skill_level: int, post_bonus: int, job_bonus: Dictionary, selected_index: int, craft_quantity: int) -> void:
	if not is_inside_tree():
		return
	_current_skill = skill
	_recipes_all = recipes
	_apply_filter()
	# ⛑ THE SELECTION IS AN INDEX INTO THE FILTERED LIST. Carrying the caller's index straight
	# across would select a different recipe than the one the player clicked the moment a filter
	# is active - silently, and only for gated or material-short rows.
	_selected_index = _src_index.find(selected_index) if selected_index >= 0 else -1
	_materials = materials
	_craft_quantity = max(1, craft_quantity)

	_refresh_filter_chips()

	# Header
	if skill != "":
		_skill_label.text = "[%s Lv%d]" % [skill.capitalize(), skill_level]
		var col := _skill_color(skill)
		_skill_label.add_theme_color_override("font_color", col)
	else:
		_skill_label.text = ""

	var bonus_parts := []
	if post_bonus > 0:
		bonus_parts.append("[color=#00FFFF]Post +%d%%[/color]" % post_bonus)
	if job_bonus.get("quality_bonus", 0) > 0:
		bonus_parts.append("[color=#FFD700]Spec +%d%%[/color]" % job_bonus["quality_bonus"])
	_bonus_label.text = "  ".join(bonus_parts) if bonus_parts.size() > 0 else ""

	# Skill chip selection
	for sk in _skill_chip_buttons.keys():
		_skill_chip_buttons[sk].button_pressed = (sk == skill)

	_rebuild_recipe_list()
	_refresh_detail()


func _skill_color(skill: String) -> Color:
	for chip in SKILL_CHIPS:
		if chip["id"] == skill:
			return chip["color"]
	return Color(1, 1, 1)


func _rebuild_recipe_list() -> void:
	for child in _recipe_list_vbox.get_children():
		child.queue_free()
	_recipe_buttons.clear()

	if _recipes.is_empty():
		var lbl := Label.new()
		lbl.text = "No recipes available."
		lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		lbl.add_theme_font_size_override("font_size", 12)
		_recipe_list_vbox.add_child(lbl)
		return

	for i in range(_recipes.size()):
		var recipe = _recipes[i]
		var btn = _make_recipe_button(recipe, i)
		_recipe_list_vbox.add_child(btn)
		_recipe_buttons.append(btn)

	# Audit #8 Layer 7 — Coming Up preview footer mirroring the text-mode list.
	if not _upcoming_unlocks.is_empty():
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 6)
		_recipe_list_vbox.add_child(spacer)

		var header := Label.new()
		header.text = "── Coming Up ──"
		header.add_theme_color_override("font_color", Color(0.60, 0.80, 0.20))
		header.add_theme_font_size_override("font_size", 12)
		_recipe_list_vbox.add_child(header)

		for unlock in _upcoming_unlocks:
			var u_name := str(unlock.get("name", "Unknown"))
			var u_req := int(unlock.get("skill_required", 0))
			var u_type := str(unlock.get("output_type", ""))
			var u_away := int(unlock.get("levels_away", 0))
			var away_label := "%d level%s away" % [u_away, "" if u_away == 1 else "s"]
			var type_tag := " (%s)" % u_type if u_type != "" else ""
			var row := RichTextLabel.new()
			row.bbcode_enabled = true
			row.fit_content = true
			row.scroll_active = false
			row.add_theme_font_size_override("normal_font_size", 12)
			row.text = "  [color=#888888]Lv%d[/color] [color=#AAAAAA]%s[/color][color=#666666]%s[/color] [color=#9ACD32]— %s[/color]" % [u_req, u_name, type_tag, away_label]
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_recipe_list_vbox.add_child(row)


func _make_recipe_button(recipe: Dictionary, index: int) -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0, 44)
	btn.toggle_mode = true
	btn.button_pressed = (index == _selected_index)
	btn.add_theme_font_size_override("font_size", 12)

	var name := str(recipe.get("name", "?"))
	var skill_req := int(recipe.get("skill_required", 1))
	var is_locked: bool = recipe.get("locked", false)
	var is_specialist_gated: bool = recipe.get("specialist_gated", false)
	var can_craft: bool = recipe.get("can_craft", false)

	var label := name
	if is_locked:
		# ⚡ A LOCKED ROW IS STILL CLICKABLE. Owner 2026-09-18, after being pointed at
		# commissions twice: *"I still don't understand how to put in a commission. Lets say I want
		# a Stone Wall... I see Locked Stone Wall (Lv3) on the left. I can't click it because it is
		# locked so how could I put a commission out for one?"*
		#
		# ⛑ EXACTLY. Disabling the row disabled the ONE thing a player under the skill
		# requirement can do about it - ask somebody else to make it. The CRAFT button stays
		# disabled, because they still cannot make it; the detail pane and Post Job do not.
		label = "Locked  %s (Lv%d)" % [name, skill_req]
		btn.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
	elif is_specialist_gated:
		# ⛑ COMMISSIONABLE ROWS ARE NOT DISABLED. Owner 2026-09-18: *"All I see are the locked
		# items that I can't click."* 43% of recipes are specialist-gated, so a flat un-clickable
		# row was the most common thing this list showed - and there is now something to DO with
		# every one of them: commission it from a post NPC, or post the job for another player.
		if recipe.get("can_commission", false):
			label = "%s   commission %dv" % [name, int(recipe.get("commission_fee", 0))]
			btn.add_theme_color_override("font_color", Color(0.78, 0.64, 0.29))
		else:
			# Same reasoning as the locked row above: you cannot make it, which is precisely when
			# posting the job to a real crafter is the answer.
			label = "[Spec]  %s (Lv%d)" % [name, skill_req]
			btn.add_theme_color_override("font_color", Color(1.0, 0.45, 0.27))
	else:
		var color := Color(0, 1, 0) if can_craft else Color(0.7, 0.7, 0.7)
		btn.add_theme_color_override("font_color", color)
		var spec_tag = " ★" if recipe.get("specialist_only", false) else ""
		label = "%s%s  Lv%d" % [name, spec_tag, skill_req]
		# Demand shown where the crafter already looks — a commission board nobody opens is a
		# commission board nobody fills.
		var wanted := int(recipe.get("wanted_count", 0))
		if wanted > 0:
			label += "    ◆ %d wanted, up to %dv" % [wanted, int(recipe.get("wanted_best", 0))]
			btn.add_theme_color_override("font_color", Color(0.78, 0.64, 0.29))

	btn.text = label
	btn.pressed.connect(_on_recipe_pressed.bind(index))
	return btn


func _refresh_detail() -> void:
	var has_selection := _selected_index >= 0 and _selected_index < _recipes.size()
	_show_detail_empty(not has_selection)
	if not has_selection:
		return

	var recipe = _recipes[_selected_index]
	var name = str(recipe.get("name", "?"))
	var recipe_id := str(recipe.get("id", ""))
	var skill_req = int(recipe.get("skill_required", 1))
	var difficulty = int(recipe.get("difficulty", 10))
	var success_chance = int(recipe.get("success_chance", 50))
	var is_bulk = recipe.get("bulk_craftable", false) and int(recipe.get("max_craftable", 1)) > 1
	var max_qty = int(recipe.get("max_craftable", 1)) if is_bulk else 1
	var can_craft = recipe.get("can_craft", false)
	var is_locked = recipe.get("locked", false)
	var is_specialist_gated = recipe.get("specialist_gated", false)

	# Restore last-used boost for this recipe, if any.
	_boost_tier = String(_boost_memory.get(recipe_id, "none"))
	if not CraftingDatabase.BOOST_CONFIG.has(_boost_tier):
		_boost_tier = "none"

	# Boost forces quantity=1 (server enforces this too).
	if _boost_tier != "none":
		_craft_quantity = 1
	elif is_bulk:
		_craft_quantity = clampi(_craft_quantity, 1, max_qty)
	else:
		_craft_quantity = 1

	_detail_title.text = name

	# Resolve boost config for shift/no_poor/mat_mult.
	var boost_cfg: Dictionary = CraftingDatabase.BOOST_CONFIG[_boost_tier]
	var boost_shift: Dictionary = boost_cfg.get("shift", {})
	var boost_no_poor: bool = bool(boost_cfg.get("no_poor", false))
	var boost_mat_mult: float = float(boost_cfg.get("mat_mult", 1.0))

	var meta_lines := []
	# Audit #4 Slice 3.8 (v0.9.547) — "Quality Rating" replaces "Success". Crafts
	# never fail — this number is the roll pivot that controls where the quality
	# bands sit, not a chance of failure. Higher = better quality distribution.
	# ⚑ WHAT IT MAKES, BEFORE HOW TO MAKE IT — owner 2026-09-18: *"I left clicked Iron sword and
	# don't see any description about attack or comparing my weapon, only Skill req difficulty
	# quality materials etc."*
	#
	# ⛑ The description WAS here, but LAST - under skill, difficulty, the quality bands and the
	# market average - and the numbers that answer "is this better than what I am holding" were
	# not here at all. A player could read the whole pane and still not know what the item was.
	var ostats: Dictionary = recipe.get("output_stats", {}) if recipe.get("output_stats", null) is Dictionary else {}
	if not ostats.is_empty():
		var parts: Array = []
		for k in ostats.keys():
			var key := String(k)
			if key in ["level", "value", "durability", "weight"]:
				continue
			var v = ostats[k]
			if (v is int or v is float) and float(v) != 0.0:
				parts.append("[color=#99FF99]%s %d[/color]" % [key.replace("_", " "), int(v)])
		if not parts.is_empty():
			meta_lines.append("[color=#87CEEB]Makes:[/color] %s   [color=#888888](Lv %d, at Standard)[/color]" % [
				"   ".join(parts), int(ostats.get("level", 1))])
			# ⛑ AND AGAINST WHAT YOU WEAR, because "118 attack" means nothing without the number
			# it would replace. This is the decision the pane exists to serve.
			var slot := String(recipe.get("output_slot", ""))
			if client_ref != null and slot != "":
				var worn = client_ref.character_data.get("equipped", {}).get(slot, null)
				if worn is Dictionary and not (worn as Dictionary).is_empty():
					var wb: Dictionary = preload("res://shared/character.gd").item_stat_bonuses(worn)
					var cmp_parts: Array = []
					for k2 in ["attack", "defense"]:
						if ostats.has(k2):
							var d := int(ostats[k2]) - int(wb.get(k2, 0))
							var col := "#99FF99" if d > 0 else ("#FF9999" if d < 0 else "#BBBBBB")
							cmp_parts.append("[color=%s]%s %+d[/color]" % [col, k2, d])
					if not cmp_parts.is_empty():
						meta_lines.append("[color=#87CEEB]vs your %s:[/color] %s" % [slot, "   ".join(cmp_parts)])
	var desc_top := str(recipe.get("description", ""))
	if desc_top != "":
		meta_lines.append("[color=#BBBBBB]%s[/color]" % desc_top)
	if is_specialist_gated:
		if recipe.get("can_commission", false):
			meta_lines.append("[color=#C8A24A]Specialist work — you have the skill but not the focus. Commission it for %d Valor, or Post Job to have a player make it.[/color]" % int(recipe.get("commission_fee", 0)))
		else:
			meta_lines.append("[color=#FF6666]Specialist work — reach the skill yourself before you can commission it.[/color]")
	meta_lines.append("")
	meta_lines.append("[color=#87CEEB]Skill Req:[/color] %d   [color=#87CEEB]Difficulty:[/color] %d   [color=#87CEEB]Quality Rating:[/color] %d%%" % [skill_req, difficulty, success_chance])
	# ⛑ ONE PERCENT SIGN. `%%` only collapses when the string is FORMATTED - this append has no
	# `% [...]` after it, so it rendered literally as "50%% stats" on screen. Caught by looking at
	# a screenshot; no amount of reading the line makes it obvious.
	meta_lines.append("[color=#888888]Crafts always produce an item — even a Poor roll gives 50% stats.[/color]")
	# Audit #8 Layer 5 — quality odds bar (recomputed live when boost changes).
	# Server seeds `quality_odds` for the base distribution; recompute via
	# CraftingDatabase.quality_distribution when a boost is active.
	var odds: Dictionary
	if _boost_tier == "none":
		odds = recipe.get("quality_odds", {})
		if odds == null or typeof(odds) != TYPE_DICTIONARY or odds.is_empty():
			odds = CraftingDatabase.quality_distribution(success_chance)
	else:
		odds = CraftingDatabase.quality_distribution(success_chance, boost_shift, boost_no_poor)
	if odds and typeof(odds) == TYPE_DICTIONARY and not odds.is_empty():
		var p = int(odds.get("poor", 0))
		var s = int(odds.get("standard", 0))
		var f = int(odds.get("fine", 0))
		var m = int(odds.get("masterwork", 0))
		meta_lines.append("[color=#FFFFFF]Poor:[/color] %d%%   [color=#00FF00]Standard:[/color] %d%%   [color=#0070DD]Fine:[/color] %d%%   [color=#A335EE]Masterwork:[/color] %d%%" % [p, s, f, m])
	# Audit #8 Layer 6 (v0.9.445) — sell-value preview from #9's rolling market avg.
	# 0 means no sales recorded yet — skip rendering rather than mislead with zero.
	var market_avg := int(recipe.get("avg_market_price", 0))
	if market_avg > 0:
		meta_lines.append("[color=#FFD700]Recent market avg:[/color] %d Valor [color=#888888](rolling)[/color]" % market_avg)
	_detail_meta.text = "\n".join(meta_lines)

	# Materials (scaled by boost mat_mult × quantity; boost forces qty=1, so
	# the two never compound). Server uses ceili — mirror exactly.
	var mat_scale := boost_mat_mult * float(_craft_quantity)
	var mat_lines := []
	var materials = recipe.get("materials", {})
	for mat_id in materials.keys():
		var required = ceili(float(int(materials[mat_id])) * mat_scale)
		var owned = _resolve_owned(mat_id)
		var mat_name = _material_display_name(mat_id)
		var color = "#00FF00" if owned >= required else "#FF4444"
		mat_lines.append("  [color=%s]%s: %d/%d[/color]" % [color, mat_name, owned, required])
	var mat_header := "Materials"
	if _boost_tier != "none":
		mat_header += " (boosted)"
	elif _craft_quantity > 1:
		mat_header += " (x%d)" % _craft_quantity
	if mat_lines.size() > 0:
		_detail_materials.text = "[color=#87CEEB]%s:[/color]\n%s" % [mat_header, "\n".join(mat_lines)]
	else:
		_detail_materials.text = "[color=#888888](no materials needed)[/color]"

	# Refresh boost selector buttons (labels, costs, pressed state, disabled).
	_refresh_boost_buttons(can_craft, is_locked, is_specialist_gated)

	# Quantity row — hidden when a boost is active (server forces qty=1).
	_qty_row.visible = is_bulk and not is_locked and not is_specialist_gated and _boost_tier == "none"
	_qty_label.text = str(_craft_quantity)
	_qty_minus.disabled = _craft_quantity <= 1
	_qty_plus.disabled = _craft_quantity >= max_qty
	_qty_max.disabled = _craft_quantity == max_qty

	if _post_job_button:
		# ⛑ SHOWN ON EVERY RECIPE THIS PLAYER CANNOT MAKE, not only the specialist ones. A
		# recipe above your crafting skill is the commonest reason to want somebody else to make
		# something, and it was the one case with no button. The server applies the same rule: it
		# refuses a commission only when you could have made the thing yourself.
		_post_job_button.visible = is_locked or is_specialist_gated
		_post_job_button.text = "Post Job for a Player"
		_post_job_button.tooltip_text = ("You cannot make this yet. Offer it to other crafters -"
			+ " they supply the materials and their own quality, and a good crafter beats the NPC"
			+ " job, which is always Standard.")

	# Craft button state
	if is_locked:
		_craft_button.text = "Locked - %s Lv%d needed" % [str(recipe.get("skill_name", "skill")).capitalize(), skill_req]
		_craft_button.disabled = true
	elif is_specialist_gated:
		# ⛑ A GATED RECIPE IS AN OFFER NOW, NOT A REFUSAL. "Specialist Job Required" was a dead
		# end on 43% of the list; a player with the skill can pay a post NPC to do the work, or
		# post the job for a real crafter.
		if recipe.get("can_commission", false):
			# Same shape as the craft path: the option stays VISIBLE and the button says why it
			# cannot be pressed, instead of the whole route vanishing because a material is short.
			if not _can_afford_with_boost(materials, boost_mat_mult, 1):
				_craft_button.text = "COMMISSION - missing materials"
				_craft_button.disabled = true
			else:
				_craft_button.text = "COMMISSION  %d Valor" % int(recipe.get("commission_fee", 0))
				_craft_button.disabled = false
		else:
			_craft_button.text = "Specialist Job Required (Lv%d)" % skill_req
			_craft_button.disabled = true
	elif not _can_afford_with_boost(materials, boost_mat_mult, _craft_quantity):
		# Boost may put a craftable recipe out of reach — recompute against
		# the boosted cost so the button reflects the real state.
		_craft_button.text = "Missing Materials"
		_craft_button.disabled = true
	elif not can_craft and _boost_tier == "none":
		_craft_button.text = "Missing Materials"
		_craft_button.disabled = true
	else:
		var prefix := ""
		if _boost_tier == "refined":
			prefix = "REFINED "
		elif _boost_tier == "master":
			prefix = "MASTER "
		_craft_button.text = "%sCRAFT %dx" % [prefix, _craft_quantity] if _craft_quantity > 1 else "%sCRAFT" % prefix
		_craft_button.disabled = false


func _refresh_boost_buttons(can_craft: bool, is_locked: bool, is_specialist_gated: bool) -> void:
	"""Sync boost button labels (with cost annotation), pressed state, and
	disabled state. Disabled when the recipe is locked/gated or when the
	boosted material cost is unaffordable."""
	var hide_row: bool = is_locked or is_specialist_gated
	_boost_row.visible = not hide_row
	if hide_row:
		return
	var recipe = _recipes[_selected_index]
	var materials: Dictionary = recipe.get("materials", {})
	for tier_def in BOOST_TIERS:
		var tier_id: String = tier_def["id"]
		var btn: Button = _boost_buttons[tier_id]
		var cfg: Dictionary = CraftingDatabase.BOOST_CONFIG[tier_id]
		var mat_mult: float = float(cfg.get("mat_mult", 1.0))
		var label: String = tier_def["label"]
		if tier_id == "refined":
			label += " (+50% mats)"
		elif tier_id == "master":
			label += " (+150% mats)"
		btn.text = label
		btn.button_pressed = (tier_id == _boost_tier)
		# Disable a tier when the player can't afford its material cost.
		# `can_craft` (None tier) is gated by the server's check (which already
		# includes pulling from your own listings), so trust it for "none".
		if tier_id == "none":
			btn.disabled = not can_craft and _boost_tier != "none"
		else:
			btn.disabled = not _can_afford_with_boost(materials, mat_mult, 1)


func _can_afford_with_boost(materials: Dictionary, mat_mult: float, qty: int) -> bool:
	"""Mirror server's per-material check using ceili. Group keys (@stat:tier)
	use the client's group-counting helper via client_ref."""
	for mat_id in materials.keys():
		var required := ceili(float(int(materials[mat_id])) * mat_mult * float(qty))
		if _resolve_owned(mat_id) < required:
			return false
	return true


func _show_detail_empty(empty: bool) -> void:
	if not _detail_empty:
		return
	_detail_empty.visible = empty
	_detail_title.visible = not empty
	_detail_meta.visible = not empty
	_detail_materials.visible = not empty
	_qty_row.visible = not empty and _qty_row.visible
	if _boost_row:
		_boost_row.visible = not empty and _boost_row.visible
	_craft_button.visible = not empty
	# The second route's button and its price row belong to a SELECTION too - left visible with
	# nothing selected, Post Job would post the last recipe you looked at.
	if _post_job_button:
		_post_job_button.visible = _post_job_button.visible and not empty
	if _commission_row:
		_commission_row.visible = _commission_row.visible and not empty
	if _commission_hint:
		_commission_hint.visible = _commission_hint.visible and not empty


func _resolve_owned(mat_id: String) -> int:
	if mat_id.begins_with("@"):
		if client_ref and client_ref.has_method("_count_group_materials"):
			return int(client_ref._count_group_materials(mat_id))
		return 0
	return int(_materials.get(mat_id, 0))


func _material_display_name(mat_id: String) -> String:
	if mat_id.begins_with("@"):
		if client_ref and client_ref.has_method("_get_group_material_label"):
			return client_ref._get_group_material_label(mat_id)
		return mat_id
	if client_ref and client_ref.has_method("_get_simple_material_name"):
		return client_ref._get_simple_material_name(mat_id)
	return mat_id.capitalize().replace("_", " ")


# === Internal callbacks ===

func _on_skill_chip_pressed(skill_id: String) -> void:
	# Re-pin selection in case user clicked the same chip
	for sk in _skill_chip_buttons.keys():
		_skill_chip_buttons[sk].button_pressed = (sk == skill_id)
	if skill_id != _current_skill:
		emit_signal("skill_changed", skill_id)


func _on_recipe_pressed(index: int) -> void:
	# A price row left open from the last recipe would post the wrong job.
	if _commission_row:
		_commission_row.visible = false
	if _commission_hint:
		_commission_hint.visible = false
	_selected_index = index
	# ⛑ THE PANEL ANSWERS ITS OWN CLICK. It used to only emit and wait for the client to draw the
	# detail - so anything the client declined to select left the pane reading "Select a recipe on
	# the left", which is exactly what the owner photographed. The panel already holds the row it
	# was clicked on; nothing has to come back for it to show it.
	_refresh_detail()
	# And only ONE row can look selected. These are toggle buttons, so without this every row a
	# player clicked stayed dark - four of them in the screenshot.
	for i in range(_recipe_buttons.size()):
		var b = _recipe_buttons[i]
		if b is Button:
			(b as Button).button_pressed = (i == index)
	# Emit the index into the list the CLIENT holds, not the filtered one shown here.
	var src: int = int(_src_index[index]) if index >= 0 and index < _src_index.size() else index
	emit_signal("recipe_selected", src)


func _on_qty_minus_pressed() -> void:
	if _craft_quantity > 1:
		_craft_quantity -= 1
		_refresh_detail()
		emit_signal("quantity_changed", _craft_quantity)


func _on_qty_plus_pressed() -> void:
	if _selected_index < 0 or _selected_index >= _recipes.size():
		return
	var max_qty := int(_recipes[_selected_index].get("max_craftable", 1))
	if _craft_quantity < max_qty:
		_craft_quantity += 1
		_refresh_detail()
		emit_signal("quantity_changed", _craft_quantity)


func _on_qty_max_pressed() -> void:
	if _selected_index < 0 or _selected_index >= _recipes.size():
		return
	var max_qty := int(_recipes[_selected_index].get("max_craftable", 1))
	if max_qty > 1:
		_craft_quantity = max_qty
		_refresh_detail()
		emit_signal("quantity_changed", _craft_quantity)


func _on_craft_pressed() -> void:
	if _selected_index < 0:
		return
	emit_signal("craft_pressed", _selected_index, _craft_quantity)


func _on_close_pressed() -> void:
	emit_signal("close_requested")


func _on_boost_tier_pressed(tier_id: String) -> void:
	"""Audit #4 Slice 2 — switch boost tier on the active recipe. Persists to
	per-recipe memory, redraws odds + material costs, and notifies client.gd."""
	if not CraftingDatabase.BOOST_CONFIG.has(tier_id):
		tier_id = "none"
	if _selected_index < 0 or _selected_index >= _recipes.size():
		return
	var recipe = _recipes[_selected_index]
	var recipe_id := str(recipe.get("id", ""))
	_boost_tier = tier_id
	if recipe_id != "":
		_boost_memory[recipe_id] = tier_id
	_refresh_detail()
	emit_signal("boost_tier_changed", tier_id)


# === Public API for client.gd to keep its state in sync ===

func get_boost_tier() -> String:
	return _boost_tier


func set_boost_tier(tier_id: String) -> void:
	"""External entry point — used by the text-mode hotkey path so both
	surfaces share state. No-op if the tier doesn't exist."""
	if not CraftingDatabase.BOOST_CONFIG.has(tier_id):
		return
	_boost_tier = tier_id
	if _selected_index >= 0 and _selected_index < _recipes.size():
		var recipe = _recipes[_selected_index]
		var recipe_id := str(recipe.get("id", ""))
		if recipe_id != "":
			_boost_memory[recipe_id] = tier_id
	_refresh_detail()
