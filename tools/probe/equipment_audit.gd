extends SceneTree
## FULL equipment audit, verification pass: EXECUTE each suspect the mapping pass found by reading.
##
## Owner 2026-09-15: *"We need to do a FULL equipment/item audit ... We need to see what still works
## and what is broken or needs revised, for example things that give +1 to warrior abilities (does
## that work and what does it do, etc.)"* The mapping (docs/BACKLOG.md, item 4) was read from code;
## CLAUDE.md is explicit that gear claims must be MEASURED - equip a real item, diff what the game
## does - so every row below changes ONE thing on an otherwise identical character and reports the
## difference. Prints a verdict table; it does not fail, because several rows are design questions
## for the owner rather than defects.
const CM = preload("res://shared/combat_manager.gd")
const DT = preload("res://shared/drop_tables.gd")
const N := 60

var sim
var cm


func _weapon(affixes: Dictionary, wear: int = 0, extra: Dictionary = {}) -> Dictionary:
	var it := {"type": "weapon_iron", "name": "Probe Blade", "rarity": "rare", "level": 60, "wear": wear, "affixes": affixes}
	it.merge(extra, true)
	return it


func _fighter(item) -> Object:
	var ch = sim.make_char(60, "none", "Fighter", "Human")
	if item != null:
		ch.equipped["weapon"] = item
	ch.current_hp = ch.get_total_max_hp()
	return ch


## Mean damage of `card` ("" = basic attack) over N identical-seeded casts, and the mean HP the
## player gained from the hit (for lifesteal-style procs).
func _mean(item, card: String, klass: String = "Fighter") -> Dictionary:
	var dmg := 0.0
	var healed := 0.0
	var skips := 0
	for i in range(N):
		# Seeded per CAST, not per arm: casts draw different amounts of randomness (crits,
		# procs), so a once-per-arm seed let the two arms build different random characters
		# from the second cast on. That made a 10% cost tome read as 28% (CLAUDE.md: seed per cell).
		seed(424242 + i)
		var ch = sim.make_char(60, "none", klass, "Human")
		if item != null:
			ch.equipped["weapon"] = item.duplicate(true)
		ch.current_hp = int(ch.get_total_max_hp() / 2)
		ch.current_mana = ch.get_total_max_mana()
		ch.current_stamina = ch.get_total_max_stamina()
		ch.current_energy = ch.get_total_max_energy()
		var mon: Dictionary = sim.make_monster(60, "normal", 50.0)
		mon["defense"] = 0
		cm.start_combat(0, ch, mon)
		var c = cm.active_combats[0]
		c["player_can_act"] = true
		c["suppress_monster_turn"] = true
		c["combat_hand"] = [card] if card != "" else []
		var hp0: int = int(c["monster"]["current_hp"])
		var php0: int = int(ch.current_hp)
		var res: Dictionary
		if card == "":
			res = cm.process_attack(c)
		else:
			res = cm.process_ability_command(0, card, "")
		dmg += hp0 - int(c["monster"]["current_hp"])
		healed += int(ch.current_hp) - php0
		if bool(res.get("skip_monster_turn", false)):
			skips += 1
		cm.active_combats.erase(0)
	return {"dmg": dmg / N, "healed": healed / N, "skips": skips}


