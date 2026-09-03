# Compare what a combat CARD PROMISES against what the SERVER ACTUALLY DEALS, for a fresh
# no-gear character. Reproduces the client's `_estimate_ability_card_effect` formulas verbatim
# alongside the real combat_manager path, so a disagreement is visible as a ratio.
extends SceneTree
const CombatManager = preload("res://shared/combat_manager.gd")
const MonsterDatabase = preload("res://shared/monster_database.gd")

func _init():
	var CharacterScript = load("res://shared/character.gd")
	var cm = CombatManager.new()
	var md = MonsterDatabase.new()
	root.add_child(cm)
	cm.monster_database = md

	print("\n=== CARD PROMISE vs SERVER TRUTH — fresh character, NO GEAR ===")
	for case in [["Fighter", "strength", 3], ["Fighter", "strength", 5], ["Fighter", "strength", 10],
				 ["Wizard", "intelligence", 3], ["Wizard", "intelligence", 5], ["Wizard", "intelligence", 10],
				 ["Ranger", "wits", 3], ["Ranger", "wits", 5], ["Ranger", "wits", 10]]:
		var cls: String = case[0]
		var stat: String = case[1]
		var lvl: int = int(case[2])
		var ch = CharacterScript.new()
		ch.initialize("probe", cls, "Human")
		for i in range(max(0, lvl - 1)):
			ch.level_up()
		while ch.unspent_stat_points > 0:
			ch.spend_stat_point(stat)

		var atk: int = ch.get_total_attack()
		var s_str: int = ch.get_effective_stat("strength")
		var s_int: int = ch.get_effective_stat("intelligence")
		var s_wit: int = ch.get_effective_stat("wits")
		var maxhp: int = ch.get_total_max_hp()
		var bar: float = float(md.ability_reference_hp(lvl)) if md.has_method("ability_reference_hp") else 0.0

		print("\n--- L%d %s (no gear) | attack=%d STR=%d INT=%d WITS=%d maxHP=%d | ability bar=%.0f" % [
			lvl, cls, atk, s_str, s_int, s_wit, maxhp, bar])
		print("%-14s %12s %12s %10s" % ["ability", "card says", "server does", "card/real"])

		var rows := []
		# --- server anchored abilities (weight x bar x stat ratio) ---
		for ab in ["power_strike", "cleave", "magic_bolt", "blast", "meteor"]:
			if not CombatManager.ABILITY_WEIGHTS.has(ab):
				continue
			var st := "strength"
			if ab in ["magic_bolt", "blast", "meteor"]:
				st = "intelligence"
			var real: float = cm._ability_anchored_damage(ch, st, float(CombatManager.ABILITY_WEIGHTS[ab]))
			rows.append([ab, _card(ab, atk, s_str, s_int, s_wit, maxhp), real])
		# --- legacy (NOT anchored) abilities: attack-based server formulas ---
		var str_m: float = 1.0 + sqrt(float(s_str)) / 10.0
		var wit_m: float = 1.0 + sqrt(float(s_wit)) / 10.0
		rows.append(["shield_bash", _card("shield_bash", atk, s_str, s_int, s_wit, maxhp), float(atk) * 1.5 * str_m])
		rows.append(["devastate@1", _card("devastate", atk, s_str, s_int, s_wit, maxhp), float(atk) * 3.0 * str_m])
		rows.append(["devastate@5", _card("devastate", atk, s_str, s_int, s_wit, maxhp), float(atk) * 7.0 * str_m])
		rows.append(["ambush", _card("ambush", atk, s_str, s_int, s_wit, maxhp), float(atk) * 3.0 * wit_m * 1.25])
		rows.append(["gambit", _card("gambit", atk, s_str, s_int, s_wit, maxhp), float(atk) * 4.5 * wit_m])
		rows.append(["forcefield", _card("forcefield", atk, s_str, s_int, s_wit, maxhp),
			float(maxhp) * CombatManager.FORCEFIELD_SHARE_OF_BAR * cm._ability_stat_ratio(ch, "intelligence")])

		for r in rows:
			var card_v: float = float(r[1])
			var real_v: float = float(r[2])
			if real_v <= 0.0:
				continue
			var flag := ""
			var ratio: float = card_v / real_v
			if ratio > 1.35 or ratio < 0.74:
				flag = "   <-- LIES"
			print("%-14s %12.0f %12.0f %9.2fx%s" % [String(r[0]), card_v, real_v, ratio, flag])
	quit()

# Verbatim mirror of client.gd `_estimate_ability_card_effect` (the numbers on the card).
func _card(ab: String, atk: int, s_str: int, s_int: int, s_wit: int, _maxhp: int) -> float:
	match ab:
		"magic_bolt":
			# card uses PLANNED SPEND; at a full-ish spend the planned cost is the pool bite.
			var im: float = 1.0 + max(sqrt(float(s_int)) / 5.0, float(s_int) / 75.0)
			return 30.0 * im   # ~30 mana planned at low level
		"blast":
			return 50.0 * (1.0 + float(s_int) * 0.04) * 2.0
		"meteor":
			return 100.0 * (1.0 + float(s_int) * 0.04) * 3.5
		"power_strike":
			return float(atk) * 2.0 * (1.0 + sqrt(float(s_str)) / 10.0)
		"cleave":
			return float(atk) * 2.5 * (1.0 + sqrt(float(s_str)) / 10.0)
		"shield_bash":
			return float(atk) * 1.5 * (1.0 + sqrt(float(s_str)) / 10.0)
		"devastate":
			return float(atk) * 5.0 * (1.0 + sqrt(float(s_str)) / 10.0)
		"ambush":
			return float(atk) * 3.0 * (1.0 + sqrt(float(s_wit)) / 10.0) * 1.25
		"gambit":
			return float(atk) * 4.5 * (1.0 + sqrt(float(s_wit)) / 10.0)
		"forcefield":
			return 100.0 + float(s_int) * 8.0
	return 0.0
