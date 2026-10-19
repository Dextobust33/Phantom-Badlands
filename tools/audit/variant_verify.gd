extends SceneTree
const DropTables = preload("res://shared/drop_tables.gd")
const CharacterScript = preload("res://shared/character.gd")

func _init():
	seed(3)
	print("\n=== 1. DID THE LEGENDARY DROP RATE MOVE? (it must not) ===")
	# The OLD formula: weight = each variant's own rarity, summed over the pool.
	var old_total := 0
	var old_r1 := 0
	for v in DropTables.EGG_VARIANTS:
		var r := int(v.get("rarity", 10))
		old_total += r
		if r == 1: old_r1 += r
	var frozen_total := 0
	for k in DropTables.VARIANT_BAND_WEIGHTS:
		frozen_total += int(DropTables.VARIANT_BAND_WEIGHTS[k])
	print("  rarity-1 variants in the pool : %d  (was 10)" % old_r1)
	print("  OLD formula would now give     : %.2f%% legendary  <-- pool growth leaked into odds" % (100.0*float(old_r1)/float(old_total)))
	print("  FROZEN band weight gives       : %.2f%% legendary  <-- unchanged by pool size" % (100.0*float(DropTables.VARIANT_BAND_WEIGHTS[1])/float(frozen_total)))
	var hits := 0
	var N := 40000
	for i in range(N):
		if int(DropTables._pick_variant_weighted().get("rarity", 10)) == 1:
			hits += 1
	print("  measured over %d rolls         : %.2f%%" % [N, 100.0*float(hits)/float(N)])

	print("\n=== 2. IS A RARE VARIANT FELT NOW? (L30 owner, same companion) ===")
	var ch = CharacterScript.new()
	ch.initialize("probe", "Fighter", "Human")
	for _i in range(29): ch.level_up()
	while ch.unspent_stat_points > 0: ch.spend_stat_point("strength")
	print("  %-12s %6s %10s %12s" % ["variant", "mult", "own HP", "dmg/hit"])
	for row in [["common (r10)", 10], ["r5", 5], ["r3", 3], ["legendary (r1)", 1]]:
		var comp := {"name": "Test", "level": 20, "tier": 3, "sub_tier": 2, "border_tier": 0,
			"variant": "X", "variant_rarity": int(row[1]),
			"bonuses": {"attack": 8, "defense": 5, "hp_bonus": 6}}
		var hp := CharacterScript.calculate_companion_max_hp(comp, ch.get_total_max_hp(), ch.level)
		var dmg := DropTables.new().get_companion_attack_damage_v(comp, 3, ch.level, 20)
		print("  %-12s %5.2fx %10d %12d" % [String(row[0]),
			DropTables.companion_variant_mult(comp), hp, dmg])
	quit()
