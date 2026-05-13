extends Control
class_name AbilityPanel

# v0.9.322 — Combat Deck viewer (formerly Ability Loadout). Shows the
# player's deck composition: one card per unlocked ability with copy count,
# cost, mastery rank/uses, and description. The deck system replaced the
# slot-equip loadout, so this is now a view-only surface (the only mutation
# is the per-card Cull button from Slice 6c). Equipped slots / keybinds /
# choose-mode were removed.

signal close_requested
signal equip_requested(slot: int, ability_name: String)
signal unequip_requested(slot: int)
signal rebind_requested(slot: int)
signal cull_requested(ability_name: String)  # Slice 6c — remove one deck copy

const SLOT_COUNT := 6

# Audit #1 Slice 4 — off-affinity tag data. Mirrors the static archetype
# tables in character.gd so the panel can render an "Off-affinity" badge
# without an extra server round-trip. Universal abilities are exempt.
const _WARRIOR_ARCHETYPE_ABILITIES = ["power_strike", "war_cry", "shield_bash", "cleave", "berserk", "iron_skin", "devastate", "fortify", "rally"]
const _MAGE_ARCHETYPE_ABILITIES = ["magic_bolt", "blast", "forcefield", "teleport", "meteor", "haste", "paralyze", "banish"]
const _TRICKSTER_ARCHETYPE_ABILITIES = ["analyze", "distract", "pickpocket", "ambush", "vanish", "exploit", "perfect_heist", "sabotage", "gambit"]
const _UNIVERSAL_ABILITIES = ["cloak", "all_or_nothing", "forethought", "tactical_retreat", "shield", "teleport"]
const _OFF_AFFINITY_MULT_BY_RANK: Array = [0.75, 0.81, 0.87, 0.94, 1.0]

var client_ref = null

var _equipped: Array = []          # Array of 6 strings (ability name or "")
var _unlocked: Array = []          # Array of {name, display, level}
var _all: Array = []               # Array of {name, display, level}
var _slot_keys: Array = ["?", "?", "?", "?", "?", "?"]
var _player_level: int = 1
var _path_label: String = ""
var _player_path: String = "warrior"  # Slice 4: warrior/mage/trickster — drives off-affinity tag
var _choose_for_slot: int = -1     # -1 idle; 0-5 panel is in "pick ability for slot N" state
var _ability_uses: Dictionary = {} # Mastery Slice 1: ability_name → use count, drives rank display
var _deck_collection: Dictionary = {} # Slice 6c: ability_name → deck copy count

# Mastery rank thresholds + display (mirrors character.gd's MASTERY_RANK_*)
const MASTERY_RANK_THRESHOLDS: Array = [30, 150, 600, 2400]
const MASTERY_RANK_NAMES: Array = ["Untrained", "Novice", "Adept", "Expert", "Master"]
const MASTERY_RANK_DAMAGE_MULT: Array = [0.80, 0.90, 1.00, 1.10, 1.20]
const MASTERY_RANK_COLORS: Array = ["#888888", "#9ACD32", "#66CCFF", "#FFD700", "#FF6644"]

var _root_panel: PanelContainer
var _title_label: Label
var _path_label_node: RichTextLabel
var _slots_row: HBoxContainer
var _slot_cards: Array = []        # Array of PanelContainers, one per slot

var _status_label: RichTextLabel
var _cancel_choose_btn: Button
var _ability_grid: HFlowContainer
var _locked_label: RichTextLabel
var _locked_grid: HFlowContainer

