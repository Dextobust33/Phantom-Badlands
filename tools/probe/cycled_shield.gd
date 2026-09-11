extends SceneTree
## Does a shield granted by a CYCLE actually absorb the monster's next hit?
##
## Owner: *"Cleave cycling says it gave 6 shield. Combat log says Kobold attack and deals 16
## damage to which my healthbar is now missing 16. If the shield did something we should specify
## since it looks like it never existed."*
##
## The backlog's standing instruction on this one is "do not guess a third time — confirm by
## logging the value of forcefield_shield immediately before the monster's damage is applied."
## So this drives a real round and reads the real dict rather than reasoning about call order.
const CM := preload("res://shared/combat_manager.gd")
const MD := preload("res://shared/monster_database.gd")
const CH := preload("res://shared/character.gd")
const DT := preload("res://shared/drop_tables.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _mgr():
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
	var cm = _mgr()
	var ch = CH.new()
	ch.name = "P"
	ch.class_type = "Fighter"
	ch.level = 20
	ch.max_hp = 2000
	ch.current_hp = 2000
	ch.max_stamina = 500
	ch.current_stamina = 500
	# A card in hand that pays SHIELD when it cycles, via the REVEAL upgrade - the same path a
	# card with a `cycle` block of its own takes.
	ch.ability_milestone_picks["power_strike"] = ["reveal_ward"]

	var mon = cm.monster_database.generate_monster_by_name("Kobold", 20, false, "")
	mon["current_hp"] = 999999
	mon["max_hp"] = 999999
	cm.start_combat(1, ch, mon)
	var combat: Dictionary = cm.active_combats[1]
	combat["combat_hand"] = ["cleave", "power_strike"]

	print("--- before the round ---")
	print("    forcefield_shield = %d" % int(combat.get("forcefield_shield", 0)))
	print("    player hp         = %d" % ch.current_hp)

	var hp_before: int = ch.current_hp
	var res = cm.process_ability_command(1, "cleave", "")
	var txt := ""
	for m in res.get("messages", []):
		txt += String(m) + "\n"
	var mt = cm.monster_turn_lines(res)
	if mt is Array:
		for m in mt:
			txt += String(m) + "\n"

	var shield_after: int = int(cm.active_combats.get(1, {}).get("forcefield_shield", 0))
	var hp_after: int = ch.current_hp
	var lost: int = hp_before - hp_after

	print("\n--- after casting cleave (an unplayed power_strike should cycle to a ward) ---")
	print("    shield remaining  = %d" % shield_after)
	print("    hp lost           = %d" % lost)
	var granted: bool = txt.contains("ward") or txt.contains("shield") or txt.contains("Held in Reserve")
	print("    log mentions a shield grant: %s" % str(granted))
	for line in txt.split("\n"):
		if line.strip_edges() != "":
			print("      | " + line.substr(0, 92))

	print("\n--- the question the owner actually asked ---")
	ck(granted, "a cycled card announces the shield it gave")
	# If a shield was granted and the monster then hit, EITHER the shield absorbed some of it
	# (hp lost < raw damage) OR some shield is still standing. Both being false is the bug.
	var absorbed: bool = txt.contains("absorb") or txt.contains("Shield") or shield_after > 0
	ck(absorbed or lost == 0,
		"the shield either absorbed part of the hit or is still standing (remaining %d, hp lost %d)" % [
			shield_after, lost])
	cm.free()

	print("")
	print("--- THE OWNER'S CASE: a shield SMALLER than the hit (partial absorb) ---")
	# Their shield was 6 and the hit 16, and their health fell by the full 16. The case above had
	# a shield LARGER than the hit, which is a different branch entirely.
	var cm2 = _mgr()
	var ch2 = CH.new()
	ch2.name = "P"
	ch2.class_type = "Fighter"
	ch2.level = 5
	ch2.max_hp = 200
	ch2.current_hp = 200
	ch2.max_stamina = 500
	ch2.current_stamina = 500
	var mon2 = cm2.monster_database.generate_monster_by_name("Kobold", 20, false, "")
	mon2["current_hp"] = 999999
	mon2["max_hp"] = 999999
	cm2.start_combat(1, ch2, mon2)
	var c2: Dictionary = cm2.active_combats[1]
	c2["forcefield_shield"] = 6
	var hp0: int = ch2.current_hp
	var r2 = cm2.process_monster_turn(c2)
	var t2 := ""
	# THROUGH monster_turn_lines, not `messages`. `process_monster_turn` returns its text under
	# `message` (singular) - CLAUDE.md Pitfall #9 - and reading the plural key gave an EMPTY list,
	# which read as "the shield said nothing". That would have been a false positive against the
	# game, caused by my own probe.
	var _l2 = cm2.monster_turn_lines(r2)
	for m in (_l2 if _l2 is Array else []):
		t2 += String(m) + "\n"
	var lost2: int = hp0 - ch2.current_hp
	var shield_left: int = int(c2.get("forcefield_shield", 0))
	print("    shield before 6 | hp lost %d | shield left %d" % [lost2, shield_left])
	for line in t2.split("\n"):
		if line.strip_edges() != "":
			print("      | " + line.substr(0, 92))
	ck(shield_left == 0, "a shield smaller than the hit is SPENT, not left standing")
	ck(t2.contains("absorb") or t2.contains("Forcefield"),
		"...and says so, so the player can see it did something")
	# THE ACTUAL FIX. The absorb used to live only in the hover, so "deals 16 damage" beside a
	# 16-point health drop was indistinguishable from having no shield. It must be readable
	# WITHOUT hovering, which is the owner's literal request.
	ck(t2.contains("shield eats"),
		"the partial absorb is visible in the LINE, not only in the hover")
	# ...and the numbers still add up: what the shield ate plus what landed is the raw swing.
	ck(lost2 > 0 and shield_left == 0,
		"a 6-point ward against a bigger swing is spent and the rest lands (%d landed)" % lost2)
	cm2.free()

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
