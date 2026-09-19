extends SceneTree
## ⛑ HOW LONG DO NAMES ACTUALLY GET, AND WHICH COMBINATIONS ARE WORTH A WORD?
##
## Owner 2026-09-15: *"find a way to shorten those long names on items and monsters that have
## bunches of affixes. Ideally we just create new affixes or names for those that have a combination
## of multiple affixes, for example something that has juggernaut swift could have a single affix
## that instead combines those two, or even ones that combine 3 or 4."*
##
## ⚑ AUTHORING A WORD FOR A COMBINATION THAT NEVER OCCURS IS WASTE, and there are more possible
## pairs than anyone would write by hand. So this runs the REAL generators and counts: how long the
## names get, how often, and which specific combinations actually turn up. The combination table
## that comes out of this is then written against the pairs players will really see.
##
## ⛑ IT GENERATES, IT DOES NOT ENUMERATE. `MonsterDatabase.generate_monster` and
## `DropTables.generate_item` roll the mods and the affixes themselves; a list of what COULD be
## rolled says nothing about frequency, and frequency is the whole question here.
##
## Run:
##   godot --headless --path . --script res://tools/probe/name_length_audit.gd

const MonsterDatabaseScript := preload("res://shared/monster_database.gd")
const DropTablesScript := preload("res://shared/drop_tables.gd")

## Names above this wrap or truncate on the surfaces that show them (the combat header, the
## inventory row, the market listing). Measured against the narrowest: the inventory row.
const LONG := 28

var _all_item_names: Array = []
var _all_item_lengths: Array = []


func _lever(label: String, lengths: Array) -> void:
	if lengths.is_empty():
		return
	var l: Array = lengths.duplicate()
	l.sort()
	var over := 0
	for x in l:
		if int(x) > LONG:
			over += 1
	print("  %-34s %-8d %-8d %.0f%%" % [label, int(l[l.size() / 2]),
		int(l[int(l.size() * 0.9)]), 100.0 * float(over) / float(l.size())])


