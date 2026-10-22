extends SceneTree
## Feat telemetry (docs/design/paths_revamp.md 8.3 item 8): a rung reached in play is counted with the level and played hours it took, so the ladder numbers can be
## retuned from real play. And the catch-up path (a veteran loading a save that predates feats) must NOT feed it.
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _init() -> void:
	var pm = load("res://server/persistence_manager.gd").new()
	pm.note_feat("bosses", 2, 40, 7200)    # 2 hours
	pm.note_feat("bosses", 2, 60, 18000)   # 5 hours
	var led: Dictionary = pm.valor_ledger
	ck(int(led.get("feat:bosses#2", {}).get("n", 0)) == 2, "two characters reached rung 2 of Bosses")
	ck(int(led.get("feat_level:bosses#2", {}).get("sum", 0)) == 100, "their levels sum to 100 (average 50)")
	ck(int(led.get("feat_hours:bosses#2", {}).get("sum", 0)) == 700, "their played hours sum to 7.00 (x100): 2h + 5h")
	var src: String = FileAccess.get_file_as_string("res://server/server.gd")
	var i: int = src.find("func _check_feats(")
	var j: int = src.find("\nfunc ", i + 10)
	var body: String = src.substr(i, j - i)
	var k: int = body.find("if got.size() <= 3:")
	var m: int = body.find("persistence.note_feat(")
	var e: int = body.find("else:", k)
	ck(k >= 0 and m > k and m < e, "only the fresh-rung branch (three or fewer at once) records telemetry; the veteran catch-up summary does not")
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
