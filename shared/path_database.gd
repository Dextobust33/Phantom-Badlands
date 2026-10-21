# path_database.gd
# Path of the Badlands — ARPG pillar 3 skill tree (design locked 2026-06-10).
#
# Three archetype trees (warrior/mage/trickster), each 3 themed branches of
# 5 nodes (4 normal + 1 branch keystone) + 3 class keystones (one per class).
# Every node costs 1 Path point. Points earned = level/5 + milestones (derived,
# never stored — see character.get_path_points_earned()).
#
# Branch rule: node tier N requires tier N-1 in the same branch. Branch
# keystone (tier 5) requires the full branch. Class keystones require
# CLASS_KEYSTONE_SPEND_REQ points spent anywhere + the matching class.
#
# The `desc` strings are the player-facing contract — effect wiring (slice 2+)
# must match them exactly. `effect` dicts are machine-readable hints for the
# wiring pass; until a node is wired, taking it stores the id but does nothing
# (slices 2-3 wire warrior, then mage/trickster).
class_name PathDatabase

const PathPointsScript = preload("res://shared/path_points.gd")

const CLASS_KEYSTONE_SPEND_REQ := 8

# archetype -> ordered branch list. Node ids: "<archetype>_<branch#>_<tier>".
const TREES = {
	"warrior": {
		"title": "Path of the Warlord",
		"branches": [
			{
				"id": "onslaught", "name": "Onslaught", "color": "#FF6666",
				"nodes": [
					{"id": "warrior_1_1", "name": "Sharpened Edge", "desc": "+5% attack damage.", "effect": {"attack_damage_pct": 5}},
					{"id": "warrior_1_2", "name": "Rending Blows", "desc": "Your bleed effects tick 50% harder.", "effect": {"bleed_power_pct": 50}},
					{"id": "warrior_1_3", "name": "Momentum", "desc": "Killing blows refund 50% of the ability's stamina cost.", "effect": {"kill_cost_refund_pct": 50}},
					{"id": "warrior_1_4", "name": "Overwhelm", "desc": "+30% damage against stunned or charmed monsters.", "effect": {"vs_disabled_damage_pct": 30}},
					{"id": "warrior_1_5", "name": "Blood Frenzy", "desc": "KEYSTONE: +35% damage while below 50% HP, but healing you receive is reduced 30%.", "keystone": true, "effect": {"low_hp_damage_pct": 35, "healing_received_pct": -30}},
				],
			},
			{
				"id": "bulwark", "name": "Bulwark", "color": "#6699FF",
				"nodes": [
					{"id": "warrior_2_1", "name": "Iron Hide", "desc": "+8% defense.", "effect": {"defense_pct": 8}},
					{"id": "warrior_2_2", "name": "Unshakeable", "desc": "Stuns and webs on you last 1 turn less.", "effect": {"stun_duration_reduction": 1}},
					{"id": "warrior_2_3", "name": "Retribution", "desc": "Reflect 15% of melee damage you take back at the attacker.", "effect": {"melee_reflect_pct": 15}},
					{"id": "warrior_2_4", "name": "Purging Strikes", "desc": "Killing blows cleanse your poison and bleed.", "effect": {"kill_cleanse": true}},
					{"id": "warrior_2_5", "name": "Juggernaut's Resolve", "desc": "KEYSTONE: You are immune to stun, but your flee chance is reduced 15%.", "keystone": true, "effect": {"stun_immune": true, "flee_chance_pct": -15}},
				],
			},
			{
				"id": "warlord", "name": "Warlord", "color": "#FFD700",
				"nodes": [
					{"id": "warrior_3_1", "name": "Conditioning", "desc": "+10% max stamina.", "effect": {"max_resource_pct": 10}},
					{"id": "warrior_3_2", "name": "War Drums", "desc": "Your combat buffs last 2 extra rounds.", "effect": {"buff_duration_bonus": 2}},
					{"id": "warrior_3_3", "name": "Second Wind", "desc": "Regenerate 2% max stamina each combat round.", "effect": {"combat_resource_regen_pct": 2}},
					{"id": "warrior_3_4", "name": "Commanding Presence", "desc": "Your buff effects are 20% stronger.", "effect": {"buff_value_pct": 20}},
					{"id": "warrior_3_5", "name": "Last Stand", "desc": "KEYSTONE: Once per combat, a lethal hit leaves you at 1 HP instead. Your max HP is reduced 10%.", "keystone": true, "effect": {"death_save_per_combat": 1, "max_hp_pct": -10}},
				],
			},
		],
		"class_keystones": {
			"Fighter": {"id": "ck_Fighter", "name": "Drillmaster", "desc": "CLASS KEYSTONE: All ability costs reduced 15%.", "effect": {"ability_cost_pct": -15}},
			"Barbarian": {"id": "ck_Barbarian", "name": "Blood Rage", "desc": "CLASS KEYSTONE: Berserk no longer reduces your defense, and you gain +3% damage per combat round (max +30%).", "effect": {"berserk_no_penalty": true, "ramp_damage_pct": 3, "ramp_damage_cap": 30}},
			"Paladin": {"id": "ck_Paladin", "name": "Crusader's Aura", "desc": "CLASS KEYSTONE: Heal 2% max HP on every kill, and your bonus vs undead/demons rises to +40%.", "effect": {"kill_heal_pct": 2, "undead_bonus_pct": 40}},
		},
	},
	"mage": {
		"title": "Path of the Archon",
		"branches": [
			{
				"id": "destruction", "name": "Destruction", "color": "#FF6666",
				"nodes": [
					{"id": "mage_1_1", "name": "Focused Mind", "desc": "+5% spell damage.", "effect": {"spell_damage_pct": 5}},
					{"id": "mage_1_2", "name": "Kindling", "desc": "Your burn effects tick 50% harder.", "effect": {"burn_power_pct": 50}},
					{"id": "mage_1_3", "name": "Essence Tap", "desc": "Killing blows refund 50% of the spell's mana cost.", "effect": {"kill_cost_refund_pct": 50}},
					{"id": "mage_1_4", "name": "Combustion", "desc": "+30% damage against burning monsters.", "effect": {"vs_burning_damage_pct": 30}},
					{"id": "mage_1_5", "name": "Overload", "desc": "KEYSTONE: Your spells deal +30% damage but cost 20% more mana.", "keystone": true, "effect": {"spell_damage_keystone_pct": 30, "ability_cost_pct": 20}},
				],
			},
			{
				"id": "aegis", "name": "Aegis", "color": "#6699FF",
				"nodes": [
					{"id": "mage_2_1", "name": "Warded Robes", "desc": "+8% defense.", "effect": {"defense_pct": 8}},
					{"id": "mage_2_2", "name": "Temporal Slip", "desc": "Stuns and webs on you last 1 turn less.", "effect": {"stun_duration_reduction": 1}},
					{"id": "mage_2_3", "name": "Static Veil", "desc": "Monsters that strike you take shock damage equal to 30% of your INT.", "effect": {"shock_thorns_int_pct": 30}},
					{"id": "mage_2_4", "name": "Cleansing Flame", "desc": "Killing blows cleanse your poison and bleed.", "effect": {"kill_cleanse": true}},
					{"id": "mage_2_5", "name": "Archmage's Ward", "desc": "KEYSTONE: Forcefield absorbs 50% more damage, but your max HP is reduced 10%.", "keystone": true, "effect": {"forcefield_power_pct": 50, "max_hp_pct": -10}},
				],
			},
			{
				"id": "wellspring", "name": "Wellspring", "color": "#FFD700",
				"nodes": [
					{"id": "mage_3_1", "name": "Deep Reserves", "desc": "+10% max mana.", "effect": {"max_resource_pct": 10}},
					{"id": "mage_3_2", "name": "Lingering Enchantment", "desc": "Your combat buffs last 2 extra rounds.", "effect": {"buff_duration_bonus": 2}},
					{"id": "mage_3_3", "name": "Flowing Font", "desc": "Your in-combat mana regeneration is 50% stronger.", "effect": {"combat_regen_bonus_pct": 50}},
					{"id": "mage_3_4", "name": "Empowered Casting", "desc": "Your buff effects are 20% stronger.", "effect": {"buff_value_pct": 20}},
					{"id": "mage_3_5", "name": "Time Anchor", "desc": "KEYSTONE: Once per combat, surviving a hit that leaves you below 20% HP freezes time — the monster skips its next turn. Your max HP is reduced 10%.", "keystone": true, "effect": {"clutch_time_stop_per_combat": 1, "max_hp_pct": -10}},
				],
			},
		],
		"class_keystones": {
			"Wizard": {"id": "ck_Wizard", "name": "Archmage", "desc": "CLASS KEYSTONE: 15% chance for your spells to cast twice.", "effect": {"double_cast_pct": 15}},
			"Sorcerer": {"id": "ck_Sorcerer", "name": "Chaos Theory", "desc": "CLASS KEYSTONE: Your double-damage chance rises from 25% to 35%.", "effect": {"sorcerer_double_pct": 35}},
			"Sage": {"id": "ck_Sage", "name": "Transcendence", "desc": "CLASS KEYSTONE: Meditate also restores 5% of your max HP.", "effect": {"meditate_heal_pct": 5}},
		},
	},
	"trickster": {
		"title": "Path of the Phantom",
		"branches": [
			{
				"id": "lethality", "name": "Lethality", "color": "#FF6666",
				"nodes": [
					{"id": "trickster_1_1", "name": "Keen Eye", "desc": "+3% critical hit chance.", "effect": {"crit_chance_pct": 3}},
					{"id": "trickster_1_2", "name": "Serrated Tools", "desc": "Your critical hits apply a bleed (30% of WIT per round, 3 rounds).", "effect": {"crit_bleed_wit_pct": 30, "crit_bleed_rounds": 3}},
					{"id": "trickster_1_3", "name": "Efficient Violence", "desc": "Killing blows refund 50% of the ability's energy cost.", "effect": {"kill_cost_refund_pct": 50}},
					{"id": "trickster_1_4", "name": "First Blood", "desc": "+30% damage against monsters at full HP.", "effect": {"vs_full_hp_damage_pct": 30}},
					{"id": "trickster_1_5", "name": "Assassinate", "desc": "KEYSTONE: Your critical hits deal +50% damage, but your normal hits deal 10% less.", "keystone": true, "effect": {"crit_damage_pct": 50, "noncrit_damage_pct": -10}},
				],
			},
			{
				"id": "shadow", "name": "Shadow", "color": "#6699FF",
				"nodes": [
					{"id": "trickster_2_1", "name": "Fleet Footed", "desc": "+8% flee chance.", "effect": {"flee_chance_pct": 8}},
					{"id": "trickster_2_2", "name": "Slippery", "desc": "Stuns and webs on you last 1 turn less.", "effect": {"stun_duration_reduction": 1}},
					{"id": "trickster_2_3", "name": "Ghost Step", "desc": "After a failed flee attempt, +30% dodge until your next turn.", "effect": {"failed_flee_dodge_pct": 30}},
					{"id": "trickster_2_4", "name": "Bleed Them Dry", "desc": "Killing blows cleanse your poison and bleed.", "effect": {"kill_cleanse": true}},
					{"id": "trickster_2_5", "name": "Phantom Strike", "desc": "KEYSTONE: Your first damaging action each combat always crits, and a first attack cannot miss. Your max HP is reduced 10%.", "keystone": true, "effect": {"first_strike_autocrit": true, "max_hp_pct": -10}},
				],
			},
			{
				"id": "fortune", "name": "Fortune", "color": "#FFD700",
				"nodes": [
					{"id": "trickster_3_1", "name": "Deep Pockets", "desc": "+10% max energy.", "effect": {"max_resource_pct": 10}},
					{"id": "trickster_3_2", "name": "Lasting Tricks", "desc": "Your combat buffs last 2 extra rounds.", "effect": {"buff_duration_bonus": 2}},
					{"id": "trickster_3_3", "name": "Profiteer", "desc": "+15% Valor from kills.", "effect": {"valor_pct": 15}},
					{"id": "trickster_3_4", "name": "Silver Tongue", "desc": "+15% Assassinate success chance.", "effect": {"assassinate_pct": 15}},
					{"id": "trickster_3_5", "name": "Jackpot", "desc": "KEYSTONE: +1 loot reveal on every combat victory, but you gain 10% less XP.", "keystone": true, "effect": {"loot_reveal_bonus": 1, "xp_pct": -10}},
				],
			},
		],
		"class_keystones": {
			"Grifter": {"id": "ck_Grifter", "name": "Cutpurse King", "desc": "CLASS KEYSTONE: Pickpocket always succeeds and steals 50% more materials.", "effect": {"pickpocket_always": true, "pickpocket_yield_pct": 50}},
			"Ranger": {"id": "ck_Ranger", "name": "Apex Hunter", "desc": "CLASS KEYSTONE: Your bonus vs beasts rises to +40%, and you gain +10% XP.", "effect": {"beast_bonus_pct": 40, "xp_pct": 10}},
			"Ninja": {"id": "ck_Ninja", "name": "Shadow Lord", "desc": "CLASS KEYSTONE: Vanish costs 50% less, and your flee chance rises another 15%.", "effect": {"vanish_cost_pct": -50, "flee_chance_pct": 15}},
		},
	},
}

