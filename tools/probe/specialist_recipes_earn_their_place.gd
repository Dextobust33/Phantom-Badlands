extends SceneTree
## ⛑ DOES EACH SPECIALIST CONVERSION DO SOMETHING SALVAGE CANNOT, AT A FAIR RATE?
##
## Owner 2026-09-18, challenging three recipes I had called dead: *"Alchemist Transmute sounds about
## useless, is essence still a thing that is widely needed? Is that not easily gained by salvaging.
## disenchant do you get runes back or something, if not isn't it just like salvage that we already
## have?"*
##
## ⛑ AND I WAS WRONG ABOUT TWO OF THE THREE. I had reported all three as dead weight because they
## "compete with salvage". Measuring them separately says otherwise:
##
##   TRANSMUTE   moves surplus UP a tier at a consistent -20%. Salvage cannot do this at all. KEEP.
##   EXTRACT     converts leather/cloth into enchant materials - also something salvage cannot do -
##               but the RATE was broken: -20% to -67% depending on tier, on a material the recipe
##               picks for you. Fixed, not culled.
##   DISENCHANT  really was strictly worse than salvage: 1 ore at Standard against ~50% of an
##               item's full crafting materials, on your lowest-level item. Rebuilt to return the
##               RUNES, which is the owner's own suggestion and the only thing that makes it a
##               different recipe rather than a worse one.
##
## The lesson is the one this codebase keeps relearning: "it overlaps with X" is not a measurement.
##
## Run:
##   godot --headless --path . --script res://tools/probe/specialist_recipes_earn_their_place.gd

const CD := preload("res://shared/crafting_database.gd")

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


func _val(mid: String) -> float:
	return float(CD.MATERIALS.get(mid, {}).get("value", 0))


func _init() -> void:
	print("")
	print("===== 1. TRANSMUTE: moves surplus UP a tier, which salvage cannot =====")
	# ⛑ Judged on RATE, not on whether something else also yields materials. A conversion that
	# charges a steady toll is a sink; one that charges a wildly varying toll is a trap.
	var ores := ["copper_ore", "iron_ore", "steel_ore", "mithril_ore", "adamantine_ore",
		"orichalcum_ore", "void_ore", "celestial_ore", "primordial_ore"]
	var worst := 0.0
	var best := -1.0
	for i in range(ores.size() - 1):
		var in_v := 5.0 * _val(ores[i])
		var out_v := 2.0 * _val(ores[i + 1])
		if in_v <= 0.0:
			continue
		var ret := out_v / in_v
		worst = minf(worst if best >= 0.0 else ret, ret)
		best = maxf(best, ret)
	print("  5x T(N) -> 2x T(N+1) returns %.0f%% to %.0f%% of value across the ore ladder" % [
		worst * 100.0, best * 100.0])
	if best - worst > 0.15:
		_fail("transmute's return swings %.0f points across tiers - that is a trap, not a toll" % ((best - worst) * 100.0))
	elif worst < 0.6:
		_fail("transmute returns only %.0f%% - too punitive to use" % (worst * 100.0))
	else:
		_ok("a consistent toll, and it does something salvage has no way to do")

	print("")
	print("===== 2. EXTRACT: cross-type conversion at a rate that no longer swings =====")
	# The old code paid a flat 2 output against a hand-authored tier map while the value ladder
	# kept doubling, so the real return ranged from -20% to -67%.
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	# ⛑ THE RATE IS CALLED, NOT RE-DERIVED. The first version of this section computed the
	# quantities itself from a hardcoded 0.80 and printed a lovely table - and passed clean while
	# the server was reverted to the old flat 2, because nothing in it touched the server's
	# arithmetic. That was the FOURTH check in one session to assert nothing.
	if srv.find("CraftingDatabaseScript.extract_output_quantity(") < 0:
		_fail("the server no longer calls extract_output_quantity - it has its own rate again")
	else:
		_ok("the server calls the shared rate function, so this probe measures what players get")
	var leathers := ["ragged_leather", "leather_scraps", "thick_leather", "enchanted_leather",
		"wyvern_leather", "dragonhide", "void_silk", "celestial_hide", "astral_weave"]
	var ess := {1: "magic_dust", 2: "magic_dust", 3: "arcane_crystal", 4: "soul_shard",
		5: "soul_shard", 6: "void_essence", 7: "void_essence", 8: "primordial_spark",
		9: "primordial_spark"}
	var lo := 9.99
	var hi := 0.0
	print("  %-20s %-10s %-16s %s" % ["input x3", "value", "output", "return"])
	for lid in leathers:
		var md: Dictionary = CD.MATERIALS.get(lid, {})
		if md.is_empty():
			continue
		var tier: int = int(md.get("tier", 1))
		var target := String(ess.get(tier, "magic_dust"))
		var in_v := 3.0 * _val(lid)
		var out_unit := maxf(1.0, _val(target))
		# The REAL function the server calls.
		var qty: int = CD.extract_output_quantity(lid, target, 1.0)
		var ret := (float(qty) * out_unit) / maxf(1.0, in_v)
		lo = minf(lo, ret)
		hi = maxf(hi, ret)
		print("  %-20s %-10.0f %-16s %.0f%%" % [lid, in_v, "%dx %s" % [qty, target], ret * 100.0])
	# ⛑ The floor() and the min-1 mean it cannot be exactly 80% everywhere; what matters is that
	# it no longer COLLAPSES. The old spread bottomed out at 33% of value returned.
	if lo < 0.5:
		_fail("extract still returns as little as %.0f%% at some tier" % (lo * 100.0))
	else:
		_ok("returns %.0f%%-%.0f%% across every tier (was 33%%-143%%)" % [lo * 100.0, hi * 100.0])

	print("")
	print("===== 3. DISENCHANT: returns the runes, and never loses to salvage =====")
	# ⛑ THE THING THAT MAKES IT A DIFFERENT RECIPE. Checked structurally because it needs a live
	# character and inventory; the behaviour it guards is "runes recorded on the way in come back
	# on the way out".
	var checks := {
		"runes are recorded when applied": srv.find("_remember_applied_rune(target_item, rune)") >= 0,
		"both rune branches record": srv.count("_remember_applied_rune(target_item, rune)") == 2,
		"disenchant reads the record": srv.find("item.get(\"applied_runes\"") >= 0,
		"it returns them to the pack": srv.find("character.add_item(rune_item.duplicate(true))") >= 0,
		"materials come from salvage itself": srv.find("drop_tables.get_salvage_value(item)") >= 0,
		"it targets the most-runed item": srv.find("runes.size() > best_runes") >= 0,
		"a full pack is reported, not silent": srv.find("rune(s) lost") >= 0,
		"the old one-ore formula is gone": srv.find("var base_amount = max(1, int(3 * recovery_pct))") < 0,
	}
	for k in checks.keys():
		if bool(checks[k]):
			_ok(String(k))
		else:
			_fail("%s -- NO" % k)

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for f in _fails:
			print("   - %s" % f)
		quit(1)
		return
	print("[PROBE] PASS all three specialist conversions do something salvage cannot, at a rate")
	print("       that holds across the tier ladder.")
	quit()
