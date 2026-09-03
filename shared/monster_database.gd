# monster_database.gd
# Monster definitions and generation for Phantasia 4 style combat
class_name MonsterDatabase
extends Node

# Class affinity types - determines which player class has advantage
enum ClassAffinity {
	NEUTRAL,    # No advantage - white/gray name (majority)
	PHYSICAL,   # Weak to Warriors, resistant to Mages - yellow name
	MAGICAL,    # Weak to Mages, resistant to Warriors - blue name
	CUNNING     # Weak to Tricksters, resistant to other paths - green name
}

# Monster ability flags
const ABILITY_GLASS_CANNON = "glass_cannon"      # 3x damage but 50% HP
const ABILITY_MULTI_STRIKE = "multi_strike"      # Attacks 2-3 times per turn
const ABILITY_POISON = "poison"                  # Damage over time
const ABILITY_MANA_DRAIN = "mana_drain"          # Steals player mana
const ABILITY_STAMINA_DRAIN = "stamina_drain"    # Drains stamina
const ABILITY_ENERGY_DRAIN = "energy_drain"      # Drains energy
const ABILITY_REGENERATION = "regeneration"      # Heals 10% HP per turn
const ABILITY_DAMAGE_REFLECT = "damage_reflect"  # Reflects 25% of damage taken
const ABILITY_ETHEREAL = "ethereal"              # 50% chance to dodge
const ABILITY_ARMORED = "armored"                # Reduces incoming damage by 50%
const ABILITY_SUMMONER = "summoner"              # Can call another monster
const ABILITY_PACK_LEADER = "pack_leader"        # High flock chance, stronger pack
const ABILITY_GOLD_HOARDER = "gold_hoarder"      # Legacy — no effect (gold removed)
const ABILITY_GEM_BEARER = "gem_bearer"          # Always drops gems
const ABILITY_CURSE = "curse"                    # Reduces stats during combat
const ABILITY_DISARM = "disarm"                  # Reduces weapon damage
const ABILITY_UNPREDICTABLE = "unpredictable"    # Wild damage variance
const ABILITY_WISH_GRANTER = "wish_granter"      # Grants buff on death
const ABILITY_DEATH_CURSE = "death_curse"        # Deals damage when killed
const ABILITY_BERSERKER = "berserker"            # Damage scales with missing HP
const ABILITY_COWARD = "coward"                  # Flees at low HP (no loot)
const ABILITY_LIFE_STEAL = "life_steal"          # Heals for damage dealt
const ABILITY_ENRAGE = "enrage"                  # Gets stronger each round
const ABILITY_AMBUSHER = "ambusher"              # First attack always crits
const ABILITY_EASY_PREY = "easy_prey"            # Low stats but no special rewards
const ABILITY_THORNS = "thorns"                  # Damages attacker on melee
const ABILITY_WEAPON_MASTER = "weapon_master"    # Guaranteed weapon drop on death
const ABILITY_SHIELD_BEARER = "shield_bearer"    # Guaranteed shield drop on death
const ABILITY_CORROSIVE = "corrosive"            # Chance to damage player's equipment on hit
const ABILITY_SUNDER = "sunder"                  # Specifically damages weapons/shields
const ABILITY_BLIND = "blind"                    # Reduces player hit chance (30%)
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

# ============================================================================
# EMPOWERED MODIFIERS (v0.9.651 — ARPG arc pillar 1)
# ============================================================================
# Diablo-2-style stacking elite affixes, rolled SEPARATELY from the legacy
# variant system (Weapon Master / Corrosive / ★ Champion stay untouched).
# 15% of eligible monsters (Lv5+, no legacy variant) become Empowered with
# 1-3 modifiers; prefixes stack in the name ("Frenzied Gilded Wolf").
#
# Each entry: prefix (name), optional ability (existing combat ability the
# modifier injects — behavior comes free from combat_manager), stat mults,
# color (client callout/border tint). Modifiers without an ability get
# bespoke hooks: juggernaut = stun shrug, warded = -35% ability damage in
# apply_ability_damage_modifiers, gilded/broodcalling = loot/flock fields.
#
# COUNTERPLAY RULE (permadeath): nothing here may reduce flee chance, and
# reflected/DoT damage relies on the existing can't-kill clamps (thorns and
# poison both floor player HP at 1). Keep it that way.
const EMPOWERED_MODIFIERS = {
	"frenzied":     {"prefix": "Frenzied",     "ability": ABILITY_ENRAGE,       "str_mult": 1.10, "color": "#FF5555"},
	"vampiric":     {"prefix": "Vampiric",     "ability": ABILITY_LIFE_STEAL,   "hp_mult": 1.15,  "color": "#C71585"},
	"thorned":      {"prefix": "Thorned",      "ability": ABILITY_THORNS,       "def_mult": 1.20, "color": "#9ACD32"},
	"swift":        {"prefix": "Swift",        "ability": ABILITY_MULTI_STRIKE, "color": "#00E5EE"},
	"juggernaut":   {"prefix": "Juggernaut",   "hp_mult": 1.50, "def_mult": 1.15, "color": "#B8860B"},
	"venomous":     {"prefix": "Venomous",     "ability": ABILITY_POISON,       "hp_mult": 1.10,  "color": "#BA55D3"},
	"warded":       {"prefix": "Warded",       "hp_mult": 1.15, "color": "#7B68EE"},
	"gilded":       {"prefix": "Gilded",       "color": "#FFD700"},
	"broodcalling": {"prefix": "Broodcalling", "color": "#FF8C00"},
}

# Name color by modifier count — D2-style rarity ladder (1 = blue magic,
# 2 = purple, 3 = orange). Client renders the monster name + ASCII border in
# this color via the existing name_color override path (v0.9.513 apex pattern).
const EMPOWERED_NAME_COLORS = {1: "#4FC3F7", 2: "#BA68C8", 3: "#FFB74D"}

# v0.9.718/719 (dungeon arc slice 1) — enemy COSMETIC tint. ~COSMETIC_CHANCE of monsters
# spawn with a random color + pattern that recolors their combat ASCII art body (purely
# visual — no stat effect). Rolls from the SAME pool as companions/eggs
# (DropTables.EGG_VARIANTS via roll_cosmetic_variant), so enemies can get ANY color +
# ANY pattern a companion can. Future dungeon themes will stamp ONE variant dungeon-wide.
const COSMETIC_CHANCE = 0.12

# Balance configuration (set by server)
var balance_config: Dictionary = {}

# v0.9.718 — dev toggle (admin): when true, EVERY generated monster gets a cosmetic tint
# (bypasses the 12% roll + the plain-only gate) so enemy cosmetics can be verified on
# demand instead of grinding the RNG. Flipped by server handle_gm_force_cosmetic.
var force_cosmetic: bool = false

# Slice 6b — biome affinity. Each monster type maps to the biome strings (see
# world_system.gd: "plains", "forest", "mountain", "swamp", "snow", "desert")
# where it appears more often. select_monster_type applies a 3× weight
# multiplier when the encounter biome matches an entry in this list — strong
# bias toward thematic encounters without strict filtering (a Tundra player
# can still occasionally meet a wandering Goblin, just rarely). Missing
# entries or empty arrays = no biome preference (legendary tier-7+ monsters
# fit anywhere). Resolution: monster's biome list checked AFTER the type is
# in the level-appropriate pool, so biome never lets a higher-tier monster
# spawn before its tier — it only re-weights inside the existing pool.
const BIOME_AFFINITY = {
	# Tier 1
	MonsterType.GOBLIN:     ["forest", "mountain", "plains"],
	MonsterType.GIANT_RAT:  ["swamp", "plains", "mountain"],
	MonsterType.KOBOLD:     ["mountain", "desert"],
	MonsterType.SKELETON:   ["swamp", "desert", "snow"],
	MonsterType.WOLF:       ["forest", "mountain", "snow"],
	# Tier 2
	MonsterType.ORC:        ["mountain", "plains", "forest"],
	MonsterType.HOBGOBLIN:  ["plains", "forest"],
	MonsterType.GNOLL:      ["desert", "plains"],
	MonsterType.ZOMBIE:     ["swamp", "plains"],
	MonsterType.GIANT_SPIDER: ["forest", "swamp"],
	MonsterType.WIGHT:      ["swamp", "snow"],
	MonsterType.SIREN:      ["swamp"],
	MonsterType.KELPIE:     ["swamp"],
	# MIMIC: any — dungeon-leaning, no biome preference
	# Tier 3
	MonsterType.OGRE:       ["mountain", "forest"],
	MonsterType.TROLL:      ["swamp", "forest", "mountain"],
	MonsterType.WRAITH:     ["swamp", "snow"],
	MonsterType.WYVERN:     ["mountain", "desert"],
	MonsterType.MINOTAUR:   ["mountain"],
	MonsterType.GARGOYLE:   ["mountain", "desert"],
	MonsterType.HARPY:      ["mountain", "desert"],
	MonsterType.SHRIEKER:   ["swamp", "forest"],
	# Tier 4
	MonsterType.GIANT:      ["mountain", "snow"],
	MonsterType.DRAGON_WYRMLING: ["mountain", "forest"],
	# DEMON: any
	MonsterType.VAMPIRE:    ["swamp", "snow"],
	MonsterType.GRYPHON:    ["mountain"],
	MonsterType.CHIMAERA:   ["desert", "mountain"],
	# SUCCUBUS: any
	# Tier 5
	# ANCIENT_DRAGON / DEMON_LORD / LICH / CERBERUS: any (legendary, no preference)
	MonsterType.TITAN:      ["mountain"],
	MonsterType.BALROG:     ["mountain"],
	MonsterType.JABBERWOCK: ["forest"],
	# Tier 6
	MonsterType.IRON_GOLEM: ["mountain", "desert"],
	MonsterType.SPHINX:     ["desert"],
	MonsterType.HYDRA:      ["swamp"],
	MonsterType.PHOENIX:    ["desert", "mountain"],
	# ELEMENTAL / NAZGUL: any
	# Tier 7+: legendary, no biome preference — leave unentered
}

const BIOME_AFFINITY_BONUS = 3  # weight multiplier when biome matches

func set_balance_config(cfg: Dictionary):
	"""Set balance configuration from server"""
	balance_config = cfg
	print("Monster Database: Balance config loaded")

func calculate_lethality(monster: Dictionary) -> int:
	"""Calculate monster lethality score based on stats and abilities.
	Lethality represents how dangerous a monster is relative to its level."""
	var cfg = balance_config.get("lethality", {})

	# Base lethality from stats
	var hp_weight = cfg.get("hp_weight", 1.0)
	var str_weight = cfg.get("str_weight", 3.0)
	var def_weight = cfg.get("def_weight", 1.0)
	var speed_weight = cfg.get("speed_weight", 2.0)

	var base = monster.get("max_hp", 10) * hp_weight
	base += monster.get("strength", 5) * str_weight
	base += monster.get("defense", 5) * def_weight
	base += monster.get("speed", 10) * speed_weight

	# Apply ability modifiers
	var ability_mods = cfg.get("ability_modifiers", {})
	var mult = 1.0
	for ability in monster.get("abilities", []):
		mult += ability_mods.get(ability, 0.0)

	return max(1, int(base * mult))

# Monster types by difficulty tier
enum MonsterType {
	# Tier 1 (Level 1-5)
	GOBLIN,
	GIANT_RAT,
	KOBOLD,
	SKELETON,
	WOLF,

	# Tier 2 (Level 6-15)
	ORC,
	HOBGOBLIN,
	GNOLL,
	ZOMBIE,
	GIANT_SPIDER,
	WIGHT,
	SIREN,
	KELPIE,
	MIMIC,

	# Tier 3 (Level 16-30)
	OGRE,
	TROLL,
	WRAITH,
	WYVERN,
	MINOTAUR,
	GARGOYLE,
	HARPY,
	SHRIEKER,

	# Tier 4 (Level 31-50)
	GIANT,
	DRAGON_WYRMLING,
	DEMON,
	VAMPIRE,
	GRYPHON,
	CHIMAERA,
	SUCCUBUS,

	# Tier 5 (Level 51-100)
	ANCIENT_DRAGON,
	DEMON_LORD,
	LICH,
	TITAN,
	BALROG,
	CERBERUS,
	JABBERWOCK,

	# Tier 6 (Level 101-500)
	ELEMENTAL,
	IRON_GOLEM,
	SPHINX,
	HYDRA,
	PHOENIX,
	NAZGUL,

	# Tier 7 (Level 501-2000)
	VOID_WALKER,
	WORLD_SERPENT,
	ELDER_LICH,
	PRIMORDIAL_DRAGON,

	# Tier 8 (Level 2001-5000)
	COSMIC_HORROR,
	TIME_WEAVER,
	DEATH_INCARNATE,

	# Tier 9 (Level 5001-10000)
	AVATAR_OF_CHAOS,
	THE_NAMELESS_ONE,
	GOD_SLAYER,
	ENTROPY
}

func _ready():
	print("Monster Database initialized")

func generate_monster(min_level: int, max_level: int, biome: String = "") -> Dictionary:
	"""Generate a random monster appropriate for the level range.
	Slice 6b — optional biome biases the selection toward monsters whose
	BIOME_AFFINITY list contains the biome (3× weight). Empty biome string
	keeps the legacy uniform selection so callers that don't care about
	biome (forced monsters, hunting, dungeon spawns) stay unchanged."""
	var target_level = randi_range(min_level, max_level)

	# Select monster type based on level (with optional biome bias)
	var monster_type = select_monster_type(target_level, biome)

	# Get base stats for this monster type
	var base_stats = get_monster_base_stats(monster_type)

	# Scale to target level
	var monster = scale_monster_to_level(base_stats, target_level)

	return monster

func generate_monster_by_name(monster_name: String, target_level: int, suppress_rare_rolls: bool = false, force_role: String = "") -> Dictionary:
	"""Generate a specific monster type by name at the given level.
	suppress_rare_rolls=true skips the variant/empowered/cosmetic rolls so a FLOCK member
	generates as a plain base — the caller then stamps the killed monster's inherited
	variant/empowered onto it (reapply_variant / reapply_empowered), no re-roll, no compounding.

	force_role ("empowered" / "elite") makes the corresponding roll land instead of leaving it
	to chance. Elite is a 1%% roll and empowered 25%%, so testing either by hand meant spawning
	dozens of monsters and hoping — which is why the elite and boss danger targets went
	unverified in play while every other change was being checked. Admin/testing only."""
	# Find the monster type by name
	for type_id in MonsterType.values():
		var base_stats = get_monster_base_stats(type_id)
		if base_stats.name == monster_name:
			var m = scale_monster_to_level(base_stats, target_level, suppress_rare_rolls, force_role)
			_apply_out_of_tier_bonus(m, type_id, target_level)
			return m

	# Fallback if name not found - generate random monster
	return generate_monster(target_level, target_level)

