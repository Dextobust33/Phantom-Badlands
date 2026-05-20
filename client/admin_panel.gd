extends Control
class_name AdminPanel

# Visual admin menu (/admin). Mouse-clickable categorized panel matching
# the Inventory / Crafting / Market visual style. Replaces the previous
# chat-mode action-bar menu which was unreachable while the input field
# held focus.
#
# Pattern: each "page" is a vertical stack of big buttons. Clicking a
# category button drills into a sub-page; clicking an action emits a
# signal back to client.gd which dispatches the corresponding gm_*
# server message.

signal close_requested
signal action_triggered(action_id: String)

var _root_panel: PanelContainer
var _vbox: VBoxContainer
var _title_label: Label
var _subtitle_label: RichTextLabel
var _button_column: VBoxContainer

var _current_page: String = "root"  # "root" | "test_b2" | "items" | "combat" | "misc" | "world"


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # Block clicks behind the panel
	_build_layout()
	visible = false


func open() -> void:
	_current_page = "root"
	_render_page()
	visible = true


func close() -> void:
	visible = false


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
	_root_panel.custom_minimum_size = Vector2(440, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.055, 0.045, 0.97)
	sb.border_color = Color(0.85, 0.27, 0.27, 1)  # Red admin border
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

	# Title
	_title_label = Label.new()
	_title_label.add_theme_color_override("font_color", Color(0.95, 0.27, 0.27))
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vbox.add_child(_title_label)

	# Subtitle / description
	_subtitle_label = RichTextLabel.new()
	_subtitle_label.bbcode_enabled = true
	_subtitle_label.fit_content = true
	_subtitle_label.scroll_active = false
	_subtitle_label.add_theme_font_size_override("normal_font_size", 13)
	_subtitle_label.custom_minimum_size = Vector2(0, 24)
	_vbox.add_child(_subtitle_label)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	_vbox.add_child(spacer)

	# Button column (rebuilt per page)
	_button_column = VBoxContainer.new()
	_button_column.add_theme_constant_override("separation", 6)
	_vbox.add_child(_button_column)


