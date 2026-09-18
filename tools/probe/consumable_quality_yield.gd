extends SceneTree
## ⛑ A GOOD CRAFT GIVES YOU MORE POTIONS, NOT A SLIGHTLY STRONGER ONE.
##
## Owner 2026-09-18: *"crafting quality for consumables would come in the form of making the next
## item in the tier from a great craft or getting bonus items (example: you made an extremely
## potent healing potion, you dilute it into 2)."* And on the old scheme: *"a lot of items that
## could get quality that didn't benefit enough to justify even having it."*
##
## Measured, the old scheme was invisible: Standard 1.00 to Masterwork 1.50 is the whole spread a
## player can influence, and Fine to Masterwork is +20% — ten HP on a fifty HP potion.
##
## ⛑ AND QUALITY MUST OWN EXACTLY ONE LEVER. Leaving the potency multiplier in place while the
## caller multiplied the COUNT would compound: a Masterwork craft would give three potions each 50%
## stronger, which is 4.5x a Standard craft rather than 3x. That is the kind of silent stacking
## that reads as "crafting is overpowered" months later with no obvious cause.
##
## Run:
##   godot --headless --path . --script res://tools/probe/consumable_quality_yield.gd

const CD := preload("res://shared/crafting_database.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	print("===== QUALITY BUYS COUNT =====")
	var y := CD.QUALITY_YIELD
	print("  poor %d | standard %d | fine %d | masterwork %d" % [
		int(y[CD.CraftingQuality.POOR]), int(y[CD.CraftingQuality.STANDARD]),
		int(y[CD.CraftingQuality.FINE]), int(y[CD.CraftingQuality.MASTERWORK])])
	ck(int(y[CD.CraftingQuality.FINE]) == 2, "a Fine craft yields 2 - the owner's 'dilute it into 2'")
	ck(int(y[CD.CraftingQuality.MASTERWORK]) > int(y[CD.CraftingQuality.FINE]),
		"a Masterwork yields more still")
	ck(int(y[CD.CraftingQuality.STANDARD]) == 1 and int(y[CD.CraftingQuality.POOR]) == 1,
		"...and an ordinary craft still gives you the potion you asked for")
	ck(int(y[CD.CraftingQuality.FAILED]) == 0, "a failure gives nothing")

	print("\n===== AND NOT POTENCY AS WELL =====")
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	# The two lines that used to scale the effect by quality must be gone from the consumable path.
	ck(srv.find('scaled_effect["amount"] = int(scaled_effect["amount"] * multiplier)') < 0,
		"the flat-amount potency multiplier is gone")
	ck(srv.find('scaled_effect["bonus_pct"] = int(scaled_effect["bonus_pct"] * multiplier)') < 0,
		"...and the percentage one, so quality cannot compound with count")
	ck(srv.find("CraftingDatabaseScript.QUALITY_YIELD.get(quality, 1)") >= 0,
		"the consumable branch reads the yield table")

	print("\n===== IDENTICAL POTIONS STACK =====")
	# ⛑ A knock-on that matters as much as the mechanic: the crafted name carried the quality
	# word, so one recipe crafted five times made FIVE piles. Owner, on inventory: "Items and
	# tools can buildup and takeover your backpack slots."
	ck(srv.find('"name": recipe.name,') >= 0,
		"a crafted consumable is named for its recipe, with no quality prefix")
	# The enhancement scroll KEEPS its prefix, because quality still scales a scroll.
	ck(srv.find('"name": "%s %s" % [quality_name, recipe.name]') >= 0,
		"...while the enhancement scroll keeps its prefix, where quality still means something")

	print("")
	if fails == 0:
		print("[PROBE] PASS quality gives you more, and only more")
	else:
		print("[PROBE] FAIL %d check(s)" % fails)
	quit(1 if fails > 0 else 0)
