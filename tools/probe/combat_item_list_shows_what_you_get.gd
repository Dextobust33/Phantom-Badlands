extends SceneTree
## Owner sheet 2026-10-13, item 18: "HP amounts that potions say in the combat use list aren't accurate."
## Measured on a geared level-40 character: the list said +155 HP for a potion that healed +381, because
## it measured the percentage part against the BASE max HP while the server heals against the TOTAL
## (gear, CON x5, house bonus); and every resource potion showed no amount at all, because the client read
## `max_resource` / `resource_name`, keys the server never sends. Compares, for every class and several
## potion tiers, what the list SHOWS with what the server's own functions GRANT.
const CharacterScript = preload("res://shared/character.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _gear(dt, lvl: int) -> Dictionary:
	var g := {}
	g["weapon"] = dt.generate_weapon(lvl)
	g["shield"] = dt.generate_shield(lvl)
	g["helm"] = dt._generate_item({"item_type": "helm_steel", "rarity": "epic"}, lvl)
	g["armor"] = dt._generate_item({"item_type": "armor_chain", "rarity": "epic"}, lvl)
	g["boots"] = dt._generate_item({"item_type": "boots_leather", "rarity": "epic"}, lvl)
	g["ring"] = dt._generate_item({"item_type": "ring_basic", "rarity": "epic"}, lvl)
	g["amulet"] = dt._generate_item({"item_type": "amulet_basic", "rarity": "epic"}, lvl)
	return g

func _init() -> void:
	seed(20261013)
	var dt = load("res://shared/drop_tables.gd").new()
	var c = load("res://client/client.gd").new()
	var checked := 0
	var wrong := 0
	var blank := 0
	var gear_boost_seen := false
	for cls in ["Fighter", "Barbarian", "Paladin", "Wizard", "Sorcerer", "Sage", "Grifter", "Ranger", "Ninja"]:
		for lvl in [15, 60, 150, 400]:
			var ch = CharacterScript.new()
			ch.initialize("PotionProbe", cls, "Human")
			ch.level = lvl
			ch.max_hp = 100 + lvl * 8
			for slot in _gear(dt, lvl).keys():
				var it: Dictionary = _gear(dt, lvl)[slot]
				if not it.is_empty():
					ch.equipped[slot] = it
			c.set("character_data", ch.to_dict())
			if ch.get_total_max_hp() > int(ch.max_hp * 1.3):
				gear_boost_seen = true
			for t in ["health_potion", "mana_potion", "stamina_potion", "energy_potion"]:
				var item: Dictionary = dt._generate_item({"item_type": t, "rarity": "common"}, lvl)
				if item.is_empty():
					continue
				var tier := int(item.get("tier", 0))
				var effect: Dictionary = dt.consumable_effect(item)
				var want := ""
				if effect.has("heal"):
					want = "+%d HP" % dt.consumable_heal_amount(item, effect, ch.get_total_max_hp(), tier)
				else:
					var pr: String = ch.get_primary_resource()
					var pool := 0
					match pr:
						"stamina": pool = ch.get_total_max_stamina()
						"energy": pool = ch.get_total_max_energy()
						_: pool = ch.get_total_max_mana()
						
					want = "+%d %s" % [dt.consumable_resource_amount(item, effect, pool, tier), pr]
				var shown: String = c._combat_item_gain_line(item)
				checked += 1
				if shown == "":
					blank += 1
				if shown != want:
					wrong += 1
					if wrong <= 5:
						print("      %s L%d %s: list shows '%s', server grants '%s'" % [cls, lvl, t, shown, want])
	ck(checked > 100, "compared %d class x level x potion cases" % checked)
	ck(gear_boost_seen, "the test characters really are geared (total max HP well above base) - otherwise this proves nothing")
	ck(blank == 0, "no potion in the list is blank (%d were)" % blank)
	ck(wrong == 0, "what the list shows is what the server grants, in every case (%d differ)" % wrong)
	print("\n[POTIONLIST] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
