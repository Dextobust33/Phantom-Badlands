extends SceneTree
## ⛑ EVERY EFFECT ICON IS LOADED, NOT LOOKED AT.
##
## `ResourceLoader.exists()` returns TRUE for a file under a `.gdignore`, because the `.import`
## sidecar is sitting right there - while `load()` returns null, nothing reaches the .pck, and an
## `[img]` tag whose texture fails to load draws **nothing at all**: no gap, no placeholder, no
## error. A HUD that was supposed to gain icons looks byte-identical to one that never had them.
## That cost a round of A/B-ing three `[img]` forms on 2026-09-16 before `ls .godot/imported/`
## settled it in one command.
##
## So this calls `load()` on every path the effect tables name - which is the same rule the
## release gate learned the hard way when v0.9.761 shipped with all 53 monster sprites broken:
## the files were checked, the row count was checked, and the resolver was never called once.
##
## It covers BUFF_ICONS and STATE_ICONS together because they are the same failure with two
## tables, and because `BUFF_ICONS` gained two entries on 2026-09-16 (`open_guard_penalty` and
## `time_stop`) that had never been loaded by anything.
##
## Run:
##   godot --headless --path . --script res://tools/probe/effect_icons_load.gd

const Client := preload("res://client/client.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	print("===== 1. EVERY BUFF ICON LOADS =====")
	var buffs: Dictionary = Client.BUFF_ICONS
	ck(not buffs.is_empty(), "the table is not empty (%d entries)" % buffs.size())
	var seen := {}
	for key in buffs.keys():
		var path: String = String(buffs[key].get("path", ""))
		ck(path != "", "%s names a path" % key)
		if path == "":
			continue
		# `exists()` deliberately NOT used - see the header. The only honest question is whether
		# the texture comes back.
		var tex = load(path)
		ck(tex != null, "%s -> %s" % [key, path.get_file()])
		seen[path] = true

	print("\n===== 2. EVERY STATE ICON LOADS, AND ITS FRAME IS INSIDE THE SHEET =====")
	var sheet = load(Client.STATE_SHEET)
	ck(sheet != null, "the state sheet loads (%s)" % String(Client.STATE_SHEET).get_file())
	if sheet != null:
		var sw: int = sheet.get_width()
		var sh: int = sheet.get_height()
		print("           sheet is %dx%d" % [sw, sh])
		for key in Client.STATE_ICONS.keys():
			var d: Dictionary = Client.STATE_ICONS[key]
			var r: Array = d.get("rect", [])
			ck(r.size() == 4, "%s has a 4-part rect" % key)
			if r.size() != 4:
				continue
			# A frame that runs off the sheet does not fail - it samples empty pixels and draws a
			# blank square, which reads as "the icon is missing" and sends anyone looking at it
			# to the wrong place entirely.
			var fx: int = int(d.get("frame", 0)) * 96 + int(r[0])
			var fy: int = int(d.get("row", 0)) * 96 + int(r[1])
			ck(fx >= 0 and fy >= 0 and fx + int(r[2]) <= sw and fy + int(r[3]) <= sh,
				"%s frame sits inside the sheet (x %d..%d, y %d..%d)" % [
					key, fx, fx + int(r[2]), fy, fy + int(r[3])])

	print("\n===== 3. AND EVERY EFFECT THE GAME APPLIES HAS ONE =====")
	# The point of the icons is that a player can see what is on them. An applied effect with no
	# entry falls back to lettering, which is what the whole icon pass was replacing.
	var f := FileAccess.open("res://shared/combat_manager.gd", FileAccess.READ)
	var cm := f.get_as_text()
	f.close()
	var f2 := FileAccess.open("res://server/server.gd", FileAccess.READ)
	var sv := f2.get_as_text()
	f2.close()
	var applied := {}
	for src in [cm, sv]:
		var from: int = 0
		while true:
			var at: int = src.find('add_buff("', from)
			if at < 0:
				break
			var start: int = at + 10
			var stop: int = src.find('"', start)
			if stop > start:
				applied[src.substr(start, stop - start)] = true
			from = stop + 1
	var missing: Array[String] = []
	for key in applied.keys():
		if not buffs.has(key):
			missing.append(String(key))
	missing.sort()
	ck(missing.is_empty(), "no applied effect is left without an icon")
	for m in missing:
		print("           %s is applied but has no icon" % m)

	print("\n===== VERDICT =====")
	print("  all checks PASS" if fails == 0 else "  %d check(s) FAIL" % fails)
	quit(0)
