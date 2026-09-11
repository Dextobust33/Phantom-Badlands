extends SceneTree
## Dump DropTables.EGG_VARIANTS to tools/egg_variants.json for the Python matcher.
##
## Step 1 of regenerating the egg table. The matcher is Python (it needs PIL to measure pixels)
## and the variant list is GDScript, so the list is exported rather than parsed — parsing
## GDScript from Python would be a second, worse reader of the same data.
##
##   godot --headless --path . --script res://tools/dump_egg_variants.gd
##   python tools/bake_egg_variants.py
const DT := preload("res://shared/drop_tables.gd")

func _init() -> void:
	var out: Array = []
	for v in DT.EGG_VARIANTS:
		out.append({
			"name": String(v.get("name", "")),
			"color": String(v.get("color", "")),
			"color2": String(v.get("color2", "")),
			"pattern": String(v.get("pattern", "")),
			"rarity": int(v.get("rarity", 10)),
		})
	var f := FileAccess.open("res://tools/egg_variants.json", FileAccess.WRITE)
	if f == null:
		push_error("could not write tools/egg_variants.json")
		quit(1)
		return
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	print("dumped %d variants to tools/egg_variants.json" % out.size())
	quit(0)
