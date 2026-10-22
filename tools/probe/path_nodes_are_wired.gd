extends SceneTree
## Every Path node's effect keys must be READ by game code (docs/design/paths_revamp.md 8.3, `pathfires` step 1).
## Until 2026-10-21 `vs_burning_damage_pct` (the Mage's Combustion) had no reader: taking it cost a point and did nothing.
## A source probe matches CODE, never prose: comment lines are skipped and a trailing comment is cut off before matching.
const PD = preload("res://shared/path_database.gd")
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _code_of(path: String) -> String:
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var out: PackedStringArray = []
	for line in f.get_as_text().split("\n"):
		var t: String = line.strip_edges()
		if t.begins_with("#"):
			continue
		var hash_at: int = line.find(" #")
		out.append(line.substr(0, hash_at) if hash_at >= 0 else line)
	return "\n".join(out)

func _init() -> void:
	var files: Array = []
	for dir in ["res://shared", "res://server", "res://client"]:
		var d = DirAccess.open(dir)
		for fn in d.get_files():
			if fn.ends_with(".gd") and fn != "path_database.gd":
				files.append(dir + "/" + fn)
	var code := ""
	for p in files:
		code += _code_of(p) + "\n"
	var keys: Dictionary = {}
	for arch in PD.TREES:
		var tree: Dictionary = PD.TREES[arch]
		for b in tree.get("branches", []):
			for n in b.get("nodes", []):
				for k in n.get("effect", {}):
					keys[String(k)] = String(n.get("id", ""))
		for cls in PD.SIGNATURES:
			for sn in PD.SIGNATURES[cls].get("nodes", []):
				for k in sn.get("effect", {}):
					keys[String(k)] = String(sn.get("id", ""))
		for cls in tree.get("class_keystones", {}):
			var ck_node: Dictionary = tree["class_keystones"][cls]
			for k in ck_node.get("effect", {}):
				keys[String(k)] = String(ck_node.get("id", ""))
	for cls in PD.ASCENDANTS:
		for an in PD.ASCENDANTS[cls].get("nodes", []):
			for k in an.get("effect", {}):
				keys[String(k)] = String(an.get("id", ""))
	print("--- %d distinct effect keys across the trees ---" % keys.size())
	var unread: Array = []
	for k in keys:
		var read: bool = code.contains("get_path_effect_total(\"%s\")" % k) or code.contains("has_path_effect(\"%s\")" % k)
		# A trigger key is read by Character.trigger_power for every id in the trigger table, so it is "read" exactly when that trigger exists.
		if String(k).begins_with("trg_"):
			read = preload("res://shared/combat_triggers.gd").TRIGGERS.has(String(k).substr(4))
		if not read:
			unread.append("%s (node %s)" % [k, keys[k]])
	ck(unread.is_empty(), "every effect key has a reader" + ("" if unread.is_empty() else ": UNREAD " + ", ".join(unread)))
	# The detector must be able to fire: a made-up key has no reader.
	var fake: bool = code.contains("get_path_effect_total(\"zz_not_a_real_key\")") or code.contains("has_path_effect(\"zz_not_a_real_key\")")
	ck(not fake, "the detector says a made-up key is unread")
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
