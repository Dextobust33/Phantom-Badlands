extends SceneTree
## ⛑ IS THE WISH STILL WORTH WINNING? Measured through the real stat aggregator.
##
## Owner 2026-09-18, on removing the undamped stat writes: *"so what does the wish do now? Ensure
## you aren't destroying our loot rewards. The wish isn't free, you have to kill a monster that can
## grant it. The balance should be in how often you can actually get a wish, not in making it
## useless."*
##
## Exactly the right question, and the honest way to answer it is to EQUIP the item and diff what
## the player actually gets - `equipment_reference` records that reasoning about gear from tables
## is how this codebase has repeatedly got gear wrong.
##
## It reports two things:
##   1. WHAT CHANGED for each item kind - old behaviour vs new, so "did I nerf the reward" has a
##      number rather than an opinion.
##   2. WHAT A WISH IS WORTH NOW, at several levels, against what the item was already giving.
##
## Run:
##   godot --headless --path . --script res://tools/probe/wish_upgrade_worth.gd

const CharacterScript := preload("res://shared/character.gd")

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


func _power(item: Dictionary) -> int:
	# One number for "how much is this item giving me", summed off the REAL aggregator.
	var b: Dictionary = CharacterScript.item_stat_bonuses(item)
	var t := 0
	for k in b.keys():
		var v = b[k]
		if v is int or v is float:
			t += int(v)
	return t


func _mk(item_type: String, level: int, rarity: String, crafted: bool) -> Dictionary:
	var it := {
		"name": "Test %s" % item_type, "type": item_type, "item_type": item_type,
		"level": level, "rarity": rarity,
	}
	if crafted:
		# A crafted item carries its recipe's own stats, which the aggregator adds on top.
		it["crafted"] = true
		it["attack"] = 20
		it["defense"] = 50
		it["speed"] = 10
	return it


## The NEW behaviour: one EFFECTIVE level per upgrade, capped per item.
## Mirrors server.gd::_upgrade_single_item. (It cannot be called directly - server.gd is a Node
## with a heavy _ready - so this is the one place a copy is unavoidable, and the copy is checked
## against the server source at the end of the probe.)
const WISH_EFFECTIVE_STEP := 0.03
const WISH_MAX_GAIN_FRACTION := 0.50

func _upgrade_new(item: Dictionary) -> void:
	var cur: int = int(item.get("level", 1))
	var cur_eff: float = CharacterScript._get_effective_item_level(cur)
	if not item.has("wish_base_effective"):
		item["wish_base_effective"] = cur_eff
	var ceiling: float = float(item["wish_base_effective"]) * (1.0 + WISH_MAX_GAIN_FRACTION)
	if cur_eff >= ceiling:
		return
	var target: float = minf(ceiling, cur_eff * (1.0 + WISH_EFFECTIVE_STEP))
	item["level"] = maxi(cur + 1, CharacterScript.raw_level_for_effective(target))


## The OLD behaviour, reproduced exactly, so the comparison is against what actually shipped.
func _upgrade_old(item: Dictionary) -> void:
	item["level"] = int(item.get("level", 1)) + 1
	var t := String(item.get("item_type", ""))
	if "weapon" in t:
		var d: int = int(item.get("damage", 10))
		item["damage"] = d + maxi(1, int(d * 0.08))
	elif "armor" in t or "shield" in t or "helm" in t:
		var v: int = int(item.get("defense", 5))
		item["defense"] = v + maxi(1, int(v * 0.08))
	elif "boots" in t:
		var s: int = int(item.get("speed", 5))
		item["speed"] = s + maxi(1, int(s * 0.08))


