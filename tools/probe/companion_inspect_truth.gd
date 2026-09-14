extends SceneTree
## Clicking someone's companion must show THEIR companion.
##
## Owner 2026-09-13: *"I just clicked on another players Titan companion and it opened an inspect
## screen that shows an H1 version but his is actually D1."*
##
## The server already put tier, sub_tier, level, name, variant and bonuses in the nearby-players
## payload. The map figure then rebuilt a MINIMAL dict of the four values the sprite needs -
## species and three colours - and dropped the rest, so the inspect fell back to defaults for
## everything missing and invented an H1.
##
## ⚑ THE FAULT IS THE HAND-COPIED SUBSET, not the missing field. Adding "tier" to that list would
## fix the report and leave level, name, variant and bonuses wrong, and the next field added to a
## companion would be wrong again. So the check below is that the WHOLE dict survives the trip,
## not that one key does.
const WorldSystemScript = preload("res://shared/world_system.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var wsrc := FileAccess.get_file_as_string("res://shared/world_system.gd")

	print("===== THE WHOLE COMPANION TRAVELS =====")
	ck(wsrc.find('_fig["companion"] = _oc.duplicate(true)') >= 0,
		"the map figure carries the companion dict ENTIRE, not a hand-picked subset")
	ck(wsrc.find('"variant_pattern": String(_oc.get("variant_pattern", "solid")),') < 0,
		"the four-field copy is gone")

	print("\n===== AND THE SERVER STILL PUTS EVERYTHING IN IT =====")
	# If the producer drops a field, passing the dict through faithfully carries nothing.
	var ssrc := FileAccess.get_file_as_string("res://server/server.gd")
	var need := ["name", "monster_type", "level", "tier", "sub_tier", "variant",
		"variant_color", "variant_pattern", "bonuses"]
	var missing: Array = []
	for k in need:
		if ssrc.find('"%s": active_comp.get("%s"' % [k, k]) < 0:
			missing.append(k)
	ck(missing.is_empty(), "the payload carries every field the inspect reads%s" % [
		"" if missing.is_empty() else " - MISSING: " + ", ".join(missing)])

	print("\n===== THE FIELDS THE REPORT WAS ABOUT =====")
	# A companion's GRADE is tier + sub_tier. Those are what "H1" and "D1" are made of, and a
	# default of 1/1 is exactly "H1" - which is what the player saw.
	ck(ssrc.find('"tier": active_comp.get("tier", 1),') >= 0, "tier is sent (H/G/F... comes from this)")
	ck(ssrc.find('"sub_tier": active_comp.get("sub_tier", 1),') >= 0, "sub_tier is sent (the number after it)")
	var csrc := FileAccess.get_file_as_string("res://client/client.gd")
	ck(csrc.find('var tier = companion.get("tier", 1)') >= 0,
		"and the inspect reads tier, defaulting to 1 - which is why a missing one read as H1")

	print("\n===== A DICT PASSED WHOLE CANNOT DRIFT =====")
	# The point of the fix: a field added to a companion tomorrow arrives without anybody
	# remembering to widen a list. Prove the copy is deep, so the map cannot mutate the source.
	var src_dict := {"monster_type": "Titan", "tier": 4, "sub_tier": 1,
		"bonuses": {"attack": 12}}
	var copied: Dictionary = src_dict.duplicate(true)
	copied["bonuses"]["attack"] = 999
	ck(int(src_dict["bonuses"]["attack"]) == 12,
		"the copy is DEEP, so the map payload cannot write back into a live companion")

	print("\n[COMPANIONINSPECT] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
