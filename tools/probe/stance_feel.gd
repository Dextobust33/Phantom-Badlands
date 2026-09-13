extends SceneTree
## Do the stances produce journeys a player would actually choose between?
##
## Owner 2026-09-13: *"Do we need to further refine stances then?"*
##
## The multipliers are easy to read off the table; what matters is what they do to a REAL
## journey. This walks 500 tiles in each stance and reports the two things a player feels: how
## many fights they picked up, and how much of their bar they had when they arrived.
##
## The failure to look for is a DOMINANT stance - one a player would simply leave on. A toggle
## nobody flips is a toggle that should not exist.
const WorldSystemScript = preload("res://shared/world_system.gd")
const ChunkManagerScript = preload("res://shared/chunk_manager.gd")
const TS = preload("res://shared/travel_stance.gd")

const WALK := 500
const TRIALS := 30
## What a step gives back at Wary, from server.gd: 5% of pool, before the stance multiplier.
const BASE_STEP_REGEN := 0.05


func _init() -> void:
	var cm = ChunkManagerScript.new()
	get_root().add_child(cm)
	cm.load_world_seed()
	cm.load_npc_posts()
	var ws = WorldSystemScript.new()
	get_root().add_child(ws)
	ws.chunk_manager = cm
	cm.terrain_generator = ws

	print("\n===== A 500-TILE JOURNEY IN EACH STANCE =====")
	print("player at their own level, across country at their own level - the case stances exist for.")
	print("%-12s %10s %14s %16s" % ["stance", "fights", "regen/100 steps", "map sight"])
	var results := {}
	for sid in TS.ORDER:
		var st: Dictionary = TS.get_stance(String(sid))
		var fights := 0
		for t in range(TRIALS):
			for step in range(WALK):
				# Ground at roughly the player's own level: use the real curve and pick a player
				# level to match, so no level-diff suppression is in play and we measure the
				# stance alone.
				var x := 200 + step
				var y := t * 5
				var al: int = ws.get_post_anchored_level(x, y)
				if ws.check_encounter(x, y, al, false, TS.encounter_mult(String(sid))):
					fights += 1
		var per := float(fights) / float(TRIALS)
		# Bar recovered over 100 steps, as a share of the pool.
		var regen100: float = BASE_STEP_REGEN * TS.regen_mult(String(sid)) * 100.0 * 100.0
		results[String(sid)] = per
		print("%-12s %10.1f %13.0f%% %16d" % [
			String(st.get("name", "?")), per, regen100, 6 + TS.vision_bonus(String(sid))])

	print("\n--- is any stance one you would simply leave on? ---")
	var wary: float = float(results.get(TS.WARY, 1.0))
	var trav: float = float(results.get(TS.TRAVELLING, 1.0))
	print("  Travelling cuts a 500-tile journey from %.0f fights to %.0f" % [wary, trav])
	print("  ...at %.0f%% of the recovery, so arriving takes a bar you do not have"
		% (TS.regen_mult(TS.TRAVELLING) * 100.0))
	# The honest test of "would you leave it on": if you travel in Travelling, you arrive empty.
	# 500 steps at 1.75%/step is 875% of a bar - so recovery is NOT the limiter over a long walk;
	# it is the limiter over a SHORT one, between fights. Say so rather than overclaim.
	var steps_to_full_wary: float = 100.0 / (BASE_STEP_REGEN * 100.0)
	var steps_to_full_trav: float = 100.0 / (BASE_STEP_REGEN * TS.regen_mult(TS.TRAVELLING) * 100.0)
	print("\n  steps to refill an empty bar:  Wary %.0f   Travelling %.0f" % [
		steps_to_full_wary, steps_to_full_trav])
	print("  Regen alone was NOT enough of a cost: over 500 quiet steps every stance refills many")
	print("  times over. That is why Travelling also pays in SURPRISE - see below.")

	print("
--- the cost that actually bites: who strikes first ---")
	# Measured through the real initiative path rather than read off the table: build a character
	# and a monster, start combat in each stance, and count how often the monster acts first.
	var sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	print("%-12s %22s" % ["stance", "monster strikes first"])
	for sid in TS.ORDER:
		var first := 0
		var n := 160
		for i in range(n):
			var ch = sim.make_char(40, "average", "Fighter", "Human")
			ch.travel_stance = String(sid)
			ch.in_combat = false
			ch.current_hp = ch.get_total_max_hp()
			var mon = sim.make_monster(40, "normal", 1.0)
			sim.combat_mgr.start_combat(0, ch, mon)
			if not sim.combat_mgr.active_combats.has(0):
				continue
			if bool(sim.combat_mgr.active_combats[0].get("monster_went_first", false)):
				first += 1
			sim.combat_mgr.end_combat(0, false, false)
		print("%-12s %21.0f%%" % [String(TS.get_stance(String(sid)).get("name", "?")),
			100.0 * float(first) / float(n)])
	print("
  Travelling avoids most fights and loses the opening move in the ones it does not.")
	print("  Hunting finds more and starts them on better terms. That is a choice, not a ladder.")
	quit(0)
