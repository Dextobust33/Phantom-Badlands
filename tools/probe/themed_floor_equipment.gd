extends SceneTree
## ⛑ DOES A BALROG DUNGEON DROP BALROG GEAR?
##
## Owner 2026-09-08: *"higher chances for players to find floor equipment with affixes related to
## our matching the dungeon type. Example Balrog equipment in a Balrog dungeon."*
##
## The affix pools were ALREADY written for this. 55 of the 120 rows named the monster they were
## themed to — "Balrog-touched", "of the Balrog", "Trollish", "of the Golem" — in a trailing
## COMMENT, which no code could read. So the association existed and was unusable, and the
## obvious implementation was a second dungeon→affix table that would drift the moment either
## side grew. The comment is a FIELD now (`"monster"`), read off the row itself.
##
## What this checks, in the order it matters:
##   1. the promotion is complete and nothing is themed to a creature that does not exist
##   2. EVERY dungeon type can be themed — measured, not hoped
##   3. the bias actually FIRES, against a control that differs in one thing (the theme list)
##   4. what it costs in item power, stated in numbers rather than assumed to be nothing
##   5. the server still PASSES the theme — the whole fault was a value in scope and discarded
##
## Run:
##   godot --headless --path . --script res://tools/probe/themed_floor_equipment.gd

