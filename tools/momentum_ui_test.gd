extends SceneTree
# v0.9.696 WIP dev tool — renders CombatScenePanel standalone with a scripted
# Warrior hand + Momentum values and screenshots it, so the pip meter + Devastate
# gating layout can be verified without a live server / manual Warrior combat.
# Run WINDOWED (not --headless) so there's a render target:
#   godot --path . --screen 1 --script res://tools/momentum_ui_test.gd

func _init():
	_run.call_deferred()

func _run():
	root.title = "Momentum UI Test"
	root.size = Vector2i(1500, 950)

	# Dark backdrop so the (partly transparent) panel reads.
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.08, 1)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	root.add_child(bg)

	var PanelScript = load("res://client/combat_scene_panel.gd")
	var panel = PanelScript.new()
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	root.add_child(panel)

	# Let _ready() build the whole UI tree.
	await process_frame
	await process_frame
	await process_frame

	# Panel defaults to hidden (visible=false, shown by client on combat start);
	# force it visible and into the normal combat view so the hand strip shows.
	panel.visible = true
	if panel.has_method("end_action_phase"):
		panel.end_action_phase()
	await process_frame
	await process_frame

	var hand := ["power_strike", "cleave", "devastate"]

	# Variant A — mid Momentum (3/5): meter shows 3 filled pips, Devastate castable.
	if panel.has_method("update_hand"):
		panel.update_hand(hand, 8, 4)
	if panel.has_method("update_momentum"):
		panel.update_momentum(3, 5, true)
	await process_frame
	await process_frame
	await process_frame
	_shot("res://claude_screenshots/momentum_ui_m3.png")

	# Variant B — zero Momentum: meter empty, Devastate gated ("Build Momentum first").
	if panel.has_method("update_momentum"):
		panel.update_momentum(0, 5, true)
	await process_frame
	await process_frame
	await process_frame
	_shot("res://claude_screenshots/momentum_ui_m0.png")

	# Variant C — full Momentum (5/5): all pips, FINISHER READY.
	if panel.has_method("update_momentum"):
		panel.update_momentum(5, 5, true)
	await process_frame
	await process_frame
	await process_frame
	_shot("res://claude_screenshots/momentum_ui_m5.png")

	# Variant D — non-Warrior: meter hidden entirely.
	if panel.has_method("update_momentum"):
		panel.update_momentum(0, 5, false)
	await process_frame
	await process_frame
	_shot("res://claude_screenshots/momentum_ui_nonwarrior.png")

	# ---- Trickster Combo variants (same meter node, purple ✦, Gambit risk note) ----
	var thand := ["sabotage", "ambush", "gambit"]
	if panel.has_method("update_hand"):
		panel.update_hand(thand, 8, 4)

	# Combo mid (3/5): chain building, Gambit "safer".
	if panel.has_method("update_combo"):
		panel.update_combo(3, 5, true)
	await process_frame
	await process_frame
	await process_frame
	_shot("res://claude_screenshots/combo_ui_c3.png")

	# Combo zero: Gambit "High-risk gamble".
	if panel.has_method("update_combo"):
		panel.update_combo(0, 5, true)
	await process_frame
	await process_frame
	await process_frame
	_shot("res://claude_screenshots/combo_ui_c0.png")

	# Combo full (5/5): SURE THING, Gambit "Guaranteed heist!".
	if panel.has_method("update_combo"):
		panel.update_combo(5, 5, true)
	await process_frame
	await process_frame
	await process_frame
	_shot("res://claude_screenshots/combo_ui_c5.png")

	# ---- Mage Focus variants (same meter, blue ◈ ramp, Meteor discharge note) ----
	var mhand := ["magic_bolt", "blast", "meteor"]
	if panel.has_method("update_hand"):
		panel.update_hand(mhand, 8, 4)

	# Focus mid (3/5): +30% ramp; spells "+◈ Focus"; Meteor "Discharge +75%".
	if panel.has_method("update_focus"):
		panel.update_focus(3, 5, true)
	await process_frame
	await process_frame
	await process_frame
	_shot("res://claude_screenshots/focus_ui_f3.png")

	# Focus zero: "cast to ramp up"; Meteor "Ramp Focus first".
	if panel.has_method("update_focus"):
		panel.update_focus(0, 5, true)
	await process_frame
	await process_frame
	await process_frame
	_shot("res://claude_screenshots/focus_ui_f0.png")

	# Focus max (5/5): MAX +50% dmg; Meteor "Discharge! +125%".
	if panel.has_method("update_focus"):
		panel.update_focus(5, 5, true)
	await process_frame
	await process_frame
	await process_frame
	_shot("res://claude_screenshots/focus_ui_f5.png")

	print("Momentum + Combo + Focus UI screenshots written to claude_screenshots/")
	quit()

func _shot(path: String) -> void:
	var img := root.get_texture().get_image()
	if img == null:
		print("  (no image for %s)" % path)
		return
	var err := img.save_png(path)
	print("  wrote %s (err=%d)" % [path, err])
