extends RefCounted
## Path SPECS for the simulator (docs/design/paths_revamp.md section 8.3, instrument 1).
##
## A spec models the PLAYER, not the maximiser: an ordered shopping list per class that a reasonable player would follow with
## the points their level has earned. Never a solver-picked optimum - a solver would measure the ceiling of the tree, and
## the game has to be balanced for the people who actually play it.
##
## Three kinds per class:
##   typical  - the default: engine perks and the card rules first, then offence and defence about evenly
##   offense  - leans into the offensive branches
##   defense  - leans into the defensive branches
## ("none" / "" spends nothing, which is what every audit did before paths were modelled. Keeping it the default is the control:
## with no `--path=` flag every number is byte-identical to the old ones.)
##
## Branch keystones (tier 5) are never bought: they trade power for a downside, and a typical player's choice there is exactly
## the kind of thing a spec should not decide for them. Each class keystone IS bought once its 8-point gate is met.
const PD = preload("res://shared/path_database.gd")
const PP = preload("res://shared/path_points.gd")

## The 12 feat-rungs-per-life that real play earns are not measured yet (section 8.3 item 8 builds the ledger). Until it exists the
## sim ASSUMES the section 3.3 estimate: ~70 feat points by L10000, accruing with the log of the level (fast early, slow late).
## It is one constant so the ledger can replace it in one place.
const FEAT_POINTS_AT_MAX := 70.0
const MAX_LEVEL := 10000.0

const BRANCHES := {
	"warrior": {"off": ["onslaught", "reaver"], "def": ["bulwark", "vanguard"], "util": ["warlord", "provisioner"]},
	"mage": {"off": ["destruction", "arcana"], "def": ["aegis", "warding"], "util": ["wellspring", "lorekeeper"]},
	"trickster": {"off": ["lethality", "cutthroat"], "def": ["shadow", "evasion"], "util": ["fortune", "gambit"]},
}

const KINDS := ["typical", "offense", "defense"]


static func feat_points(level: int) -> int:
	return int(round(FEAT_POINTS_AT_MAX * log(1.0 + float(level)) / log(1.0 + MAX_LEVEL)))


static func points_for(level: int) -> int:
	return PP.from_level(level) + feat_points(level)


static func _branch_ids(archetype: String, branch_id: String) -> Array:
	"""The first four node ids of a branch (the keystone, tier 5, is left out on purpose)."""
	var ids: Array = PD.branch_node_ids(archetype, branch_id)
	return ids.slice(0, 4)


static func plan(klass: String, kind: String) -> Array:
	"""Ordered [node_id, target_rank] steps."""
	var arch: String = PD.class_archetype(klass)
	if arch == "" or not (kind in KINDS):
		return []
	var b: Dictionary = BRANCHES[arch]
	var sig: Array = []
	for n in PD.signature_nodes(klass):
		sig.append(String(n.get("id", "")))
	var sig_engine: Array = sig.slice(0, 3)
	var sig_rules: Array = sig.slice(3, 6)
	var ck: String = String(PD.get_archetype_tree(arch).get("class_keystones", {}).get(klass, {}).get("id", ""))
	var primary: Array = []
	var secondary: Array = []
	match kind:
		"offense":
			primary = b["off"]
			secondary = b["def"]
		"defense":
			primary = b["def"]
			secondary = b["off"]
		_:
			# typical alternates, offence first
			primary = [b["off"][0], b["def"][0], b["off"][1], b["def"][1]]
			secondary = b["util"]
	var steps: Array = []
	var first_rank: int = 2 if kind == "typical" else 3
	for id in sig_engine:
		steps.append([id, 2])
	for id in sig_rules:
		steps.append([id, 1])
	if ck != "":
		steps.append([ck, 1])
	# The Ascendant tier, as soon as the level opens it (apply() enforces the level gate).
	for an in PD.ascendant_nodes(klass):
		steps.append([String(an.get("id", "")), 1])
	for br in primary:
		for id in _branch_ids(arch, String(br)):
			steps.append([id, first_rank])
	for br in secondary:
		for id in _branch_ids(arch, String(br)):
			steps.append([id, 2])
	# second pass: deepen what the player already likes, engine perks first
	for id in sig_engine:
		steps.append([id, 5])
	for br in primary:
		for id in _branch_ids(arch, String(br)):
			steps.append([id, 5])
	for br in secondary:
		for id in _branch_ids(arch, String(br)):
			steps.append([id, 5])
	return steps


