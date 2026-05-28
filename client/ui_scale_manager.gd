extends Node
class_name UIScaleManager

# v0.9.646 — per-element UI scale registry. Layered on top of the existing
# 7-category bulk scales (ui_scale_monster_art / ui_scale_map / etc in
# client.gd) so individual elements can be tweaked without changing the broad
# defaults. Designed for the click-to-scale edit mode in
# ui_scale_edit_overlay.gd.
#
# Each panel that has a scalable element calls register() during init with:
#   - group_id: stable string ID (e.g. "combat_monster_ascii")
#   - control: the Control node the player will click on
#   - applier: Callable(scale: float) that knows how to apply the scale
#              (font size override, custom_minimum_size, both, etc)
#   - display_name: human-readable label for the +/- popup
#
# The manager handles persistence (user://ui_scale_per_element.json) and
# applies the saved scale on registration so reload-after-restart Just Works.

const CONFIG_PATH := "user://ui_scale_per_element.json"
const MIN_SCALE: float = 0.5
const MAX_SCALE: float = 3.0
const STEP: float = 0.1  # +/- button step size

# group_id -> {
#   "scale": float,
#   "display_name": String,
#   "appliers": Array[Callable],
#   "ctrls": Array[Control],
# }
var _groups: Dictionary = {}


func _ready() -> void:
	_load_config()


func register(group_id: String, ctrl: Control, applier: Callable, display_name: String = "") -> void:
	"""Register a Control as part of a scalable group. Multiple Controls can
	share the same group_id (e.g. all the HP bar parts). Each gets its own
	applier. The current saved scale is applied immediately so a freshly-
	created panel matches the player's preference."""
	if not is_instance_valid(ctrl):
		return
	if not _groups.has(group_id):
		_groups[group_id] = {
			"scale": 1.0,
			"display_name": display_name if display_name != "" else group_id,
			"appliers": [],
			"ctrls": [],
		}
	elif display_name != "":
		# Allow a later registration to set the display name if the first one didn't.
		if _groups[group_id].display_name == group_id:
			_groups[group_id].display_name = display_name
	var info: Dictionary = _groups[group_id]
	info.appliers.append(applier)
	info.ctrls.append(ctrl)
	ctrl.set_meta("ui_scale_group", group_id)
	# Apply current scale so the newly-registered element matches persisted state.
	if applier.is_valid():
		applier.call(float(info.scale))


func unregister_control(ctrl: Control) -> void:
	"""Remove a Control from its group (e.g. when a panel is freed). The group
	itself stays so its persisted scale survives panel rebuild."""
	if not is_instance_valid(ctrl):
		return
	var grp_id: String = String(ctrl.get_meta("ui_scale_group", ""))
	if grp_id == "" or not _groups.has(grp_id):
		return
	var info: Dictionary = _groups[grp_id]
	var idx: int = info.ctrls.find(ctrl)
	if idx >= 0:
		info.ctrls.remove_at(idx)
		if idx < info.appliers.size():
			info.appliers.remove_at(idx)


func set_scale(group_id: String, scale: float) -> void:
	"""Update the scale for a group, apply to all registered Controls, save."""
	if not _groups.has(group_id):
		return
	scale = clampf(scale, MIN_SCALE, MAX_SCALE)
	_groups[group_id].scale = scale
	for i in range(_groups[group_id].appliers.size()):
		var applier: Callable = _groups[group_id].appliers[i]
		if applier.is_valid():
			applier.call(scale)
	_save_config()


func bump_scale(group_id: String, delta: float) -> void:
	"""Adjust by delta (used by the +/- buttons)."""
	set_scale(group_id, get_scale(group_id) + delta)


func get_scale(group_id: String) -> float:
	if not _groups.has(group_id):
		return 1.0
	return float(_groups[group_id].scale)


func get_display_name(group_id: String) -> String:
	if not _groups.has(group_id):
		return group_id
	return String(_groups[group_id].display_name)


func has_group(group_id: String) -> bool:
	return _groups.has(group_id)


func reset_group(group_id: String) -> void:
	set_scale(group_id, 1.0)


func reset_all() -> void:
	for group_id in _groups.keys():
		set_scale(group_id, 1.0)


func find_group_for_control(start: Node) -> String:
	"""Walk up the parent chain looking for a registered ui_scale_group meta.
	Returns the deepest match (closest ancestor) so a click on a nested label
	bubbles to the outer panel only if nothing closer is registered."""
	var node: Node = start
	while node != null:
		if node is Control:
			var grp: String = String(node.get_meta("ui_scale_group", ""))
			if grp != "" and _groups.has(grp):
				return grp
		node = node.get_parent()
	return ""


func find_group_at_position(mouse_pos: Vector2) -> String:
	"""Iterate registered Controls and return the group whose Control contains
	the mouse position. Prefers the deepest in the tree (handles overlap of
	parent panel + child widget). Returns '' when nothing scalable is under
	the mouse."""
	var best_group: String = ""
	var best_depth: int = -1
	for group_id in _groups.keys():
		for ctrl in _groups[group_id].ctrls:
			if not is_instance_valid(ctrl):
				continue
			if not ctrl.visible:
				continue
			if not ctrl.is_visible_in_tree():
				continue
			var rect: Rect2 = ctrl.get_global_rect()
			if rect.has_point(mouse_pos):
				var d: int = _node_depth(ctrl)
				if d > best_depth:
					best_depth = d
					best_group = group_id
	return best_group


func get_all_groups() -> Array:
	"""Return list of all registered group IDs (for the bulk reset list)."""
	return _groups.keys()


# === Internal ===

func _node_depth(node: Node) -> int:
	var d: int = 0
	var n: Node = node
	while n != null and n.get_parent() != null:
		d += 1
		n = n.get_parent()
	return d


func _save_config() -> void:
	var data: Dictionary = {}
	for group_id in _groups.keys():
		data[group_id] = float(_groups[group_id].scale)
	var f: FileAccess = FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))
		f.close()


func _load_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var f: FileAccess = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		return
	var raw: String = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return
	# Pre-seed each group so register() can read the saved scale immediately.
	for group_id in parsed.keys():
		var s: float = clampf(float(parsed[group_id]), MIN_SCALE, MAX_SCALE)
		_groups[String(group_id)] = {
			"scale": s,
			"display_name": String(group_id),
			"appliers": [],
			"ctrls": [],
		}
