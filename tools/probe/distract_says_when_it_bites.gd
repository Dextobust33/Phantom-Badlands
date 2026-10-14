extends SceneTree
## Playtest sheet item 9: "Distract debuff not shown/applied".
## MEASURED: it IS applied (monster damaged the caster in ~40% of actions after Distract vs ~62%
## after a plain attack). It was never SHOWN: the monster's turn resolves inside the cast action and
## erases the debuff, so the status chip was visible in 0 of 400 casts and the cast-time line was
## the only trace. The monster's turn now announces it where it bites.
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _init() -> void:
	var sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	get_root().add_child(sim)
	await process_frame
	var told := 0
	var control_told := 0
	var N := 60
	for mode in ["distract", "attack"]:
		for f in N:
			var ch = sim.make_char(40, "average", "Grifter", "Human")
			var mon = sim.make_monster(40, "normal", 60.0)
			ch.in_combat = false
			sim.combat_mgr.start_combat(0, ch, mon)
			var c = sim.combat_mgr.active_combats[0]
			ch.current_energy = ch.get_total_max_energy()
			var hand: Array = c.get("combat_hand", [])
			if not hand.has("distract"):
				hand.append("distract")
			c["combat_hand"] = hand
			var r: Dictionary
			if mode == "distract":
				r = sim.combat_mgr.process_ability_command(0, "distract", "")
			else:
				r = sim.combat_mgr.process_combat_action(0, sim.combat_mgr.CombatAction.ATTACK)
			var txt := str(r)
			if txt.find("aim is off") >= 0:
				if mode == "distract":
					told += 1
				else:
					control_told += 1
			sim.combat_mgr.end_combat(0, false, false)
	ck(told >= N - 3, "the monster's turn says Distract bit (%d of %d casts)" % [told, N])
	ck(control_told == 0, "and says nothing after a plain attack (%d)" % control_told)
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