static func spent_points(ch) -> int:
	var total := 0
	for id in ch.path_ranks:
		total += PP.total_cost(int(ch.path_ranks[id]))
	return total


static func apply(ch, klass: String, kind: String, level: int) -> int:
	"""Spend this level's points on the spec. Returns points spent. Respects the game's own rules: a node needs the one above it,
	a rank costs its number, the class keystone needs 8 points spent."""
	if kind == "" or kind == "none":
		return 0
	var budget: int = points_for(level)
	var spent := 0
	for step in plan(klass, kind):
		var id: String = String(step[0])
		var target: int = int(step[1])
		var node: Dictionary = PD.find_node(id)
		if node.is_empty():
			continue
		var cap: int = mini(target, PD.max_rank(node))
		var pre: String = PD.get_prereq_id(id)
		if pre != "" and int(ch.path_ranks.get(pre, 0)) < 1:
			continue
		if bool(node.get("ascendant", false)):
			if not PD.ascendant_unlocked(node, level):
				continue
		elif String(node.get("class_lock", "")) != "" and not bool(node.get("signature", false)) and spent < PD.CLASS_KEYSTONE_SPEND_REQ:
			continue
		var r: int = int(ch.path_ranks.get(id, 0))
		while r < cap and spent + PP.rank_cost(r + 1) <= budget:
			spent += PP.rank_cost(r + 1)
			r += 1
			ch.set_path_rank(id, r)
	return spent


# ---------------------------------------------------------------------------------------------------------------------
# AUDITS (registered in real_combat_sim.gd). Each ends with its own PASS / FAIL line.
# ---------------------------------------------------------------------------------------------------------------------
const ALL := ["Fighter", "Barbarian", "Paladin", "Wizard", "Sorcerer", "Sage", "Grifter", "Ranger", "Ninja"]
const SENTINEL_LEVELS := [1, 5, 10, 20, 30, 50, 100, 200, 500, 1000, 2000, 5000, 10000]


static func capacity(klass: String) -> int:
	"""Every point a character of this class could ever spend: all six branches, its Signature branch, its class keystone."""
	var arch: String = PD.class_archetype(klass)
	var total := 0
	for b in PD.get_archetype_tree(arch).get("branches", []):
		for n in b.get("nodes", []):
			total += PP.total_cost(PD.max_rank(PD.find_node(String(n.get("id", "")))))
	for n in PD.signature_nodes(klass):
		total += PP.total_cost(PD.max_rank(PD.find_node(String(n.get("id", "")))))
	var ck: String = String(PD.get_archetype_tree(arch).get("class_keystones", {}).get(klass, {}).get("id", ""))
	if ck != "":
		total += 1
	total += PD.ascendant_nodes(klass).size()   # three single-rank nodes, one point each
	return total


