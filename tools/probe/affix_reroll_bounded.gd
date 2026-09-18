extends SceneTree
## ⛑ CAN A PLAYER BUFF ONE ITEM FOREVER? The whole point of this probe is to answer NO in numbers.
##
## Owner 2026-09-18: *"we don't want these things to make it where players can infinitely upgrade
## for free. It's meant to be a quality of life thing with maybe some discount but not a gate. We
## don't want a player to just be able to keep buffing their same item for free infinitely."*
##
## A reroll is unlike the other specialist services: repair/heal/recharge/camp all RESTORE TO A
## CEILING and stop mattering once you are at it, so free-plus-cooldown is self-limiting. A reroll
## COMPOUNDS. So the brakes are the feature, and each is tested as its own claim:
##
##   1. REPLACES, NEVER ADDS   — the affix count cannot grow
##   2. SAME POOL ONLY         — a rare cannot reroll into the epic-only chase pool
##   3. FRESH ROLL, NO UNDO    — the value can come out WORSE, so it is a lateral trade
##   4. HARD CAP               — MAX_AFFIX_REROLLS per item, absolutely
##   5. RISING, NON-ZERO COST  — including for the specialist, whose perk is a discount
##
## ⛑ CLAIM 3 IS MEASURED ACROSS MANY TRIALS, NOT ASSERTED ONCE. "It can come out worse" is a
## statement about a distribution; a single reroll that happens to go down proves nothing, and one
## that goes up disproves nothing. The probe rerolls hundreds of times and reports the share that
## lost value — if that share were ~0 the brake would not exist however the code reads.
##
## Run:
##   godot --headless --path . --script res://tools/probe/affix_reroll_bounded.gd

const DT := preload("res://shared/drop_tables.gd")

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


