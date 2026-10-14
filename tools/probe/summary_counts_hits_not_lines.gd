extends SceneTree
## Playtest sheet item 4: big monsters' turn hover showed "6 or 7 hits (some of those were misses)".
## The server never sends more than 3 hits per monster turn (measured over 1,500+ real actions);
## the round-summary line counted MESSAGES, so "attacks multiple times!", "strikes with unexpected
## ferocity!" and misses all read as hits. A hit is a line carrying a measured number.
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _init() -> void:
	get_root().set_content_scale_size(Vector2i(1920, 1080))
	get_root().size = Vector2i(1920, 1080)
	var c = (load("res://client/client.tscn") as PackedScene).instantiate()
	get_root().add_child(c)
	for _i in range(8):
		await process_frame
	var p = c.get("combat_scene_panel")
	p.reset_round_summary()
	# The shape of one Swift turn: three prose lines, the damage riding the last one.
	p.log_actor_action("monster", "Swift Hobgoblin", {}, "The Swift Hobgoblin attacks multiple times!")
	p.log_actor_action("monster", "Swift Hobgoblin", {}, "The Swift Hobgoblin strikes with unexpected ferocity!")
	p.log_actor_action("monster", "Swift Hobgoblin", {}, "The Swift Hobgoblin misses!")
	p.log_actor_action("monster", "Swift Hobgoblin", {"taken": 21}, "The Swift Hobgoblin hits 2 times for 21 total damage!")
	var a: Dictionary = p._round_actors["monster"]
	ck(int(a["hits"]) == 1, "four lines, one carrying damage = 1 hit, not 4 (got %d)" % int(a["hits"]))
	ck(String(p._log_lines[int(a["index"])]).find("4 hits") < 0, "the line never says '4 hits'")
	# Control: a player striking three times with damage on each IS three hits.
	p.reset_round_summary()
	for d in [10, 12, 9]:
		p.log_actor_action("player", "You", {"dmg": d}, "You hit for %d" % d)
	ck(int(p._round_actors["player"]["hits"]) == 3, "three damaging lines still count as 3 hits")
	ck(String(p._log_lines[int(p._round_actors["player"]["index"])]).find("3 hits") >= 0, "and the line says so")
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
