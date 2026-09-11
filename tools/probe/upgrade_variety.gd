extends SceneTree
## HOW DIFFERENT ARE THEY, REALLY?
##
## Owner 2026-09-11: *"Many of them feel like a bit of the same and many of them are fairly
## situational. Situational can be good but only if there is a clear answer to how to use them
## properly and make it easily apparent in combat when it's worth using. If not it all becomes
## micro-management and feels like dead options."*
##
## First pass of this audit was WRONG twice and is worth recording: it counted probabilistic
## upgrades (a 12% crit chance) as "situational", which they are not - there is no decision in
## variance - and it reported enemy-stun as invisible because it searched for the wrong symbol,
## when the monster carries hoverable status chips.
const CU := preload("res://shared/card_upgrades.gd")

# What NUMBER does it move? Answers "how same-y are they".
const CHANNEL := {
	"damage":   ["power", "rider", "executioner", "opener", "overdraw", "reckless", "slow_burn",
	             "wild_swing", "brittle", "all_in", "greedy", "sacrificial", "bloodprice"],
	"crit":     ["keen", "sure_strike"],
	"heal":     ["leeching", "mending", "vindication", "renewing", "slow_mend"],
	"shield":   ["warding", "bulwark", "entrenched", "demoralising", "reveal_ward", "fragile_ward"],
	"resource": ["efficiency", "second_wind", "relentless", "refund", "opening_act", "hair_trigger",
	             "gamblers_cut", "costly_vigil", "second_look"],
	"engine":   ["momentum_feed", "kindling", "desperate", "harrying", "reveal_engine", "rally_point"],
	"buff_str": ["duration", "preload", "shared", "concentrated", "reckless_guard", "slow_cast"],
	"control":  ["unsettling", "disorienting", "pinning", "provoking", "unstable_hex"],
	"turn":     ["swift"],
	"mitigate": ["steadfast", "last_stand"],
	"chip":     ["reveal_spark"],
}

# When does it fire? THREE kinds, and only the third is what the owner means by situational.
const ALWAYS := ["power", "efficiency", "duration", "leeching", "momentum_feed", "preload",
	"shared", "warding", "mending", "second_wind", "steadfast", "entrenched", "renewing",
	"overdraw", "reckless", "slow_burn", "concentrated", "reckless_guard", "bloodprice",
	"brittle", "greedy", "fragile_ward", "slow_cast", "costly_vigil", "sacrificial",
	"unsettling", "provoking"]
const CHANCE := ["rider", "keen", "swift", "pinning", "hair_trigger", "wild_swing",
	"unstable_hex", "gamblers_cut", "disorienting"]
## conditional id -> [what it keys off, is that state ON SCREEN at decision time]
const CONDITIONAL := {
	"executioner":   ["foe below 30% HP",      true],
	"rally_point":   ["foe below 50% HP",      true],
	"last_stand":    ["you below 25%",         true],
	"sure_strike":   ["first use this fight",  false],
	"second_look":   ["you DON'T play it",     false],
	"slow_mend":     ["you DON'T play it",     false],
	"refund":        ["this cast kills",       true],
	"vindication":   ["this cast kills",       true],
	"desperate":     ["you below a threshold", true],
	"bulwark":       ["you below half",        true],
	"kindling":      ["resource bar FULL",     true],
	"all_in":        ["resource bar EMPTY",    true],
	"harrying":      ["foe stunned",           true],
	"demoralising":  ["foe stunned/rattled",   true],
	"opener":        ["first use this fight",  false],
	"opening_act":   ["first use this fight",  false],
	"relentless":    ["every 3rd cast",        false],
	"reveal_engine": ["you DON'T play it",     false],
	"reveal_ward":   ["you DON'T play it",     false],
	"reveal_spark":  ["you DON'T play it",     false],
}

