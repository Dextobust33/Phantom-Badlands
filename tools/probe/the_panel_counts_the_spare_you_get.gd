extends SceneTree
## ⛑ DOES THE TOOLS PANEL COUNT THE SPARE THE GAME WOULD ACTUALLY EQUIP?
##
## Owner, on tools being a chore: *"They are currently a pain to have to go back and craft and then
## they take up an inventory slot, it's hard to tell if you have backups etc."*
##
## Half of that was already built and I nearly rebuilt it - `_auto_equip_tool_replacement` has been
## swapping in your best spare for a long time. The real gap was that nothing told you a spare
## EXISTED until the break happened. So the Tools panel now says `(2 spares)`.
##
## ⚡ WHICH IS THE DANGEROUS KIND OF FEATURE. A panel counting spares by its own rule is the
## "one value, two places" shape that has caused nearly every wrong-text bug in this codebase, and
## the failure here is specific and nasty: the panel promises a backup the game will not reach for,
## so a player walks into a gathering run believing they are covered. Both sides now ask
## `Character.tool_spares`.
##
## WHAT THIS ASSERTS:
##   1. the rule behaves - a broken spare is not a spare, a different subtype is not a spare
##   2. the one it names FIRST is the highest tier, which is the one that gets equipped
##   3. ⚑ BOTH SITES REALLY CALL IT - the server's replacement and the client's panel. Matched on
##      the CALL, not on the word appearing nearby: this exact probe shape passed twice this week
##      while reading a COMMENT about a check instead of the check.
##
## Run:
##   godot --headless --path . --script res://tools/probe/the_panel_counts_the_spare_you_get.gd

const CharacterScript := preload("res://shared/character.gd")

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


func _tool(subtype: String, tier: int, dur: int) -> Dictionary:
	return {"type": "tool", "subtype": subtype, "tier": tier, "durability": dur, "max_durability": 20}


func _init() -> void:
	print("")
	print("===== 1. WHAT COUNTS AS A SPARE =====")
	var inv: Array = [
		_tool("pickaxe", 1, 20),
		_tool("pickaxe", 4, 12),          # the best one, deliberately NOT first in the pack
		_tool("pickaxe", 5, 0),           # BROKEN - the thing the player is being told to replace
		_tool("axe", 3, 20),              # a different slot entirely
		{"type": "weapon", "subtype": "pickaxe", "tier": 9, "durability": 20},   # not a tool
	]
	var spares: Array = CharacterScript.tool_spares(inv, "pickaxe")
	print("  pack holds 3 pickaxes (T1 intact, T4 intact, T5 broken), 1 axe, 1 weapon")
	print("  tool_spares(pickaxe) -> %s" % str(spares))
	if spares.size() != 2:
		_fail("counted %d pickaxe spares, expected 2 (the broken one is not a spare)" % spares.size())
	else:
		_ok("a broken tool in the pack is not counted as a backup")
	if spares.size() > 0 and int(inv[spares[0]].get("tier", 0)) != 4:
		_fail("the first spare is T%d, but the game equips the HIGHEST tier (T4)"
			% int(inv[spares[0]].get("tier", 0)))
	elif spares.size() > 0:
		_ok("the first one named is the highest tier - the one that would be equipped")
	if CharacterScript.tool_spares(inv, "axe").size() != 1:
		_fail("the axe count picked up something that is not an axe")
	else:
		_ok("a different slot's tools are not counted")
	if not CharacterScript.tool_spares(inv, "sickle").is_empty():
		_fail("a slot with nothing in the pack still reported a spare")
	else:
		_ok("no sickle in the pack reads as no sickle spare")

	print("")
	print("===== 2. AN EMPTY OR RAGGED PACK DOES NOT BREAK IT =====")
	if not CharacterScript.tool_spares([], "pickaxe").is_empty():
		_fail("an empty pack reported a spare")
	else:
		_ok("an empty pack reports nothing")
	# A pack can carry nulls and non-dictionaries through a bad deserialize; a status panel is the
	# worst place to learn that, because it redraws on every character_update.
	if not CharacterScript.tool_spares([null, 7, "x"], "pickaxe").is_empty():
		_fail("a ragged pack reported a spare")
	else:
		_ok("a ragged pack reports nothing instead of erroring")

	print("")
	print("===== 3. BOTH SIDES ASK THE SAME FUNCTION =====")
	# ⛑ MATCHED ON THE CALL, NOT THE WORD. The healer probe and the canvas-heal probe both passed
	# this week while matching a COMMENT that happened to name the thing being checked. A comment
	# cannot contain `Character.tool_spares(` followed by an argument list, so that is what is
	# required here.
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	var cli := FileAccess.get_file_as_string("res://client/client.gd")
	var i := srv.find("func _auto_equip_tool_replacement(")
	if i < 0:
		_fail("_auto_equip_tool_replacement is gone - a broken tool no longer replaces itself")
	else:
		var j := srv.find("\nfunc ", i + 8)
		var body := srv.substr(i, (j - i) if j > i else 3000)
		if body.find("Character.tool_spares(character.inventory,") < 0:
			_fail("the server picks its replacement with its OWN loop again - the panel's count "
				+ "and the tool you actually get can now disagree")
		else:
			_ok("the server's replacement is chosen by Character.tool_spares")
	var k := cli.find("func update_tool_status_overlay(")
	if k < 0:
		_fail("update_tool_status_overlay is gone - there is no Tools panel to count on")
	else:
		var j2 := cli.find("\nfunc ", k + 8)
		var body2 := cli.substr(k, (j2 - k) if j2 > k else 6000)
		if body2.find("CharacterScript.tool_spares(") < 0:
			_fail("the Tools panel no longer asks CharacterScript.tool_spares - it is counting "
				+ "spares by some other rule than the one that equips them")
		else:
			_ok("the Tools panel counts with CharacterScript.tool_spares")
		if body2.find("spare") < 0:
			_fail("the panel says nothing about spares at all - the owner's actual complaint")

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS the Tools panel counts spares by the same rule that equips them, and a")
	print("       broken tool in the pack is not offered as a backup.")
	quit()
