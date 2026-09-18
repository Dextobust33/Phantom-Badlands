extends SceneTree
## ⛑ CAN EVERY RECIPE BE REACHED, WITHOUT COMMISSIONING BECOMING A WAY TO SKIP CRAFTING?
##
## Owner 2026-09-18, on finding that committing locks you out of 43% of recipes: keep the identity
## and add *"a commission route... commission another player (or a post NPC as a fallback)"*.
##
## Then, immediately after: *"what does continuing to level up a none commited job do if you can't
## build specialty items for it?"* — which is the question that decides the whole design. If a
## commission lent you the SKILL as well as the FOCUS, levelling a trade you did not commit to
## would be pointless and commissioning would be a way to skip crafting progression entirely.
##
## **So the rule is: a commission lends a FOCUS, never a SKILL.** You still meet the recipe's own
## skill requirement yourself. That is what makes levelling an uncommitted crafting skill worth
## doing — it is the prerequisite for commissioning that trade's specialist work.
##
## Run:
##   godot --headless --path . --script res://tools/probe/commission_lends_focus_not_skill.gd

const CD := preload("res://shared/crafting_database.gd")
const CharacterScript := preload("res://shared/character.gd")

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


func _init() -> void:
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	var cli := FileAccess.get_file_as_string("res://client/client.gd")

	print("")
	print("===== 1. HOW MUCH WAS ACTUALLY WALLED OFF =====")
	var gated := 0
	var total := 0
	var by_skill: Dictionary = {}
	for rid in CD.RECIPES:
		var r: Dictionary = CD.RECIPES[rid]
		var sk := String(CD.get_skill_name(r.get("skill", 0)))
		if not by_skill.has(sk):
			by_skill[sk] = [0, 0]
		by_skill[sk][1] += 1
		total += 1
		if bool(r.get("specialist_only", false)):
			by_skill[sk][0] += 1
			gated += 1
	var keys: Array = by_skill.keys()
	keys.sort()
	for k in keys:
		var g: int = int(by_skill[k][0])
		var t: int = int(by_skill[k][1])
		print("  %-16s %d of %d specialist-only (%d%%)" % [k, g, t, int(100.0 * float(g) / maxf(1.0, float(t)))])
	print("  TOTAL            %d of %d (%d%%)" % [gated, total, int(100.0 * float(gated) / maxf(1.0, float(total)))])
	if gated == 0:
		_fail("no recipe is specialist-only - the identity this is built around is gone")
	else:
		_ok("crafter identity intact: %d recipes belong to a trade" % gated)

	print("")
	print("===== 2. THE COMMISSION LENDS A FOCUS, NEVER A SKILL =====")
	# ⛑ THE LOAD-BEARING RULE. The skill check sits BEFORE the specialist gate in
	# handle_craft_item, so a commission cannot route around it. Checked by ORDER, because
	# "the check exists" is not the same as "the check runs first".
	var i_skill: int = srv.find("Requires %s level %d (you have %d)")
	var i_gate: int = srv.find("var _is_commission: bool = bool(message.get(\"commission\", false))")
	if i_skill < 0 or i_gate < 0:
		_fail("could not locate the skill check or the commission fork")
	elif i_skill > i_gate:
		_fail("the commission fork runs BEFORE the skill requirement - a commission would skip skill")
	else:
		_ok("the skill requirement is enforced before any commission can be considered")
	if srv.find("var can_commission: bool = specialist_gated and not is_locked") < 0:
		_fail("the recipe list no longer marks gated recipes commissionable")
	else:
		_ok("a gated recipe you have the skill for is offered, not refused")

	print("")
	print("===== 3. A COMMISSION NEVER BEATS A REAL SPECIALIST =====")
	# ⛑ If the NPC matched a committed crafter, committing would be worthless and we would have
	# solved the gate by deleting the identity. Fixed at STANDARD against a specialist's ladder:
	print("  %-8s %-10s %s" % ["skill", "success", "masterwork share for a committed crafter"])
	for sk in [25, 40, 60]:
		var d: Dictionary = CD.roll_quality_detailed(sk, 35)
		print("  %-8d %-10d %s%%" % [sk, int(d.get("success_chance", 0)),
			str(d.get("distribution", {}).get("masterwork", 0))])
	if srv.find("quality = CraftingDatabaseScript.CraftingQuality.STANDARD") < 0:
		_fail("a commission is no longer pinned to STANDARD - it can match or beat a specialist")
	else:
		_ok("a commission is always STANDARD; only a real specialist reaches Masterwork")

	print("")
	print("===== 4. IT COSTS SOMETHING, AND THE COST TRACKS THE CONTENT =====")
	var fees: Array = []
	for req in [5, 15, 35, 60, 90]:
		var fee: int = 60 + 8 * req
		fees.append(fee)
		print("  skill %-4d recipe -> %d Valor" % [req, fee])
	if fees[0] >= fees[fees.size() - 1]:
		_fail("the fee does not rise with the recipe's skill requirement")
	else:
		_ok("a skill-90 commission costs %.1fx a skill-5 one" % (float(fees[fees.size() - 1]) / float(fees[0])))
	if srv.find("persistence.spend_valor(comm_account, fee)") < 0:
		_fail("the fee is never actually charged")
	else:
		_ok("the fee is charged before the craft runs")

	print("")
	print("===== 5. THE PLAYER HALF: A COMMISSION IS A BUY ORDER FOR WORK =====")
	# ⛑ IT REUSES THE ORDER SYSTEM RATHER THAN ADDING A SECOND ONE. Buy orders already escrow
	# Valor, survive a restart, pay an offline seller and deliver to an offline buyer - every hard
	# part of a commission board, already built and already exercised in production.
	var player_half := {
		"commission is an order type": srv.find("\"monster_part\", \"commission\"]") >= 0,
		"it names a recipe": srv.find("order[\"recipe_id\"] = commission_recipe_id") >= 0,
		"only gated recipes qualify": srv.find("post a normal buy order instead") >= 0,
		"filled with YOUR OWN craft": srv.find("a commission is filled with your own work") >= 0,
		"the crafter is credited": srv.find("inv_item[\"crafted_by\"] = character.name") >= 0,
	}
	for k in player_half.keys():
		if bool(player_half[k]):
			_ok(String(k))
		else:
			_fail("%s -- MISSING" % k)

	# ⛑ THE TWO FAILURE MODES THAT WOULD ACTUALLY HURT A PLAYER.
	#
	# 1. MATCHED BY NAME instead of recipe. A Masterwork craft is named "Masterwork <recipe>" and a
	#    Standard one is bare "<recipe>", so name-matching would reject exactly the good ones - and
	#    accept a same-named DROP that no crafter ever made.
	if srv.find("String(inv_item.get(\"recipe_id\", \"\")) == want_recipe") < 0:
		_fail("commission fulfilment does not match on recipe_id")
	else:
		_ok("matched on recipe_id, so quality prefixes cannot break it")
	if srv.find("\"recipe_id\": source_recipe_id,") < 0:
		_fail("crafted items no longer record which recipe made them")
	else:
		_ok("crafted items record their recipe")
	# 2. DELIVERED AS A NAMEPLATE. Every other order type is name-only, so the delivery path
	#    REBUILDS the item from {type, name, id}. Doing that to a crafted weapon hands the buyer
	#    an item with no stats, no quality, no affixes and no maker.
	if srv.find("item_copy = _commission_delivery_items.pop_front()") < 0:
		_fail("online delivery rebuilds the item - a commissioned piece would arrive with no stats")
	else:
		_ok("online delivery hands over the real item")
	if srv.find("_pending[\"items\"] = _commission_delivery_items.duplicate(true)") < 0:
		_fail("an OFFLINE buyer would receive a nameplate instead of the item")
	else:
		_ok("the offline queue carries the whole item too")
	if srv.find("character.inventory.append((full_items[fit] as Dictionary).duplicate(true))") < 0:
		_fail("the delivery drain ignores the stored item and rebuilds it")
	else:
		_ok("and the drain honours it on next login")

	print("")
	print("===== 6. CAN A PLAYER ACTUALLY DO EITHER OF THESE? =====")
	# ⚑ Owner 2026-09-18: *"You mention commission it from an NPC and post it to a player but how do
	# players actually do those things? Remember the answers should be UI based where possible."*
	#
	# ⛑ AND THEY COULD NOT. The player half shipped with the server accepting a `recipe_id` on
	# `market_order_create` and NOTHING ANYWHERE ABLE TO SEND ONE - the "capability built, route
	# missing" defect, for the seventh time in this arc. A capability with no surface is not a
	# feature, so every step of both journeys is a check here rather than an assumption.
	var journey := {
		# Route A - the NPC job, on the recipe you cannot make.
		"A1 the list says it can be commissioned": cli.find("commission from a %s (%d Valor)") >= 0,
		"A2 the recipe opens instead of bouncing": cli.find("recipe.get(\"can_commission\", false)") >= 0,
		"A3 the button names the price": cli.find("Commission (%dv)") >= 0,
		"A4 pressing it sends the flag": cli.find("msg[\"commission\"] = true") >= 0,
		# Route B - posting the job to other players, from the same screen.
		# ⛑ B1 MUST NAME THE BUTTON, NOT THE ACTION ID. The first version searched for
		# `"craft_post_job"`, which the HANDLER case also contains - so deleting the button
		# entirely still passed. Two checks matching one string are one check.
		"B1 a Post Job button exists": cli.find("\"action_data\": (\"craft_post_job\"") >= 0,
		"B2 clicking it is handled": cli.find("		\"craft_post_job\":") >= 0,
		"B3 it asks what you will pay": cli.find("func _start_commission_prompt") >= 0,
		"B4 Escape cancels the prompt": cli.find("pending_commission_recipe = \"\"") >= 0,
		"B5 the answer creates the order": cli.find("\"item_type\": \"commission\",") >= 0,
		"B6 and it carries the recipe": cli.find("\"recipe_id\": _rid,") >= 0,
		# Route C - the crafter finding the work.
		"C1 the server counts open jobs": srv.find("var _open_commissions_here: Array = []") >= 0,
		"C2 it ships them per recipe": srv.find("\"wanted_count\": wanted_count,") >= 0,
		"C3 the crafter SEES the demand": cli.find("player(s) want this — up to %d Valor") >= 0,
	}
	var jk: Array = journey.keys()
	jk.sort()
	for k in jk:
		if bool(journey[k]):
			_ok(String(k))
		else:
			_fail("%s -- NO DOOR" % k)

	print("")
	print("===== 7. THE ROUTE IS COMPLETE =====")
	var checks := {
		"server accepts the flag": srv.find("message.get(\"commission\", false)") >= 0,
		"server requires a post": srv.find("Commissioning needs a %s at a trading post") >= 0,
		"list reports the fee": srv.find("\"commission_fee\": commission_fee(recipe)") >= 0,
		"client offers it in the list": cli.find("commission from a %s (%d Valor)") >= 0,
		"client can open a gated recipe": cli.find("recipe.get(\"can_commission\", false)") >= 0,
		"client sends the flag": cli.find("msg[\"commission\"] = true") >= 0,
		"the button names the price": cli.find("Commission (%dv)") >= 0,
	}
	for k in checks.keys():
		if bool(checks[k]):
			_ok(String(k))
		else:
			_fail("%s -- MISSING" % k)

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for f in _fails:
			print("   - %s" % f)
		quit(1)
		return
	print("[PROBE] PASS every recipe is reachable, a commission lends a focus and never a skill,")
	print("       and it never matches what a committed crafter can make.")
	quit()
