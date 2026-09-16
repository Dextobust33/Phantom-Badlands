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
signal add_requested(ability_name: String)   # v0.9.678 slice 3 — restore a thinned card (0->1)

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
# 2026-09-11 — card instances: copies OWNED per card, in the deck or benched. A thinned copy is
# benched rather than destroyed, so `+` has to know one is waiting to come back.
var owned_counts: Dictionary = {}
# 2026-09-15 — {card: [{key, n, in_deck}]} for cards owned MORE than once. Each copy has its own
# uses and upgrades, so each is drawn as its own tile with its own thin/restore buttons.
var instances_by_card: Dictionary = {}

# Mastery rank thresholds + display (mirrors character.gd's MASTERY_RANK_*).
# v0.9.567 — extended to R6 (Legend, Mythic) + softened early thresholds.
const MASTERY_RANK_THRESHOLDS: Array = [10, 35, 100, 275, 650, 1400]  # v0.9.716 — synced to character.gd's compressed v0.9.701 curve (was stale [10,50,250,1200,4000,10000])
const MASTERY_RANK_NAMES: Array = ["Untrained", "Novice", "Adept", "Expert", "Master", "Legend", "Mythic"]
const MASTERY_RANK_DAMAGE_MULT: Array = [0.80, 0.90, 1.00, 1.10, 1.20, 1.30, 1.45]
const MASTERY_RANK_COLORS: Array = ["#888888", "#9ACD32", "#66CCFF", "#FFD700", "#FF6644", "#FF44FF", "#88FFFF"]

var _root_panel: PanelContainer
var _title_label: Label

# v0.9.504 — reusable HelpPanel attached to the header ? Help button.
var _help_panel: Control = null
var _deck_count_label: RichTextLabel = null  # v0.9.688 — live deck-size counter
var _traits_label: RichTextLabel = null      # #69 — class + race passive Trait cards
var _class_trait: Dictionary = {}            # #69 — {name, description, color}
var _race_trait: Dictionary = {}             # #69 — {name, description, color}
## ⚑ DRAG AND DROP, in two inner classes.
##
## Owner 2026-09-16: *"It would be nice to be able to drag and drop into and out of your deck on
## the deck screen. Maybe we can see the cards you have in your deck similar to how we see All
## Cards currently. Players should be able to scroll down if needed through their All Cards and
## Drag up into their Deck that displays above to add it or drag from their deck down into All
## cards to remove the card."*
##
## Godot's drag/drop is a set of VIRTUAL METHODS on a Control, so a tile built at runtime cannot
## take part without a script of its own. These two are the smallest thing that does it: one wraps
## a card so it can be picked up, one wraps a zone so a card can be let go over it.
##
## The −/+ buttons STAY. A drag is invisible until you try it, and this project's own rule is that
## a discoverable control comes first and the power-user gesture is a supplement, never the only
## way in. Both paths end in the same two signals.
class CardDrag extends PanelContainer:
	## One card tile, picked up by the mouse. `key` is the exact copy ("cleave#2"), so a drag moves
	## the card the player grabbed rather than "one of those".
	##
	## ⛑ A WRAPPER CANNOT BE A DRAG SOURCE, and that cost the first attempt.
	##
	## Godot asks for drag data from the control that TOOK THE PRESS - `gui.mouse_focus` - and does
	## not walk up the tree looking for a parent that implements `_get_drag_data`. (It does walk up
	## for drop TARGETS, which is why the zones work as containers.) The card tile itself is
	## `MOUSE_FILTER_STOP`, so it took every press and this wrapper was never asked. Measured, not
	## guessed: a synthesised drag (`--shots=deckdrag`) reported all three counters at zero, and the
	## hover chain showed `DeckCard(Control,mf=0) < VBoxContainer(mf=1) < PanelContainer(mf=1)` -
	## the wrapper present, in the chain, and skipped.
	##
	## So the press is watched on the CARD's own `gui_input` signal - which fires however the filter
	## is set - and once the pointer has moved far enough, `force_drag` starts a real Godot drag
	## from here. The tile keeps its click-to-flip, because a click that does not travel is still
	## a click.
	var key: String = ""
	var in_deck: bool = false
	var title: String = ""
	var panel_ref = null

	var _press_pos: Vector2 = Vector2.ZERO
	var _armed: bool = false
	const DRAG_SLOP := 8.0

	func _init() -> void:
		# Draws nothing: the tile inside supplies the whole look. A PanelContainer is used only
		# because it sizes itself to its child.
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		mouse_filter = Control.MOUSE_FILTER_PASS

	func watch(card: Control) -> void:
		"""Listen to the tile's own input, since the tile is what the mouse actually hits."""
		if card == null or not is_instance_valid(card):
			return
		if not card.gui_input.is_connected(_on_card_input):
			card.gui_input.connect(_on_card_input)
		# ⛑ AND THE TILE MUST NOT *STOP* THE MOUSE, or nothing can be dropped ON it.
		#
		# Godot finds a drop target by walking UP from the control under the cursor - and that
		# walk BREAKS at the first `MOUSE_FILTER_STOP` control it meets. The tile was STOP, so a
		# release anywhere over a card (which is most of a full zone) stopped dead on that card
		# and the zone behind it was never asked. Measured: the synthesised drag reported
		# `get_drag_data: 1, can_drop: 2` and no `drop` - it could be picked up and hovered, and
		# only the release did nothing, which is exactly the shape of that break.
		#
		# PASS keeps everything the tile had: it still receives its own input (click-to-flip, and
		# the signal this class listens to) and still becomes the mouse focus, but the walk can
		# now continue past it to the zone.
		card.mouse_filter = Control.MOUSE_FILTER_PASS

	func _on_card_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_armed = event.pressed
			_press_pos = (event as InputEventMouseButton).position
			return
		if not _armed or key == "":
			return
		if not (event is InputEventMouseMotion):
			return
		# Far enough to be a drag rather than a click. Godot has its own threshold for native
		# drags; this one guards the click-to-flip the tile already had.
		if ((event as InputEventMouseMotion).position - _press_pos).length() < DRAG_SLOP:
			return
		_armed = false
		if panel_ref != null:
			panel_ref._drag_debug["get_drag_data"] = int(panel_ref._drag_debug.get("get_drag_data", 0)) + 1
		force_drag({"kind": "pbcard", "key": key, "in_deck": in_deck}, _make_preview())

	func _make_preview() -> Control:
		# Follows the cursor, so it has to read at a glance and cost nothing to build.
		var prev := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.06, 0.09, 0.95)
		sb.border_color = Color(0.85, 0.7, 0.2)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(4)
		sb.set_content_margin_all(6)
		prev.add_theme_stylebox_override("panel", sb)
		var lbl := Label.new()
		lbl.text = ("↓ " if in_deck else "↑ ") + title
		lbl.add_theme_font_size_override("font_size", 12)
		prev.add_child(lbl)
		return prev