static func audit_curve(sim) -> void:
	"""`pathcurve` (section 8.3 item 4): the point economy. Points earned by level versus what the tree can absorb. Two promises:
	the tree is never full before L10000 (there is always something to choose), and at L50 a character has enough to have made real choices."""
	print("\n===== PATH POINT ECONOMY (pathcurve) =====")
	print("earned = level points + modelled feat points (feat points are an ASSUMPTION until the feat ledger exists: %d at L%d)" % [int(FEAT_POINTS_AT_MAX), int(MAX_LEVEL)])
	var fails := 0
	var head := "%-9s %7s %6s" % ["level", "earned", "feats"]
	for k in ALL:
		head += " %9s" % k.substr(0, 9)
	print(head + "   (cells: share of the tree a character could afford)")
	for lvl in SENTINEL_LEVELS:
		var row := "%-9d %7d %6d" % [lvl, points_for(lvl), feat_points(lvl)]
		for k in ALL:
			row += " %8.0f%%" % (100.0 * float(points_for(lvl)) / float(capacity(k)))
		print(row)
	print("\ncapacity (points to fill the whole tree): " + ", ".join(ALL.map(func(k): return "%s %d" % [k, capacity(k)])))
	for k in ALL:
		var cap: int = capacity(k)
		var ok_not_full: bool = points_for(10000) < cap
		var ok_choices: bool = points_for(50) >= 10
		if not ok_not_full or not ok_choices:
			fails += 1
		print("  %s %-10s never full by L10000 (%d of %d); real choices by L50 (%d points)" % ["PASS" if ok_not_full and ok_choices else "FAIL", k, points_for(10000), cap, points_for(50)])
	# Single-rank plain nodes are where the capacity went: a node whose per-rank amount is over MAX_SCALABLE_AMOUNT cannot be multiplied by five.
	print("
single-rank PLAIN nodes (not keystones, not yes/no) - these are what keeps the tree small:")
	var singles := 0
	for arch in ["warrior", "mage", "trickster"]:
		var names := []
		for b in PD.get_archetype_tree(arch).get("branches", []):
			for n in b.get("nodes", []):
				var nd: Dictionary = PD.find_node(String(n.get("id", "")))
				if not bool(nd.get("keystone", false)) and PD.max_rank(nd) == 1:
					var only_bool := true
					for v in nd.get("effect", {}).values():
						if not (v is bool):
							only_bool = false
					if not only_bool:
						names.append("%s (%s)" % [nd.get("name", "?"), String(n.get("id", ""))])
		singles += names.size()
		print("  %-9s %d: %s" % [arch, names.size(), ", ".join(names)])
	# Names must be unique inside what ONE class can see: a player cannot tell two "Quiet Mind"s apart.
	var dupes := 0
	for k in ALL:
		var seen := {}
		var arch2: String = PD.class_archetype(k)
		var all_nodes: Array = []
		for b in PD.get_archetype_tree(arch2).get("branches", []):
			all_nodes.append_array(b.get("nodes", []))
			if seen.has(String(b.get("name", ""))):
				dupes += 1
				print("  FAIL %s: branch name '%s' is also a node name" % [k, b.get("name", "")])
		all_nodes.append_array(PD.signature_nodes(k))
		for n in all_nodes:
			var nm: String = String(n.get("name", ""))
			if seen.has(nm):
				dupes += 1
				print("  FAIL %s: two things are called '%s' (%s and %s)" % [k, nm, seen[nm], n.get("id", "")])
			seen[nm] = String(n.get("id", ""))
		for b in PD.get_archetype_tree(arch2).get("branches", []):
			if seen.has(String(b.get("name", ""))):
				dupes += 1
				print("  FAIL %s: branch '%s' shares its name with node %s" % [k, b.get("name", ""), seen[String(b.get("name", ""))]])
	fails += dupes
	print("  %s no class sees two things with one name (%d collisions)" % ["PASS" if dupes == 0 else "FAIL", dupes])
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)


static func audit_spec(sim) -> void:
	"""`pathspec` (instrument 1): the spec spends legally and the instrument actually carries it. Specs are checked by BUILDING the character
	through make_char with the flag on, then reading the character back - not by trusting the planner's own list."""
	print("\n===== PATH SPECS (pathspec) =====")
	var fails := 0
	var saved: String = sim._path_kind
	for kind in KINDS:
		print("\n-- spec: %s" % kind)
		print("%-10s %6s %8s %8s %6s  %s" % ["class", "level", "budget", "spent", "nodes", "ranked up (top 4)"])
		for k in ALL:
			for lvl in [10, 50, 100, 500, 2000]:
				sim._path_kind = kind
				var ch = sim.make_char(lvl, "average", k, "Human")
				var budget: int = points_for(lvl)
				var spent: int = spent_points(ch)
				var nodes: int = ch.path_ranks.size()
				var legal := spent <= budget
				for id in ch.path_ranks:
					var pre: String = PD.get_prereq_id(String(id))
					if pre != "" and int(ch.path_ranks.get(pre, 0)) < 1:
						legal = false
				var used: bool = float(spent) >= float(budget) * 0.80 or nodes >= 30 or spent >= capacity(k) - 5
				if not legal or not used:
					fails += 1
				if lvl in [50, 500, 2000]:
					var top := []
					var ids: Array = ch.path_ranks.keys()
					ids.sort_custom(func(a, b): return int(ch.path_ranks[a]) > int(ch.path_ranks[b]))
					for i in range(mini(4, ids.size())):
						top.append("%s %d" % [PD.find_node(String(ids[i])).get("name", ids[i]), int(ch.path_ranks[ids[i]])])
					print("%-10s %6d %8d %8d %6d  %s%s" % [k, lvl, budget, spent, nodes, ", ".join(top), "" if legal and used else "   <-- FAIL"])
	# the control: with no spec, a character carries no ranks at all
	sim._path_kind = ""
	var plain = sim.make_char(500, "average", "Wizard", "Human")
	var none_ok: bool = plain.path_ranks.is_empty()
	if not none_ok:
		fails += 1
	print("\n  %s no spec = no ranks (the control: old numbers stay byte-identical)" % ["PASS" if none_ok else "FAIL"])
	sim._path_kind = saved
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)


