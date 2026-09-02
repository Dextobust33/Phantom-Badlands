# Build a test character that MATCHES the reference player the monster model is tuned
# against, so a manual balance playtest measures the model rather than an accident of gear.
#
#   godot --headless --path . --script tools/test_setup/balance_char.gd -- \
#       --acc=acc_6 --user=Testing3 --pass=devtest --name=test003 \
#       --class=Fighter --race=Human --level=100
#
# WHY THIS EXISTS. /setlevel produces a NAKED character. The reference-player monster model
# sizes every monster against a player carrying "average" gear — rarity rolled per slot from
# the game's own RARITY_WEIGHTS, item level ~0.85x character level, plus a tier-appropriate
# companion. A naked level-2500 character fighting monsters sized for a geared one would read
# as "the model is far too hard" when the real fault would be the fixture. This mirrors the
# simulator's make_char exactly (tools/combat_simulator/real_combat_sim.gd), which is the
# build the curve was calibrated to.
extends SceneTree

const SLOTS := ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]
const GEAR_LEVEL_RATIO := 0.85  # solved against real saved characters; see item 5

var drop_tables
var persistence

func _tier_for_level(lvl: int) -> int:
	if lvl <= 5: return 1
	elif lvl <= 15: return 2
	elif lvl <= 30: return 3
	elif lvl <= 50: return 4
	elif lvl <= 100: return 5
	elif lvl <= 500: return 6
	elif lvl <= 2000: return 7
	elif lvl <= 5000: return 8
	return 9

func _reference_ehp(level: int) -> float:
	"""Reference player max HP at `level`, from the same curve the monster model is built on.
	Returns 0.0 when unavailable, in which case gear selection falls back to a single roll."""
	var f = FileAccess.open("res://shared/reference_player_curve.json", FileAccess.READ)
	if f == null:
		return 0.0
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary) or not (parsed.get("anchors", null) is Array):
		return 0.0
	var anchors: Array = parsed["anchors"]
	if anchors.is_empty():
		return 0.0
	var lvl := float(maxi(1, level))
	if lvl <= float(anchors[0].get("level", 1)):
		return float(anchors[0].get("ehp", 0.0))
	if lvl >= float(anchors[anchors.size() - 1].get("level", 1)):
		return float(anchors[anchors.size() - 1].get("ehp", 0.0))
	for i in range(1, anchors.size()):
		var a2: Dictionary = anchors[i - 1]
		var b2: Dictionary = anchors[i]
		var la := float(a2.get("level", 1))
		var lb := float(b2.get("level", 1))
		if lvl <= lb:
			var t: float = (log(lvl) - log(la)) / maxf(0.000001, (log(lb) - log(la)))
			return lerp(float(a2.get("ehp", 0.0)), float(b2.get("ehp", 0.0)), t)
	return float(anchors[anchors.size() - 1].get("ehp", 0.0))

func _roll_rarity(tier: int) -> String:
	var weights: Dictionary = drop_tables.RARITY_WEIGHTS.get(clampi(tier, 1, 9), {})
	if weights.is_empty():
		return "uncommon"
	var total := 0.0
	for k in weights.keys():
		total += float(weights[k])
	var pick := randf() * total
	for k in weights.keys():
		pick -= float(weights[k])
		if pick <= 0.0:
			return String(k)
	return "uncommon"

