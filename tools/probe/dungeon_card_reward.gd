extends SceneTree
## Do dungeons actually hand out cards when you clear them?
##
## Owner 2026-09-13: *"Can we confirm are dungeons giving cards upon completion?"*
##
## ⚑ WIRED IS NOT GIVEN. The roll is called from `_complete_dungeon`, which is easy to confirm by
## reading and proves nothing: the roll can fire and still hand back nothing if the themed card
## does not exist for that dungeon type, if the character is already maxed, or if the fallback
## pool comes up empty. Each of those returns the same "no card" as a failed chance roll, and a
## player cannot tell them apart. So this runs real completions and counts what a character ends
## up holding.
const ServerScript = preload("res://server/server.gd")
const CharacterScript = preload("res://shared/character.gd")
const DungeonDB = preload("res://shared/dungeon_database.gd")
const DropTablesScript = preload("res://shared/drop_tables.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _char(cls: String, lvl: int) -> Character:
	var c = CharacterScript.new()
	c.name = "Probe"
	c.class_type = cls
	c.level = lvl
	return c


func _init() -> void:
	var srv = ServerScript.new()

	print("===== IS A THEMED CARD DEFINED FOR EACH DUNGEON TYPE? =====")
	var types: Array = DungeonDB.DUNGEON_TYPES.keys()
	var without: Array = []
	for t in types:
		if String(DropTablesScript.dungeon_card_id_for_dungeon(String(t))) == "":
			without.append(String(t))
	print("  %d of %d dungeon types have a themed card" % [types.size() - without.size(), types.size()])
	if not without.is_empty():
		print("  without one (they fall back to a duplicate of a card you already know):")
		print("    " + ", ".join(without.slice(0, 12)) + (" ..." if without.size() > 12 else ""))

	print("\n===== THE ADVERTISED CHANCE, BY TIER =====")
	for tier in [1, 3, 5, 7, 9]:
		var chance: float = min(0.30, 0.05 + float(tier) * 0.02)
		print("  tier %d: %.0f%% per clear" % [tier, chance * 100.0])

	print("\n===== AND WHAT A PLAYER ACTUALLY WALKS AWAY WITH =====")
	# Force the roll so the CHANCE is not what is being measured - what is being measured is
	# whether a forced roll ever fails to produce a card, which is the silent-failure case.
	var classes := ["Fighter", "Wizard", "Ninja", "Grifter", "Sage"]
	var forced_runs := 0
	var forced_cards := 0
	var empties: Array = []
	for cls in classes:
		for t in types:
			var ch = _char(cls, 30)
			var res: Dictionary = srv._roll_dungeon_card_reward(ch, 5, String(t), true)
			forced_runs += 1
			if bool(res.get("granted", false)):
				forced_cards += 1
			elif empties.size() < 6:
				empties.append("%s / %s" % [cls, String(t)])
	print("  a FORCED roll produced a card in %d of %d cases" % [forced_cards, forced_runs])
	ck(forced_cards == forced_runs,
		"a clear that rolls a card always produces one%s" % [
			"" if empties.is_empty() else " - EMPTY: " + ", ".join(empties)])

	print("\n===== AND OVER A REALISTIC RUN OF CLEARS =====")
	# Unforced, so this is the rate a player would feel.
	for tier in [1, 5, 9]:
		var ch2 = _char("Ninja", 30)
		var got := 0
		var runs := 400
		for i in range(runs):
			var r2: Dictionary = srv._roll_dungeon_card_reward(ch2, tier, String(types[i % types.size()]), false)
			if bool(r2.get("granted", false)):
				got += 1
		var pct: float = 100.0 * float(got) / float(runs)
		var want: float = min(0.30, 0.05 + float(tier) * 0.02) * 100.0
		print("  tier %d: %d cards in %d clears = %.1f%% (advertised %.0f%%)" % [
			tier, got, runs, pct, want])
		# A character fills up on a themed card after MAX_ABILITY_COPIES, so the measured rate
		# drifts BELOW the advertised one over a long run. It must not be zero, and must not be
		# wildly above.
		ck(pct > 0.0, "tier %d clears do give cards" % tier)
		ck(pct <= want + 6.0, "tier %d does not exceed its advertised rate" % tier)

	print("\n===== WHICH DUNGEONS HAVE A CARD OF THEIR OWN =====")
	var themed: Array = []
	for t in types:
		var cid := String(DropTablesScript.dungeon_card_id_for_dungeon(String(t)))
		if cid != "":
			themed.append("%s -> %s" % [String(t), DropTablesScript.card_display_name(cid)])
	for line in themed:
		print("    " + line)
	# ⚑ REPORTED, NOT FAILED. Only 4 of 53 types have a card of their own, and that is missing
	# CONTENT rather than a broken mechanism - the other 49 correctly fall through to a duplicate.
	# A check that fails every run until somebody writes 49 cards is a check people learn to
	# ignore, and then it is worth nothing on the day it catches something real.
	print("  ADVISORY: %d of %d dungeon types have an exclusive card. The other %d give a"
		% [themed.size(), types.size(), types.size() - themed.size()])
	print("  duplicate of a card you already know, which is the fallback working, not a fault.")
	ck(themed.size() > 0, "at least the themed-card path is reachable (%d types)" % themed.size())

	print("\n===== WHEN DOES THE REWARD STOP? =====")
	# ⚑ THE NUMBER THAT MATTERS. Cards cap at MAX_ABILITY_COPIES each, and once every card a
	# class can hold is maxed the roll has nothing left to give - it returns "no card" exactly
	# like a failed chance roll. A player cannot tell those apart, so "dungeons stopped giving
	# cards" would read as a bug rather than as the pool running dry.
	for cls in ["Ninja", "Fighter", "Wizard"]:
		var ch3 = _char(cls, 40)
		var clears := 0
		var cards := 0
		var dry_at := -1
		while clears < 3000:
			clears += 1
			var r3: Dictionary = srv._roll_dungeon_card_reward(ch3, 9, String(types[clears % types.size()]), true)
			if bool(r3.get("granted", false)):
				cards += 1
			else:
				dry_at = clears
				break
		print("  %-8s ran dry after %d cards (at forced clear #%s)" % [
			cls, cards, str(dry_at) if dry_at > 0 else "never"])
	print("  (forced rolls, so this is the CEILING - at the real 23%% rate a tier-9 clear")
	print("   reaches it after roughly four times as many runs)")

	print("\n[DUNGEONCARD] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
