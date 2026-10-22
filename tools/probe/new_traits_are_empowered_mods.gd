extends SceneTree
## Item 11b (owner 2026-10-22): the new monster TRAITS join the existing Empowered modifier list rather than becoming a second system. This proves each new trait exists in BOTH tables that must agree
## (the generation table and the combat-start / hover wording), does what it says to the monster it is stamped on, and that the roll rate is the owner's "about 1 in 3".
const MD = preload("res://shared/monster_database.gd")
const CM = preload("res://shared/combat_manager.gd")
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _init() -> void:
	var db := MD.new()
	root.add_child(db)
	var new_ids := ["thickhided", "stalwart", "giant", "ponderous", "skittish", "regenerating"]
	print("--- the two tables agree ---")
	var missing_disp: Array = []
	for id in MD.EMPOWERED_MODIFIERS:
		if not CM.EMPOWERED_MOD_DISPLAY.has(id):
			missing_disp.append(id)
	ck(missing_disp.is_empty(), "every modifier in the generation table has wording and a colour in the combat table (missing: %s)" % str(missing_disp))
	for id in new_ids:
		ck(MD.EMPOWERED_MODIFIERS.has(id) and String(MD.EMPOWERED_MODIFIERS[id]["prefix"]) != "", "%s is a modifier (prefix '%s')" % [id, String(MD.EMPOWERED_MODIFIERS.get(id, {}).get("prefix", ""))])
	print("--- what each does to the monster ---")
	var plain: Dictionary = db.generate_monster_by_name("Wolf", 40, true)
	var h0: int = int(plain["max_hp"])
	var s0: int = int(plain["strength"])
	var d0: int = int(plain["defense"])
	var stamped := {}
	for id in new_ids:
		var m: Dictionary = plain.duplicate(true)
		db.reapply_empowered(m, [id])
		stamped[id] = m
	ck(int(stamped["thickhided"]["max_hp"]) > h0 and int(stamped["thickhided"]["defense"]) >= d0, "Thick-hided has more HP (%d -> %d) and no less defence" % [h0, int(stamped["thickhided"]["max_hp"])])
	ck(int(stamped["stalwart"]["defense"]) > d0, "Stalwart has more defence (%d -> %d)" % [d0, int(stamped["stalwart"]["defense"])])
	ck(int(stamped["giant"]["max_hp"]) > h0 and int(stamped["giant"]["strength"]) > s0, "Giant has more HP and hits harder (%d/%d -> %d/%d)" % [h0, s0, int(stamped["giant"]["max_hp"]), int(stamped["giant"]["strength"])])
	ck(int(stamped["ponderous"]["strength"]) > s0, "Ponderous hits harder (%d -> %d)" % [s0, int(stamped["ponderous"]["strength"])])
	ck("coward" in stamped["skittish"]["abilities"], "Skittish carries the existing coward ability (it flees at low health, so the kill must be finished)")
	ck("regeneration" in stamped["regenerating"]["abilities"], "Regenerating carries the existing regeneration ability")
	for id in new_ids:
		ck(String(stamped[id]["name"]).begins_with(String(MD.EMPOWERED_MODIFIERS[id]["prefix"])), "%s shows in the monster's name ('%s')" % [id, String(stamped[id]["name"])])
	print("--- the rate ---")
	var emp := 0
	var total := 400
	seed(2026)
	for i in range(total):
		var mm: Dictionary = db.generate_monster(30, 30)
		if bool(mm.get("is_empowered", false)):
			emp += 1
	var rate: float = float(emp) / float(total)
	ck(rate > 0.25 and rate < 0.42, "about 1 in 3 monsters of level 30 carry a modifier (%d of %d = %.0f%%)" % [emp, total, rate * 100.0])
	var seen := {}
	for i in range(1500):
		var m2: Dictionary = db.generate_monster(40, 40)
		for mod in m2.get("empowered_mods", []):
			seen[String(mod)] = true
	var unseen: Array = []
	for id in new_ids:
		if not seen.has(id):
			unseen.append(id)
	ck(unseen.is_empty(), "every new trait actually appears in 1500 generated monsters (never seen: %s)" % str(unseen))
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
