extends SceneTree
## A fight's text stays out of the dungeon run log; ordinary underground news still goes in.
##
## Owner, from a live player on v0.9.791: *"Their text on the right while in the dungeon and out of
## combat also says your turn sabotage analyze vanish, etc. things that don't need output over there."*
## Underground, display_game writes to the side panel's run log, and the party (Warden) combat path
## prints every round line and "YOUR TURN" through display_game.

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var c = load("res://client/client.gd").new()
	c.dungeon_mode = true
	c.dungeon_data = {"floor": 1}
	c._dungeon_log = []

	c.in_combat = true
	c.display_game("[color=#00FF00]═══ YOUR TURN ═══[/color]")
	c.display_game("You use Sabotage!")
	ck(c._dungeon_log.is_empty(), "lines printed during a fight stay out of the run log (%s)" % str(c._dungeon_log))

	c.in_combat = false
	c.display_game("You step on a pressure plate.")
	ck(c._dungeon_log.size() == 1, "a line printed out of combat still reaches the run log (%s)" % str(c._dungeon_log))

	c.free()
	print("RESULT: %s (%d failing)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
