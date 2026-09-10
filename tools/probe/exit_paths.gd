extends SceneTree
## Every way a player LEAVES must clean up their party first.
##
## 2026-09-10. `handle_disconnect` did. `handle_logout_character` and `handle_logout_account` did
## not - so a graceful logout left the player in `active_parties` and `party_membership` while
## erasing their character, and if they were the LEADER no transfer ran and the party was left
## pointing at a leader with no character. Backlog: "Leader logout must not strand the party."
##
## The ROOT is not those two functions, it is that a new exit path can be written without anyone
## remembering the rule - which is how these two came to exist. So the rule is checked instead of
## remembered: any function that erases a peer from `characters` must call
## `_cleanup_party_on_disconnect` somewhere in its body.
func _init() -> void:
	var src := FileAccess.get_file_as_string("res://server/server.gd")
	var lines := src.split("\n")
	var cur := ""
	var bodies := {}
	var order: Array = []
	for ln in lines:
		var line := String(ln)
		if line.begins_with("func "):
			cur = line.substr(5, line.find("(") - 5)
			bodies[cur] = ""
			order.append(cur)
		elif cur != "":
			bodies[cur] += line + "\n"
	var bad: Array = []
	var checked := 0
	for fn in order:
		var body: String = String(bodies[fn])
		# Does this function remove a player's character from the live table?
		if body.find("characters.erase(") < 0:
			continue
		checked += 1
		if body.find("_cleanup_party_on_disconnect") < 0:
			bad.append(fn)
	print("[EXITPATH] functions that erase a character: %d" % checked)
	for b in bad:
		print("[EXITPATH] BROKEN %s() erases the character without leaving the party" % b)
	print("[EXITPATH] %s" % ("PASS - every exit path leaves the party first"
		if bad.is_empty() else "FAIL - %d exit path(s) can strand a party" % bad.size()))
	quit(0 if bad.is_empty() else 1)
