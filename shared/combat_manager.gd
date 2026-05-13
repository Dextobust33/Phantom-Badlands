# combat_manager.gd
# Handles turn-based combat in Phantasia 4 style
class_name CombatManager
extends Node

# Combat actions
enum CombatAction {
	ATTACK,
	FLEE,
	SPECIAL,
	OUTSMART,
	ABILITY
}

# Ability lookup for parsing commands
const MAGE_ABILITY_COMMANDS = ["magic_bolt", "bolt", "cloak", "blast", "forcefield", "teleport", "meteor", "haste", "paralyze", "banish"]
const WARRIOR_ABILITY_COMMANDS = ["power_strike", "strike", "war_cry", "warcry", "shield_bash", "bash", "cleave", "berserk", "iron_skin", "ironskin", "devastate", "fortify", "rally"]
const TRICKSTER_ABILITY_COMMANDS = ["analyze", "distract", "pickpocket", "ambush", "vanish", "exploit", "perfect_heist", "heist", "sabotage", "gambit"]
const UNIVERSAL_ABILITY_COMMANDS = ["all_or_nothing", "forethought", "tactical_retreat"]

# Mastery Slice 1 polish — only the first N uses of an ability per fight
# count toward rank progress. Stops grind-spam (e.g., 5-mana Magic Bolts
# repeated 30 times); bridges to deck-building's natural per-round draw
# limit when that lands.
const MASTERY_USES_PER_COMBAT_CAP: int = 5

# Audit #1 Slice 6a — deck/hand/draw runtime. Each combat builds a deck of
# the character's accessible combat abilities (1 copy each) and draws the
# top N into a hand. Players may only fire abilities that are currently in
# hand; using one moves it to discard and refills the hand. When the deck
# empties the discard reshuffles in. Standard actions (attack/item/flee/
# outsmart) bypass the hand entirely.
const COMBAT_HAND_SIZE: int = 3
# Stripped from the deck. Teleport is a guaranteed-flee non-combat utility.
# Cloak is a 75%-flee escape with a hard level-20 gate inside _process_universal_ability,
# which contradicts Slice 1's "all abilities accessible from L1" rule and would
# otherwise hand low-level players a card that always rejects on cast — confusing
# UX. If we re-enable it in a later slice we should drop the level gate too.
# All-or-nothing is too niche to draw — per user 2026-05-10 it lives on the R
# slot of the action bar instead, always available outside the deck.
const COMBAT_DECK_NON_COMBAT: Array = ["teleport", "cloak", "all_or_nothing"]

# Audit #1 variable-cost rework — floor + ceiling per ability. Spending the floor
# yields VARIABLE_COST_MIN_FRACTION of the full effect; spending the ceiling yields
# 100%. Linear scaling between. The "auto-spend max-affordable" UX means the player
# never has a dead card so long as they can afford the floor.
#
# Table format (v0.9.260+):
#   ceiling      — base ceiling cost
#   floor_ratio  — floor = max(1, int(ceiling * floor_ratio)). Default 0.3.
#   cost_percent — mage-only: ceiling = max(ceiling, max_mana * cost_percent / 100)
#                  so high-level mages still see scaling. Same shape used in the
#                  existing fixed-cost mage flow (_process_mage_ability).
#   resource     — "stamina" | "mana" | "energy"
#
# Pilot covered Warrior damage (v0.9.259). v0.9.260 extends to Mage damage.
# Subsequent slices add Warrior buffs / Mage CC / Trickster.
const VARIABLE_COST_MIN_FRACTION: float = 0.3
const VARIABLE_COST_TABLE: Dictionary = {
	"power_strike": {"ceiling": 10, "floor_ratio": 0.3, "resource": "stamina"},
	"shield_bash":  {"ceiling": 20, "floor_ratio": 0.3, "resource": "stamina"},
	"cleave":       {"ceiling": 30, "floor_ratio": 0.3, "resource": "stamina"},
	"devastate":    {"ceiling": 50, "floor_ratio": 0.3, "resource": "stamina"},
	"blast":        {"ceiling": 50, "cost_percent": 5, "floor_ratio": 0.3, "resource": "mana"},
	"meteor":       {"ceiling": 100, "cost_percent": 8, "floor_ratio": 0.3, "resource": "mana"},
	"ambush":       {"ceiling": 30, "floor_ratio": 0.3, "resource": "energy"},
	"exploit":      {"ceiling": 35, "floor_ratio": 0.3, "resource": "energy"},
	"gambit":       {"ceiling": 35, "floor_ratio": 0.3, "resource": "energy"},
	"forcefield":   {"ceiling": 20, "cost_percent": 2, "floor_ratio": 0.3, "resource": "mana"},
	# Warrior buffs (v0.9.263): magnitude scales with spend, duration unchanged.
	"war_cry":      {"ceiling": 15, "floor_ratio": 0.3, "resource": "stamina"},
	"fortify":      {"ceiling": 25, "floor_ratio": 0.3, "resource": "stamina"},
	"iron_skin":    {"ceiling": 35, "floor_ratio": 0.3, "resource": "stamina"},
	"rally":        {"ceiling": 35, "floor_ratio": 0.3, "resource": "stamina"},
	"berserk":      {"ceiling": 40, "floor_ratio": 0.3, "resource": "stamina"},
	# Mage CC (v0.9.264): haste = magnitude scaling, paralyze + banish = chance scaling.
	"haste":        {"ceiling": 35, "cost_percent": 3, "floor_ratio": 0.3, "resource": "mana"},
	"paralyze":     {"ceiling": 60, "cost_percent": 6, "floor_ratio": 0.3, "resource": "mana"},
	"banish":       {"ceiling": 80, "cost_percent": 10, "floor_ratio": 0.3, "resource": "mana"},
	# Trickster utility (v0.9.265): chance scaling for pickpocket + perfect_heist,
	# magnitude scaling for distract + sabotage. Analyze + Vanish stay fixed-cost
	# (binary mechanics — partial cast doesn't make sense).
	"distract":     {"ceiling": 15, "floor_ratio": 0.3, "resource": "energy"},
	"pickpocket":   {"ceiling": 20, "floor_ratio": 0.3, "resource": "energy"},
	"sabotage":     {"ceiling": 25, "floor_ratio": 0.3, "resource": "energy"},
	"perfect_heist":{"ceiling": 50, "floor_ratio": 0.3, "resource": "energy"},
}

# Active combats (peer_id -> combat_state)
var active_combats = {}

# Active party combats (leader_peer_id -> party_combat_state)
var active_party_combats = {}
# Reverse lookup for party combat (peer_id -> leader_peer_id)
var party_combat_membership = {}

# Pending buff expiration notifications (peer_id -> array of expired buffs)
var _pending_buff_expirations = {}

# Drop tables reference (set by server when initialized)
# Using Node type to avoid compile-time dependency on DropTables class
var drop_tables: Node = null

# Monster database reference (for class affinity helpers)
var monster_database: Node = null

# Titles reference for title item drops
const TitlesScript = preload("res://shared/titles.gd")

# Balance configuration (set by server)
var balance_config: Dictionary = {}

func set_balance_config(cfg: Dictionary):
	"""Set balance configuration from server"""
	balance_config = cfg
	print("Combat Manager: Balance config loaded")

# Monster ability constants (duplicated from MonsterDatabase for easy access)
const ABILITY_GLASS_CANNON = "glass_cannon"
const ABILITY_MULTI_STRIKE = "multi_strike"
const ABILITY_POISON = "poison"
const ABILITY_MANA_DRAIN = "mana_drain"
const ABILITY_STAMINA_DRAIN = "stamina_drain"
const ABILITY_ENERGY_DRAIN = "energy_drain"
const ABILITY_REGENERATION = "regeneration"
const ABILITY_DAMAGE_REFLECT = "damage_reflect"
const ABILITY_ETHEREAL = "ethereal"
const ABILITY_ARMORED = "armored"
const ABILITY_SUMMONER = "summoner"
const ABILITY_PACK_LEADER = "pack_leader"
const ABILITY_GOLD_HOARDER = "gold_hoarder"  # Legacy — no effect (gold removed)
const ABILITY_GEM_BEARER = "gem_bearer"
const ABILITY_CURSE = "curse"
const ABILITY_DISARM = "disarm"
const ABILITY_UNPREDICTABLE = "unpredictable"
const ABILITY_WISH_GRANTER = "wish_granter"
const ABILITY_DEATH_CURSE = "death_curse"
const ABILITY_BERSERKER = "berserker"
const ABILITY_COWARD = "coward"
const ABILITY_LIFE_STEAL = "life_steal"
const ABILITY_ENRAGE = "enrage"
const ABILITY_AMBUSHER = "ambusher"
const ABILITY_EASY_PREY = "easy_prey"
const ABILITY_THORNS = "thorns"
const ABILITY_WEAPON_MASTER = "weapon_master"    # Guaranteed weapon drop
const ABILITY_SHIELD_BEARER = "shield_bearer"    # Guaranteed shield drop
const ABILITY_CORROSIVE = "corrosive"            # Chance to damage player's equipment on hit
const ABILITY_SUNDER = "sunder"                  # Specifically damages weapons/shields
const ABILITY_BLIND = "blind"                    # Reduces player hit chance
const ABILITY_BLEED = "bleed"                    # Stacking bleed DoT on player
const ABILITY_SLOW_AURA = "slow_aura"            # Reduces player flee chance
const ABILITY_ARCANE_HOARDER = "arcane_hoarder"  # 35% chance to drop mage gear
const ABILITY_CUNNING_PREY = "cunning_prey"      # 35% chance to drop trickster gear
const ABILITY_WARRIOR_HOARDER = "warrior_hoarder"  # 35% chance to drop warrior gear
const ABILITY_WEAKNESS = "weakness"              # Applies -25% attack debuff for 20 rounds

# New abilities from Phantasia 5 inspiration
const ABILITY_CHARM = "charm"                    # Player attacks themselves for 1 turn
const ABILITY_BUFF_DESTROY = "buff_destroy"      # Removes one random active buff
const ABILITY_SHIELD_SHATTER = "shield_shatter"  # Destroys forcefield/shield buffs instantly
const ABILITY_FLEE_ATTACK = "flee_attack"        # Deals damage then flees (no loot)
const ABILITY_DISGUISE = "disguise"              # Appears as weaker monster, reveals after 2 rounds
const ABILITY_XP_STEAL = "xp_steal"              # Steals 1-3% of player XP on hit (rare, punishing)
const ABILITY_ITEM_STEAL = "item_steal"          # 5% chance to steal random equipped item

# Audit #5 — Boss signature mechanics. Each boss should have ONE distinct
# mechanic not in its base monster pool. These are wired to flavor names like
# "Death Defiance" / "Constricting Web" via boss_ability_map in server.gd.
const ABILITY_BOSS_REVIVE_ONCE = "boss_revive_once"  # When boss dies, revives at 50% HP exactly once per fight
const ABILITY_BOSS_WEB_STUN = "boss_web_stun"        # On hit, chance to web the player (skips next player turn)
const ABILITY_BOSS_BLOODIED_FURY = "boss_bloodied_fury"  # When boss <30% HP, one-shot trigger: +75% damage rest of fight
const ABILITY_BOSS_TREASURE_DECOY = "boss_treasure_decoy"  # First monster attack guaranteed crit at 2x damage
const ABILITY_BOSS_BLOODSCENT = "boss_bloodscent"        # When player <50% HP, boss gains +50% damage rest of fight (one-shot trigger)
const ABILITY_BOSS_FESTERING_BITE = "boss_festering_bite"  # Each monster hit adds +1 festering stack (max 5); ticks 2% max HP per stack per player turn
const ABILITY_BOSS_IRON_DISCIPLINE = "boss_iron_discipline"  # Every 5 monster turns, boss heals 10% max HP and clears its own debuffs
const ABILITY_BOSS_SOUL_SIPHON = "boss_soul_siphon"        # Every 3 monster turns, drains 8% of player max HP and heals boss for same — vampiric burst, distinct from passive life_steal
const ABILITY_BOSS_PACK_FRENZY = "boss_pack_frenzy"        # Boss attack scales +5% per round, uncapped escalating. Rewards fast kills, punishes long fights
const ABILITY_BOSS_CONTAGION_AURA = "boss_contagion_aura"  # Passive: +1 contagion stack every 2 monster turns (cap 5); each stack ticks 1% player max HP at start of player turn. No hit required, distinct from on-hit Festering Bite
const ABILITY_BOSS_LULLABY = "boss_lullaby"                # Every 4 monster turns, forces player to skip next turn (timer-based, deterministic — distinct from Web Stun's on-hit chance)
const ABILITY_BOSS_DROWNING = "boss_drowning"              # On hit, +1 drowning stack (cap 3). Each stack ticks 2% player max HP per turn AND reduces player damage by 10%. Combines DoT + offensive debuff — only signature that does both
# Audit #5 boss signatures (Slice 8 — T3 layer)
const ABILITY_BOSS_TROLL_REGROWTH = "boss_troll_regrowth"  # When boss <50% HP, heals 8% max HP at start of each monster turn. Threshold-triggered, distinct from passive regeneration
const ABILITY_BOSS_AERIAL_DIVE = "boss_aerial_dive"        # Every 4 monster turns, deals 12% player max HP damage (telegraphed). Cyclical burst — distinct from on-hit DoTs
const ABILITY_BOSS_CONCUSSIVE_SLAM = "boss_concussive_slam"  # Each successful hit also strips 1 active player buff (rage/stone_skin/haste/etc). Counter to buff stacking
const ABILITY_BOSS_PHASE_MIRROR = "boss_phase_mirror"      # 25% of incoming damage reflected back to player. Punishes hard hitters — softer attacks net better DPS
const ABILITY_BOSS_LABYRINTH_CHARGE = "boss_labyrinth_charge"  # Every 5 monster turns, charges for (round × 3%) max player HP burst damage. Time-scaled burst, distinct from Pack Frenzy's steady ramp
const ABILITY_BOSS_STONEFORM = "boss_stoneform"            # On even-numbered monster rounds (2,4,6...), incoming damage reduced 70%. Players must burst on odd rounds
const ABILITY_BOSS_WIND_SHEAR = "boss_wind_shear"          # Every 3 monster turns, player damage reduced 50% for next round only. Periodic offensive debuff
const ABILITY_BOSS_SONIC_ECHO = "boss_sonic_echo"          # Each monster turn adds +1 echo stack; at 4 stacks, deals 15% max HP burst then resets to 0. Cyclical 4-turn rhythm
# Audit #5 boss signatures (Slice 9 — T4 layer)
const ABILITY_BOSS_TREMOR_STOMP = "boss_tremor_stomp"      # Every 3 monster turns, deals 10% max HP and forces player to skip next turn. Burst + stun combo
const ABILITY_BOSS_BLOOD_FRENZY = "boss_blood_frenzy"      # Vampire heals 30% of damage dealt back as HP (distinct from generic life_steal which is per-hit fixed %)
const ABILITY_BOSS_HATCHLING_SWARM = "boss_hatchling_swarm"  # Every 4 monster turns, 15% player max HP burst (no spawn — already-hatched swarmlings just hit you)
const ABILITY_BOSS_INFERNAL_CURSE = "boss_infernal_curse"  # Each monster turn +1 curse stack; at 5 stacks deals 25% max HP burst and resets to 0. Stacking burst that's faster than Sonic Echo
const ABILITY_BOSS_TALON_BARRAGE = "boss_talon_barrage"    # On-hit, 30% chance for +2 bonus attacks at 50% damage each. Distinct from multi_strike (fixed multiplier, not chance-based)
const ABILITY_BOSS_TRIPLE_THREAT = "boss_triple_threat"    # Cycles poison/burn/slow per round (round % 3 == 0/1/2). Each cycle applies its debuff to the player. Distinct from any single debuff signature
const ABILITY_BOSS_BUILDING_CHARM = "boss_building_charm"  # On-hit, +1 charm stack (cap 3); at 3 stacks the player auto-attacks themselves for 50% damage NEXT player turn, then resets to 0. Cyclical charm-burst
# Audit #5 boss signatures (Slice 10 — T5 layer)
const ABILITY_BOSS_SOUL_BURN = "boss_soul_burn"            # On-hit, drains 5% of player primary resource max (mana/stamina/energy by class). Resource pressure — distinct from HP DoTs
const ABILITY_BOSS_THREE_HEADS = "boss_three_heads"        # Each monster turn, 4% player max HP damage that ignores DEF (gnaws through gear). Steady chip
const ABILITY_BOSS_HELLFIRE_STACK = "boss_hellfire_stack"  # On-hit, first deals (current_stacks × 4% max HP), then +1 stack (cap 5). Damage from PRIOR stacks fires on each hit — pressure builds across the fight, distinct from Festering (player-turn tick)
const ABILITY_BOSS_SOUL_FORGE = "boss_soul_forge"          # Every 5 monster turns, heals 15% max HP. Bigger than Trollish Regrowth (8%) and distinct from Iron Discipline (heal + clears debuffs). Pure heal cycle
const ABILITY_BOSS_TITAN_EARTHQUAKE = "boss_titan_earthquake"  # Every 4 monster turns, 8% max HP damage + permanently +1 earthquake stack (cap 5). Each stack reduces incoming player damage by 10%. Distinct from Stoneform (binary alt-round) — escalating persistent defense
const ABILITY_BOSS_VORPAL_STRIKE = "boss_vorpal_strike"    # Every 4 monster turns, the boss's normal attack deals 3x damage. Telegraphed, infrequent, single-moment burst
# Audit #5 boss signatures (Slice 11 — T6 layer)
const ABILITY_BOSS_DRAGONS_HOARD = "boss_dragons_hoard"    # Every 5 monster turns, strips one active player buff AND gains a permanent +5% damage stack. Long-fight punisher
const ABILITY_BOSS_HYDRA_REGEN = "boss_hydra_regen"        # When player deals > 10% boss max HP in a single attack, boss heals 10% max HP. Anti-burst — distinct from threshold heals
const ABILITY_BOSS_PHOENIX_REBIRTH = "boss_phoenix_rebirth"  # When boss dies, revives at 75% HP exactly once per fight. Stronger than Skeleton Lord's Death Defiance (50%)
const ABILITY_BOSS_ELEMENT_CYCLE = "boss_element_cycle"    # 4-phase rotation per round: fire (5% burn) → water (5% resource drain) → earth (next-round wind shear) → air (skip turn). Distinct from Triple Threat (3 heads)
const ABILITY_BOSS_FORGE_HEAT = "boss_forge_heat"          # On-hit, +1 heat stack; at 5 stacks deals 10% player max HP burst and resets. Threshold burst — distinct from Hellfire Stack's compounding per-hit
const ABILITY_BOSS_RIDDLE_CURSE = "boss_riddle_curse"      # Every 3 monster turns, +1 riddle stack (cap 5); each stack reduces player damage by 5%. Persistent stacking debuff — distinct from Wind Shear (one-round) and Drowning (on-hit, smaller cap)
const ABILITY_BOSS_SOUL_TOUCH = "boss_soul_touch"          # On-hit, +1 soul stack (uncapped); each stack reduces player effective defense by 2% (compounding). Distinct from any other debuff — attacks DEFENSE stat, not damage
# Audit #5 boss signatures (Slice 12 — T7 layer)
const ABILITY_BOSS_VOID_STEP = "boss_void_step"            # Every 3 monster turns, boss phases out; next player attack deals 0 damage (intangible). Anti-burst by negating one strike
const ABILITY_BOSS_PRIMORDIAL_ROAR = "boss_primordial_roar"  # Every 5 monster turns, deals 20% player max HP AND strips ALL active player buffs. Single-moment apocalypse
const ABILITY_BOSS_COIL_SQUEEZE = "boss_coil_squeeze"      # Each monster turn +1 coil stack (cap 10); each stack ticks 1% player max HP at start of player turn. Fastest-filling stacking DoT
const ABILITY_BOSS_DEATH_MARK = "boss_death_mark"          # On first successful hit, applies permanent Death Mark. While marked, every 3 monster turns deals 8% player max HP. One-shot apply, persistent timer
# Audit #5 boss signatures (Slice 12 — T8 layer)
const ABILITY_BOSS_MADNESS_AURA = "boss_madness_aura"      # Every 4 monster turns, sets madness flag for the player's next 2 turns. While maddened, each player action has 30% chance to fizzle (waste action)
const ABILITY_BOSS_TEMPORAL_REWIND = "boss_temporal_rewind"  # Every 6 monster turns, heals 25% max HP AND clears its own debuffs. Slower rhythm than Iron Discipline but bigger heal
const ABILITY_BOSS_REAPERS_TOUCH = "boss_reapers_touch"    # On-hit, 15% chance to apply soul mark; at start of NEXT player turn, marked players lose 15% max HP. Per-hit chance with fixed payload
# Audit #5 boss signatures (Slice 12 — T9 layer)
const ABILITY_BOSS_CHAOTIC_SURGE = "boss_chaotic_surge"    # Each monster turn picks a RANDOM effect from 6: heal 10% / 10% max HP dmg / strip buff / skip player turn / +50% next monster dmg / -50% next monster dmg. True chaos
const ABILITY_BOSS_UNKNOWABLE = "boss_unknowable"          # Each player attack has 25% chance to be "forgotten" — damage doesn't apply, no message. Anti-pattern, distinct from dodge (which announces)
const ABILITY_BOSS_DIVINE_PUNISHMENT = "boss_divine_punishment"  # Every 4 monster turns, deals damage equal to (player_level × 5%) max HP. Scales with player power — anti-high-level
const ABILITY_BOSS_DECAY = "boss_decay"                    # Each player turn START, +1 decay stack (uncapped); each stack ticks 2% player max HP at start of player turn. Self-decay — existing in the fight costs HP

func get_monster_combat_bg_color(monster_name: String) -> String:
	"""Get the contrasting background color for a monster's combat screen"""
	var raw_art_array = _get_raw_monster_ascii_art(monster_name)
	var art_color = _extract_art_color(raw_art_array)
	return _get_contrasting_bg_color(art_color)

func get_flock_varied_colors(monster_name: String, flock_count: int) -> Dictionary:
	"""Get varied art and background colors for flock encounters to add visual variety"""
	# Use distinct color palette for big, noticeable changes between flock members
	var color_palette = [
		"#00FF00",  # Green
		"#00BFFF",  # Deep Sky Blue
		"#FF4500",  # Orange Red
		"#FFD700",  # Gold
		"#FF00FF",  # Magenta
		"#00FFFF",  # Cyan
		"#FF6347",  # Tomato
		"#ADFF2F",  # Green Yellow
		"#DA70D6",  # Orchid
		"#7FFF00",  # Chartreuse
		"#FF1493",  # Deep Pink
		"#1E90FF",  # Dodger Blue
	]

	# Pick color based on flock count to ensure each pack member looks different
	var varied_art_color = color_palette[flock_count % color_palette.size()]
	# Use contrasting background for the varied art color
	var varied_bg_color = _get_contrasting_bg_color(varied_art_color)

	return {
		"art_color": varied_art_color,
		"bg_color": varied_bg_color
	}

func get_random_varied_colors(monster_name: String) -> Dictionary:
	"""Get randomly varied art and background colors for visual variety on any encounter"""
	# Use distinct color palette for big, noticeable changes
	var color_palette = [
		"#00FF00",  # Green
		"#00BFFF",  # Deep Sky Blue
		"#FF4500",  # Orange Red
		"#FFD700",  # Gold
		"#FF00FF",  # Magenta
		"#00FFFF",  # Cyan
		"#FF6347",  # Tomato
		"#ADFF2F",  # Green Yellow
		"#DA70D6",  # Orchid
		"#7FFF00",  # Chartreuse
		"#FF1493",  # Deep Pink
		"#1E90FF",  # Dodger Blue
	]

	# Pick a random color from the palette
	var varied_art_color = color_palette[randi() % color_palette.size()]
	var varied_bg_color = _get_contrasting_bg_color(varied_art_color)

	return {
		"art_color": varied_art_color,
		"bg_color": varied_bg_color
	}

func _shift_color_hue(hex_color: String, degrees: int) -> String:
	"""Shift the hue of a hex color by the specified degrees (0-360)"""
	if not hex_color.begins_with("#") or hex_color.length() < 7:
		return hex_color

	var r = hex_color.substr(1, 2).hex_to_int() / 255.0
	var g = hex_color.substr(3, 2).hex_to_int() / 255.0
	var b = hex_color.substr(5, 2).hex_to_int() / 255.0

	# Convert RGB to HSV
	var max_c = max(r, max(g, b))
	var min_c = min(r, min(g, b))
	var delta = max_c - min_c

	var h = 0.0
	var s = 0.0 if max_c == 0 else delta / max_c
	var v = max_c

	if delta > 0:
		if max_c == r:
			h = 60.0 * fmod((g - b) / delta, 6.0)
		elif max_c == g:
			h = 60.0 * ((b - r) / delta + 2.0)
		else:
			h = 60.0 * ((r - g) / delta + 4.0)

	if h < 0:
		h += 360.0

	# Shift hue
	h = fmod(h + degrees, 360.0)

	# Convert HSV back to RGB
	var c = v * s
	var x = c * (1.0 - abs(fmod(h / 60.0, 2.0) - 1.0))
	var m = v - c

	var r2 = 0.0
	var g2 = 0.0
	var b2 = 0.0

	if h < 60:
		r2 = c; g2 = x; b2 = 0
	elif h < 120:
		r2 = x; g2 = c; b2 = 0
	elif h < 180:
		r2 = 0; g2 = c; b2 = x
	elif h < 240:
		r2 = 0; g2 = x; b2 = c
	elif h < 300:
		r2 = x; g2 = 0; b2 = c
	else:
		r2 = c; g2 = 0; b2 = x

	var new_r = int((r2 + m) * 255)
	var new_g = int((g2 + m) * 255)
	var new_b = int((b2 + m) * 255)

	return "#%02X%02X%02X" % [new_r, new_g, new_b]

func _get_contrasting_bg_color(art_color: String) -> String:
	"""Generate a dark complementary background for high contrast with art color"""
	# Parse the hex color (format: #RRGGBB)
	if not art_color.begins_with("#") or art_color.length() < 7:
		return "#0A0A0A"  # Default near-black

	var r = art_color.substr(1, 2).hex_to_int()
	var g = art_color.substr(3, 2).hex_to_int()
	var b = art_color.substr(5, 2).hex_to_int()

	# Use complementary color (opposite on color wheel) at low brightness
	# Invert the color then darken it significantly
	var inv_r = 255 - r
	var inv_g = 255 - g
	var inv_b = 255 - b

	# Dark version of complementary (20% brightness)
	var bg_r = int(inv_r * 0.15) + 5
	var bg_g = int(inv_g * 0.15) + 5
	var bg_b = int(inv_b * 0.15) + 5

	# Keep it dark but visible
	bg_r = min(bg_r, 50)
	bg_g = min(bg_g, 50)
	bg_b = min(bg_b, 50)

	return "#%02X%02X%02X" % [bg_r, bg_g, bg_b]

func _extract_art_color(art_array: Array) -> String:
	"""Extract the color hex code from an ASCII art array"""
	if art_array.size() == 0:
		return "#FFFFFF"

	var first_element = art_array[0]
	if first_element.begins_with("[color="):
		# Extract color from [color=#HEXCODE]
		var start = first_element.find("#")
		var end = first_element.find("]")
		if start != -1 and end != -1:
			return first_element.substr(start, end - start)

	return "#FFFFFF"  # Default white

func apply_damage_variance(base_damage: int) -> int:
	"""Apply Â±15% variance to damage to make combat less predictable"""
	# Variance range: 0.85 to 1.15 (Â±15%)
	var variance = 0.85 + (randf() * 0.30)
	return max(1, int(base_damage * variance))

func apply_ability_damage_modifiers(damage: int, char_level: int, monster: Dictionary) -> int:
	"""Apply 50% defense and level penalty to ability damage"""
	var mod_damage = damage
	var mon_def = monster.get("defense", 0)
	var def_ratio = float(mon_def) / (float(mon_def) + 100.0)
	var partial_red = (def_ratio * 0.6) * 0.5
	mod_damage = int(mod_damage * (1.0 - partial_red))
	var mon_level = monster.get("level", 1)
	var lvl_diff = mon_level - char_level
	if lvl_diff > 0:
		var lvl_penalty = min(0.40, lvl_diff * 0.015)
		mod_damage = int(mod_damage * (1.0 - lvl_penalty))
	return max(1, mod_damage)

func set_monster_database(db: Node):
	"""Set the monster database reference"""
	monster_database = db

func _process_status_ticks(character: Character, messages: Array) -> void:
	"""Process poison and blind ticks at the start of a player's turn.
	Called by all player combat actions."""
	# === POISON TICK ===
	if character.poison_active:
		var poison_dmg = character.tick_poison()
		if poison_dmg > 0:
			character.current_hp -= poison_dmg
			character.current_hp = max(1, character.current_hp)  # Poison can't kill
			var turns_left = character.poison_turns_remaining
			if turns_left > 0:
				messages.append("[color=#FF00FF]Poison deals %d damage! (%d turns remaining)[/color]" % [poison_dmg, turns_left])
			else:
				messages.append("[color=#FF00FF]Poison deals %d damage! The poison fades.[/color]" % poison_dmg)

	# === BLIND TICK ===
	if character.blind_active:
		var still_blind = character.tick_blind()
		if still_blind:
			messages.append("[color=#808080]You are blinded! (%d turns remaining)[/color]" % character.blind_turns_remaining)
		else:
			messages.append("[color=#00FF00]Your vision clears![/color]")

func _apply_gear_resource_regen(character: Character, messages: Array) -> void:
	"""Apply equipment-based and buff-based resource regeneration at start of player turn.
	Called by both regular attacks and ability usage."""
	var bonuses = character.get_equipment_bonuses()

	# Combine gear mana_regen with buff mana_regen (from crafted consumables like Enchanted Kindling)
	var mana_regen = bonuses.get("mana_regen", 0) + character.get_buff_value("mana_regen")
	if mana_regen > 0 and character.current_mana < character.get_total_max_mana():
		var old_mana = character.current_mana
		character.current_mana = mini(character.get_total_max_mana(), character.current_mana + mana_regen)
		var actual_regen = character.current_mana - old_mana
		if actual_regen > 0:
			if bonuses.get("mana_regen", 0) > 0 and character.get_buff_value("mana_regen") > 0:
				messages.append("[color=#66CCFF]Arcane power restores %d mana.[/color]" % actual_regen)
			elif character.get_buff_value("mana_regen") > 0:
				messages.append("[color=#66CCFF]Enchantment restores %d mana.[/color]" % actual_regen)
			else:
				messages.append("[color=#66CCFF]Arcane gear restores %d mana.[/color]" % actual_regen)

	# Combine gear energy_regen with buff energy_regen
	var energy_regen = bonuses.get("energy_regen", 0) + character.get_buff_value("energy_regen")
	if energy_regen > 0 and character.current_energy < character.get_total_max_energy():
		var old_energy = character.current_energy
		character.current_energy = mini(character.get_total_max_energy(), character.current_energy + energy_regen)
		var actual_regen = character.current_energy - old_energy
		if actual_regen > 0:
			if character.get_buff_value("energy_regen") > 0:
				messages.append("[color=#66FF66]Enchantment restores %d energy.[/color]" % actual_regen)
			else:
				messages.append("[color=#66FF66]Shadow gear restores %d energy.[/color]" % actual_regen)

	# Combine gear stamina_regen with buff stamina_regen
	var stamina_regen = bonuses.get("stamina_regen", 0) + character.get_buff_value("stamina_regen")
	if stamina_regen > 0 and character.current_stamina < character.get_total_max_stamina():
		var old_stam = character.current_stamina
		character.current_stamina = mini(character.get_total_max_stamina(), character.current_stamina + stamina_regen)
		var actual_regen = character.current_stamina - old_stam
		if actual_regen > 0:
			if character.get_buff_value("stamina_regen") > 0:
				messages.append("[color=#FF6600]Enchantment restores %d stamina.[/color]" % actual_regen)
			else:
				messages.append("[color=#FF6600]Warlord gear restores %d stamina.[/color]" % actual_regen)

func _apply_companion_resource_regen(combat: Dictionary, character: Character, messages: Array) -> void:
	"""Apply companion passive resource regeneration each turn.
	All resource regen (mana/stamina/energy) is pooled and applied to the player's primary resource."""
	var companion = character.get_active_companion() if character.has_active_companion() else null
	if companion == null:
		return

	# HP Regen from companion (all classes have HP)
	var hp_regen = combat.get("companion_hp_regen", 0)
	hp_regen += int(character.get_companion_bonus("hp_regen"))
	if hp_regen > 0 and character.current_hp < character.get_total_max_hp():
		var heal_amount = max(1, int(character.get_total_max_hp() * hp_regen / 100.0))
		var old_hp = character.current_hp
		character.current_hp = min(character.get_total_max_hp(), character.current_hp + heal_amount)
		var actual_heal = character.current_hp - old_hp
		if actual_heal > 0:
			messages.append("[color=#00FFFF]%s's presence heals you for %d HP.[/color]" % [companion.name, actual_heal])

	# Resource Regen: Pool ALL types (mana/stamina/energy) and apply to player's primary resource
	var resource_regen = 0
	resource_regen += combat.get("companion_mana_regen", 0)
	resource_regen += combat.get("companion_energy_regen", 0)
	resource_regen += combat.get("companion_stamina_regen", 0)
	resource_regen += int(character.get_companion_bonus("mana_regen"))
	resource_regen += int(character.get_companion_bonus("energy_regen"))
	resource_regen += int(character.get_companion_bonus("stamina_regen"))

	if resource_regen > 0:
		var regen_amount = max(1, resource_regen)
		var class_path = character.get_class_path()
		match class_path:
			"warrior":
				if character.current_stamina < character.get_total_max_stamina():
					var old_val = character.current_stamina
					character.current_stamina = min(character.get_total_max_stamina(), character.current_stamina + regen_amount)
					var actual_regen = character.current_stamina - old_val
					if actual_regen > 0:
						messages.append("[color=#00FFFF]%s restores %d stamina.[/color]" % [companion.name, actual_regen])
			"mage":
				if character.current_mana < character.get_total_max_mana():
					var old_val = character.current_mana
					character.current_mana = min(character.get_total_max_mana(), character.current_mana + regen_amount)
					var actual_regen = character.current_mana - old_val
					if actual_regen > 0:
						messages.append("[color=#00FFFF]%s restores %d mana.[/color]" % [companion.name, actual_regen])
			"trickster":
				if character.current_energy < character.get_total_max_energy():
					var old_val = character.current_energy
					character.current_energy = min(character.get_total_max_energy(), character.current_energy + regen_amount)
					var actual_regen = character.current_energy - old_val
					if actual_regen > 0:
						messages.append("[color=#00FFFF]%s restores %d energy.[/color]" % [companion.name, actual_regen])

func _process_monster_dots(combat: Dictionary, monster: Dictionary, messages: Array) -> void:
	"""Process companion DoT effects on the monster (poison only - bleed is handled in monster turn)."""

	# Poison damage
	var poison_damage = combat.get("monster_poison", 0)
	var poison_duration = combat.get("monster_poison_duration", 0)
	if poison_damage > 0 and poison_duration > 0:
		monster.current_hp -= poison_damage
		monster.current_hp = max(0, monster.current_hp)
		messages.append("[color=#00FF00]Poison deals %d damage to the %s![/color]" % [poison_damage, monster.name])
		combat["monster_poison_duration"] = poison_duration - 1
		if combat["monster_poison_duration"] <= 0:
			combat["monster_poison"] = 0

	# Decrement weakness duration
	var weakness_duration = combat.get("monster_weakness_duration", 0)
	if weakness_duration > 0:
		combat["monster_weakness_duration"] = weakness_duration - 1
		if combat["monster_weakness_duration"] <= 0:
			combat["monster_weakness"] = 0

	# Decrement slow duration
	var slow_duration = combat.get("monster_slow_duration", 0)
	if slow_duration > 0:
		combat["monster_slow_duration"] = slow_duration - 1
		if combat["monster_slow_duration"] <= 0:
			combat["monster_slowed"] = 0

func _apply_companion_passive_effect(combat_state: Dictionary, character: Character, effect: String, value: int) -> void:
	"""Apply a single companion passive effect to combat state or character."""
	match effect:
		"attack":
			combat_state["companion_attack_bonus"] = combat_state.get("companion_attack_bonus", 0) + value
		"defense":
			combat_state["companion_defense_bonus"] = combat_state.get("companion_defense_bonus", 0) + value
		"speed":
			combat_state["companion_speed_bonus"] = combat_state.get("companion_speed_bonus", 0) + value
		"crit_chance":
			combat_state["companion_crit_bonus"] = combat_state.get("companion_crit_bonus", 0) + value
		"lifesteal":
			combat_state["companion_lifesteal_bonus"] = combat_state.get("companion_lifesteal_bonus", 0) + value
		"hp_bonus":
			# Increase max HP for this combat (applied as temporary buff)
			combat_state["companion_hp_bonus"] = combat_state.get("companion_hp_bonus", 0) + value
		"mana_bonus":
			combat_state["companion_mana_bonus"] = combat_state.get("companion_mana_bonus", 0) + value
		"hp_regen":
			combat_state["companion_hp_regen"] = combat_state.get("companion_hp_regen", 0) + value
		"mana_regen":
			combat_state["companion_mana_regen"] = combat_state.get("companion_mana_regen", 0) + value
		"energy_regen":
			combat_state["companion_energy_regen"] = combat_state.get("companion_energy_regen", 0) + value
		"stamina_regen":
			combat_state["companion_stamina_regen"] = combat_state.get("companion_stamina_regen", 0) + value
		"gathering_bonus":
			combat_state["companion_gathering_bonus"] = combat_state.get("companion_gathering_bonus", 0) + value
		"flee_bonus":
			combat_state["companion_flee_bonus"] = combat_state.get("companion_flee_bonus", 0) + value
		"crit_damage":
			combat_state["companion_crit_damage"] = combat_state.get("companion_crit_damage", 0) + value
		"wisdom_bonus":
			combat_state["companion_wisdom_bonus"] = combat_state.get("companion_wisdom_bonus", 0) + value

func _process_companion_attack(combat: Dictionary, messages: Array) -> void:
	"""Process companion attack during player's turn.
	Called by both regular attacks and ability usage."""
	var character = combat.character
	var monster = combat.monster

	if monster.current_hp <= 0:
		return

	if not character.has_active_companion():
		return

	# Phase B1 — KO companions skip their turn (they're at 0 combat HP and
	# need to be healed at a healer NPC / station before they can fight).
	if character.is_companion_ko():
		return

	var companion = character.get_active_companion()
	var companion_tier = companion.get("tier", 1)
	var companion_level = companion.get("level", 1)
	var companion_bonuses = companion.get("bonuses", {})
	var companion_sub_tier = companion.get("sub_tier", 1)

	# 95% hit chance for companions
	if randi() % 100 >= 95:
		messages.append("[color=#00FFFF]Your %s lunges but misses![/color]" % companion.get("name", "companion"))
		return

	# Calculate companion damage (now scales with companion level and sub-tier)
	var companion_damage = 0
	if drop_tables:
		companion_damage = drop_tables.get_companion_attack_damage(companion_tier, character.level, companion_bonuses, companion_level, companion_sub_tier)
	else:
		# Fallback formula matching drop_tables
		companion_damage = companion_tier * 5 + int(character.level * 0.3) + int(companion_level * 0.5)

	# Apply variant multiplier
	var variant_mult = character.get_variant_stat_multiplier()
	companion_damage = int(companion_damage * variant_mult)

	# Apply some variance (80-120%)
	companion_damage = int(companion_damage * randf_range(0.8, 1.2))
	companion_damage = max(1, companion_damage)
	monster.current_hp -= companion_damage
	monster.current_hp = max(0, monster.current_hp)
	messages.append("[color=#00FFFF]Your %s attacks for %d damage![/color]" % [companion.name, companion_damage])

	# === COMPANION CHANCE ABILITIES ===
	# Use monster-specific abilities stored at combat start (pre-scaled by level + variant)
	var comp_abilities = combat.get("companion_abilities", {})
	if not comp_abilities.is_empty() and not comp_abilities.get("active", {}).is_empty() and monster.current_hp > 0:
		var ability = comp_abilities.active
		var trigger_chance = ability.get("chance", 0)
		if randi() % 100 < trigger_chance:
			var effect = ability.get("effect", "")
			var ability_name = ability.get("name", "ability")
			var ability_damage_dealt = 0  # Track damage for lifesteal calc
			if effect == "enemy_miss":
				combat["companion_distraction"] = true
				messages.append("[color=#FFAA00]%s's %s distracts the enemy![/color]" % [companion.name, ability_name])
			elif effect == "bonus_damage":
				var bonus_value = ability.get("damage", ability.get("value", 10))
				monster.current_hp -= bonus_value
				monster.current_hp = max(0, monster.current_hp)
				ability_damage_dealt = bonus_value
				messages.append("[color=#FFAA00]%s uses %s for %d bonus damage![/color]" % [companion.name, ability_name, bonus_value])
			elif effect == "stun":
				combat["monster_stunned"] = 1
				messages.append("[color=#FFAA00]%s's attack stuns the %s![/color]" % [companion.name, monster.name])
			elif effect == "crit":
				# Critical strike ability - crit_mult not level-scaled, variant already in companion_damage
				var crit_mult = ability.get("crit_mult", 1.5)
				var crit_damage = int(companion_damage * (crit_mult - 1.0))
				monster.current_hp -= crit_damage
				monster.current_hp = max(0, monster.current_hp)
				ability_damage_dealt = companion_damage + crit_damage
				messages.append("[color=#FFD700]%s lands a critical %s for %d bonus damage![/color]" % [companion.name, ability_name, crit_damage])
			elif effect == "bleed":
				# Apply bleed DoT to monster (damage is pre-scaled)
				var bleed_damage = ability.get("damage", ability.get("base_damage", 5))
				var bleed_duration = ability.get("duration", 3)
				combat["monster_bleed"] = combat.get("monster_bleed", 0) + bleed_damage
				combat["monster_bleed_duration"] = max(combat.get("monster_bleed_duration", 0), bleed_duration)
				messages.append("[color=#FF4444]%s's %s causes bleeding! (%d damage/turn)[/color]" % [companion.name, ability_name, bleed_damage])
			elif effect == "poison":
				# Apply poison DoT to monster (damage is pre-scaled)
				var poison_damage = ability.get("damage", ability.get("base_damage", 5))
				var poison_duration = ability.get("duration", 3)
				combat["monster_poison"] = combat.get("monster_poison", 0) + poison_damage
				combat["monster_poison_duration"] = max(combat.get("monster_poison_duration", 0), poison_duration)
				messages.append("[color=#00FF00]%s's %s poisons the enemy! (%d damage/turn)[/color]" % [companion.name, ability_name, poison_damage])
			elif effect == "charm":
				# Monster skips its turn
				var charm_duration = ability.get("duration", 1)
				combat["monster_charmed"] = charm_duration
				messages.append("[color=#FF69B4]%s's %s charms the %s! (Skips %d turn(s))[/color]" % [companion.name, ability_name, monster.name, charm_duration])
			elif effect == "multi_hit":
				# Multiple hits (damage is pre-scaled)
				var num_hits = ability.get("hits", 3)
				var hit_damage = ability.get("damage", ability.get("base_damage", 5))
				var total_multi_damage = hit_damage * num_hits
				monster.current_hp -= total_multi_damage
				monster.current_hp = max(0, monster.current_hp)
				ability_damage_dealt = total_multi_damage
				messages.append("[color=#FFAA00]%s uses %s! %d hits for %d total damage![/color]" % [companion.name, ability_name, num_hits, total_multi_damage])
			elif effect == "mana_drain":
				# Drain mana from monster (reduces magic effectiveness)
				var drain_amount = ability.get("base_amount", 10)
				combat["monster_mana_drained"] = combat.get("monster_mana_drained", 0) + drain_amount
				messages.append("[color=#9966FF]%s's %s drains the enemy's magical power![/color]" % [companion.name, ability_name])
			elif effect == "weakness":
				# Reduce monster's attack (value is pre-scaled)
				var weakness_value = ability.get("value", ability.get("base_reduction", 15))
				var weakness_duration = ability.get("duration", 3)
				combat["monster_weakness"] = weakness_value
				combat["monster_weakness_duration"] = weakness_duration
				messages.append("[color=#808080]%s's %s weakens the %s! (-%d%% attack for %d turns)[/color]" % [companion.name, ability_name, monster.name, weakness_value, weakness_duration])
			elif effect == "execute":
				# Execute enemies below threshold
				var execute_threshold = ability.get("execute_threshold", 20) / 100.0
				var monster_hp_pct = float(monster.current_hp) / float(monster.max_hp)
				if monster_hp_pct <= execute_threshold:
					monster.current_hp = 0
					messages.append("[color=#FF0000]%s's %s executes the %s![/color]" % [companion.name, ability_name, monster.name])
				else:
					# If not below threshold, deal bonus damage instead
					var exec_damage = int(companion_damage * 0.5)
					monster.current_hp -= exec_damage
					monster.current_hp = max(0, monster.current_hp)
					messages.append("[color=#FFAA00]%s's %s deals %d damage![/color]" % [companion.name, ability_name, exec_damage])
			elif effect == "lifesteal":
				# Direct lifesteal effect (percent is pre-scaled)
				var lifesteal_pct = ability.get("percent", ability.get("base_percent", 20))
				var steal_value = max(1, int(companion_damage * lifesteal_pct / 100.0))
				var actual_heal = character.heal(steal_value)
				if actual_heal > 0:
					messages.append("[color=#00FF00]%s's %s drains %d HP for you![/color]" % [companion.name, ability_name, actual_heal])

			# Check for secondary effects (lifesteal, stun, bleed, etc.)
			if ability.has("effect2"):
				# If chance2 is specified, roll for it; otherwise effect2 triggers with main effect
				var effect2_triggers = true
				if ability.has("chance2"):
					effect2_triggers = randi() % 100 < ability.get("chance2", 0)

				if effect2_triggers:
					var effect2 = ability.get("effect2", "")
					if effect2 == "stun":
						# Stun may have its own stun_chance (e.g., Giant's Ground Slam)
						var stun_triggers = true
						if ability.has("stun_chance"):
							stun_triggers = randi() % 100 < ability.get("stun_chance", 0)
						if stun_triggers:
							combat["monster_stunned"] = 1
							messages.append("[color=#FFAA00]The %s is stunned![/color]" % monster.name)
					elif effect2 == "lifesteal":
						# Use lifesteal_percent if available, otherwise value2
						var lifesteal_pct = ability.get("lifesteal_percent", ability.get("value2", 10))
						var base_damage = ability_damage_dealt if ability_damage_dealt > 0 else companion_damage
						var steal_value = max(1, int(base_damage * lifesteal_pct / 100.0))
						var actual_heal = character.heal(steal_value)
						if actual_heal > 0:
							messages.append("[color=#00FF00]%s drains %d HP for you![/color]" % [companion.name, actual_heal])
					elif effect2 == "bleed":
						var bleed_damage = ability.get("bleed_damage", 5)
						combat["monster_bleed"] = combat.get("monster_bleed", 0) + bleed_damage
						combat["monster_bleed_duration"] = max(combat.get("monster_bleed_duration", 0), 3)
						messages.append("[color=#FF4444]The %s is bleeding![/color]" % monster.name)
					elif effect2 == "mana_drain":
						var drain_amount = ability.get("drain_amount", 10)
						combat["monster_mana_drained"] = combat.get("monster_mana_drained", 0) + drain_amount
						messages.append("[color=#9966FF]%s drains the enemy's mana![/color]" % companion.name)
					elif effect2 == "poison":
						var poison_damage = ability.get("poison_damage", 5)
						combat["monster_poison"] = combat.get("monster_poison", 0) + poison_damage
						combat["monster_poison_duration"] = max(combat.get("monster_poison_duration", 0), 3)
						messages.append("[color=#00FF00]The %s is poisoned![/color]" % monster.name)
					elif effect2 == "heal":
						var heal_pct = ability.get("heal_percent", 10)
						var heal_amount = max(1, int(character.get_total_max_hp() * heal_pct / 100.0))
						var actual_heal = character.heal(heal_amount)
						if actual_heal > 0:
							messages.append("[color=#00FF00]%s heals you for %d HP![/color]" % [companion.name, actual_heal])
					elif effect2 == "weakness":
						var weakness_val = ability.get("weakness_value", ability.get("weakness_base", 15))
						var weakness_dur = ability.get("duration", 3)
						combat["monster_weakness"] = weakness_val
						combat["monster_weakness_duration"] = weakness_dur
						messages.append("[color=#808080]The %s is weakened! (-%d%% attack for %d turns)[/color]" % [monster.name, weakness_val, weakness_dur])
					elif effect2 == "random_debuff":
						# Apply a random debuff
						var debuffs = ["stun", "weakness", "slow"]
						var chosen = debuffs[randi() % debuffs.size()]
						if chosen == "stun":
							combat["monster_stunned"] = 1
							messages.append("[color=#FFAA00]The %s is stunned![/color]" % monster.name)
						elif chosen == "weakness":
							combat["monster_weakness"] = 15
							combat["monster_weakness_duration"] = 2
							messages.append("[color=#808080]The %s is weakened![/color]" % monster.name)
						elif chosen == "slow":
							combat["monster_slowed"] = 20
							combat["monster_slow_duration"] = 2
							messages.append("[color=#6699FF]The %s is slowed![/color]" % monster.name)

func _infer_tier_from_name(item_name: String) -> int:
	"""Infer consumable tier from item name for legacy items without tier field"""
	var name_lower = item_name.to_lower()
	if "divine" in name_lower: return 7
	if "master" in name_lower: return 6
	if "superior" in name_lower: return 5
	if "greater" in name_lower: return 4
	if "standard" in name_lower: return 3
	if "lesser" in name_lower: return 2
	if "minor" in name_lower: return 1
	# Default to tier 1 for consumables with no tier indicator
	return 1

func _is_tier_based_consumable(item_type: String) -> bool:
	"""Check if item type uses the tier system for scaling"""
	# Health, mana, stamina, energy potions and scrolls use tier-based values
	if item_type in ["health_potion", "mana_potion", "stamina_potion", "energy_potion"]:
		return true
	# Scrolls also use tier system
	if item_type.begins_with("scroll_"):
		return true
	return false

func _indent_new_messages(messages: Array, from_index: int, indent: String) -> void:
	"""Add indentation prefix to all messages added since from_index."""
	for i in range(from_index, messages.size()):
		if messages[i].strip_edges() != "":
			messages[i] = indent + messages[i]

func _indent_multiline(text: String, indent: String) -> String:
	"""Indent each non-empty line of a multi-line string."""
	var lines = text.split("\n")
	var result = []
	for line in lines:
		if line.strip_edges() != "":
			result.append(indent + line)
		else:
			result.append(line)
	return "\n".join(result)

func _apply_combat_wear(character, messages: Array):
	"""~30% chance per fight to apply 1-3 wear to one random equipped item."""
	if randf() >= 0.30:
		return
	var slots = ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]
	slots.shuffle()
	for slot in slots:
		var result = character.damage_equipment(slot, randi_range(1, 3))
		if result.success:
			if result.new_wear >= 75:
				messages.append("[color=#FFA500]Your %s is badly worn! (%d%%)[/color]" % [result.item_name, result.new_wear])
			elif result.new_wear >= 50:
				messages.append("[color=#FFFF00]Your %s took some wear. (%d%%)[/color]" % [result.item_name, result.new_wear])
			break  # Only 1 item per fight

func _ready():
	print("Combat Manager initialized")

func start_combat(peer_id: int, character: Character, monster: Dictionary) -> Dictionary:
	"""Initialize a new combat encounter"""

	# Check for ambusher ability (first attack always crits)
	var monster_abilities = monster.get("abilities", [])
	var ambusher_active = ABILITY_AMBUSHER in monster_abilities

	# === INITIATIVE CHECK ===
	# Base: 5-25% from monster speed (static, doesn't scale with level)
	# Beyond-optimal bonus: when player fights past their optimal XP zone, initiative rises
	# Tier bonus: fighting above your tier is very dangerous (+10% per tier)
	# DEX penalty: logarithmic reduction from player dexterity
	var player_dex = character.get_effective_stat("dexterity")
	var companion_speed = int(character.get_companion_bonus("speed")) if character.has_active_companion() else 0
	var monster_speed = monster.get("speed", 10)
	var speed_rating = clampf(float(monster_speed) / 50.0, 0.0, 1.0)
	var base_initiative = 5.0 + speed_rating * 20.0
	# Beyond-optimal zone bonus: initiative rises when player pushes past their XP sweet spot
	var init_level_diff = monster.get("level", 1) - character.level
	if init_level_diff > 0:
		# Optimal ceiling matches the same-tier XP bonus cap formula
		var reference_gap = 10.0 + float(character.level) * 0.05
		var optimal_ceiling = reference_gap * 2.0
		if init_level_diff > optimal_ceiling:
			base_initiative += minf(15.0, (init_level_diff - optimal_ceiling) * 0.5)
	# Cross-tier bonus: fighting above your tier is very dangerous
	var init_player_tier = _get_tier_for_level(character.level)
	var init_monster_tier = _get_tier_for_level(monster.get("level", 1))
	var init_tier_diff = max(0, init_monster_tier - init_player_tier)
	if init_tier_diff > 0:
		base_initiative += init_tier_diff * 10.0
	var effective_dex = float(player_dex) + float(companion_speed) / 2.0
	var dex_penalty = 2.0 * log(maxf(1.0, effective_dex / 10.0)) / log(2.0)
	var monster_initiative_chance = int(base_initiative - dex_penalty)
	if ambusher_active:
		monster_initiative_chance += 8
	monster_initiative_chance = clampi(monster_initiative_chance, 5, 55)

	var init_roll = randi() % 100
	var monster_goes_first = monster_initiative_chance > 0 and init_roll < monster_initiative_chance

	# Handle disguise ability - monster appears weaker initially
	var disguise_active = ABILITY_DISGUISE in monster_abilities
	var true_stats = {}
	if disguise_active:
		# Store true stats for reveal later
		true_stats = {
			"max_hp": monster.max_hp,
			"current_hp": monster.current_hp,
			"strength": monster.strength,
			"defense": monster.defense,
			"name": monster.name
		}
		# Show weakened stats initially (50%)
		monster.max_hp = max(10, int(monster.max_hp * 0.5))
		monster.current_hp = monster.max_hp
		monster.strength = max(5, int(monster.strength * 0.5))
		monster.defense = max(3, int(monster.defense * 0.5))

	# Create combat state
	var combat_state = {
		"peer_id": peer_id,
		"character": character,
		"monster": monster,
		"round": 1,
		"player_can_act": not monster_goes_first,  # Monster may act first!
		"combat_log": [],
		"started_at": Time.get_ticks_msec(),
		"outsmart_failed": false,  # Can only attempt outsmart once per combat
		# Monster ability tracking
		"ambusher_active": ambusher_active,  # Monster's first attack crits
		"monster_went_first": monster_goes_first,  # Track for display
		# Note: Poison is now tracked on character (poison_active, poison_damage, poison_turns_remaining)
		"cc_resistance": 0,  # Increases each time CC (stun/paralyze) lands on monster
		"enrage_stacks": 0,  # Damage bonus per round
		"thorns_damage": 0,  # Damage reflected on hit
		"curse_applied": false,  # Stat curse active
		"disarm_applied": false,  # Weapon damage reduced
		"summoner_triggered": false,  # Already called reinforcements
		# Audit #5 boss signatures (Slice 2)
		"treasure_decoy_pending": ABILITY_BOSS_TREASURE_DECOY in monster_abilities,  # First monster attack 2x crit
		"bloodied_fury_triggered": false,  # One-shot Orc Warlord low-HP buff
		# Disguise ability tracking
		"disguise_active": disguise_active,
		"disguise_true_stats": true_stats,
		"disguise_revealed": false,
		# Damage tracking for death screen
		"total_damage_dealt": 0,
		"total_damage_taken": 0,
		"player_hp_at_start": character.current_hp,
		"pickpocket_count": 0,
		"pickpocket_max": randi_range(1, 3),  # Monster has 1-3 pockets of materials
		# Audit #1 Slice 6a — deck/hand/discard. Initialized after
		# active_combats assignment (the helpers read combat_state by ref).
		"combat_hand_size": COMBAT_HAND_SIZE,
		"combat_deck": [],
		"combat_hand": [],
		"combat_discard": []
	}

	active_combats[peer_id] = combat_state
	_initialize_combat_deck(combat_state)
	_draw_to_hand(combat_state)

	# Audit #5 Slice 13 — Siren's Cove SHALLOW_TIDE pending-lull carryover.
	# If the player stepped on a tide tile that rolled the 5% lull chance just
	# before this combat started, apply player_lulled here so it consumes on
	# the player's first turn.
	if character.has_meta("pending_dungeon_lull") and character.get_meta("pending_dungeon_lull", false):
		combat_state["player_lulled"] = true
		character.remove_meta("pending_dungeon_lull")

	# Audit #5 Slice 14 — Rat Warrens FILTHY_PUDDLE pending-festering carryover.
	# Each stack ticks 2% player max HP per turn — read by the existing Rat
	# King Festering Bite block in the player-turn-start tick path. Uses the
	# SAME combat key (player_fester_stacks) so puddle festering stacks with
	# Rat-King-applied stacks (cap 5 enforced when boss applies more).
	if character.has_meta("pending_dungeon_festering"):
		var fest_stacks = int(character.get_meta("pending_dungeon_festering", 0))
		if fest_stacks > 0:
			combat_state["player_fester_stacks"] = clamp(fest_stacks, 0, 5)
		character.remove_meta("pending_dungeon_festering")

	# Audit #5 Slice 14 — Orc Stronghold WAR_BANNER pending-buff carryover.
	# Player damage +15% while combat.round <= the deadline. combat.round
	# starts at 1, so N rounds = deadline N inclusive.
	if character.has_meta("pending_war_banner"):
		var banner_rounds = int(character.get_meta("pending_war_banner", 0))
		if banner_rounds > 0:
			combat_state["player_war_banner_until_round"] = banner_rounds
		character.remove_meta("pending_war_banner")

	# Audit #5 Slice 14 — Wraith Barrow SPECTRAL_VEIL pending-buff carryover.
	# Monster attacks have 20% miss chance while combat.round <= the deadline.
	if character.has_meta("pending_dungeon_veil"):
		var veil_rounds = int(character.get_meta("pending_dungeon_veil", 0))
		if veil_rounds > 0:
			combat_state["player_veil_until_round"] = veil_rounds
		character.remove_meta("pending_dungeon_veil")

	# Mark character as in combat and reset per-combat flags
	character.in_combat = true
	character.reset_combat_flags()  # Reset Dwarf Last Stand etc.

	# Check for forcefield persistent buff (from scrolls) and apply it
	var forcefield_buff = character.get_buff_value("forcefield")
	if forcefield_buff > 0:
		combat_state["forcefield_shield"] = forcefield_buff

	# Check for other scroll buffs that affect combat
	var lifesteal_buff = character.get_buff_value("lifesteal")
	if lifesteal_buff > 0:
		combat_state["lifesteal_percent"] = lifesteal_buff

	var thorns_buff = character.get_buff_value("thorns")
	if thorns_buff > 0:
		combat_state["player_thorns"] = thorns_buff

	var crit_buff = character.get_buff_value("crit_chance")
	if crit_buff > 0:
		combat_state["crit_bonus"] = crit_buff

	# === COMPANION PASSIVE ABILITIES ===
	# Apply passive companion abilities at combat start (using monster-specific abilities)
	if character.has_active_companion() and drop_tables:
		var companion = character.get_active_companion()
		var companion_level = companion.get("level", 1)
		var monster_type = companion.get("monster_type", "")
		var variant_mult = character.get_variant_stat_multiplier()
		var companion_sub_tier = companion.get("sub_tier", 1)
		var companion_abilities = drop_tables.get_monster_companion_abilities(monster_type, companion_level, variant_mult, companion_sub_tier)
		# Store for use by active/threshold handlers later
		combat_state["companion_abilities"] = companion_abilities

		# Apply passive abilities (values already scaled by level + variant + sub-tier)
		if not companion_abilities.passive.is_empty():
			var passive = companion_abilities.passive
			if passive.has("effect") and passive.has("value"):
				_apply_companion_passive_effect(combat_state, character, passive.effect, passive.value)
			if passive.has("effect2") and passive.has("value2"):
				_apply_companion_passive_effect(combat_state, character, passive.effect2, passive.value2)
			if passive.has("effect3") and passive.has("value3"):
				_apply_companion_passive_effect(combat_state, character, passive.effect3, passive.value3)

		# Track that threshold ability hasn't triggered yet
		combat_state["companion_threshold_triggered"] = false

	# === APPLY COMPANION HP/MANA BONUSES ===
	# Base companion bonuses + passive ability bonuses, applied as temporary max HP/mana boost
	if character.has_active_companion():
		var comp_hp_bonus = int(character.get_companion_bonus("hp_bonus")) + combat_state.get("companion_hp_bonus", 0)
		if comp_hp_bonus > 0:
			var hp_boost = max(1, int(character.get_total_max_hp() * comp_hp_bonus / 100.0))
			character.max_hp += hp_boost
			character.current_hp += hp_boost
			combat_state["companion_hp_boost_applied"] = hp_boost

		# Resource bonus: Apply mana_bonus to player's primary resource (not just mana)
		var comp_resource_bonus = int(character.get_companion_bonus("mana_bonus")) + combat_state.get("companion_mana_bonus", 0)
		if comp_resource_bonus > 0:
			var class_path = character.get_class_path()
			match class_path:
				"warrior":
					var boost = max(1, int(character.get_total_max_stamina() * comp_resource_bonus / 100.0))
					character.max_stamina += boost
					character.current_stamina = mini(character.current_stamina + boost, character.get_total_max_stamina())
					combat_state["companion_resource_boost_applied"] = boost
					combat_state["companion_resource_boost_type"] = "stamina"
				"mage":
					var boost = max(1, int(character.get_total_max_mana() * comp_resource_bonus / 100.0))
					character.max_mana += boost
					character.current_mana = mini(character.current_mana + boost, character.get_total_max_mana())
					combat_state["companion_resource_boost_applied"] = boost
					combat_state["companion_resource_boost_type"] = "mana"
				"trickster":
					var boost = max(1, int(character.get_total_max_energy() * comp_resource_bonus / 100.0))
					character.max_energy += boost
					character.current_energy = mini(character.current_energy + boost, character.get_total_max_energy())
					combat_state["companion_resource_boost_applied"] = boost
					combat_state["companion_resource_boost_type"] = "energy"

		# Store base wisdom bonus for use in resist checks
		var comp_wisdom_bonus = int(character.get_companion_bonus("wisdom_bonus")) + combat_state.get("companion_wisdom_bonus", 0)
		if comp_wisdom_bonus > 0:
			combat_state["companion_wisdom_bonus"] = comp_wisdom_bonus

	# Generate initial combat message
	var msg = generate_combat_start_message(character, monster)

	# Add XP zone hint - shows the player where they stand relative to optimal XP range
	var hint_level_diff = monster.get("level", 1) - character.level
	var hint_player_tier = _get_tier_for_level(character.level)
	var hint_monster_tier = _get_tier_for_level(monster.get("level", 1))
	var hint_tier_diff = hint_monster_tier - hint_player_tier
	if hint_tier_diff > 0:
		var tier_xp_mult = int(pow(2.0, hint_tier_diff))
		msg += "\n[color=#FF00FF]⚠ TIER +%d — Extreme danger! (%dx XP if you survive)[/color]" % [hint_tier_diff, tier_xp_mult]
	elif hint_level_diff > 0 and hint_tier_diff == 0:
		# Calculate same-tier XP bonus to show the player
		var hint_ref_gap = 10.0 + float(character.level) * 0.05
		var hint_gap_ratio = float(hint_level_diff) / hint_ref_gap
		var hint_xp_mult = 1.0 + minf(1.0, sqrt(hint_gap_ratio) * 0.7)
		var hint_bonus_pct = int((hint_xp_mult - 1.0) * 100)
		var hint_optimal_ceiling = hint_ref_gap * 2.0
		if hint_level_diff > hint_optimal_ceiling:
			# Past optimal zone - XP bonus is capped, danger increases
			msg += "\n[color=#FF6600]⚠ Beyond optimal range (+%d%% XP cap) — beware![/color]" % hint_bonus_pct
		elif hint_bonus_pct >= 10:
			msg += "\n[color=#FFD700]Worthy challenge (+%d%% XP bonus)[/color]" % hint_bonus_pct
	elif hint_level_diff < -5 and hint_tier_diff == 0:
		# Fighting below level
		var under_gap = abs(hint_level_diff)
		var penalty_threshold = 5.0 + float(character.level) * 0.03
		if under_gap > penalty_threshold:
			var excess = under_gap - penalty_threshold
			var penalty = minf(0.6, excess * 0.03)
			var penalty_pct = int(penalty * 100)
			if penalty_pct >= 10:
				msg += "\n[color=#808080]Weak foe (-%d%% XP)[/color]" % penalty_pct

	combat_state.combat_log.append(msg)

	# === MONSTER FIRST STRIKE ===
	# If monster won initiative, they attack immediately
	var first_strike_msg = ""
	if monster_goes_first:
		first_strike_msg = "\n[color=#444444]─────────────────────────────[/color]"
		first_strike_msg += "\n         [color=#FF4444][b]⚔ The %s strikes first! ⚔[/b][/color]" % monster.name
		var monster_result = process_monster_turn(combat_state)
		first_strike_msg += "\n" + _indent_multiline(monster_result.get("message", ""), "         ")
		first_strike_msg += "\n[color=#444444]─────────────────────────────[/color]"

		# Check if player died from first strike
		if character.current_hp <= 0:
			var death_extra = ""
			var death_base_end = msg.find("![/color]")
			if death_base_end != -1:
				death_extra = msg.substr(death_base_end + 9)
			death_extra += first_strike_msg + "\n[color=#FF0000]You have been defeated![/color]"
			return {
				"success": true,
				"message": msg + first_strike_msg + "\n[color=#FF0000]You have been defeated![/color]",
				"extra_combat_text": death_extra,
				"combat_state": get_combat_display(peer_id),
				"combat_ended": true,
				"victory": false
			}

		# Player can now act
		combat_state.player_can_act = true

	# Build extra text (XP hints + first strike) for client-side art rendering
	# The client rebuilds the encounter text locally, so these get sent separately
	var extra_combat_text = ""
	# Extract XP hint from msg (everything after the base encounter line)
	var base_encounter_end = msg.find("![/color]")
	if base_encounter_end != -1:
		var after_encounter = msg.substr(base_encounter_end + 9)  # Skip past "![/color]"
		if after_encounter.strip_edges() != "":
			extra_combat_text += after_encounter
	if first_strike_msg != "":
		extra_combat_text += first_strike_msg

	return {
		"success": true,
		"message": msg + first_strike_msg,
		"extra_combat_text": extra_combat_text,
		"combat_state": get_combat_display(peer_id)
	}

func get_active_combat(peer_id: int) -> Dictionary:
	"""Get the active combat state for a peer, or empty dict if not in combat"""
	if active_combats.has(peer_id):
		return active_combats[peer_id]
	return {}

func process_combat_command(peer_id: int, command: String) -> Dictionary:
	"""Process a combat command from player"""

	if not active_combats.has(peer_id):
		return {"success": false, "message": "You are not in combat!"}

	var parts = command.to_lower().split(" ", false)
	var cmd = parts[0] if parts.size() > 0 else ""
	var arg = parts[1] if parts.size() > 1 else ""

	var action: CombatAction

	match cmd:
		"attack", "a":
			action = CombatAction.ATTACK
		"flee", "f", "run":
			action = CombatAction.FLEE
		"special", "s":
			action = CombatAction.SPECIAL
		"outsmart", "o":
			action = CombatAction.OUTSMART
		_:
			# Check if it's an ability command
			if cmd in MAGE_ABILITY_COMMANDS or cmd in WARRIOR_ABILITY_COMMANDS or cmd in TRICKSTER_ABILITY_COMMANDS or cmd in UNIVERSAL_ABILITY_COMMANDS:
				return process_ability_command(peer_id, cmd, arg)
			return {"success": false, "message": "Unknown combat command! Use: attack, flee, outsmart, or abilities"}

	return process_combat_action(peer_id, action)

func process_combat_action(peer_id: int, action: CombatAction) -> Dictionary:
	"""Process a player's combat action"""
	
	if not active_combats.has(peer_id):
		return {"success": false, "message": "You are not in combat!"}
	
	var combat = active_combats[peer_id]
	
	if not combat.player_can_act:
		return {"success": false, "message": "Wait for your turn!"}
	
	var result = {}

	# Track monster HP before player action for damage tracking
	var monster_hp_before = combat.monster.current_hp
	var player_hp_before = combat.character.current_hp

	match action:
		CombatAction.ATTACK:
			result = process_attack(combat)
		CombatAction.FLEE:
			result = process_flee(combat)
		CombatAction.SPECIAL:
			result = process_special(combat)
		CombatAction.OUTSMART:
			result = process_outsmart(combat)

	# Track damage dealt to monster this turn
	var damage_dealt_this_turn = max(0, monster_hp_before - combat.monster.current_hp)
	combat["total_damage_dealt"] = combat.get("total_damage_dealt", 0) + damage_dealt_this_turn
	# Track any self-damage from player action (backfire, thorns reflection)
	var self_damage = max(0, player_hp_before - combat.character.current_hp)
	combat["total_damage_taken"] = combat.get("total_damage_taken", 0) + self_damage

	# Check if combat ended
	if result.has("combat_ended") and result.combat_ended:
		end_combat(peer_id, result.get("victory", false))
		return result

	# Monster's turn (if still alive and didn't already act this round)
	if combat.monster.current_hp > 0 and not result.get("monster_acted", false):
		var player_hp_before_monster = combat.character.current_hp
		var monster_hp_before_turn = combat.monster.current_hp
		var monster_result = process_monster_turn(combat)
		result.messages.append("[color=#444444]─────────────────────────────[/color]")
		var monster_msg = monster_result.get("message", "")
		result.messages.append(_indent_multiline(monster_msg, "         "))
		result.messages.append("[color=#444444]─────────────────────────────[/color]")
		# Track damage taken from monster
		var damage_taken_this_turn = max(0, player_hp_before_monster - combat.character.current_hp)
		combat["total_damage_taken"] = combat.get("total_damage_taken", 0) + damage_taken_this_turn
		# Track any damage dealt by reflect/thorns during monster turn
		var reflect_damage = max(0, monster_hp_before_turn - combat.monster.current_hp)
		combat["total_damage_dealt"] = combat.get("total_damage_dealt", 0) + reflect_damage

		# Check if monster fled (Coward, Flee Attack, or Shrieker summon)
		if monster_result.get("monster_fled", false):
			result.combat_ended = true
			result.victory = false
			result["monster_fled"] = true
			result["summon_next_fight"] = monster_result.get("summon_next_fight", "")
			result["monster_level"] = monster_result.get("monster_level", combat.monster.level)
			end_combat(peer_id, false)
			return result

		# Check if player died
		# Note: Don't call end_combat here - let server check eternal status first
		if combat.character.current_hp <= 0:
			result.combat_ended = true
			result.victory = false
			result.monster_name = "%s (Lvl %d)" % [combat.monster.name, combat.monster.level]
			result.monster_level = combat.monster.level
			result.messages.append("[color=#FF0000]You have been defeated![/color]")
			return result
	
	# Increment round
	combat.round += 1
	combat.player_can_act = true

	# === DISGUISE REVEAL (after 2 rounds) ===
	if combat.get("disguise_active", false) and not combat.get("disguise_revealed", false) and combat.round >= 3:
		var true_stats = combat.get("disguise_true_stats", {})
		if not true_stats.is_empty():
			combat["disguise_revealed"] = true
			var monster = combat.monster
			# Calculate how much damage was dealt to disguised form
			var damage_dealt = combat.get("disguise_true_stats", {}).get("max_hp", monster.max_hp) * 0.5 - monster.current_hp
			# Restore true stats
			monster.max_hp = true_stats.max_hp
			monster.strength = true_stats.strength
			monster.defense = true_stats.defense
			# Set current HP to true max minus proportional damage
			monster.current_hp = max(1, true_stats.max_hp - int(damage_dealt * 2))
			result.messages.append("[color=#FF0000]The %s reveals its true form![/color]" % monster.name)
			result.messages.append("[color=#FF4444]It was much stronger than it appeared![/color]")

	# Tick buff durations at end of round and notify of expired buffs
	var expired_buffs = combat.character.tick_buffs()
	for buff in expired_buffs:
		var buff_name = buff.type.capitalize()
		result.messages.append("[color=#808080]Your %s buff has worn off.[/color]" % buff_name)

	return result

func process_attack(combat: Dictionary) -> Dictionary:
	"""Process player attack action with monster ability interactions"""
	var character = combat.character
	var monster = combat.monster
	var abilities = monster.get("abilities", [])
	var messages = []

	# === EQUIPMENT-BASED RESOURCE REGENERATION (at start of player turn) ===
	_apply_gear_resource_regen(character, messages)

	# === BASE MANA REGENERATION FOR MAGES ===
	# Mages regenerate 2% max mana per round (Sage gets 3%)
	var is_mage_class = character.class_type in ["Wizard", "Sorcerer", "Sage"]
	if is_mage_class and character.current_mana < character.get_total_max_mana():
		var base_mana_regen_pct = 0.02
		if character.class_type == "Sage":
			base_mana_regen_pct = 0.03
		var base_regen = max(1, int(character.get_total_max_mana() * base_mana_regen_pct))
		var old_mana = character.current_mana
		character.current_mana = mini(character.get_total_max_mana(), character.current_mana + base_regen)
		var actual_regen = character.current_mana - old_mana
		if actual_regen > 0:
			messages.append("[color=#9999FF]Arcane focus restores %d mana.[/color]" % actual_regen)

	# === COMPANION RESOURCE REGENERATION ===
	var _cr = messages.size()
	_apply_companion_resource_regen(combat, character, messages)
	_indent_new_messages(messages, _cr, "   ")

	# === MONSTER DOT EFFECTS (bleed/poison from companion abilities) ===
	var _cd = messages.size()
	_process_monster_dots(combat, monster, messages)
	_indent_new_messages(messages, _cd, "   ")

	# === POISON & BLIND TICK (at start of player turn) ===
	_process_status_ticks(character, messages)

	# === BLEED TICK (stacking DoT from Bleed ability) ===
	var bleed_stacks = combat.get("player_bleed_stacks", 0)
	if bleed_stacks > 0:
		var bleed_dmg_per_stack = combat.get("player_bleed_damage", 5)
		var total_bleed = bleed_stacks * bleed_dmg_per_stack
		character.current_hp -= total_bleed
		character.current_hp = max(1, character.current_hp)  # Bleed can't kill either
		messages.append("[color=#FF4444]Bleeding deals [color=#FF8800]%d[/color] damage! (%d stacks)[/color]" % [total_bleed, bleed_stacks])

	# === FESTERING BITE TICK (Audit #5 — Rat King boss_festering_bite) ===
	# Each stack ticks 2% of max HP per player turn. Stacks accumulate from
	# successful monster hits (capped at 5). Damage cannot kill the player.
	var fester_stacks = combat.get("player_fester_stacks", 0)
	if fester_stacks > 0:
		var fester_dmg = max(1, int(character.get_total_max_hp() * 0.02 * fester_stacks))
		character.current_hp -= fester_dmg
		character.current_hp = max(1, character.current_hp)
		messages.append("[color=#9ACD32]Festering wounds tick [color=#FF8800]%d[/color] damage! (%d stacks)[/color]" % [fester_dmg, fester_stacks])

	# === CONTAGION AURA TICK (Audit #5 Slice 6 — Plague Zombie boss_contagion_aura) ===
	# Each contagion stack ticks 1% of max HP per player turn. Stacks accumulate
	# passively (every 2 monster turns, applied from the boss's post-turn block),
	# distinct from Festering Bite's on-hit stacking. Damage cannot kill.
	var contagion_stacks = combat.get("player_contagion_stacks", 0)
	if contagion_stacks > 0:
		var contagion_dmg = max(1, int(character.get_total_max_hp() * 0.01 * contagion_stacks))
		character.current_hp -= contagion_dmg
		character.current_hp = max(1, character.current_hp)
		messages.append("[color=#6B8E23]Contagion seeps in — [color=#FF8800]%d[/color] damage. (%d stacks)[/color]" % [contagion_dmg, contagion_stacks])

	# === DROWNING TICK (Audit #5 Slice 7 — Elder Kelpie boss_drowning) ===
	# 2% max HP per stack per player turn (cap 3 stacks = 6%/turn). Damage-debuff
	# component lives in calculate_damage. Stacks accumulate on monster HITS,
	# distinct from Contagion (passive) and Festering (lower per-stack, capped
	# at 5). Damage cannot kill.
	var drowning_stacks = combat.get("player_drowning_stacks", 0)
	if drowning_stacks > 0:
		var drowning_dmg = max(1, int(character.get_total_max_hp() * 0.02 * drowning_stacks))
		character.current_hp -= drowning_dmg
		character.current_hp = max(1, character.current_hp)
		messages.append("[color=#1E90FF]The murky water fills your lungs — [color=#FF8800]%d[/color] damage. (drowning %d/3)[/color]" % [drowning_dmg, drowning_stacks])

	# === COIL SQUEEZE TICK (World Serpent / boss_coil_squeeze) ===
	# Each coil stack ticks 1% max HP per player turn. Cap 10 = -10% per turn.
	var coil_stacks = combat.get("player_coil_stacks", 0)
	if coil_stacks > 0:
		var coil_dmg = max(1, int(character.get_total_max_hp() * 0.01 * coil_stacks))
		character.current_hp -= coil_dmg
		character.current_hp = max(1, character.current_hp)
		messages.append("[color=#2E8B57]The coils tighten — [color=#FF8800]%d[/color] damage. (coil %d/10)[/color]" % [coil_dmg, coil_stacks])

	# === DECAY TICK (Entropy / boss_decay) ===
	# Each decay stack ticks 2% max HP per player turn. Uncapped.
	var decay_stacks = combat.get("player_decay_stacks", 0)
	if decay_stacks > 0:
		var decay_dmg = max(1, int(character.get_total_max_hp() * 0.02 * decay_stacks))
		character.current_hp -= decay_dmg
		character.current_hp = max(1, character.current_hp)
		messages.append("[color=#696969]Entropy unravels you — [color=#FF8800]%d[/color] damage. (decay %d)[/color]" % [decay_dmg, decay_stacks])

	# === REAPER'S MARK CONSUMPTION (Death Incarnate / boss_reapers_touch) ===
	# If marked, lose 15% max HP at start of this player turn, then clear mark.
	if combat.get("player_reaper_marked", false):
		combat["player_reaper_marked"] = false
		var reaper_dmg = max(1, int(character.get_total_max_hp() * 0.15))
		character.current_hp -= reaper_dmg
		character.current_hp = max(1, character.current_hp)
		messages.append("[color=#000000]The reaper's mark claims its due — [color=#FF8800]%d[/color] damage.[/color]" % reaper_dmg)

	# === CHARM EFFECT (player attacks themselves) ===
	if combat.get("player_charmed", false):
		combat["player_charmed"] = false  # Only lasts one turn
		var self_damage = max(1, int(character.get_total_attack() * 0.5))  # 50% of player attack
		character.current_hp -= self_damage
		character.current_hp = max(1, character.current_hp)  # Can't kill yourself
		messages.append("[color=#FF00FF]You are charmed and attack yourself for [color=#FF8800]%d[/color] damage![/color]" % self_damage)
		combat.player_can_act = false
		return {"success": true, "messages": messages, "combat_ended": false}

	# === WEB STUN EFFECT (Constricting Web / boss_web_stun) ===
	# Player struggles free this turn instead of acting. Web clears after one
	# skipped turn so the boss can re-apply on a future hit.
	if combat.get("player_webbed", false):
		combat["player_webbed"] = false
		messages.append("[color=#A335EE]You struggle free of the webbing — but lose this turn![/color]")
		combat.player_can_act = false
		return {"success": true, "messages": messages, "combat_ended": false}

	# === LULLABY EFFECT (Audit #5 Slice 6 — Siren Enchantress boss_lullaby) ===
	# Deterministic timed CC: the siren's song reaches the player and the next
	# turn is lost. Flag is applied from the boss's post-turn block every 4
	# monster turns and consumed here. Distinct from Web Stun (chance on-hit,
	# clears after one skip) by being timer-based and unavoidable.
	if combat.get("player_lulled", false):
		combat["player_lulled"] = false
		messages.append("[color=#00CED1]The siren's lullaby washes over you — you cannot act this turn![/color]")
		combat.player_can_act = false
		return {"success": true, "messages": messages, "combat_ended": false}

	# === MADNESS AURA FIZZLE (Cosmic Horror / boss_madness_aura) ===
	# While madness is active (until specified round), 30% chance for the
	# player's action to fizzle (wasted turn). Flag is consumed by round.
	var madness_until = int(combat.get("player_madness_until_round", -1))
	if madness_until >= int(combat.get("round", 0)) and randi() % 100 < 30:
		messages.append("[color=#9400D3]Madness grips you — your hand refuses to obey![/color]")
		combat.player_can_act = false
		return {"success": true, "messages": messages, "combat_ended": false}

	# Check for vanish (auto-crit from Trickster ability)
	var is_vanished = combat.get("vanished", false)
	if is_vanished:
		combat.erase("vanished")

	# Hit chance: 75% base + (player DEX - monster speed/2) per point
	# Monster speed halved so higher speeds don't tank early-game accuracy
	# DEX makes it easier to hit enemies, Vanish guarantees hit
	var player_dex = character.get_effective_stat("dexterity")
	var monster_speed = monster.get("speed", 10)  # Use monster speed as DEX equivalent
	var dex_diff = player_dex - int(monster_speed / 2.0)
	var hit_chance = 75 + dex_diff
	# Companion speed bonus improves hit chance
	var comp_speed_hit = int(character.get_companion_bonus("speed")) if character.has_active_companion() else 0
	comp_speed_hit += combat.get("companion_speed_bonus", 0)
	hit_chance += int(comp_speed_hit / 3.0)

	# Apply blind debuff (persistent status effect)
	if character.blind_active:
		var blind_penalty = 30  # 30% hit chance reduction when blinded
		hit_chance -= blind_penalty

	hit_chance = clamp(hit_chance, 30, 95)  # 30% minimum (can be reduced by blind), 95% maximum

	# Ethereal ability: 33% dodge chance for monster (Audit #1 TWEAK
	# 2026-05-11 — was 50%, dropped per audit memo so high-investment
	# fights aren't gated on a coin-flip per swing. Pairs with the −10
	# player hit-chance penalty against ethereal targets in process_attack,
	# so the layered miss math still rewards bringing accuracy gear.)
	var ethereal_dodge = ABILITY_ETHEREAL in abilities and not is_vanished
	if ethereal_dodge and randi() % 100 < 33:
		messages.append("[color=#FF00FF]Your attack passes through the ethereal %s![/color]" % monster.name)
		combat.player_can_act = false
		return {"success": true, "messages": messages, "combat_ended": false}

	var hit_roll = randi() % 100

	# === CLASS PASSIVE: Paladin Divine Favor ===
	# Heal 3% max HP per combat round
	var passive = character.get_class_passive()
	var effects = passive.get("effects", {})
	if effects.has("combat_regen_percent"):
		var regen_amount = max(1, int(character.get_total_max_hp() * effects.get("combat_regen_percent", 0)))
		var actual_heal = character.heal(regen_amount)
		if actual_heal > 0:
			messages.append("[color=#FFD700]Divine Favor heals %d HP.[/color]" % actual_heal)

	# === COMPANION BONUS: HP regeneration ===
	var companion_regen = character.get_companion_bonus("hp_regen")
	if companion_regen > 0:
		var regen_amount = max(1, int(character.get_total_max_hp() * companion_regen / 100.0))
		var actual_heal = character.heal(regen_amount)
		if actual_heal > 0:
			messages.append("[color=#00FFFF]Companion heals %d HP.[/color]" % actual_heal)

	if is_vanished or hit_roll < hit_chance:
		# Hit!
		var damage_result = calculate_damage(character, monster, combat)
		var damage = damage_result.damage
		var is_crit = damage_result.is_crit
		var passive_messages = damage_result.get("passive_messages", [])
		var backfire_damage = damage_result.get("backfire_damage", 0)

		# Apply analyze bonus (+10% from Analyze ability)
		var analyze_bonus = combat.get("analyze_bonus", 0)
		if analyze_bonus > 0:
			damage = int(damage * (1.0 + analyze_bonus / 100.0))

		# Apply vanish bonus (extra 1.5x on top of any crit)
		if is_vanished:
			damage = int(damage * 1.5)
			messages.append("[color=#FFD700]You strike from the shadows![/color]")

		# Show passive messages (Blood Rage, Chaos Magic, etc.)
		for msg in passive_messages:
			messages.append(msg)

		# Handle Sorcerer backfire damage
		if backfire_damage > 0:
			character.current_hp -= backfire_damage
			character.current_hp = max(1, character.current_hp)
			messages.append("[color=#9400D3]Wild magic burns you for %d damage![/color]" % backfire_damage)

		# Audit #5 Slice 12 — Void Step consumer (Void Walker). If void step is
		# active, the attack passes through and deals 0 damage. Consumed.
		if ABILITY_BOSS_VOID_STEP in abilities and combat.get("void_step_active", false):
			combat["void_step_active"] = false
			damage = 0
			messages.append("[color=#9400D3]Your strike passes through the %s — void-phase![/color]" % monster.name)

		# Audit #5 Slice 12 — Unknowable consumer (Nameless One). 25% chance for
		# the attack to be "forgotten" — damage doesn't apply, brief flavor.
		if ABILITY_BOSS_UNKNOWABLE in abilities and damage > 0 and randi() % 100 < 25:
			damage = 0
			messages.append("[color=#A0A0A0]The %s's form blurs — your strike never quite happens.[/color]" % monster.name)

		# Audit #5 Slice 8 — Stoneform (Gargoyle Lord). On even-numbered rounds
		# (2, 4, 6...), the boss takes 70% reduced incoming damage. Telegraphs
		# the rhythm — players time bursts to odd rounds.
		var stoneform_active = (ABILITY_BOSS_STONEFORM in abilities) and combat.get("round", 0) > 0 and int(combat.round) % 2 == 0
		if stoneform_active:
			damage = max(1, int(damage * 0.3))
			messages.append("[color=#808080]The %s is in stoneform! Damage reduced.[/color]" % monster.name)

		# Audit #5 Slice 10 — Titan Earthquake stacks (Titan). Each stack
		# reduces incoming player damage by 10% (cap 5 = 50% reduction).
		# Distinct from Stoneform (binary alt-round) — escalating, persistent.
		var quake_stacks = int(combat.get("titan_earthquake_stacks", 0))
		if quake_stacks > 0 and ABILITY_BOSS_TITAN_EARTHQUAKE in abilities:
			var quake_mult = max(0.5, 1.0 - 0.1 * quake_stacks)
			damage = max(1, int(damage * quake_mult))

		monster.current_hp -= damage
		monster.current_hp = max(0, monster.current_hp)

		# Audit #5 Slice 8 — Phase Mirror (Wraith Lord). 25% of damage dealt
		# is reflected back to the player. Punishes hard hitters — softer
		# damage nets better DPS. HP-floored at 1 (can't suicide on reflect).
		if ABILITY_BOSS_PHASE_MIRROR in abilities and damage > 0:
			var mirror_dmg = max(1, int(damage * 0.25))
			character.current_hp = max(1, character.current_hp - mirror_dmg)
			messages.append("[color=#9370DB]Phase Mirror reflects [color=#FF4444]%d[/color] back to you![/color]" % mirror_dmg)

		# Audit #5 Slice 9 — Blood Frenzy (Vampire). Heals 30% of damage dealt
		# back as HP. Distinct from generic life_steal (per-hit fixed % of
		# monster max HP) — this scales with damage dealt, so glass-cannon
		# strategies feed the vampire more aggressively. Capped at boss max HP.
		if ABILITY_BOSS_BLOOD_FRENZY in abilities and damage > 0:
			var blood_heal = max(1, int(damage * 0.30))
			var blood_max = int(monster.get("max_hp", 1))
			var blood_actual = mini(blood_heal, blood_max - int(monster.current_hp))
			if blood_actual > 0:
				monster.current_hp = int(monster.current_hp) + blood_actual
				messages.append("[color=#660000][b]BLOOD FRENZY![/b][/color] [color=#FF66CC]The %s drinks deep, healing %d HP from your strike.[/color]" % [monster.name, blood_actual])

		# Audit #5 Slice 11 — Hydra Regen (Hydra). When player deals more than
		# 10% of the boss's max HP in a single attack, boss heals 10% max HP.
		# Anti-burst — distinct from Blood Frenzy (% of damage) and from
		# threshold heals (HP-band triggered). Punishes hard-hitting strategies.
		if ABILITY_BOSS_HYDRA_REGEN in abilities and damage > 0 and monster.current_hp > 0:
			var hydra_threshold = int(monster.max_hp * 0.10)
			if damage > hydra_threshold:
				var hydra_heal = max(1, int(monster.max_hp * 0.10))
				var hydra_actual = mini(hydra_heal, int(monster.max_hp) - int(monster.current_hp))
				if hydra_actual > 0:
					monster.current_hp = int(monster.current_hp) + hydra_actual
					messages.append("[color=#2E8B57][b]HYDRA REGEN![/b][/color] [color=#9ACD32]The %s sprouts two heads for every blow — regrows %d HP![/color]" % [monster.name, hydra_actual])

		# Use class-specific attack description
		var attack_desc = character.get_class_attack_description(damage, monster.name, is_crit)
		messages.append(attack_desc)

		# === TRICKSTER DOUBLE STRIKE ===
		# Tricksters have 25% chance for a bonus attack at 50% damage
		var is_trickster = character.class_type in ["Thief", "Ranger", "Ninja"]
		if is_trickster and monster.current_hp > 0 and randi() % 100 < 25:
			var second_damage = int(damage * 0.5)
			monster.current_hp -= second_damage
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#66FF66]Quick Strike! +%d bonus damage![/color]" % second_damage)

		# Lifesteal from scroll/potion buff
		var lifesteal_percent = combat.get("lifesteal_percent", 0)
		if lifesteal_percent > 0:
			var heal_amount = max(1, int(damage * lifesteal_percent / 100.0))
			var actual_heal = character.heal(heal_amount)
			if actual_heal > 0:
				messages.append("[color=#00FF00]Lifesteal heals you for %d HP![/color]" % actual_heal)

		# === EQUIPMENT PROC EFFECTS ===
		var procs = character.get_equipment_procs()

		# Lifesteal from equipment
		if procs.lifesteal > 0:
			var proc_heal = max(1, int(damage * procs.lifesteal / 100.0))
			var actual_proc_heal = character.heal(proc_heal)
			if actual_proc_heal > 0:
				messages.append("[color=#FF00FF]Vampiric gear drains %d HP![/color]" % actual_proc_heal)

		# Lifesteal from companion bonus (Vampire, Death Incarnate, Entropy, etc.)
		var companion_lifesteal = character.get_companion_bonus("lifesteal")
		# Also check for companion passive lifesteal from abilities
		companion_lifesteal += combat.get("companion_lifesteal_bonus", 0)
		# Also check for companion lifesteal buff from threshold abilities
		var lifesteal_buff = combat.get("companion_lifesteal_buff", 0)
		if lifesteal_buff > 0:
			companion_lifesteal += lifesteal_buff
			# Decrement duration
			var buff_duration = combat.get("companion_lifesteal_buff_duration", 0)
			if buff_duration > 0:
				combat["companion_lifesteal_buff_duration"] = buff_duration - 1
				if buff_duration - 1 <= 0:
					combat["companion_lifesteal_buff"] = 0
		if companion_lifesteal > 0:
			var companion_heal = max(1, int(damage * companion_lifesteal / 100.0))
			var actual_companion_heal = character.heal(companion_heal)
			if actual_companion_heal > 0:
				var companion = character.get_active_companion()
				var comp_name = companion.get("name", "Companion") if companion else "Companion"
				messages.append("[color=#00FFFF]%s drains %d HP for you![/color]" % [comp_name, actual_companion_heal])

		# Shocking proc (bonus lightning damage on hit)
		if procs.shocking.chance > 0 and procs.shocking.value > 0:
			if randi() % 100 < procs.shocking.chance:
				var lightning_damage = max(1, int(damage * procs.shocking.value / 100.0))
				monster.current_hp -= lightning_damage
				monster.current_hp = max(0, monster.current_hp)
				messages.append("[color=#00FFFF]>> Shocking strikes for %d bonus damage![/color]" % lightning_damage)

		# Execute proc (bonus damage when enemy below 30% HP)
		if procs.execute.chance > 0 and procs.execute.value > 0:
			var monster_hp_percent = float(monster.current_hp) / float(monster.max_hp)
			if monster_hp_percent <= 0.30 and randi() % 100 < procs.execute.chance:
				var execute_damage = max(1, int(damage * procs.execute.value / 100.0))
				monster.current_hp -= execute_damage
				monster.current_hp = max(0, monster.current_hp)
				messages.append("[color=#FF4444]ðŸ’€ Execute strikes for %d bonus damage![/color]" % execute_damage)

		# Thorns ability: reflect damage back to attacker
		if ABILITY_THORNS in abilities:
			var thorn_damage = max(1, int(damage * 0.25))
			character.current_hp -= thorn_damage
			character.current_hp = max(1, character.current_hp)
			messages.append("[color=#FF4444]Thorns deal [color=#FF8800]%d[/color] damage to you![/color]" % thorn_damage)

		# Damage reflect ability: reflect 25% of damage
		if ABILITY_DAMAGE_REFLECT in abilities:
			var reflect_damage = max(1, int(damage * 0.25))
			character.current_hp -= reflect_damage
			character.current_hp = max(1, character.current_hp)
			messages.append("[color=#FF00FF]The %s reflects [color=#FF8800]%d[/color] damage![/color]" % [monster.name, reflect_damage])

		if monster.current_hp <= 0:
			# Monster defeated - process victory with ability bonuses
			return _process_victory_with_abilities(combat, messages)
	else:
		# Miss
		messages.append("[color=#FF4444]You swing at the %s but miss![/color]" % monster.name)

	# === COMPANION ATTACK (independent of player hit/miss) ===
	if monster.current_hp > 0:
		var _ca = messages.size()
		_process_companion_attack(combat, messages)
		_indent_new_messages(messages, _ca, "   ")
		if monster.current_hp <= 0:
			return _process_victory_with_abilities(combat, messages)

	combat.player_can_act = false

	return {
		"success": true,
		"messages": messages,
		"combat_ended": false
	}

func _process_victory_with_abilities(combat: Dictionary, messages: Array) -> Dictionary:
	"""Process monster defeat with all ability effects (death message, bonuses, curses)"""
	var victory_msg_start = messages.size()
	var character = combat.character
	var monster = combat.monster
	var abilities = monster.get("abilities", [])

	# Audit #5 boss signature — Death Defiance / boss_revive_once.
	# Boss revives once at 50% HP. Suppress the victory cascade and continue
	# the fight. Tracks via combat["boss_revive_used"] so it triggers exactly
	# once per encounter.
	if ABILITY_BOSS_REVIVE_ONCE in abilities and not combat.get("boss_revive_used", false):
		combat["boss_revive_used"] = true
		var revive_hp = max(1, int(monster.max_hp * 0.5))
		monster.current_hp = revive_hp
		messages.append("[color=#FFD700]The %s crumbles to dust... but bones rise once more![/color]" % monster.name)
		messages.append("[color=#FFAA00]Death Defiance![/color] [color=#9ACD32]The %s revives at %d HP![/color]" % [monster.name, revive_hp])
		return {"success": true, "messages": messages, "combat_ended": false}

	# Audit #5 boss signature (Slice 11) — Phoenix Rebirth (Phoenix). Same shape
	# as Death Defiance but revives at 75% HP instead of 50%. Final-tier
	# resurrection — stronger comeback that punishes one-shot strategies.
	if ABILITY_BOSS_PHOENIX_REBIRTH in abilities and not combat.get("boss_revive_used", false):
		combat["boss_revive_used"] = true
		var phoenix_hp = max(1, int(monster.max_hp * 0.75))
		monster.current_hp = phoenix_hp
		messages.append("[color=#FF8C00]The %s erupts in flames... and is reborn from the ashes![/color]" % monster.name)
		messages.append("[color=#FFAA00]Phoenix Rebirth![/color] [color=#9ACD32]The %s rises at %d HP![/color]" % [monster.name, phoenix_hp])
		return {"success": true, "messages": messages, "combat_ended": false}

	# Custom death message — emit flavor first if set, then ALWAYS emit the
	# generic "defeated" line so the combat log has an unambiguous death
	# marker (some flavor messages like "The troll stops regenerating. Finally."
	# don't read as obvious deaths).
	var death_msg = monster.get("death_message", "")
	if death_msg != "":
		messages.append("[color=#FFD700]%s[/color]" % death_msg)
	messages.append("[color=#00FF00]The %s is defeated![/color]" % monster.name)

	# Death curse ability: deal damage on death (nerfed from 25% to 10%, reduced by WIS)
	# Undead racial: immune to death curses
	if ABILITY_DEATH_CURSE in abilities:
		if character.is_immune_to_death_curse():
			messages.append("[color=#708090]The %s's death curse has no effect on your undead form![/color]" % monster.name)
		else:
			var base_curse_damage = int(monster.max_hp * 0.10)  # Reduced from 25% to 10%
			# WIS provides ability resistance: reduces damage by min(50%, WIS/200)
			var player_wis = character.get_effective_stat("wisdom") + combat.get("companion_wisdom_bonus", 0)
			var wis_reduction = minf(0.50, float(player_wis) / 200.0)  # Max 50% reduction at WIS 100+
			var curse_damage = int(base_curse_damage * (1.0 - wis_reduction))
			curse_damage = max(1, curse_damage)
			character.current_hp -= curse_damage
			character.current_hp = max(1, character.current_hp)
			if wis_reduction > 0:
				messages.append("[color=#FF00FF]The %s's death curse deals [color=#FF8800]%d[/color] damage! (WIS resists %d%%)[/color]" % [monster.name, curse_damage, int(wis_reduction * 100)])
			else:
				messages.append("[color=#FF00FF]The %s's death curse deals [color=#FF8800]%d[/color] damage![/color]" % [monster.name, curse_damage])

	# Calculate XP with smooth level-based scaling (no tier cliffs)
	var base_xp = monster.experience_reward
	var xp_level_diff = monster.level - character.level
	var xp_multiplier = 1.0

	# Tier info for display flavor
	var xp_player_tier = _get_tier_for_level(character.level)
	var xp_monster_tier = _get_tier_for_level(monster.level)
	var xp_tier_diff = xp_monster_tier - xp_player_tier

	# Unified XP scaling: smooth sqrt curve based on level difference
	# No tier cliffs — bonus grows continuously with level gap
	# reference_gap scales with player level: 10 at lv1, 15 at lv100, 35 at lv500
	if xp_level_diff > 0:
		var reference_gap = 10.0 + float(character.level) * 0.05
		var gap_ratio = float(xp_level_diff) / reference_gap
		# sqrt provides diminishing returns: +70% at gap_ratio 1, +140% at 4, +210% at 9
		xp_multiplier = 1.0 + sqrt(gap_ratio) * 0.7
		var bonus_pct = int((xp_multiplier - 1.0) * 100)
		if xp_tier_diff > 0:
			messages.append("[color=#FF00FF]* TIER CHALLENGE: +%d%% XP! *[/color]" % bonus_pct)
		elif bonus_pct >= 5:
			messages.append("[color=#FFD700]Challenge bonus: +%d%% XP[/color]" % bonus_pct)
	elif xp_level_diff < 0:
		# Downlevel penalty — small grace zone, then gradual reduction
		var under_gap = abs(xp_level_diff)
		var penalty_threshold = 5.0 + float(character.level) * 0.03  # Grace zone grows with level
		if under_gap > penalty_threshold:
			var excess = under_gap - penalty_threshold
			var penalty = minf(0.6, excess * 0.03)  # -3% per level beyond threshold
			xp_multiplier = maxf(0.4, 1.0 - penalty)  # Floor at 40% XP
			var penalty_pct = int((1.0 - xp_multiplier) * 100)
			if penalty_pct >= 10:
				messages.append("[color=#808080]Weak foe: -%d%% XP[/color]" % penalty_pct)

	var final_xp = int(base_xp * xp_multiplier * 1.10)  # +10% XP boost

	# Slice 6i — Danger Zone bonus. Hotspot kills give an extra +30-70% XP on
	# top of the natural level scaling. Edge of a hotspot = +30%, center =
	# +70%. The monster's level was already 1.5-2.5x larger from the hotspot
	# multiplier, so total reward for fighting in a hotspot is meaningful.
	var hotspot_intensity = float(monster.get("hotspot_intensity", 0.0))
	var hotspot_xp_pct = 0
	if hotspot_intensity > 0.0:
		var hotspot_xp_mult = 1.3 + hotspot_intensity * 0.4
		final_xp = int(final_xp * hotspot_xp_mult)
		hotspot_xp_pct = int((hotspot_xp_mult - 1.0) * 100)

	# Gambit kill bonus: +1 gem awarded later
	var gambit_kill = combat.get("gambit_kill", false)

	# Easy prey: reduced XP
	if ABILITY_EASY_PREY in abilities:
		final_xp = int(final_xp * 0.5)

	# === CLASS PASSIVE: Ranger Hunter's Mark ===
	# +30% XP from kills
	var passive = character.get_class_passive()
	var passive_effects = passive.get("effects", {})
	if passive_effects.has("xp_bonus"):
		var xp_mult = 1.0 + passive_effects.get("xp_bonus", 0)
		final_xp = int(final_xp * xp_mult)
		messages.append("[color=#228B22]Hunter's Mark: +%d%% XP![/color]" % int(passive_effects.get("xp_bonus", 0) * 100))

	var effective_bonus_pct = int((xp_multiplier - 1.0) * 100)
	if effective_bonus_pct > 0:
		messages.append("[color=#FFD700]You gain %d experience! [color=#00FFFF](+%d%% bonus)[/color][/color]" % [final_xp, effective_bonus_pct])
	else:
		messages.append("[color=#FFD700]You gain %d experience![/color]" % final_xp)
	if hotspot_xp_pct > 0:
		messages.append("[color=#FF6600]Danger Zone Bonus: +%d%% XP and improved drop chance![/color]" % hotspot_xp_pct)

	# Award experience
	character.add_experience(final_xp)

	# === COMPANION XP DISTRIBUTION ===
	# Active companions gain 10% of monster XP
	if character.has_active_companion():
		var companion_xp = max(1, int(base_xp * 0.10))
		var companion_result = character.add_companion_xp(companion_xp)
		character.increment_companion_battles()
		if companion_result.leveled_up:
			var companion = character.get_active_companion()
			messages.append("[color=#00FFFF]* %s leveled up to %d! *[/color]" % [companion.get("name", "Companion"), companion_result.new_level])
			# Notify of unlocked abilities
			for ability_level in companion_result.abilities_unlocked:
				if drop_tables:
					var tier = companion.get("tier", 1)
					var ability = drop_tables.get_companion_ability(tier, ability_level)
					if not ability.is_empty():
						messages.append("[color=#FFD700]* New ability unlocked: %s! *[/color]" % ability.get("name", "Unknown"))
			# Audit #1 Slice 4b — companion-gift ability. When the companion
			# crosses level 10 this combat AND its monster type has a mapped
			# gift_ability AND the player's deck doesn't yet contain it, add
			# 1 copy + announce. One-time per ability per character (we
			# don't re-gift once it's in the deck). Closes the chassis lock
			# from Slice 4 — this is the primary cross-class acquisition
			# path.
			if drop_tables and 10 in companion_result.abilities_unlocked:
				var monster_type = companion.get("monster_type", companion.get("name", ""))
				var gift_ability = drop_tables.get_companion_gift_ability(monster_type)
				if gift_ability != "" and not character.combat_deck_collection.has(gift_ability):
					character.combat_deck_collection[gift_ability] = 1
					var ability_display = gift_ability.capitalize().replace("_", " ")
					messages.append("[color=#FFD700]* %s teaches you %s! +1 deck card. *[/color]" % [companion.get("name", "Companion"), ability_display])

	# Normal gem drops (from high-level monsters) → Monster Gem material
	var gems_earned = roll_gem_drops(monster, character)
	if gems_earned > 0:
		character.add_crafting_material("monster_gem", gems_earned)
		messages.append("[color=#00FFFF]+ + [/color][color=#FF00FF]You found %d Monster Gem%s![/color][color=#00FFFF] + +[/color]" % [gems_earned, "s" if gems_earned > 1 else ""])

	# Gambit kill bonus: +1 Monster Gem
	if gambit_kill:
		character.add_crafting_material("monster_gem", 1)
		messages.append("[color=#FFD700]+ Gambit bonus: +1 Monster Gem! +[/color]")

	# Gem Bearer bonus (separate from normal drops, scales with monster level)
	if ABILITY_GEM_BEARER in abilities:
		var monster_level = monster.get("level", 1)
		# Calculate tier bonus based on monster level - scales generously
		var tier_bonus = 0
		if monster_level >= 5000:
			tier_bonus = 15
		elif monster_level >= 2000:
			tier_bonus = 10
		elif monster_level >= 1000:
			tier_bonus = 8
		elif monster_level >= 500:
			tier_bonus = 6
		elif monster_level >= 250:
			tier_bonus = 4
		elif monster_level >= 100:
			tier_bonus = 3
		elif monster_level >= 50:
			tier_bonus = 2
		elif monster_level >= 25:
			tier_bonus = 1

		# Gem Bearer always drops: 2-5 base + tier bonus → Monster Gems
		var bearer_gems = randi_range(2, 5) + tier_bonus
		character.add_crafting_material("monster_gem", bearer_gems)
		gems_earned += bearer_gems
		messages.append("[color=#00FFFF]* The gem bearer's hoard glitters! [/color][color=#FF00FF]+%d Monster Gem%s![/color][color=#00FFFF] *[/color]" % [bearer_gems, "s" if bearer_gems > 1 else ""])

	# Weapon Master ability: 50% chance to drop a weapon with attack bonuses
	if ABILITY_WEAPON_MASTER in abilities and drop_tables != null:
		if randf() < 0.50:  # 50% chance
			var weapon = drop_tables.generate_weapon(monster.level)
			if not weapon.is_empty():
				messages.append("[color=#FF8000]The Weapon Master drops a powerful weapon![/color]")
				messages.append("[color=%s]Dropped: %s (Level %d)[/color]" % [
					_get_rarity_color(weapon.get("rarity", "common")),
					weapon.get("name", "Unknown Weapon"),
					weapon.get("level", 1)
				])
				if not combat.has("extra_drops"):
					combat.extra_drops = []
				combat.extra_drops.append(weapon)
		else:
			messages.append("[color=#AA6666]- The Weapon Master's weapon shatters on death...[/color]")

	# Shield Bearer ability: 50% chance to drop a shield with HP bonuses
	if ABILITY_SHIELD_BEARER in abilities and drop_tables != null:
		if randf() < 0.50:  # 50% chance
			var shield = drop_tables.generate_shield(monster.level)
			if not shield.is_empty():
				messages.append("[color=#00FFFF]The Shield Guardian drops a sturdy shield![/color]")
				messages.append("[color=%s]Dropped: %s (Level %d)[/color]" % [
					_get_rarity_color(shield.get("rarity", "common")),
					shield.get("name", "Unknown Shield"),
					shield.get("level", 1)
				])
				if not combat.has("extra_drops"):
					combat.extra_drops = []
				combat.extra_drops.append(shield)
		else:
			messages.append("[color=#AA6666]- The Shield Guardian's shield crumbles to dust...[/color]")

	# Arcane Hoarder ability: 35% chance to drop mage gear
	if ABILITY_ARCANE_HOARDER in abilities and drop_tables != null:
		if randf() < 0.35:  # 35% chance
			var mage_item = drop_tables.generate_mage_gear(monster.level)
			if not mage_item.is_empty():
				messages.append("[color=#66CCCC]The Arcane Hoarder drops magical equipment![/color]")
				messages.append("[color=%s]Dropped: %s (Level %d)[/color]" % [
					_get_rarity_color(mage_item.get("rarity", "common")),
					mage_item.get("name", "Unknown Item"),
					mage_item.get("level", 1)
				])
				if not combat.has("extra_drops"):
					combat.extra_drops = []
				combat.extra_drops.append(mage_item)
		else:
			messages.append("[color=#AA66AA]- The Arcane Hoarder's magic dissipates...[/color]")

	# Cunning Prey ability: 35% chance to drop trickster gear
	if ABILITY_CUNNING_PREY in abilities and drop_tables != null:
		if randf() < 0.35:  # 35% chance
			var trick_item = drop_tables.generate_trickster_gear(monster.level)
			if not trick_item.is_empty():
				messages.append("[color=#66FF66]The Cunning Prey drops elusive equipment![/color]")
				messages.append("[color=%s]Dropped: %s (Level %d)[/color]" % [
					_get_rarity_color(trick_item.get("rarity", "common")),
					trick_item.get("name", "Unknown Item"),
					trick_item.get("level", 1)
				])
				if not combat.has("extra_drops"):
					combat.extra_drops = []
				combat.extra_drops.append(trick_item)
		else:
			messages.append("[color=#66AA66]- The Cunning Prey's gear vanishes into shadow...[/color]")

	# Warrior Hoarder ability: 35% chance to drop warrior gear
	if ABILITY_WARRIOR_HOARDER in abilities and drop_tables != null:
		if randf() < 0.35:
			var war_item = drop_tables.generate_warrior_gear(monster.level)
			if not war_item.is_empty():
				messages.append("[color=#FF6600]The Warrior Hoarder drops battle-worn gear![/color]")
				messages.append("[color=%s]Dropped: %s (Level %d)[/color]" % [
					_get_rarity_color(war_item.get("rarity", "common")),
					war_item.get("name", "Unknown Item"),
					war_item.get("level", 1)
				])
				if not combat.has("extra_drops"):
					combat.extra_drops = []
				combat.extra_drops.append(war_item)
		else:
			messages.append("[color=#AA8866]- The Warrior Hoarder's armor crumbles...[/color]")

	# Wish granter ability: 10% chance to offer a wish (100% if GM-guaranteed)
	if ABILITY_WISH_GRANTER in abilities:
		var wish_chance = 1.0 if combat.get("gm_wish_guaranteed", false) else 0.10
		if randf() < wish_chance:
			var monster_lethality = monster.get("lethality", 100)
			var wish_options = generate_wish_options(character, monster.level, monster_lethality)
			combat["wish_pending"] = true
			combat["wish_options"] = wish_options
			messages.append("[color=#FFD700]* The %s offers you a WISH! *[/color]" % monster.name)
			messages.append("[color=#FFD700]Choose your reward wisely...[/color]")
		else:
			messages.append("[color=#808080]The %s's magic fades before granting a wish...[/color]" % monster.name)

	# Trophy drops - rare collectibles from powerful monsters
	if drop_tables != null:
		var trophy = drop_tables.roll_trophy_drop(monster.name)
		if not trophy.is_empty():
			var trophy_id = trophy.get("id", "")
			var trophy_name = trophy.get("name", "Unknown Trophy")
			var trophy_desc = trophy.get("description", "")
			var is_first = not character.has_trophy(trophy_id)
			var trophy_count = character.add_trophy(trophy_id, monster.name, monster.level)
			messages.append("[color=#A335EE]===========================================================================[/color]")
			if is_first:
				messages.append("[color=#A335EE]*** NEW TROPHY COLLECTED! ***[/color]")
			else:
				messages.append("[color=#A335EE]* TROPHY DROP! *[/color]")
			messages.append("[color=#FFD700]%s[/color]" % trophy_name)
			messages.append("[color=#808080]%s[/color]" % trophy_desc)
			if trophy_count > 1:
				messages.append("[color=#00FF00]Trophy added! (x%d of this type, %d total)[/color]" % [trophy_count, character.get_trophy_count()])
			else:
				messages.append("[color=#00FF00]Trophy added to your collection! (%d total)[/color]" % character.get_trophy_count())
			messages.append("[color=#A335EE]===========================================================================[/color]")

	# Soul Gem drops - companions (Tier 7+)
	if drop_tables != null:
		var monster_tier = drop_tables.get_tier_for_level(monster.level)
		if monster_tier >= 7:
			var soul_gem = drop_tables.roll_soul_gem_drop(monster_tier)
			if not soul_gem.is_empty():
				var gem_id = soul_gem.get("id", "")
				var gem_name = soul_gem.get("name", "Unknown Soul Gem")
				var gem_desc = soul_gem.get("description", "")
				var gem_bonuses = soul_gem.get("bonuses", {})
				if character.has_soul_gem(gem_id):
					messages.append("[color=#00FFFF]===========================================================================[/color]")
					messages.append("[color=#00FFFF]* SOUL GEM DROP: %s *[/color]" % gem_name)
					messages.append("[color=#808080]%s[/color]" % gem_desc)
					messages.append("[color=#FFFF00](You already have this soul gem!)[/color]")
					messages.append("[color=#00FFFF]===========================================================================[/color]")
				else:
					character.add_soul_gem(gem_id, gem_name, gem_bonuses)
					messages.append("[color=#00FFFF]===========================================================================[/color]")
					messages.append("[color=#00FFFF]*** NEW SOUL GEM ACQUIRED! ***[/color]")
					messages.append("[color=#FFD700]%s[/color]" % gem_name)
					messages.append("[color=#808080]%s[/color]" % gem_desc)
					# Show bonuses
					var bonus_text = []
					for bonus_type in gem_bonuses:
						var val = gem_bonuses[bonus_type]
						match bonus_type:
							"attack": bonus_text.append("+%d%% attack" % val)
							"hp_regen": bonus_text.append("+%d%% HP/round" % val)
							"flee_bonus": bonus_text.append("+%d%% flee chance" % val)
							"crit_chance": bonus_text.append("+%d%% crit chance" % val)
							"hp_bonus": bonus_text.append("+%d%% max HP" % val)
							"defense": bonus_text.append("+%d%% defense" % val)
							"lifesteal": bonus_text.append("+%d%% lifesteal" % val)
					messages.append("[color=#00FF00]Bonuses: %s[/color]" % ", ".join(bonus_text))
					messages.append("[color=#808080]Use /companion to activate this companion![/color]")
					messages.append("[color=#00FFFF]===========================================================================[/color]")

	# Title item drops (Jarl's Ring, Unforged Crown)
	var title_item = roll_title_item_drop(monster.level)
	if not title_item.is_empty():
		messages.append("[color=#FFD700]===========================================================================[/color]")
		messages.append("[color=#FFD700]*** A LEGENDARY TITLE ITEM DROPS! ***[/color]")
		messages.append("[color=#C0C0C0]%s[/color]" % title_item.name)
		messages.append("[color=#808080]%s[/color]" % title_item.description)
		messages.append("[color=#FFD700]===========================================================================[/color]")
		if not combat.has("extra_drops"):
			combat.extra_drops = []
		combat.extra_drops.append(title_item)

	# Roll for item drops
	var dropped_items = roll_combat_drops(monster, character)
	for item in dropped_items:
		messages.append("[color=%s]%s dropped: %s![/color]" % [
			_get_rarity_color(item.get("rarity", "common")),
			monster.name,
			item.get("name", "Unknown Item")
		])

	# Pack leader: higher flock chance
	var flock = monster.get("flock_chance", 0)
	if ABILITY_PACK_LEADER in abilities:
		flock = min(75, flock + 25)

	# Combine regular drops with extra drops from abilities
	var all_drops = dropped_items.duplicate()
	if combat.has("extra_drops"):
		all_drops.append_array(combat.extra_drops)

	# Combat durability wear (~30% chance per fight, 1 random item takes 1-3 wear)
	_apply_combat_wear(character, messages)

	# Indent all victory/reward messages
	var victory_indent = "          "  # 10 spaces
	messages.insert(victory_msg_start, "[color=#444444]─────────────────────────────[/color]")
	_indent_new_messages(messages, victory_msg_start + 1, victory_indent)

	return {
		"success": true,
		"messages": messages,
		"combat_ended": true,
		"victory": true,
		"monster_name": monster.name,
		"monster_base_name": monster.get("base_name", monster.name),  # For flock generation
		"monster_level": monster.level,
		"flock_chance": flock,
		"dropped_items": all_drops,
		"gems_earned": gems_earned,
		"summon_next_fight": combat.get("summon_next_fight", ""),
		"is_rare_variant": monster.get("is_rare_variant", false),
		"wish_pending": combat.get("wish_pending", false),
		"wish_options": combat.get("wish_options", []),
		"is_dungeon_combat": combat.get("is_dungeon_combat", false),
		"is_boss_fight": combat.get("is_boss_fight", false),
		"dungeon_monster_id": combat.get("dungeon_monster_id", -1)
	}

func process_flee(combat: Dictionary) -> Dictionary:
	"""Process flee attempt"""
	var character = combat.character
	var monster = combat.monster
	var messages = []

	# Process status effects (poison/blind tick)
	_process_status_ticks(character, messages)

	# Get class passive for flee bonuses
	var passive = character.get_class_passive()
	var passive_effects = passive.get("effects", {})

	# Flee chance based on level difference, DEX, and equipment speed
	# Base 40% + DEX + equipment_speed + speed_buff + flee_bonus - (level_diff Ã— 3)
	var equipment_bonuses = character.get_equipment_bonuses()
	var player_dex = character.get_effective_stat("dexterity")
	var speed_buff = character.get_buff_value("speed")
	var equipment_speed = equipment_bonuses.speed  # Boots provide speed bonus
	var flee_bonus = equipment_bonuses.get("flee_bonus", 0)  # Evasion gear provides flee bonus
	var monster_level = monster.get("level", 1)
	var player_level = character.level
	var level_diff = max(0, monster_level - player_level)  # Only penalize if monster is higher level

	# WITS vs monster speed: witty players outsmart faster monsters
	var player_wits = character.get_effective_stat("wits")
	var monster_speed_stat = monster.get("speed", 10)
	var wits_vs_speed = int(float(player_wits - monster_speed_stat) * 0.5)

	# Base 40%, +1% per DEX, +equipment speed (boots!), +speed buffs, +flee bonus
	# +WITS vs monster speed, -1% per level the monster is above you
	var flee_chance = 40 + player_dex + equipment_speed + speed_buff + flee_bonus + wits_vs_speed - level_diff

	# === CLASS PASSIVE: Ninja Shadow Step ===
	# +40% flee success chance
	if passive_effects.has("flee_bonus"):
		var ninja_flee_bonus = int(passive_effects.get("flee_bonus", 0) * 100)
		flee_chance += ninja_flee_bonus
		messages.append("[color=#191970]Shadow Step: +%d%% flee chance![/color]" % ninja_flee_bonus)

	# === COMPANION BONUS: Flee chance ===
	var companion_flee = character.get_companion_bonus("flee_bonus")
	# Companion speed also helps flee
	var companion_speed_flee = int(character.get_companion_bonus("speed"))
	companion_speed_flee += combat.get("companion_speed_bonus", 0)
	companion_flee += companion_speed_flee / 2.0
	if companion_flee > 0:
		flee_chance += int(companion_flee)
		messages.append("[color=#00FFFF]Companion: +%d%% flee chance![/color]" % int(companion_flee))
	# Add companion flee from passive abilities
	var companion_flee_ability = combat.get("companion_flee_bonus", 0)
	if companion_flee_ability > 0:
		flee_chance += companion_flee_ability
	# Add companion flee from threshold ability buff
	var companion_flee_buff = combat.get("companion_flee_buff", 0)
	if companion_flee_buff > 0:
		flee_chance += companion_flee_buff
		messages.append("[color=#00FFFF]Companion ability: +%d%% flee chance![/color]" % companion_flee_buff)
		# Decrement duration
		var flee_duration = combat.get("companion_flee_duration", 0)
		if flee_duration > 0:
			combat["companion_flee_duration"] = flee_duration - 1
			if flee_duration - 1 <= 0:
				combat["companion_flee_buff"] = 0

	# Apply slow aura debuff (from monster ability)
	var slow_penalty = combat.get("player_slow", 0)
	if slow_penalty > 0:
		flee_chance -= slow_penalty

	# === FLOCK FLEE BONUS ===
	# Each monster fought in a flock increases flee chance by 15%
	var flock_count = combat.get("flock_count", 0)
	if flock_count > 0:
		var flock_flee_bonus = flock_count * 15
		flee_chance += flock_flee_bonus
		messages.append("[color=#FFD700]Flock fatigue: +%d%% flee chance![/color]" % flock_flee_bonus)

	flee_chance = clamp(flee_chance, 10, 95)  # Hardcap 10-95%

	var roll = randi() % 100

	if roll < flee_chance:
		# Successful flee
		messages.append("[color=#FFD700]You successfully flee from combat![/color]")
		return {
			"success": true,
			"messages": messages,
			"combat_ended": true,
			"victory": false,
			"fled": true
		}
	else:
		# Failed flee
		messages.append("[color=#FF4444]You fail to escape![/color]")
		# === CLASS PASSIVE: Ninja Shadow Step ===
		# Take no damage when fleeing fails
		if passive_effects.get("flee_no_damage", false):
			combat["ninja_flee_protection"] = true
			messages.append("[color=#191970]Shadow Step: You evade the counterattack![/color]")
		combat.player_can_act = false
		return {
			"success": true,
			"messages": messages,
			"combat_ended": false
		}

func process_special(combat: Dictionary) -> Dictionary:
	"""Process special action (class-specific)"""
	var character = combat.character
	var messages = []

	# Process status effects (poison/blind tick)
	_process_status_ticks(character, messages)

	messages.append("[color=#808080]Special abilities coming soon![/color]")

	return {
		"success": false,
		"messages": messages,
		"combat_ended": false
	}

func process_outsmart(combat: Dictionary) -> Dictionary:
	"""Process outsmart action (Trickster ability).
	Success = instant win with full rewards.
	Failure = monster gets free attack, can't outsmart again this combat.
	Tricksters get +20% bonus. High wits helps, high monster INT hurts."""
	var character = combat.character
	var monster = combat.monster
	var messages = []

	# Process status effects (poison/blind tick)
	_process_status_ticks(character, messages)

	# Check if already failed outsmart this combat
	if combat.get("outsmart_failed", false):
		messages.append("[color=#FF4444]You already failed to outsmart this enemy![/color]")
		return {
			"success": false,
			"messages": messages,
			"combat_ended": false
		}

	# Calculate outsmart chance - WIT vs monster INT and LEVEL DIFFERENCE are key factors
	# Dumb monsters are easy to fool, smart ones nearly impossible
	# Higher level monsters are harder to outsmart - it's risky to fight above your level
	var player_wits = character.get_effective_stat("wits")
	var monster_intelligence = monster.get("intelligence", 15)
	var player_level = character.level
	var monster_level = monster.level

	# Base chance is very low - outsmart is situational
	var base_chance = 5

	# WIT bonus: logarithmic scaling for diminishing returns
	# Formula: 18 * log2(WITS/10) = ~18% at WITS 20, ~36% at WITS 40, ~54% at WITS 80
	var wits_bonus = 0
	if player_wits > 10:
		wits_bonus = int(18.0 * log(float(player_wits) / 10.0) / log(2.0))

	# Trickster class bonus (+20%)
	var class_type = character.class_type
	var is_trickster = class_type in ["Thief", "Ranger", "Ninja"]
	var trickster_bonus = 20 if is_trickster else 0

	# Dumb monster bonus: +3% per INT below 10
	var dumb_bonus = max(0, (10 - monster_intelligence) * 3)

	# Smart monster penalty: -1% per INT above 10 (reduced from -2% for better balance)
	var smart_penalty = max(0, monster_intelligence - 10)

	# Additional penalty if monster INT exceeds your wits (-2% per point)
	var int_vs_wits_penalty = max(0, (monster_intelligence - player_wits) * 2)

	# LEVEL DIFFERENCE PENALTY - This is the big balancing factor
	# Fighting monsters much higher level is risky for Outsmart
	var level_diff = monster_level - player_level
	var level_penalty = 0
	if level_diff > 0:
		# Scaling penalty: -2% per level for first 10 levels, -1% per level after
		if level_diff <= 10:
			level_penalty = level_diff * 2  # -2% to -20% for 1-10 levels above
		elif level_diff <= 50:
			level_penalty = 20 + (level_diff - 10)  # -21% to -60% for 11-50 levels above
		else:
			# Severe penalty for extreme level differences
			level_penalty = 60 + int((level_diff - 50) * 0.5)  # -60%+ for 51+ levels above

	# Level BONUS for fighting weaker monsters (small bonus)
	var level_bonus = 0
	if level_diff < 0:
		level_bonus = min(15, abs(level_diff))  # Up to +15% for fighting weaker monsters

	var outsmart_chance = base_chance + wits_bonus + trickster_bonus + dumb_bonus + level_bonus - smart_penalty - int_vs_wits_penalty - level_penalty

	# INT-based cap: High monster INT reduces maximum success chance
	# Base max: 85% for tricksters, 70% for others. Reduced by monster INT/3
	var base_max_chance = 85 if is_trickster else 70
	var max_chance = max(30, base_max_chance - int(monster_intelligence / 3))  # Min 30% cap
	outsmart_chance = clampi(outsmart_chance, 2, max_chance)

	messages.append("[color=#FFA500]You attempt to outsmart the %s...[/color]" % monster.name)
	var bonus_text = ""
	if is_trickster:
		bonus_text = " [Trickster]"
	var level_text = ""
	if level_diff > 10:
		level_text = " [color=#FF4444]Lv%+d[/color]" % level_diff
	elif level_diff > 0:
		level_text = " [color=#FFA500]Lv%+d[/color]" % level_diff
	messages.append("[color=#808080](Wits: %d vs INT: %d, %d%% chance%s%s)[/color]" % [player_wits, monster_intelligence, outsmart_chance, bonus_text, level_text])

	var roll = randi() % 100

	if roll < outsmart_chance:
		# SUCCESS! Instant victory
		messages.append("[color=#00FF00][b]SUCCESS![/b] You outwit the %s![/color]" % monster.name)
		messages.append("[color=#FFD700]The enemy falls for your trick and you claim victory![/color]")

		# Process death curse (monster curses you as it falls)
		var monster_abilities = monster.get("abilities", [])
		if ABILITY_DEATH_CURSE in monster_abilities:
			if character.is_immune_to_death_curse():
				messages.append("[color=#708090]The %s's death curse has no effect on your undead form![/color]" % monster.name)
			else:
				var base_curse_damage = int(monster.max_hp * 0.10)
				var player_wis_stat = character.get_effective_stat("wisdom") + combat.get("companion_wisdom_bonus", 0)
				var wis_reduction = minf(0.50, float(player_wis_stat) / 200.0)
				var curse_damage = int(base_curse_damage * (1.0 - wis_reduction))
				curse_damage = max(1, curse_damage)
				character.current_hp -= curse_damage
				character.current_hp = max(1, character.current_hp)
				if wis_reduction > 0:
					messages.append("[color=#FF00FF]The %s's death curse deals [color=#FF8800]%d[/color] damage! (WIS resists %d%%)[/color]" % [monster.name, curse_damage, int(wis_reduction * 100)])
				else:
					messages.append("[color=#FF00FF]The %s's death curse deals [color=#FF8800]%d[/color] damage![/color]" % [monster.name, curse_damage])

		# Give full rewards as if monster was killed
		var base_xp = monster.experience_reward
		var xp_level_diff = monster.level - character.level
		var xp_multiplier = 1.0

		# Get tier difference - big rewards for fighting above your tier!
		var player_tier = _get_tier_for_level(character.level)
		var monster_tier = _get_tier_for_level(monster.level)
		var tier_diff = monster_tier - player_tier

		# TIER BONUS: Fighting higher tier monsters is very rewarding!
		var xp_tier_bonus = 1.0
		if tier_diff > 0:
			xp_tier_bonus = pow(2.0, tier_diff)  # 2x per tier
			messages.append("[color=#FF00FF]* TIER CHALLENGE: +%dx XP bonus! *[/color]" % int(xp_tier_bonus))

		# Small level difference bonus (within same tier)
		if xp_level_diff > 0 and tier_diff == 0:
			xp_multiplier = 1.0 + min(0.5, xp_level_diff * 0.02)

		var final_xp = int(base_xp * xp_multiplier * xp_tier_bonus * 1.10)  # +10% XP boost

		# Add XP
		var old_level = character.level
		var level_result = character.add_experience(final_xp)

		messages.append("[color=#FF00FF]+%d XP[/color]" % final_xp)

		if level_result.leveled_up:
			messages.append("[color=#FFD700][b]LEVEL UP![/b] You are now level %d![/color]" % level_result.new_level)

			# Check for newly unlocked abilities
			var new_abilities = character.get_newly_unlocked_abilities(old_level, level_result.new_level)
			if new_abilities.size() > 0:
				messages.append("")
				messages.append("[color=#00FFFF]+======================================+[/color]")
				messages.append("[color=#00FFFF]|[/color]  [color=#FFFF00][b]NEW ABILITY UNLOCKED![/b][/color]")
				for ability in new_abilities:
					var ability_type = "Universal" if ability.get("universal", false) else "Class"
					messages.append("[color=#00FFFF]|[/color]  [color=#00FF00]*[/color] [color=#FFFFFF]%s[/color] [color=#808080](%s)[/color]" % [ability.display, ability_type])
				messages.append("[color=#00FFFF]|[/color]  [color=#808080]Check Abilities menu to equip![/color]")
				messages.append("[color=#00FFFF]+======================================+[/color]")

		# === COMPANION XP DISTRIBUTION ===
		# Active companions gain 10% of monster XP (same as normal victory)
		if character.has_active_companion():
			var companion_xp = max(1, int(base_xp * 0.10))
			var companion_result = character.add_companion_xp(companion_xp)
			character.increment_companion_battles()
			if companion_result.leveled_up:
				var companion = character.get_active_companion()
				messages.append("[color=#00FFFF]* %s leveled up to %d! *[/color]" % [companion.get("name", "Companion"), companion_result.new_level])
				# Notify of unlocked abilities
				for ability_level in companion_result.abilities_unlocked:
					if drop_tables:
						var tier = companion.get("tier", 1)
						var ability = drop_tables.get_companion_ability(tier, ability_level)
						if not ability.is_empty():
							messages.append("[color=#FFD700]* New ability unlocked: %s! *[/color]" % ability.get("name", "Unknown"))

		# Roll for item drops
		var dropped_items = []
		var gems_earned = 0
		var extra_drops = []
		var abilities = monster.get("abilities", [])
		var wish_pending = false
		var wish_options = []

		if drop_tables:
			var drops_result = drop_tables.roll_drops(
				monster.get("drop_table_id", "tier1"),
				monster.get("drop_chance", 5),
				monster.level
			)
			dropped_items = drops_result

			# Reclaimer's Lantern — dungeon-only consumable that grants a chance
			# at an extra drop on dungeon monster kills for N battles. The buff
			# value IS the chance (e.g. 25 → 25% per kill).
			if combat.get("is_dungeon_combat", false):
				var lantern_pct = character.get_buff_value("reclaimer_lantern")
				if lantern_pct > 0 and (randi() % 100) < lantern_pct:
					var extra_drop = drop_tables.roll_drops(
						monster.get("drop_table_id", "tier1"),
						100,  # Bonus roll always succeeds when chance hit
						monster.level
					)
					if extra_drop.size() > 0:
						messages.append("[color=#FFD700]The Lantern reveals an extra prize![/color]")
						extra_drops.append_array(extra_drop)

				# Weapon Master ability: 50% chance to drop a weapon with attack bonuses
			if ABILITY_WEAPON_MASTER in abilities:
				if randf() < 0.50:  # 50% chance
					var weapon = drop_tables.generate_weapon(monster.level)
					if not weapon.is_empty():
						messages.append("[color=#FF8000]The Weapon Master drops a powerful weapon![/color]")
						messages.append("[color=%s]Dropped: %s (Level %d)[/color]" % [
							_get_rarity_color(weapon.get("rarity", "common")),
							weapon.get("name", "Unknown Weapon"),
							weapon.get("level", 1)
						])
						extra_drops.append(weapon)
				else:
					messages.append("[color=#AA6666]- The Weapon Master's weapon shatters on death...[/color]")

			# Shield Bearer ability: 50% chance to drop a shield with HP bonuses
			if ABILITY_SHIELD_BEARER in abilities:
				if randf() < 0.50:  # 50% chance
					var shield = drop_tables.generate_shield(monster.level)
					if not shield.is_empty():
						messages.append("[color=#00FFFF]The Shield Guardian drops a sturdy shield![/color]")
						messages.append("[color=%s]Dropped: %s (Level %d)[/color]" % [
							_get_rarity_color(shield.get("rarity", "common")),
							shield.get("name", "Unknown Shield"),
							shield.get("level", 1)
						])
						extra_drops.append(shield)
				else:
					messages.append("[color=#AA6666]- The Shield Guardian's shield crumbles to dust...[/color]")

			# Arcane Hoarder ability: 35% chance to drop mage gear
			if ABILITY_ARCANE_HOARDER in abilities:
				if randf() < 0.35:  # 35% chance
					var mage_item = drop_tables.generate_mage_gear(monster.level)
					if not mage_item.is_empty():
						messages.append("[color=#66CCCC]The Arcane Hoarder drops magical equipment![/color]")
						messages.append("[color=%s]Dropped: %s (Level %d)[/color]" % [
							_get_rarity_color(mage_item.get("rarity", "common")),
							mage_item.get("name", "Unknown Item"),
							mage_item.get("level", 1)
						])
						extra_drops.append(mage_item)
				else:
					messages.append("[color=#AA66AA]- The Arcane Hoarder's magic dissipates...[/color]")

			# Cunning Prey ability: 35% chance to drop trickster gear
			if ABILITY_CUNNING_PREY in abilities:
				if randf() < 0.35:  # 35% chance
					var trick_item = drop_tables.generate_trickster_gear(monster.level)
					if not trick_item.is_empty():
						messages.append("[color=#66FF66]The Cunning Prey drops elusive equipment![/color]")
						messages.append("[color=%s]Dropped: %s (Level %d)[/color]" % [
							_get_rarity_color(trick_item.get("rarity", "common")),
							trick_item.get("name", "Unknown Item"),
							trick_item.get("level", 1)
						])
						extra_drops.append(trick_item)
				else:
					messages.append("[color=#66AA66]- The Cunning Prey's gear vanishes into shadow...[/color]")

			# Warrior Hoarder ability: 35% chance to drop warrior gear
			if ABILITY_WARRIOR_HOARDER in abilities:
				if randf() < 0.35:
					var war_item = drop_tables.generate_warrior_gear(monster.level)
					if not war_item.is_empty():
						messages.append("[color=#FF6600]The Warrior Hoarder drops battle-worn gear![/color]")
						messages.append("[color=%s]Dropped: %s (Level %d)[/color]" % [
							_get_rarity_color(war_item.get("rarity", "common")),
							war_item.get("name", "Unknown Item"),
							war_item.get("level", 1)
						])
						extra_drops.append(war_item)
				else:
					messages.append("[color=#AA8866]- The Warrior Hoarder's armor crumbles...[/color]")

			# Roll for gem drops → Monster Gems
			gems_earned = roll_gem_drops(monster, character)
			if gems_earned > 0:
				character.add_crafting_material("monster_gem", gems_earned)
				messages.append("[color=#00FFFF]+ + [/color][color=#FF00FF]+%d Monster Gem%s![/color][color=#00FFFF] + +[/color]" % [gems_earned, "s" if gems_earned > 1 else ""])

		# Wish granter ability: 10% chance to offer a wish (100% if GM-guaranteed)
		if ABILITY_WISH_GRANTER in abilities:
			var wish_chance_f = 1.0 if combat.get("gm_wish_guaranteed", false) else 0.10
			if randf() < wish_chance_f:
				var monster_lethality = monster.get("lethality", 100)
				wish_options = generate_wish_options(character, monster.level, monster_lethality)
				wish_pending = true
				messages.append("[color=#FFD700]* The %s offers you a WISH! *[/color]" % monster.name)
				messages.append("[color=#FFD700]Choose your reward wisely...[/color]")
			else:
				messages.append("[color=#808080]The %s's magic fades before granting a wish...[/color]" % monster.name)

		# Combine regular drops with extra drops (like normal victory)
		var all_drops = dropped_items.duplicate()
		all_drops.append_array(extra_drops)

		return {
			"success": true,
			"messages": messages,
			"combat_ended": true,
			"victory": true,
			"victory_type": "outsmart",  # For pilgrimage tracking
			"monster_name": monster.name,
			"monster_level": monster.level,
			"monster_base_name": monster.get("base_name", monster.name),
			"flock_chance": monster.get("flock_chance", 0),
			"dropped_items": all_drops,
			"gems_earned": gems_earned,
			"wish_pending": wish_pending,
			"wish_options": wish_options,
			"is_dungeon_combat": combat.get("is_dungeon_combat", false),
			"is_boss_fight": combat.get("is_boss_fight", false),
			"dungeon_monster_id": combat.get("dungeon_monster_id", -1)
		}
	else:
		# FAILURE! Monster gets free attack
		combat.outsmart_failed = true
		messages.append("[color=#FF4444][b]FAILED![/b] The %s sees through your trick![/color]" % monster.name)

		# Companion still attacks even when outsmart fails - they're loyal!
		var _ca2 = messages.size()
		_process_companion_attack(combat, messages)
		_indent_new_messages(messages, _ca2, "   ")

		# Check if companion killed the monster
		if monster.current_hp <= 0:
			messages.append("[color=#00FF00]Your companion saved you by finishing off the %s![/color]" % monster.name)
			# Give rewards as if outsmart succeeded (companion clutch kill)
			var base_xp = monster.experience_reward
			var xp_result = character.add_experience(base_xp)
			messages.append("[color=#FFD700]+%d XP[/color]" % base_xp)
			return {
				"success": true,
				"messages": messages,
				"combat_ended": true,
				"victory": true,
				"victory_type": "companion_clutch",
				"monster_name": monster.name,
				"monster_level": monster.level,
				"monster_base_name": monster.get("base_name", monster.name),
				"flock_chance": monster.get("flock_chance", 0),
				"dropped_items": [],
				"gems_earned": 0,
				"is_dungeon_combat": combat.get("is_dungeon_combat", false),
				"is_boss_fight": combat.get("is_boss_fight", false)
			}

		# Monster gets a free attack
		var monster_result = process_monster_turn(combat)
		messages.append("[color=#444444]─────────────────────────────[/color]")
		messages.append(_indent_multiline(monster_result.message, "         "))
		messages.append("[color=#444444]─────────────────────────────[/color]")

		# Check if player died
		if character.current_hp <= 0:
			return {
				"success": true,
				"messages": messages,
				"combat_ended": true,
				"victory": false,
				"monster_name": "%s (Lvl %d)" % [monster.name, monster.level],
				"monster_level": monster.level
			}

		# Combat continues normally
		combat.round += 1
		combat.player_can_act = true
		var expired_buffs = character.tick_buffs()
		for buff in expired_buffs:
			var buff_name = buff.type.capitalize()
			messages.append("[color=#808080]Your %s buff has worn off.[/color]" % buff_name)

		return {
			"success": true,
			"messages": messages,
			"combat_ended": false,
			"outsmart_failed": true,  # Tell client outsmart can't be used again
			"monster_acted": true  # Monster already got free attack, don't give another turn
		}

# ===== ABILITY SYSTEM =====

func process_ability_command(peer_id: int, ability_name: String, arg: String) -> Dictionary:
	"""Process an ability command from player"""
	if not active_combats.has(peer_id):
		return {"success": false, "message": "You are not in combat!"}

	var combat = active_combats[peer_id]

	if not combat.player_can_act:
		return {"success": false, "message": "Wait for your turn!"}

	var character = combat.character
	var result: Dictionary

	# Track HP/monster HP before ability for damage tracking
	var monster_hp_before = combat.monster.current_hp
	var player_hp_before = combat.character.current_hp

	# Normalize ability names
	match ability_name:
		"bolt": ability_name = "magic_bolt"
		"strike": ability_name = "power_strike"
		"warcry": ability_name = "war_cry"
		"bash": ability_name = "shield_bash"
		"ironskin": ability_name = "iron_skin"
		"heist": ability_name = "perfect_heist"
		"shield": ability_name = "forcefield"  # Shield is now an alias for Forcefield

	# Audit #1 Slice 6a — hand gate. Only abilities currently in hand may
	# be cast. Standard actions (attack/item/flee/outsmart) bypass this and
	# don't go through process_ability_command. Reject upfront so resource
	# costs aren't pre-checked against a card the player doesn't even hold.
	# Note: server.gd's combat command failure path iterates result.messages
	# (plural), so we surface the error there as well as in `message` for
	# any consumer that reads the singular field.
	var card_name = _ability_alias_to_card(ability_name)
	var hand: Array = combat.get("combat_hand", [])
	if not hand.is_empty() and card_name not in hand:
		var hand_msg = "[color=#FFA500]%s is not in your hand.[/color]" % card_name.replace("_", " ").capitalize()
		return {"success": false, "message": hand_msg, "messages": [hand_msg]}

	# Universal abilities (available to all classes, use class resource)
	if ability_name in ["cloak", "all_or_nothing", "forethought", "tactical_retreat"]:
		result = _process_universal_ability(combat, ability_name)
	# Mage abilities (use mana)
	elif ability_name in ["magic_bolt", "blast", "forcefield", "teleport", "meteor", "haste", "paralyze", "banish"]:
		result = _process_mage_ability(combat, ability_name, arg)
	# Warrior abilities (use stamina)
	elif ability_name in ["power_strike", "war_cry", "shield_bash", "cleave", "berserk", "iron_skin", "devastate", "fortify", "rally"]:
		result = _process_warrior_ability(combat, ability_name)
	# Trickster abilities (use energy)
	elif ability_name in ["analyze", "distract", "pickpocket", "ambush", "vanish", "exploit", "perfect_heist", "sabotage", "gambit"]:
		result = _process_trickster_ability(combat, ability_name)
	else:
		return {"success": false, "message": "Unknown ability!"}

	# Mastery Slice 1 — track ability use only on successful resolution.
	# A failed ability path (insufficient resources, requirement check) sets
	# result.success=false and we skip the counter so failed casts don't
	# rank up. Rank-up notification piggybacks on the result messages so the
	# client doesn't need a new message handler for it.
	#
	# Per-combat cap (Slice 1 polish) — only the first MASTERY_USES_PER_COMBAT_CAP
	# uses of an ability per fight credit toward mastery. Beyond the cap the
	# ability still works normally but doesn't rank you up. Bridges to the
	# eventual deck-building model where draw-3-per-round naturally bounds
	# uses per fight; until then this prevents grind-spam (e.g., casting
	# Magic Bolt at 5 mana over and over).
	if result.get("success", true) != false:
		var combat_uses_so_far: Dictionary = combat.get("mastery_uses_this_fight", {})
		var current_combat_uses = int(combat_uses_so_far.get(ability_name, 0))
		if current_combat_uses < MASTERY_USES_PER_COMBAT_CAP:
			combat_uses_so_far[ability_name] = current_combat_uses + 1
			combat["mastery_uses_this_fight"] = combat_uses_so_far
			var rank_result = combat.character.record_mastery_use(ability_name)
			if rank_result.get("ranked_up", false):
				var new_rank = int(rank_result.get("new_rank", 0))
				var rank_label = combat.character.MASTERY_RANK_NAMES[new_rank] if new_rank < combat.character.MASTERY_RANK_NAMES.size() else "Master"
				# Slice 6b — rank-up no longer auto-grants the damage bonus.
				# Player picks between "+1 Copy in Deck" and "+10% Damage" via popup.
				# Queue persists across disconnect; client pops popup on next event.
				var queued_choice := {"ability": ability_name, "new_rank": new_rank, "queued_at": Time.get_unix_time_from_system()}
				if not (combat.character.pending_rank_choices is Array):
					combat.character.pending_rank_choices = []
				combat.character.pending_rank_choices.append(queued_choice)
				var rank_msg = "[color=#FFD700]Mastery rank up![/color] [color=#9ACD32]%s[/color] reached [color=#FFD700]Rank %d (%s)[/color] — choose [color=#87CEEB]+1 Card[/color] or [color=#FFB6C1]+10%% Damage[/color]." % [ability_name.replace("_", " ").capitalize(), new_rank, rank_label]
				if not result.has("messages"):
					result["messages"] = []
				result.messages.append(rank_msg)
				# Slice 2 — surface rank-up so server can update account-level
				# highest-ever record (survives permadeath, feeds future Slice 3
				# Sanctuary headstart purchases).
				result["mastery_rank_changed"] = {"ability": ability_name, "new_rank": new_rank}
				result["rank_up_choice_pending"] = queued_choice
		# Audit #1 Slice 6a — successful ability use moves the card from
		# hand to discard and refills the hand. Done after mastery tracking
		# so a rank-up notification still ties to the card just played.
		_consume_card_from_hand(combat, _ability_alias_to_card(ability_name))

	# Track damage dealt/taken by the ability itself (backfire, thorns, etc.)
	var ability_damage_dealt = max(0, monster_hp_before - combat.monster.current_hp)
	combat["total_damage_dealt"] = combat.get("total_damage_dealt", 0) + ability_damage_dealt
	var ability_self_damage = max(0, player_hp_before - combat.character.current_hp)
	combat["total_damage_taken"] = combat.get("total_damage_taken", 0) + ability_self_damage

	# Check if combat ended
	if result.has("combat_ended") and result.combat_ended:
		end_combat(peer_id, result.get("victory", false))
		return result

	# === GEAR RESOURCE REGEN (skipped on CC ability turns to prevent spend/regen loops) ===
	var cc_abilities = ["shield_bash", "paralyze"]
	if ability_name not in cc_abilities:
		_apply_gear_resource_regen(combat.character, result.messages)

	# === COMPANION ATTACK (only if ability takes a combat turn) ===
	# Don't attack on free actions like Analyze, Pickpocket success, etc.
	if not result.get("skip_monster_turn", false):
		var _ca3 = result.messages.size()
		_process_companion_attack(combat, result.messages)
		_indent_new_messages(result.messages, _ca3, "   ")

	# Track companion damage to monster
	var companion_damage = max(0, monster_hp_before - combat.monster.current_hp) - ability_damage_dealt
	if companion_damage > 0:
		combat["total_damage_dealt"] = combat.get("total_damage_dealt", 0) + companion_damage

	# Check if companion killed the monster
	if combat.monster.current_hp <= 0:
		# Process full victory with rewards (XP, items, etc.)
		result.messages.append("[color=#00FF00]Your companion finishes off the %s![/color]" % combat.monster.name)
		var victory_result = _process_victory_with_abilities(combat, result.messages)
		end_combat(peer_id, true)
		return victory_result

	# Monster's turn (if still alive and ability didn't end turn specially)
	# Buff abilities only give monster 25% chance to attack (player is being defensive/cautious)
	var monster_attacks = true
	if result.get("buff_ability", false):
		monster_attacks = randi() % 100 < 25  # 25% chance monster still attacks
		if not monster_attacks:
			result.messages.append("[color=#00FF00]You act quickly, avoiding the %s's attack![/color]" % combat.monster.name)

	if not result.get("skip_monster_turn", false) and monster_attacks and combat.monster.current_hp > 0:
		var player_hp_before_monster = combat.character.current_hp
		var monster_hp_before_turn = combat.monster.current_hp
		var monster_result = process_monster_turn(combat)
		result.messages.append("[color=#444444]─────────────────────────────[/color]")
		var monster_msg = monster_result.get("message", "")
		result.messages.append(_indent_multiline(monster_msg, "         "))
		result.messages.append("[color=#444444]─────────────────────────────[/color]")
		# Track damage taken from monster
		var damage_taken_this_turn = max(0, player_hp_before_monster - combat.character.current_hp)
		combat["total_damage_taken"] = combat.get("total_damage_taken", 0) + damage_taken_this_turn
		# Track any damage dealt by reflect/thorns during monster turn
		var reflect_damage = max(0, monster_hp_before_turn - combat.monster.current_hp)
		combat["total_damage_dealt"] = combat.get("total_damage_dealt", 0) + reflect_damage

		# Check if player died
		# Note: Don't call end_combat here - let server check eternal status first
		if combat.character.current_hp <= 0:
			result.combat_ended = true
			result.victory = false
			result.monster_name = "%s (Lvl %d)" % [combat.monster.name, combat.monster.level]
			result.monster_level = combat.monster.level
			result.messages.append("[color=#FF0000]You have been defeated![/color]")
			return result

	# Increment round
	combat.round += 1
	combat.player_can_act = true

	# Tick buff durations and regenerate energy
	var expired_buffs = combat.character.tick_buffs()
	for buff in expired_buffs:
		var buff_name = buff.type.capitalize()
		result.messages.append("[color=#808080]Your %s buff has worn off.[/color]" % buff_name)
	# Note: Resources do not auto-regenerate in combat
	# Resource regen comes from gear (Shadow/Warlord/Mystic) or out-of-combat rest/meditate

	return result

func _process_universal_ability(combat: Dictionary, ability_name: String) -> Dictionary:
	"""Process universal abilities available to all classes (use class resource)"""
	var character = combat.character
	var monster = combat.monster
	var messages = []

	match ability_name:
		"cloak":
			# Check level requirement for cloak (level 20)
			if character.level < 20:
				return {"success": false, "messages": ["[color=#FF4444]Cloak requires level 20![/color]"], "combat_ended": false}

			# Determine cost based on class path (8% of max resource)
			var cost = character.get_cloak_cost()
			var resource_name = character.get_primary_resource()
			var current_resource = character.get_primary_resource_current()

			# In combat, cloak lets you avoid one monster attack and escape
			if current_resource < cost:
				return {"success": false, "messages": ["[color=#FF4444]Not enough %s! Need %d.[/color]" % [resource_name, cost]], "combat_ended": false}

			# Drain the resource
			character.drain_cloak_cost()

			# 75% chance to escape combat successfully
			if randf() < 0.75:
				messages.append("[color=#9932CC]You cloak yourself in shadows and slip away from combat![/color]")
				return {
					"success": true,
					"messages": messages,
					"combat_ended": true,
					"victory": false,
					"fled": true,
					"skip_monster_turn": true
				}
			else:
				messages.append("[color=#FF4444]You try to cloak but the %s sees through your disguise![/color]" % monster.name)
				return {"success": true, "messages": messages, "combat_ended": false}

		"all_or_nothing":
			# Universal desperation ability - very low chance to instant kill
			# Costs 1 mana/stamina/energy (uses whatever resource the class has)
			var has_resource = false
			if character.current_mana >= 1:
				character.current_mana -= 1
				has_resource = true
			elif character.current_stamina >= 1:
				character.current_stamina -= 1
				has_resource = true
			elif character.current_energy >= 1:
				character.current_energy -= 1
				has_resource = true

			if not has_resource:
				return {"success": false, "messages": ["[color=#FF4444]You need at least 1 resource to attempt this![/color]"], "combat_ended": false, "skip_monster_turn": true}

			# Track usage (for "gets better over time" mechanic)
			character.all_or_nothing_uses += 1

			# Calculate success chance:
			# Base: 3%
			# +0.1% per use (max +25% from uses, so caps at 250 uses)
			# -0.5% per monster level above player (heavily penalized vs high level)
			# +0.5% per monster level below player
			var base_chance = 3.0
			var use_bonus = min(25.0, character.all_or_nothing_uses * 0.1)
			var level_diff = monster.level - character.level
			var level_modifier = -level_diff * 0.5  # Negative if monster higher, positive if lower

			var success_chance = base_chance + use_bonus + level_modifier
			success_chance = clamp(success_chance, 1.0, 34.0)  # Min 1%, max 34%

			messages.append("[color=#FF00FF][b]ALL OR NOTHING![/b][/color]")
			messages.append("[color=#808080](Success chance: %.1f%%)[/color]" % success_chance)

			if randf() * 100.0 < success_chance:
				# SUCCESS - instant kill!
				var killing_blow = monster.current_hp
				monster.current_hp = 0
				messages.append("[color=#00FF00][b]MIRACULOUS SUCCESS![/b][/color]")
				messages.append("[color=#FFD700]Against all odds, you strike the %s's vital point for %d damage![/color]" % [monster.name, killing_blow])
			else:
				# FAILURE - monster gets enraged (double strength and speed)
				monster.strength = monster.strength * 2
				monster.speed = monster.speed * 2
				# Wake up paralyzed monsters faster
				if combat.get("monster_stunned", 0) > 0:
					combat["monster_stunned"] = max(0, combat["monster_stunned"] - 2)
					messages.append("[color=#FF4444]The monster snaps out of paralysis![/color]")
				messages.append("[color=#FF0000][b]CATASTROPHIC FAILURE![/b][/color]")
				messages.append("[color=#FF4444]The %s becomes ENRAGED! Its strength and speed DOUBLE![/color]" % monster.name)

			# Check if monster died
			if monster.current_hp <= 0:
				return _process_victory(combat, messages)

			return {"success": true, "messages": messages, "combat_ended": false}

		"forethought":
			# Audit #1 deck variant — pay 1 of any primary resource, discard
			# the rest of the hand, refill from deck. Player keeps the turn:
			# action remains available, so this is a paid mulligan that lets
			# you cast something usable afterward.
			var has_res = false
			if character.current_mana >= 1:
				character.current_mana -= 1
				has_res = true
			elif character.current_stamina >= 1:
				character.current_stamina -= 1
				has_res = true
			elif character.current_energy >= 1:
				character.current_energy -= 1
				has_res = true
			if not has_res:
				return {"success": false, "messages": ["[color=#FF4444]Forethought needs at least 1 resource.[/color]"], "combat_ended": false}

			# Move the rest of the hand into the discard pile, then refill.
			# Forethought itself is the card the player just spent — it's
			# already being consumed by the standard _consume_card_from_hand
			# path in the caller, so we touch only the OTHER cards here.
			var hand: Array = combat.get("combat_hand", [])
			var discard: Array = combat.get("combat_discard", [])
			var discarded_count = 0
			# Strip everything except Forethought (which is consumed by the caller).
			var remaining_hand: Array = []
			for card in hand:
				if card == "forethought":
					remaining_hand.append(card)
				else:
					discard.append(card)
					discarded_count += 1
			combat["combat_hand"] = remaining_hand
			combat["combat_discard"] = discard
			# Caller will consume Forethought + redraw — but we want the redraw
			# to happen AFTER the discard so the player gets a full fresh hand.
			# The normal hand-refill in _consume_card_from_hand uses the deck +
			# discard reshuffle pattern, so this just works.
			messages.append("[color=#9370DB]You take a moment — discard %d cards, draw fresh.[/color]" % discarded_count)
			# Skip monster turn — Forethought is a "setup" card like Analyze /
			# Pickpocket. The player paid a resource AND a card for a fresh hand;
			# the round advances but the boss doesn't get a free swing.
			return {"success": true, "messages": messages, "combat_ended": false, "skip_monster_turn": true}

		"tactical_retreat":
			# Audit #1 deck variant — free mulligan, but spends the turn. The
			# whole hand goes to discard (Tactical Retreat itself is consumed
			# normally by the caller). Player skips their action; monster
			# takes its turn next. Useful when no card is castable AND you
			# can't afford Forethought's resource cost.
			var hand2: Array = combat.get("combat_hand", [])
			var discard2: Array = combat.get("combat_discard", [])
			var discarded2 = 0
			var remaining_hand2: Array = []
			for card2 in hand2:
				if card2 == "tactical_retreat":
					remaining_hand2.append(card2)
				else:
					discard2.append(card2)
					discarded2 += 1
			combat["combat_hand"] = remaining_hand2
			combat["combat_discard"] = discard2
			messages.append("[color=#87CEEB]Tactical retreat — discard %d cards, surrender your turn for a fresh draw.[/color]" % discarded2)
			# Player's turn ends; monster still acts.
			return {"success": true, "messages": messages, "combat_ended": false}

	return {"success": false, "messages": ["[color=#FF4444]Unknown universal ability![/color]"], "combat_ended": false}

func _process_mage_ability(combat: Dictionary, ability_name: String, arg: String) -> Dictionary:
	"""Process mage abilities (use mana)"""
	var character = combat.character
	var monster = combat.monster
	var messages = []
	var is_buff_ability = false  # Buff abilities only give monster 25% chance to attack

	# Check INT requirement for mage path
	if character.get_stat("intelligence") <= 10:
		return {"success": false, "messages": ["[color=#FF4444]You need INT > 10 to use mage abilities![/color]"], "combat_ended": false}

	# Get ability info
	var ability_info = _get_ability_info("mage", ability_name)
	if ability_info.is_empty():
		return {"success": false, "messages": ["[color=#FF4444]Unknown mage ability![/color]"], "combat_ended": false}

	# Mastery Slice 1 — all abilities accessible from L1, replacing the
	# fixed level-unlock gate. Effective power scales with use-rank instead.

	# Calculate mana cost - use percentage of max mana or base cost, whichever is higher
	# This ensures abilities scale with late-game mana pools
	var base_cost = ability_info.cost
	var cost_percent = ability_info.get("cost_percent", 0)
	var percent_cost = int(character.get_total_max_mana() * cost_percent / 100.0)
	var mana_cost = max(base_cost, percent_cost)

	# Get class passive for spell modifications
	var passive = character.get_class_passive()
	var passive_effects = passive.get("effects", {})

	# Audit #1 variable-cost rework — abilities in VARIABLE_COST_TABLE (blast,
	# meteor in v0.9.260) auto-spend max-affordable up to ceiling. Magic Bolt
	# stays on its own existing variable path (arg-driven). Other mage abilities
	# stay fixed-cost until later slices.
	var variable_fraction: float = 1.0
	var on_variable_cost: bool = VARIABLE_COST_TABLE.has(ability_name) and ability_name != "magic_bolt"
	if on_variable_cost:
		var vc_result = apply_variable_cost(character, ability_name, combat)
		for vc_msg in vc_result.get("messages", []):
			messages.append(vc_msg)
		if not vc_result.get("ok", false):
			return {"success": false, "messages": messages, "combat_ended": false, "skip_monster_turn": true}
		variable_fraction = float(vc_result.get("fraction", 1.0))

	match ability_name:
		"magic_bolt":
			# Variable mana cost - damage scales with INT
			# Formula: damage = mana * (1 + INT/50), reduced by monster WIS
			var bolt_amount = arg.to_int() if arg.is_valid_int() else 0
			if bolt_amount <= 0:
				return {"success": false, "messages": ["[color=#808080]Usage: bolt <amount> - deals mana Ã— INT damage[/color]"], "combat_ended": false, "skip_monster_turn": true}
			bolt_amount = mini(bolt_amount, character.current_mana)
			if bolt_amount <= 0:
				return {"success": false, "messages": ["[color=#FF4444]Not enough mana![/color]"], "combat_ended": false, "skip_monster_turn": true}

			# === RACIAL/CLASS COST REDUCTIONS ===
			# Gnome racial: -15% ability costs, Sage: -25% mana costs
			var actual_mana_cost = bolt_amount
			var gnome_mult = character.get_ability_cost_multiplier()
			if gnome_mult < 1.0:
				actual_mana_cost = int(actual_mana_cost * gnome_mult)
			if passive_effects.has("mana_cost_reduction"):
				actual_mana_cost = int(actual_mana_cost * (1.0 - passive_effects.get("mana_cost_reduction", 0)))
			actual_mana_cost = max(1, actual_mana_cost)
			if actual_mana_cost < bolt_amount:
				messages.append("[color=#20B2AA]Cost reduced to %d mana![/color]" % actual_mana_cost)
			character.current_mana -= actual_mana_cost

			# Calculate INT-based damage (based on intended bolt_amount, not reduced cost)
			# Hybrid scaling: max of sqrt and linear for better high-level scaling
			# sqrt(INT)/5: INT 25=2x, INT 100=3x, INT 225=4x (diminishing returns)
			# INT/75: INT 75=2x, INT 150=3x, INT 225=4x (linear, better at high INT)
			var int_stat = character.get_effective_stat("intelligence")
			var int_multiplier = 1.0 + max(sqrt(float(int_stat)) / 5.0, float(int_stat) / 75.0)
			var base_damage = int(bolt_amount * int_multiplier)

			# Apply damage buff (from War Cry, potions, etc.)
			var damage_buff = character.get_buff_value("damage")
			if damage_buff > 0:
				base_damage = int(base_damage * (1.0 + damage_buff / 100.0))

			# Apply mastery + legacy skill enhancement (rank 0 = -20%, rank 4 = +20%)
			var magic_bolt_skill_bonus = character.get_skill_damage_bonus("magic_bolt")
			base_damage = apply_skill_damage_bonus(character, "magic_bolt", base_damage)
			if magic_bolt_skill_bonus > 0:
				messages.append("[color=#00FFFF]Skill Enhancement: +%d%% damage![/color]" % int(magic_bolt_skill_bonus))

			# === CLASS PASSIVE: Wizard Arcane Precision ===
			# +15% spell damage
			if passive_effects.has("spell_damage_bonus"):
				base_damage = int(base_damage * (1.0 + passive_effects.get("spell_damage_bonus", 0)))
				messages.append("[color=#4169E1]Arcane Precision: +%d%% spell damage![/color]" % int(passive_effects.get("spell_damage_bonus", 0) * 100))

			# === CLASS PASSIVE: Sorcerer Chaos Magic ===
			# 25% double damage, 5% backfire
			if passive_effects.has("double_damage_chance"):
				var chaos_roll = randf()
				if chaos_roll < passive_effects.get("backfire_chance", 0.10):
					# Backfire: damage yourself (capped at 15% max HP)
					var backfire_dmg = mini(int(base_damage * 0.5), int(character.get_total_max_hp() * 0.15))
					character.current_hp -= backfire_dmg
					character.current_hp = max(1, character.current_hp)
					base_damage = int(base_damage * 0.5)
					messages.append("[color=#9400D3]Chaos Magic backfires for %d damage![/color]" % backfire_dmg)
				elif chaos_roll < passive_effects.get("backfire_chance", 0.10) + passive_effects.get("double_damage_chance", 0.25):
					base_damage = base_damage * 2
					messages.append("[color=#9400D3]Chaos Magic: DOUBLE DAMAGE![/color]")

			# === CLASS PASSIVE: Wizard Spell Crit ===
			# +10% spell crit chance (1.5x damage)
			if passive_effects.has("spell_crit_bonus"):
				var spell_crit_chance = int(passive_effects.get("spell_crit_bonus", 0) * 100)
				if randi() % 100 < spell_crit_chance:
					base_damage = int(base_damage * 1.5)
					messages.append("[color=#4169E1]Spell Critical! +50%% damage![/color]")

			# Monster WIS reduces damage (up to 30% reduction)
			var monster_wis = monster.get("wisdom", monster.get("intelligence", 15))
			var wis_reduction = min(0.30, float(monster_wis) / 300.0)  # WIS 90 = 30% reduction
			var pre_mod_dmg = max(1, int(base_damage * (1.0 - wis_reduction)))

			# Apply class affinity bonus (Mages deal +25% to Magical affinity monsters)
			var affinity = monster.get("class_affinity", 0)
			var class_multiplier = _get_class_advantage_multiplier(affinity, character.class_type)
			pre_mod_dmg = int(pre_mod_dmg * class_multiplier)
			if class_multiplier > 1.0:
				messages.append("[color=#00BFFF]Class advantage! +%d%% damage![/color]" % [int((class_multiplier - 1.0) * 100)])
			elif class_multiplier < 1.0:
				messages.append("[color=#FF6666]Class disadvantage: -%d%% damage[/color]" % [int((1.0 - class_multiplier) * 100)])

			var final_damage = apply_damage_variance(apply_ability_damage_modifiers(pre_mod_dmg, character.level, monster))

			monster.current_hp -= final_damage
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#FF00FF]You cast Magic Bolt for %d mana![/color]" % actual_mana_cost)
			messages.append("[color=#00FFFF]The bolt strikes for %d damage![/color]" % final_damage)

		"cloak":
			if not character.use_mana(mana_cost):
				return {"success": false, "messages": ["[color=#FF4444]Not enough mana! (Need %d)[/color]" % mana_cost], "combat_ended": false, "skip_monster_turn": true}
			combat["cloak_active"] = true  # 50% miss chance for enemy
			messages.append("[color=#FF00FF]You cast Cloak! (50%% chance enemy misses next attack)[/color]" % [])
			is_buff_ability = true

		"blast":
			# Variable cost (v0.9.260) — apply_variable_cost helper above has
			# already spent the mana and computed variable_fraction. The legacy
			# Gnome/Sage cost reduction was rolled into apply_skill_cost_reduction
			# inside the helper; the inline block is no longer needed.
			# Base damage 50, scaled by INT (+4% per point) and multiplied by 2.
			# Variable-cost: damage AND burn DoT magnitude scale by spend.
			var int_stat = character.get_effective_stat("intelligence")
			var int_multiplier = 1.0 + (int_stat * 0.04)  # +4% per INT point
			var base_damage = int(50 * int_multiplier * 2 * variable_fraction)
			var damage_buff = character.get_buff_value("damage")
			base_damage = int(base_damage * (1.0 + damage_buff / 100.0))

			# Apply mastery + legacy skill enhancement (rank 0 = -20%, rank 4 = +20%)
			var blast_skill_bonus = character.get_skill_damage_bonus("blast")
			base_damage = apply_skill_damage_bonus(character, "blast", base_damage)
			if blast_skill_bonus > 0:
				messages.append("[color=#00FFFF]Skill Enhancement: +%d%% damage![/color]" % int(blast_skill_bonus))

			# === CLASS PASSIVE: Wizard Arcane Precision ===
			if passive_effects.has("spell_damage_bonus"):
				base_damage = int(base_damage * (1.0 + passive_effects.get("spell_damage_bonus", 0)))

			# === CLASS PASSIVE: Sorcerer Chaos Magic ===
			if passive_effects.has("double_damage_chance"):
				var chaos_roll = randf()
				if chaos_roll < passive_effects.get("backfire_chance", 0.10):
					var backfire_dmg = mini(int(base_damage * 0.5), int(character.get_total_max_hp() * 0.15))
					character.current_hp -= backfire_dmg
					character.current_hp = max(1, character.current_hp)
					base_damage = int(base_damage * 0.5)
					messages.append("[color=#9400D3]Chaos Magic backfires for %d damage![/color]" % backfire_dmg)
				elif chaos_roll < passive_effects.get("backfire_chance", 0.10) + passive_effects.get("double_damage_chance", 0.25):
					base_damage = base_damage * 2
					messages.append("[color=#9400D3]Chaos Magic: DOUBLE DAMAGE![/color]")

			# === CLASS PASSIVE: Wizard Spell Crit ===
			if passive_effects.has("spell_crit_bonus"):
				var spell_crit_chance = int(passive_effects.get("spell_crit_bonus", 0) * 100)
				if randi() % 100 < spell_crit_chance:
					base_damage = int(base_damage * 1.5)
					messages.append("[color=#4169E1]Spell Critical![/color]")

			var damage = apply_damage_variance(base_damage)
			monster.current_hp -= damage
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#FF00FF]You cast Blast![/color]")
			messages.append("[color=#00FFFF]The explosion deals %d damage![/color]" % damage)
			# Apply burn DoT (20% of INT per round, scaled by spend, for 3 rounds)
			var burn_damage = max(1, int(int_stat * 0.2 * variable_fraction))
			combat["monster_burn"] = burn_damage
			combat["monster_burn_duration"] = 3
			messages.append("[color=#FF6600]The target is burning! (%d damage/round for 3 rounds)[/color]" % burn_damage)

		"forcefield":
			# Variable cost (v0.9.262) — apply_variable_cost helper above has
			# spent the mana and set variable_fraction. Shield magnitude scales
			# with spend: full = 100 + INT × 8; floor = 30% of that.
			var int_stat = character.get_effective_stat("intelligence")
			var shield_value = int((100 + (int_stat * 8)) * variable_fraction)
			combat["forcefield_shield"] = shield_value
			messages.append("[color=#FF00FF]You cast Forcefield! (Absorbs next %d damage)[/color]" % shield_value)
			is_buff_ability = true

		"teleport":
			if not character.use_mana(mana_cost):
				return {"success": false, "messages": ["[color=#FF4444]Not enough mana! (Need %d)[/color]" % mana_cost], "combat_ended": false, "skip_monster_turn": true}
			messages.append("[color=#FF00FF]You cast Teleport and vanish![/color]")
			return {
				"success": true,
				"messages": messages,
				"combat_ended": true,
				"fled": true,
				"skip_monster_turn": true
			}

		"meteor":
			# Variable cost (v0.9.260) — apply_variable_cost above has spent the
			# mana and computed variable_fraction. Base damage 100 × INT × 3-4x rng,
			# scaled by spend.
			var int_stat = character.get_effective_stat("intelligence")
			var int_multiplier = 1.0 + (int_stat * 0.04)  # +4% per INT point
			var meteor_mult = 3.0 + randf()  # 3.0 to 4.0x random multiplier
			var base_damage = int(100 * int_multiplier * meteor_mult * variable_fraction)
			var damage_buff = character.get_buff_value("damage")
			base_damage = int(base_damage * (1.0 + damage_buff / 100.0))

			# Apply mastery + legacy skill enhancement (rank 0 = -20%, rank 4 = +20%)
			var meteor_skill_bonus = character.get_skill_damage_bonus("meteor")
			base_damage = apply_skill_damage_bonus(character, "meteor", base_damage)
			if meteor_skill_bonus > 0:
				messages.append("[color=#00FFFF]Skill Enhancement: +%d%% damage![/color]" % int(meteor_skill_bonus))

			# === CLASS PASSIVE: Wizard Arcane Precision ===
			if passive_effects.has("spell_damage_bonus"):
				base_damage = int(base_damage * (1.0 + passive_effects.get("spell_damage_bonus", 0)))

			# === CLASS PASSIVE: Sorcerer Chaos Magic ===
			if passive_effects.has("double_damage_chance"):
				var chaos_roll = randf()
				if chaos_roll < passive_effects.get("backfire_chance", 0.10):
					var backfire_dmg = mini(int(base_damage * 0.5), int(character.get_total_max_hp() * 0.15))
					character.current_hp -= backfire_dmg
					character.current_hp = max(1, character.current_hp)
					base_damage = int(base_damage * 0.5)
					messages.append("[color=#9400D3]Chaos Magic backfires for %d damage![/color]" % backfire_dmg)
				elif chaos_roll < passive_effects.get("backfire_chance", 0.10) + passive_effects.get("double_damage_chance", 0.25):
					base_damage = base_damage * 2
					messages.append("[color=#9400D3]Chaos Magic: DOUBLE DAMAGE![/color]")

			# === CLASS PASSIVE: Wizard Spell Crit ===
			if passive_effects.has("spell_crit_bonus"):
				var spell_crit_chance = int(passive_effects.get("spell_crit_bonus", 0) * 100)
				if randi() % 100 < spell_crit_chance:
					base_damage = int(base_damage * 1.5)
					messages.append("[color=#4169E1]Spell Critical![/color]")

			var damage = apply_damage_variance(base_damage)
			monster.current_hp -= damage
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#FFD700][b]METEOR![/b][/color]")
			messages.append("[color=#FF4444]A massive meteor crashes down for %d damage![/color]" % damage)

		"haste":
			# Speed buff - reduces monster attacks and increases player dodge.
			# Variable cost (v0.9.264): magnitude scales, duration stays 5 rounds.
			var speed_bonus = max(1, int((20 + character.get_effective_stat("intelligence") / 5) * variable_fraction))
			character.add_buff("speed", speed_bonus, 5)
			combat["haste_active"] = true
			messages.append("[color=#00FFFF]You cast Haste! (+%d%% speed for 5 rounds)[/color]" % speed_bonus)
			is_buff_ability = true

		"paralyze":
			# Attempt to stun monster for 1-2 turns, with diminishing returns.
			# Variable cost (v0.9.264): stun CHANCE scales with spend (chance-based
			# rule). Duration stays 1-2 turns if it lands; floor still has 10% floor.
			var int_stat = character.get_effective_stat("intelligence")
			var cc_resist = combat.get("cc_resistance", 0)
			var resist_penalty = cc_resist * 20  # -20% per prior CC
			var raw_chance = mini(85, 50 + int(int_stat / 2)) - resist_penalty
			var success_chance = maxi(10, int(raw_chance * variable_fraction))  # 10% floor for Paralyze
			if randf() * 100 < success_chance:
				var stun_duration = 1 + (randi() % 2)  # 1-2 turns
				combat["monster_stunned"] = stun_duration
				combat["cc_resistance"] = cc_resist + 1
				messages.append("[color=#FFFF00]You paralyze the %s for %d turn(s)![/color]" % [monster.name, stun_duration])
				is_buff_ability = true  # 75% chance to avoid monster's retaliation while casting
			else:
				messages.append("[color=#FF4444]The %s resists your paralysis![/color]" % monster.name)
			if cc_resist > 0:
				messages.append("[color=#808080](Enemy CC resistance: %d%%)[/color]" % (cc_resist * 20))

		"banish":
			# Attempt to remove monster from combat with 50% loot chance.
			# Variable cost (v0.9.264): banish CHANCE scales with spend. Loot
			# drop chance stays 50% (binary bonus outcome, not the headline).
			var int_stat = character.get_effective_stat("intelligence")
			var raw_chance = min(75, 40 + int(int_stat / 3))  # 40% base + 0.33% per INT, cap 75%
			var success_chance = int(raw_chance * variable_fraction)
			if randf() * 100 < success_chance:
				messages.append("[color=#FF00FF]You banish the %s to another dimension![/color]" % monster.name)
				# 50% chance to get loot from banished monster
				if randf() < 0.5:
					messages.append("[color=#FFD700]The creature drops something as it vanishes![/color]")
					return _process_victory_with_abilities(combat, messages)
				else:
					messages.append("[color=#808080]The creature vanishes without a trace...[/color]")
					return {
						"success": true,
						"messages": messages,
						"combat_ended": true,
						"victory": false,
						"fled": true,
						"skip_monster_turn": true
					}
			else:
				messages.append("[color=#FF4444]The %s resists being banished![/color]" % monster.name)

	# Check if monster died
	if monster.current_hp <= 0:
		return _process_victory(combat, messages)

	return {"success": true, "messages": messages, "combat_ended": false, "buff_ability": is_buff_ability}

func _process_warrior_ability(combat: Dictionary, ability_name: String) -> Dictionary:
	"""Process warrior abilities (use stamina)"""
	var character = combat.character
	var monster = combat.monster
	var messages = []
	var is_buff_ability = false  # Buff abilities only give monster 25% chance to attack

	# Check STR requirement for warrior path
	if character.get_stat("strength") <= 10:
		return {"success": false, "messages": ["[color=#FF4444]You need STR > 10 to use warrior abilities![/color]"], "combat_ended": false}

	# Get ability info
	var ability_info = _get_ability_info("warrior", ability_name)
	if ability_info.is_empty():
		return {"success": false, "messages": ["[color=#FF4444]Unknown warrior ability![/color]"], "combat_ended": false}

	# Mastery Slice 1 — level gate removed; rank scales effective power.

	# Audit #1 variable-cost rework — abilities in VARIABLE_COST_TABLE take the
	# variable-cost path; everything else stays on the fixed-cost path. Variable
	# cost auto-spends max-affordable up to ceiling, returns a 0.3-1.0 fraction
	# that the ability body uses to scale damage + secondary effects.
	var variable_fraction: float = 1.0
	var passive = character.get_class_passive()
	var passive_effects = passive.get("effects", {})
	if VARIABLE_COST_TABLE.has(ability_name):
		var vc_result = apply_variable_cost(character, ability_name, combat)
		for vc_msg in vc_result.get("messages", []):
			messages.append(vc_msg)
		if not vc_result.get("ok", false):
			return {"success": false, "messages": messages, "combat_ended": false, "skip_monster_turn": true}
		variable_fraction = float(vc_result.get("fraction", 1.0))
	else:
		var base_stamina_cost = ability_info.cost
		var stamina_cost = apply_skill_cost_reduction(character, ability_name, base_stamina_cost)

		# Show skill enhancement message only if player has skill enhancement (not just racial)
		var skill_reduction = character.get_skill_cost_reduction(ability_name)
		if skill_reduction > 0:
			messages.append("[color=#00FFFF]Skill Enhancement: -%d%% cost![/color]" % int(skill_reduction))

		# === CLASS PASSIVE: Fighter Tactical Discipline ===
		# 20% reduced stamina costs
		if passive_effects.has("stamina_cost_reduction"):
			stamina_cost = max(1, int(stamina_cost * (1.0 - passive_effects.get("stamina_cost_reduction", 0))))
			messages.append("[color=#C0C0C0]Tactical Discipline: Only costs %d stamina![/color]" % stamina_cost)

		# === CLASS PASSIVE: Barbarian Blood Rage ===
		# Abilities cost 25% more
		if passive_effects.has("stamina_cost_increase"):
			stamina_cost = int(stamina_cost * (1.0 + passive_effects.get("stamina_cost_increase", 0)))

		if not character.use_stamina(stamina_cost):
			return {"success": false, "messages": ["[color=#FF4444]Not enough stamina! (Need %d)[/color]" % stamina_cost], "combat_ended": false, "skip_monster_turn": true}

	# Use total attack (includes weapon) for physical abilities
	var total_attack = character.get_total_attack()

	# Get damage buff (War Cry, Berserk) to apply to ability damage
	var damage_buff = character.get_buff_value("damage")
	var damage_multiplier = 1.0 + (damage_buff / 100.0)

	match ability_name:
		"power_strike":
			# Buffed: 2x damage multiplier (was 1.5x), sqrt STR scaling.
			# Variable cost: damage scales linearly with spend (0.3x at floor → 1.0x at ceiling).
			var str_stat = character.get_effective_stat("strength")
			var str_mult = 1.0 + (sqrt(float(str_stat)) / 10.0)  # Sqrt scaling
			var base_dmg = int(total_attack * 2.0 * damage_multiplier * str_mult * variable_fraction)
			# Apply mastery + legacy skill enhancement (rank 0 = -20%, rank 4 = +20%)
			var ps_skill_bonus = character.get_skill_damage_bonus("power_strike")
			base_dmg = apply_skill_damage_bonus(character, "power_strike", base_dmg)
			if ps_skill_bonus > 0:
				messages.append("[color=#00FFFF]Skill Enhancement: +%d%% damage![/color]" % int(ps_skill_bonus))
			var mod_dmg = apply_ability_damage_modifiers(base_dmg, character.level, monster)
			var damage = apply_damage_variance(mod_dmg)
			monster.current_hp -= damage
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#FF4444]POWER STRIKE![/color]")
			messages.append("[color=#FFFF00]You deal %d damage![/color]" % damage)

		"war_cry":
			# Variable cost (v0.9.263): damage magnitude scales with spend.
			# Duration stays 4 rounds so the buff still "feels real" at floor.
			var war_cry_bonus = max(1, int(35 * variable_fraction))
			character.add_buff("damage", war_cry_bonus, 4)
			messages.append("[color=#FF4444]WAR CRY![/color]")
			messages.append("[color=#FFD700]+%d%% damage for 4 rounds![/color]" % war_cry_bonus)
			is_buff_ability = true

		"shield_bash":
			# 1.5x damage multiplier, sqrt STR scaling, diminishing stun chance.
			# Variable cost: damage AND stun chance scale with spend.
			var str_stat = character.get_effective_stat("strength")
			var str_mult = 1.0 + (sqrt(float(str_stat)) / 10.0)
			var base_dmg = int(total_attack * 1.5 * damage_multiplier * str_mult * variable_fraction)
			# Apply mastery + legacy skill enhancement (rank 0 = -20%, rank 4 = +20%)
			var sb_skill_bonus = character.get_skill_damage_bonus("shield_bash")
			base_dmg = apply_skill_damage_bonus(character, "shield_bash", base_dmg)
			if sb_skill_bonus > 0:
				messages.append("[color=#00FFFF]Skill Enhancement: +%d%% damage![/color]" % int(sb_skill_bonus))
			var mod_dmg = apply_ability_damage_modifiers(base_dmg, character.level, monster)
			var damage = apply_damage_variance(mod_dmg)
			monster.current_hp -= damage
			monster.current_hp = max(0, monster.current_hp)
			# Diminishing stun chance: 100% → 75% → 50% → 25% → 20% floor, scaled by spend
			var cc_resist = combat.get("cc_resistance", 0)
			var stun_chance = int(maxi(20, 100 - cc_resist * 25) * variable_fraction)
			messages.append("[color=#FF4444]SHIELD BASH![/color]")
			if randi() % 100 < stun_chance:
				combat["monster_stunned"] = 1  # Enemy skips next turn
				combat["cc_resistance"] = cc_resist + 1
				messages.append("[color=#FFFF00]You deal %d damage and stun the enemy![/color]" % damage)
			else:
				messages.append("[color=#FFFF00]You deal %d damage but the enemy resists the stun![/color]" % damage)
			if cc_resist > 0:
				messages.append("[color=#808080](Enemy CC resistance: %d%%)[/color]" % (cc_resist * 25))

		"cleave":
			# Buffed: 2.5x damage multiplier (was 2x), sqrt STR scaling.
			# Variable cost: damage AND bleed magnitude scale with spend; duration stays 4 rounds.
			var str_stat = character.get_effective_stat("strength")
			var str_mult = 1.0 + (sqrt(float(str_stat)) / 10.0)
			var base_dmg = int(total_attack * 2.5 * damage_multiplier * str_mult * variable_fraction)
			# Apply mastery + legacy skill enhancement (rank 0 = -20%, rank 4 = +20%)
			var cleave_skill_bonus = character.get_skill_damage_bonus("cleave")
			base_dmg = apply_skill_damage_bonus(character, "cleave", base_dmg)
			if cleave_skill_bonus > 0:
				messages.append("[color=#00FFFF]Skill Enhancement: +%d%% damage![/color]" % int(cleave_skill_bonus))
			var mod_dmg = apply_ability_damage_modifiers(base_dmg, character.level, monster)
			var damage = apply_damage_variance(mod_dmg)
			monster.current_hp -= damage
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#FF4444]CLEAVE![/color]")
			messages.append("[color=#FFFF00]Your massive swing deals %d damage![/color]" % damage)
			# Apply bleed DoT (20% of STR per round, scaled by spend, for 4 rounds)
			var bleed_damage = max(1, int(str_stat * 0.20 * variable_fraction))
			combat["monster_bleed"] = bleed_damage
			combat["monster_bleed_duration"] = 4
			messages.append("[color=#FF4444]The target is bleeding! (%d damage/round for 4 rounds)[/color]" % bleed_damage)

		"berserk":
			# Variable cost (v0.9.263): BOTH buff and penalty scale by spend.
			# "Same risk shape, smaller stakes" — partial berserk = smaller
			# damage swing AND smaller defense exposure. Duration stays 4 rounds.
			var hp_percent = float(character.current_hp) / float(character.get_total_max_hp())
			var missing_hp_percent = 1.0 - hp_percent
			var damage_bonus = max(1, int((75 + (missing_hp_percent * 125)) * variable_fraction))
			var defense_penalty = int(-40 * variable_fraction)
			character.add_buff("damage", damage_bonus, 4)
			character.add_buff("defense_penalty", defense_penalty, 4)
			messages.append("[color=#FF0000][b]BERSERK![/b][/color]")
			messages.append("[color=#FFD700]+%d%% damage (scales with missing HP), %d%% defense for 4 rounds![/color]" % [damage_bonus, defense_penalty])

		"iron_skin":
			# Variable cost (v0.9.263): reduction magnitude scales with spend.
			# Duration stays 4 rounds.
			var iron_skin_reduction = max(1, int(60 * variable_fraction))
			character.add_buff("damage_reduction", iron_skin_reduction, 4)
			messages.append("[color=#AAAAAA]IRON SKIN![/color]")
			messages.append("[color=#00FF00]Block %d%% damage for 4 rounds![/color]" % iron_skin_reduction)
			is_buff_ability = true

		"devastate":
			# Buffed: 5x damage (was 4x), sqrt STR scaling.
			# Variable cost: pure damage scaling (no secondary effects).
			var str_stat = character.get_effective_stat("strength")
			var str_mult = 1.0 + (sqrt(float(str_stat)) / 10.0)
			var base_dmg = int(total_attack * 5.0 * damage_multiplier * str_mult * variable_fraction)
			# Apply mastery + legacy skill enhancement (rank 0 = -20%, rank 4 = +20%)
			var dev_skill_bonus = character.get_skill_damage_bonus("devastate")
			base_dmg = apply_skill_damage_bonus(character, "devastate", base_dmg)
			if dev_skill_bonus > 0:
				messages.append("[color=#00FFFF]Skill Enhancement: +%d%% damage![/color]" % int(dev_skill_bonus))
			var mod_dmg = apply_ability_damage_modifiers(base_dmg, character.level, monster)
			var damage = apply_damage_variance(mod_dmg)
			monster.current_hp -= damage
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#FF0000][b]DEVASTATE![/b][/color]")
			messages.append("[color=#FFFF00]A catastrophic blow deals %d damage![/color]" % damage)

		"fortify":
			# Variable cost (v0.9.263): defense magnitude scales with spend.
			# Duration stays 5 rounds.
			var str_stat = character.get_effective_stat("strength")
			var defense_bonus = max(1, int((30 + sqrt(float(str_stat)) * 3) * variable_fraction))
			character.add_buff("defense", defense_bonus, 5)
			messages.append("[color=#00FFFF]You fortify your defenses! (+%d%% defense for 5 rounds)[/color]" % defense_bonus)
			is_buff_ability = true

		"rally":
			# Variable cost (v0.9.263): heal amount AND STR buff both scale with spend.
			# Duration stays 3 rounds.
			var con_stat = character.get_effective_stat("constitution")
			var heal_amount = max(1, int((30 + sqrt(float(con_stat)) * 10) * variable_fraction))
			var actual_heal = character.heal(heal_amount)
			var str_bonus = max(1, int((10 + character.get_effective_stat("strength") / 5) * variable_fraction))
			character.add_buff("strength", str_bonus, 3)
			messages.append("[color=#00FF00]You rally your strength! Healed %d HP, +%d STR for 3 rounds![/color]" % [actual_heal, str_bonus])
			is_buff_ability = true

	# Check if monster died
	if monster.current_hp <= 0:
		return _process_victory(combat, messages)

	return {"success": true, "messages": messages, "combat_ended": false, "buff_ability": is_buff_ability}

func _process_trickster_ability(combat: Dictionary, ability_name: String) -> Dictionary:
	"""Process trickster abilities (use energy)"""
	var character = combat.character
	var monster = combat.monster
	var messages = []
	var is_buff_ability = false  # Buff/debuff abilities only give monster 25% chance to attack

	# Check WITS requirement for trickster path
	if character.get_stat("wits") <= 10:
		return {"success": false, "messages": ["[color=#FF4444]You need WITS > 10 to use trickster abilities![/color]"], "combat_ended": false}

	# Get ability info
	var ability_info = _get_ability_info("trickster", ability_name)
	if ability_info.is_empty():
		return {"success": false, "messages": ["[color=#FF4444]Unknown trickster ability![/color]"], "combat_ended": false}

	# Mastery Slice 1 — level gate removed; rank scales effective power.

	# Audit #1 variable-cost rework — abilities in VARIABLE_COST_TABLE (ambush,
	# exploit, gambit in v0.9.261) take the variable-cost path. Other Trickster
	# abilities stay on the fixed-cost flow below.
	var variable_fraction: float = 1.0
	if VARIABLE_COST_TABLE.has(ability_name):
		var vc_result = apply_variable_cost(character, ability_name, combat)
		for vc_msg in vc_result.get("messages", []):
			messages.append(vc_msg)
		if not vc_result.get("ok", false):
			return {"success": false, "messages": messages, "combat_ended": false, "skip_monster_turn": true}
		variable_fraction = float(vc_result.get("fraction", 1.0))
	else:
		var base_energy_cost = ability_info.cost
		var energy_cost = apply_skill_cost_reduction(character, ability_name, base_energy_cost)

		if energy_cost < base_energy_cost and energy_cost > 0:
			messages.append("[color=#00FFFF]Skill Enhancement: -%d%% cost![/color]" % int(character.get_skill_cost_reduction(ability_name)))
		elif energy_cost == 0 and base_energy_cost > 0:
			messages.append("[color=#00FFFF]Skill Enhancement: FREE![/color]")

		if not character.use_energy(energy_cost):
			return {"success": false, "messages": ["[color=#FF4444]Not enough energy! (Need %d)[/color]" % energy_cost], "combat_ended": false, "skip_monster_turn": true}

	match ability_name:
		"analyze":
			messages.append("[color=#00FF00]ANALYZE![/color]")
			messages.append("[color=#808080]%s (Level %d)[/color]" % [monster.name, monster.level])
			messages.append("[color=#FF4444]HP:[/color] %d/%d" % [monster.current_hp, monster.max_hp])
			messages.append("[color=#FFFF00]Damage:[/color] ~%d" % monster.strength)
			var monster_int = monster.get("intelligence", 15)
			messages.append("[color=#FFA500]Intelligence:[/color] %d" % monster_int)

			# Calculate and show outsmart chance (must match process_outsmart formula)
			var player_wits = character.get_effective_stat("wits")
			var is_trickster = character.class_type in ["Thief", "Ranger", "Ninja"]
			var player_level = character.level
			var monster_level = monster.level
			var base_chance = 5
			# Logarithmic WITS scaling
			var wits_bonus = 0
			if player_wits > 10:
				wits_bonus = int(18.0 * log(float(player_wits) / 10.0) / log(2.0))
			var trickster_bonus = 20 if is_trickster else 0
			var dumb_bonus = max(0, (10 - monster_int) * 3)
			var smart_penalty = max(0, monster_int - 10)  # -1% per INT above 10
			var int_vs_wits_penalty = max(0, (monster_int - player_wits) * 2)
			# Level difference penalty
			var level_diff = monster_level - player_level
			var level_penalty = 0
			if level_diff > 0:
				if level_diff <= 10:
					level_penalty = level_diff * 2
				elif level_diff <= 50:
					level_penalty = 20 + (level_diff - 10)
				else:
					level_penalty = 60 + int((level_diff - 50) * 0.5)
			var level_bonus = 0
			if level_diff < 0:
				level_bonus = min(15, abs(level_diff))
			var outsmart_chance = base_chance + wits_bonus + trickster_bonus + dumb_bonus + level_bonus - smart_penalty - int_vs_wits_penalty - level_penalty
			# INT-based cap
			var base_max_chance = 85 if is_trickster else 70
			var max_chance = max(30, base_max_chance - int(monster_int / 3))
			outsmart_chance = clampi(outsmart_chance, 2, max_chance)
			var level_warning = ""
			if level_diff > 10:
				level_warning = " [color=#FF4444](Lv%+d penalty!)[/color]" % level_diff
			elif level_diff > 0:
				level_warning = " [color=#FFA500](Lv%+d)[/color]" % level_diff
			messages.append("[color=#00FFFF]Outsmart Chance:[/color] %d%%%s" % [outsmart_chance, level_warning])

			# Grant +10% damage bonus for rest of combat
			combat["analyze_bonus"] = 10
			messages.append("[color=#00FF00]+10%% damage bonus for this combat![/color]" % [])
			# Skip monster turn for analyze (information only)
			# Include revealed HP data for client health bar update
			return {
				"success": true,
				"messages": messages,
				"combat_ended": false,
				"skip_monster_turn": true,
				"revealed_enemy_hp": monster.max_hp,
				"revealed_enemy_current_hp": monster.current_hp
			}

		"distract":
			# Variable cost (v0.9.265): accuracy debuff magnitude scales with spend.
			# Stored as int percent (was bool flag pre-0.9.265). Consumer in
			# process_monster_turn reads the int and applies accordingly.
			var distract_pct = max(1, int(50 * variable_fraction))
			combat["enemy_distracted"] = distract_pct
			messages.append("[color=#00FF00]DISTRACT![/color]")
			messages.append("[color=#808080]The enemy is distracted! (-%d%% accuracy)[/color]" % distract_pct)
			is_buff_ability = true

		"pickpocket":
			# Check if monster has anything left to steal
			var pp_count = combat.get("pickpocket_count", 0)
			var pp_max = combat.get("pickpocket_max", 2)
			if pp_count >= pp_max:
				messages.append("[color=#808080]The enemy has nothing left to steal![/color]")
				return {"success": true, "messages": messages, "combat_ended": false, "skip_monster_turn": false}
			# Variable cost (v0.9.265): success CHANCE scales with spend. Ore
			# quantity stays as-is — pp_max cap per fight already limits reward.
			var wits = character.get_effective_stat("wits")
			var raw_chance = 50 + wits - monster.get("intelligence", 15)
			raw_chance = clampi(raw_chance, 10, 90)
			var success_chance = max(1, int(raw_chance * variable_fraction))
			var roll = randi() % 100
			if roll < success_chance:
				combat["pickpocket_count"] = pp_count + 1
				# Steal crafting materials based on monster tier
				var monster_tier = monster.get("tier", 1)
				var ore_tiers = ["copper_ore", "iron_ore", "steel_ore", "mithril_ore", "adamantine_ore", "orichalcum_ore", "void_ore", "celestial_ore", "primordial_ore"]
				var ore_id = ore_tiers[mini(monster_tier - 1, ore_tiers.size() - 1)]
				var stolen_qty = randi_range(1, 2) + (monster_tier / 3)
				character.add_crafting_material(ore_id, stolen_qty)
				var mat_name = ore_id.replace("_", " ").capitalize()
				messages.append("[color=#00FF00]PICKPOCKET SUCCESS![/color]")
				messages.append("[color=#FFD700]You steal %dx %s![/color]" % [stolen_qty, mat_name])
				return {"success": true, "messages": messages, "combat_ended": false, "skip_monster_turn": true}
			else:
				messages.append("[color=#FF4444]PICKPOCKET FAILED![/color]")
				messages.append("[color=#808080]The enemy catches you![/color]")
				# Enemy gets free attack
				var monster_result = process_monster_turn(combat)
				messages.append("[color=#444444]─────────────────────────────[/color]")
				messages.append(_indent_multiline(monster_result.message, "         "))
				messages.append("[color=#444444]─────────────────────────────[/color]")
				if character.current_hp <= 0:
					return {
						"success": true,
						"messages": messages,
						"combat_ended": true,
						"victory": false,
						"monster_name": "%s (Lvl %d)" % [monster.name, monster.level]
					}
				return {"success": true, "messages": messages, "combat_ended": false, "skip_monster_turn": true}

		"ambush":
			# Ambush: 3x multiplier, 50% crit chance, sqrt WITS scaling.
			# Variable cost (v0.9.261): damage scales by spend; crit chance stays 50%
			# (binary mechanic — partial ambush still has the full crit potential).
			var wits_stat = character.get_effective_stat("wits")
			var wits_mult = 1.0 + (sqrt(float(wits_stat)) / 10.0)  # Sqrt scaling for WITS
			var base_damage = character.get_total_attack()
			var damage_buff = character.get_buff_value("damage")
			var damage_multiplier = 1.0 + (damage_buff / 100.0)
			var base_dmg = int(base_damage * 3.0 * damage_multiplier * wits_mult * variable_fraction)
			# Apply mastery + legacy skill enhancement (rank 0 = -20%, rank 4 = +20%)
			var ambush_skill_bonus = character.get_skill_damage_bonus("ambush")
			base_dmg = apply_skill_damage_bonus(character, "ambush", base_dmg)
			if ambush_skill_bonus > 0:
				messages.append("[color=#00FFFF]Skill Enhancement: +%d%% damage![/color]" % int(ambush_skill_bonus))
			var mod_dmg = apply_ability_damage_modifiers(base_dmg, character.level, monster)
			var damage = apply_damage_variance(mod_dmg)
			# 50% crit chance
			if randi() % 100 < 50:
				damage = int(damage * 1.5)
				messages.append("[color=#FFD700]CRITICAL AMBUSH![/color]")
			else:
				messages.append("[color=#00FF00]AMBUSH![/color]")
			monster.current_hp -= damage
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#FFFF00]You deal %d damage![/color]" % damage)

		"vanish":
			# Auto-crit on next attack, skips monster turn
			combat["vanished"] = true  # Next attack auto-crits
			messages.append("[color=#00FF00]VANISH![/color]")
			messages.append("[color=#808080]You fade into shadow... Next attack will crit![/color]")
			return {"success": true, "messages": messages, "combat_ended": false, "skip_monster_turn": true}

		"exploit":
			# Uses monster's MAX HP, scales with WITS (15-35%).
			# Variable cost (v0.9.261): damage scales by spend AFTER the percent
			# calc, so a partial exploit on a beefy monster still does a
			# proportional chunk of max HP.
			var wits = character.get_effective_stat("wits")
			var base_percent = 15 + int(wits / 4)  # 15% base + 0.25% per WIT
			base_percent = min(35, base_percent)  # Cap at 35%
			var raw_damage = int(monster.max_hp * (base_percent / 100.0) * variable_fraction)
			raw_damage = max(10, raw_damage)  # Minimum 10 damage
			# Apply mastery + legacy skill enhancement (rank 0 = -20%, rank 4 = +20%)
			var exploit_skill_bonus = character.get_skill_damage_bonus("exploit")
			var damage = apply_skill_damage_bonus(character, "exploit", raw_damage)
			if exploit_skill_bonus > 0:
				messages.append("[color=#00FFFF]Skill Enhancement: +%d%% damage![/color]" % int(exploit_skill_bonus))
			monster.current_hp -= damage
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#00FF00]EXPLOIT WEAKNESS![/color]")
			messages.append("[color=#FFFF00]You exploit a weakness for %d damage! (%d%% of max HP)[/color]" % [damage, base_percent])

		"perfect_heist":
			# Chance-based instant win with slight bonus rewards.
			# Variable cost (v0.9.265): success CHANCE scales with spend.
			# Already chance-based (5-60% cap), scaling makes floor casts
			# mostly miss — that's the trickster's high-risk play.
			var wits = character.get_effective_stat("wits")
			var monster_int = monster.get("intelligence", 15)
			var level_diff = monster.level - character.level

			# Base 30% success, +1.5% per wits over monster intelligence
			var raw_heist_chance = 30 + int((wits - monster_int) * 1.5)
			# Heavy penalty for fighting above your level: -2% per level difference
			if level_diff > 0:
				raw_heist_chance -= level_diff * 2
			# Cap at 5-60% (was 20-90%)
			raw_heist_chance = clampi(raw_heist_chance, 5, 60)
			var success_chance = max(1, int(raw_heist_chance * variable_fraction))

			var roll = randi() % 100
			if roll < success_chance:
				messages.append("[color=#FFD700][b]PERFECT HEIST![/b][/color]")
				messages.append("[color=#00FF00]You execute a flawless heist![/color]")

				# Slight bonus XP (1.25x, was 2x)
				var base_xp = int(monster.experience_reward * 1.25)
				# Small bonus for level difference, capped at 1.5x max
				var xp_multiplier = 1.0
				if level_diff > 0:
					xp_multiplier = 1.0 + min(0.5, level_diff * 0.02)  # +2% per level, max +50%

				var final_xp = int(base_xp * xp_multiplier * 1.10)  # +10% XP boost

				var heist_old_level = character.level
				var level_result = character.add_experience(final_xp)

				messages.append("[color=#FF00FF]+%d XP[/color]" % final_xp)

				if level_result.leveled_up:
					messages.append("[color=#FFD700][b]LEVEL UP![/b] You are now level %d![/color]" % level_result.new_level)

					# Check for newly unlocked abilities
					var new_abilities = character.get_newly_unlocked_abilities(heist_old_level, level_result.new_level)
					if new_abilities.size() > 0:
						messages.append("")
						messages.append("[color=#00FFFF]+======================================+[/color]")
						messages.append("[color=#00FFFF]|[/color]  [color=#FFFF00][b]NEW ABILITY UNLOCKED![/b][/color]")
						for ability in new_abilities:
							var ability_type = "Universal" if ability.get("universal", false) else "Class"
							messages.append("[color=#00FFFF]|[/color]  [color=#00FF00]*[/color] [color=#FFFFFF]%s[/color] [color=#808080](%s)[/color]" % [ability.display, ability_type])
						messages.append("[color=#00FFFF]|[/color]  [color=#808080]Check Abilities menu to equip![/color]")
						messages.append("[color=#00FFFF]+======================================+[/color]")

				# Roll for item drops (normal chance, was doubled)
				var dropped_items = []
				var gems_earned = 0
				if drop_tables:
					var drops_result = drop_tables.roll_drops(
						monster.get("drop_table_id", "tier1"),
						monster.get("drop_chance", 5),
						monster.level
					)
					dropped_items = drops_result
					gems_earned = roll_gem_drops(monster, character)
					if gems_earned > 0:
						character.add_crafting_material("monster_gem", gems_earned)
						messages.append("[color=#00FFFF]+ + [/color][color=#FF00FF]+%d Monster Gem%s![/color][color=#00FFFF] + +[/color]" % [gems_earned, "s" if gems_earned > 1 else ""])

				return {
					"success": true,
					"messages": messages,
					"combat_ended": true,
					"victory": true,
					"monster_name": monster.name,
					"monster_level": monster.level,
					"flock_chance": 0,  # No flock after perfect heist
					"dropped_items": dropped_items,
					"gems_earned": gems_earned,
					"skip_monster_turn": true,
					"is_dungeon_combat": combat.get("is_dungeon_combat", false),
					"is_boss_fight": combat.get("is_boss_fight", false)
				}
			else:
				# Failed heist - take damage and combat continues
				messages.append("[color=#FF4444][b]HEIST FAILED![/b][/color]")
				messages.append("[color=#FF4444]You're caught mid-heist![/color]")
				# Monster gets a free attack
				var monster_result = process_monster_turn(combat)
				messages.append("[color=#444444]─────────────────────────────[/color]")
				messages.append(_indent_multiline(monster_result.message, "         "))
				messages.append("[color=#444444]─────────────────────────────[/color]")
				if character.current_hp <= 0:
					return {
						"success": true,
						"messages": messages,
						"combat_ended": true,
						"victory": false,
						"monster_name": "%s (Lvl %d)" % [monster.name, monster.level]
					}
				return {"success": true, "messages": messages, "combat_ended": false, "skip_monster_turn": true}

		"sabotage":
			# Weaken monster - reduce strength and defense.
			# Variable cost (v0.9.265): debuff magnitude scales with spend.
			# 50% stack cap unchanged.
			var wits = character.get_effective_stat("wits")
			var debuff_amount = max(1, int((15 + wits / 3) * variable_fraction))
			# Store debuffs in combat state
			var existing_sabotage = combat.get("monster_sabotaged", 0)
			combat["monster_sabotaged"] = min(50, existing_sabotage + debuff_amount)  # Cap at 50%
			messages.append("[color=#FFA500]You sabotage the %s! (-%d%% strength/defense)[/color]" % [monster.name, debuff_amount])
			is_buff_ability = true

		"gambit":
			# High-risk, high-reward ability - big damage with WITS scaling, bonus loot on kill
			var wits = character.get_effective_stat("wits")
			var success_chance = 55 + int(wits / 4)  # 55% base + 0.25% per WITS
			success_chance = min(80, success_chance)  # Cap at 80%

			if randf() * 100 < success_chance:
				# Success - deal big damage with WITS scaling (4.5x multiplier).
				# Variable cost (v0.9.261): damage scales by spend. Success chance
				# stays constant — partial gambit is "same odds, smaller stakes".
				var wits_mult = 1.0 + (sqrt(float(wits)) / 10.0)  # Same scaling as Ambush
				var total_attack = character.get_total_attack() + character.get_buff_value("strength")
				var damage_buff = character.get_buff_value("damage")
				var damage_multiplier = 1.0 + (damage_buff / 100.0)
				var base_dmg = int(total_attack * 4.5 * damage_multiplier * wits_mult * variable_fraction)
				# Apply mastery + legacy skill enhancement (rank 0 = -20%, rank 4 = +20%)
				var gambit_skill_bonus = character.get_skill_damage_bonus("gambit")
				base_dmg = apply_skill_damage_bonus(character, "gambit", base_dmg)
				if gambit_skill_bonus > 0:
					messages.append("[color=#00FFFF]Skill Enhancement: +%d%% damage![/color]" % int(gambit_skill_bonus))
				var mod_dmg = apply_ability_damage_modifiers(base_dmg, character.level, monster)
				var damage = apply_damage_variance(mod_dmg)
				monster.current_hp -= damage
				monster.current_hp = max(0, monster.current_hp)
				messages.append("[color=#FFD700][b]GAMBIT SUCCESS![/b][/color]")
				messages.append("[color=#00FF00]Your risky gambit pays off for %d damage![/color]" % damage)
				# Mark for bonus loot if this kills the monster
				if monster.current_hp <= 0:
					combat["gambit_kill"] = true
			else:
				# Failure - take damage yourself (15% max HP, scaled by spend).
				# Variable cost: smaller gambits hurt proportionally less on miss.
				var self_damage = max(5, int(character.get_total_max_hp() * 0.15 * variable_fraction))
				character.current_hp -= self_damage
				character.current_hp = max(1, character.current_hp)  # Can't kill yourself
				messages.append("[color=#FF4444][b]GAMBIT FAILED![/b][/color]")
				messages.append("[color=#FF4444]Your gambit backfires for %d self-damage![/color]" % self_damage)

	# Check if monster died
	if monster.current_hp <= 0:
		return _process_victory(combat, messages)

	return {"success": true, "messages": messages, "combat_ended": false, "buff_ability": is_buff_ability}

func _get_ability_info(path: String, ability_name: String) -> Dictionary:
	"""Get ability info from constants"""
	# Universal abilities (available to all paths)
	match ability_name:
		"cloak": return {"level": 20, "cost": 0, "name": "Cloak", "universal": true}
		"all_or_nothing": return {"level": 1, "cost": 1, "name": "All or Nothing", "universal": true}

	match path:
		"mage":
			# Mage abilities use percentage-based mana costs for late-game scaling
			match ability_name:
				"magic_bolt": return {"level": 1, "cost": 0, "cost_percent": 0, "name": "Magic Bolt"}
				# Shield removed - use Forcefield instead
				"haste": return {"level": 30, "cost": 35, "cost_percent": 3, "name": "Haste"}
				"blast": return {"level": 40, "cost": 50, "cost_percent": 5, "name": "Blast"}
				"paralyze": return {"level": 50, "cost": 60, "cost_percent": 6, "name": "Paralyze"}
				"forcefield": return {"level": 10, "cost": 20, "cost_percent": 2, "name": "Forcefield"}
				"banish": return {"level": 70, "cost": 80, "cost_percent": 10, "name": "Banish"}
				"teleport": return {"level": 80, "cost": 40, "cost_percent": 0, "name": "Teleport"}  # Uses distance-based cost
				"meteor": return {"level": 100, "cost": 100, "cost_percent": 8, "name": "Meteor"}
		"warrior":
			match ability_name:
				"power_strike": return {"level": 1, "cost": 10, "name": "Power Strike"}
				"war_cry": return {"level": 10, "cost": 15, "name": "War Cry"}
				"shield_bash": return {"level": 25, "cost": 20, "name": "Shield Bash"}
				"fortify": return {"level": 35, "cost": 25, "name": "Fortify"}
				"cleave": return {"level": 40, "cost": 30, "name": "Cleave"}
				"rally": return {"level": 55, "cost": 35, "name": "Rally"}
				"berserk": return {"level": 60, "cost": 40, "name": "Berserk"}
				"iron_skin": return {"level": 80, "cost": 35, "name": "Iron Skin"}
				"devastate": return {"level": 100, "cost": 50, "name": "Devastate"}
		"trickster":
			match ability_name:
				"analyze": return {"level": 1, "cost": 5, "name": "Analyze"}
				"distract": return {"level": 10, "cost": 15, "name": "Distract"}
				"pickpocket": return {"level": 25, "cost": 20, "name": "Pickpocket"}
				"sabotage": return {"level": 30, "cost": 25, "name": "Sabotage"}
				"ambush": return {"level": 40, "cost": 30, "name": "Ambush"}
				"gambit": return {"level": 50, "cost": 35, "name": "Gambit"}
				"vanish": return {"level": 60, "cost": 40, "name": "Vanish"}
				"exploit": return {"level": 80, "cost": 35, "name": "Exploit"}
				"perfect_heist": return {"level": 100, "cost": 50, "name": "Perfect Heist"}
	return {}

func _process_victory(combat: Dictionary, messages: Array) -> Dictionary:
	"""Process monster defeat and return victory result - redirects to ability-aware version"""
	return _process_victory_with_abilities(combat, messages)

func apply_skill_cost_reduction(character: Character, ability_name: String, base_cost: int) -> int:
	"""Apply skill enhancement cost reduction and racial bonuses to an ability's cost.
	Returns the reduced cost (minimum 1 unless reduction is 100%)."""
	var cost = base_cost

	# Gnome racial: -15% ability costs
	var racial_mult = character.get_ability_cost_multiplier()
	if racial_mult < 1.0:
		cost = int(cost * racial_mult)

	# Skill enhancement cost reduction
	var cost_reduction = character.get_skill_cost_reduction(ability_name)
	if cost_reduction >= 100:
		return 0  # Free ability!
	if cost_reduction > 0:
		cost = int(cost * (1.0 - cost_reduction / 100.0))

	return max(1, cost)

func apply_variable_cost(character: Character, ability_name: String, combat: Dictionary) -> Dictionary:
	"""Audit #1 variable-cost rework — spend max-affordable up to ceiling,
	fail if below floor. Returns {ok, spent, fraction, messages}.
	Fraction is VARIABLE_COST_MIN_FRACTION at floor → 1.0 at ceiling (linear).
	Applies same cost reductions as the fixed-cost path (racial, skill enhancement,
	class passives) to both floor + ceiling so the curve scales with build.
	On ok: the resource has already been spent on the character."""
	var result := {"ok": false, "spent": 0, "fraction": 0.0, "messages": [] as Array}
	if not VARIABLE_COST_TABLE.has(ability_name):
		result.messages.append("[color=#FF4444]Ability %s missing from variable-cost table![/color]" % ability_name)
		return result
	var entry: Dictionary = VARIABLE_COST_TABLE[ability_name]
	var base_ceiling: int = int(entry.get("ceiling", 10))
	var floor_ratio: float = float(entry.get("floor_ratio", VARIABLE_COST_MIN_FRACTION))
	var cost_percent: int = int(entry.get("cost_percent", 0))
	var resource_type: String = str(entry.get("resource", "stamina"))

	# Mage percentage-cost scaling: ceiling = max(base, max_mana * percent / 100).
	# Matches the existing fixed-cost mage flow so late-game mages still see
	# scaling. Only applies to mana abilities.
	if resource_type == "mana" and cost_percent > 0:
		var percent_cost = int(character.get_total_max_mana() * cost_percent / 100.0)
		base_ceiling = max(base_ceiling, percent_cost)
	var base_floor: int = max(1, int(base_ceiling * floor_ratio))

	# Apply skill enhancement + racial reduction proportionally to both
	var adj_floor = apply_skill_cost_reduction(character, ability_name, base_floor)
	var adj_ceiling = apply_skill_cost_reduction(character, ability_name, base_ceiling)
	var skill_reduction = character.get_skill_cost_reduction(ability_name)
	if skill_reduction > 0:
		result.messages.append("[color=#00FFFF]Skill Enhancement: -%d%% cost![/color]" % int(skill_reduction))

	# Apply class passive cost modifiers
	var passive = character.get_class_passive()
	var passive_effects = passive.get("effects", {})
	var reduction_key := ""
	var increase_key := ""
	match resource_type:
		"stamina":
			reduction_key = "stamina_cost_reduction"
			increase_key = "stamina_cost_increase"
		"mana":
			reduction_key = "mana_cost_reduction"
		"energy":
			reduction_key = "energy_cost_reduction"
	if reduction_key != "" and passive_effects.has(reduction_key):
		var red = passive_effects.get(reduction_key, 0)
		adj_floor = max(1, int(adj_floor * (1.0 - red)))
		adj_ceiling = max(1, int(adj_ceiling * (1.0 - red)))
		result.messages.append("[color=#C0C0C0]Tactical Discipline: -%d%% cost![/color]" % int(red * 100))
	if increase_key != "" and passive_effects.has(increase_key):
		var inc = passive_effects.get(increase_key, 0)
		adj_floor = int(adj_floor * (1.0 + inc))
		adj_ceiling = int(adj_ceiling * (1.0 + inc))

	# Read available resource
	var current = 0
	match resource_type:
		"stamina": current = character.current_stamina
		"mana": current = character.current_mana
		"energy": current = character.current_energy
		_:
			result.messages.append("[color=#FF4444]Unknown resource type %s![/color]" % resource_type)
			return result

	if current < adj_floor:
		result.messages.append("[color=#FF4444]Not enough %s! (Need at least %d, you have %d)[/color]" % [resource_type, adj_floor, current])
		return result

	var spend = min(current, adj_ceiling)
	var fraction: float
	if adj_ceiling > adj_floor:
		fraction = VARIABLE_COST_MIN_FRACTION + (1.0 - VARIABLE_COST_MIN_FRACTION) * float(spend - adj_floor) / float(adj_ceiling - adj_floor)
	else:
		fraction = 1.0
	fraction = clamp(fraction, VARIABLE_COST_MIN_FRACTION, 1.0)

	# Spend the resource
	match resource_type:
		"stamina": character.use_stamina(spend)
		"mana": character.use_mana(spend)
		"energy": character.use_energy(spend)

	result.ok = true
	result.spent = spend
	result.fraction = fraction
	# Partial-cast banner — only when fraction is meaningfully below 1.0
	if fraction < 0.99:
		result.messages.append("[color=#FFA500]Partial cast — %d/%d %s (%d%% effect).[/color]" % [spend, adj_ceiling, resource_type, int(fraction * 100)])
	return result

func apply_skill_damage_bonus(character: Character, ability_name: String, base_damage: int) -> int:
	"""Apply mastery + legacy skill_enhancement damage modifier to an
	ability's damage. Mastery Slice 1 stacks the use-progression damage
	multiplier (rank 0 = 0.80, rank 4 = 1.20) on top of any legacy
	skill_enhancements bonus. Slice 4 (v0.9.323) additionally multiplies
	by an off-affinity damage penalty when the ability isn't in the
	character's class path — rank 0 caster of an off-archetype ability gets
	0.80 (mastery) × 0.75 (off-affinity) = 0.60 of baseline damage; rank 4
	erases the penalty entirely. Universal abilities (cloak, all_or_nothing,
	forethought, tactical_retreat, teleport) bypass off-affinity. Returns
	the modified damage."""
	var damage_bonus = character.get_skill_damage_bonus(ability_name)
	var dmg = float(base_damage)
	if damage_bonus > 0:
		dmg = dmg * (1.0 + damage_bonus / 100.0)
	dmg = dmg * character.get_ability_damage_mult(ability_name)
	dmg = dmg * character.get_off_affinity_damage_mult(ability_name)
	return int(dmg)

func process_use_item(peer_id: int, item_index: int, target: String = "self") -> Dictionary:
	"""Process using an item during combat. Returns result with messages.
	target: 'self' (default) or 'companion' — when 'companion' and the item is
	a healing potion, the heal lands on the active companion's persistent
	combat HP instead of the player."""
	if not active_combats.has(peer_id):
		return {"success": false, "message": "You are not in combat!"}

	var combat = active_combats[peer_id]

	if not combat.player_can_act:
		return {"success": false, "message": "Wait for your turn!"}

	var character = combat.character
	var inventory = character.inventory

	if item_index < 0 or item_index >= inventory.size():
		return {"success": false, "message": "Invalid item!"}

	var item = inventory[item_index]
	var item_type = item.get("type", "")

	# Normalize item type for consumables (e.g., mana_minor -> mana_potion)
	var normalized_type = drop_tables._normalize_consumable_type(item_type)
	if normalized_type != item_type:
		item_type = normalized_type

	# Check if item is usable in combat
	if drop_tables == null:
		return {"success": false, "message": "Item system not available!"}

	var effect = drop_tables.get_potion_effect(item_type)
	if effect.is_empty():
		return {"success": false, "message": "This item cannot be used in combat!"}

	var messages = []
	var item_name = item.get("name", "item")
	var item_level = item.get("level", 1)
	var item_tier = int(item.get("tier", 0))  # int() ensures proper dict key lookup (JSON may store as float)

	# Infer tier from item name for legacy tier-based consumables
	if item_tier == 0 and _is_tier_based_consumable(item_type):
		item_tier = _infer_tier_from_name(item_name)

	# Get tier data for proper healing values
	var tier_data = {}
	if item_tier > 0 and drop_tables.CONSUMABLE_TIERS.has(item_tier):
		tier_data = drop_tables.CONSUMABLE_TIERS[item_tier]

	# Apply effect
	# Check for crafted item's own effect data (quality-scaled amounts from recipe)
	var item_effect = item.get("effect", {})
	if effect.has("companion_taunt"):
		# Taunt Charm — companion draws extra aggro for next N monster turns.
		# Validate: companion must exist and not be KO'd (no aggro to draw).
		if not character.has_active_companion():
			return {"success": false, "message": "You have no active companion to taunt with."}
		if character.is_companion_ko():
			return {"success": false, "message": "Your companion is knocked out — revive them first."}
		var aggro_bonus: int = int(effect.get("aggro_bonus", 30))
		var taunt_turns: int = int(effect.get("turns", 3))
		# Apply additively if a charm is already active (stacking caps at the
		# 80% aggro clamp anyway, so this is safe).
		combat["companion_taunt_bonus"] = int(combat.get("companion_taunt_bonus", 0)) + aggro_bonus
		combat["companion_taunt_turns"] = maxi(int(combat.get("companion_taunt_turns", 0)), taunt_turns)
		var comp_name: String = str(character.active_companion.get("name", "your companion"))
		messages.append("[color=#FFD700]You crush the %s![/color]" % item_name)
		messages.append("[color=#FF8800]%s glows with menace — drawing +%d%% aggro for %d turns![/color]" % [comp_name, aggro_bonus, taunt_turns])
	elif effect.has("revive_companion"):
		# Companion Revive Potion — instantly revives a KO'd active companion
		# at revive_pct% of max HP. In-combat path: consumes the player's turn.
		if not character.has_active_companion():
			return {"success": false, "message": "You have no active companion to revive."}
		if not character.is_companion_ko():
			return {"success": false, "message": "Your companion isn't knocked out — no need to use this."}
		var revive_pct: int = int(effect.get("revive_pct", 50))
		var comp_max: int = character.get_companion_max_hp()
		var revive_hp: int = maxi(1, int(comp_max * revive_pct / 100.0))
		character.set_companion_combat_hp(revive_hp)
		var comp_name: String = str(character.active_companion.get("name", "your companion"))
		messages.append("[color=#FFD700]You use the %s![/color]" % item_name)
		messages.append("[color=#00FF00]Your %s rises with %d/%d HP![/color]" % [comp_name, revive_hp, comp_max])
	elif effect.has("heal"):
		# Phase B1 — KO'd companion can only be revived by a healer / NPC,
		# never by potions or natural regen. Reject here with a clear msg
		# instead of silently consuming the potion.
		if target == "companion" and character.has_active_companion() and character.is_companion_ko():
			return {"success": false, "message": "Your companion is knocked out and can only be revived by a healer."}
		# Healing potion - hybrid flat + % max HP
		var heal_amount: int
		# When targeting a companion, use the companion's max HP for the
		# percentage-based portion so a tier-3 potion heals roughly the same
		# fraction of the companion as it would the player.
		var heal_max_hp: int = character.get_total_max_hp()
		if target == "companion" and character.has_active_companion():
			heal_max_hp = character.get_companion_max_hp()
		if effect.get("heal_pct_only", false):
			# Elixir: pure % max HP heal
			var elixir_pct = effect.get("elixir_pct", drop_tables.ELIXIR_HEAL_PCT.get(item_tier, 50))
			heal_amount = int(heal_max_hp * elixir_pct / 100.0)
		elif item_effect.get("type", "") == "heal" and item_effect.has("amount"):
			# Crafted potion: use item's own quality-scaled amount
			heal_amount = int(item_effect.get("amount", 0))
		elif tier_data.has("healing"):
			# Tier-based: flat + % max HP
			heal_amount = tier_data.healing + int(heal_max_hp * tier_data.get("heal_pct", 0) / 100.0)
		else:
			heal_amount = effect.get("base", 0) + (effect.get("per_level", 0) * item_level)
		var heal_verb = "use" if "scroll" in item_type else "drink"
		if target == "companion" and character.has_active_companion():
			var actual_heal: int = character.heal_companion(heal_amount)
			var comp_name: String = str(character.active_companion.get("name", "your companion"))
			messages.append("[color=#00FF00]You %s %s and your %s recovers %d HP![/color]" % [heal_verb, item_name, comp_name, actual_heal])
		else:
			var actual_heal = character.heal(heal_amount)
			messages.append("[color=#00FF00]You %s %s and restore %d HP![/color]" % [heal_verb, item_name, actual_heal])
	elif effect.has("mana") or effect.has("stamina") or effect.has("energy") or effect.has("resource"):
		# Resource potion - restores the player's PRIMARY resource based on class path
		var primary_resource = character.get_primary_resource()
		var max_resource: int
		match primary_resource:
			"mana": max_resource = character.get_total_max_mana()
			"stamina": max_resource = character.get_total_max_stamina()
			"energy": max_resource = character.get_total_max_energy()
			_: max_resource = character.get_total_max_mana()

		# Hybrid flat + % max resource
		var resource_amount: int
		var item_effect_type = item_effect.get("type", "")
		if item_effect_type in ["restore_mana", "restore_stamina", "restore_energy"] and item_effect.has("amount"):
			# Crafted potion: use item's own quality-scaled amount
			resource_amount = int(item_effect.get("amount", 0))
		elif tier_data.has("resource"):
			resource_amount = tier_data.resource + int(max_resource * tier_data.get("resource_pct", 0) / 100.0)
		elif tier_data.has("healing"):
			resource_amount = int(tier_data.healing * 0.6)
		else:
			resource_amount = effect.get("base", 0) + (effect.get("per_level", 0) * item_level)

		var old_value: int
		var actual_restore: int
		var color: String

		match primary_resource:
			"mana":
				old_value = character.current_mana
				character.current_mana = min(character.get_total_max_mana(), character.current_mana + resource_amount)
				actual_restore = character.current_mana - old_value
				color = "#00FFFF"
			"stamina":
				old_value = character.current_stamina
				character.current_stamina = min(character.get_total_max_stamina(), character.current_stamina + resource_amount)
				actual_restore = character.current_stamina - old_value
				color = "#FFCC00"
			"energy":
				old_value = character.current_energy
				character.current_energy = min(character.get_total_max_energy(), character.current_energy + resource_amount)
				actual_restore = character.current_energy - old_value
				color = "#66FF66"
			_:
				old_value = character.current_mana
				character.current_mana = min(character.get_total_max_mana(), character.current_mana + resource_amount)
				actual_restore = character.current_mana - old_value
				color = "#00FFFF"
				primary_resource = "mana"

		var resource_verb = "use" if "scroll" in item_type else "drink"
		messages.append("[color=%s]You %s %s and restore %d %s![/color]" % [color, resource_verb, item_name, actual_restore, primary_resource])
	elif effect.has("buff"):
		# Buff scroll - tier-based values
		var buff_type = effect.buff
		var buff_value: int = 0
		var duration: int = 0
		# Set true when the crafted-scroll branch has already applied + emitted
		# its message — skips the tier-formula apply block at the bottom.
		var crafted_buff_handled: bool = false

		# Crafted buff scrolls: bypass tier formulas entirely and apply the
		# exact values shown on inspect (effect.amount or effect.bonus_pct +
		# effect.duration or effect.duration_battles). The existing
		# stat_pct / tier_value branches assume tier_data is populated, which
		# isn't the case for crafted items. This keeps inspect = applied.
		if item.get("crafted", false) and item_effect.get("type", "") == "buff":
			buff_type = str(item_effect.get("stat", buff_type))
			if item_effect.has("bonus_pct"):
				buff_value = int(item_effect.get("bonus_pct", 0))
			else:
				buff_value = int(item_effect.get("amount", 0))
			var is_battles_buff: bool = item_effect.has("duration_battles")
			if is_battles_buff:
				duration = int(item_effect.get("duration_battles", 1))
			else:
				duration = int(item_effect.get("duration", 5))
			var crafted_verb: String = "use" if "scroll" in item_type else "drink"
			var crafted_value_suffix: String = "%%" if buff_type in ["lifesteal", "thorns", "crit_chance"] or item_effect.has("bonus_pct") else ""
			if is_battles_buff:
				character.add_persistent_buff(buff_type, buff_value, duration)
				messages.append("[color=#00FFFF]You %s %s! +%d%s %s for %d battle%s![/color]" % [crafted_verb, item_name, buff_value, crafted_value_suffix, buff_type, duration, "s" if duration != 1 else ""])
			else:
				character.add_buff(buff_type, buff_value, duration)
				messages.append("[color=#00FFFF]You %s %s! +%d%s %s for %d rounds![/color]" % [crafted_verb, item_name, buff_value, crafted_value_suffix, buff_type, duration])
			crafted_buff_handled = true
		elif effect.get("tier_forcefield", false):
			# Forcefield: use forcefield_value from tier, duration from scroll_duration
			buff_value = tier_data.get("forcefield_value", 1500)
			duration = tier_data.get("scroll_duration", 1)
		elif effect.get("stat_pct", false):
			# Stat scroll: % of character's base stat
			var stat_pct = tier_data.get("scroll_stat_pct", 10)
			var equip_bonuses = character.get_equipment_bonuses()
			match buff_type:
				"strength": buff_value = maxi(1, int(character.get_total_attack() * stat_pct / 100.0))
				"defense": buff_value = maxi(1, int(character.get_total_defense() * stat_pct / 100.0))
				"speed": buff_value = maxi(1, int((character.dexterity + equip_bonuses.speed) * stat_pct / 100.0))
				_: buff_value = maxi(1, int(character.get_total_attack() * stat_pct / 100.0))
			duration = tier_data.get("scroll_duration", 1)
		elif effect.get("tier_value", false):
			# Percentage scroll: use buff_value directly (lifesteal, thorns, crit %)
			buff_value = tier_data.get("buff_value", 3)
			duration = tier_data.get("scroll_duration", 1)
		elif tier_data.has("buff_value"):
			# Legacy tier-based fallback
			if buff_type == "forcefield" and tier_data.has("forcefield_value"):
				buff_value = tier_data.forcefield_value
			else:
				buff_value = tier_data.buff_value
			var base_duration = effect.get("base_duration", 5)
			var duration_per_10 = effect.get("duration_per_10_levels", 1)
			duration = base_duration + (item_level / 10) * duration_per_10
		else:
			buff_value = effect.get("base", 0) + (effect.get("per_level", 0) * item_level)
			var base_duration = effect.get("base_duration", 5)
			var duration_per_10 = effect.get("duration_per_10_levels", 1)
			duration = base_duration + (item_level / 10) * duration_per_10

		if not crafted_buff_handled:
			var buff_verb = "use" if "scroll" in item_type else "drink"
			var value_suffix = "%%" if buff_type in ["lifesteal", "thorns", "crit_chance"] else ""

			if effect.get("battles", false):
				character.add_persistent_buff(buff_type, buff_value, duration)
				messages.append("[color=#00FFFF]You %s %s! +%d%s %s for %d battle%s![/color]" % [buff_verb, item_name, buff_value, value_suffix, buff_type, duration, "s" if duration != 1 else ""])
			else:
				character.add_buff(buff_type, buff_value, duration)
				messages.append("[color=#00FFFF]You %s %s! +%d%s %s for %d rounds![/color]" % [buff_verb, item_name, buff_value, value_suffix, buff_type, duration])

	# Remove item from inventory (use stack method for consumables)
	if item.get("is_consumable", false) and item.get("quantity", 1) > 0:
		character.use_consumable_stack(item_index)
	else:
		character.remove_item(item_index)

	# Item use is a FREE ACTION - player can still act this turn
	# No monster turn, no round increment, no buff tick
	messages.append("[color=#808080](Free action - you may still act)[/color]")

	return {
		"success": true,
		"messages": messages,
		"combat_ended": false
	}

func process_monster_turn(combat: Dictionary) -> Dictionary:
	"""Process the monster's attack with all ability effects"""
	var character = combat.character
	var monster = combat.monster
	var abilities = monster.get("abilities", [])
	var messages = []

	# Check if monster is stunned (Shield Bash, Paralyze, or companion)
	var stun_turns = int(combat.get("monster_stunned", 0))
	if stun_turns > 0:
		combat["monster_stunned"] = stun_turns - 1
		if stun_turns - 1 <= 0:
			combat.erase("monster_stunned")
		if stun_turns == 1:
			return {"success": true, "message": "[color=#808080]The %s is stunned and cannot act![/color]" % monster.name}
		else:
			return {"success": true, "message": "[color=#808080]The %s is paralyzed and cannot act! (%d turn(s) remaining)[/color]" % [monster.name, max(0, stun_turns - 1)]}

	# Check for Time Stop scroll buff (monster skips turn)
	if character.has_buff("time_stop"):
		character.remove_buff("time_stop")
		return {"success": true, "message": "[color=#9932CC]Time freezes around the %s! It cannot move or act this turn![/color]" % monster.name}

	# Check for companion charm effect (monster skips turn)
	var charmed_turns = combat.get("monster_charmed", 0)
	if charmed_turns > 0:
		combat["monster_charmed"] = charmed_turns - 1
		return {"success": true, "message": "[color=#FF69B4]The %s is charmed and stands motionless![/color]" % monster.name}

	# Check for companion enemy_miss effect (guaranteed miss)
	var enemy_miss_turns = combat.get("companion_enemy_miss", 0)
	if enemy_miss_turns > 0:
		combat["companion_enemy_miss"] = enemy_miss_turns - 1
		return {"success": true, "message": "[color=#FFAA00]The %s attacks but misses completely![/color]" % monster.name}

	# === PRE-ATTACK ABILITIES ===

	# Coward ability: flee at 20% HP (no loot)
	if ABILITY_COWARD in abilities:
		var hp_percent = float(monster.current_hp) / float(monster.max_hp)
		if hp_percent <= 0.2:
			return {
				"success": true,
				"message": "[color=#FFD700]The %s flees in terror! It escapes with its loot...[/color]" % monster.name,
				"monster_fled": true
			}

	# Process burn DoT on monster (from Blast)
	var burn_raw = combat.get("monster_burn", 0)
	if burn_raw is Dictionary:
		# Legacy dict format: convert to unified format
		combat["monster_burn"] = int(burn_raw.get("damage", 0))
		combat["monster_burn_duration"] = int(burn_raw.get("rounds", 0))
		burn_raw = combat["monster_burn"]
	var m_burn_damage = int(burn_raw)
	var m_burn_duration = int(combat.get("monster_burn_duration", 0))
	if m_burn_damage > 0 and m_burn_duration > 0:
		monster.current_hp -= m_burn_damage
		monster.current_hp = max(0, monster.current_hp)
		combat["monster_burn_duration"] = m_burn_duration - 1
		messages.append("[color=#FF6600]The %s burns for %d damage![/color]" % [monster.name, m_burn_damage])
		if combat["monster_burn_duration"] <= 0:
			combat["monster_burn"] = 0
			messages.append("[color=#808080]The flames die out.[/color]")
		# Check if burn killed the monster
		if monster.current_hp <= 0:
			return _process_victory(combat, messages)

	# Process bleed DoT on monster (from Cleave and companions)
	# Unified int format: monster_bleed = damage per tick, monster_bleed_duration = rounds left
	var bleed_raw = combat.get("monster_bleed", 0)
	if bleed_raw is Dictionary:
		# Legacy dict format: convert to unified format
		combat["monster_bleed"] = int(bleed_raw.get("damage", 0))
		combat["monster_bleed_duration"] = int(bleed_raw.get("rounds", 0))
		bleed_raw = combat["monster_bleed"]
	var m_bleed_damage = int(bleed_raw)
	var m_bleed_duration = int(combat.get("monster_bleed_duration", 0))
	if m_bleed_damage > 0 and m_bleed_duration > 0:
		monster.current_hp -= m_bleed_damage
		monster.current_hp = max(0, monster.current_hp)
		combat["monster_bleed_duration"] = m_bleed_duration - 1
		messages.append("[color=#FF4444]The %s bleeds for %d damage![/color]" % [monster.name, m_bleed_damage])
		if combat["monster_bleed_duration"] <= 0:
			combat["monster_bleed"] = 0
			messages.append("[color=#808080]The bleeding stops.[/color]")
		if monster.current_hp <= 0:
			return _process_victory(combat, messages)

	# Regeneration ability: heal 10% HP per turn
	if ABILITY_REGENERATION in abilities:
		var heal_amount = max(1, int(monster.max_hp * 0.10))
		monster.current_hp = min(monster.max_hp, monster.current_hp + heal_amount)
		messages.append("[color=#00FF00]The %s regenerates %d HP![/color]" % [monster.name, heal_amount])

	# Enrage ability: +10% damage per round, capped at 10 stacks (100%)
	if ABILITY_ENRAGE in abilities:
		if combat.get("enrage_stacks", 0) < 10:
			combat["enrage_stacks"] = combat.get("enrage_stacks", 0) + 1
			if combat.enrage_stacks > 1:
				messages.append("[color=#FF4444]The %s grows more furious! (+%d%% damage)[/color]" % [monster.name, combat.enrage_stacks * 10])

	# === ATTACK CALCULATION ===

	# Monster hit chance: 85% base, +1% per monster level above player (cap 95%)
	var player_level = character.level
	var monster_level = monster.level
	var level_diff = monster_level - player_level
	var hit_chance = 85 + level_diff

	# DEX provides dodge chance: -1% hit chance per 5 DEX (max -30%)
	var player_dex = character.get_effective_stat("dexterity")
	var dex_dodge = min(30, int(player_dex / 5))
	hit_chance -= dex_dodge

	# WITS provides additional dodge for tricksters: -1% per 50 WITS (max -15%)
	var is_trickster = character.class_type in ["Thief", "Ranger", "Ninja"]
	if is_trickster:
		var player_wits = character.get_effective_stat("wits")
		var wits_dodge = min(15, int(player_wits / 50))
		hit_chance -= wits_dodge

	# Speed buff (from Haste, equipment, etc.) reduces monster hit chance
	var speed_buff = character.get_buff_value("speed")
	if speed_buff > 0:
		# Speed buff directly reduces hit chance (e.g., +20 speed = -10% hit chance)
		hit_chance -= int(speed_buff / 2)

	# Equipment speed bonus also helps dodge
	var equipment_bonuses = character.get_equipment_bonuses()
	var equipment_speed = equipment_bonuses.get("speed", 0)
	if equipment_speed > 0:
		hit_chance -= int(equipment_speed / 3)

	# Companion speed bonus helps dodge
	if character.has_active_companion():
		var comp_speed_dodge = int(character.get_companion_bonus("speed"))
		comp_speed_dodge += combat.get("companion_speed_bonus", 0)
		if comp_speed_dodge > 0:
			hit_chance -= int(comp_speed_dodge / 3)

	# Halfling racial: +10% dodge chance (reduces monster hit chance)
	var racial_dodge = character.get_dodge_bonus()
	if racial_dodge > 0:
		hit_chance -= int(racial_dodge * 100)

	# Companion dodge buff (from threshold ability)
	var companion_dodge = combat.get("companion_dodge_buff", 0)
	if companion_dodge > 0:
		hit_chance -= companion_dodge
		# Decrement duration
		var dodge_duration = combat.get("companion_dodge_duration", 0)
		if dodge_duration > 0:
			combat["companion_dodge_duration"] = dodge_duration - 1
			if dodge_duration - 1 <= 0:
				combat["companion_dodge_buff"] = 0

	# Armor rarity dodge bonus (from all equipped armor pieces)
	var armor_dodge_total = 0
	var armor_dr_total = 0.0
	var char_equipped = character.equipped if character else {}
	if char_equipped is Dictionary:
		for slot_name in ["armor", "helm", "shield", "boots"]:
			var armor_piece = char_equipped.get(slot_name, {})
			if armor_piece is Dictionary:
				var arb = armor_piece.get("rarity_bonuses", {})
				armor_dodge_total += int(arb.get("dodge", 0))
				armor_dr_total += float(arb.get("damage_reduction", 0))
	if armor_dodge_total > 0:
		hit_chance -= armor_dodge_total

	hit_chance = clamp(hit_chance, 40, 95)  # 40% minimum (can dodge well), 95% maximum

	# Ethereal ability: 50% chance for player attacks to miss (handled elsewhere)
	# but ethereal monsters also have lower hit chance
	if ABILITY_ETHEREAL in abilities:
		hit_chance -= 10  # Ethereal creatures are less precise

	# === CLASS PASSIVE: Ninja Shadow Step ===
	# Take no damage after failed flee attempt
	if combat.get("ninja_flee_protection", false):
		combat.erase("ninja_flee_protection")
		messages.append("[color=#191970]You slip away from the %s's counterattack![/color]" % monster.name)
		return {"success": true, "message": "\n".join(messages)}

	# Cloak: 50% miss chance (one time)
	if combat.get("cloak_active", false):
		combat.erase("cloak_active")
		if randi() % 100 < 50:
			messages.append("[color=#FF00FF]Your Cloak causes the %s to miss![/color]" % monster.name)
			return {"success": true, "message": "\n".join(messages)}

	# Distract: accuracy debuff (one time, magnitude set by player's spend on
	# the Distract ability). Pre-v0.9.265 this was a bool flag with hardcoded
	# -50%; now it's an int percent so partial-cast Distract has weaker effect.
	# Truthy check tolerates legacy bool values from saved combat states.
	var distract_raw = combat.get("enemy_distracted", 0)
	var distract_pct_int: int = 0
	if typeof(distract_raw) == TYPE_BOOL:
		distract_pct_int = 50 if distract_raw else 0
	else:
		distract_pct_int = int(distract_raw)
	if distract_pct_int > 0:
		combat.erase("enemy_distracted")
		hit_chance = int(hit_chance * (1.0 - distract_pct_int / 100.0))

	# Companion Distraction ability: causes monster to miss (one time)
	if combat.get("companion_distraction", false):
		combat.erase("companion_distraction")
		messages.append("[color=#00FFFF]The %s is distracted by your companion and misses![/color]" % monster.name)
		return {"success": true, "message": "\n".join(messages)}

	# Audit #5 Slice 14 — Wraith Barrow SPECTRAL_VEIL buff. While the veil is
	# active, the monster has a flat 20% miss chance per attack. Picked up via
	# the dungeon move handler which sets `pending_dungeon_veil` on the
	# character meta and is carried into combat in start_combat.
	if int(combat.get("player_veil_until_round", 0)) >= int(combat.get("round", 0)):
		if randi() % 100 < 20:
			messages.append("[color=#9370DB]The wraith's veil shrouds you — the %s's attack passes through empty air![/color]" % monster.name)
			return {"success": true, "message": "\n".join(messages)}

	# === DETERMINE NUMBER OF ATTACKS ===
	var num_attacks = 1
	if ABILITY_MULTI_STRIKE in abilities:
		num_attacks = randi_range(2, 3)
		messages.append("[color=#FF4444]The %s attacks multiple times![/color]" % monster.name)

	var total_damage = 0
	var hits = 0

	for attack_num in range(num_attacks):
		var hit_roll = randi() % 100

		if hit_roll < hit_chance:
			# Monster hits
			var damage = calculate_monster_damage(monster, character, combat)

			# Sabotage debuff: reduce monster damage
			var sabotage_reduction = combat.get("monster_sabotaged", 0)
			if sabotage_reduction > 0:
				damage = int(damage * (1.0 - sabotage_reduction / 100.0))
				damage = max(1, damage)

			# Monster weakness (from companion ability): reduce monster damage
			var monster_weakness = combat.get("monster_weakness", 0)
			if monster_weakness > 0:
				damage = int(damage * (1.0 - monster_weakness / 100.0))
				damage = max(1, damage)

			# Companion absorb (from threshold ability): reduce damage taken
			var companion_absorb = combat.get("companion_absorb", 0)
			if companion_absorb > 0:
				var absorbed = int(damage * companion_absorb / 100.0)
				damage = max(1, damage - absorbed)
				# Decrement duration
				var absorb_duration = combat.get("companion_absorb_duration", 0)
				if absorb_duration > 0:
					combat["companion_absorb_duration"] = absorb_duration - 1
					if absorb_duration - 1 <= 0:
						combat["companion_absorb"] = 0

			# Ambusher ability: first attack deals bonus damage (75% chance to trigger)
			if combat.get("ambusher_active", false):
				combat["ambusher_active"] = false
				if randi() % 100 < 75:  # 75% chance to ambush
					damage = int(damage * 1.75)  # 1.75x damage (nerfed from 2x)
					messages.append("[color=#FF0000]AMBUSH! The %s strikes from the shadows![/color]" % monster.name)

			# Audit #5 — Treasure Decoy / boss_treasure_decoy. Guaranteed 2x first
			# attack telegraphing the boss's deceptive nature. Distinct from
			# ambusher (75% chance, 1.75x): always triggers, hits harder, and is
			# announced as a trap rather than a stealth strike.
			if combat.get("treasure_decoy_pending", false):
				combat["treasure_decoy_pending"] = false
				damage = int(damage * 2.0)
				messages.append("[color=#FF6600]TREASURE DECOY![/color] [color=#FFD700]The %s lashes out from its disguise![/color]" % monster.name)

			# Berserker ability: +50% damage when below 50% HP
			if ABILITY_BERSERKER in abilities:
				var hp_percent = float(monster.current_hp) / float(monster.max_hp)
				if hp_percent <= 0.5:
					damage = int(damage * 1.5)
					if attack_num == 0:
						messages.append("[color=#FF4444]The %s enters a berserker rage![/color]" % monster.name)

			# Audit #5 — Bloodied Fury / boss_bloodied_fury. One-shot trigger when
			# boss drops below 30% HP: +75% damage permanent for rest of fight.
			# Distinct from berserker (50% threshold, +50%, every turn) — single
			# announcement, higher peak, sharper threshold.
			if ABILITY_BOSS_BLOODIED_FURY in abilities:
				if not combat.get("bloodied_fury_triggered", false):
					var bf_hp_percent = float(monster.current_hp) / float(monster.max_hp)
					if bf_hp_percent <= 0.3:
						combat["bloodied_fury_triggered"] = true
						messages.append("[color=#8B0000][b]BLOODIED FURY![/b][/color] [color=#FFAA00]The %s is bleeding heavily and surges into a killing rage![/color]" % monster.name)
				if combat.get("bloodied_fury_triggered", false):
					damage = int(damage * 1.75)

			# Audit #5 — Bloodscent / boss_bloodscent. Mirror of Bloodied Fury but
			# targeting the PLAYER's HP: when player drops below 50%, the boss
			# scents the kill and gains +50% damage rest of fight. One-shot trigger.
			if ABILITY_BOSS_BLOODSCENT in abilities:
				if not combat.get("bloodscent_triggered", false):
					var bs_player_hp_pct = float(character.current_hp) / float(character.get_total_max_hp())
					if bs_player_hp_pct <= 0.5:
						combat["bloodscent_triggered"] = true
						messages.append("[color=#8B0000][b]BLOODSCENT![/b][/color] [color=#FFAA00]The %s smells your blood and bares its fangs![/color]" % monster.name)
				if combat.get("bloodscent_triggered", false):
					damage = int(damage * 1.5)

			# Audit #5 — Pack Frenzy / boss_pack_frenzy (Gnoll Packmaster).
			# Escalating damage: +5% per round elapsed, no cap. Distinct from
			# one-shot triggers — pressure builds the longer the fight runs,
			# so there is a soft tempo cap. Round 1 = 1.0x, round 5 = 1.20x,
			# round 10 = 1.45x, round 20 = 1.95x.
			if ABILITY_BOSS_PACK_FRENZY in abilities:
				var frenzy_round = max(0, int(combat.get("round", 1)) - 1)
				if frenzy_round > 0:
					damage = int(damage * (1.0 + 0.05 * frenzy_round))
					var last_frenzy_msg = int(combat.get("pack_frenzy_last_msg_round", 0))
					if (frenzy_round == 3 or frenzy_round == 6 or frenzy_round == 10) and last_frenzy_msg < frenzy_round:
						combat["pack_frenzy_last_msg_round"] = frenzy_round
						messages.append("[color=#8B6914][b]PACK FRENZY![/b][/color] [color=#FFAA00]The %s's blows land harder with each passing moment (+%d%% damage).[/color]" % [monster.name, int(0.05 * frenzy_round * 100)])

			# Enrage stacks
			var enrage = combat.get("enrage_stacks", 0)
			if enrage > 0:
				damage = int(damage * (1.0 + enrage * 0.10))

			# Unpredictable ability: wild damage variance (0.5x to 2.5x)
			if ABILITY_UNPREDICTABLE in abilities:
				var variance = randf_range(0.5, 2.5)
				damage = int(damage * variance)
				if variance > 1.8:
					messages.append("[color=#FF0000]The %s strikes with unexpected ferocity![/color]" % monster.name)
				elif variance < 0.7:
					messages.append("[color=#00FF00]The %s's attack is feeble this time.[/color]" % monster.name)

			# Apply damage reduction buff (Iron Skin)
			var damage_reduction = character.get_buff_value("damage_reduction")
			if damage_reduction > 0:
				damage = int(damage * (1.0 - damage_reduction / 100.0))
				damage = max(1, damage)

			# Apply armor rarity damage reduction (percentage)
			if armor_dr_total > 0:
				damage = int(damage * (1.0 - armor_dr_total / 100.0))
				damage = max(1, damage)

			# Apply defense buff (Shield spell)
			var defense_buff = character.get_buff_value("defense")
			if defense_buff > 0:
				var reduction = 1.0 - (defense_buff / 100.0)
				damage = int(damage * reduction)
				damage = max(1, damage)

			total_damage += damage
			hits += 1

			# Life steal ability: heal for 50% of damage dealt
			if ABILITY_LIFE_STEAL in abilities:
				var heal = int(damage * 0.5)
				monster.current_hp = min(monster.max_hp, monster.current_hp + heal)
				messages.append("[color=#FF4444]The %s drains %d life from you![/color]" % [monster.name, heal])

	if hits > 0:
		# === Phase B2 — Weighted companion targeting ===
		# Each companion has an `aggro` value (in COMPANION_DATA bonuses) that
		# controls how often monsters target it instead of the player. Tank
		# companions (golems, giants) draw more aggro; sneaky / aerial ones
		# draw less. Default 25 if a companion lacks an explicit value.
		# Taunt Charm consumable applies a temporary additive bonus for a
		# few monster turns. Final aggro is clamped to [0, 80] so even tanks
		# don't permanently soak every hit.
		var target_companion := false
		var companion_target_name := ""
		if character.has_active_companion() and not character.is_companion_ko():
			var comp_dict: Dictionary = character.get_active_companion()
			var comp_bonuses: Dictionary = comp_dict.get("bonuses", {})
			var base_aggro: int = int(comp_bonuses.get("aggro", 25))
			var taunt_bonus: int = int(combat.get("companion_taunt_bonus", 0))
			var taunt_turns: int = int(combat.get("companion_taunt_turns", 0))
			var final_aggro: int = base_aggro
			if taunt_turns > 0:
				final_aggro += taunt_bonus
				# Decrement taunt counter each monster turn (regardless of
				# whether the roll favors companion). The buff shouldn't
				# survive longer than its declared duration.
				combat["companion_taunt_turns"] = taunt_turns - 1
				if combat["companion_taunt_turns"] <= 0:
					combat.erase("companion_taunt_bonus")
					combat.erase("companion_taunt_turns")
			final_aggro = clampi(final_aggro, 0, 80)
			if randf() * 100.0 < float(final_aggro):
				target_companion = true
				companion_target_name = str(comp_dict.get("name", "companion"))

		if target_companion:
			var comp_hp_before: int = character.get_companion_combat_hp()
			# Per-sub_tier damage reduction so tankier companions feel tougher.
			# 3% per sub_tier, capped at 27% (sub_tier 9). Tracks the same
			# sub_tier scaling already used for HP pool / variant bonuses.
			var comp_sub_tier: int = int(character.get_active_companion().get("sub_tier", 1))
			var comp_dr_pct: int = clampi(comp_sub_tier * 3, 0, 27)
			var damage_to_companion: int = total_damage
			var dr_amount: int = 0
			if comp_dr_pct > 0:
				dr_amount = int(total_damage * comp_dr_pct / 100.0)
				damage_to_companion = maxi(1, total_damage - dr_amount)
			var comp_new_hp: int = maxi(0, comp_hp_before - damage_to_companion)
			character.set_companion_combat_hp(comp_new_hp)
			combat["total_damage_taken"] = combat.get("total_damage_taken", 0)  # companion damage not counted toward player
			if num_attacks > 1:
				messages.append("[color=#FF8888]The %s hits your %s %d times for [color=#FF8800]%d[/color] total damage![/color]" % [monster.name, companion_target_name, hits, damage_to_companion])
			else:
				messages.append("[color=#FF8888]The %s attacks your %s for [color=#FF8800]%d[/color] damage![/color]" % [monster.name, companion_target_name, damage_to_companion])
			if dr_amount > 0:
				messages.append("[color=#3DD9FF]  Sub-tier %d toughness absorbs %d damage.[/color]" % [comp_sub_tier, dr_amount])
			if comp_new_hp <= 0 and comp_hp_before > 0:
				messages.append("[color=#808080]Your %s is knocked out![/color]" % companion_target_name)
			return {"success": true, "message": "\n".join(messages), "companion_hit": true}

		# Check for Forcefield shield (absorbs damage)
		var forcefield_shield = combat.get("forcefield_shield", 0)
		if forcefield_shield > 0:
			if total_damage <= forcefield_shield:
				combat["forcefield_shield"] = forcefield_shield - total_damage
				messages.append("[color=#FF00FF]Your Forcefield absorbs %d damage! (%d shield remaining)[/color]" % [total_damage, combat.forcefield_shield])
				total_damage = 0
			else:
				total_damage -= forcefield_shield
				combat.erase("forcefield_shield")
				messages.append("[color=#FF00FF]Your Forcefield absorbs %d damage before breaking![/color]" % forcefield_shield)

		# GM godmode: negate all damage
		if character.get_meta("gm_godmode", false):
			messages.append("[color=#00FF00][GM] Godmode: %d damage negated[/color]" % total_damage)
			total_damage = 0

		character.current_hp -= total_damage

		# Player thorns from scroll/potion buff (reflect damage back to monster)
		var player_thorns = combat.get("player_thorns", 0)
		if player_thorns > 0 and total_damage > 0:
			var thorns_damage = max(1, int(total_damage * player_thorns / 100.0))
			monster.current_hp -= thorns_damage
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#FF00FF]Thorns reflect %d damage back![/color]" % thorns_damage)

		# Equipment damage reflect proc
		var procs = character.get_equipment_procs()
		if procs.damage_reflect > 0 and total_damage > 0:
			var reflect_dmg = max(1, int(total_damage * procs.damage_reflect / 100.0))
			monster.current_hp -= reflect_dmg
			monster.current_hp = max(0, monster.current_hp)
			messages.append("[color=#9932CC]Retribution gear reflects %d damage![/color]" % reflect_dmg)
			# Check if reflection killed monster
			if monster.current_hp <= 0:
				return _process_victory(combat, messages)

		# Check for Dwarf Last Stand (survive lethal damage with 1 HP)
		if character.current_hp <= 0:
			if character.try_last_stand():
				character.current_hp = 1
				messages.append("[color=#FF4444]The %s attacks and deals [color=#FF8800]%d[/color] damage![/color]" % [monster.name, total_damage])
				messages.append("[color=#FFD700][b]LAST STAND![/b] Your dwarven resilience saves you![/color]")
				return {"success": true, "message": "\n".join(messages), "last_stand": true}

		# Check for Resurrect scroll buff (survive lethal damage and revive at % HP)
		if character.current_hp <= 0:
			var resurrect_percent = character.get_buff_value("resurrect")
			if resurrect_percent > 0:
				character.remove_buff("resurrect")
				var revive_hp = max(1, int(character.get_total_max_hp() * resurrect_percent / 100.0))
				character.current_hp = revive_hp
				messages.append("[color=#FF4444]The %s attacks and deals a lethal blow![/color]" % monster.name)
				messages.append("[color=#FFD700][b]RESURRECTION![/b] Divine magic pulls you back from death![/color]")
				messages.append("[color=#00FF00]You are revived with %d HP![/color]" % revive_hp)
				return {"success": true, "message": "\n".join(messages), "resurrected": true}

		# Check for companion revive (from threshold ability like Lich King's Phylactery)
		if character.current_hp <= 0:
			var companion_revive = combat.get("companion_revive", 0)
			if companion_revive > 0:
				combat.erase("companion_revive")  # One-time use
				var revive_hp = max(1, int(character.get_total_max_hp() * companion_revive / 100.0))
				character.current_hp = revive_hp
				var companion = character.get_active_companion()
				var comp_name = companion.get("name", "Your companion") if companion else "Your companion"
				messages.append("[color=#FF4444]The %s attacks and deals a lethal blow![/color]" % monster.name)
				messages.append("[color=#FFD700][b]COMPANION REVIVE![/b] %s pulls you back from death![/color]" % comp_name)
				messages.append("[color=#00FF00]You are revived with %d HP![/color]" % revive_hp)
				return {"success": true, "message": "\n".join(messages), "companion_revived": true}

		character.current_hp = max(0, character.current_hp)

		# === COMPANION THRESHOLD ABILITY ===
		# Check if companion's threshold ability should trigger (once per combat)
		# Uses monster-specific abilities stored at combat start (pre-scaled by level + variant)
		if character.current_hp > 0 and character.has_active_companion() and not combat.get("companion_threshold_triggered", false):
			var threshold_abilities = combat.get("companion_abilities", {})
			if not threshold_abilities.is_empty() and not threshold_abilities.get("threshold", {}).is_empty():
				var companion = character.get_active_companion()
				var ability = threshold_abilities.threshold
				var hp_threshold = ability.get("hp_percent", 50) / 100.0
				var current_hp_percent = float(character.current_hp) / float(character.get_total_max_hp())

				if current_hp_percent <= hp_threshold:
					combat["companion_threshold_triggered"] = true
					var effect = ability.get("effect", "")
					var ability_name = ability.get("name", "ability")

					if effect == "defense_buff":
						var buff_value = ability.get("value", 10)
						var duration = ability.get("duration", 3)
						character.add_buff("defense", buff_value, duration)
						messages.append("[color=#00FFFF]%s uses %s! (+%d%% defense for %d rounds)[/color]" % [companion.name, ability_name, buff_value, duration])
					elif effect == "attack_buff":
						var buff_value = ability.get("value", 10)
						var duration = ability.get("duration", 3)
						character.add_buff("strength", buff_value, duration)
						messages.append("[color=#FF6600]%s uses %s! (+%d%% attack for %d rounds)[/color]" % [companion.name, ability_name, buff_value, duration])
					elif effect == "speed_buff":
						var buff_value = ability.get("value", 10)
						var duration = ability.get("duration", 3)
						character.add_buff("speed", buff_value, duration)
						messages.append("[color=#00FFFF]%s uses %s! (+%d%% speed for %d rounds)[/color]" % [companion.name, ability_name, buff_value, duration])
					elif effect == "all_buff":
						var buff_value = ability.get("value", 10)
						var duration = ability.get("duration", 3)
						character.add_buff("strength", buff_value, duration)
						character.add_buff("defense", buff_value, duration)
						character.add_buff("speed", buff_value, duration)
						messages.append("[color=#FFD700]%s uses %s! (+%d%% to all stats for %d rounds)[/color]" % [companion.name, ability_name, buff_value, duration])
					elif effect == "dodge_buff":
						var buff_value = ability.get("value", 15)
						var duration = ability.get("duration", 3)
						combat["companion_dodge_buff"] = buff_value
						combat["companion_dodge_duration"] = duration
						messages.append("[color=#00FFFF]%s uses %s! (+%d%% dodge for %d rounds)[/color]" % [companion.name, ability_name, buff_value, duration])
					elif effect == "absorb":
						var absorb_value = ability.get("value", 10)
						var duration = ability.get("duration", 3)
						combat["companion_absorb"] = absorb_value
						combat["companion_absorb_duration"] = duration
						messages.append("[color=#8888FF]%s uses %s! (Absorbs %d%% damage for %d rounds)[/color]" % [companion.name, ability_name, absorb_value, duration])
					elif effect == "heal":
						var heal_percent = ability.get("value", 10)
						var heal_amount = max(1, int(character.get_total_max_hp() * heal_percent / 100.0))
						character.current_hp = min(character.get_total_max_hp(), character.current_hp + heal_amount)
						messages.append("[color=#00FF00]%s uses %s and heals you for %d HP![/color]" % [companion.name, ability_name, heal_amount])
					elif effect == "full_heal":
						character.current_hp = character.get_total_max_hp()
						messages.append("[color=#FFD700]%s uses %s! You are fully healed![/color]" % [companion.name, ability_name])
					elif effect == "flee_bonus":
						var flee_value = ability.get("value", 20)
						var duration = ability.get("duration", 2)
						combat["companion_flee_buff"] = flee_value
						combat["companion_flee_duration"] = duration
						messages.append("[color=#AAAAAA]%s uses %s! (+%d%% flee chance for %d rounds)[/color]" % [companion.name, ability_name, flee_value, duration])
					elif effect == "slow_enemy":
						var slow_value = ability.get("value", 20)
						var duration = ability.get("duration", 2)
						combat["monster_slowed"] = slow_value
						combat["monster_slow_duration"] = duration
						messages.append("[color=#6699FF]%s uses %s! The %s is slowed![/color]" % [companion.name, ability_name, monster.name])
					elif effect == "enemy_miss":
						var duration = ability.get("duration", 2)
						combat["companion_enemy_miss"] = duration
						messages.append("[color=#FFAA00]%s uses %s! The %s will miss its next %d attack(s)![/color]" % [companion.name, ability_name, monster.name, duration])
					elif effect == "lifesteal_buff":
						var lifesteal_value = ability.get("value", 20)
						var duration = ability.get("duration", 3)
						combat["companion_lifesteal_buff"] = lifesteal_value
						combat["companion_lifesteal_buff_duration"] = duration
						messages.append("[color=#00FF00]%s uses %s! (+%d%% lifesteal for %d rounds)[/color]" % [companion.name, ability_name, lifesteal_value, duration])
					elif effect == "lifesteal":
						# Immediate lifesteal heal (percent is pre-scaled)
						var lifesteal_pct = ability.get("percent", ability.get("base_percent", 20))
						var heal_amount = max(1, int(character.get_total_max_hp() * lifesteal_pct / 100.0))
						character.current_hp = min(character.get_total_max_hp(), character.current_hp + heal_amount)
						messages.append("[color=#00FF00]%s uses %s and drains %d HP![/color]" % [companion.name, ability_name, heal_amount])
					elif effect == "mana_restore":
						# Restore player's primary resource based on class
						var restore_percent = ability.get("value", 20)
						var class_path = character.get_class_path()
						match class_path:
							"warrior":
								var amount = max(1, int(character.get_total_max_stamina() * restore_percent / 100.0))
								character.current_stamina = min(character.get_total_max_stamina(), character.current_stamina + amount)
								messages.append("[color=#6699FF]%s uses %s and restores %d stamina![/color]" % [companion.name, ability_name, amount])
							"mage":
								var amount = max(1, int(character.get_total_max_mana() * restore_percent / 100.0))
								character.current_mana = min(character.get_total_max_mana(), character.current_mana + amount)
								messages.append("[color=#6699FF]%s uses %s and restores %d mana![/color]" % [companion.name, ability_name, amount])
							"trickster":
								var amount = max(1, int(character.get_total_max_energy() * restore_percent / 100.0))
								character.current_energy = min(character.get_total_max_energy(), character.current_energy + amount)
								messages.append("[color=#6699FF]%s uses %s and restores %d energy![/color]" % [companion.name, ability_name, amount])
					elif effect == "poison":
						var poison_damage = ability.get("damage", ability.get("base_damage", 10))
						var duration = ability.get("duration", 3)
						combat["monster_poison"] = combat.get("monster_poison", 0) + poison_damage
						combat["monster_poison_duration"] = max(combat.get("monster_poison_duration", 0), duration)
						messages.append("[color=#00FF00]%s uses %s! The %s is poisoned![/color]" % [companion.name, ability_name, monster.name])
					elif effect == "bonus_damage":
						var bonus_damage = ability.get("damage", ability.get("base_damage", 20))
						monster.current_hp -= bonus_damage
						monster.current_hp = max(0, monster.current_hp)
						messages.append("[color=#FF4444]%s uses %s for %d damage![/color]" % [companion.name, ability_name, bonus_damage])
					elif effect == "execute":
						var execute_threshold = ability.get("execute_threshold", 20) / 100.0
						var monster_hp_pct = float(monster.current_hp) / float(monster.max_hp)
						if monster_hp_pct <= execute_threshold:
							monster.current_hp = 0
							messages.append("[color=#FF0000]%s uses %s and executes the %s![/color]" % [companion.name, ability_name, monster.name])
						else:
							var exec_damage = int(monster.max_hp * 0.15)
							monster.current_hp -= exec_damage
							monster.current_hp = max(0, monster.current_hp)
							messages.append("[color=#FF4444]%s uses %s for %d damage![/color]" % [companion.name, ability_name, exec_damage])
					elif effect == "revive":
						# Store revive for if player dies
						var revive_percent = ability.get("revive_percent", 50)
						combat["companion_revive"] = revive_percent
						messages.append("[color=#FFD700]%s prepares %s! (Will revive at %d%% HP if killed)[/color]" % [companion.name, ability_name, revive_percent])

					# Check for secondary threshold effects (values pre-scaled where applicable)
					if ability.has("effect2"):
						var effect2 = ability.get("effect2", "")
						if effect2 == "attack_buff":
							var buff_value = ability.get("value2", ability.get("attack_base", 20))
							var duration = ability.get("duration", 3)
							character.add_buff("strength", buff_value, duration)
						elif effect2 == "speed_buff":
							var buff_value = ability.get("value2", ability.get("base2", 15))
							var duration = ability.get("duration", 3)
							character.add_buff("speed", buff_value, duration)
						elif effect2 == "heal":
							var heal_pct = ability.get("heal_percent", 20)
							var heal_amount = max(1, int(character.get_total_max_hp() * heal_pct / 100.0))
							character.current_hp = min(character.get_total_max_hp(), character.current_hp + heal_amount)
							messages.append("[color=#00FF00]%s also heals you for %d HP![/color]" % [companion.name, heal_amount])
						elif effect2 == "poison":
							var poison_damage = ability.get("poison_damage", 10)
							combat["monster_poison"] = combat.get("monster_poison", 0) + poison_damage
							combat["monster_poison_duration"] = max(combat.get("monster_poison_duration", 0), 3)
						elif effect2 == "stun":
							combat["monster_stunned"] = 1
							messages.append("[color=#FFAA00]The %s is stunned![/color]" % monster.name)
						elif effect2 == "crit_buff":
							var crit_value = ability.get("value2", ability.get("crit_base", 20))
							var duration = ability.get("duration", 3)
							combat["companion_crit_buff"] = crit_value
							combat["companion_crit_buff_duration"] = duration
						elif effect2 == "all_buff":
							var buff_value = ability.get("value2", ability.get("buff_base", 20))
							var duration = ability.get("duration", 3)
							character.add_buff("strength", buff_value, duration)
							character.add_buff("defense", buff_value, duration)
							character.add_buff("speed", buff_value, duration)
						elif effect2 == "reset_cooldowns":
							# Reset companion threshold so it can trigger again
							combat["companion_threshold_triggered"] = false
							messages.append("[color=#FFD700]Cooldowns reset![/color]")

		if num_attacks > 1:
			messages.append("[color=#FF4444]The %s hits %d times for [color=#FF8800]%d[/color] total damage![/color]" % [monster.name, hits, total_damage])
		else:
			messages.append("[color=#FF4444]The %s attacks and deals [color=#FF8800]%d[/color] damage![/color]" % [monster.name, total_damage])
	else:
		messages.append("[color=#00FF00]The %s attacks but misses![/color]" % monster.name)

	# === POST-ATTACK ABILITIES ===

	# Poison ability: apply poison if not already active (lasts 50 turns, persists outside combat)
	# WIS reduces poison chance and damage
	if ABILITY_POISON in abilities and not character.poison_active:
		var player_wis = character.get_effective_stat("wisdom") + combat.get("companion_wisdom_bonus", 0)
		var wis_resist = minf(0.50, float(player_wis) / 200.0)  # Max 50% resistance at WIS 100+
		var poison_chance = int(40 * (1.0 - wis_resist))  # Base 40%, reduced by WIS
		if randi() % 100 < poison_chance:
			var base_poison_dmg = max(1, int(monster.strength * 0.30))
			var poison_dmg = max(1, int(base_poison_dmg * (1.0 - wis_resist)))  # WIS also reduces damage
			character.apply_poison(poison_dmg, 50)
			if wis_resist > 0:
				messages.append("[color=#FF00FF]You have been poisoned! (-[color=#FF8800]%d[/color] HP/round for 50 turns, WIS resists %d%%)[/color]" % [poison_dmg, int(wis_resist * 100)])
			else:
				messages.append("[color=#FF00FF]You have been poisoned! (-[color=#FF8800]%d[/color] HP/round for 50 turns)[/color]" % poison_dmg)

	# Mana drain ability - drains the character's primary resource based on class path
	# WIS reduces drain amount
	if ABILITY_MANA_DRAIN in abilities and hits > 0:
		var player_wis = character.get_effective_stat("wisdom") + combat.get("companion_wisdom_bonus", 0)
		var wis_resist = minf(0.50, float(player_wis) / 200.0)  # Max 50% resistance
		var base_drain = randi_range(5, 20) + int(monster_level / 10)
		var drain = max(1, int(base_drain * (1.0 - wis_resist)))
		var resource_name = ""
		# Determine primary resource based on class type
		match character.class_type:
			"Wizard", "Sage", "Sorcerer":
				character.current_mana = max(0, character.current_mana - drain)
				resource_name = "mana"
			"Fighter", "Barbarian", "Paladin":
				character.current_stamina = max(0, character.current_stamina - drain)
				resource_name = "stamina"
			"Thief", "Ranger", "Ninja":
				character.current_energy = max(0, character.current_energy - drain)
				resource_name = "energy"
			_:
				character.current_mana = max(0, character.current_mana - drain)
				resource_name = "mana"
		if wis_resist > 0:
			messages.append("[color=#FF00FF]The %s drains [color=#FF8800]%d[/color] %s! (WIS resists %d%%)[/color]" % [monster.name, drain, resource_name, int(wis_resist * 100)])
		else:
			messages.append("[color=#FF00FF]The %s drains [color=#FF8800]%d[/color] %s![/color]" % [monster.name, drain, resource_name])

	# Stamina drain ability
	if ABILITY_STAMINA_DRAIN in abilities and hits > 0:
		var drain = randi_range(5, 15) + int(monster_level / 10)
		character.current_stamina = max(0, character.current_stamina - drain)
		messages.append("[color=#FF4444]The %s drains %d stamina![/color]" % [monster.name, drain])

	# Energy drain ability
	if ABILITY_ENERGY_DRAIN in abilities and hits > 0:
		var drain = randi_range(5, 15) + int(monster_level / 10)
		character.current_energy = max(0, character.current_energy - drain)
		messages.append("[color=#FFA500]The %s drains %d energy![/color]" % [monster.name, drain])

	# Curse ability: reduce defense for rest of combat (once)
	# WIS reduces curse chance and effect
	if ABILITY_CURSE in abilities and not combat.get("curse_applied", false):
		var player_wis = character.get_effective_stat("wisdom") + combat.get("companion_wisdom_bonus", 0)
		var wis_resist = minf(0.50, float(player_wis) / 200.0)  # Max 50% resistance
		var curse_chance = int(30 * (1.0 - wis_resist))  # Base 30%, reduced by WIS
		if randi() % 100 < curse_chance:
			combat["curse_applied"] = true
			var curse_penalty = int(-25 * (1.0 - wis_resist))  # WIS reduces penalty too
			character.add_buff("defense_penalty", curse_penalty, 999)  # Lasts entire combat
			if wis_resist > 0:
				messages.append("[color=#FF00FF]The %s curses you! (%d%% defense, WIS resists %d%%)[/color]" % [monster.name, curse_penalty, int(wis_resist * 100)])
			else:
				messages.append("[color=#FF00FF]The %s curses you! (-25%% defense)[/color]" % monster.name)

	# Disarm ability: reduce weapon damage temporarily (once)
	if ABILITY_DISARM in abilities and not combat.get("disarm_applied", false):
		if randi() % 100 < 25:  # 25% chance
			combat["disarm_applied"] = true
			character.add_buff("damage", -30, 3)  # -30% damage for 3 rounds
			messages.append("[color=#FF4444]The %s disarms you! (-30%% damage for 3 rounds)[/color]" % monster.name)

	# Corrosive ability: chance to damage random equipment on hit (configurable)
	var ability_cfg = balance_config.get("monster_abilities", {})
	if ABILITY_CORROSIVE in abilities and hits > 0:
		var corrosive_chance = ability_cfg.get("corrosive_chance", 15)
		if randi() % 100 < corrosive_chance:
			# Damage one random piece of equipment (all slots including ring/amulet)
			var all_slots = ["weapon", "shield", "armor", "helm", "boots", "ring", "amulet"]
			all_slots.shuffle()
			for slot in all_slots:
				var result = character.damage_equipment(slot, randi_range(5, 15))
				if result.success:
					if result.is_broken:
						messages.append("[color=#FF0000]The %s's acid BREAKS your %s! Replace it immediately![/color]" % [monster.name, result.item_name])
					else:
						messages.append("[color=#FFA500]The %s's acid corrodes your %s! (%d%% worn)[/color]" % [monster.name, result.item_name, result.new_wear])
					break

	# Sunder ability: specifically damages weapons and shields (configurable)
	if ABILITY_SUNDER in abilities and hits > 0:
		var sunder_chance = ability_cfg.get("sunder_chance", 20)
		if randi() % 100 < sunder_chance:
			# 50/50 weapon or shield
			var target_slot = "weapon" if randf() < 0.5 else "shield"
			var result = character.damage_equipment(target_slot, randi_range(10, 25))
			if result.success:
				if result.is_broken:
					messages.append("[color=#FF0000]The %s SHATTERS your %s! You need a new one![/color]" % [monster.name, result.item_name])
				else:
					messages.append("[color=#FF4444]The %s sunders your %s! (%d%% worn)[/color]" % [monster.name, result.item_name, result.new_wear])

	# Blind ability: persistent debuff that reduces hit chance, hides monster HP, reduces map vision
	if ABILITY_BLIND in abilities and not character.blind_active:
		if randi() % 100 < 40:  # 40% chance
			var blind_duration = ability_cfg.get("blind_duration", 15)
			character.apply_blind(blind_duration)
			messages.append("[color=#808080]The %s blinds you! (-%d%% hit chance, reduced vision for %d turns)[/color]" % [monster.name, ability_cfg.get("blind_hit_reduction", 30), blind_duration])

	# Bleed ability: stacking bleed DoT (can stack up to 3 times)
	if ABILITY_BLEED in abilities and hits > 0:
		var bleed_chance = ability_cfg.get("bleed_chance", 40)
		if randi() % 100 < bleed_chance:
			var bleed_stacks = combat.get("player_bleed_stacks", 0)
			if bleed_stacks < 3:  # Max 3 stacks
				bleed_stacks += 1
				combat["player_bleed_stacks"] = bleed_stacks
				var bleed_damage = max(1, int(monster.strength * ability_cfg.get("bleed_damage_percent", 15) / 100.0))
				combat["player_bleed_damage"] = bleed_damage
				messages.append("[color=#FF4444]The %s causes you to bleed! (%d stacks)[/color]" % [monster.name, bleed_stacks])

	# Slow aura ability: reduces player flee chance (passive)
	if ABILITY_SLOW_AURA in abilities and not combat.get("slow_aura_applied", false):
		combat["slow_aura_applied"] = true
		var slow_reduction = ability_cfg.get("slow_aura_flee_reduction", 25)
		combat["player_slow"] = slow_reduction
		messages.append("[color=#808080]The %s's aura slows you! (-%d%% flee chance)[/color]" % [monster.name, slow_reduction])

	# Weakness ability: applies -25% attack debuff for 20 rounds (persists outside combat)
	if ABILITY_WEAKNESS in abilities and hits > 0 and not character.has_debuff("weakness"):
		var weakness_chance = ability_cfg.get("weakness_chance", 30)  # 30% chance
		if randi() % 100 < weakness_chance:
			character.apply_debuff("weakness", 25, 20)  # 25% reduction, 20 rounds
			messages.append("[color=#FFA500]The %s's attack weakens you! (-25%% attack damage for 20 turns)[/color]" % monster.name)

	# Summoner ability: call reinforcements (once per combat)
	if ABILITY_SUMMONER in abilities and not combat.get("summoner_triggered", false):
		if randi() % 100 < 20:  # 20% chance
			combat["summoner_triggered"] = true
			var base_name = monster.get("base_name", monster.name)
			# Shrieker summons higher-tier monsters with weighted probability
			if base_name == "Shrieker":
				var summon_tier = _get_shrieker_summon_tier()
				var summoned_name = monster_database.get_random_monster_name_from_tier(summon_tier)
				combat["summon_next_fight"] = summoned_name
				combat["monster_fled"] = true  # Shrieker flees after summoning
				messages.append("[color=#FF4444]The %s's shriek echoes through the realm, summoning a %s![/color]" % [monster.name, summoned_name])
				messages.append("[color=#FFA500]The %s scurries away as its call is answered![/color]" % monster.name)
			else:
				# Normal summoner: summons same monster type
				combat["summon_next_fight"] = base_name
				messages.append("[color=#FF4444]The %s calls for reinforcements![/color]" % monster.name)

	# Charm ability: player attacks themselves next turn (once per combat)
	if ABILITY_CHARM in abilities and not combat.get("charm_applied", false):
		if randi() % 100 < 25:  # 25% chance
			combat["charm_applied"] = true
			combat["player_charmed"] = true
			messages.append("[color=#FF00FF]The %s charms you! You will attack yourself next turn![/color]" % monster.name)

	# Audit #5 boss signature — Constricting Web / boss_web_stun. On hit, 25%
	# chance to web the player so their next turn skips. WIS provides
	# resistance like other CC. Does not stack — re-roll only after the web
	# expires.
	if ABILITY_BOSS_WEB_STUN in abilities and hits > 0 and not combat.get("player_webbed", false):
		var web_resist = int(character.get_effective_stat("wisdom") / 4)  # +0.25% per WIS
		var web_chance = max(10, 25 - web_resist)  # Floor at 10%
		if randi() % 100 < web_chance:
			combat["player_webbed"] = true
			messages.append("[color=#A335EE]The %s ensnares you in constricting webs![/color]" % monster.name)
			messages.append("[color=#FFAA00]You are webbed — your next turn is lost struggling free![/color]")

	# Audit #5 boss signature — Festering Bite / boss_festering_bite. Each
	# successful hit applies +1 stack of festering wound (max 5). Stacks tick
	# 2% max HP per player turn. Distinct from generic Bleed (fixed-value DoT
	# applied once) — scales with player's HP pool, accumulates per-hit.
	if ABILITY_BOSS_FESTERING_BITE in abilities and hits > 0:
		var current_stacks = int(combat.get("player_fester_stacks", 0))
		if current_stacks < 5:
			combat["player_fester_stacks"] = current_stacks + 1
			messages.append("[color=#9ACD32]The %s's filthy bite festers! (Festering: %d stack%s)[/color]" % [monster.name, current_stacks + 1, "s" if current_stacks + 1 > 1 else ""])

	# Audit #5 boss signature — Drowning / boss_drowning (Elder Kelpie). Each
	# successful hit applies +1 drowning stack (cap 3). Damage tick handled in
	# the player turn-start block; damage debuff in calculate_damage. Combines
	# DoT + offensive debuff so the player simultaneously loses HP and loses
	# damage output — pressure mounts fast unless you burst.
	if ABILITY_BOSS_DROWNING in abilities and hits > 0:
		var current_drown = int(combat.get("player_drowning_stacks", 0))
		if current_drown < 3:
			combat["player_drowning_stacks"] = current_drown + 1
			messages.append("[color=#1E90FF]The %s drags you under! (Drowning %d/3 — your attacks weaken.)[/color]" % [monster.name, current_drown + 1])

	# Audit #5 boss signature (Slice 8) — Concussive Slam (Ogre Chief).
	# Each successful hit also strips one active player buff (rage, stone
	# skin, haste, forcefield, etc). Counter to buff stacking. Reuses
	# get_active_buff_names() but unlike ABILITY_BUFF_DESTROY (30% chance)
	# this fires 100% on a hit landing.
	if ABILITY_BOSS_CONCUSSIVE_SLAM in abilities and hits > 0:
		var slam_buffs = character.get_active_buff_names()
		if slam_buffs.size() > 0:
			var stripped_buff = slam_buffs[randi() % slam_buffs.size()]
			character.remove_buff(stripped_buff)
			messages.append("[color=#FFA500]The %s's slam shatters your [color=#FFFF00]%s[/color] buff![/color]" % [monster.name, stripped_buff])

	# Audit #5 boss signature (Slice 9) — Building Charm (Succubus Queen). On
	# each successful hit, +1 charm stack (cap 3). At 3 stacks, sets a flag
	# that triggers a forced player self-attack at the start of the player's
	# next turn (handled in the player-turn-start block alongside the existing
	# charm path). Stacks reset to 0 after firing — cyclical pressure.
	if ABILITY_BOSS_BUILDING_CHARM in abilities and hits > 0:
		var charm_stacks = int(combat.get("player_building_charm_stacks", 0)) + 1
		combat["player_building_charm_stacks"] = charm_stacks
		if charm_stacks >= 3:
			combat["player_charmed"] = true
			combat["player_building_charm_stacks"] = 0
			messages.append("[color=#FF00FF][b]CHARM PEAKS![/b][/color] [color=#FF66CC]The %s's seduction overwhelms you — your next turn you'll strike yourself.[/color]" % monster.name)
		else:
			messages.append("[color=#FF66CC]The %s's allure tightens (charm %d/3).[/color]" % [monster.name, charm_stacks])

	# Audit #5 boss signature (Slice 9) — Talon Barrage (Gryphon Alpha). On
	# each successful hit, 30% chance for 2 additional attacks at ~50% of the
	# monster's base attack. Distinct from generic multi_strike (deterministic
	# bonus damage on every hit) — chance-based, two strikes, scales with the
	# boss's attack stat rather than the last damage roll (avoids feedback loop
	# with player defense reducing the burst to zero).
	if ABILITY_BOSS_TALON_BARRAGE in abilities and hits > 0 and randi() % 100 < 30:
		var barrage_base = max(1, int(monster.get("attack", 1) * 0.5))
		for i in range(2):
			character.current_hp = max(1, character.current_hp - barrage_base)
		messages.append("[color=#FFD700][b]TALON BARRAGE![/b][/color] [color=#FF8800]The %s rakes you with two extra strikes! [color=#FF4444]-%d HP[/color] each.[/color]" % [monster.name, barrage_base])

	# Audit #5 boss signature (Slice 10) — Soul Burn (Lich). On each successful
	# hit, drains 5% of the player's primary resource max (mana/stamina/energy
	# by class path). Pressure on resource-dependent classes — distinct from
	# the HP-focused DoTs. Floored at 0.
	if ABILITY_BOSS_SOUL_BURN in abilities and hits > 0:
		var sb_resource = character.get_primary_resource()
		var sb_max = character.get_primary_resource_max()
		var sb_drain = max(1, int(sb_max * 0.05))
		match sb_resource:
			"mana":
				character.current_mana = max(0, character.current_mana - sb_drain)
			"stamina":
				character.current_stamina = max(0, character.current_stamina - sb_drain)
			"energy":
				character.current_energy = max(0, character.current_energy - sb_drain)
		messages.append("[color=#9400D3][b]SOUL BURN![/b][/color] [color=#A0A0FF]The %s tears %d %s from your reserves.[/color]" % [monster.name, sb_drain, sb_resource])

	# Audit #5 boss signature (Slice 10) — Hellfire Stack (Balrog). On each
	# successful hit, FIRST burns for (current_stacks × 4% max HP), THEN +1
	# stack (cap 5). Damage from prior stacks compounds across the fight —
	# distinct from Festering (player-turn tick) and from Drowning (damage
	# debuff). Pure escalating on-hit pressure.
	if ABILITY_BOSS_HELLFIRE_STACK in abilities and hits > 0:
		var hellfire_stacks = int(combat.get("player_hellfire_stacks", 0))
		if hellfire_stacks > 0:
			var hellfire_dmg = max(1, int(character.get_total_max_hp() * 0.04 * hellfire_stacks))
			character.current_hp = max(1, character.current_hp - hellfire_dmg)
			messages.append("[color=#FF4500][b]HELLFIRE![/b][/color] [color=#FF8800]Your existing burns flare for [color=#FF4444]-%d HP[/color] (%d stacks).[/color]" % [hellfire_dmg, hellfire_stacks])
		if hellfire_stacks < 5:
			combat["player_hellfire_stacks"] = hellfire_stacks + 1

	# Audit #5 boss signature (Slice 11) — Forge Heat (Iron Golem Overlord).
	# On-hit +1 heat stack. At 5 stacks, deals 10% player max HP and resets
	# to 0. Threshold burst — distinct from Hellfire Stack's compounding
	# per-hit damage. Players who multi-hit hard hit the threshold faster.
	if ABILITY_BOSS_FORGE_HEAT in abilities and hits > 0:
		var heat_stacks = int(combat.get("forge_heat_stacks", 0)) + 1
		combat["forge_heat_stacks"] = heat_stacks
		if heat_stacks >= 5:
			combat["forge_heat_stacks"] = 0
			var forge_dmg = max(1, int(character.get_total_max_hp() * 0.10))
			character.current_hp = max(1, character.current_hp - forge_dmg)
			messages.append("[color=#CD7F32][b]FORGE HEAT OVERFLOW![/b][/color] [color=#FF8800]The %s's forge-fires erupt! [color=#FF4444]-%d HP[/color].[/color]" % [monster.name, forge_dmg])
		else:
			messages.append("[color=#CD7F32]The %s's heat builds (forge %d/5).[/color]" % [monster.name, heat_stacks])

	# Audit #5 boss signature (Slice 11) — Soul Touch (Nazgul Lord). On each
	# successful hit, +1 soul stack (uncapped). Each stack reduces player
	# effective defense by 2% (consumer in calculate_monster_damage).
	# Compounding, no cap — long fights make you increasingly fragile.
	if ABILITY_BOSS_SOUL_TOUCH in abilities and hits > 0:
		var soul_stacks = int(combat.get("soul_touch_stacks", 0)) + 1
		combat["soul_touch_stacks"] = soul_stacks
		messages.append("[color=#4B0082]The %s's touch withers your soul (Soul Touch %d — defense weakened).[/color]" % [monster.name, soul_stacks])

	# Audit #5 boss signature (Slice 12) — Death Mark first-hit apply (Elder Lich).
	# On the FIRST successful hit, mark the player. Tick is handled in the
	# round-cycle block. Idempotent — only applies once per fight.
	if ABILITY_BOSS_DEATH_MARK in abilities and hits > 0 and not combat.get("player_death_marked", false):
		combat["player_death_marked"] = true
		messages.append("[color=#4B0082][b]DEATH MARK![/b][/color] [color=#9400D3]The %s brands your soul. The mark will pulse every third turn.[/color]" % monster.name)

	# Audit #5 boss signature (Slice 12) — Reaper's Touch (Death Incarnate).
	# Each hit has 15% chance to apply soul mark. At start of next player turn,
	# marked players lose 15% max HP. Per-hit chance with fixed payload.
	if ABILITY_BOSS_REAPERS_TOUCH in abilities and hits > 0 and randi() % 100 < 15:
		combat["player_reaper_marked"] = true
		messages.append("[color=#000000][b]REAPER'S TOUCH![/b][/color] [color=#A0A0A0]The %s brushes you with the scythe — your soul is marked.[/color]" % monster.name)

	# Buff destroy ability: removes one random active buff
	if ABILITY_BUFF_DESTROY in abilities and hits > 0:
		if randi() % 100 < 30:  # 30% chance
			var active_buffs = character.get_active_buff_names()
			if active_buffs.size() > 0:
				var buff_to_remove = active_buffs[randi() % active_buffs.size()]
				character.remove_buff(buff_to_remove)
				messages.append("[color=#FF00FF]The %s dispels your %s![/color]" % [monster.name, buff_to_remove])

	# Shield shatter ability: destroys forcefield/shield buffs instantly
	if ABILITY_SHIELD_SHATTER in abilities and hits > 0:
		if combat.get("forcefield_shield", 0) > 0:
			combat["forcefield_shield"] = 0
			messages.append("[color=#FF0000]The %s shatters your Forcefield![/color]" % monster.name)
		if character.has_buff("defense"):
			character.remove_buff("defense")
			messages.append("[color=#FF4444]The %s shatters your defensive shields![/color]" % monster.name)

	# XP steal ability: steals 1-3% of player XP on hit (rare but punishing)
	if ABILITY_XP_STEAL in abilities and hits > 0:
		if randi() % 100 < 20:  # 20% chance
			var steal_percent = randi_range(1, 3)
			var xp_stolen = max(1, int(character.experience * steal_percent / 100.0))
			character.experience = max(0, character.experience - xp_stolen)
			messages.append("[color=#FF00FF]The %s drains [color=#FF8800]%d[/color] experience from you![/color]" % [monster.name, xp_stolen])

	# Item steal ability: 5% chance to steal random equipped item
	if ABILITY_ITEM_STEAL in abilities and hits > 0:
		if randi() % 100 < 5:  # 5% chance
			var equip_slots = ["weapon", "shield", "armor", "helm", "boots", "ring", "amulet"]
			equip_slots.shuffle()
			for slot in equip_slots:
				var equipped_item = character.get_equipped_item(slot)
				if equipped_item != null and not equipped_item.is_empty():
					character.unequip_item(slot)
					combat["stolen_item"] = equipped_item
					messages.append("[color=#FF0000]The %s steals your %s![/color]" % [monster.name, equipped_item.get("name", slot)])
					break

	# Flee attack ability: monster deals damage then flees (no loot)
	if ABILITY_FLEE_ATTACK in abilities and not combat.get("flee_attack_used", false):
		if randi() % 100 < 30 and monster.current_hp < monster.max_hp * 0.5:  # 30% chance when below 50% HP
			combat["flee_attack_used"] = true
			combat["monster_fled"] = true
			messages.append("[color=#FFA500]The %s strikes one last time and flees into the shadows![/color]" % monster.name)

	# Audit #5 boss signature — Iron Discipline / boss_iron_discipline. Every
	# 5 monster turns, the boss heals 10% max HP and clears its own debuffs
	# (sabotage, weakness stacks). Distinct from regeneration (per-turn flat) —
	# periodic burst that punishes long fights.
	if ABILITY_BOSS_IRON_DISCIPLINE in abilities and combat.round > 0 and combat.round % 5 == 0 and monster.current_hp < monster.max_hp:
		var iron_disc_already = int(combat.get("iron_discipline_last_round", -1))
		if iron_disc_already != int(combat.round):
			combat["iron_discipline_last_round"] = int(combat.round)
			var heal_amt = max(1, int(monster.max_hp * 0.10))
			monster.current_hp = mini(int(monster.max_hp), int(monster.current_hp) + heal_amt)
			combat["monster_sabotaged"] = 0
			combat.erase("monster_weakness")
			messages.append("[color=#C0C0C0][b]IRON DISCIPLINE![/b][/color] [color=#9ACD32]The %s steels itself, healing %d HP and shrugging off debuffs![/color]" % [monster.name, heal_amt])

	# Audit #5 boss signature — Soul Siphon / boss_soul_siphon (Barrow Wight).
	# Every 3 monster turns, drain 8% of player's max HP and heal boss for the
	# same amount. Distinct from passive life_steal (per-hit small %) — periodic
	# burst that the player can plan around. Cannot kill the player (HP floored
	# at 1) so it shapes the fight rather than ending it.
	if ABILITY_BOSS_SOUL_SIPHON in abilities and combat.round > 0 and combat.round % 3 == 0:
		var siphon_already = int(combat.get("soul_siphon_last_round", -1))
		if siphon_already != int(combat.round):
			combat["soul_siphon_last_round"] = int(combat.round)
			var drain_amt = max(1, int(character.get_total_max_hp() * 0.08))
			character.current_hp = max(1, character.current_hp - drain_amt)
			var heal_amt_ss = mini(drain_amt, int(monster.max_hp) - int(monster.current_hp))
			monster.current_hp = mini(int(monster.max_hp), int(monster.current_hp) + drain_amt)
			messages.append("[color=#9370DB][b]SOUL SIPHON![/b][/color] [color=#A0C8E0]The %s drains [color=#FF8800]%d[/color] HP from you — and heals %d.[/color]" % [monster.name, drain_amt, heal_amt_ss])

	# Audit #5 boss signature — Contagion Aura / boss_contagion_aura (Plague
	# Zombie). Every 2 monster turns, apply +1 contagion stack (cap 5). The
	# tick damage is applied at the start of the player's turn (see player
	# turn-start block). Passive — no hit needed — so the player can't dodge
	# the buildup by avoiding attacks, only by ending the fight quickly.
	if ABILITY_BOSS_CONTAGION_AURA in abilities and combat.round > 0 and combat.round % 2 == 0:
		var contagion_already = int(combat.get("contagion_aura_last_round", -1))
		if contagion_already != int(combat.round):
			combat["contagion_aura_last_round"] = int(combat.round)
			var cur_stacks = int(combat.get("player_contagion_stacks", 0))
			if cur_stacks < 5:
				combat["player_contagion_stacks"] = cur_stacks + 1
				messages.append("[color=#6B8E23][b]CONTAGION AURA![/b][/color] [color=#9ACD32]The %s's miasma seeps into you — contagion stack %d/5.[/color]" % [monster.name, cur_stacks + 1])

	# Audit #5 boss signature — Lullaby / boss_lullaby (Siren Enchantress).
	# Every 4 monster turns, force the player to skip their next turn. Flag
	# is consumed at the start of the player's turn. Distinct from Web Stun:
	# deterministic timer (not on-hit), no chance to resist.
	if ABILITY_BOSS_LULLABY in abilities and combat.round > 0 and combat.round % 4 == 0:
		var lullaby_already = int(combat.get("lullaby_last_round", -1))
		if lullaby_already != int(combat.round):
			combat["lullaby_last_round"] = int(combat.round)
			combat["player_lulled"] = true
			messages.append("[color=#00CED1][b]LULLABY![/b][/color] [color=#A0E8FF]The %s's voice rises into an enchanting song. Your eyelids grow heavy...[/color]" % monster.name)

	# Audit #5 boss signature (Slice 8) — Trollish Regrowth (Troll King).
	# When boss <50% HP, heals 8% max HP at start of each monster turn.
	# Threshold-triggered (different from passive regeneration which is
	# always-on). Punishes "almost killed it" stalls — bring burst.
	if ABILITY_BOSS_TROLL_REGROWTH in abilities and monster.current_hp < int(monster.max_hp * 0.5) and monster.current_hp > 0:
		var regrowth_already = int(combat.get("troll_regrowth_last_round", -1))
		if regrowth_already != int(combat.round):
			combat["troll_regrowth_last_round"] = int(combat.round)
			var regrow_amt = max(1, int(monster.max_hp * 0.08))
			var actual_regrow = mini(regrow_amt, int(monster.max_hp) - int(monster.current_hp))
			if actual_regrow > 0:
				monster.current_hp = int(monster.current_hp) + actual_regrow
				messages.append("[color=#7FBF3F][b]TROLLISH REGROWTH![/b][/color] [color=#9ACD32]The %s's flesh knits before your eyes (+%d HP).[/color]" % [monster.name, actual_regrow])

	# Audit #5 boss signature (Slice 8) — Aerial Dive (Wyvern Queen). Every
	# 4 monster turns deals 12% player max HP damage that ignores normal
	# attack flow. Cyclical burst — distinct from on-hit DoTs.
	if ABILITY_BOSS_AERIAL_DIVE in abilities and combat.round > 0 and combat.round % 4 == 0:
		var dive_already = int(combat.get("aerial_dive_last_round", -1))
		if dive_already != int(combat.round):
			combat["aerial_dive_last_round"] = int(combat.round)
			var dive_dmg = max(1, int(character.get_total_max_hp() * 0.12))
			character.current_hp = max(1, character.current_hp - dive_dmg)
			messages.append("[color=#87CEEB][b]AERIAL DIVE![/b][/color] [color=#FF8800]The %s plummets from above! [color=#FF4444]-%d HP[/color].[/color]" % [monster.name, dive_dmg])

	# Audit #5 boss signature (Slice 8) — Labyrinth Charge (Minotaur). Every
	# 5 monster turns, charges for (round × 3%) max player HP burst damage.
	# Time-scaled burst — distinct from Pack Frenzy's per-attack steady ramp.
	if ABILITY_BOSS_LABYRINTH_CHARGE in abilities and combat.round > 0 and combat.round % 5 == 0:
		var charge_already = int(combat.get("labyrinth_charge_last_round", -1))
		if charge_already != int(combat.round):
			combat["labyrinth_charge_last_round"] = int(combat.round)
			var charge_pct = float(combat.round) * 0.03
			var charge_dmg = max(1, int(character.get_total_max_hp() * charge_pct))
			character.current_hp = max(1, character.current_hp - charge_dmg)
			messages.append("[color=#8B4513][b]LABYRINTH CHARGE![/b][/color] [color=#FF8800]The %s tramples you with maddened fury! [color=#FF4444]-%d HP[/color].[/color]" % [monster.name, charge_dmg])

	# Audit #5 boss signature (Slice 8) — Wind Shear (Harpy Matriarch).
	# Every 3 monster turns, the boss's gust halves player damage for the
	# next round only. Periodic offensive debuff — distinct from Drowning
	# (stacking, persistent). Sets a flag consumed by calculate_damage.
	if ABILITY_BOSS_WIND_SHEAR in abilities and combat.round > 0 and combat.round % 3 == 0:
		var shear_already = int(combat.get("wind_shear_last_round", -1))
		if shear_already != int(combat.round):
			combat["wind_shear_last_round"] = int(combat.round)
			combat["player_wind_sheared_until_round"] = int(combat.round) + 1
			messages.append("[color=#87CEEB][b]WIND SHEAR![/b][/color] [color=#A0E8FF]The %s's wings whip a stinging gust around you — your next strike will feel weaker.[/color]" % monster.name)

	# Audit #5 boss signature (Slice 8) — Sonic Echo (Shrieker Titan).
	# Each monster turn adds +1 echo stack; at 4 stacks, deals 15% player
	# max HP burst and resets to 0. Cyclical 4-turn rhythm players can
	# plan around — bursty rather than steady.
	if ABILITY_BOSS_SONIC_ECHO in abilities and combat.round > 0:
		var echo_already = int(combat.get("sonic_echo_last_round", -1))
		if echo_already != int(combat.round):
			combat["sonic_echo_last_round"] = int(combat.round)
			var echo_stacks = int(combat.get("sonic_echo_stacks", 0)) + 1
			combat["sonic_echo_stacks"] = echo_stacks
			if echo_stacks >= 4:
				combat["sonic_echo_stacks"] = 0
				var echo_dmg = max(1, int(character.get_total_max_hp() * 0.15))
				character.current_hp = max(1, character.current_hp - echo_dmg)
				messages.append("[color=#DDA0DD][b]SONIC ECHO RELEASE![/b][/color] [color=#FF8800]The %s's resonance shatters the air around you! [color=#FF4444]-%d HP[/color].[/color]" % [monster.name, echo_dmg])
			else:
				messages.append("[color=#DDA0DD]The %s's screech builds (echo %d/4).[/color]" % [monster.name, echo_stacks])

	# Audit #5 boss signature (Slice 9) — Tremor Stomp (Giant). Every 3 monster
	# turns, deals 10% max HP damage AND forces player skip next turn. Burst +
	# stun combo. HP floored at 1. Sets player_lulled flag (shared with Lullaby).
	if ABILITY_BOSS_TREMOR_STOMP in abilities and combat.round > 0 and combat.round % 3 == 0:
		var tremor_already = int(combat.get("tremor_stomp_last_round", -1))
		if tremor_already != int(combat.round):
			combat["tremor_stomp_last_round"] = int(combat.round)
			var tremor_dmg = max(1, int(character.get_total_max_hp() * 0.10))
			character.current_hp = max(1, character.current_hp - tremor_dmg)
			combat["player_lulled"] = true
			messages.append("[color=#A0522D][b]TREMOR STOMP![/b][/color] [color=#FF8800]The %s slams the ground! [color=#FF4444]-%d HP[/color] — you stagger.[/color]" % [monster.name, tremor_dmg])

	# Audit #5 boss signature (Slice 9) — Hatchling Swarm (Broodmother Wyrmling).
	# Every 4 monster turns, hidden hatchlings burst for 15% max HP damage.
	# Distinct from Aerial Dive's larger burst — slightly smaller, different
	# rhythm (4 turns vs 4 turns... same but a different boss). Floored at 1.
	if ABILITY_BOSS_HATCHLING_SWARM in abilities and combat.round > 0 and combat.round % 4 == 0:
		var swarm_already = int(combat.get("hatchling_swarm_last_round", -1))
		if swarm_already != int(combat.round):
			combat["hatchling_swarm_last_round"] = int(combat.round)
			var swarm_dmg = max(1, int(character.get_total_max_hp() * 0.15))
			character.current_hp = max(1, character.current_hp - swarm_dmg)
			messages.append("[color=#FF6347][b]HATCHLING SWARM![/b][/color] [color=#FF8800]Hidden hatchlings swarm from the shadows! [color=#FF4444]-%d HP[/color].[/color]" % swarm_dmg)

	# Audit #5 boss signature (Slice 9) — Infernal Curse (Demon Overlord). Each
	# monster turn +1 curse stack; at 5 stacks deals 25% max HP burst and resets.
	# Stacking burst with a longer fuse than Sonic Echo (5 vs 4) and bigger
	# payoff (25% vs 15%). Players know the count and can race to kill before it
	# fires.
	if ABILITY_BOSS_INFERNAL_CURSE in abilities and combat.round > 0:
		var curse_already = int(combat.get("infernal_curse_last_round", -1))
		if curse_already != int(combat.round):
			combat["infernal_curse_last_round"] = int(combat.round)
			var curse_stacks = int(combat.get("infernal_curse_stacks", 0)) + 1
			combat["infernal_curse_stacks"] = curse_stacks
			if curse_stacks >= 5:
				combat["infernal_curse_stacks"] = 0
				var curse_dmg = max(1, int(character.get_total_max_hp() * 0.25))
				character.current_hp = max(1, character.current_hp - curse_dmg)
				messages.append("[color=#8B0000][b]INFERNAL CURSE EXPLODES![/b][/color] [color=#FF4444]-%d HP[/color].[/color]" % curse_dmg)
			else:
				messages.append("[color=#9400D3]The %s's curse darkens around you (%d/5).[/color]" % [monster.name, curse_stacks])

	# Audit #5 boss signature (Slice 9) — Triple Threat (Elder Chimaera). Each
	# round applies a different debuff: round %% 3 == 0 → poison stack,
	# == 1 → burn stack, == 2 → slow flag. Cycles through three monstrous heads.
	# Distinct from Drowning (single debuff that stacks) — three rotating effects.
	if ABILITY_BOSS_TRIPLE_THREAT in abilities and combat.round > 0:
		var triple_already = int(combat.get("triple_threat_last_round", -1))
		if triple_already != int(combat.round):
			combat["triple_threat_last_round"] = int(combat.round)
			var phase = int(combat.round) % 3
			if phase == 0:
				# Poison head: +1 poison stack
				var poison_stacks = int(combat.get("player_poison_stacks", 0)) + 1
				combat["player_poison_stacks"] = poison_stacks
				messages.append("[color=#7FBF3F][b]TRIPLE THREAT (Poison)![/b][/color] [color=#9ACD32]The serpent head spits venom (poison %d).[/color]" % poison_stacks)
			elif phase == 1:
				# Burn head: 5% max HP immediate damage
				var burn_dmg = max(1, int(character.get_total_max_hp() * 0.05))
				character.current_hp = max(1, character.current_hp - burn_dmg)
				messages.append("[color=#FF4500][b]TRIPLE THREAT (Burn)![/b][/color] [color=#FF8800]The dragon head exhales flame! [color=#FF4444]-%d HP[/color].[/color]" % burn_dmg)
			else:
				# Slow head: wind-shear-style debuff for next round only
				combat["player_wind_sheared_until_round"] = int(combat.round) + 1
				messages.append("[color=#87CEEB][b]TRIPLE THREAT (Chill)![/b][/color] [color=#A0E8FF]The goat head's breath chills you — your next strike will be weaker.[/color]")

	# Audit #5 boss signature (Slice 10) — Three Heads (Cerberus). Each monster
	# turn, deals 4% player max HP damage that ignores DEF (gnaws through gear).
	# Steady, defense-piercing chip — pressure that gear can't mitigate.
	if ABILITY_BOSS_THREE_HEADS in abilities and combat.round > 0:
		var three_heads_already = int(combat.get("three_heads_last_round", -1))
		if three_heads_already != int(combat.round):
			combat["three_heads_last_round"] = int(combat.round)
			var gnaw_dmg = max(1, int(character.get_total_max_hp() * 0.04))
			character.current_hp = max(1, character.current_hp - gnaw_dmg)
			messages.append("[color=#8B0000][b]THREE HEADS![/b][/color] [color=#FF8800]The %s's heads bite, claw, and gnaw past your armor! [color=#FF4444]-%d HP[/color].[/color]" % [monster.name, gnaw_dmg])

	# Audit #5 boss signature (Slice 10) — Soul Forge (Demon Lord). Every 5
	# monster turns, heals 15% max HP. Distinct from Iron Discipline (10% + clears
	# debuffs at 5 turns) and from Trollish Regrowth (8% threshold-gated). Pure
	# heal cycle, biggest periodic-heal in the boss-sig roster.
	if ABILITY_BOSS_SOUL_FORGE in abilities and combat.round > 0 and combat.round % 5 == 0 and monster.current_hp < monster.max_hp:
		var forge_already = int(combat.get("soul_forge_last_round", -1))
		if forge_already != int(combat.round):
			combat["soul_forge_last_round"] = int(combat.round)
			var forge_amt = max(1, int(monster.max_hp * 0.15))
			var forge_actual = mini(forge_amt, int(monster.max_hp) - int(monster.current_hp))
			if forge_actual > 0:
				monster.current_hp = int(monster.current_hp) + forge_actual
				messages.append("[color=#B22222][b]SOUL FORGE![/b][/color] [color=#9ACD32]The %s drinks from forge-fire, healing %d HP![/color]" % [monster.name, forge_actual])

	# Audit #5 boss signature (Slice 10) — Titan Earthquake. Every 4 monster
	# turns, 8% max HP damage AND permanently +1 earthquake stack (cap 5).
	# Each stack reduces incoming player damage by 10% (consumed in player
	# attack path). Escalating defense — distinct from Stoneform's binary
	# alt-round model.
	if ABILITY_BOSS_TITAN_EARTHQUAKE in abilities and combat.round > 0 and combat.round % 4 == 0:
		var quake_already = int(combat.get("titan_earthquake_last_round", -1))
		if quake_already != int(combat.round):
			combat["titan_earthquake_last_round"] = int(combat.round)
			var quake_dmg = max(1, int(character.get_total_max_hp() * 0.08))
			character.current_hp = max(1, character.current_hp - quake_dmg)
			var quake_stacks = int(combat.get("titan_earthquake_stacks", 0))
			if quake_stacks < 5:
				combat["titan_earthquake_stacks"] = quake_stacks + 1
				messages.append("[color=#8B4513][b]TITAN EARTHQUAKE![/b][/color] [color=#FF8800]The %s shakes the ground! [color=#FF4444]-%d HP[/color]. The %s gains hardened stance (Earthquake %d/5).[/color]" % [monster.name, quake_dmg, monster.name, quake_stacks + 1])
			else:
				messages.append("[color=#8B4513][b]TITAN EARTHQUAKE![/b][/color] [color=#FF8800]The %s shakes the ground! [color=#FF4444]-%d HP[/color].[/color]" % [monster.name, quake_dmg])

	# Audit #5 boss signature (Slice 11) — Dragon's Hoard (Ancient Dragon).
	# Every 5 monster turns, strip one active player buff AND gain a permanent
	# +5% damage stack (consumed in calculate_monster_damage). Long-fight
	# punisher — stalling lets the dragon grow.
	if ABILITY_BOSS_DRAGONS_HOARD in abilities and combat.round > 0 and combat.round % 5 == 0:
		var hoard_already = int(combat.get("dragons_hoard_last_round", -1))
		if hoard_already != int(combat.round):
			combat["dragons_hoard_last_round"] = int(combat.round)
			var hoard_stacks = int(combat.get("dragons_hoard_stacks", 0)) + 1
			combat["dragons_hoard_stacks"] = hoard_stacks
			var hoard_buffs = character.get_active_buff_names()
			if hoard_buffs.size() > 0:
				var swallowed = hoard_buffs[randi() % hoard_buffs.size()]
				character.remove_buff(swallowed)
				messages.append("[color=#FFD700][b]DRAGON'S HOARD![/b][/color] [color=#FFA500]The %s swallows your [color=#FFFF00]%s[/color] buff — the dragon's might grows (+%d%% damage stack %d).[/color]" % [monster.name, swallowed, 5 * hoard_stacks, hoard_stacks])
			else:
				messages.append("[color=#FFD700][b]DRAGON'S HOARD![/b][/color] [color=#FFA500]The %s broods on its hoard — its might grows (+%d%% damage stack %d).[/color]" % [monster.name, 5 * hoard_stacks, hoard_stacks])

	# Audit #5 boss signature (Slice 11) — Element Cycle (Primeval Elemental).
	# 4-phase rotation per round: fire (5% burn) → water (5% resource drain)
	# → earth (next-round wind shear) → air (skip turn).
	if ABILITY_BOSS_ELEMENT_CYCLE in abilities and combat.round > 0:
		var elem_already = int(combat.get("element_cycle_last_round", -1))
		if elem_already != int(combat.round):
			combat["element_cycle_last_round"] = int(combat.round)
			var elem_phase = int(combat.round) % 4
			if elem_phase == 0:
				var fire_dmg = max(1, int(character.get_total_max_hp() * 0.05))
				character.current_hp = max(1, character.current_hp - fire_dmg)
				messages.append("[color=#FF4500][b]ELEMENT CYCLE (Fire)![/b][/color] [color=#FF8800]The elemental burns! [color=#FF4444]-%d HP[/color].[/color]" % fire_dmg)
			elif elem_phase == 1:
				var water_resource = character.get_primary_resource()
				var water_max = character.get_primary_resource_max()
				var water_drain = max(1, int(water_max * 0.05))
				match water_resource:
					"mana":
						character.current_mana = max(0, character.current_mana - water_drain)
					"stamina":
						character.current_stamina = max(0, character.current_stamina - water_drain)
					"energy":
						character.current_energy = max(0, character.current_energy - water_drain)
				messages.append("[color=#1E90FF][b]ELEMENT CYCLE (Water)![/b][/color] [color=#A0C8E0]The current saps -%d %s.[/color]" % [water_drain, water_resource])
			elif elem_phase == 2:
				combat["player_wind_sheared_until_round"] = int(combat.round) + 1
				messages.append("[color=#8B4513][b]ELEMENT CYCLE (Earth)![/b][/color] [color=#FFA500]The earth shifts beneath you — your next strike falters.[/color]")
			else:
				combat["player_lulled"] = true
				messages.append("[color=#87CEEB][b]ELEMENT CYCLE (Air)![/b][/color] [color=#A0E8FF]A gale rips the breath from your lungs — you skip your next turn.[/color]")

	# Audit #5 boss signature (Slice 11) — Riddle Curse (Ancient Sphinx). Every
	# 3 monster turns, +1 riddle stack (cap 5); each stack reduces player damage
	# by 5% (consumer in calculate_damage). Persistent stacking debuff —
	# distinct from Wind Shear (one-round) and Drowning (on-hit, smaller cap).
	if ABILITY_BOSS_RIDDLE_CURSE in abilities and combat.round > 0 and combat.round % 3 == 0:
		var riddle_already = int(combat.get("riddle_curse_last_round", -1))
		if riddle_already != int(combat.round):
			combat["riddle_curse_last_round"] = int(combat.round)
			var riddle_stacks = int(combat.get("riddle_curse_stacks", 0))
			if riddle_stacks < 5:
				combat["riddle_curse_stacks"] = riddle_stacks + 1
				messages.append("[color=#9370DB][b]RIDDLE CURSE![/b][/color] [color=#DDA0DD]The %s poses an impossible riddle — your strength falters (curse %d/5).[/color]" % [monster.name, riddle_stacks + 1])

	# Audit #5 boss signature (Slice 12) — Void Step (Void Walker). Every 3
	# monster turns, the boss phases out. Sets a flag that makes the next
	# player attack deal 0 damage (consumed in player attack path).
	if ABILITY_BOSS_VOID_STEP in abilities and combat.round > 0 and combat.round % 3 == 0:
		var void_already = int(combat.get("void_step_last_round", -1))
		if void_already != int(combat.round):
			combat["void_step_last_round"] = int(combat.round)
			combat["void_step_active"] = true
			messages.append("[color=#9400D3][b]VOID STEP![/b][/color] [color=#DDA0DD]The %s phases out of reality — your next strike will pass through.[/color]" % monster.name)

	# Audit #5 boss signature (Slice 12) — Primordial Roar (Primordial Dragon).
	# Every 5 monster turns, 20% player max HP damage AND strips ALL active
	# player buffs. Single-moment apocalypse.
	if ABILITY_BOSS_PRIMORDIAL_ROAR in abilities and combat.round > 0 and combat.round % 5 == 0:
		var roar_already = int(combat.get("primordial_roar_last_round", -1))
		if roar_already != int(combat.round):
			combat["primordial_roar_last_round"] = int(combat.round)
			var roar_dmg = max(1, int(character.get_total_max_hp() * 0.20))
			character.current_hp = max(1, character.current_hp - roar_dmg)
			var roar_buffs = character.get_active_buff_names()
			for b in roar_buffs:
				character.remove_buff(b)
			if roar_buffs.size() > 0:
				messages.append("[color=#FF6347][b]PRIMORDIAL ROAR![/b][/color] [color=#FF8800]Reality itself shudders! [color=#FF4444]-%d HP[/color]. All your buffs are torn away (%d stripped).[/color]" % [roar_dmg, roar_buffs.size()])
			else:
				messages.append("[color=#FF6347][b]PRIMORDIAL ROAR![/b][/color] [color=#FF8800]Reality itself shudders! [color=#FF4444]-%d HP[/color].[/color]" % roar_dmg)

	# Audit #5 boss signature (Slice 12) — Coil Squeeze (World Serpent). Each
	# monster turn +1 coil stack (cap 10). Stacks tick 1% player max HP at
	# start of player turn (handled in turn-start block).
	if ABILITY_BOSS_COIL_SQUEEZE in abilities and combat.round > 0:
		var coil_already = int(combat.get("coil_squeeze_last_round", -1))
		if coil_already != int(combat.round):
			combat["coil_squeeze_last_round"] = int(combat.round)
			var coil_stacks = int(combat.get("player_coil_stacks", 0))
			if coil_stacks < 10:
				combat["player_coil_stacks"] = coil_stacks + 1
				messages.append("[color=#2E8B57]The %s tightens its coils around you (coil %d/10).[/color]" % [monster.name, coil_stacks + 1])

	# Audit #5 boss signature (Slice 12) — Death Mark periodic tick (Elder Lich).
	# Trigger condition is "player_death_marked" flag set on first hit (handled
	# in on-hit block). When marked AND every 3 monster turns, deals 8% max HP.
	if ABILITY_BOSS_DEATH_MARK in abilities and combat.get("player_death_marked", false) and combat.round > 0 and combat.round % 3 == 0:
		var dmark_already = int(combat.get("death_mark_last_round", -1))
		if dmark_already != int(combat.round):
			combat["death_mark_last_round"] = int(combat.round)
			var dmark_dmg = max(1, int(character.get_total_max_hp() * 0.08))
			character.current_hp = max(1, character.current_hp - dmark_dmg)
			messages.append("[color=#4B0082][b]DEATH MARK![/b][/color] [color=#9400D3]The mark on your soul flares! [color=#FF4444]-%d HP[/color].[/color]" % dmark_dmg)

	# Audit #5 boss signature (Slice 12) — Madness Aura (Cosmic Horror). Every
	# 4 monster turns, sets madness flag for player's next 2 turns. Consumer in
	# player turn-start block has 30% chance to fizzle the action.
	if ABILITY_BOSS_MADNESS_AURA in abilities and combat.round > 0 and combat.round % 4 == 0:
		var madness_already = int(combat.get("madness_aura_last_round", -1))
		if madness_already != int(combat.round):
			combat["madness_aura_last_round"] = int(combat.round)
			combat["player_madness_until_round"] = int(combat.round) + 2
			messages.append("[color=#9400D3][b]MADNESS AURA![/b][/color] [color=#DDA0DD]The %s's gaze unhinges you — your next two turns will falter at random.[/color]" % monster.name)

	# Audit #5 boss signature (Slice 12) — Temporal Rewind (Time Weaver). Every
	# 6 monster turns, heals 25% max HP AND clears all its own debuffs. Slower
	# rhythm than Iron Discipline (5) but bigger heal (25% vs 10%).
	if ABILITY_BOSS_TEMPORAL_REWIND in abilities and combat.round > 0 and combat.round % 6 == 0 and monster.current_hp < monster.max_hp:
		var rewind_already = int(combat.get("temporal_rewind_last_round", -1))
		if rewind_already != int(combat.round):
			combat["temporal_rewind_last_round"] = int(combat.round)
			var rewind_amt = max(1, int(monster.max_hp * 0.25))
			var rewind_actual = mini(rewind_amt, int(monster.max_hp) - int(monster.current_hp))
			monster.current_hp = int(monster.current_hp) + rewind_actual
			combat["monster_sabotaged"] = 0
			combat.erase("monster_weakness")
			messages.append("[color=#4169E1][b]TEMPORAL REWIND![/b][/color] [color=#9ACD32]The %s rewinds itself — heals %d HP and shrugs off all debuffs![/color]" % [monster.name, rewind_actual])

	# Audit #5 boss signature (Slice 12) — Chaotic Surge (Avatar of Chaos).
	# Each monster turn picks a RANDOM effect from a pool of 6 outcomes.
	if ABILITY_BOSS_CHAOTIC_SURGE in abilities and combat.round > 0:
		var chaos_already = int(combat.get("chaotic_surge_last_round", -1))
		if chaos_already != int(combat.round):
			combat["chaotic_surge_last_round"] = int(combat.round)
			var chaos_roll = randi() % 6
			match chaos_roll:
				0:
					var chaos_heal = max(1, int(monster.max_hp * 0.10))
					var chaos_actual = mini(chaos_heal, int(monster.max_hp) - int(monster.current_hp))
					if chaos_actual > 0:
						monster.current_hp = int(monster.current_hp) + chaos_actual
					messages.append("[color=#FF1493][b]CHAOTIC SURGE (Heal)![/b][/color] The %s regenerates %d HP." % [monster.name, chaos_actual])
				1:
					var chaos_dmg = max(1, int(character.get_total_max_hp() * 0.10))
					character.current_hp = max(1, character.current_hp - chaos_dmg)
					messages.append("[color=#FF1493][b]CHAOTIC SURGE (Burst)![/b][/color] Reality shears! [color=#FF4444]-%d HP[/color]." % chaos_dmg)
				2:
					var chaos_buffs = character.get_active_buff_names()
					if chaos_buffs.size() > 0:
						var chaos_buff = chaos_buffs[randi() % chaos_buffs.size()]
						character.remove_buff(chaos_buff)
						messages.append("[color=#FF1493][b]CHAOTIC SURGE (Unweave)![/b][/color] Your [color=#FFFF00]%s[/color] buff is dispelled." % chaos_buff)
					else:
						messages.append("[color=#FF1493][b]CHAOTIC SURGE (Unweave)![/b][/color] Chaos finds nothing to unweave.")
				3:
					combat["player_lulled"] = true
					messages.append("[color=#FF1493][b]CHAOTIC SURGE (Stillness)![/b][/color] Time freezes — you skip your next turn.")
				4:
					combat["chaotic_next_dmg_mult"] = 1.5
					messages.append("[color=#FF1493][b]CHAOTIC SURGE (Frenzy)![/b][/color] The %s's next attack will be enhanced." % monster.name)
				5:
					combat["chaotic_next_dmg_mult"] = 0.5
					messages.append("[color=#FF1493][b]CHAOTIC SURGE (Weakness)![/b][/color] The %s's next attack will be diminished." % monster.name)

	# Audit #5 boss signature (Slice 12) — Divine Punishment (God Slayer).
	# Every 4 monster turns, deals damage = player_level × 5% max HP. High-
	# level players take MORE damage. Scales with player power.
	if ABILITY_BOSS_DIVINE_PUNISHMENT in abilities and combat.round > 0 and combat.round % 4 == 0:
		var divine_already = int(combat.get("divine_punishment_last_round", -1))
		if divine_already != int(combat.round):
			combat["divine_punishment_last_round"] = int(combat.round)
			# Use level multiplier capped so the burst is meaningful but not
			# instakill — at level 100 it'd be 500% max HP otherwise.
			var divine_pct = clamp(float(character.level) * 0.005, 0.10, 0.40)
			var divine_dmg = max(1, int(character.get_total_max_hp() * divine_pct))
			character.current_hp = max(1, character.current_hp - divine_dmg)
			messages.append("[color=#FFD700][b]DIVINE PUNISHMENT![/b][/color] [color=#FF8800]The %s judges your insolence! [color=#FF4444]-%d HP[/color] (scales with your level).[/color]" % [monster.name, divine_dmg])

	# Audit #5 boss signature (Slice 12) — Decay (Entropy). Each monster turn,
	# +1 decay stack (uncapped). The tick is applied in player turn-start block.
	# Existing in the fight costs HP.
	if ABILITY_BOSS_DECAY in abilities and combat.round > 0:
		var decay_already = int(combat.get("decay_last_round", -1))
		if decay_already != int(combat.round):
			combat["decay_last_round"] = int(combat.round)
			var decay_stacks = int(combat.get("player_decay_stacks", 0)) + 1
			combat["player_decay_stacks"] = decay_stacks
			messages.append("[color=#696969]Entropy spreads through you (decay %d).[/color]" % decay_stacks)

	# Build return result - include monster_fled and summon_next_fight if set
	var result = {"success": true, "message": "\n".join(messages)}
	if combat.get("monster_fled", false):
		result["monster_fled"] = true
		result["summon_next_fight"] = combat.get("summon_next_fight", "")
		result["monster_level"] = monster.level
	return result

func calculate_damage(character: Character, monster: Dictionary, combat: Dictionary = {}) -> Dictionary:
	"""Calculate player damage to monster (includes equipment, buffs, crits, class passives, and class advantage)
	Returns dictionary with 'damage', 'is_crit', and 'passive_messages' keys"""
	var cfg = balance_config.get("combat", {})
	var passive_messages = []
	var passive = character.get_class_passive()
	var effects = passive.get("effects", {})

	# Use total attack which includes equipment
	var base_damage = character.get_total_attack()

	# Mage INT-based attack: use INT/5 as minimum base damage when STR is low
	var is_mage_class = character.class_type in ["Wizard", "Sorcerer", "Sage"]
	if is_mage_class:
		var int_attack = int(character.get_effective_stat("intelligence") / 5.0)
		base_damage = max(base_damage, int_attack)

	# Add strength buff bonus
	var strength_buff = character.get_buff_value("strength")
	base_damage += strength_buff

	# Apply STR percentage bonus (configurable, default +2% per point)
	var str_stat = character.get_effective_stat("strength")
	var str_mult = cfg.get("player_str_multiplier", 0.02)
	var str_multiplier = 1.0 + (str_stat * str_mult)
	base_damage = int(base_damage * str_multiplier)

	var damage_roll = (randi() % 6) + 1  # 1d6
	var raw_damage = base_damage + damage_roll

	# Apply damage buff (War Cry, Berserk)
	var damage_buff = character.get_buff_value("damage")
	if damage_buff > 0:
		raw_damage = int(raw_damage * (1.0 + damage_buff / 100.0))

	# Audit #5 Slice 13 — Gargoyle Cathedral SACRED_GROUND blesses next attack
	# with +20% damage. Consumed on use. Picked up via the dungeon move handler
	# which sets `pending_sacred_buff` on the character meta.
	if character.has_meta("pending_sacred_buff") and character.get_meta("pending_sacred_buff", false):
		raw_damage = int(raw_damage * 1.2)
		character.remove_meta("pending_sacred_buff")
		passive_messages.append("[color=#F0E68C]The blessing flares — your strike lands with divine force![/color]")

	# Audit #5 Slice 14 — Orc Stronghold WAR_BANNER buff. +15% damage while
	# combat.round <= player_war_banner_until_round. Picked up via the dungeon
	# move handler which sets `pending_war_banner` on the character meta and
	# is carried into combat in start_combat.
	if int(combat.get("player_war_banner_until_round", 0)) >= int(combat.get("round", 0)):
		raw_damage = int(raw_damage * 1.15)

	# Audit #5 — Drowning debuff (Elder Kelpie boss_drowning). Each stack drops
	# player damage by 10% (cap 3 stacks = -30%). Combined with the DoT tick
	# applied at start of player turn, the player simultaneously loses HP and
	# loses output — the only signature that does both.
	var drown_stacks = int(combat.get("player_drowning_stacks", 0))
	if drown_stacks > 0:
		var drown_mult = max(0.1, 1.0 - 0.1 * drown_stacks)
		raw_damage = max(1, int(raw_damage * drown_mult))

	# Audit #5 Slice 8 — Wind Shear debuff (Harpy Matriarch). When the boss has
	# applied wind shear, the player's damage is halved for the next round only.
	# `player_wind_sheared_until_round` is set by the boss-turn block to
	# (current round + 1) — we check against the CURRENT player turn round
	# (combat.round is incremented in the boss-turn block). Falls through cleanly
	# once the round passes.
	var shear_until = int(combat.get("player_wind_sheared_until_round", -1))
	if shear_until >= int(combat.get("round", 0)):
		raw_damage = max(1, int(raw_damage * 0.5))

	# Audit #5 Slice 11 — Riddle Curse stacks (Ancient Sphinx). Each stack
	# reduces player damage by 5% (cap 5 = -25%). Persistent across the fight.
	var riddle_stacks = int(combat.get("riddle_curse_stacks", 0))
	if riddle_stacks > 0:
		var riddle_mult = max(0.5, 1.0 - 0.05 * riddle_stacks)
		raw_damage = max(1, int(raw_damage * riddle_mult))

	# === COMPANION BONUS: Attack damage ===
	var companion_attack = character.get_companion_bonus("attack")
	# Also add attack bonus from companion passive abilities (stored in combat state)
	companion_attack += combat.get("companion_attack_bonus", 0)
	if companion_attack > 0:
		raw_damage = int(raw_damage * (1.0 + companion_attack / 100.0))
		passive_messages.append("[color=#00FFFF]Companion: +%d%% damage![/color]" % int(companion_attack))

	# === CLASS PASSIVE: Barbarian Blood Rage ===
	# +3% damage per 10% HP missing, max +30%
	if effects.has("damage_per_missing_hp"):
		var hp_percent = float(character.current_hp) / float(character.get_total_max_hp())
		var missing_hp_percent = 1.0 - hp_percent
		var rage_bonus = min(effects.get("max_rage_bonus", 0.30), missing_hp_percent * effects.get("damage_per_missing_hp", 0.03) * 10.0)
		if rage_bonus > 0.01:
			raw_damage = int(raw_damage * (1.0 + rage_bonus))
			passive_messages.append("[color=#8B0000]Blood Rage: +%d%% damage![/color]" % int(rage_bonus * 100))

	# === RACIAL PASSIVE: Orc Low HP Damage ===
	# +20% damage when below 50% HP
	var orc_damage_bonus = character.get_low_hp_damage_bonus()
	if orc_damage_bonus > 0:
		raw_damage = int(raw_damage * (1.0 + orc_damage_bonus))
		passive_messages.append("[color=#556B2F]Orcish Fury: +%d%% damage![/color]" % int(orc_damage_bonus * 100))

	# Critical hit check (configurable base, per-dex, max, and damage multiplier)
	var dex_stat = character.get_effective_stat("dexterity")
	var crit_base = cfg.get("player_crit_base", 5)
	var crit_per_dex = cfg.get("player_crit_per_dex", 0.5)
	var crit_max = cfg.get("player_crit_max", 25)
	var crit_damage = cfg.get("player_crit_damage", 1.5)

	var crit_chance = crit_base + int(dex_stat * crit_per_dex)
	# Add crit bonus from scrolls/potions
	var crit_bonus = combat.get("crit_bonus", 0)
	crit_chance += crit_bonus

	# Add crit bonus from equipment rarity (weapon rarity_bonuses)
	var crit_equipped = character.equipped if character else {}
	var weapon_rb = {}
	if crit_equipped is Dictionary:
		var wpn = crit_equipped.get("weapon", {})
		if wpn is Dictionary:
			weapon_rb = wpn.get("rarity_bonuses", {})
	if weapon_rb.has("crit_chance"):
		crit_chance += int(weapon_rb["crit_chance"])

	# Add companion crit bonus (from base bonus)
	var companion_crit = character.get_companion_bonus("crit_chance")
	if companion_crit > 0:
		crit_chance += int(companion_crit)
	# Add companion crit from passive abilities
	var companion_crit_bonus = combat.get("companion_crit_bonus", 0)
	if companion_crit_bonus > 0:
		crit_chance += companion_crit_bonus
	# Add companion crit from threshold ability buff
	var companion_crit_buff = combat.get("companion_crit_buff", 0)
	if companion_crit_buff > 0:
		crit_chance += companion_crit_buff
		# Decrement duration
		var crit_buff_duration = combat.get("companion_crit_buff_duration", 0)
		if crit_buff_duration > 0:
			combat["companion_crit_buff_duration"] = crit_buff_duration - 1
			if crit_buff_duration - 1 <= 0:
				combat["companion_crit_buff"] = 0

	# === CLASS PASSIVE: Thief Backstab ===
	# +15% base crit chance
	if effects.has("crit_chance_bonus"):
		crit_chance += int(effects.get("crit_chance_bonus", 0) * 100)

	crit_chance = min(crit_chance, 75)  # Cap at 75% even with bonuses
	var is_crit = (randi() % 100) < crit_chance

	# === CLASS PASSIVE: Thief Backstab crit damage bonus ===
	# +50% crit damage multiplier (1.5x becomes 2.0x)
	var final_crit_damage = crit_damage
	if is_crit and effects.has("crit_damage_bonus"):
		final_crit_damage += effects.get("crit_damage_bonus", 0)
	# Weapon rarity crit damage bonus (percentage points, e.g., 10 = +10%)
	if is_crit and weapon_rb.has("crit_damage"):
		final_crit_damage += weapon_rb["crit_damage"] / 100.0
	# Companion crit damage bonus (base bonus + passive abilities like Godslayer)
	var companion_crit_damage = int(character.get_companion_bonus("crit_damage")) + combat.get("companion_crit_damage", 0)
	if is_crit and companion_crit_damage > 0:
		final_crit_damage += companion_crit_damage / 100.0

	if is_crit:
		raw_damage = int(raw_damage * final_crit_damage)

	# === CLASS PASSIVE: Sorcerer Chaos Magic ===
	# 25% chance for double damage, 5% chance to backfire
	var backfire_damage = 0
	if effects.has("double_damage_chance"):
		var chaos_roll = randf()
		if chaos_roll < effects.get("backfire_chance", 0.10):
			# Backfire: deal damage to self (capped at 15% max HP)
			backfire_damage = mini(int(raw_damage * 0.5), int(character.get_total_max_hp() * 0.15))
			raw_damage = int(raw_damage * 0.5)  # Halve the attack damage
			passive_messages.append("[color=#9400D3]Chaos Magic backfires![/color]")
		elif chaos_roll < effects.get("backfire_chance", 0.10) + effects.get("double_damage_chance", 0.25):
			# Double damage
			raw_damage = raw_damage * 2
			passive_messages.append("[color=#9400D3]Chaos Magic surges: DOUBLE DAMAGE![/color]")

	# === CLASS PASSIVE: Wizard Arcane Precision ===
	# +15% spell damage (applied to all attacks for Wizards)
	if effects.has("spell_damage_bonus"):
		raw_damage = int(raw_damage * (1.0 + effects.get("spell_damage_bonus", 0)))

	# Monster defense reduces damage by a percentage (not flat)
	var defense_constant = cfg.get("defense_formula_constant", 100)
	var defense_max = cfg.get("defense_max_reduction", 0.6)
	var defense_ratio = float(monster.defense) / (float(monster.defense) + defense_constant)
	var damage_reduction = defense_ratio * defense_max
	var total = int(raw_damage * (1.0 - damage_reduction))

	# Apply class advantage multiplier
	var affinity = monster.get("class_affinity", 0)
	var class_multiplier = _get_class_advantage_multiplier(affinity, character.class_type)
	total = int(total * class_multiplier)

	# Apply level difference penalty (1.5% per level, max 25%)
	# At 25 level gap: 37.5% penalty, at 50 level gap: 75% penalty (capped at 25%)
	# Good gear should help bridge ~15-20 level gaps, not infinite
	var lvl_diff = monster.get("level", 1) - character.level
	if lvl_diff > 0:
		var lvl_penalty = min(0.25, lvl_diff * 0.015)
		total = int(total * (1.0 - lvl_penalty))

	# === CLASS PASSIVE: Paladin Divine Favor ===
	# +25% damage vs undead/demons
	if effects.has("bonus_vs_undead"):
		var monster_type = monster.get("type", "").to_lower()
		var undead_demon_names = [
			"skeleton", "zombie", "wraith", "wight", "lich", "elder lich", "vampire", "nazgul", "death incarnate",  # Undead
			"demon", "demon lord", "balrog", "succubus"  # Demons
		]
		if "undead" in monster_type or "demon" in monster_type or monster.name.to_lower() in undead_demon_names:
			total = int(total * (1.0 + effects.get("bonus_vs_undead", 0)))
			passive_messages.append("[color=#FFD700]Divine Favor: +%d%% vs undead![/color]" % int(effects.get("bonus_vs_undead", 0) * 100))

	# === CLASS PASSIVE: Ranger Hunter's Mark ===
	# +25% damage vs beasts (natural creatures, animals, monsters with animal forms)
	if effects.has("bonus_vs_beasts"):
		var monster_type = monster.get("type", "").to_lower()
		var beast_names = [
			"giant rat", "wolf", "dire wolf", "giant spider", "bear", "dire bear",  # Basic beasts
			"wyvern", "gryphon", "chimaera", "cerberus", "hydra",  # Mythical beasts
			"world serpent", "harpy", "minotaur"  # Part-beast creatures
		]
		if "beast" in monster_type or "animal" in monster_type or monster.name.to_lower() in beast_names:
			total = int(total * (1.0 + effects.get("bonus_vs_beasts", 0)))
			passive_messages.append("[color=#228B22]Hunter's Mark: +%d%% vs beasts![/color]" % int(effects.get("bonus_vs_beasts", 0) * 100))

	# === MONSTER BANE POTIONS ===
	# Check for monster_bane_<type> buffs that give +damage% vs specific monster types
	var bane_types = ["dragon", "undead", "beast", "demon", "elemental"]
	for bane_type in bane_types:
		var bane_buff_key = "monster_bane_" + bane_type
		var bane_bonus = character.get_buff_value(bane_buff_key)
		if bane_bonus > 0:
			# Check if monster matches this type using drop_tables lookup
			if drop_tables and drop_tables.get_monster_type(monster.name) == bane_type:
				total = int(total * (1.0 + bane_bonus / 100.0))
				passive_messages.append("[color=#FF4500]%s Bane: +%d%% damage![/color]" % [bane_type.capitalize(), bane_bonus])

	# === BOSS-SLAYER TONIC ===
	# Dungeon-exclusive consumable. +damage% against boss-tagged monsters only.
	var boss_bonus = character.get_buff_value("boss_damage")
	if boss_bonus > 0 and bool(monster.get("is_boss", false)):
		total = int(total * (1.0 + boss_bonus / 100.0))
		passive_messages.append("[color=#FF8800]Boss-Slayer: +%d%% damage![/color]" % boss_bonus)

	# === WEAKNESS DEBUFF ===
	# Apply -25% damage if the player has the Weakness debuff
	var weakness_penalty = character.get_debuff_value("weakness")
	if weakness_penalty > 0:
		total = int(total * (1.0 - weakness_penalty / 100.0))
		passive_messages.append("[color=#FFA500]Weakness: -%d%% damage![/color]" % weakness_penalty)

	return {"damage": max(1, total), "is_crit": is_crit, "passive_messages": passive_messages, "backfire_damage": backfire_damage}

func _get_class_advantage_multiplier(affinity: int, character_class: String) -> float:
	"""Calculate damage multiplier based on class affinity.
	Returns: 1.0 (neutral), 1.25 (advantage), 0.85 (disadvantage)"""
	var player_path = _get_player_class_path(character_class)

	match affinity:
		1:  # PHYSICAL - Warriors do +25%, Mages do -15%
			if player_path == "warrior":
				return 1.25
			elif player_path == "mage":
				return 0.85
		2:  # MAGICAL - Mages do +25%, Warriors do -15%
			if player_path == "mage":
				return 1.25
			elif player_path == "warrior":
				return 0.85
		3:  # CUNNING - Tricksters do +25%, others do -15%
			if player_path == "trickster":
				return 1.25
			else:
				return 0.85
	return 1.0  # Neutral

func _get_player_class_path(character_class: String) -> String:
	"""Determine the combat path of a character class"""
	match character_class.to_lower():
		"fighter", "barbarian", "paladin":
			return "warrior"
		"wizard", "sorcerer", "sage":
			return "mage"
		"thief", "ranger", "ninja":
			return "trickster"
		_:
			return "warrior"  # Default

func _get_shrieker_summon_tier() -> int:
	"""Get a weighted random tier for Shrieker summons (4-9, lower tiers more likely)"""
	var roll = randi() % 100
	# Tier 4: 40%, Tier 5: 25%, Tier 6: 15%, Tier 7: 10%, Tier 8: 7%, Tier 9: 3%
	if roll < 40:
		return 4
	elif roll < 65:
		return 5
	elif roll < 80:
		return 6
	elif roll < 90:
		return 7
	elif roll < 97:
		return 8
	else:
		return 9

func _get_tier_for_level(level: int) -> int:
	"""Get monster/player tier based on level (matches monster_database tier ranges)"""
	if level <= 5:
		return 1
	elif level <= 15:
		return 2
	elif level <= 30:
		return 3
	elif level <= 50:
		return 4
	elif level <= 100:
		return 5
	elif level <= 500:
		return 6
	elif level <= 2000:
		return 7
	elif level <= 5000:
		return 8
	else:
		return 9

func calculate_monster_damage(monster: Dictionary, character: Character, combat: Dictionary = {}) -> int:
	"""Calculate monster damage to player (reduced by equipment defense, buffs, and class passives)"""
	var cfg = balance_config.get("combat", {})
	var passive = character.get_class_passive()
	var effects = passive.get("effects", {})

	var base_damage = monster.strength
	var damage_roll = (randi() % 6) + 1  # 1d6
	var raw_damage = base_damage + damage_roll

	# Audit #5 Slice 10 — Vorpal Strike (Jabberwock). Every 4 monster turns
	# the next monster attack deals 3x damage. Check before defense reduction
	# so the strike feels enormous even through gear. Telegraphed by the rhythm.
	var vorpal_abilities = monster.get("abilities", [])
	if ABILITY_BOSS_VORPAL_STRIKE in vorpal_abilities and combat.get("round", 0) > 0 and int(combat.round) % 4 == 0:
		var vorpal_already = int(combat.get("vorpal_last_round", -1))
		if vorpal_already != int(combat.round):
			combat["vorpal_last_round"] = int(combat.round)
			raw_damage *= 3

	# Audit #5 Slice 11 — Dragon's Hoard damage scaling (Ancient Dragon). Each
	# stack from hoard buff-swallows gives the dragon +5% damage (uncapped).
	# Stacks accumulate every 5 turns — long fights become brutal.
	var hoard_stacks_dmg = int(combat.get("dragons_hoard_stacks", 0))
	if hoard_stacks_dmg > 0:
		raw_damage = int(raw_damage * (1.0 + 0.05 * hoard_stacks_dmg))

	# Audit #5 Slice 12 — Chaotic Surge next-attack multiplier (Avatar of Chaos).
	# Set by Frenzy (1.5x) or Weakness (0.5x) outcomes. Consumed on use.
	if combat.has("chaotic_next_dmg_mult"):
		var chaos_mult = float(combat.get("chaotic_next_dmg_mult", 1.0))
		raw_damage = max(1, int(raw_damage * chaos_mult))
		combat.erase("chaotic_next_dmg_mult")

	# Equipment defense provides flat reduction BEFORE defense formula
	# This makes gear meaningful against higher-level monsters
	var equipment_defense = character.get_equipment_defense()
	var equip_cap = cfg.get("equipment_defense_cap", 0.3)
	var equip_divisor = cfg.get("equipment_defense_divisor", 500)
	var equipment_reduction = 0.0
	if equip_cap > 0 and equip_divisor > 0:
		equipment_reduction = min(equip_cap, float(equipment_defense) / equip_divisor)
	raw_damage = int(raw_damage * (1.0 - equipment_reduction))

	# Player defense reduces damage by percentage (not flat)
	var player_defense = character.get_total_defense()

	# Add defense buff bonus
	var defense_buff = character.get_buff_value("defense")
	player_defense += defense_buff

	# Audit #5 Slice 11 — Soul Touch defense erosion (Nazgul Lord). Each
	# soul stack reduces effective defense by 2%, compounding multiplicatively.
	# Uncapped: long fights make you increasingly fragile.
	var soul_stacks_def = int(combat.get("soul_touch_stacks", 0))
	if soul_stacks_def > 0:
		var soul_mult = pow(0.98, soul_stacks_def)
		player_defense = int(player_defense * soul_mult)

	# === COMPANION BONUS: Defense ===
	if character.has_active_companion():
		var companion_defense = int(character.get_companion_bonus("defense"))
		companion_defense += combat.get("companion_defense_bonus", 0)
		player_defense += companion_defense

	# === CLASS PASSIVE: Fighter Tactical Discipline ===
	# +15% defense bonus
	if effects.has("defense_bonus_percent"):
		var defense_bonus = int(player_defense * effects.get("defense_bonus_percent", 0))
		player_defense += defense_bonus

	var defense_constant = cfg.get("defense_formula_constant", 100)
	var defense_max = cfg.get("defense_max_reduction", 0.6)
	var defense_ratio = float(player_defense) / (float(player_defense) + defense_constant)
	var damage_reduction = defense_ratio * defense_max
	var total = int(raw_damage * (1.0 - damage_reduction))

	# Level difference bonus: monsters higher level deal extra damage (exponential)
	var level_diff = monster.level - character.level
	if level_diff > 0:
		var level_base = cfg.get("monster_level_diff_base", 1.04)
		var level_cap = cfg.get("monster_level_diff_cap", 75)
		var level_multiplier = pow(level_base, min(level_diff, level_cap))
		total = int(total * level_multiplier)

	# Minimum damage based on monster level (higher level = higher floor)
	var min_damage = max(1, monster.level / 5)
	return max(min_damage, total)

func get_combat_summary(peer_id: int) -> Dictionary:
	"""Extract combat summary data before end_combat erases it."""
	if not active_combats.has(peer_id):
		return {}
	var combat = active_combats[peer_id]
	return {
		"rounds": combat.round,
		"combat_log": combat.combat_log.duplicate(),
		"monster_name": combat.monster.name,
		"monster_base_name": combat.monster.get("base_name", combat.monster.name),
		"monster_level": combat.monster.level,
		"monster_max_hp": combat.monster.max_hp,
		"total_damage_dealt": combat.get("total_damage_dealt", 0),
		"total_damage_taken": combat.get("total_damage_taken", 0),
		"player_hp_at_start": combat.get("player_hp_at_start", 0),
	}

func end_combat(peer_id: int, victory: bool):
	"""End combat and clean up"""
	if active_combats.has(peer_id):
		var combat = active_combats[peer_id]
		var character = combat.character

		# Restore temporary companion HP/mana boosts
		var hp_boost = combat.get("companion_hp_boost_applied", 0)
		if hp_boost > 0:
			character.max_hp = max(1, character.max_hp - hp_boost)
			# Cap to total max HP (including equipment), not just base max_hp
			character.current_hp = mini(character.current_hp, character.get_total_max_hp())

		var resource_boost = combat.get("companion_resource_boost_applied", 0)
		if resource_boost > 0:
			var boost_type = combat.get("companion_resource_boost_type", "mana")
			match boost_type:
				"stamina":
					character.max_stamina = max(1, character.max_stamina - resource_boost)
					character.current_stamina = mini(character.current_stamina, character.get_total_max_stamina())
				"mana":
					character.max_mana = max(1, character.max_mana - resource_boost)
					character.current_mana = mini(character.current_mana, character.get_total_max_mana())
				"energy":
					character.max_energy = max(1, character.max_energy - resource_boost)
					character.current_energy = mini(character.current_energy, character.get_total_max_energy())
		# Legacy fallback for old combat states
		var mana_boost = combat.get("companion_mana_boost_applied", 0)
		if mana_boost > 0 and resource_boost == 0:
			character.max_mana = max(1, character.max_mana - mana_boost)
			character.current_mana = mini(character.current_mana, character.get_total_max_mana())

		# Mark character as not in combat
		character.in_combat = false

		# Clear combat buffs (round-based)
		character.clear_buffs()

		# Tick persistent buffs (battle-based) - reduces remaining battles by 1
		var expired_persistent = character.tick_persistent_buffs()

		# Store expired persistent buffs for the server to notify about
		if not expired_persistent.is_empty():
			_pending_buff_expirations[peer_id] = expired_persistent

		# Remove from active combats
		active_combats.erase(peer_id)

		print("Combat ended for peer %d - Victory: %s" % [peer_id, victory])

func get_expired_persistent_buffs(peer_id: int) -> Array:
	"""Get and clear any pending persistent buff expiration notifications for a peer."""
	if _pending_buff_expirations.has(peer_id):
		var expired = _pending_buff_expirations[peer_id]
		_pending_buff_expirations.erase(peer_id)
		return expired
	return []

func is_in_combat(peer_id: int) -> bool:
	"""Check if a player is in combat (solo or party)"""
	return active_combats.has(peer_id) or party_combat_membership.has(peer_id)

func get_analyze_bonus(peer_id: int) -> int:
	"""Get the analyze bonus for a player's current combat"""
	if not active_combats.has(peer_id):
		return 0
	return active_combats[peer_id].get("analyze_bonus", 0)

func set_analyze_bonus(peer_id: int, bonus: int):
	"""Set the analyze bonus for a player's current combat (used for flock carry-over)"""
	if active_combats.has(peer_id):
		active_combats[peer_id]["analyze_bonus"] = bonus

func get_combat_display(peer_id: int) -> Dictionary:
	"""Get formatted combat state for display"""
	if not active_combats.has(peer_id):
		return {}

	var combat = active_combats[peer_id]
	var character = combat.character
	var monster = combat.monster

	# Get monster's class affinity for color coding
	var affinity = monster.get("class_affinity", 0)
	var name_color = _get_affinity_color(affinity)

	# Check if player knows this monster (has killed it at or above this level)
	# Use base_name so killing any variant teaches you about the base monster type
	# If unknown OR player is blinded, send -1 for HP values so client shows "???"
	var monster_base = monster.get("base_name", monster.name)
	var knows_monster = character.knows_monster(monster_base, monster.level)
	var can_see_hp = knows_monster and not character.blind_active
	var display_hp = monster.current_hp if can_see_hp else -1
	var display_max_hp = monster.max_hp if can_see_hp else -1
	var display_hp_percent = int((float(monster.current_hp) / monster.max_hp) * 100) if can_see_hp else -1

	return {
		"round": combat.round,
		"player_name": character.name,
		"player_hp": character.current_hp,
		"player_max_hp": character.get_total_max_hp(),
		"player_hp_percent": int((float(character.current_hp) / character.get_total_max_hp()) * 100),
		"player_mana": character.current_mana,
		"player_max_mana": character.get_total_max_mana(),
		"player_stamina": character.current_stamina,
		"player_max_stamina": character.max_stamina,
		"player_energy": character.current_energy,
		"player_max_energy": character.max_energy,
		"monster_name": monster.name,
		"monster_base_name": monster.get("base_name", monster.name),  # Original name for art lookup
		"monster_level": monster.level,
		"monster_hp": display_hp,
		"monster_max_hp": display_max_hp,
		"monster_hp_percent": display_hp_percent,
		"monster_name_color": name_color,  # Color based on class affinity
		"monster_affinity": affinity,
		"monster_abilities": monster.get("abilities", []),  # For client-side trait display
		"monster_known": knows_monster,  # Let client know if HP is real or estimated
		"is_rare_variant": monster.get("is_rare_variant", false),  # For visual indicator
		"is_elite": monster.get("is_elite", false),  # Elite variant — stronger, better loot
		"variant_type": monster.get("variant_type", ""),  # Specific variant ID for client-side border tinting on monster ASCII art
		"can_act": combat.player_can_act,
		# Audit #1 Slice 6a — deck/hand. Client renders the hand as cards
		# in the combat scene; deck/discard counts ride along for the
		# "Deck N · Discard M" status indicator.
		"combat_hand": combat.get("combat_hand", []).duplicate(),
		"combat_deck_count": combat.get("combat_deck", []).size(),
		"combat_discard_count": combat.get("combat_discard", []).size(),
		"combat_hand_size": int(combat.get("combat_hand_size", COMBAT_HAND_SIZE)),
		# Combat status effects (now tracked on character for persistence)
		"poison_active": character.poison_active,
		"poison_damage": character.poison_damage,
		"poison_turns_remaining": character.poison_turns_remaining,
		# Outsmart tracking
		"outsmart_failed": combat.get("outsmart_failed", false),
		# Forcefield/shield for visual display
		"forcefield_shield": combat.get("forcefield_shield", 0),
		# Status-effect strip (additive — old clients ignore these fields).
		# Compact dicts grouped by side so the client renders them under each
		# combatant's HP bar without hunting through scattered top-level keys.
		"player_status": {
			"poison_turns": character.poison_turns_remaining if character.poison_active else 0,
			"poison_damage": character.poison_damage if character.poison_active else 0,
			"blind_turns": character.blind_turns_remaining if character.blind_active else 0,
			"cloak": character.cloak_active,
			"forcefield_shield": int(combat.get("forcefield_shield", 0)),
			"buffs": character.active_buffs.duplicate(true) if character.active_buffs is Array else [],
		},
		"monster_status": {
			"bleed_damage": int(combat.get("monster_bleed", 0)),
			"bleed_turns": int(combat.get("monster_bleed_duration", 0)),
			"poison_damage": int(combat.get("monster_poison", 0)),
			"poison_turns": int(combat.get("monster_poison_duration", 0)),
			"stun_turns": int(combat.get("monster_stunned", 0)),
			"charm_turns": int(combat.get("monster_charmed", 0)),
			"weakness_value": int(combat.get("monster_weakness", 0)),
			"weakness_turns": int(combat.get("monster_weakness_duration", 0)),
			"slow_value": int(combat.get("monster_slowed", 0)),
			"slow_turns": int(combat.get("monster_slow_duration", 0)),
		},
		# Phase B1 — Companion combat HP. Additive fields; old clients ignore
		# them. -1 / false when no active companion.
		"companion_combat_hp": character.get_companion_combat_hp() if character.has_active_companion() else -1,
		"companion_combat_max_hp": character.get_companion_max_hp() if character.has_active_companion() else -1,
		"companion_ko": character.is_companion_ko() if character.has_active_companion() else false,
	}

func get_monster_ascii_art(monster_name: String) -> String:
	# Server-side ASCII art removed - all art is now rendered client-side via monster_art.gd
	return ""

func _get_raw_monster_ascii_art(monster_name: String) -> Array:
	"""Return the raw ASCII art array for color extraction"""
	# This is a simplified lookup - just need the first element for color
	var color_map = {
		"Goblin": ["[color=#00FF00]"],
		"Giant Rat": ["[color=#8B4513]"],
		"Skeleton": ["[color=#FFFFFF]"],
		"Wolf": ["[color=#808080]"],
		"Kobold": ["[color=#CD853F]"],
		"Orc": ["[color=#228B22]"],
		"Hobgoblin": ["[color=#228B22]"],
		"Gnoll": ["[color=#DAA520]"],
		"Zombie": ["[color=#556B2F]"],
		"Giant Spider": ["[color=#2F4F4F]"],
		"Wight": ["[color=#708090]"],
		"Ogre": ["[color=#556B2F]"],
		"Troll": ["[color=#556B2F]"],
		"Wraith": ["[color=#4B0082]"],
		"Minotaur": ["[color=#8B4513]"],
		"Giant": ["[color=#8B4513]"],
		"Vampire": ["[color=#8B0000]"],
		"Demon Lord": ["[color=#FF0000]"],
		"Lich": ["[color=#9400D3]"],
		"Titan": ["[color=#FFD700]"],
		"Wyvern": ["[color=#8FBC8F]"],
		"Ghost": ["[color=#778899]"],
		"Specter": ["[color=#B8B8B8]"],
		"Banshee": ["[color=#E6E6FA]"],
		"Basilisk": ["[color=#2E8B57]"],
		"Chimera": ["[color=#DC143C]"],
		"Manticore": ["[color=#CD5C5C]"],
		"Hydra": ["[color=#006400]"],
		"Phoenix": ["[color=#FF8C00]"],
		"Primordial Dragon": ["[color=#8B0000]"],
		"Ancient Wyrm": ["[color=#4169E1]"],
		"Void Walker": ["[color=#191970]"],
		"Chaos Spawn": ["[color=#800080]"],
		"World Eater": ["[color=#2F4F4F]"],
		"Entropy": ["[color=#000080]"],
	}
	return color_map.get(monster_name, ["[color=#555555]"])

func generate_combat_start_message(character: Character, monster: Dictionary) -> String:
	"""Generate the initial combat message (text only - art is rendered client-side)"""
	return generate_encounter_text(monster)

func generate_encounter_text(monster: Dictionary) -> String:
	"""Generate encounter text WITHOUT ASCII art (for client-side art rendering)"""
	# Get class affinity color
	var affinity = monster.get("class_affinity", 0)  # 0 = NEUTRAL
	var name_color = _get_affinity_color(affinity)

	# Build encounter message with colored monster name (color indicates class affinity)
	var msg = "[color=#FFD700]You encounter a [/color][color=%s]%s[/color][color=#FFD700] (Lvl %d)![/color]" % [name_color, monster.name, monster.level]

	# Show notable abilities
	var abilities = monster.get("abilities", [])
	var notable_abilities = []
	if ABILITY_GLASS_CANNON in abilities:
		notable_abilities.append("[color=#FF4444]Glass Cannon[/color]")
	if ABILITY_REGENERATION in abilities:
		notable_abilities.append("[color=#00FF00]Regenerates[/color]")
	if ABILITY_POISON in abilities:
		notable_abilities.append("[color=#FF00FF]Venomous[/color]")
	if ABILITY_LIFE_STEAL in abilities:
		notable_abilities.append("[color=#FF4444]Life Stealer[/color]")
	if ABILITY_GEM_BEARER in abilities:
		notable_abilities.append("[color=#00FFFF]Gem Bearer[/color]")
	if ABILITY_WISH_GRANTER in abilities:
		notable_abilities.append("[color=#FFD700]Wish Granter[/color]")
	if ABILITY_WEAPON_MASTER in abilities:
		notable_abilities.append("[color=#FF8000]* WEAPON MASTER *[/color]")
	if ABILITY_SHIELD_BEARER in abilities:
		notable_abilities.append("[color=#00FFFF]* SHIELD GUARDIAN *[/color]")
	if ABILITY_CORROSIVE in abilities:
		notable_abilities.append("[color=#FFFF00]! CORROSIVE ![/color]")
	if ABILITY_SUNDER in abilities:
		notable_abilities.append("[color=#FF4444]! SUNDERING ![/color]")
	if ABILITY_CHARM in abilities:
		notable_abilities.append("[color=#FF00FF]Enchanting[/color]")
	if ABILITY_BUFF_DESTROY in abilities:
		notable_abilities.append("[color=#808080]Dispeller[/color]")
	if ABILITY_SHIELD_SHATTER in abilities:
		notable_abilities.append("[color=#FF4444]Shield Breaker[/color]")
	if ABILITY_XP_STEAL in abilities:
		notable_abilities.append("[color=#FF00FF]! XP DRAINER ![/color]")
	if ABILITY_ITEM_STEAL in abilities:
		notable_abilities.append("[color=#FF0000]! PICKPOCKET ![/color]")
	if ABILITY_DISGUISE in abilities:
		notable_abilities.append("[color=#808080]Deceptive[/color]")
	if ABILITY_FLEE_ATTACK in abilities:
		notable_abilities.append("[color=#FFA500]Skirmisher[/color]")

	if notable_abilities.size() > 0:
		msg += "\n[color=#808080]Traits: %s[/color]" % ", ".join(notable_abilities)

	return msg

func _get_affinity_color(affinity: int) -> String:
	"""Get the color code for a class affinity"""
	match affinity:
		1:  # PHYSICAL
			return "#FFFF00"  # Yellow - weak to Warriors
		2:  # MAGICAL
			return "#00BFFF"  # Blue - weak to Mages
		3:  # CUNNING
			return "#00FF00"  # Green - weak to Tricksters
		_:
			return "#FFFFFF"  # White - neutral

# Item Drop System Hooks

func set_drop_tables(tables: Node):
	"""Set the drop tables reference for item drops"""
	drop_tables = tables

func roll_combat_drops(monster: Dictionary, character: Character) -> Array:
	"""Roll for item drops after defeating a monster. Returns array of items.
	NOTE: Does NOT add items to inventory - server handles that to avoid duplication.
	TIER BONUS: Fighting higher tier monsters gives +50% drop chance per tier above."""
	# If drop tables not initialized, return empty
	if drop_tables == null:
		return []

	var drop_table_id = monster.get("drop_table_id", "common")
	var drop_chance = monster.get("drop_chance", 5)
	var monster_level = monster.get("level", 1)

	# Apply tier bonus to drop chance - fighting above your tier is rewarding!
	var player_tier = _get_tier_for_level(character.level)
	var monster_tier = _get_tier_for_level(monster_level)
	var tier_diff = monster_tier - player_tier
	if tier_diff > 0:
		# +50% drop chance per tier above (multiplicative)
		var tier_mult = pow(1.5, tier_diff)  # T+1=1.5x, T+2=2.25x, T+3=3.4x
		drop_chance = int(drop_chance * tier_mult)

	# Slice 6i — Danger Zone loot bonus. Same scale as the XP bonus: edge of
	# hotspot = +30% drop chance, center = +70%. Stacks multiplicatively with
	# the above-tier bonus.
	var hotspot_intensity = float(monster.get("hotspot_intensity", 0.0))
	if hotspot_intensity > 0.0:
		var hotspot_drop_mult = 1.3 + hotspot_intensity * 0.4
		drop_chance = int(drop_chance * hotspot_drop_mult)

	# Roll for drops - server will handle adding to inventory
	return drop_tables.roll_drops(drop_table_id, drop_chance, monster_level)

func _get_rarity_color(rarity: String) -> String:
	"""Get display color for item rarity"""
	var colors = {
		"common": "#FFFFFF",
		"uncommon": "#1EFF00",
		"rare": "#0070DD",
		"epic": "#A335EE",
		"legendary": "#FF8000",
		"artifact": "#E6CC80"
	}
	return colors.get(rarity, "#FFFFFF")

func roll_gem_drops(monster: Dictionary, character: Character) -> int:
	"""Roll for gem drops. Returns number of gems earned.
	   Gems are the primary high-level currency - drop more often at high monster levels."""
	var monster_level = monster.get("level", 1)
	var player_level = character.level
	var level_diff = monster_level - player_level

	# Base gem chance from high monster levels (regardless of player level)
	var level_gem_chance = 0
	if monster_level >= 500:
		level_gem_chance = 40  # L500+ monsters always have good gem chance
	elif monster_level >= 200:
		level_gem_chance = 25
	elif monster_level >= 100:
		level_gem_chance = 15
	elif monster_level >= 50:
		level_gem_chance = 5

	# Bonus gem chance from fighting higher-level monsters
	var diff_gem_chance = 0
	if level_diff >= 100:
		diff_gem_chance = 50
	elif level_diff >= 75:
		diff_gem_chance = 35
	elif level_diff >= 50:
		diff_gem_chance = 25
	elif level_diff >= 30:
		diff_gem_chance = 18
	elif level_diff >= 20:
		diff_gem_chance = 12
	elif level_diff >= 15:
		diff_gem_chance = 8
	elif level_diff >= 10:
		diff_gem_chance = 5
	elif level_diff >= 5:
		diff_gem_chance = 2

	# Combined chance (capped at 80%)
	var gem_chance = mini(80, level_gem_chance + diff_gem_chance)

	if gem_chance <= 0:
		return 0

	# Roll for gem drop
	var roll = randi() % 100
	if roll >= gem_chance:
		return 0

	# Gem quantity formula: scales with monster level
	var cfg = balance_config.get("rewards", {})
	var lethality = monster.get("lethality", 0)
	var lethality_divisor = cfg.get("gem_lethality_divisor", 1000)
	var level_divisor = cfg.get("gem_level_divisor", 50)  # Reduced from 100 for more gems
	var gem_count = max(1, int(lethality / lethality_divisor) + int(monster_level / level_divisor))

	return gem_count

# ===== TITLE ITEM DROPS =====

func roll_title_item_drop(monster_level: int) -> Dictionary:
	"""Roll for title item drops. Returns item dictionary or empty if no drop.
	- Jarl's Ring: 0.5% chance from level 100+ monsters
	- Unforged Crown: 0.2% chance from level 200+ monsters
	"""
	var title_items = TitlesScript.TITLE_ITEMS

	# Check Unforged Crown first (rarer, higher level requirement)
	if monster_level >= 200:
		var crown_info = title_items.get("unforged_crown", {})
		var crown_chance = crown_info.get("drop_chance", 0.2)
		if randf() * 100 < crown_chance:
			return {
				"type": "unforged_crown",
				"name": crown_info.get("name", "Unforged Crown"),
				"rarity": crown_info.get("rarity", "legendary"),
				"description": crown_info.get("description", ""),
				"is_title_item": true
			}

	# Check Jarl's Ring
	if monster_level >= 50:
		var ring_info = title_items.get("jarls_ring", {})
		var ring_chance = ring_info.get("drop_chance", 0.5)
		if randf() * 100 < ring_chance:
			return {
				"type": "jarls_ring",
				"name": ring_info.get("name", "Jarl's Ring"),
				"rarity": ring_info.get("rarity", "legendary"),
				"description": ring_info.get("description", ""),
				"is_title_item": true
			}

	return {}

# ===== WISH GRANTER SYSTEM =====

func generate_wish_options(character: Character, monster_level: int, monster_lethality: int = 100) -> Array:
	"""Generate 3 wish options for player to choose from after defeating a wish granter.
	Options include: gear upgrades, gems, equipment upgrade, or rare permanent stat upgrades."""
	var options = []
	var player_level = character.level
	var level_diff = max(0, monster_level - player_level)

	# Option 1: Always a good option (experience or gear)
	if randf() < 0.5:
		options.append(_generate_experience_wish(monster_level, player_level))
	else:
		options.append(_generate_gear_wish(player_level, monster_level))

	# Option 2: Another good option (different from option 1)
	if options[0].type == "experience":
		options.append(_generate_gear_wish(player_level, monster_level))
	else:
		options.append(_generate_experience_wish(monster_level, player_level))

	# Option 3: Special option - small chance for permanent stats, otherwise buff or equipment upgrade
	if randf() < 0.10:  # 10% chance for permanent stat boost
		options.append(_generate_stat_wish())
	elif randf() < 0.5:
		options.append(_generate_buff_wish())
	else:
		options.append(_generate_upgrade_wish(monster_lethality, level_diff))

	return options

func _generate_experience_wish(monster_level: int, player_level: int) -> Dictionary:
	"""Generate an experience windfall wish option.
	Targets ~50% of a level (roughly 22 kills worth).
	XP to next level = pow(L+1, 2.5) * 100, so 50% = pow(L+1, 2.5) * 50."""
	var effective_level = max(monster_level, player_level)
	var base_xp = int(pow(effective_level + 1, 2.5) * 50)
	var xp_amount = max(1000, base_xp + randi_range(0, int(base_xp * 0.25)))
	return {
		"type": "experience",
		"amount": xp_amount,
		"label": "Windfall of Experience",
		"description": "Gain %d bonus XP" % xp_amount,
		"color": "#00FF00"
	}

func _generate_gear_wish(player_level: int, monster_level: int) -> Dictionary:
	"""Generate a gear reward wish option"""
	var gear_level = max(player_level, monster_level) + randi_range(5, 15)
	var rarity = "rare" if randf() < 0.7 else "epic"
	if randf() < 0.1:
		rarity = "legendary"
	return {
		"type": "gear",
		"level": gear_level,
		"rarity": rarity,
		"label": "%s Lv%d Gear" % [rarity.capitalize(), gear_level],
		"description": "Receive a %s quality item at level %d" % [rarity, gear_level],
		"color": _get_rarity_color(rarity)
	}

func _generate_buff_wish() -> Dictionary:
	"""Generate a powerful temporary buff wish option"""
	var buff_types = [
		{"stat": "damage", "value": 75, "battles": 15, "label": "+75% Damage (15 battles)"},
		{"stat": "defense", "value": 75, "battles": 15, "label": "+75% Defense (15 battles)"},
		{"stat": "speed", "value": 50, "battles": 15, "label": "+50 Speed (15 battles)"},
		{"stat": "crit", "value": 25, "battles": 20, "label": "+25% Crit Chance (20 battles)"}
	]
	var chosen = buff_types[randi() % buff_types.size()]
	return {
		"type": "buff",
		"stat": chosen.stat,
		"value": chosen.value,
		"battles": chosen.battles,
		"label": chosen.label,
		"description": "Powerful combat enhancement",
		"color": "#FFD700"
	}

func _generate_upgrade_wish(monster_lethality: int, level_diff: int) -> Dictionary:
	"""Generate an equipment upgrade wish option.
	Number of upgrades scales with monster lethality and level difference.
	Harder fights = more upgrades."""
	# Base upgrades: 3-5
	# Lethality bonus: +1 per 500 lethality (max +5)
	# Level diff bonus: +1 per 10 levels above player (max +5)
	var base_upgrades = randi_range(3, 5)
	var lethality_bonus = mini(5, int(monster_lethality / 500))
	var level_bonus = mini(5, int(level_diff / 10))
	var total_upgrades = base_upgrades + lethality_bonus + level_bonus

	return {
		"type": "upgrade",
		"upgrades": total_upgrades,
		"label": "Equipment Upgrade (x%d)" % total_upgrades,
		"description": "Upgrade a random equipped item %d time%s" % [total_upgrades, "s" if total_upgrades > 1 else ""],
		"color": "#FF8000"
	}

func _generate_stat_wish() -> Dictionary:
	"""Generate a permanent stat increase wish option (rare!)"""
	var stats = ["strength", "constitution", "dexterity", "intelligence", "wisdom", "wits"]
	var chosen_stat = stats[randi() % stats.size()]
	var boost = randi_range(1, 3)
	return {
		"type": "stats",
		"stat": chosen_stat,
		"amount": boost,
		"label": "+%d %s (PERMANENT)" % [boost, chosen_stat.capitalize()],
		"description": "Permanently increase your %s by %d!" % [chosen_stat, boost],
		"color": "#FF00FF"
	}

func apply_wish_choice(character: Character, wish: Dictionary) -> String:
	"""Apply the chosen wish reward to the character. Returns result message."""
	match wish.type:
		"experience":
			character.add_experience(wish.amount)
			return "[color=#00FF00]+ + [/color][color=#FF00FF]WISH GRANTED: +%d XP![/color][color=#00FF00] + +[/color]" % wish.amount
		"materials":
			var mat_id = wish.get("material_id", "copper_ore")
			character.add_crafting_material(mat_id, wish.amount)
			var mat_name = mat_id.replace("_", " ").capitalize()
			return "[color=#FFD700]WISH GRANTED: +%d %s![/color]" % [wish.amount, mat_name]
		"buff":
			character.add_persistent_buff(wish.stat, wish.value, wish.battles)
			return "[color=#FFD700]WISH GRANTED: %s![/color]" % wish.label
		"stats":
			# Permanent stat increase
			match wish.stat:
				"strength": character.strength += wish.amount
				"constitution": character.constitution += wish.amount
				"dexterity": character.dexterity += wish.amount
				"intelligence": character.intelligence += wish.amount
				"wisdom": character.wisdom += wish.amount
				"wits": character.wits += wish.amount
			return "[color=#FF00FF]WISH GRANTED: Permanent +%d %s![/color]" % [wish.amount, wish.stat.capitalize()]
		"gear":
			# Server will handle gear generation
			return "[color=%s]WISH GRANTED: Generating %s gear...[/color]" % [wish.color, wish.rarity]
		"upgrade":
			# Server will handle equipment upgrades
			return "[color=#FF8000]WISH GRANTED: Upgrading equipment %d time%s...[/color]" % [wish.upgrades, "s" if wish.upgrades > 1 else ""]
	return "[color=#FFD700]WISH GRANTED![/color]"

# ===== COMBAT PERSISTENCE (for disconnect recovery) =====

# ===== Audit #1 Slice 6a — Combat deck / hand / discard =====

func _initialize_combat_deck(combat_state: Dictionary) -> void:
	"""Build a fresh deck for a combat. Slice 6b: reads
	character.combat_deck_collection (ability_name → copy_count) so player
	rank-up choices that grow the deck carry across combats. On first call
	after the Slice 6b patch, initialize_deck_collection_if_needed populates
	the collection with 1 copy of each accessible ability and migrates
	ability_effect_ranks so existing characters don't lose damage. Non-combat
	abilities (e.g. teleport) are stripped. Discard starts empty."""
	var character = combat_state.character
	if character != null and character.has_method("initialize_deck_collection_if_needed"):
		character.initialize_deck_collection_if_needed()
	var deck: Array = []
	var collection: Dictionary = {}
	if character != null and "combat_deck_collection" in character:
		collection = character.combat_deck_collection
	# Build an "accessible now" set so legacy entries for retired/reclassed
	# abilities can't appear in a deck — only currently accessible cards count.
	var accessible := {}
	var available = character.get_all_available_abilities() if (character != null and character.has_method("get_all_available_abilities")) else []
	for entry in available:
		var name = entry.get("name", "")
		if name != "" and not (name in COMBAT_DECK_NON_COMBAT):
			accessible[name] = true
	# Pull each ability the player owns in their collection (1+ copies),
	# clamped to a sane max so a corrupted collection can't generate a 10k deck.
	for ability_name in collection.keys():
		if not accessible.has(ability_name):
			continue
		var copies = int(collection.get(ability_name, 1))
		copies = clamp(copies, 1, 50)
		for i in range(copies):
			deck.append(ability_name)
	# Backstop: if the collection is somehow empty (e.g., a non-player edge case),
	# fall back to 1-of-each accessible so combat is never card-starved.
	if deck.is_empty():
		for name2 in accessible.keys():
			deck.append(name2)
	deck.shuffle()
	combat_state["combat_deck"] = deck
	combat_state["combat_discard"] = []
	combat_state["combat_hand"] = []

func _draw_to_hand(combat_state: Dictionary) -> void:
	"""Refill hand up to combat_hand_size. Pulls from deck; when deck is
	empty, reshuffles discard into deck and continues. Stops if both deck
	and discard are exhausted (hand may end smaller than target)."""
	var hand: Array = combat_state.get("combat_hand", [])
	var deck: Array = combat_state.get("combat_deck", [])
	var discard: Array = combat_state.get("combat_discard", [])
	var target = int(combat_state.get("combat_hand_size", COMBAT_HAND_SIZE))
	while hand.size() < target:
		if deck.is_empty():
			if discard.is_empty():
				break
			deck = discard.duplicate()
			deck.shuffle()
			discard = []
		hand.append(deck.pop_back())
	combat_state["combat_hand"] = hand
	combat_state["combat_deck"] = deck
	combat_state["combat_discard"] = discard

func _consume_card_from_hand(combat_state: Dictionary, ability_name: String) -> bool:
	"""Move a card from hand to discard and refill the hand. Returns true if
	the ability was actually in hand and removed."""
	var hand: Array = combat_state.get("combat_hand", [])
	var idx = hand.find(ability_name)
	if idx < 0:
		return false
	hand.remove_at(idx)
	var discard: Array = combat_state.get("combat_discard", [])
	discard.append(ability_name)
	combat_state["combat_hand"] = hand
	combat_state["combat_discard"] = discard
	_draw_to_hand(combat_state)
	return true

func _ability_alias_to_card(ability_name: String) -> String:
	"""Normalize an inbound ability command (which may be an alias like
	'bolt' or 'shield') to the canonical card name stored in the deck.
	Mirrors the alias map at the top of process_ability_command."""
	match ability_name:
		"bolt": return "magic_bolt"
		"strike": return "power_strike"
		"warcry": return "war_cry"
		"bash": return "shield_bash"
		"ironskin": return "iron_skin"
		"heist": return "perfect_heist"
		"shield": return "forcefield"
	return ability_name

func serialize_combat_state(peer_id: int) -> Dictionary:
	"""Serialize combat state for saving when player disconnects.
	Returns empty dict if not in combat."""
	if not active_combats.has(peer_id):
		return {}

	var combat = active_combats[peer_id]
	var monster = combat.monster

	# Serialize only what's needed to restore combat
	return {
		"monster": {
			"name": monster.get("name", ""),
			"base_name": monster.get("base_name", monster.get("name", "")),
			"level": monster.get("level", 1),
			"current_hp": monster.get("current_hp", 1),
			"max_hp": monster.get("max_hp", 1),
			"strength": monster.get("strength", 10),
			"defense": monster.get("defense", 0),
			"speed": monster.get("speed", 10),
			"abilities": monster.get("abilities", []),
			"is_rare_variant": monster.get("is_rare_variant", false),
			"variant_name": monster.get("variant_name", ""),
			"experience_reward": monster.get("experience_reward", 10),
			"class_affinity": monster.get("class_affinity", 0),
			"is_dungeon_monster": monster.get("is_dungeon_monster", false),
			"is_boss": monster.get("is_boss", false)
		},
		"round": combat.get("round", 1),
		"player_can_act": combat.get("player_can_act", true),
		"outsmart_failed": combat.get("outsmart_failed", false),
		"analyze_bonus": combat.get("analyze_bonus", 0),
		"ambusher_active": combat.get("ambusher_active", false),
		"is_dungeon_combat": combat.get("is_dungeon_combat", false),
		"is_boss_fight": combat.get("is_boss_fight", false),
		"dungeon_monster_id": combat.get("dungeon_monster_id", -1),
		"flock_remaining": combat.get("flock_remaining", 0),
		"cc_resistance": combat.get("cc_resistance", 0),
		# Audit #1 Slice 6a — deck/hand persistence across reconnect.
		"combat_hand_size": int(combat.get("combat_hand_size", COMBAT_HAND_SIZE)),
		"combat_deck": combat.get("combat_deck", []).duplicate(),
		"combat_hand": combat.get("combat_hand", []).duplicate(),
		"combat_discard": combat.get("combat_discard", []).duplicate()
	}

func restore_combat(peer_id: int, character: Character, saved_state: Dictionary) -> Dictionary:
	"""Restore combat from saved state after reconnection.
	Returns result similar to start_combat."""
	if saved_state.is_empty():
		return {"success": false, "message": "No saved combat state"}

	var monster = saved_state.get("monster", {})
	if monster.is_empty():
		return {"success": false, "message": "Invalid monster data"}

	# Migrate old xp_reward key to experience_reward
	if not monster.has("experience_reward") and monster.has("xp_reward"):
		monster["experience_reward"] = monster["xp_reward"]
	elif not monster.has("experience_reward"):
		monster["experience_reward"] = 10

	# Build combat state from saved data
	# Always set player_can_act = true on restore so the player can act immediately
	# (they may have disconnected during the monster's turn phase)
	var combat_state = {
		"peer_id": peer_id,
		"character": character,
		"monster": monster,
		"round": saved_state.get("round", 1),
		"player_can_act": true,
		"combat_log": [],
		"started_at": Time.get_ticks_msec(),
		"outsmart_failed": saved_state.get("outsmart_failed", false),
		"ambusher_active": saved_state.get("ambusher_active", false),
		"analyze_bonus": saved_state.get("analyze_bonus", 0),
		"is_dungeon_combat": saved_state.get("is_dungeon_combat", false),
		"is_boss_fight": saved_state.get("is_boss_fight", false),
		"dungeon_monster_id": saved_state.get("dungeon_monster_id", -1),
		"flock_remaining": saved_state.get("flock_remaining", 0),
		"cc_resistance": saved_state.get("cc_resistance", 0),
		# Audit #1 Slice 6a — deck/hand restoration. If saved state predates
		# Slice 6a (legacy disconnect), arrays are empty and we re-initialize
		# below so the player still has a valid hand.
		# v0.9.419 — clamp restored hand_size to the current const so older
		# saves (with hand_size=5) don't reconstitute with 5-card hands on a
		# 3-cell client strip after the drop from 5 → 3.
		"combat_hand_size": mini(int(saved_state.get("combat_hand_size", COMBAT_HAND_SIZE)), COMBAT_HAND_SIZE),
		"combat_deck": saved_state.get("combat_deck", []).duplicate() if saved_state.get("combat_deck", []) is Array else [],
		"combat_hand": saved_state.get("combat_hand", []).duplicate() if saved_state.get("combat_hand", []) is Array else [],
		"combat_discard": saved_state.get("combat_discard", []).duplicate() if saved_state.get("combat_discard", []) is Array else []
	}

	active_combats[peer_id] = combat_state
	# Re-init deck if legacy save (no deck fields). Hand is drawn fresh so
	# the player isn't stuck with an empty hand on reconnect.
	if combat_state["combat_deck"].is_empty() and combat_state["combat_hand"].is_empty() and combat_state["combat_discard"].is_empty():
		_initialize_combat_deck(combat_state)
		_draw_to_hand(combat_state)
	# v0.9.419 — if a pre-drop save restored a 5-card hand into the new
	# 3-card system, move the excess into discard so the visible hand
	# matches the client cell strip. Refill won't redraw past the new cap
	# until cards leave the hand.
	while combat_state["combat_hand"].size() > combat_state["combat_hand_size"]:
		combat_state["combat_discard"].append(combat_state["combat_hand"].pop_back())

	# Mark character as in combat
	character.in_combat = true

	# Re-apply companion passives if character has active companion (using monster-specific abilities)
	if character.has_active_companion() and drop_tables:
		var companion = character.get_active_companion()
		var companion_level = companion.get("level", 1)
		var monster_type = companion.get("monster_type", "")
		var variant_mult = character.get_variant_stat_multiplier()
		var companion_sub_tier = companion.get("sub_tier", 1)
		var companion_abilities = drop_tables.get_monster_companion_abilities(monster_type, companion_level, variant_mult, companion_sub_tier)
		combat_state["companion_abilities"] = companion_abilities

		if not companion_abilities.passive.is_empty():
			var passive = companion_abilities.passive
			if passive.has("effect") and passive.has("value"):
				_apply_companion_passive_effect(combat_state, character, passive.effect, passive.value)
			if passive.has("effect2") and passive.has("value2"):
				_apply_companion_passive_effect(combat_state, character, passive.effect2, passive.value2)
			if passive.has("effect3") and passive.has("value3"):
				_apply_companion_passive_effect(combat_state, character, passive.effect3, passive.value3)

		combat_state["companion_threshold_triggered"] = false

	# Generate restoration message
	var msg = "[color=#FFFF00]Combat restored![/color]\n"
	msg += "[color=#FF4444]You are fighting: %s (Lvl %d)[/color]\n" % [monster.name, monster.level]
	msg += "[color=#808080]Round %d - Your HP: %d/%d | Enemy HP: %d/%d[/color]" % [
		combat_state.round,
		character.current_hp, character.get_total_max_hp(),
		monster.current_hp, monster.max_hp
	]

	return {
		"success": true,
		"message": msg,
		"combat_state": get_combat_display(peer_id),
		"restored": true
	}

# ===== PARTY COMBAT SYSTEM =====

func start_party_combat(party_members: Array, characters: Dictionary, monster: Dictionary) -> Dictionary:
	"""Start a party combat encounter.
	party_members: Array of peer_ids (leader first)
	characters: Dictionary of peer_id -> Character
	monster: Generated monster dictionary
	Returns: {success, messages, combat_state}
	"""
	if party_members.is_empty():
		return {"success": false, "message": "No party members"}

	var leader_id = party_members[0]
	var party_size = party_members.size()

	# Scale monster HP by party size
	monster["original_max_hp"] = monster.get("max_hp", 100)
	monster.max_hp = int(monster.get("max_hp", 100) * party_size)
	monster.current_hp = monster.max_hp

	# Initiative: use leader's stats
	var leader_char = characters[leader_id]
	var init_roll = randi() % 100
	var monster_speed = monster.get("speed", 10)
	var player_dex = leader_char.get_effective_stat("dexterity")
	var equipment_speed = leader_char.get_equipment_bonuses().get("speed", 0)
	var monster_initiative = clamp(5 + int(monster_speed * 0.15) - int(log(max(1, player_dex + equipment_speed)) * 3.0), 5, 55)
	var monster_goes_first = init_roll < monster_initiative

	# Build per-member combat states
	var member_states = {}
	for pid in party_members:
		var ch = characters[pid]
		ch.in_combat = true
		ch.last_stand_used = false
		member_states[pid] = {
			"total_damage_dealt": 0,
			"total_damage_taken": 0,
			"outsmart_failed": false,
			"companion_threshold_triggered": false,
			"player_hp_at_start": ch.current_hp,
			"analyze_bonus": 0,
			"fled": false,
			"dead": false,
			# Companion buffs applied per member
			"companion_hp_boost_applied": 0,
			"companion_resource_boost_applied": 0,
			"companion_resource_boost_type": "mana",
			"companion_abilities": {},
			"forcefield_shield": 0
		}

	# Create party combat state
	var combat = {
		"leader_peer_id": leader_id,
		"members": party_members.duplicate(),
		"characters": characters,
		"monster": monster,
		"round": 1,
		"current_turn_index": 0 if not monster_goes_first else -1,
		"monster_actions_remaining": 0,
		"fled_members": [],
		"dead_members": [],
		"combat_log": [],
		"started_at": Time.get_ticks_msec(),
		"member_states": member_states,
		"monster_went_first": monster_goes_first,
		"cc_resistance": 0,
		"enrage_stacks": 0,
		"target_weights": {},
		# Monster DOT effects
		"monster_poison": 0,
		"monster_poison_duration": 0,
		"monster_burn": 0,
		"monster_burn_duration": 0,
		"monster_bleed": 0,
		"monster_bleed_duration": 0,
		"monster_stunned": 0,
		"monster_charmed": 0,
	}

	# Initialize equal targeting weights
	for pid in party_members:
		combat.target_weights[pid] = 1.0 / float(party_size)

	# Store in tracking dicts
	active_party_combats[leader_id] = combat
	for pid in party_members:
		party_combat_membership[pid] = leader_id

	# Apply companion passives for each member
	for pid in party_members:
		_apply_party_member_companion(combat, pid)

	# Build start messages
	var messages = []
	var xp_zone = _get_xp_zone_text(leader_char.level, monster)
	messages.append("[color=#FF4444]%s%s appears! (Lv%d, HP: %d)[/color]" % [
		monster.get("name", "Monster"), xp_zone, monster.get("level", 1), monster.max_hp])
	messages.append("[color=#00BFFF]Party combat! %d members vs 1 monster.[/color]" % party_size)

	if monster_goes_first:
		messages.append("[color=#FF8800]The %s strikes first![/color]" % monster.get("name", "monster"))
		# Process monster's first strike - limited to 1 action to prevent instant kills
		var first_results = _process_party_monster_phase(combat, 1)
		messages.append_array(first_results.get("messages", []))
		# After first strike, check for deaths
		_check_party_deaths(combat)
		# Set up first player turn
		combat.current_turn_index = 0
		_skip_inactive_members(combat)

	return {
		"success": true,
		"messages": messages,
		"leader_id": leader_id,
		"first_turn_peer_id": _get_current_turn_peer_id(combat)
	}

func _apply_party_member_companion(combat: Dictionary, peer_id: int):
	"""Apply companion passives for a party member in party combat."""
	var character = combat.characters[peer_id]
	var ms = combat.member_states[peer_id]
	var companion = character.active_companion
	if companion.is_empty():
		return
	# Get companion abilities
	if drop_tables and drop_tables.has_method("get_companion_abilities"):
		var abilities = drop_tables.get_companion_abilities(companion)
		ms["companion_abilities"] = abilities

func _get_xp_zone_text(player_level: int, monster: Dictionary) -> String:
	"""Get XP zone indicator for combat start message."""
	var monster_level = monster.get("level", 1)
	var level_diff = monster_level - player_level
	if level_diff >= 10:
		return " [color=#FF00FF]*TIER CHALLENGE*[/color]"
	elif level_diff >= 5:
		return " [color=#FFD700]*CHALLENGE*[/color]"
	return ""

func process_party_combat_action(leader_id: int, acting_peer_id: int, action: CombatAction) -> Dictionary:
	"""Process a party member's combat action.
	Returns: {success, messages[], combat_ended, victory, next_turn_peer_id, monster_phase_results}
	"""
	if not active_party_combats.has(leader_id):
		return {"success": false, "message": "No active party combat"}

	var combat = active_party_combats[leader_id]
	var current_pid = _get_current_turn_peer_id(combat)

	if acting_peer_id != current_pid:
		return {"success": false, "message": "Not your turn"}

	var character = combat.characters[acting_peer_id]
	var monster = combat.monster
	var ms = combat.member_states[acting_peer_id]
	var messages = []

	var monster_hp_before = monster.current_hp
	var player_hp_before = character.current_hp

	# Process player action using EXISTING solo combat logic adapted for party
	match action:
		CombatAction.ATTACK:
			var result = _party_process_attack(combat, acting_peer_id)
			messages.append_array(result.get("messages", []))
		CombatAction.FLEE:
			var result = _party_process_flee(combat, acting_peer_id)
			messages.append_array(result.get("messages", []))
			if result.get("fled", false):
				combat.fled_members.append(acting_peer_id)
				ms["fled"] = true
				messages.append("[color=#FFAA00]%s flees from battle![/color]" % character.name)
		CombatAction.OUTSMART:
			var result = _party_process_outsmart(combat, acting_peer_id)
			messages.append_array(result.get("messages", []))

	# Track damage
	var damage_dealt = max(0, monster_hp_before - monster.current_hp)
	ms["total_damage_dealt"] = ms.get("total_damage_dealt", 0) + damage_dealt
	var self_damage = max(0, player_hp_before - character.current_hp)
	ms["total_damage_taken"] = ms.get("total_damage_taken", 0) + self_damage

	# Check if monster died
	if monster.current_hp <= 0:
		var victory_result = _process_party_victory(combat)
		messages.append_array(victory_result.get("messages", []))
		return {
			"success": true,
			"messages": messages,
			"combat_ended": true,
			"victory": true,
			"member_rewards": victory_result.get("member_rewards", {})
		}

	# Check if all members fled/dead
	if _all_members_inactive(combat):
		messages.append("[color=#FF4444]The party has been defeated![/color]")
		_end_party_combat(leader_id, false)
		return {"success": true, "messages": messages, "combat_ended": true, "victory": false}

	# Advance to next player or monster phase
	combat.current_turn_index += 1
	_skip_inactive_members(combat)

	if combat.current_turn_index >= combat.members.size():
		# All players acted - monster phase
		var monster_results = _process_party_monster_phase(combat)
		messages.append_array(monster_results.get("messages", []))

		# Check for deaths
		_check_party_deaths(combat)

		# Check if all members dead/fled after monster phase
		if _all_members_inactive(combat):
			messages.append("[color=#FF4444]The party has been wiped out![/color]")
			_end_party_combat(leader_id, false)
			return {"success": true, "messages": messages, "combat_ended": true, "victory": false}

		# Next round
		combat.round += 1
		combat.current_turn_index = 0
		_skip_inactive_members(combat)

	return {
		"success": true,
		"messages": messages,
		"combat_ended": false,
		"victory": false,
		"next_turn_peer_id": _get_current_turn_peer_id(combat)
	}

func process_party_combat_ability(leader_id: int, acting_peer_id: int, ability_name: String, arg: String) -> Dictionary:
	"""Process an ability command from a player in party combat.
	Creates an adapter dict so existing ability functions can be reused."""
	if not active_party_combats.has(leader_id):
		return {"success": false, "message": "No active party combat"}

	var combat = active_party_combats[leader_id]
	var current_pid = _get_current_turn_peer_id(combat)

	if acting_peer_id != current_pid:
		return {"success": false, "message": "Not your turn"}

	var character = combat.characters[acting_peer_id]
	var monster = combat.monster
	var ms = combat.member_states[acting_peer_id]

	var monster_hp_before = monster.current_hp
	var player_hp_before = character.current_hp

	# Normalize ability names (same as solo)
	match ability_name:
		"bolt": ability_name = "magic_bolt"
		"strike": ability_name = "power_strike"
		"warcry": ability_name = "war_cry"
		"bash": ability_name = "shield_bash"
		"ironskin": ability_name = "iron_skin"
		"heist": ability_name = "perfect_heist"
		"shield": ability_name = "forcefield"

	# Build adapter dict that mimics solo combat structure
	var adapter = {
		"character": character,
		"monster": monster,
		"round": combat.round,
		"player_can_act": true,
		"messages": [],
		"total_damage_dealt": ms.get("total_damage_dealt", 0),
		"total_damage_taken": ms.get("total_damage_taken", 0),
		# Per-member buff/debuff state (stored in member_states)
		"outsmart_failed": ms.get("outsmart_failed", false),
		"analyze_bonus": ms.get("analyze_bonus", 0),
		"forcefield_shield": ms.get("forcefield_shield", 0),
		"cloak_active": ms.get("cloak_active", false),
		"haste_active": ms.get("haste_active", false),
		"vanished": ms.get("vanished", false),
		"ninja_flee_protection": ms.get("ninja_flee_protection", false),
		"pickpocket_count": ms.get("pickpocket_count", 0),
		"pickpocket_max": ms.get("pickpocket_max", 2),
		"gambit_kill": ms.get("gambit_kill", false),
		# Shared monster state (stored on combat dict)
		"monster_stunned": combat.get("monster_stunned", 0),
		"monster_burn": combat.get("monster_burn", 0),
		"monster_burn_duration": combat.get("monster_burn_duration", 0),
		"monster_bleed": combat.get("monster_bleed", 0),
		"monster_bleed_duration": combat.get("monster_bleed_duration", 0),
		"monster_poison": combat.get("monster_poison", 0),
		"monster_poison_duration": combat.get("monster_poison_duration", 0),
		"monster_weakness": combat.get("monster_weakness", 0),
		"monster_weakness_duration": combat.get("monster_weakness_duration", 0),
		"monster_slowed": combat.get("monster_slowed", 0),
		"monster_slow_duration": combat.get("monster_slow_duration", 0),
		"monster_mana_drained": combat.get("monster_mana_drained", 0),
		"monster_charmed": combat.get("monster_charmed", 0),
		"monster_sabotaged": combat.get("monster_sabotaged", 0),
		"enemy_distracted": combat.get("enemy_distracted", false),
		"cc_resistance": combat.get("cc_resistance", 0),
		"enrage_stacks": combat.get("enrage_stacks", 0),
		"damage_buff": ms.get("damage_buff", 0),
		"defense_buff": ms.get("defense_buff", 0),
		"disguise_active": combat.get("disguise_active", false),
		"disguise_revealed": combat.get("disguise_revealed", false),
		"disguise_true_stats": combat.get("disguise_true_stats", {}),
		# Companion state
		"companion_hp_regen": ms.get("companion_hp_regen", 0),
		"companion_mana_regen": ms.get("companion_mana_regen", 0),
		"companion_energy_regen": ms.get("companion_energy_regen", 0),
		"companion_stamina_regen": ms.get("companion_stamina_regen", 0),
		"companion_wisdom_bonus": ms.get("companion_wisdom_bonus", 0),
		"companion_speed_bonus": ms.get("companion_speed_bonus", 0),
		"companion_abilities": ms.get("companion_abilities", {}),
		"companion_distraction": combat.get("companion_distraction", false),
		# Dungeon state
		"is_dungeon_combat": combat.get("is_dungeon_combat", false),
		"is_boss_fight": combat.get("is_boss_fight", false),
	}

	# Process the ability using existing solo ability functions
	var result: Dictionary
	if ability_name == "cloak" or ability_name == "all_or_nothing":
		result = _process_universal_ability(adapter, ability_name)
	elif ability_name in ["magic_bolt", "blast", "forcefield", "teleport", "meteor", "haste", "paralyze", "banish"]:
		result = _process_mage_ability(adapter, ability_name, arg)
	elif ability_name in ["power_strike", "war_cry", "shield_bash", "cleave", "berserk", "iron_skin", "devastate", "fortify", "rally"]:
		result = _process_warrior_ability(adapter, ability_name)
	elif ability_name in ["analyze", "distract", "pickpocket", "ambush", "vanish", "exploit", "perfect_heist", "sabotage", "gambit"]:
		result = _process_trickster_ability(adapter, ability_name)
	else:
		return {"success": false, "message": "Unknown ability!"}

	# Copy modified state back from adapter to party combat structures
	# Per-member state
	ms["analyze_bonus"] = adapter.get("analyze_bonus", 0)
	ms["forcefield_shield"] = adapter.get("forcefield_shield", 0)
	ms["cloak_active"] = adapter.get("cloak_active", false)
	ms["haste_active"] = adapter.get("haste_active", false)
	ms["vanished"] = adapter.get("vanished", false)
	ms["ninja_flee_protection"] = adapter.get("ninja_flee_protection", false)
	ms["pickpocket_count"] = adapter.get("pickpocket_count", 0)
	ms["gambit_kill"] = adapter.get("gambit_kill", false)
	ms["damage_buff"] = adapter.get("damage_buff", 0)
	ms["defense_buff"] = adapter.get("defense_buff", 0)
	# Shared monster state — copy back to combat dict
	combat["monster_stunned"] = adapter.get("monster_stunned", 0)
	combat["monster_burn"] = adapter.get("monster_burn", 0)
	combat["monster_burn_duration"] = adapter.get("monster_burn_duration", 0)
	combat["monster_bleed"] = adapter.get("monster_bleed", 0)
	combat["monster_bleed_duration"] = adapter.get("monster_bleed_duration", 0)
	combat["monster_poison"] = adapter.get("monster_poison", 0)
	combat["monster_poison_duration"] = adapter.get("monster_poison_duration", 0)
	combat["monster_weakness"] = adapter.get("monster_weakness", 0)
	combat["monster_weakness_duration"] = adapter.get("monster_weakness_duration", 0)
	combat["monster_slowed"] = adapter.get("monster_slowed", 0)
	combat["monster_slow_duration"] = adapter.get("monster_slow_duration", 0)
	combat["monster_mana_drained"] = adapter.get("monster_mana_drained", 0)
	combat["monster_charmed"] = adapter.get("monster_charmed", 0)
	combat["monster_sabotaged"] = adapter.get("monster_sabotaged", 0)
	combat["enemy_distracted"] = adapter.get("enemy_distracted", false)
	combat["cc_resistance"] = adapter.get("cc_resistance", 0)
	combat["enrage_stacks"] = adapter.get("enrage_stacks", 0)
	combat["disguise_active"] = adapter.get("disguise_active", false)
	combat["disguise_revealed"] = adapter.get("disguise_revealed", false)
	combat["companion_distraction"] = adapter.get("companion_distraction", false)

	# Party CC resistance: each CC used by any party member increases resistance faster
	# This prevents multiple players from perma-stunning/paralyzing
	if ability_name in ["shield_bash", "paralyze"]:
		combat["cc_resistance"] = combat.get("cc_resistance", 0) + 2  # Extra +2 per CC in party

	var messages = result.get("messages", [])

	# Track damage
	var damage_dealt = max(0, monster_hp_before - monster.current_hp)
	ms["total_damage_dealt"] = ms.get("total_damage_dealt", 0) + damage_dealt
	var self_damage = max(0, player_hp_before - character.current_hp)
	ms["total_damage_taken"] = ms.get("total_damage_taken", 0) + self_damage

	# Check if monster died
	if monster.current_hp <= 0:
		var victory_result = _process_party_victory(combat)
		messages.append_array(victory_result.get("messages", []))
		return {
			"success": true,
			"messages": messages,
			"combat_ended": true,
			"victory": true,
			"member_rewards": victory_result.get("member_rewards", {})
		}

	# Check if player died from ability self-damage (backfire etc.)
	if character.current_hp <= 0:
		combat.dead_members.append(acting_peer_id)
		ms["dead"] = true
		messages.append("[color=#FF0000]%s has fallen![/color]" % character.name)

	# Check if all members fled/dead
	if _all_members_inactive(combat):
		messages.append("[color=#FF4444]The party has been defeated![/color]")
		_end_party_combat(leader_id, false)
		return {"success": true, "messages": messages, "combat_ended": true, "victory": false}

	# Check if ability already ended combat (e.g., teleport = flee)
	if result.get("combat_ended", false):
		# Treat as this member fleeing
		if acting_peer_id not in combat.fled_members:
			combat.fled_members.append(acting_peer_id)
			ms["fled"] = true
		if _all_members_inactive(combat):
			_end_party_combat(leader_id, false)
			return {"success": true, "messages": messages, "combat_ended": true, "victory": false}

	# Advance turn (same logic as process_party_combat_action)
	# Free actions (analyze, pickpocket success, etc.) don't advance turns
	var is_free_action = result.get("free_action", false)
	if not is_free_action:
		combat.current_turn_index += 1
		_skip_inactive_members(combat)

		if combat.current_turn_index >= combat.members.size():
			var monster_results = _process_party_monster_phase(combat)
			messages.append_array(monster_results.get("messages", []))
			_check_party_deaths(combat)
			if _all_members_inactive(combat):
				messages.append("[color=#FF4444]The party has been wiped out![/color]")
				_end_party_combat(leader_id, false)
				return {"success": true, "messages": messages, "combat_ended": true, "victory": false}
			combat.round += 1
			combat.current_turn_index = 0
			_skip_inactive_members(combat)

	return {
		"success": true,
		"messages": messages,
		"combat_ended": false,
		"victory": false,
		"next_turn_peer_id": _get_current_turn_peer_id(combat)
	}

func _party_process_attack(combat: Dictionary, peer_id: int) -> Dictionary:
	"""Simplified attack logic for party combat member."""
	var character = combat.characters[peer_id]
	var monster = combat.monster
	var ms = combat.member_states[peer_id]
	var messages = []

	# Resource regen
	var mage_classes = ["Wizard", "Sorcerer", "Sage"]
	if character.class_type in mage_classes:
		var regen_pct = 0.03 if character.class_type == "Sage" else 0.02
		character.current_mana = min(character.get_total_max_mana(), character.current_mana + max(1, int(character.get_total_max_mana() * regen_pct)))

	# Hit chance
	var player_dex = character.get_effective_stat("dexterity")
	var equipment_speed = character.get_equipment_bonuses().get("speed", 0)
	var monster_speed = monster.get("speed", 10)
	var hit_chance = clamp(75 + (player_dex + equipment_speed - monster_speed / 2), 30, 95)
	if character.blind_active:
		hit_chance = max(10, hit_chance - 30)

	var hit_roll = randi() % 100
	if hit_roll >= hit_chance:
		messages.append("[color=#808080]%s's attack misses![/color]" % character.name)
		return {"messages": messages}

	# Damage calculation
	var weapon_damage = character.get_equipment_bonuses().get("attack", 0)
	var base_damage = max(1, character.get_effective_stat("strength") + weapon_damage)

	# Critical hit
	var crit_chance = 5
	if character.class_type == "Thief":
		crit_chance = 15
	elif character.class_type == "Ninja":
		crit_chance = 12
	var is_crit = (randi() % 100) < crit_chance
	if is_crit:
		base_damage = int(base_damage * 1.5)

	# Apply variance
	base_damage = apply_damage_variance(base_damage)

	# Analyze bonus
	var analyze = ms.get("analyze_bonus", 0)
	if analyze > 0:
		base_damage = int(base_damage * (1.0 + analyze / 100.0))

	# Apply damage to monster
	monster.current_hp -= base_damage

	var crit_text = " [color=#FFD700]CRITICAL![/color]" if is_crit else ""
	messages.append("[color=#00FF00]%s attacks for %d damage!%s[/color]" % [character.name, base_damage, crit_text])

	# Process companion attack if applicable
	if not character.active_companion.is_empty() and ms.get("companion_abilities", {}).size() > 0:
		var comp = character.active_companion
		var comp_level = comp.get("level", 1)
		var comp_tier = comp.get("tier", 1)
		var comp_damage = max(1, int(comp_tier * 3 + comp_level * 0.5))
		comp_damage = apply_damage_variance(comp_damage)
		monster.current_hp -= comp_damage
		messages.append("[color=#00FFAA]  %s's companion attacks for %d![/color]" % [character.name, comp_damage])

	return {"messages": messages}

func _party_process_flee(combat: Dictionary, peer_id: int) -> Dictionary:
	"""Process flee attempt for a party member (mirrors solo process_flee bonuses)."""
	var character = combat.characters[peer_id]
	var monster = combat.monster
	var messages = []

	# Get class passive for flee bonuses
	var passive = character.get_class_passive()
	var passive_effects = passive.get("effects", {})

	# Base flee calculation: 40 + DEX + equipment speed/flee + speed buffs - level diff
	var equipment_bonuses = character.get_equipment_bonuses()
	var player_dex = character.get_effective_stat("dexterity")
	var speed_buff = character.get_buff_value("speed")
	var equipment_speed = equipment_bonuses.get("speed", 0)
	var flee_bonus = equipment_bonuses.get("flee_bonus", 0)
	var level_diff = max(0, monster.get("level", 1) - character.level)
	var flee_chance = 40 + player_dex + equipment_speed + speed_buff + flee_bonus - level_diff

	# Class passive: Ninja Shadow Step (+40% flee)
	if passive_effects.has("flee_bonus"):
		var ninja_flee_bonus = int(passive_effects.get("flee_bonus", 0) * 100)
		flee_chance += ninja_flee_bonus
		messages.append("[color=#191970]Shadow Step: +%d%% flee chance![/color]" % ninja_flee_bonus)

	# Companion bonuses
	var companion_flee = character.get_companion_bonus("flee_bonus")
	var companion_speed_flee = int(character.get_companion_bonus("speed")) / 2.0
	companion_flee += companion_speed_flee
	if companion_flee > 0:
		flee_chance += int(companion_flee)
		messages.append("[color=#00FFFF]Companion: +%d%% flee chance![/color]" % int(companion_flee))

	# Slow aura debuff (from monster ability)
	var slow_penalty = combat.get("player_slow", 0)
	if slow_penalty > 0:
		flee_chance -= slow_penalty

	# Flock flee bonus
	var flock_count = combat.get("flock_count", 0)
	if flock_count > 0:
		var flock_flee_bonus = flock_count * 15
		flee_chance += flock_flee_bonus
		messages.append("[color=#FFD700]Flock fatigue: +%d%% flee chance![/color]" % flock_flee_bonus)

	# House flee bonus
	var house_flee = character.house_bonuses.get("flee_bonus", 0)
	if house_flee > 0:
		flee_chance += house_flee

	flee_chance = clamp(flee_chance, 10, 95)

	var roll = randi() % 100
	if roll < flee_chance:
		messages.append("[color=#FFAA00]%s escapes from battle![/color]" % character.name)
		return {"messages": messages, "fled": true}
	else:
		messages.append("[color=#FF4444]%s fails to flee![/color]" % character.name)
		return {"messages": messages, "fled": false}

func _party_process_outsmart(combat: Dictionary, peer_id: int) -> Dictionary:
	"""Process outsmart attempt for a party member."""
	var character = combat.characters[peer_id]
	var monster = combat.monster
	var ms = combat.member_states[peer_id]
	var messages = []

	if ms.get("outsmart_failed", false):
		messages.append("[color=#808080]%s already failed to outsmart this enemy.[/color]" % character.name)
		return {"messages": messages}

	var player_wits = character.wits + character.wits_training_bonus
	var monster_int = monster.get("intelligence", 10)
	var outsmart_chance = clamp(30 + (player_wits - monster_int) * 2, 5, 75)

	var roll = randi() % 100
	if roll < outsmart_chance:
		# Victory by outsmarting
		messages.append("[color=#FFD700]%s outsmarts the %s![/color]" % [character.name, monster.get("name", "monster")])
		monster.current_hp = 0
		return {"messages": messages}
	else:
		ms["outsmart_failed"] = true
		messages.append("[color=#FF4444]%s fails to outsmart the %s![/color]" % [character.name, monster.get("name", "monster")])
		return {"messages": messages}

func _process_party_monster_phase(combat: Dictionary, max_actions: int = 0) -> Dictionary:
	"""Process the monster's actions against party members.
	max_actions: If > 0, limits the number of actions (used for first strike to prevent instant kills)."""
	var monster = combat.monster
	var messages = []

	# Check if monster is stunned
	var stun_turns = int(combat.get("monster_stunned", 0))
	if stun_turns > 0:
		combat["monster_stunned"] = stun_turns - 1
		messages.append("[color=#808080]The %s is stunned![/color]" % monster.get("name", "monster"))
		return {"messages": messages}

	# Monster gets N actions where N = active members (or capped by max_actions)
	var active_members = _get_active_members(combat)
	if active_members.is_empty():
		return {"messages": messages}

	var num_actions = active_members.size()
	if max_actions > 0:
		num_actions = min(num_actions, max_actions)
	var targets = _select_monster_targets(combat, active_members, num_actions)

	messages.append("[color=#FF8800]── %s's Turn ──[/color]" % monster.get("name", "monster"))

	# Tick enrage
	if "enrage" in monster.get("abilities", []):
		combat["enrage_stacks"] = min(10, combat.get("enrage_stacks", 0) + 1)

	for i in range(targets.size()):
		var target_pid = targets[i]
		var target_char = combat.characters[target_pid]
		var target_ms = combat.member_states[target_pid]

		# Calculate damage
		var base_str = monster.get("strength", 10)
		var enrage_bonus = 1.0 + combat.get("enrage_stacks", 0) * 0.1
		var raw_damage = max(1, int(float(base_str) * enrage_bonus))

		# Apply defense
		var player_def = target_char.get_equipment_bonuses().get("defense", 0)
		var damage = max(1, raw_damage - int(player_def * 0.5))

		# Apply variance
		damage = apply_damage_variance(damage)

		# Dodge check (DEX-based)
		var dodge_chance = min(30, target_char.dexterity / 5)
		if (randi() % 100) < dodge_chance:
			messages.append("         [color=#808080]%s dodges the attack![/color]" % target_char.name)
			continue

		# Forcefield check
		var shield = target_ms.get("forcefield_shield", 0)
		if shield > 0:
			var absorbed = min(shield, damage)
			target_ms["forcefield_shield"] = shield - absorbed
			damage -= absorbed
			if damage <= 0:
				messages.append("         [color=#9932CC]%s's forcefield absorbs the hit![/color]" % target_char.name)
				continue

		# Apply damage
		target_char.current_hp -= damage
		target_ms["total_damage_taken"] = target_ms.get("total_damage_taken", 0) + damage

		# Dwarf Last Stand
		if target_char.current_hp <= 0 and target_char.race == "Dwarf" and not target_char.last_stand_used:
			target_char.last_stand_used = true
			target_char.current_hp = max(1, int(target_char.get_total_max_hp() * 0.1))
			messages.append("         [color=#FF8800]%s takes %d damage! [color=#FFD700]LAST STAND! Dwarf resilience![/color][/color]" % [target_char.name, damage])
		else:
			messages.append("         [color=#FF8800]%s takes %d damage! (%d/%d HP)[/color]" % [target_char.name, damage, max(0, target_char.current_hp), target_char.get_total_max_hp()])

	return {"messages": messages}

func _select_monster_targets(combat: Dictionary, active_members: Array, num_actions: int) -> Array:
	"""Select targets for monster actions using weighted random."""
	var targets = []
	var weights = {}

	for pid in active_members:
		weights[pid] = combat.target_weights.get(pid, 1.0 / float(active_members.size()))

	# Normalize weights
	var total_weight = 0.0
	for pid in active_members:
		total_weight += weights.get(pid, 0.0)
	if total_weight <= 0:
		total_weight = 1.0
	for pid in active_members:
		weights[pid] = weights.get(pid, 0.0) / total_weight

	for _i in range(num_actions):
		var roll = randf()
		var cumulative = 0.0
		var chosen = active_members[0]
		for pid in active_members:
			cumulative += weights.get(pid, 0.0)
			if roll <= cumulative:
				chosen = pid
				break
		targets.append(chosen)

		# Halve chosen target's weight, redistribute
		if active_members.size() > 1:
			var halved = weights[chosen] / 2.0
			var redistributed = halved / float(active_members.size() - 1)
			weights[chosen] = halved
			for pid in active_members:
				if pid != chosen:
					weights[pid] = weights.get(pid, 0.0) + redistributed

	# Save updated weights
	combat.target_weights = weights
	return targets

func _check_party_deaths(combat: Dictionary):
	"""Check for newly dead party members."""
	for pid in combat.members:
		if pid in combat.dead_members or pid in combat.fled_members:
			continue
		var ch = combat.characters[pid]
		if ch.current_hp <= 0:
			combat.dead_members.append(pid)
			combat.member_states[pid]["dead"] = true

func _get_active_members(combat: Dictionary) -> Array:
	"""Get list of active (alive and not fled) member peer_ids."""
	var active = []
	for pid in combat.members:
		if pid not in combat.dead_members and pid not in combat.fled_members:
			active.append(pid)
	return active

func _all_members_inactive(combat: Dictionary) -> bool:
	"""Check if all party members have fled or died."""
	return _get_active_members(combat).is_empty()

func _get_current_turn_peer_id(combat: Dictionary) -> int:
	"""Get the peer_id of the member whose turn it is, or -1 if none."""
	if combat.current_turn_index < 0 or combat.current_turn_index >= combat.members.size():
		return -1
	var pid = combat.members[combat.current_turn_index]
	if pid in combat.dead_members or pid in combat.fled_members:
		return -1
	return pid

func _skip_inactive_members(combat: Dictionary):
	"""Skip dead/fled members in the turn order."""
	while combat.current_turn_index < combat.members.size():
		var pid = combat.members[combat.current_turn_index]
		if pid not in combat.dead_members and pid not in combat.fled_members:
			break
		combat.current_turn_index += 1

func _process_party_victory(combat: Dictionary) -> Dictionary:
	"""Process victory for all surviving party members."""
	var monster = combat.monster
	var messages = []
	var member_rewards = {}

	messages.append("[color=#00FF00]══════ VICTORY! ══════[/color]")
	messages.append("[color=#00FF00]The party defeated %s![/color]" % monster.get("name", "monster"))

	# Each surviving member gets FULL rewards (not split)
	for pid in combat.members:
		if pid in combat.dead_members:
			continue
		var character = combat.characters[pid]

		# XP calculation (per member, based on their level)
		var base_xp = monster.get("experience_reward", 10)
		var monster_level = monster.get("level", 1)
		var xp_level_diff = monster_level - character.level
		var xp_multiplier = 1.0
		if xp_level_diff > 0:
			var reference_gap = 10.0 + float(character.level) * 0.05
			var gap_ratio = float(xp_level_diff) / reference_gap
			xp_multiplier = 1.0 + sqrt(gap_ratio) * 0.7
		elif xp_level_diff < 0:
			var under_gap = abs(xp_level_diff)
			var penalty_threshold = 5.0 + float(character.level) * 0.03
			if under_gap > penalty_threshold:
				var excess = under_gap - penalty_threshold
				var penalty = minf(0.6, excess * 0.03)
				xp_multiplier = maxf(0.4, 1.0 - penalty)

		# House XP bonus
		var house_xp_mult = 1.0 + (character.house_bonuses.get("xp_bonus", 0) / 100.0)
		var final_xp = int(base_xp * xp_multiplier * house_xp_mult)

		# Gem drops
		var gems = 0
		if drop_tables and drop_tables.has_method("roll_gem_drops"):
			gems = drop_tables.roll_gem_drops(monster, character)

		member_rewards[pid] = {
			"xp": final_xp,
			"gems": gems,
			"drops": []
		}

		# Loot drops
		if drop_tables and drop_tables.has_method("roll_monster_drops"):
			var drops = drop_tables.roll_monster_drops(monster, character)
			member_rewards[pid]["drops"] = drops

		# Apply rewards
		character.experience += final_xp
		if gems > 0:
			character.add_crafting_material("monster_gem", gems)

		# Level up check
		while character.experience >= character.experience_to_next_level:
			character.experience -= character.experience_to_next_level
			character.level_up()

		messages.append("[color=#00BFFF]%s[/color]: +%d XP%s" % [
			character.name, final_xp,
			", +%d gems" % gems if gems > 0 else ""])

		# Combat durability wear for each surviving party member
		var wear_msgs: Array = []
		_apply_combat_wear(character, wear_msgs)
		for wm in wear_msgs:
			messages.append("[color=#00BFFF]%s[/color] - %s" % [character.name, wm])

	return {"messages": messages, "member_rewards": member_rewards}

func _end_party_combat(leader_id: int, victory: bool):
	"""Clean up party combat state."""
	if not active_party_combats.has(leader_id):
		return
	var combat = active_party_combats[leader_id]

	for pid in combat.members:
		var character = combat.characters.get(pid)
		if character:
			character.in_combat = false
			# Restore companion boosts
			var ms = combat.member_states.get(pid, {})
			var hp_boost = ms.get("companion_hp_boost_applied", 0)
			if hp_boost > 0:
				character.max_hp = max(1, character.max_hp - hp_boost)
				character.current_hp = min(character.current_hp, character.get_total_max_hp())
		party_combat_membership.erase(pid)

	active_party_combats.erase(leader_id)

func get_party_combat_state(leader_id: int) -> Dictionary:
	"""Get party combat state for client display."""
	if not active_party_combats.has(leader_id):
		return {}
	var combat = active_party_combats[leader_id]
	var monster = combat.monster
	var members_info = []
	for pid in combat.members:
		var ch = combat.characters.get(pid)
		if not ch:
			continue
		members_info.append({
			"peer_id": pid,
			"name": ch.name,
			"current_hp": max(0, ch.current_hp),
			"max_hp": ch.get_total_max_hp(),
			"current_mana": ch.current_mana,
			"max_mana": ch.get_total_max_mana(),
			"current_stamina": ch.current_stamina,
			"max_stamina": ch.get_total_max_stamina(),
			"current_energy": ch.current_energy,
			"max_energy": ch.get_total_max_energy(),
			"class_type": ch.class_type,
			"is_dead": pid in combat.dead_members,
			"is_fled": pid in combat.fled_members
		})
	return {
		"monster_name": monster.get("name", "Monster"),
		"monster_level": monster.get("level", 1),
		"monster_hp": max(0, monster.current_hp),
		"monster_max_hp": monster.max_hp,
		"round": combat.round,
		"members": members_info,
		"current_turn_peer_id": _get_current_turn_peer_id(combat)
	}