# ---------------------------------------------------------------------------------------------------------------------
# pathvalue (section 8.3 item 3): what is each BRANCH worth, per class and level?
# ---------------------------------------------------------------------------------------------------------------------
## Paired A/B. Both arms of a cell build the SAME character (gear is rolled before any path is applied) against the SAME monster:
## each fight is seeded from its own index, so fight i is fight i in both arms. The arms then differ in the path and nothing else.
## "Branch only" = every point the level has earned goes into that one branch (first four nodes, in order). That is a CEILING for
## the branch at this level, not what a typical player does; `pathspread` covers the typical mix.
const SIGNIFICANT_PP := 6.0   # the +-10pp rule, halved for a PAIRED comparison: nothing under this is called a difference


static func apply_only(ch, klass: String, branch_key: String, level: int) -> int:
	"""Spend the level's points on ONE branch (or "signature"), tiers in order, spreading ranks evenly (rank 1 of every node, then rank 2...)."""
	var arch: String = PD.class_archetype(klass)
	var ids: Array = []
	if branch_key == "signature":
		for n in PD.signature_nodes(klass):
			ids.append(String(n.get("id", "")))
	else:
		ids = _branch_ids(arch, branch_key)
	var budget: int = points_for(level)
	var spent := 0
	for target in range(1, 6):
		for id in ids:
			var node: Dictionary = PD.find_node(id)
			if node.is_empty():
				continue
			var cap: int = PD.max_rank(node)
			var pre: String = PD.get_prereq_id(id)
			if pre != "" and int(ch.path_ranks.get(pre, 0)) < 1:
				continue
			var r: int = int(ch.path_ranks.get(id, 0))
			while r < mini(target, cap) and spent + PP.rank_cost(r + 1) <= budget:
				spent += PP.rank_cost(r + 1)
				r += 1
				ch.set_path_rank(id, r)
	return spent


static func _paired(sim, level: int, klass: String, branch_key: String, n: int, tag: String) -> Dictionary:
	var w := 0
	var d := 0
	var turns := 0
	var taken := 0
	for i in range(n):
		seed(hash("pathvalue|%s|%d|%s|%d" % [klass, level, tag, i]))
		sim._path_kind = ""
		sim._path_only = branch_key
		var r = sim.run_fight(level, "average", "normal", 1.0, 1.0, 1.0, klass)
		sim._path_only = ""
		if bool(r.get("win", false)):
			w += 1
		if bool(r.get("died", false)):
			d += 1
		turns += int(r.get("turns", 0))
		taken += int(r.get("taken", 0))
	return {"win": 100.0 * w / n, "death": 100.0 * d / n, "turns": float(turns) / n, "taken": float(taken) / n}


