extends SceneTree
## A personal dungeon must not outlive the player who owns it.
##
## Owner 2026-09-11: *"we need to ensure we have proper cleanup of those after players logout for
## so long or their character dies so they don't just linger on the map."*
##
## This is implemented. The probe exists because it is EXACTLY the shape that rots silently: four
## pieces that must all be present - a grace clock started on disconnect, an immediate drop on
## permadeath, an age cap, and something that actually RUNS the sweep - and losing any one of them
## leaves the other three looking correct. A dungeon that lingers costs memory, draws a `D` on its
## owner's map forever, and is counted against the world's dungeon budget.
##
## Three separate things in this codebase have been written, exported and never called
## (`vision_bonus`, the `--buildverify` probe, the first `first_strike_autocrit`). A reaper that is
## never invoked looks identical to one that finds nothing.

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var s := FileAccess.get_file_as_string("res://server/server.gd")
	var ServerScript = load("res://server/server.gd")

	print("===== THE CLOCK STARTS WHEN THEY LOG OUT =====")
	ck(s.find('active_dungeons[_dc_iid]["abandoned_at"] = _dc_now') >= 0,
		"disconnect stamps `abandoned_at` on every personal dungeon they own")
	ck(s.find('_inst.erase("abandoned_at")') >= 0,
		"...and reconnecting clears it, so coming back does not cost them the run")

	print("\n===== DEATH DROPS THEM AT ONCE =====")
	ck(s.find('_drop_personal_dungeons(String(peers.get(peer_id, {}).get("username", "")), peer_id, "permadeath")') >= 0,
		"permadeath erases them immediately - there is no coming back to them")

	print("\n===== AND NOTHING LIVES FOREVER =====")
	ck(ServerScript.PERSONAL_DUNGEON_GRACE_SECONDS > 0,
		"an offline owner gets %d minutes before the run is let go"
			% int(ServerScript.PERSONAL_DUNGEON_GRACE_SECONDS / 60))
	ck(ServerScript.PERSONAL_DUNGEON_MAX_AGE_SECONDS > 0,
		"and nothing survives past %d hours regardless"
			% int(ServerScript.PERSONAL_DUNGEON_MAX_AGE_SECONDS / 3600))
	ck(ServerScript.PERSONAL_DUNGEON_GRACE_SECONDS < ServerScript.PERSONAL_DUNGEON_MAX_AGE_SECONDS,
		"the grace is shorter than the age cap, or the cap could never be what removes one")

	print("\n===== ⚑ AND SOMETHING ACTUALLY RUNS IT =====")
	# The check that matters. A reaper nobody calls is the fault this file is guarding against.
	var defined: int = s.count("func _sweep_personal_dungeons() -> void:")
	var refs: int = s.count("_sweep_personal_dungeons()")
	ck(defined == 1, "the sweep is defined once")
	ck(refs - defined >= 1,
		"and CALLED from somewhere (%d call site(s) besides the definition)" % (refs - defined))
	ck(s.find("	_sweep_personal_dungeons()") >= 0,
		"...from the periodic dungeon check, not only from a hand-run admin action")

	print("\n===== IT SKIPS THE ONES SOMEBODY IS STANDING IN =====")
	ck(s.find('if not inst.get("active_players", []).is_empty():') >= 0,
		"a dungeon with players inside is never swept out from under them")
	ck(s.find('if int(inst.get("owner_peer_id", -1)) < 0:') >= 0,
		"and WORLD dungeons are left to their own cull, not caught by this one")

	print("\n[PERSONALDUNGEON] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