func _monster_base_tier(type_id) -> int:
	"""The tier a monster TYPE belongs to (its natural home), 1-9."""
	for t in range(1, 10):
		if type_id in _get_tier_monsters(t):
			return t
	return 1

func _apply_out_of_tier_bonus(monster: Dictionary, type_id, target_level: int) -> void:
	"""#55 (2026-08-27) — when a HIGH-TIER monster type is generated at a level whose tier
	is LOWER than its home tier (i.e. summoned into a lower-level area, e.g. by a Shrieker),
	it keeps its might: boost stats by the tier gap (DEADLY even at the local level) and its
	XP by MORE than the gap (RICHLY rewarding — the payoff for a dangerous summon). Normal,
	tier-appropriate spawns have gap<=0 and are untouched."""
	var base_tier: int = _monster_base_tier(type_id)
	var level_tier: int = int(_get_tier_info(target_level).tier)
	var gap: int = base_tier - level_tier
	if gap <= 0:
		return
	var stat_mult: float = 1.0 + float(gap) * 0.6   # deadly (≈ +60% power per tier over)
	var xp_mult: float = 1.0 + float(gap) * 0.9     # rewarding — grows FASTER than the danger
	monster["max_hp"] = int(monster.get("max_hp", 1) * stat_mult)
	monster["current_hp"] = monster["max_hp"]
	monster["strength"] = int(monster.get("strength", 1) * stat_mult)
	if monster.has("defense"):
		monster["defense"] = int(monster.get("defense", 0) * stat_mult)
	monster["experience_reward"] = int(monster.get("experience_reward", 1) * xp_mult)
	monster["out_of_tier_gap"] = gap  # flag: an out-of-place, tier-boosted foe (display/loot)

func get_all_monster_names() -> Array:
	"""Get a list of all monster names for selection UI"""
	var names = []
	for type_id in MonsterType.values():
		var base_stats = get_monster_base_stats(type_id)
		if base_stats.has("name"):
			names.append(base_stats.name)
	names.sort()  # Alphabetical order for easier navigation
	return names

func select_monster_type(level: int, biome: String = "") -> MonsterType:
	"""Select an appropriate monster type for the level, with tier blending.
	Lower tier monsters become rarer but never completely disappear.
	Slice 6b — optional biome multiplies the per-monster weight by
	BIOME_AFFINITY_BONUS (3×) when the monster's affinity list contains the
	biome. Biome NEVER overrides the tier-based base pool — it only re-weights
	inside the level-appropriate options, so a Tundra player still can't
	encounter a Tier-3 monster while at Tier-1 levels."""
	# Get tier bleed settings from config
	var spawn_cfg = balance_config.get("monster_spawning", {})
	var base_bleed_chance = spawn_cfg.get("tier_bleed_chance", 7)
	var scale_to_area = spawn_cfg.get("tier_bleed_scale_to_area", true)

	# Determine current tier and progress within tier
	var tier_info = _get_tier_info(level)
	var current_tier = tier_info.tier
	var tier_progress = tier_info.progress  # 0.0 to 1.0

	# Calculate higher tier bleed chance (chance to encounter next tier up)
	var bleed_chance = base_bleed_chance
	if scale_to_area:
		bleed_chance = int(base_bleed_chance * (0.5 + tier_progress))

	# Check for higher tier bleed
	var target_tier = current_tier
	if current_tier < 9 and randi() % 100 < bleed_chance:
		target_tier = current_tier + 1

	# Build weighted pool from target tier and all lower tiers
	# Weights: target tier = 100, each tier below gets progressively rarer
	# Formula: weight = 100 / (3 ^ tiers_below) - so tier-1=33%, tier-2=11%, tier-3=4%, tier-4=1%
	var weighted_pool: Array[Dictionary] = []
	var total_weight = 0

	for tier in range(1, target_tier + 1):
		var tiers_below = target_tier - tier
		var weight: int
		if tiers_below == 0:
			weight = 100  # Current/target tier
		else:
			# Exponential decay: 30, 10, 3, 1 for tiers below
			weight = max(1, int(100.0 / pow(3.0, tiers_below)))

		var tier_monsters = _get_tier_monsters(tier)
		for monster in tier_monsters:
			var w = weight
			# Slice 6b — biome bias. Lookup monster's affinity list; if the
			# encounter biome is in it, multiply weight. Monsters with no
			# entry (or empty list) keep their base weight regardless of
			# biome — they fit anywhere.
			if biome != "" and BIOME_AFFINITY.has(monster):
				var affinity = BIOME_AFFINITY[monster]
				if affinity is Array and biome in affinity:
					w = int(w * BIOME_AFFINITY_BONUS)
			weighted_pool.append({"monster": monster, "weight": w})
			total_weight += w

	# Select from weighted pool
	var roll = randi() % total_weight
	var cumulative = 0
	for entry in weighted_pool:
		cumulative += entry.weight
		if roll < cumulative:
			return entry.monster

	# Fallback (shouldn't happen)
	var fallback = _get_tier_monsters(current_tier)
	return fallback[randi() % fallback.size()]

func _get_tier_info(level: int) -> Dictionary:
	"""Get the tier number and progress through that tier (0.0 to 1.0)"""
	if level <= 5:
		return {"tier": 1, "progress": float(level) / 5.0}
	elif level <= 15:
		return {"tier": 2, "progress": float(level - 5) / 10.0}
	elif level <= 30:
		return {"tier": 3, "progress": float(level - 15) / 15.0}
	elif level <= 50:
		return {"tier": 4, "progress": float(level - 30) / 20.0}
	elif level <= 100:
		return {"tier": 5, "progress": float(level - 50) / 50.0}
	elif level <= 500:
		return {"tier": 6, "progress": float(level - 100) / 400.0}
	elif level <= 2000:
		return {"tier": 7, "progress": float(level - 500) / 1500.0}
	elif level <= 5000:
		return {"tier": 8, "progress": float(level - 2000) / 3000.0}
	else:
		return {"tier": 9, "progress": 1.0}

func get_random_monster_name_from_tier(tier: int) -> String:
	"""Get a random monster name from a specific tier (public function for summoning)"""
	var tier_monsters = _get_tier_monsters(tier)
	if tier_monsters.is_empty():
		return "Goblin"  # Fallback
	var monster_type = tier_monsters[randi() % tier_monsters.size()]
	var base_stats = get_monster_base_stats(monster_type)
	return base_stats.get("name", "Goblin")

func _get_tier_monsters(tier: int) -> Array:
	"""Get list of monster types for a specific tier"""
	match tier:
		1:
			return [
				MonsterType.GOBLIN,
				MonsterType.GIANT_RAT,
				MonsterType.KOBOLD,
				MonsterType.SKELETON,
				MonsterType.WOLF
			]
		2:
			return [
				MonsterType.ORC,
				MonsterType.HOBGOBLIN,
				MonsterType.GNOLL,
				MonsterType.ZOMBIE,
				MonsterType.GIANT_SPIDER,
				MonsterType.WIGHT,
				MonsterType.SIREN,
				MonsterType.KELPIE,
				MonsterType.MIMIC
			]
		3:
			return [
				MonsterType.OGRE,
				MonsterType.TROLL,
				MonsterType.WRAITH,
				MonsterType.WYVERN,
				MonsterType.MINOTAUR,
				MonsterType.GARGOYLE,
				MonsterType.HARPY,
				MonsterType.SHRIEKER
			]
		4:
			return [
				MonsterType.GIANT,
				MonsterType.DRAGON_WYRMLING,
				MonsterType.DEMON,
				MonsterType.VAMPIRE,
				MonsterType.GRYPHON,
				MonsterType.CHIMAERA,
				MonsterType.SUCCUBUS
			]
		5:
			return [
				MonsterType.ANCIENT_DRAGON,
				MonsterType.DEMON_LORD,
				MonsterType.LICH,
				MonsterType.TITAN,
				MonsterType.BALROG,
				MonsterType.CERBERUS,
				MonsterType.JABBERWOCK
			]
		6:
			return [
				MonsterType.ELEMENTAL,
				MonsterType.IRON_GOLEM,
				MonsterType.SPHINX,
				MonsterType.HYDRA,
				MonsterType.PHOENIX,
				MonsterType.NAZGUL
			]
		7:
			return [
				MonsterType.VOID_WALKER,
				MonsterType.WORLD_SERPENT,
				MonsterType.ELDER_LICH,
				MonsterType.PRIMORDIAL_DRAGON
			]
		8:
			return [
				MonsterType.COSMIC_HORROR,
				MonsterType.TIME_WEAVER,
				MonsterType.DEATH_INCARNATE
			]
		_:  # Tier 9 or higher
			return [
				MonsterType.AVATAR_OF_CHAOS,
				MonsterType.THE_NAMELESS_ONE,
				MonsterType.GOD_SLAYER,
				MonsterType.ENTROPY
			]