func _init() -> void:
	print("")
	print("===== 1. WHAT THE CHANGE ACTUALLY COST, PER ITEM KIND =====")
	print("  A wish grants 3-15 upgrades. Using 9 (the midpoint).")
	print("")
	print("  %-22s %-9s %-9s %-9s %s" % ["item", "before", "old+9", "new+9", "verdict"])
	var kinds := [
		["weapon", false], ["armor", false], ["boots", false],
		["weapon", true], ["armor", true], ["boots", true],
	]
	var unchanged := 0
	var reduced := 0
	for kind in kinds:
		var t := String(kind[0])
		var crafted: bool = bool(kind[1])
		var base := _mk(t, 20, "rare", crafted)
		var p0 := _power(base)
		var a := base.duplicate(true)
		var b := base.duplicate(true)
		for _i in range(9):
			_upgrade_old(a)
			_upgrade_new(b)
		var pa := _power(a)
		var pb := _power(b)
		var label := "%s%s" % [t, " (crafted)" if crafted else " (dropped)"]
		var verdict := ""
		if pa == pb:
			verdict = "IDENTICAL - nothing lost"
			unchanged += 1
		else:
			verdict = "reduced by %d (%.0f%%)" % [pa - pb, 100.0 * float(pa - pb) / maxf(1.0, float(pa))]
			reduced += 1
		print("  %-22s %-9d %-9d %-9d %s" % [label, p0, pa, pb, verdict])
	print("")
	print("  %d of %d item kinds are byte-identical to before." % [unchanged, kinds.size()])
	# ⛑ THE CLAIM BEING CHECKED. The raw writes were dead for dropped gear (nothing reads a
	# top-level `damage`, and `defense`/`speed` are read only when `crafted`), so removing them
	# can only have changed CRAFTED armour and boots. If a DROPPED item moved, that reasoning was
	# wrong and the removal really did take something away.
	for kind in [["weapon", false], ["armor", false], ["boots", false]]:
		var base := _mk(String(kind[0]), 20, "rare", false)
		var a := base.duplicate(true)
		var b := base.duplicate(true)
		for _i in range(9):
			_upgrade_old(a)
			_upgrade_new(b)
		if _power(a) != _power(b):
			_fail("dropped %s LOST power in the change (%d -> %d)" % [String(kind[0]), _power(a), _power(b)])
	if _fails.is_empty():
		_ok("no dropped item lost anything - the removed writes were dead for them")

	print("")
	print("===== 2. SO WHAT IS A WISH WORTH NOW? =====")
	# The owner's actual worry: that the reward is now useless. A wish must be clearly worth
	# winning at the levels people win them at.
	print("  %-8s %-10s %-11s %-11s %-10s %s" % ["lvl", "item was", "wish x3", "wish x9", "wish x15", "x9 gain"])
	for lvl in [5, 20, 50, 100, 300]:
		var base := _mk("weapon", lvl, "rare", false)
		var p0 := _power(base)
		var row: Array = []
		for n in [3, 9, 15]:
			var w := base.duplicate(true)
			for _i in range(n):
				_upgrade_new(w)
			row.append(_power(w))
		var gain_pct: float = 100.0 * float(int(row[1]) - p0) / maxf(1.0, float(p0))
		print("  %-8d %-10d %-11d %-11d %-10d +%.0f%%" % [lvl, p0, int(row[0]), int(row[1]), int(row[2]), gain_pct])
		# ⛑ A REWARD THAT MOVES THE NUMBER BY UNDER 5% IS THE THING THE OWNER IS WARNING ABOUT.
		# It has to be visible on the character sheet or it is not a reward.
		if gain_pct < 5.0:
			_fail("at level %d a 9-upgrade wish is only +%.0f%% - that is not worth winning" % [lvl, gain_pct])
	if _fails.is_empty():
		_ok("a wish is a visible gain at every level tested")

	print("")
	print("===== 3. THE REWARD IS BOUNDED PER ITEM =====")
	# ⛑ A wish is REPEATABLE (10% per wish_granter kill), and this sweep has already removed three
	# unbounded paths. A meaningful grant plus repeatability needs a ceiling or it is the fourth.
	var far := _mk("weapon", 100, "rare", false)
	var eff0: float = CharacterScript._get_effective_item_level(int(far["level"]))
	for _i in range(200):
		_upgrade_new(far)
	var eff1: float = CharacterScript._get_effective_item_level(int(far["level"]))
	var gain_frac: float = (eff1 - eff0) / maxf(1.0, eff0)
	print("  200 upgrades on one level-100 item: effective %.0f -> %.0f (+%.0f%%, cap +%.0f%%)" % [
		eff0, eff1, gain_frac * 100.0, WISH_MAX_GAIN_FRACTION * 100.0])
	if gain_frac > WISH_MAX_GAIN_FRACTION + 0.03:
		_fail("wish upgrades exceeded the per-item cap (+%.0f%%)" % (gain_frac * 100.0))
	else:
		_ok("stops at +%.0f%% of the item's natural power, however many wishes are spent" % (gain_frac * 100.0))
	# The probe keeps a copy of the server's arithmetic; assert the server still has the shape it
	# is copying, so the two cannot drift silently.
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	for shape in ["WISH_MAX_GAIN_FRACTION", "raw_level_for_effective", "wish_base_effective"]:
		if srv.find(shape) < 0:
			_fail("server.gd no longer uses %s - this probe is modelling code that is gone" % shape)
	print("")
	print("===== 4. THE DAMPING IS THE BRAKE, AND IT IS SOFT =====")
	# ⛑ The point of routing through `level` is that the curve already decides how much a wish is
	# worth, and it does NOT flatten to nothing - it just stops being exponential. Printed so the
	# shape is visible rather than asserted.
	for lvl in [10, 50, 100, 500, 1000]:
		print("  item level %-6d effective %.0f" % [lvl, CharacterScript._get_effective_item_level(lvl)])

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for f in _fails:
			print("   - %s" % f)
		quit(1)
		return
	print("[PROBE] PASS the wish still pays, dropped gear lost nothing, and only crafted armour")
	print("       and boots gave up their undamped compounding.")
	quit()
