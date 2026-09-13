extends SceneTree
## Travel stances: one table, both sides, and a real trade in both directions.
##
## Owner 2026-09-13: an evasive stance where *"you don't get as much back each step or from rests
## but you're much less likely to hit random encounters"*, plus a couple more, as an obvious
## coloured toggle under the map with an explanation.
##
## The failure worth guarding is not "a stance does nothing" - it is a stance that is strictly
## BETTER than another, which turns a choice into a correct answer and makes the toggle pointless.
const TS = preload("res://shared/travel_stance.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	print("--- every stance is a real trade ---")
	# The one that matters: nothing may be better than Wary on every axis at once, or there is
	# no decision to make and the bar is decoration.
	var base: Dictionary = TS.get_stance(TS.WARY)
	for sid in TS.ORDER:
		if String(sid) == TS.WARY:
			continue
		var st: Dictionary = TS.get_stance(String(sid))
		# ENCOUNTER RATE IS A PREFERENCE AXIS, NOT A QUALITY ONE. Fewer encounters is what a
		# traveller wants and more is what a hunter wants, so "different from Wary" is the gain;
		# reading it as "lower is better" calls Hunting strictly worse. The first version of this
		# probe did exactly that - and was still worth having, because it then caught that
		# Hunting cost NOTHING, which made it a free switch rather than a choice.
		var diff_enc: bool = not is_equal_approx(float(st["encounter"]), float(base["encounter"]))
		var better_regen: bool = float(st["regen"]) > float(base["regen"])
		var better_vis: bool = int(st["vision"]) > int(base["vision"])
		var worse_any: bool = float(st["regen"]) < float(base["regen"]) or int(st["vision"]) < int(base["vision"])
		ck(worse_any, "%s gives something up" % st["name"])
		ck(diff_enc or better_regen or better_vis, "...and gains something")

	print("\n--- the numbers are the ones the owner described ---")
	ck(TS.encounter_mult(TS.TRAVELLING) < 0.3,
		"Travelling is much less likely to meet anything (x%.2f)" % TS.encounter_mult(TS.TRAVELLING))
	ck(TS.regen_mult(TS.TRAVELLING) < 0.5,
		"...and recovers much less per step and rest (x%.2f)" % TS.regen_mult(TS.TRAVELLING))
	ck(TS.encounter_mult(TS.HUNTING) > 1.5, "Hunting finds more")
	ck(TS.vision_bonus(TS.SCOUTING) > 0, "Scouting sees further")
	ck(TS.encounter_mult(TS.WARY) == 1.0 and TS.regen_mult(TS.WARY) == 1.0,
		"Wary is exactly today's behaviour, so it is a fair baseline")

	print("\n--- an unknown stance cannot strand a character ---")
	# A bad save, an older client, a hand-edited message.
	ck(TS.get_stance("nonsense").get("name", "") == "Wary", "an unknown id resolves to Wary")
	ck(TS.encounter_mult("") == 1.0, "...and multiplies nothing")
	ck(not TS.is_valid("nonsense"), "...while still being rejected on the way in")

	print("\n--- the server applies BOTH halves, and validates ---")
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	ck(srv.find("TravelStanceScript.encounter_mult(String(character.travel_stance))") >= 0,
		"the movement encounter roll is scaled by the stance")
	ck(srv.find("TravelStanceScript.regen_mult(String(character.travel_stance))") >= 0,
		"and so is what a step gives back - without this a stance is free")
	ck(srv.find("if not TravelStanceScript.is_valid(want):") >= 0,
		"the handler validates rather than trusting the client")
	ck(srv.find('send_to_peer(peer_id, {"type": "travel_stance", "stance": String(character.travel_stance)})') >= 0,
		"and the stance is sent at login, so the bar cannot disagree with the character")

	print("\n--- the multiplier reaches the ROLL, not just the call site ---")
	var ws := FileAccess.get_file_as_string("res://shared/world_system.gd")
	ck(ws.find("stance_mult: float = 1.0") >= 0, "check_encounter takes it")
	ck(ws.find("rate *= maxf(0.0, stance_mult)") >= 0, "...and applies it to the rate")

	print("\n--- the client draws from the SAME table ---")
	var cli := FileAccess.get_file_as_string("res://client/client.gd")
	ck(cli.find("for sid in _TravelStance.ORDER:") >= 0,
		"the buttons are generated from the shared order, not hand-listed")
	ck(cli.find("b.tooltip_text") >= 0, "each carries its explanation")
	ck(cli.find("b.disabled = active") >= 0,
		"the active stance is also DISABLED, so it reads without relying on colour")

	print("\n[STANCES] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
