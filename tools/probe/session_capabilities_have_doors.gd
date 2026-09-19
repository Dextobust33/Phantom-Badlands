extends SceneTree
## ⛑ FOR EVERYTHING BUILT THIS SESSION: CAN A PLAYER ACTUALLY REACH IT?
##
## Owner 2026-09-18, after catching that the player-commission half had no UI at all: *"You might
## want to do a similar check for other work completed this session to ensure players can actually
## interact with or make use of things implemented."*
##
## ⛑ THIS ARC HAS SHIPPED A CAPABILITY WITH NO DOOR **SEVEN TIMES**: party invite, Duel for Valor,
## the fight log, the death log, the Bestiary Page, the bestiary reader, and the player commission.
## The failure is always invisible from the server side — the handler is correct, the data is
## right, and nothing on screen can reach it. So this probe treats "is there a surface" as the
## thing under test, once, for the whole session's work.
##
## ⛑ AND IT CHECKS THE SURFACE, NOT THE ID. A check that greps for an action id matches the
## HANDLER as well as the button, so deleting the button passes it — that happened here on
## 2026-09-18 and is why every UI check below names the button form (`"action_data": "x"`) or the
## rendered text a player would actually see.
##
## Run:
##   godot --headless --path . --script res://tools/probe/session_capabilities_have_doors.gd

var _fails: Array = []
var _cli: String = ""
var _srv: String = ""
var _chr: String = ""


func _fail(m: String) -> void:
	_fails.append(m)
	print("    FAIL  %s" % m)


func _ok(m: String) -> void:
	print("    ok    %s" % m)


## One capability: it must EXIST on the server and be REACHABLE from a surface.
func _capability(title: String, server_proof: String, doors: Dictionary) -> void:
	print("")
	print("  %s" % title)
	if server_proof != "" and _srv.find(server_proof) < 0 and _chr.find(server_proof) < 0:
		_fail("the capability itself is gone (%s)" % server_proof)
		return
	for label in doors.keys():
		if bool(doors[label]):
			_ok(String(label))
		else:
			_fail("%s -- NO DOOR" % label)


