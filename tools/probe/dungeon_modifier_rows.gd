extends SceneTree
## ⛑ A MODIFIER MUST STATE ITS TRADE IN NUMBERS, AND THE NUMBERS MUST BE THE REAL ONES.
##
## Owner direction: dungeon modifiers are a RISK/REWARD TRADE, and visible before you go in. The
## entry screen showed the name and a flavour blurb - "What died here did not finish dying" - and
## never once said 40% more HP or +20% XP. A sentence about dying is not something you can weigh.
##
## The fault this guards against is the one that has cost this codebase most often: a hand-written
## sentence sitting beside a number. Tune `hp_mult` from 1.40 to 1.25 and the copy still says 40%,
## confidently and forever. So `modifier_rows` DERIVES its wording from the same fields
## `modifier_effects` folds, and this asserts that derivation against the table - including that
## every modifier in the table has BOTH halves, because one with no upside is not a trade.
##
## Run:
##   godot --headless --path . --script res://tools/probe/dungeon_modifier_rows.gd

const DungeonDB := preload("res://shared/dungeon_database.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	print("===== 1. EVERY MODIFIER STATES BOTH HALVES OF THE TRADE =====")
	for key in DungeonDB.DUNGEON_MODIFIERS.keys():
		var rows: Array = DungeonDB.modifier_rows([key])
		ck(rows.size() == 1, "%s produces a row" % key)
		if rows.is_empty():
			continue
		var r: Dictionary = rows[0]
		ck(String(r.get("cost", "")) != "", "%s says what it COSTS  -> %s" % [key, r.get("cost", "")])
		ck(String(r.get("pay", "")) != "", "%s says what it PAYS   -> %s" % [key, r.get("pay", "")])

	print("\n===== 2. AND THE NUMBERS COME OFF THE TABLE, NOT OUT OF A SENTENCE =====")
	# The whole point of deriving them. If someone retunes `hp_mult` the screen must move with it,
	# so re-derive the expected text here from the SAME fields rather than hardcoding "40%".
	for key in DungeonDB.DUNGEON_MODIFIERS.keys():
		var d: Dictionary = DungeonDB.DUNGEON_MODIFIERS[key]
		var r: Dictionary = DungeonDB.modifier_rows([key])[0]
		if float(d.get("hp_mult", 1.0)) != 1.0:
			var want := "%d%% more HP" % int(round((float(d["hp_mult"]) - 1.0) * 100.0))
			ck(String(r["cost"]).contains(want), "%s quotes its real hp_mult (%s)" % [key, want])
		if float(d.get("xp_mult", 1.0)) != 1.0:
			var want_xp := "+%d%% XP" % int(round((float(d["xp_mult"]) - 1.0) * 100.0))
			ck(String(r["pay"]).contains(want_xp), "%s quotes its real xp_mult (%s)" % [key, want_xp])

	print("\n===== 3. THE PROSE SURFACE IS BUILT FROM THE SAME ROWS =====")
	# `modifier_lines` feeds the dungeon LIST. It used to own its own formatting, which is two
	# copies of one fact - the exact shape that has produced a wrong-text bug on nearly every
	# player-facing surface in this project.
	var lines: Array = DungeonDB.modifier_lines(["bloodgorged"])
	ck(lines.size() == 1, "one line per modifier")
	ck(String(lines[0]).contains("40% more HP") and String(lines[0]).contains("+20% XP"),
		"the list line carries the same numbers as the entry screen")
	ck(String(lines[0]).contains("Bloodgorged"), "...and still names it")

	print("\n===== 4. AND NOTHING IS INVENTED FOR A MODIFIER THAT DOES NOT EXIST =====")
	ck(DungeonDB.modifier_rows([]).is_empty(), "a plain dungeon has no rows")
	ck(DungeonDB.modifier_rows(["not_a_real_modifier"]).is_empty(), "an unknown key is skipped")

	print("\n===== VERDICT =====")
	print("  all checks PASS" if fails == 0 else "  %d check(s) FAIL" % fails)
	quit(0)
