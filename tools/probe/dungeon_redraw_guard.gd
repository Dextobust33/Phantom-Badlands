extends SceneTree
## The dungeon floor must not repaint over something the player is reading.
##
## Owner: "when my character died in the dungeon I attempted to view the Log but all I see is the
## dungeon screen." The death screen and the [L] combat-log view both own `game_output`; so does
## the dungeon floor, and the floor did not know the other two existed.
const CLIENT := "res://client/client.gd"

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var C = load(CLIENT)
	var c = C.new()
	c.set("combat_scene_panel", null)          # the panel is not up in these cases

	# The [L] combat-log view is DERIVED from the panel now (`_fight_log_open()` reads
	# `fight_log_panel.visible`; the `_victory_legacy_view` bool this probe used to set was removed
	# in 8f61d178 because the bool and the view drifted apart). So the case is built the way the game
	# builds it: a panel that is, or is not, visible.
	var log_panel := Control.new()
	log_panel.visible = false
	c.set("fight_log_panel", log_panel)
	c.set("game_state", c.GameState.PLAYING)
	ck(not c._dungeon_redraw_blocked(), "walking around alive: the floor paints normally")

	log_panel.visible = true
	ck(c._dungeon_redraw_blocked(), "the [L] combat-log view blocks the redraw")

	log_panel.visible = false
	c.set("game_state", c.GameState.DEAD)
	ck(c._dungeon_redraw_blocked(), "the death screen blocks the redraw")

	c.set("game_state", c.GameState.PLAYING)
	ck(not c._dungeon_redraw_blocked(), "and it unblocks once the player is playing again")

	# The guard must be asked by the PAINTER, not by its callers - there were seventeen of them.
	var src := FileAccess.get_file_as_string(CLIENT)
	var lines := src.split("\n")
	var a := -1
	for i in range(lines.size()):
		if lines[i].begins_with("func display_dungeon_floor("):
			a = i
			break
	var guarded := false
	for i in range(a, mini(a + 12, lines.size())):
		if lines[i].strip_edges().begins_with("if _dungeon_redraw_blocked()"):
			guarded = true
	ck(a >= 0 and guarded, "display_dungeon_floor asks the guard itself, before it paints")

	var callers := 0
	for l in lines:
		if l.strip_edges() == "display_dungeon_floor()":
			callers += 1
	print("      (%d call sites rely on that one guard)" % callers)
	log_panel.free()
	c.free()

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
