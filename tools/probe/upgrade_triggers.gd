extends SceneTree
## An upgrade must say when it is worth using, and the card must show it.
##
## Owner 2026-09-11: *"Situational can be good but only if there is a clear answer to how to use
## them properly and make it easily apparent in combat when it's worth using. If not it all
## becomes micro-management and feels like dead options."*
##
## The audit (`upgrade_variety.gd`) found the triggers were NOT the hidden part - 9 of the 15
## conditional upgrades already key off something on screen. What was missing was any link
## between that state and the card: the condition lived only in English prose, and a card in hand
## showed nothing about what it carried.
const CU := preload("res://shared/card_upgrades.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _u(id: String) -> Dictionary:
	return CU.upgrade_by_id(id)


func _init() -> void:
	print("--- the condition is DATA now, not prose ---")
	var tagged := 0
	for u in CU.UPGRADES:
		if CU.trigger_of(u) != CU.TRIGGER_NONE:
			tagged += 1
	ck(tagged == 24, "24 of %d upgrades carry a machine-readable trigger - got %d" % [
		CU.UPGRADES.size(), tagged])
	# Every conditional upgrade the audit named must be tagged. A trigger that exists only in the
	# description is exactly the state this work is undoing.
	for id in ["executioner", "bulwark", "desperate", "kindling", "all_in", "harrying",
			"demoralising", "opener", "opening_act", "relentless", "refund", "vindication",
			"reveal_engine", "reveal_ward", "reveal_spark"]:
		ck(CU.trigger_of(_u(id)) != CU.TRIGGER_NONE, "'%s' declares its trigger" % id)
	# ...and the thresholds must match what the SERVER actually rolls against.
	ck(float(_u("executioner").get("at", 0)) == 0.30, "Executioner's 30% matches combat_manager")
	ck(float(_u("bulwark").get("at", 0)) == 0.50, "Bulwark's half matches combat_manager")
	ck(float(_u("desperate").get("at", 0)) == 0.34, "Desperation's 34% matches combat_manager")

	print("\n--- and it evaluates against real combat state ---")
	ck(CU.trigger_live(_u("executioner"), {"foe_hp_pct": 0.22}), "Executioner lights at foe 22%")
	ck(not CU.trigger_live(_u("executioner"), {"foe_hp_pct": 0.55}), "...and not at 55%")
	ck(CU.trigger_live(_u("bulwark"), {"self_hp_pct": 0.30}), "Bulwark lights below half")
	ck(not CU.trigger_live(_u("desperate"), {"self_hp_pct": 0.40}),
		"Desperation does NOT light at 40% - its bar is 34%, and the two must not be conflated")
	ck(CU.trigger_live(_u("kindling"), {"resource_pct": 1.0}), "Kindling lights on a full bar")
	ck(not CU.trigger_live(_u("kindling"), {"resource_pct": 0.9}), "...and not at 90%")
	ck(CU.trigger_live(_u("all_in"), {"resource_pct": 0.2}), "All In lights on a low bar")
	ck(CU.trigger_live(_u("harrying"), {"foe_stunned": true}), "Harrying lights while the foe is stunned")
	ck(CU.trigger_live(_u("opener"), {"card_casts": 0}), "Opener lights on the first cast")
	ck(not CU.trigger_live(_u("opener"), {"card_casts": 1}), "...and not on the second")
	ck(CU.trigger_live(_u("relentless"), {"card_casts": 2}),
		"Relentless lights on the cast that COMPLETES the third, not the one after")
	ck(not CU.trigger_live(_u("relentless"), {"card_casts": 1}), "...and not on the second")

	print("\n--- an unknown fact must UNDER-light, never over-claim ---")
	# A missing key means the caller cannot tell. Lighting up on a guess would be worse than
	# staying dark: the player is about to spend a turn on it.
	for id in ["executioner", "bulwark", "kindling", "opener", "relentless", "harrying"]:
		ck(not CU.trigger_live(_u(id), {}), "'%s' stays dark when the state is unknown" % id)
	# Always-on and pure-chance never light: if everything glows, nothing does.
	ck(not CU.trigger_live(_u("power"), {"foe_hp_pct": 0.1, "self_hp_pct": 0.1, "card_casts": 0}),
		"an always-on upgrade never lights - it is not a thing you time")
	ck(not CU.trigger_live(_u("keen"), {"foe_hp_pct": 0.1}),
		"a pure-chance upgrade never lights - variance is not a decision")

	print("\n--- every trigger has a plain-language hint, and always-on has none ---")
	for id in ["executioner", "bulwark", "kindling", "all_in", "harrying", "opener",
			"relentless", "refund", "reveal_engine", "keen"]:
		ck(CU.trigger_hint(_u(id)) != "", "'%s' can say when it pays: \"%s\"" % [
			id, CU.trigger_hint(_u(id))])
	ck(CU.trigger_hint(_u("power")) == "", "an always-on upgrade adds no note - a note on every card is noise")

	print("\n--- the card in hand actually SHOWS it ---")
	var panel := FileAccess.get_file_as_string("res://client/combat_scene_panel.gd")
	ck(panel.contains("func _card_upgrade_strip("), "the hand renders the upgrades a card carries")
	ck(panel.contains("CardUpgrades.trigger_live("), "...and asks the SHARED evaluator which is live")
	ck(panel.contains("_monster_status = monster_status.duplicate()"),
		"the panel keeps the foe's statuses, so 'foe stunned' can be answered")
	# The counter has to exist and reach the client, or first-use and cadence never light.
	var cm := FileAccess.get_file_as_string("res://shared/combat_manager.gd")
	ck(cm.contains('combat["casts_this_fight"] = _casts'), "the server counts casts per card per fight")
	ck(cm.count('"casts_this_fight": (combat.get("casts_this_fight", {}) as Dictionary).duplicate(),') == 2,
		"...and BOTH combat-state builders send it (solo and party)")
	var cli := FileAccess.get_file_as_string("res://client/client.gd")
	ck(cli.contains("combat_scene_panel.set_cast_counts("), "the client forwards it to the hand")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
