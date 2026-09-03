# The companion stat + comparison helpers, against the SHARED formula the server uses.
extends SceneTree
const CharacterScript = preload("res://shared/character.gd")

func _init():
	var owner_hp := 1128
	var owner_lvl := 13
	var tanky := {"name": "Zombie Thrall", "level": 10, "sub_tier": 2, "tier": 1,
		"variant": "Normal", "bonuses": {"hp_bonus": 5, "defense": 2, "attack": 3}}
	var glassy := {"name": "Wolf Pup", "level": 10, "sub_tier": 1, "tier": 1,
		"variant": "Normal", "bonuses": {"attack": 8, "speed": 4}}
	print("\n=== companion HP via the SHARED static (same call the server makes) ===")
	for c in [tanky, glassy]:
		print("  %-14s L%-3d sub%-2d -> %d HP" % [c["name"], c["level"], c["sub_tier"],
			CharacterScript.calculate_companion_max_hp(c, owner_hp, owner_lvl)])
	var a := CharacterScript.calculate_companion_max_hp(tanky, owner_hp, owner_lvl)
	var b := CharacterScript.calculate_companion_max_hp(glassy, owner_hp, owner_lvl)
	print("\n  durability profile spread: %.2fx  %s" % [float(a)/maxf(1.0,float(b)),
		"(tanky IS tougher - the identity holds)" if a > b else "*** tanky is NOT tougher ***"])
	print("\n  A player could not see EITHER number before this: the panel showed the top three")
	print("  bonus values and no HP at all.")
	quit()
