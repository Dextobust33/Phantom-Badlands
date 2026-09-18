extends SceneTree
## ⛑ A THREAT BOUNTY SCALES WITH THE LAND, AND BOTH PATHS AGREE ON WHAT IT PAYS.
##
## Owner, reading a quest board, 2026-09-17: *"the Threat quest doesn't seem to scale and is low
## rewards."* It did not: the reward was a flat lookup on the dungeon TYPE, so driving a threat off
## a post in level-200 country paid exactly what the same type of threat paid outside Haven, while
## every other quest on that board had already been re-anchored to the land.
##
## Two things are checked, and the second is the one with history:
##
##   1. the payout RISES with the post's area level, and never falls below the old flat table;
##   2. the OFFER path and the REHYDRATE path return the same numbers.
##
## (2) is not hypothetical. In v0.9.596 those two paths disagreed - the regen path returned
## {xp: 0, valor: 0} while the offer path had the real table - and every threat quest paid nothing
## at turn-in for as long as it took a player to report it. The fix then was to give both a single
## helper; this asserts they are still calling it the same way, which is the part a refactor breaks.
##
## Run:
##   godot --headless --path . --script res://tools/probe/threat_quest_rewards.gd

const QD = preload("res://shared/quest_database.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	# A type that exists, so the tier weight is real rather than the default.
	var dtype := ""
	for k in QD.DungeonDatabaseScript.DUNGEON_TYPES.keys():
		dtype = String(k)
		break
	ck(dtype != "", "found a dungeon type to price (%s)" % dtype)

	print("\n===== IT MOVES WITH THE LAND =====")
	var posts := ["haven", "northeast_farm", "northwatch"]
	var seen: Array = []
	for pid in posts:
		var lvl: int = QD.area_level_for_post(pid)
		var r: Dictionary = QD.get_threat_relief_rewards(dtype, pid)
		var flat: Dictionary = QD.get_threat_relief_rewards(dtype)
		print("  %-16s area_level=%-4d  xp=%-8d valor=%-5d   (flat was xp=%d valor=%d)" % [
			pid, lvl, int(r["xp"]), int(r["valor"]), int(flat["xp"]), int(flat["valor"])])
		ck(int(r["xp"]) >= int(flat["xp"]) and int(r["valor"]) >= int(flat["valor"]),
			"  %s: never pays LESS than the flat table it replaced" % pid)
		seen.append({"lvl": lvl, "xp": int(r["xp"]), "valor": int(r["valor"])})

	# Sort by level and assert the payout is non-decreasing across them.
	seen.sort_custom(func(a, b): return int(a["lvl"]) < int(b["lvl"]))
	var rising_xp := true
	var rising_valor := true
	for i in range(1, seen.size()):
		if int(seen[i]["xp"]) < int(seen[i - 1]["xp"]):
			rising_xp = false
		if int(seen[i]["valor"]) < int(seen[i - 1]["valor"]):
			rising_valor = false
	ck(rising_xp, "XP never falls as the post gets deeper")
	ck(rising_valor, "valor never falls as the post gets deeper")
	# The complaint was that it did not scale AT ALL - so a flat result is the failure.
	ck(int(seen[seen.size() - 1]["valor"]) > int(seen[0]["valor"]),
		"the deepest post pays MORE valor than the shallowest (%d vs %d) - the actual complaint"
			% [int(seen[seen.size() - 1]["valor"]), int(seen[0]["valor"])])

	print("\n===== THE OFFER AND THE REHYDRATE AGREE =====")
	# The rehydrate path parses post+type out of the quest id; the offer path is handed them.
	# Same helper, same arguments - the thing that broke in v0.9.596 was one side not doing this.
	var src := FileAccess.get_file_as_string("res://shared/quest_database.gd")
	ck(src.find("get_threat_relief_rewards(dungeon_type, post_id)") >= 0,
		"the rehydrate path passes the post it parsed out of the quest id")
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	ck(srv.find("get_threat_relief_rewards(dungeon_type, tp.id)") >= 0,
		"the offer path passes the post the board belongs to")
	ck(srv.find("get_threat_relief_rewards(dungeon_type)\n") < 0,
		"...and no caller is left on the unanchored form")
	for pid in posts:
		var a: Dictionary = QD.get_threat_relief_rewards(dtype, pid)
		var b: Dictionary = QD.get_threat_relief_rewards(dtype, pid)
		ck(int(a["xp"]) == int(b["xp"]) and int(a["valor"]) == int(b["valor"]),
			"  %s: the same quest priced twice gives the same answer" % pid)

	print("")
	print("===== SIZED AGAINST THE BOARD IT SITS ON =====")
	# ⛑ TUNE TO A TARGET, NOT TO A NUMBER THAT LOOKS BIG. A threat bounty is a full dungeon
	# clear plus an emergency, so the thing it must be comparable to is an ORDINARY dungeon quest
	# at the same post - printed here rather than assumed, because the first version of this fix
	# capped threat XP at 4000 and that looked fine until it was put beside the real board.
	var q = QD.new()
	get_root().add_child(q)
	for pid in posts:
		var best_xp := 0
		var best_valor := 0
		var n := 0
		var xps: Array = []
		var vls: Array = []
		for quest in q.generate_dynamic_quests(pid, [], [], 30, 0, {}, "probe"):
			if not quest.has("dungeon_tier"):
				continue
			n += 1
			best_xp = maxi(best_xp, int(quest.get("rewards", {}).get("xp", 0)))
			best_valor = maxi(best_valor, int(quest.get("rewards", {}).get("valor", 0)))
			xps.append(int(quest.get("rewards", {}).get("xp", 0)))
			vls.append(int(quest.get("rewards", {}).get("valor", 0)))
		var tr: Dictionary = QD.get_threat_relief_rewards(dtype, pid)
		print("  %-16s dungeon quest best: xp=%-8d valor=%-5d (%d quests) | threat: xp=%-8d valor=%d" % [
			pid, best_xp, best_valor, n, int(tr["xp"]), int(tr["valor"])])
		xps.sort()
		vls.sort()
		# ⛑ THE MEDIAN IS THE TARGET, NOT THE BEST. A board carries seven dungeon quests of
		# wildly different sizes; measuring against the largest makes any sane figure look
		# tiny and would drive the bounty far too high.
		if xps.size() > 0:
			var mid_xp: int = int(xps[xps.size() / 2])
			var mid_vl: int = int(vls[vls.size() / 2])
			print("      median dungeon quest: xp=%-8d valor=%d" % [mid_xp, mid_vl])
			if mid_xp > 0:
				var rx: float = float(tr["xp"]) / float(mid_xp)
				var rv: float = float(tr["valor"]) / float(maxi(1, mid_vl))
				print("      threat is %.2fx median XP, %.2fx median valor" % [rx, rv])
				# ⛑ A BAND, NOT A NUMBER. ±10pp is noise on a randomly generated board; the fault
				# worth catching is the GROSS one this item existed for - 0.06x at depth. Judged
				# loosely on purpose, so a content change that shifts the board slightly does not
				# turn this red for no reason.
				ck(rx >= 0.6 and rx <= 1.6,
					"  %s: threat XP is within reach of a median dungeon quest (%.2fx)" % [pid, rx])
				ck(rv >= 0.8,
					"  %s: and its valor is not below one either (%.2fx)" % [pid, rv])
	print("")
	if fails == 0:
		print("[PROBE] PASS threat bounties scale with the land and price consistently")
	else:
		print("[PROBE] FAIL %d check(s)" % fails)
	quit(1 if fails > 0 else 0)
