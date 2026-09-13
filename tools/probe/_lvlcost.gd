extends SceneTree
const WS = preload("res://shared/world_system.gd")
const CM = preload("res://shared/chunk_manager.gd")
func _init():
	var cm = CM.new(); get_root().add_child(cm); cm.load_world_seed(); cm.load_npc_posts()
	var ws = WS.new(); get_root().add_child(ws); ws.chunk_manager = cm; cm.terrain_generator = ws
	ws.get_post_anchored_level(40, 40)
	var REPS := 20
	var t := Time.get_ticks_usec()
	for i in range(REPS):
		for dy in range(-11, 12):
			for dx in range(-11, 12):
				ws.get_post_anchored_level(40 + dx, 40 + dy)
	print("529x get_post_anchored_level: %.2f ms" % (float(Time.get_ticks_usec()-t)/float(REPS)/1000.0))
	var t2 := Time.get_ticks_usec()
	for i in range(REPS):
		for dy in range(-2, 4):
			for dx in range(-2, 4):
				ws.get_post_anchored_level(40 + dx*4, 40 + dy*4)
	print(" 36x (coarse 4x4 blocks):     %.2f ms" % (float(Time.get_ticks_usec()-t2)/float(REPS)/1000.0))
	quit()
