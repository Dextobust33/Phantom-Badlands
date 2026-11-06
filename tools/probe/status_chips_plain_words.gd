extends SceneTree
# Fighter opening turn: defence + guard buffs are folded into ONE damage-taken chip, and no chip says "4T".
func _init():
	var P = load("res://client/combat_scene_panel.gd").new()
	var st := {"buffs": [
		{"type": "damage_reduction", "value": 10, "duration": 4, "source": "Stance"},
		{"type": "path_guard", "value": 8, "duration": 5, "source": "Path - Guard"},
		{"type": "war_cry", "value": 15, "duration": 3}],
		"mitigation_pct": 22,
		"mitigation_sources": [{"label": "Constitution", "pct": 5}, {"label": "Stance", "pct": 10}, {"label": "Path - Guard", "pct": 8}]}
	var out: String = P._build_player_status_bbcode(st)
	print(out)
	var ok := true
	if out.contains("4T") or out.contains("5T") or out.contains("3T"): ok = false; print("FAIL: T abbreviation")
	if out.contains("Guard 8") and out.split("[url=").size() > 3: ok = false; print("FAIL: guard shown twice")
	if out.split("[url=").size() - 1 != 2: ok = false; print("FAIL: want 2 chips (War Cry + Damage taken), got ", out.split("[url=").size() - 1)
	if not out.contains("left"): ok = false; print("FAIL: no turns-left in hover")
	print("PASS" if ok else "FAILED")
	P.free()
	quit()