func get_monster_base_stats(type: MonsterType) -> Dictionary:
	"""Get base statistics for a monster type"""
	match type:
		# Tier 1
		MonsterType.GOBLIN:
			return {
				"name": "Goblin",
				"base_level": 2,
				"base_hp": 15,
				"base_strength": 8,
				"base_defense": 5,
				"base_speed": 22,
				"base_experience": 25,
				"base_gold": 5,
				"flock_chance": 35,
				"drop_table_id": "tier1",
				"drop_chance": 5,
				"description": "A small, green-skinned creature with sharp teeth",
				"class_affinity": ClassAffinity.CUNNING,  # Weak to Tricksters
				"abilities": [ABILITY_PACK_LEADER, ABILITY_CUNNING_PREY],
				"death_message": "The goblin squeaks 'Not the face!' as it falls."
			}
		MonsterType.GIANT_RAT:
			return {
				"name": "Giant Rat",
				"base_level": 1,
				"base_hp": 8,
				"base_strength": 6,
				"base_defense": 3,
				"base_speed": 18,
				"base_experience": 15,
				"base_gold": 2,
				"flock_chance": 40,
				"drop_table_id": "tier1",
				"drop_chance": 3,
				"description": "A rat the size of a large dog",
				"class_affinity": ClassAffinity.NEUTRAL,
				"abilities": [ABILITY_EASY_PREY],
				"death_message": ""
			}
		MonsterType.KOBOLD:
			return {
				"name": "Kobold",
				"base_level": 3,
				"base_hp": 12,
				"base_strength": 7,
				"base_defense": 6,
				"base_speed": 15,
				"base_experience": 30,
				"base_gold": 8,
				"flock_chance": 30,
				"drop_table_id": "tier1",
				"drop_chance": 5,
				"description": "A small reptilian humanoid with crude weapons",
				"class_affinity": ClassAffinity.PHYSICAL,  # Weak to Warriors
				"abilities": [ABILITY_GOLD_HOARDER],
				"death_message": "The kobold squeaks its last, clutching an empty pouch."
			}
		MonsterType.SKELETON:
			return {
				"name": "Skeleton",
				"base_level": 4,
				"base_hp": 18,
				"base_strength": 10,
				"base_defense": 8,
				"base_speed": 8,
				"base_experience": 40,
				"base_gold": 3,
				"flock_chance": 25,
				"drop_table_id": "tier1",
				"drop_chance": 5,
				"description": "Animated bones held together by dark magic",
				"class_affinity": ClassAffinity.MAGICAL,  # Weak to Mages
				"abilities": [],
				"death_message": "The skeleton collapses into a pile of bones."
			}
		MonsterType.WOLF:
			return {
				"name": "Wolf",
				"base_level": 3,
				"base_hp": 20,
				"base_strength": 12,
				"base_defense": 6,
				"base_speed": 30,
				"base_experience": 35,
				"base_gold": 0,
				"flock_chance": 45,
				"drop_table_id": "tier1",
				"drop_chance": 5,
				"description": "A fierce predator with sharp fangs",
				"class_affinity": ClassAffinity.NEUTRAL,
				"abilities": [ABILITY_PACK_LEADER, ABILITY_AMBUSHER, ABILITY_BLEED],
				"death_message": ""
			}
		
		# Tier 2
		MonsterType.ORC:
			return {
				"name": "Orc",
				"base_level": 8,
				"base_hp": 45,
				"base_strength": 16,
				"base_defense": 12,
				"base_speed": 14,
				"base_experience": 120,
				"base_gold": 25,
				"flock_chance": 30,
				"drop_table_id": "tier2",
				"drop_chance": 8,
				"description": "A brutish humanoid warrior",
				"class_affinity": ClassAffinity.PHYSICAL,  # Weak to Warriors
				"abilities": [ABILITY_BERSERKER],
				"death_message": "The orc grunts 'Me... not... weak...' and collapses."
			}
		MonsterType.HOBGOBLIN:
			return {
				"name": "Hobgoblin",
				"base_level": 10,
				"base_hp": 50,
				"base_strength": 18,
				"base_defense": 14,
				"base_speed": 18,
				"base_experience": 150,
				"base_gold": 35,
				"flock_chance": 35,
				"drop_table_id": "tier2",
				"drop_chance": 8,
				"description": "A large, disciplined goblinoid soldier",
				"class_affinity": ClassAffinity.CUNNING,  # Weak to Tricksters
				"abilities": [ABILITY_SUMMONER, ABILITY_CUNNING_PREY],
				"death_message": "The hobgoblin salutes as it falls, maintaining military bearing."
			}
		MonsterType.GNOLL:
			return {
				"name": "Gnoll",
				"base_level": 9,
				"base_hp": 42,
				"base_strength": 17,
				"base_defense": 11,
				"base_speed": 24,
				"base_experience": 130,
				"base_gold": 20,
				"flock_chance": 40,
				"drop_table_id": "tier2",
				"drop_chance": 8,
				"description": "A hyena-like humanoid scavenger",
				"class_affinity": ClassAffinity.NEUTRAL,
				"abilities": [ABILITY_PACK_LEADER],
				"death_message": "The gnoll lets out a final, mocking laugh."
			}
		MonsterType.ZOMBIE:
			return {
				"name": "Zombie",
				"base_level": 6,
				"base_hp": 35,
				"base_strength": 14,
				"base_defense": 9,
				"base_speed": 5,
				"base_experience": 80,
				"base_gold": 0,
				"flock_chance": 50,
				"drop_table_id": "tier2",
				"drop_chance": 5,
				"description": "A shambling corpse animated by necromancy",
				"class_affinity": ClassAffinity.MAGICAL,  # Weak to Mages
				"abilities": [ABILITY_EASY_PREY],
				"death_message": "The zombie finally finds peace... probably."
			}
		MonsterType.GIANT_SPIDER:
			return {
				"name": "Giant Spider",
				"base_level": 7,
				"base_hp": 30,
				"base_strength": 13,
				"base_defense": 10,
				"base_speed": 32,
				"base_experience": 100,
				"base_gold": 15,
				"flock_chance": 25,
				"drop_table_id": "tier2",
				"drop_chance": 8,
				"description": "A spider large enough to prey on humans",
				"class_affinity": ClassAffinity.NEUTRAL,
				"abilities": [ABILITY_POISON, ABILITY_AMBUSHER, ABILITY_CUNNING_PREY],
				"death_message": "The spider curls up its legs in defeat."
			}
		MonsterType.WIGHT:
			return {
				"name": "Wight",
				"base_level": 12,
				"base_hp": 55,
				"base_strength": 19,
				"base_defense": 15,
				"base_speed": 12,
				"base_experience": 200,
				"base_gold": 40,
				"flock_chance": 15,
				"drop_table_id": "tier2",
				"drop_chance": 10,
				"description": "An undead warrior with life-draining abilities",
				"class_affinity": ClassAffinity.MAGICAL,  # Weak to Mages
				"abilities": [ABILITY_LIFE_STEAL, ABILITY_CURSE, ABILITY_BLIND],
				"death_message": "The wight's eyes fade as the dark magic releases it."
			}
		MonsterType.SIREN:
			return {
				"name": "Siren",
				"base_level": 10,
				"base_hp": 40,
				"base_strength": 12,
				"base_defense": 8,
				"base_speed": 20,
				"base_experience": 180,
				"base_gold": 35,
				"flock_chance": 10,
				"drop_table_id": "tier2",
				"drop_chance": 12,
				"description": "A beautiful sea creature with an entrancing voice",
				"class_affinity": ClassAffinity.MAGICAL,  # Weak to Mages
				"abilities": [ABILITY_CHARM, ABILITY_MANA_DRAIN],
				"death_message": "The siren's song fades to silence as she sinks beneath the waves."
			}
		MonsterType.KELPIE:
			return {
				"name": "Kelpie",
				"base_level": 11,
				"base_hp": 50,
				"base_strength": 16,
				"base_defense": 12,
				"base_speed": 25,
				"base_experience": 190,
				"base_gold": 30,
				"flock_chance": 5,
				"drop_table_id": "tier2",
				"drop_chance": 10,
				"description": "A shape-shifting water horse that drowns its prey",
				"class_affinity": ClassAffinity.MAGICAL,  # Weak to Mages
				"abilities": [ABILITY_BLEED, ABILITY_SLOW_AURA],
				"death_message": "The kelpie dissolves into water and seeps into the ground."
			}
		MonsterType.MIMIC:
			return {
				"name": "Mimic",
				"base_level": 13,
				"base_hp": 60,
				"base_strength": 20,
				"base_defense": 20,
				"base_speed": 35,
				"base_experience": 250,
				"base_gold": 100,
				"flock_chance": 0,
				"drop_table_id": "tier2",
				"drop_chance": 25,
				"description": "A creature disguised as a treasure chest",
				"class_affinity": ClassAffinity.CUNNING,  # Weak to Tricksters
				"abilities": [ABILITY_AMBUSHER, ABILITY_DISGUISE, ABILITY_GOLD_HOARDER],
				"death_message": "The mimic's chest lid slams shut one final time, its lure finally silent."
			}

		# Tier 3
		MonsterType.OGRE:
			return {
				"name": "Ogre",
				"base_level": 18,
				"base_hp": 100,
				"base_strength": 25,
				"base_defense": 18,
				"base_speed": 10,
				"base_experience": 400,
				"base_gold": 80,
				"flock_chance": 10,
				"drop_table_id": "tier3",
				"drop_chance": 10,
				"description": "A huge, dim-witted giant",
				"class_affinity": ClassAffinity.CUNNING,  # Weak to Tricksters
				"abilities": [ABILITY_GLASS_CANNON],
				"death_message": "The ogre falls with ground-shaking force. You find its lunch pouch... ew."
			}
		MonsterType.TROLL:
			return {
				"name": "Troll",
				"base_level": 20,
				"base_hp": 90,
				"base_strength": 24,
				"base_defense": 16,
				"base_speed": 14,
				"base_experience": 500,
				"base_gold": 60,
				"flock_chance": 15,
				"drop_table_id": "tier3",
				"drop_chance": 12,
				"description": "A regenerating monster with terrible claws that rend equipment",
				"class_affinity": ClassAffinity.NEUTRAL,
				"abilities": [ABILITY_REGENERATION, ABILITY_SUNDER],
				"death_message": "The troll stops regenerating. Finally."
			}
		MonsterType.WRAITH:
			return {
				"name": "Wraith",
				"base_level": 22,
				"base_hp": 75,
				"base_strength": 20,
				"base_defense": 20,
				"base_speed": 28,
				"base_experience": 600,
				"base_gold": 100,
				"flock_chance": 20,
				"drop_table_id": "tier3",
				"drop_chance": 12,
				"description": "A ghostly spirit that feeds on life force",
				"class_affinity": ClassAffinity.PHYSICAL,  # Weak to Warriors
				"abilities": [ABILITY_ETHEREAL, ABILITY_LIFE_STEAL, ABILITY_MANA_DRAIN, ABILITY_ARCANE_HOARDER],
				"death_message": "The wraith dissipates with an ethereal wail."
			}
		MonsterType.WYVERN:
			return {
				"name": "Wyvern",
				"base_level": 25,
				"base_hp": 120,
				"base_strength": 28,
				"base_defense": 22,
				"base_speed": 36,
				"base_experience": 800,
				"base_gold": 150,
				"flock_chance": 5,
				"drop_table_id": "tier3",
				"drop_chance": 15,
				"description": "A two-legged dragon with a venomous tail",
				"class_affinity": ClassAffinity.NEUTRAL,
				"abilities": [ABILITY_POISON, ABILITY_AMBUSHER],
				"death_message": "The wyvern crashes to the ground, its wings folding."
			}
		MonsterType.MINOTAUR:
			return {
				"name": "Minotaur",
				"base_level": 23,
				"base_hp": 110,
				"base_strength": 27,
				"base_defense": 19,
				"base_speed": 16,
				"base_experience": 700,
				"base_gold": 120,
				"flock_chance": 10,
				"drop_table_id": "tier3",
				"drop_chance": 12,
				"description": "A bull-headed humanoid warrior",
				"class_affinity": ClassAffinity.PHYSICAL,  # Weak to Warriors
				"abilities": [ABILITY_BERSERKER, ABILITY_ENRAGE, ABILITY_WARRIOR_HOARDER],
				"death_message": "The minotaur's labyrinthine rage finally ends."
			}
		MonsterType.GARGOYLE:
			return {
				"name": "Gargoyle",
				"base_level": 22,
				"base_hp": 95,
				"base_strength": 22,
				"base_defense": 35,
				"base_speed": 20,
				"base_experience": 650,
				"base_gold": 80,
				"flock_chance": 15,
				"drop_table_id": "tier3",
				"drop_chance": 10,
				"description": "An animated stone guardian with demonic features",
				"class_affinity": ClassAffinity.MAGICAL,  # Weak to Mages
				"abilities": [ABILITY_ARMORED, ABILITY_THORNS],
				"death_message": "The gargoyle crumbles back into lifeless stone."
			}
		MonsterType.HARPY:
			return {
				"name": "Harpy",
				"base_level": 19,
				"base_hp": 65,
				"base_strength": 18,
				"base_defense": 12,
				"base_speed": 30,
				"base_experience": 550,
				"base_gold": 70,
				"flock_chance": 30,
				"drop_table_id": "tier3",
				"drop_chance": 10,
				"description": "A winged creature with a woman's face and vulture's body",
				"class_affinity": ClassAffinity.PHYSICAL,  # Weak to Warriors
				"abilities": [ABILITY_ETHEREAL, ABILITY_BLIND, ABILITY_SUMMONER],
				"death_message": "The harpy's shriek echoes as she plummets from the sky."
			}
		MonsterType.SHRIEKER:
			return {
				"name": "Shrieker",
				"base_level": 17,
				"base_hp": 40,
				"base_strength": 5,
				"base_defense": 5,
				"base_speed": 5,
				"base_experience": 300,
				"base_gold": 20,
				"flock_chance": 0,
				"drop_table_id": "tier3",
				"drop_chance": 5,
				"description": "A fungal creature that screams when disturbed",
				"class_affinity": ClassAffinity.NEUTRAL,
				"abilities": [ABILITY_SUMMONER, ABILITY_COWARD],
				"death_message": "The shrieker's final wail summons... nothing. It dies alone."
			}

		# Tier 4
		MonsterType.GIANT:
			return {
				"name": "Giant",
				"base_level": 35,
				"base_hp": 200,
				"base_strength": 35,
				"base_defense": 25,
				"base_speed": 10,
				"base_experience": 1500,
				"base_gold": 300,
				"flock_chance": 5,
				"drop_table_id": "tier4",
				"drop_chance": 15,
				"description": "A towering humanoid of immense power",
				"class_affinity": ClassAffinity.CUNNING,  # Weak to Tricksters
				"abilities": [ABILITY_GLASS_CANNON, ABILITY_GOLD_HOARDER],
				"death_message": "The giant falls like a mighty oak, shaking the ground as it lands."
			}
		MonsterType.DRAGON_WYRMLING:
			return {
				"name": "Young Dragon",
				"base_level": 40,
				"base_hp": 180,
				"base_strength": 38,
				"base_defense": 30,
				"base_speed": 28,
				"base_experience": 2000,
				"base_gold": 500,
				"flock_chance": 0,
				"drop_table_id": "tier4",
				"drop_chance": 20,
				"description": "A young but deadly dragon",
				"class_affinity": ClassAffinity.NEUTRAL,
				"abilities": [ABILITY_GEM_BEARER, ABILITY_MULTI_STRIKE],
				"death_message": "The young dragon collapses, its pride wounded beyond repair."
			}
		MonsterType.DEMON:
			return {
				"name": "Demon",
				"base_level": 38,
				"base_hp": 170,
				"base_strength": 36,
				"base_defense": 28,
				"base_speed": 24,
				"base_experience": 1800,
				"base_gold": 400,
				"flock_chance": 15,
				"drop_table_id": "tier4",
				"drop_chance": 15,
				"description": "A fiend from the lower planes with hellfire that melts equipment",
				"class_affinity": ClassAffinity.MAGICAL,  # Weak to Mages
				"abilities": [ABILITY_SUMMONER, ABILITY_CURSE, ABILITY_DEATH_CURSE, ABILITY_CORROSIVE, ABILITY_WEAKNESS],
				"death_message": "The demon curses your bloodline as it's banished."
			}
		MonsterType.VAMPIRE:
			return {
				"name": "Vampire",
				"base_level": 42,
				"base_hp": 160,
				"base_strength": 34,
				"base_defense": 32,
				"base_speed": 38,
				"base_experience": 2200,
				"base_gold": 600,
				"flock_chance": 0,
				"drop_table_id": "tier4",
				"drop_chance": 18,
				"description": "An undead noble with supernatural powers",
				"class_affinity": ClassAffinity.PHYSICAL,  # Weak to Warriors
				"abilities": [ABILITY_LIFE_STEAL, ABILITY_ETHEREAL, ABILITY_DISARM, ABILITY_AMBUSHER],
				"death_message": "The vampire crumbles to dust. 'I'll... be... back...' he whispers."
			}
		MonsterType.GRYPHON:
			return {
				"name": "Gryphon",
				"base_level": 38,
				"base_hp": 150,
				"base_strength": 32,
				"base_defense": 28,
				"base_speed": 32,
				"base_experience": 1800,
				"base_gold": 400,
				"flock_chance": 5,
				"drop_table_id": "tier4",
				"drop_chance": 15,
				"description": "A majestic creature with eagle head and lion body",
				"class_affinity": ClassAffinity.PHYSICAL,  # Weak to Warriors
				"abilities": [ABILITY_MULTI_STRIKE, ABILITY_BERSERKER],
				"death_message": "The noble gryphon lets out a final screech before falling silent."
			}
		MonsterType.CHIMAERA:
			return {
				"name": "Chimaera",
				"base_level": 44,
				"base_hp": 175,
				"base_strength": 36,
				"base_defense": 26,
				"base_speed": 30,
				"base_experience": 2400,
				"base_gold": 550,
				"flock_chance": 0,
				"drop_table_id": "tier4",
				"drop_chance": 15,
				"description": "A three-headed beast: lion, goat, and serpent",
				"class_affinity": ClassAffinity.NEUTRAL,
				"abilities": [ABILITY_MULTI_STRIKE, ABILITY_POISON, ABILITY_UNPREDICTABLE],
				"death_message": "All three heads of the chimaera fall at once."
			}
		MonsterType.SUCCUBUS:
			return {
				"name": "Succubus",
				"base_level": 40,
				"base_hp": 130,
				"base_strength": 28,
				"base_defense": 22,
				"base_speed": 26,
				"base_experience": 2000,
				"base_gold": 450,
				"flock_chance": 0,
				"drop_table_id": "tier4",
				"drop_chance": 15,
				"description": "A seductive demon that drains life force",
				"class_affinity": ClassAffinity.MAGICAL,  # Weak to Mages
				"abilities": [ABILITY_CHARM, ABILITY_LIFE_STEAL, ABILITY_MANA_DRAIN],
				"death_message": "The succubus fades away with a haunting smile."
			}

		# Tier 5
		MonsterType.ANCIENT_DRAGON:
			return {
				"name": "Ancient Dragon",
				"base_level": 70,
				"base_hp": 500,
				"base_strength": 60,
				"base_defense": 50,
				"base_speed": 30,
				"base_experience": 10000,
				"base_gold": 5000,
				"flock_chance": 0,
				"drop_table_id": "tier5",
				"drop_chance": 20,
				"description": "A legendary wyrm whose breath dissolves armor",
				"class_affinity": ClassAffinity.NEUTRAL,
				"abilities": [ABILITY_MULTI_STRIKE, ABILITY_ARMORED, ABILITY_GEM_BEARER, ABILITY_CORROSIVE],
				"death_message": "The ancient dragon's eyes dim as centuries of wisdom fade."
			}
		MonsterType.DEMON_LORD:
			return {
				"name": "Demon Lord",
				"base_level": 75,
				"base_hp": 450,
				"base_strength": 65,
				"base_defense": 55,
				"base_speed": 22,
				"base_experience": 12000,
				"base_gold": 6000,
				"flock_chance": 0,
				"drop_table_id": "tier5",
				"drop_chance": 22,
				"description": "A ruler of the infernal realms",
				"class_affinity": ClassAffinity.MAGICAL,  # Weak to Mages
				"abilities": [ABILITY_SUMMONER, ABILITY_CURSE, ABILITY_DEATH_CURSE, ABILITY_GEM_BEARER],
				"death_message": "'This changes nothing! My armies will-' The portal closes."
			}
		MonsterType.LICH:
			return {
				"name": "Lich",
				"base_level": 80,
				"base_hp": 400,
				"base_strength": 50,
				"base_defense": 60,
				"base_speed": 16,
				"base_experience": 15000,
				"base_gold": 8000,
				"flock_chance": 0,
				"drop_table_id": "tier5",
				"drop_chance": 22,
				"description": "An undead sorcerer of terrible power",
				"class_affinity": ClassAffinity.PHYSICAL,  # Weak to Warriors
				"abilities": [ABILITY_MANA_DRAIN, ABILITY_CURSE, ABILITY_SUMMONER, ABILITY_REGENERATION, ABILITY_ARCANE_HOARDER],
				"death_message": "The lich's phylactery shatters. 'Impossible...' it whispers."
			}
		MonsterType.TITAN:
			return {
				"name": "Titan",
				"base_level": 85,
				"base_hp": 600,
				"base_strength": 70,
				"base_defense": 58,
				"base_speed": 18,
				"base_experience": 18000,
				"base_gold": 10000,
				"flock_chance": 0,
				"drop_table_id": "tier5",
				"drop_chance": 25,
				"description": "A godlike being from the dawn of time",
				"class_affinity": ClassAffinity.CUNNING,  # Weak to Tricksters
				"abilities": [ABILITY_WISH_GRANTER, ABILITY_GLASS_CANNON, ABILITY_GEM_BEARER],
				"death_message": "The titan grants you a final gift as it returns to the cosmos."
			}
		MonsterType.BALROG:
			return {
				"name": "Balrog",
				"base_level": 75,
				"base_hp": 480,
				"base_strength": 72,
				"base_defense": 48,
				"base_speed": 24,
				"base_experience": 14000,
				"base_gold": 7000,
				"flock_chance": 0,
				"drop_table_id": "tier5",
				"drop_chance": 20,
				"description": "A demon of shadow and flame from the deepest pits",
				"class_affinity": ClassAffinity.MAGICAL,  # Weak to Mages
				"abilities": [ABILITY_BERSERKER, ABILITY_DEATH_CURSE, ABILITY_ENRAGE],
				"death_message": "The Balrog's flames extinguish as it plummets into darkness."
			}
		MonsterType.CERBERUS:
			return {
				"name": "Cerberus",
				"base_level": 78,
				"base_hp": 520,
				"base_strength": 68,
				"base_defense": 52,
				"base_speed": 26,
				"base_experience": 15000,
				"base_gold": 7500,
				"flock_chance": 0,
				"drop_table_id": "tier5",
				"drop_chance": 20,
				"description": "The three-headed guardian of the underworld",
				"class_affinity": ClassAffinity.PHYSICAL,  # Weak to Warriors
				"abilities": [ABILITY_MULTI_STRIKE, ABILITY_POISON, ABILITY_BLEED],
				"death_message": "All three heads of Cerberus howl in unison before falling silent."
			}
		MonsterType.JABBERWOCK:
			return {
				"name": "Jabberwock",
				"base_level": 82,
				"base_hp": 550,
				"base_strength": 75,
				"base_defense": 45,
				"base_speed": 38,
				"base_experience": 16000,
				"base_gold": 8500,
				"flock_chance": 0,
				"drop_table_id": "tier5",
				"drop_chance": 22,
				"description": "A fearsome creature with jaws that bite and claws that catch",
				"class_affinity": ClassAffinity.CUNNING,  # Weak to Tricksters
				"abilities": [ABILITY_UNPREDICTABLE, ABILITY_MULTI_STRIKE, ABILITY_FLEE_ATTACK, ABILITY_AMBUSHER],
				"death_message": "The Jabberwock goes galumphing back whence it came... permanently."
			}

		# Tier 6 (Level 101-500)
		MonsterType.ELEMENTAL:
			return {
				"name": "Elemental",
				"base_level": 150,
				"base_hp": 800,
				"base_strength": 90,
				"base_defense": 70,
				"base_speed": 28,
				"base_experience": 25000,
				"base_gold": 15000,
				"flock_chance": 10,
				"drop_table_id": "tier6",
				"drop_chance": 8,
				"description": "A being of pure elemental energy",
				"class_affinity": ClassAffinity.MAGICAL,  # Weak to Mages
				"abilities": [ABILITY_UNPREDICTABLE, ABILITY_DAMAGE_REFLECT, ABILITY_SLOW_AURA, ABILITY_ARCANE_HOARDER],
				"death_message": "The elemental disperses into raw mana."
			}
		MonsterType.IRON_GOLEM:
			return {
				"name": "Iron Golem",
				"base_level": 200,
				"base_hp": 1200,
				"base_strength": 100,
				"base_defense": 120,
				"base_speed": 6,
				"base_experience": 35000,
				"base_gold": 20000,
				"flock_chance": 0,
				"drop_table_id": "tier6",
				"drop_chance": 10,
				"description": "An animated construct of living metal with crushing fists",
				"class_affinity": ClassAffinity.PHYSICAL,  # Weak to Warriors
				"abilities": [ABILITY_ARMORED, ABILITY_THORNS, ABILITY_WARRIOR_HOARDER, ABILITY_SUNDER],
				"death_message": "The golem's core shatters. It salutes you... wait, that's new."
			}
		MonsterType.SPHINX:
			return {
				"name": "Sphinx",
				"base_level": 250,
				"base_hp": 900,
				"base_strength": 85,
				"base_defense": 90,
				"base_speed": 18,
				"base_experience": 40000,
				"base_gold": 25000,
				"flock_chance": 0,
				"drop_table_id": "tier6",
				"drop_chance": 12,
				"description": "An ancient guardian of forbidden knowledge",
				"class_affinity": ClassAffinity.CUNNING,  # Weak to Tricksters
				"abilities": [ABILITY_WISH_GRANTER, ABILITY_GEM_BEARER, ABILITY_ARCANE_HOARDER],
				"death_message": "'Your riddle... was superior...' the sphinx admits gracefully."
			}
		MonsterType.HYDRA:
			return {
				"name": "Hydra",
				"base_level": 350,
				"base_hp": 1500,
				"base_strength": 110,
				"base_defense": 80,
				"base_speed": 20,
				"base_experience": 60000,
				"base_gold": 35000,
				"flock_chance": 0,
				"drop_table_id": "tier6",
				"drop_chance": 15,
				"description": "A many-headed serpent with acidic venom",
				"class_affinity": ClassAffinity.NEUTRAL,
				"abilities": [ABILITY_REGENERATION, ABILITY_MULTI_STRIKE, ABILITY_ENRAGE, ABILITY_CORROSIVE],
				"death_message": "All seven heads finally stop bickering. Permanently."
			}
		MonsterType.PHOENIX:
			return {
				"name": "Phoenix",
				"base_level": 400,
				"base_hp": 1000,
				"base_strength": 120,
				"base_defense": 75,
				"base_speed": 42,
				"base_experience": 80000,
				"base_gold": 50000,
				"flock_chance": 0,
				"drop_table_id": "tier6",
				"drop_chance": 18,
				"description": "An immortal bird of fire and rebirth",
				"class_affinity": ClassAffinity.MAGICAL,  # Weak to Mages
				"abilities": [ABILITY_DEATH_CURSE, ABILITY_GEM_BEARER, ABILITY_WISH_GRANTER],
				"death_message": "The phoenix erupts in flame... but this time, it doesn't rise."
			}
		MonsterType.NAZGUL:
			return {
				"name": "Nazgul",
				"base_level": 300,
				"base_hp": 1100,
				"base_strength": 115,
				"base_defense": 95,
				"base_speed": 40,
				"base_experience": 70000,
				"base_gold": 40000,
				"flock_chance": 5,
				"drop_table_id": "tier6",
				"drop_chance": 15,
				"description": "A wraith king bound to a ring of power",
				"class_affinity": ClassAffinity.PHYSICAL,  # Weak to Warriors
				"abilities": [ABILITY_ETHEREAL, ABILITY_CURSE, ABILITY_SLOW_AURA, ABILITY_XP_STEAL, ABILITY_WEAKNESS, ABILITY_LIFE_STEAL, ABILITY_DISARM, ABILITY_AMBUSHER],
				"death_message": "The Nazgul screams as its ring shatters, freeing what remains of its soul."
			}

		# Tier 7 (Level 501-2000)
		MonsterType.VOID_WALKER:
			return {
				"name": "Void Walker",
				"base_level": 700,
				"base_hp": 2000,
				"base_strength": 150,
				"base_defense": 130,
				"base_speed": 44,
				"base_experience": 150000,
				"base_gold": 80000,
				"flock_chance": 5,
				"drop_table_id": "tier7",
				"drop_chance": 10,
				"description": "A creature from between dimensions",
				"class_affinity": ClassAffinity.NEUTRAL,
				"abilities": [ABILITY_ETHEREAL, ABILITY_UNPREDICTABLE, ABILITY_MANA_DRAIN, ABILITY_ENERGY_DRAIN, ABILITY_CUNNING_PREY, ABILITY_AMBUSHER],
				"death_message": "Reality snaps back as the Void Walker is erased from existence."
			}
		MonsterType.WORLD_SERPENT:
			return {
				"name": "World Serpent",
				"base_level": 1000,
				"base_hp": 3500,
				"base_strength": 180,
				"base_defense": 150,
				"base_speed": 32,
				"base_experience": 300000,
				"base_gold": 150000,
				"flock_chance": 0,
				"drop_table_id": "tier7",
				"drop_chance": 15,
				"description": "A serpent large enough to encircle the world",
				"class_affinity": ClassAffinity.PHYSICAL,  # Weak to Warriors
				"abilities": [ABILITY_POISON, ABILITY_MULTI_STRIKE, ABILITY_ARMORED, ABILITY_GEM_BEARER],
				"death_message": "The World Serpent releases its tail. The cosmos trembles."
			}
		MonsterType.ELDER_LICH:
			return {
				"name": "Elder Lich",
				"base_level": 1200,
				"base_hp": 2500,
				"base_strength": 160,
				"base_defense": 180,
				"base_speed": 18,
				"base_experience": 400000,
				"base_gold": 200000,
				"flock_chance": 0,
				"drop_table_id": "tier7",
				"drop_chance": 18,
				"description": "An undead sorcerer of unfathomable age",
				"class_affinity": ClassAffinity.PHYSICAL,  # Weak to Warriors
				"abilities": [ABILITY_MANA_DRAIN, ABILITY_SUMMONER, ABILITY_CURSE, ABILITY_DEATH_CURSE, ABILITY_GEM_BEARER, ABILITY_ARCANE_HOARDER, ABILITY_WEAKNESS],
				"death_message": "'I have seen the end times... you are not it.' *crumbles*"
			}
		MonsterType.PRIMORDIAL_DRAGON:
			return {
				"name": "Primordial Dragon",
				"base_level": 1500,
				"base_hp": 5000,
				"base_strength": 220,
				"base_defense": 200,
				"base_speed": 34,
				"base_experience": 600000,
				"base_gold": 300000,
				"flock_chance": 0,
				"drop_table_id": "tier7",
				"drop_chance": 20,
				"description": "A dragon from before recorded history",
				"class_affinity": ClassAffinity.NEUTRAL,
				"abilities": [ABILITY_MULTI_STRIKE, ABILITY_BERSERKER, ABILITY_ARMORED, ABILITY_GEM_BEARER, ABILITY_WISH_GRANTER],
				"death_message": "The Primordial Dragon's final breath shapes new constellations."
			}

		# Tier 8 (Level 2001-5000)
		MonsterType.COSMIC_HORROR:
			return {
				"name": "Cosmic Horror",
				"base_level": 2500,
				"base_hp": 8000,
				"base_strength": 300,
				"base_defense": 250,
				"base_speed": 30,
				"base_experience": 1000000,
				"base_gold": 500000,
				"flock_chance": 0,
				"drop_table_id": "tier8",
				"drop_chance": 12,
				"description": "An incomprehensible entity from beyond the stars",
				"class_affinity": ClassAffinity.CUNNING,  # Weak to Tricksters
				"abilities": [ABILITY_UNPREDICTABLE, ABILITY_CURSE, ABILITY_MANA_DRAIN, ABILITY_STAMINA_DRAIN, ABILITY_ENERGY_DRAIN, ABILITY_GEM_BEARER],
				"death_message": "The Cosmic Horror's form unravels. Your sanity... mostly intact."
			}
		MonsterType.TIME_WEAVER:
			return {
				"name": "Time Weaver",
				"base_level": 3500,
				"base_hp": 6000,
				"base_strength": 280,
				"base_defense": 300,
				"base_speed": 38,
				"base_experience": 1500000,
				"base_gold": 750000,
				"flock_chance": 0,
				"drop_table_id": "tier8",
				"drop_chance": 15,
				"description": "A being that exists across all timelines",
				"class_affinity": ClassAffinity.MAGICAL,  # Weak to Mages
				"abilities": [ABILITY_ETHEREAL, ABILITY_REGENERATION, ABILITY_MULTI_STRIKE, ABILITY_GEM_BEARER, ABILITY_WISH_GRANTER, ABILITY_ARCANE_HOARDER],
				"death_message": "'We will meet again... in another timeline...' Time resumes."
			}
		MonsterType.DEATH_INCARNATE:
			return {
				"name": "Death Incarnate",
				"base_level": 4500,
				"base_hp": 10000,
				"base_strength": 350,
				"base_defense": 280,
				"base_speed": 36,
				"base_experience": 2000000,
				"base_gold": 1000000,
				"flock_chance": 0,
				"drop_table_id": "tier8",
				"drop_chance": 18,
				"description": "The physical manifestation of death itself",
				"class_affinity": ClassAffinity.PHYSICAL,  # Weak to Warriors
				"abilities": [ABILITY_GLASS_CANNON, ABILITY_LIFE_STEAL, ABILITY_DEATH_CURSE, ABILITY_GEM_BEARER, ABILITY_WARRIOR_HOARDER],
				"death_message": "'Impossible... I AM death...' Life, it seems, finds a way."
			}

		# Tier 9 (Level 5001-10000)
		MonsterType.AVATAR_OF_CHAOS:
			return {
				"name": "Avatar of Chaos",
				"base_level": 6000,
				"base_hp": 15000,
				"base_strength": 450,
				"base_defense": 380,
				"base_speed": 36,
				"base_experience": 5000000,
				"base_gold": 2000000,
				"flock_chance": 0,
				"drop_table_id": "tier9",
				"drop_chance": 15,
				"description": "Pure entropy given form and purpose",
				"class_affinity": ClassAffinity.NEUTRAL,
				"abilities": [ABILITY_UNPREDICTABLE, ABILITY_MULTI_STRIKE, ABILITY_ENRAGE, ABILITY_CURSE, ABILITY_GEM_BEARER],
				"death_message": "Chaos screams as order is restored. The universe sighs in relief."
			}
		MonsterType.THE_NAMELESS_ONE:
			return {
				"name": "The Nameless One",
				"base_level": 7500,
				"base_hp": 20000,
				"base_strength": 500,
				"base_defense": 450,
				"base_speed": 38,
				"base_experience": 8000000,
				"base_gold": 4000000,
				"flock_chance": 0,
				"drop_table_id": "tier9",
				"drop_chance": 18,
				"description": "An entity so ancient its name has been forgotten",
				"class_affinity": ClassAffinity.CUNNING,  # Weak to Tricksters
				"abilities": [ABILITY_ETHEREAL, ABILITY_CURSE, ABILITY_DEATH_CURSE, ABILITY_WISH_GRANTER, ABILITY_GEM_BEARER],
				"death_message": "At last... a name... *You hear your own name whispered eternally*"
			}
		MonsterType.GOD_SLAYER:
			return {
				"name": "God Slayer",
				"base_level": 8500,
				"base_hp": 25000,
				"base_strength": 600,
				"base_defense": 500,
				"base_speed": 40,
				"base_experience": 12000000,
				"base_gold": 6000000,
				"flock_chance": 0,
				"drop_table_id": "tier9",
				"drop_chance": 20,
				"description": "A being that has killed gods and taken their power",
				"class_affinity": ClassAffinity.PHYSICAL,  # Weak to Warriors
				"abilities": [ABILITY_BERSERKER, ABILITY_GLASS_CANNON, ABILITY_LIFE_STEAL, ABILITY_GEM_BEARER, ABILITY_WISH_GRANTER],
				"death_message": "The God Slayer bows. 'Finally... a worthy successor.'"
			}
		MonsterType.ENTROPY:
			return {
				"name": "Entropy",
				"base_level": 9500,
				"base_hp": 30000,
				"base_strength": 700,
				"base_defense": 600,
				"base_speed": 45,
				"base_experience": 20000000,
				"base_gold": 10000000,
				"flock_chance": 0,
				"drop_table_id": "tier9",
				"drop_chance": 25,
				"description": "The end of all things made manifest",
				"class_affinity": ClassAffinity.MAGICAL,  # Weak to Mages
				"abilities": [ABILITY_ARMORED, ABILITY_REGENERATION, ABILITY_DEATH_CURSE, ABILITY_CURSE, ABILITY_GEM_BEARER, ABILITY_WISH_GRANTER],
				"death_message": "You have defeated the end itself. What lies beyond is... new beginnings."
			}

	# Fallback
	return {
		"name": "Unknown",
		"base_level": 1,
		"base_hp": 10,
		"base_strength": 5,
		"base_defense": 5,
		"base_speed": 10,
		"base_experience": 10,
		"base_gold": 1,
		"flock_chance": 0,
		"description": "A mysterious creature"
	}

