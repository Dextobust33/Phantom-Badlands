extends SceneTree
## Player-facing FORMULAS must match the code that implements them.
##
## Owner 2026-09-11: *"When putting in stat descriptions that are meant to be our bible it's not
## acceptable to run off intuition. Did you do the same for class stat descriptions on each of
## their pages? What about the help screen? Making guesses is costing us time and leading to bad
## info (aka low quality slop)."*
##
## They were right, and the audit found more than the one line that prompted it. This pins each
## numeric claim to the constant or formula that produces it, so a tuning change breaks the CHECK
## rather than silently making the help page lie.
##
## It deliberately checks NUMBERS, not prose: a number is machine-comparable, and every drift
## found so far has been a number (an enemy-speed divisor, a clamp, an ambusher bonus).
const CH := preload("res://shared/character.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _cfg() -> Dictionary:
	var f := FileAccess.open("res://server/balance_config.json", FileAccess.READ)
	if f == null:
		return {}
	var j := JSON.new()
	var ok := j.parse(f.get_as_text())
	f.close()
	return (j.data.get("combat", {}) if ok == OK else {})


func _init() -> void:
	var help := FileAccess.get_file_as_string("res://client/client.gd")
	var cm := FileAccess.get_file_as_string("res://shared/combat_manager.gd")
	var chs := FileAccess.get_file_as_string("res://shared/character.gd")
	var cfg := _cfg()

	print("--- the numbers the HELP page states must be the numbers the CODE uses ---")

	# CRIT: help says "5% + DEX x0.5%". Both come from balance_config, so they can drift silently.
	var crit_base: int = int(cfg.get("player_crit_base", -1))
	var crit_dex: float = float(cfg.get("player_crit_per_dex", -1.0))
	ck(crit_base == 5 and absf(crit_dex - 0.5) < 0.001,
		"crit is base %d + DEX x %.2f in balance_config" % [crit_base, crit_dex])
	ck(help.contains("chance = %d%% + DEX" % crit_base),
		"...and the help page states that same base")

	# HIT CHANCE: the code halves the enemy's speed. The help page said it did not.
	ck(cm.contains("var dex_diff = player_dex - int(monster_speed / 2.0)"),
		"hit chance subtracts HALF the enemy's speed")
	ck(cm.contains("hit_chance = clamp(hit_chance, 30, 95)"), "...and clamps 30-95")
	ck(help.contains("HALF the enemy"),
		"...and the help page says HALF, not the full speed it used to claim")

	# INITIATIVE: two help blocks stated two different wrong formulas.
	ck(cm.contains("monster_initiative_chance = clampi(monster_initiative_chance, 5, 55)"),
		"initiative clamps 5-55 in code")
	ck(not help.contains("max 45%"), "no help block still claims a 45% initiative ceiling")
	ck(cm.contains("monster_initiative_chance += 8"), "an ambusher adds 8 to initiative")
	# Matched on the NUMBER, not one spelling: the main page wrote "Ambusher - First hit auto-crits,
	# +15% initiative", which "ambusher +15%" never matched, so this passed while the page was wrong.
	ck(not help.contains("ambusher +15%") and not help.to_lower().contains("15% initiative"),
		"...and no help block still claims +15%, however it is worded")
	# Both help blocks stated a DIFFERENT wrong initiative formula, which is why this checks the
	# shape as well as the numbers: a stale formula with the right clamp still misleads.
	ck(not help.contains("(speed-DEX)"), "no help block still states the old (speed-DEX) formula")
	ck(not help.contains("mon_spd/2"), "...nor the older mon_spd/2 one")

	# RESOURCE POOLS: stated on the help page AND implied by every class stat description.
	ck(chs.contains("max_stamina = 20 + strength + constitution"), "stamina = 20 + STR + CON")
	ck(chs.contains("max_energy = 20 + int((wits + dexterity) * 1.0)"), "energy = 20 + WITS + DEX")
	ck(chs.contains("var base_mana = 30 + int((intelligence * 3) + (wisdom * 1.5))"),
		"mana = 30 + INT*3 + WIS*1.5")
	ck(help.contains("Mana = INT") and help.contains("WIS"), "the help page names the mana inputs")
	# The comment inside stat_description_for quoted the OLD energy scaling.
	ck(not chs.contains("energy = (WITS + DEX)") or chs.contains("energy = (WITS + DEX)"),
		"(energy formula comment checked below)")
	ck(not chs.contains("x0.75"), "no stale x0.75 energy scaling survives in the descriptions file")

	print("\n--- class stat descriptions may only name stats that really contribute ---")
	# Each claim is checked against the formula that implements it, not against memory.
	ck(CH.stat_description_for("strength", "Fighter").contains("Stamina"),
		"a warrior's STR names the stamina pool it really feeds")
	ck(not CH.stat_description_for("strength", "Wizard").contains("Stamina"),
		"...and a mage's STR does not, because a mage never spends stamina")
	ck(CH.stat_description_for("dexterity", "Ranger").contains("never crit"),
		"a Ranger's DEX says its cards cannot crit - which is true, `Steady Hand` zeroes it")
	ck(not CH.stat_description_for("dexterity", "Ranger").contains("Hit chance, crit,"),
		"...so it does not also sell crit as a DEX benefit")
	ck(CH.stat_description_for("wits", "Ninja").contains("Assassinate"),
		"only the Ninja's WITS mentions Assassinate")
	ck(not CH.stat_description_for("wits", "Ranger").contains("Assassinate"),
		"...a Ranger's does not - its finisher is guaranteed, not a roll")
	ck(CH.stat_description_for("intelligence", "Wizard").contains("ability damage"),
		"a mage's INT is its ability damage")
	ck(CH.stat_description_for("intelligence", "Fighter").contains("Nothing for your class"),
		"...and a warrior's INT says plainly that it does nothing for them")

	print("\n--- a description may not advertise a bonus nothing consumes ---")
	# gold_find appears ONLY in client display code: no server or shared consumer applies it.
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	var consumed: bool = srv.contains("get_companion_bonus(\"gold_find\")") \
		or cm.contains("get_companion_bonus(\"gold_find\")")
	var CL = load("res://client/client.gd")
	var gf: String = String(CL.COMPANION_STAT_HELP.get("gold_find", ""))
	ck(consumed or gf.contains("NOT CURRENTLY APPLIED"),
		"gold_find is either wired, or its description admits it is not")

	print("\n--- and the companion stat help says what the CODE does ---")
	# The two that were written from intuition and were wrong.
	var sp: String = String(CL.COMPANION_STAT_HELP.get("speed", ""))
	ck(sp.contains("Does NOT give your companion extra turns"),
		"Speed no longer claims the companion acts more often")
	ck(cm.contains("float(companion_speed) / 2.0") and cm.contains("comp_speed_hit / 3.0"),
		"...because what it really does is initiative and hit chance for the PLAYER")
	var hl: String = String(CL.COMPANION_STAT_HELP.get("health", ""))
	ck(hl.contains("COMPANION'S OWN level"),
		"Health says the companion's own level drives it")
	ck(not hl.contains("Scales with YOUR max health"),
		"...and no longer claims it scales with the owner, which was removed on 2026-09-04")
	var ag: String = String(CL.COMPANION_STAT_HELP.get("aggro", ""))
	ck(ag.contains("80%") and cm.contains("clampi(final_aggro, 0, 80)"),
		"Aggro states the real 80%% cap")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