static func audit_value(sim) -> void:
	"""Which branch is worth its points, for which class, at which level. Args: --class=Wizard --levels=30,100 --n=120."""
	var classes: Array = ALL
	var levels: Array = [30, 100, 500]
	var n := 120
	for a in OS.get_cmdline_user_args():
		var sa := String(a)
		if sa.begins_with("--class="):
			classes = [sa.substr(8)]
		elif sa.begins_with("--levels="):
			levels = Array(sa.substr(9).split(",")).map(func(x): return int(x))
		elif sa.begins_with("--n="):
			n = int(sa.substr(4))
	print("\n===== WHAT EACH BRANCH IS WORTH (pathvalue) =====")
	print("paired: fight i is the same character and monster in both arms; branch-only = every point the level has earned goes into that one branch.")
	print("win/death in percentage points over the unspent baseline, %d fights per cell; |change| < %.0fpp is NOT called a difference (shown as ~).\n" % [n, SIGNIFICANT_PP])
	var fails := 0
	var zero_value: Array = []
	for k in classes:
		var arch: String = PD.class_archetype(k)
		var keys: Array = []
		for b in PD.get_archetype_tree(arch).get("branches", []):
			keys.append(String(b.get("id", "")))
		keys.append("signature")
		for lvl in levels:
			var base: Dictionary = _paired(sim, lvl, k, "", n, "base")
			var line := "%-9s L%-5d base %3.0f/%4.1f |" % [k, lvl, base["win"], base["death"]]
			for key in keys:
				var arm: Dictionary = _paired(sim, lvl, k, key, n, "base")   # same tag: same seeds as the baseline
				var dw: float = arm["win"] - base["win"]
				var dd: float = arm["death"] - base["death"]
				var mark := " "
				if abs(dw) < SIGNIFICANT_PP and abs(dd) < SIGNIFICANT_PP:
					mark = "~"
				line += " %s%s %+.0f/%+.1f" % [key.substr(0, 6), mark, dw, dd]
				if key == "signature" and abs(dw) < 0.5 and abs(dd) < 0.5 and abs(arm["turns"] - base["turns"]) < 0.05:
					zero_value.append("%s L%d signature" % [k, lvl])
			print(line)
	# A branch that changes NOTHING at all (turns identical to the decimal) is not "small", it is not running.
	for z in zero_value:
		fails += 1
		print("  FAIL %s: identical numbers after a real change means the change is not running" % z)
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)


# ---------------------------------------------------------------------------------------------------------------------
# pathspread (section 8.3 item 5): is any build mandatory, or a trap?
# ---------------------------------------------------------------------------------------------------------------------
static func _paired_spec(sim, level: int, klass: String, kind: String, n: int) -> Dictionary:
	var w := 0
	var d := 0
	for i in range(n):
		seed(hash("pathspread|%s|%d|%d" % [klass, level, i]))   # the same fight in every arm
		sim._path_kind = kind
		var r = sim.run_fight(level, "average", "normal", 1.0, 1.0, 1.0, klass)
		sim._path_kind = ""
		if bool(r.get("win", false)):
			w += 1
		if bool(r.get("died", false)):
			d += 1
	return {"win": 100.0 * w / n, "death": 100.0 * d / n}


static func audit_spread(sim) -> void:
	"""Per class and level: none / typical / offense / defense, paired. Deep means choices matter but none is mandatory:
	flags a class where the three specs differ by more than 10pp (a mandatory build), or where `typical` loses to another spec by more than
	10pp (the default is a trap). Args: --class=X --levels=30,100 --n=120."""
	var classes: Array = ALL
	var levels: Array = [30, 100, 500]
	var n := 120
	for a in OS.get_cmdline_user_args():
		var sa := String(a)
		if sa.begins_with("--class="):
			classes = [sa.substr(8)]
		elif sa.begins_with("--levels="):
			levels = Array(sa.substr(9).split(",")).map(func(x): return int(x))
		elif sa.begins_with("--n="):
			n = int(sa.substr(4))
	print("\n===== SPEC SPREAD (pathspread) =====")
	print("win%% / death%%, paired seeds, %d fights per arm. none = no points spent (the old game)." % n)
	print("%-9s %5s | %-11s %-11s %-11s %-11s | spread flags" % ["class", "level", "none", "typical", "offense", "defense"])
	var fails := 0
	for k in classes:
		for lvl in levels:
			var arms := {}
			for kind in ["none", "typical", "offense", "defense"]:
				arms[kind] = _paired_spec(sim, lvl, k, "" if kind == "none" else kind, n)
			var wins := [arms["typical"]["win"], arms["offense"]["win"], arms["defense"]["win"]]
			var spread: float = float(wins.max()) - float(wins.min())
			var flags := ""
			if spread > 10.0:
				flags += " MANDATORY-BUILD(%.0fpp)" % spread
				fails += 1
			if float(wins.max()) - float(arms["typical"]["win"]) > 10.0:
				flags += " TYPICAL-IS-A-TRAP"
				fails += 1
			var cells := ""
			for kind in ["none", "typical", "offense", "defense"]:
				cells += " %3.0f/%4.1f    " % [arms[kind]["win"], arms[kind]["death"]]
			print("%-9s %5d |%s| %s" % [k, lvl, cells, flags if flags != "" else "ok"])
	print("PASS" if fails == 0 else "FAIL (%d flagged)" % fails)


