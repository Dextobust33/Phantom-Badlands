extends SceneTree
## The area-level readout must warn you, because distance no longer does.
##
## Owner 2026-09-13: *"We will need to make the area danger a little more obvious like changing
## the color of the area text as it gets way higher than your character and maybe even pulse."*
##
## This matters more than a normal polish item. Danger USED to be inferable from distance - walk
## further, meet worse. Regional menace deliberately broke that so every grade of country can
## exist anywhere, which makes this line the player's only standing warning, under permadeath.
##
## So the bands are checked as arithmetic rather than read out of the source: a 10-level gap is
## lethal at level 12 and meaningless at level 900, so the thresholds have to be RATIOS.
const SRC := "res://client/client.gd"

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var src := FileAccess.get_file_as_string(SRC)
	var i := src.find("func _area_level_tag(")
	var body := src.substr(i, src.find("\nfunc ", i + 10) - i) if i >= 0 else ""
	ck(body != "", "the readout has its own function")

	print("--- the thresholds are RATIOS, not fixed level gaps ---")
	ck(body.find("float(maxi(1, area_lv)) / float(me)") >= 0,
		"danger is measured as area level RELATIVE to the character")
	ck(body.find("area_lv - me") < 0, "...and not as a flat difference, which does not scale")

	print("\n--- it escalates, and the top band pulses ---")
	for t in ["0.6", "0.85", "1.35", "2.0", "3.0"]:
		ck(body.find(t) >= 0, "a band at ratio %s" % t)
	ck(body.find("[pulse freq=") >= 0, "the lethal band pulses")
	ck(body.find("LETHAL") >= 0, "...and says so in words, not only in colour")
	# Count DISTINCT colour values, not BBCode tags - the bands assign bare hex strings to a
	# variable and the tag is written once. Counting tags measured the wrong thing and failed on
	# correct code, which is the same mistake as every other check that reads for a shape instead
	# of the fact it cares about.
	var hexes := {}
	var at := body.find("#")
	while at >= 0:
		var hx := body.substr(at, 7)
		if hx.length() == 7:
			hexes[hx.to_upper()] = true
		at = body.find("#", at + 1)
	ck(hexes.size() >= 4, "%d distinct colours across the bands" % hexes.size())

	print("\n--- the pulse is RESERVED, or it stops being a warning ---")
	# Something that blinks all the time is wallpaper. It must fire only at the top band.
	var pulse_i := body.find("[pulse freq=")
	var before := body.substr(0, pulse_i)
	ck(before.find("if ratio >= 3.0:") >= 0,
		"the pulse sits behind the highest threshold, not an early one")

	print("\n--- and the line still carries everything it used to ---")
	var caller := src.find("_area_level_tag(hud_area_level)")
	ck(caller >= 0, "the status line calls it")
	var line := src.substr(caller - 200, 400)
	for part in ["danger", "apex_tag", "threat_tag"]:
		ck(line.find(part) >= 0, "...and still shows %s" % part)

	print("\n[AREADANGER] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