class CardZone extends PanelContainer:
	## A place a card can be dropped. `wants_in_deck` says which way this zone moves a card, so the
	## deck area and the collection area are the same class configured twice rather than two
	## near-identical ones that can drift apart.
	var panel_ref = null
	var wants_in_deck: bool = false

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		if panel_ref != null:
			panel_ref._drag_debug["can_drop"] = int(panel_ref._drag_debug.get("can_drop", 0)) + 1
		if not (data is Dictionary):
			return false
		if String((data as Dictionary).get("kind", "")) != "pbcard":
			return false
		# Dropping a card back where it already is does nothing, and saying so with the cursor is
		# better than accepting it and sending the server a no-op.
		return bool((data as Dictionary).get("in_deck", false)) != wants_in_deck

	func _drop_data(_at: Vector2, data: Variant) -> void:
		if panel_ref != null:
			panel_ref._drag_debug["drop"] = int(panel_ref._drag_debug.get("drop", 0)) + 1
		if panel_ref == null or not (data is Dictionary):
			return
		var k := String((data as Dictionary).get("key", ""))
		if k == "":
			return
		if wants_in_deck:
			panel_ref._on_add_pressed(k)
		else:
			panel_ref._on_cull_pressed(k)


var _deck_strip_label: RichTextLabel = null   # v0.9.716 — "Your Deck" strip header
## TEMP: which drag/drop virtuals actually fired. Read by `--shots=deckdrag`.
var _drag_debug: Dictionary = {}
## The two drop zones, so a probe can address them without walking the tree by index.
var _zone_deck: Control = null
var _zone_avail: Control = null
var _deck_strip: HFlowContainer = null        # v0.9.716 — at-a-glance visual of the cards actually in your deck
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

	# v0.9.504 — Help button + ability_page topic.
	var HelpPanelScript = load("res://client/help_panel.gd")
	_help_panel = HelpPanelScript.new()
	add_child(_help_panel)
	var help_btn = HelpPanelScript.make_help_button("ability_page", _help_panel)
	header.add_child(help_btn)

	# v0.9.678 slice 3 — deck rules line, always visible on the page.
	var rules_lbl := RichTextLabel.new()
	rules_lbl.bbcode_enabled = true
	rules_lbl.fit_content = true
	rules_lbl.scroll_active = false
	rules_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules_lbl.add_theme_font_size_override("normal_font_size", 12)
	rules_lbl.add_theme_color_override("default_color", Color("#B8A98C"))
	rules_lbl.text = "[color=#D4A017]Deck rules:[/color]  Max [b]3[/b] copies per card  ·  minimum [b]5[/b] cards  ·  [b]click a card to flip[/b] for details  ·  [b]every copy is its own card[/b] — it levels on its own uses, so bench the ones you are not building  ·  extra copies come from [b]dungeon rewards[/b] & [b]companion cards[/b]."
	root_vbox.add_child(rules_lbl)

	# v0.9.688 — live deck-size counter; updates as you +/- cards.
	_deck_count_label = RichTextLabel.new()
	_deck_count_label.bbcode_enabled = true
	_deck_count_label.fit_content = true
	_deck_count_label.scroll_active = false
	_deck_count_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_deck_count_label.add_theme_font_size_override("normal_font_size", 15)
	root_vbox.add_child(_deck_count_label)

	# #69 — Class + Race Trait cards. Surfaces the (previously invisible) class/race
	# passives as part of your deck identity. Always-on, non-draggable — they're the
	# "traits" your whole deck plays around.
	var traits_panel := _make_subpanel()
	traits_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(traits_panel)
	_traits_label = RichTextLabel.new()
	_traits_label.bbcode_enabled = true
	_traits_label.fit_content = true
	_traits_label.scroll_active = false
	_traits_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_traits_label.add_theme_font_size_override("normal_font_size", 13)
	traits_panel.add_child(_traits_label)

	# v0.9.716 — visual "Your Deck" strip. The catalog below shows EVERY card with
	# its copy count; this strip shows only the cards actually IN your deck, badged
	# by copies, so your real draw pile reads at a glance. Click a tile to thin one
	# copy (server enforces the 5-card minimum).
	_deck_strip_label = RichTextLabel.new()
	_deck_strip_label.bbcode_enabled = true
	_deck_strip_label.fit_content = true
	_deck_strip_label.scroll_active = false
	_deck_strip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_deck_strip_label.add_theme_font_size_override("normal_font_size", 13)
	root_vbox.add_child(_deck_strip_label)
	# ⚑ THE DECK IS A CARD GRID NOW, not a strip of chips - and it is a DROP ZONE.
	#
	# Owner 2026-09-16: *"Maybe we can see the cards you have in your deck similar to how we see
	# All Cards currently... Drag up into their Deck that displays above to add it or drag from
	# their deck down into All cards to remove the card."*
	#
	# So it uses the SAME tile builder as the collection below (`_make_deck_entry`), which is
	# what makes the two halves read as one screen you move cards between. It scrolls, because
	# a deck can outgrow two rows, and it keeps a minimum height so the zone is still a target
	# to drop onto when the deck is empty.
	var deck_zone := CardZone.new()
	deck_zone.panel_ref = self
	deck_zone.wants_in_deck = true
	deck_zone.add_theme_stylebox_override("panel", _subpanel_style())
	deck_zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# ⛑ THE TWO HALVES SHARE THE HEIGHT. A fixed 150px deck zone clipped its own second row -
	# measured, a card tile is ~158px, so a nine-card deck hid "Venom Fang ×2" completely and
	# the screen silently disagreed with its own "Cards in deck: 9". Both zones expand and
	# scroll instead, so the split follows the window rather than a guessed constant, and the
	# minimum is one full tile so an empty deck is still an obvious drop target.
	deck_zone.size_flags_vertical = Control.SIZE_EXPAND_FILL
	deck_zone.size_flags_stretch_ratio = 1.2
	# 215, measured rather than picked: a tile is ~160px, its rank line and − button another
	# ~30, and the panel adds 6px of padding top and bottom. At 180 the control row was cut
	# off the bottom of every deck card - the tiles were there and the − was not.
	deck_zone.custom_minimum_size = Vector2(0, 215)
	_zone_deck = deck_zone
	root_vbox.add_child(deck_zone)
	var deck_scroll := ScrollContainer.new()
	deck_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	deck_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# The scroll must not eat the drag: a ScrollContainer that grabs the mouse stops the zone
	# underneath ever seeing a drop.
	deck_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	deck_zone.add_child(deck_scroll)
	_deck_strip = HFlowContainer.new()
	_deck_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_deck_strip.add_theme_constant_override("h_separation", 6)
	_deck_strip.add_theme_constant_override("v_separation", 6)
	_deck_strip.mouse_filter = Control.MOUSE_FILTER_PASS
	deck_scroll.add_child(_deck_strip)

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
	avail_header.text = "All Cards — drag one UP into your deck to play it, or use +. Drag a deck card DOWN here to bench it."
	avail_header.add_theme_color_override("font_color", Color(0.0, 1.0, 1.0))
	avail_header.add_theme_font_size_override("font_size", 13)
	root_vbox.add_child(avail_header)

	# The other half of the gesture: dropping a card here takes it OUT of the deck.
	var avail_panel := CardZone.new()
	avail_panel.panel_ref = self
	avail_panel.wants_in_deck = false
	avail_panel.add_theme_stylebox_override("panel", _subpanel_style())
	avail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	avail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# The collection gets the larger share: it holds everything you are not playing, and it is
	# the half the owner asked to be able to scroll through.
	avail_panel.size_flags_stretch_ratio = 1.5
	_zone_avail = avail_panel
	root_vbox.add_child(avail_panel)

	var avail_scroll := ScrollContainer.new()
	avail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	avail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	avail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	avail_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
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
	# Reworded with the tiles. "Click − Cull to remove one copy" described a per-card COUNTER,
	# and a tile is one card now - − benches the card it sits under, by name.
	hint.text = "Each copy is its own card and ranks up on its own uses. − benches that card, + puts it back. Your deck keeps at least 5."
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


