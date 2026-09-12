extends SceneTree
## The overworld sprite map is a SETTING, and turning it off really returns the text map.
##
## Two project rules meet here. "A new entry point is a visible control, never a hidden variable"
## - so this lives on the Game Settings screen with the other toggles rather than as a flag only
## the code knows about. And the art is licence-restricted and not in git, so a build without it
## must still draw a map: the fallback has to be automatic as well as optional.
##
## What this holds is the WIRING, because the failure mode is silent: a setting that renders but
## never flips, or a key that lands on two rows at once, looks exactly like a working one until
## somebody uses it.
const SRC := "res://client/client.gd"

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _body(src: String, fname: String) -> String:
	var i := src.find("func %s(" % fname)
	if i < 0:
		return ""
	var j := src.find("\nfunc ", i + 10)
	return src.substr(i, (j if j > 0 else src.length()) - i)


func _init() -> void:
	var src := FileAccess.get_file_as_string(SRC)

	print("--- it is on the settings screen, and it says which way it is ---")
	var screen := _body(src, "display_game_settings")
	ck(screen.find("Overworld Map Sprites") >= 0, "the Game Settings screen offers it")
	ck(screen.find("sprites_status") >= 0, "and shows ON or OFF rather than leaving you to guess")
	ck(screen.find("_OverworldRoom.available()") >= 0,
		"...and says 'art not installed' instead of offering a switch that does nothing")

	print("\n--- the keys do not collide ---")
	# The row it took over used to open Stat Compare Priority. If both answer to 7, one press
	# does two things - the exact shape of the double-trigger bugs this project keeps hitting.
	ck(screen.find('display_game("[7] Overworld Map Sprites') >= 0 or screen.find('"[7] Overworld Map Sprites') >= 0,
		"sprites is row 7")
	ck(screen.find('[8] Stat Compare Priority') >= 0, "and stat priority moved to row 8")
	var dispatch_i := src.find("_toggle_overworld_sprites()")
	ck(dispatch_i > 0, "row 7 is wired to the toggle")
	var around := src.substr(maxi(0, dispatch_i - 200), 500)
	ck(around.find("elif keycode == KEY_8:") >= 0 and around.find("_display_stat_priority_settings()") >= 0,
		"...and KEY_8 now opens stat priority, so no key answers twice")

	print("\n--- it actually flips something, and it is remembered ---")
	var t := _body(src, "_toggle_overworld_sprites")
	ck(t != "", "_toggle_overworld_sprites exists")
	ck(t.find("overworld_sprites = not overworld_sprites") >= 0, "it flips the flag")
	ck(t.find("_save_keybinds()") >= 0, "and saves, so the choice survives a restart")
	ck(src.find('save_data["overworld_sprites"] = overworld_sprites') >= 0, "...which writes it")
	ck(src.find('if data.has("overworld_sprites"):') >= 0, "...and reads it back")

	print("\n--- and OFF really means the text map ---")
	var disp := _body(src, "_overworld_display")
	ck(disp.find("if not overworld_sprites or not _OverworldRoom.available():") >= 0,
		"the very first thing the renderer does is honour the setting")
	ck(disp.count("return MapPayload.inflate(payload)") == 3,
		"and all three exits return the text map the server has always sent")

	print("\n[OVERWORLDTOGGLE] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