var _ctx_menu: PopupMenu
var _ctx_slot: int = -1
const CTX_REPLACE := 1
const CTX_UNEQUIP := 2
const CTX_REBIND := 3


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

	# Header
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	root_vbox.add_child(header)

	_title_label = Label.new()
	_title_label.text = "Combat Deck"
	_title_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
	_title_label.add_theme_font_size_override("font_size", 18)
	header.add_child(_title_label)

	_path_label_node = RichTextLabel.new()
	_path_label_node.bbcode_enabled = true
	_path_label_node.fit_content = true
	_path_label_node.scroll_active = false
	_path_label_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path_label_node.custom_minimum_size = Vector2(0, 22)
	_path_label_node.add_theme_font_size_override("normal_font_size", 14)
	header.add_child(_path_label_node)

	# v0.9.322 — slot row / status row removed (deck system replaced
	# slot-equip). Status + cancel-choose still allocated as dummy instances
	# so legacy code paths that touch them don't NPE; they're never added to
	# the visible tree.
	_status_label = RichTextLabel.new()
	_status_label.bbcode_enabled = true
	_status_label.fit_content = true
	_status_label.scroll_active = false
	_cancel_choose_btn = Button.new()
	_cancel_choose_btn.visible = false

	# Deck cards header
	var avail_header := Label.new()
	avail_header.text = "Your Deck — copies, cost, and mastery per card:"
	avail_header.add_theme_color_override("font_color", Color(0.0, 1.0, 1.0))
	avail_header.add_theme_font_size_override("font_size", 13)
	root_vbox.add_child(avail_header)

	var avail_panel := _make_subpanel()
	avail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	avail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(avail_panel)

	var avail_scroll := ScrollContainer.new()
	avail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	avail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	avail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	avail_panel.add_child(avail_scroll)

	var avail_vbox := VBoxContainer.new()
	avail_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	avail_vbox.add_theme_constant_override("separation", 6)
	avail_scroll.add_child(avail_vbox)

	_ability_grid = HFlowContainer.new()
	_ability_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ability_grid.add_theme_constant_override("h_separation", 6)
	_ability_grid.add_theme_constant_override("v_separation", 6)
	avail_vbox.add_child(_ability_grid)

	_locked_label = RichTextLabel.new()
	_locked_label.bbcode_enabled = true
	_locked_label.fit_content = true
	_locked_label.scroll_active = false
	_locked_label.add_theme_font_size_override("normal_font_size", 12)
	_locked_label.text = "[color=#888888]Locked (level required):[/color]"
	avail_vbox.add_child(_locked_label)

	_locked_grid = HFlowContainer.new()
	_locked_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_locked_grid.add_theme_constant_override("h_separation", 6)
	_locked_grid.add_theme_constant_override("v_separation", 4)
	avail_vbox.add_child(_locked_grid)

	# Bottom action row
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	root_vbox.add_child(action_row)

	var hint := Label.new()
	hint.text = "Multi-copy cards stay in your hand longer. Click − Cull to remove one copy (min 1 always remains)."
	hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	hint.add_theme_font_size_override("font_size", 12)
	action_row.add_child(hint)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(spacer)

	var close_btn := Button.new()
	close_btn.text = "Close (Space)"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_font_size_override("font_size", 12)
	close_btn.custom_minimum_size = Vector2(0, 30)
	close_btn.pressed.connect(_on_close_pressed)
	action_row.add_child(close_btn)

	# Right-click context menu kept as dormant member (legacy code paths
	# may still reference it). Never popped under the new deck-view flow.
	_ctx_menu = PopupMenu.new()
	_ctx_menu.id_pressed.connect(_on_ctx_menu_id_pressed)
	add_child(_ctx_menu)


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