func scale_monster_to_level(base_stats: Dictionary, target_level: int, suppress_rare_rolls: bool = false, force_role: String = "") -> Dictionary:
	"""Scale monster stats to match target level, accounting for expected player equipment"""
	var level_diff = target_level - base_stats.base_level

	# Tiered scaling to prevent astronomical stats at high levels
	var stat_scale = _calculate_tiered_stat_scale(base_stats.base_level, target_level)

	# Calculate expected player equipment bonuses at this level
	# Uses CONSERVATIVE estimates so exceptional gear feels powerful
	# Assumes ~60% of level with common-uncommon gear (below average)
	var expected_player_attack_bonus = _estimate_player_equipment_attack(target_level)
	var expected_player_defense_bonus = _estimate_player_equipment_defense(target_level)

	# Calculate base scaled stats
	var base_scaled_hp = max(5, int(base_stats.base_hp * stat_scale))
	var base_scaled_strength = max(3, int(base_stats.base_strength * stat_scale))
	var base_scaled_defense = max(1, int(base_stats.base_defense * stat_scale))

	# #6 (2026-09-02) — reference-player model. When enabled, magnitude comes from
	# what a real player at this level can do rather than from base_level scaling.
	# Everything below (abilities, variants, glass_cannon, elite/boss mults, XP) is
	# untouched and still rides on top. Returns {} if the curve file is missing, in
	# which case we fall through to the legacy path rather than break generation.
	var _anchored: Dictionary = compute_anchored_stats(base_stats, target_level) if USE_REFERENCE_MODEL else {}

	# Adjust HP - base 2x multiplier with diminishing returns for player attack
	# Uses hyperbolic saturation: approaches 7.0x asymptotically
	# This ensures multi-round fights without making high-level monsters unkillable
	# v0.9.700 (#29) — base HP raised ~1.4× (2.0+5.0 → 2.8+7.0) so trash lands ~2.5-3
	# turns instead of 1-2. The big length increase for "real fights" rides on the
	# elite/empowered variant mults below, kept tiered so trash stays snappy.
	var hp_multiplier = 2.8 + 7.0 * expected_player_attack_bonus / (150.0 + expected_player_attack_bonus)
	var scaled_hp = max(10, int(base_scaled_hp * hp_multiplier))

	# Minimum HP floor based on level to prevent trivial one-shot kills
	var min_hp = max(10, target_level * 3)
	scaled_hp = max(scaled_hp, min_hp)
	if not _anchored.is_empty():
		scaled_hp = int(_anchored["max_hp"])

	# Adjust strength modestly - armor should reduce damage but not negate it
	# Only account for ~30% of expected defense so good armor feels impactful
	var strength_bonus = int(expected_player_defense_bonus * 0.3)
	var scaled_strength = max(3, base_scaled_strength + strength_bonus)

	# Defense scales normally but with a small boost at higher levels
	var defense_bonus = int(target_level / 10)
	var scaled_defense = max(1, base_scaled_defense + defense_bonus)
	if not _anchored.is_empty():
		scaled_strength = int(_anchored["strength"])
		scaled_defense = int(_anchored["defense"])

	# Calculate XP and gold with tiered formulas (based on final stats)
	var experience_reward = _calculate_experience_reward(scaled_hp, scaled_strength, scaled_defense, target_level)
	# Apex species are tuned above their tier's band, so they pay above it too. Applied before
	# the elite/empowered multipliers below, which then stack on top as normal.
	if is_apex_species(String(base_stats.get("name", ""))):
		experience_reward = int(experience_reward * APEX_XP_MULT)
	# Gold removed — Valor is now earned via market listings only

	# Calculate monster intelligence based on level tier (for Outsmart mechanic)
	var intelligence = _calculate_monster_intelligence(target_level, base_stats.name)

	# Apply glass cannon ability (3x damage but 50% HP)
	var abilities = base_stats.get("abilities", [])
	if ABILITY_GLASS_CANNON in abilities:
		scaled_hp = max(5, int(scaled_hp * 0.5))
		scaled_strength = int(scaled_strength * 3)

	# Apply armored ability (50% more defense)
	if ABILITY_ARMORED in abilities:
		scaled_defense = int(scaled_defense * 1.5)

	# Rare variant system - chance for special monster variants
	var monster_name = base_stats.name
	var monster_abilities = abilities.duplicate() if abilities is Array else []
	var is_rare_variant = false
	var variant_type = ""

	# 4% chance for GOOD rare variant (drops gear)
	if not suppress_rare_rolls and randf() < 0.04 and target_level >= 5:
		# Don't double up on abilities
		if ABILITY_WEAPON_MASTER not in monster_abilities and ABILITY_SHIELD_BEARER not in monster_abilities:
			is_rare_variant = true
			# 50/50 weapon or shield variant
			if randf() < 0.5:
				monster_name = base_stats.name + " Weapon Master"
				monster_abilities.append(ABILITY_WEAPON_MASTER)
				variant_type = "weapon_master"
				# Weapon masters are more aggressive
				scaled_strength = int(scaled_strength * 1.25)
			else:
				monster_name = base_stats.name + " Shield Guardian"
				monster_abilities.append(ABILITY_SHIELD_BEARER)
				variant_type = "shield_guardian"
				# Shield guardians are tankier
				scaled_hp = int(scaled_hp * 1.25)
				scaled_defense = int(scaled_defense * 1.25)

	# 2% chance for DANGEROUS rare variant (damages gear) - separate roll
	# These are scary encounters that give players a reason to upgrade gear
	if not suppress_rare_rolls and not is_rare_variant and randf() < 0.02 and target_level >= 10:
		if ABILITY_CORROSIVE not in monster_abilities and ABILITY_SUNDER not in monster_abilities:
			is_rare_variant = true
			# 50/50 corrosive (acid damage) or sunder (physical destruction)
			if randf() < 0.5:
				monster_name = "Corrosive " + base_stats.name
				monster_abilities.append(ABILITY_CORROSIVE)
				variant_type = "corrosive"
				# Corrosive monsters are slightly tougher
				scaled_hp = int(scaled_hp * 1.15)
			else:
				monster_name = "Sundering " + base_stats.name
				monster_abilities.append(ABILITY_SUNDER)
				variant_type = "sunder"
				# Sundering monsters hit harder
				scaled_strength = int(scaled_strength * 1.15)

	# 1% chance for ELITE variant (powerful, rewarding) - Lv15+ only, separate roll
	var is_elite = false
	if force_role == "elite" or (not suppress_rare_rolls and not is_rare_variant and randf() < 0.01 and target_level >= 15):
		is_elite = true
		is_rare_variant = true
		variant_type = "elite"
		monster_name = "★ " + base_stats.name + " Champion"
		# Elite stat bonuses: significantly harder but very rewarding.
		# v0.9.700 (#29) — HP 1.5→3.5 so a Champion is a "real fight" (~8t at avg gear),
		# not a slightly-chunkier trash mob. Damage untouched (win-rate guardrail).
		# #6 (2026-09-02) — derived from ROLE_TARGETS rather than hand-tuned. Was
		# ×3.5 HP / ×1.3 STR, which on the corrected baseline made Champions
		# unwinnable (0% win at L1) because HP and damage compound into cost.
		var _elite_m := role_multipliers("elite", target_level)
		scaled_hp = int(scaled_hp * float(_elite_m.hp_mult))
		scaled_strength = int(scaled_strength * float(_elite_m.str_mult))
		scaled_defense = int(scaled_defense * maxf(1.0, float(_elite_m.str_mult)))
		experience_reward = int(experience_reward * 1.5)
		# Add 2 random abilities from a curated pool (no duplicates)
		var elite_ability_pool = [
			ABILITY_REGENERATION, ABILITY_ENRAGE, ABILITY_BERSERKER,
			ABILITY_MULTI_STRIKE, ABILITY_POISON, ABILITY_BLEED,
			ABILITY_CURSE, ABILITY_LIFE_STEAL, ABILITY_ARMORED,
		]
		elite_ability_pool.shuffle()
		var added = 0
		for ea in elite_ability_pool:
			if ea not in monster_abilities:
				monster_abilities.append(ea)
				added += 1
				if added >= 2:
					break

	# === EMPOWERED MODIFIER ROLL (v0.9.651 — ARPG arc pillar 1) ===
	# Separate from the legacy variant rolls above (skipped when one already
	# fired, mirroring their mutual-exclusion pattern). 25% of Lv5+ monsters
	# (launched at 15% in v0.9.651; raised v0.9.655 after the Paths talent
	# tree shipped the permadeath counterplay the higher density required —
	# stun negation, reflects, on-kill cleansing in Bulwark/Aegis/Shadow).
	# Modifier count gates by level: always 1; Lv20+ has 25% for 2; Lv40+ has
	# an additional 10% for 3. Server grants +1 combat-loot reveal per modifier
	# (+1 extra for Gilded) and drop_chance scales below.
	var empowered_mods: Array = []
	if force_role == "empowered" or (not suppress_rare_rolls and not is_rare_variant and target_level >= 5 and randf() < 0.25):
		var mod_count = 1
		if target_level >= 40 and randf() < 0.10:
			mod_count = 3
		elif target_level >= 20 and randf() < 0.25:
			mod_count = 2
		var mod_pool = EMPOWERED_MODIFIERS.keys()
		mod_pool.shuffle()
		for mod_id in mod_pool:
			if empowered_mods.size() >= mod_count:
				break
			var mod: Dictionary = EMPOWERED_MODIFIERS[mod_id]
			# Skip when the monster already has this modifier's ability
			# naturally — the prefix would promise nothing new.
			var mod_ability = String(mod.get("ability", ""))
			if mod_ability != "" and mod_ability in monster_abilities:
				continue
			empowered_mods.append(mod_id)
			if mod_ability != "":
				monster_abilities.append(mod_ability)
			scaled_hp = max(10, int(scaled_hp * float(mod.get("hp_mult", 1.0))))
			scaled_strength = max(3, int(scaled_strength * float(mod.get("str_mult", 1.0))))
			scaled_defense = max(1, int(scaled_defense * float(mod.get("def_mult", 1.0))))
			monster_name = String(mod.get("prefix", "")) + " " + monster_name
		# +30% XP per modifier (additive), applied at generation like elite's 1.5x
		if empowered_mods.size() > 0:
			experience_reward = int(experience_reward * (1.0 + 0.30 * empowered_mods.size()))
			# v0.9.700 (#29) — empowered monsters are the overworld's "real fights",
			# but the per-mod hp_mults are tiny (1.10-1.50, and most mods have none),
			# so add a reliable HP bump by mod count: 1 mod ×2.0 … 3 mods ×3.0 (on top
			# of base + any per-mod hp_mult). Makes them ~6-8t at avg gear. Damage untouched.
			# #6 (2026-09-02) — was a flat (1.5 + 0.5*mods) bump tuned against the old,
			# too-weak baseline. Now derived from the empowered role target and scaled by
			# how many modifiers rolled, with strength adjusted so tankiness and damage
			# do not compound into an unwinnable fight.
			var _emp_m := role_multipliers("empowered", target_level)
			var _emp_scale: float = 1.0 + (float(_emp_m.hp_mult) - 1.0) * (float(empowered_mods.size()) / 3.0)
			scaled_hp = max(10, int(scaled_hp * _emp_scale))
			scaled_strength = max(3, int(scaled_strength * (1.0 + (float(_emp_m.str_mult) - 1.0) * (float(empowered_mods.size()) / 3.0))))

	# Empowered drop chance: +20 per modifier, Gilded adds +20 more on top.
	var final_drop_chance: int = 100 if is_elite else int(base_stats.get("drop_chance", 5))
	# Apex species pay in LOOT as well as XP. The owner's framing was "highly rewarding
	# experience and reward wise", and an XP multiplier alone makes a dangerous monster
	# something you kill for a number rather than something you hunt for what it drops.
	if is_apex_species(String(base_stats.get("name", ""))):
		final_drop_chance = mini(100, int(round(float(final_drop_chance) * APEX_DROP_MULT)))
	if empowered_mods.size() > 0:
		final_drop_chance = min(100, final_drop_chance + 20 * empowered_mods.size() + (20 if "gilded" in empowered_mods else 0))

	# Broodcalling: its kin WILL avenge it — guaranteed flock chain on kill.
	var final_flock_chance: int = int(base_stats.get("flock_chance", 0))
	if "broodcalling" in empowered_mods:
		final_flock_chance = 100

	# v0.9.718 (dungeon arc slice 1) — cosmetic tint roll (visual only, no stats).
	# Gated to PLAIN monsters (no rare variant, no empowered mod) so a tinted monster
	# reads as its own thing and doesn't fight the variant/empowered border identity.
	var appearance_color := ""
	var appearance_color2 := ""
	var appearance_pattern := "solid"
	if force_cosmetic or (not suppress_rare_rolls and not is_rare_variant and empowered_mods.is_empty() and randf() < COSMETIC_CHANCE):
		# Roll from the companion cosmetic pool → any color + any pattern a companion
		# can get (rarer = fancier patterns). Same weighting the eggs use.
		var tint: Dictionary = DropTables.roll_cosmetic_variant()
		appearance_color = String(tint.get("color", ""))
		appearance_color2 = String(tint.get("color2", ""))
		appearance_pattern = String(tint.get("pattern", "solid"))

	var monster = {
		"name": monster_name,
		"base_name": base_stats.name,  # Original name without variant prefix/suffix (for art lookup)
		"appearance_color": appearance_color,   # v0.9.718 — cosmetic tint (visual)
		"appearance_color2": appearance_color2,
		"appearance_pattern": appearance_pattern,
		"base_level": base_stats.base_level,  # Intrinsic monster base level — needed for accurate HP estimation in client-side discovery system
		"level": target_level,
		"max_hp": scaled_hp,
		"current_hp": scaled_hp,
		"strength": scaled_strength,
		"defense": scaled_defense,
		"speed": base_stats.base_speed,  # Speed doesn't scale
		"intelligence": intelligence,    # For Outsmart mechanic
		"experience_reward": experience_reward,
		"flock_chance": final_flock_chance,
		"drop_table_id": base_stats.get("drop_table_id", "common"),
		"drop_chance": final_drop_chance,  # Elite = guaranteed; empowered scales +20/mod
		"description": base_stats.description,
		# New fields for ability system
		"class_affinity": base_stats.get("class_affinity", ClassAffinity.NEUTRAL),
		"abilities": monster_abilities,
		"death_message": base_stats.get("death_message", ""),
		"is_rare_variant": is_rare_variant,
		"is_elite": is_elite,
		# Flagged on the monster so the client can mark an apex species in the UI — a player
		# cannot learn to be careful of something the game never tells them is dangerous.
		"is_apex_species": is_apex_species(String(base_stats.get("name", ""))),
		"variant_type": variant_type,  # "" / "weapon_master" / "shield_guardian" / "corrosive" / "sunder" / "elite" — drives client-side border tint on monster ASCII art
		# Empowered (v0.9.651) — stacking modifier ids ("frenzied", "gilded", ...).
		# name_color drives the D2-style rarity tint on name + ASCII border;
		# empty string = fall through to affinity color (get_combat_display).
		"is_empowered": empowered_mods.size() > 0,
		"empowered_mods": empowered_mods,
		"name_color": EMPOWERED_NAME_COLORS.get(empowered_mods.size(), "") if empowered_mods.size() > 0 else "",
		"lethality": 0  # Placeholder, calculated below
	}

	# Calculate and store lethality score
	monster.lethality = calculate_lethality(monster)

	return monster

