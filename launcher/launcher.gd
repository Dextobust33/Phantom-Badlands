# launcher.gd
# Auto-updating launcher for Phantom Badlands.
#
# UPDATE STRATEGY (v2 — exe/pck split):
# The client ships as two bundles so players don't re-download the ~100MB Godot
# runtime on every content update:
#   - RUNTIME bundle (exe + sqlite dll): rarely changes, versioned by
#     RUNTIME_VERSION.txt. Only re-downloaded when runtime_version changes.
#   - PCK bundle (PhantomBadlandsClient.pck + VERSION.txt + CREDITS.md): the game
#     content, changes every release — the only thing most updates download.
# A tiny `client-manifest.json` release asset declares the current
# content_version + runtime_version and the per-platform bundle asset names.
#
# BACKWARD COMPAT: if a release has no manifest (older releases), the launcher
# falls back to downloading the full client zip. We also keep shipping that full
# zip so older launchers keep working.
extends Control

const GITHUB_OWNER = "Dextobust33"
const GITHUB_REPO = "Phantom-Badlands"
const MAX_DOWNLOAD_RETRIES = 3

func _is_linux() -> bool:
	return OS.get_name() == "Linux"

func _client_executable() -> String:
	return "PhantomBadlandsClient.x86_64" if _is_linux() else "PhantomBadlandsClient.exe"

@onready var status_label = $VBox/StatusLabel
@onready var progress_bar = $VBox/ProgressBar
@onready var play_button = $VBox/PlayButton
@onready var version_label = $VBox/VersionLabel

var http_request: HTTPRequest
var download_request: HTTPRequest
var local_version = ""          # local content version (VERSION.txt)
var local_runtime = ""          # local runtime version (RUNTIME_VERSION.txt)
var remote_version = ""         # release tag (content version)
var game_path = ""
var download_retries = 0

# Release asset list (cached from the version check) + parsed manifest state.
var _assets: Array = []
var _target_content := ""
var _target_runtime := ""
# Queue of {"url": String, "name": String} bundles to download+extract in order.
var _download_queue: Array = []

func _ready():
	play_button.disabled = true
	play_button.pressed.connect(_on_play_pressed)
	game_path = OS.get_executable_path().get_base_dir()
	local_version = _load_marker("VERSION.txt")
	local_runtime = _load_marker("RUNTIME_VERSION.txt")
	version_label.text = "Local: %s" % [local_version if local_version else "Not installed"]
	_check_for_updates()

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
	var url = "https://api.github.com/repos/%s/%s/releases/latest" % [GITHUB_OWNER, GITHUB_REPO]
	var error = http_request.request(url, ["User-Agent: PhantomBadlandsLauncher/2.0"])
	if error != OK:
		status_label.text = "Failed to check for updates"
		_enable_play_if_installed()

func _find_asset_url(asset_name: String) -> String:
	# Exact-name match against the cached release assets.
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
	# Legacy fallback: the full client zip (platform-matched).
	var want_linux = _is_linux()
	for asset in _assets:
		var aname = String(asset.get("name", "")).to_lower()
		if not (aname.ends_with(".zip") and "client" in aname and "pck" not in aname):
			continue
		if ("linux" in aname) == want_linux:
			return String(asset.get("browser_download_url", ""))
	return ""

func _on_version_check_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
	http_request.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		status_label.text = "Could not reach update server"
		_enable_play_if_installed()
		return
	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		status_label.text = "Invalid update response"
		_enable_play_if_installed()
		return
	var data = json.data
	remote_version = String(data.get("tag_name", "")).trim_prefix("v")
	_assets = data.get("assets", [])
	version_label.text = "Local: %s | Latest: %s" % [local_version if local_version else "None", remote_version]

	# Prefer the split-update manifest; fall back to the full client zip.
	var manifest_url = _find_manifest_url()
	if manifest_url != "":
		_download_to_memory(manifest_url, _on_manifest_downloaded)
	else:
		_fallback_full_download()

# --- Split-update path -----------------------------------------------------

func _download_to_memory(url: String, cb: Callable) -> void:
	var req = HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(r, rc, _h, b):
		req.queue_free()
		cb.call(r, rc, b))
	if req.request(url, ["User-Agent: PhantomBadlandsLauncher/2.0", "Accept: application/octet-stream"]) != OK:
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
	# Runtime bundle: only when the runtime version changed (or nothing installed).
	var have_exe = FileAccess.file_exists(game_path.path_join(_client_executable()))
	if runtime_name != "" and (local_runtime != _target_runtime or not have_exe):
		var rurl = _find_asset_url(runtime_name)
		if rurl != "":
			_download_queue.append({"url": rurl, "name": "runtime"})
	# Content bundle: when the content version changed (or nothing installed).
	if pck_name != "" and (local_version != _target_content or not have_exe):
		var purl = _find_asset_url(pck_name)
		if purl != "":
			_download_queue.append({"url": purl, "name": "content"})

	if _download_queue.is_empty():
		if have_exe and local_version == _target_content and local_runtime == _target_runtime:
			status_label.text = "Game is up to date!"
			_enable_play_if_installed()
		else:
			# Manifest referenced assets we couldn't find — be safe, full download.
			_fallback_full_download()
		return

	var mb_note = "update" if _download_queue.size() > 1 or _download_queue[0].name == "runtime" else "content update"
	status_label.text = "Downloading %s: %s" % [mb_note, remote_version]
	download_retries = 0
	_process_download_queue()

func _process_download_queue() -> void:
	if _download_queue.is_empty():
		# All bundles applied — commit the version markers.
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

# --- Legacy full-download fallback -----------------------------------------

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
	# Full download updates both markers to the release version; runtime "" is fine.
	_target_content = remote_version
	_target_runtime = local_runtime if local_runtime != "" else "1"
	_download_queue = [{"url": url, "name": "content"}]
	status_label.text = "Update available: %s" % remote_version
	download_retries = 0
	_process_download_queue()

# --- Shared download + extract (one bundle at a time) ----------------------

func _start_download(url: String):
	progress_bar.value = 0
	download_request = HTTPRequest.new()
	download_request.download_file = game_path.path_join("update.zip")
	add_child(download_request)
	download_request.request_completed.connect(_on_download_completed)
	var error = download_request.request(url, [
		"User-Agent: PhantomBadlandsLauncher/2.0",
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
	var success = _extract_zip(zip_path, game_path)
	DirAccess.remove_absolute(zip_path)
	if not success:
		status_label.text = "Failed to extract update"
		_enable_play_if_installed()
		return
	if _is_linux():
		var exe_path = game_path.path_join(_client_executable())
		if FileAccess.file_exists(exe_path):
			OS.execute("chmod", ["+x", exe_path])
	# This bundle applied — move to the next in the queue.
	download_retries = 0
	_download_queue.pop_front()
	_process_download_queue()

func _extract_zip(zip_path: String, destination: String) -> bool:
	var reader = ZIPReader.new()
	if reader.open(zip_path) != OK:
		return false
	for file_path in reader.get_files():
		if file_path.ends_with("/"):
			DirAccess.make_dir_recursive_absolute(destination.path_join(file_path))
		else:
			var content = reader.read_file(file_path)
			var full_path = destination.path_join(file_path)
			DirAccess.make_dir_recursive_absolute(full_path.get_base_dir())
			var file = FileAccess.open(full_path, FileAccess.WRITE)
			if file:
				file.store_buffer(content)
	reader.close()
	return true

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
