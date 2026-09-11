extends SceneTree
## Every attribute gear can roll must reach the inline comparison bracket.
##
## Owner 2026-09-11: *"equipment comparisons may be missing some stats like Dex"*. They were, and
## it was wider than DEX. Of the six attributes an item can carry, STRENGTH folded into ATK and
## CONSTITUTION into DEF/HP, WITS had its own line — and DEXTERITY, INTELLIGENCE and WISDOM were
## read ONLY to size the resource pool, so a ring with +6 DEX and no max_energy showed NOTHING.
##
## The detail view (`_display_computed_item_bonuses`) was already correct; only the bracket was
## short. That distinction matters: the bug was invisible to anyone reading the detail screen.
const CLIENT := "res://client/client.gd"

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _strip(s: String) -> String:
	var re := RegEx.new()
	re.compile("[[][/]?[a-zA-Z=#0-9_]+[]]")
	return re.sub(s, "", true)


func _parts(c, affixes: Dictionary) -> String:
	var item := {"affixes": affixes, "level": 10, "rarity": "common", "type": "weapon"}
	var out: Array = []
	for p in c._get_item_comparison_parts(item, null):
		out.append(_strip(String(p)))
	return " ".join(out)


func _init() -> void:
	var c = load(CLIENT).new()
	c.set("character_data", {})
	c.set("house_bonuses_data", {})

	print("--- every attribute an item can roll reaches the bracket ---")
	# The affix keys are the ones _compute_item_bonuses actually reads.
	var cases := [
		["dex_bonus", "DEX"], ["int_bonus", "INT"], ["wis_bonus", "WIS"],
		["wits_bonus", "WIT"],
	]
	for case in cases:
		var shown: String = _parts(c, {String(case[0]): 6})
		ck(shown.contains(String(case[1])),
			"+6 %s shows '%s'  ->  %s" % [case[0], case[1], shown])

	# STR and CON are deliberately FOLDED, not raw — assert that too, so a later edit that
	# "helpfully" adds raw STR is caught as a change of contract rather than passing silently.
	var s_shown: String = _parts(c, {"str_bonus": 5})
	ck(s_shown.contains("ATK") and not s_shown.contains("STR"),
		"STR still folds into ATK rather than showing raw  ->  %s" % s_shown)
	var con_shown: String = _parts(c, {"con_bonus": 6})
	ck(con_shown.contains("DEF") or con_shown.contains("HP"),
		"CON still folds into DEF/HP  ->  %s" % con_shown)

	print("\n--- an item with several attributes shows them all ---")
	var mixed: String = _parts(c, {"dex_bonus": 3, "int_bonus": 2, "wis_bonus": 1})
	print("      %s" % mixed)
	for tag in ["DEX", "INT", "WIS"]:
		ck(mixed.contains(tag), "'%s' survives alongside the others" % tag)

	print("\n--- and nothing is invented when there is no difference ---")
	var none: String = _parts(c, {})
	ck(not none.contains("DEX") and not none.contains("INT") and not none.contains("WIS"),
		"an item with no attributes shows no attribute lines  ->  '%s'" % none)
	c.free()

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
