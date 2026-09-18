extends SceneTree
## ⛑ THE COMPANION'S LINES ARE NAMED AT THE ACTION, NOT AT THE CALL SITE.
##
## The round summary folds a round's messages into one line PER ACTOR, so a message that carries no
## actor mark inherits whichever mark is still in force - the player's. That is invisible until two
## rounds of the same fight disagree, which is exactly how it was found.
##
## `_process_companion_attack` has TWO callers: the basic-attack path and the CAST path. Only the
## first marked the companion. So attacking gave the companion its own line and casting a card
## merged it into yours. Owner 2026-09-17, comparing rounds of one fight: *"I did a forcefield and
## my companion was in that line as well as me... Round 2 my stuff and my companions are on
## different lines unlike round 1."*
##
## The fix is not "mark it at the second site too" - that leaves a third caller free to forget in
## the same way. The marking moved INSIDE the function, so this probe guards the property that
## makes forgetting impossible rather than the two call sites that exist today:
##
##   ACTOR_COMPANION is marked in exactly ONE place, and that place is inside the function that
##   makes the companion act.
##
## Proven to fire: re-injecting the fault (moving the mark back out to a caller) turns both checks
## red - the count check on the second copy, and the containment check on the zero copies left
## inside the function.
##
## Run:
##   godot --headless --path . --script res://tools/probe/companion_lines_are_marked.gd

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _body_of(src: String, header: String) -> String:
	"""Source of one function: from its header to the next top-level `func`."""
	var at := src.find(header)
	if at < 0:
		return ""
	var rest := src.substr(at + header.length())
	var end := rest.find("\nfunc ")
	return rest if end < 0 else rest.substr(0, end)


func _init() -> void:
	var src := FileAccess.get_file_as_string("res://shared/combat_manager.gd")

	print("===== THE MARK LIVES WITH THE ACTION =====")
	var marks := src.count("_mark_actor(combat, _mark_from, ACTOR_COMPANION)")
	var any := src.count("ACTOR_COMPANION)")
	ck(any == marks and marks == 1,
		"ACTOR_COMPANION is marked in exactly one place (found %d mark call(s), %d total)"
			% [marks, any])

	var wrapper := _body_of(src, "func _process_companion_attack(combat: Dictionary, messages: Array) -> void:")
	ck(wrapper != "", "the wrapper `_process_companion_attack` exists")
	ck(wrapper.find("_mark_actor(combat, _mark_from, ACTOR_COMPANION)") >= 0,
		"...and the one mark is INSIDE it, so no caller can omit it")
	ck(wrapper.find("_process_companion_attack_body(combat, messages)") >= 0,
		"...and it delegates to the real body, whose early `return`s it therefore cannot skip")

	print("\n===== BOTH CALLERS GO THROUGH IT =====")
	# Untyped-argument form, so this counts CALLS only: the definition spells its parameters
	# `(combat: Dictionary, messages: Array)` and the wrapper's own call goes to `..._body`.
	var callers := src.count("_process_companion_attack(combat, ")
	ck(callers == 2,
		"exactly two callers - the attack path and the cast path (found %d)" % callers)
	ck(src.find("_process_companion_attack(combat, result.messages)") >= 0,
		"the CAST path calls the wrapper (this is the site that used to forget)")
	ck(src.find("_process_companion_attack(combat, messages)\n") >= 0,
		"the ATTACK path calls the wrapper")

	print("\n===== NO CALL SITE MARKS IT BY HAND ANY MORE =====")
	ck(src.find("_mark_actor(combat, _ca, ACTOR_COMPANION)") < 0,
		"the attack path's hand-written mark is gone (it was the only one, which was the bug)")
	ck(src.find("_mark_actor(combat, _ca3, ACTOR_COMPANION)") < 0,
		"and the cast path was not 'fixed' by adding a second copy")

	print("")
	if fails == 0:
		print("[PROBE] PASS the companion names its own lines")
	else:
		print("[PROBE] FAIL %d check(s)" % fails)
	quit(1 if fails > 0 else 0)
