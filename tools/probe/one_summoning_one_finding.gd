extends SceneTree
## Owner sheet 2026-10-13, item 45: several "different" Scrolls of Summoning/Finding that did the same thing.
## Loot named them Summoning/Finding (with Ancient/Arcane prefixes that changed nothing); scribing made
## "Scroll of Monster Select"/"Target Farm" with the same effects. One name each, at every rarity.
const DTS := preload("res://shared/drop_tables.gd")
var DT = DTS.new()
const CDB := preload("res://shared/crafting_database.gd")
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _init() -> void:
	for pair in [["scroll_monster_select", "Scroll of Summoning"], ["scroll_target_farm", "Scroll of Finding"]]:
		var names := {}
		for r in ["common", "uncommon", "rare", "epic", "legendary"]:
			names[DT._get_item_name(pair[0], r)] = true
		ck(names.size() == 1 and names.has(pair[1]), "%s is '%s' at every rarity (%s)" % [pair[0], pair[1], ", ".join(names.keys())])
	ck(String(CDB.RECIPES["scroll_of_monster_select"]["name"]) == "Scroll of Summoning", "the scribed Summoning scroll has the same name")
	ck(String(CDB.RECIPES["scroll_of_target_farm"]["name"]) == "Scroll of Finding", "the scribed Finding scroll has the same name")
	ck(DT._get_item_name("scroll_rage", "epic") == "Ancient Scroll of Rage", "scrolls whose power DOES scale keep their rarity prefix")
	print("\n[ONESCROLL] %s" % ("PASS" if fails == 0 else "FAIL - %d" % fails))
	quit(0 if fails == 0 else 1)