func _subpanel_style() -> StyleBoxFlat:
	"""The sub-panel look, as a style rather than a built node.

	Split out of `_make_subpanel` because the two drop ZONES are `CardZone`s, not plain
	PanelContainers, and they have to look identical to every other panel on the screen. One
	style, two node types - rather than a second hand-copied StyleBoxFlat that drifts."""
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.045, 0.035, 0.025, 0.7)
	sb.border_color = Color(0.4, 0.34, 0.25, 0.6)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6
	sb.content_margin_top = 6
	sb.content_margin_right = 6
	sb.content_margin_bottom = 6
	return sb


func _make_subpanel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _subpanel_style())
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

func populate(equipped: Array, unlocked: Array, all_abilities: Array, slot_keys: Array, player_level: int, path_label: String, ability_uses: Dictionary = {}, deck_collection: Dictionary = {}, player_path: String = "warrior", class_trait: Dictionary = {}, race_trait: Dictionary = {}) -> void:
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
	_class_trait = class_trait          # #69
	_race_trait = race_trait            # #69
	# Reset choose state on data refresh (server sent new abilities → likely an equip/unequip just landed)
	_choose_for_slot = -1
	_path_label_node.text = path_label
	_rebuild_traits()                   # #69
	_update_status()
	_cancel_choose_btn.visible = false
	_rebuild_slots()
	_rebuild_abilities()