func reapply_variant(monster: Dictionary, variant_type: String) -> void:
	"""v0.9.718 — re-stamp a rare variant onto an ALREADY-generated monster so a flock
	inherits the killed monster's variant (server.gd trigger_flock_encounter passed a
	variant_type but this function never existed → the v0.9.711 flock-variant feature
	errored whenever it fired). Rebuilds the name from base_name and applies the
	variant's stat multipliers + ability + flags, mirroring scale_monster_to_level().
	No-op for '' or an already-matching variant. Mutates `monster` in place."""
	if variant_type == "" or String(monster.get("variant_type", "")) == variant_type:
		return
	# v0.9.721 FIX — the freshly-generated flock monster may have rolled EMPOWERED
	# (mutually exclusive with rare variants). Strip that HP inflation BEFORE applying the
	# inherited variant's multiplier, or elite ×3.5 compounds on empowered ×(1.5-3.0) into
	# a 5-10× HP monster that feels un-killable. Clears the empowered flags/name-color too
	# (the name is rebuilt from base_name below, dropping any empowered prefix).
	if monster.get("is_empowered", false):
		var _emp_mods: Array = monster.get("empowered_mods", [])
		var _emp_mult := 1.5 + 0.5 * float(_emp_mods.size())
		if _emp_mult > 1.0:
			monster["max_hp"] = max(10, int(round(float(int(monster.get("max_hp", 10))) / _emp_mult)))
		monster["current_hp"] = int(monster.get("max_hp", 10))
		monster["is_empowered"] = false
		monster["empowered_mods"] = []
		monster["name_color"] = ""
	var base_name := String(monster.get("base_name", monster.get("name", "Monster")))
	var abilities: Array = monster.get("abilities", [])
	var new_name := base_name
	var hp_mult := 1.0
	var str_mult := 1.0
	var def_mult := 1.0
	var xp_mult := 1.0
	var add_abilities: Array = []
	match variant_type:
		"weapon_master":
			new_name = base_name + " Weapon Master"
			str_mult = 1.25
			add_abilities = [ABILITY_WEAPON_MASTER]
		"shield_guardian":
			new_name = base_name + " Shield Guardian"
			hp_mult = 1.25
			def_mult = 1.25
			add_abilities = [ABILITY_SHIELD_BEARER]
		"corrosive":
			new_name = "Corrosive " + base_name
			hp_mult = 1.15
			add_abilities = [ABILITY_CORROSIVE]
		"sunder":
			new_name = "Sundering " + base_name
			str_mult = 1.15
			add_abilities = [ABILITY_SUNDER]
		"elite":
			new_name = "★ " + base_name + " Champion"
			hp_mult = 3.5
			str_mult = 1.3
			def_mult = 1.25
			xp_mult = 1.5
			var elite_pool := [
				ABILITY_REGENERATION, ABILITY_ENRAGE, ABILITY_BERSERKER,
				ABILITY_MULTI_STRIKE, ABILITY_POISON, ABILITY_BLEED,
				ABILITY_CURSE, ABILITY_LIFE_STEAL, ABILITY_ARMORED,
			]
			elite_pool.shuffle()
			var added := 0
			for ea in elite_pool:
				if ea not in abilities:
					add_abilities.append(ea)
					added += 1
					if added >= 2:
						break
		_:
			return  # unknown variant id — leave the monster untouched
	monster["name"] = new_name
	for ea in add_abilities:
		if ea not in abilities:
			abilities.append(ea)
	monster["abilities"] = abilities
	var new_hp: int = max(10, int(int(monster.get("max_hp", 10)) * hp_mult))
	monster["max_hp"] = new_hp
	monster["current_hp"] = new_hp
	monster["strength"] = max(3, int(int(monster.get("strength", 3)) * str_mult))
	monster["defense"] = max(1, int(int(monster.get("defense", 1)) * def_mult))
	monster["experience_reward"] = int(int(monster.get("experience_reward", 0)) * xp_mult)
	monster["variant_type"] = variant_type
	monster["is_rare_variant"] = true
	monster["is_elite"] = (variant_type == "elite")
	if variant_type == "elite":
		monster["drop_chance"] = 100
	monster["lethality"] = calculate_lethality(monster)

