extends Control
class_name BoonPanel

# Persistent boons (shared/boons.gd): the pick-1-of-3 offer. The offer lives on the character
# (pending_boon_offers), so this panel only ever renders what the server holds; a pick sends
# boon_pick and the next character_update closes it or shows the next waiting offer.
# Opened by the client when an offer is waiting and the fight's aftermath is finished.

signal picked(choice: String)

const BoonsScript = preload("res://shared/boons.gd")

var _title: RichTextLabel
var _sub: RichTextLabel
var _cards: VBoxContainer
var _offer_key: String = ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.06, 1.0)
	sb.border_color = Color(0.85, 0.7, 0.2)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)
	_title = RichTextLabel.new()
	_title.bbcode_enabled = true
	_title.fit_content = true
	_title.scroll_active = false
	_title.add_theme_font_size_override("normal_font_size", 20)
	vbox.add_child(_title)
	_sub = RichTextLabel.new()
	_sub.bbcode_enabled = true
	_sub.fit_content = true
	_sub.scroll_active = false
	_sub.add_theme_font_size_override("normal_font_size", 12)
	vbox.add_child(_sub)
	_cards = VBoxContainer.new()
	_cards.add_theme_constant_override("separation", 6)
	vbox.add_child(_cards)
	var skip := Button.new()
	skip.text = "Decline all"
	skip.pressed.connect(func(): picked.emit(""))
	vbox.add_child(skip)
	visible = false


func show_offer(offer: Dictionary, held: Dictionary, dungeon_held: Dictionary) -> void:
	"""Render one offer; a re-render of the SAME offer is a no-op so a character_update does not rebuild buttons under the player's cursor."""
	var key := str(offer.get("options", [])) + str(offer.get("scope", ""))
	if visible and key == _offer_key:
		return
	_offer_key = key
	var life: bool = String(offer.get("scope", "life")) == "life"
	_title.text = "[color=#FFD700]✦ Choose a boon[/color]"
	_sub.text = "[color=#B0A080]%s. %s[/color]" % [String(offer.get("why", "")),
		"It lasts as long as this character lives." if life else "It lasts until you leave this dungeon - and is stronger for it."]
	for c in _cards.get_children():
		c.queue_free()
	var mult: float = 1.0 if life else BoonsScript.DUNGEON_VALUE_MULT
	for id in offer.get("options", []):
		var b: Dictionary = BoonsScript.BOONS.get(String(id), {})
		if b.is_empty():
			continue
		var have: int = int((held if life else dungeon_held).get(String(id), 0))
		var btn := Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 54)
		btn.text = "%s%s\n%s" % [String(b["name"]), ("   (you hold %d - each extra is worth less)" % have) if have > 0 else "", String(b["text"])]
		btn.tooltip_text = "Values shown are for one boon%s." % ("" if life else "; dungeon boons are x%.1f" % mult)
		var chosen := String(id)
		btn.pressed.connect(func(): picked.emit(chosen))
		_cards.add_child(btn)
	_fit_to_screen()
	visible = true


func hide_offer() -> void:
	visible = false
	_offer_key = ""


func _fit_to_screen() -> void:
	"""This panel has no parent rect to anchor to (the client root is not a sizing container), so its anchors resolve to zero: size it to the viewport by hand (the dim and the centring container hang off it)."""
	position = Vector2.ZERO
	size = get_viewport_rect().size
