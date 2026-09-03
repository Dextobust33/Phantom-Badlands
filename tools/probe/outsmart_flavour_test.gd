extends SceneTree
const CombatManager = preload("res://shared/combat_manager.gd")
func _init():
	seed(7)
	print("\n=== OUTSMART FLAVOUR — 6 attempts, each with both outcomes ===")
	for i in range(6):
		var a: String = CombatManager.outsmart_attempt_line()
		print("  %s... %s." % [a, CombatManager.outsmart_outcome_line(true)])
		print("  %s... %s." % [a, CombatManager.outsmart_outcome_line(false)])
		print("")
	print("attempt lines: %d   win lines: %d   fail lines: %d" % [
		CombatManager.OUTSMART_ATTEMPTS.size(), CombatManager.OUTSMART_WINS.size(),
		CombatManager.OUTSMART_FAILS.size()])
	quit()
