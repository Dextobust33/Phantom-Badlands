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

var _current_page: String = "root"  # root | dungeon | combat | items | companions | player | world | loot_lab | abilities | patreon


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

	# An unknown page would render as an empty panel with no Back button - which looks
	# exactly like a crash. Fall back to root rather than stranding the panel.
	if not _current_page in ["root", "dungeon", "combat", "items", "companions", "player",
			"world", "loot_lab", "abilities", "patreon"]:
		_current_page = "root"
	match _current_page:
		"root":
			_title_label.text = "ADMIN MENU"
			_subtitle_label.text = "[color=#aaaaaa]All commands are server-gated. Non-admin accounts will be rejected.[/color]"
			# 2026-09-10 - reorganised. Owner: "the Admin panel needs reorganized. It doesn't make
			# sense where some of the things are in it... It should just be logical where things are."
			# The worst of it: every DUNGEON control lived under ITEMS - nine buttons that are not
			# items - and there was no Dungeon page at all. That is why the dungeon buttons were
			# repeatedly hunted for under World and not found, three sessions running.
			# Pages are now named for what they DO, ordered by how often they are reached for, and
			# nothing appears on two pages (Revive Companion was on two, Spawn Monster on two).
			_add_button("Dungeon - enter, traps, loot, finish a run", "_page_dungeon", Color(1, 0.7, 0.3))
			_add_button("Combat - spawn monsters, godmode, co-op", "_page_combat", Color(1.0, 0.45, 0.45))
			_add_button("Items - gear, consumables, cards, structures", "_page_items")
			_add_button("Companions - eggs, KO/revive, fusion catalysts", "_page_companions", Color(1, 0.84, 0))
			_add_button("Player - heal, quests, help reference", "_page_player", Color(0.6, 1, 0.6))
			_add_button("World - test posts, guards, cartography", "_page_world", Color(0.6, 1, 0.6))
			_add_separator()
			_add_button("Loot Lab - force minigame + rare cells / affixed tools", "_page_loot_lab", Color(0.4, 0.9, 1.0))
			_add_button("Abilities - test +X to ability gear", "_page_abilities", Color(0.85, 0.65, 1.0))
			_add_button("Patreon - fulfill supporter tiers (nearest player)", "_page_patreon", Color(0.95, 0.55, 1.0))
			_add_separator()
			_add_button("Close", "_close", Color(0.7, 0.7, 0.7))
		"dungeon":
			_title_label.text = "ADMIN - DUNGEON"
			_subtitle_label.text = "[color=#aaaaaa]Get in, and reach the states that are otherwise rare. Every button here runs the REAL server path a player takes, so what it shows is what a player sees.[/color]"
			_add_button("Enter T1 Dungeon (instant)", "enter_dungeon_t1", Color(0.6, 1, 0.6))
			_add_button("Enter T6 Dungeon (instant)", "enter_dungeon_t6", Color(0.6, 1, 0.6))
			_add_button("Enter Tier-Appropriate Dungeon (own level)", "enter_dungeon_auto", Color(0.6, 1, 0.6))
			_subtitle_subline("Skips spawn-and-walk: drops you straight inside a fresh personal dungeon instance.")
			_add_separator()
			_subtitle_subline("INSIDE a dungeon - a trap you must walk onto, a chest you must find, a floor you must clear. Each one used to mean wandering until luck provided it.")
			_add_button("Spring a Trap (here)", "dungeon_spring_trap", Color(1, 0.5, 0.5))
			_add_button("Drop Loot Beside Me", "dungeon_drop_loot", Color(1, 0.84, 0))
			_add_button("Flood the Run Log (12 lines)", "dungeon_flood_log", Color(0.7, 0.8, 1))
			_add_button("Finish Dungeon -> Final Chest", "dungeon_finish", Color(1, 0.7, 0.3))
			_subtitle_subline("Places the real FINAL_CHEST tile and defers the teleport exactly as a boss kill does - walk onto it. Forces the card reward so the DUNGEON CARD banner always shows.")
			_add_separator()
			_add_button("Test Dungeon Chest Drops (1 of each new item)", "give_chest_test_kit", Color(1, 0.84, 0))
			_subtitle_subline("Boss-Slayer Tonic, Reclaimer's Lantern, Floor Skip Charm + a T6 equipment piece.")
			_add_separator()
			_add_button("Back", "_back_root", Color(0.7, 0.7, 0.7))
		"companions":
			_title_label.text = "ADMIN - COMPANIONS"
			_subtitle_label.text = "[color=#aaaaaa]Eggs, KO and revive, aggro items, fusion catalysts. Everything companion-shaped is here now; it used to be spread across three pages, with Revive Companion on two of them.[/color]"
			_add_button("Setup Companion Test Scenario  (recommended)", "gm_test_b2", Color(1, 0.84, 0))
			_subtitle_subline("Rank 8 companion (~24% DR), KO'd, +3x revive potions, 5x elixirs, 3x taunt charms.")
			_add_button("KO Active Companion (instant)", "gm_ko_companion")
			_add_button("Revive Companion to Full HP", "gm_revive_companion")
			_add_button("Give 3x Companion Revive Potion", "give_revive_x3")
			_add_button("Give 3x Taunt Charm", "give_taunt_x3")
			_add_separator()
			_add_button("Give Egg (random monster type)", "give_egg")
			_add_button("Give Companion (random, T5)", "give_companion_t5")
			_add_button("Give Companion Stable (structure)", "give_companion_stable_structure", Color(1, 0.5, 1))
			_subtitle_subline("A buildable Companion Stable. Place inside your own enclosure for Sanctuary kennel access at your post.")
			_add_separator()
			_add_button("Give 3x Hybrid Catalyst", "give_hybrid_catalyst_x3", Color(1, 0.5, 1))
			_subtitle_subline("Enables Hybrid fusion (2 different monster types, both rank 5+).")
			_add_button("Give 3x Ascension Catalyst", "give_ascension_catalyst_x3", Color(1, 0.67, 0.4))
			_subtitle_subline("Enables Tier Ascend fusion (3 same monster type + same tier -> tier+1).")
			_add_separator()
			_add_button("Back", "_back_root", Color(0.7, 0.7, 0.7))
		"loot_lab":
			_title_label.text = "ADMIN — LOOT LAB"
			_subtitle_label.text = "[color=#aaaaaa]Test the Prize Shuffle rare outcomes + tool affixes without grinding RNG. Toggle force-mode ON, then gather / craft a tool once — every rare cell is guaranteed in the board.[/color]"
			_add_button("Force Minigame + Rare Cells: TOGGLE", "gm_loot_force", Color(0.4, 0.9, 1.0))
			_subtitle_subline("While ON: every gather/craft shows the minigame, and the board is seeded with one of each rare cell (Motherlode / Wildcard / Auto-Sell / Prospector / affixes). Toggle again to turn off.")
			_add_button("Grant Affixed Test Tools (all 4 affixes)", "gm_loot_grant_tools", Color(1, 0.84, 0))
			_subtitle_subline("Gives Everlasting / Lucky / Prospector / Wide-Harvest tools so you can test the EFFECTS on gather (durability skip, extra reveals, wildcard, nearby catches).")
			_add_separator()
			_add_button("Force Cosmetic Monsters: TOGGLE", "gm_force_cosmetic", Color(0.7, 0.85, 1.0))
			_subtitle_subline("Dungeon arc: while ON, EVERY monster spawns with a random color/pattern tint on its combat art (normal rate 12%). Start a fight to see it.")
			_add_separator()
			_add_button("Back", "_back_root", Color(0.7, 0.7, 0.7))
		"items":
			_title_label.text = "ADMIN - ITEMS"
			_subtitle_label.text = "[color=#aaaaaa]Gear, consumables, cards and buildables. Dungeon entry and the companion shortcuts moved to their own pages - nine of the buttons that used to be here were not items.[/color]"
			_add_button("Give Tier 5 Item (random slot)", "give_item_t5")
			_add_button("Give Tier 8 Item (random slot)", "give_item_t8")
			_add_button("Give 5x Hedge Elixir (T7 heal)", "give_elixirs")
			_add_button("Give Starter Kit (Valor / gems / mats)", "gm_giveall")
			_add_button("Grant Test Cards (dungeon + companion, tradeable)", "gm_give_test_card", Color(1.0, 0.7, 0.28))
			_add_separator()
			_add_button("Give Cosmetic Structures (1 of each)", "give_cosmetic_structures_set", Color(1, 0.84, 0))
			_subtitle_subline("Banner + Lamp Post + Torch + Statue + Signpost. Bump into a placed signpost to read or (as owner) edit its text.")
			_add_separator()
			_add_button("Back", "_back_root", Color(0.7, 0.7, 0.7))
		"combat":
			_title_label.text = "ADMIN - COMBAT"
			_subtitle_label.text = "[color=#aaaaaa]Force encounters, toggle invincibility, and drive the co-op path.[/color]"
			_add_button("Spawn Monster (own level)", "spawn_mob_own_level")
			_subtitle_subline("A normal same-level monster of a species that really spawns here.")
			_add_button("Spawn EMPOWERED (own level)", "spawn_mob_empowered", Color(1.0, 0.72, 0.3))
			_subtitle_subline("Normally a 25% roll. Target: ~55% of your health bar.")
			_add_button("Spawn ELITE Champion (own level)", "spawn_mob_elite", Color(1.0, 0.45, 0.45))
			_subtitle_subline("Normally a 1% roll, so testing one by hand meant ~100 spawns. Target: ~65%.")
			_add_button("Spawn Wish Granter (1 HP, 100% wish)", "gm_spawnwish")
			_add_separator()
			_add_button("Toggle Godmode", "gm_godmode")
			_add_separator()
			_subtitle_subline("Co-op - these were on MISC, which is not where anyone looks for combat controls.")
			_add_button("Toggle Co-op Party Combat", "gm_toggle_coop", Color(1.0, 0.7, 0.28))
			_add_button("Preview Party Column (while in combat)", "preview_party_column", Color(1.0, 0.7, 0.28))
			_add_separator()
			_add_button("Back", "_back_root", Color(0.7, 0.7, 0.7))
		"world":
			_title_label.text = "ADMIN - WORLD"
			_subtitle_label.text = "[color=#aaaaaa]Posts, guards, the settler bubble, and finding things on the map.[/color]"
			_add_button("Build Test Post Here  (5x5 + 2 tower-boosted guards)", "gm_build_test_post", Color(0.6, 1, 0.6))
			_subtitle_subline("Drops a fresh enclosure at your feet and hires 2 free guards. Monsters in the bubble drop to T1.")
			_add_button("Hire Free Guard (north of you)", "gm_hire_test_guard")
			_subtitle_subline("Stacks more suppression on a post. Auto-detects tower adjacency.")
			_add_button("Diagnose Settler Bubble Here", "gm_settler_diag")
			_subtitle_subline("Prints wilderness tier, bubble status, guard count, monster level.")
			_add_separator()
			_subtitle_subline("Cartography (rooted Locate) - rank sets precision: 1-2 region, 3-4 coarse, 5-7 precise, 8 = anywhere sense. Moved here from MISC: it is a map feature.")
			_add_button("Cartography rank +1", "gm_cartography_up", Color(0.35, 0.78, 1.0))
			_add_button("Cartography -> 5 (precise, post-gated)", "gm_cartography_5", Color(0.35, 0.78, 1.0))
			_add_button("Cartography -> 8 (anywhere sense)", "gm_cartography_8", Color(0.48, 0.88, 0.48))
			_add_button("Cartography -> 1 (reset)", "gm_cartography_1", Color(0.7, 0.7, 0.7))
			_add_separator()
			_subtitle_subline("[color=#FF6666]DANGER.[/color] The map wipe. Accounts, characters, Sanctuary and VALOR all survive; the land, posts, dungeons, market and every built tile do not. Two presses: the first only tells you what it would destroy.")
			_add_button("WORLD RESET - show me what it would destroy", "gm_world_reset", Color(1.0, 0.7, 0.3))
			_add_button("...CONFIRM WORLD RESET (no undo)", "gm_world_reset_confirm", Color(1.0, 0.3, 0.3))
			_add_separator()
			_add_button("Back", "_back_root", Color(0.7, 0.7, 0.7))
		"player":
			_title_label.text = "ADMIN - PLAYER"
			_subtitle_label.text = "[color=#aaaaaa]Your own character. This page was called MISC, which is what a page gets called when nobody decides what it is for.[/color]"
			_add_button("Heal Self (full HP / mana / stamina)", "gm_heal")
			_add_button("Reset Active Quests", "gm_resetquests")
			_add_separator()
			_add_button("Show /gmhelp text reference", "show_gmhelp")
			_add_separator()
			_add_button("Back", "_back_root", Color(0.7, 0.7, 0.7))
		"abilities":
			# v0.9.607 — admin page for testing the v0.9.606 +X to ability
			# gear. Kit button covers stacking + multi-slot in one shot;
			# individual buttons let you bias toward a specific ability.
			_title_label.text = "ADMIN — +ABILITIES GEAR (v0.9.606)"
			_subtitle_label.text = "[color=#aaaaaa]Spawn gear with forced [color=#FFD700]ability_rank_*[/color] affixes to test the v0.9.606 +X to ability mechanic without grinding epic+ drops. Each +1 lifts the ability's effective mastery rank; past rank 6 the multiplier keeps growing (+10% per extra rank, uncapped).[/color]"
			_add_button("Spawn full +abilities test kit (5 items)", "give_ability_kit", Color(1, 0.84, 0))
			_subtitle_subline("Weapon +3 Cleave / Ring +3 Magic Bolt / Amulet +3 Ambush / Helm +2 Warrior / Boots +1 Warrior. Equip all 5 to test specific + archetype stacking (Cleave ends up at +6).")
			_add_separator()
			# Specific damage abilities
			_add_button("Weapon: +3 to Cleave", "give_ability_cleave_3", Color(0.95, 0.65, 0.55))
			_add_button("Weapon: +3 to Power Strike", "give_ability_power_strike_3", Color(0.95, 0.65, 0.55))
			_add_button("Weapon: +3 to Shield Bash", "give_ability_shield_bash_3", Color(0.95, 0.65, 0.55))
			_add_button("Weapon: +3 to Devastate", "give_ability_devastate_3", Color(0.95, 0.65, 0.55))
			_add_separator()
			_add_button("Ring: +3 to Magic Bolt", "give_ability_magic_bolt_3", Color(0.6, 0.75, 1))
			_add_button("Ring: +3 to Blast", "give_ability_blast_3", Color(0.6, 0.75, 1))
			_add_button("Ring: +3 to Meteor", "give_ability_meteor_3", Color(0.6, 0.75, 1))
			_add_separator()
			_add_button("Amulet: +3 to Ambush", "give_ability_ambush_3", Color(0.85, 0.65, 1.0))
			_add_button("Amulet: +3 to Exploit", "give_ability_exploit_3", Color(0.85, 0.65, 1.0))
			_add_separator()
			# Archetype-wide rolls
			_add_button("Helm: +2 to Warrior damage", "give_ability_warrior_dmg_2", Color(1, 0.84, 0))
			_add_button("Helm: +2 to Mage damage", "give_ability_mage_dmg_2", Color(1, 0.84, 0))
			_add_button("Helm: +2 to Trickster damage", "give_ability_trickster_dmg_2", Color(1, 0.84, 0))
			_subtitle_subline("Archetype rolls affect every damage ability in that archetype — handy for testing the get_ability_rank_bonus archetype lookup path.")
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
	# Any "_page_<name>" button navigates, and the page name IS the suffix - so adding a page needs
	# no new case here at all.
	#
	# This was nine near-identical cases, each setting `_current_page` and then calling
	# `_render_page()`. A tenth was added by hand for the new Dungeon page and omitted the render
	# call, so the button set the variable and redrew nothing: owner, immediately, *"Clicking
	# Dungeon in the Admin pannel does nothing."* Nine correct copies of a two-step rule is nine
	# chances to write the tenth wrong. One rule cannot forget half of itself.
	if action_id.begins_with("_page_"):
		_current_page = action_id.substr(6)
		_render_page()
		return
	match action_id:
		"_close":
			emit_signal("close_requested")
		"_back_root":
			_current_page = "root"
			_render_page()
		_:
			emit_signal("action_triggered", action_id)
