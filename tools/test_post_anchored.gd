extends SceneTree

const WorldSystemScript = preload("res://shared/world_system.gd")

func _initialize():
	var ws = WorldSystemScript.new()
	get_root().add_child(ws)

	var samples = [
		[0, 10, "Haven (T1)"],
		[0, 0, "Crossroads (T1)"],
		[0, 75, "Northwatch (T2)"],
		[40, 40, "Northeast Farm (T2)"],
		[150, 0, "Eastwatch (T3)"],
		[120, 120, "NE Bastion (T3)"],
		[250, 0, "Far East Station (T4)"],
		[200, 200, "NE Frontier (T4)"],
		[300, 300, "Shadowmere (T5)"],
		[0, 350, "Storm Peak (T5)"],
		[0, 500, "Primordial Sanctum (T6)"],
		[500, 0, "Eastern Terminus (T6)"],
		[0, 700, "World's Spine N (T7)"],
		[550, 550, "Apex NE (T7)"],
		[0, 35, "between Haven and Northwatch"],
		[0, 50, "between Haven and Northwatch (closer to NW)"],
		[100, 0, "wilderness east of Haven"],
		[300, 0, "wilderness east"],
		[1000, 1000, "deep wilderness"],
		[2000, 0, "near edge"],
		[2800, 0, "world corner-ish"],
		[200, 0, "midway between Eastwatch(T3) and Far East Station(T4)"],
		[200, 100, "off-axis between Eastwatch and NE Bastion"],
		[400, 400, "outside Apex NE bubble, deep wilderness"],
		[125, 125, "right next to NE Bastion"],
		[60, 60, "between NE Tower and NE Farm"],
	]

	print("=== Post-Anchored Level Smoke Test ===")
	print("%-40s %15s %15s" % ["coord", "post-anchored", "wilderness"])
	for s in samples:
		var x = s[0]
		var y = s[1]
		var label = s[2]
		var pa = ws.get_post_anchored_level(x, y)
		var wild = ws._distance_to_level(sqrt(float(x * x + y * y)))
		print("%-40s %15d %15d" % ["(%d,%d) %s" % [x, y, label], pa, wild])

	quit()
