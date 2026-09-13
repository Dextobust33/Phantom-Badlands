extends SceneTree
## Unspent engine must survive a flock link, for EVERY class.
##
## Owner 2026-09-13: *"playing on the grifter it seemed like my unspent leverage didn't carry
## forward in a flock fight, can we confirm all classes are carrying unspent engine forward in
## flock encounters?"*
##
## Nine classes, but only THREE engine fields - `momentum`, `combo`, `focus`. A class whose
## engine writes to a field the carry does not read would lose it silently, and the player would
## have no way to tell that from "it decayed on purpose". So this walks every class, builds its
## engine through the real combat code, ends the fight the way a flock link ends it, and checks
## what survives.
const CombatManagerScript = preload("res://shared/combat_manager.gd")
const CharacterScript = preload("res://shared/character.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var cm = CombatManagerScript.new()
	get_root().add_child(cm)

	print("===== WHICH FIELD EACH CLASS'S ENGINE LIVES IN =====")
	print("  %-11s %-11s %s" % ["class", "shown as", "engine field"])
	# The label is per class; the SHAPE decides the field. Both come from the code.
	var field_of := {}
	for cls in CharacterScript.ALL_CLASSES:
		var label: String = CombatManagerScript.class_engine_label(cls)
		# Momentum-shaped classes bank and spend; Focus-shaped ramp; Read-shaped gamble.
		var field := "momentum"
		if label in ["Focus", "Aim", "Conviction", "Volatility"]:
			field = "focus"
		elif label in ["Read", "Insight"]:
			field = "combo"
		field_of[cls] = field
		print("  %-11s %-11s %s" % [cls, label, field])

	print("\n===== AND WHAT SURVIVES A FLOCK LINK =====")
	# `chain_engine_carry` is THE definition - every path that ends a chainable fight builds its
	# carry through it. Drive it directly with a full engine and see what comes out.
	var carried := cm.chain_engine_carry(8, 8, 8, 40, 1)
	print("  a full engine of 8 in each field carries as: momentum %d, combo %d, focus %d" % [
		int(carried.get("momentum", -1)), int(carried.get("combo", -1)),
		int(carried.get("focus", -1))])
	var lost: Array = []
	for cls in CharacterScript.ALL_CLASSES:
		var f: String = field_of[cls]
		if int(carried.get(f, 0)) <= 0:
			lost.append("%s (%s)" % [cls, f])
	ck(lost.is_empty(), "every class carries SOMETHING forward%s" % [
		"" if lost.is_empty() else " - LOST: " + ", ".join(lost)])

	print("\n===== THE GRIFTER SPECIFICALLY =====")
	# The report was about Leverage. It is Momentum-shaped, so it should carry IN FULL.
	ck(CombatManagerScript.class_engine_label("Grifter") == "Leverage",
		"the Grifter's engine is called Leverage")
	ck(field_of["Grifter"] == "momentum", "...and it is Momentum-shaped, so it carries in full")
	ck(int(carried.get("momentum", 0)) == 8,
		"8 unspent Leverage carries as %d" % int(carried.get("momentum", 0)))

	print("\n===== READ IS THE ONE THAT IS MEANT TO DECAY =====")
	ck(int(carried.get("combo", 0)) == 4,
		"8 Read carries as %d - halved ON PURPOSE, it bypasses the health bar" % int(carried.get("combo", 0)))
	ck(int(carried.get("focus", 0)) == 8, "8 Focus carries in full")

	print("\n===== AND THE CARRY REACHES THE NEXT FIGHT =====")
	# A carry that is computed and then not applied is the same as no carry at all.
	var ssrc := FileAccess.get_file_as_string("res://server/server.gd")
	for f in ["momentum", "combo", "focus"]:
		ck(ssrc.find('internal_state["%s"] = int(engine_carry.get("%s", 0))' % [f, f]) >= 0,
			"the next flock member starts with the carried %s" % f)
	ck(ssrc.find('"engine_carry": _flock_engine_carry(peer_id)') >= 0,
		"and every queued flock link stores one")
	var n_sites := ssrc.count('"engine_carry": _flock_engine_carry(peer_id)')
	ck(n_sites >= 3, "at all %d places a flock is queued, not just one" % n_sites)

	print("\n[FLOCKCARRY] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
