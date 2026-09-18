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
const CD := preload("res://shared/crafting_database.gd")
const CharacterScript := preload("res://shared/character.gd")

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
	print("===== 3b. NOR DOES ANY ROLL COMPOUND OFF THE CURRENT VALUE =====")
	# ⛑ THE ADDITIVE SWEEP ABOVE MISSED A SECOND ONE, AND THAT IS THE LESSON. `_craft_reforge`
	# wrote `target_item[stat_key]`, not `target_item["affixes"][key]`, and it MULTIPLIED rather
	# than added - so it slipped past a check written around the blacksmith's exact shape.
	#
	# Measured before the fix, median of 400 runs starting at attack 100:
	#   STANDARD    100 -> 42 after 100 reforges   (a multiplicative walk's median sits below
	#                                               its mean, so "reroll +/-10%" quietly ate the
	#                                               stat - a trap, not a wash)
	#   MASTERWORK  100 -> 769 after 100 reforges  (expected 1.025x per reforge, exponential)
	#
	# The cause in one word: the roll read the CURRENT value as its basis. It now reads a stored
	# original, so the band is fixed and repeating it drifts nowhere.
	# ⛑ DRIVEN WITH A REAL ITEM, REPEATEDLY. Two earlier versions of this check asserted nothing:
	# one looked for the name `reforge_base` and an absent literal (an injection setting
	# `base_val = old_val` passed it clean), and one looped while passing a CONSTANT base, so the
	# loop was decoration. "Does this compound?" is a question about what happens to an item over
	# many reforges, so the probe reforges an item many times and looks at the item.
	for qname in ["STANDARD", "FINE", "MASTERWORK"]:
		var qm: float = {"STANDARD": 1.0, "FINE": 1.25, "MASTERWORK": 1.5}[qname]
		var finals: Array = []
		for _run in range(300):
			var it: Dictionary = {"attack": 100}
			for _step in range(100):
				CD.reforge_stat(it, "attack", qm, randf())
			finals.append(int(it["attack"]))
		finals.sort()
		var med: int = int(finals[finals.size() / 2])
		var hi_seen: int = int(finals[finals.size() - 1])
		# Band is [0.90 x 100, (1 + 0.10 x qm) x 100]. Anything outside it after a hundred
		# reforges means the value drifted, in whichever direction.
		var band_hi: int = int(100.0 * (1.0 + 0.10 * qm))
		if med < 88 or med > band_hi + 3:
			_fail("%s drifted to a median of %d after 100 reforges (band 90-%d)" % [qname, med, band_hi])
		elif hi_seen > band_hi + 3:
			_fail("%s reached %d, above its band ceiling of %d" % [qname, hi_seen, band_hi])
		else:
			_ok("%-10s median %d, max %d after 100 reforges (band 90-%d)" % [qname, med, hi_seen, band_hi])
	# ⛑ AND THE DANGER IS DEMONSTRATED, not just the fix. Feeding the roll its own output is what
	# the shipped code did; printing where that lands is what makes the numbers above mean
	# something rather than look like an arbitrary band.
	var compounded: Array = []
	for _run in range(300):
		var v: int = 100
		for _step in range(100):
			var tmp: Dictionary = {"attack": v}
			CD.reforge_stat(tmp, "attack", 1.5, randf())
			v = int(tmp["attack"])
		compounded.append(v)
	compounded.sort()
	print("  (for contrast: re-pinning the base every reforge - what the shipped code did -")
	print("   lands at a median of %d after 100 at Masterwork)" % int(compounded[compounded.size() / 2]))
	if int(compounded[compounded.size() / 2]) < 200:
		_fail("the contrast case did not compound - this check is not measuring what it claims")

	print("")
	print("===== 3c. THE WISH UPGRADE GOES THROUGH THE DAMPED ROUTE ONLY =====")
	# ⛑ THE THIRD ONE THE SWEEP FOUND, and the one that shows why the sweep had to keep going.
	# `_upgrade_single_item` bumped `level` (correct - `_get_effective_item_level` is logarithmic
	# above 50, so L1000 counts as 148) AND wrote raw stat fields at +8% compounding with no
	# damping at all. Measured on crafted armour at 50 defense, 9 upgrades a wish:
	#   1 wish -> 95    3 -> 358    5 -> 1410    10 -> 44799
	# from a `wish_granter` monster at 10% per kill, so repeatable.
	#
	# Worse, the weapon branch wrote `damage`, which NO aggregator reads - so the headline of an
	# "Equipment Upgrade (x15)" wish did nothing whatsoever. Dead for most items, uncapped for the
	# rest, from the same six lines.
	var wish_src_ok := true
	for shape in ["item[\"damage\"] = current_dmg", "item[\"defense\"] = current_def", "item[\"speed\"] = current_speed"]:
		if srv.find(shape) >= 0:
			_fail("the wish upgrade still writes a raw stat: %s" % shape)
			wish_src_ok = false
	if wish_src_ok:
		_ok("the wish upgrade writes level only - no undamped stat writes")
	# And the damping it now relies on must still be logarithmic, or removing the raw writes
	# would have handed the job to something linear.
	var l100: float = CharacterScript._get_effective_item_level(100)
	var l1000: float = CharacterScript._get_effective_item_level(1000)
	if l1000 >= l100 * 2.0:
		_fail("_get_effective_item_level is no longer damping (L100=%.0f, L1000=%.0f)" % [l100, l1000])
	else:
		_ok("item level stays damped: L100 counts as %.0f, L1000 as %.0f" % [l100, l1000])
	# ⛑ AND THE COMMENT MUST MATCH THE FUNCTION. This printed line is how the 50-point error in
	# `_get_effective_item_level`'s docstring was found on 2026-09-18 - it had said L100 = 85 and
	# L1000 = 148 (it computed `15 * log2(51)` and dropped the `50 +`), and that figure had
	# already been copied into drop_tables.gd and quoted as a design target. Asserting it here
	# means the next edit to either cannot silently disagree.
	var char_src := FileAccess.get_file_as_string("res://shared/character.gd")
	if char_src.find("L100 = %d" % int(l100)) < 0:
		_fail("_get_effective_item_level's docstring does not state its real L100 (%.0f)" % l100)
	else:
		_ok("the docstring's worked examples match what the function returns")

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
