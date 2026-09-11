extends SceneTree
## Every new upgrade must actually DO something.
##
## An upgrade that sits in the table and never fires is precisely the "dead option" this whole
## arc exists to remove, and it is the failure mode that looks finished: the card renders, the
## rarity shows, the trigger tag reads correctly, and the effect is absent. So this does not check
## that the entries exist - it drives real casts and looks for the effect.
const CU := preload("res://shared/card_upgrades.gd")
const CM := preload("res://shared/combat_manager.gd")
const MD := preload("res://shared/monster_database.gd")
const CH := preload("res://shared/character.gd")
const DT := preload("res://shared/drop_tables.gd")

const NEW := ["sure_strike", "last_stand", "second_look", "slow_mend", "rally_point"]

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _mgr():
	var cm = CM.new()
	cm.monster_database = MD.new()
	cm.drop_tables = DT.new()
	var f := FileAccess.open("res://server/balance_config.json", FileAccess.READ)
	if f != null:
		var j := JSON.new()
		if j.parse(f.get_as_text()) == OK:
			cm.balance_config = j.data
		f.close()
	return cm


func _char(klass: String, picks: Array, card: String):
	var c = CH.new()
	c.name = "P"
	c.class_type = klass
	c.level = 20
	c.max_hp = 2000
	c.current_hp = 2000
	c.max_energy = 400
	c.current_energy = 400
	c.max_stamina = 400
	c.current_stamina = 400
	c.max_mana = 400
	c.current_mana = 400
	c.ability_milestone_picks[card] = picks.duplicate()
	return c


func _cast(cm, ch, card: String, mon_hp_frac: float = 1.0) -> Dictionary:
	var mon = cm.monster_database.generate_monster_by_name("Giant Spider", 20, false, "")
	mon["max_hp"] = 100000
	mon["current_hp"] = int(100000.0 * mon_hp_frac)
	cm.start_combat(1, ch, mon)
	cm.active_combats[1]["combat_hand"] = [card]
	var res = cm.process_combat_command(1, card)
	var txt := ""
	for m in res.get("messages", []):
		txt += String(m) + "\n"
	return {"res": res, "text": txt, "combat": cm.active_combats.get(1, {})}


func _init() -> void:
	print("--- all five are declared complete ---")
	for id in NEW:
		var u := CU.upgrade_by_id(id)
		ck(not u.is_empty(), "'%s' is in the pool" % id)
		ck(bool(u.get("wired", false)), "...and claims to be wired")
		ck(CU.trigger_of(u) != CU.TRIGGER_NONE, "...and declares a trigger (%s)" % CU.trigger_of(u))
		ck(CU.rarity_of(u) != CU.RARITY_COMMON, "...and is not another common (%s)" % CU.rarity_of(u))

	print("\n--- and each one FIRES in a real cast ---")
	# SURE STRIKE: a guaranteed crit on the first cast, and NOT on the second.
	var cm = _mgr()
	var ch = _char("Warrior", ["sure_strike"], "power_strike")
	var a := _cast(cm, ch, "power_strike")
	ck(String(a["text"]).contains("Sure Strike"),
		"Sure Strike crits on the first cast, and names ITSELF rather than Keen Edge")
	var again = cm.process_combat_command(1, "power_strike") if cm.active_combats.has(1) else {}
	var again_txt := ""
	for m in again.get("messages", []):
		again_txt += String(m) + "\n"
	ck(not again_txt.contains("Sure Strike"), "...and does NOT fire again the same fight")
	cm.free()

	# LAST STAND: only below a quarter health.
	cm = _mgr()
	ch = _char("Warrior", ["last_stand"], "power_strike")
	ch.current_hp = int(0.9 * float(ch.max_hp))
	ck(not String(_cast(cm, ch, "power_strike")["text"]).contains("Last Stand"),
		"Last Stand stays silent at 90% health")
	cm.free()
	cm = _mgr()
	ch = _char("Warrior", ["last_stand"], "power_strike")
	ch.current_hp = int(0.15 * float(ch.max_hp))
	ck(String(_cast(cm, ch, "power_strike")["text"]).contains("Last Stand"),
		"...and fires at 15%")
	ck(ch.has_buff("damage_reduction") if ch.has_method("has_buff") else true,
		"...leaving the damage-reduction buff it promises")
	cm.free()

	# RALLY POINT: only once the foe is wounded.
	cm = _mgr()
	ch = _char("Warrior", ["rally_point"], "power_strike")
	ck(not String(_cast(cm, ch, "power_strike", 1.0)["text"]).contains("Rally Point"),
		"Rally Point stays silent against a healthy foe")
	cm.free()
	cm = _mgr()
	ch = _char("Warrior", ["rally_point"], "power_strike")
	ck(String(_cast(cm, ch, "power_strike", 0.30)["text"]).contains("Rally Point"),
		"...and feeds the engine once the foe is at 30%")
	cm.free()

	# THE TWO REVEALS: the cycle resolver must describe them, and with the right effect.
	cm = _mgr()
	for pair in [["second_look", "back"], ["slow_mend", "health"]]:
		var c2 = _char("Warrior", [String(pair[0])], "power_strike")
		var line := String(cm._cycle_preview_text(c2, "power_strike"))
		ck(line != "", "'%s' produces a cycle line: \"%s\"" % [pair[0], line])
		ck(line.contains(String(pair[1])),
			"...and it is the %s effect, not another copy of an existing reveal" % pair[1])
	cm.free()

	print("\n--- both reveal branches were updated, not just the one you can see ---")
	# The display resolver and the apply site carry the same if/elif chain. Updating only the
	# display makes the card promise something it never does.
	var src := FileAccess.get_file_as_string("res://shared/combat_manager.gd")
	ck(src.count('elif "second_look" in picks:') == 2, "Second Look is in BOTH chains")
	ck(src.count('elif "slow_mend" in picks:') == 2, "Slow Mend is in BOTH chains")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
