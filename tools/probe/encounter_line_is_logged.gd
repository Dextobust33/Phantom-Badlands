extends SceneTree
## Owner 2026-10-13: the death log records deaths but not the encounters they came from, so "11 of 13 deaths were
## modified monsters" could not be divided by how many modified monsters players meet. Every finished fight now
## prints one [ENCOUNTER] line. This pins the line's content (role, outcome, gap, mods) and that both end paths
## emit it before they erase the combat.
const CM := preload("res://shared/combat_manager.gd")
const SimScript := preload("res://tools/combat_simulator/real_combat_sim.gd")
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _line(sim, mon: Dictionary, victory: bool, hp: int, extra := {}, party := 1, dead := 0) -> String:
	var ch = sim.make_char(10, "average", "Ranger", "Human")
	ch.current_hp = hp
	var combat := {"monster": mon, "character": ch, "round": 4, "player_hp_at_start": 300}
	combat.merge(extra, true)
	return CM.encounter_log_line(combat, victory, party, dead)

func _init() -> void:
	var sim = SimScript.new()
	var base := {"name": "Ogre", "level": 12, "max_hp": 630}
	var l: String = _line(sim, base.duplicate(), true, 200)
	ck(l.begins_with("[ENCOUNTER] outcome=won role=normal mods=- "), "a plain win: " + l.substr(0, 60))
	ck(l.find("mon=Ogre mlvl=12 mhp=630 class=Ranger plvl=10 gap=2 rounds=4 hp0=300 hp1=200") >= 0, "monster, class, level gap, rounds and HP are on the line")
	var emp := base.duplicate(); emp["empowered_mods"] = ["vampiric", "juggernaut"]; emp["name"] = "Vampiric Juggernaut Ogre"
	l = _line(sim, emp, true, 200)
	ck(l.find("role=empowered mods=vampiric,juggernaut") >= 0, "empowered: role and mods listed")
	var el := base.duplicate(); el["name"] = "\u2605 Ogre Champion"; el["variant_type"] = "elite"
	l = _line(sim, el, true, 200)
	ck(l.find("role=elite") >= 0 and l.find("variant=elite") >= 0, "a starred monster is an elite")
	var bs := base.duplicate(); bs["is_boss"] = true
	ck(_line(sim, bs, true, 200).find("role=boss") >= 0, "a boss")
	ck(_line(sim, base.duplicate(), false, 0).find("outcome=died") >= 0, "not a win at 0 HP is a death")
	ck(_line(sim, base.duplicate(), false, 120).find("outcome=left") >= 0, "not a win, still alive, is a flee/retreat/abort")
	var pl: String = _line(sim, base.duplicate(), false, 0, {}, 3, 1)
	ck(pl.find("outcome=died") >= 0 and pl.find("party=3 dead=1") >= 0, "a party fight carries size and deaths")
	ck(_line(sim, base.duplicate(), true, 200, {"monster_went_first": true, "is_dungeon_combat": true}).find("first=1 dungeon=1") >= 0, "ambush and dungeon flags")
	ck(_line(sim, base.duplicate(), true, 200).find("Player") < 0 and _line(sim, base.duplicate(), true, 200).find("name=") < 0, "no player name is written")
	# both end paths emit it, before the erase (statement matches, bounded to each function)
	var src := FileAccess.get_file_as_string("res://shared/combat_manager.gd")
	var a := src.find("\nfunc end_combat(")
	var b := src.find("\nfunc get_expired_persistent_buffs", a)
	var body := src.substr(a, b - a)
	var p := body.find("\n\t\tprint(encounter_log_line(combat, victory))\n")
	ck(p > 0 and p < body.find("active_combats.erase(peer_id)"), "end_combat prints the line before it erases the combat")
	var c := src.find("\nfunc _end_party_combat(")
	var d := src.find("\nfunc get_party_combat_state", c)
	var pb := src.substr(c, d - c)
	var pp := pb.find("\n\tprint(encounter_log_line(_p_view, victory, combat.members.size(), _p_dead))\n")
	ck(pp > 0 and pp < pb.find("active_party_combats.erase(leader_id)"), "_end_party_combat prints the line before it erases the combat")
	print("\n[ENCOUNTERLINE] %s" % ("PASS" if fails == 0 else "FAIL - %d" % fails))
	quit(0 if fails == 0 else 1)
