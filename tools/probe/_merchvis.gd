extends SceneTree
## Do merchants exist, do they move, and is one ever actually in view from a post?
const WorldScript := preload("res://shared/world_system.gd")
const OverworldRoom := preload("res://client/overworld_room.gd")

func _init() -> void:
	# 1. Does the sprite LOAD (not exists() - the .gdignore trap)?
	var tex = load("res://client/sprites/overworld32/overlay/merchant.png")
	print("")
	print("overlay/merchant.png load() -> %s" % ("OK" if tex != null else "NULL"))
	var im = OverworldRoom._overlay_img("merchant")
	print("overworld_room._overlay_img('merchant') -> %s" % ("OK %dx%d" % [im.get_width(), im.get_height()] if im != null else "NULL"))
	print("")
	quit()
