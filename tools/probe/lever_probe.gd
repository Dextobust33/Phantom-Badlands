extends SceneTree
# Does monster HP move fight length? Before #6g the answer was no: ability damage was a share
# of the same curve, so scaling HP scaled damage identically. Scales the LIVE curve only.
const MonsterDB = preload("res://shared/monster_database.gd")
const CombatMgr = preload("res://shared/combat_manager.gd")

func _init():
	var mdb = MonsterDB.new()
	print("\n=== IS MONSTER HP A REAL LEVER? ===")
	print("%-8s %14s %16s" % ["level", "live curve hp", "frozen ability bar"])
	for lvl in [1, 50, 1000, 10000]:
		print("%-8d %14.0f %16.0f" % [lvl, mdb.reference_monster_hp(lvl), mdb.ability_reference_hp(lvl)])
	print("\nThey are equal today (the frozen bar was snapshotted from the live curve).")
	print("The point is that refcal can now move the FIRST without moving the SECOND.")
	quit()
