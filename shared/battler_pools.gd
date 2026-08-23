class_name BattlerPools
extends RefCounted

# v0.9.670 — single source of truth for which battler sprite ids belong to each
# class. Shared by the server (rolls a new character's battler_id at creation
# from EXPANDED_POOLS) and the client (renders it). Character sprite is now
# STORED per-character (character.battler_id) instead of derived live, so growing
# EXPANDED_POOLS never changes an existing character's look.

# LEGACY_POOLS — the exact 25-id assignment that shipped v0.9.669, when the
# sprite was derived live as `abs(name.hash()) % pool.size()`. Characters created
# before battler_id existed backfill their id from THIS table (same formula), so
# their avatar is preserved bit-for-bit. DO NOT reorder or edit these arrays —
# that would reshuffle every legacy character's sprite.
const LEGACY_POOLS := {
	"Fighter": ["1_1", "2_1", "6_4"],
	"Barbarian": ["6_2", "5_3", "7_8"],
	"Paladin": ["4_7", "2_8", "3_8"],
	"Wizard": ["1_6", "5_6", "2_6"],
	"Sorcerer": ["4_5", "3_6", "1_5"],
	"Sage": ["3_3", "5_7", "5_8"],
	"Thief": ["5_7", "6_3", "7_5"],
	"Ranger": ["3_4", "2_4", "6_1"],
	"Ninja": ["4_5", "1_8", "7_3"],
}

# EXPANDED_POOLS — the full curated set (56 battlers extracted from the
# TimeFantasy singleframes pack). NEW characters roll their battler_id from here
# at creation. Each class's pool is a superset of its legacy pool so the theme
# stays consistent; ids may appear in two classes (e.g. 4_5 Sorcerer+Ninja).
const EXPANDED_POOLS := {
	"Fighter":   ["1_1", "2_1", "6_4", "1_2", "1_3", "2_3", "4_1", "6_6", "7_1"],
	"Barbarian": ["6_2", "5_3", "7_8", "4_2", "4_8", "5_4", "7_7"],
	"Paladin":   ["4_7", "2_8", "3_8", "2_2", "7_4", "7_6"],
	"Wizard":    ["1_6", "5_6", "2_6", "3_7"],
	"Sorcerer":  ["4_5", "3_6", "1_5", "3_5", "5_5"],
	"Sage":      ["3_3", "5_7", "5_8", "2_7", "4_6", "6_8"],
	"Thief":     ["5_7", "6_3", "7_5", "1_7", "3_2", "5_2", "7_2"],
	"Ranger":    ["3_4", "2_4", "6_1", "2_5", "3_1", "6_5", "6_7", "1_4"],
	"Ninja":     ["4_5", "1_8", "7_3", "4_3", "4_4", "5_1"],
}

static func legacy_id_for(cls: String, char_name: String) -> String:
	"""Reproduce the v0.9.669 live-derived id exactly, for legacy backfill."""
	var pool: Array = LEGACY_POOLS.get(cls, [])
	if pool.is_empty():
		return ""
	return String(pool[abs(char_name.hash()) % pool.size()])

static func pick_expanded(cls: String, rng: RandomNumberGenerator) -> String:
	"""Roll a new character's battler_id from the full pool (falls back to the
	legacy pool for any class not present in EXPANDED_POOLS)."""
	var pool: Array = EXPANDED_POOLS.get(cls, [])
	if pool.is_empty():
		pool = LEGACY_POOLS.get(cls, [])
	if pool.is_empty():
		return ""
	return String(pool[rng.randi() % pool.size()])
