# launcher.gd
# Auto-updating launcher for Phantom Badlands.
#
# UI (v2.1 revamp): a larger window with a two-column layout — left = update status +
# Play button, right = a live "Recent Changes" panel fetched from GitHub release notes.
# Two top-right feedback buttons (Suggest Idea / Report Issue) open a dialog that POSTs
# the player's text (+ optional screenshot) to a private Discord webhook. The webhook URL
# lives in a gitignored res://webhook_secret.gd (bundled at export, never committed); if
# it's absent the feedback buttons simply disable.
#
# UPDATE STRATEGY (v2 — exe/pck split), unchanged:
#   - RUNTIME bundle (exe + sqlite dll): versioned by RUNTIME_VERSION.txt, rarely changes.
#   - PCK bundle (pck + VERSION.txt + CREDITS.md): game content, changes every release.
# A client-manifest.json release asset declares versions + per-platform bundle names.
# Falls back to the full client zip when a release has no manifest.
extends Control

const GITHUB_OWNER = "Dextobust33"
const GITHUB_REPO = "Phantom-Badlands"
const MAX_DOWNLOAD_RETRIES = 3
const LAUNCHER_VERSION = "2.1"  # bump when launcher.gd changes (surfaced in feedback + future self-update)

func _is_linux() -> bool:
	return OS.get_name() == "Linux"

func _client_executable() -> String:
	return "PhantomBadlandsClient.x86_64" if _is_linux() else "PhantomBadlandsClient.exe"

func _expected_content_file() -> String:
	return "PhantomBadlandsClient.x86_64" if _is_linux() else "PhantomBadlandsClient.pck"

func _expected_runtime_file() -> String:
	return "PhantomBadlandsClient.x86_64" if _is_linux() else "PhantomBadlandsClient.exe"

# --- UI nodes (built in code) ---
var status_label: Label
var progress_bar: ProgressBar
var play_button: Button
var version_label: Label
var changelog_label: RichTextLabel

# --- update state ---
var http_request: HTTPRequest
var download_request: HTTPRequest
var local_version = ""
var local_runtime = ""
var remote_version = ""
var game_path = ""
var download_retries = 0
var _assets: Array = []
var _target_content := ""
var _target_runtime := ""
var _download_queue: Array = []
var _pending_pck := ""            # manifest pck asset name (deferred while a launcher self-update runs)
var _pending_runtime_name := ""   # manifest runtime asset name

# --- feedback ---
var _webhook_url := ""
var _feedback_kind := ""
var _feedback_dialog: AcceptDialog
var _feedback_text: TextEdit
var _feedback_status: Label
var _feedback_shot_path := ""
var _feedback_shot_label: Label
var _file_dialog: FileDialog


func _ready():
	_load_webhook()
	_build_ui()
	play_button.disabled = true
	play_button.pressed.connect(_on_play_pressed)
	game_path = OS.get_executable_path().get_base_dir()
	local_version = _load_marker("VERSION.txt")
	local_runtime = _load_marker("RUNTIME_VERSION.txt")
	version_label.text = "Local: %s" % [local_version if local_version else "Not installed"]
	_check_for_updates()


func _load_webhook():
	# Read the Discord webhook URL from a gitignored, export-bundled script. Absent → disabled.
	if FileAccess.file_exists("res://webhook_secret.gd"):
		var s = load("res://webhook_secret.gd")
		if s:
			var inst = s.new()
			var v = inst.get("URL") if inst else null
			if typeof(v) == TYPE_STRING and String(v) != "":
				_webhook_url = String(v)


# ============================ UI ============================

