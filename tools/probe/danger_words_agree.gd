extends SceneTree
## Owner sheet 2026-10-13: the danger-step confirmation called ground "far above you" from 1.15x while
## the Area readout beside it said "about your level" until 1.35x - one ground, two descriptions. Both
## now read shared/danger_words.gd. This pins that they agree, and that the wording actually varies.
const DW = preload("res://shared/danger_words.gd")
const ServerScript = preload("res://server/server.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _body(src: String, fn: String) -> String:
	var i := src.find("\nfunc %s(" % fn)
	if i < 0:
		return ""
	var j := src.find("\nfunc ", i + 8)
	return src.substr(i, (j - i) if j > i else 4000)

func _init() -> void:
	var srv = ServerScript.new()

	print("--- the guard asks exactly where the readout turns red ---")
	ck(ServerScript.DANGER_STEP_RATIO == DW.ABOVE, "the guard's threshold IS the readout's 'above you' edge (%.2f)" % DW.ABOVE)
	var mismatches := 0
	var r := 0.30
	while r < 5.0:
		var asks: bool = srv._danger_band(r) >= 1
		var red: bool = DW.verdict(r) in ["above", "far", "lethal"]
		if asks != red:
			mismatches += 1
		r += 0.01
	ck(mismatches == 0, "across ratios 0.30-5.00 the guard asks iff the readout is red (%d disagreements)" % mismatches)
	ck(DW.verdict(1.2) == "above" and DW.phrase("above") == "above you",
		"1.2x - the old contradiction - reads 'above you' (it was 'far above you' in the guard and 'about your level' in the readout)")

	print("\n--- every warning uses the readout's own words, and only those ---")
	var all_ok := true
	var words_for := {"above": "above you", "far": "far above you", "lethal": "LETHAL"}
	var samples := {"above": [23, 20], "far": [45, 20], "lethal": [90, 20]}   # ground level, your level
	for key in samples:
		var there: int = int(samples[key][0])
		var me: int = int(samples[key][1])
		ck(DW.verdict(float(there) / float(me)) == key, "setup: %d vs %d is '%s'" % [there, me, key])
		var seen := {}
		for p in range(0, 120):
			var t: String = DW.warning(there, me, p)
			seen[t] = true
			if t.find(String(words_for[key])) < 0:
				all_ok = false
				print("      MISSING '%s' in: %s" % [words_for[key], t.replace("\n", " | ")])
			if t.find("to go anyway") < 0:
				all_ok = false
			if key == "above" and (t.find("far above") >= 0 or t.find("LETHAL") >= 0 or t.find("about your level") >= 0):
				all_ok = false
				print("      WRONG VERDICT in: %s" % t.replace("\n", " | "))
			if key == "far" and (t.find("LETHAL") >= 0 or t.find("about your level") >= 0):
				all_ok = false
			if t.find("Lv %d" % there) < 0:
				all_ok = false
		ck(seen.size() >= 6, "'%s' has real variety: %d distinct warnings" % [key, seen.size()])
	ck(all_ok, "every variant names the ground's level, uses the readout's phrase, and says how to go on")

	print("\n--- both surfaces are wired to the shared vocabulary ---")
	var srv_src := FileAccess.get_file_as_string("res://server/server.gd")
	var guard := _body(srv_src, "_confirm_dangerous_step")
	ck(guard != "" and guard.find("DangerWordsScript.warning(there, me)") >= 0, "the server guard builds its message from DangerWords")
	ck(guard.find('var how := "far above you"') < 0, "...and no longer carries its own wording")
	var cli := FileAccess.get_file_as_string("res://client/client.gd")
	ck(cli.find("_DangerWords.bbcode(_DangerWords.verdict(ratio))") >= 0, "the Area readout builds its verdict from DangerWords")
	ck(cli.find('verdict = "[color=#FF5555]above you[/color]"') < 0, "...and no longer carries its own thresholds")

	srv.free()
	print("\n[DANGERWORDS] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
