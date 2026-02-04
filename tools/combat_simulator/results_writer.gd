# results_writer.gd
# Generate JSON and Markdown output from simulation results
extends RefCounted
class_name ResultsWriter

var output_dir: String = "res://docs/simulation_results/"

func _init(custom_output_dir: String = ""):
	if custom_output_dir != "":
		output_dir = custom_output_dir

func write_results(results: Dictionary, config: Dictionary) -> Dictionary:
	"""Write simulation results to JSON and Markdown files
	Returns {json_path: String, markdown_path: String}"""
	var timestamp = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var date_str = Time.get_date_string_from_system()

	# Ensure output directory exists
	var dir = DirAccess.open("res://")
	if not dir.dir_exists(output_dir):
		dir.make_dir_recursive(output_dir)

	# Write JSON
	var json_filename = "%s_results.json" % date_str
	var json_path = output_dir + json_filename
	var json_content = _build_json_output(results, config, timestamp)
	_write_file(json_path, json_content)

	# Write Markdown summary
	var md_filename = "%s_summary.md" % date_str
	var md_path = output_dir + md_filename
	var md_content = _build_markdown_output(results, config, date_str)
	_write_file(md_path, md_content)

	return {"json_path": json_path, "markdown_path": md_path}

func _write_file(path: String, content: String):
	"""Write content to file"""
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(content)
		file.close()
		print("Written: %s" % path)
	else:
		push_error("Failed to write: %s" % path)

func _build_json_output(results: Dictionary, config: Dictionary, timestamp: String) -> String:
	"""Build JSON output string"""
	var output = {
		"timestamp": timestamp,
		"config": config,
		"results": results.get("class_results", {}),
		"monster_analysis": results.get("monster_analysis", {}),
		"lethality_comparison": results.get("lethality_comparison", {}),
		"summary_stats": results.get("summary_stats", {})
	}
	return JSON.stringify(output, "  ")

func _build_markdown_output(results: Dictionary, config: Dictionary, date_str: String) -> String:
	"""Build Markdown summary output"""
	var md = []
	md.append("# Combat Simulation Results - %s" % date_str)
	md.append("")
	md.append("## Configuration")
	md.append("- **Iterations per matchup:** %d" % config.get("iterations", 1000))
	md.append("- **Classes tested:** %s" % ", ".join(config.get("classes", [])))
	md.append("- **Levels tested:** %s" % str(config.get("levels", [])))
	md.append("- **Gear qualities:** %s" % ", ".join(config.get("gear_qualities", [])))
	md.append("- **Monster level offsets:** %s" % str(config.get("monster_level_offsets", [])))
	md.append("")

	# Class Performance Overview
	md.append("## Class Performance Overview")
	md.append("")
	md.append(_build_class_performance_table(results))
	md.append("")

	# Monster Danger Rankings
	md.append("## Monster Danger Rankings")
	md.append("")
	md.append(_build_monster_danger_table(results))
	md.append("")

	# Lethality Analysis
	md.append("## Lethality Analysis")
	md.append("")
	md.append(_build_lethality_analysis(results))
	md.append("")

	# Ability Impact Analysis
	md.append("## Ability Impact Analysis")
	md.append("")
	md.append(_build_ability_analysis(results))
	md.append("")

	# Detailed Results by Class
	md.append("## Detailed Results by Class")
	md.append("")
	md.append(_build_detailed_class_results(results))

	return "\n".join(md)

func _build_class_performance_table(results: Dictionary) -> String:
	"""Build class performance comparison table"""
	var lines = []
	lines.append("| Class | Avg Win Rate | Avg Damage Taken | Avg Rounds | Best Matchup | Worst Matchup |")
	lines.append("|-------|-------------|-----------------|------------|--------------|---------------|")

	var class_results = results.get("class_results", {})
	var summary_stats = results.get("summary_stats", {})

	for char_class in summary_stats.get("class_rankings", []):
		var stats = summary_stats.get("class_stats", {}).get(char_class, {})
		var win_rate = stats.get("avg_win_rate", 0) * 100
		var damage = stats.get("avg_damage_taken", 0)
		var rounds = stats.get("avg_rounds", 0)
		var best = stats.get("best_matchup", "N/A")
		var worst = stats.get("worst_matchup", "N/A")

		lines.append("| %s | %.1f%% | %.0f | %.1f | %s | %s |" % [
			char_class, win_rate, damage, rounds, best, worst
		])

	return "\n".join(lines)

