# path_feats.gd
# Path feats: points paid for doing ordinary things (docs/design/paths_revamp.md 3.6).
#
# A feat is a COUNTER and a LADDER of rungs. Each rung reached pays 1 Path point, once. The six
# milestones that used to be hard-wired into server.gd are now the first rung of their ladders
# (`legacy` keeps the old id, so nothing is paid twice - see Character.from_dict).
#
# Counter kinds:
#   "stored"   a count the character keeps in `feat_counts[id]` (bumped by `Character.bump_feat`)
#   "max"      the best value seen, kept in `feat_counts[id]` (`Character.note_feat_max`)
#   "derived"  read from state the character already has, never stored twice (one value, one place)
#
# Rung numbers are guesses (G); the feat ledger (docs 8.3 item 8) retunes them from real play.
class_name PathFeats

const FEATS := {
	"kills": {
		"label": "Slay monsters", "kind": "derived", "source": "monsters_killed",
		"rungs": [100, 1000, 10000, 100000, 1000000], "legacy": "hundred_kills",
	},
	"champions": {
		"label": "Slay champions (Empowered monsters)", "kind": "stored",
		"rungs": [1, 10, 100, 1000, 10000], "legacy": "first_empowered_kill",
	},
	"triple_champions": {
		"label": "Slay 3-modifier Empowered monsters", "kind": "stored",
		"rungs": [1, 10, 100, 1000], "legacy": "first_triple_empowered_kill",
	},
	"bosses": {
		"label": "Defeat bosses", "kind": "stored",
		"rungs": [1, 5, 25, 100, 500], "legacy": "first_boss_kill",
	},
	"dungeons": {
		"label": "Clear dungeons", "kind": "stored",
		"rungs": [1, 5, 25, 100, 500], "legacy": "first_dungeon_clear",
	},
	"apex": {
		"label": "Slay monsters in the Apex Frontier", "kind": "stored",
		"rungs": [1, 25, 250], "legacy": "first_apex_kill",
	},
	"quests": {
		"label": "Complete quests", "kind": "derived", "source": "completed_quests",
		"rungs": [10, 50, 250, 1000],
	},
	"gear_level": {
		"label": "Wear a piece of gear of level", "kind": "max",
		"rungs": [20, 50, 100, 500, 2000, 8000],
	},
	"level": {
		"label": "Reach level", "kind": "derived", "source": "level",
		"rungs": [100, 500, 1000, 2500, 5000, 10000],
	},
	"master_smith": {
		"label": "Buy from the Master Smith", "kind": "stored",
		"rungs": [1, 5, 20],
	},
}


static func value_of(feat_id: String, src: Dictionary) -> int:
	"""A feat's counter from plain numbers: {monsters_killed, completed_quests (a count), level, counts (the stored
	feat_counts)}. Character.feat_value and the Paths panel both call this, so neither keeps its own copy."""
	var f: Dictionary = FEATS.get(feat_id, {})
	if String(f.get("kind", "")) == "derived":
		return int(src.get(String(f.get("source", "")), 0))
	return int((src.get("counts", {}) as Dictionary).get(feat_id, 0))


static func rungs_reached(feat_id: String, value: int) -> int:
	"""How many rungs of this ladder `value` has reached."""
	var f: Dictionary = FEATS.get(feat_id, {})
	var n := 0
	for r in f.get("rungs", []):
		if value >= int(r):
			n += 1
	return n


static func rung_value(feat_id: String, rung: int) -> int:
	"""The threshold of rung `rung` (1-based), or 0 when there is no such rung."""
	var rungs: Array = FEATS.get(feat_id, {}).get("rungs", [])
	if rung < 1 or rung > rungs.size():
		return 0
	return int(rungs[rung - 1])


static func legacy_feat_for(milestone_id: String) -> String:
	for fid in FEATS:
		if String(FEATS[fid].get("legacy", "")) == milestone_id:
			return String(fid)
	return ""


static func total_rungs() -> int:
	var n := 0
	for fid in FEATS:
		n += (FEATS[fid].get("rungs", []) as Array).size()
	return n


static func describe_rung(feat_id: String, rung: int) -> String:
	var f: Dictionary = FEATS.get(feat_id, {})
	var v: int = rung_value(feat_id, rung)
	if v <= 0:
		return String(f.get("label", feat_id))
	var label: String = String(f.get("label", feat_id))
	if feat_id in ["gear_level", "level"]:
		return "%s %d" % [label, v]
	return "%s: %d" % [label, v]
