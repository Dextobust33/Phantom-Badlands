extends SceneTree
## Owner sheet 2026-10-13, item 15: "Companion Card face damage doesn't match the damage done in the combat
## log." Companion/dungeon strike cards had no server quote at all. They are now quoted through the same
## `_companion_strike_mod` the cast uses; this casts every strike KIND for real and compares the mean to the
## face, and fails if COMPANION_STRIKE_POWER drifts from the powers at the call sites.
const CM := preload("res://shared/combat_manager.gd")
const DT := preload("res://shared/drop_tables.gd")
const CASTS := 30
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _init() -> void:
	seed(20261013)
	var sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	get_root().add_child(sim)
	await process_frame
	var cm = sim.combat_mgr
	var by_kind := {}
	for t in DT.COMPANION_CARD_DATA:
		var k := String(DT.COMPANION_CARD_DATA[t].get("kind", ""))
		if CM.COMPANION_STRIKE_POWER.has(k) and not by_kind.has(k):
			by_kind[k] = "companion_card_" + String(t).to_lower().replace(" ", "_")
	ck(by_kind.size() == CM.COMPANION_STRIKE_POWER.size(), "every strike kind has a companion card to cast (%d of %d)" % [by_kind.size(), CM.COMPANION_STRIKE_POWER.size()])
	var worst := 0.0
	for kind in by_kind:
		for lvl in [20, 200]:
			var sum := 0.0
			var q := 0
			for i in range(CASTS):
				var ch = sim.make_char(lvl, "average", "Fighter", "Human")
				var mon: Dictionary = sim.make_monster(lvl, "normal", 400.0)
				mon["max_hp"] = 1000000000
				mon["current_hp"] = 1000000000
				cm.start_combat(0, ch, mon)
				var c = cm.active_combats[0]
				var id: String = by_kind[kind]
				c["combat_hand"] = [id]
				c["player_can_act"] = true
				c["suppress_monster_turn"] = true
				ch.current_stamina = ch.get_total_max_stamina()
				ch.current_mana = ch.get_total_max_mana()
				ch.current_energy = ch.get_total_max_energy()
				q = int(cm.preview_ability_effect(ch, c, id).get("value", -1))
				var hp0 := int(c["monster"]["current_hp"])
				cm.process_ability_command(0, id, "")
				var dealt: int = hp0 - int(c["monster"]["current_hp"])
				if kind == "execute":
					pass
				sum += float(dealt) / float(maxi(1, q))
				cm.active_combats.erase(0)
			var ratio: float = sum / CASTS   # mean of dealt/own-quote, each cast against its own character
			worst = maxf(worst, absf(ratio - 1.0))
			if absf(ratio - 1.0) > 0.12:
				print("      %s L%d: mean dealt/face %.2fx" % [kind, lvl, ratio])
	ck(worst <= 0.12, "every kind's face is within 12%% of the mean cast (worst %.0f%% off)" % (worst * 100.0))
	print("\n[COMPFACE] %s" % ("PASS" if fails == 0 else "FAIL - %d" % fails))
	quit(0 if fails == 0 else 1)