func reapply_empowered(monster: Dictionary, mods: Array) -> void:
	"""v0.9.723 — stamp a specific set of Empowered modifiers onto an already-generated
	monster so a FLOCK inherits the killed monster's empowered mods instead of re-rolling
	them each member (a gilded harpy's flock was coming out gilded → juggernaut → normal).
	Meant for a monster generated with suppress_rare_rolls=true (a plain base), so mods apply
	cleanly with no compounding. Mirrors the empowered block in scale_monster_to_level.
	Mutates in place; no-op for empty/unknown mods."""
	if mods.is_empty():
		return
	var base_name := String(monster.get("base_name", monster.get("name", "Monster")))
	var abilities: Array = monster.get("abilities", [])
	var new_name := base_name
	var hp := int(monster.get("max_hp", 10))
	var strv := int(monster.get("strength", 3))
	var defv := int(monster.get("defense", 1))
	var final_mods: Array = []
	for mod_id in mods:
		var mod: Dictionary = EMPOWERED_MODIFIERS.get(mod_id, {})
		if mod.is_empty():
			continue
		final_mods.append(mod_id)
		var mod_ability := String(mod.get("ability", ""))
		if mod_ability != "" and mod_ability not in abilities:
			abilities.append(mod_ability)
		hp = max(10, int(hp * float(mod.get("hp_mult", 1.0))))
		strv = max(3, int(strv * float(mod.get("str_mult", 1.0))))
		defv = max(1, int(defv * float(mod.get("def_mult", 1.0))))
		new_name = String(mod.get("prefix", "")) + " " + new_name
	if final_mods.is_empty():
		return
	# #6 (2026-09-02) — must match the empowered block in scale_monster_to_level, which now
	# derives from ROLE_TARGETS rather than the old flat (1.5 + 0.5*count). Two copies of the
	# same formula is how this drifts; kept in lockstep via role_multipliers().
	var _emp_m := role_multipliers("empowered", int(monster.get("level", 0)))
	var _emp_scale: float = 1.0 + (float(_emp_m.hp_mult) - 1.0) * (float(final_mods.size()) / 3.0)
	hp = max(10, int(hp * _emp_scale))
	strv = max(3, int(strv * (1.0 + (float(_emp_m.str_mult) - 1.0) * (float(final_mods.size()) / 3.0))))
	monster["max_hp"] = hp
	monster["current_hp"] = hp
	monster["strength"] = strv
	monster["defense"] = defv
	monster["abilities"] = abilities
	monster["name"] = new_name
	monster["base_name"] = base_name
	monster["is_empowered"] = true
	monster["empowered_mods"] = final_mods
	monster["name_color"] = EMPOWERED_NAME_COLORS.get(final_mods.size(), "")
	monster["experience_reward"] = int(int(monster.get("experience_reward", 1)) * (1.0 + 0.30 * final_mods.size()))
	var dc := int(monster.get("drop_chance", 5))
	monster["drop_chance"] = min(100, dc + 20 * final_mods.size() + (20 if "gilded" in final_mods else 0))
	# NOTE: deliberately do NOT re-force broodcalling's flock_chance=100 here — the ORIGINAL
	# broodcalling monster already triggered this flock; forcing it on every inherited member
	# would make the chain never terminate. Inherited members keep the base flock_chance.
	monster["lethality"] = calculate_lethality(monster)

func _estimate_player_equipment_attack(player_level: int) -> int:
	"""Estimate player attack bonus for monster scaling.
	Conservative estimate: uncommon-rare gear at 95% of level.
	Uses logarithmic diminishing returns matching real equipment scaling."""
	var item_level = int(player_level * 0.95)
	# Apply diminishing returns (character.gd lines 1028-1043)
	# Never let effective_level exceed actual item_level (log formula boosts below ~200)
	var effective_level = float(item_level)
	if item_level > 50:
		var log_level = 50.0 + 15.0 * log(float(item_level - 49)) / log(2.0)
		effective_level = min(float(item_level), log_level)
	# Rarity 1.3 = average of uncommon (1.2) and rare (1.4)
	# Weapon slot multiplier = 1.5 (from character.gd SLOT_BONUSES)
	var rarity_mult = 1.3
	var weapon_slot_mult = 1.5
	var weapon_attack = int(effective_level * rarity_mult * weapon_slot_mult)
	return weapon_attack

func _estimate_player_equipment_defense(player_level: int) -> int:
	"""Estimate player defense bonus for monster scaling.
	Conservative estimate: uncommon-rare gear at 95% of level.
	Uses logarithmic diminishing returns matching real equipment scaling."""
	var item_level = int(player_level * 0.95)
	var effective_level = float(item_level)
	if item_level > 50:
		var log_level = 50.0 + 15.0 * log(float(item_level - 49)) / log(2.0)
		effective_level = min(float(item_level), log_level)
	# Rarity 1.3, armor slot multiplier = 1.0 (from character.gd SLOT_BONUSES)
	var rarity_mult = 1.3
	var armor_slot_mult = 1.0
	var armor_defense = int(effective_level * rarity_mult * armor_slot_mult)
	return armor_defense

func _calculate_tiered_stat_scale(base_level: int, target_level: int) -> float:
	"""Calculate stat scaling using tiered percentages.

	v0.9.481 — added DOWN-scale path for target_level < base_level. The old
	function only scaled UP from base_level and silently returned scale=1.0 when
	the target was below base. That meant a T3 Chimaera (base_level 44) clamped
	to "Lv 1" by the v0.9.480 threat-corridor fix still kept its full base_hp /
	base_str / base_def — a zero-gear Lv 1 player would face a 350-HP, 41-STR
	monster wearing a "Lv 1" name tag, ~0% win rate. The downscale uses a linear
	ratio (target/base) so high-base monsters appearing well below their natural
	level read as runts of their species rather than full-grown apex predators.
	The max(5, base_scaled_*) clamps on the call site keep absolutely-tiny stats
	from breaking math; the HP floor max(10, target_level*3) prevents instakills.
	"""
	if target_level < base_level:
		# Down-scale: monster is spawning below its natural base level.
		# Linear ratio with no floor — call-site min clamps (max(5/3/1) on base
		# stats + max(10, level*3) HP floor) handle the very-low-stat edge cases.
		# A Lv 1 spawn of a base-44 monster gets scale ~0.023 → stats collapse
		# to the call-site floors, producing a tier-1-equivalent fight while
		# preserving the monster's name/abilities so the threat narrative reads.
		return float(target_level) / float(base_level)
	var scale = 1.0
	var current_level = base_level

	# Tier 1: Levels 1-100 at 12% per level
	if current_level < 100:
		var levels_in_tier = min(target_level, 100) - current_level
		if levels_in_tier > 0:
			scale += levels_in_tier * 0.12
			current_level = min(target_level, 100)

	# Tier 2: Levels 101-500 at 5% per level
	if current_level < 500 and target_level > 100:
		var start = max(current_level, 100)
		var levels_in_tier = min(target_level, 500) - start
		if levels_in_tier > 0:
			scale += levels_in_tier * 0.05
			current_level = min(target_level, 500)

	# Tier 3: Levels 501-2000 at 2% per level
	if current_level < 2000 and target_level > 500:
		var start = max(current_level, 500)
		var levels_in_tier = min(target_level, 2000) - start
		if levels_in_tier > 0:
			scale += levels_in_tier * 0.02
			current_level = min(target_level, 2000)

	# Tier 4: Levels 2000+ at 0.5% per level
	if target_level > 2000:
		var start = max(current_level, 2000)
		var levels_in_tier = target_level - start
		if levels_in_tier > 0:
			scale += levels_in_tier * 0.005

	return max(0.25, scale)