func _rebuild_traits() -> void:
	# #69 — render the class + race passives as always-on Trait "cards" so players see
	# what their class/race actually does as part of their deck identity.
	if _traits_label == null:
		return
	var parts: Array = []
	if not _class_trait.is_empty() and String(_class_trait.get("name", "")) != "None":
		parts.append("[color=#C8A24A]◆ CLASS TRAIT[/color]  [color=%s][b]%s[/b][/color] — [color=#CFC3AA]%s[/color]" % [
			String(_class_trait.get("color", "#FFFFFF")), String(_class_trait.get("name", "")), String(_class_trait.get("description", ""))])
	if not _race_trait.is_empty() and String(_race_trait.get("name", "")) != "None":
		parts.append("[color=#7FB2FF]◆ RACE TRAIT[/color]  [color=%s][b]%s[/b][/color] — [color=#CFC3AA]%s[/color]" % [
			String(_race_trait.get("color", "#FFFFFF")), String(_race_trait.get("name", "")), String(_race_trait.get("description", ""))])
	if parts.is_empty():
		_traits_label.text = "[color=#808080]Your class & race passives will show here.[/color]"
	else:
		_traits_label.text = "\n".join(parts)

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
	var name = MASTERY_RANK_NAMES[rank] if rank < MASTERY_RANK_NAMES.size() else "Mythic"
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
	if _deck_strip != null:
		for child in _deck_strip.get_children():
			child.queue_free()

	var unlocked_names := {}
	for u in _unlocked:
		unlocked_names[str(u.get("name", ""))] = true

	var locked_count := 0
	var deck_total := 0
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
			# v0.9.678 slice 3 — combat-styled deck card (flip for details) + thin/restore controls.
			# v0.9.697 — default 0 (not 1): with curated starter decks, an ability
			# absent from the collection is BENCHED (addable), not in the deck.
			var deck_count := int(_deck_collection.get(ab_name, 0))
			deck_total += max(0, deck_count)
			# ⚑ ONE TILE PER CARD YOU CAN ACT ON — which is per INSTANCE, unless two instances are
			# genuinely identical.
			#
			# Owner 2026-09-16: *"If not all cards should appear individually. This will allow the
			# players to manage their deck properly. Say for example they have 2 Ambush cards each of
			# them should be separate cards that would need added to the deck and used to start
			# ranking up."* The 2026-09-15 version only split a card when MORE than one copy was
			# owned, and then split every copy unconditionally - so two untouched duplicates showed
			# as two tiles you could not tell apart, while a single copy kept a "x N/3" counter and a
			# dead "+". Grouping by `_stack_signature` gets both right from one rule.
			# ⚑ A CARD IS IN THE DECK GRID OR THE COLLECTION GRID - NEVER BOTH.
			#
			# That is what makes the drag unambiguous: every card is in exactly one place, so "drag it
			# up" and "drag it down" each have one meaning. The old screen listed every card in the
			# catalogue AND mirrored the in-deck ones into a strip, so a card appeared twice and
			# dragging the catalogue copy of a card already in the deck would have meant nothing.
			var _copies: Array = instances_by_card.get(ab_name, [])
			if not _copies.is_empty():
				var _groups: Array = _group_copies(_copies)
				for _g in _groups:
					var _rep: Dictionary = _g["rep"]
					var _n_in_group: int = int((_g["copies"] as Array).size())
					var _in_deck: bool = bool(_rep.get("in_deck", false))
					var _cp_ab: Dictionary = ability.duplicate()
					var _base_disp := str(ability.get("display", _humanize(ab_name)))
					# Named by copy number only when there is more than one tile to tell apart; a
					# stack of identical copies is named by its count, because that is what it is.
					if _n_in_group > 1:
						_cp_ab["display"] = "%s ×%d" % [_base_disp, _n_in_group]
					elif _groups.size() > 1:
						_cp_ab["display"] = "%s · copy %d" % [_base_disp, int(_rep.get("n", 1))]
					var _cp_entry := _make_deck_entry(_cp_ab, _n_in_group if _in_deck else 0, _rep)
					if _cp_entry != null:
						_add_card_tile(_cp_entry, _copy_target(ab_name, _rep), _in_deck,
							str(_cp_ab.get("display", _base_disp)))
				continue
			# No owned instances: a card the player can reach but does not hold a copy of, or a
			# companion LOANER - active in the deck with a copy count of 0 while the companion is
			# equipped. The loaner belongs in the DECK half, because that is where it is playing
			# from; it just cannot be dragged out, since benching a card you do not own is not a
			# thing (its key is passed anyway, and the server refuses).
			var _is_loaner := ab_name.begins_with("companion_card_") and not _deck_collection.has(ab_name)
			var entry := _make_deck_entry(ability, deck_count)
			if entry == null:
				entry = _make_ability_card(ability, true)  # fallback
			_add_card_tile(entry, ab_name, deck_count >= 1 or _is_loaner,
				str(ability.get("display", _humanize(ab_name))))
		else:
			var card := _make_ability_card(ability, false)
			_locked_grid.add_child(card)
			locked_count += 1

	_locked_label.visible = locked_count > 0
	_locked_grid.visible = locked_count > 0

	# v0.9.688 — refresh the deck-size counter (min 5 enforced server-side).
	if _deck_count_label != null:
		var _col := "#7AE07A" if deck_total >= 5 else "#FF8844"
		_deck_count_label.text = "[color=#B8A98C]Cards in deck:[/color] [color=%s][b]%d[/b][/color] [color=#7A6E58](minimum 5)[/color]" % [_col, deck_total]

	# v0.9.716/717 — headline for the visual deck strip. Count the tiles actually
	# shown (includes loaners) rather than only owned copies, and let the "Cards in
	# deck" line above carry the exact copy total to avoid a confusing double count.
	if _deck_strip_label != null:
		var _types := _deck_strip.get_child_count() if _deck_strip != null else 0
		if _types <= 0:
			_deck_strip_label.text = "[color=#00E5E5][b]⚔ Your Deck[/b][/color] [color=#FF8844]— empty. Drag a card up from All Cards below, or press its +.[/color]"
		else:
			_deck_strip_label.text = "[color=#00E5E5][b]⚔ Your Deck[/b][/color] [color=#B8A98C]— the cards you'll draw from. [i]Drag one down into All Cards to bench it[/i], or press its −.[/color]"

	# Every rebuild makes new tiles, so the zones have to be re-opened for drops each time -
	# a STOP control anywhere inside one is a patch where a release silently does nothing.
	_open_zone_for_drops(_zone_deck)
	_open_zone_for_drops(_zone_avail)


