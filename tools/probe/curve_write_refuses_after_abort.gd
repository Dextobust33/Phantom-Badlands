extends SceneTree
## A calibration run that outlived its budget must NOT write the curve.
##
## 2026-09-15: `rolecal` hit its 45-minute budget, printed "results above are INCOMPLETE and must
## not be used", and wrote its half-converged multipliers into
## `shared/reference_monster_curve.json` anyway. All three layers had their own FileAccess call and
## none asked whether the run had aborted. The file is the game's monster sizing, so a silent bad
## write is a balance regression nobody sees. `_write_curve` is now the one write path; this proves
## it refuses.
const SIM = preload("res://tools/combat_simulator/real_combat_sim.gd")
const CURVE := "res://shared/reference_monster_curve.json"

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _digest() -> String:
	return FileAccess.get_file_as_string(CURVE).sha256_text()


func _init() -> void:
	var sim = SIM.new()
	var before := _digest()
	ck(before != "", "the curve file is readable (%s...)" % before.substr(0, 12))

	# The shape that bit: the budget tripped, the layer finished its loop anyway, and wrote.
	sim._budget_tripped = true
	var wrote_after_abort: bool = sim._write_curve({"role_multipliers": {"probe": "junk"}}, "probe junk")
	ck(not wrote_after_abort, "a budget-aborted run's write is REFUSED")
	ck(_digest() == before, "...and the curve file is byte-identical")

	# Prove the detector fires for the right reason: the same call, budget intact, DOES write.
	# Written to a copy so this probe can never touch the real curve.
	sim._budget_tripped = false
	var scratch := "user://probe_curve_copy.json"
	var src := FileAccess.get_file_as_string(CURVE)
	var cf = FileAccess.open(scratch, FileAccess.WRITE)
	cf.store_string(src)
	cf.close()
	# _write_curve is hardcoded to the real path, so the control is the guard itself: with the
	# budget intact the function proceeds past the refusal and reaches the file open. Assert the
	# refusal message is the ONLY thing standing between the two cases.
	var body := FileAccess.get_file_as_string("res://tools/combat_simulator/real_combat_sim.gd")
	var at := body.find("func _write_curve(")
	var fn := body.substr(at, body.find("\nfunc ", at + 10) - at)
	ck(fn.contains("if _budget_tripped:") and fn.contains("return false"), "the guard is inside the one writer")
	ck(fn.find("if _budget_tripped:") < fn.find("FileAccess.open"), "...and runs before the file is opened")
	# Everything EXCEPT _write_curve's own body — cut by the function's real length, not a
	# guessed offset (the first version cut ten characters and then reported its own writer).
	var whole := body.substr(0, at) + body.substr(at + fn.length())
	var other_writes := whole.count("FileAccess.open(\"res://shared/reference_monster_curve.json\", FileAccess.WRITE)")
	ck(other_writes == 0, "no calibration layer writes the curve around it (%d found)" % other_writes)
	ck(body.count("_write_curve({") == 3, "all three layers (anchors, species_power, role_multipliers) go through it")

	print("RESULT: %s (%d failing)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