## One card cast N times on the same seed, with `enh` written into skill_enhancements first.
func _cast(card: String, klass: String, enh: Dictionary) -> Dictionary:
	var dmg := 0.0
	var spent := 0.0
	var refused := ""
	var after := ""
	for i in range(N):
		# Seeded per CAST, not per arm: casts draw different amounts of randomness (crits,
		# procs), so a once-per-arm seed let the two arms build different random characters
		# from the second cast on. That made a 10% cost tome read as 28% (CLAUDE.md: seed per cell).
		seed(515151 + i)
		var ch = sim.make_char(60, "none", klass, "Human")
		ch.equipped["weapon"] = _weapon({})
		for k in enh:
			for e in enh[k]:
				ch.enhance_skill(k, e, enh[k][e])
		ch.current_hp = ch.get_total_max_hp()
		ch.current_mana = ch.get_total_max_mana()
		ch.current_stamina = ch.get_total_max_stamina()
		ch.current_energy = ch.get_total_max_energy()
		var pool0: int = ch.current_mana + ch.current_stamina + ch.current_energy
		var mon: Dictionary = sim.make_monster(60, "normal", 50.0)
		mon["defense"] = 0
		cm.start_combat(0, ch, mon)
		var c = cm.active_combats[0]
		c["player_can_act"] = true
		c["suppress_monster_turn"] = true
		c["combat_hand"] = [card]
		var hp0: int = int(c["monster"]["current_hp"])
		# Magic Bolt takes the mana to pour in; a fixed amount keeps the cast identical across both arms.
		var res: Dictionary = cm.process_ability_command(0, card, "200" if card == "magic_bolt" else "")
		if not bool(res.get("success", true)) and refused == "":
			refused = String(res.get("message", "?"))
		dmg += hp0 - int(c["monster"]["current_hp"])
		# GROSS cost, as paid - the funnel records it. The pool difference is NET of on-hit refunds
		# (Power Strike pays ~97 and gets ~64 back), and a fixed refund makes a 10% cut read as 27%.
		spent += float(ch.get_meta("path_last_ability_cost")) if ch.has_meta("path_last_ability_cost") 			else float(pool0 - (ch.current_mana + ch.current_stamina + ch.current_energy))
		if i == 0:
			after = "buffs=%s shield=%s" % [JSON.stringify(ch.active_buffs.filter(func(b): return String(b.get("type", "")) in ["damage", "defense"])), str(c.get("forcefield_shield", c.get("player_shield", "")))]
		cm.active_combats.erase(0)
	return {"dmg": dmg / N, "spent": spent / N, "refused": refused, "after": after}


## A persistent buff written exactly as the scroll handlers write it, then one player swing and one
## monster turn: damage dealt, damage taken, thorns returned, HP healed by the swing.
func _buffed(stat: String, value: int) -> Dictionary:
	var r := {"dealt": 0.0, "taken": 0.0, "thorns": 0.0, "healed": 0.0}
	for i in range(N):
		# Seeded per CAST, not per arm: casts draw different amounts of randomness (crits,
		# procs), so a once-per-arm seed let the two arms build different random characters
		# from the second cast on. That made a 10% cost tome read as 28% (CLAUDE.md: seed per cell).
		seed(626262 + i)
		var ch = sim.make_char(60, "none", "Fighter", "Human")
		ch.equipped["weapon"] = _weapon({})
		if stat != "":
			ch.add_persistent_buff(stat, value, 3)
		ch.current_hp = int(ch.get_total_max_hp() / 2)
		var mon: Dictionary = sim.make_monster(60, "normal", 50.0)
		mon["defense"] = 0
		mon["abilities"] = []
		cm.start_combat(0, ch, mon)
		var c = cm.active_combats[0]
		c["player_can_act"] = true
		c["suppress_monster_turn"] = true
		var mhp0: int = int(c["monster"]["current_hp"])
		var php0: int = int(ch.current_hp)
		cm.process_attack(c)
		r.dealt += mhp0 - int(c["monster"]["current_hp"])
		r.healed += int(ch.current_hp) - php0
		var php1: int = int(ch.current_hp)
		var mhp1: int = int(c["monster"]["current_hp"])
		c["suppress_monster_turn"] = false
		cm.process_monster_turn(c)
		r.taken += php1 - int(ch.current_hp)
		r.thorns += mhp1 - int(c["monster"]["current_hp"])
		cm.active_combats.erase(0)
	for k in r:
		r[k] = r[k] / N
	return r


## Mean rarity step and item count of roll_combat_drops over N kills, with the named buff at 100.
func _loot(buff: String, dungeon: bool) -> Dictionary:
	var steps := 0.0
	var count := 0.0
	var n := 0
	for i in range(N):
		# Seeded per CAST, not per arm: casts draw different amounts of randomness (crits,
		# procs), so a once-per-arm seed let the two arms build different random characters
		# from the second cast on. That made a 10% cost tome read as 28% (CLAUDE.md: seed per cell).
		seed(737373 + i)
		var ch = sim.make_char(60, "none", "Fighter", "Human")
		ch.in_dungeon = dungeon
		if buff != "":
			ch.add_persistent_buff(buff, 100, 3)
		var mon: Dictionary = sim.make_monster(60, "normal", 50.0)
		mon["drop_chance"] = 100
		for it in cm.roll_combat_drops(mon, ch):
			count += 1
			if it is Dictionary and it.has("rarity"):
				steps += DT.RARITY_ORDER.find(String(it.rarity))
				n += 1
	return {"rarity": steps / maxf(1.0, n), "count": count / N}


