# Can a Trickster actually REACH a full Read? Playtest report: ran dry at 3 stacks, and
# attacking for a round restored no energy at all.
extends SceneTree
const CombatManager = preload("res://shared/combat_manager.gd")

func _init():
	var CharacterScript = load("res://shared/character.gd")
	var cm = CombatManager.new(); root.add_child(cm)
	print("\n=== CAN A TRICKSTER REACH %d READ? ===" % CombatManager.COMBO_MAX)
	print("%-8s %8s %10s %12s %14s %s" % ["level", "energy", "cost/card", "cards afford", "baseline regen", "verdict"])
	for lvl in [5, 10, 30, 60]:
		var ch = CharacterScript.new()
		ch.initialize("probe", "Ranger", "Human")
		for _i in range(max(0, lvl-1)): ch.level_up()
		while ch.unspent_stat_points > 0: ch.spend_stat_point("wits")
		var pool: int = ch.get_total_max_energy()
		ch.current_energy = pool
		# Cost of a typical Read-building Trickster card, via the real cost path.
		var t = CombatManager.VARIABLE_COST_TABLE
		var pct: float = float(t.get("ambush", {}).get("cost_percent", 22))
		var per_card: int = maxi(1, int(float(ch.max_energy) * pct / 100.0))
		var afford: float = float(pool) / float(maxi(1, per_card))
		# Baseline (no-gear, no-companion) regen per turn for this class.
		var before: int = ch.current_energy
		ch.current_energy = maxi(0, pool - 50)
		var msgs := []
		cm._apply_gear_resource_regen(ch, msgs)
		var regen: int = ch.current_energy - (pool - 50)
		var ok: bool = afford >= float(CombatManager.COMBO_MAX)
		print("%-8d %8d %10d %12.1f %14d %s" % [
			lvl, pool, per_card, afford, regen,
			"ok" if ok else "*** CANNOT REACH FULL READ ***"])
	print("\nBaseline regen of 0 means energy comes ONLY from gear or a companion — there is no")
	print("class regen for Tricksters or Warriors the way mages get 1.2-2%% mana per turn.")
	quit()
