# "They should have to invest around the same amount of extra to accomplish it just like the
# mages and warrior do to kill the monster with their abilities." (owner, 2026-09-03)
#
# So MEASURE the investment: what share of your own resource pool does it cost to remove one
# same-level monster, by class and by route?
extends SceneTree
const CombatManager = preload("res://shared/combat_manager.gd")
const MonsterDatabase = preload("res://shared/monster_database.gd")

func _init():
	var cm = CombatManager.new(); var md = MonsterDatabase.new()
	root.add_child(cm); root.add_child(md); cm.monster_database = md
	print("\n=== COST TO REMOVE ONE FULL HEALTH BAR (share of your own resource pool) ===")
	print("%-22s %10s %12s %14s" % ["route", "weight", "cost/cast", "to clear 1 bar"])
	var W = CombatManager.ABILITY_WEIGHTS
	var T = CombatManager.VARIABLE_COST_TABLE
	for row in [["Mage: Magic Bolt", "magic_bolt"], ["Mage: Blast", "blast"],
				["Warrior: Cleave", "cleave"], ["Warrior: Power Strike", "power_strike"],
				["Trickster: Ambush", "ambush"], ["Trickster: Gambit", "gambit"]]:
		var ab: String = String(row[1])
		if not W.has(ab):
			continue
		var w: float = float(W[ab])
		var pct: float = 0.0
		if ab == "magic_bolt":
			pct = CombatManager.MAGIC_BOLT_FULL_SPEND_PCT * 100.0
		elif T.has(ab):
			pct = float(T[ab].get("cost_percent", 0))
		var casts: float = 1.0 / maxf(0.01, w)
		print("%-22s %9.2f %11.0f%% %13.0f%%" % [String(row[0]), w, pct, casts * pct])

	print("\n=== TRICKSTER VIA OUTSMART: the Read ramp IS the investment ===")
	var ramp_cost := 0.0
	for ab in ["ambush", "sabotage", "distract", "pickpocket"]:
		if T.has(ab):
			ramp_cost += float(T[ab].get("cost_percent", 0))
	var avg_card: float = ramp_cost / 4.0
	var stacks: int = CombatManager.COMBO_MAX
	print("  Read needs %d stacks; a Trickster card averages %.0f%% of the energy pool" % [stacks, avg_card])
	print("  Building a full Read therefore costs about %.0f%% of the pool, over %d turns," % [avg_card * float(stacks), stacks])
	print("  plus an optional energy commitment worth up to +%d%% odds." % CombatManager.OUTSMART_DUMP_MAX_BONUS)
	print("\n  Compare that against the 'to clear 1 bar' column above. Regen over %d turns" % stacks)
	print("  offsets part of it, exactly as it does for a mage spending across several casts.")
	quit()
