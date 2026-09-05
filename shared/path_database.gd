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
					{"id": "trickster_2_5", "name": "Phantom Strike", "desc": "KEYSTONE: Your first attack each combat always crits and cannot miss. Your max HP is reduced 10%.", "keystone": true, "effect": {"first_strike_autocrit": true, "max_hp_pct": -10}},
				],
			},
			{
				"id": "fortune", "name": "Fortune", "color": "#FFD700",
				"nodes": [
					{"id": "trickster_3_1", "name": "Deep Pockets", "desc": "+10% max energy.", "effect": {"max_resource_pct": 10}},
					{"id": "trickster_3_2", "name": "Lasting Tricks", "desc": "Your combat buffs last 2 extra rounds.", "effect": {"buff_duration_bonus": 2}},
					{"id": "trickster_3_3", "name": "Profiteer", "desc": "+15% Valor from kills.", "effect": {"valor_pct": 15}},
					{"id": "trickster_3_4", "name": "Silver Tongue", "desc": "+15% Outsmart success chance.", "effect": {"outsmart_pct": 15}},
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


static func get_archetype_tree(archetype: String) -> Dictionary:
	return TREES.get(archetype, {})


static func find_node(node_id: String) -> Dictionary:
	"""Locate any node (branch node or class keystone) by id. Returns {} when
	unknown. Result includes 'archetype', 'branch_index' (-1 for class
	keystones), 'tier' (1-5, 0 for class keystones), 'class_lock' ("" unless
	class keystone)."""
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
	if node.is_empty() or node.get("branch_index", -1) < 0:
		return ""
	var tier: int = int(node.get("tier", 1))
	if tier <= 1:
		return ""
	var branches: Array = TREES[node["archetype"]]["branches"]
	var nodes: Array = branches[node["branch_index"]]["nodes"]
	return String(nodes[tier - 2].get("id", ""))