func _init() -> void:
	_cli = FileAccess.get_file_as_string("res://client/client.gd")
	var _panel := FileAccess.get_file_as_string("res://client/crafting_panel.gd")
	var _invp := FileAccess.get_file_as_string("res://client/inventory_panel.gd")
	_srv = FileAccess.get_file_as_string("res://server/server.gd")
	_chr = FileAccess.get_file_as_string("res://shared/character.gd")

	print("")
	print("===== EVERY CAPABILITY BUILT 2026-09-18, AND THE WAY IN =====")

	_capability("SPECIALIST FIELD SERVICES (5, one per crafting focus)",
		"func handle_specialist_service(", {
			"a button on the Jobs screen": _cli.find("\"action_data\": \"specialist_service\"") >= 0,
			"a second button for an adjacent ally": _cli.find("\"specialist_service_ally\"") >= 0,
			"the label is read off the real table": _cli.find("CharacterScript.SPECIALIST_SERVICES.get(_sj") >= 0,
			"the click is handled": _cli.find("\t\t\"specialist_service\":") >= 0,
		})

	_capability("REWORK A STAT (the affix reroll loop)",
		"func handle_affix_reroll(", {
			# ⛑ NAMES THE ENTRY BUTTON, NOT THE ACTION ID. `rework_start` is also on a "Pick Item"
			# button INSIDE the rework flow - which is only reachable from this one - so checking
			# the id alone passed while the way in was deleted. A door you can only open from
			# behind is not a door.
			"a Rework button on the inventory bar":
				_cli.find("{\"label\": \"Rework\", \"action_type\": \"local\", \"action_data\": \"rework_start\"") >= 0,
			"the enchanter's field button opens the same panel": _cli.find("\"open_affix_rework\":") >= 0,
			"an item picker": _cli.find("func _display_rework_item_picker") >= 0,
			"a stat picker showing the cost": _cli.find("func _display_rework_quote") >= 0,
			"the cap is shown BEFORE committing": _cli.find("Reworks used: %d of %d") >= 0,
		})

	_capability("COMMISSION — the NPC route",
		"func commission_fee(", {
			"the recipe list offers it": _cli.find("commission from a %s (%d Valor)") >= 0,
			"the button names the price": _cli.find("Commission (%dv)") >= 0,
			"the client sends the flag": _cli.find("msg[\"commission\"] = true") >= 0,
		})

	_capability("COMMISSION — the player route",
		"\"monster_part\", \"commission\"]", {
			"a Post Job button": _cli.find("\"action_data\": (\"craft_post_job\"") >= 0,
			"it asks what you will pay": _cli.find("func _start_commission_prompt") >= 0,
			"the order carries the recipe": _cli.find("\"recipe_id\": _rid,") >= 0,
			"a crafter SEES the demand": _cli.find("player(s) want this — up to %d Valor") >= 0,
		})

	_capability("JOBS LEVEL FREELY, COMMITTING PAYS +50%",
		"func job_xp_multiplier(", {
			"the gathering hint sells the bonus": _cli.find("commit one at a trading post for +50%% XP in it") >= 0,
			"the specialty hint does too": _cli.find("for +50%% XP, its recipes and its field service") >= 0,
			"the commit screen lists what you gain": _cli.find("XP whenever you work %s") >= 0,
			"the committed job is marked": _cli.find("★ COMMITTED  [color=#FFD700]+50%% XP") >= 0,
			"no screen still says LOCKED": _cli.find("✗ LOCKED") < 0,
			"the help page describes the new rule": _cli.find("Level them all freely.") >= 0,
		})

	_capability("SAFE PASSAGE (Make Camp + two Scribe scrolls)",
		"safe_passage_steps", {
			"the HUD shows how many steps are left": _cli.find("🛡 Unnoticed %d") >= 0,
			"and in a safe zone too, so it never appears from nowhere":
				_cli.find("[color=#00FF00]Safe Zone[/color]\" + passage_tag") >= 0,
		})

	_capability("DISENCHANT RETURNS YOUR RUNES",
		"func _remember_applied_rune(", {
			"the result names the runes returned": _srv.find("Runes returned: %s") >= 0,
			"it explains an EMPTY result rather than going quiet":
				_srv.find("Gear enchanted before this update kept no record") >= 0,
			"a full pack is reported, not silently eaten": _srv.find("rune(s) lost") >= 0,
		})

	_capability("THE TOWN BLACKSMITH NO LONGER UPGRADES",
		"Enchanter's work", {
			"the screen says where enhancing went": _cli.find("no longer enhances gear") >= 0,
			"it points at the replacement": _cli.find("Inventory → Rework") >= 0,
			"the dead button is gone": _cli.find("\"action_data\": \"blacksmith_upgrade\"") < 0,
		})

	_capability("TWO NEW MATERIAL SINKS (ice crystal, rock salt)",
		"", {
			"Refine Ice Crystal is a real recipe":
				FileAccess.get_file_as_string("res://shared/crafting_database.gd").find("\"refine_ice_crystal\"") >= 0,
			"Refine Rock Salt is a real recipe":
				FileAccess.get_file_as_string("res://shared/crafting_database.gd").find("\"refine_rock_salt\"") >= 0,
		})

	print("")
	print("===== THE DOOR MUST BE ON THE SURFACE THE GAME ACTUALLY SHOWS =====")
	# ⚑ THE MOST EXPENSIVE MISTAKE OF THIS SESSION. Owner 2026-09-18, testing the crafting arc:
	# *"Action bar buttons? They should be UI buttons."* ... *"I left clicked Iron sword and don't
	# see any description about attack or comparing my weapon."* ... *"All I see are the locked
	# items that I can't click."*
	#
	# ⛑ EVERY ONE OF THOSE WAS ONE FAULT: the whole crafting UI redesign went into `client.gd`'s
	# TEXT renderers - `display_craft_recipe_list`, `display_craft_recipe_details`, the action bar -
	# and `client/crafting_panel.gd` had replaced all three. The panel is shown whenever
	# `crafting_mode` is on, so the player never saw a single line of it.
	#
	# And the probe PASSED, because it grepped client.gd for the strings and found them - in the
	# dead path. A door in a room nobody enters is not a door, and checking client.gd cannot tell
	# the difference. **When a screen has a panel, the panel IS the screen.**
	print("")
	print("  CRAFTING — the panel, not the text fallback")
	var panel_doors := {
		"filters are panel BUTTONS": _panel.find("_filter_buttons[String(f[\"id\"])] = fb") >= 0,
		"each filter shows its count": _panel.find("btn.text = \"%s (%d)\"") >= 0,
		"the panel owns the filtering": _panel.find("func _apply_filter") >= 0,
		"gated rows are CLICKABLE when commissionable": _panel.find("if recipe.get(\"can_commission\", false):") >= 0,
		# ⚡ THE TWO ROUTES ARE NAMED FOR WHAT THEY DO (2026-09-18). Both used to say "commission",
		# which made the skill-gated NPC route look like the general answer - the owner went looking
		# for it four times and found a dead end. The NPC route lends a FOCUS and needs your skill;
		# the player route needs nothing and works at any level, so it is listed first.
		"the craft button names the tradesman": _panel.find("_craft_button.text = \"Hire a %s") >= 0,
		"the player route says it is a player": _panel.find("_post_job_button.text = \"Ask a Player to Make This\"") >= 0,
		"and the LIST says which route a row has": _panel.find("· ask a player") >= 0,
		"the detail says what it MAKES": _panel.find("[color=#87CEEB]Makes:[/color]") >= 0,
		"and compares it to what you wear": _panel.find("vs your %s:") >= 0,
		"demand is shown on rows you can make": _panel.find("◆ %d wanted, up to %dv") >= 0,
	}
	for k in panel_doors.keys():
		if bool(panel_doors[k]):
			_ok(String(k))
		else:
			_fail("%s -- IN THE TEXT PATH ONLY" % k)
	# ⛑ AND THE INDEX MUST SURVIVE FILTERING. The panel shows a filtered list while the client
	# indexes the unfiltered one, so emitting the filtered position would craft a DIFFERENT recipe
	# than the one clicked - silently, and only while a filter is active.
	if _panel.find("_src_index.append(i)") < 0:
		_fail("the panel does not map filtered rows back to the client's indices")
	else:
		_ok("a filtered row still crafts the recipe you clicked")

	print("")
	print("  REWORK — the result has to survive the next character_update")
	# Owner: *"Rework screen pulled up some text then it disappears."* The Player-Visible Output
	# Rule in CLAUDE.md names this exact step and it was skipped.
	if _cli.find("elif pending_inventory_action in [\"rework_select\", \"rework_stat\"]:") < 0:
		_fail("the rework modes still fall through to display_inventory() and get wiped")
	else:
		_ok("rework modes bypass the inventory refresh")

	print("")
	print("===== CAPABILITIES THAT NEED NO NEW DOOR =====")
	# ⛑ LISTED, NOT SKIPPED. Saying WHY something is exempt is what stops the exemption quietly
	# growing to cover things that do need one.
	print("  compass axis fix ........ corrects existing text on surfaces players already read")
	print("  reforge band fix ........ an existing recipe; the result message already reports it")
	print("  wish upgrade rebalance .. an existing reward; the wish screen already announces it")
	print("  extract rate fix ........ an existing recipe; output quantity is shown in the result")
	print("  uncapped-growth removals. the absence of a thing needs no button")

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d capability(ies) a player cannot reach:" % _fails.size())
		for f in _fails:
			print("   - %s" % f)
		quit(1)
		return
	print("[PROBE] PASS every capability built this session has a surface a player can reach,")
	print("       and each check names the button or the rendered text rather than an action id.")
	quit()
