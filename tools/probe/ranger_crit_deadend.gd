extends SceneTree
## A Ranger's cards can never crit — and every surface that mentions crit must say so.
##
## Owner 2026-09-10, having asked whether a Wolf companion card raises a Ranger's ability crit:
## *"We may need to put something in the players buff panel or avoid crit from being able to go
## there if the ranger can't crit though. Ensure when addressing these that we look for other
## classes and cards that may be effected."*
##
## `Steady Hand` sets no_glance, and the ability path zeroes crit alongside it — never glances,
## never crits. Crit is still summed from DEX, gear affixes, companion bonuses and the focus
## cards, then thrown away. The game was showing all of it as though it worked.
const CH := preload("res://shared/character.gd")
const DT := preload("res://shared/drop_tables.gd")
const CLIENT := "res://client/client.gd"

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	print("--- exactly one class voids crit, and the audit says which ---")
	var voided: Array = []
	var classes := ["Fighter", "Barbarian", "Paladin", "Wizard", "Sorcerer", "Sage",
		"Grifter", "Ranger", "Ninja"]
	for k in classes:
		if not CH.class_crit_affects_abilities(k):
			voided.append(k)
	print("      classes whose cards cannot crit: %s" % str(voided))
	ck(voided == ["Ranger"], "only the Ranger — no other class silently voids crit")

	print("\n--- the stat screen stops selling a stat the class cannot spend ---")
	var dex_r: String = CH.stat_description_for("dexterity", "Ranger")
	print("      Ranger DEX: %s" % dex_r)
	ck(not dex_r.contains("Hit chance, crit,"), "the Ranger's DEX no longer lists crit flatly")
	ck(dex_r.to_lower().contains("never crit"), "...it says the cards never crit")
	for k in ["Fighter", "Ninja", "Wizard"]:
		ck(CH.stat_description_for("dexterity", k).contains("crit"),
			"%s still gets crit listed (unchanged)" % k)

	print("\n--- combat and the UI read ONE predicate, not four copies of 'is Ranger' ---")
	var cm := FileAccess.get_file_as_string("res://shared/combat_manager.gd")
	ck(cm.contains("return not character.crit_affects_abilities()"),
		"combat's no-glance test defers to the shared rule")
	var cl := FileAccess.get_file_as_string(CLIENT)
	ck(cl.contains("Character.class_crit_affects_abilities("),
		"the client reads the same rule rather than testing the class name")
	ck(not cl.contains('class_type == "Ranger"'),
		"no hand-rolled 'is this a Ranger' test crept into the client")

	print("\n--- the buff panel marks a crit buff as inert, and explains why ---")
	ck(cl.contains("func _buff_is_inert("), "there is an inert-buff rule")
	ck(cl.contains("func _inert_buff_reason("), "...and a reason to show on hover")
	ck(cl.contains("buff_display_label.meta_hover_started.connect"),
		"the buff strip actually listens for hover (it did not before)")

	print("\n--- and the dead CARDS say so on their face ---")
	var focus_cards: Array = []
	for mt in DT.COMPANION_CARD_DATA:
		if String(DT.COMPANION_CARD_DATA[mt].get("kind", "")) == "focus":
			focus_cards.append("%s (%s)" % [String(DT.COMPANION_CARD_DATA[mt].get("name", "?")), mt])
	print("      pure-crit companion cards: %s" % ", ".join(focus_cards))
	ck(focus_cards.size() >= 3, "found the focus cards (all crit, all dead for a Ranger)")
	ck(cl.contains('String(_cd.get("kind", "")) == "focus"'),
		"the card description checks for a focus card")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
