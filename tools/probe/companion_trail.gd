extends SceneTree
## A companion walks BEHIND its owner, whichever way they are facing.
##
## Owner 2026-09-13: *"Other players companions don't look like they are following them instead
## they seem to always be drawn to the left of them."*
##
## They were. The offset was hard-coded to one cell west, under a comment saying another player's
## facing "is not in the payload" - true, and beside the point: the client had been deriving every
## remote player's facing from their position deltas the whole time, for their own sprite. The
## companion never asked for it.
##
## ⚑ AND BOTH PATHS USE ONE RULE. The local player's companion had its own copy of the same match
## statement. Two copies of one rule is how the local player's companion ends up following
## correctly while everybody else's does not - which is exactly what was reported.

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var src := FileAccess.get_file_as_string("res://client/client.gd")

	print("===== THE RULE EXISTS ONCE =====")
	ck(src.find("func _trail_offset(facing: String) -> Vector2i:") >= 0,
		"there is a single `_trail_offset` helper")
	ck(src.count("_trail_offset(") == 3,
		"and it is CALLED from both companion paths (found %d references incl. the definition)"
			% src.count("_trail_offset("))
	ck(src.find("var tdx := -1") < 0,
		"the local player's private copy of the rule is gone")

	print("\n===== REMOTE COMPANIONS USE THEIR OWNER'S FACING =====")
	ck(src.find('_trail_offset(String(_remote_facings.get(owner_name, "right")))') >= 0,
		"a remote companion is placed from `_remote_facings`, not from a constant")
	ck(src.find("pending_companions.append([int(kp[0]) - 1, int(kp[1]), cpath, comp])") < 0,
		"the hard-coded one-cell-west offset is gone")
	ck(src.find("func _update_remote_facings() -> void:") >= 0,
		"...and the thing that computes those facings is still there")

	print("\n===== BEHIND MEANS BEHIND, IN ALL FOUR DIRECTIONS =====")
	# Screen rows run north to south, so behind an UP-facing player is one row DOWN the grid.
	# Getting that sign backwards would put the companion in front, which looks like a lead, not
	# a follow - and is the kind of thing only a table makes obvious.
	var want := {"right": Vector2i(-1, 0), "left": Vector2i(1, 0),
		"up": Vector2i(0, 1), "down": Vector2i(0, -1)}
	for facing in want:
		var line := '"%s":' % facing
		print("    facing %-6s -> companion at %s" % [facing, str(want[facing])])
	ck(src.find('		"left":\n			return Vector2i(1, 0)') >= 0, "facing left, the companion is to the RIGHT")
	ck(src.find('		"up":\n			return Vector2i(0, 1)') >= 0, "facing up, the companion is BELOW")
	ck(src.find('		"down":\n			return Vector2i(0, -1)') >= 0, "facing down, the companion is ABOVE")
	ck(src.find("return Vector2i(-1, 0)      # facing right, and the default") >= 0,
		"facing right, the companion is to the LEFT - the old behaviour, now only one case of four")

	print("\n[COMPANIONTRAIL] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
