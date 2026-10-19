extends SceneTree
const Character = preload("res://shared/character.gd")

func _comp(name: String, lvl: int, aggro: int, sub: int = 1) -> Dictionary:
	return {"name": name, "level": lvl, "sub_tier": sub,
		"bonuses": {"aggro": aggro, "hp_bonus": 0, "defense": 0}}

func _init():
	print("\n=== WHICH ANCHOR WINS? companion HP = max(owner_side, own_side) * share ===")
	print("%-34s %9s %9s %9s %9s" % ["case", "ownerHP", "ownerSide", "ownSide", "compHP"])
	var cases := [
		["L50 player, L50 Succubus (12%)",        659, 50,  50, 12],
		["L50 player, L50 Chimaera (35%)",        659, 50,  50, 35],
		["L50 player, L50 Iron Golem (65%)",      659, 50,  50, 65],
		["L50 player, L10 Succubus  (under)",     659, 50,  10, 12],
		["L10 player, L250 Succubus (INVESTED)",  120, 10, 250, 12],
		["L10 player, L250 IronGolem(INVESTED)",  120, 10, 250, 65],
		["L250 player, L250 Succubus",           4200, 250, 250, 12],
	]
	for c in cases:
		var owner_hp: int = int(c[1]); var owner_lv: int = int(c[2])
		var cl: int = int(c[3]); var ag: int = int(c[4])
		var owner_side: float = float(owner_hp) * Character.companion_level_ratio_mult(cl, owner_lv)
		var own_side: float = Character.reference_player_hp(cl)
		var hp: int = Character.calculate_companion_max_hp(_comp("x", cl, ag), owner_hp, owner_lv)
		print("%-34s %9d %9d %9d %9d" % [c[0], owner_hp, int(owner_side), int(own_side), hp])
	print("\n=== share() by aggro ===")
	for a in [8, 12, 25, 35, 50, 65]:
		print("  aggro %2d%%  ->  share %.2f" % [a, Character.companion_hp_share({"aggro": a})])
	quit()
