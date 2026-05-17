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
			"A [color=#FFD700]Companion Stable[/color] (the magenta [color=#FF80FF]C[/color] tile at Tier 5+ trading posts, or a player-built one inside an enclosure) is a living link to your Sanctuary's companion storage. Bump the tile to open it.\n\n"
			+ "[color=#888888]Build your own:[/color] Construction skill 35 unlocks a [color=#FFD700]Companion Stable[/color] recipe (8 wooden plank + 4 iron ore + 2 heartwood + 2 arcane crystal + 3 magic dust). Place inside your own enclosure for Sanctuary access at your settlement.\n\n"
			+ "[color=#FFD700]MANAGE TAB[/color]\n"
			+ "[color=#A335EE]✦ Deposit[/color] — non-registered active companion → kennel. Frees a roster slot.\n"
			+ "[color=#A335EE]✦ Return to Slot[/color] — a [color=#FF80FF][REGISTERED][/color] companion goes back to its registered slot (still registered).\n"
			+ "[color=#A335EE]✦ Withdraw[/color] — pull a kennel companion into your roster.\n"
			+ "[color=#A335EE]✦ Check Out[/color] (v0.9.493) — pull a Sanctuary-registered companion onto your character as the new active. Closes the death-and-respawn detour. Requires no current active.\n\n"
			+ "[color=#FFD700]FUSE TAB[/color]\n"
			+ "Mid-character fusion. Four modes via the selector at the top:\n"
			+ "  • [color=#FFD700]Same Type[/color] — 3 of same monster type AND sub-tier → next sub-tier (max sub-tier 8).\n"
			+ "  • [color=#FF00FF]Mixed T9[/color] — 8 [b]T8.8[/b] companions (Tier 8, sub-tier 8) → random Tier 9 companion. The capstone fusion.\n"
			+ "  • [color=#FF66FF]Hybrid[/color] — 2 different monster types both sub-tier 5+, consumes 1 [color=#FFD700]Hybrid Catalyst[/color] → hybrid blend.\n"
			+ "  • [color=#FFAA66]Tier Ascend[/color] — 3 of same monster type AND same tier (any sub-tier), consumes 1 [color=#FFD700]Ascension Catalyst[/color] → same type at tier+1, sub-tier 1. Keeps your pet's identity while raising rank.\n"
			+ "Inputs can come from kennel OR registered slots in any mode. If any input is registered, the output is auto-registered (slot-preserving). Otherwise it goes to the kennel.\n\n"
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
	"companions_page": {
		"title": "[color=#FFD700]Companions Page[/color]",
		"body": (
			"Your active pet, your collected roster, and your Sanctuary-registered companions — all on one page.\n\n"
			+ "[color=#FFD700]Active Companion[/color] — the pet currently fighting alongside you. Shown at the top with full ability text + XP bar.\n\n"
			+ "[color=#FFD700]Sanctuary Registered[/color] (when present) — companions stored in your account's permadeath-resistant slots. Read-only here; manage at any Tier 5+ NPC [color=#A335EE]Companion Stable[/color] or the Sanctuary's K tile. The currently checked-out slot is dimmed and marked [color=#FFD700][CHECKED OUT][/color].\n\n"
			+ "[color=#FFD700]Roster[/color] — your collected (non-registered) companions. Left-click to activate; right-click for Inspect / Release.\n\n"
			+ "[color=#FFD700]── Card info ──[/color]\n"
			+ "  • [color=#FF80FF][REG][/color] — currently checked out from a Sanctuary slot.\n"
			+ "  • [color=#FF80FF][HYBRID×X][/color] — a Hybrid Fusion result; the X is the partner monster type.\n"
			+ "  • Color-coded rarity tag — variant tier from [color=#888888][C][/color] common up to [color=#FFD700][P][/color] prismatic.\n"
			+ "  • [b]T<n>.<m>[/b] — Tier <n>, sub-tier <m>. Sub-tier is the within-tier ladder (1-8). T9 is the cap.\n"
			+ "  • [color=#FFAA66]Veteran/Champion/Warlord/Tyrant/Apex[/color] prefix — appears on companions ascended via Tier Ascension Fusion. The prefix tells you how many tier-steps above the base species the companion has climbed.\n\n"
			+ "[color=#FFD700]── Aggro Roles ──[/color]\n"
			+ "Each companion has an Aggro value (0-100%) controlling how often enemies target it instead of you. Roles:\n"
			+ "  • [color=#FFD700]Tank[/color] (50%+) — Frontliner. Draws enemy attacks; designed to soak hits so your character stays safe.\n"
			+ "  • [color=#FFA500]Fighter[/color] (30-49%) — Engaged participant. Balances damage with attention drawn.\n"
			+ "  • [color=#FFFFFF]Default[/color] (20-29%) — Neutral. Targeted at the baseline rate.\n"
			+ "  • [color=#87CEEB]Evasive[/color] (<20%) — Backline. Rarely targeted; relies on positioning. Pair with a tank or your character.\n\n"
			+ "[color=#888888]Hover any card for a detail tooltip. Right-click for the full Inspect view (abilities, effective bonuses, role, art).[/color]"
		),
	},
	"inventory_page": {
		"title": "[color=#FFD700]Inventory[/color]",
		"body": (
			"Your character's carried items, equipment, and gathered materials.\n\n"
			+ "[color=#FFD700]── Filter chips ──[/color] Click the chips at the top to toggle category visibility. Hidden categories don't take up screen space; toggle them back on when you need them.\n\n"
			+ "[color=#FFD700]── Item rarity colors ──[/color]\n"
			+ "  • [color=#FFFFFF]Common[/color] (white) → [color=#1EFF00]Uncommon[/color] (green) → [color=#0070DD]Rare[/color] (blue) → [color=#A335EE]Epic[/color] (purple) → [color=#FF8000]Legendary[/color] (orange) → [color=#FFD700]Mythic[/color] (gold).\n\n"
			+ "[color=#FFD700]── Common actions ──[/color]\n"
			+ "  • [b]Left-click[/b] an item to bring up its actions (Equip / Use / Discard / etc.).\n"
			+ "  • [b]Hover[/b] for a detailed tooltip (stats, comparison to current gear, source for materials).\n"
			+ "  • [b]Salvage[/b] turns items into [color=#FFD700]Salvage Essence[/color] (ESS) + a chance at bonus materials. Use it on duplicates and low-tier finds.\n"
			+ "  • [b]Materials[/b] (gathered resources) live in their own group — use them as crafting inputs.\n\n"
			+ "[color=#FFD700]── Equipment comparison ──[/color]\n"
			+ "When you hover an equipable item the tooltip shows green/red deltas vs whatever's currently in that slot, including Sanctuary house bonuses (HP multipliers, resource max).\n\n"
			+ "[color=#FFD700]── Home Stones ──[/color]\n"
			+ "Special consumables (Egg / Supplies / Equipment / Companion) that send items to your Sanctuary — survive permadeath. Drop from Tier 4+ chests or buy at NPC posts (`/stones`).\n\n"
			+ "[color=#888888]Capacity is shown at the top right. Upgrade in Sanctuary → Storage tier for more slots.[/color]"
		),
	},
	"stats_page": {
		"title": "[color=#FFD700]Stats & Progression[/color]",
		"body": (
			"Your character's stats, racial passives, class passives, and the [color=#FFD700]Progression Vectors[/color] dashboard.\n\n"
			+ "[color=#FFD700]── Stat allocation ──[/color] You earn 1 stat point per level. Spend them on STR / CON / DEX / INT / WIS / WITS to taste. Sanctuary upgrades + race bonuses stack on top.\n\n"
			+ "[color=#FFD700]── Class + Race passives ──[/color] Named here with full effect text. Each class has a passive that defines its identity; each race has its own. Both are always-on; you don't need to activate them.\n\n"
			+ "[color=#FFD700]── Progression Vectors ──[/color] The dashboard names every track you're advancing:\n"
			+ "  • Character XP + level progression\n"
			+ "  • Stat-point bank (visible bank with current count + spend pointer to /stats)\n"
			+ "  • [color=#FFD700]Sanctuary upgrades[/color] + Baddie Points (account-level, survive permadeath)\n"
			+ "  • 10 [color=#FFD700]Job specialties[/color] with commit markers — you can only fully commit to one specialty per skill family\n"
			+ "  • [color=#FFD700]Bestiary[/color] — kills per monster type unlock entries\n"
			+ "  • [color=#FFD700]Compass[/color] — 3-tier post-discovery layered reveal (direction → distance → name)\n"
			+ "  • [color=#FFD700]Atlas[/color] — regions visited per account\n"
			+ "  • [color=#FFD700]Soul Gems[/color] — late-game crafting material progression\n"
			+ "  • [color=#FFD700]Titles[/color] — rank progression (Jarl → High King → Elder → Eternal)\n\n"
			+ "[color=#FFD700]── Why all in one place ──[/color] Players were missing systems they were already advancing. The dashboard makes every track visible at a glance, with the next milestone called out.\n\n"
			+ "[color=#888888]Type [color=#9ACD32]/stats[/color] to spend stat points, [color=#9ACD32]/status[/color] for this dashboard.[/color]"
		),
	},
	"crafting_page": {
		"title": "[color=#FFD700]Crafting[/color]",
		"body": (
			"Combine materials into equipment, consumables, structures, and ingredients. The crafting station shows up to [b]7 transparency layers[/b] before you commit so you know what you're getting.\n\n"
			+ "[color=#FFD700]── Specialty lock-in ──[/color] Each skill family (e.g., Blacksmithing) has multiple specialties (Weaponsmith / Armorer / etc.). When you reach skill 25 you commit to ONE specialty per family — that unlocks the specialist-only recipes. Switching specialties is expensive; choose carefully.\n\n"
			+ "[color=#FFD700]── The 7 transparency layers ──[/color]\n"
			+ "  1. [b]Materials needed[/b] — exact counts, highlighted red if you're short.\n"
			+ "  2. [b]Skill required[/b] vs your current skill — green if you can craft.\n"
			+ "  3. [b]Output preview[/b] — name + base stats of what you'll produce.\n"
			+ "  4. [b]Material sources[/b] — where each input drops/spawns (reverse-lookup map).\n"
			+ "  5. [b]Quality odds[/b] — your % chance per quality tier given current skill.\n"
			+ "  6. [b]Sell-value preview[/b] — market rolling-average price for the output.\n"
			+ "  7. [b]Skill progression preview[/b] — your next 3 locked recipes by skill_required + levels_away.\n\n"
			+ "[color=#FFD700]── Quality scaling ──[/color] Higher quality = better base stats on the output. Skill ratio (your skill vs recipe difficulty) drives the odds; higher skill = better odds at higher quality tiers.\n\n"
			+ "[color=#888888]Crafting skill levels via successful crafts at or near your current skill. Failed crafts return some materials.[/color]"
		),
	},
	"market_page": {
		"title": "[color=#FFD700]Market[/color]",
		"body": (
			"Player-driven economy at trading posts. List items for [color=#FFD700]Valor[/color] (the universal currency), buy other players' listings.\n\n"
			+ "[color=#FFD700]── How pricing works ──[/color]\n"
			+ "  • [color=#FFAA00]base_valor[/color] — what the seller receives immediately when listing.\n"
			+ "  • [color=#FFAA00]markup_price[/color] — what the buyer pays. Includes a supply/demand markup that grows with the listed quantity at this post per category.\n"
			+ "  • Difference is the [color=#FFAA00]post tax[/color] (revenue absorbed by the trading post).\n\n"
			+ "[color=#FFD700]── Categories ──[/color] Equipment, Companion Eggs, Consumables, Tools, Runes, Materials, Monster Parts. Items stack in browse view EXCEPT equipment, eggs, and tools (each unique).\n\n"
			+ "[color=#FFD700]── Bulk listing ──[/color] List all equipment / consumables+tools / materials in one click.\n\n"
			+ "[color=#FFD700]── Network browse ──[/color] See listings from OTHER trading posts. To buy from another post, consume a [color=#FFD700]Travel Stone[/color] or physically travel there. Specialty + Threat-marked posts always require physical presence (geographic value preserved).\n\n"
			+ "[color=#FFD700]── My Listings ──[/color] Track what you've listed across the network. Sort by category, price (asc/desc), name, or level.\n\n"
			+ "[color=#888888]Valor balance shows top-right. Earn it from quests, monster drops, and listing items. Spend it on market buys, NPC vendors, Sanctuary upgrades (where applicable).[/color]"
		),
	},
	"fusion_overview": {
		"title": "[color=#FFD700]Fusion[/color]",
		"body": (
			"At the [color=#FFD700]Fusion Station[/color] in your Sanctuary (or a Companion Stable's Fuse tab), you can combine kennel companions in four ways:\n\n"
			+ "[color=#A335EE]✦ Same Type[/color] — 3 companions of the same monster type and the same sub-tier → 1 companion of the next sub-tier. Path to maxing within a tier.\n\n"
			+ "[color=#A335EE]✦ Mixed T9[/color] — 8 [b]T8.8[/b] companions (Tier 8, sub-tier 8). Types can differ. → 1 random Tier 9 companion. The capstone fusion.\n\n"
			+ "[color=#A335EE]✦ Hybrid[/color] — 2 companions of [b]different[/b] monster types, both at sub-tier 5+, plus 1 [color=#FFD700]Hybrid Catalyst[/color] → a hybrid companion that blends both parents' bonuses and inherits the second parent's threshold ability.\n\n"
			+ "[color=#A335EE]✦ Tier Ascend[/color] — 3 companions of the [b]same monster type and same tier[/b] (any sub-tier mix), plus 1 [color=#FFD700]Ascension Catalyst[/color] → 1 companion of the [b]same type at tier+1[/b], sub-tier 1. Lets you raise your favorite pet's rank without changing what it is.\n\n"
			+ "[color=#FFD700]Hybrid Catalysts[/color] drop from Tier 5+ dungeon chests. [color=#FFD700]Ascension Catalysts[/color] drop from Tier 6+ dungeon chests.\n\n"
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
