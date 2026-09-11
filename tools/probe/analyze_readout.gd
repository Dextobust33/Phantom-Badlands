extends SceneTree
## Analyze must report what it already knows.
##
## Owner 2026-09-06: *"Analyze needs an adjustment to show something fresh rather than the same
## crap."* It was showing FOUR facts out of the thirty a monster carries, the same four every
## cast — so it did not need new information invented, it was withholding most of what it had.
## Defence was simply absent, as were the two facts that change how you play the fight: whether
## MORE arrive, and whether this one is worth killing.
const CM := preload("res://shared/combat_manager.gd")
const MD := preload("res://shared/monster_database.gd")
const CH := preload("res://shared/character.gd")
const DT := preload("res://shared/drop_tables.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _strip(s: String) -> String:
	var re := RegEx.new()
	re.compile("[[][/]?(url|color|b|i)[^]]*[]]")
	return re.sub(s, "", true)


func _readout(klass: String, force: String) -> String:
	var cm = CM.new()
	cm.monster_database = MD.new()
	cm.drop_tables = DT.new()
	var f := FileAccess.open("res://server/balance_config.json", FileAccess.READ)
	if f != null:
		var j := JSON.new()
		if j.parse(f.get_as_text()) == OK:
			cm.balance_config = j.data
		f.close()
	var ch = CH.new()
	ch.name = "P"
	ch.class_type = klass
	ch.level = 12
	ch.max_hp = 999
	ch.current_hp = 999
	ch.max_energy = 999
	ch.current_energy = 999
	var mon = cm.monster_database.generate_monster_by_name("Giant Spider", 12, false, force)
	cm.start_combat(1, ch, mon)
	cm.active_combats[1]["combat_hand"] = ["analyze"]
	cm.active_combats[1]["combo"] = 3
	var res = cm.process_ability_command(1, "analyze", "")
	var out := ""
	for m in res.get("messages", []):
		out += _strip(String(m)) + "\n"
	return out


func _init() -> void:
	var txt := _readout("Ranger", "empowered")
	print(txt.strip_edges())
	print("")

	print("--- the facts that were missing are there now ---")
	for want in ["Defense", "Speed", "Spoils", "Traits"]:
		ck(txt.contains(want), "'%s' is reported" % want)
	# Guile must SAY what it does — a bare "Intelligence: 12" told the player nothing.
	ck(txt.contains("Guile") and txt.contains("resists Distract"),
		"the opaque Intelligence number now says what it gates")
	ck(not txt.contains("Intelligence:"), "...and the bare 'Intelligence:' line is gone")

	print("\n--- and they are READ from the monster, not printed as constants ---")
	# Two different monsters must not produce the same numbers.
	var a := _readout("Ranger", "empowered")
	var b := _readout("Ranger", "elite")
	# Compare the TRAITS line specifically. Comparing whole readouts is not a real check:
	# HP differs between any two rolls, so a readout that printed nothing but HP would
	# pass it. Caught by re-injection: the loose version passed against the OLD Analyze.
	var elite_traits := ""
	for line in b.split("
"):
		if line.contains("Traits"):
			elite_traits = line
	var emp_traits := ""
	for line in a.split("
"):
		if line.contains("Traits"):
			emp_traits = line
	ck(elite_traits != "" and emp_traits != "" and elite_traits != emp_traits,
		"an elite and an empowered monster list DIFFERENT traits, not one canned line")

	print("\n--- it still does its old job ---")
	ck(txt.contains("HP"), "exact HP is still revealed (its real value on a first cast)")
	ck(txt.contains("damage bonus for this combat"), "the +10% buff still applies")
	ck(txt.contains("Killing Shot"), "the class-correct finisher is still named")
	ck(not txt.contains("Assassinate"),
		"a Ranger is not told about Assassinate, which is the Ninja's finisher")

	print("\n--- traits come from the shared table, not a second list ---")
	var src := FileAccess.get_file_as_string("res://shared/combat_manager.gd")
	# Scoped to the analyze branch. A file-wide search for MONSTER_TRAITS passes on the
	# ENCOUNTER line's use of it and proves nothing about Analyze - confirmed by
	# re-injection, where the unscoped check passed against a build printing no traits.
	# Anchored on the READOUT line, not on '"analyze":' - that string first occurs in the
	# card-definition table 2200 lines earlier, which is a window with no traits in it.
	var a0 := src.find('ability_line(character, "analyze", "title"')
	var branch := src.substr(a0, 4000) if a0 >= 0 else ""
	ck(a0 >= 0 and branch.contains("MONSTER_TRAITS"),
		"the analyze branch itself reads MONSTER_TRAITS, not a second hand-written list")
	ck(a0 >= 0 and branch.contains("empowered_mod_hover("),
		"...and resolves empowered prefixes through the shared hover table too")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
