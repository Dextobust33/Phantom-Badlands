# Throwaway verification harness for the Empowered modifier roll (v0.9.651).
# Run: godot --headless --path . --script res://tools/test_empowered_gen.gd
extends SceneTree

func _init():
	var db = load("res://shared/monster_database.gd").new()
	var levels = [3, 10, 25, 50, 120]
	var n = 4000
	for lvl in levels:
		var empowered = 0
		var legacy_variant = 0
		var counts = {1: 0, 2: 0, 3: 0}
		var mod_tally = {}
		var bad = 0
		var brood_no_flock = 0
		var gilded_seen = 0
		for i in range(n):
			var m = db.generate_monster(lvl, lvl)
			var mods: Array = m.get("empowered_mods", [])
			if m.get("is_rare_variant", false):
				legacy_variant += 1
			if mods.size() > 0:
				empowered += 1
				counts[mods.size()] = counts.get(mods.size(), 0) + 1
				for mid in mods:
					mod_tally[mid] = mod_tally.get(mid, 0) + 1
				# Field sanity
				if not m.get("is_empowered", false):
					bad += 1
				if String(m.get("name_color", "")) == "":
					bad += 1
				# Prefix sanity: every mod's prefix must be in the name
				for mid in mods:
					var prefix = String(db.EMPOWERED_MODIFIERS[mid].get("prefix", ""))
					if not String(m.get("name", "")).contains(prefix):
						bad += 1
				if "broodcalling" in mods and int(m.get("flock_chance", 0)) != 100:
					brood_no_flock += 1
				if "gilded" in mods:
					gilded_seen += 1
				if mods.size() == 1 and i < 3:
					print("    sample: %s (drop %d%%, xp %d, color %s)" % [m.name, m.drop_chance, m.experience_reward, m.name_color])
			else:
				if m.get("is_empowered", false) or String(m.get("name_color", "")) != "":
					bad += 1
		print("Lv%d: empowered %.1f%% (expect ~15%% of non-variant, 0%% below Lv5) | legacy variants %.1f%% | counts 1/2/3 = %d/%d/%d | bad-fields %d | brood-without-flock %d | gilded %d" % [
			lvl, 100.0 * empowered / n, 100.0 * legacy_variant / n,
			counts.get(1, 0), counts.get(2, 0), counts.get(3, 0), bad, brood_no_flock, gilded_seen])
		var tally_strs = []
		for k in mod_tally:
			tally_strs.append("%s:%d" % [k, mod_tally[k]])
		print("    mods: " + ", ".join(tally_strs))
	quit()
