extends SceneTree
## Owner sheet 2026-10-13, item 3: "Inspecting gear descriptions are also missing some of the things
## listed on the preview." Measured at the time: 90 of 227 generated epic-and-up items showed a stat on
## the inventory card (card cost/power bonuses, crit, extra turns, resource on hit, HP on kill) that the
## Inspect page did not mention. Both now read the one `_chase_affix_rows` table; this pins it.
const DT = preload("res://shared/drop_tables.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _strip(t: String) -> String:
	var out := ""
	var depth := 0
	for ch in t:
		if ch == "[":
			depth += 1
		elif ch == "]":
			depth = maxi(0, depth - 1)
		elif depth == 0:
			out += ch
	return out

func _nums(t: String) -> Array:
	var res: Array = []
	var cur := ""
	for ch in t:
		if ch >= "0" and ch <= "9":
			cur += ch
		else:
			if cur != "":
				res.append(cur)
			cur = ""
	if cur != "":
		res.append(cur)
	return res

func _client():
	var c = load("res://client/client.gd").new()
	c.set("character_data", {"class": "Fighter", "level": 60, "equipped": {}, "inventory": []})
	var out := RichTextLabel.new()
	out.bbcode_enabled = true
	c.set("game_output", out)
	return [c, out]

func _init() -> void:
	seed(20261013)
	var pair = _client()
	var c = pair[0]
	var out: RichTextLabel = pair[1]

	print("--- every chase key a hand-built item can carry appears, in words, on Inspect ---")
	var item := {"name": "Probe Blade", "type": "weapon", "rarity": "legendary", "level": 60, "id": 7,
		"affixes": {"attack_bonus": 10, "damage_mult": 11, "crit_chance_bonus": 12, "crit_damage_bonus": 13,
			"extra_turn_chance": 14, "hp_on_kill": 15, "mana_on_hit": 16, "stamina_on_hit": 17, "energy_on_hit": 18,
			"card_power_cleave": 21, "card_cost_blast": 22}}
	var rows: Array = c._chase_affix_rows(item["affixes"], item)
	ck(rows.size() >= 10, "the table yields a row per chase effect (%d)" % rows.size())
	out.clear()
	c.display_item_details(item, "inventory")
	var page := _strip(out.get_parsed_text())
	var missing: Array = []
	for n in ["11", "12", "13", "14", "15", "16", "17", "18", "21", "22"]:
		if not (n in _nums(page)):
			missing.append(n)
	ck(missing.is_empty(), "Inspect shows all ten chase values (missing: %s)" % str(missing))
	ck(page.find("critical chance") >= 0 and page.find("extra turn") >= 0 and page.find("on every hit") >= 0,
		"...in full words, not the card's abbreviations")
	ck(page.find("Cleave") >= 0 and page.find("Blast") >= 0, "...and the card gear names the CARD, as it is named in your hand")

	print("\n--- no token on the card without its line on the page, across generated gear ---")
	var dt = DT.new()
	var checked := 0
	var bad := 0
	for lvl in [30, 60, 90]:
		for slot in ["weapon", "armor", "helm", "ring", "amulet", "shield", "boots"]:
			for r in range(12):
				var it: Dictionary = {}
				match slot:
					"weapon": it = dt.generate_weapon(lvl)
					"shield": it = dt.generate_shield(lvl)
					"helm": it = dt._generate_item({"item_type": "helm_steel", "rarity": "epic"}, lvl)
					"armor": it = dt._generate_item({"item_type": "armor_chain", "rarity": "epic"}, lvl)
					"boots": it = dt._generate_item({"item_type": "boots_leather", "rarity": "epic"}, lvl)
					"ring": it = dt._generate_item({"item_type": "ring_basic", "rarity": "epic"}, lvl)
					"amulet": it = dt._generate_item({"item_type": "amulet_basic", "rarity": "epic"}, lvl)
				if it.is_empty() or String(it.get("rarity", "common")) in ["common", "uncommon"]:
					continue
				checked += 1
				var preview := _strip(String(c.get_compact_stats_bbcode(it)))
				out.clear()
				c.display_item_details(it, "inventory")
				var inspect := _strip(out.get_parsed_text())
				var inn := _nums(inspect)
				for n in _nums(preview):
					if not (n in inn):
						bad += 1
						print("      %s: preview shows %s, Inspect does not" % [it.get("name", "?"), n])
						break
	ck(checked > 100, "sampled %d generated items" % checked)
	ck(bad == 0, "every number on the card is also on the Inspect page (%d items disagree)" % bad)

	print("\n[INSPECTCARD] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
