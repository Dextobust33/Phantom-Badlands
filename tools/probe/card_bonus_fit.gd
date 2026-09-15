extends SceneTree
## Which kinds of card-specific bonus actually DO something for each card - measured, not written.
##
## Owner 2026-09-15, retiring the "+N to abilities" rank affixes: *"There should instead be equipment
## that increases specific skills (ensuring it actually benefits the skill and doesn't give like +
## damage to a skill with no damage)."* So a card only gets a bonus kind whose effect was SEEN here:
##   POWER    - skill enhancement damage_bonus +50 (the same key tomes write): read by the damage
##              funnel on damaging cards and the buff funnel on shield / buff / debuff cards
##   COST     - skill enhancement cost_reduction 50
##   DURATION - one "duration" milestone pick (+2 rounds through _buff_duration)
## Each card is cast by a class that can hold it, on the same per-cast seed in every arm, and the
## probe lists what moved: monster HP, monster stats, the player's buffs, numeric combat state, and
## the resource paid. A kind that moves nothing is not offered for that card.
const N := 6

var sim
var cm


func _numbers(ch, c: Dictionary) -> Dictionary:
	var out := {}
	var mon: Dictionary = c.get("monster", {})
	out["monster_hp_lost"] = float(int(mon.get("max_hp", 0)) - int(mon.get("current_hp", 0)))
	for k in ["strength", "defense", "speed"]:
		out["monster_" + k] = float(mon.get(k, 0))
	for k in c.keys():
		var v = c[k]
		if (v is int or v is float) and not String(k).begins_with("_") and not k in ["round", "player_can_act", "started_at"]:
			out["combat." + String(k)] = float(v)
	for b in ch.active_buffs:
		var key := "buff.%s" % String(b.get("type", "?"))
		out[key] = float(out.get(key, 0.0)) + float(b.get("value", 0))
		out[key + ".rounds"] = maxf(float(out.get(key + ".rounds", 0.0)), float(b.get("duration", 0)))
	out["player_hp"] = float(ch.current_hp)
	out["paid"] = float(ch.get_meta("path_last_ability_cost")) if ch.has_meta("path_last_ability_cost") else -1.0
	return out


func _arm(klass: String, card: String, arm: String) -> Dictionary:
	var sums := {}
	var refused := ""
	for i in range(N):
		seed(20260915 + i)
		var ch = sim.make_char(60, "none", klass, "Human")
		match arm:
			"power": ch.enhance_skill(card, "damage_bonus", 50.0)
			"cost": ch.enhance_skill(card, "cost_reduction", 50.0)
			"duration": ch.apply_milestone_pick(card, "duration")
		ch.current_hp = int(ch.get_total_max_hp() * 0.6)
		ch.current_mana = ch.get_total_max_mana()
		ch.current_stamina = ch.get_total_max_stamina()
		ch.current_energy = ch.get_total_max_energy()
		var mon: Dictionary = sim.make_monster(60, "normal", 50.0)
		mon["max_hp"] = 999999
		mon["current_hp"] = 999999
		mon["abilities"] = []
		cm.start_combat(0, ch, mon)
		var c = cm.active_combats[0]
		c["player_can_act"] = true
		c["suppress_monster_turn"] = true
		c["combat_hand"] = [card]
		# Finishers refuse without their engine; prime it the way card_face_truth does (every class's
		# engine is read from one of these three keys).
		c["combo"] = 4
		c["focus"] = 4
		c["momentum"] = 4
		if ch.has_meta("path_last_ability_cost"):
			ch.remove_meta("path_last_ability_cost")
		seed(777 + i)
		var res: Dictionary = cm.process_ability_command(0, card, "200" if card == "magic_bolt" else "")
		if not bool(res.get("success", true)) and refused == "":
			refused = String(res.get("message", "?")).substr(0, 60)
		var nums := _numbers(ch, c)
		# An outright kill (Judgement's / Unmaking's lethal chance) is not damage: averaging one in
		# swamps the mean and hides whether the bonus moved the ordinary hit. Same rule as card_face_truth.
		if int(c.get("monster", {}).get("current_hp", 1)) <= 0:
			sums["_kills"] = float(sums.get("_kills", 0.0)) + 1.0
			cm.active_combats.erase(0)
			continue
		sums["_n"] = float(sums.get("_n", 0.0)) + 1.0
		for k in nums:
			sums[k] = float(sums.get(k, 0.0)) + nums[k]
		cm.active_combats.erase(0)
	var n: float = maxf(1.0, float(sums.get("_n", 0.0)))
	for k in sums.keys():
		if not String(k).begins_with("_"):
			sums[k] = float(sums[k]) / n
	sums["_refused"] = refused
	return sums


