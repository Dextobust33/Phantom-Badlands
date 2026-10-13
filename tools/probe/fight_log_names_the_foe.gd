extends SceneTree
## Owner sheet 2026-10-13, item 19: monster traits (Elite, Champion, Swift...) must be in the combat log.
## The header line is built by CombatManager.fight_log_header from the same tables the encounter text uses;
## the client must append it to the battle log at fight start (a statement match, not prose).
const CM := preload("res://shared/combat_manager.gd")
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _init() -> void:
	var plain: String = CM.fight_log_header("Goblin", 12, false, false, false, [], [])
	ck(plain.find("Goblin") >= 0 and plain.find("Lv 12") >= 0, "a plain foe is still named with its level")
	ck(plain.find("Elite") < 0 and plain.find("Swift") < 0, "a plain foe claims no traits")
	var full: String = CM.fight_log_header("Swift Goblin", 40, true, true, true, ["swift", "juggernaut"], ["glass_cannon", "regeneration"])
	for word in ["Elite", "Apex species", "Rare variant", "Swift", "Juggernaut", "Glass Cannon", "Regenerates"]:
		ck(full.find(word) >= 0, "header names \"%s\"" % word)
	ck(full.find("strikes 2-3 times per turn") >= 0, "the Swift chip hovers with what it does")
	# a loot-only trait must not be listed as a danger (same rule as the nameplate)
	var loot: String = CM.fight_log_header("Goblin", 5, false, false, false, [], ["gem_bearer"])
	ck(loot.find("Gem Bearer") < 0, "loot-only traits stay off the header")
	# the client wires it: one statement, inside the combat-scene setup, after populate
	var src := FileAccess.get_file_as_string("res://client/client.gd")
	var stmt := "
	combat_scene_panel.append_log(CombatManager.fight_log_header("
	ck(src.count(stmt) == 1, "client appends the header to the battle log exactly once")
	print("\n[FIGHTLOGHEADER] %s" % ("PASS" if fails == 0 else "FAIL - %d" % fails))
	quit(0 if fails == 0 else 1)
