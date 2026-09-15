extends SceneTree
## A death curse is sized to the PLAYER, not to the monster that cast it.
##
## Owner 2026-09-15: *"take a look at the strength of death curse and if the enemies with it can
## flock. It often puts a player to 1 hp meaning it could be death in a flock or if they can't heal."*
##
## Measured first: the curse was 10% of the MONSTER's max HP, and monster HP is sized to take
## several turns. Across all eight carriers at their home levels it came to roughly 40% of a real
## player's bar at the low end (Balrog/Phoenix at their first levels, a Demon at L100) and 100-500%
## for most carriers, most levels and every elite - so it usually left the player at 1 HP.
## Any carrier can flock (Broodcalling forces it; the flock is the same species). Owner chose 20% of
## the player's max HP, Wisdom resisting up to half, never lethal. Driven through the real kill path.
const CM = preload("res://shared/combat_manager.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _kill(sim, cm, ch, mon: Dictionary) -> Dictionary:
	cm.start_combat(0, ch, mon)
	var c = cm.active_combats[0]
	c["monster"]["current_hp"] = 1
	c["monster"]["defense"] = 0
	c["player_can_act"] = true
	c["suppress_monster_turn"] = true
	var hp0: int = int(ch.current_hp)
	var res: Dictionary = cm.process_attack(c)
	var tries := 0
	while int(c["monster"]["current_hp"]) > 0 and tries < 20:
		res = cm.process_attack(c)
		tries += 1
	var lost: int = hp0 - int(ch.current_hp)
	var text := ""
	for m in res.get("messages", []):
		text += String(m) + " "
	cm.active_combats.erase(0)
	return {"lost": lost, "text": text, "hp_after": int(ch.current_hp)}


func _init() -> void:
	var sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	get_root().add_child(sim)
	await process_frame
	var cm = sim.combat_mgr
	var md = sim.monster_db

	print("===== 1. THE CURSE IS A SHARE OF YOUR BAR =====")
	var ch = sim.make_char(100, "average", "Fighter", "Human")
	ch.current_hp = ch.get_total_max_hp()
	var mon: Dictionary = md.generate_monster_by_name("Demon", 100, true)
	var php: int = ch.get_total_max_hp()
	var wis := float(ch.get_effective_stat("wisdom"))
	var want: int = maxi(1, int(int(float(php) * CM.DEATH_CURSE_PLAYER_SHARE) * (1.0 - minf(0.5, wis / 200.0))))
	var k: Dictionary = _kill(sim, cm, ch, mon)
	print("  Demon L100 (monster HP %d) against a %d HP Fighter: lost %d (expected curse %d)" % [int(mon.get("max_hp", 0)), php, int(k["lost"]), want])
	ck(String(k["text"]).find("death curse deals") >= 0, "the kill really applies the curse")
	# Other on-kill effects (leech, procs) can move HP by a little, so allow a small tolerance.
	ck(absi(int(k["lost"]) - want) <= maxi(3, int(want * 0.05)), "it costs 20% of the player's bar after Wisdom, not the monster's size")
	ck(int(k["hp_after"]) > int(php * 0.5), "  so a full-health player walks away with most of their bar (%d/%d)" % [int(k["hp_after"]), php])
	var old_curse: int = int(int(mon.get("max_hp", 0)) * 0.10 * (1.0 - minf(0.5, wis / 200.0)))
	# Control: the old rule, at this exact point, cost more. (NOT "a whole bar": at L100 against a
	# 2.7k Fighter it was ~40%. The whole-bar cases are higher levels and elites.)
	ck(old_curse > int(k["lost"]), "control: the OLD rule cost more here (%d vs %d now, player bar %d)" % [old_curse, int(k["lost"]), php])

	print("\n===== 2. IT STILL CANNOT KILL, AND UNDEAD STILL SHRUG IT OFF =====")
	var low = sim.make_char(100, "average", "Fighter", "Human")
	low.current_hp = 5
	var k2: Dictionary = _kill(sim, cm, low, md.generate_monster_by_name("Demon", 100, true))
	ck(int(k2["hp_after"]) >= 1, "a nearly dead player is left alive (%d HP)" % int(k2["hp_after"]))
	var und = sim.make_char(100, "average", "Fighter", "Undead")
	und.current_hp = und.get_total_max_hp()
	var k3: Dictionary = _kill(sim, cm, und, md.generate_monster_by_name("Demon", 100, true))
	ck(String(k3["text"]).find("no effect on your undead form") >= 0 and int(k3["lost"]) <= 3, "an Undead character is immune")

	print("\n===== 3. WHAT THE PLAYER IS TOLD MATCHES =====")
	var src := FileAccess.get_file_as_string("res://shared/combat_manager.gd")
	var i := src.find('"death_curse": {"label": "Death Curse"')
	var desc := src.substr(i, 260) if i >= 0 else ""
	ck(desc.find("%d%% of YOUR maximum HP" % int(round(CM.DEATH_CURSE_PLAYER_SHARE * 100.0))) >= 0,
		"the trait chip states the same share the curse uses")
	var help := FileAccess.get_file_as_string("res://client/client.gd")
	ck(help.find("strikes you for %d%% of your max HP" % int(round(CM.DEATH_CURSE_PLAYER_SHARE * 100.0))) >= 0,
		"and so does the help page")

	print("")
	print("RESULT: %s (%d failing)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
