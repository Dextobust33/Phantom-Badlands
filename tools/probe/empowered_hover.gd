extends SceneTree
## The empowered prefix in a monster's NAME must explain itself on hover.
##
## Owner 2026-09-11: "I just ran into a Juggernaut Giant Spider and tried to hover the Juggernaut
## in it's name and didn't get anything to tell me what Juggernaut does."
##
## The EMPOWERED FOE banner did explain it — in one line, at the moment the fight started, which
## scrolls away. The NAME is the part that stays on screen, and the name is what a player reaches
## for. Same lesson the Scroll of Finding taught earlier the same day.
const CM := preload("res://shared/combat_manager.gd")
const MD := preload("res://shared/monster_database.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var cm = CM.new()

	print("--- EVERY empowered modifier is hoverable, not just the one reported ---")
	for mod_id in MD.EMPOWERED_MODIFIERS:
		var prefix := String(MD.EMPOWERED_MODIFIERS[mod_id].get("prefix", ""))
		ck(prefix != "", "'%s' has a name prefix" % mod_id)
		var desc: String = cm.empowered_mod_hover(String(mod_id))
		ck(desc != "", "'%s' has hover text" % mod_id)
		var name := "%s Giant Spider" % prefix
		var out: String = cm.annotate_empowered_name(name, [mod_id])
		ck(out.contains("[url="), "'%s' is wrapped in a hover link" % prefix)
		ck(out.contains(desc), "'%s' carries its description" % prefix)
		ck(out.ends_with("Giant Spider"), "'%s' leaves the species name intact" % prefix)

	print("\n--- and it does not annotate what it should not ---")
	ck(cm.annotate_empowered_name("Giant Spider", []) == "Giant Spider",
		"a plain monster is untouched")
	ck(cm.annotate_empowered_name("Giant Spider", ["juggernaut"]) == "Giant Spider",
		"a mod the NAME does not carry is not forced in")
	ck(cm.annotate_empowered_name("", ["juggernaut"]) == "", "an empty name is safe")
	ck(cm.annotate_empowered_name("Swift Wolf", null) == "Swift Wolf", "a null mod list is safe")
	# A species whose name merely CONTAINS a prefix word must not be mangled.
	ck(not cm.annotate_empowered_name("Swiftclaw", []).contains("[url="),
		"a species containing a prefix word is untouched when it has no mods")

	print("\n--- stacked modifiers each get their own link ---")
	var two: String = cm.annotate_empowered_name("Vampiric Giant Spider", ["vampiric"])
	ck(two.contains("[url="), "a single stacked mod annotates")
	print("      e.g. %s" % cm.annotate_empowered_name("Juggernaut Giant Spider", ["juggernaut"]))

	print("\n--- the encounter line uses it ---")
	var txt: String = cm.generate_encounter_text({
		"name": "Juggernaut Giant Spider", "level": 12, "max_hp": 200, "current_hp": 200,
		"empowered_mods": ["juggernaut"], "abilities": []})
	ck(txt.contains("[url="), "the encounter line's name is hoverable")
	var plain: String = cm.generate_encounter_text({
		"name": "Giant Spider", "level": 12, "max_hp": 200, "current_hp": 200, "abilities": []})
	ck(not plain.contains("[url="), "...and a plain encounter has nothing to hover")

	print("\n--- so does the NAMEPLATE, through the same helper ---")
	var cs := FileAccess.get_file_as_string("res://client/client.gd")
	ck(cs.contains("CombatManager.annotate_empowered_name("),
		"the client annotates the name it sends to the combat panel")
	var ps := FileAccess.get_file_as_string("res://client/combat_scene_panel.gd")
	ck(ps.contains("_monster_name_label.meta_hover_started.connect"),
		"the nameplate label listens for hover (it did not before)")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
