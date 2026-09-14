extends SceneTree
## A registered companion must go BACK to the Sanctuary, and must NOT also drop on the corpse.
##
## Owner 2026-09-13: *"players who have registered companions can still drop their registered
## companions on their corpses effectively 'duping' those companions."*
##
## Both halves of the answer already existed and disagreed with each other. The corpse path asked
## `house_slot >= 0`. The return path asked that too, and then fell back to
## `using_registered_companion` + `registered_companion_slot` for legacy characters whose
## companions predate the per-companion field. So for exactly those characters the return fired
## and the corpse guard did not - the companion went home AND a copy was left on the body.
##
## One definition now (`_is_registered_companion`), asked by both.
##
## Harness note, and it earned its keep: the first run of this probe reported three PASSes that
## were VACUOUS. `_create_corpse_from_character` bails early on a null world_system, so the corpse
## came back empty and "the companion is not on the corpse" was true for every case including the
## ones that should fail. The control check - "an ordinary companion still DROPS" - is what
## exposed it. A guard that swallows every companion is as wrong as one that dupes them, and
## without that control this probe would have certified the bug as fixed while testing nothing.
const ServerScript = preload("res://server/server.gd")
const CharacterScript = preload("res://shared/character.gd")
const ChunkManagerScript = preload("res://shared/chunk_manager.gd")
const WorldSystemScript = preload("res://shared/world_system.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _comp(id: String, slot: int) -> Dictionary:
	var c := {"id": id, "name": "Titan Spawn", "monster_type": "Titan", "level": 28,
			  "xp": 0, "tier": 5, "sub_tier": 1, "variant": "Jailbird", "bonuses": {}}
	if slot >= 0:
		c["house_slot"] = slot
	return c


func _hero(nm: String) -> Character:
	var c = CharacterScript.new()
	c.initialize(nm, "warrior", "human")
	c.level = 30
	return c


func _init() -> void:
	var cm = ChunkManagerScript.new()
	get_root().add_child(cm)
	cm.load_world_seed()
	cm.load_npc_posts()
	var ws = WorldSystemScript.new()
	get_root().add_child(ws)
	ws.chunk_manager = cm
	cm.terrain_generator = ws

	var srv = ServerScript.new()
	srv.world_system = ws
	srv.drop_tables = load("res://shared/drop_tables.gd").new()
	get_root().add_child(srv.drop_tables)
	srv.chunk_manager = cm
	srv.trading_post_db = load("res://shared/trading_post_database.gd").new()
	get_root().add_child(srv.trading_post_db)

	print("===== THE MODERN CASE: house_slot on the companion =====")
	var a := _hero("Modern")
	a.active_companion = _comp("c1", 2)
	a.collected_companions = [a.active_companion]
	ck(srv._is_registered_companion(a, a.active_companion), "recognised as the Sanctuary's")
	var corpse_a: Dictionary = srv._create_corpse_from_character(a, "a Wolf")
	ck(corpse_a.get("contents", {}).get("active_companion", null) == null,
		"and it is NOT left on the corpse")

	print("")
	print("===== THE LEGACY CASE - THIS IS THE ONE THAT DUPED =====")
	# No house_slot anywhere; the registration is tracked on the CHARACTER, which is how
	# characters from before the per-companion field still look.
	var b := _hero("Legacy")
	b.active_companion = _comp("c1", -1)
	b.collected_companions = [b.active_companion]
	b.using_registered_companion = true
	b.registered_companion_slot = 2
	ck(srv._is_registered_companion(b, b.active_companion),
		"recognised as the Sanctuary's through the legacy pair")
	var corpse_b: Dictionary = srv._create_corpse_from_character(b, "a Wolf")
	ck(corpse_b.get("contents", {}).get("active_companion", null) == null,
		"and it is NOT left on the corpse either - this is the dupe, closed")
	ck(corpse_b.get("contents", {}).get("other_companion", null) == null,
		"nor picked up by the random OTHER-companion roll, which had the same gap")

	print("")
	print("===== AN ORDINARY COMPANION STILL DROPS =====")
	# The whole point of a corpse is that death costs something. A guard that swallowed every
	# companion would be just as wrong as one that duped them.
	var c := _hero("Plain")
	c.active_companion = _comp("c9", -1)
	c.collected_companions = [c.active_companion]
	ck(not srv._is_registered_companion(c, c.active_companion), "not registered")
	var corpse_c: Dictionary = srv._create_corpse_from_character(c, "a Wolf")
	var dropped = corpse_c.get("contents", {}).get("active_companion", null)
	ck(dropped != null, "an unregistered companion is still lost to the corpse")
	if dropped != null:
		ck(String(dropped.get("id", "")) == "c9", "  ...and it is the right one")

	print("")
	print("===== A MIXED BAG DROPS ONLY THE UNREGISTERED ONE =====")
	var d := _hero("Mixed")
	d.active_companion = _comp("reg", 3)
	d.collected_companions = [d.active_companion, _comp("free", -1)]
	var corpse_d: Dictionary = srv._create_corpse_from_character(d, "a Wolf")
	ck(corpse_d.get("contents", {}).get("active_companion", null) == null,
		"the registered active one stays out of the corpse")
	var other = corpse_d.get("contents", {}).get("other_companion", null)
	ck(other != null and String(other.get("id", "")) == "free",
		"and the free one is what gets left behind")

	print("")
	print("----- NOT COVERED HERE -----")
	print("  The RETURN half (_return_registered_companions writing the slot back) needs a real")
	print("  PersistenceManager; it is exercised in tools/probe/companion_level_survives_death.gd.")
	print("  This probe proves the corpse no longer makes a second copy.")

	print("")
	if fails == 0:
		print("PASS - a registered companion goes home and nowhere else")
	else:
		print("FAIL - %d check(s) failed" % fails)
	quit(1 if fails > 0 else 0)