func _make_slot_card(slot_index: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(140, 90)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.set_meta("slot_index", slot_index)
	card.set_meta("name_label", null)
	card.set_meta("cost_label", null)
	card.set_meta("key_label", null)
	card.gui_input.connect(_on_slot_card_input.bind(slot_index))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vbox)

	# Header row: slot # + keybind
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 4)
	header_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(header_row)

	var slot_lbl := Label.new()
	slot_lbl.text = "Slot %d" % (slot_index + 1)
	slot_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	slot_lbl.add_theme_font_size_override("font_size", 11)
	slot_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(slot_lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(spacer)

	var key_lbl := RichTextLabel.new()
	key_lbl.bbcode_enabled = true
	key_lbl.fit_content = true
	key_lbl.scroll_active = false
	key_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key_lbl.custom_minimum_size = Vector2(60, 18)
	key_lbl.add_theme_font_size_override("normal_font_size", 11)
	header_row.add_child(key_lbl)
	card.set_meta("key_label", key_lbl)

	var name_lbl := RichTextLabel.new()
	name_lbl.bbcode_enabled = true
	name_lbl.fit_content = true
	name_lbl.scroll_active = false
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.add_theme_font_size_override("normal_font_size", 13)
	vbox.add_child(name_lbl)
	card.set_meta("name_label", name_lbl)

	var cost_lbl := RichTextLabel.new()
	cost_lbl.bbcode_enabled = true
	cost_lbl.fit_content = true
	cost_lbl.scroll_active = false
	cost_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_lbl.add_theme_font_size_override("normal_font_size", 11)
	vbox.add_child(cost_lbl)
	card.set_meta("cost_label", cost_lbl)

	return card


# === Public API ===

func populate(equipped: Array, unlocked: Array, all_abilities: Array, slot_keys: Array, player_level: int, path_label: String, ability_uses: Dictionary = {}, deck_collection: Dictionary = {}, player_path: String = "warrior") -> void:
	if not is_inside_tree():
		return
	_equipped = equipped
	_unlocked = unlocked
	_all = all_abilities
	_slot_keys = slot_keys
	_player_level = player_level
	_path_label = path_label
	_player_path = player_path
	_ability_uses = ability_uses
	_deck_collection = deck_collection
	# Reset choose state on data refresh (server sent new abilities → likely an equip/unequip just landed)
	_choose_for_slot = -1
	_path_label_node.text = path_label
	_update_status()
	_cancel_choose_btn.visible = false
	_rebuild_slots()
	_rebuild_abilities()

func update_deck_collection(deck_collection: Dictionary) -> void:
	"""Slice 6c — refresh just the deck counts after a cull, without a full
	populate() round-trip. Called from the client when cull_ability_card_result
	arrives. Cheaper than re-running populate (which would rebuild slots too)."""
	_deck_collection = deck_collection
	if is_inside_tree():
		_rebuild_abilities()

func _get_ability_rank(ability_name: String) -> int:
	"""Compute mastery rank from use count using same thresholds as character.gd."""
	var uses = int(_ability_uses.get(ability_name, 0))
	var rank = 0
	for threshold in MASTERY_RANK_THRESHOLDS:
		if uses >= int(threshold):
			rank += 1
		else:
			break
	return rank

func _get_rank_progress_text(ability_name: String) -> String:
	"""Returns BBCode progress text: 'R2 Adept (45/200)' or 'R4 Master ★' at cap."""
	var uses = int(_ability_uses.get(ability_name, 0))
	var rank = _get_ability_rank(ability_name)
	var name = MASTERY_RANK_NAMES[rank] if rank < MASTERY_RANK_NAMES.size() else "Master"
	var color = MASTERY_RANK_COLORS[rank] if rank < MASTERY_RANK_COLORS.size() else "#FFFFFF"
	if rank >= MASTERY_RANK_THRESHOLDS.size():
		return "[color=%s]R%d %s ★[/color]" % [color, rank, name]
	var threshold = int(MASTERY_RANK_THRESHOLDS[rank])
	return "[color=%s]R%d %s (%d/%d)[/color]" % [color, rank, name, uses, threshold]


# === Internal rendering ===

func _update_status() -> void:
	if _choose_for_slot >= 0:
		_status_label.text = "[color=#FFD700]Click an unlocked ability below to assign to Slot %d[/color]" % (_choose_for_slot + 1)
	else:
		_status_label.text = ""


func _rebuild_slots() -> void:
	# v0.9.322 — slot row removed under the deck-view rework. Keep the
	# function callable for legacy paths but bail out if no cards exist.
	if _slot_cards.is_empty():
		return
	for i in range(SLOT_COUNT):
		var card: PanelContainer = _slot_cards[i]
		var sb := StyleBoxFlat.new()
		var is_target := (i == _choose_for_slot)
		var has_ability := i < _equipped.size() and str(_equipped[i]) != "" and str(_equipped[i]) != "null"
		if is_target:
			sb.bg_color = Color(0.13, 0.10, 0.04, 0.95)
			sb.border_color = Color(1.0, 0.84, 0.0, 0.9)
			sb.set_border_width_all(2)
		elif has_ability:
			sb.bg_color = Color(0.07, 0.10, 0.07, 0.95)
			sb.border_color = Color(0.0, 0.7, 0.5, 0.7)
			sb.set_border_width_all(1)
		else:
			sb.bg_color = Color(0.05, 0.05, 0.05, 0.95)
			sb.border_color = Color(0.3, 0.3, 0.3, 0.6)
			sb.set_border_width_all(1)
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 6
		sb.content_margin_top = 4
		sb.content_margin_right = 6
		sb.content_margin_bottom = 4
		card.add_theme_stylebox_override("panel", sb)

		var key_label: RichTextLabel = card.get_meta("key_label")
		var name_label: RichTextLabel = card.get_meta("name_label")
		var cost_label: RichTextLabel = card.get_meta("cost_label")
		var key_text = str(_slot_keys[i]) if i < _slot_keys.size() else "?"
		key_label.text = "[color=#FFAA00][%s][/color]" % key_text

		if has_ability:
			var ab_name = str(_equipped[i])
			var info := _find_ability(ab_name)
			var disp = str(info.get("display", _humanize(ab_name)))
			name_label.text = "[color=#00FF00]%s[/color]  %s" % [disp, _get_rank_progress_text(ab_name)]
			cost_label.text = _cost_text_for(ab_name)
			card.tooltip_text = _tooltip_for(ab_name)
		else:
			name_label.text = "[color=#666666]Empty[/color]"
			cost_label.text = ""
			card.tooltip_text = "Empty slot — click to assign an ability."


func _rebuild_abilities() -> void:
	for child in _ability_grid.get_children():
		child.queue_free()
	for child in _locked_grid.get_children():
		child.queue_free()

	var unlocked_names := {}
	for u in _unlocked:
		unlocked_names[str(u.get("name", ""))] = true

	var locked_count := 0
	for ability in _all:
		# v0.9.423 — non_combat abilities (Cloak, Teleport) are utility
		# triggers used outside combat. They shouldn't appear in the combat
		# ability/deck panel because equipping them to a combat slot would
		# do nothing (the in-combat handlers refuse).
		if bool(ability.get("non_combat", false)):
			continue
		var ab_name = str(ability.get("name", ""))
		var req_level = int(ability.get("level", 1))
		var is_unlocked = unlocked_names.has(ab_name) or _player_level >= req_level
		if is_unlocked:
			var card := _make_ability_card(ability, true)
			_ability_grid.add_child(card)
		else:
			var card := _make_ability_card(ability, false)
			_locked_grid.add_child(card)
			locked_count += 1

	_locked_label.visible = locked_count > 0
	_locked_grid.visible = locked_count > 0


func _make_ability_card(ability: Dictionary, is_unlocked: bool) -> PanelContainer:
	var card := PanelContainer.new()
	var ab_name = str(ability.get("name", ""))
	var disp = str(ability.get("display", _humanize(ab_name)))
	var req_level = int(ability.get("level", 1))

	# v0.9.322 — deck-view styling. No more "equipped" green border; the
	# concept doesn't apply. Multi-copy cards get a faint lime tint so
	# they're spot-readable in the grid.
	var deck_count = int(_deck_collection.get(ab_name, 1)) if is_unlocked else 0
	var sb := StyleBoxFlat.new()
	if not is_unlocked:
		sb.bg_color = Color(0.05, 0.05, 0.05, 0.95)
		sb.border_color = Color(0.3, 0.3, 0.3, 0.5)
		sb.set_border_width_all(1)
	elif deck_count > 1:
		sb.bg_color = Color(0.07, 0.09, 0.05, 0.95)
		sb.border_color = Color(0.4, 0.6, 0.3, 0.7)
		sb.set_border_width_all(1)
	else:
		sb.bg_color = Color(0.06, 0.05, 0.04, 0.95)
		sb.border_color = Color(0.4, 0.34, 0.25, 0.7)
		sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6
	sb.content_margin_top = 4
	sb.content_margin_right = 6
	sb.content_margin_bottom = 4
	card.add_theme_stylebox_override("panel", sb)
	# v0.9.322 — taller cards fit a 2-line description below the meta row.
	card.custom_minimum_size = Vector2(260, 110)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	# Hover tooltip with the original ability description (long-form).
	card.tooltip_text = _tooltip_for(ab_name)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vbox)

	var name_lbl := RichTextLabel.new()
	name_lbl.bbcode_enabled = true
	name_lbl.fit_content = true
	name_lbl.scroll_active = false
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.add_theme_font_size_override("normal_font_size", 13)
	if not is_unlocked:
		name_lbl.text = "[color=#666666]%s[/color]" % disp
	else:
		name_lbl.text = "[color=#FFFFFF]%s[/color]" % disp
	vbox.add_child(name_lbl)

	var meta := RichTextLabel.new()
	meta.bbcode_enabled = true
	meta.fit_content = true
	meta.scroll_active = false
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_theme_font_size_override("normal_font_size", 11)
	if is_unlocked:
		# Mastery Slice 1 — cost + rank/progress on one line
		var cost = _cost_text_for(ab_name)
		var rank_str = _get_rank_progress_text(ab_name)
		var meta_text = ""
		if cost != "":
			meta_text = "%s    %s" % [cost, rank_str]
		else:
			meta_text = rank_str
		# Audit #1 Slice 4 — off-affinity tag. Tag color softens with rank so
		# players see the penalty shrinking as they grind use-progression.
		var off_pct = _off_affinity_pct_for(ab_name)
		if off_pct > 0:
			var tag_color = "#FF6347" if off_pct >= 19 else ("#FFAA33" if off_pct >= 6 else "#9ACD32")
			meta_text += "    [color=%s]Off-affinity (−%d%% dmg)[/color]" % [tag_color, off_pct]
		meta.text = meta_text
	else:
		# Slice 1 removed level gates; the locked branch is now only used
		# if a future slice gates abilities again (e.g., account unlocks).
		meta.text = "[color=#888888]Locked[/color]"
	vbox.add_child(meta)

	# v0.9.322 — description line on the card itself (was tooltip-only).
	# Helps players see at a glance what each deck card does.
	if is_unlocked:
		var desc := RichTextLabel.new()
		desc.bbcode_enabled = true
		desc.fit_content = true
		desc.scroll_active = false
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		desc.add_theme_font_size_override("normal_font_size", 10)
		desc.add_theme_color_override("default_color", Color(0.75, 0.72, 0.65))
		desc.text = _description_for(ab_name)
		desc.custom_minimum_size = Vector2(0, 36)
		vbox.add_child(desc)

	# Slice 6c — deck row (only for unlocked abilities). Shows deck copy count
	# and a cull button when there's more than 1 copy. Cull is min 1, so
	# baseline copies aren't removable. Hidden entirely for locked abilities
	# (they aren't in the collection yet).
	if is_unlocked:
		var deck_row := HBoxContainer.new()
		deck_row.add_theme_constant_override("separation", 6)
		deck_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(deck_row)

		var deck_lbl := Label.new()
		deck_lbl.add_theme_font_size_override("font_size", 11)
		if deck_count > 1:
			deck_lbl.text = "Deck × %d" % deck_count
			deck_lbl.add_theme_color_override("font_color", Color("#9ACD32"))
		else:
			deck_lbl.text = "Deck × 1"
			deck_lbl.add_theme_color_override("font_color", Color("#888888"))
		deck_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		deck_row.add_child(deck_lbl)

		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		deck_row.add_child(spacer)

		if deck_count > 1:
			var cull_btn := Button.new()
			cull_btn.text = "− Cull"
			cull_btn.tooltip_text = "Remove one copy of this card from your deck (min 1 always remains)."
			cull_btn.focus_mode = Control.FOCUS_NONE
			cull_btn.custom_minimum_size = Vector2(58, 20)
			cull_btn.add_theme_font_size_override("font_size", 10)
			cull_btn.pressed.connect(_on_cull_pressed.bind(ab_name))
			deck_row.add_child(cull_btn)

	card.gui_input.connect(_on_ability_card_input.bind(ab_name, is_unlocked))
	return card