func _build_monster_danger_table(results: Dictionary) -> String:
	"""Build monster danger ranking table"""
	var lines = []
	lines.append("| Monster | Avg Win Rate vs | Empirical Lethality | Formula Lethality | Delta |")
	lines.append("|---------|-----------------|---------------------|-------------------|-------|")

	var monster_analysis = results.get("monster_analysis", {})
	var lethality_comparison = results.get("lethality_comparison", {})

	# Sort by empirical lethality descending
	var sorted_monsters = monster_analysis.keys()
	sorted_monsters.sort_custom(func(a, b):
		return monster_analysis.get(a, {}).get("empirical_lethality", 0) > monster_analysis.get(b, {}).get("empirical_lethality", 0)
	)

	for monster_name in sorted_monsters.slice(0, 20):  # Top 20
		var stats = monster_analysis.get(monster_name, {})
		var lethality_data = lethality_comparison.get(monster_name, {})
		var win_rate = stats.get("avg_player_win_rate", 0) * 100
		var emp_lethality = stats.get("empirical_lethality", 0)
		var formula_lethality = lethality_data.get("formula_lethality", 0)
		var delta = lethality_data.get("delta_percent", 0)
		var delta_str = "%+.0f%%" % delta if delta != 0 else "0%"

		lines.append("| %s | %.1f%% | %.0f | %.0f | %s |" % [
			monster_name, win_rate, emp_lethality, formula_lethality, delta_str
		])

	return "\n".join(lines)

func _build_lethality_analysis(results: Dictionary) -> String:
	"""Build lethality analysis section"""
	var lines = []
	var lethality_comparison = results.get("lethality_comparison", {})

	# Find monsters with biggest formula discrepancy
	var discrepancies = []
	for monster_name in lethality_comparison:
		var data = lethality_comparison[monster_name]
		var delta = abs(data.get("delta_percent", 0))
		if delta > 15:  # Only show significant discrepancies
			discrepancies.append({"name": monster_name, "data": data, "delta": delta})

	discrepancies.sort_custom(func(a, b): return a.delta > b.delta)

	if discrepancies.is_empty():
		lines.append("All monsters have lethality within expected ranges (delta < 15%).")
	else:
		lines.append("### Monsters with Significant Lethality Discrepancies")
		lines.append("")
		lines.append("These monsters have empirical lethality significantly different from the formula:")
		lines.append("")

		for entry in discrepancies.slice(0, 10):
			var name = entry.name
			var data = entry.data
			var direction = "more dangerous" if data.delta_percent > 0 else "less dangerous"
			lines.append("- **%s**: Empirical %.0f vs Formula %.0f (%+.0f%% - %s than expected)" % [
				name,
				data.get("empirical_lethality", 0),
				data.get("formula_lethality", 0),
				data.get("delta_percent", 0),
				direction
			])

	return "\n".join(lines)

func _build_ability_analysis(results: Dictionary) -> String:
	"""Build ability impact analysis section"""
	var lines = []
	var ability_stats = results.get("ability_stats", {})

	if ability_stats.is_empty():
		lines.append("No ability data collected.")
		return "\n".join(lines)

	lines.append("### Ability Trigger Rates")
	lines.append("")
	lines.append("| Ability | Trigger Rate | Avg Impact |")
	lines.append("|---------|-------------|------------|")

	# Sort by impact
	var sorted_abilities = ability_stats.keys()
	sorted_abilities.sort_custom(func(a, b):
		return ability_stats.get(a, {}).get("avg_impact", 0) > ability_stats.get(b, {}).get("avg_impact", 0)
	)

	for ability in sorted_abilities:
		var stats = ability_stats[ability]
		var trigger_rate = stats.get("trigger_rate", 0) * 100
		var impact = stats.get("avg_impact", 0)
		var impact_str = "%+.1f%% win rate" % impact

		lines.append("| %s | %.1f%% | %s |" % [ability.capitalize().replace("_", " "), trigger_rate, impact_str])

	return "\n".join(lines)

func _build_detailed_class_results(results: Dictionary) -> String:
	"""Build detailed results section for each class"""
	var lines = []
	var class_results = results.get("class_results", {})

	for char_class in class_results:
		lines.append("### %s" % char_class)
		lines.append("")

		var level_data = class_results[char_class]
		for level_str in level_data:
			var gear_data = level_data[level_str]
			lines.append("**Level %s:**" % level_str)

			for gear_quality in gear_data:
				var matchups = gear_data[gear_quality]
				var total_wins = 0
				var total_fights = 0
				var total_damage = 0

				for matchup_key in matchups:
					var matchup = matchups[matchup_key]
					total_wins += matchup.get("wins", 0)
					total_fights += matchup.get("total", 0)
					total_damage += matchup.get("total_damage_taken", 0)

				if total_fights > 0:
					var win_rate = float(total_wins) / total_fights * 100
					var avg_damage = total_damage / total_fights
					lines.append("- %s gear: %.1f%% win rate, %.0f avg damage taken" % [gear_quality.capitalize(), win_rate, avg_damage])

			lines.append("")

	return "\n".join(lines)