func _render_page() -> void:
	# Clear existing buttons
	for child in _button_column.get_children():
		child.queue_free()

	match _current_page:
		"root":
			_title_label.text = "ADMIN MENU"
			_subtitle_label.text = "[color=#aaaaaa]All commands are server-gated. Non-admin accounts will be rejected.[/color]"
			_add_button("Test B2 — companion polish (DR + revive items)", "_page_test_b2", Color(1, 0.84, 0))
			_add_button("World — settler bubble + post testing", "_page_world", Color(0.6, 1, 0.6))
			_add_button("Items — give items, consumables, materials", "_page_items")
			_add_button("Combat — spawn monsters, godmode", "_page_combat")
			_add_button("Misc — heal, reset quests, revive companion", "_page_misc")
			_add_button("Patreon — fulfill supporter tiers (nearest player)", "_page_patreon", Color(0.95, 0.55, 1.0))
			_add_separator()
			_add_button("Close", "_close", Color(0.7, 0.7, 0.7))
		"test_b2":
			_title_label.text = "ADMIN — TEST PHASE B2"
			_subtitle_label.text = "[color=#aaaaaa]Test scenarios for the Phase B2 companion polish bundle: per-sub_tier damage reduction, Companion Revive Potion, and the new aggro / Taunt Charm system.[/color]"
			_add_button("Setup B2 Test Scenario  (recommended)", "gm_test_b2", Color(1, 0.84, 0))
			_subtitle_subline("Sub-tier 8 companion (~24% DR), KO'd, +3x revive potions, 5x elixirs, 3x taunt charms.")
			_add_button("KO Active Companion (instant)", "gm_ko_companion")
			_add_button("Revive Companion to Full HP", "gm_revive_companion")
			_add_button("Give 3x Companion Revive Potion", "give_revive_x3")
			_add_button("Give 3x Taunt Charm", "give_taunt_x3")
			_add_button("Spawn Monster (own level)", "spawn_mob_own_level")
			_add_separator()
			_add_button("Back", "_back_root", Color(0.7, 0.7, 0.7))
		"items":
			_title_label.text = "ADMIN — ITEMS"
			_subtitle_label.text = "[color=#aaaaaa]Gear, consumables, and starter kit shortcuts.[/color]"
			_add_button("Give Tier 5 Item (random slot)", "give_item_t5")
			_add_button("Give Tier 8 Item (random slot)", "give_item_t8")
			_add_button("Give 5x Hedge Elixir (T7 heal)", "give_elixirs")
			_add_button("Give Starter Kit (Valor / gems / mats)", "gm_giveall")
			_add_button("Give Egg (random monster type)", "give_egg")
			_add_button("Give Companion (random, T5)", "give_companion_t5")
			_add_separator()
			# v0.9.496 — fusion catalyst shortcuts for Stable / Sanctuary testing.
			_add_button("Give 3x Hybrid Catalyst", "give_hybrid_catalyst_x3", Color(1, 0.5, 1))
			_subtitle_subline("Enables Hybrid fusion (2 different monster types, both sub-tier 5+).")
			_add_button("Give 3x Ascension Catalyst", "give_ascension_catalyst_x3", Color(1, 0.67, 0.4))
			_subtitle_subline("Enables Tier Ascend fusion (3 same monster type + same tier → tier+1).")
			# v0.9.500 — Companion Stable structure for testing player-built Stables.
			_add_button("Give Companion Stable (structure)", "give_companion_stable_structure", Color(1, 0.5, 1))
			_subtitle_subline("A buildable Companion Stable. Place inside your own enclosure to get Sanctuary kennel access at your post.")
			# v0.9.507 — cosmetic structure set for testing buildable catalogue.
			_add_button("Give Cosmetic Structures (1 of each)", "give_cosmetic_structures_set", Color(1, 0.84, 0))
			_subtitle_subline("Banner + Lamp Post + Torch + Statue + Signpost. Bump into a placed signpost to read or (as owner) edit its text.")
			_add_separator()
			_add_button("Test Dungeon Chest Drops (1 of each new item)", "give_chest_test_kit", Color(1, 0.84, 0))
			_subtitle_subline("Boss-Slayer Tonic, Reclaimer's Lantern, Floor Skip Charm + a T6 equipment piece.")
			_add_separator()
			_add_button("Enter T1 Dungeon (instant)", "enter_dungeon_t1", Color(0.6, 1, 0.6))
			_add_button("Enter T6 Dungeon (instant)", "enter_dungeon_t6", Color(0.6, 1, 0.6))
			_add_button("Enter Tier-Appropriate Dungeon (own level)", "enter_dungeon_auto", Color(0.6, 1, 0.6))
			_subtitle_subline("Skips spawn-and-walk: drops you straight inside a fresh personal dungeon instance.")
			_add_separator()
			_add_button("Back", "_back_root", Color(0.7, 0.7, 0.7))
		"combat":
			_title_label.text = "ADMIN — COMBAT"
			_subtitle_label.text = "[color=#aaaaaa]Force encounters and toggle invincibility.[/color]"
			_add_button("Spawn Monster (own level)", "spawn_mob_own_level")
			_add_button("Spawn Wish Granter (1 HP, 100% wish)", "gm_spawnwish")
			_add_button("Toggle Godmode", "gm_godmode")
			_add_separator()
			_add_button("Back", "_back_root", Color(0.7, 0.7, 0.7))
		"world":
			_title_label.text = "ADMIN — WORLD"
			_subtitle_label.text = "[color=#aaaaaa]Test the post-anchored world Slice 4 settler-bubble suppression without grinding for build materials.[/color]"
			_add_button("Build Test Post Here  (5x5 + 2 tower-boosted guards)", "gm_build_test_post", Color(0.6, 1, 0.6))
			_subtitle_subline("Drops a fresh enclosure at your feet and hires 2 free guards. Monsters in the bubble drop to T1.")
			_add_button("Hire Free Guard (north of you)", "gm_hire_test_guard")
			_subtitle_subline("Stacks more suppression on a post. Auto-detects tower adjacency.")
			_add_button("Diagnose Settler Bubble Here", "gm_settler_diag")
			_subtitle_subline("Prints wilderness tier, bubble status, guard count, monster level.")
			_add_separator()
			_add_button("Back", "_back_root", Color(0.7, 0.7, 0.7))
		"misc":
			_title_label.text = "ADMIN — MISC"
			_subtitle_label.text = "[color=#aaaaaa]Self-heal, quest reset, companion revive.[/color]"
			_add_button("Heal Self (full HP / mana / stamina)", "gm_heal")
			_add_button("Revive Companion (full HP)", "gm_revive_companion")
			_add_button("Reset Active Quests", "gm_resetquests")
			_add_button("Show /gmhelp text reference", "show_gmhelp")
			_add_separator()
			_add_button("Back", "_back_root", Color(0.7, 0.7, 0.7))
		"patreon":
			# v0.9.578 — Patreon supporter-tier fulfillment. Manual flow: walk
			# up to the player (within 5 tiles), open this page, pick a tier.
			# Server resolves nearest-online-player and flips the tier on
			# their account. Hard rule: cosmetic + tame QoL only — never
			# combat advantage.
			_title_label.text = "ADMIN — PATREON FULFILLMENT"
			_subtitle_label.text = "[color=#aaaaaa]Sets the nearest online player's account.patreon_tier. Walk within 5 tiles of the supporter before pressing. Cosmetic title is auto-granted; tame QoL bonuses (Sanctuary slot at T2+, kennel-tier at T3) are scoped for a follow-up.[/color]"
			_add_button("Tier 0 — None (clear support)", "gm_set_patreon_tier_0", Color(0.85, 0.85, 0.85))
			_subtitle_subline("Removes any patreon title from the nearest player.")
			_add_button("Tier 1 — Supporter ($5/mo)", "gm_set_patreon_tier_1", Color(0.5, 1.0, 0.5))
			_subtitle_subline("Green [Supporter] title.")
			_add_button("Tier 2 — Founder ($10/mo)", "gm_set_patreon_tier_2", Color(1.0, 0.84, 0))
			_subtitle_subline("Gold [Founder] title.")
			_add_button("Tier 3 — Patron ($20/mo)", "gm_set_patreon_tier_3", Color(0.64, 0.21, 0.93))
			_subtitle_subline("Purple [Patron] title.")
			_add_separator()
			_add_button("Back", "_back_root", Color(0.7, 0.7, 0.7))


