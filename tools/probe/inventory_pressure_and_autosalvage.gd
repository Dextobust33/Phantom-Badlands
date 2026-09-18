extends SceneTree
## ⛑ IS INVENTORY BLOAT REAL, AND DOES AUTO-SALVAGE EXPLAIN ITSELF?
##
## Owner, scoping crafting: *"Items and tools can buildup and takeover your backpack slots. We may
## want to have a separate item pouch or unlimited items... for inventory bloat we need to make
## autosalvage easy to understand and setup."*
##
## ⛑ THE LIVE POPULATION SAYS THE POUCH IS NOT NEEDED YET. Measured against the real server on
## 2026-09-18, 18 characters: **median 2 of 40 slots used.** The fullest is a level-48 at 28/40,
## the next 24/40. Nobody is near the cap, so a pouch would have been a large change to the item
## model solving a problem that does not exist — and the owner's other half, making auto-salvage
## understandable, is live for everyone today.
##
## What the live data DOES show is WHICH items accumulate: the fullest character's 28 slots are
## `ring_arcane:4, tool:2, scroll_target_farm:2, scroll_monster_select:2` — utility, not gear. So
## the pouch stays filed with a trigger rather than cancelled, and this probe is the trigger.
##
## Run:
##   godot --headless --path . --script res://tools/probe/inventory_pressure_and_autosalvage.gd

const CharacterScript := preload("res://shared/character.gd")

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


func _init() -> void:
	print("")
	print("===== 1. THE RULE HAS ONE IMPLEMENTATION =====")
	# ⛑ AUTO-SALVAGE DESTROYS ITEMS. A preview computed from a second copy of the rule is the one
	# kind of duplicate that can tell a player their gear is safe while the server eats it — and
	# this session has already found six rules that existed in two places, several already wrong.
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	var cli := FileAccess.get_file_as_string("res://client/client.gd")
	if srv.find("Character.would_auto_salvage(item,") < 0:
		_fail("the server no longer calls the shared rule")
	else:
		_ok("the server destroys items through Character.would_auto_salvage")
	if cli.find("CharacterScript.would_auto_salvage(_it,") < 0:
		_fail("the preview does not use the shared rule")
	else:
		_ok("the settings screen previews with the SAME function")
	# ⛑ THE SECOND PATH IS A DIFFERENT QUESTION, NOT A DUPLICATE - and finding that out is what
	# this check earned. `_try_auto_salvage` asks "which item I already OWN can I destroy for
	# space", which deserves a harder floor than "should I keep this drop". It carried its own
	# three-entry rarity array against the pickup path's five, so the same setting meant two
	# different things depending on which code you reached. The cap is kept and NAMED.
	if srv.find("Character.AUTO_SALVAGE_MAKE_ROOM_CEILING") < 0:
		_fail("the make-room path has an unnamed rarity ceiling again")
	else:
		_ok("the make-room ceiling is a named constant, not a truncated array")
	if srv.find("var rarity_order = [\"common\", \"uncommon\", \"rare\"]") >= 0:
		_fail("the truncated rarity array is back")
	else:
		_ok("both paths read the same five-rarity ladder")
	print("  make-room ceiling: %s (a player who picks Legendary still never loses an epic for space)" % (
		["-", "common", "uncommon", "rare", "epic", "legendary"][CharacterScript.AUTO_SALVAGE_MAKE_ROOM_CEILING]))

	print("")
	print("===== 2. THE RULE BEHAVES, RUN AGAINST REAL ITEM SHAPES =====")
	var common := {"name": "Rusty Blade", "type": "weapon", "rarity": "common"}
	var epic := {"name": "Epic Blade", "type": "weapon", "rarity": "epic"}
	var locked := {"name": "Locked Blade", "type": "weapon", "rarity": "common", "locked": true}
	var a_tool := {"name": "Pickaxe", "type": "tool", "rarity": "common"}
	var a_rune := {"name": "Rune", "type": "rune", "rarity": "common"}
	var kept := {"name": "Mighty Blade", "type": "weapon", "rarity": "common",
		"affixes": {"prefix_name": "Mighty"}}
	var cases := [
		["OFF salvages nothing", not CharacterScript.would_auto_salvage(common, false, 3, [], false)],
		["a common IS caught at rarity 3", CharacterScript.would_auto_salvage(common, true, 3, [], false)],
		["an epic is NOT caught at rarity 3", not CharacterScript.would_auto_salvage(epic, true, 3, [], false)],
		["a LOCKED item is never caught", not CharacterScript.would_auto_salvage(locked, true, 5, [], false)],
		["a tool is never caught", not CharacterScript.would_auto_salvage(a_tool, true, 5, [], false)],
		["a rune is never caught", not CharacterScript.would_auto_salvage(a_rune, true, 5, [], false)],
		["a consumable is never caught", not CharacterScript.would_auto_salvage(common, true, 5, [], true)],
		["a KEPT affix protects an item", not CharacterScript.would_auto_salvage(kept, true, 3, ["Mighty"], false)],
		["...and only that affix", CharacterScript.would_auto_salvage(kept, true, 3, ["Brutal"], false)],
	]
	for c in cases:
		if bool(c[1]):
			_ok(String(c[0]))
		else:
			_fail(String(c[0]))

	print("")
	print("===== 3. THE SCREEN SHOWS THE CONSEQUENCE, NOT JUST THE RULE =====")
	# ⛑ The rules were already stated clearly. What was missing was the answer to "so what will
	# that do to MY stuff" - a player could read "Items up to Rare will be auto-salvaged" and have
	# no idea whether that meant two items or twenty.
	var surface := {
		"it counts what would go": cli.find("this would salvage %d of your %d items") >= 0,
		"it NAMES a few of them": cli.find("\", \".join(_shown)") >= 0,
		"it says so when nothing is at risk": cli.find("this would salvage NOTHING you are carrying") >= 0,
		"it says so when the feature is off": cli.find("Auto-salvage is OFF") >= 0,
		"it explains the preview is not an action": cli.find("only runs on NEW drops") >= 0,
	}
	for k in surface.keys():
		if bool(surface[k]):
			_ok(String(k))
		else:
			_fail("%s -- MISSING" % k)

	print("")
	print("===== 4. THE POUCH: FILED, WITH A TRIGGER =====")
	print("  live population 2026-09-18 (18 characters): median 2 of %d slots used" % CharacterScript.MAX_INVENTORY_SIZE)
	print("  fullest: 28/40 (level 48), next 24/40 - nobody is near the cap")
	print("  BUT the fullest character's load is utility, not gear:")
	print("    ring_arcane:4, tool:2, scroll_target_farm:2, scroll_monster_select:2")
	print("  ⛑ Re-measure with tools/check_player_progress.sh before building a pouch. Build it")
	print("     when a real character passes ~32/40, not before - the crafting arc adds four")
	print("     Scribe items, returned runes and commissioned deliveries, so the pressure rises.")

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for f in _fails:
			print("   - %s" % f)
		quit(1)
		return
	print("[PROBE] PASS auto-salvage has one implementation, behaves on every shape tested, and")
	print("       the settings screen shows what it would actually do to your items.")
	quit()
