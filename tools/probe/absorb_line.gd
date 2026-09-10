extends SceneTree
## A fully-absorbed hit must NAME what absorbed it, not just say "0 damage".
func _init() -> void:
	var sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	get_root().add_child(sim)
	await process_frame
	var cm = sim.combat_mgr
	# amount 0 WITH a mitigation note -> must mention the absorber
	var c1 := {}
	cm._note_mitigation(c1, "Forcefield absorbs 46")
	var absorbed: String = cm._monster_attack_line(c1, "Mimic", 0)
	# amount 0 with NO note -> the plain old line (a genuine whiff)
	var c2 := {}
	var whiff: String = cm._monster_attack_line(c2, "Mimic", 0)
	# a normal hit -> unchanged shape, detail on hover
	var c3 := {}
	cm._note_mitigation(c3, "Constitution 12%")
	var normal: String = cm._monster_attack_line(c3, "Mimic", 37)
	var plain := func(t: String) -> String:
		var out := ""
		var depth := 0
		for i in range(t.length()):
			var ch := t[i]
			if ch == "[":
				depth += 1
			elif ch == "]":
				depth = maxi(0, depth - 1)
			elif depth == 0:
				out += ch
		return out
	print("[ABSORB] absorbed : %s" % plain.call(absorbed))
	print("[ABSORB] whiff    : %s" % plain.call(whiff))
	print("[ABSORB] normal   : %s" % plain.call(normal))
	var bad := 0
	if absorbed.find("Forcefield absorbs 46") < 0:
		print("[ABSORB] FAIL - absorbed hit does not name the absorber"); bad += 1
	if plain.call(whiff).find("0 damage") < 0:
		print("[ABSORB] FAIL - a true whiff should still read as 0 damage"); bad += 1
	if plain.call(normal).find("37") < 0 or normal.find("[url=") < 0:
		print("[ABSORB] FAIL - a normal hit lost its number or its hover"); bad += 1
	print("[ABSORB] %s" % ("PASS" if bad == 0 else "FAIL (%d)" % bad))
	quit(0)
