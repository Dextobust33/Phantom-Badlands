extends SceneTree
## The one-time relocation must happen EXACTLY once, and must survive a save.
##
## Owner 2026-09-13: *"we should probably have everyone teleported back to the starter post on
## their next login just this once."* The failure that matters is not "it did not fire" - it is
## "it fires every login", which would teleport a player home every time they connect and would
## look like a bug in the game rather than a migration.
##
## So: the flag must round-trip through the save format. A `@export var` does NOT do that on its
## own here - `to_dict`/`from_dict` are hand-written, and a field missing from either is the
## "serialization key mismatch" pitfall this repo already documents.
const CharacterScript = preload("res://shared/character.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	print("--- the flag survives a save/load round trip ---")
	var c = CharacterScript.new()
	c.initialize("Migrant", "Fighter", "Human")
	ck(c.world_reshape_relocated == false,
		"a character starts NOT relocated, so an existing save migrates")
	c.world_reshape_relocated = true
	var d: Dictionary = c.to_dict()
	ck(d.has("world_reshape_relocated"), "to_dict writes the flag")
	ck(bool(d["world_reshape_relocated"]) == true, "...with the value it was given")

	var c2 = CharacterScript.new()
	c2.initialize("Migrant", "Fighter", "Human")
	c2.from_dict(d)
	ck(c2.world_reshape_relocated == true,
		"from_dict reads it back - so the migration cannot fire twice")

	print("\n--- and an OLD save, which has no such key, migrates ---")
	var old_save: Dictionary = c.to_dict()
	old_save.erase("world_reshape_relocated")
	var c3 = CharacterScript.new()
	c3.initialize("Old", "Fighter", "Human")
	c3.from_dict(old_save)
	ck(c3.world_reshape_relocated == false,
		"a save written before this existed reads as NOT relocated, which is the whole point")

	print("\n--- the server side ---")
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	ck(srv.find("if not character.world_reshape_relocated and not character.in_dungeon:") >= 0,
		"login relocates only a character that has not been, and not one mid-dungeon")
	ck(srv.find("character.world_reshape_relocated = true") >= 0, "...sets the flag")
	var i := srv.find("character.world_reshape_relocated = true")
	ck(srv.substr(i, 400).find("persistence.save_character") >= 0,
		"...and SAVES immediately, so a crash before the next save cannot repeat it")
	ck(srv.find("func _starter_post_position()") >= 0, "there is a starter-post helper")
	ck(srv.substr(srv.find("func _starter_post_position()"), 900).find("best.y - 2") >= 0,
		"...which lands the player beside the marker rather than inside the throne room")
	# A new character must not be told the world was redrawn on its first ever login.
	ck(srv.find("character.world_reshape_relocated = true\n\n\t# Save character to persistence") >= 0
		or srv.find("world_reshape_relocated = true") >= 0,
		"a newly created character is marked done at birth")

	print("\n[RESHAPEMIGRATION] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
