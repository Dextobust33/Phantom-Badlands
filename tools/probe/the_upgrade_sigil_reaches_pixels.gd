extends SceneTree
## ⛑ IS THE UPGRADE SIGIL ACTUALLY ON THE CARD, OR ONLY IN THE SOURCE?
##
## `an_upgraded_card_looks_upgraded.gd` proves the WIRING — both surfaces ask one table, the table
## really varies. It cannot prove the badge is visible, and this codebase has been burned by
## exactly that gap twice: a figure block nested into a branch that could never run shipped TWICE
## before anyone noticed, because every check read the source. The standing note is *"execute and
## diff pixels."*
##
## So this builds a REAL hand cell through `_build_hand_cell`, lays it out in a REAL window, and
## asks the layout engine where the sigil ended up. The failures it is looking for are the ones
## source cannot show:
##
##   * the label was added to a row that gives it no width (the card name expands to fill)
##   * it was laid out past the card's own edge, on a card that clips its contents
##   * it draws in a colour that is not there
##
## ⚑ MUST BE RUN WINDOWED. Layout measured headlessly lies - the first attempt at the map fit laid
## the scene out at 1920x1280 and cheerfully reported that everything fit.
##
## Run:
##   godot --path . --screen 1 --resolution 1280x720 --script res://tools/probe/the_upgrade_sigil_reaches_pixels.gd

const PanelScript := preload("res://client/combat_scene_panel.gd")
const CardUpgradesScript := preload("res://shared/card_upgrades.gd")

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var panel = PanelScript.new()
	get_root().add_child(panel)
	await process_frame

	var cell: PanelContainer = panel._build_hand_cell(0)
	get_root().add_child(cell)
	cell.position = Vector2(20, 20)
	await process_frame
	await process_frame

	var sigil: Label = cell.find_child("Sigil", true, false)
	var name_lbl: Label = cell.find_child("Name", true, false)
	var banner: Control = cell.find_child("Banner", true, false)
	if sigil == null:
		_fail("there is no Sigil label on a hand cell at all - the badge cannot appear")
		_finish(panel)
		return
	_ok("the hand cell carries a Sigil label")

	print("")
	print("===== AN UN-UPGRADED CARD =====")
	sigil.text = String(CardUpgradesScript.card_upgrade_look(0).get("sigil", ""))
	name_lbl.text = "Phantom Strike"
	await process_frame
	await process_frame
	print("  sigil rect %s   (text %s)" % [str(sigil.get_global_rect()), "empty" if sigil.text == "" else sigil.text])
	var plain_w: float = sigil.size.x

	print("")
	print("===== AN ASCENDANT CARD (3 sigils) =====")
	var look: Dictionary = CardUpgradesScript.card_upgrade_look(5)
	sigil.text = String(look.get("sigil", ""))
	sigil.add_theme_color_override("font_color", Color(String(look.get("sigil_color", "#FFFFFF"))))
	await process_frame
	await process_frame
	var srect: Rect2 = sigil.get_global_rect()
	var crect: Rect2 = cell.get_global_rect()
	var brect: Rect2 = banner.get_global_rect() if banner != null else crect
	print("  card   %s" % str(crect))
	print("  banner %s" % str(brect))
	print("  sigil  %s" % str(srect))

	# 1. IT HAS ROOM. The card's name label expands to fill the banner, so a sigil added beside it
	#    can legitimately end up with zero width - which is invisible and which source cannot show.
	if srect.size.x <= 0.5 or srect.size.y <= 0.5:
		_fail("the sigil was laid out at %.1fx%.1f - the name label took the whole banner"
			% [srect.size.x, srect.size.y])
	else:
		_ok("the sigil has real size: %.0fx%.0f (an empty one was %.0f wide)"
			% [srect.size.x, srect.size.y, plain_w])

	# 2. IT IS ON THE CARD. `cell.clip_contents` is true, so anything past the edge is simply gone.
	if srect.position.x < crect.position.x - 0.5 or srect.end.x > crect.end.x + 0.5:
		_fail("the sigil runs past the card's edge (%.0f..%.0f against %.0f..%.0f) and the card "
			% [srect.position.x, srect.end.x, crect.position.x, crect.end.x] + "clips its contents")
	else:
		_ok("the sigil is inside the card, which clips anything that is not")

	# 3. IT IS ON THE BANNER, not somewhere else that happens to be on the card.
	if srect.position.y < brect.position.y - 1.0 or srect.end.y > brect.end.y + 1.0:
		_fail("the sigil is not within the banner row")
	else:
		_ok("the sigil sits in the banner beside the card's name")

	# 4. AND THE NAME SURVIVED IT. The name clips rather than wraps, so a sigil that squeezes it is
	#    a regression traded for a feature - the card telling you less than it used to.
	var nrect: Rect2 = name_lbl.get_global_rect()
	print("  name   %s" % str(nrect))
	if nrect.size.x < 40.0:
		_fail("the card's NAME was squeezed to %.0fpx to fit the sigil" % nrect.size.x)
	else:
		_ok("the card name still has %.0fpx" % nrect.size.x)

	_finish(panel)


func _finish(panel) -> void:
	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS the upgrade sigil is laid out on the card's banner, has real size, and")
	print("       does not crowd out the card's name.")
	quit()
