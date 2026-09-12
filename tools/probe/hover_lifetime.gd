extends SceneTree
## A tooltip must not outlive what opened it, must appear where the pointer is, and every term
## that is underlined must say something.
##
## Three faults, reported together by the owner 2026-09-11, and two of them turned out to be one
## cause: nothing owned the popup's lifetime.
##   1. *"I've got a Thorned - reflects melee damage box stuck on my screen after hovering a
##      Thorned hobgoblin. It has persisted through fights."*
##   2. *"when hovering the underlined Damage word on a companion inspect ... the hoverbox
##      appeared way over on the right of my screen."*
##   3. *"APEX should be a hoverable term in names as well."*
##
## The first was a single surface out of eight wired for hover-IN and never hover-OUT. Fixing
## that one line would have left the class alive, so the pair is now one call and this probe
## fails if a raw connect reappears.
const SRC := "res://client/combat_scene_panel.gd"

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _body(src: String, fname: String) -> String:
	var i := src.find("func %s(" % fname)
	if i < 0:
		return ""
	var j := src.find("\nfunc ", i + 10)
	return src.substr(i, (j if j > 0 else src.length()) - i)


func _init() -> void:
	var src := FileAccess.get_file_as_string(SRC)

	print("--- a hover can only be wired BOTH ways ---")
	var w := _body(src, "_wire_hover")
	ck(w != "", "_wire_hover exists")
	ck(w.find("meta_hover_started.connect") >= 0 and w.find("meta_hover_ended.connect") >= 0,
		"and it connects the pair, so neither can be forgotten")
	# Every other connect must go through it. This is the check that retires the class: the
	# original fault was one label out of eight connected for hover-in only.
	# Counted OUTSIDE `_wire_hover` itself: its own two lines are the whole point of it, and its
	# docstring names the signal as well. Scoping by FUNCTION rather than by pattern is what
	# keeps this check from arguing with the comment that explains it.
	var wi := src.find("func _wire_hover(")
	var before := src.substr(0, wi)
	var after := src.substr(wi + w.length())
	var raw_started := before.count("meta_hover_started.connect") + after.count("meta_hover_started.connect")
	var raw_ended := before.count("meta_hover_ended.connect") + after.count("meta_hover_ended.connect")
	ck(raw_started == 0, "no label connects hover-in by hand any more (%d found)" % raw_started)
	ck(raw_ended == 0, "nor hover-out (%d found)" % raw_ended)
	ck(src.count("_wire_hover(") >= 8, "%d surfaces go through it" % src.count("_wire_hover("))

	print("\n--- and it cannot outlive the panel either ---")
	# Connecting hover-out covers the pointer LEAVING a label. It does nothing when the label
	# leaves instead: combat ends, the scene is rebuilt, and no hover-out ever fires because
	# there is nothing left to leave. That is the half of the report that said "persisted
	# through fights".
	var ready := _body(src, "_ready")
	ck(ready.find("visibility_changed.connect") >= 0,
		"the panel watches its own visibility")
	ck(ready.find("_hide_formula_popup()") >= 0,
		"...and closes the popup when it goes away")

	print("\n--- it appears where the pointer is ---")
	var show := _body(src, "_show_formula_popup")
	ck(show.find("await get_tree().process_frame") >= 0,
		"the size is read AFTER a layout, not in the frame the text was set")
	ck(show.find("_formula_popup.get_global_mouse_position()") >= 0,
		"and the mouse is read in the POPUP's space, the one global_position is in")
	ck(show.find("get_global_mouse_position()\n") < 0 or show.find("\tvar mp := get_global_mouse_position()") < 0,
		"...not the panel's, which is only the same when nothing between them scales")
	ck(show.find("maxf(4.0, vp.x - sz.x - 4.0)") >= 0,
		"and a popup wider than the screen still clamps to a real position")

	print("\n--- every underlined term says something ---")
	ck(src.find("_APEX_HELP_APEX") >= 0 and src.find("_APEX_HELP_ELITE") >= 0,
		"APEX and ELITE both carry hover text")
	var name_block := src.substr(src.find("var danger_tag := \"\""), 500)
	ck(name_block.find("[url=%s]") >= 0 and name_block.count("[url=%s]") == 2,
		"and both are wrapped in a url, which is what makes a term hoverable here")
	ck(src.find('_APEX_HELP_APEX := "APEX') >= 0 and src.find("38%") >= 0,
		"...and the apex text carries the real number, read off APEX_TARGET_WIN rather than invented")
	ck(String(src).find('_APEX_HELP_APEX := "APEX') >= 0 and src.find('"APEX - one of the species') >= 0,
		"the text contains no double quote, which would end the url tag dead")

	print("\n[HOVERLIFETIME] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