func _add_button(label: String, action_id: String, font_color: Color = Color(1, 1, 1)) -> void:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(0, 36)
	btn.focus_mode = Control.FOCUS_NONE  # Don't steal keyboard focus
	btn.add_theme_color_override("font_color", font_color)
	btn.add_theme_font_size_override("font_size", 14)
	var sb_normal := StyleBoxFlat.new()
	sb_normal.bg_color = Color(0.13, 0.10, 0.08, 1)
	sb_normal.border_color = Color(0.55, 0.30, 0.20, 1)
	sb_normal.set_border_width_all(1)
	sb_normal.set_corner_radius_all(4)
	sb_normal.content_margin_left = 12
	sb_normal.content_margin_right = 12
	var sb_hover := sb_normal.duplicate()
	sb_hover.bg_color = Color(0.20, 0.14, 0.10, 1)
	sb_hover.border_color = Color(0.85, 0.50, 0.27, 1)
	var sb_pressed := sb_normal.duplicate()
	sb_pressed.bg_color = Color(0.25, 0.15, 0.10, 1)
	btn.add_theme_stylebox_override("normal", sb_normal)
	btn.add_theme_stylebox_override("hover", sb_hover)
	btn.add_theme_stylebox_override("pressed", sb_pressed)
	btn.pressed.connect(_on_button_pressed.bind(action_id))
	_button_column.add_child(btn)


func _add_separator() -> void:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 6)
	_button_column.add_child(sep)


func _subtitle_subline(text: String) -> void:
	"""Append a small grey line directly under the most recently added button."""
	var lbl := RichTextLabel.new()
	lbl.bbcode_enabled = true
	lbl.fit_content = true
	lbl.scroll_active = false
	lbl.add_theme_font_size_override("normal_font_size", 11)
	lbl.custom_minimum_size = Vector2(0, 16)
	lbl.text = "[color=#888888]   " + text + "[/color]"
	_button_column.add_child(lbl)


func _on_button_pressed(action_id: String) -> void:
	match action_id:
		"_close":
			emit_signal("close_requested")
		"_back_root":
			_current_page = "root"
			_render_page()
		"_page_test_b2":
			_current_page = "test_b2"
			_render_page()
		"_page_items":
			_current_page = "items"
			_render_page()
		"_page_combat":
			_current_page = "combat"
			_render_page()
		"_page_misc":
			_current_page = "misc"
			_render_page()
		"_page_world":
			_current_page = "world"
			_render_page()
		"_page_patreon":
			_current_page = "patreon"
			_render_page()
		_:
			emit_signal("action_triggered", action_id)
