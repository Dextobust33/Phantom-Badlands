extends SceneTree
## ⛑ THE COMBAT ITEM LIST SAYS WHAT AN ITEM GIVES *YOU*, AS A NUMBER.
##
## Owner 2026-09-18: *"the item info in combat needs improved so players can see what they do at a
## glance. Also shouldn't require them trying to do math, should just tell how much it will give
## them back."*
##
## Both halves were real. The picker renders NAMES, so choosing under pressure meant hovering each
## row — and 19 of the 35 craftable consumables cannot be told apart by name at all. Worse, the
## hover itself said *"restores 25% of max HP"*, so even reading it left the player multiplying by
## their own maximum mid-fight.
##
## ⛑ THE NUMBER COMES FROM THE SERVER'S OWN FUNCTION. `consumable_heal_amount` is static and is the
## same call `handle_use_item` makes, so what is shown is what is granted. Re-deriving the formula
## client-side is exactly how this codebase has produced confidently wrong numbers before — the
## potion is authored with a FLAT part and a PERCENTAGE part together, which a re-derivation would
## almost certainly get wrong in one direction or the other.
##
## Run:
##   godot --headless --path . --script res://tools/probe/combat_item_gain.gd

const DT := preload("res://shared/drop_tables.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	print("===== THE AMOUNT IS REAL, AND IT SCALES WITH THE PLAYER =====")
	# A tier-4 healing potion: flat 100 PLUS 25% of max HP (CONSUMABLE_TIERS[4]).
	var item := {"name": "Greater Health Potion", "tier": 4, "level": 20}
	var effect := {"heal": true}
	var small: int = DT.consumable_heal_amount(item, effect, 200, 4)
	var large: int = DT.consumable_heal_amount(item, effect, 2000, 4)
	print("  same potion: %d HP on a 200 HP character, %d HP on a 2000 HP one" % [small, large])
	ck(small > 0 and large > 0, "it restores something in both cases")
	ck(large > small, "and MORE for the bigger pool - the percentage half is real")
	# This is the arithmetic the player was being asked to do: 100 flat + 25% of max.
	ck(large >= 500, "a 2000 HP character gets a meaningful number (%d), not a percentage" % large)

	print("\n===== THE ROW CARRIES IT =====")
	var cli := FileAccess.get_file_as_string("res://client/client.gd")
	var pan := FileAccess.get_file_as_string("res://client/combat_scene_panel.gd")
	ck(cli.find('"gain": _combat_item_gain_line(item),') >= 0, "the picker payload carries a `gain`")
	ck(cli.find("DropTables.consumable_heal_amount(item, effect, pool, tier)") >= 0,
		"...computed by the SERVER'S function, not re-derived")
	ck(cli.find("DropTables.consumable_resource_amount(item, effect, rpool, tier)") >= 0,
		"...and the same for resource restores")
	ck(pan.find('var gain := str(entry.get("gain", ""))') >= 0, "the picker reads it")
	ck(pan.find('btn.text = "[%d]  %s%s%s" % [slot, name, qty_text, gain_text]') >= 0,
		"...and puts it on the ROW, where a player choosing under pressure will see it")

	print("\n===== A COMPANION POTION SAYS SO =====")
	# ⛑ Reading "+340 HP" on a companion revive mid-fight would be actively misleading.
	ck(cli.find('"+%d HP to your companion" % amt if target_is_companion else "+%d HP" % amt') >= 0,
		"a companion-targeted heal names its target rather than reading as a self-heal")

	print("")
	if fails == 0:
		print("[PROBE] PASS the item list does the arithmetic for you")
	else:
		print("[PROBE] FAIL %d check(s)" % fails)
	quit(1 if fails > 0 else 0)
