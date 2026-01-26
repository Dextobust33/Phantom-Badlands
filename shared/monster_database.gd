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
const ABILITY_GOLD_HOARDER = "gold_hoarder"      # 3x gold drops
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

# Balance configuration (set by server)
var balance_config: Dictionary = {}

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

	# Tier 3 (Level 16-30)
	OGRE,
	TROLL,
	WRAITH,
	WYVERN,
	MINOTAUR,

	# Tier 4 (Level 31-50)
	GIANT,
	DRAGON_WYRMLING,
	DEMON,
	VAMPIRE,

	# Tier 5 (Level 51-100)
	ANCIENT_DRAGON,
	DEMON_LORD,
	LICH,
	TITAN,

	# Tier 6 (Level 101-500)
	ELEMENTAL,
	IRON_GOLEM,
	SPHINX,
	HYDRA,
	PHOENIX,

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

func generate_monster(min_level: int, max_level: int) -> Dictionary:
	"""Generate a random monster appropriate for the level range"""
	var target_level = randi_range(min_level, max_level)

	# Select monster type based on level
	var monster_type = select_monster_type(target_level)

	# Get base stats for this monster type
	var base_stats = get_monster_base_stats(monster_type)

	# Scale to target level
	var monster = scale_monster_to_level(base_stats, target_level)

	return monster

func generate_monster_by_name(monster_name: String, target_level: int) -> Dictionary:
	"""Generate a specific monster type by name at the given level"""
	# Find the monster type by name
	for type_id in MonsterType.values():
		var base_stats = get_monster_base_stats(type_id)
		if base_stats.name == monster_name:
			return scale_monster_to_level(base_stats, target_level)

	# Fallback if name not found - generate random monster
	return generate_monster(target_level, target_level)

func get_all_monster_names() -> Array:
	"""Get a list of all monster names for selection UI"""
	var names = []
	for type_id in MonsterType.values():
		var base_stats = get_monster_base_stats(type_id)
		if base_stats.has("name"):
			names.append(base_stats.name)
	names.sort()  # Alphabetical order for easier navigation
	return names