func _make_deck_pile_tile(ability: Dictionary, count: int, is_loaner: bool = false, copy: Dictionary = {}) -> Control:
	"""v0.9.716/717 — compact tile for the visual deck strip: category-tinted, shows
	the card name + a ×N copy badge (or a gold 'loan' tag for an active companion
	loaner). Click an OWNED tile to thin one copy (server enforces the 5-card
	minimum). No native tooltip — those hover boxes look bad; the catalog card below
	flips for full details."""
	var ab_name := str(ability.get("name", ""))
	var disp := str(ability.get("display", _humanize(ab_name)))
	var col := Color("#8C7656")
	var glyph := ""
	if client_ref and client_ref.has_method("get_ability_category_info"):
		var ci: Dictionary = client_ref.get_ability_category_info(ab_name)
		col = Color(str(ci.get("color", "#8C7656")))
		glyph = str(ci.get("glyph", ""))
	var tile := PanelContainer.new()
	tile.mouse_filter = Control.MOUSE_FILTER_STOP
	if not is_loaner:
		tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r * 0.18, col.g * 0.18, col.b * 0.18, 0.95)
	sb.border_color = Color("#C8A24A") if is_loaner else col
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	tile.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color("#C8A24A") if is_loaner else Color("#F0E6D2"))
	var prefix := (glyph + " ") if glyph != "" else ""
	var badge := ""
	if is_loaner:
		badge = "  (loan)"
	elif count > 1:
		badge = "  ×%d" % count
	lbl.text = "%s%s%s" % [prefix, disp, badge]
	tile.add_child(lbl)
	if not is_loaner:
		var _cull_target := _copy_command(ab_name, copy)
		tile.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_on_cull_pressed(_cull_target))
	return tile


func _copy_command(ab_name: String, copy: Dictionary) -> String:
	"""What to send to act on ONE copy: 'card#n' (the first copy is addressed as 'card#1', since
	its stored key is the bare id and a bare id means 'any copy'). The card itself when no copy."""
	if copy.is_empty():
		return ab_name
	return "%s#%d" % [ab_name, int(copy.get("n", 1))]


func _loaner_permanence_text(ability_name: String) -> String:
	"""v0.9.717 — 'X/N casts to keep' for an active loaner companion card (the
	permanence grind), or a 'ready to keep!' nudge once the threshold is met."""
	var dt = preload("res://shared/drop_tables.gd")
	var mtype := ability_name.trim_prefix("companion_card_").capitalize()
	var need := int(dt.companion_card_permanence_uses(mtype))
	var uses := int(_ability_uses.get(ability_name, 0))
	if need <= 0:
		return "use it to keep"
	if uses >= need:
		return "ready to keep! (%d/%d)" % [uses, need]
	return "%d/%d casts to keep" % [uses, need]


