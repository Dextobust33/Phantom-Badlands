extends SceneTree
## Player report (v0.9.764, CapsElfMagOra): "Magic bolt stated it did 593 damage, but this did
## not show/register on monster's health bar." Fighting an APEX Mimic.
##
## Reproduce it: the Mimic carries ABILITY_DISGUISE, which halves its HP at combat start and then
## REWRITES current_hp on reveal from a derived damage figure. Track what the log claims against
## what the bar would show, round by round.
func _init() -> void:
	var sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	get_root().add_child(sim)
	await process_frame
	var ch = sim.make_char(7, "average", "Wizard", "Human")
	ch.initialize_deck_collection_if_needed()
	var mon = sim.make_monster(8, "normal", 12.0)
	mon["name"] = "Mimic"
	mon["abilities"] = ["ambusher", "disguise", "gold_hoarder", "cunning_prey"]
	print("true max_hp before combat: %d" % int(mon.get("max_hp", 0)))
	sim.combat_mgr.start_combat(0, ch, mon)
	var c = sim.combat_mgr.active_combats[0]
	print("after start (disguised): max=%d cur=%d  disguise_active=%s"
		% [int(mon.max_hp), int(mon.current_hp), str(c.get("disguise_active", false))])
	var claimed := 0
	for rnd in range(5):
		c["round"] = rnd + 3          # force the reveal window open
		var before: int = int(mon.current_hp)
		var maxb: int = int(mon.max_hp)
		c["combat_hand"] = ["magic_bolt"]
		c["player_can_act"] = true
		ch.current_mana = ch.get_total_max_mana()
		var res: Dictionary = sim.combat_mgr.process_ability_command(0, "magic_bolt", str(int(ch.get_total_max_mana() * 0.05)))
		var after: int = int(mon.current_hp)
		var said := 0
		for m in res.get("messages", []):
			var t: String = str(sim._strip_bbcode(String(m)))
			if t.find("Magic Bolt") >= 0 or t.find("Bolt") >= 0:
				for w in t.split(" "):
					if w.is_valid_int() and int(w) > said:
						said = int(w)
		claimed += said
		print("round %d: bar %d/%d -> %d/%d   drop %d   log claimed ~%d   revealed=%s"
			% [rnd + 1, before, maxb, after, int(mon.max_hp), before - after, said,
				str(c.get("disguise_revealed", false))])
		if bool(res.get("combat_ended", false)) or int(mon.current_hp) <= 0:
			print("  (combat ended)")
			break
	quit(0)