func _build_ui():
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(m, 18)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	# --- Top bar: title + feedback buttons ---
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	root.add_child(top)
	var title := Label.new()
	title.text = "Phantom Badlands"
	title.add_theme_font_size_override("font_size", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)

	var idea_btn := Button.new()
	idea_btn.text = "💡 Suggest Idea"
	idea_btn.focus_mode = Control.FOCUS_NONE
	idea_btn.pressed.connect(func(): _open_feedback("idea"))
	top.add_child(idea_btn)
	var issue_btn := Button.new()
	issue_btn.text = "🐞 Report Issue"
	issue_btn.focus_mode = Control.FOCUS_NONE
	issue_btn.pressed.connect(func(): _open_feedback("issue"))
	top.add_child(issue_btn)
	if _webhook_url == "":
		idea_btn.disabled = true
		issue_btn.disabled = true
		idea_btn.tooltip_text = "Feedback is unavailable in this build."
		issue_btn.tooltip_text = "Feedback is unavailable in this build."

	# --- Main: two columns ---
	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 16)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(main)

	# Left column: status + version + Play
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	left.custom_minimum_size = Vector2(320, 0)
	main.add_child(left)

	var sub := Label.new()
	sub.text = "A text-based multiplayer RPG"
	sub.add_theme_color_override("font_color", Color(0.7, 0.7, 0.78))
	left.add_child(sub)

	status_label = Label.new()
	status_label.text = "Checking for updates..."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 14)
	left.add_child(status_label)

	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(0, 22)
	progress_bar.show_percentage = false
	left.add_child(progress_bar)

	version_label = Label.new()
	version_label.add_theme_font_size_override("font_size", 12)
	version_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	left.add_child(version_label)

	var lspacer := Control.new()
	lspacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(lspacer)

	play_button = Button.new()
	play_button.text = "Play Phantom Badlands"
	play_button.custom_minimum_size = Vector2(0, 56)
	play_button.add_theme_font_size_override("font_size", 20)
	left.add_child(play_button)

	# Right column: changelog panel
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.11, 0.16, 1)
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.28, 0.28, 0.4, 1)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)
	main.add_child(panel)

	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 8)
	panel.add_child(pv)
	var ch_title := Label.new()
	ch_title.text = "📜 Recent Changes"
	ch_title.add_theme_font_size_override("font_size", 16)
	pv.add_child(ch_title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pv.add_child(scroll)
	changelog_label = RichTextLabel.new()
	changelog_label.bbcode_enabled = true
	changelog_label.fit_content = true
	changelog_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	changelog_label.custom_minimum_size = Vector2(500, 0)
	changelog_label.append_text("[color=#888888]Loading recent changes…[/color]")
	scroll.add_child(changelog_label)


# ============================ update check ============================

func _load_marker(fname: String) -> String:
	var p = game_path.path_join(fname)
	if FileAccess.file_exists(p):
		var f = FileAccess.open(p, FileAccess.READ)
		if f:
			return f.get_as_text().strip_edges()
	return ""

func _save_marker(fname: String, value: String) -> void:
	var f = FileAccess.open(game_path.path_join(fname), FileAccess.WRITE)
	if f:
		f.store_string(value)

func _check_for_updates():
	status_label.text = "Checking for updates..."
	progress_bar.value = 0
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_version_check_completed)
	# Fetch the recent RELEASES LIST (not just /latest) so we get changelog + the latest in one call.
	var url = "https://api.github.com/repos/%s/%s/releases?per_page=8" % [GITHUB_OWNER, GITHUB_REPO]
	var error = http_request.request(url, ["User-Agent: PhantomBadlandsLauncher/2.1"])
	if error != OK:
		status_label.text = "Failed to check for updates"
		_enable_play_if_installed()

func _on_version_check_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
	http_request.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		status_label.text = "Could not reach update server"
		changelog_label.clear()
		changelog_label.append_text("[color=#888888]Couldn't load recent changes (offline?).[/color]")
		_enable_play_if_installed()
		return
	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		status_label.text = "Invalid update response"
		_enable_play_if_installed()
		return
	var releases = json.data
	if not (releases is Array) or releases.is_empty():
		status_label.text = "No releases found"
		_enable_play_if_installed()
		return
	_render_changelog(releases)
	var latest = releases[0]
	remote_version = String(latest.get("tag_name", "")).trim_prefix("v")
	_assets = latest.get("assets", [])
	version_label.text = "Local: %s | Latest: %s" % [local_version if local_version else "None", remote_version]

	# Prefer the split-update manifest; fall back to the full client zip.
	var manifest_url = _find_manifest_url()
	if manifest_url != "":
		_download_to_memory(manifest_url, _on_manifest_downloaded)
	else:
		_fallback_full_download()

func _render_changelog(releases: Array) -> void:
	changelog_label.clear()
	var count = min(6, releases.size())
	for i in range(count):
		var r = releases[i]
		if not (r is Dictionary):
			continue
		var tag = String(r.get("tag_name", ""))
		var rname = String(r.get("name", tag))
		if rname.strip_edges() == "":
			rname = tag
		var bodytext = String(r.get("body", ""))
		changelog_label.push_color(Color(1.0, 0.84, 0.0))
		changelog_label.push_bold()
		changelog_label.add_text(rname + "\n")
		changelog_label.pop()
		changelog_label.pop()
		if bodytext.strip_edges() != "":
			changelog_label.push_color(Color(0.80, 0.80, 0.86))
			changelog_label.add_text(_clean_md(bodytext) + "\n")
			changelog_label.pop()
		changelog_label.add_text("\n")