# Path milestones — one-time per character, +1 point each. label is the
# player-facing toast; hooks live server-side (see _grant_path_milestone).
const MILESTONES = {
	"first_dungeon_clear": "Clear your first dungeon",
	"first_boss_kill": "Slay your first boss",
	"first_empowered_kill": "Slay your first Empowered monster",
	"first_triple_empowered_kill": "Slay a 3-modifier Empowered monster",
	"hundred_kills": "Slay 100 monsters",
	"first_apex_kill": "Slay a monster in the Apex Frontier",
}


# Effect keys that do NOT multiply with rank: durations, booleans and per-combat counts are one-shot facts, not
# amounts. A node carrying any of them is a single-rank node unless it names its own `ranks`.
const NON_SCALING_KEYS := ["stun_duration_reduction", "buff_duration_bonus", "crit_bleed_rounds",
	"death_save_per_combat", "clutch_time_stop_per_combat", "loot_reveal_bonus", "ramp_damage_cap"]
## Per-rank amounts larger than this are not safely multiplied by five; those nodes stay single-rank until
## `pathvalue` has measured what a rank is worth. (New nodes name their own `ranks`.)
const MAX_SCALABLE_AMOUNT := 10.0


# Class SIGNATURE branches (docs/design/paths_revamp.md section 7): six nodes only that class can see, chained S1..S6,
# then the class keystone (`ck_*`) as the seventh. Engine perks rank; card-rule nodes are single purchases. Every
# card-rule node names the card it changes, and each was written against that card's code, not its name.
# Ids are "sig_<Class>_<n>". The class keystone keeps its old id and its old unlock rule.
const SIGNATURES = {
	"Barbarian": {
		"id": "signature", "name": "Way of the Berserker", "color": "#8B0000",
		"nodes": [
			{"id": "sig_Barbarian_1", "name": "Thicker Skin", "desc": "While below half HP, take 1.5% less damage.", "effect": {"low_hp_reduction_pct": 1.5}},
			{"id": "sig_Barbarian_2", "name": "Fury Reserve", "desc": "Begin every fight with +1 Rage.", "effect": {"start_momentum": 1}, "ranks": 2},
			{"id": "sig_Barbarian_3", "name": "Reaver", "desc": "Rampage heals you for 3% of the damage it deals.", "effect": {"rampage_lifesteal_pct": 3}},
			{"id": "sig_Barbarian_4", "name": "Berserk Discipline", "desc": "Berserk lasts 1 round longer and its defense penalty is halved.", "effect": {"berserk_duration_bonus": 1, "berserk_penalty_cut_pct": 50}, "ranks": 1},
			{"id": "sig_Barbarian_5", "name": "Bull Rush Breaks", "desc": "Bull Rush also saps the target: -10% attack for 3 rounds.", "effect": {"bull_rush_weaken_pct": 10}, "ranks": 1},
			{"id": "sig_Barbarian_6", "name": "Unchained", "desc": "Rampage at full Rage also stuns the target (subject to its stun resistance).", "effect": {"rampage_full_stun": true}},
		],
	},
	"Paladin": {
		"id": "signature", "name": "Way of the Crusader", "color": "#FFD700",
		"nodes": [
			{"id": "sig_Paladin_1", "name": "Resolute", "desc": "The first blow that lands on you each fight builds +1 extra Conviction.", "effect": {"first_hit_conviction": 1}, "ranks": 3},
			{"id": "sig_Paladin_2", "name": "Bastion of Faith", "desc": "+2% max HP.", "effect": {"max_hp_pct": 2}},
			{"id": "sig_Paladin_3", "name": "Mercy", "desc": "Lay on Hands heals 5% more.", "effect": {"lay_on_hands_heal_pct": 5}},
			{"id": "sig_Paladin_4", "name": "Cleansing Hands", "desc": "Lay on Hands also cleanses your poison and bleed.", "effect": {"lay_on_hands_cleanse": true}},
			{"id": "sig_Paladin_5", "name": "Radiant Shield", "desc": "Shield of Faith also blocks 10% of damage for as long as it lasts.", "effect": {"shield_of_faith_dr_pct": 10}, "ranks": 1},
			{"id": "sig_Paladin_6", "name": "Verdict", "desc": "Judgement is 10% more likely to be simply lethal.", "effect": {"judgement_lethal_bonus": 10}, "ranks": 1},
		],
	},
	"Fighter": {
		"id": "signature", "name": "Drillmaster's Way", "color": "#C0C0C0",
		"nodes": [
			{"id": "sig_Fighter_1", "name": "Drilled Stance", "desc": "Your opening stance is 4% stronger. (It starts at half strength; this is where the rest is earned.)", "effect": {"stance_strength_pct": 4}},
			{"id": "sig_Fighter_2", "name": "Banked Momentum", "desc": "Begin every fight with +1 Momentum.", "effect": {"start_momentum": 1}, "ranks": 3},
			{"id": "sig_Fighter_3", "name": "Shield Wall", "desc": "Shield Bash adds 4% of your defense to its damage.", "effect": {"shield_bash_defense_pct": 4}},
			{"id": "sig_Fighter_4", "name": "Lasting Guard", "desc": "Bulwark lasts 2 rounds longer.", "effect": {"bulwark_duration_bonus": 2}, "ranks": 1},
			{"id": "sig_Fighter_5", "name": "Staggering Bash", "desc": "A Shield Bash that stuns builds an extra Momentum.", "effect": {"bash_stun_momentum": true}},
			{"id": "sig_Fighter_6", "name": "Aftershock", "desc": "Devastate leaves 2 Momentum behind instead of spending it all.", "effect": {"devastate_aftershock": 2}, "ranks": 1},
		],
	},
}


