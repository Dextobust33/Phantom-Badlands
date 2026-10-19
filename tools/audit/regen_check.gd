extends SceneTree
const MonsterDB = preload("res://shared/monster_database.gd")
const CombatManager = preload("res://shared/combat_manager.gd")

func _init():
	var mdb = MonsterDB.new()
	print("\n=== Can a regenerator still outheal a correct player? ===")
	print("Player ability = ~22%% of a normal bar. Regen must stay well under that.")
	print("%-8s %10s %12s %12s %10s %10s" % ["level", "normbar", "old regen", "new regen", "old %bar", "new %bar"])
	for lvl in [10, 50, 250, 1000]:
		var bar: float = mdb.ability_reference_hp(lvl)
		for role in [["normal", 1.0], ["elite", 1.8], ["boss", 2.8]]:
			var mhp: float = bar * float(role[1])
			var old_h: float = mhp * 0.10
			var cap: float = bar * CombatManager.REGEN_MAX_SHARE_OF_BAR
			var new_h: float = minf(old_h, cap)
			# player damage per turn against THIS monster, as a share of its pool
			var dmg: float = bar * 0.22
			var old_net: float = dmg - old_h
			var new_net: float = dmg - new_h
			if role[0] == "boss" or role[0] == "normal":
				print("L%-7d %10.0f %12.0f %12.0f   net/turn old %+8.0f  new %+8.0f  [%s]" % [
					lvl, bar, old_h, new_h, old_net, new_net, role[0]])
	print("\nnet/turn = player damage minus regen. NEGATIVE means the fight cannot be won.")
	quit()