func _clean_md(s: String) -> String:
	# Light markdown → plain text so GitHub release notes read cleanly (no bbcode injection:
	# we use add_text, which renders literally). Drop ** emphasis, tidy bullets, strip images.
	s = s.replace("**", "").replace("__", "")
	var lines = s.split("\n")
	var out: Array = []
	for ln in lines:
		var t = String(ln).strip_edges()
		if t.begins_with("🤖") or t.begins_with("![") or t.begins_with("Co-Authored-By"):
			continue
		if t.begins_with("- ") or t.begins_with("* "):
			out.append("  • " + t.substr(2))
		else:
			out.append(ln)
	return "\n".join(out)


# --- asset lookup (unchanged) ---

func _find_asset_url(asset_name: String) -> String:
	for asset in _assets:
		if String(asset.get("name", "")) == asset_name:
			return String(asset.get("browser_download_url", ""))
	return ""

func _find_manifest_url() -> String:
	for asset in _assets:
		if String(asset.get("name", "")).to_lower() == "client-manifest.json":
			return String(asset.get("browser_download_url", ""))
	return ""

func _find_full_client_url() -> String:
	var want_linux = _is_linux()
	for asset in _assets:
		var aname = String(asset.get("name", "")).to_lower()
		if not (aname.ends_with(".zip") and "client" in aname and "pck" not in aname):
			continue
		if ("linux" in aname) == want_linux:
			return String(asset.get("browser_download_url", ""))
	return ""

# --- split-update path (unchanged) ---

func _download_to_memory(url: String, cb: Callable) -> void:
	var req = HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(r, rc, _h, b):
		req.queue_free()
		cb.call(r, rc, b))
	if req.request(url, ["User-Agent: PhantomBadlandsLauncher/2.1", "Accept: application/octet-stream"]) != OK:
		_fallback_full_download()

