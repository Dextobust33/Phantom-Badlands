extends SceneTree
## Capture / compare the EXACT overworld display string.
##
## Phase 2.95 PHASE 1 turns `generate_map_display` into "build a payload, then inflate it". The
## whole promise of that step is that the player sees nothing change, so the only honest check is
## a byte-for-byte comparison against what the function produced before the refactor.
##
##   --script res://tools/probe/map_payload_golden.gd -- capture   (before, writes the golden)
##   --script res://tools/probe/map_payload_golden.gd              (after, compares)
const WorldSystemScript = preload("res://shared/world_system.gd")
const ChunkManagerScript = preload("res://shared/chunk_manager.gd")
const GOLDEN := "res://tools/probe/data/map_golden.json"

func _init() -> void:
	var capture := "capture" in OS.get_cmdline_user_args()
	var cm = ChunkManagerScript.new()
	get_root().add_child(cm)
	cm.load_world_seed()
	cm.load_npc_posts()
	var ws = WorldSystemScript.new()
	get_root().add_child(ws)
	ws.chunk_manager = cm
	cm.terrain_generator = ws

	# Spots chosen to reach all three header branches and both overlay families: open wilderness,
	# a coast, deep wilds, and ON several NPC posts (which take a different branch entirely).
	var spots: Array = [Vector2i(40, 40), Vector2i(0, 0), Vector2i(-120, 60), Vector2i(300, -200)]
	for i in range(mini(4, cm.get_npc_posts().size())):
		var p: Dictionary = cm.get_npc_posts()[i]
		spots.append(Vector2i(int(p.get("x", 0)), int(p.get("y", 0))))

	var got: Dictionary = {}
	for s in spots:
		var key := "%d,%d" % [s.x, s.y]
		# Two passes: the second sees `explored_tiles` already populated, which is the branch that
		# draws FOG - a whole rendering path the first pass never touches.
		var explored: Dictionary = {}
		var first: String = ws.generate_map_display(s.x, s.y, 11, [], [], [], [], [], explored, [], false, [])
		var away: String = ws.generate_map_display(s.x + 6, s.y + 6, 11, [], [], [], [], [], explored, [], false, [])
		# And one with every overlay family present at once, so players / dungeons / corpses /
		# bounties / sacks / threatened posts all render.
		var over: String = ws.generate_map_display(s.x, s.y, 11,
			[{"x": s.x + 1, "y": s.y, "name": "Kestrel", "in_my_party": true},
			 {"x": s.x + 2, "y": s.y, "name": "Vole"}, {"x": s.x + 2, "y": s.y, "name": "Wren"}],
			[{"x": s.x - 1, "y": s.y, "color": "#A335EE"}],
			["%d,%d" % [s.x, s.y + 1]],
			[{"x": s.x, "y": s.y - 1}],
			[{"x": s.x + 3, "y": s.y + 1}],
			explored, ["%d,%d" % [s.x - 2, s.y - 2]], true,
			[{"x": s.x - 3, "y": s.y + 2}])
		got[key] = [first, away, over]

	if capture:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/probe/data"))
		var f := FileAccess.open(GOLDEN, FileAccess.WRITE)
		f.store_string(JSON.stringify(got))
		f.close()
		print("[GOLDEN] captured %d spots x 3 views" % got.size())
		quit(0)
		return

	if not FileAccess.file_exists(GOLDEN):
		print("[GOLDEN] FAIL - no golden captured. Run with `-- capture` on the OLD code first.")
		quit(1)
		return
	var want: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN))
	var same := 0
	var diff := 0
	for key in want:
		for i in range(3):
			var a: String = String(want[key][i])
			var b: String = String(got.get(key, ["", "", ""])[i])
			if a == b:
				same += 1
			else:
				diff += 1
				if diff <= 2:
					print("  first difference at %s view %d:" % [key, i])
					for c in range(mini(a.length(), b.length())):
						if a[c] != b[c]:
							print("    byte %d: golden %s / now %s" % [c, JSON.stringify(a.substr(maxi(0, c - 40), 80)), JSON.stringify(b.substr(maxi(0, c - 40), 80))])
							break
					print("    lengths golden %d / now %d" % [a.length(), b.length()])
	print("  %d views identical, %d different" % [same, diff])
	print("[GOLDEN] %s" % ("PASS" if diff == 0 else "FAIL - %d view(s) changed" % diff))
	quit(0 if diff == 0 else 1)