func select_monster_type(level: int) -> MonsterType:
	"""Select an appropriate monster type for the level, with chance for higher-tier bleed"""
	# Get tier bleed settings from config
	var spawn_cfg = balance_config.get("monster_spawning", {})
	var base_bleed_chance = spawn_cfg.get("tier_bleed_chance", 7)
	var scale_to_area = spawn_cfg.get("tier_bleed_scale_to_area", true)

	# Determine current tier and progress within tier
	var tier_info = _get_tier_info(level)
	var current_tier = tier_info.tier
	var tier_progress = tier_info.progress  # 0.0 to 1.0

	# Calculate actual bleed chance
	var bleed_chance = base_bleed_chance
	if scale_to_area:
		# Scale chance based on how far into the tier we are (higher at end of tier)
		bleed_chance = int(base_bleed_chance * (0.5 + tier_progress))

	# Roll for tier bleed (only if not already at highest tier)
	var use_higher_tier = current_tier < 9 and randi() % 100 < bleed_chance

	var possible_types = _get_tier_monsters(current_tier if not use_higher_tier else current_tier + 1)
	return possible_types[randi() % possible_types.size()]

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
				MonsterType.WIGHT
			]
		3:
			return [
				MonsterType.OGRE,
				MonsterType.TROLL,
				MonsterType.WRAITH,
				MonsterType.WYVERN,
				MonsterType.MINOTAUR
			]
		4:
			return [
				MonsterType.GIANT,
				MonsterType.DRAGON_WYRMLING,
				MonsterType.DEMON,
				MonsterType.VAMPIRE
			]
		5:
			return [
				MonsterType.ANCIENT_DRAGON,
				MonsterType.DEMON_LORD,
				MonsterType.LICH,
				MonsterType.TITAN
			]
		6:
			return [
				MonsterType.ELEMENTAL,
				MonsterType.IRON_GOLEM,
				MonsterType.SPHINX,
				MonsterType.HYDRA,
				MonsterType.PHOENIX
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
				"base_speed": 12,
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
				"base_speed": 14,
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
				"base_speed": 11,
				"base_experience": 30,
				"base_gold": 8,
				"flock_chance": 30,
				"drop_table_id": "tier1",
				"drop_chance": 5,
				"description": "A small reptilian humanoid with crude weapons",
				"class_affinity": ClassAffinity.PHYSICAL,  # Weak to Warriors
				"abilities": [ABILITY_GOLD_HOARDER],
				"death_message": "The kobold drops its treasure pouch as it expires."
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
				"base_speed": 15,
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
				"base_speed": 9,
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
				"base_speed": 10,
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
				"base_speed": 12,
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
				"base_speed": 16,
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
				"base_speed": 8,
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
		
		# Tier 3
		MonsterType.OGRE:
			return {
				"name": "Ogre",
				"base_level": 18,
				"base_hp": 100,
				"base_strength": 25,
				"base_defense": 18,
				"base_speed": 7,
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
				"base_speed": 10,
				"base_experience": 500,
				"base_gold": 60,
				"flock_chance": 15,
				"drop_table_id": "tier3",
				"drop_chance": 12,
				"description": "A regenerating monster with terrible claws",
				"class_affinity": ClassAffinity.NEUTRAL,
				"abilities": [ABILITY_REGENERATION],
				"death_message": "The troll stops regenerating. Finally."
			}
		MonsterType.WRAITH:
			return {
				"name": "Wraith",
				"base_level": 22,
				"base_hp": 75,
				"base_strength": 20,
				"base_defense": 20,
				"base_speed": 12,
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
				"base_speed": 15,
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
				"base_speed": 11,
				"base_experience": 700,
				"base_gold": 120,
				"flock_chance": 10,
				"drop_table_id": "tier3",
				"drop_chance": 12,
				"description": "A bull-headed humanoid warrior",
				"class_affinity": ClassAffinity.PHYSICAL,  # Weak to Warriors
				"abilities": [ABILITY_BERSERKER, ABILITY_ENRAGE],
				"death_message": "The minotaur's labyrinthine rage finally ends."
			}
		
		# Tier 4
		MonsterType.GIANT:
			return {
				"name": "Giant",
				"base_level": 35,
				"base_hp": 200,
				"base_strength": 35,
				"base_defense": 25,
				"base_speed": 8,
				"base_experience": 1500,
				"base_gold": 300,
				"flock_chance": 5,
				"drop_table_id": "tier4",
				"drop_chance": 15,
				"description": "A towering humanoid of immense power",
				"class_affinity": ClassAffinity.CUNNING,  # Weak to Tricksters
				"abilities": [ABILITY_GLASS_CANNON, ABILITY_GOLD_HOARDER],
				"death_message": "The giant falls like a mighty oak, scattering its treasure."
			}
		MonsterType.DRAGON_WYRMLING:
			return {
				"name": "Young Dragon",
				"base_level": 40,
				"base_hp": 180,
				"base_strength": 38,
				"base_defense": 30,
				"base_speed": 14,
				"base_experience": 2000,
				"base_gold": 500,
				"flock_chance": 0,
				"drop_table_id": "tier4",
				"drop_chance": 20,
				"description": "A young but deadly dragon",
				"class_affinity": ClassAffinity.NEUTRAL,
				"abilities": [ABILITY_GEM_BEARER, ABILITY_MULTI_STRIKE],
				"death_message": "The young dragon's hoard is yours... along with its pride."
			}
		MonsterType.DEMON:
			return {
				"name": "Demon",
				"base_level": 38,
				"base_hp": 170,
				"base_strength": 36,
				"base_defense": 28,
				"base_speed": 13,
				"base_experience": 1800,
				"base_gold": 400,
				"flock_chance": 15,
				"drop_table_id": "tier4",
				"drop_chance": 15,
				"description": "A fiend from the lower planes",
				"class_affinity": ClassAffinity.MAGICAL,  # Weak to Mages
				"abilities": [ABILITY_SUMMONER, ABILITY_CURSE, ABILITY_DEATH_CURSE],
				"death_message": "The demon curses your bloodline as it's banished."
			}
		MonsterType.VAMPIRE:
			return {
				"name": "Vampire",
				"base_level": 42,
				"base_hp": 160,
				"base_strength": 34,
				"base_defense": 32,
				"base_speed": 16,
				"base_experience": 2200,
				"base_gold": 600,
				"flock_chance": 0,
				"drop_table_id": "tier4",
				"drop_chance": 18,
				"description": "An undead noble with supernatural powers",
				"class_affinity": ClassAffinity.PHYSICAL,  # Weak to Warriors
				"abilities": [ABILITY_LIFE_STEAL, ABILITY_ETHEREAL, ABILITY_DISARM],
				"death_message": "The vampire crumbles to dust. 'I'll... be... back...' he whispers."
			}
		
		# Tier 5
		MonsterType.ANCIENT_DRAGON:
			return {
				"name": "Ancient Dragon",
				"base_level": 70,
				"base_hp": 500,
				"base_strength": 60,
				"base_defense": 50,
				"base_speed": 18,
				"base_experience": 10000,
				"base_gold": 5000,
				"flock_chance": 0,
				"drop_table_id": "tier5",
				"drop_chance": 20,
				"description": "A legendary wyrm of immense age and power",
				"class_affinity": ClassAffinity.NEUTRAL,
				"abilities": [ABILITY_MULTI_STRIKE, ABILITY_ARMORED, ABILITY_GEM_BEARER],
				"death_message": "The ancient dragon's eyes dim as centuries of wisdom fade."
			}
		MonsterType.DEMON_LORD:
			return {
				"name": "Demon Lord",
				"base_level": 75,
				"base_hp": 450,
				"base_strength": 65,
				"base_defense": 55,
				"base_speed": 17,
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
				"base_speed": 12,
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
				"base_speed": 15,
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

		# Tier 6 (Level 101-500)
		MonsterType.ELEMENTAL:
			return {
				"name": "Elemental",
				"base_level": 150,
				"base_hp": 800,
				"base_strength": 90,
				"base_defense": 70,
				"base_speed": 20,
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
				"base_speed": 8,
				"base_experience": 35000,
				"base_gold": 20000,
				"flock_chance": 0,
				"drop_table_id": "tier6",
				"drop_chance": 10,
				"description": "An animated construct of living metal",
				"class_affinity": ClassAffinity.PHYSICAL,  # Weak to Warriors
				"abilities": [ABILITY_ARMORED, ABILITY_THORNS],
				"death_message": "The golem's core shatters. It salutes you... wait, that's new."
			}
		MonsterType.SPHINX:
			return {
				"name": "Sphinx",
				"base_level": 250,
				"base_hp": 900,
				"base_strength": 85,
				"base_defense": 90,
				"base_speed": 16,
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
				"base_speed": 12,
				"base_experience": 60000,
				"base_gold": 35000,
				"flock_chance": 0,
				"drop_table_id": "tier6",
				"drop_chance": 15,
				"description": "A many-headed serpent that regenerates",
				"class_affinity": ClassAffinity.NEUTRAL,
				"abilities": [ABILITY_REGENERATION, ABILITY_MULTI_STRIKE, ABILITY_ENRAGE],
				"death_message": "All seven heads finally stop bickering. Permanently."
			}
		MonsterType.PHOENIX:
			return {
				"name": "Phoenix",
				"base_level": 400,
				"base_hp": 1000,
				"base_strength": 120,
				"base_defense": 75,
				"base_speed": 25,
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

		# Tier 7 (Level 501-2000)
		MonsterType.VOID_WALKER:
			return {
				"name": "Void Walker",
				"base_level": 700,
				"base_hp": 2000,
				"base_strength": 150,
				"base_defense": 130,
				"base_speed": 22,
				"base_experience": 150000,
				"base_gold": 80000,
				"flock_chance": 5,
				"drop_table_id": "tier7",
				"drop_chance": 10,
				"description": "A creature from between dimensions",
				"class_affinity": ClassAffinity.NEUTRAL,
				"abilities": [ABILITY_ETHEREAL, ABILITY_UNPREDICTABLE, ABILITY_MANA_DRAIN, ABILITY_ENERGY_DRAIN, ABILITY_CUNNING_PREY],
				"death_message": "Reality snaps back as the Void Walker is erased from existence."
			}
		MonsterType.WORLD_SERPENT:
			return {
				"name": "World Serpent",
				"base_level": 1000,
				"base_hp": 3500,
				"base_strength": 180,
				"base_defense": 150,
				"base_speed": 18,
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
				"base_speed": 15,
				"base_experience": 400000,
				"base_gold": 200000,
				"flock_chance": 0,
				"drop_table_id": "tier7",
				"drop_chance": 18,
				"description": "An undead sorcerer of unfathomable age",
				"class_affinity": ClassAffinity.PHYSICAL,  # Weak to Warriors
				"abilities": [ABILITY_MANA_DRAIN, ABILITY_SUMMONER, ABILITY_CURSE, ABILITY_DEATH_CURSE, ABILITY_GEM_BEARER, ABILITY_ARCANE_HOARDER],
				"death_message": "'I have seen the end times... you are not it.' *crumbles*"
			}
		MonsterType.PRIMORDIAL_DRAGON:
			return {
				"name": "Primordial Dragon",
				"base_level": 1500,
				"base_hp": 5000,
				"base_strength": 220,
				"base_defense": 200,
				"base_speed": 20,
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
				"base_speed": 25,
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
				"base_speed": 30,
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
				"base_speed": 28,
				"base_experience": 2000000,
				"base_gold": 1000000,
				"flock_chance": 0,
				"drop_table_id": "tier8",
				"drop_chance": 18,
				"description": "The physical manifestation of death itself",
				"class_affinity": ClassAffinity.PHYSICAL,  # Weak to Warriors
				"abilities": [ABILITY_GLASS_CANNON, ABILITY_LIFE_STEAL, ABILITY_DEATH_CURSE, ABILITY_GEM_BEARER],
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
				"base_speed": 32,
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
				"base_speed": 35,
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
				"base_speed": 38,
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
				"base_speed": 40,
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

func scale_monster_to_level(base_stats: Dictionary, target_level: int) -> Dictionary:
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

	# Adjust HP - base 2x multiplier plus bonus for expected player attack
	# This ensures combat takes multiple rounds even with good gear
	var hp_multiplier = 2.0 + (expected_player_attack_bonus / 30.0)
	var scaled_hp = max(10, int(base_scaled_hp * hp_multiplier))

	# Minimum HP floor based on level to prevent trivial one-shot kills
	var min_hp = max(10, target_level * 3)
	scaled_hp = max(scaled_hp, min_hp)

	# Adjust strength modestly - armor should reduce damage but not negate it
	# Only account for ~30% of expected defense so good armor feels impactful
	var strength_bonus = int(expected_player_defense_bonus * 0.3)
	var scaled_strength = max(3, base_scaled_strength + strength_bonus)

	# Defense scales normally but with a small boost at higher levels
	var defense_bonus = int(target_level / 10)
	var scaled_defense = max(1, base_scaled_defense + defense_bonus)

	# Calculate XP and gold with tiered formulas (based on final stats)
	var experience_reward = _calculate_experience_reward(scaled_hp, scaled_strength, scaled_defense, target_level)
	var gold_reward = _calculate_gold_reward(base_stats, stat_scale, target_level)

	# Calculate monster intelligence based on level tier (for Outsmart mechanic)
	var intelligence = _calculate_monster_intelligence(target_level)

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
	if randf() < 0.04 and target_level >= 5:
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
	if not is_rare_variant and randf() < 0.02 and target_level >= 10:
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

	var monster = {
		"name": monster_name,
		"base_name": base_stats.name,  # Original name without variant prefix/suffix (for art lookup)
		"level": target_level,
		"max_hp": scaled_hp,
		"current_hp": scaled_hp,
		"strength": scaled_strength,
		"defense": scaled_defense,
		"speed": base_stats.base_speed,  # Speed doesn't scale
		"intelligence": intelligence,    # For Outsmart mechanic
		"experience_reward": experience_reward,
		"gold_reward": gold_reward,
		"flock_chance": base_stats.get("flock_chance", 0),
		"drop_table_id": base_stats.get("drop_table_id", "common"),
		"drop_chance": base_stats.get("drop_chance", 5),
		"description": base_stats.description,
		# New fields for ability system
		"class_affinity": base_stats.get("class_affinity", ClassAffinity.NEUTRAL),
		"abilities": monster_abilities,
		"death_message": base_stats.get("death_message", ""),
		"is_rare_variant": is_rare_variant,
		"lethality": 0  # Placeholder, calculated below
	}

	# Calculate and store lethality score
	monster.lethality = calculate_lethality(monster)

	return monster

func _estimate_player_equipment_attack(player_level: int) -> int:
	"""Estimate BASELINE player attack bonus - intentionally conservative.
	This ensures players with good gear feel overpowered, not just 'normal'."""
	# Assume player has weapon at ~50% of level with common rarity (worst case baseline)
	var effective_item_level = int(player_level * 0.5)
	var rarity_mult = 1.0  # Common baseline

	# Only weapon assumed (some players may not have ring)
	var weapon_attack = int(effective_item_level * rarity_mult * 2)

	return weapon_attack

func _estimate_player_equipment_defense(player_level: int) -> int:
	"""Estimate BASELINE player defense bonus - intentionally conservative.
	This ensures players with good armor feel tanky, not just 'adequate'."""
	# Assume player has only armor at ~50% of level with common rarity
	var effective_item_level = int(player_level * 0.5)
	var rarity_mult = 1.0  # Common baseline

	# Only armor assumed (some players may not have full set)
	var armor_defense = int(effective_item_level * rarity_mult * 2)

	return armor_defense

func _calculate_tiered_stat_scale(base_level: int, target_level: int) -> float:
	"""Calculate stat scaling using tiered percentages"""
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
	"""Calculate XP reward using tiered formula for high levels"""
	var lethality = hp + (strength * 3) + defense

	# Level 1-100: (lethality * level) / 10
	if level <= 100:
		return max(10, int((lethality * level) / 10))

	# Level 101-1000: lethality * (100 + sqrt(level-100) * 20) / 10
	if level <= 1000:
		var bonus = 100 + sqrt(level - 100) * 20
		return max(10, int(lethality * bonus / 10))

	# Level 1000+: lethality * (1000 + log(level) * 200) / 10
	var bonus = 1000 + log(level) * 200
	return max(10, int(lethality * bonus / 10))

func _calculate_gold_reward(base_stats: Dictionary, stat_scale: float, level: int) -> int:
	"""Calculate gold reward with level bonus for high-level monsters"""
	var base_gold = base_stats.base_gold
	var gold_scale = max(0.5, stat_scale)
	var gold_reward = base_gold * gold_scale

	# Add level bonus for level 100+
	if level >= 100:
		var level_bonus = 1.0 + log(level / 100.0) * 0.5
		gold_reward *= level_bonus

	# Apply variance
	gold_reward *= randf_range(0.8, 1.2)

	return max(1, int(gold_reward))

func _calculate_monster_intelligence(level: int) -> int:
	"""Calculate monster intelligence based on level tier.
	Used for the Outsmart mechanic - higher intelligence = harder to outsmart.
	Tier 1-2 (1-15): 5-15 - easy to outsmart
	Tier 3-4 (16-50): 15-30 - moderate
	Tier 5-6 (51-500): 30-50 - challenging
	Tier 7-9 (500+): 50-80 - nearly impossible to outsmart"""

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
		base_intelligence = 35
		variance = 10
	elif level <= 500:
		# Tier 6: Highly intelligent
		base_intelligence = 45
		variance = 5
	elif level <= 2000:
		# Tier 7: Genius-level
		base_intelligence = 55
		variance = 10
	elif level <= 5000:
		# Tier 8: Near-omniscient
		base_intelligence = 65
		variance = 10
	else:
		# Tier 9: Godlike intelligence
		base_intelligence = 75
		variance = 5

	# Add some randomness to the intelligence within the tier
	var final_intelligence = base_intelligence + (randi() % (variance + 1)) - (variance / 2)
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