# ---------------------------------------------------------------------------------------------------------------------
# pathfires (section 8.3 item 2): does every node CHANGE a fight?
# ---------------------------------------------------------------------------------------------------------------------
## Paired, isolating ONE node: arm A holds the node's prerequisite chain at rank 1, arm B holds the same chain plus the node at its top rank.
## Identical numbers over every paired fight (damage dealt, damage taken, turns) means the node is not running - "identical numbers after a real
## change" is the instrument's own signal for a dead change. The unit probes prove a key CAN fire; this asks whether the fights the sim
## actually plays ever reach it. Nodes the sim cannot exercise by construction are listed, not hidden: it never uses a potion, never flees
## on purpose, and does not collect loot or valor.
const NOT_MODELLED_KEYS := ["item_heal_pct", "item_resource_pct", "item_cleanse", "item_guard_pct", "flee_chance_pct", "failed_flee_dodge_pct",
	"valor_pct", "loot_reveal_bonus", "xp_pct", "pickpocket_always", "pickpocket_yield_pct", "stun_immune", "stun_duration_reduction"]
## Kill riders act AFTER the one fight a paired comparison measures; the next fight is where they pay. Measuring them needs a run model (fights in
## sequence), which is the same model the persistent-boon design needs - listed there, not faked here.
## Cards or engine states the simulator's policy never reaches (it plays a fixed rotation, and a level-100 mage kills in two or three rounds, before
## Focus has built). The node is proven by its own probe; these are policy and fight-length limits, listed so they are not mistaken for dead nodes.
const POLICY_GAP_KEYS := ["meteor_per_focus_pct", "surge_focus", "bolt_full_focus_double", "meteor_burn", "frost_nova_pct", "ambush_damage_pct",
	"exploit_damage_pct", "vanish_evasion_pct", "assassinate_pct", "buff_duration_bonus", "oracle_lance_per_focus_pct", "rampage_full_stun",
	"rampage_lifesteal_pct", "vs_low_hp_damage_pct"]
const AFTER_THE_FIGHT_KEYS := ["kill_cost_refund_pct", "kill_heal_pct", "kill_cleanse", "kill_resource_pct", "kill_defense_buff_pct"]
## Conditions the simulator's fights rarely create: a stunned/charmed/burning monster, poison or bleed on the player, a player below half HP.
const RARE_CONDITION_KEYS := ["vs_disabled_damage_pct", "vs_burning_damage_pct", "burn_power_pct", "bleed_power_pct", "lay_on_hands_cleanse",
	"dot_reduction_pct", "low_hp_damage_pct", "low_hp_reduction_pct", "low_hp_regen_pct", "healing_received_pct", "death_save_per_combat", "clutch_time_stop_per_combat"]


static func _chain_ids(id: String) -> Array:
	var chain: Array = []
	var cur: String = PD.get_prereq_id(id)
	while cur != "":
		chain.push_front(cur)
		cur = PD.get_prereq_id(cur)
	return chain


static func _fires_arm(sim, klass: String, level: int, node_id: String, with_node: bool, n: int) -> Dictionary:
	var dealt := 0
	var taken := 0
	var turns := 0
	var wins := 0
	var casts := 0
	var res := 0.0
	for i in range(n):
		seed(hash("pathfires|%s|%d|%d" % [klass, level, i]))
		sim._path_only = ""
		sim._path_kind = ""
		sim._path_nodes = {}
		for pid in _chain_ids(node_id):
			sim._path_nodes[pid] = 1
		if with_node:
			sim._path_nodes[node_id] = PD.max_rank(PD.find_node(node_id))
		var r = sim.run_fight(level, "average", "normal", 1.0, 1.0, 1.0, klass)
		sim._path_nodes = {}
		dealt += int(r.get("dealt", 0))
		taken += int(r.get("taken", 0))
		turns += int(r.get("turns", 0))
		casts += int(r.get("casts", 0))
		# resource and HP low-water marks: a node that only moves the pool (Pilfer, Siphon) or only the HP floor is firing, just not in damage
		res += float(r.get("min_res_pct", 0.0)) + float(r.get("end_res_pct", 0.0)) + float(r.get("min_hp_pct", 0.0))
		if bool(r.get("win", false)):
			wins += 1
	return {"dealt": dealt, "taken": taken, "turns": turns, "wins": wins, "casts": casts, "res": snappedf(res, 0.001)}