func _calculate_experience_reward(hp: int, strength: int, defense: int, level: int) -> int:
	"""Calculate XP reward - balanced for ~45 kills per level on average.
	   Lethality significantly affects XP: weak monsters give less, tough ones more."""
	var lethality = hp + (strength * 2) + defense

	# Target: ~45 kills per level on average (range 35-60 based on lethality)
	# XP_needed = pow(level+1, 2.2) * 50
	# XP_reward = XP_needed / 45 = pow(level+1, 2.2) * 1.11
	var base_xp = pow(level + 1, 2.2) * 1.11

	# Lethality bonus: weak monsters (0.7x) to tough monsters (1.4x)
	# Expected lethality at level L is roughly 50 + L*10
	var expected_lethality = 50.0 + level * 10.0
	var lethality_ratio = float(lethality) / expected_lethality
	# Multiplier: 0.3 means 30% variance per 100% deviation from expected
	var lethality_bonus = 1.0 + (lethality_ratio - 1.0) * 0.3
	lethality_bonus = clamp(lethality_bonus, 0.7, 1.4)

	return max(5, int(base_xp * lethality_bonus))

func _get_intelligence_modifier(monster_name: String) -> int:
	"""Per-monster intelligence adjustment for thematic accuracy.
	Positive = smarter (harder to outsmart), Negative = dumber (easier to outsmart)."""
	match monster_name:
		# --- DUMBER (brutes, beasts, mindless) ---
		"Giant Rat": return -3
		"Wolf": return -2
		"Skeleton": return -3
		"Zombie": return -5
		"Ogre": return -8
		"Troll": return -6
		"Gargoyle": return -5
		"Giant": return -10
		"Cerberus": return -8
		"Iron Golem": return -12
		"Hydra": return -5
		# --- SMARTER (magical, ancient, cunning) ---
		"Siren": return 8
		"Hobgoblin": return 5
		"Wraith": return 5
		"Succubus": return 5
		"Vampire": return 5
		"Demon": return 3
		"Lich": return 8
		"Sphinx": return 8
		"Nazgul": return 6
		"Elder Lich": return 5
	return 0

func _calculate_monster_intelligence(level: int, monster_name: String = "") -> int:
	"""Calculate monster intelligence based on level tier.
	Used for the Outsmart mechanic - higher intelligence = harder to outsmart.
	Tier 1-2 (1-15): 5-15 - easy to outsmart
	Tier 3-4 (16-50): 15-30 - moderate
	Tier 5-6 (51-500): 30-45 - challenging but outsmart viable for tricksters
	Tier 7-9 (500+): 45-65 - very challenging to outsmart"""

	var base_intelligence: int
	var variance: int

	if level <= 5:
		# Tier 1: Very dumb monsters
		base_intelligence = 5
		variance = 5
	elif level <= 15:
		# Tier 2: Simple-minded
		base_intelligence = 10
		variance = 5
	elif level <= 30:
		# Tier 3: Average intelligence
		base_intelligence = 18
		variance = 7
	elif level <= 50:
		# Tier 4: Cunning
		base_intelligence = 25
		variance = 5
	elif level <= 100:
		# Tier 5: Intelligent
		base_intelligence = 32
		variance = 8
	elif level <= 500:
		# Tier 6: Highly intelligent
		base_intelligence = 38
		variance = 5
	elif level <= 2000:
		# Tier 7: Genius-level
		base_intelligence = 48
		variance = 8
	elif level <= 5000:
		# Tier 8: Near-omniscient
		base_intelligence = 55
		variance = 8
	else:
		# Tier 9: Godlike intelligence
		base_intelligence = 65
		variance = 5

	# Add some randomness to the intelligence within the tier
	var final_intelligence = base_intelligence + (randi() % (variance + 1)) - (variance / 2)
	final_intelligence += _get_intelligence_modifier(monster_name)
	return max(5, final_intelligence)

func to_dict() -> Dictionary:
	return {"initialized": true}

# ===== CLASS AFFINITY HELPERS =====

func get_affinity_color(affinity: int) -> String:
	"""Get the color code for a class affinity"""
	match affinity:
		ClassAffinity.PHYSICAL:
			return "#FFFF00"  # Yellow - weak to Warriors
		ClassAffinity.MAGICAL:
			return "#00BFFF"  # Blue - weak to Mages
		ClassAffinity.CUNNING:
			return "#00FF00"  # Green - weak to Tricksters
		_:
			return "#FFFFFF"  # White - neutral

func get_affinity_name(affinity: int) -> String:
	"""Get the name of a class affinity for display"""
	match affinity:
		ClassAffinity.PHYSICAL:
			return "Physical"
		ClassAffinity.MAGICAL:
			return "Magical"
		ClassAffinity.CUNNING:
			return "Cunning"
		_:
			return "Neutral"

func get_player_class_path(character_class: String) -> String:
	"""Determine the combat path of a character class"""
	match character_class.to_lower():
		"fighter", "barbarian", "paladin":
			return "warrior"
		"wizard", "sorcerer", "sage":
			return "mage"
		"thief", "ranger", "ninja":
			return "trickster"
		_:
			return "warrior"  # Default to warrior

func calculate_class_advantage_multiplier(affinity: int, player_class_path: String) -> float:
	"""Calculate damage multiplier based on class affinity.
	Returns: 1.0 (neutral), 1.5 (advantage), 0.75 (disadvantage)"""
	match affinity:
		ClassAffinity.PHYSICAL:
			# Warriors do +50% damage, Mages do -25%
			if player_class_path == "warrior":
				return 1.5
			elif player_class_path == "mage":
				return 0.75
		ClassAffinity.MAGICAL:
			# Mages do +50% damage, Warriors do -25%
			if player_class_path == "mage":
				return 1.5
			elif player_class_path == "warrior":
				return 0.75
		ClassAffinity.CUNNING:
			# Tricksters do +50% damage, others do -25%
			if player_class_path == "trickster":
				return 1.5
			else:
				return 0.75
	return 1.0  # Neutral

# ============================================================================
# REFERENCE-PLAYER MONSTER MODEL (#6, 2026-09-02)
# ============================================================================
# Monster magnitude is derived from what a real player at that level can
# actually do, instead of from each monster's hand-authored base_level run
# through an asymmetric up/down scale.
#
# WHY (all measured this session, from two independent directions):
#   * PLAYER SIDE — player output grows far faster than player durability. The
#     reference curve shows damage-per-turn / own-max-HP rising from 1.15 at L1
#     to ~51 at L5000, a 44x drift. Any fixed monster table is therefore correct
#     at exactly one level and wrong everywhere else.
#   * MONSTER SIDE — routing level through base_level made difficulty COLLAPSE
#     at every tier boundary, because a tier's level band and its monsters' base
#     levels do not line up (T8 monsters are base 2500-4500 but T8 covers
#     L2500-5000). Median monster HP fell 6.7x from L2000 to L2500 while the
#     player only got stronger. Same-level HP variance reached 85x.
# Re-authoring base levels only moves those teeth. This removes the mechanism.
#
# WHAT IT PRESERVES. Only magnitude is anchored. Species identity — abilities
# (multi_strike, regeneration, armored, ethereal...), variants, glass_cannon,
# elite/boss multipliers, XP — all still ride on top exactly as before. A Void
# Walker still behaves like a Void Walker; it is just sized against the player
# it will actually meet. Species keeps a bounded stat SHAPE (below) so a Hydra
# is still beefier than a Goblin, within a designed range rather than 85x.
#
# HOW DIFFICULTY IS SET. Two explicit knobs, which is the point of the exercise:
#   TARGET_TURNS_NORMAL — how long a plain same-level fight should last
#   DANGER_NORMAL       — the fraction of the player's health bar that fight
#                         should cost them
# and PROGRESSION_DANGER_SLOPE makes the game get HARDER as a player advances,
# by design rather than by accident. That was the stated goal and it was
# previously not expressible anywhere.
const USE_REFERENCE_MODEL := true          # false = legacy base_level scaling
# The CALIBRATED monster curve: target hp/strength for a plain same-level monster at each
# anchor level, produced by driving real fights until they land on the design target
# (see the sim's `-- refcal`). Preferred over deriving from the player curve analytically,
# because the analytic route is self-referential — a player's damage per turn depends on
# how long the fight lasts, which is what the number is being used to set.
# ============================================================================
# ROLE TARGETS (#6, 2026-09-02) — elite/boss sized against the corrected baseline
# ============================================================================
# Before the reference-player model, the plain-monster baseline was too weak, so the
# elite and empowered multipliers had been inflated to compensate (Champion HP was
# raised 1.5 -> 3.5 in v0.9.700 to make a Champion "a real fight"). Stacking those on a
# correctly-sized baseline made elites unwinnable — measured 0% win at L1.
#
# So roles are no longer hand-tuned multipliers. Each role states what its fight should
# FEEL like — how long it lasts and how much of the player's health bar it costs — and
# the multipliers are derived:
#
#   hp_mult  = turns_role / turns_normal
#   str_mult = (danger_role / danger_normal) * (turns_normal / turns_role)
#
# The str_mult term is the one that is easy to get wrong by hand, and it is why the old
# numbers compounded: total damage taken is strength x turns, so making a monster
# TANKIER already makes it more dangerous. A Champion that lasts 1.8x longer at the same
# strength already costs 1.8x the health. Raising its damage on top multiplies rather
# than adds — the old ×3.5 HP with ×1.3 STR was ~4.5x a normal fight's cost, not 1.75x.
const ROLE_TARGETS := {
	"normal":    {"turns": 5.0,  "danger": 0.40},
	"empowered": {"turns": 7.0,  "danger": 0.55},
	"elite":     {"turns": 9.0,  "danger": 0.65},
	"boss":      {"turns": 14.0, "danger": 0.80},
}

# Role multipliers CALIBRATED against real fights, written into the curve file by the sim's
# `-- refcal`. Empty until a calibration has produced them, in which case the derived algebra
# below is used instead.
static var _calibrated_role_mults: Dictionary = {}
# Per-species power corrections from `-- speciescal`, keyed by monster name. 1.0 = untouched.
static var _species_power: Dictionary = {}

# APEX SPECIES (#6c, user direction 2026-09-02) — deliberately harder than their tier peers.
#
# Calibrating every species into one band makes the same level the same fight, which was the
# fix for a 69-point spread but overshoots into blandness. The intent: *"when players get to
# know their limits and climb into the higher tiers they have some monsters they have to be
# very careful of, but are highly rewarding experience and reward wise."*
#
# These are exempt from the normal win-rate band and calibrated to a LOWER one instead, so they
# read as a genuine threat rather than a stat check — and they pay for it, with an XP bonus
# scaled to the extra danger. One or two per tier, chosen as the highest-level and most
# thematically fearsome of their band, so the ladder has a recognisable "careful of that one"
# at every stage rather than only at the top.
const APEX_SPECIES := {
	"Skeleton": true,            # T1
	"Mimic": true,               # T2 — the ambusher
	"Wyvern": true, "Wraith": true,           # T3
	"Chimaera": true,            # T4
	"Titan": true, "Jabberwock": true,        # T5
	"Hydra": true, "Phoenix": true,           # T6
	"Primordial Dragon": true, "World Serpent": true,   # T7
	"Death Incarnate": true, "Cosmic Horror": true,     # T8
	"Entropy": true, "God Slayer": true,      # T9
}
# Win-rate band an apex species is calibrated to, against the normal 0.60 +/- 0.12.
const APEX_TARGET_WIN := 0.38
const APEX_TARGET_BAND := 0.10
# XP multiplier for killing one. Sized against the risk: at ~38% win against ~60% for a normal
# species, an apex kill costs roughly 1.6x the attempts, so 2.0x pays a premium on top of that
# rather than merely compensating.
const APEX_XP_MULT := 2.0
# Drop-chance multiplier for an apex kill. Deliberately larger than the XP multiplier: XP is a
# steady trickle a player gets from everything, so doubling it is a modest nudge, whereas a
# drop is the thing actually worth taking the risk for. A base 5% drop becomes 15%.
const APEX_DROP_MULT := 3.0

static func is_apex_species(monster_name: String) -> bool:
	"""True for species deliberately tuned above their tier's difficulty band."""
	return APEX_SPECIES.has(monster_name)

static func set_species_power(m: Dictionary) -> void:
	_species_power = m if m != null else {}

static func set_calibrated_role_multipliers(m: Dictionary) -> void:
	_calibrated_role_mults = m if m != null else {}

static func _interpolate_role_anchors(anchors: Array, level: int) -> Dictionary:
	"""Log-linear interpolation between calibrated role anchors, matching how the baseline
	curve is read. level <= 0 (callers with no level to hand) takes the middle anchor rather
	than an end, so it is a fair average rather than the easiest or hardest point in the game."""
	if anchors.is_empty():
		return {"hp_mult": 1.0, "str_mult": 1.0}
	if level <= 0:
		var mid: Dictionary = anchors[anchors.size() / 2]
		return {"hp_mult": float(mid.get("hp_mult", 1.0)), "str_mult": float(mid.get("str_mult", 1.0))}
	var lvl: float = maxf(1.0, float(level))
	var first: Dictionary = anchors[0]
	var last: Dictionary = anchors[anchors.size() - 1]
	if lvl <= float(first.get("level", 1)):
		return {"hp_mult": float(first.get("hp_mult", 1.0)), "str_mult": float(first.get("str_mult", 1.0))}
	if lvl >= float(last.get("level", 1)):
		return {"hp_mult": float(last.get("hp_mult", 1.0)), "str_mult": float(last.get("str_mult", 1.0))}
	for i in range(1, anchors.size()):
		var a2: Dictionary = anchors[i - 1]
		var b2: Dictionary = anchors[i]
		var la: float = float(a2.get("level", 1))
		var lb: float = float(b2.get("level", 1))
		if lvl <= lb:
			var t: float = (log(lvl) - log(la)) / maxf(0.000001, (log(lb) - log(la)))
			return {
				"hp_mult": lerp(float(a2.get("hp_mult", 1.0)), float(b2.get("hp_mult", 1.0)), t),
				"str_mult": lerp(float(a2.get("str_mult", 1.0)), float(b2.get("str_mult", 1.0)), t),
			}
	return {"hp_mult": float(last.get("hp_mult", 1.0)), "str_mult": float(last.get("str_mult", 1.0))}

