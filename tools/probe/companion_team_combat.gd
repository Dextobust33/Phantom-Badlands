extends SceneTree
## Item 14 S3: the companion TEAM in a real fight. Column companions act after the beside-you one, each with its
## own HP; monsters pick targets across the whole team; a healer tends the lowest ally and revives a fallen one;
## the team earns XP and recovers out of combat.
## Run:  godot --headless --path . --script res://tools/probe/companion_team_combat.gd
const RolesScript = preload("res://shared/companion_roles.gd")
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

var sim

func _comp(id: String, species: String, tactics: String = "balanced") -> Dictionary:
	var d: Dictionary = sim.drop_tables.COMPANION_DATA.get(species, {})
	return {"id": id, "monster_type": species, "name": str(d.get("companion_name", species)) + " " + id,
		"tier": int(d.get("tier", 1)), "level": 60, "xp": 0, "bonuses": (d.get("bonuses", {}) as Dictionary).duplicate(),
		"variant": "Normal", "sub_tier": 1, "border_tier": 1, "tactics": tactics}

# A level-100 character with an optional active companion and a column team (species list).
func _fight(active: String, team: Array):
	var ch = sim.make_char(100, "average", "Fighter", "Human")
	ch.active_companion = {}
	if active != "":
		ch.active_companion = _comp("act", active)
		ch.collected_companions.append(_comp("act", active))
	var n := 0
	for sp in team:
		var cd := _comp("m%d" % n, String(sp))
		ch.collected_companions.append(cd)
		ch.companion_party.append(cd.id)
		n += 1
	var mon = sim.make_monster(60, "normal", 1.0)
	mon["max_hp"] = 99999999
	mon["current_hp"] = 99999999
	# A PLAIN monster: the generated one carried multi_strike, which splits its hits by design and made the
	# aggro share unreadable (the first version of this probe measured 37%% for a 25%% companion).
	mon["abilities"] = []
	mon["empowered_mods"] = []
	ch.in_combat = false
	sim.combat_mgr.start_combat(0, ch, mon)
	var c = sim.combat_mgr.active_combats[0]
	return [ch, c]

func _team_dmg(team: Array) -> int:
	var f = _fight("", team)
	var c = f[1]
	var m0: int = int(c.monster.current_hp)
	var msgs: Array = []
	sim.combat_mgr._process_companion_attack(c, msgs)
	var d: int = m0 - int(c.monster.current_hp)
	sim.combat_mgr.end_combat(0, false, false)
	return d

# share of 400 single-hit monster turns that landed on a COMPANION (message names it)
func _companion_share(active: String, team: Array, n: int = 400) -> float:
	var f = _fight(active, team)
	var ch = f[0]
	var c = f[1]
	var hit := 0
	var landed := 0
	for i in n:
		ch.current_hp = ch.get_total_max_hp()
		for cd in ch.collected_companions:
			ch.set_party_companion_combat_hp(String(cd.id), 999999999) if String(cd.id) != "act" else ch.set_companion_combat_hp(999999999)
		c["monster_turns_taken"] = 5
		var r: Dictionary = sim.combat_mgr.process_monster_turn(c)
		var txt: String = str(r.get("message", ""))
		if txt.find("misses") >= 0:
			continue
		landed += 1
		if bool(r.get("companion_hit", false)) or txt.find("attacks your") >= 0 or txt.find("hits your") >= 0:
			hit += 1
		ch.in_combat = true
	sim.combat_mgr.end_combat(0, false, false)
	return float(hit) / float(maxi(1, landed))

func _init() -> void:
	sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	get_root().add_child(sim)
	await process_frame

	print("--- column companions act ---")
	var d0 := _team_dmg([])
	var d1 := _team_dmg(["Balrog"])
	var d3 := _team_dmg(["Balrog", "Demon", "Dragon Wyrmling"])
	ck(d0 == 0, "no companions, no companion damage (%d)" % d0)
	ck(d1 > 0 and d3 > d1, "one column companion hits, three hit more (%d -> %d)" % [d1, d3])
	var f = _fight("", ["Balrog", "Demon"])
	f[0].set_party_companion_combat_hp("m0", 0)
	var m0: int = int(f[1].monster.current_hp)
	var msgs: Array = []
	sim.combat_mgr._process_companion_attack(f[1], msgs)
	ck(msgs.size() == 1 and str(msgs[0]).find("m0") < 0, "a knocked-out column companion does not act (%d line(s))" % msgs.size())
	sim.combat_mgr.end_combat(0, false, false)

	print("--- the monster picks among the team ---")
	var solo := _companion_share("Wolf", [])
	var team := _companion_share("Wolf", ["Iron Golem"])
	print("  share of monster turns that hit a companion: wolf alone %.0f%%, wolf + Iron Golem %.0f%%" % [solo * 100.0, team * 100.0])
	ck(absf(solo - 0.25) < 0.08, "ONE companion keeps its old aggro share (wolf, aggro 25: %.0f%%)" % (solo * 100.0))
	ck(team > solo + 0.15 and absf(team - 0.50) < 0.09, "a TEAM soaks about its 50%% cap, not 80%% (%.0f%% vs %.0f%% alone)" % [team * 100.0, solo * 100.0])

	print("--- a healer tends the lowest ally and revives a fallen one ---")
	var g = _fight("Wolf", ["Phoenix", "Balrog"])
	g[0].set_companion_combat_hp(int(g[0].get_companion_max_hp() * 0.3))
	g[0].current_hp = g[0].get_total_max_hp()
	var hurt0: int = g[0].get_companion_combat_hp()
	var gm: Array = []
	sim.combat_mgr._process_companion_attack(g[1], gm)
	ck(g[0].get_companion_combat_hp() > hurt0, "healer heals the hurt companion rather than the full-health owner (%d -> %d)" % [hurt0, g[0].get_companion_combat_hp()])
	sim.combat_mgr.end_combat(0, false, false)
	var h = _fight("Wolf", ["Phoenix", "Balrog"])
	h[0].set_party_companion_combat_hp("m1", 0)
	var hm: Array = []
	sim.combat_mgr._process_companion_attack(h[1], hm)
	ck(h[0].get_party_companion_combat_hp("m1") > 0, "healer revives the fallen Balrog (now %d HP)" % h[0].get_party_companion_combat_hp("m1"))
	sim.combat_mgr.end_combat(0, false, false)

	print("--- XP, recovery, the healer NPC ---")
	var x = _fight("Wolf", ["Balrog", "Demon"])
	var lv0: int = int(x[0].collected_companions[1].level)
	x[0].add_companion_xp(5000000)
	ck(int(x[0].collected_companions[1].level) > lv0, "a column companion levels from the same victory XP (%d -> %d)" % [lv0, int(x[0].collected_companions[1].level)])
	x[0].set_party_companion_combat_hp("m0", 5)
	x[0].set_party_companion_combat_hp("m1", 0)
	x[0].regen_companion(0.10)
	ck(x[0].get_party_companion_combat_hp("m0") > 5, "a hurt column companion recovers with rest")
	ck(x[0].is_party_companion_ko("m1"), "a knocked-out one does NOT recover on its own")
	ck(x[0].revive_party_companions(1.0) == 1 and not x[0].is_party_companion_ko("m1"), "the healer's service revives it")
	sim.combat_mgr.end_combat(0, false, false)

	print("")
	print(("PASS - companion_team_combat" if fails == 0 else "FAIL - companion_team_combat: %d check(s)" % fails))
	quit(1 if fails > 0 else 0)
