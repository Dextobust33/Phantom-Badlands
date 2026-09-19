extends SceneTree
## ⛑ CAN YOU ALWAYS REST AND REACH YOUR ITEMS UNDERGROUND?
##
## Owner 2026-09-18: *"After killing the boss of a dungeon it looks like you can't rest anymore as
## the option isn't on the bar anymore."*
##
## ⚑ THE BRANCH'S OWN COMMENT SAID "Items + Rest still available" AND THE ARRAY UNDER IT OFFERED
## Items and eight blanks. A comment describing an intention nobody implemented reads as
## documentation and tests as nothing — and this is the worst state to lose Rest in, because it sits
## between the boss fight (the hardest thing in the dungeon) and the walk to the final chest, in a
## permadeath game where in-dungeon recovery is half the overworld rate.
##
## So the invariant is checked rather than described: every action-bar state a player can be STANDING
## in underground, out of combat, must offer both Items and Rest.
##
## Run:
##   godot --headless --path . --script res://tools/probe/dungeon_bar_never_strands_you.gd

## States that legitimately offer neither, with the reason. Named so an exemption cannot grow
## quietly into covering a real one.
const NOT_STANDING_THERE := {
	"awaiting_dungeon_trap_ack": "a modal acknowledgement - one button, then you are back on the map",
	"pending_continue": "the round is still resolving; the bar is a Continue",
	"dungeon_food_select": "already INSIDE Rest, choosing what to eat",
	"dungeon_resource_prompt": "a yes/no on a resource you just stepped on",
}

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


func _init() -> void:
	var cli := FileAccess.get_file_as_string("res://client/client.gd")
	var lines: PackedStringArray = cli.split("\n")

	print("")
	print("===== EVERY DUNGEON ACTION-BAR STATE =====")
	var i := 0
	var found := 0
	while i < lines.size():
		var line := String(lines[i])
		var t := line.strip_edges()
		if not (t.begins_with("elif dungeon_mode") or t.begins_with("if dungeon_mode")):
			i += 1
			continue
		if line.find("current_actions") >= 0:
			i += 1
			continue
		# Gather this branch's body: up to the closing `]` of its current_actions array.
		var body := ""
		var j := i + 1
		var saw_actions := false
		while j < lines.size() and j < i + 60:
			var b := String(lines[j])
			if b.strip_edges().begins_with("elif ") and saw_actions:
				break
			if b.find("current_actions = [") >= 0:
				saw_actions = true
			body += b + "\n"
			if saw_actions and b.strip_edges() == "]":
				break
			j += 1
		if not saw_actions:
			i += 1
			continue
		found += 1
		# Which state is this?
		var label := t.replace("elif ", "").replace("if ", "").replace(":", "")
		var exempt := ""
		for k in NOT_STANDING_THERE.keys():
			if t.find("dungeon_mode and %s" % k) >= 0:
				exempt = String(NOT_STANDING_THERE[k])
				break
		var has_rest: bool = body.find("\"dungeon_rest\"") >= 0
		var has_items: bool = body.find("\"action_data\": \"inventory\"") >= 0
		var short := label.substr(0, mini(64, label.length()))
		if exempt != "":
			print("  ---   %-66s exempt: %s" % [short, exempt])
		elif has_rest and has_items:
			_ok(short)
		else:
			var missing: Array = []
			if not has_rest:
				missing.append("Rest")
			if not has_items:
				missing.append("Items")
			_fail("%s -- no %s" % [short, ", ".join(missing)])
		i = j + 1

	print("")
	print("  %d dungeon action-bar states examined" % found)
	if found < 4:
		_fail("only %d states found - the branch shape this greps for has changed" % found)

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d dungeon state(s) leave you without Rest or your items:" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS every state you can stand in underground offers both Rest and Items.")
	quit()