static func signature_nodes(class_type: String) -> Array:
	return SIGNATURES.get(class_type, {}).get("nodes", [])


static func max_rank(node: Dictionary) -> int:
	"""How many times a node can be bought. A node may name `ranks`; otherwise keystones, class keystones and
	anything with a duration/boolean/large amount are single-rank, and the small plain percent perks get
	PathPoints.DEFAULT_MAX_RANK. One rank is worth exactly what the node was worth before ranks existed, so
	nothing a character already bought changed."""
	if node.has("ranks"):
		return maxi(1, int(node["ranks"]))
	if bool(node.get("keystone", false)) or (String(node.get("class_lock", "")) != "" and not bool(node.get("signature", false))):
		return 1
	var fx: Dictionary = node.get("effect", {})
	if fx.is_empty():
		return 1
	for k in fx:
		var v = fx[k]
		if v is bool or String(k) in NON_SCALING_KEYS:
			return 1
		if (v is int or v is float) and absf(float(v)) > MAX_SCALABLE_AMOUNT:
			return 1
	return PathPointsScript.DEFAULT_MAX_RANK


static func rank_effect(node: Dictionary, rank: int) -> Dictionary:
	"""The node's effect dict at `rank`: scalable keys times rank, the rest unchanged."""
	var out: Dictionary = {}
	var fx: Dictionary = node.get("effect", {})
	for k in fx:
		var v = fx[k]
		if (v is int or v is float) and not (v is bool) and not (String(k) in NON_SCALING_KEYS):
			out[k] = v * maxi(1, rank)
		else:
			out[k] = v
	return out


