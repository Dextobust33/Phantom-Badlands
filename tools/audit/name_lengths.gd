extends SceneTree
## How long do monster and item names ACTUALLY get, and which stacks cause it?
##
## Owner 2026-09-15: *"find a way to shorten those long names on items and monsters that have
## bunches of affixes. Ideally we just create new affixes or names for those that have a
## combination of multiple affixes, for example something that has juggernaut swift could have a
## single affix that instead combines those two, or even ones that combine 3 or 4."*
##
## Before authoring a combination table, measure: how long names really run, how often, and WHICH
## word pairs actually co-occur. Authoring combinations for pairs that never appear together is
## work nobody sees; the pairs worth a hand-written word are the common ones.
const MonsterDB = preload("res://shared/monster_database.gd")
const DropTablesScript = preload("res://shared/drop_tables.gd")
const SAMPLES := 400

func _pct(sorted_lens: Array, q: float) -> int:
	if sorted_lens.is_empty():
		return 0
	var i: int = clampi(int(round(q * float(sorted_lens.size() - 1))), 0, sorted_lens.size() - 1)
	return int(sorted_lens[i])


func _report(label: String, names: Array) -> void:
	var lens: Array = []
	for n in names:
		lens.append(String(n).length())
	lens.sort()
	var total := 0
	for l in lens:
		total += int(l)
	var over30 := 0
	var over40 := 0
	for l in lens:
		if int(l) > 30:
			over30 += 1
		if int(l) > 40:
			over40 += 1
	print("  %-26s n=%d  mean %.1f  median %d  p90 %d  max %d   >30ch %.0f%%  >40ch %.0f%%" % [
		label, names.size(), float(total) / float(maxi(1, names.size())),
		_pct(lens, 0.5), _pct(lens, 0.9), _pct(lens, 1.0),
		100.0 * float(over30) / float(maxi(1, names.size())),
		100.0 * float(over40) / float(maxi(1, names.size()))])
	# The longest few, because that is what the owner is actually looking at.
	var by_len: Array = names.duplicate()
	by_len.sort_custom(func(a, b): return String(a).length() > String(b).length())
	for i in range(mini(4, by_len.size())):
		print("      %3d  %s" % [String(by_len[i]).length(), String(by_len[i])])


func _init() -> void:
	var db = MonsterDB.new()
	get_root().add_child(db)
	var dt = DropTablesScript.new()
	get_root().add_child(dt)

	print("===== MONSTER NAMES =====")
	for lvl in [5, 50, 500, 5000]:
		var names: Array = []
		var word_counts := {}
		var pair_counts := {}
		for i in range(SAMPLES):
			var m: Dictionary = db.generate_monster(lvl, lvl)
			if m.is_empty():
				continue
			var nm := String(m.get("name", ""))
			names.append(nm)
			var words := nm.split(" ", false)
			for w in words:
				word_counts[w] = int(word_counts.get(w, 0)) + 1
			for a in range(words.size()):
				for b in range(a + 1, words.size()):
					var key := "%s + %s" % [words[a], words[b]]
					pair_counts[key] = int(pair_counts.get(key, 0)) + 1
		_report("level %d" % lvl, names)
		if lvl == 500:
			var pairs: Array = pair_counts.keys()
			pairs.sort_custom(func(a, b): return int(pair_counts[a]) > int(pair_counts[b]))
			print("    most common word pairs at this level:")
			for i in range(mini(8, pairs.size())):
				print("      %4d  %s" % [int(pair_counts[pairs[i]]), pairs[i]])

	print("")
	print("===== ITEM NAMES =====")
	for rarity in ["common", "rare", "epic", "legendary", "artifact"]:
		var names: Array = []
		for i in range(SAMPLES):
			var it: Dictionary = dt._generate_item({"item_type": "weapon_iron", "rarity": rarity}, 200)
			if it.is_empty():
				continue
			names.append(String(it.get("name", "")))
		_report(rarity, names)
	quit(0)
