extends SceneTree
## The launcher self-update must not be silently inert.
##
## Owner 2026-09-11: *"We historically had a way for the client to download the launcher and
## effectively 'self update' it without players having to reinstall the launcher from the site.
## Is that something we can still do here?"*
##
## Yes - and it is built TWICE, on both sides:
##   launcher.gd  updates ITSELF when the manifest's launcher_version differs from its own
##   client.gd    replaces the launcher for anyone still on a pre-self-update one (the bootstrap)
##
## Both read `launcher_version` out of client-manifest.json and BOTH EXPLICITLY BAIL when it is
## missing. The manifest was hand-written into the release command and omitted that field, so the
## whole capability sat dead - a complete feature switched off by an absent line. CLAUDE.md even
## recorded the symptom ("it does not self-update") as though it were the design.

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _lv_from_source() -> String:
	var src := FileAccess.get_file_as_string("res://launcher/launcher.gd")
	var re := RegEx.new()
	re.compile("const\\s+LAUNCHER_VERSION\\s*=\\s*\"([^\"]+)\"")
	var m := re.search(src)
	return m.get_string(1) if m != null else ""


func _init() -> void:
	print("--- both update paths still exist ---")
	var lsrc := FileAccess.get_file_as_string("res://launcher/launcher.gd")
	var csrc := FileAccess.get_file_as_string("res://client/client.gd")
	ck(lsrc.contains('var lver := String(m.get("launcher_version", ""))'),
		"the launcher reads launcher_version from the manifest")
	ck(lsrc.contains("_start_launcher_self_update("), "...and updates itself when it differs")
	ck(csrc.contains("func _maybe_update_launcher()"),
		"the client carries the bootstrap updater for old launchers")
	ck(csrc.contains('var target_lv := String(m.get("launcher_version", ""))'),
		"...and keys off the same field")
	ck(csrc.contains('call_deferred("_maybe_update_launcher")'), "...and it is actually called")

	print("\n--- and the manifest FEEDS them, which is what was missing ---")
	var mf := FileAccess.get_file_as_string("res://releases/client-manifest.json")
	ck(mf != "", "the manifest exists")
	var j := JSON.new()
	ck(j.parse(mf) == OK, "...and parses")
	var m: Dictionary = j.data if j.data is Dictionary else {}
	var lv_manifest := String(m.get("launcher_version", ""))
	ck(lv_manifest != "",
		"it carries launcher_version - WITHOUT THIS both updaters return immediately")
	var lv_source := _lv_from_source()
	ck(lv_source != "", "launcher.gd declares LAUNCHER_VERSION (%s)" % lv_source)
	ck(lv_manifest == lv_source,
		"and the two agree (manifest %s, launcher.gd %s)" % [lv_manifest, lv_source])
	# The other two fields the game update needs.
	ck(String(m.get("content_version", "")) == FileAccess.get_file_as_string("res://VERSION.txt").strip_edges(),
		"content_version matches VERSION.txt")
	ck(String(m.get("runtime_version", "")) != "", "runtime_version is present")

	print("\n--- the manifest is GENERATED, not retyped ---")
	# Hand-typing it is precisely how the field went missing, twice.
	ck(FileAccess.file_exists("res://tools/make_client_manifest.py"),
		"there is a generator that reads the versions from source")
	var gen := FileAccess.get_file_as_string("res://tools/make_client_manifest.py")
	ck(gen.contains("LAUNCHER_VERSION"), "...and it reads LAUNCHER_VERSION out of launcher.gd")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
