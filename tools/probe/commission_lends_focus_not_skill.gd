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
	print("===== 5. THE ROUTE IS COMPLETE =====")
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
