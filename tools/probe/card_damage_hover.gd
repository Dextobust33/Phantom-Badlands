extends SceneTree
## A companion/dungeon card's damage number must be hoverable AND pop over the monster.
##
## Reported 2026-09-10: "I used Venom fang and the damage number doesn't seem to be hoverable
## still." The uniform-hover change landed in `_damage_with_detail` - and this whole card path
## never called it, building its lines with a raw %d. That also meant no `_dmg_marks` entry, so
## these cards never popped a floating damage number over the enemy either.
func _init() -> void:
	var sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	get_root().add_child(sim)
	await process_frame
	var ch = sim.make_char(30, "average", "Fighter", "Human")
	ch.initialize_deck_collection_if_needed()
	var cid := "dungeon_card_venom_fang"
	ch.combat_deck_collection[cid] = 3
	var mon = sim.make_monster(30, "normal", 8.0)
	sim.combat_mgr.start_combat(0, ch, mon)
	var c = sim.combat_mgr.active_combats[0]
	c["combat_hand"] = [cid]
	c["player_can_act"] = true
	c["suppress_monster_turn"] = true
	ch.current_stamina = ch.get_total_max_stamina()
	var res: Dictionary = sim.combat_mgr.process_ability_command(0, cid, "10")
	var hoverable := 0
	var line := ""
	for m in res.get("messages", []):
		var t := String(m)
		if t.find("Venom Fang") >= 0:
			line = t
			if t.find("[url=") >= 0:
				hoverable += 1
	var marks = c.get("_dmg_marks", [])
	print("[CARDHOVER] line: %s" % line)
	print("[CARDHOVER] hoverable=%d  damage marks recorded=%d" % [hoverable, (marks.size() if marks is Array else -1)])
	var bad := 0
	if hoverable == 0:
		print("[CARDHOVER] FAIL - the number carries no hover"); bad += 1
	if not (marks is Array) or marks.is_empty():
		print("[CARDHOVER] FAIL - no damage mark, so no number pops over the monster"); bad += 1
	print("[CARDHOVER] %s" % ("PASS" if bad == 0 else "FAIL"))
	quit(0)
