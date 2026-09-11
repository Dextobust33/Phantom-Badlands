extends SceneTree
## Every help topic BUILDS, and the numbers it states are the numbers the game uses.
##
## 2026-09-11 audit (docs/design/help_audit_2026-09-11.md): 26 help entries disagreed with the
## code. Title costs were ~100x too high and written as gold; poison, ethereal and the affix
## ladder were stale; a whole gathering section described a minigame with no callers. The fixes
## read constants where they could, which turns several topics into format strings - and a bad
## `%` in one of those fails only when the string is evaluated. So this builds all of them.
const CLIENT := "res://client/client.gd"

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _topic(secs: Array, title: String) -> String:
	for s in secs:
		if String(s.get("title", "")) == title:
			return String(s.get("content", ""))
	return ""


func _init() -> void:
	var c = load(CLIENT).new()
	var secs: Array = c._help_sections()
	ck(secs.size() >= 30, "all help topics build (%d)" % secs.size())
	var empty := []
	for s in secs:
		if String(s.get("content", "")).strip_edges() == "":
			empty.append(String(s.get("title", "?")))
	ck(empty.is_empty(), "no topic is blank %s" % ("" if empty.is_empty() else str(empty)))

	print("\n--- numbers are read, not typed ---")
	var titles := _topic(secs, "TITLES & ENDGAME")
	var t_ab := _topic(secs, "TITLE ABILITIES")
	for pair in [["Summon", Titles.JARL_ABILITIES["summon"]], ["Knight", Titles.HIGH_KING_ABILITIES["knight"]],
			["Bless", Titles.ETERNAL_ABILITIES["bless"]]]:
		var want: String = "%s %s valor" % [pair[0], c.format_number(int(pair[1]["valor_cost"]))]
		ck(titles.find(want) >= 0 and t_ab.find(want) >= 0, "both title topics state '%s'" % want)
	ck(titles.find("500g") < 0 and t_ab.find("5M+100g") < 0, "no stale gold prices survive")
	var pil := _topic(secs, "ETERNAL PILGRIMAGE")
	ck(pil.find(c.format_number(int(Titles.PILGRIMAGE_STAGES["trial_wealth"]["requirement"])) + " valor") >= 0, "Trial of Wealth states the real valor requirement")
	var mon := _topic(secs, "MONSTER ABILITIES")
	ck(mon.find("for %d turns" % CombatManager.POISON_DURATION_TURNS) >= 0, "poison duration is the constant")
	ck(mon.find("33%") >= 0 and mon.find("50% dodge") < 0, "ethereal is 33%, not 50%")
	ck(mon.find("Gold Hoarder") < 0, "Gold Hoarder (no effect in code) is gone")
	var uni := _topic(secs, "UNIVERSAL ABILITIES")
	ck(uni.find("%d%% chance" % CombatManager.DEFENSIVE_REPRIEVE_CHANCE) >= 0 and uni.find("All or Nothing") < 0,
		"defensive reprieve chance is the constant; retired All or Nothing is gone")
	var loot := _topic(secs, "LOOT & PROGRESSION")
	ck(loot.find("Artifact 6") >= 0 and loot.find("Common (0 affixes)") < 0, "affix ladder matches AFFIX_COUNTS")
	var eq := _topic(secs, "EQUIPMENT & GEAR")
	ck(eq.find("Nearly Broken") >= 0 and eq.find("merchants") < 0, "condition ladder complete; repair is at a blacksmith")
	var gath := _topic(secs, "CRAFTING & GATHERING")
	ck(gath.find("Wrong key") < 0 and gath.find("3 choices") >= 0, "gathering describes the live 3-choice minigame")
	var comp := _topic(secs, "COMPANIONS")
	ck(comp.find("Frost Guardian") < 0 and comp.find("Eggs:") >= 0, "companions describes eggs, not invented soul gems")
	var dun := _topic(secs, "DUNGEONS")
	ck(dun.find("Into the Depths") < 0 and dun.find("ONLY drop") < 0, "no quest that does not exist; eggs are not dungeon-only")
	var q := _topic(secs, "QUESTS")
	ck(q.find("Gold") < 0 and q.find("Rescue") >= 0, "quest rewards are Valor; the live board types are listed")
	var war := _topic(secs, "WARRIOR PATH")
	var rage_pct := int(round(CombatManager.BARBARIAN_RAGE_DMG_PER * 100.0))
	ck(war.find("+%d%% each" % rage_pct) >= 0 and war.find("+11% each") < 0,
		"Warrior Path formats, and states the real Rage ramp (+%d%%)" % rage_pct)
	var cm_src := FileAccess.get_file_as_string("res://shared/combat_manager.gd")
	ck(cm_src.find('"Drops a weapon. Guaranteed."') < 0 and cm_src.find('"50% chance to drop a weapon."') >= 0,
		"the in-combat Weapon Master badge states the real 50%")

	print("
--- the MAIN help page formats ---")
	# 2026-09-11 — it was a 23-argument positional `%` over text full of percent signs, so it failed
	# on every call and Godot showed it UNFORMATTED: every key read "[%s]", every "25%%" doubled.
	var main: String = c._main_help_text()
	ck(main.length() > 5000, "main help builds (%d chars)" % main.length())
	ck(main.find("[%s]") < 0, "no key placeholder survives as a raw [%s]")
	ck(main.find("%%") < 0, "no doubled percent sign reaches the player")
	ck(main.find("{k") < 0, "every {kN} key token was filled")
	ck(main.find("=Primary") >= 0 and main.find("[]=Primary") < 0, "the Primary key is named")
	ck(main.find("12 turns") >= 0 and main.find("35 rounds") < 0, "poison matches the constant on the main page too")
	ck(main.find("-25% defense for the rest of the fight") >= 0, "curse is a DEFENSE penalty, as the code applies it")
	ck(main.find("+15% initiative") < 0 and main.find("+8% chance to strike first") >= 0, "ambusher initiative is +8")
	ck(main.find("hides HP bar") < 0, "blind does not claim to hide the HP bar")
	ck(main.find("Frost(+10%def)") < 0 and main.find("dungeons only") < 0, "no invented soul gems, eggs not dungeon-only")

	c.free()
	print("\n[HELPTOPICS] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
