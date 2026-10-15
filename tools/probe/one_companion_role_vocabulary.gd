extends SceneTree
## A companion's ROLE has ONE source: shared/companion_roles.gd. The combat card, the combat overlay and the inspect
## screens used to label a companion from its AGGRO number alone (Tank / Fighter / Default / Evasive) - a second
## vocabulary that contradicted the real one (a Wolf was "Default" there and "Striker" everywhere else; a Troll was
## "Tank" there and "Healer" elsewhere). Source-reading probe: matches CODE statements, never comments.
## Run:  godot --headless --path . --script res://tools/probe/one_companion_role_vocabulary.gd
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _code_lines(path: String) -> Array:
	var out: Array = []
	for ln in FileAccess.get_file_as_string(path).split("\n"):
		var t := String(ln).strip_edges(true, false)
		if not t.begins_with("#"):
			out.append(String(ln))
	return out

func _count(lines: Array, needle: String) -> int:
	var n := 0
	for l in lines:
		if String(l).find(needle) >= 0:
			n += 1
	return n

func _init() -> void:
	var cl := _code_lines("res://client/client.gd")
	var cp := _code_lines("res://client/combat_scene_panel.gd")
	ck(_count(cl, "func _get_aggro_role_info(") == 0, "the aggro-band role function is gone")
	ck(_count(cl, "_get_aggro_role_info(") == 0 and _count(cp, "_get_aggro_role_info(") == 0, "nothing calls it")
	ck(_count(cl, "aggro_label = \"Tank\"") == 0 and _count(cl, "aggro_label = \"Fighter\"") == 0, "no inspect surface relabels aggro as a role")
	ck(_count(cp, "CompanionRolesScript.role_label(") >= 2, "the combat card and overlay take the role from the roles module (%d reads)" % _count(cp, "CompanionRolesScript.role_label("))
	ck(_count(cl, "CompanionRolesUI.aggro_phrase(") >= 2, "the inspect screens describe aggro in non-role words (%d)" % _count(cl, "CompanionRolesUI.aggro_phrase("))
	print("")
	print(("PASS - one_companion_role_vocabulary" if fails == 0 else "FAIL - one_companion_role_vocabulary: %d check(s)" % fails))
	quit(1 if fails > 0 else 0)
