extends SceneTree
## Owner sheet 2026-10-13, item 26: legendaries/artifacts "just show up in your inventory". The loot minigame
## celebrated rare/epic/legendary but not ARTIFACT, and the victory card gave a top find no more emphasis than a
## common one. Statement-level checks on both files.
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _init() -> void:
	var loot := FileAccess.get_file_as_string("res://client/combat_loot_panel.gd")
	ck(loot.count("[\"rare\", \"epic\", \"legendary\", \"artifact\"]") == 2, "loot panel celebrates and marks artifact (notable + reveal burst)")
	ck(loot.find("\t\t\t\"artifact\": score = 120\n") >= 0, "artifact tops the preview ranking")
	var card := FileAccess.get_file_as_string("res://client/combat_scene_panel.gd")
	ck(card.find("if _gd is Dictionary and String(_gd.get(\"rarity\", \"\")) in [\"legendary\", \"artifact\"]:") >= 0, "victory card has the top-rarity headline")
	print("\n[TOPRARITY] %s" % ("PASS" if fails == 0 else "FAIL - %d" % fails))
	quit(0 if fails == 0 else 1)