func _on_manifest_downloaded(result: int, response_code: int, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_fallback_full_download()
		return
	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		_fallback_full_download()
		return
	var m = json.data
	if not (m is Dictionary):
		_fallback_full_download()
		return
	_target_content = String(m.get("content_version", remote_version))
	_target_runtime = String(m.get("runtime_version", ""))
	var plat = "linux" if _is_linux() else "windows"
	var plat_map = m.get(plat, {})
	var pck_name = String(plat_map.get("pck", ""))
	var runtime_name = String(plat_map.get("runtime", ""))

	_download_queue.clear()
	var have_exe = FileAccess.file_exists(game_path.path_join(_client_executable()))
	if runtime_name != "" and (local_runtime != _target_runtime or not have_exe):
		var rurl = _find_asset_url(runtime_name)
		if rurl != "":
			_download_queue.append({"url": rurl, "name": "runtime"})
	if pck_name != "" and (local_version != _target_content or not have_exe):
		var purl = _find_asset_url(pck_name)
		if purl != "":
			_download_queue.append({"url": purl, "name": "content"})

	if _download_queue.is_empty():
		if have_exe and local_version == _target_content and local_runtime == _target_runtime:
			status_label.text = "Game is up to date!"
			_enable_play_if_installed()
		else:
			_fallback_full_download()
		return

	var mb_note = "update" if _download_queue.size() > 1 or _download_queue[0].name == "runtime" else "content update"
	status_label.text = "Downloading %s: %s" % [mb_note, remote_version]
	download_retries = 0
	_process_download_queue()

func _process_download_queue() -> void:
	if _download_queue.is_empty():
		_save_marker("VERSION.txt", _target_content)
		_save_marker("RUNTIME_VERSION.txt", _target_runtime)
		local_version = _target_content
		local_runtime = _target_runtime
		version_label.text = "Local: %s | Latest: %s" % [local_version, remote_version]
		status_label.text = "Update complete! Ready to play."
		_enable_play_if_installed()
		return
	var next = _download_queue[0]
	_start_download(String(next.url))

# --- legacy full-download fallback (unchanged) ---

func _fallback_full_download() -> void:
	if local_version == remote_version and FileAccess.file_exists(game_path.path_join(_client_executable())):
		status_label.text = "Game is up to date!"
		_enable_play_if_installed()
		return
	var url = _find_full_client_url()
	if url == "":
		status_label.text = "No download found in release"
		_enable_play_if_installed()
		return
	_target_content = remote_version
	_target_runtime = local_runtime if local_runtime != "" else "1"
	_download_queue = [{"url": url, "name": "content"}]
	status_label.text = "Update available: %s" % remote_version
	download_retries = 0
	_process_download_queue()

# --- shared download + extract (unchanged) ---

func _start_download(url: String):
	progress_bar.value = 0
	download_request = HTTPRequest.new()
	download_request.download_file = game_path.path_join("update.zip")
	add_child(download_request)
	download_request.request_completed.connect(_on_download_completed)
	var error = download_request.request(url, [
		"User-Agent: PhantomBadlandsLauncher/2.1",
		"Accept: application/octet-stream"
	])
	if error != OK:
		status_label.text = "Failed to start download"
		_enable_play_if_installed()

func _process(_delta):
	if download_request and download_request.get_body_size() > 0:
		var downloaded = download_request.get_downloaded_bytes()
		var total = download_request.get_body_size()
		progress_bar.value = (float(downloaded) / float(total)) * 100
		status_label.text = "Downloading... %.1f MB / %.1f MB" % [downloaded / 1048576.0, total / 1048576.0]

func _on_download_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray):
	download_request.queue_free()
	download_request = null
	var zip_path = game_path.path_join("update.zip")
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		if response_code >= 500 and download_retries < MAX_DOWNLOAD_RETRIES:
			download_retries += 1
			status_label.text = "Download failed (code: %d), retrying (%d/%d)..." % [response_code, download_retries, MAX_DOWNLOAD_RETRIES]
			if FileAccess.file_exists(zip_path):
				DirAccess.remove_absolute(zip_path)
			await get_tree().create_timer(2.0).timeout
			_start_download(String(_download_queue[0].url))
			return
		status_label.text = "Download failed (code: %d)" % response_code
		_enable_play_if_installed()
		return

	progress_bar.value = 100
	status_label.text = "Extracting update..."
	await get_tree().process_frame
	var written = _extract_zip(zip_path, game_path)
	DirAccess.remove_absolute(zip_path)
	if written.is_empty():
		status_label.text = "Failed to extract update (no files written)"
		_enable_play_if_installed()
		return

	var bundle_name = String(_download_queue[0].get("name", ""))
	var required = _expected_runtime_file() if bundle_name == "runtime" else _expected_content_file()
	if not (required in written):
		status_label.text = "Update was for the wrong platform (missing %s). Aborted — please re-download the launcher." % required
		_enable_play_if_installed()
		return

	if _is_linux():
		var exe_path = game_path.path_join(_client_executable())
		if FileAccess.file_exists(exe_path):
			OS.execute("chmod", ["+x", exe_path])
	download_retries = 0
	_download_queue.pop_front()
	_process_download_queue()

func _extract_zip(zip_path: String, destination: String) -> Array:
	var written: Array = []
	var reader = ZIPReader.new()
	if reader.open(zip_path) != OK:
		return []
	for file_path in reader.get_files():
		if file_path.ends_with("/"):
			DirAccess.make_dir_recursive_absolute(destination.path_join(file_path))
			continue
		var content = reader.read_file(file_path)
		var full_path = destination.path_join(file_path)
		DirAccess.make_dir_recursive_absolute(full_path.get_base_dir())
		if FileAccess.file_exists(full_path):
			DirAccess.remove_absolute(full_path)
		var file = FileAccess.open(full_path, FileAccess.WRITE)
		if file:
			file.store_buffer(content)
			file.close()
			if FileAccess.file_exists(full_path) and FileAccess.open(full_path, FileAccess.READ).get_length() == content.size():
				written.append(full_path.get_file())
	reader.close()
	return written

func _enable_play_if_installed():
	var exe_path = game_path.path_join(_client_executable())
	play_button.disabled = not FileAccess.file_exists(exe_path)
	play_button.text = "Game Not Found" if play_button.disabled else "Play Phantom Badlands"

func _on_play_pressed():
	var exe_path = game_path.path_join(_client_executable())
	if FileAccess.file_exists(exe_path):
		status_label.text = "Launching game..."
		OS.create_process(exe_path, [])
		await get_tree().create_timer(1.0).timeout
		get_tree().quit()


# ============================ feedback → Discord ============================

func _open_feedback(kind: String):
	if _webhook_url == "":
		return
	_feedback_kind = kind
	_feedback_shot_path = ""
	if _feedback_dialog == null:
		_build_feedback_dialog()
	_feedback_dialog.title = "Suggest an Idea" if kind == "idea" else "Report an Issue"
	_feedback_text.text = ""
	_feedback_status.text = ""
	_feedback_shot_label.text = "No screenshot attached"
	_feedback_dialog.popup_centered(Vector2i(580, 440))
	_feedback_text.grab_focus()