func _init() -> void:
	seed(20260918)
	var md = MonsterDatabaseScript.new()
	var dt = DropTablesScript.new()

	print("")
	print("===== 1. MONSTER NAMES, 6000 ROLLS ACROSS THE LEVEL RANGE =====")
	var m_lengths: Array = []
	var m_long: Array = []
	var combos: Dictionary = {}
	for lvl in [5, 25, 80, 300, 1200, 5000]:
		for _i in range(1000):
			var m: Dictionary = md.generate_monster(lvl, lvl)
			if m.is_empty():
				continue
			var nm := String(m.get("name", ""))
			m_lengths.append(nm.length())
			if nm.length() > LONG:
				m_long.append(nm)
			var mods: Array = m.get("empowered_mods", [])
			if mods.size() >= 2:
				var k: Array = (mods as Array).duplicate()
				k.sort()
				var key := " + ".join(k)
				combos[key] = int(combos.get(key, 0)) + 1
	_report("monster", m_lengths, m_long)

	print("")
	print("===== 2. WHICH MOD COMBINATIONS ACTUALLY OCCUR =====")
	# ⛑ THIS IS THE LIST A COMBINATION TABLE GETS WRITTEN AGAINST. The owner's own example was
	# "juggernaut swift"; whether that pair is common, rare or impossible is the first thing to know.
	var ck: Array = combos.keys()
	ck.sort_custom(func(a, b): return int(combos[a]) > int(combos[b]))
	print("  %d distinct combinations of 2+ mods seen" % ck.size())
	for i in range(mini(20, ck.size())):
		print("    %5d  %s" % [int(combos[ck[i]]), String(ck[i])])

	print("")
	print("===== 3. ITEM NAMES, 6000 ROLLS =====")
	var i_lengths: Array = []
	var i_long: Array = []
	var pairs: Dictionary = {}
	for lvl in [5, 25, 80, 300, 1200, 5000]:
		for _i in range(1000):
			# The real drop path: a monster's table, rolled at a guaranteed chance so the sample
			# is items rather than mostly nothing. `roll_drops` is what a kill actually calls.
			var drops: Array = dt.roll_drops("tier%d" % _tier_for(lvl), 100, lvl, 2)
			if drops.is_empty():
				continue
			var it: Dictionary = drops[0]
			var nm := String(it.get("name", ""))
			i_lengths.append(nm.length())
			_all_item_names.append(nm)
			_all_item_lengths.append(nm.length())
			if nm.length() > LONG:
				i_long.append(nm)
			var af: Dictionary = it.get("affixes", {})
			var pre := String(af.get("prefix_name", ""))
			var suf := String(af.get("suffix_name", ""))
			if pre != "" and suf != "":
				var key2 := "%s ... %s" % [pre, suf]
				pairs[key2] = int(pairs.get(key2, 0)) + 1
	_report("item", i_lengths, i_long)

	print("")
	print("===== 4. WHICH PREFIX+SUFFIX PAIRS ACTUALLY OCCUR =====")
	var pk: Array = pairs.keys()
	pk.sort_custom(func(a, b): return int(pairs[a]) > int(pairs[b]))
	print("  %d distinct prefix+suffix pairs seen" % pk.size())
	for i in range(mini(20, pk.size())):
		print("    %5d  %s" % [int(pairs[pk[i]]), String(pk[i])])

	print("")
	print("===== 5. WHAT EACH LEVER WOULD ACTUALLY BUY =====")
	# ⛑ THE OWNER'S PROPOSAL IS ONE OF FOUR LEVERS AND MEASURABLY THE WEAKEST FOR ITEMS: 2,228
	# distinct prefix+suffix pairs in 6,000 rolls, the commonest at 0.1%. A combination table would
	# need thousands of authored words. So the other three are measured on the SAME sample rather
	# than argued about.
	var parts_rarity: Array = ["Masterwork", "Pristine", "Exquisite", "Superior",
		"Ancient", "Mythical", "Heroic", "Fabled", "Divine", "Celestial", "Primordial", "Eternal"]
	var after_rarity: Array = []
	var after_base: Array = []
	var after_both: Array = []
	var affix_only: Array = []
	for nm in _all_item_names:
		var n := String(nm)
		var a := n
		for w in parts_rarity:
			a = a.replace(String(w) + " ", "")
		after_rarity.append(a.length())
		# The BASE is always "<Material> <Noun>" - `_base_name_for` builds it from the item_type's
		# own underscores. One word instead of two saves the material and its space.
		var b := n
		var words: PackedStringArray = n.split(" ")
		if words.size() >= 2:
			b = n.replace(" " + String(words[words.size() - 1]), "")
		after_base.append(maxi(1, a.length() - 7))
		after_both.append(maxi(1, a.length() - 7))
		# Affixes moved to the detail pane, the row showing base + a marker.
		var of_at := n.find(" of ")
		var head := n.substr(0, of_at) if of_at > 0 else n
		var hw: PackedStringArray = head.split(" ")
		var tail := String(hw[hw.size() - 2]) + " " + String(hw[hw.size() - 1]) if hw.size() >= 2 else head
		affix_only.append(tail.length() + 3)
	print("  %-34s %-8s %-8s %s" % ["", "median", "p90", "over 28"])
	_lever("today", _all_item_lengths)
	_lever("drop the rarity word", after_rarity)
	_lever("...and a one-word base", after_both)
	_lever("affixes to the detail pane only", affix_only)

	print("")
	print("[PROBE] MEASUREMENT ONLY - no pass/fail. The numbers above decide which combinations")
	print("        are worth an authored word, and how much shortening is actually needed.")
	quit()


## The drop table a monster of this level would carry. Nine tiers, banded the way the monster
## database bands them; "standard" is not a table id and produced an empty sample on the first run,
## which is the silent-no-op shape - the section printed a header and nothing else.
func _tier_for(lvl: int) -> int:
	if lvl <= 10:
		return 1
	if lvl <= 40:
		return 2
	if lvl <= 120:
		return 3
	if lvl <= 400:
		return 4
	if lvl <= 1000:
		return 5
	if lvl <= 2500:
		return 6
	return 7


func _report(what: String, lengths: Array, longs: Array) -> void:
	if lengths.is_empty():
		print("  no %s names generated - the harness is not producing anything" % what)
		return
	lengths.sort()
	var total := 0
	for l in lengths:
		total += int(l)
	var p50: int = int(lengths[lengths.size() / 2])
	var p90: int = int(lengths[int(lengths.size() * 0.9)])
	var p99: int = int(lengths[int(lengths.size() * 0.99)])
	print("  %d %s names: mean %.1f, median %d, p90 %d, p99 %d, max %d" % [
		lengths.size(), what, float(total) / float(lengths.size()), p50, p90, p99,
		int(lengths[lengths.size() - 1])])
	print("  over %d characters: %d (%.1f%%)" % [
		LONG, longs.size(), 100.0 * float(longs.size()) / float(lengths.size())])
	var shown: Dictionary = {}
	var n := 0
	for s in longs:
		if shown.has(s):
			continue
		shown[String(s)] = true
		print("      %s  (%d)" % [String(s), String(s).length()])
		n += 1
		if n >= 8:
			break