func _moved(base: Dictionary, other: Dictionary) -> Array:
	var out: Array = []
	for k in other:
		if String(k).begins_with("_") or String(k) == "player_hp":
			continue
		var a: float = float(base.get(k, 0.0))
		var b: float = float(other[k])
		if absf(b - a) > maxf(0.5, absf(a) * 0.02):
			out.append("%s %s->%s" % [k, _fmt(a), _fmt(b)])
	return out


func _fmt(v: float) -> String:
	return str(int(round(v))) if absf(v) >= 10.0 else "%.1f" % v


func _init() -> void:
	sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	get_root().add_child(sim)
	await process_frame
	cm = sim.combat_mgr
	var CharacterScript = load("res://shared/character.gd")
	var arche := {
		"warrior": CharacterScript._WARRIOR_ARCHETYPE_ABILITIES,
		"mage": CharacterScript._MAGE_ARCHETYPE_ABILITIES,
		"trickster": CharacterScript._TRICKSTER_ARCHETYPE_ABILITIES,
	}
	var class_arch := {"Fighter": "warrior", "Barbarian": "warrior", "Paladin": "warrior",
		"Wizard": "mage", "Sorcerer": "mage", "Sage": "mage",
		"Grifter": "trickster", "Ranger": "trickster", "Ninja": "trickster"}
	var only: Array = OS.get_cmdline_user_args()   # e.g. -- Paladin Sage
	var measured := {}   # card -> {kind: true}, across every class that holds it
	for klass in ["Fighter", "Barbarian", "Paladin", "Wizard", "Sorcerer", "Sage", "Grifter", "Ranger", "Ninja"]:
		if not only.is_empty() and not klass in only:
			continue
		var cards: Array = (CharacterScript.CURATED_STARTER_DECKS_BY_CLASS.get(klass, []) as Array).duplicate()
		for extra in arche[class_arch[klass]]:
			if not extra in cards and not extra in CombatManager.COMBAT_DECK_NON_COMBAT:
				cards.append(extra)
		print("\n[FIT] ===== %s =====" % klass)
		for card in cards:
			var probe_ch = sim.make_char(60, "none", klass, "Human")
			var disp: String = cm._ability_display_name(probe_ch, card)
			var base := _arm(klass, card, "base")
			if String(base._refused) != "":
				print("[FIT] %-9s %-14s %-18s REFUSED: %s" % [klass, card, disp, base._refused])
				continue
			var power := _moved(base, _arm(klass, card, "power"))
			var cost := _moved(base, _arm(klass, card, "cost"))
			var dur := _moved(base, _arm(klass, card, "duration"))
			var in_deck: bool = card in (CharacterScript.CURATED_STARTER_DECKS_BY_CLASS.get(klass, []) as Array)
			var got: Dictionary = measured.get(card, {})
			if not power.is_empty(): got["power"] = true
			if not cost.is_empty(): got["cost"] = true
			if not dur.is_empty(): got["duration"] = true
			measured[card] = got
			print("[FIT] %-9s %-14s %-18s %s dmg=%s paid=%s | POWER: %s | COST: %s | DURATION: %s" % [klass, card, disp, "deck " if in_deck else "extra",
				_fmt(float(base.get("monster_hp_lost", 0.0))), _fmt(float(base.get("paid", -1.0))),
				"none" if power.is_empty() else ", ".join(power),
				"none" if cost.is_empty() else ", ".join(cost),
				"none" if dur.is_empty() else ", ".join(dur)])
	# THE GUARD: card_gear.gd's KINDS table must be exactly what was measured - a card must never be
	# offered a bonus that does nothing for it, nor miss one that works. A class-filtered run checks the
	# cards it measured (every class holding a card measures it the same).
	var fails := 0
	if true:
		var table: Dictionary = load("res://shared/card_gear.gd").KINDS
		for card in measured:
			var want: Array = (measured[card] as Dictionary).keys()
			want.sort()
			var have: Array = (table.get(card, []) as Array).duplicate()
			have.sort()
			if want != have:
				fails += 1
				print("[FIT] TABLE DRIFT  %s: measured %s, card_gear.KINDS says %s" % [card, str(want), str(have)])
		print("RESULT: %s (%d cards differ from card_gear.KINDS)" % ["PASS" if fails == 0 else "FAIL", fails])
	print("\n[FIT] done")
	quit(0 if fails == 0 else 1)