func _init() -> void:
	var dt = DT.new()
	get_root().add_child(dt)
	seed(31337)

	print("")
	print("===== A REAL DROPPED ITEM, FROM THE REAL GENERATOR =====")
	# ⛑ Not a hand-built dictionary. `crafting_worth` recorded what that costs: a hand-made stand-in
	# gave "crafted beats drops 52x" because it guessed the wrong container for the stats.
	var item: Dictionary = {}
	for _try in range(400):
		var cand: Dictionary = dt.roll_dungeon_chest_equipment(4, 60)
		if cand.is_empty():
			continue
		if dt.rerollable_affixes(cand).size() >= 2:
			item = cand
			break
	if item.is_empty():
		print("[PROBE] FAIL could not generate a dropped item with 2+ affixes")
		quit(1)
		return
	print("  %s (level %d, %s)" % [item.get("name", "?"), int(item.get("level", 0)),
		item.get("rarity", "?")])
	print("  affixes: %s" % str(item.get("affixes", {})))

	# ---- 1. REPLACES, NEVER ADDS -----------------------------------------------------------
	print("")
	print("===== 1. IT REPLACES, IT NEVER ADDS =====")
	var before_n: int = dt.rerollable_affixes(item).size()
	var work: Dictionary = item.duplicate(true)
	var target: String = dt.rerollable_affixes(work)[0]
	var r: Dictionary = dt.reroll_affix(work, target)
	if not bool(r.get("ok", false)):
		_fail("a first reroll on a fresh drop failed: %s" % r.get("error", ""))
	else:
		var after_n: int = dt.rerollable_affixes(work).size()
		if after_n != before_n:
			_fail("affix count changed %d -> %d; a reroll must replace, not add" % [before_n, after_n])
		else:
			_ok("count held at %d   (%s -> %s)" % [after_n, r.get("old_stat", ""), r.get("new_stat", "")])
		if String(r.get("new_stat", "")) == target:
			_fail("rerolled into the SAME stat — that is a value reroll, not a stat reroll")
		else:
			_ok("the stat actually changed")

	# ---- 2. SAME POOL ONLY: the chase pool stays out of reach -------------------------------
	print("")
	print("===== 2. A REROLL CANNOT REACH THE EPIC-ONLY CHASE POOL =====")
	# ⛑ THE SHARPEST BACK DOOR. The chase pool is epic+ only and holds crit, damage_mult,
	# extra_turn_chance and the resource-on-hit stats. If a rare could reroll into it, rerolling
	# would be a route to rarity itself, which is a far bigger break than a strong roll.
	var chase_stats: Dictionary = {}
	for e in DT.CHASE_SUFFIX_POOL:
		var st := String(e.get("stat", ""))
		var in_normal := false
		for n in (DT.PREFIX_POOL + DT.SUFFIX_POOL):
			if String(n.get("stat", "")) == st:
				in_normal = true
				break
		if not in_normal:
			chase_stats[st] = true
	print("  chase-exclusive stats: %s" % ", ".join(chase_stats.keys()))
	# ⛑ THIS CHECK WAS VACUOUS ON ITS FIRST WRITING AND THE FAULT INJECTION IS WHAT EXPOSED IT.
	# The chase pool is only reachable from a BONUS slot, and a bonus slot only exists at epic+
	# (AFFIX_COUNTS: rare=2 is prefix+suffix and nothing else). The probe's sample item was
	# uncommon, so the bonus branch never ran, and deliberately routing the chase pool into that
	# branch produced a clean pass. A test that cannot fail is not a test.
	var rich: Dictionary = {}
	for _try in range(1200):
		var cand: Dictionary = dt.roll_dungeon_chest_equipment(8, 120)
		if cand.is_empty():
			continue
		if dt.rerollable_affixes(cand).size() >= 3 and String(cand.get("rarity", "")) in ["epic", "legendary", "artifact"]:
			rich = cand
			break
	if rich.is_empty():
		_fail("could not generate an epic+ item with a bonus slot — the chase check cannot run")
		rich = item
	else:
		print("  bonus-slot sample: %s (%s, %d affixes)" % [rich.get("name", "?"),
			rich.get("rarity", "?"), dt.rerollable_affixes(rich).size()])
	# Prove the bonus branch is actually exercised, rather than trusting the affix count.
	var bonus_hits := 0
	var leaked: Array = []
	for _i in range(600):
		var w: Dictionary = rich.duplicate(true)
		var keys: Array = dt.rerollable_affixes(w)
		if keys.is_empty():
			continue
		var pickk := String(keys[randi() % keys.size()])
		if dt._affix_slot_for(w, pickk) == "bonus":
			bonus_hits += 1
		var res: Dictionary = dt.reroll_affix(w, pickk)
		if bool(res.get("ok", false)) and chase_stats.has(String(res.get("new_stat", ""))):
			leaked.append(String(res.get("new_stat", "")))
	print("  bonus-slot rerolls exercised: %d of 600" % bonus_hits)
	if bonus_hits == 0:
		_fail("no reroll hit a BONUS slot — the chase-pool check proved nothing")
	if not leaked.is_empty():
		_fail("%d of 600 rerolls produced a chase-only stat (%s)" % [leaked.size(), leaked[0]])
	elif chase_stats.is_empty():
		_fail("no chase-exclusive stats found — this check proved nothing, fix the derivation")
	else:
		_ok("0 of 600 rerolls reached a chase-only stat")

	# ---- 3. IT CAN COME OUT WORSE ------------------------------------------------------------
	print("")
	print("===== 3. THE NEW ROLL CAN BE WORSE, AND IT STANDS =====")
	var worse := 0
	var better := 0
	var trials := 0
	for _i in range(600):
		var w: Dictionary = item.duplicate(true)
		var keys: Array = dt.rerollable_affixes(w)
		if keys.is_empty():
			continue
		var k := String(keys[randi() % keys.size()])
		var ov = w["affixes"][k]
		var res: Dictionary = dt.reroll_affix(w, k)
		if not bool(res.get("ok", false)):
			continue
		trials += 1
		if float(res.get("new_value", 0)) < float(ov):
			worse += 1
		elif float(res.get("new_value", 0)) > float(ov):
			better += 1
	var pct_worse: float = 100.0 * float(worse) / maxf(1.0, float(trials))
	print("  %d rerolls: %d worse (%.0f%%), %d better" % [trials, worse, pct_worse, better])
	if trials < 100:
		_fail("only %d trials completed — the distribution claim is untested" % trials)
	elif worse == 0:
		_fail("NO reroll ever lost value — it is a one-way upgrade ladder")
	else:
		_ok("a reroll is a genuine gamble, not a ratchet")

	# ---- 4. HARD CAP -------------------------------------------------------------------------
	print("")
	print("===== 4. THE HARD CAP HOLDS =====")
	var w2: Dictionary = item.duplicate(true)
	var done := 0
	for _i in range(DT.MAX_AFFIX_REROLLS + 6):
		var keys: Array = dt.rerollable_affixes(w2)
		if keys.is_empty():
			break
		var res: Dictionary = dt.reroll_affix(w2, String(keys[0]))
		if bool(res.get("ok", false)):
			done += 1
	if done != DT.MAX_AFFIX_REROLLS:
		_fail("got %d successful rerolls, cap is %d" % [done, DT.MAX_AFFIX_REROLLS])
	else:
		_ok("stopped at exactly %d rerolls, then refused" % done)
	var past: Dictionary = dt.reroll_affix(w2, String(dt.rerollable_affixes(w2)[0]))
	if bool(past.get("ok", false)):
		_fail("a reroll past the cap still succeeded")
	else:
		_ok("past the cap it refuses and says why")

	# ---- 5. COST RISES, AND NEVER REACHES ZERO ----------------------------------------------
	print("")
	print("===== 5. THE COST RISES AND NEVER REACHES ZERO =====")
	print("  %-6s %-28s %-28s" % ["n", "town", "committed enchanter"])
	var prev_town := -1
	var prev_spec := -1
	for n in range(DT.MAX_AFFIX_REROLLS):
		var probe_item: Dictionary = item.duplicate(true)
		probe_item["reroll_count"] = n
		var ct: Dictionary = dt.affix_reroll_cost(probe_item, false)
		var cs: Dictionary = dt.affix_reroll_cost(probe_item, true)
		var tq: int = 0
		var sq: int = 0
		for k in ct["materials"].keys():
			tq = int(ct["materials"][k])
		for k in cs["materials"].keys():
			sq = int(cs["materials"][k])
		print("  %-6d %-28s %-28s" % [n,
			"%d mat + %d valor" % [tq, int(ct["valor"])],
			"%d mat + %d valor" % [sq, int(cs["valor"])]])
		# ⛑ THE ZERO CHECK IS THE OWNER'S LINE, LITERALLY. A specialist cost that reaches 0
		# materials and 0 valor IS "buffing the same item for free".
		if sq <= 0:
			_fail("the specialist cost reached ZERO materials at reroll %d — that is free buffing" % n)
		if tq < prev_town or sq < prev_spec:
			_fail("cost went DOWN at reroll %d" % n)
		if n > 0 and tq == prev_town and sq == prev_spec:
			_fail("cost did not rise at reroll %d — a flat cost is not a brake" % n)
		prev_town = tq
		prev_spec = sq
	if _fails.is_empty():
		_ok("rises every step, and the specialist discount never becomes a waiver")
	# And the cap must be reflected in the cost, not only in the action.
	var capped_item: Dictionary = item.duplicate(true)
	capped_item["reroll_count"] = DT.MAX_AFFIX_REROLLS
	if not bool(dt.affix_reroll_cost(capped_item, true).get("capped", false)):
		_fail("a capped item does not report itself as capped")
	else:
		_ok("a capped item reports capped instead of quoting a price")

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for f in _fails:
			print("   - %s" % f)
		quit(1)
		return
	print("[PROBE] PASS a reroll replaces without adding, cannot reach the chase pool, can come")
	print("       out worse, stops at %d per item, and never costs nothing." % DT.MAX_AFFIX_REROLLS)
	quit()