static func audit_fires(sim) -> void:
	"""Every node a class can see, one at a time. Args: --class=X --level=100 --n=60."""
	var classes: Array = ALL
	var level := 100
	var n := 60
	for a in OS.get_cmdline_user_args():
		var sa := String(a)
		if sa.begins_with("--class="):
			classes = [sa.substr(8)]
		elif sa.begins_with("--level="):
			level = int(sa.substr(8))
		elif sa.begins_with("--n="):
			n = int(sa.substr(4))
	print("\n===== DOES EVERY NODE CHANGE A FIGHT? (pathfires) =====")
	print("paired, %d fights at L%d, one node at its top rank over its prerequisite chain at rank 1. SILENT = identical damage dealt, damage taken, turns, casts, resource and HP low-water marks." % [n, level])
	var silent_total := 0
	var unexpected := 0
	var seen_nodes := {}
	for k in classes:
		var arch: String = PD.class_archetype(k)
		var ids: Array = []
		for b in PD.get_archetype_tree(arch).get("branches", []):
			for nd in b.get("nodes", []):
				ids.append(String(nd.get("id", "")))
		for nd in PD.signature_nodes(k):
			ids.append(String(nd.get("id", "")))
		var silent: Array = []
		for id in ids:
			var node: Dictionary = PD.find_node(id)
			var a: Dictionary = _fires_arm(sim, k, level, id, false, n)
			var b: Dictionary = _fires_arm(sim, k, level, id, true, n)
			if a["dealt"] == b["dealt"] and a["taken"] == b["taken"] and a["turns"] == b["turns"] and a["casts"] == b["casts"] and a["res"] == b["res"]:
				var keys: Array = node.get("effect", {}).keys()
				var modelled := true
				var why := ""
				for key in keys:
					if String(key) in NOT_MODELLED_KEYS:
						modelled = false
						why = "not modelled"
					elif String(key) in AFTER_THE_FIGHT_KEYS:
						modelled = false
						why = "pays in the NEXT fight"
					elif String(key) in RARE_CONDITION_KEYS:
						modelled = false
						why = "rare condition"
					elif String(key) in POLICY_GAP_KEYS:
						modelled = false
						why = "the sim's policy never reaches it"
				silent.append("%s%s" % [node.get("name", id), "" if modelled else " (%s)" % why])
				if modelled:
					unexpected += 1
		silent_total += silent.size()
		print("%-9s %d nodes, %d silent: %s" % [k, ids.size(), silent.size(), ", ".join(silent) if not silent.is_empty() else "none"])
	print("\nsilent in total: %d, of which NOT explained by something the sim does not play: %d" % [silent_total, unexpected])
	print("PASS" if unexpected == 0 else "FAIL (%d nodes the sim's fights never reach)" % unexpected)


# ---------------------------------------------------------------------------------------------------------------------
# pathgap (section 8.3 item 6): what each class's paths need to sit with the field
# ---------------------------------------------------------------------------------------------------------------------
## The monster refit holds the AVERAGE win rate at its design target, so what a path change can fix is each class's distance from the field, never the field
## itself. The target here is therefore the MEDIAN class at the same level with the typical spec - not the strongest class (a treadmill) - and the lever is
## PathDatabase.CLASS_SCALE (every numeric path effect of the class times a factor). For each class and level the audit sweeps the factor, interpolates the one
## that lands on the median, and says plainly when it cannot: a class whose win rate stops moving as the factor grows is bound by a ceiling (Wizard at 95%),
## and "saturation is not convergence" - it is reported as BOUND, not as a solved scale.
const GAP_SCALES := [0.5, 1.0, 1.5, 2.0]


