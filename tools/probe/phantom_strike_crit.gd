extends SceneTree
## Does Phantom Strike actually crit an ability, and does the log SAY so?
##
## Owner 2026-09-13: *"I'm not sure Phantom strike is actually critting with ambush or other
## damaging abilities like it says or maybe it's just not reporting them in the combat log?"*
##
## Two questions, and they need separating - a player cannot tell "it did not happen" from "it
## happened silently", and the fix is completely different. So this measures the DAMAGE with and
## without the setup, and separately inspects the MESSAGES the fight produced.
const CombatManagerScript = preload("res://shared/combat_manager.gd")
const CharacterScript = preload("res://shared/character.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _mon() -> Dictionary:
	return {"name": "Goblin", "level": 10, "current_hp": 100000, "max_hp": 100000,
		"strength": 5, "defense": 0, "speed": 10, "experience_reward": 10, "gold_reward": 5}


func _dmg_with_vanish(cm, ch, vanished: bool) -> Array:
	"""One Ambush, with or without the Phantom Strike setup. Returns [damage, messages]."""
	var mon := _mon()
	cm.start_combat(2, ch, mon)
	var combat = cm.get_active_combat(2)
	if vanished:
		combat["vanished"] = true
	var before: int = int(combat.monster.current_hp)
	var msgs: Array = []
	var base := 400
	var out: int = cm.apply_ability_damage_modifiers(base, ch.level, combat.monster, ch, combat, msgs)
	cm.end_combat(2, false)
	return [out, msgs, base]


func _init() -> void:
	var cm = CombatManagerScript.new()
	get_root().add_child(cm)
	var ch = CharacterScript.new()
	ch.name = "Probe"
	ch.class_type = "Ninja"
	ch.level = 20

	print("===== DOES THE SETUP ACTUALLY MULTIPLY THE DAMAGE? =====")
	# Averaged, because an ordinary crit can also fire and would otherwise be mistaken for the
	# setup working. The SETUP case must be reliably higher, not occasionally.
	var plain_total := 0
	var vanish_total := 0
	var n := 200
	for i in range(n):
		plain_total += int(_dmg_with_vanish(cm, ch, false)[0])
	for i in range(n):
		vanish_total += int(_dmg_with_vanish(cm, ch, true)[0])
	var plain := float(plain_total) / n
	var vanish := float(vanish_total) / n
	print("  base 400  ->  no setup %.0f   with Phantom Strike %.0f   (x%.2f)" % [
		plain, vanish, vanish / maxf(1.0, plain)])
	ck(vanish > plain * 1.15,
		"Phantom Strike raises ability damage (%.2fx over the ordinary roll)" % (vanish / maxf(1.0, plain)))
	ck(CombatManagerScript.ABILITY_CRIT_DAMAGE > 1.0,
		"the crit multiplier is %.2fx" % CombatManagerScript.ABILITY_CRIT_DAMAGE)

	print("\n===== AND DOES IT SAY SO? =====")
	var r = _dmg_with_vanish(cm, ch, true)
	var said := false
	for m in r[1]:
		if String(m).to_lower().find("shadow") >= 0 or String(m).to_lower().find("phantom") >= 0:
			said = true
			print("    log line: %s" % String(m))
	ck(said, "the Phantom Strike consumption announces itself in the combat log")
	# ⚑ AND IN THE WORDS A PLAYER IS LOOKING FOR. It always printed a line; the line said "the
	# strike lands true", which names neither the card nor the crit, while every ordinary crit
	# announces itself as CRITICAL!. That is indistinguishable from "it did not fire".
	var named := false
	var said_crit := false
	for m in r[1]:
		var t := String(m)
		if t.find("Phantom Strike") >= 0:
			named = true
		if t.find("CRITICAL") >= 0:
			said_crit = true
	ck(named, "...naming the CARD, so it can be told from any other bonus")
	ck(said_crit, "...and using the word CRITICAL, the same as every other crit in the game")

	print("\n===== WHAT ABOUT AN ORDINARY CRIT? =====")
	# The owner's real question is whether crits are REPORTED at all on the ability path. Force
	# the shared roll to land by driving many casts and looking for any crit line.
	var crit_lines := 0
	var casts := 400
	for i in range(casts):
		var rr = _dmg_with_vanish(cm, ch, false)
		for m in rr[1]:
			var lm := String(m).to_lower()
			if lm.find("crit") >= 0:
				crit_lines += 1
				break
	print("  %d of %d ordinary ability casts produced a line containing 'crit'" % [crit_lines, casts])
	ck(crit_lines > 0,
		"an ordinary ability crit is visible in the log (%d of %d)" % [crit_lines, casts])

	print("\n[PHANTOMSTRIKE] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
