extends Control
class_name MenuTreePanel

const PanelCloseKeysScript := preload("res://client/panel_close_keys.gd")

## Everything the game can do, in one place, as a two-level tree.
##
## Owner 2026-09-17: *"all slash commands should be accessible through a UI element that makes
## sense. If we don't have a place for it we need to build one in a tree structure that makes
## sense and doesn't crowd our UI or cause confusion."*
##
## ⛑ WHY A TREE AND NOT MORE BUTTONS. The shortcut row already carries fifteen, which is the
## crowding the owner named. Thirty more capabilities cannot go there. A category list on the left
## and its entries on the right is two clicks to anything, one screen wide, and adding a
## capability costs a row in a table rather than a button on a strip that is already full.
##
## ⛑ IT DOES NOT REPLACE ANYTHING. Every existing shortcut and panel still works and is still
## where it was; this is an ADDITIONAL door, and the home for the capabilities that had none. A
## reorganisation that moved the buttons people already know would be a second change wearing the
## same name, and the audit has not earned that yet.
##
## The panel owns no behaviour. Every entry is an action id that `client.gd` already dispatches -
## the same ids the shortcut row and the action bar use - so this file cannot drift from what the
## rest of the UI does, and nothing here sends a protocol message.

signal close_requested
signal action_chosen(action_id: String)

## category -> [[label, action_id, hint], ...]
##
## The order is the order they are drawn. Categories are the nouns a player thinks in - what I am,
## where I am, who else is here, what I own, and how to get help - rather than the order the
## features were built in.
const TREE: Array = [
	["Character", [
		["Stats", "stats_shortcut", "Attributes, and spending points"],
		["Deck", "deck_shortcut", "Your combat cards"],
		["Last Fight Log", "last_fight_log", "The blow-by-blow of your last battle"],
		["Companions", "companions", "Companions and eggs"],
		["Inventory", "inventory_shortcut", "Carried items"],
		["Pouch", "pouch_shortcut", "Materials and catches"],
		["Titles", "title", "Claim and wear titles"],
		["Jobs", "jobs_shortcut", "Gathering and crafting skills"],
	]],
	["World", [
		["Atlas", "atlas_shortcut", "Dungeons you know of"],
		["Quests", "quests_shortcut", "Your quest log"],
		["Bounty Board", "bounty_board", "Bounties posted on players"],
		["Zone Deck", "zone_deck", "What spawns where you are standing"],
		["The Crucible", "crucible", "Enter the Elder gauntlet"],
	]],
	["People", [
		["Friends", "social_shortcut", "Friends, requests and blocked players"],
		["Mentors", "mentor_list", "Volunteers who will help new players"],
		["Trade History", "trade_history", "Your recent trades"],
	]],
	["Clan", [
		["Clan", "clan_shortcut", "Members, ranks and invitations"],
		["Clan Vault", "clan_vault", "Shared storage"],
		["Shared Posts", "clan_posts", "Posts your clanmates have shared"],
		["Set Description", "clan_set_desc", "What your clan is for"],
		["Set Motto", "clan_set_motto", "A line under the name"],
		["Set Colour", "clan_set_color", "The clan's colour"],
	]],
	["Your Post", [
		["Post Status", "post_shortcut", "Guards, food and threat"],
		["Build", "build_shortcut", "Place and remove structures"],
		["Home Stones", "stones_shortcut", "Send things to your Sanctuary"],
	]],
	["Help", [
		["Help", "help", "The main help page"],
		["Browse Topics", "help_topics", "Help for every screen"],
		["Search Help", "help_search", "Find a topic by word"],
		["Report a Bug", "bug_report", "Sends your state with the report"],
	]],
	["Settings", [
		["Settings", "settings", "Keys, scaling and preferences"],
		["Clear Log", "clear_log", "Empty the game and chat logs"],
	]],
]

var _cat: int = 0
var _cat_box: VBoxContainer = null
var _item_box: VBoxContainer = null
var _hint: RichTextLabel = null


func _ready() -> void:
	top_level = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_layout()
	visible = false

	# ⛑ `top_level` DETACHES THIS CONTROL FROM ITS PARENT'S RECT, so PRESET_FULL_RECT has no
	# rectangle to resolve against and sizes the panel to NOTHING - which centres it at the
	# origin and shrinks the dim to the panel's own bounds. Size it from the viewport instead,
	# and again whenever the window changes.
	_fit_to_viewport()
	get_viewport().size_changed.connect(_fit_to_viewport)


func _fit_to_viewport() -> void:
	var r := get_viewport().get_visible_rect()
	position = Vector2.ZERO
	size = r.size



func open() -> void:
	visible = true
	_fit_to_viewport()
	_rebuild()


func close() -> void:
	visible = false
	close_requested.emit()


