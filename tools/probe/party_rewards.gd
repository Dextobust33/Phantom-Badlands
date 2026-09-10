extends SceneTree
## Does every surviving party member get a share of the victory?
##
## Backlog Phase 4: "verify every member really receives combat rewards (especially equipment)",
## alongside the unreproduced "party play isn't working properly" (owner 2026-08-26).
##
## WHAT THIS CAN AND CANNOT SEE, because the first version of it got this wrong and nearly
## reported a catastrophic bug that does not exist:
##
##   * The SIMULTANEOUS party path (`resolve_party_round`) resolves the round in the combat
##     manager, and the REWARDS are handed out afterwards by the server in
##     `_end_party_combat_all` - which needs `characters`, `peers` and `persistence`, none of
##     which exist in this harness. So the payout itself is not reachable from here.
##   * The first version asserted on `member_rewards` in the round result and "found" that every
##     living member was missing from it. That field belongs to the OLD sequential path; the
##     simultaneous one never populates it and does not read it. The audit was measuring a field
##     nothing uses. (The function that DID read it turned out to have no callers at all, and has
##     since been deleted - 182 lines of plausible-looking reward logic that inferred death from
##     an empty dictionary.)
##
## So this checks the half that IS reachable: that a party round resolves to a victory with every
## member still alive and unfled, which is the precondition the server's reward loop tests. The
## payout itself needs a live server and is noted in the backlog as such.
func _init() -> void:
	var sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	get_root().add_child(sim)
	await process_frame
	var chars := {}
	for i in range(2):
		var ch = sim.make_char(20, "average", "Fighter" if i == 0 else "Wizard", "Human")
		ch.initialize_deck_collection_if_needed()
		ch.name = "Member%d" % i
		chars[i] = ch
	var monster = sim.make_monster(20, "normal", 1.0)
	sim.combat_mgr.start_party_combat_simul([0, 1], chars, monster)
	if not sim.combat_mgr.active_party_combats.has(0):
		print("[PARTYREW] could not start a party combat"); quit(1); return
	var pc = sim.combat_mgr.active_party_combats[0]
	# On its last legs AFTER the combat is built - starting it at 1 HP does nothing, because
	# start_party_combat_simul re-initialises the monster from its max.
	pc.monster["current_hp"] = 1
	sim.combat_mgr.submit_party_action(0, 0, {"kind": "attack"})
	sim.combat_mgr.submit_party_action(0, 1, {"kind": "attack"})
	var res: Dictionary = sim.combat_mgr.resolve_party_round(0)
	var bad := 0
	if not bool(res.get("victory", false)):
		print("[PARTYREW] round did not resolve to victory"); bad += 1
	# Every member must be eligible: the server skips `dead` / `fled` / missing, so anyone
	# wrongly flagged here would silently receive nothing.
	for i in range(2):
		var st: Dictionary = pc.member_states.get(i, {})
		var eligible: bool = not bool(st.get("dead", false)) and not bool(st.get("fled", false))
		print("[PARTYREW] member %d: dead=%s fled=%s -> eligible for rewards=%s"
			% [i, str(st.get("dead", false)), str(st.get("fled", false)), str(eligible)])
		if not eligible:
			bad += 1
	print("[PARTYREW] %s" % ("PASS - victory, and both members eligible" if bad == 0
		else "FAIL - %d problem(s)" % bad))
	quit(0 if bad == 0 else 1)