func _on_cull_pressed(ability_name: String) -> void:
	emit_signal("cull_requested", ability_name)


func _cost_text_for(ability_name: String) -> String:
	if client_ref and client_ref.has_method("_get_ability_cost_text"):
		return str(client_ref._get_ability_cost_text(ability_name))
	return ""

func _tooltip_for(ability_name: String) -> String:
	"""Plain-text hover tooltip from the client. Falls back to a humanized
	display name if the client doesn't expose the helper yet."""
	if client_ref and client_ref.has_method("_get_ability_tooltip"):
		return str(client_ref._get_ability_tooltip(ability_name))
	return _humanize(ability_name)

func _ability_archetype(ability_name: String) -> String:
	"""Slice 4 — local archetype lookup. Returns warrior/mage/trickster/universal."""
	if ability_name in _UNIVERSAL_ABILITIES:
		return "universal"
	if ability_name in _WARRIOR_ARCHETYPE_ABILITIES:
		return "warrior"
	if ability_name in _MAGE_ARCHETYPE_ABILITIES:
		return "mage"
	if ability_name in _TRICKSTER_ARCHETYPE_ABILITIES:
		return "trickster"
	return "universal"

func _off_affinity_pct_for(ability_name: String) -> int:
	"""Returns the current off-affinity damage penalty as a positive int
	percentage (e.g., 13 means damage is reduced by 13%). 0 if on-affinity
	or universal."""
	var arch = _ability_archetype(ability_name)
	if arch == "universal" or arch == _player_path:
		return 0
	var rank = _get_ability_rank(ability_name)
	if rank < 0:
		rank = 0
	if rank >= _OFF_AFFINITY_MULT_BY_RANK.size():
		rank = _OFF_AFFINITY_MULT_BY_RANK.size() - 1
	var mult = float(_OFF_AFFINITY_MULT_BY_RANK[rank])
	return int(round((1.0 - mult) * 100.0))

