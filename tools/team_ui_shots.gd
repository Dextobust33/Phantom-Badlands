extends SceneTree
## Item 14 S4 dev tool: render the REAL combat scene panel with a scripted solo fight and a full companion team,
## and the Companions panel with its Team section, then write PNGs so the layout can be judged without a server.
## Run WINDOWED (a render target is needed):
##   godot --path . --screen 1 --script res://tools/team_ui_shots.gd

func _init():
	_run.call_deferred()

func _comp(id: String, name: String, mt: String, tier: int, hp: int, mx: int, ko: bool = false, tactics: String = "balanced") -> Dictionary:
	var d: Dictionary = DropTables.COMPANION_DATA.get(mt, {})
	return {"id": id, "name": name, "monster_type": mt, "level": 40, "tier": tier, "sub_tier": 2, "variant": "Normal",
		"variant_color": "#FFFFFF", "variant_pattern": "solid", "border_tier": 2, "bonuses": (d.get("bonuses", {}) as Dictionary).duplicate(),
		"combat_hp": hp, "combat_max_hp": mx, "ko": ko, "tactics": tactics, "xp": 0}

func _run():
	root.title = "Team UI shots"
	root.size = Vector2i(1920, 1080)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.08, 1)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	root.add_child(bg)

	# ---------- 1. combat scene with a team ----------
	var PanelScript = load("res://client/combat_scene_panel.gd")
	var panel = PanelScript.new()
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	root.add_child(panel)
	for i in 4:
		await process_frame
	panel.visible = true
	if panel.has_method("end_action_phase"):
		panel.end_action_phase()
	var MonsterArtS = load("res://client/monster_art.gd")
	var raw: String = MonsterArtS.get_monster_ascii_art("Troll")
	panel.populate({
		"player_class": "Fighter", "player_name": "Dexto", "player_hp": 1500, "player_max_hp": 2000,
		"player_resource_cur": 60, "player_resource_max": 100, "player_resource_color": "#FFAA00",
		"companion_data": _comp("act", "Hydra Sprout", "Hydra", 4, 700, 900),
		"companion_font_size": 4,
		"monster_name": "Troll", "monster_level": 44, "monster_name_color": "#FFFFFF",
		"monster_art_bbcode": "[right][font_size=5]%s[/font_size][/right]" % raw,
		"monster_hp": 4000, "monster_max_hp": 6000, "monster_hp_known": true,
	})
	var team := [
		_comp("t1", "Golem Fragment", "Iron Golem", 6, 120, 400, false, "protect"),
		_comp("t2", "Phoenix Chick", "Phoenix", 6, 90, 90, false),
		_comp("t3", "Demon Imp", "Demon", 4, 0, 160, true),
		_comp("t4", "Siren Sprite", "Siren", 2, 60, 80),
	]
	var cards: Array = []
	for c in team:
		var comp: Dictionary = c.duplicate(true)
		var tag := {"tank": "Tank", "healer": "Healer", "dps": "Striker", "utility": "Utility", "jack": "All-rounder"}
		var role: String = load("res://shared/companion_roles.gd").role_of(comp)
		comp["max_hp"] = int(comp.combat_max_hp)
		comp["name"] = "%s [%s]%s" % [comp.name, tag[role], "  (KO)" if comp.ko else ""]
		cards.append({"name": "", "companion_only": true, "companion": comp, "current_hp": 1, "max_hp": 1})
	panel.set_party_members(cards)
	for i in 6:
		await process_frame
	_shot("res://claude_screenshots/team_combat.png")

	# ---------- 2. companions panel with its Team section ----------
	panel.visible = false
	var fake := Node.new()
	var gs := GDScript.new()
	gs.source_code = "extends Node\nvar character_data = {}\nfunc _get_variant_rarity_info(v):\n\treturn {\"color\": \"#FFFFFF\", \"tier\": \"R3\"}\n"
	gs.reload()
	fake.set_script(gs)
	root.add_child(fake)
	var cp = load("res://client/companions_panel.gd").new()
	cp.anchor_right = 1.0
	cp.anchor_bottom = 1.0
	root.add_child(cp)
	for i in 3:
		await process_frame
	cp.client_ref = fake
	cp.visible = true
	var act := _comp("act", "Hydra Sprout", "Hydra", 4, 700, 900)
	fake.character_data = {"companion_slots": 4, "companion_team": team, "companion_party": ["t1", "t2", "t3", "t4"]}
	cp.populate_companions([act] + team + [_comp("x1", "Wolf Pup", "Wolf", 1, 50, 50), _comp("x2", "Ogre Youngling", "Ogre", 3, 80, 80)], act, "level", false)
	for i in 6:
		await process_frame
	_shot("res://claude_screenshots/team_companions_panel.png")

	# ---------- 3. Stable: Role Swap with three companions picked ----------
	cp.visible = false
	var sp = load("res://client/companion_stable_panel.gd").new()
	sp.anchor_right = 1.0
	sp.anchor_bottom = 1.0
	root.add_child(sp)
	for i in 3:
		await process_frame
	var kennel := [
		_comp("k1", "Goblin Sprite", "Goblin", 2, 1, 1), _comp("k2", "Bone Servant", "Skeleton", 2, 1, 1), _comp("k3", "Zombie Thrall", "Zombie", 2, 1, 1),
		_comp("k4", "Wolf Pup", "Wolf", 1, 1, 1), _comp("k5", "Ogre Youngling", "Ogre", 3, 1, 1)]
	sp.show_with_payload({"kennel": kennel, "collected": [], "registered": [], "kennel_capacity": 30, "gold": 4000})
	sp.visible = true
	sp._set_tab("fuse")
	sp._set_fuse_mode("role")
	for i in 3:
		await process_frame
	for k in range(3):
		sp._fuse_selection.append({"source": "kennel", "index": k, "companion": kennel[k]})
	sp._refresh_fuse_selection_state()
	for i in 4:
		await process_frame
	_shot("res://claude_screenshots/team_role_swap.png")

	# ---------- 4. a PAIR party: the other human + one teammate each ----------
	sp.visible = false
	panel.visible = true
	var kira := {"name": "Kira", "battler_id": "2_1", "current_hp": 1400, "max_hp": 1800, "resource_cur": 50, "resource_max": 80,
		"companion": {"name": "Ashfang", "monster_type": "Kobold", "combat_hp": 60, "max_hp": 90}}
	var mine: Dictionary = _comp("t1", "Golem Fragment", "Iron Golem", 6, 300, 400)
	var hers: Dictionary = _comp("t9", "Phoenix Chick", "Phoenix", 6, 90, 90)
	var RolesUI = load("res://shared/companion_roles.gd")
	var cards2: Array = [kira]
	for pair in [[mine, ""], [hers, "Kira"]]:
		var comp2: Dictionary = (pair[0] as Dictionary).duplicate(true)
		comp2["max_hp"] = int(comp2.combat_max_hp)
		comp2["name"] = "%s [%s]%s" % [comp2.name, RolesUI.role_label(RolesUI.role_of(comp2)), (" (%s)" % pair[1]) if pair[1] != "" else ""]
		cards2.append({"name": "", "companion_only": true, "companion": comp2, "current_hp": 1, "max_hp": 1})
	panel.set_party_members(cards2)
	for i in 6:
		await process_frame
	_shot("res://claude_screenshots/team_party_combat.png")
	print("done")
	quit()

func _shot(path: String) -> void:
	var img := root.get_texture().get_image()
	if img == null:
		print("  (no image for %s)" % path)
		return
	print("  wrote %s (err=%d)" % [path, img.save_png(path)])
