# DRIFT GUARD for the authoritative card preview.
#
# `combat_manager.preview_ability_effect()` is what the combat cards now display. It is a
# statement ABOUT the resolve code rather than the resolve code itself, so it can drift — which
# is exactly how the client's own mirror came to advertise a 252-point shield for a 27-point
# Forcefield, and Meteor at 2.1x what it dealt.
#
# This drives the REAL resolve path for each ability against a dummy monster and compares the
# actual HP removed (or shield granted) with what the preview promised. Damage carries variance,
# so it samples and compares means with a tolerance.
#
# Run after touching ANY damage formula:
#   godot --headless --path . --script res://tools/probe/preview_drift.gd
extends SceneTree

const CombatManager = preload("res://shared/combat_manager.gd")
const MonsterDatabase = preload("res://shared/monster_database.gd")

const SAMPLES := 40
const TOLERANCE := 0.18   # means should land within 18%; variance alone is well inside this

func _init():
	var CharacterScript = load("res://shared/character.gd")
	var cm = CombatManager.new()
	var md = MonsterDatabase.new()
	root.add_child(cm)
	root.add_child(md)
	cm.monster_database = md

	var cases := [
		["Fighter", "strength", ["power_strike", "cleave", "shield_bash", "devastate"]],
		["Wizard", "intelligence", ["magic_bolt", "blast", "meteor", "forcefield"]],
		["Ranger", "wits", ["ambush", "gambit", "exploit"]],
	]

	var failures := 0
	var checked := 0
	print("\n=== PREVIEW DRIFT GUARD — card promise vs real resolve ===")
	print("%-8s %-14s %10s %10s %9s  %s" % ["level", "ability", "preview", "actual", "ratio", "verdict"])

	for lvl in [5, 60]:
		for case in cases:
			var cls: String = String(case[0])
			var stat: String = String(case[1])
			for ability in case[2]:
				var name: String = String(ability)
				var preview := 0
				var total := 0.0
				var n := 0
				for i in range(SAMPLES):
					var ch = CharacterScript.new()
					ch.initialize("drift", cls, "Human")
					for _l in range(max(0, lvl - 1)):
						ch.level_up()
					while ch.unspent_stat_points > 0:
						ch.spend_stat_point(stat)
					ch.current_hp = ch.get_total_max_hp()

					var mon = md.scale_monster_to_level(
						md.get_monster_base_stats(MonsterDatabase.MonsterType.GNOLL), lvl, true)
					# A wall, so nothing dies mid-sample and truncates the damage.
					mon["max_hp"] = 100000000
					mon["current_hp"] = 100000000
					mon["defense"] = 0
					mon["abilities"] = []

					var combat := _make_combat(ch, mon, name)
					if i == 0:
						var pv: Dictionary = cm.preview_ability_effect(ch, combat, name)
						if pv.is_empty():
							break
						preview = int(pv.get("value", 0))

					var before_hp: int = int(mon["current_hp"])
					_resolve(cm, combat, cls, name)
					var dealt: int = before_hp - int(combat["monster"]["current_hp"])
					var gained: int = int(combat.get("forcefield_shield", 0))
					var got: int = maxi(dealt, gained)
					# Gambit can whiff entirely (self-damage instead), and the card deliberately
					# quotes the ON-HIT value with the odds beside it — so a miss is not a
					# sample of the number under test. Averaging misses in would make a correct
					# card look like drift.
					if name == "gambit" and got <= 0:
						continue
					total += float(got)
					n += 1

				if preview <= 0 or n == 0:
					continue
				checked += 1
				var actual: float = total / float(n)
				var ratio: float = actual / float(preview)
				var ok: bool = abs(ratio - 1.0) <= TOLERANCE
				if not ok:
					failures += 1
				print("%-8d %-14s %10d %10.0f %8.2fx  %s" % [
					lvl, name, preview, actual, ratio, "ok" if ok else "*** DRIFT ***"])

	print("\n%d checked, %d drifted." % [checked, failures])
	if failures > 0:
		print("A drifted row means the CARD IS LYING to the player again. Fix preview_ability_effect")
		print("to match the resolve path, or convert the ability so both read the same formula.")
	quit(1 if failures > 0 else 0)

func _make_combat(ch, mon: Dictionary, ability: String) -> Dictionary:
	# Momentum/Focus matter to the preview, so exercise a mid-build state rather than zero —
	# a preview that is only correct at 0 stacks is the bug this guard exists to catch.
	return {
		"peer_id": 1, "character": ch, "monster": mon, "round": 3,
		"momentum": 3, "combo": 3, "focus": 2,
		"player_can_act": true, "combat_log": [],
		"combat_hand": [ability],
		"outsmart_attempts": 0,
		"cc_resistance": 0, "enrage_stacks": 0, "thorns_damage": 0,
	}

func _resolve(cm, combat: Dictionary, cls: String, ability: String) -> void:
	# The real resolve path, dispatched the way process_ability_command dispatches it. A full
	# spend is what the preview quotes, so give the character a full bar first.
	var ch = combat["character"]
	ch.current_mana = ch.get_total_max_mana()
	ch.current_stamina = ch.get_total_max_stamina()
	ch.current_energy = ch.get_total_max_energy()
	match cls:
		"Wizard":
			# magic_bolt takes its spend as an argument; a full spend is the design's ceiling.
			var arg := ""
			if ability == "magic_bolt":
				arg = str(int(float(ch.max_mana) * cm.MAGIC_BOLT_FULL_SPEND_PCT))
			cm._process_mage_ability(combat, ability, arg)
		"Fighter":
			cm._process_warrior_ability(combat, ability)
		_:
			cm._process_trickster_ability(combat, ability)
