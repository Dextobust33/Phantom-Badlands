extends SceneTree
## The class ENGINE ramp on a card face must equal the one the hit actually uses.
##
## Owner 2026-09-10: *"Killing shot on the ranger seems like it may not be estimating damage
## properly. Possibly just on higher Aim meters."* The finisher was the symptom. Steady Aim
## (+11%/Aim) and Rage (+16%/Rage) are applied inside `apply_ability_damage_modifiers`, the funnel
## EVERY damaging card passes through — and the client card faces knew nothing about either, so
## every card was right at an empty meter and understated by stacks x 11% (or 16%) at every other
## value. Up to 88% low on a full Aim bar.
const CM := preload("res://shared/combat_manager.gd")
const CH := preload("res://shared/character.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _char(klass: String):
	var c = CH.new()
	c.name = "P"
	c.class_type = klass
	c.level = 10
	return c


func _init() -> void:
	var cm = CM.new()

	print("--- the ramp matches the constants the funnel multiplies by ---")
	var r = _char("Ranger")
	for aim in [0, 1, 4, CM.COMBO_MAX]:
		var got: float = cm.engine_damage_ramp(r, {"combo": aim})
		var want: float = 1.0 + float(aim) * CM.RANGER_AIM_DMG_PER
		ck(absf(got - want) < 0.0001,
			"Ranger at %d Aim -> x%.2f (+%d%%)" % [aim, got, int((got - 1.0) * 100.0)])
	var b = _char("Barbarian")
	for rage in [0, 1, 3, CM.MOMENTUM_MAX]:
		var got2: float = cm.engine_damage_ramp(b, {"momentum": rage})
		var want2: float = 1.0 + float(rage) * CM.BARBARIAN_RAGE_DMG_PER
		ck(absf(got2 - want2) < 0.0001,
			"Barbarian at %d Rage -> x%.2f (+%d%%)" % [rage, got2, int((got2 - 1.0) * 100.0)])

	print("\n--- and it is 1.0 for everyone else, and for a null character ---")
	for k in ["Fighter", "Wizard", "Grifter", "Ninja", "Paladin", "Sage", "Sorcerer"]:
		var c = _char(k)
		ck(absf(cm.engine_damage_ramp(c, {"combo": 8, "momentum": 5}) - 1.0) < 0.0001,
			"%s has no engine ramp even with full meters" % k)
	ck(absf(cm.engine_damage_ramp(null, {}) - 1.0) < 0.0001, "a null character is safe")
	# A meter beyond its cap must not run away.
	ck(absf(cm.engine_damage_ramp(r, {"combo": 999}) - (1.0 + float(CM.COMBO_MAX) * CM.RANGER_AIM_DMG_PER)) < 0.0001,
		"an over-full Aim meter clamps at COMBO_MAX")

	print("\n--- the funnel and the card face are the SAME computation ---")
	var src := FileAccess.get_file_as_string("res://shared/combat_manager.gd")
	ck(src.count("engine_damage_ramp(character, combat)") >= 3,
		"the funnel (both classes) and the wire all call the one helper")
	ck(not src.contains("* (1.0 + float(_aim) * RANGER_AIM_DMG_PER)"),
		"the Ranger funnel no longer has its own inline copy of the maths")
	ck(not src.contains("* (1.0 + float(_rage) * BARBARIAN_RAGE_DMG_PER)"),
		"nor does the Barbarian's")
	ck(src.contains('"engine_damage_ramp": engine_damage_ramp(character, combat)'),
		"it is sent as combat STATE, so the client never owns the constant")

	print("\n--- the client reads it rather than recomputing it ---")
	var cl := FileAccess.get_file_as_string("res://client/client.gd")
	ck(cl.contains('_combat_engine_ramp = maxf(0.01, float(state.get("engine_damage_ramp", 1.0)))'),
		"the client caches the server's value")
	ck(cl.contains("mult *= _combat_engine_ramp"),
		"...and folds it into the outgoing-damage estimate")
	# Look at CODE, not prose: the explanatory comment beside the fix names the constant on
	# purpose, and an earlier version of this check failed on its own documentation.
	var code_only := ""
	for line in cl.split("
"):
		var t := String(line).strip_edges()
		if t.begins_with("#"):
			continue
		code_only += t + "
"
	ck(not code_only.contains("RANGER_AIM_DMG_PER") and not code_only.contains("BARBARIAN_RAGE_DMG_PER"),
		"no copy of either constant exists in client CODE (comments may name them)")
	ck(cl.contains("_combat_engine_ramp = 1.0"), "and it resets when combat ends")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
