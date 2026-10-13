extends SceneTree
## Owner sheet 2026-10-13, items 32 and 44: "Hybrid Catalyst item gives unknown effect" and "Can't inspect
## some items like Tome of Fortify: +1 round". Walking EVERY item type in the loot tables found seven
## whose Inspect page said "Unknown effect" or the generic "Tome of knowledge": both catalysts, three Bane
## potions, the material pouch, and every card tome. They are described now; this fails on the next one.
##
## The list of types is not hand-kept: it is read out of drop_tables.gd's own constants, so an item added
## to a loot table tomorrow is checked tomorrow.
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _strip(t: String) -> String:
	var out := ""
	var depth := 0
	for ch in t:
		if ch == "[":
			depth += 1
		elif ch == "]":
			depth = maxi(0, depth - 1)
		elif depth == 0:
			out += ch
	return out

func _collect(v, found: Dictionary) -> void:
	if v is Dictionary:
		if v.has("item_type") and v["item_type"] is String:
			found[String(v["item_type"])] = String(v.get("rarity", "common"))
		for k in v.keys():
			_collect(v[k], found)
	elif v is Array:
		for e in v:
			_collect(e, found)

func _init() -> void:
	seed(20261013)
	var c = load("res://client/client.gd").new()
	c.set("character_data", {"class": "Fighter", "level": 60, "equipped": {}, "inventory": []})
	var out := RichTextLabel.new()
	out.bbcode_enabled = true
	c.set("game_output", out)
	var dt = load("res://shared/drop_tables.gd").new()
	var found := {}
	var cm: Dictionary = dt.get_script().get_script_constant_map()
	for k in cm.keys():
		_collect(cm[k], found)
	ck(found.size() > 80, "found %d item types in the loot tables' own data" % found.size())

	var bad: Array = []
	var generated := 0
	for t in found.keys():
		var it: Dictionary = dt._generate_item({"item_type": t, "rarity": found[t]}, 50)
		if it.is_empty():
			continue
		generated += 1
		out.clear()
		c.display_item_details(it, "inventory")
		var txt := _strip(out.get_parsed_text())
		if txt.find("Unknown effect") >= 0 or txt.find("permanent enhancement") >= 0:
			bad.append(t)
	ck(generated > 80, "generated and inspected %d of them" % generated)
	ck(bad.is_empty(), "none says 'Unknown effect' or the generic tome line (offenders: %s)" % str(bad))

	print("\n--- the ones that used to say nothing now say the true thing ---")
	var checks := {
		"hybrid_catalyst": "DIFFERENT monster types",
		"ascension_catalyst": "a tier higher",
		"potion_dragon_bane": "+50% damage against Dragon monsters",
		"essence_pouch": "ore",
	}
	for t in checks:
		var it: Dictionary = dt._generate_item({"item_type": t, "rarity": found.get(t, "common")}, 50)
		out.clear()
		c.display_item_details(it, "inventory")
		var txt := _strip(out.get_parsed_text())
		ck(txt.find(String(checks[t])) >= 0, "%s says '%s'" % [t, checks[t]])
	var CG = load("res://shared/card_gear.gd")
	var tome: Dictionary = CG.tome_for("fortify", "duration")
	out.clear()
	c.display_item_details(tome, "inventory")
	var tt := _strip(out.get_parsed_text())
	ck(tt.find("PERMANENT") >= 0 and tt.find("+1 round") >= 0 and tt.find("Fortify") >= 0 and tt.find("every copy") >= 0,
		"Tome of Fortify: +1 round says what it does, to which card, and that it covers every copy")

	print("\n[EVERYITEM] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
