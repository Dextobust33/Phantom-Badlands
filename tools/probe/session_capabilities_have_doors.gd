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