func _build_feedback_dialog():
	_feedback_dialog = AcceptDialog.new()
	_feedback_dialog.ok_button_text = "Send"
	_feedback_dialog.confirmed.connect(_on_feedback_send)
	add_child(_feedback_dialog)

	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(540, 360)
	vb.add_theme_constant_override("separation", 8)
	_feedback_dialog.add_child(vb)

	var lbl := Label.new()
	lbl.text = "Tell us what you think — be as detailed as you like:"
	vb.add_child(lbl)

	_feedback_text = TextEdit.new()
	_feedback_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_feedback_text.custom_minimum_size = Vector2(0, 220)
	_feedback_text.placeholder_text = "Your idea or the issue you're hitting…"
	_feedback_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	vb.add_child(_feedback_text)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)
	var attach := Button.new()
	attach.text = "Attach screenshot…"
	attach.focus_mode = Control.FOCUS_NONE
	attach.pressed.connect(_on_attach_screenshot)
	row.add_child(attach)
	_feedback_shot_label = Label.new()
	_feedback_shot_label.text = "No screenshot attached"
	_feedback_shot_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	row.add_child(_feedback_shot_label)

	_feedback_status = Label.new()
	_feedback_status.add_theme_color_override("font_color", Color(0.6, 0.85, 0.6))
	vb.add_child(_feedback_status)

func _on_attach_screenshot():
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.use_native_dialog = true
		_file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg ; Images"])
		_file_dialog.file_selected.connect(func(p):
			_feedback_shot_path = p
			if _feedback_shot_label:
				_feedback_shot_label.text = String(p).get_file())
		add_child(_file_dialog)
	_file_dialog.popup_centered(Vector2i(760, 520))

func _on_feedback_send():
	var txt := _feedback_text.text.strip_edges()
	if txt == "" or _webhook_url == "":
		return
	var kind_tag := "💡 IDEA" if _feedback_kind == "idea" else "🐞 ISSUE"
	var meta := "launcher v%s · %s · client %s" % [LAUNCHER_VERSION, OS.get_name(), (local_version if local_version else "not installed")]
	# Discord hard-caps content at 2000 chars.
	var content := "%s  (%s)\n%s" % [kind_tag, meta, txt]
	if content.length() > 1950:
		content = content.substr(0, 1950) + "…"
	if _feedback_shot_path != "" and FileAccess.file_exists(_feedback_shot_path):
		_post_feedback_multipart(content, _feedback_shot_path)
	else:
		_post_feedback_json(content)
	status_label.text = "Thanks! Your feedback was sent. 🙏"

func _post_feedback_json(content: String):
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(_r, _rc, _h, _b): req.queue_free())
	var payload := JSON.stringify({"content": content, "username": "PB Launcher"})
	req.request(_webhook_url, ["Content-Type: application/json", "User-Agent: PhantomBadlandsLauncher/2.1"], HTTPClient.METHOD_POST, payload)

func _post_feedback_multipart(content: String, path: String):
	var img := FileAccess.get_file_as_bytes(path)
	if img.is_empty():
		_post_feedback_json(content)
		return
	var boundary := "----PBLauncher%dBoundary" % Time.get_ticks_msec()
	var fname := String(path).get_file()
	var pre := PackedByteArray()
	pre.append_array(("--%s\r\nContent-Disposition: form-data; name=\"payload_json\"\r\nContent-Type: application/json\r\n\r\n" % boundary).to_utf8_buffer())
	pre.append_array(JSON.stringify({"content": content, "username": "PB Launcher"}).to_utf8_buffer())
	pre.append_array(("\r\n--%s\r\nContent-Disposition: form-data; name=\"files[0]\"; filename=\"%s\"\r\nContent-Type: application/octet-stream\r\n\r\n" % [boundary, fname]).to_utf8_buffer())
	var post := PackedByteArray()
	post.append_array(("\r\n--%s--\r\n" % boundary).to_utf8_buffer())
	var full := PackedByteArray()
	full.append_array(pre)
	full.append_array(img)
	full.append_array(post)
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(_r, _rc, _h, _b): req.queue_free())
	req.request_raw(_webhook_url, ["Content-Type: multipart/form-data; boundary=%s" % boundary, "User-Agent: PhantomBadlandsLauncher/2.1"], HTTPClient.METHOD_POST, full)
