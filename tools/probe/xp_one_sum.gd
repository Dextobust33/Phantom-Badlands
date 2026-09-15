extends SceneTree
## A kill pays the same XP whoever swung - solo, in a party, or through Perfect Heist.
##
## Owner 2026-09-15, from the live server: *"I killed a Venomous Hobgoblin Lv 7 in a Hotzone area.
## I'm level 7 as well. I only got +195 XP."* 195 was the monster's RAW experience_reward - the
## Size Them Up card had quoted that exact number before the kill. It was a party fight (the
## Warden), and the co-op payout in `_end_party_combat_all` awarded `experience_reward` and
## nothing else: no flat +10%, no Danger Zone +30-70%, no level-gap scaling, no apex, no Hunter's
## Mark, no Path, no Insight potion. The same kill solo pays ~280-365.
##
## It was the FOURTH copy of a kill's XP sum. `combat_manager.kill_xp` is the only one now, and
## this measures the co-op payout by running the real `_end_party_combat_all` and comparing it
## against what that same function returns for the same character and monster.
const ServerScript = preload("res://server/server.gd")
const CharacterScript = preload("res://shared/character.gd")
const CombatMgr = preload("res://shared/combat_manager.gd")
const MonsterDB = preload("res://shared/monster_database.gd")
const DropTablesScript = preload("res://shared/drop_tables.gd")
const QuestDB = preload("res://shared/quest_database.gd")
const QuestMgr = preload("res://shared/quest_manager.gd")
const ChunkManagerScript = preload("res://shared/chunk_manager.gd")
const WorldSystemScript = preload("res://shared/world_system.gd")

const BASE_XP := 195

var fails := 0
var _ws = null

func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _srv() -> Node:
	var s = ServerScript.new()
	s.combat_mgr = CombatMgr.new()
	s.monster_db = MonsterDB.new()
	s.drop_tables = DropTablesScript.new()
	s.quest_db = QuestDB.new()
	s.quest_mgr = QuestMgr.new()
	s.combat_mgr.set_drop_tables(s.drop_tables)
	s.combat_mgr.set_monster_database(s.monster_db)
	s.world_system = _ws
	return s


func _mk(nm: String) -> Character:
	var c = CharacterScript.new()
	c.name = nm
	c.class_type = "warrior"
	c.level = 7
	# A bare Character keeps level 1's XP requirement, so a 300-XP kill levelled it three times
	# and `experience` wrapped - the first run of this probe printed 210 for a kill worth 282 and
	# only agreed because BOTH sides wrapped the same way. Put the bar out of reach so the
	# measurement is the kill, not the level-up loop.
	c.experience_to_next_level = 100000000
	c.current_hp = c.get_total_max_hp()
	return c


func _monster(lvl: int, hotspot: float) -> Dictionary:
	return {
		"name": "Venomous Hobgoblin", "base_name": "Hobgoblin", "level": lvl,
		"max_hp": 954, "current_hp": 0, "strength": 108, "defense": 24, "speed": 18,
		"experience_reward": BASE_XP, "abilities": [], "flock_chance": 0,
		"variant_type": "Venomous", "empowered_mods": [], "hotspot_intensity": hotspot,
	}


func _party_xp(mon: Dictionary) -> int:
	"""The REAL co-op payout: two heroes, one dead monster, `_end_party_combat_all`."""
	var s = _srv()
	var a := _mk("Leader")
	var b := _mk("Mate")
	s.characters = {1: a, 2: b}
	s.active_parties = {1: {"leader": 1, "members": [1, 2], "formed_at": 0}}
	s.party_membership = {1: 1, 2: 1}
	s.combat_mgr.start_party_combat_simul([1, 2], {1: a, 2: b}, mon)
	var lvl0: int = a.level
	var xp0: int = a.experience
	s._end_party_combat_all(1, true, [])
	if a.level != lvl0:
		print("    (levelled during the measurement - widen the gap between level and XP)")
	return a.experience - xp0


func _expected(mon: Dictionary) -> int:
	"""What the one sum pays this character, run through add_experience as the payout does -
	so the race / Sanctuary / house multipliers are measured, not re-derived here."""
	var s = _srv()
	var c := _mk("Yardstick")
	var raw: int = int(s.combat_mgr.kill_xp(c, mon, [])["xp"])
	var before: int = c.experience
	c.add_experience(raw)
	return c.experience - before


func _case(label: String, mon: Dictionary) -> void:
	var want: int = _expected(mon)
	var got: int = _party_xp(mon)
	print("  %-38s base %4d -> solo sum %4d, party paid %4d" % [label, BASE_XP, want, got])
	ck(got == want, "    %s: the party pays what the kill is worth" % label)


func _init() -> void:
	var cm = ChunkManagerScript.new()
	get_root().add_child(cm)
	cm.load_world_seed()
	cm.load_npc_posts()
	_ws = WorldSystemScript.new()
	get_root().add_child(_ws)
	_ws.chunk_manager = cm
	cm.terrain_generator = _ws

	print("===== THE SUM IS DEFINED ONCE =====")
	var src := FileAccess.get_file_as_string("res://shared/combat_manager.gd")
	ck(src.count("sqrt(gap_ratio)") == 1, "one level-gap curve in combat_manager (%d found)" % src.count("sqrt(gap_ratio)"))
	var ssrc := FileAccess.get_file_as_string("res://server/server.gd")
	ck(ssrc.contains("combat_mgr.kill_xp(ch, monster, _xp_notes)"), "the co-op payout asks for it")
	ck(not ssrc.contains('var xp: int = int(monster.get("experience_reward", monster.get("xp_reward", 10)))'),
		"...instead of paying the monster's raw reward")

	print("")
	print("===== THE OWNER'S FIGHT, AND ITS NEIGHBOURS =====")
	# The reported one: level 7 player, level 7 monster, inside a hotzone.
	_case("L7 vs L7 in a DANGER hotzone", _monster(7, 0.6))
	_case("L7 vs L7, open country", _monster(7, 0.0))
	_case("L7 vs L17 (challenge bonus)", _monster(17, 0.0))
	_case("L7 vs L1 (weak foe penalty)", _monster(1, 0.0))
	var apexy := _monster(7, 0.0)
	apexy["is_apex_frontier"] = true
	apexy["is_apex_variant"] = true
	_case("L7 vs L7 apex frontier + variant", apexy)

	print("")
	print("===== AND THE BONUSES ACTUALLY LAND =====")
	var s = _srv()
	var plain: int = int(s.combat_mgr.kill_xp(_mk("A"), _monster(7, 0.0), [])["xp"])
	var hot: int = int(s.combat_mgr.kill_xp(_mk("B"), _monster(7, 0.6), [])["xp"])
	var up: int = int(s.combat_mgr.kill_xp(_mk("C"), _monster(17, 0.0), [])["xp"])
	print("  base %d | flat %d | hotzone %d (x%.2f) | ten levels up %d (x%.2f)"
		% [BASE_XP, plain, hot, float(hot) / float(plain), up, float(up) / float(plain)])
	ck(plain > BASE_XP, "an ordinary kill pays more than the monster's raw reward (+10%)")
	ck(hot > plain, "a hotzone kill pays more than the same kill outside one")
	ck(up > plain * 2, "ten levels up pays over double (the 2.0 curve, not the stale 0.7)")

	print("RESULT: %s (%d failing)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