func _description_for(ability_name: String) -> String:
	"""v0.9.322 — short BBCode description rendered inside the card. Pulls
	from the client's existing `_get_ability_description_text` helper which
	already feeds combat tooltips."""
	if client_ref and client_ref.has_method("_get_ability_description_text"):
		var raw = str(client_ref._get_ability_description_text(ability_name))
		if raw == "":
			return ""
		return "[color=#BFB5A4]%s[/color]" % raw
	return ""


func _find_ability(ab_name: String) -> Dictionary:
	for a in _all:
		if str(a.get("name", "")) == ab_name:
			return a
	for a in _unlocked:
		if str(a.get("name", "")) == ab_name:
			return a
	return {}


func _humanize(name: String) -> String:
	return name.replace("_", " ").capitalize()


# === Internal callbacks ===

func _on_slot_card_input(event: InputEvent, slot_index: int) -> void:
	if not (event is InputEventMouseButton):
		return
	if not event.pressed:
		return
	var has_ability := slot_index < _equipped.size() and str(_equipped[slot_index]) != "" and str(_equipped[slot_index]) != "null"
	if event.button_index == MOUSE_BUTTON_LEFT:
		if has_ability:
			_open_slot_ctx(slot_index, event.global_position)
		else:
			_enter_choose_mode(slot_index)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_open_slot_ctx(slot_index, event.global_position)


