extends SceneTree
## ⛑ DOES EVERY ONE-SHOT HINT ACTUALLY FIRE?
##
## The walkthrough half of the gather→craft guide is a set of `_maybe_send_*_hint` functions, each
## fired the first time a player meets the thing it teaches. A hint that is never CALLED is the
## purest form of the defect this arc has produced seven times: the capability is written, it is
## correct, and nothing reaches it.
##
## ⚑ FOUND EXACTLY THAT. `_maybe_send_rework_hint` was written on 2026-09-18, has a persisted
## `seen_rework_hint` flag, parses, and had **no call site at all** — so the one moment the arc most
## needed to explain (Rework can come out WORSE, and it stands) taught nobody. A session note said
## it was wired; grep says otherwise, which is why this is a check rather than a memory.
##
## ⛑ AND THE FLAG IS CHECKED TOO. A hint whose `seen_` flag is never PERSISTED fires on every
## login, which is the other half of the same failure and is worse than not firing at all.
##
## Run:
##   godot --headless --path . --script res://tools/probe/every_hint_has_a_moment.gd

const CharacterScript := preload("res://shared/character.gd")

## Hints that are deliberately unwired, with the reason. Named so the exemption is visible and
## cannot quietly grow to cover one that is merely forgotten - which is the whole fault this probe
## exists to catch, and the difference between the two is a decision somebody made.
const RETIRED := {
	"_maybe_send_progression_hint":
		"owner 2026-09-16: \"I really don't like the progression reminder popup, it's intrusive "
		+ "and pops up too much or at bad times\" - retired in favour of the pulsing Stats +N "
		+ "marker. The text is kept in case a calmer surface ever wants it.",
}

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


## How many times a function is CALLED, which is its total mentions minus its declaration.
func _calls(src: String, fn: String) -> int:
	return src.count("%s(" % fn) - src.count("func %s(" % fn)


func _init() -> void:
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	var chr := FileAccess.get_file_as_string("res://shared/character.gd")

	print("")
	print("===== EVERY ONE-SHOT HINT, AND THE MOMENT THAT FIRES IT =====")
	var rx := RegEx.new()
	rx.compile("func (_maybe_send_[a-z_]*hint)[(]")
	var names: Array = []
	for m in rx.search_all(srv):
		names.append(m.get_string(1))
	names.sort()
	print("  %-36s %-8s %s" % ["hint", "callers", "flag persisted"])
	for n in names:
		var fn := String(n)
		# Count calls that are NOT the declaration.
		var calls := _calls(srv, fn)
		# The `seen_` flag this hint sets, if it has one.
		var i := srv.find("func %s(" % fn)
		var j := srv.find("\nfunc ", i + 8)
		var body := srv.substr(i, (j - i) if j > i else 2000)
		var fx := RegEx.new()
		fx.compile("character[.](seen_[a-z_]+) = true")
		var fm = fx.search(body)
		var flag := String(fm.get_string(1)) if fm != null else ""
		var persisted: bool = flag != "" and chr.find("\"%s\": %s," % [flag, flag]) >= 0
		var flag_txt := (("%s %s" % [flag, "yes" if persisted else "NO"]) if flag != "" else "(no flag)")
		print("  %-36s %-8d %s" % [fn, calls, flag_txt])
		if calls < 1:
			if RETIRED.has(fn):
				print("        retired on purpose: %s" % String(RETIRED[fn]))
			else:
				_fail("%s is never called - it teaches nobody" % fn)
		if flag != "" and not persisted:
			_fail("%s sets %s and it is not saved - it would fire every login" % [fn, flag])

	print("")
	print("===== THE GATHER -> CRAFT LOOP, MOMENT BY MOMENT =====")
	# ⛑ THE BACKLOG NAMES THE MOMENTS, so they are checked by name rather than by counting hints.
	# A player meets the loop in this order; each step a hint covers is one fewer thing they have
	# to already know to look up.
	# ⛑ COUNT CALLS, DO NOT GREP THE NAME. The first version of this searched for
	# `_maybe_send_rework_hint(peer_id` - which the DECLARATION also contains - so the one moment
	# that was genuinely missing reported ok. Two checks matching one string are one check, and
	# this arc has now hit that trap three times.
	var moments := {
		"1 gather - a material has a destination": _calls(srv, "_maybe_send_gather_hint") > 0,
		"2 craft - the bench can be asked a question": _calls(srv, "_maybe_send_crafting_hint") > 0,
		"3 improve - salvage turns gear into materials": _calls(srv, "_maybe_send_salvage_hint") > 0,
		"3 improve - a rune adds an affix": _calls(srv, "_maybe_send_rune_hint") > 0,
		"3 improve - Rework trades a stat, and can lose": _calls(srv, "_maybe_send_rework_hint") > 0,
		"4 what you cannot make - commission it": _calls(srv, "_maybe_send_commission_hint") > 0,
		"5 somebody is PAYING for this one": _calls(srv, "_maybe_send_wanted_hint") > 0,
	}
	var mk: Array = moments.keys()
	mk.sort()
	for k in mk:
		if bool(moments[k]):
			_ok(String(k))
		else:
			_fail("%s -- no hint fires here" % k)

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS every one-shot hint has a moment that fires it, saves its flag, and the")
	print("       gather->craft loop is taught at every step a player meets it.")
	quit()
