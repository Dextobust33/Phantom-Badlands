# "These numbers look pretty low when presented in this way. Are they actually or do they just
# look that way?" (owner 2026-09-03). So measure what a variant multiplier is WORTH.
extends SceneTree
const CharacterScript = preload("res://shared/character.gd")

func _init():
	var ch = CharacterScript.new()
	ch.initialize("probe", "Fighter", "Human")
	for _i in range(29): ch.level_up()
	while ch.unspent_stat_points > 0: ch.spend_stat_point("strength")

	# A representative mid companion: the bonuses are PERCENTAGES of the player's stats.
	var base_bonuses := {"attack": 8, "defense": 5, "hp_bonus": 6, "speed": 4}
	print("\n=== WHAT A VARIANT MULTIPLIER IS ACTUALLY WORTH ===")
	print("Companion bonuses are PERCENT bonuses to the player. Base companion: %s" % str(base_bonuses))
	print("Player L%d: %d HP, %d attack, %d defense\n" % [
		ch.level, ch.get_total_max_hp(), ch.get_total_attack(), ch.get_total_defense()])
	print("%-22s %8s %10s %10s %10s" % ["variant", "mult", "+ATK%", "+HP%", "player HP gained"])
	for row in [["(none / 90% of them)", 1.00], ["Shiny tier", 1.10], ["Spectral tier", 1.25], ["Prismatic tier", 1.50]]:
		var m := float(row[1])
		var atk_pct := float(base_bonuses["attack"]) * m
		var hp_pct := float(base_bonuses["hp_bonus"]) * m
		var hp_gain := int(float(ch.get_total_max_hp()) * hp_pct / 100.0)
		print("%-22s %7.2fx %9.1f%% %9.1f%% %14d" % [String(row[0]), m, atk_pct, hp_pct, hp_gain])

	var base_hp := int(float(ch.get_total_max_hp()) * float(base_bonuses["hp_bonus"]) / 100.0)
	var best_hp := int(float(ch.get_total_max_hp()) * float(base_bonuses["hp_bonus"]) * 1.5 / 100.0)
	print("\n  Rarest variant vs none: %d extra HP (%d -> %d), and +4%% attack." % [
		best_hp - base_hp, base_hp, best_hp])
	print("  As a share of the player's own health bar: %.1f%% -> %.1f%%." % [
		100.0 * float(base_hp) / float(ch.get_total_max_hp()),
		100.0 * float(best_hp) / float(ch.get_total_max_hp())])
	print("\n  VERDICT: the multiplier scales a bonus that is itself small, so 1.50x of a")
	print("  6%% HP bonus is 9%% - a 3 percentage point swing for the rarest find in the game.")
	quit()