func _open_slot_ctx(slot_index: int, screen_pos: Vector2) -> void:
	_ctx_slot = slot_index
	_ctx_menu.clear()
	var has_ability := slot_index < _equipped.size() and str(_equipped[slot_index]) != "" and str(_equipped[slot_index]) != "null"
	if has_ability:
		_ctx_menu.add_item("Replace", CTX_REPLACE)
		_ctx_menu.add_item("Unequip", CTX_UNEQUIP)
	else:
		_ctx_menu.add_item("Assign Ability", CTX_REPLACE)
	_ctx_menu.add_separator()
	_ctx_menu.add_item("Rebind Key...", CTX_REBIND)
	_ctx_menu.position = Vector2i(screen_pos)
	_ctx_menu.popup()


func _on_ctx_menu_id_pressed(id: int) -> void:
	if _ctx_slot < 0:
		return
	match id:
		CTX_REPLACE:
			_enter_choose_mode(_ctx_slot)
		CTX_UNEQUIP:
			emit_signal("unequip_requested", _ctx_slot)
		CTX_REBIND:
			emit_signal("rebind_requested", _ctx_slot)
	_ctx_slot = -1


func _enter_choose_mode(slot_index: int) -> void:
	_choose_for_slot = slot_index
	_cancel_choose_btn.visible = true
	_update_status()
	_rebuild_slots()
	_rebuild_abilities()


func _on_cancel_choose_pressed() -> void:
	_choose_for_slot = -1
	_cancel_choose_btn.visible = false
	_update_status()
	_rebuild_slots()
	_rebuild_abilities()


func _on_ability_card_input(event: InputEvent, ability_name: String, is_unlocked: bool) -> void:
	if not (event is InputEventMouseButton):
		return
	if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not is_unlocked:
		return
	if _choose_for_slot < 0:
		# Idle click — no slot selected, nothing to do
		return
	var slot := _choose_for_slot
	# Reset local choose state immediately for snappy feedback;
	# the next populate() from the server response will reconfirm.
	_choose_for_slot = -1
	_cancel_choose_btn.visible = false
	emit_signal("equip_requested", slot, ability_name)


func _on_close_pressed() -> void:
	emit_signal("close_requested")