static func _paired_scale(sim, level: int, klass: String, scale: float, n: int) -> float:
	var w := 0
	for i in range(n):
		seed(hash("pathgap|%s|%d|%d" % [klass, level, i]))
		sim._path_kind = "typical"
		sim._path_scale = scale
		var r = sim.run_fight(level, "average", "normal", 1.0, 1.0, 1.0, klass)
		sim._path_kind = ""
		sim._path_scale = -1.0
		if bool(r.get("win", false)):
			w += 1
	return 100.0 * w / n


static func _solve_scale(points: Array, target: float) -> Array:
	"""points = [[scale, win], ...] ascending in scale. Returns [scale, status]."""
	var lo: float = float(points[0][1])
	var hi: float = float(points[points.size() - 1][1])
	if target < lo - 3.0:
		return [float(points[0][0]), "BOUND-LOW (still above the field at the smallest scale)"]
	if target > hi + 3.0:
		return [float(points[points.size() - 1][0]), "BOUND-HIGH (cannot reach the field even at the largest scale)"]
	for i in range(points.size() - 1):
		var a: float = float(points[i][1])
		var b: float = float(points[i + 1][1])
		if (target >= a and target <= b) or (target <= a and target >= b):
			if abs(b - a) < 2.0:
				return [float(points[i][0]) if abs(target - a) < abs(target - b) else float(points[i + 1][0]), "FLAT (win barely moves with scale: a ceiling or a noise floor)"]
			var t: float = (target - a) / (b - a)
			return [snappedf(float(points[i][0]) + t * (float(points[i + 1][0]) - float(points[i][0])), 0.05), "ok"]
	return [1.0, "ok"]


static func audit_gap(sim) -> void:
	var classes: Array = ALL
	var levels: Array = [30, 100, 500]
	var n := 100
	for a in OS.get_cmdline_user_args():
		var sa := String(a)
		if sa.begins_with("--levels="):
			levels = Array(sa.substr(9).split(",")).map(func(x): return int(x))
		elif sa.begins_with("--n="):
			n = int(sa.substr(4))
		elif sa.begins_with("--class="):
			classes = [sa.substr(8)]
	print("\n===== PATH GAP (pathgap) =====")
	print("win%% of the typical spec at scale %s; target = the median class at the same level; %d paired fights per cell." % [str(GAP_SCALES), n])
	var rows := {}
	for lvl in levels:
		var wins := {}
		for k in classes:
			var pts: Array = []
			for sc in GAP_SCALES:
				pts.append([sc, _paired_scale(sim, lvl, k, sc, n)])
			wins[k] = pts
		var at1: Array = []
		for k in classes:
			at1.append(float(wins[k][1][1]))
		at1.sort()
		var target: float = float(at1[at1.size() / 2])
		print("\nL%d   target (median class at scale 1.0) = %.0f%%" % [lvl, target])
		print("%-9s %s | gap  -> needed scale" % ["class", "  ".join(GAP_SCALES.map(func(s): return "x%.1f" % s))])
		for k in classes:
			var pts2: Array = wins[k]
			var sol: Array = _solve_scale(pts2, target)
			var cells := "  ".join(pts2.map(func(p): return "%3.0f" % p[1]))
			print("%-9s %s | %+3.0f  -> x%.2f  %s" % [k, cells, float(pts2[1][1]) - target, float(sol[0]), "" if sol[1] == "ok" else sol[1]])
			if not rows.has(k):
				rows[k] = []
			rows[k].append([lvl, sol[0], sol[1]])
	print("\nPER-CLASS SUGGESTION (median needed scale across the levels; BOUND levels are shown, not averaged away):")
	for k in classes:
		var scs: Array = rows[k].map(func(r): return float(r[1]))
		scs.sort()
		var bound: Array = rows[k].filter(func(r): return String(r[2]) != "ok")
		print("  %-9s x%.2f   (%s)%s" % [k, float(scs[scs.size() / 2]), ", ".join(rows[k].map(func(r): return "L%d x%.2f" % [r[0], r[1]])), "   <- %d level(s) bound or flat" % bound.size() if not bound.is_empty() else ""])
	print("PASS")