const DT := preload("res://shared/drop_tables.gd")
const DDB := preload("res://shared/dungeon_database.gd")
const MDB := preload("res://shared/monster_database.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _themed_names(pool: Array) -> Array:
	var out: Array = []
	for row in pool:
		if String(row.get("monster", "")) != "":
			out.append(row)
	return out


## How many of `n` rolled items carry an affix naming one of `species`.
func _themed_rate(dt, tier: int, lvl: int, species: Array, n: int) -> Dictionary:
	var hits := 0
	var rolled := 0
	var value_sum := 0.0
	var example := ""
	for _i in range(n):
		var it: Dictionary = dt.roll_dungeon_chest_equipment(tier, lvl, 0, species)
		if it.is_empty():
			continue
		rolled += 1
		var af: Dictionary = it.get("affixes", {})
		var nm: String = String(af.get("prefix_name", "")) + "|" + String(af.get("suffix_name", ""))
		var hit := false
		for sp in species:
			# The affix NAME does not always contain the species ("Draconic" for Dragon), so ask
			# the pool which rows are themed rather than matching on the string.
			for row in _themed_names(DT.PREFIX_POOL):
				if String(row.get("monster", "")) == String(sp) and nm.begins_with(String(row.get("name", "")) + "|"):
					hit = true
			for row in _themed_names(DT.SUFFIX_POOL):
				if String(row.get("monster", "")) == String(sp) and nm.ends_with("|" + String(row.get("name", ""))):
					hit = true
		if hit:
			hits += 1
			if example == "":
				example = String(it.get("name", ""))
		# Item POWER, so the gradient can be reported instead of guessed at.
		for k in af.keys():
			if af[k] is int or af[k] is float:
				if not (k in ["roll_quality"]):
					value_sum += float(af[k])
	return {
		"rate": float(hits) / float(maxi(1, rolled)),
		"rolled": rolled,
		"mean_value": value_sum / float(maxi(1, rolled)),
		"example": example,
	}


func _init() -> void:
	var dt = DT.new()
	var ddb = DDB.new()

	print("===== 1. THE COMMENT IS NOW A FIELD =====")
	var tp: Array = _themed_names(DT.PREFIX_POOL)
	var ts: Array = _themed_names(DT.SUFFIX_POOL)
	print("           %d/%d prefixes and %d/%d suffixes name a monster" % [
		tp.size(), DT.PREFIX_POOL.size(), ts.size(), DT.SUFFIX_POOL.size()])
	ck(tp.size() >= 20, "the prefix pool carries its monster names as data")
	ck(ts.size() >= 36, "the suffix pool carries its monster names as data")
	# ⛑ A themed affix pointing at a creature that does not exist is a silent dead row: it can
	# never be picked, and looks exactly like one that simply never came up.
	var mdb = MDB.new()
	var real: Array = mdb.get_all_monster_names()
	var unknown: Array = []
	for row in tp + ts:
		var m: String = String(row.get("monster", ""))
		if not real.has(m):
			unknown.append("%s -> %s" % [row.get("name", ""), m])
	for u in unknown:
		print("           UNKNOWN CREATURE: " + String(u))
	ck(unknown.is_empty(), "every themed affix names a real monster (%d bad)" % unknown.size())

	print("\n===== 2. EVERY DUNGEON TYPE CAN BE THEMED =====")
	var combined: Array = DT.PREFIX_POOL + DT.SUFFIX_POOL
	var by_boss := 0
	var by_pool := 0
	var bare: Array = []
	var ids: Array = DDB.DUNGEON_TYPES.keys()
	for id in ids:
		var d: Dictionary = DDB.DUNGEON_TYPES[id]
		var boss: String = String(d.get("boss_egg", ""))
		var pool: Array = d.get("monster_pool", [])
		if not DT.themed_affix_subset(combined, [boss]).is_empty():
			by_boss += 1
		elif not DT.themed_affix_subset(combined, pool).is_empty():
			by_pool += 1
		else:
			bare.append("%s (boss %s)" % [id, boss])
	print("           %d dungeon types: %d themed by their boss, %d only by their floor pool, %d bare" % [
		ids.size(), by_boss, by_pool, bare.size()])
	for b in bare:
		print("           NO THEMED AFFIX: " + String(b))
	ck(bare.is_empty(), "no dungeon type is left unthemeable (%d bare)" % bare.size())
	ck(by_boss >= 38, "and most are themed by the boss itself, which is what the owner named")

	print("\n===== 3. THE BIAS FIRES (and the control differs in ONE thing) =====")
	# Balrog's Depths, as the owner's own example. Theme = the boss plus what spawns there.
	var balrog: Array = ["Balrog", "Demon", "Nazgul"]
	var themed: Dictionary = _themed_rate(dt, 7, 400, balrog, 4000)
	var control: Dictionary = _themed_rate(dt, 7, 400, [], 4000)
	# The control still COUNTS Balrog affixes — it just is not biased toward them, which is the
	# only difference between the two cells. A control that also stopped counting them would
	# have proved nothing.
	var base_hits := 0
	var base_rolled := 0
	for _i in range(4000):
		var it: Dictionary = dt.roll_dungeon_chest_equipment(7, 400, 0, [])
		if it.is_empty():
			continue
		base_rolled += 1
		var af: Dictionary = it.get("affixes", {})
		var nm: String = String(af.get("prefix_name", "")) + "|" + String(af.get("suffix_name", ""))
		for row in _themed_names(DT.PREFIX_POOL) + _themed_names(DT.SUFFIX_POOL):
			if balrog.has(String(row.get("monster", ""))) and String(row.get("name", "")) in nm:
				base_hits += 1
				break
	var base_rate: float = float(base_hits) / float(maxi(1, base_rolled))
	print("           themed  %5.1f%% of %d items carry a Balrog-pack affix" % [themed.rate * 100.0, themed.rolled])
	print("           control %5.1f%% of %d items (same pools, no theme)" % [base_rate * 100.0, base_rolled])
	print("           example: %s" % themed.example)
	ck(themed.rate > base_rate * 2.0,
		"the theme at least DOUBLES the chance (%.1f%% vs %.1f%%)" % [themed.rate * 100.0, base_rate * 100.0])
	ck(themed.rate > 0.5, "and it happens often enough for a player to notice (%.1f%%)" % [themed.rate * 100.0])
	ck(themed.rate < 0.98, "but not so often that every piece is the same piece (%.1f%%)" % [themed.rate * 100.0])
	ck(themed.example != "", "and the item's NAME carries it, with no extra naming code")

	print("\n===== 4. WHAT THE BIAS DOES TO ITEM POWER, MEASURED IN ONE UNIT =====")
	# ⛑ THE FIRST VERSION OF THIS CHECK WAS UNSOUND and said the bias cost 11% of item power.
	# It summed raw affix values across DIFFERENT stats - and the pool's hp affixes are worth
	# 40 + 6/level while its attack affixes top out at 7 + 1.2/level. A Balrog dungeon has no
	# hp-themed affix, so biasing toward its own creatures moved the roll off hp and the sum
	# fell. That is a change of stat MIX, not a loss of power, and reading it as one is the
	# "two cells differing in more than one way" trap.
	#
	# The sound question is WITHIN A STAT: when a themed affix is picked instead of a free roll,
	# is it stronger or weaker than an average affix OF THE SAME KIND? That is one unit, so it
	# can be compared - and it can be answered off the pools directly, with no sampling error.
	var fam_mean := {}
	var fam_n := {}
	for row in DT.PREFIX_POOL + DT.SUFFIX_POOL:
		var st: String = String(row.get("stat", ""))
		# The per-level term is what dominates at any real level; the flat base is noise by L50.
		fam_mean[st] = float(fam_mean.get(st, 0.0)) + float(row.get("per_level", 0.0))
		fam_n[st] = int(fam_n.get(st, 0)) + 1
	for st in fam_mean.keys():
		fam_mean[st] = float(fam_mean[st]) / float(maxi(1, int(fam_n[st])))

	var worst_id := ""
	var worst := 999.0
	var best_id := ""
	var best := -999.0
	var themed_total := 0.0
	var themed_count := 0
	for id in ids:
		var d: Dictionary = DDB.DUNGEON_TYPES[id]
		var spec: Array = [String(d.get("boss_egg", ""))]
		for m in d.get("monster_pool", []):
			spec.append(String(m))
		var sub: Array = DT.themed_affix_subset(combined, spec)
		if sub.is_empty():
			continue
		var rel := 0.0
		for row in sub:
			var st: String = String(row.get("stat", ""))
			rel += float(row.get("per_level", 0.0)) / maxf(0.0001, float(fam_mean.get(st, 1.0)))
		rel /= float(sub.size())
		themed_total += rel
		themed_count += 1
		if rel < worst:
			worst = rel
			worst_id = id
		if rel > best:
			best = rel
			best_id = id
	var mean_rel: float = themed_total / float(maxi(1, themed_count))
	print("           across %d dungeon types, a themed affix is worth %.2fx an average affix" % [
		themed_count, mean_rel])
	print("           weakest theme: %-22s %.2fx" % [worst_id, worst])
	print("           strongest theme: %-20s %.2fx" % [best_id, best])
	# The themed rows were written with affix strength matched to monster strength, so this is a
	# GRADIENT and is meant to be: a goblin affix should not be worth a balrog one. What would be
	# wrong is the average being off 1.0, because then every dungeon in the game quietly pays
	# more or less than the pool it replaced.
	ck(absf(mean_rel - 1.0) < 0.15,
		"on average a themed roll is neither a buff nor a nerf (%.2fx)" % mean_rel)
	ck(worst > 0.6, "and no dungeon's theme is a real punishment (%s at %.2fx)" % [worst_id, worst])
	ck(best < 1.6, "and none is a windfall (%s at %.2fx)" % [best_id, best])

	print("\n===== 5. EVERY IN-DUNGEON EQUIPMENT SITE GOES THROUGH THE ONE DOOR =====")
	# ⛑ THIS CHECK IS THE REASON THE FEATURE IS CORRECT. The first cut wired the theme into the
	# scattered floor roll and stopped. This found FIVE `roll_dungeon_chest_equipment` calls in
	# server.gd - the treasure chest, the final chest's two rolls, the guaranteed floor piece and
	# the floor scatter - with four still handing out generic gear, plus a forced fallback calling
	# the generator directly. A player would have seen Balrog gear on the ground and ordinary gear
	# in the chest and had no way to describe the difference.
	#
	# Written as a token BAN with an allowlist rather than a search for the good call, because a
	# search for the good call passes the moment it finds one and says nothing about the others.
	var src := FileAccess.get_file_as_string("res://server/server.gd")
	var allowed := [
		# The /admin floor-item test hook. Spawns a real item outside any dungeon instance, so
		# there is no dungeon to be themed to.
		"var _eq = drop_tables.roll_dungeon_chest_equipment(3, maxi(1, character.level))",
		# The door's own call. It is the one place allowed to reach the generator, and it is the
		# line immediately above `_dungeon_theme_species(instance_id)`.
		"return drop_tables.roll_dungeon_chest_equipment(",
	]
	var offenders: Array = []
	var door_calls := 0
	for line in src.split("\n"):
		var t: String = line.strip_edges()
		if "_dungeon_equipment_for(" in t and not t.begins_with("func "):
			door_calls += 1
		if "drop_tables.roll_dungeon_chest_equipment(" in t and not allowed.has(t):
			offenders.append(t)
	for o in offenders:
		print("           UNTHEMED CALL: " + String(o).substr(0, 130))
	print("           %d sites go through _dungeon_equipment_for" % door_calls)
	ck(offenders.is_empty(),
		"nothing bypasses the door (%d bypass%s)" % [offenders.size(), "" if offenders.size() == 1 else "es"])
	ck(door_calls >= 5, "and all five dungeon-loot sites use it (%d)" % door_calls)

	print("\n===== VERDICT =====")
	print("  all checks PASS" if fails == 0 else "  %d check(s) FAIL" % fails)
	quit(0)
