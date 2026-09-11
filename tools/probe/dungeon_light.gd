extends SceneTree
## Does the lighting shader compile, and does every uniform the client sets actually exist?
##
## `set_shader_parameter` with a name the shader does not declare fails SILENTLY - no error, no
## warning, the value simply goes nowhere. A torch that never moves because `player_uv` was typed
## `player_pos` would look like a design problem rather than a typo, so the names are checked
## against the shader source instead of trusted.
const SHADER := "res://client/shaders/dungeon_light.gdshader"
const CLIENT := "res://client/client.gd"

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var sh = load(SHADER)
	ck(sh != null, "the shader loads and compiles")
	if sh == null:
		quit(1)
		return

	# what the shader DECLARES. Character classes rather than \\w, so the pattern survives being
	# written through a shell.
	var src := FileAccess.get_file_as_string(SHADER)
	var re := RegEx.new()
	re.compile("uniform[ \t]+[a-z0-9]+[ \t]+([A-Za-z_]+)")
	var declared := {}
	for m in re.search_all(src):
		declared[m.get_string(1)] = true
	print("      shader declares: %s" % ", ".join(declared.keys()))

	# what the CLIENT sets on this material
	var cs := FileAccess.get_file_as_string(CLIENT)
	var re2 := RegEx.new()
	re2.compile("_dungeon_light_material[.]set_shader_parameter[(][\"]([A-Za-z_]+)[\"]")
	var used := {}
	for m in re2.search_all(cs):
		used[m.get_string(1)] = true
	print("      client sets:     %s" % ", ".join(used.keys()))
	ck(used.size() > 0, "the client actually sets uniforms (the scan found the call site)")
	for u in used:
		ck(declared.has(u), "'%s' is declared by the shader" % u)

	print("--- the material accepts them at runtime ---")
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("ambient", 0.62)
	mat.set_shader_parameter("player_uv", Vector2(0.3, 0.4))
	var pv := PackedVector2Array()
	for i in range(24):
		pv.append(Vector2(-9, -9))
	mat.set_shader_parameter("lights", pv)
	mat.set_shader_parameter("light_count", 3)
	ck(abs(float(mat.get_shader_parameter("ambient")) - 0.62) < 0.001,
		"a value set on the material reads back (0.62 ambient, the chosen default)")
	ck(Vector2(mat.get_shader_parameter("player_uv")).is_equal_approx(Vector2(0.3, 0.4)),
		"the torch centre is settable OFF-centre, which floor edges require")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