func _init() -> void:
	var ids := {}
	for u in CU.UPGRADES:
		ids[String(u.get("id", ""))] = String(u.get("name", ""))

	print("=== 1. HOW DIFFERENT ARE THEY? (what number each one moves) ===")
	var covered := {}
	var rows: Array = []
	for ch in CHANNEL:
		var n: int = (CHANNEL[ch] as Array).size()
		for id in CHANNEL[ch]:
			covered[id] = true
		rows.append([n, ch])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	for r in rows:
		var bar := "#".repeat(int(r[0]))
		print("  %-9s %2d  %s" % [r[1], r[0], bar])
	var missed: Array = []
	for id in ids:
		if not covered.has(id):
			missed.append(id)
	print("  (unclassified: %s)" % ("none" if missed.is_empty() else ", ".join(missed)))
	print("")
	print("  DAMAGE alone is %d of %d. Thirteen ways to say 'the number goes up'." % [
		(CHANNEL["damage"] as Array).size(), CU.UPGRADES.size()])
	print("")

	print("=== 2. WHEN DOES IT FIRE? ===")
	print("  always-on     %2d  %s" % [ALWAYS.size(), "#".repeat(ALWAYS.size())])
	print("  pure variance %2d  %s   <- no decision to make, just a dice roll" % [
		CHANCE.size(), "#".repeat(CHANCE.size())])
	print("  CONDITIONAL   %2d  %s   <- the only ones that ask you to time anything" % [
		CONDITIONAL.size(), "#".repeat(CONDITIONAL.size())])
	var total: int = ALWAYS.size() + CHANCE.size() + CONDITIONAL.size()
	print("  (%d of %d accounted for)" % [total, CU.UPGRADES.size()])
	print("")

	print("=== 3. CAN YOU SEE THE TRIGGER AT DECISION TIME? ===")
	var blind: Array = []
	for id in CONDITIONAL:
		var e: Array = CONDITIONAL[id]
		print("  %-9s %-14s keys off %-24s" % ["visible" if e[1] else "BLIND",
			String(ids.get(id, id)), String(e[0])])
		if not bool(e[1]):
			blind.append(String(ids.get(id, id)))
	print("")
	print("  %d of %d conditional triggers ARE on screen (HP bars, resource bar, status chips)."
		% [CONDITIONAL.size() - blind.size(), CONDITIONAL.size()])
	print("  Genuinely invisible: %s" % ", ".join(blind))
	print("")

	print("=== 4. THE ACTUAL GAP ===")
	var cli := FileAccess.get_file_as_string("res://client/client.gd")
	var panel := FileAccess.get_file_as_string("res://client/combat_scene_panel.gd")
	var _tagged := 0
	for u in CU.UPGRADES:
		if CU.trigger_of(u) != CU.TRIGGER_NONE:
			_tagged += 1
	print("  upgrade table carries a machine-readable trigger : %s (%d of %d tagged)" % [
		("yes" if _tagged > 0 else "NO"), _tagged, CU.UPGRADES.size()])
	print("  a card in hand shows WHICH upgrades it carries    : %s" % (
		"yes" if panel.contains("milestone_picks") or panel.contains("card_upgrades") else "NO"))
	# Checked by the real symbol, not a name I guessed the implementation would use. The first
	# version searched for "upgrade_live", which was never the name, so it reported NO against a
	# feature that shipped - an audit lying about its own project.
	print("  ...or that one of them is LIVE this turn          : %s" % (
		"yes" if panel.contains("CardUpgrades.trigger_live(") else "NO"))
	
	print("")
	print("=== 5. THE CLASSIFICATION ABOVE MUST NOT GO STALE ===")
	# An audit that silently under-reports when the pool grows is worse than none: it would
	# keep saying "13 damage upgrades" while someone adds five more. Both tables are checked
	# against the real pool, so a new upgrade fails this until it is classified.
	var fails := 0
	var unclassified_channel: Array = []
	var unclassified_timing: Array = []
	for id in ids:
		if not covered.has(id):
			unclassified_channel.append(id)
		if not (id in ALWAYS) and not (id in CHANCE) and not CONDITIONAL.has(id):
			unclassified_timing.append(id)
	if unclassified_channel.is_empty():
		print("  PASS  every upgrade is assigned a channel")
	else:
		fails += 1
		print("  FAIL  unclassified channel: %s" % ", ".join(unclassified_channel))
	if unclassified_timing.is_empty():
		print("  PASS  every upgrade is assigned a firing mode")
	else:
		fails += 1
		print("  FAIL  unclassified timing: %s" % ", ".join(unclassified_timing))
	quit(1 if fails > 0 else 0)
