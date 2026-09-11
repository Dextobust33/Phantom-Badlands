extends SceneTree
## What a dungeon actually hands you, as numbers rather than impressions.
##
## Owner 2026-09-10: "Currently it seems like Equipment is pretty seldom in dungeons can we up the
## amount of it slightly? ... going through a whole dungeon without finding any doesn't feel
## great." The complaint is about the ZERO case, which a percentage alone cannot fix.
const SERVER := "res://server/server.gd"
const DD := preload("res://shared/dungeon_database.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _bands() -> Dictionary:
	"""The roll boundaries, read out of _roll_floor_item rather than copied."""
	var src := FileAccess.get_file_as_string(SERVER)
	var lines := src.split("\n")
	var a := -1
	var b := lines.size()
	for i in range(lines.size()):
		if lines[i].begins_with("func _roll_floor_item"):
			a = i
		elif a >= 0 and lines[i].begins_with("func ") and i > a:
			b = i
			break
	var out := {}
	var re := RegEx.new()
	re.compile("roll < ([0-9]+):[ \t]*#[ \t]*([a-z0-9% ]+)")
	for i in range(a, b):
		var m := re.search(lines[i])
		if m != null:
			out[m.get_string(2).strip_edges()] = int(m.get_string(1))
	return out


func _init() -> void:
	var b := _bands()
	print("      roll boundaries: %s" % str(b))
	ck(b.has("crafting material") and b.has("valor coins") and b.has("equipment"),
		"found the material / valor / equipment bands")
	var eq_lo: int = int(b.get("valor coins", 0))
	var eq_hi: int = int(b.get("equipment", 0))
	var eq_pct: int = eq_hi - eq_lo
	print("      equipment band: %d..%d  = %d%%" % [eq_lo, eq_hi, eq_pct])
	ck(eq_pct >= 25 and eq_pct <= 30,
		"equipment is ~26%% of a floor-item roll (was 20%%), raised but not overdone")

	# What that means for a whole tier-1 dungeon.
	var dd = DD.get_dungeon("goblin_caves")
	var floors: int = int(dd.floors)
	var tier: int = int(dd.tier)
	# `extra` per floor is 1 + tier/3 + randi()%2 -> mean 1.5 + tier/3
	var per_floor: float = 1.0 + float(tier / 3) + 0.5
	var rolls: float = per_floor * float(floors)
	var expected: float = rolls * float(eq_pct) / 100.0
	var p_zero: float = pow(1.0 - float(eq_pct) / 100.0, rolls)
	print("      tier-%d, %d floors: ~%.1f scattered items -> ~%.1f equipment, P(none)=%.0f%%"
		% [tier, floors, rolls, expected, p_zero * 100.0])
	ck(expected >= 1.5, "an average run yields at least ~1.5 pieces from the scatter alone")

	print("\n--- and the zero case is removed outright ---")
	var src := FileAccess.get_file_as_string(SERVER)
	ck(src.contains("(d2) Guarantee ONE piece of equipment somewhere in the dungeon"),
		"one piece is guaranteed per dungeon, so P(none) is 0 regardless of the roll")
	ck(src.contains("var _geq_floor: int = randi() % floor_count"),
		"...on a RANDOM floor, so it is not a grab-and-leave on floor 1")

	print("\n--- the Scroll of Summoning is on the floor table ---")
	ck(src.contains('{"item_type": "scroll_monster_select", "rarity": "rare"}'),
		"a Scroll of Summoning can drop as dungeon floor loot")
	var con_hi: int = int(b.get("consumable", 0))
	print("      summoning band: %d..100 = %d%%" % [con_hi, 100 - con_hi])
	ck(100 - con_hi >= 2 and 100 - con_hi <= 6, "it is RARE (2-6%%), not a staple")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