func _rebuild() -> void:
	if _cat_box == null:
		return
	# ⛑ NOT `disabled`. Greying the current category makes the thing you are looking at
	# the dimmest item on the panel, which reads as "unavailable" rather than "here".
	for i in range(_cat_box.get_child_count()):
		var b := _cat_box.get_child(i) as Button
		if b == null:
			continue
		var here := (i == _cat)
		b.text = ("▸ " if here else "   ") + String(TREE[i][0])
		b.add_theme_color_override("font_color",
			Color(1.0, 0.86, 0.45) if here else Color(0.78, 0.78, 0.78))
	for c in _item_box.get_children():
		c.queue_free()
	var entries: Array = TREE[_cat][1]
	for e in entries:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var b := Button.new()
		b.text = String(e[0])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_ALL
		b.custom_minimum_size = Vector2(190, 30)
		var act := String(e[1])
		b.pressed.connect(func():
			close()
			action_chosen.emit(act))
		# The hint follows FOCUS as well as hover, or a controller gets a menu of bare verbs.
		b.focus_entered.connect(func(): _set_hint(String(e[2])))
		b.mouse_entered.connect(func(): _set_hint(String(e[2])))
		row.add_child(b)
		var l := RichTextLabel.new()
		l.bbcode_enabled = true
		l.fit_content = true
		l.scroll_active = false
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.custom_minimum_size = Vector2(260, 24)
		l.append_text("[color=#8A8A8A]%s[/color]" % String(e[2]))
		row.add_child(l)
		_item_box.add_child(row)
	# ⛑ THE HINT IS SET DIRECTLY, not left to `focus_entered`. `grab_focus()` on a node
	# added THIS frame does not land - the freed buttons still hold focus until the frame
	# ends - so the signal never fired and the hint line kept showing the PREVIOUS
	# category's first entry. Visible only in the capture: the Clan page was explaining
	# "Attributes, and spending points".
	if entries.is_empty():
		_set_hint("")
		return
	_set_hint(String(entries[0][2]))
	var first := _item_box.get_child(0).get_child(0) as Control
	if first != null:
		first.call_deferred("grab_focus")


func _set_hint(text: String) -> void:
	if _hint:
		_hint.clear()
		_hint.append_text("[color=#9AA8B8]%s[/color]" % text)


func _build_layout() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(700, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.10, 0.16, 0.98)
	sb.border_color = Color(0.70, 0.66, 0.42, 1.0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := RichTextLabel.new()
	title.bbcode_enabled = true
	title.fit_content = true
	title.scroll_active = false
	title.add_theme_font_size_override("normal_font_size", 18)
	title.append_text("[b]Menu[/b]")
	vbox.add_child(title)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	vbox.add_child(cols)

	_cat_box = VBoxContainer.new()
	_cat_box.add_theme_constant_override("separation", 4)
	_cat_box.custom_minimum_size = Vector2(150, 300)
	cols.add_child(_cat_box)
	for i in range(TREE.size()):
		var cb := Button.new()
		cb.text = "   " + String(TREE[i][0])
		cb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		cb.focus_mode = Control.FOCUS_ALL
		cb.custom_minimum_size = Vector2(150, 30)
		var idx := i
		cb.pressed.connect(func():
			_cat = idx
			_rebuild())
		_cat_box.add_child(cb)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(480, 300)
	cols.add_child(scroll)
	_item_box = VBoxContainer.new()
	_item_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_box.add_theme_constant_override("separation", 4)
	scroll.add_child(_item_box)

	_hint = RichTextLabel.new()
	_hint.bbcode_enabled = true
	_hint.fit_content = true
	_hint.scroll_active = false
	_hint.custom_minimum_size = Vector2(0, 22)
	vbox.add_child(_hint)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)
	var close_btn := Button.new()
	close_btn.text = PanelCloseKeysScript.CLOSE_HINT
	close_btn.custom_minimum_size = Vector2(200, 32)
	close_btn.focus_mode = Control.FOCUS_ALL
	close_btn.pressed.connect(close)
	btn_row.add_child(close_btn)


## Every action id the tree offers — for the probe, which checks that `client.gd` dispatches all
## of them. A tree entry pointing at an id nothing handles is a dead button with a nice label.
static func all_action_ids() -> Array:
	var out: Array = []
	for cat in TREE:
		for e in cat[1]:
			out.append(String(e[1]))
	return out


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	if PanelCloseKeysScript.wants_close(event):
		get_viewport().set_input_as_handled()
		close()


func blocks_hotkeys() -> bool:
	"""Swallow the action bar's hotkeys while this is up - see `client._blocking_overlay_open`.

	The bar polls physical keys, not focus, so without this a number key does two things at once."""
	return visible
