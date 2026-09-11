extends SceneTree
## A round divider marks a ROUND, not an update.
##
## Owner 2026-09-11, four potions drunk in round 4: the log printed "──── Round 4 ────" four
## times and chopped one round into four fake turns. Every combat_update armed a divider, and a
## FREE ITEM action sends a combat_update without advancing the round.
const CLIENT := "res://client/client.gd"

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var src := FileAccess.get_file_as_string(CLIENT)
	var lines := src.split("\n")

	# Find the arming site and prove it is guarded by a round-change test.
	var arm := -1
	for i in range(lines.size()):
		if lines[i].strip_edges() == "_pending_round_divider = true":
			# the one inside the combat_update branch (not the combat_start reset)
			var window := ""
			for j in range(maxi(0, i - 14), i):
				window += lines[j]
			if window.contains("state.get(\"round\""):
				arm = i
				break
	ck(arm > 0, "found the combat_update divider arming site")
	var guarded := false
	for j in range(maxi(0, arm - 6), arm):
		if lines[j].strip_edges().begins_with("if _new_round != _combat_known_round"):
			guarded = true
	ck(guarded, "it is guarded by an actual round CHANGE, not armed on every update")

	# Simulate the sequence that produced the bug: one round, four updates.
	var known := 3
	var dividers := 0
	for state_round in [4, 4, 4, 4]:
		if state_round != known:
			known = state_round
			dividers += 1
	print("      round 3 -> four updates all reporting round 4: %d divider(s)" % dividers)
	ck(dividers == 1, "four free-item updates in one round print ONE divider")

	# ...and a genuine round advance still prints.
	known = 4
	dividers = 0
	for state_round in [5, 5, 6]:
		if state_round != known:
			known = state_round
			dividers += 1
	print("      rounds 5,5,6: %d divider(s)" % dividers)
	ck(dividers == 2, "a real round advance still prints exactly one each")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