func _init():
	var args := {}
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		for k in ["acc", "name", "class", "race", "level", "user", "pass"]:
			if s.begins_with("--%s=" % k):
				args[k] = s.substr(k.length() + 3)
	if not args.has("name") or not args.has("acc"):
		print("need --acc= and --name="); quit(1); return

	var level := int(args.get("level", "10"))
	var klass := String(args.get("class", "Fighter"))
	var race := String(args.get("race", "Human"))

	drop_tables = load("res://shared/drop_tables.gd").new()
	root.add_child(drop_tables)
	persistence = load("res://server/persistence_manager.gd").new()
	root.add_child(persistence)
	if persistence.has_method("load_accounts"):
		persistence.load_accounts()

	var CharacterScript = load("res://shared/character.gd")
	var ch = CharacterScript.new()
	ch.initialize(String(args["name"]), klass, race)
	for i in range(level - 1):
		ch.level_up()
	# Spend every point in the class's primary stat — a focused build, as the sim assumes.
	var primary := "strength"
	if klass in ["Wizard", "Sorcerer", "Sage"]:
		primary = "intelligence"
	elif klass in ["Thief", "Ranger", "Ninja"]:
		primary = "dexterity"
	while ch.unspent_stat_points > 0:
		ch.spend_stat_point(primary)

	# Gear: per-slot rarity rolled from the real drop table, item level 0.85x character level,
	# tier-appropriate bases — the same construction the reference curve was calibrated on.
	#
	# CALIBRATED FIXTURE. Rarity is rolled per slot, so a single draw varies a lot: a L50 Wizard
	# came out at 385 HP against a reference of 659, about 40% under, which would have made
	# every monster hit ~1.7x harder relative to its health bar than the model intends and made
	# the whole playtest a measurement of a bad gear roll. The build is now repeated and the set
	# whose total HP lands nearest the reference curve is kept, so the character on screen is
	# the one the monsters were actually tuned against.
	var glevel: int = maxi(1, int(round(float(level) * GEAR_LEVEL_RATIO)))
	var gtier: int = _tier_for_level(glevel)
	var target_hp: float = _reference_ehp(level)
	var best_set := {}
	var best_err := INF
	var equipped := 0
	for attempt in range(40):
		var candidate := {}
		for slot in SLOTS:
			var base_type := ""
			for t in range(gtier, 0, -1):
				for entry in drop_tables.EQUIPMENT_BASES.get(t, []):
					if String(entry.get("item_type", "")).begins_with(slot):
						base_type = String(entry["item_type"])
						break
				if base_type != "":
					break
			if base_type == "":
				continue
			var item = drop_tables._generate_item({"item_type": base_type}, glevel, _roll_rarity(gtier))
			if item is Dictionary and not item.is_empty():
				candidate[slot] = item
		ch.equipped = candidate
		var err: float = absf(float(ch.get_total_max_hp()) - target_hp) if target_hp > 0.0 else 0.0
		if err < best_err:
			best_err = err
			best_set = candidate.duplicate(true)
		if target_hp <= 0.0:
			break   # no curve to aim at — first roll stands
	ch.equipped = best_set
	equipped = best_set.size()

	# A real companion of the tier a player at this level would plausibly have, drawn from
	# COMPANION_DATA, levelled to match the character (companion level is what actually pays).
	# Companion tier uses the SAME level bands as gear and monsters. The simulator's
	# clampi(1 + level/12, 1, 9) saturates at tier 9 by level 96, which handed a level-100
	# character an Entropy companion — the strongest creature in the game. Realistic tiering
	# matters here because the playtest is meant to represent a plausible player.
	var comp_tier: int = _tier_for_level(level)
	var candidates: Array = []
	for mtype in drop_tables.COMPANION_DATA.keys():
		if int((drop_tables.COMPANION_DATA[mtype] as Dictionary).get("tier", 1)) == comp_tier:
			candidates.append(mtype)
	if candidates.is_empty():
		candidates = ["Wolf"]
	var pick: String = String(candidates[randi() % candidates.size()])
	var pdata: Dictionary = drop_tables.COMPANION_DATA.get(pick, {})
	ch.active_companion = {
		"id": "balance_test_comp", "monster_type": pick,
		"name": String(pdata.get("companion_name", pick)),
		"tier": int(pdata.get("tier", 1)), "level": level, "xp": 0,
		"bonuses": (pdata.get("bonuses", {}) as Dictionary).duplicate(),
		"variant": "Normal", "sub_tier": 1, "border_tier": 1,
	}

	ch.current_hp = ch.get_total_max_hp()
	ch.current_mana = ch.get_total_max_mana()
	ch.current_stamina = ch.get_total_max_stamina()
	ch.current_energy = ch.get_total_max_energy()
	# Park somewhere with no safe-zone restriction so /spawnmonster fights can start.
	ch.x = 57
	ch.y = -11

	var acc_id := String(args["acc"])
	persistence.save_character(acc_id, ch)
	# Register the character on the ACCOUNT as well. Saving the file alone is not enough —
	# the server lists characters from the account's character_slots, and PERMADEATH removes
	# the slot entry while the tool happily rewrites the file. The result is a rebuilt
	# character that exists on disk but does not appear at the character-select door, which is
	# exactly what happened the first time a playtest character died. add_character_to_account
	# is idempotent for an existing name.
	persistence.add_character_to_account(acc_id, ch.name)
	var ref_hp := _reference_ehp(level)
	print("built %s: %s %s L%d | HP %d (ref %.0f, %.2fx) | ATK %d | %d/%d gear | companion %s (T%d, L%d)" % [
		String(args["name"]), race, klass, level, ch.get_total_max_hp(), ref_hp,
		float(ch.get_total_max_hp()) / maxf(1.0, ref_hp), ch.get_total_attack(),
		equipped, SLOTS.size(), pick, int(pdata.get("tier", 1)), level])
	quit()
