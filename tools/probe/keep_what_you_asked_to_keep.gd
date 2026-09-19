extends SceneTree
## ⛑ DOES THE KEEP FILTER ACTUALLY KEEP WHAT THE PLAYER ASKED FOR?
##
## Owner 2026-09-18, on inventory bloat: *"lets say they only want things that give them an HP and
## Wit increase, if they can easily set that up then they could make it where any equipment they
## get that isn't an upgrade to both of those gets autosalvaged."*
##
## ⚡ THAT WAS NOT EXPRESSIBLE. The rule matched affix NAMES, and every stat has more affix names
## than the 5-per-stat cap allowed - hp_bonus 15, attack_bonus 16, defense_bonus 15, wits_bonus 6.
## A player who filled the screen as carefully as it permitted still had two thirds of their HP
## gear salvaged, silently, having been told it was set up. Wrong UNIT, which CLAUDE.md names as
## the failure that is "as wrong as a guess and far more convincing".
const CharacterScript := preload("res://shared/character.gd")
const DropTables := preload("res://shared/drop_tables.gd")

var _fails: Array = []
func _fail(m: String) -> void:
	_fails.append(m); print("  FAIL  %s" % m)
func _ok(m: String) -> void:
	print("  ok    %s" % m)

func _item(rarity: String, affixes: Dictionary) -> Dictionary:
	return {"type": "weapon", "rarity": rarity, "affixes": affixes}

func _init() -> void:
	print("")
	print("===== 1. \"KEEP HP AND WITS\" IS ONE SELECTION EACH, AND COVERS EVERYTHING =====")
	var keep := ["hp_bonus", "wits_bonus"]
	# Every affix in the pools that grants a kept stat must survive - not five of them.
	var covered := 0
	var missed := 0
	for pool in [DropTables.PREFIX_POOL, DropTables.SUFFIX_POOL]:
		for e in pool:
			var st := String(e.get("stat", ""))
			if not (st in keep):
				continue
			covered += 1
			var it := _item("common", {st: 5.0})
			if CharacterScript.would_auto_salvage(it, true, 5, keep, false):
				missed += 1
				_fail("an item granting %s (affix %s) would still be salvaged" % [st, e.get("name", "?")])
	print("  %d affixes grant HP or Wits; %d would be destroyed" % [covered, missed])
	if missed == 0:
		_ok("every one of them is protected by two selections")

	print("")
	print("===== 2. WHAT THE PLAYER DID NOT ASK FOR IS STILL SALVAGED =====")
	# A keep-rule that protects everything is the same as auto-salvage being off.
	var junk := _item("common", {"speed_bonus": 8.0})
	if not CharacterScript.would_auto_salvage(junk, true, 5, keep, false):
		_fail("an item with none of the kept stats survived - the filter protects everything")
	else:
		_ok("an item with none of the kept stats is salvaged")
	# ...and an item carrying BOTH a kept and an unkept stat is kept: it is an upgrade to one.
	var mixed := _item("common", {"speed_bonus": 8.0, "hp_bonus": 3.0})
	if CharacterScript.would_auto_salvage(mixed, true, 5, keep, false):
		_fail("an item granting HP was salvaged because it also had something else")
	else:
		_ok("an item is kept if it grants ANY kept stat")

	print("")
	print("===== 3. THE OLD PROTECTIONS STILL HOLD =====")
	for case in [
		{"n": "locked", "it": {"type": "weapon", "rarity": "common", "locked": true, "affixes": {}}},
		{"n": "a consumable", "it": {"type": "weapon", "rarity": "common", "is_consumable": true, "affixes": {}}},
		{"n": "a tool", "it": {"type": "tool", "rarity": "common", "affixes": {}}},
		{"n": "a rune", "it": {"type": "rune", "rarity": "common", "affixes": {}}},
	]:
		if CharacterScript.would_auto_salvage(case["it"], true, 5, [], false):
			_fail("%s would be auto-salvaged" % case["n"])
	if _fails.is_empty():
		_ok("locked items, consumables, tools and runes are still never destroyed")

	print("")
	print("===== 4. A FILTER SET IN THE OLD UNIT IS CLEARED, NOT TRANSLATED =====")
	# Owner chose clearing over migration: a translated filter would protect MORE than was picked,
	# and for a destructive setting the safe direction is off-until-reconfirmed.
	var ch = CharacterScript.new()
	ch.initialize("Probe", "Fighter", "Human")
	var saved := ch.to_dict()
	saved["auto_salvage_affixes"] = ["Vital", "Hearty"]   # affix NAMES, the old unit
	saved["auto_salvage_enabled"] = true
	saved.erase("auto_salvage_unit_migrated")
	var ch2 = CharacterScript.new()
	ch2.from_dict(saved)
	print("  loaded a character whose filter was [Vital, Hearty], enabled")
	print("  -> filter %s, auto-salvage %s" % [str(ch2.auto_salvage_affixes), str(ch2.auto_salvage_enabled)])
	if not ch2.auto_salvage_affixes.is_empty():
		_fail("the old name-based filter survived the change and now means nothing")
	elif ch2.auto_salvage_enabled:
		_fail("auto-salvage is still ON with an empty filter - it would salvage by rarity alone")
	else:
		_ok("the old filter is cleared and auto-salvage is off until the player sets it up again")

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS two selections express what the owner described, they cover every affix")
	print("       that grants those stats, and an old filter is cleared rather than guessed at.")
	quit()
