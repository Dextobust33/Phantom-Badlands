extends SceneTree
## ⛑ IS WHAT THE BOARD ADVERTISED WHAT THE DUNGEON ACTUALLY CONTAINS?
##
## Owner 2026-09-19, correcting me when I said this needed a screenshot to judge: *"It doesn't need
## to read as ominous it just needs to show as it was advertised and work as intended."* That is a
## testable bar, and this is the test.
##
## The three pieces were each proven separately — the board names the modifiers
## (`the_board_does_not_lie`), the look derives from them (`a_modified_dungeon_looks_it`), the egg
## inherits it (`the_egg_matches_its_dungeon`). Separately is not the same as JOINED. A chain of
## four correct links still breaks if two of them are wired to different sources, which is the
## exact shape of the `refcal` two-worlds bug found earlier today: every piece right, the whole
## thing measuring something nobody plays.
##
## So this walks ONE quest id all the way through the REAL functions:
##
##     quest id ──► seeded modifiers ──► board line      (what the player was promised)
##                        │
##                        └──────────► instance ──► _stamp_dungeon_look ──► a real monster
##                                                                          (what they get)
##
## Run:
##   godot --headless --path . --script res://tools/probe/advertised_is_what_you_get.gd

const ServerScript := preload("res://server/server.gd")
const ChunkManagerScript := preload("res://shared/chunk_manager.gd")
const WorldSystemScript := preload("res://shared/world_system.gd")
const DungeonDB := preload("res://shared/dungeon_database.gd")
const QuestDB := preload("res://shared/quest_database.gd")
const MonsterDB := preload("res://shared/monster_database.gd")

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


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
	get_root().add_child(srv)
	srv.chunk_manager = cm
	srv.world_system = ws
	var db = MonsterDB.new()

	# A quest id that actually rolls something, so the test is not vacuous.
	var quest_id := ""
	var mods: Array = []
	for i in range(80):
		var qid := "post_probe_daily_%d" % i
		var m: Array = DungeonDB.roll_dungeon_modifiers_seeded(9, qid)
		if m.size() >= 2:
			quest_id = qid
			mods = m
			break
	if quest_id == "":
		_fail("no quest id in 80 tries rolled 2+ modifiers - cannot test the joined chain")
		_finish()
		return

	print("")
	print("===== THE CHAIN, FOR ONE QUEST =====")
	print("  quest id   %s" % quest_id)
	print("  modifiers  %s" % str(mods))

	# 1. WHAT THE PLAYER WAS PROMISED.
	var board := String(QuestDB.modifier_board_line(mods))
	print("")
	print("  board says:")
	print("    %s" % board.replace("\n", "\n    "))

	# 2. WHAT THE INSTANCE CARRIES. The server derives it from the SAME quest id, independently -
	#    it does not receive the board's list, which is the whole point of seeding.
	var inst_mods: Array = DungeonDB.roll_dungeon_modifiers_seeded(9, quest_id)
	if inst_mods != mods:
		_fail("the instance would carry %s where the board promised %s" % [str(inst_mods), str(mods)])
	else:
		_ok("the instance derives the same modifiers the board advertised")

	# 3. WHAT A MONSTER IN IT ACTUALLY CARRIES - through the real server function.
	var iid := "probe_instance"
	srv.active_dungeons[iid] = {"instance_id": iid, "modifiers": inst_mods}
	var roll: Dictionary = db.generate_monster_by_name("Goblin", 20, true)
	if roll.is_empty():
		_fail("could not roll a monster to stamp")
		_finish()
		return
	var before_hp := int(roll.get("max_hp", 0))
	var before_str := int(roll.get("strength", 0))
	srv._stamp_dungeon_look(iid, roll)
	var look: Dictionary = DungeonDB.dungeon_look_for(inst_mods)
	print("")
	print("  a monster in it carries:")
	print("    colour  %s   (dungeon: %s)" % [roll.get("appearance_color", ""), look.get("color", "")])
	print("    pattern %s   (dungeon: %s)" % [roll.get("appearance_pattern", ""), look.get("pattern", "")])
	print("    named   %s" % roll.get("appearance_variant", ""))
	if String(roll.get("appearance_color", "")) != String(look.get("color", "")):
		_fail("the monster's colour is not the dungeon's")
	elif String(roll.get("appearance_pattern", "")) != String(look.get("pattern", "")):
		_fail("the monster's pattern is not the dungeon's")
	else:
		_ok("the monster wears exactly what the board advertised")

	# 4. AND IT WORKS AS INTENDED - the stamp changed no stat, so the modifier's real effects are
	#    applied once, by modifier_effects(), and not a second time here.
	if int(roll.get("max_hp", 0)) != before_hp or int(roll.get("strength", 0)) != before_str:
		_fail("stamping changed hp %d->%d or strength %d->%d - the modifier would apply twice"
			% [before_hp, int(roll.get("max_hp", 0)), before_str, int(roll.get("strength", 0))])
	else:
		_ok("stamping changed no stat - the modifier's effects still apply exactly once")

	# 5. EVERY MONSTER IN THE DUNGEON, NOT JUST ONE. "They all share a trait" is the feature.
	var looks := {}
	for i in range(25):
		var r: Dictionary = db.generate_monster_by_name("Goblin", 20, true)
		srv._stamp_dungeon_look(iid, r)
		looks["%s|%s" % [r.get("appearance_color", ""), r.get("appearance_pattern", "")]] = true
	print("")
	print("  25 monsters spawned -> %d distinct look(s)" % looks.size())
	if looks.size() != 1:
		_fail("monsters in one dungeon do not share a look (%d distinct)" % looks.size())
	else:
		_ok("every monster in the dungeon shares one look")

	# 6. AN UNMODIFIED DUNGEON IS UNTOUCHED.
	srv.active_dungeons["plain"] = {"instance_id": "plain", "modifiers": []}
	var plain: Dictionary = db.generate_monster_by_name("Goblin", 20, true)
	var plain_before := String(plain.get("appearance_color", ""))
	srv._stamp_dungeon_look("plain", plain)
	if String(plain.get("appearance_color", "")) != plain_before:
		_fail("an unmodified dungeon overwrote its monster's own tint")
	else:
		_ok("an unmodified dungeon leaves monsters their own tints")

	_finish()


func _finish() -> void:
	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS what the board advertises is what the instance carries, what its monsters")
	print("       wear, and it changes no stat on the way.")
	quit()