func calculate_empirical_lethality(win_rate: float, avg_damage_ratio: float) -> float:
	"""Calculate empirical lethality from simulation data
	win_rate 90% = ~110, 50% = ~200, 10% = ~1000"""
	# Base lethality inversely proportional to win rate
	var base = 100.0 / max(0.01, win_rate)
	# Factor in damage taken as % of max HP
	var damage_factor = 1.0 + avg_damage_ratio
	return base * damage_factor * 100

func generate_summary_stats(results: Dictionary) -> Dictionary:
	"""Generate summary statistics from raw results"""
	var class_results = results.get("class_results", {})
	var class_stats = {}
	var class_rankings = []

	for char_class in class_results:
		var total_wins = 0
		var total_fights = 0
		var total_damage = 0
		var total_rounds = 0
		var best_matchup = ""
		var best_win_rate = 0.0
		var worst_matchup = ""
		var worst_win_rate = 1.0

		var level_data = class_results[char_class]
		for level_str in level_data:
			var gear_data = level_data[level_str]
			for gear_quality in gear_data:
				var matchups = gear_data[gear_quality]
				for matchup_key in matchups:
					var matchup = matchups[matchup_key]
					total_wins += matchup.get("wins", 0)
					total_fights += matchup.get("total", 0)
					total_damage += matchup.get("total_damage_taken", 0)
					total_rounds += matchup.get("total_rounds", 0)

					var win_rate = float(matchup.get("wins", 0)) / max(1, matchup.get("total", 1))
					if win_rate > best_win_rate:
						best_win_rate = win_rate
						best_matchup = matchup_key
					if win_rate < worst_win_rate:
						worst_win_rate = win_rate
						worst_matchup = matchup_key

		if total_fights > 0:
			class_stats[char_class] = {
				"avg_win_rate": float(total_wins) / total_fights,
				"avg_damage_taken": float(total_damage) / total_fights,
				"avg_rounds": float(total_rounds) / total_fights,
				"best_matchup": best_matchup,
				"worst_matchup": worst_matchup,
				"total_fights": total_fights
			}
			class_rankings.append(char_class)

	# Sort by win rate
	class_rankings.sort_custom(func(a, b):
		return class_stats.get(a, {}).get("avg_win_rate", 0) > class_stats.get(b, {}).get("avg_win_rate", 0)
	)

	return {
		"class_stats": class_stats,
		"class_rankings": class_rankings
	}

func generate_monster_analysis(results: Dictionary) -> Dictionary:
	"""Analyze monster performance across all matchups"""
	var class_results = results.get("class_results", {})
	var monster_data = {}

	for char_class in class_results:
		var level_data = class_results[char_class]
		for level_str in level_data:
			var gear_data = level_data[level_str]
			for gear_quality in gear_data:
				var matchups = gear_data[gear_quality]
				for matchup_key in matchups:
					var matchup = matchups[matchup_key]
					var monster_name = matchup.get("monster_name", matchup_key.split("_")[1] if "_" in matchup_key else matchup_key)

					if not monster_data.has(monster_name):
						monster_data[monster_name] = {
							"total_fights": 0,
							"player_wins": 0,
							"total_damage_to_player": 0,
							"total_player_max_hp": 0
						}

					monster_data[monster_name].total_fights += matchup.get("total", 0)
					monster_data[monster_name].player_wins += matchup.get("wins", 0)
					monster_data[monster_name].total_damage_to_player += matchup.get("total_damage_taken", 0)
					monster_data[monster_name].total_player_max_hp += matchup.get("total_player_max_hp", 0)

	# Calculate derived stats
	var analysis = {}
	for monster_name in monster_data:
		var data = monster_data[monster_name]
		var fights = data.total_fights
		if fights > 0:
			var win_rate = float(data.player_wins) / fights
			var avg_damage_ratio = 0.0
			if data.total_player_max_hp > 0:
				avg_damage_ratio = float(data.total_damage_to_player) / data.total_player_max_hp

			analysis[monster_name] = {
				"avg_player_win_rate": win_rate,
				"avg_damage_ratio": avg_damage_ratio,
				"empirical_lethality": calculate_empirical_lethality(win_rate, avg_damage_ratio),
				"total_fights": fights
			}

	return analysis
