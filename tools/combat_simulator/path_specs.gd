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
		if String(node.get("class_lock", "")) != "" and not bool(node.get("signature", false)) and spent < PD.CLASS_KEYSTONE_SPEND_REQ:
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