func _make_ability_card(ability: Dictionary, is_unlocked: bool) -> PanelContainer:
	var card := PanelContainer.new()
	var ab_name = str(ability.get("name", ""))
	var disp = str(ability.get("display", _humanize(ab_name)))
	var req_level = int(ability.get("level", 1))

	# v0.9.322 — deck-view styling. No more "equipped" green border; the
	# concept doesn't apply. Multi-copy cards get a faint lime tint so
	# they're spot-readable in the grid.
	# v0.9.425 — ability category color drives the border + a subtle bg tint
	# on unlocked cards (mirrors the combat hand strip theming). Multi-copy
	# tint kept as a small additional cue. Locked cards stay neutral muted.
	var deck_count = int(_deck_collection.get(ab_name, 0)) if is_unlocked else 0  # v0.9.697 benched = 0
	var category_info: Dictionary = {}
	if client_ref and client_ref.has_method("get_ability_category_info"):
		category_info = client_ref.get_ability_category_info(ab_name)
	var sb := StyleBoxFlat.new()
	if not is_unlocked:
		sb.bg_color = Color(0.05, 0.05, 0.05, 0.95)
		sb.border_color = Color(0.3, 0.3, 0.3, 0.5)
		sb.set_border_width_all(1)
	else:
		var category_color_hex = str(category_info.get("color", "#675444"))
		var tint_alpha = float(category_info.get("tint_alpha", 0.0))
		var base_bg := Color(0.06, 0.05, 0.04, 0.95)
		if tint_alpha > 0.0:
			var tint := Color(category_color_hex)
			tint.a = base_bg.a
			base_bg = base_bg.lerp(tint, tint_alpha)
		sb.bg_color = base_bg
		# Multi-copy emphasis: thicker border + a hint toward green.
		if deck_count > 1:
			var dup_tint := Color("#7AE07A")
			dup_tint.a = 1.0
			sb.border_color = Color(category_color_hex).lerp(dup_tint, 0.25)
			sb.set_border_width_all(2)
		else:
			sb.border_color = Color(category_color_hex)
			sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6
	sb.content_margin_top = 4
	sb.content_margin_right = 6
	sb.content_margin_bottom = 4
	card.add_theme_stylebox_override("panel", sb)

	# v0.9.425 — category glyph in the top-right corner. Skips when locked
	# (no category to advertise) or when the ability has no category info.
	if is_unlocked:
		var glyph_text = str(category_info.get("glyph", ""))
		if glyph_text != "":
			var glyph_lbl := Label.new()
			glyph_lbl.text = glyph_text
			glyph_lbl.add_theme_font_size_override("font_size", 18)
			var glyph_col := Color(str(category_info.get("color", "#FFFFFF")))
			glyph_col.a = 0.55
			glyph_lbl.add_theme_color_override("font_color", glyph_col)
			glyph_lbl.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			glyph_lbl.position = Vector2(-22, 2)
			glyph_lbl.size = Vector2(18, 18)
			glyph_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			glyph_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			glyph_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(glyph_lbl)
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
		# v0.9.678 — show copies out of the cap of 3; 0 = thinned out of the deck.
		# A tile is ONE card now, or a stack of identical ones - so it says whether it is in the
		# deck, not "x 1/3" out of a per-card cap the tile no longer represents.
		if deck_count >= 2:
			deck_lbl.text = "In deck ×%d" % deck_count
			deck_lbl.add_theme_color_override("font_color", Color("#9ACD32"))
		elif deck_count == 1:
			deck_lbl.text = "In deck"
			deck_lbl.add_theme_color_override("font_color", Color("#888888"))
		else:
			deck_lbl.text = "Benched"
			deck_lbl.add_theme_color_override("font_color", Color("#B05050"))
		deck_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		deck_row.add_child(deck_lbl)

		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		deck_row.add_child(spacer)

		# v0.9.678 slice 3 — thin (−) down to 0, and restore (+) 0→1 for free.
		# Extra copies (2nd/3rd) come from dungeon rewards / companion cards, so the
		# + is disabled (with an explanatory tooltip) once a card is already in.
		# Same two corrections as the deck entry above: no button that cannot be pressed, and
		# − sends the card id it is sitting under.
		if deck_count >= 1:
			var cull_btn := Button.new()
			cull_btn.text = "−"
			cull_btn.tooltip_text = "Bench this card (your deck keeps at least 5)."
			cull_btn.focus_mode = Control.FOCUS_NONE
			cull_btn.custom_minimum_size = Vector2(28, 20)
			cull_btn.add_theme_font_size_override("font_size", 12)
			cull_btn.pressed.connect(_on_cull_pressed.bind(ab_name))
			deck_row.add_child(cull_btn)
		else:
			var add_btn := Button.new()
			add_btn.text = "+"
			add_btn.focus_mode = Control.FOCUS_NONE
			add_btn.custom_minimum_size = Vector2(28, 20)
			add_btn.add_theme_font_size_override("font_size", 12)
			add_btn.tooltip_text = "Put this card in your deck."
			add_btn.pressed.connect(_on_add_pressed.bind(ab_name))
			deck_row.add_child(add_btn)

	card.gui_input.connect(_on_ability_card_input.bind(ab_name, is_unlocked))
	return card


func _open_zone_for_drops(zone: Control) -> void:
	"""Make sure a release ANYWHERE inside a drop zone actually lands.

	⛑ Godot finds a drop target by walking UP from the control under the cursor, and that walk
	BREAKS at the first `MOUSE_FILTER_STOP` control it meets. So any STOP control inside a zone
	is a dead patch: release over it and nothing happens, with no feedback at all.

	That is not hypothetical. The card tiles were STOP and swallowed every drop until they were
	demoted; then a synthesised drag onto the collection failed once and passed the next run,
	because the zone's centre happened to land on different content each time. Dead patches you
	can only find by aiming at them are worse than a total failure.

	So every descendant is demoted to PASS, which changes nothing about what they receive - a
	PASS control still gets its own input and still becomes the mouse focus - it only stops them
	ENDING the search. The zone itself stays STOP, because it is the thing that must be found.

	Called after every rebuild, since the tiles are new nodes each time."""
	if zone == null or not is_instance_valid(zone):
		return
	var stack: Array = zone.get_children()
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Control and (n as Control).mouse_filter == Control.MOUSE_FILTER_STOP:
			(n as Control).mouse_filter = Control.MOUSE_FILTER_PASS
		stack.append_array(n.get_children())


func _find_deck_card(root: Node) -> Control:
	"""The built card tile inside an entry - the node the mouse actually lands on.

	`combat_scene_panel.build_deck_card` names it "DeckCard"; the fallback is the first
	descendant that STOPS the mouse, which is the same thing by definition."""
	if root == null:
		return null
	if root is Control and String(root.name) == "DeckCard":
		return root as Control
	for c in root.get_children():
		var got := _find_deck_card(c)
		if got != null:
			return got
	if root is Control and (root as Control).mouse_filter == Control.MOUSE_FILTER_STOP:
		return root as Control
	return null