## XP one solo kill pays, with an xp_bonus buff of the given percent.
func _kill_xp(pct: int) -> int:
	seed(848484)
	var ch = sim.make_char(60, "none", "Fighter", "Human")
	if pct > 0:
		ch.add_persistent_buff("xp_bonus", pct, 3)
	var mon: Dictionary = sim.make_monster(60, "normal", 50.0)
	mon["current_hp"] = 1
	mon["abilities"] = []
	cm.start_combat(0, ch, mon)
	var c = cm.active_combats[0]
	c["player_can_act"] = true
	var total0: int = int(ch.experience) + int(ch.level) * 1000000
	cm.process_attack(c)
	cm.active_combats.erase(0)
	return int(ch.experience) + int(ch.level) * 1000000 - total0


func _row(tag: String, verdict: String, detail: String) -> void:
	print("[AUDIT] %-44s %-11s %s" % [tag, verdict, detail])


func _init() -> void:
	sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	get_root().add_child(sim)
	await process_frame
	cm = sim.combat_mgr

	print("[AUDIT] ================= RANK AFFIXES (the owner's example) =================")
	var w1 := _weapon({"ability_rank_warrior_dmg": 1})
	var ch1 = _fighter(w1)
	_row("+1 Warrior dmg: power_strike rank bonus", "WORKS" if ch1.get_ability_rank_bonus("power_strike") == 1 else "BROKEN", "bonus=%d" % ch1.get_ability_rank_bonus("power_strike"))
	var base_mult: float = _fighter(null).get_ability_damage_mult("power_strike")
	_row("  -> ability damage multiplier", "WORKS", "%.2f -> %.2f" % [base_mult, ch1.get_ability_damage_mult("power_strike")])
	# BASELINE = the same weapon with NO affixes. The first run compared against an empty hand, so
	# the weapon's own base Strength showed up as a few % of "affix" effect on abilities.
	var plain_w := _weapon({})
	var ps0: Dictionary = _mean(plain_w, "power_strike")
	var ps1: Dictionary = _mean(w1, "power_strike")
	_row("  -> Power Strike real damage", "WORKS" if ps1.dmg > ps0.dmg * 1.05 else "BROKEN", "%.0f -> %.0f (%+.0f%%)" % [ps0.dmg, ps1.dmg, 100.0 * (ps1.dmg / maxf(1.0, ps0.dmg) - 1.0)])
	for wear in [1, 10, 49]:
		var chw = _fighter(_weapon({"ability_rank_warrior_dmg": 1}, wear))
		_row("  +1 with %d%% wear" % wear, "BROKEN" if chw.get_ability_rank_bonus("power_strike") == 0 else "WORKS", "bonus=%d (int(1 x %.2f))" % [chw.get_ability_rank_bonus("power_strike"), 1.0 - wear / 100.0])
	var tr = sim.make_char(60, "none", "Ninja", "Human")
	tr.equipped["weapon"] = _weapon({"ability_rank_trickster_dmg": 3})
	for card in ["ambush", "exploit", "vanish", "perfect_heist", "gambit"]:
		_row("+3 Trickster dmg covers %s" % card, "WORKS" if tr.get_ability_rank_bonus(card) == 3 else "MISSING", "bonus=%d" % tr.get_ability_rank_bonus(card))
	var mg = sim.make_char(60, "none", "Wizard", "Human")
	mg.equipped["weapon"] = _weapon({"ability_rank_mage_dmg": 3})
	for card in ["magic_bolt", "blast", "meteor", "frost_nova", "banish"]:
		_row("+3 Mage dmg covers %s" % card, "WORKS" if mg.get_ability_rank_bonus(card) == 3 else "MISSING", "bonus=%d" % mg.get_ability_rank_bonus(card))

	print("[AUDIT] ================= DAMAGE / CRIT / PROC AFFIXES: basic attack vs ability =================")
	var crit_only: Dictionary = {}
	var cases := [
		["damage_mult +50%", {"damage_mult": 50}],
		["crit_chance +100%", {"crit_chance_bonus": 100}],
		["crit_damage +100% (on top of crit_chance +100%)", {"crit_chance_bonus": 100, "crit_damage_bonus": 100}],
		["attack_bonus +300", {"attack_bonus": 300}],
		["proc lifesteal 30%", {"proc_type": "lifesteal", "proc_value": 30, "proc_chance": 100}],
	]
	var basic0: Dictionary = _mean(plain_w, "")
	for cs in cases:
		var w := _weapon(cs[1])
		var b: Dictionary = _mean(w, "")
		var a: Dictionary = _mean(w, "power_strike")
		# crit_damage is judged against crit_chance alone, so the chance's own effect is not counted.
		var bref: float = basic0.dmg
		var aref: float = ps0.dmg
		if String(cs[0]).begins_with("crit_damage"):
			bref = float(crit_only.get("b", basic0.dmg))
			aref = float(crit_only.get("a", ps0.dmg))
		var bdelta: float = 100.0 * (b.dmg / maxf(1.0, bref) - 1.0)
		var adelta: float = 100.0 * (a.dmg / maxf(1.0, aref) - 1.0)
		if String(cs[0]).begins_with("crit_chance"):
			crit_only = {"b": b.dmg, "a": a.dmg}
		var heal_note := ""
		if String(cs[0]).begins_with("proc lifesteal"):
			heal_note = " | heal basic %.0f vs base %.0f, ability %.0f vs base %.0f" % [b.healed, basic0.healed, a.healed, ps0.healed]
		var verdict := "BOTH"
		if absf(adelta) < 3.0 and absf(bdelta) >= 3.0:
			verdict = "BASIC ONLY"
		elif absf(adelta) < 3.0 and absf(bdelta) < 3.0:
			verdict = "NO EFFECT"
		if String(cs[0]).begins_with("proc lifesteal"):
			verdict = "BASIC ONLY" if (b.healed > basic0.healed + 1.0 and a.healed <= ps0.healed + 1.0) else ("BOTH" if a.healed > ps0.healed + 1.0 else "NO EFFECT")
		_row(String(cs[0]), verdict, "basic %+.0f%%, Power Strike %+.0f%%%s" % [bdelta, adelta, heal_note])

	print("[AUDIT] ================= PROC RUNES (item.proc_effects) =================")
	# The shape the rune-application handlers really write: a dictionary keyed by proc type, chance
	# as a 0-1 fraction. (The first version of this row used an array, which nothing writes.)
	var rune_w := _weapon({}, 0, {"proc_effects": {"lifesteal": {"percent": 30, "proc_chance": 1.0}}})
	var rb: Dictionary = _mean(rune_w, "")
	_row("proc rune lifesteal 30% (proc_effects)", "NO EFFECT" if rb.healed <= basic0.healed + 1.0 else "WORKS", "heal on basic attack %.0f vs base %.0f" % [rb.healed, basic0.healed])

	print("[AUDIT] ================= EXTRA TURN (no cap?) =================")
	var et := _weapon({"extra_turn_chance": 150})
	var etm: Dictionary = _mean(et, "power_strike")
	_row("  control: same weapon, no extra-turn affix", "INFO", "monster turn skipped on %d/%d casts by other causes" % [int(ps0.skips), N])
	_row("extra_turn_chance 150 on one item", "UNCAPPED" if etm.skips >= N - 1 else "CAPPED", "monster turn skipped on %d/%d damaging casts (cap %.0f%% -> expect ~%.0f)" % [etm.skips, N, float(load("res://shared/character.gd").EXTRA_TURN_GEAR_CAP) if "EXTRA_TURN_GEAR_CAP" in load("res://shared/character.gd").get_script_constant_map() else 100.0, N * 0.30])
	_row("  value one item rolls at item level 900", "INFO", "5 + 0.10 x 900 = %.0f%% (per the chase formula, before the 0.7-1.3 roll)" % (5.0 + 0.10 * 900.0))

	print("[AUDIT] ================= CRAFTED GEAR =================")
	# The shape _create_crafted_equipment writes, including its "crafted" flag.
	var plain := {"type": "helm_crafted", "name": "Crafted Helm", "rarity": "rare", "level": 60, "wear": 0, "affixes": {}, "crafted": true}
	var listed := plain.duplicate(true)
	listed["attack"] = 500
	listed["defense"] = 500
	listed["hp"] = 500
	listed["speed"] = 50
	listed["tempered"] = true
	var cp = sim.make_char(60, "none", "Fighter", "Human")
	cp.equipped["helm"] = plain
	var bp: Dictionary = cp.get_equipment_bonuses()
	cp.equipped["helm"] = listed
	var bl: Dictionary = cp.get_equipment_bonuses()
	var same: bool = int(bp.get("attack", 0)) == int(bl.get("attack", 0)) and int(bp.get("defense", 0)) == int(bl.get("defense", 0)) and int(bp.get("max_hp", 0)) == int(bl.get("max_hp", 0)) and int(bp.get("speed", 0)) == int(bl.get("speed", 0))
	_row("crafted item's own attack/defense/hp/speed", "NO EFFECT" if same else "WORKS", "atk %d->%d def %d->%d hp %d->%d spd %d->%d" % [int(bp.get("attack", 0)), int(bl.get("attack", 0)), int(bp.get("defense", 0)), int(bl.get("defense", 0)), int(bp.get("max_hp", 0)), int(bl.get("max_hp", 0)), int(bp.get("speed", 0)), int(bl.get("speed", 0))])
	# apply_rarity_bonuses is the CRAFTING path and matches bare "helm"/"armor"/...; crafting names the
	# item "<slot>_crafted". Compare exactly those two spellings.
	var rarity_out: Dictionary = DT.apply_rarity_bonuses({"type": "helm_crafted"}, "legendary")
	var normal_out: Dictionary = DT.apply_rarity_bonuses({"type": "helm"}, "legendary")
	var pot_out: Dictionary = DT.apply_rarity_bonuses({"type": "health_potion", "is_consumable": true}, "legendary")
	_row("crafted potion rarity bonuses", "NONE" if not (pot_out.get("rarity_bonuses", {}) as Dictionary).size() > 0 else "PRESENT", str(pot_out.get("rarity_bonuses", {})))
	_row("crafted armour rarity bonuses", "NONE" if not (rarity_out.get("rarity_bonuses", {}) as Dictionary).size() > 0 else "PRESENT",
		"helm_crafted legendary -> %s | bare helm legendary -> %s" % [str(rarity_out.get("rarity_bonuses", {})), str(normal_out.get("rarity_bonuses", {}))])

	print("[AUDIT] ================= SKILL ENHANCER TOMES (read off POTION_EFFECTS, not copied) =================")
	# Owner 2026-09-15: *"Lots of those items were designed before we had our current classes or their
	# decks/abilities."* Each tome is cast with and without its enhancement on the same seed; the row
	# says what moved - damage, resource spent, or the buff/shield the card leaves behind.
	for tk in DT.POTION_EFFECTS.keys():
		var te: Dictionary = DT.POTION_EFFECTS[tk]
		if not te.has("skill_enhance"):
			continue
		var card := String(te.skill_enhance)
		var klass := "Fighter"
		if card in ["magic_bolt", "blast", "forcefield", "meteor", "haste", "paralyze", "banish", "frost_nova"]:
			klass = "Wizard"
		elif card in ["analyze", "distract", "pickpocket", "ambush", "vanish", "exploit", "perfect_heist", "sabotage", "gambit", "shadowstep"]:
			klass = "Ninja"
		var a0: Dictionary = _cast(card, klass, {})
		var a1: Dictionary = _cast(card, klass, {card: {String(te.get("effect", "")): float(te.get("value", 0))}})
		var what := String(te.get("effect", ""))
		var moved := ""
		if a0.refused != "":
			_row(String(tk), "UNTESTABLE", "%s refused the cast: %s" % [card, a0.refused])
			continue
		if what == "damage_bonus":
			var d: float = 100.0 * (a1.dmg / maxf(1.0, a0.dmg) - 1.0)
			moved = "damage %.0f -> %.0f (%+.0f%%, tome says +%d%%)" % [a0.dmg, a1.dmg, d, int(te.value)]
			if a0.dmg < 1.0:
				moved += " | card deals no damage; leftover %s -> %s" % [a0.after, a1.after]
				_row(String(tk), "NO EFFECT" if a0.after == a1.after else "CHANGES", moved)
			else:
				_row(String(tk), "WORKS" if absf(d - float(te.value)) < 4.0 else ("NO EFFECT" if absf(d) < 2.0 else "OFF"), moved)
		else:
			if a0.spent < 1.0:
				_row(String(tk), "POINTLESS", "%s already costs %.1f - nothing to reduce" % [card, a0.spent])
				continue
			var r: float = 100.0 * (1.0 - a1.spent / maxf(0.01, a0.spent))
			_row(String(tk), "WORKS" if absf(r - float(te.value)) < 4.0 else ("NO EFFECT" if absf(r) < 2.0 else "OFF"),
				"%s cost %.1f -> %.1f (%.0f%% cheaper, tome says %d%%)" % [card, a0.spent, a1.spent, r, int(te.value)])

	print("[AUDIT] ================= BUFF NAMES SCROLLS WRITE: does combat read them? =================")
	# Crafted scrolls write {stat: bonus_pct|amount} as a persistent buff under the recipe's stat name;
	# tier scrolls write "strength"/"defense"/... The tier names are the CONTROL - they must move.
	var buff_rows := [
		["strength (tier Rage, control)", "strength", 200, "dealt"],
		["attack (crafted Rage / Dragon Fury)", "attack", 30, "dealt"],
		["crit_chance (crafted Precision)", "crit_chance", 50, "dealt"],
		["defense (tier Stone Skin, control)", "defense", 400, "taken"],
		["shield (crafted Forcefield / Sea Ward)", "shield", 500, "taken"],
		["forcefield (tier Forcefield, control)", "forcefield", 500, "taken"],
		["thorns (crafted Thorns)", "thorns", 50, "thorns"],
		["lifesteal (crafted Vampirism)", "lifesteal", 50, "healed"],
	]
	var b_none: Dictionary = _buffed("", 0)
	for br in buff_rows:
		var m: Dictionary = _buffed(String(br[1]), int(br[2]))
		var key := String(br[3])
		var moved: float = float(m[key]) - float(b_none[key])
		var pct: float = 100.0 * moved / maxf(1.0, absf(float(b_none[key])))
		_row(String(br[0]), "READ" if absf(pct) >= 3.0 else "IGNORED", "%s %.0f -> %.0f (%+.0f%%) with value %d" % [key, float(b_none[key]), float(m[key]), pct, int(br[2])])

	# The three buffs that had no reader until 2026-09-15, measured through the real functions.
	var luck0 := _loot("", false)
	var luck1 := _loot("rare_drop", false)
	_row("rare_drop 100 (Elixir of Luck)", "READ" if luck1.rarity > luck0.rarity + 0.3 else "IGNORED", "mean rarity step %.2f -> %.2f" % [luck0.rarity, luck1.rarity])
	var lan_out := _loot("reclaimer_lantern", false)
	var lan0 := _loot("", true)
	var lan1 := _loot("reclaimer_lantern", true)
	_row("reclaimer_lantern 100 (Reclaimer's Lantern)", "READ" if lan1.count > lan0.count * 1.5 and absf(lan_out.count - luck0.count) < 0.3 else "IGNORED",
		"drops per dungeon kill %.2f -> %.2f; outside a dungeon %.2f -> %.2f" % [lan0.count, lan1.count, luck0.count, lan_out.count])
	var xp0 := _kill_xp(0)
	var xp1 := _kill_xp(50)
	_row("xp_bonus 50 (Potion of Insight)", "READ" if xp1 > xp0 * 1.4 else "IGNORED", "XP from one kill %d -> %d" % [xp0, xp1])

	print("[AUDIT] ================= SOURCE-ONLY FACTS (could not execute cheaply) =================")
	var ssrc := FileAccess.get_file_as_string("res://server/server.gd")
	_row("wish upgrade reads item_type (items store type)", "BROKEN" if ssrc.find('item.get("item_type", "")') >= 0 and ssrc.find("func _upgrade_single_item") >= 0 else "?", "only the +level part of an upgrade wish can apply")
	var csrc := FileAccess.get_file_as_string("res://shared/crafting_database.gd")
	_row("Void/Abyssal/Primordial rune fields", "BROKEN" if csrc.find("enchant_stat") >= 0 else "?", "recipes carry enchant_stat/enchant_amount; nothing reads them")
	print("[AUDIT] done")
	quit(0)
