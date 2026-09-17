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

	print("\n===== 3. IN A PARTY, EVERY MEMBER TAKES IT =====")
	# ⛑ IT FIRED FOR NOBODY. `_process_victory_with_abilities` returns early on
	# `suppress_victory` - a member's killing blow must not run the solo victory - and the curse
	# lived below that return, so an ability the monster's trait chip advertises did nothing at
	# all in co-op. Owner 2026-09-17, asked whether the killer or everyone should take it:
	# *"Everyone in the fight."*
	#
	# Driven through the real party victory path rather than checked in the source, because the
	# fault being guarded against is precisely a function that exists and is never reached.
	var pa = sim.make_char(100, "average", "Fighter", "Human")
	var pb = sim.make_char(100, "average", "Wizard", "Human")
	pa.name = "Aleader"
	pb.name = "Bmate"
	pa.current_hp = pa.get_total_max_hp()
	pb.current_hp = pb.get_total_max_hp()
	var pmon: Dictionary = md.generate_monster_by_name("Demon", 100, true)
	pmon["current_hp"] = 0          # the blow has landed; this is the victory beat
	var pcombat := {
		"members": [1, 2],
		"characters": {1: pa, 2: pb},
		"member_states": {1: {}, 2: {}},
		"monster": pmon,
		"round": 1,
	}
	cm.active_party_combats[1] = pcombat
	var a_before: int = int(pa.current_hp)
	var b_before: int = int(pb.current_hp)
	var pres: Dictionary = cm._party_victory(pcombat, [])
	var a_lost: int = a_before - int(pa.current_hp)
	var b_lost: int = b_before - int(pb.current_hp)
	var want_a: int = maxi(1, int(int(float(pa.get_total_max_hp()) * CM.DEATH_CURSE_PLAYER_SHARE)
		* (1.0 - minf(0.5, float(pa.get_effective_stat("wisdom")) / 200.0))))
	var want_b: int = maxi(1, int(int(float(pb.get_total_max_hp()) * CM.DEATH_CURSE_PLAYER_SHARE)
		* (1.0 - minf(0.5, float(pb.get_effective_stat("wisdom")) / 200.0))))
	print("  Fighter (%d HP) lost %d, expected %d | Wizard (%d HP) lost %d, expected %d" % [
		pa.get_total_max_hp(), a_lost, want_a, pb.get_total_max_hp(), b_lost, want_b])
	ck(a_lost > 0 and b_lost > 0, "BOTH members take the curse, not just the killer")
	ck(a_lost == want_a and b_lost == want_b,
		"and each takes a share of their OWN bar, so a party is not punished four times over")
	# The Wizard has more Wisdom, so it should resist more - proof the shared function is doing
	# the per-character maths rather than one figure applied to everyone.
	ck(want_a != want_b or pa.get_effective_stat("wisdom") == pb.get_effective_stat("wisdom"),
		"  (their Wisdom differs, so the amounts differ - one figure for all would not)")
	ck(pres.get("victory", false) and pres.get("combat_ended", false),
		"the party victory result is still a victory")
	var ptext := ""
	for m in pres.get("messages", []):
		ptext += String(m) + " "
	ck("death curse" in ptext.to_lower(), "and the log says so (%d chars)" % ptext.length())
	# ⚑ BOTH victory exits. A member's blow can finish it mid-order and a DoT can during the
	# monster phase; they used to build the result inline in two places, which is how something
	# added on victory ends up firing on one path only.
	var src0 := FileAccess.get_file_as_string("res://shared/combat_manager.gd")
	var rp := src0.find("func resolve_party_round(")
	var rp_end := src0.find("\nfunc ", rp + 10)
	var rpbody := src0.substr(rp, (rp_end - rp) if rp_end > rp else 6000)
	ck(rpbody.count("_party_victory(combat, entries)") == 2,
		"both party victory exits go through the one path (%d)" % rpbody.count("_party_victory(combat, entries)"))
	ck(not rpbody.contains('"victory": true, "messages": party_flatten_log'),
		"  and neither builds its own victory result any more")
	cm.active_party_combats.erase(1)

	print("\n===== 4. WHAT THE PLAYER IS TOLD MATCHES =====")
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