func _add_card_tile(entry: Control, key: String, in_deck: bool, title: String) -> void:
	"""Put a built tile in the right grid, wrapped so it can be dragged.

	ONE function decides which half of the screen a card lives in. Two call sites choosing that
	for themselves is how a card would end up in both grids, or in neither."""
	var drag := CardDrag.new()
	drag.panel_ref = self
	drag.key = key
	drag.in_deck = in_deck
	drag.title = title
	drag.add_child(entry)
	# The tile itself is what the mouse hits, so the wrapper has to watch ITS input. Found by
	# name rather than by index: `_make_deck_entry` builds a small tree and the card is not
	# always its first child.
	var _card := _find_deck_card(entry)
	if _card != null:
		drag.watch(_card)
	if in_deck and _deck_strip != null:
		_deck_strip.add_child(drag)
	else:
		_ability_grid.add_child(drag)


func _copy_target(ab_name: String, copy: Dictionary) -> String:
	"""The id a −/+ press should act on: this COPY when the tile is one, else the card.

	The first copy is stored bare ("cleave"), later ones as "cleave#2" - see
	`Character._explicit_copy_key`, which both the cull and add handlers already understand."""
	if copy.is_empty():
		return ab_name
	return String(copy.get("key", ab_name))


func _stack_signature(copy: Dictionary) -> String:
	"""What makes two copies THE SAME CARD, and therefore stackable under one tile.

	Owner 2026-09-16: *"get rid of the + on the deck screen unless the player has two exact copies
	of a card (same rank, same number of uses, same upgrades, etc.). If not all cards should appear
	individually. This will allow the players to manage their deck properly."*

	So the test is equality of everything that makes a copy worth keeping over its sibling: mastery
	rank, the exact use count, the milestone picks, the effect rank, and whether it is in the deck.
	Uses are in here deliberately - two copies at rank 1 with 12 and 40 uses are not
	interchangeable, because one is much closer to its next milestone.

	Picks arrive already sorted (see `client._card_instances_sorted`), so two copies that chose the
	same upgrades in a different order sign the same."""
	return "r%d|u%d|e%d|d%d|%s" % [
		int(copy.get("rank", 0)), int(copy.get("uses", 0)), int(copy.get("effect_rank", 0)),
		1 if bool(copy.get("in_deck", false)) else 0,
		",".join(PackedStringArray(copy.get("picks", [])))]


func _group_copies(copies: Array) -> Array:
	"""Copies grouped into what the screen should draw: [{copies:[...], rep:{...}}].

	Identical copies collapse into ONE tile carrying a count; anything that differs by so much as a
	single use gets its own tile. Order is preserved by first appearance, so copy 1 stays leftmost."""
	var order: Array = []
	var by_sig := {}
	for c in copies:
		if not (c is Dictionary):
			continue
		var sig := _stack_signature(c as Dictionary)
		if not by_sig.has(sig):
			by_sig[sig] = []
			order.append(sig)
		(by_sig[sig] as Array).append(c)
	var out: Array = []
	for sig in order:
		var grp: Array = by_sig[sig]
		out.append({"copies": grp, "rep": grp[0]})
	return out