static func role_multipliers(role: String, level: int = 0) -> Dictionary:
	"""HP and strength multipliers for a role, relative to a plain monster.

	MEASURED role multipliers are preferred. The derived form below is only a starting
	estimate: it assumes the fight actually lasts `turns_role`, and it does not, so the damage
	never accumulates to the intended cost. Measured at n=90 with the derived values, elite
	landed at 48% of the player's health bar against a 65% target and boss at 52% against 80%,
	while NORMAL — the only role that is calibrated rather than derived — hit its 40% target
	exactly. The algebra is a decent first guess and a poor final answer, so the sim now
	corrects these against real elite and boss fights the same way it corrects the baseline."""
	if _calibrated_role_mults.has(role):
		var entry = _calibrated_role_mults[role]
		# PER-LEVEL form (an Array of anchors) is preferred. One pair of multipliers for the
		# whole game cannot correct a level-dependent gap, and measurement showed a large one:
		# with a single calibrated pair, boss win rate ran 23-24% at L10-L50 against 47% at
		# L1000, so the same nominal encounter was twice as lethal in the mid game. The
		# baseline curve has always been per-anchor; the roles now are too.
		if entry is Array and not (entry as Array).is_empty():
			return _interpolate_role_anchors(entry, level)
		if entry is Dictionary:
			return {"hp_mult": float(entry.get("hp_mult", 1.0)), "str_mult": float(entry.get("str_mult", 1.0))}
	var base: Dictionary = ROLE_TARGETS.get("normal", {"turns": 5.0, "danger": 0.40})
	var r: Dictionary = ROLE_TARGETS.get(role, base)
	var t_ratio: float = float(r.get("turns", 5.0)) / maxf(0.1, float(base.get("turns", 5.0)))
	var d_ratio: float = float(r.get("danger", 0.40)) / maxf(0.01, float(base.get("danger", 0.40)))
	return {"hp_mult": t_ratio, "str_mult": d_ratio / maxf(0.1, t_ratio)}

const REFERENCE_MONSTER_PATH := "res://shared/reference_monster_curve.json"
const REFERENCE_CURVE_PATH := "res://shared/reference_player_curve.json"
const TARGET_TURNS_NORMAL := 5.0           # a plain same-level fight, in turns
const DANGER_NORMAL := 0.40                # ...costs this share of the player's HP
# Difficulty rises with progression: danger is multiplied by
# (1 + slope * log10(level)). At L1 x1.00, L100 x1.12, L10000 x1.24. Deliberately
# gentle — it compounds with the player also facing higher tiers and variants.
const PROGRESSION_DANGER_SLOPE := 0.06
# Species shape is clamped to this band, so identity survives but same-level
# variance is a DESIGNED ~2x rather than the 85x the old model produced.
const SHAPE_MIN := 0.70
const SHAPE_MAX := 1.45

var _reference_anchors: Array = []
var _curve_is_calibrated: bool = false
var _tier_shape_cache: Dictionary = {}

func _load_reference_curve() -> void:
	if not _reference_anchors.is_empty():
		return
	# Prefer the calibrated monster curve; fall back to the player curve only if absent.
	var mf = FileAccess.open(REFERENCE_MONSTER_PATH, FileAccess.READ)
	if mf != null:
		var mp = JSON.parse_string(mf.get_as_text())
		mf.close()
		if mp is Dictionary and mp.get("anchors", null) is Array and not (mp["anchors"] as Array).is_empty():
			_reference_anchors = mp["anchors"]
			_curve_is_calibrated = true
			# Role multipliers ride in the same file when a calibration has produced them.
			if mp.get("role_multipliers", null) is Dictionary:
				set_calibrated_role_multipliers(mp["role_multipliers"])
			if mp.get("species_power", null) is Dictionary:
				set_species_power(mp["species_power"])
			return
	var f = FileAccess.open(REFERENCE_CURVE_PATH, FileAccess.READ)
	if f != null:
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary and parsed.get("anchors", null) is Array:
			_reference_anchors = parsed["anchors"]
	# Fail LOUDLY. USE_REFERENCE_MODEL is on but no curve loaded means every monster in the
	# game silently reverts to legacy base_level scaling — the sawtooth, the 85x same-level
	# variance and the tier-boundary difficulty collapses all come back, with nothing on
	# screen to say so. A missing or unparseable curve file in an export is exactly the kind
	# of thing that would otherwise be discovered by a player, not by us.
	if _reference_anchors.is_empty() and USE_REFERENCE_MODEL:
		push_error("[monster_database] USE_REFERENCE_MODEL is ON but no reference curve loaded (%s / %s). Falling back to LEGACY base_level scaling — monster difficulty will not match the tuned model." % [REFERENCE_MONSTER_PATH, REFERENCE_CURVE_PATH])
		printerr("[monster_database] reference curve MISSING — monsters are using legacy scaling.")

func _reference_at(level: int) -> Dictionary:
	"""Interpolate the reference curve at `level`. Interpolation is LINEAR IN
	log(level) because the anchors are spaced logarithmically (1..10000) — linear
	interpolation in raw level would badly under-read everything between, say,
	L2500 and L5000. Clamps to the end anchors outside the measured range."""
	_load_reference_curve()
	if _reference_anchors.is_empty():
		return {}
	var lvl: float = maxf(1.0, float(level))
	var first: Dictionary = _reference_anchors[0]
	var last: Dictionary = _reference_anchors[_reference_anchors.size() - 1]
	if lvl <= float(first.get("level", 1)):
		return first
	if lvl >= float(last.get("level", 1)):
		return last
	for i in range(1, _reference_anchors.size()):
		var a: Dictionary = _reference_anchors[i - 1]
		var b: Dictionary = _reference_anchors[i]
		var la: float = float(a.get("level", 1))
		var lb: float = float(b.get("level", 1))
		if lvl <= lb:
			var t: float = (log(lvl) - log(la)) / maxf(0.000001, (log(lb) - log(la)))
			return {
				"level": lvl,
				"dpt": lerp(float(a.get("dpt", 1.0)), float(b.get("dpt", 1.0)), t),
				"ehp": lerp(float(a.get("ehp", 1.0)), float(b.get("ehp", 1.0)), t),
				"taken_ps": lerp(float(a.get("taken_ps", 1.0)), float(b.get("taken_ps", 1.0)), t),
				"hp": lerp(float(a.get("hp", 1.0)), float(b.get("hp", 1.0)), t),
				"str": lerp(float(a.get("str", 1.0)), float(b.get("str", 1.0)), t),
			}
	return last

# === FROZEN ABILITY REFERENCE BAR (#6g, 2026-09-02) ===
# Ability damage used to be a share of reference_monster_hp — the SAME curve refcal rewrites.
# That made monster HP a dead lever: raising it to lengthen a fight raised every ability's
# damage by the identical factor, so fight length never moved and repeated calibration runs
# inflated the curve 2-5x while abilities kept pace and BASIC ATTACKS (which do not scale with
# it) silently fell behind. The ability bar is now a frozen snapshot that refcal never touches,
# so monster HP is an independent lever again.
const ABILITY_BAR_PATH := "res://shared/ability_reference_bar.json"
static var _ability_bar_anchors: Array = []
static var _ability_bar_loaded: bool = false

func ability_reference_hp(level: int) -> float:
	"""The health bar an ABILITY is measured against. Frozen — see ABILITY_BAR_PATH. Falls back
	to the live curve if the snapshot is missing, so an ability never silently reads 0."""
	if not _ability_bar_loaded:
		_ability_bar_loaded = true
		var f = FileAccess.open(ABILITY_BAR_PATH, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary and parsed.get("anchors", null) is Array:
				_ability_bar_anchors = parsed["anchors"]
	var a: Array = _ability_bar_anchors
	if a.is_empty():
		return reference_monster_hp(level)
	var lvl: float = maxf(1.0, float(level))
	if lvl <= float(a[0].get("level", 1)):
		return float(a[0].get("hp", 0.0))
	if lvl >= float(a[a.size() - 1].get("level", 1)):
		return float(a[a.size() - 1].get("hp", 0.0))
	# Log-linear, matching _reference_at: the anchors are spaced logarithmically.
	for i in range(1, a.size()):
		var p: Dictionary = a[i - 1]
		var q: Dictionary = a[i]
		var lp: float = float(p.get("level", 1))
		var lq: float = float(q.get("level", 1))
		if lvl <= lq:
			var t: float = (log(lvl) - log(lp)) / maxf(0.000001, (log(lq) - log(lp)))
			return lerp(float(p.get("hp", 0.0)), float(q.get("hp", 0.0)), t)
	return float(a[a.size() - 1].get("hp", 0.0))

func reference_monster_hp(level: int) -> float:
	"""Calibrated HP of a plain same-level monster — the health bar an ability is measured
	against. Public so combat_manager can size ability damage as a share of it instead of
	each ability inventing its own scaling curve. Returns 0.0 when no curve is loaded, which
	callers treat as "fall back to the legacy formula"."""
	var ref := _reference_at(level)
	if ref.is_empty():
		return 0.0
	return float(ref.get("hp", 0.0))

func _species_shape(base_stats: Dictionary) -> Dictionary:
	"""A species' stat SHAPE relative to the other monsters of its own tier —
	how beefy / hard-hitting / armoured it is *for its kind*. Magnitude comes
	from the reference curve; this is what keeps a Hydra feeling different from
	a Goblin. Derived from the existing hand-authored tables (so no new content
	authoring is needed) but used only as a RATIO, which is why re-tiering or
	re-authoring a monster can no longer move absolute difficulty."""
	var tier: int = _monster_base_tier_by_name(base_stats.get("name", ""))
	if not _tier_shape_cache.has(tier):
		var sums := {"hp": 0.0, "str": 0.0, "def": 0.0}
		var n := 0
		for mt in _get_tier_monsters(tier):
			var bs = get_monster_base_stats(mt)
			sums.hp += float(bs.get("base_hp", 1))
			sums.str += float(bs.get("base_strength", 1))
			sums.def += float(bs.get("base_defense", 1))
			n += 1
		if n > 0:
			_tier_shape_cache[tier] = {
				"hp": sums.hp / float(n), "str": sums.str / float(n), "def": sums.def / float(n)}
		else:
			_tier_shape_cache[tier] = {"hp": 1.0, "str": 1.0, "def": 1.0}
	var mean: Dictionary = _tier_shape_cache[tier]
	return {
		"hp": clampf(float(base_stats.get("base_hp", 1)) / maxf(1.0, float(mean.hp)), SHAPE_MIN, SHAPE_MAX),
		"str": clampf(float(base_stats.get("base_strength", 1)) / maxf(1.0, float(mean.str)), SHAPE_MIN, SHAPE_MAX),
		"def": clampf(float(base_stats.get("base_defense", 1)) / maxf(1.0, float(mean.def)), SHAPE_MIN, SHAPE_MAX),
	}

func _monster_base_tier_by_name(mname: String) -> int:
	for t in range(1, 10):
		for mt in _get_tier_monsters(t):
			if String(get_monster_base_stats(mt).get("name", "")) == mname:
				return t
	return 1

func compute_anchored_stats(base_stats: Dictionary, target_level: int) -> Dictionary:
	"""Monster hp/strength/defense for a PLAIN monster at `target_level`, derived
	from the reference player rather than from base_level. Elite/boss/variant
	multipliers still ride on top downstream — this sets the baseline they scale.

	    hp  = dpt * target_turns                      (fight lasts target_turns)
	    str = ehp * danger / (target_turns * taken_ps) (fight costs `danger` of the bar)

	Returns {} when the curve is unavailable, so callers fall back to the legacy
	path rather than generating a broken monster."""
	var ref := _reference_at(target_level)
	if ref.is_empty():
		return {}
	var shape := _species_shape(base_stats)
	# #6c (2026-09-02) — per-species POWER CORRECTION, calibrated from real fights.
	#
	# The shape above normalises a species' HP/STR/DEF ratios, but monster ABILITIES sit
	# entirely outside the anchor and dominate the outcome. Measured: at the same level in the
	# same gear, win rate ran from 31% (Titan) to 100% (Shrieker) at L50 and 22% (Hydra, 40
	# turns, regeneration outpacing player damage) to 86% at L1000 — a ~69-point spread that
	# made the aggregate difficulty numbers a poor description of any actual fight.
	#
	# Rather than model each ability's impact by hand, the sim measures each species' real win
	# rate and writes back a single multiplier that pulls the outliers toward a band. Variety is
	# preserved deliberately — the target is a BAND, not equality, so a Hydra is still a harder
	# fight than a Harpy, just not a different game.
	var sp_name := String(base_stats.get("name", ""))
	if _species_power.has(sp_name):
		var corr: float = float(_species_power[sp_name])
		shape.hp = float(shape.hp) * corr
		shape.str = float(shape.str) * corr
	# #6 (2026-09-02, found in playtest) — the danger budget is per ENCOUNTER, not per monster.
	# A flock chains more monsters into the same fight with NO healing in between, so a species
	# with a 35% flock chance really presents ~1.5 monsters per encounter and a calibrated 40%
	# cost per monster becomes 60%+ overall — and the tail (two or three chained, plus a rare
	# variant) simply kills. Reported from a live L5 test: beat an Orc Weapon Master, died to
	# the second of its flock.
	# Expected chain length for chance p is 1/(1-p); dividing each monster's DAMAGE by it keeps
	# the whole encounter inside the budget. HP is untouched, so each monster still takes its
	# target number of turns. A species that never flocks is unaffected.
	var flock_p: float = clampf(float(base_stats.get("flock_chance", 0)) / 100.0, 0.0, 0.85)
	var chain_len: float = 1.0 / maxf(0.15, 1.0 - flock_p)
	if _curve_is_calibrated:
		# Calibrated curve already encodes the target fight length and cost, measured from
		# real fights. Only the species SHAPE is applied on top.
		var c_hp: float = float(ref.get("hp", 100.0)) * float(shape.hp)
		var c_str: float = float(ref.get("str", 10.0)) * float(shape.str) / chain_len
		var c_def: float = c_str * 0.45 * float(shape.def) / maxf(0.01, float(shape.str))
		return {
			"max_hp": maxi(10, int(round(c_hp))),
			"strength": maxi(3, int(round(c_str))),
			"defense": maxi(1, int(round(c_def))),
		}
	var danger: float = DANGER_NORMAL * (1.0 + PROGRESSION_DANGER_SLOPE * (log(maxf(1.0, float(target_level))) / log(10.0)))
	var hp: float = float(ref.get("dpt", 1.0)) * TARGET_TURNS_NORMAL * float(shape.hp)
	# Strength needed for the monster to remove `danger` of the player's bar over
	# the whole fight, given how much damage the player actually takes per point
	# of monster strength at this level.
	var taken_ps: float = maxf(0.000001, float(ref.get("taken_ps", 1.0)))
	var strength: float = (float(ref.get("ehp", 1.0)) * danger) / (TARGET_TURNS_NORMAL * taken_ps)
	strength *= float(shape.str)
	strength /= chain_len
	# Defense keeps its historic relationship to the monster's own strength — it
	# is a texture stat here, not a difficulty lever, and the player's damage is
	# already accounted for in dpt (which was measured THROUGH monster defense).
	var defense: float = strength * 0.45 * float(shape.def) / maxf(0.01, float(shape.str))
	return {
		"max_hp": maxi(10, int(round(hp))),
		"strength": maxi(3, int(round(strength))),
		"defense": maxi(1, int(round(defense))),
	}
