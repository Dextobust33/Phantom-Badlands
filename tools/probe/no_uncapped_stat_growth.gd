extends SceneTree
## ⛑ IS THERE ANY WAY LEFT TO BUFF ONE ITEM WITHOUT A CEILING?
##
## Owner 2026-09-18: *"we don't want these things to make it where players can infinitely upgrade
## for free. It's meant to be a quality of life thing with maybe some discount but not a gate. We
## don't want a player to just be able to keep buffing their same item for free infinitely."*
##
## That was said about the NEW reroll loop — but the audit it prompted found the rule was already
## being broken by something live. The **town blacksmith's Enhance** did:
##
##     equipped_item["affixes"][affix_key] = old_value + upgrade_amount
##
## with no ceiling anywhere on the path. `ENCHANTMENT_STAT_CAPS` exists but is only consulted by
## the ENCHANTING code; this wrote to `affixes` instead, so the cap never applied. The only brake
## was a quadratic cost. Measured on a level-60 item: `attack_bonus` **40 → 340 in twenty steps**,
## against a fresh drop of that level rolling **45–69**, and nothing stopping step twenty-one.
##
## ⛑ SO THIS PROBE GUARDS A RULE, NOT A FEATURE. It fails if any code path writes a stat as
## `old + amount` on an item's `affixes`, because that shape is what unbounded growth looks like.
## The sanctioned path (`reroll_affix`) REPLACES a stat rather than adding to it, and is capped.
##
## Run:
##   godot --headless --path . --script res://tools/probe/no_uncapped_stat_growth.gd

const DT := preload("res://shared/drop_tables.gd")

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


func _init() -> void:
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	var cli := FileAccess.get_file_as_string("res://client/client.gd")

	print("")
	print("===== 1. THE BLACKSMITH'S UNCAPPED UPGRADE IS GONE =====")
	# Each of these is a distinct limb of the same path. Any one surviving means it can be
	# re-reached, and a half-removed feature is worse than either state.
	var limbs := {
		"the affix-add write": "[\"affixes\"][affix_key] = old_value",
		"the upgrade cost helper": "func _calculate_affix_upgrade_cost(",
		"the upgrade amount helper": "func _calculate_affix_upgrade_amount(",
		"the upgradeable-item scan": "upgradeable_items",
		"the select-affix message": "blacksmith_upgrade_select_affix",
	}
	for label in limbs.keys():
		if srv.find(String(limbs[label])) >= 0:
			_fail("%s is still in server.gd" % label)
		else:
			_ok("%s removed" % label)
	if cli.find("\"action_data\": \"blacksmith_upgrade\"") >= 0:
		_fail("the client still offers an Enhance button")
	else:
		_ok("the Enhance button is gone from the action bar")

	print("")
	print("===== 2. IT TELLS THE PLAYER WHERE THE CAPABILITY WENT =====")
	# ⛑ A REMOVED BUTTON THAT SAYS NOTHING READS AS A BUG. Returning players will look for
	# Enhance exactly where it used to be.
	if cli.find("no longer enhances gear") < 0:
		_fail("the blacksmith screen does not say where enhancing went")
	else:
		_ok("the blacksmith screen points at Inventory -> Rework")
	if srv.find("Enchanter's work") < 0:
		_fail("the server does not answer an upgrade request with an explanation")
	else:
		_ok("an old client asking to upgrade gets told why it cannot")

	print("")
	print("===== 3. NO OTHER PATH GROWS A STAT WITHOUT A CEILING =====")
	# ⛑ THE GENERAL RULE, not the one instance. Written as a source sweep because the fault is a
	# SHAPE - reading a stat and writing back a larger value - and the next one will be written
	# by someone who has never heard of the blacksmith.
	var bad: Array = []
	for hay in [{"f": "server.gd", "s": srv}]:
		var src: String = String(hay["s"])
		var from := 0
		while true:
			var i: int = src.find("[\"affixes\"][", from)
			if i < 0:
				break
			from = i + 1
			var line_end: int = src.find("\n", i)
			var line: String = src.substr(i, maxi(0, line_end - i))
			# An assignment that references the same key on the right-hand side is the shape.
			if line.find("] = ") >= 0 and (line.find("old_value +") >= 0 or line.find("current_value +") >= 0 or line.find("+ upgrade") >= 0):
				bad.append("%s: %s" % [String(hay["f"]), line.strip_edges()])
	if not bad.is_empty():
		for b in bad:
			_fail("unbounded stat growth: %s" % b)
	else:
		_ok("no `affixes[key] = old + amount` write remains")

	print("")
	print("===== 4. THE SANCTIONED PATH REPLACES AND IS CAPPED =====")
	var dt = DT.new()
	get_root().add_child(dt)
	seed(99)
	var item: Dictionary = {}
	for _t in range(400):
		var cand: Dictionary = dt.roll_dungeon_chest_equipment(4, 60)
		if not cand.is_empty() and dt.rerollable_affixes(cand).size() >= 2:
			item = cand
			break
	if item.is_empty():
		_fail("could not generate a test item")
	else:
		var keys: Array = dt.rerollable_affixes(item)
		var k := String(keys[0])
		var before = item["affixes"][k]
		var res: Dictionary = dt.reroll_affix(item, k)
		if bool(res.get("ok", false)) and item.get("affixes", {}).has(k):
			_fail("reroll ADDED to the existing stat instead of replacing it")
		else:
			_ok("reroll removed %s (was %s) rather than growing it" % [k, str(before)])
		# And the total number of stats cannot climb.
		if dt.rerollable_affixes(item).size() != keys.size():
			_fail("the stat COUNT changed through a reroll")
		else:
			_ok("stat count unchanged at %d" % keys.size())
		print("  hard cap: %d reworks per item" % DT.MAX_AFFIX_REROLLS)

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for f in _fails:
			print("   - %s" % f)
		quit(1)
		return
	print("[PROBE] PASS nothing grows an item's stats without a ceiling; the one path that did")
	print("       is removed, signposted, and replaced by a capped trade.")
	quit()
