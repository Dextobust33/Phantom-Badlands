extends SceneTree

## Which monsters in the roster still have NO dungeon sprite?
##
## Owner 2026-09-09: "For monsters use the closest match we have, no glyphs for them." So this
## lists the gap that decision has to close, by calling the real resolver on every roster name
## rather than by reading the table - `MONSTER_SPRITE` is keyed by display name and the resolver
## strips variant decorations, so the two do not answer the same question. Enumerates the
## `MonsterType` enum through `get_monster_base_stats`, which is the only place a display name
## actually comes from.

func _init() -> void:
	var DS = load("res://client/dungeon_sprites.gd")
	var MDB = load("res://shared/monster_database.gd")
	var md = MDB.new()
	var missing: Array = []
	var have := 0
	for v in MDB.MonsterType.values():
		var st: Dictionary = md.get_monster_base_stats(v)
		var n := String(st.get("name", ""))
		if n == "":
			continue
		if DS.monster_path(n, 0) == "":
			missing.append(n)
		else:
			have += 1
	missing.sort()
	print("[SPRITEGAP] mapped=%d missing=%d" % [have, missing.size()])
	for m in missing:
		print("[SPRITEGAP] MISSING ", m)
	quit(0)
