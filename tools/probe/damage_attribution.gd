extends SceneTree
## Does every point of damage the monster LOSES get reported on a line the client can see?
##
## Owner 2026-09-11: "something isn't right with the health on this monster or am I missing
## something in the log?" — a bar that had moved 84 against a log claiming ~706.
##
## The client's enemy bar is driven by `message_damage`, an array the server builds parallel to
## `messages` so the number pops on the right line. If a hit's mark misses that array, the damage
## is still APPLIED but never reported — the monster quietly loses health the player cannot
## account for, or (the reported symptom) the bar under-moves.
##
## Monsters that HEAL are excluded: life steal and regeneration are legitimate reasons for the
## pool to move against the claims, and mixing them in would make this unable to fail honestly.
const CM := preload("res://shared/combat_manager.gd")
const MD := preload("res://shared/monster_database.gd")
const CH := preload("res://shared/character.gd")
const DT := preload("res://shared/drop_tables.gd")

const FIGHTS := 40
const ROUNDS := 4

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _new_mgr():
	var cm = CM.new()
	cm.monster_database = MD.new()
	cm.drop_tables = DT.new()
	var f := FileAccess.open("res://server/balance_config.json", FileAccess.READ)
	if f != null:
		var j := JSON.new()
		if j.parse(f.get_as_text()) == OK:
			cm.balance_config = j.data
		f.close()
	return cm


func _init() -> void:
	var mismatches := 0
	var checked := 0
	var worst := 0
	var sample := ""

	for fight in range(FIGHTS):
		var cm = _new_mgr()
		var ch = CH.new()
		ch.name = "P"
		ch.class_type = "Barbarian"
		ch.level = 8
		ch.max_hp = 99999
		ch.current_hp = 99999
		ch.max_stamina = 9999
		ch.current_stamina = 9999
		ch.active_companion = {"id": "c", "name": "Bone Servant", "monster_type": "Skeleton",
			"tier": 1, "sub_tier": 1, "level": 5, "bonuses": {"attack": 6}, "combat_hp": 99999}

		var mon = cm.monster_database.generate_monster_by_name("Giant Spider", 8)
		# Strip anything that can HEAL the monster — those are legitimate pool movements.
		var ab: Array = []
		for a in mon.get("abilities", []):
			if String(a) in ["life_steal", "regeneration"]:
				continue
			ab.append(a)
		mon["abilities"] = ab
		mon["max_hp"] = 200000
		mon["current_hp"] = 200000
		cm.start_combat(1, ch, mon)
		var st = cm.active_combats[1]

		for r in range(ROUNDS):
			st["combat_hand"] = ["power_strike", "cleave", "bull_rush"]
			var before: int = int(st.monster.current_hp)
			var res = cm.process_ability_command(1, "power_strike", "")
			var after: int = int(st.monster.current_hp)
			var lost: int = before - after
			var claimed := 0
			for d in res.get("message_damage", []):
				claimed += int(d)
			checked += 1
			if absi(claimed - lost) > 2:
				mismatches += 1
				if absi(claimed - lost) > worst:
					worst = absi(claimed - lost)
					var lines: Array = res.get("messages", [])
					var dmgs: Array = res.get("message_damage", [])
					sample = "fight %d round %d: monster lost %d, lines claimed %d (missing %d)\n" % [
						fight + 1, r + 1, lost, claimed, lost - claimed]
					for i in range(lines.size()):
						var d2: int = int(dmgs[i]) if i < dmgs.size() else -1
						var t := String(lines[i])
						if t.length() > 78:
							t = t.substr(0, 78)
						sample += "        dmg=%-5d | %s\n" % [d2, t]

	print("=== %d player actions across %d fights ===" % [checked, FIGHTS])
	print("    rounds where reported damage != actual HP lost: %d (%.0f%%)"
		% [mismatches, 100.0 * float(mismatches) / float(checked)])
	if sample != "":
		print("\n    worst case:")
		print("      " + sample.strip_edges())
	ck(mismatches == 0,
		"every point the monster loses is reported on a line the client can attribute")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
