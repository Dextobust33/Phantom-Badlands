# launcher.gd
# Auto-updating launcher for Phantom Badlands
extends Control

# CONFIGURE THESE FOR YOUR GITHUB REPO
const GITHUB_OWNER = "Dextobust33"
const GITHUB_REPO = "Phantom-Badlands"
const GAME_EXECUTABLE = "PhantomBadlandsClient.exe"

@onready var status_label = $VBox/StatusLabel
@onready var progress_bar = $VBox/ProgressBar
@onready var play_button = $VBox/PlayButton
@onready var version_label = $VBox/VersionLabel

var http_request: HTTPRequest
var download_request: HTTPRequest
var local_version = ""
var remote_version = ""
var download_url = ""
var game_path = ""

func _ready():
	play_button.disabled = true
	play_button.pressed.connect(_on_play_pressed)

	# Determine game path (same directory as launcher)
	game_path = OS.get_executable_path().get_base_dir()

	# Load local version
	local_version = _load_local_version()
	version_label.text = "Local: %s" % [local_version if local_version else "Not installed"]

	# Check for updates
	_check_for_updates()

func _load_local_version() -> String:
	var version_file = game_path.path_join("VERSION.txt")
	if FileAccess.file_exists(version_file):
		var file = FileAccess.open(version_file, FileAccess.READ)
		if file:
			return file.get_as_text().strip_edges()
	return ""

func _save_local_version(version: String):
	var version_file = game_path.path_join("VERSION.txt")
	var file = FileAccess.open(version_file, FileAccess.WRITE)
	if file:
		file.store_string(version)

func _check_for_updates():
	status_label.text = "Checking for updates..."
	progress_bar.value = 0

	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_version_check_completed)

	var url = "https://api.github.com/repos/%s/%s/releases/latest" % [GITHUB_OWNER, GITHUB_REPO]
	var headers = ["User-Agent: PhantomBadlandsLauncher/1.0"]

	var error = http_request.request(url, headers)
	if error != OK:
		status_label.text = "Failed to check for updates"
		_enable_play_if_installed()

func _on_version_check_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	http_request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		status_label.text = "Could not reach update server"
		_enable_play_if_installed()
		return

	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		status_label.text = "Invalid update response"
		_enable_play_if_installed()
		return

	var data = json.data
	remote_version = data.get("tag_name", "").trim_prefix("v")
	version_label.text = "Local: %s | Latest: %s" % [
		local_version if local_version else "None",
		remote_version
	]

	# Find the Windows client asset
	var assets = data.get("assets", [])
	for asset in assets:
		var name = asset.get("name", "")
		if "client" in name.to_lower() and name.ends_with(".zip"):
			download_url = asset.get("browser_download_url", "")
			break

	# Check if update needed
	if local_version == remote_version:
		status_label.text = "Game is up to date!"
		_enable_play_if_installed()
	elif download_url != "":
		status_label.text = "Update available: %s" % remote_version
		_start_download()
	else:
		status_label.text = "No download found in release"
		_enable_play_if_installed()

func _start_download():
	status_label.text = "Downloading update..."
	progress_bar.value = 0

	download_request = HTTPRequest.new()
	download_request.download_file = game_path.path_join("update.zip")
	add_child(download_request)
	download_request.request_completed.connect(_on_download_completed)

	var headers = ["User-Agent: PhantomBadlandsLauncher/1.0"]
	var error = download_request.request(download_url, headers)
	if error != OK:
		status_label.text = "Failed to start download"
		_enable_play_if_installed()

func _process(_delta):
	if download_request and download_request.get_body_size() > 0:
		var downloaded = download_request.get_downloaded_bytes()
		var total = download_request.get_body_size()
		progress_bar.value = (float(downloaded) / float(total)) * 100
		status_label.text = "Downloading... %.1f MB / %.1f MB" % [
			downloaded / 1048576.0,
			total / 1048576.0
		]

func _on_download_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	download_request.queue_free()
	download_request = null

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		status_label.text = "Download failed (code: %d)" % response_code
		_enable_play_if_installed()
		return

	progress_bar.value = 100
	status_label.text = "Extracting update..."

	# Extract the zip file
	await get_tree().process_frame  # Let UI update

	var zip_path = game_path.path_join("update.zip")
	var success = _extract_zip(zip_path, game_path)

	# Clean up zip file
	DirAccess.remove_absolute(zip_path)

	if success:
		_save_local_version(remote_version)
		local_version = remote_version
		version_label.text = "Local: %s | Latest: %s" % [local_version, remote_version]
		status_label.text = "Update complete! Ready to play."
	else:
		status_label.text = "Failed to extract update"

	_enable_play_if_installed()

func _extract_zip(zip_path: String, destination: String) -> bool:
	var reader = ZIPReader.new()
	var err = reader.open(zip_path)
	if err != OK:
		return false

	var files = reader.get_files()
	for file_path in files:
		if file_path.ends_with("/"):
			# Directory - create it
			DirAccess.make_dir_recursive_absolute(destination.path_join(file_path))
		else:
			# File - extract it
			var content = reader.read_file(file_path)
			var full_path = destination.path_join(file_path)

			# Ensure parent directory exists
			var dir = full_path.get_base_dir()
			DirAccess.make_dir_recursive_absolute(dir)

			var file = FileAccess.open(full_path, FileAccess.WRITE)
			if file:
				file.store_buffer(content)

	reader.close()
	return true

func _enable_play_if_installed():
	var exe_path = game_path.path_join(GAME_EXECUTABLE)
	play_button.disabled = not FileAccess.file_exists(exe_path)
	if play_button.disabled:
		play_button.text = "Game Not Found"
	else:
		play_button.text = "Play Phantom Badlands"

func _on_play_pressed():
	var exe_path = game_path.path_join(GAME_EXECUTABLE)
	if FileAccess.file_exists(exe_path):
		status_label.text = "Launching game..."
		OS.create_process(exe_path, [])
		await get_tree().create_timer(1.0).timeout
		get_tree().quit()