func _make_deck_entry(ability: Dictionary, deck_count: int, copy: Dictionary = {}) -> Control:
	"""v0.9.678 slice 3 — a combat-styled deck card (built by combat_scene_panel,
	flips on click for the long description) plus a −/+ control row (thin/restore)."""
	var ab_name := str(ability.get("name", ""))
	var disp := str(ability.get("display", _humanize(ab_name)))
	var csp = client_ref.combat_scene_panel if (client_ref and "combat_scene_panel" in client_ref) else null
	if csp == null or not csp.has_method("build_deck_card"):
		return null
	var cat: Dictionary = client_ref.get_ability_category_info(ab_name) if client_ref.has_method("get_ability_category_info") else {}
	var color := str(cat.get("color", "#8C7656"))
	var glyph := str(cat.get("glyph", ""))
	var cost_text := _cost_text_for(ab_name)
	# v0.9.688 — computed-number description (Warrior slice); hover a number for its formula.
	# A copy's OWN progress lives under its stored key (bare for copy 1, 'card#n' after).
	var _data_key: String = str(copy.get("key", ab_name)) if not copy.is_empty() else ab_name
	var back: String = client_ref._ability_desc_bbcode(_data_key) if (client_ref and client_ref.has_method("_ability_desc_bbcode")) else _tooltip_for(ab_name)
	# v0.9.683 — companion cards carry the companion's monster art.
	var art_bb: String = csp.companion_card_art_bbcode(ab_name) if csp.has_method("companion_card_art_bbcode") else ""
	# v0.9.691 — damage/heal value on the card front.
	var val_text := ""
	var val_color := "#FF7A5A"
	if client_ref and client_ref.has_method("_ability_primary_value"):
		var pv: Dictionary = client_ref._ability_primary_value(ab_name)
		var pv_kind := str(pv.get("kind", ""))
		if pv_kind == "damage":
			val_text = "⚔ %d" % int(pv.get("value", 0))
			val_color = "#FF7A5A"
		elif pv_kind == "heal":
			val_text = "♥ %d" % int(pv.get("value", 0))
			val_color = "#7AE07A"
	# v0.9.693/717 — a companion card that isn't earned yet (key absent) is a LOANER
	# (active while the companion is equipped). Pass the flag so the card renders LIT
	# (not greyed) with a 'LOAN' badge instead of 'OUT'.
	var is_loaner := ab_name.begins_with("companion_card_") and not _deck_collection.has(ab_name)
	var card = csp.build_deck_card(disp, color, glyph, cost_text, deck_count, back, art_bb, val_text, val_color, is_loaner)
	var entry := VBoxContainer.new()
	entry.add_theme_constant_override("separation", 4)
	if card != null:
		card.gui_input.connect(_on_deck_card_input.bind(card))
		entry.add_child(card)
	# v0.9.717 — mastery progress line so players see how close each card is to its
	# next rank without flipping it (loaners show permanence progress instead below).
	if not is_loaner:
		var rank_lbl := RichTextLabel.new()
		rank_lbl.bbcode_enabled = true
		rank_lbl.fit_content = true
		rank_lbl.scroll_active = false
		rank_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		rank_lbl.add_theme_font_size_override("normal_font_size", 10)
		rank_lbl.text = "[center]%s[/center]" % _get_rank_progress_text(_data_key)
		entry.add_child(rank_lbl)
	var ctl := HBoxContainer.new()
	ctl.alignment = BoxContainer.ALIGNMENT_CENTER
	ctl.add_theme_constant_override("separation", 6)
	# The loaner can't be thinned/restored; show permanence progress instead of the
	# -/+ controls (which would just error).
	if is_loaner:
		var note := Label.new()
		note.text = "Loaner — " + _loaner_permanence_text(ab_name)
		note.add_theme_font_size_override("font_size", 11)
		note.add_theme_color_override("font_color", Color("#C8A24A"))
		ctl.add_child(note)
	elif not copy.is_empty():
		# ONE copy: take this one out, or put this one back. Its upgrades stay with it either way.
		var _cmd := _copy_command(ab_name, copy)
		if deck_count >= 1:
			var cminus := Button.new()
			cminus.text = "−"
			cminus.custom_minimum_size = Vector2(30, 22)
			cminus.focus_mode = Control.FOCUS_NONE
			cminus.tooltip_text = "Take THIS copy out of your deck (it keeps its upgrades)."
			cminus.pressed.connect(_on_cull_pressed.bind(_cmd))
			ctl.add_child(cminus)
		else:
			var cplus := Button.new()
			cplus.text = "+"
			cplus.custom_minimum_size = Vector2(30, 22)
			cplus.focus_mode = Control.FOCUS_NONE
			cplus.tooltip_text = "Put THIS copy back in your deck (it keeps its own upgrades)."
			cplus.pressed.connect(_on_add_pressed.bind(_cmd))
			ctl.add_child(cplus)
	else:
		# ⚑ THE BUTTONS ADDRESS THIS COPY, AND THERE IS NO DEAD "+".
		#
		# Both used to bind the BARE card name, so pressing − on "copy 2" asked the server to
		# thin "whichever copy" - the tile said which card it was and then acted on another.
		# `Character.cull_ability_card` already accepts a specific copy ("cleave#2"), so the key
		# just had to be sent. Owner 2026-09-16: *"This will allow the players to manage their
		# deck properly."* It cannot, if the control does not name its target.
		#
		# And the "+" is only drawn when there is something to add. It used to appear on EVERY
		# card, disabled, explaining where copies come from - a button that cannot be pressed on
		# a screen about managing your deck. Owner: *"get rid of the + on the deck screen."*
		var _key: String = _copy_target(ab_name, copy)
		if deck_count >= 1:
			var minus := Button.new()
			minus.text = "−"
			minus.custom_minimum_size = Vector2(30, 22)
			minus.focus_mode = Control.FOCUS_NONE
			minus.tooltip_text = "Bench this card (your deck keeps at least 5)."
			minus.pressed.connect(_on_cull_pressed.bind(_key))
			ctl.add_child(minus)
		else:
			var plus := Button.new()
			plus.text = "+"
			plus.custom_minimum_size = Vector2(30, 22)
			plus.focus_mode = Control.FOCUS_NONE
			plus.tooltip_text = "Put this card in your deck (it keeps its own upgrades)."
			plus.pressed.connect(_on_add_pressed.bind(_key))
			ctl.add_child(plus)
	entry.add_child(ctl)
	return entry


func _on_deck_card_input(event: InputEvent, card: Control) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if card == null or not is_instance_valid(card):
			return
		var front = card.get_node_or_null("Front")
		var back = card.get_node_or_null("Back")
		if front == null or back == null:
			return
		var flipped := not bool(card.get_meta("flipped", false))
		card.set_meta("flipped", flipped)
		front.visible = not flipped
		back.visible = flipped


func _on_cull_pressed(ability_name: String) -> void:
	emit_signal("cull_requested", ability_name)


func _on_add_pressed(ability_name: String) -> void:
	emit_signal("add_requested", ability_name)


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
	"""#11 — short BBCode description rendered inside the deck card. Now pulls the
	PLAIN-LANGUAGE `_ability_desc_bbcode` (the same friendly text combat card-hovers
	use) instead of the jargon-heavy `_get_ability_description_text`, so the deck
	screen reads like the rest of the game ('Deal a massive finishing blow' rather
	than 'INT-scaled burst × 3-4× multiplier, variable cost ≈30% of mana pool max')."""
	if client_ref and client_ref.has_method("_ability_desc_bbcode"):
		var raw = str(client_ref._ability_desc_bbcode(ability_name))
		if raw != "":
			return "[color=#BFB5A4]%s[/color]" % raw
	# Fallback for anything without a friendly entry (cloak/teleport utility).
	if client_ref and client_ref.has_method("_get_ability_description_text"):
		var raw2 = str(client_ref._get_ability_description_text(ability_name))
		if raw2 != "":
			return "[color=#BFB5A4]%s[/color]" % raw2
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
