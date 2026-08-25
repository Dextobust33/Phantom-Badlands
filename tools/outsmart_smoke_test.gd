extends SceneTree
# v0.9.698 — headless smoke test of the Trickster Outsmart engine: Read builds via
# abilities, raises the Outsmart chance, get_combat_display reports it, and a failed
# attempt resets Read.

func _init():
	var drop_tables = load("res://shared/drop_tables.gd").new()
	var monster_db = load("res://shared/monster_database.gd").new()
	var combat_mgr = load("res://shared/combat_manager.gd").new()
	var CharacterScript = load("res://shared/character.gd")
	root.add_child(drop_tables); root.add_child(monster_db); root.add_child(combat_mgr)
	combat_mgr.set_balance_config({})
	combat_mgr.set_monster_database(monster_db)
	combat_mgr.drop_tables = drop_tables

	var ch = CharacterScript.new()
	ch.initialize("Smoke", "Thief", "Human")
	for i in range(29):
		ch.level_up()
	ch.current_hp = ch.get_total_max_hp()
	# Fight a LOW-INT weak monster so outsmart is actually plausible.
	var monster = monster_db.generate_monster_by_name("Goblin", 20)
	monster["current_hp"] = monster.get("max_hp", 1)
	combat_mgr.start_combat(0, ch, monster)
	if not combat_mgr.active_combats.has(0):
		print("FAIL: no combat"); quit(); return
	var combat = combat_mgr.active_combats[0]

	print("Read 0 -> outsmart%: ", combat_mgr._outsmart_chance(ch, monster, combat))
	# Cast whatever trickster card is actually in the drawn hand (real-play rule).
	for n in range(5):
		var hand: Array = combat.get("combat_hand", [])
		var cast_name := ""
		for ab in ["sabotage", "ambush", "exploit", "vanish", "gambit", "analyze", "distract"]:
			if ab in hand:
				cast_name = ab
				break
		if cast_name == "":
			print("  (no trickster card in hand: %s)" % str(hand)); break
		var res = combat_mgr.process_ability_command(0, cast_name, "")
		print("  cast %-10s success=%s  Read now=%d" % [cast_name, res.get("success"), int(combat.get("combo"))])
		if int(monster.get("current_hp", 0)) <= 0:
			print("  (monster died mid-build)"); break
	var readv := int(combat.get("combo"))
	print("Read %d -> outsmart%%: " % readv, combat_mgr._outsmart_chance(ch, monster, combat))
	var disp = combat_mgr.get_combat_display(0)
	print("display: read=%s read_max=%s is_trickster_read=%s outsmart_chance=%s" % [disp.get("read"), disp.get("read_max"), disp.get("is_trickster_read"), disp.get("outsmart_chance")])
	# Attempt the outsmart payoff.
	if combat_mgr.active_combats.has(0):
		var read_before = int(combat.get("combo"))
		var r = combat_mgr.process_outsmart(combat)
		var read_after = int(combat.get("combo", -1)) if combat_mgr.active_combats.has(0) else -99
		print("outsmart: success=%s combat_ended=%s victory=%s  read_before=%d read_after=%d" % [r.get("success"), r.get("combat_ended"), r.get("victory", "?"), read_before, read_after])
	print("SMOKE OK")
	quit()