static func branch_node_ids(archetype: String, branch_key: String) -> Array:
	"""Every node id in one branch (`branch_key` is the branch id, or "class" for the class keystone)."""
	var ids: Array = []
	var tree: Dictionary = TREES.get(archetype, {})
	if branch_key == "signature":
		for cls in SIGNATURES:
			for n in SIGNATURES[cls].get("nodes", []):
				ids.append(String(n.get("id", "")))
		return ids
	if branch_key == "class":
		for cls in tree.get("class_keystones", {}):
			ids.append(String(tree["class_keystones"][cls].get("id", "")))
		return ids
	for b in tree.get("branches", []):
		if String(b.get("id", "")) == branch_key:
			for n in b.get("nodes", []):
				ids.append(String(n.get("id", "")))
	return ids


static func get_archetype_tree(archetype: String) -> Dictionary:
	return TREES.get(archetype, {})


static func class_archetype(class_type: String) -> String:
	match class_type:
		"Fighter", "Barbarian", "Paladin":
			return "warrior"
		"Wizard", "Sorcerer", "Sage":
			return "mage"
		"Grifter", "Ranger", "Ninja":
			return "trickster"
	return ""


static func find_node(node_id: String) -> Dictionary:
	"""Locate any node (branch node or class keystone) by id. Returns {} when
	unknown. Result includes 'archetype', 'branch_index' (-1 for class
	keystones), 'tier' (1-5, 0 for class keystones), 'class_lock' ("" unless
	class keystone)."""
	if node_id.begins_with("sig_"):
		for cls in SIGNATURES:
			var sig_nodes: Array = SIGNATURES[cls].get("nodes", [])
			for i in range(sig_nodes.size()):
				if String(sig_nodes[i].get("id", "")) == node_id:
					var out_s: Dictionary = sig_nodes[i].duplicate()
					out_s["archetype"] = class_archetype(String(cls))
					out_s["branch_index"] = -2
					out_s["tier"] = i + 1
					out_s["class_lock"] = String(cls)
					out_s["signature"] = true
					return out_s
		return {}
	for archetype in TREES:
		var tree: Dictionary = TREES[archetype]
		var branches: Array = tree.get("branches", [])
		for b_idx in range(branches.size()):
			var nodes: Array = branches[b_idx].get("nodes", [])
			for t_idx in range(nodes.size()):
				var node: Dictionary = nodes[t_idx]
				if node.get("id", "") == node_id:
					var out: Dictionary = node.duplicate()
					out["archetype"] = archetype
					out["branch_index"] = b_idx
					out["tier"] = t_idx + 1
					out["class_lock"] = ""
					return out
		var keystones: Dictionary = tree.get("class_keystones", {})
		for cls in keystones:
			var ck: Dictionary = keystones[cls]
			if ck.get("id", "") == node_id:
				var out_ck: Dictionary = ck.duplicate()
				out_ck["archetype"] = archetype
				out_ck["branch_index"] = -1
				out_ck["tier"] = 0
				out_ck["class_lock"] = cls
				return out_ck
	return {}


static func get_prereq_id(node_id: String) -> String:
	"""Branch node tier N requires tier N-1 of the same branch. Tier-1 nodes
	and class keystones have no node prereq (class keystones gate on spend
	count + class instead)."""
	var node := find_node(node_id)
	if not node.is_empty() and int(node.get("branch_index", -1)) == -2:
		var s_tier: int = int(node.get("tier", 1))
		if s_tier <= 1:
			return ""
		return String(signature_nodes(String(node.get("class_lock", "")))[s_tier - 2].get("id", ""))
	if node.is_empty() or node.get("branch_index", -1) < 0:
		return ""
	var tier: int = int(node.get("tier", 1))
	if tier <= 1:
		return ""
	var branches: Array = TREES[node["archetype"]]["branches"]
	var nodes: Array = branches[node["branch_index"]]["nodes"]
	return String(nodes[tier - 2].get("id", ""))
