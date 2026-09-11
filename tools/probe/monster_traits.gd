extends SceneTree
## Every announced monster trait must be real, named, and explain itself on hover.
##
## Owner 2026-09-10: "lets go ahead and make those name traits hoverable as well as venemous,
## champion, etc. so players can know what they mean or do to the monster."
##
## This replaced twenty hand-written `if ABILITY_X in abilities: append(...)` lines — which is how
## three traits came to be missing from the list entirely while still being offered by a scroll.
const CM := preload("res://shared/combat_manager.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var cm = CM.new()

	print("--- every key is a REAL ability id, not a typo ---")
	# Collect the ABILITY_* constant VALUES from the source, then check every table key is one.
	var src := FileAccess.get_file_as_string("res://shared/combat_manager.gd")
	var re := RegEx.new()
	re.compile("const ABILITY_[A-Z_]+ = \"([a-z_]+)\"")
	var real := {}
	for m in re.search_all(src):
		real[m.get_string(1)] = true
	print("      %d ABILITY_* constants declared, %d traits in the table"
		% [real.size(), CM.MONSTER_TRAITS.size()])
	for k in CM.MONSTER_TRAITS:
		ck(real.has(k), "'%s' matches a declared ABILITY_* constant" % k)

	print("\n--- every trait is named, coloured and explained ---")
	var seen_labels := {}
	for k in CM.MONSTER_TRAITS:
		var t: Dictionary = CM.MONSTER_TRAITS[k]
		var lab := String(t.get("label", ""))
		var desc := String(t.get("desc", ""))
		var col := String(t.get("color", ""))
		if lab == "" or desc == "" or col == "":
			ck(false, "'%s' is missing label/desc/color" % k)
			continue
		if seen_labels.has(lab):
			ck(false, "'%s' reuses the label '%s'" % [k, lab])
		seen_labels[lab] = true
	ck(seen_labels.size() == CM.MONSTER_TRAITS.size(),
		"all %d traits have a distinct label, colour and description" % CM.MONSTER_TRAITS.size())

	print("\n--- and each one is HOVERABLE in the encounter line ---")
	for k in CM.MONSTER_TRAITS:
		var txt: String = cm.generate_encounter_text({
			"name": "Wolf", "level": 5, "max_hp": 10, "current_hp": 10, "abilities": [k]})
		var lab := String(CM.MONSTER_TRAITS[k].get("label", ""))
		var desc := String(CM.MONSTER_TRAITS[k].get("desc", ""))
		ck(txt.contains("[url="), "'%s' is wrapped in a hover link" % k)
		ck(txt.contains(desc), "'%s' carries its description in the link" % k)
		ck(txt.contains(lab), "'%s' still shows its label" % k)

	print("\n--- the six scroll traits are all in it ---")
	for k in CM.SCROLL_TRAITS:
		ck(CM.MONSTER_TRAITS.has(k),
			"scroll trait '%s' is announced (this is the check that was missing)" % k)

	var sample: String = cm.generate_encounter_text({
		"name": "Wolf", "level": 5, "max_hp": 10, "current_hp": 10,
		"abilities": ["poison", "weapon_master"]})
	print("\n      sample: %s" % sample.replace("\n", " | "))

	print("")
	print("--- a CHAMPION explains itself, with the calibrated numbers ---")
	var champ: String = cm.generate_encounter_text({
		"name": "Skeleton Champion", "level": 9, "max_hp": 10, "current_hp": 10,
		"variant_type": "elite", "abilities": []})
	var plain_m: String = cm.generate_encounter_text({
		"name": "Skeleton", "level": 9, "max_hp": 10, "current_hp": 10, "abilities": []})
	ck(champ.contains("CHAMPION"), "an elite is announced at all (it used to be name-only)")
	ck(not plain_m.contains("CHAMPION"), "an ordinary monster is not")
	ck(champ.contains("[url="), "the champion banner is hoverable")
	# The numbers must be READ from the database, not restated — so they track rolecal.
	var md = load("res://shared/monster_database.gd").new()
	var em: Dictionary = md.role_multipliers("elite", 9)
	var want: String = "%.0f%%" % (float(em.get("hp_mult", 1.0)) * 100.0)
	ck(champ.contains(want),
		"it shows the LIVE hp multiplier (%s), so a recalibration cannot stale it" % want)
	print("      champion line: %s" % champ.split("
")[1])

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
