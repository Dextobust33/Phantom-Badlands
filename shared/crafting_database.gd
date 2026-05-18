# crafting_database.gd
# Defines crafting skills, recipes, materials, and quality system
extends Node
class_name CraftingDatabase

# Crafting skill types
enum CraftingSkill {
	BLACKSMITHING,  # Weapons, armor
	ALCHEMY,        # Potions, consumables
	ENCHANTING,     # Upgrade equipment, add effects
	SCRIBING,       # Scrolls, maps, tomes, bestiary
	CONSTRUCTION    # Structures, player posts, workstations
}

# Station → crafting skill mapping
const STATION_SKILL_MAP = {
	"forge": "blacksmithing",
	"apothecary": "alchemy",
	"enchant_table": "enchanting",
	"writing_desk": "scribing",
	"workbench": "construction"
}

const SKILL_STATION_NAMES = {
	"blacksmithing": "Forge",
	"alchemy": "Apothecary",
	"enchanting": "Enchanting Table",
	"scribing": "Writing Desk",
	"construction": "Workbench"
}

# Reverse map: skill name -> required station tile type
const SKILL_STATION_MAP = {
	"blacksmithing": "forge",
	"alchemy": "apothecary",
	"enchanting": "enchant_table",
	"scribing": "writing_desk",
	"construction": "workbench"
}

# Quality levels from crafting
enum CraftingQuality {
	FAILED,      # 0% - materials lost
	POOR,        # 50% stats
	STANDARD,    # 100% stats
	FINE,        # 125% stats
	MASTERWORK   # 150% stats
}

# Quality multipliers for item stats
const QUALITY_MULTIPLIERS = {
	CraftingQuality.FAILED: 0.0,
	CraftingQuality.POOR: 0.5,
	CraftingQuality.STANDARD: 1.0,
	CraftingQuality.FINE: 1.25,
	CraftingQuality.MASTERWORK: 1.5
}

# Quality color codes for display
const QUALITY_COLORS = {
	CraftingQuality.FAILED: "#808080",
	CraftingQuality.POOR: "#FFFFFF",
	CraftingQuality.STANDARD: "#00FF00",
	CraftingQuality.FINE: "#0070DD",
	CraftingQuality.MASTERWORK: "#A335EE"
}

# Quality names
const QUALITY_NAMES = {
	CraftingQuality.FAILED: "Failed",
	CraftingQuality.POOR: "Poor",
	CraftingQuality.STANDARD: "Standard",
	CraftingQuality.FINE: "Fine",
	CraftingQuality.MASTERWORK: "Masterwork"
}

# XP per craft based on recipe difficulty
const BASE_CRAFT_XP = 25

# ===== CRAFTING BOOST CONFIG =====
# Audit #4 — Crafting Minigame overhaul (Slice 1).
# Players can opt into spending extra materials for a better quality distribution.
# - mat_mult: multiplier applied to every recipe material cost
# - shift:    +/- percentage-point shifts applied to each quality bucket
#             (applied AFTER the base roll_quality distribution is computed,
#             then renormalized to sum to 100)
# - no_poor:  if true, Poor outcomes are converted to Standard (Master floor)
# Specialist crafters (Lv 40+ in the recipe's skill) get -20% off mat_mult cost;
# Lv 20-39 get -10%. See apply_specialist_discount().
const BOOST_CONFIG = {
	"none":    {"mat_mult": 1.0, "shift": {"masterwork": 0,  "fine": 0, "standard": 0,   "poor": 0},   "no_poor": false},
	"refined": {"mat_mult": 1.5, "shift": {"masterwork": 5,  "fine": 5, "standard": -5,  "poor": -5},  "no_poor": false},
	"master":  {"mat_mult": 2.5, "shift": {"masterwork": 15, "fine": 5, "standard": -10, "poor": -10}, "no_poor": true}
}

# ===== UPGRADE & ENCHANTMENT CAPS =====
# Max upgrade levels that can be applied to a single item via crafting
const MAX_UPGRADE_LEVELS = 50

# Max different enchantment stats allowed on a single item
const MAX_ENCHANTMENT_TYPES = 3

# Per-stat enchantment cap per item (max total bonus from enchanting)
const ENCHANTMENT_STAT_CAPS = {
	"attack": 60,
	"defense": 60,
	"max_hp": 200,
	"max_mana": 150,
	"speed": 15,
	"stamina": 50,
	"energy": 50,
	"strength": 20,
	"constitution": 20,
	"dexterity": 20,
	"intelligence": 20,
	"wisdom": 20,
	"wits": 20,
}

# ===== MONSTER PART GROUP SYSTEM =====
# Maps rune stats to the part suffixes that provide them
const PART_SUFFIX_GROUPS = {
	"attack": ["_fang", "_tooth", "_claw", "_horn", "_mandible"],
	"defense": ["_hide", "_scale", "_plate", "_chitin"],
	"hp": ["_heart"],
	"speed": ["_fin", "_gear"],
	"mana": ["_soul_shard"],
	"stamina": ["_core"],
	"energy": ["_charm", "_spark", "_ember"],
	"str": ["_ichor", "_venom_sac"],
	"con": ["_bone"],
	"dex": ["_tentacle"],
	"int": ["_dust", "_eye"],
	"wis": ["_essence", "_pearl"],
	"wits": ["_ear"],
}

# Maps rune tier names to the monster tier range [min, max] that qualifies
const RUNE_TIER_RANGES = {
	"minor": [1, 2],
	"greater": [3, 6],
	"supreme": [7, 9],
}

# Human-readable display names for each part group
const PART_GROUP_DISPLAY = {
	"attack": "Fang/Tooth/Claw",
	"defense": "Hide/Scale/Plate",
	"hp": "Heart",
	"speed": "Fin/Gear",
	"mana": "Soul Shard",
	"stamina": "Core",
	"energy": "Charm/Spark/Ember",
	"str": "Ichor/Venom",
	"con": "Bone",
	"dex": "Tentacle",
	"int": "Dust/Eye",
	"wis": "Essence/Pearl",
	"wits": "Ear",
}

# ===== CRAFTING CHALLENGE QUESTIONS =====
# 10 question sets per skill, each with 3 options (index 0 is always correct)
const CRAFT_CHALLENGE_QUESTIONS = {
	"blacksmithing": [
		{"q": "The metal is cooling. What do you do?", "opts": ["Reheat to orange glow", "Hammer faster", "Quench it now"]},
		{"q": "The blade is warping. How do you fix it?", "opts": ["Flatten on the anvil face", "Plunge into oil", "Bend it back by hand"]},
		{"q": "You see bubbles forming in the steel.", "opts": ["Flux the impurities", "Ignore and continue", "Add more coal"]},
		{"q": "The edge needs to be hardened.", "opts": ["Heat to cherry red then quench", "Cold hammer the edge", "File it sharper"]},
		{"q": "The tang connection is loose.", "opts": ["Rivet and peen the joint", "Add more solder", "Wrap with wire"]},
		{"q": "How should you start the forging?", "opts": ["Draw out the billet first", "Start at the tip", "Shape the guard"]},
		{"q": "The alloy needs tempering.", "opts": ["Heat gently then air cool", "Plunge into ice water", "Leave it in the forge"]},
		{"q": "You notice scale forming on the surface.", "opts": ["Wire brush and reflux", "Sand it down later", "Scrape with a chisel"]},
		{"q": "The piece needs to be joined.", "opts": ["Forge weld at white heat", "Use cold rivets only", "Twist the pieces together"]},
		{"q": "Final finishing step?", "opts": ["Progressive grit polishing", "Single rough pass", "Leave the forge scale"]},
	],
	"alchemy": [
		{"q": "The mixture is bubbling violently.", "opts": ["Reduce the heat slowly", "Add more catalyst", "Stir vigorously"]},
		{"q": "The solution turned the wrong color.", "opts": ["Add the reagent drop by drop", "Pour in more solvent", "Start over"]},
		{"q": "When should you add the catalyst?", "opts": ["After the base stabilizes", "Immediately at the start", "When it starts smoking"]},
		{"q": "The potion needs to be concentrated.", "opts": ["Simmer on low heat", "Boil rapidly", "Add a thickening agent"]},
		{"q": "Sediment is forming at the bottom.", "opts": ["Filter through silk cloth", "Shake vigorously", "Ignore it"]},
		{"q": "The extract needs to be preserved.", "opts": ["Add stabilizing salts", "Cork it immediately", "Expose to moonlight"]},
		{"q": "How do you test the potency?", "opts": ["Smell the vapor carefully", "Taste a drop", "Pour it on metal"]},
		{"q": "The ingredients are reacting too fast.", "opts": ["Add a buffer solution", "Stir clockwise rapidly", "Remove from heat"]},
		{"q": "The distillation process stalls.", "opts": ["Check the condenser seal", "Increase flame to maximum", "Add water"]},
		{"q": "Final step before bottling?", "opts": ["Strain and decant", "Cool naturally", "Add a preservative pinch"]},
	],
	"enchanting": [
		{"q": "The rune circle is flickering.", "opts": ["Realign the focus crystal", "Add more mana", "Draw the circle again"]},
		{"q": "Which alignment for the sigil?", "opts": ["Align to the item's material", "Point north always", "Random orientation"]},
		{"q": "The enchantment is resisting.", "opts": ["Channel energy through the gem", "Force more power", "Wait for it to settle"]},
		{"q": "The glyph sequence matters.", "opts": ["Inner circle first, then outer", "Outer to inner", "All at once"]},
		{"q": "The binding is unstable.", "opts": ["Anchor with a ward stone", "Press on quickly", "Dispel and restart"]},
		{"q": "How to strengthen the enchantment?", "opts": ["Layer the runes precisely", "Use a bigger crystal", "Double the mana input"]},
		{"q": "The essence is dissipating.", "opts": ["Seal the circle boundaries", "Add more reagents", "Chant louder"]},
		{"q": "Interference from the environment.", "opts": ["Ground the excess energy", "Move to a new location", "Ignore and continue"]},
		{"q": "The item is resisting the enchantment.", "opts": ["Attune through slow contact", "Strike it with lightning", "Submerge in mana"]},
		{"q": "Final sealing step?", "opts": ["Trace the binding seal", "Break the circle cleanly", "Flood with energy"]},
	],
	"scribing": [
		{"q": "The ink is bleeding on the parchment.", "opts": ["Switch to finer nib", "Use thicker ink", "Press harder"]},
		{"q": "The scroll design requires precision.", "opts": ["Use broad strokes for borders", "Freehand everything", "Use a single line weight"]},
		{"q": "The magical ink is fading.", "opts": ["Recharge with essence drops", "Write faster", "Use normal ink instead"]},
		{"q": "The binding spell needs a focus.", "opts": ["Inscribe the focus glyph first", "Skip the focus", "Use a random symbol"]},
		{"q": "The parchment is curling.", "opts": ["Weight the corners flat", "Roll it tighter", "Moisten and press"]},
		{"q": "Complex diagram ahead. Best approach?", "opts": ["Cross-hatch for shading", "Single bold lines only", "Dot stippling"]},
		{"q": "The tome needs page reinforcement.", "opts": ["Apply sizing to the paper", "Use thicker pages", "Glue pages together"]},
		{"q": "You notice an error in the text.", "opts": ["Carefully scrape and rewrite", "Cross it out", "Leave it and continue"]},
		{"q": "The map scale needs to be set.", "opts": ["Measure and grid first", "Estimate by eye", "Copy from memory"]},
		{"q": "Finishing the illuminated border.", "opts": ["Fine detail with thin brush", "Broad sweeping strokes", "Skip the decoration"]},
	],
	"construction": [
		{"q": "The foundation is shifting.", "opts": ["Brace the corners first", "Add more weight on top", "Dig deeper"]},
		{"q": "The load distribution is uneven.", "opts": ["Add a center support pillar", "Shift everything left", "Remove the top layer"]},
		{"q": "The joint needs reinforcement.", "opts": ["Buttress with cross-beams", "Use more nails", "Lash with rope"]},
		{"q": "The wall is bowing outward.", "opts": ["Install flying buttresses", "Push it back", "Thin the wall"]},
		{"q": "The mortar isn't setting.", "opts": ["Adjust the sand-to-lime ratio", "Add more water", "Heat it with fire"]},
		{"q": "How to waterproof the structure?", "opts": ["Apply pitch to seams", "Build a moat", "Use thicker stone"]},
		{"q": "The roof angle matters for snow.", "opts": ["Steep pitch for shedding", "Flat for easy building", "Moderate for balance"]},
		{"q": "Choosing the right wood for beams.", "opts": ["Seasoned hardwood", "Green softwood", "Any available lumber"]},
		{"q": "The doorframe is sagging.", "opts": ["Install a header beam", "Remove the door", "Add more hinges"]},
		{"q": "Final structural check?", "opts": ["Test load-bearing capacity", "Visual inspection only", "Move in immediately"]},
	],
}

# Auto-skip threshold: if skill - difficulty >= this, skip the minigame
const CRAFT_CHALLENGE_AUTO_SKIP = 30

# Output types that support bulk crafting (quantity > 1)
const BULK_CRAFTABLE_TYPES = ["consumable", "structure", "rune", "enhancement",
	"escape_scroll", "material", "scroll", "map", "tome", "bestiary"]

# ===== MATERIALS =====
# Materials can come from fishing, monster drops, or gathering
const MATERIALS = {
	# Fish (from fishing)
	"small_fish": {"name": "Small Fish", "type": "fish", "tier": 1, "value": 5},
	"medium_fish": {"name": "Medium Fish", "type": "fish", "tier": 2, "value": 15},
	"large_fish": {"name": "Large Fish", "type": "fish", "tier": 3, "value": 30},
	"rare_fish": {"name": "Rare Fish", "type": "fish", "tier": 4, "value": 50},
	"deep_sea_fish": {"name": "Deep Sea Fish", "type": "fish", "tier": 5, "value": 80},
	"legendary_fish": {"name": "Legendary Fish", "type": "fish", "tier": 6, "value": 150},

	# Aquatic materials (from fishing)
	"seaweed": {"name": "Seaweed", "type": "plant", "tier": 1, "value": 3},
	"magic_kelp": {"name": "Magic Kelp", "type": "plant", "tier": 3, "value": 25},
	"pearl": {"name": "Pearl", "type": "gem", "tier": 4, "value": 100},
	"black_pearl": {"name": "Black Pearl", "type": "gem", "tier": 6, "value": 300},
	"coral_fragment": {"name": "Coral Fragment", "type": "mineral", "tier": 2, "value": 10},
	"sea_crystal": {"name": "Sea Crystal", "type": "gem", "tier": 5, "value": 150},
	"freshwater_pearl": {"name": "Freshwater Pearl", "type": "gem", "tier": 2, "value": 50},
	"river_crab": {"name": "River Crab", "type": "fish", "tier": 2, "value": 25},
	"golden_fish": {"name": "Golden Fish", "type": "fish", "tier": 3, "value": 100},
	"enchanted_kelp": {"name": "Enchanted Kelp", "type": "plant", "tier": 3, "value": 75},
	"abyssal_crab": {"name": "Abyssal Crab", "type": "fish", "tier": 5, "value": 50},
	"giant_pearl": {"name": "Giant Pearl", "type": "gem", "tier": 5, "value": 150},
	"leviathan_scale": {"name": "Leviathan Scale", "type": "mineral", "tier": 5, "value": 200},
	"prismatic_fish": {"name": "Prismatic Fish", "type": "fish", "tier": 5, "value": 250},
	"sea_dragon_fang": {"name": "Sea Dragon Fang", "type": "mineral", "tier": 5, "value": 300},
	"ancient_relic": {"name": "Ancient Relic", "type": "treasure", "tier": 5, "value": 400},
	"kraken_ink": {"name": "Kraken Ink", "type": "writing", "tier": 5, "value": 350},

	# Ores (from monster drops by tier)
	"copper_ore": {"name": "Copper Ore", "type": "ore", "tier": 1, "value": 8},
	"iron_ore": {"name": "Iron Ore", "type": "ore", "tier": 2, "value": 15},
	"steel_ore": {"name": "Steel Ore", "type": "ore", "tier": 3, "value": 30},
	"mithril_ore": {"name": "Mithril Ore", "type": "ore", "tier": 4, "value": 60},
	"adamantine_ore": {"name": "Adamantine Ore", "type": "ore", "tier": 5, "value": 120},
	"orichalcum_ore": {"name": "Orichalcum Ore", "type": "ore", "tier": 6, "value": 250},
	"void_ore": {"name": "Void Ore", "type": "ore", "tier": 7, "value": 500},
	"celestial_ore": {"name": "Celestial Ore", "type": "ore", "tier": 8, "value": 1000},
	"primordial_ore": {"name": "Primordial Ore", "type": "ore", "tier": 9, "value": 2000},

	# Wood (from logging)
	"common_wood": {"name": "Common Wood", "type": "wood", "tier": 1, "value": 6},
	"oak_wood": {"name": "Oak Wood", "type": "wood", "tier": 2, "value": 12},
	"ash_wood": {"name": "Ash Wood", "type": "wood", "tier": 3, "value": 25},
	"ironwood": {"name": "Ironwood", "type": "wood", "tier": 4, "value": 50},
	"darkwood": {"name": "Darkwood", "type": "wood", "tier": 5, "value": 100},
	"worldtree_branch": {"name": "Worldtree Branch", "type": "wood", "tier": 6, "value": 200},
	"heartwood": {"name": "Heartwood", "type": "wood", "tier": 4, "value": 80},
	"elderwood": {"name": "Elderwood", "type": "wood", "tier": 5, "value": 150},
	"worldtree_heartwood": {"name": "Worldtree Heartwood", "type": "wood", "tier": 6, "value": 400},

	# Mining extras (gems, minerals)
	"stone": {"name": "Stone", "type": "mineral", "tier": 1, "value": 2},
	"coal": {"name": "Coal", "type": "mineral", "tier": 1, "value": 5},
	"rough_gem": {"name": "Rough Gem", "type": "gem", "tier": 1, "value": 25},
	"polished_gem": {"name": "Polished Gem", "type": "gem", "tier": 2, "value": 75},
	"flawless_gem": {"name": "Flawless Gem", "type": "gem", "tier": 3, "value": 150},
	"perfect_gem": {"name": "Perfect Gem", "type": "gem", "tier": 4, "value": 300},
	"star_gem": {"name": "Star Gem", "type": "gem", "tier": 5, "value": 500},
	"celestial_gem": {"name": "Celestial Gem", "type": "gem", "tier": 6, "value": 800},
	"primordial_gem": {"name": "Primordial Gem", "type": "gem", "tier": 7, "value": 1500},

	# Logging extras (saps, resins)
	"bark": {"name": "Bark", "type": "plant", "tier": 1, "value": 3},
	"sap": {"name": "Tree Sap", "type": "plant", "tier": 1, "value": 8},
	"acorn": {"name": "Golden Acorn", "type": "plant", "tier": 1, "value": 20},
	"enchanted_resin": {"name": "Enchanted Resin", "type": "enchant", "tier": 3, "value": 75},
	"celestial_shard": {"name": "Celestial Shard", "type": "enchant", "tier": 7, "value": 400},

	# Leather/Cloth (from monster drops)
	"ragged_leather": {"name": "Ragged Leather", "type": "leather", "tier": 1, "value": 5},
	"leather_scraps": {"name": "Leather Scraps", "type": "leather", "tier": 2, "value": 10},
	"thick_leather": {"name": "Thick Leather", "type": "leather", "tier": 3, "value": 20},
	"enchanted_leather": {"name": "Enchanted Leather", "type": "leather", "tier": 4, "value": 45},
	"wyvern_leather": {"name": "Wyvern Leather", "type": "leather", "tier": 5, "value": 100},
	"dragonhide": {"name": "Dragonhide", "type": "leather", "tier": 6, "value": 200},
	"void_silk": {"name": "Void Silk", "type": "cloth", "tier": 7, "value": 400},
	"celestial_hide": {"name": "Celestial Hide", "type": "leather", "tier": 8, "value": 800},
	"astral_weave": {"name": "Astral Weave", "type": "leather", "tier": 9, "value": 1500},

	# Herbs (from monster drops, for alchemy)
	"healing_herb": {"name": "Healing Herb", "type": "herb", "tier": 1, "value": 5},
	"mana_blossom": {"name": "Mana Blossom", "type": "herb", "tier": 2, "value": 12},
	"vigor_root": {"name": "Vigor Root", "type": "herb", "tier": 2, "value": 12},
	"shadowleaf": {"name": "Shadowleaf", "type": "herb", "tier": 3, "value": 25},
	"phoenix_petal": {"name": "Phoenix Petal", "type": "herb", "tier": 5, "value": 100},
	"dragon_blood": {"name": "Dragon Blood", "type": "essence", "tier": 6, "value": 250},
	"essence_of_life": {"name": "Essence of Life", "type": "essence", "tier": 7, "value": 500},

	# Enchanting materials
	"magic_dust": {"name": "Magic Dust", "type": "enchant", "tier": 1, "value": 10},
	"arcane_crystal": {"name": "Arcane Crystal", "type": "enchant", "tier": 3, "value": 50},
	"soul_shard": {"name": "Soul Shard", "type": "enchant", "tier": 4, "value": 80},
	"void_essence": {"name": "Void Essence", "type": "enchant", "tier": 6, "value": 200},
	"primordial_spark": {"name": "Primordial Spark", "type": "enchant", "tier": 8, "value": 800},

	# Dungeon-exclusive crystals (only from dungeon gathering nodes)
	"void_crystal": {"name": "Void Crystal", "type": "crystal", "tier": 7, "value": 600},
	"abyssal_shard": {"name": "Abyssal Shard", "type": "crystal", "tier": 8, "value": 1200},
	"primordial_essence": {"name": "Primordial Essence", "type": "crystal", "tier": 9, "value": 2500},

	# Monster Gems (from combat, quest rewards)
	"monster_gem": {"name": "Monster Gem", "type": "gem", "tier": 5, "value": 1000},

	# Writing materials (crafted by scribes)
	"parchment": {"name": "Parchment", "type": "paper", "tier": 1, "value": 5},
	"fine_parchment": {"name": "Fine Parchment", "type": "paper", "tier": 3, "value": 30},
	"vellum": {"name": "Vellum", "type": "paper", "tier": 5, "value": 100},
	"ink": {"name": "Ink", "type": "writing", "tier": 1, "value": 8},
	"arcane_ink": {"name": "Arcane Ink", "type": "writing", "tier": 3, "value": 40},
	"void_ink": {"name": "Void Ink", "type": "writing", "tier": 5, "value": 150},
	"binding_thread": {"name": "Binding Thread", "type": "writing", "tier": 2, "value": 15},

	# Construction materials (crafted by builders)
	"wooden_plank": {"name": "Wooden Plank", "type": "construction", "tier": 1, "value": 5},
	"rope": {"name": "Rope", "type": "construction", "tier": 1, "value": 4},
	"stone_block": {"name": "Stone Block", "type": "construction", "tier": 1, "value": 6},

	# Foraging — T1
	"clover": {"name": "Clover", "type": "herb", "tier": 1, "value": 5},
	"wild_berries": {"name": "Wild Berries", "type": "plant", "tier": 1, "value": 4},
	"common_mushroom": {"name": "Common Mushroom", "type": "fungus", "tier": 1, "value": 6},
	"reed_fiber": {"name": "Reed Fiber", "type": "plant", "tier": 1, "value": 3},
	"four_leaf_clover": {"name": "Four-Leaf Clover", "type": "herb", "tier": 1, "value": 50},
	# Foraging — T2
	"sage": {"name": "Sage", "type": "herb", "tier": 2, "value": 12},
	"thornberry": {"name": "Thornberry", "type": "plant", "tier": 2, "value": 15},
	"cave_mushroom": {"name": "Cave Mushroom", "type": "fungus", "tier": 2, "value": 18},
	"enchanted_pollen": {"name": "Enchanted Pollen", "type": "enchant", "tier": 2, "value": 40},
	# Foraging — T3
	"moonpetal": {"name": "Moonpetal", "type": "herb", "tier": 3, "value": 30},
	"glowing_mushroom": {"name": "Glowing Mushroom", "type": "fungus", "tier": 3, "value": 35},
	"crystal_flower": {"name": "Crystal Flower", "type": "plant", "tier": 3, "value": 45},
	"arcane_moss": {"name": "Arcane Moss", "type": "enchant", "tier": 3, "value": 50},
	# Foraging — T4
	"bloodroot": {"name": "Bloodroot", "type": "herb", "tier": 4, "value": 60},
	"nightmare_cap": {"name": "Nightmare Cap", "type": "fungus", "tier": 4, "value": 70},
	"spirit_blossom": {"name": "Spirit Blossom", "type": "herb", "tier": 4, "value": 80},
	"heartwood_seed": {"name": "Heartwood Seed", "type": "plant", "tier": 4, "value": 120},
	# Foraging — T5
	"starbloom": {"name": "Starbloom", "type": "herb", "tier": 5, "value": 120},
	"void_spore": {"name": "Void Spore", "type": "fungus", "tier": 5, "value": 150},
	"celestial_petal": {"name": "Celestial Petal", "type": "herb", "tier": 5, "value": 250},
	"worldtree_seed": {"name": "Worldtree Seed", "type": "plant", "tier": 5, "value": 300},
	# Foraging — T6
	"voidpetal": {"name": "Voidpetal", "type": "herb", "tier": 6, "value": 250},
	"primordial_fungus": {"name": "Primordial Fungus", "type": "fungus", "tier": 6, "value": 300},
	"void_blossom": {"name": "Void Blossom", "type": "herb", "tier": 6, "value": 600},
	"creation_seed": {"name": "Creation Seed", "type": "plant", "tier": 6, "value": 800},

	# Slice 6c — biome-exclusive foraging materials. Each non-plains biome
	# has two T1 anchors + one T2 standout that only drop when foraging in
	# that biome. Values lean slightly higher than the equivalent generic
	# foraging material so the trip is rewarded; rarity is enforced via
	# their weight in BIOME_FORAGING_BONUS (drop_tables.gd), not their
	# entry here. The "type" field re-uses existing material categories so
	# they slot into future crafting recipes without a new dimension.
	# Forest
	"pine_resin":      {"name": "Pine Resin", "type": "plant", "tier": 1, "value": 8},
	"oak_acorn":       {"name": "Oak Acorn", "type": "plant", "tier": 1, "value": 7},
	"silverleaf":      {"name": "Silverleaf", "type": "herb", "tier": 2, "value": 22},
	# Highlands (mountain)
	"alpine_lichen":   {"name": "Alpine Lichen", "type": "herb", "tier": 1, "value": 8},
	"rock_salt":       {"name": "Rock Salt", "type": "mineral", "tier": 1, "value": 6},
	"crag_thistle":    {"name": "Crag Thistle", "type": "herb", "tier": 2, "value": 22},
	# Swamp
	"bog_iris":        {"name": "Bog Iris", "type": "herb", "tier": 1, "value": 9},
	"marsh_reed":      {"name": "Marsh Reed", "type": "plant", "tier": 1, "value": 6},
	"witch_cap":       {"name": "Witch Cap", "type": "fungus", "tier": 2, "value": 24},
	# Tundra (snow)
	"frost_lichen":    {"name": "Frost Lichen", "type": "herb", "tier": 1, "value": 9},
	"ice_crystal":     {"name": "Ice Crystal", "type": "gem", "tier": 1, "value": 12},
	"snow_bloom":      {"name": "Snow Bloom", "type": "herb", "tier": 2, "value": 26},
	# Desert
	"cactus_flesh":    {"name": "Cactus Flesh", "type": "plant", "tier": 1, "value": 8},
	"sun_petal":       {"name": "Sun Petal", "type": "herb", "tier": 1, "value": 10},
	"scorched_root":   {"name": "Scorched Root", "type": "herb", "tier": 2, "value": 24},
}

# ===== RECIPES =====
# Each recipe defines what can be crafted
const RECIPES = {
	# ===== BLACKSMITHING RECIPES =====
	# Tier 1 - Copper (Level 1-15)
	"copper_sword": {
		"name": "Copper Sword",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 1,
		"difficulty": 5,
		"materials": {"copper_ore": 3},
		"output_type": "weapon",
		"output_slot": "weapon",
		"base_stats": {"attack": 5, "level": 5},
		"craft_time": 2.0
	},
	"copper_shield": {
		"name": "Copper Shield",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 5,
		"difficulty": 10,
		"materials": {"copper_ore": 4, "ragged_leather": 1},
		"output_type": "armor",
		"output_slot": "shield",
		"base_stats": {"defense": 4, "level": 5},
		"craft_time": 2.5
	},
	"copper_helm": {
		"name": "Copper Helm",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 8,
		"difficulty": 12,
		"materials": {"copper_ore": 3, "ragged_leather": 1},
		"output_type": "armor",
		"output_slot": "helm",
		"base_stats": {"defense": 3, "hp": 10, "level": 5},
		"craft_time": 2.0
	},
	"copper_armor": {
		"name": "Copper Armor",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 10,
		"difficulty": 15,
		"materials": {"copper_ore": 5, "ragged_leather": 2},
		"output_type": "armor",
		"output_slot": "armor",
		"base_stats": {"defense": 5, "hp": 15, "level": 5},
		"craft_time": 3.0
	},
	"copper_boots": {
		"name": "Copper Boots",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 12,
		"difficulty": 14,
		"materials": {"copper_ore": 3, "ragged_leather": 2},
		"output_type": "armor",
		"output_slot": "boots",
		"base_stats": {"defense": 2, "speed": 1, "level": 5},
		"craft_time": 2.0
	},

	# Tier 2 - Iron (Level 15-30)
	"iron_sword": {
		"name": "Iron Sword",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 15,
		"difficulty": 20,
		"materials": {"iron_ore": 4, "leather_scraps": 1},
		"output_type": "weapon",
		"output_slot": "weapon",
		"base_stats": {"attack": 12, "level": 15},
		"craft_time": 3.0
	},
	"iron_breastplate": {
		"name": "Iron Breastplate",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 20,
		"difficulty": 25,
		"materials": {"iron_ore": 6, "leather_scraps": 2},
		"output_type": "armor",
		"output_slot": "armor",
		"base_stats": {"defense": 10, "hp": 25, "level": 15},
		"craft_time": 4.0
	},
	"iron_shield": {
		"name": "Iron Shield",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 18,
		"difficulty": 22,
		"materials": {"iron_ore": 5, "leather_scraps": 1},
		"output_type": "armor",
		"output_slot": "shield",
		"base_stats": {"defense": 8, "level": 15},
		"craft_time": 3.0
	},
	"iron_helm": {
		"name": "Iron Helm",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 22,
		"difficulty": 26,
		"materials": {"iron_ore": 4, "leather_scraps": 1},
		"output_type": "armor",
		"output_slot": "helm",
		"base_stats": {"defense": 6, "hp": 20, "level": 15},
		"craft_time": 2.5
	},
	"iron_boots": {
		"name": "Iron Boots",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 25,
		"difficulty": 28,
		"materials": {"iron_ore": 4, "leather_scraps": 2},
		"output_type": "armor",
		"output_slot": "boots",
		"base_stats": {"defense": 5, "speed": 2, "level": 15},
		"craft_time": 2.5
	},

	# Tier 3 - Steel (Level 30-50)
	"steel_sword": {
		"name": "Steel Sword",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 30,
		"difficulty": 35,
		"materials": {"steel_ore": 5, "thick_leather": 1},
		"output_type": "weapon",
		"output_slot": "weapon",
		"base_stats": {"attack": 25, "level": 30},
		"craft_time": 4.0
	},
	"steel_armor": {
		"name": "Steel Armor",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 35,
		"difficulty": 40,
		"materials": {"steel_ore": 8, "thick_leather": 3},
		"output_type": "armor",
		"output_slot": "armor",
		"base_stats": {"defense": 20, "hp": 50, "level": 30},
		"craft_time": 5.0
	},
	"steel_shield": {
		"name": "Steel Shield",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 32,
		"difficulty": 38,
		"materials": {"steel_ore": 6, "thick_leather": 2},
		"output_type": "armor",
		"output_slot": "shield",
		"base_stats": {"defense": 15, "level": 30},
		"craft_time": 3.5
	},
	"steel_helm": {
		"name": "Steel Helm",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 38,
		"difficulty": 42,
		"materials": {"steel_ore": 5, "thick_leather": 1},
		"output_type": "armor",
		"output_slot": "helm",
		"base_stats": {"defense": 12, "hp": 40, "level": 30},
		"craft_time": 3.0
	},
	"steel_boots": {
		"name": "Steel Boots",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 40,
		"difficulty": 45,
		"materials": {"steel_ore": 5, "thick_leather": 2},
		"output_type": "armor",
		"output_slot": "boots",
		"base_stats": {"defense": 10, "speed": 4, "level": 30},
		"craft_time": 3.0
	},

	# Tier 4 - Mithril (Level 50-100)
	"mithril_blade": {
		"name": "Mithril Blade",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 45,
		"difficulty": 50,
		"materials": {"mithril_ore": 6, "enchanted_leather": 2},
		"output_type": "weapon",
		"output_slot": "weapon",
		"base_stats": {"attack": 45, "speed": 5, "level": 50},
		"craft_time": 5.0
	},
	"mithril_mail": {
		"name": "Mithril Mail",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 50,
		"difficulty": 55,
		"materials": {"mithril_ore": 10, "enchanted_leather": 4},
		"output_type": "armor",
		"output_slot": "armor",
		"base_stats": {"defense": 35, "hp": 100, "speed": 3, "level": 50},
		"craft_time": 6.0
	},
	"mithril_shield": {
		"name": "Mithril Shield",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 48,
		"difficulty": 52,
		"materials": {"mithril_ore": 7, "enchanted_leather": 2},
		"output_type": "armor",
		"output_slot": "shield",
		"base_stats": {"defense": 25, "speed": 2, "level": 50},
		"craft_time": 4.0
	},
	"mithril_helm": {
		"name": "Mithril Helm",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 52,
		"difficulty": 58,
		"materials": {"mithril_ore": 6, "enchanted_leather": 2},
		"output_type": "armor",
		"output_slot": "helm",
		"base_stats": {"defense": 20, "hp": 75, "speed": 2, "level": 50},
		"craft_time": 4.0
	},
	"mithril_boots": {
		"name": "Mithril Boots",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 55,
		"difficulty": 60,
		"materials": {"mithril_ore": 6, "enchanted_leather": 3},
		"output_type": "armor",
		"output_slot": "boots",
		"base_stats": {"defense": 18, "speed": 6, "level": 50},
		"craft_time": 4.0
	},

	# Tier 5+ - High level crafting
	"adamantine_greatsword": {
		"name": "Adamantine Greatsword",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 65,
		"difficulty": 70,
		"materials": {"adamantine_ore": 8, "dragonhide": 2, "arcane_crystal": 1},
		"output_type": "weapon",
		"output_slot": "weapon",
		"base_stats": {"attack": 80, "level": 100},
		"craft_time": 8.0
	},
	"orichalcum_plate": {
		"name": "Orichalcum Plate",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 80,
		"difficulty": 85,
		"materials": {"orichalcum_ore": 12, "dragonhide": 4, "void_essence": 1},
		"output_type": "armor",
		"output_slot": "armor",
		"base_stats": {"defense": 60, "hp": 200, "level": 150},
		"craft_time": 10.0
	},
	"adamantine_shield": {
		"name": "Adamantine Shield",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 62,
		"difficulty": 68,
		"materials": {"adamantine_ore": 6, "dragonhide": 1},
		"output_type": "armor",
		"output_slot": "shield",
		"base_stats": {"defense": 40, "level": 100},
		"craft_time": 6.0
	},
	"adamantine_helm": {
		"name": "Adamantine Helm",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 68,
		"difficulty": 72,
		"materials": {"adamantine_ore": 5, "dragonhide": 1},
		"output_type": "armor",
		"output_slot": "helm",
		"base_stats": {"defense": 35, "hp": 150, "level": 100},
		"craft_time": 5.0
	},
	"adamantine_boots": {
		"name": "Adamantine Boots",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 70,
		"difficulty": 75,
		"materials": {"adamantine_ore": 5, "dragonhide": 2},
		"output_type": "armor",
		"output_slot": "boots",
		"base_stats": {"defense": 30, "speed": 8, "level": 100},
		"craft_time": 5.0
	},
	"orichalcum_shield": {
		"name": "Orichalcum Shield",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 78,
		"difficulty": 82,
		"materials": {"orichalcum_ore": 8, "dragonhide": 2, "void_essence": 1},
		"output_type": "armor",
		"output_slot": "shield",
		"base_stats": {"defense": 55, "hp": 50, "level": 150},
		"craft_time": 7.0
	},
	"orichalcum_helm": {
		"name": "Orichalcum Helm",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 82,
		"difficulty": 88,
		"materials": {"orichalcum_ore": 8, "dragonhide": 2, "void_essence": 1},
		"output_type": "armor",
		"output_slot": "helm",
		"base_stats": {"defense": 45, "hp": 180, "level": 150},
		"craft_time": 7.0
	},
	"orichalcum_boots": {
		"name": "Orichalcum Boots",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 85,
		"difficulty": 90,
		"materials": {"orichalcum_ore": 8, "dragonhide": 3, "void_essence": 1},
		"output_type": "armor",
		"output_slot": "boots",
		"base_stats": {"defense": 40, "speed": 12, "level": 150},
		"craft_time": 7.0
	},

	# Rings (Tier 1-5)
	"copper_ring": {
		"name": "Copper Ring",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 5,
		"difficulty": 8,
		"materials": {"copper_ore": 2, "rough_gem": 1},
		"output_type": "armor",
		"output_slot": "ring",
		"base_stats": {"defense": 1, "level": 5},
		"craft_time": 2.0
	},
	"iron_ring": {
		"name": "Iron Ring",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 18,
		"difficulty": 22,
		"materials": {"iron_ore": 3, "polished_gem": 1},
		"output_type": "armor",
		"output_slot": "ring",
		"base_stats": {"defense": 3, "hp": 10, "level": 15},
		"craft_time": 2.5
	},
	"steel_ring": {
		"name": "Steel Ring",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 35,
		"difficulty": 40,
		"materials": {"steel_ore": 3, "flawless_gem": 1},
		"output_type": "armor",
		"output_slot": "ring",
		"base_stats": {"defense": 6, "hp": 25, "level": 30},
		"craft_time": 3.0
	},
	"mithril_ring": {
		"name": "Mithril Ring",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 55,
		"difficulty": 60,
		"materials": {"mithril_ore": 3, "perfect_gem": 1, "soul_shard": 1},
		"output_type": "armor",
		"output_slot": "ring",
		"base_stats": {"defense": 10, "speed": 2, "level": 50},
		"craft_time": 4.0
	},
	"adamantine_ring": {
		"name": "Adamantine Ring",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 78,
		"difficulty": 84,
		"materials": {"adamantine_ore": 3, "star_gem": 1, "void_essence": 1},
		"output_type": "armor",
		"output_slot": "ring",
		"base_stats": {"defense": 15, "speed": 3, "level": 100},
		"craft_time": 5.0
	},

	# Amulets (Tier 1-5)
	"copper_amulet": {
		"name": "Copper Amulet",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 5,
		"difficulty": 8,
		"materials": {"copper_ore": 2, "coal": 1},
		"output_type": "armor",
		"output_slot": "amulet",
		"base_stats": {"hp": 15, "level": 5},
		"craft_time": 2.0
	},
	"iron_amulet": {
		"name": "Iron Amulet",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 18,
		"difficulty": 22,
		"materials": {"iron_ore": 3, "coral_fragment": 1},
		"output_type": "armor",
		"output_slot": "amulet",
		"base_stats": {"hp": 30, "level": 15},
		"craft_time": 2.5
	},
	"steel_amulet": {
		"name": "Steel Amulet",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 35,
		"difficulty": 40,
		"materials": {"steel_ore": 3, "arcane_crystal": 1},
		"output_type": "armor",
		"output_slot": "amulet",
		"base_stats": {"hp": 60, "mana": 10, "level": 30},
		"craft_time": 3.0
	},
	"mithril_amulet": {
		"name": "Mithril Amulet",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 55,
		"difficulty": 60,
		"materials": {"mithril_ore": 3, "soul_shard": 1, "pearl": 1},
		"output_type": "armor",
		"output_slot": "amulet",
		"base_stats": {"hp": 100, "mana": 25, "level": 50},
		"craft_time": 4.0
	},
	"adamantine_amulet": {
		"name": "Adamantine Amulet",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 78,
		"difficulty": 84,
		"materials": {"adamantine_ore": 3, "void_essence": 1, "sea_crystal": 1},
		"output_type": "armor",
		"output_slot": "amulet",
		"base_stats": {"hp": 175, "mana": 50, "level": 100},
		"craft_time": 5.0
	},

	# Missing Tier 5 - Adamantine Armor
	"adamantine_armor": {
		"name": "Adamantine Armor",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 80,
		"difficulty": 86,
		"materials": {"adamantine_ore": 10, "dragonhide": 3, "arcane_crystal": 2},
		"output_type": "armor",
		"output_slot": "armor",
		"base_stats": {"defense": 50, "hp": 200, "level": 100},
		"craft_time": 8.0
	},
	# Missing Tier 6 - Orichalcum Weapon
	"orichalcum_blade": {
		"name": "Orichalcum Blade",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 85,
		"difficulty": 90,
		"materials": {"orichalcum_ore": 10, "dragonhide": 2, "void_essence": 2},
		"output_type": "weapon",
		"output_slot": "weapon",
		"base_stats": {"attack": 120, "speed": 8, "level": 150},
		"craft_time": 8.0
	},

	# ===== ALCHEMY RECIPES =====
	# Healing Potions
	"minor_health_potion": {
		"name": "Minor Health Potion",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 1,
		"difficulty": 5,
		"materials": {"healing_herb": 2, "clover": 2},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "heal", "amount": 50},
		"craft_time": 1.5
	},
	"health_potion": {
		"name": "Health Potion",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 15,
		"difficulty": 20,
		"materials": {"healing_herb": 3, "common_mushroom": 2, "medium_fish": 1},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "heal", "amount": 150},
		"craft_time": 2.0
	},
	"greater_health_potion": {
		"name": "Greater Health Potion",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 35,
		"difficulty": 40,
		"materials": {"healing_herb": 4, "crystal_flower": 2, "phoenix_petal": 1},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "heal", "amount": 400},
		"craft_time": 3.0
	},
	"supreme_health_potion": {
		"name": "Supreme Health Potion",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 60,
		"difficulty": 65,
		"materials": {"phoenix_petal": 3, "dragon_blood": 1, "essence_of_life": 1},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "heal", "amount": 1000},
		"craft_time": 4.0
	},

	# Mana Potions
	"minor_mana_potion": {
		"name": "Minor Mana Potion",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 5,
		"difficulty": 10,
		"materials": {"mana_blossom": 2, "seaweed": 2},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "restore_mana", "amount": 30},
		"craft_time": 1.5
	},
	"mana_potion": {
		"name": "Mana Potion",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 20,
		"difficulty": 25,
		"materials": {"mana_blossom": 3, "enchanted_kelp": 2, "moonpetal": 1},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "restore_mana", "amount": 80},
		"craft_time": 2.0
	},

	# Stamina Potions
	"minor_stamina_potion": {
		"name": "Minor Stamina Potion",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 5,
		"difficulty": 10,
		"materials": {"vigor_root": 2, "bark": 2},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "restore_stamina", "amount": 30},
		"craft_time": 1.5
	},
	"stamina_potion": {
		"name": "Stamina Potion",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 20,
		"difficulty": 25,
		"materials": {"vigor_root": 3, "medium_fish": 1, "rare_fish": 1},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "restore_stamina", "amount": 80},
		"craft_time": 2.0
	},

	# Buff Potions
	"potion_of_strength": {
		"name": "Potion of Strength",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 25,
		"difficulty": 30,
		"materials": {"vigor_root": 2, "river_crab": 2, "shadowleaf": 1},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "buff", "stat": "attack", "amount": 15, "duration": 10},
		"craft_time": 3.0
	},
	"potion_of_fortitude": {
		"name": "Potion of Fortitude",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 25,
		"difficulty": 30,
		"materials": {"healing_herb": 2, "large_fish": 2, "shadowleaf": 1},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "buff", "stat": "defense", "amount": 15, "duration": 10},
		"craft_time": 3.0
	},
	"elixir_of_speed": {
		"name": "Elixir of Speed",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 40,
		"difficulty": 45,
		"materials": {"shadowleaf": 2, "golden_fish": 1, "legendary_fish": 1, "arcane_crystal": 1},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "buff", "stat": "speed", "amount": 20, "duration": 8},
		"craft_time": 4.0
	},
	# Energy Potions
	"minor_energy_potion": {
		"name": "Minor Energy Potion",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 5,
		"difficulty": 8,
		"materials": {"vigor_root": 1, "wild_berries": 2, "cave_mushroom": 1},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "restore_energy", "amount": 30},
		"craft_time": 1.5
	},
	"potion_of_vigor": {
		"name": "Potion of Vigor",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 10,
		"difficulty": 12,
		"materials": {"healing_herb": 3, "vigor_root": 2},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "heal", "amount": 100},
		"craft_time": 2.0
	},
	"energy_potion": {
		"name": "Energy Potion",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 20,
		"difficulty": 25,
		"materials": {"vigor_root": 4, "thornberry": 2},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "restore_energy", "amount": 80},
		"craft_time": 2.5
	},
	# Greater Resource Potions
	"greater_mana_potion": {
		"name": "Greater Mana Potion",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 40,
		"difficulty": 45,
		"materials": {"mana_blossom": 4, "spirit_blossom": 2, "arcane_crystal": 1},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "restore_mana", "amount": 200},
		"craft_time": 3.5
	},
	"greater_stamina_potion": {
		"name": "Greater Stamina Potion",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 40,
		"difficulty": 45,
		"materials": {"vigor_root": 6, "phoenix_petal": 1, "iron_ore": 2},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "restore_stamina", "amount": 200},
		"craft_time": 3.5
	},
	"greater_energy_potion": {
		"name": "Greater Energy Potion",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 40,
		"difficulty": 45,
		"materials": {"vigor_root": 3, "glowing_mushroom": 2, "arcane_crystal": 1},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "restore_energy", "amount": 200},
		"craft_time": 3.5
	},

	# ===== ENCHANTING RECIPES =====
	"minor_weapon_enhancement": {
		"name": "Minor Weapon Enhancement",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 10,
		"difficulty": 15,
		"materials": {"magic_dust": 5},
		"output_type": "enhancement",
		"output_slot": "weapon",
		"effect": {"type": "enhance", "stat": "attack", "bonus": 3},
		"craft_time": 3.0
	},
	"minor_armor_enhancement": {
		"name": "Minor Armor Enhancement",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 10,
		"difficulty": 15,
		"materials": {"magic_dust": 5},
		"output_type": "enhancement",
		"output_slot": "armor",
		"effect": {"type": "enhance", "stat": "defense", "bonus": 3},
		"craft_time": 3.0
	},
	"arcane_weapon_enhancement": {
		"name": "Arcane Weapon Enhancement",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 35,
		"difficulty": 40,
		"materials": {"arcane_crystal": 3, "soul_shard": 1},
		"output_type": "enhancement",
		"output_slot": "weapon",
		"effect": {"type": "enhance", "stat": "attack", "bonus": 10},
		"craft_time": 5.0
	},
	"arcane_armor_enhancement": {
		"name": "Arcane Armor Enhancement",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 35,
		"difficulty": 40,
		"materials": {"arcane_crystal": 3, "soul_shard": 1},
		"output_type": "enhancement",
		"output_slot": "armor",
		"effect": {"type": "enhance", "stat": "defense", "bonus": 10},
		"craft_time": 5.0
	},
	"void_enhancement": {
		"name": "Void Enhancement",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 60,
		"difficulty": 65,
		"materials": {"void_essence": 2, "primordial_spark": 1},
		"output_type": "enhancement",
		"output_slot": "any",
		"effect": {"type": "enhance", "stat": "all", "bonus": 5},
		"craft_time": 8.0
	},

	# ===== BEGINNER ENCHANTING RECIPES =====
	"refine_magic_dust": {
		"name": "Refine Magic Dust",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 1,
		"difficulty": 5,
		"materials": {"sap": 2, "acorn": 1},
		"output_type": "material",
		"output_item": "magic_dust",
		"output_quantity": 2,
		"craft_time": 1.5
	},
	"distill_magic_dust": {
		"name": "Distill Magic Dust",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 1,
		"difficulty": 5,
		"materials": {"sap": 4},
		"output_type": "material",
		"output_item": "magic_dust",
		"output_quantity": 2,
		"craft_time": 1.5
	},
	# ===== RUNE RECIPES (create tradeable Rune items) =====
	# --- Minor Runes (Skill 3-5, T1-T3 monster parts) ---
	"rune_minor_attack": {
		"name": "Minor Rune of Attack",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 3,
		"difficulty": 8,
		"materials": {"@attack:minor": 3, "magic_dust": 3},
		"output_type": "rune",
		"target_slot": "weapon",
		"rune_stat": "attack_bonus",
		"rune_tier": "minor",
		"rune_cap": 8,
		"craft_time": 3.0
	},
	"rune_minor_defense": {
		"name": "Minor Rune of Defense",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 3,
		"difficulty": 8,
		"materials": {"@defense:minor": 3, "magic_dust": 3},
		"output_type": "rune",
		"target_slot": "armor,shield",
		"rune_stat": "defense_bonus",
		"rune_tier": "minor",
		"rune_cap": 8,
		"craft_time": 3.0
	},
	"rune_minor_hp": {
		"name": "Minor Rune of Vitality",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 3,
		"difficulty": 8,
		"materials": {"@hp:minor": 3, "magic_dust": 3},
		"output_type": "rune",
		"target_slot": "helm,armor,shield",
		"rune_stat": "hp_bonus",
		"rune_tier": "minor",
		"rune_cap": 25,
		"craft_time": 3.0
	},
	"rune_minor_speed": {
		"name": "Minor Rune of Speed",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 5,
		"difficulty": 10,
		"materials": {"@speed:minor": 3, "magic_dust": 3},
		"output_type": "rune",
		"target_slot": "boots",
		"rune_stat": "speed_bonus",
		"rune_tier": "minor",
		"rune_cap": 3,
		"craft_time": 3.0
	},
	"rune_minor_mana": {
		"name": "Minor Rune of Mana",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 5,
		"difficulty": 10,
		"materials": {"@mana:minor": 3, "magic_dust": 3},
		"output_type": "rune",
		"target_slot": "amulet,ring",
		"rune_stat": "mana_bonus",
		"rune_tier": "minor",
		"rune_cap": 12,
		"craft_time": 3.0
	},
	"rune_minor_stamina": {
		"name": "Minor Rune of Stamina",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 5,
		"difficulty": 10,
		"materials": {"@stamina:minor": 3, "magic_dust": 3},
		"output_type": "rune",
		"target_slot": "armor,shield",
		"rune_stat": "stamina_bonus",
		"rune_tier": "minor",
		"rune_cap": 6,
		"craft_time": 3.0
	},
	"rune_minor_energy": {
		"name": "Minor Rune of Energy",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 5,
		"difficulty": 10,
		"materials": {"@energy:minor": 3, "magic_dust": 3},
		"output_type": "rune",
		"target_slot": "boots,ring",
		"rune_stat": "energy_bonus",
		"rune_tier": "minor",
		"rune_cap": 6,
		"craft_time": 3.0
	},
	"rune_minor_str": {
		"name": "Minor Rune of Strength",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 5,
		"difficulty": 10,
		"materials": {"@str:minor": 3, "magic_dust": 1, "enchanted_pollen": 1},
		"output_type": "rune",
		"target_slot": "weapon,armor,ring,amulet",
		"rune_stat": "str_bonus",
		"rune_tier": "minor",
		"rune_cap": 2,
		"craft_time": 3.0
	},
	"rune_minor_con": {
		"name": "Minor Rune of Constitution",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 5,
		"difficulty": 10,
		"materials": {"@con:minor": 3, "magic_dust": 1, "enchanted_pollen": 1},
		"output_type": "rune",
		"target_slot": "armor,shield,helm,amulet",
		"rune_stat": "con_bonus",
		"rune_tier": "minor",
		"rune_cap": 2,
		"craft_time": 3.0
	},
	"rune_minor_dex": {
		"name": "Minor Rune of Dexterity",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 5,
		"difficulty": 10,
		"materials": {"@dex:minor": 3, "magic_dust": 1, "enchanted_pollen": 1},
		"output_type": "rune",
		"target_slot": "weapon,boots,ring",
		"rune_stat": "dex_bonus",
		"rune_tier": "minor",
		"rune_cap": 2,
		"craft_time": 3.0
	},
	"rune_minor_int": {
		"name": "Minor Rune of Intellect",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 5,
		"difficulty": 10,
		"materials": {"@int:minor": 3, "magic_dust": 1, "enchanted_pollen": 1},
		"output_type": "rune",
		"target_slot": "weapon,helm,amulet,ring",
		"rune_stat": "int_bonus",
		"rune_tier": "minor",
		"rune_cap": 2,
		"craft_time": 3.0
	},
	"rune_minor_wis": {
		"name": "Minor Rune of Wisdom",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 5,
		"difficulty": 10,
		"materials": {"@wis:minor": 3, "magic_dust": 1, "enchanted_pollen": 1},
		"output_type": "rune",
		"target_slot": "helm,amulet,shield,ring",
		"rune_stat": "wis_bonus",
		"rune_tier": "minor",
		"rune_cap": 2,
		"craft_time": 3.0
	},
	"rune_minor_wits": {
		"name": "Minor Rune of Cunning",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 5,
		"difficulty": 10,
		"materials": {"@wits:minor": 3, "magic_dust": 1, "enchanted_pollen": 1},
		"output_type": "rune",
		"target_slot": "weapon,ring,amulet,boots",
		"rune_stat": "wits_bonus",
		"rune_tier": "minor",
		"rune_cap": 2,
		"craft_time": 3.0
	},
	# --- Greater Runes (Skill 30-35, T4-T6 monster parts) ---
	"rune_greater_attack": {
		"name": "Greater Rune of Attack",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 30,
		"difficulty": 40,
		"materials": {"@attack:greater": 4, "arcane_crystal": 2, "soul_shard": 1},
		"output_type": "rune",
		"target_slot": "weapon",
		"rune_stat": "attack_bonus",
		"rune_tier": "greater",
		"rune_cap": 30,
		"craft_time": 5.0
	},
	"rune_greater_defense": {
		"name": "Greater Rune of Defense",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 30,
		"difficulty": 40,
		"materials": {"@defense:greater": 4, "arcane_crystal": 2, "soul_shard": 1},
		"output_type": "rune",
		"target_slot": "armor,shield",
		"rune_stat": "defense_bonus",
		"rune_tier": "greater",
		"rune_cap": 30,
		"craft_time": 5.0
	},
	"rune_greater_hp": {
		"name": "Greater Rune of Vitality",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 30,
		"difficulty": 40,
		"materials": {"@hp:greater": 4, "arcane_crystal": 2, "soul_shard": 1},
		"output_type": "rune",
		"target_slot": "helm,armor,shield",
		"rune_stat": "hp_bonus",
		"rune_tier": "greater",
		"rune_cap": 80,
		"craft_time": 5.0
	},
	"rune_greater_speed": {
		"name": "Greater Rune of Speed",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 33,
		"difficulty": 43,
		"materials": {"@speed:greater": 4, "arcane_crystal": 2, "soul_shard": 1},
		"output_type": "rune",
		"target_slot": "boots",
		"rune_stat": "speed_bonus",
		"rune_tier": "greater",
		"rune_cap": 9,
		"craft_time": 5.0
	},
	"rune_greater_mana": {
		"name": "Greater Rune of Mana",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 33,
		"difficulty": 43,
		"materials": {"@mana:greater": 4, "arcane_crystal": 2, "giant_pearl": 1},
		"output_type": "rune",
		"target_slot": "amulet,ring",
		"rune_stat": "mana_bonus",
		"rune_tier": "greater",
		"rune_cap": 40,
		"craft_time": 5.0
	},
	"rune_greater_stamina": {
		"name": "Greater Rune of Stamina",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 33,
		"difficulty": 43,
		"materials": {"@stamina:greater": 4, "arcane_crystal": 2, "soul_shard": 1},
		"output_type": "rune",
		"target_slot": "armor,shield",
		"rune_stat": "stamina_bonus",
		"rune_tier": "greater",
		"rune_cap": 20,
		"craft_time": 5.0
	},
	"rune_greater_energy": {
		"name": "Greater Rune of Energy",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 33,
		"difficulty": 43,
		"materials": {"@energy:greater": 4, "arcane_crystal": 2, "soul_shard": 1},
		"output_type": "rune",
		"target_slot": "boots,ring",
		"rune_stat": "energy_bonus",
		"rune_tier": "greater",
		"rune_cap": 20,
		"craft_time": 5.0
	},
	"rune_greater_str": {
		"name": "Greater Rune of Strength",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 35,
		"difficulty": 45,
		"materials": {"@str:greater": 4, "arcane_crystal": 2, "monster_gem": 1},
		"output_type": "rune",
		"target_slot": "weapon,armor,ring,amulet",
		"rune_stat": "str_bonus",
		"rune_tier": "greater",
		"rune_cap": 8,
		"craft_time": 5.0
	},
	"rune_greater_con": {
		"name": "Greater Rune of Constitution",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 35,
		"difficulty": 45,
		"materials": {"@con:greater": 4, "arcane_crystal": 2},
		"output_type": "rune",
		"target_slot": "armor,shield,helm,amulet",
		"rune_stat": "con_bonus",
		"rune_tier": "greater",
		"rune_cap": 8,
		"craft_time": 5.0
	},
	"rune_greater_dex": {
		"name": "Greater Rune of Dexterity",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 35,
		"difficulty": 45,
		"materials": {"@dex:greater": 4, "arcane_crystal": 2},
		"output_type": "rune",
		"target_slot": "weapon,boots,ring",
		"rune_stat": "dex_bonus",
		"rune_tier": "greater",
		"rune_cap": 8,
		"craft_time": 5.0
	},
	"rune_greater_int": {
		"name": "Greater Rune of Intellect",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 35,
		"difficulty": 45,
		"materials": {"@int:greater": 4, "arcane_crystal": 2},
		"output_type": "rune",
		"target_slot": "weapon,helm,amulet,ring",
		"rune_stat": "int_bonus",
		"rune_tier": "greater",
		"rune_cap": 8,
		"craft_time": 5.0
	},
	"rune_greater_wis": {
		"name": "Greater Rune of Wisdom",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 35,
		"difficulty": 45,
		"materials": {"@wis:greater": 4, "arcane_crystal": 2},
		"output_type": "rune",
		"target_slot": "helm,amulet,shield,ring",
		"rune_stat": "wis_bonus",
		"rune_tier": "greater",
		"rune_cap": 8,
		"craft_time": 5.0
	},
	"rune_greater_wits": {
		"name": "Greater Rune of Cunning",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 35,
		"difficulty": 45,
		"materials": {"@wits:greater": 4, "arcane_crystal": 2},
		"output_type": "rune",
		"target_slot": "weapon,ring,amulet,boots",
		"rune_stat": "wits_bonus",
		"rune_tier": "greater",
		"rune_cap": 8,
		"craft_time": 5.0
	},

	# ===== UPGRADE RECIPES (replace merchant upgrades) =====
	# Weapon upgrades
	"weapon_upgrade_1": {
		"name": "Weapon Upgrade (+1)",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 5,
		"difficulty": 10,
		"materials": {"copper_ore": 2, "coal": 1},
		"output_type": "upgrade",
		"target_slot": "weapon",
		"effect": {"type": "upgrade_level", "levels": 1},
		"max_upgrades": 10,
		"craft_time": 2.0
	},
	"weapon_upgrade_5": {
		"name": "Weapon Upgrade (+5)",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 25,
		"difficulty": 35,
		"materials": {"iron_ore": 3, "steel_ore": 2, "coal": 2},
		"output_type": "upgrade",
		"target_slot": "weapon",
		"effect": {"type": "upgrade_level", "levels": 5},
		"max_upgrades": 30,
		"craft_time": 5.0
	},
	"weapon_upgrade_10": {
		"name": "Weapon Upgrade (+10)",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 50,
		"difficulty": 60,
		"materials": {"mithril_ore": 3, "adamantine_ore": 2, "magic_dust": 5},
		"output_type": "upgrade",
		"target_slot": "weapon",
		"effect": {"type": "upgrade_level", "levels": 10},
		"max_upgrades": 50,
		"craft_time": 8.0
	},

	# Armor upgrades
	"armor_upgrade_1": {
		"name": "Armor Upgrade (+1)",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 5,
		"difficulty": 10,
		"materials": {"copper_ore": 2, "ragged_leather": 1},
		"output_type": "upgrade",
		"target_slot": "armor",
		"effect": {"type": "upgrade_level", "levels": 1},
		"max_upgrades": 10,
		"craft_time": 2.0
	},
	"armor_upgrade_5": {
		"name": "Armor Upgrade (+5)",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 25,
		"difficulty": 35,
		"materials": {"iron_ore": 3, "steel_ore": 2, "thick_leather": 2},
		"output_type": "upgrade",
		"target_slot": "armor",
		"effect": {"type": "upgrade_level", "levels": 5},
		"max_upgrades": 30,
		"craft_time": 5.0
	},
	"armor_upgrade_10": {
		"name": "Armor Upgrade (+10)",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 50,
		"difficulty": 60,
		"materials": {"mithril_ore": 3, "enchanted_leather": 2, "magic_dust": 5},
		"output_type": "upgrade",
		"target_slot": "armor",
		"effect": {"type": "upgrade_level", "levels": 10},
		"max_upgrades": 50,
		"craft_time": 8.0
	},

	# Accessory upgrades (ring, amulet)
	"accessory_upgrade_1": {
		"name": "Accessory Upgrade (+1)",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 5,
		"difficulty": 10,
		"materials": {"rough_gem": 1, "magic_dust": 2},
		"output_type": "upgrade",
		"target_slot": "ring,amulet",
		"effect": {"type": "upgrade_level", "levels": 1},
		"max_upgrades": 10,
		"craft_time": 2.0
	},
	"accessory_upgrade_5": {
		"name": "Accessory Upgrade (+5)",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 25,
		"difficulty": 35,
		"materials": {"polished_gem": 2, "arcane_crystal": 2},
		"output_type": "upgrade",
		"target_slot": "ring,amulet",
		"effect": {"type": "upgrade_level", "levels": 5},
		"max_upgrades": 30,
		"craft_time": 5.0
	},
	"accessory_upgrade_10": {
		"name": "Accessory Upgrade (+10)",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 50,
		"difficulty": 60,
		"materials": {"flawless_gem": 2, "soul_shard": 2, "void_essence": 1},
		"output_type": "upgrade",
		"target_slot": "ring,amulet",
		"effect": {"type": "upgrade_level", "levels": 10},
		"max_upgrades": 50,
		"craft_time": 8.0
	},

	# ===== BLACKSMITH SPECIALIST RECIPES =====
	"self_repair": {
		"name": "Self Repair",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 15,
		"difficulty": 20,
		"materials": {"iron_ore": 2, "coal": 1},
		"output_type": "self_repair",
		"specialist_only": true,
		"craft_time": 3.0
	},
	"reforge_weapon": {
		"name": "Reforge Weapon",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 25,
		"difficulty": 35,
		"materials": {"steel_ore": 3, "coal": 2},
		"output_type": "reforge",
		"specialist_only": true,
		"reforge_slot": "weapon",
		"craft_time": 5.0
	},
	"reforge_armor": {
		"name": "Reforge Armor",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 30,
		"difficulty": 40,
		"materials": {"steel_ore": 4, "thick_leather": 2},
		"output_type": "reforge",
		"specialist_only": true,
		"reforge_slot": "armor",
		"craft_time": 5.0
	},
	"void_blade": {
		"name": "Void Blade",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 70,
		"difficulty": 80,
		"materials": {"void_ore": 8, "dragonhide": 3, "void_essence": 2},
		"output_type": "weapon",
		"output_slot": "weapon",
		"base_stats": {"attack": 180, "level": 70},
		"specialist_only": true,
		"craft_time": 8.0
	},
	"celestial_plate": {
		"name": "Celestial Plate",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 80,
		"difficulty": 90,
		"materials": {"celestial_ore": 10, "void_silk": 4, "primordial_spark": 1},
		"output_type": "armor",
		"output_slot": "armor",
		"base_stats": {"defense": 200, "level": 80},
		"specialist_only": true,
		"craft_time": 10.0
	},
	# Tier 7 - Void (specialist full set)
	"void_armor": {
		"name": "Void Armor",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 75,
		"difficulty": 85,
		"materials": {"void_ore": 12, "void_silk": 4, "void_essence": 3},
		"output_type": "armor",
		"output_slot": "armor",
		"base_stats": {"defense": 120, "hp": 250, "level": 70},
		"specialist_only": true,
		"craft_time": 9.0
	},
	"void_helm": {
		"name": "Void Helm",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 72,
		"difficulty": 82,
		"materials": {"void_ore": 8, "void_silk": 2, "void_essence": 2},
		"output_type": "armor",
		"output_slot": "helm",
		"base_stats": {"defense": 80, "hp": 200, "level": 70},
		"specialist_only": true,
		"craft_time": 8.0
	},
	"void_shield": {
		"name": "Void Shield",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 73,
		"difficulty": 83,
		"materials": {"void_ore": 10, "dragonhide": 3, "void_essence": 2},
		"output_type": "armor",
		"output_slot": "shield",
		"base_stats": {"defense": 100, "hp": 50, "level": 70},
		"specialist_only": true,
		"craft_time": 8.0
	},
	"void_boots": {
		"name": "Void Boots",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 72,
		"difficulty": 82,
		"materials": {"void_ore": 8, "void_silk": 3, "void_essence": 2},
		"output_type": "armor",
		"output_slot": "boots",
		"base_stats": {"defense": 70, "speed": 15, "level": 70},
		"specialist_only": true,
		"craft_time": 8.0
	},
	"void_ring": {
		"name": "Void Ring",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 78,
		"difficulty": 88,
		"materials": {"void_ore": 5, "primordial_spark": 1, "perfect_gem": 1},
		"output_type": "armor",
		"output_slot": "ring",
		"base_stats": {"defense": 25, "speed": 5, "level": 70},
		"specialist_only": true,
		"craft_time": 7.0
	},
	"void_amulet": {
		"name": "Void Amulet",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 78,
		"difficulty": 88,
		"materials": {"void_ore": 5, "void_silk": 2, "void_essence": 2},
		"output_type": "armor",
		"output_slot": "amulet",
		"base_stats": {"hp": 300, "mana": 80, "level": 70},
		"specialist_only": true,
		"craft_time": 7.0
	},
	# Tier 8 - Celestial (specialist full set)
	"celestial_blade": {
		"name": "Celestial Blade",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 85,
		"difficulty": 95,
		"materials": {"celestial_ore": 12, "void_silk": 3, "primordial_spark": 2},
		"output_type": "weapon",
		"output_slot": "weapon",
		"base_stats": {"attack": 250, "speed": 10, "level": 80},
		"specialist_only": true,
		"craft_time": 10.0
	},
	"celestial_helm": {
		"name": "Celestial Helm",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 82,
		"difficulty": 92,
		"materials": {"celestial_ore": 8, "void_silk": 2, "primordial_spark": 1},
		"output_type": "armor",
		"output_slot": "helm",
		"base_stats": {"defense": 130, "hp": 300, "level": 80},
		"specialist_only": true,
		"craft_time": 9.0
	},
	"celestial_shield": {
		"name": "Celestial Shield",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 83,
		"difficulty": 93,
		"materials": {"celestial_ore": 10, "void_silk": 3, "primordial_spark": 1},
		"output_type": "armor",
		"output_slot": "shield",
		"base_stats": {"defense": 150, "hp": 100, "level": 80},
		"specialist_only": true,
		"craft_time": 9.0
	},
	"celestial_boots": {
		"name": "Celestial Boots",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 82,
		"difficulty": 92,
		"materials": {"celestial_ore": 8, "void_silk": 3, "primordial_spark": 1},
		"output_type": "armor",
		"output_slot": "boots",
		"base_stats": {"defense": 100, "speed": 20, "level": 80},
		"specialist_only": true,
		"craft_time": 9.0
	},
	"celestial_ring": {
		"name": "Celestial Ring",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 88,
		"difficulty": 95,
		"materials": {"celestial_ore": 5, "primordial_spark": 2, "star_gem": 1},
		"output_type": "armor",
		"output_slot": "ring",
		"base_stats": {"defense": 40, "speed": 8, "level": 80},
		"specialist_only": true,
		"craft_time": 8.0
	},
	"celestial_amulet": {
		"name": "Celestial Amulet",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 88,
		"difficulty": 95,
		"materials": {"celestial_ore": 5, "void_silk": 2, "primordial_spark": 2},
		"output_type": "armor",
		"output_slot": "amulet",
		"base_stats": {"hp": 400, "mana": 120, "level": 80},
		"specialist_only": true,
		"craft_time": 8.0
	},
	# Tier 6 specialist ring/amulet
	"orichalcum_ring": {
		"name": "Orichalcum Ring",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 85,
		"difficulty": 90,
		"materials": {"orichalcum_ore": 5, "void_essence": 1, "star_gem": 1},
		"output_type": "armor",
		"output_slot": "ring",
		"base_stats": {"defense": 20, "speed": 5, "level": 150},
		"specialist_only": true,
		"craft_time": 6.0
	},
	"orichalcum_amulet": {
		"name": "Orichalcum Amulet",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 85,
		"difficulty": 90,
		"materials": {"orichalcum_ore": 5, "void_essence": 1, "sea_crystal": 1},
		"output_type": "armor",
		"output_slot": "amulet",
		"base_stats": {"hp": 225, "mana": 70, "level": 150},
		"specialist_only": true,
		"craft_time": 6.0
	},
	# Tier 9 - Primordial (specialist)
	"primordial_blade": {
		"name": "Primordial Blade",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 90,
		"difficulty": 98,
		"materials": {"primordial_ore": 15, "astral_weave": 3, "primordial_gem": 2},
		"output_type": "weapon",
		"output_slot": "weapon",
		"base_stats": {"attack": 320, "speed": 12, "level": 90},
		"specialist_only": true,
		"craft_time": 12.0
	},
	"primordial_plate": {
		"name": "Primordial Plate",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 90,
		"difficulty": 98,
		"materials": {"primordial_ore": 15, "astral_weave": 4, "primordial_gem": 1},
		"output_type": "armor",
		"output_slot": "armor",
		"base_stats": {"defense": 260, "hp": 400, "level": 90},
		"specialist_only": true,
		"craft_time": 12.0
	},

	# ===== ALCHEMIST SPECIALIST RECIPES =====
	"transmute_ore_up": {
		"name": "Transmute Ore Up",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 15,
		"difficulty": 20,
		"materials": {},
		"output_type": "transmute",
		"specialist_only": true,
		"transmute_type": "ore",
		"craft_time": 3.0
	},
	"transmute_herb_up": {
		"name": "Transmute Herb Up",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 15,
		"difficulty": 20,
		"materials": {},
		"output_type": "transmute",
		"specialist_only": true,
		"transmute_type": "herb",
		"craft_time": 3.0
	},
	"extract_essence": {
		"name": "Extract Essence",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 20,
		"difficulty": 25,
		"materials": {"magic_dust": 1},
		"output_type": "extract",
		"specialist_only": true,
		"craft_time": 3.0
	},
	"elixir_of_power": {
		"name": "Elixir of Power",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 40,
		"difficulty": 50,
		"materials": {"phoenix_petal": 2, "dragon_blood": 1},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "buff", "stat": "attack_defense", "bonus_pct": 25, "duration_battles": 5},
		"specialist_only": true,
		"craft_time": 5.0
	},
	"potion_of_insight": {
		"name": "Potion of Insight",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 50,
		"difficulty": 60,
		"materials": {"phoenix_petal": 3, "void_spore": 2},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "buff", "stat": "xp_bonus", "bonus_pct": 15, "duration_battles": 10},
		"specialist_only": true,
		"craft_time": 6.0
	},
	"elixir_of_luck": {
		"name": "Elixir of Luck",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 55,
		"difficulty": 65,
		"materials": {"four_leaf_clover": 5, "starbloom": 3},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "buff", "stat": "rare_drop", "bonus_pct": 10, "duration_battles": 5},
		"specialist_only": true,
		"craft_time": 6.0
	},
	# Bane Potions (specialist-only, rare materials)
	"dragon_bane_potion": {
		"name": "Dragon Bane Potion",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 60,
		"difficulty": 70,
		"materials": {"dragon_blood": 3, "phoenix_petal": 2, "void_essence": 1},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "bane", "monster_type": "dragon", "bonus_pct": 50, "duration_battles": 3},
		"specialist_only": true,
		"craft_time": 6.0
	},
	"undead_bane_potion": {
		"name": "Undead Bane Potion",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 60,
		"difficulty": 70,
		"materials": {"soul_shard": 3, "healing_herb": 5, "magic_dust": 3},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "bane", "monster_type": "undead", "bonus_pct": 50, "duration_battles": 3},
		"specialist_only": true,
		"craft_time": 6.0
	},
	"beast_bane_potion": {
		"name": "Beast Bane Potion",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 60,
		"difficulty": 70,
		"materials": {"thick_leather": 3, "wyvern_leather": 2, "bloodroot": 3},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "bane", "monster_type": "beast", "bonus_pct": 50, "duration_battles": 3},
		"specialist_only": true,
		"craft_time": 6.0
	},
	"demon_bane_potion": {
		"name": "Demon Bane Potion",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 65,
		"difficulty": 75,
		"materials": {"void_essence": 2, "phoenix_petal": 3, "primordial_spark": 1},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "bane", "monster_type": "demon", "bonus_pct": 50, "duration_battles": 3},
		"specialist_only": true,
		"craft_time": 7.0
	},
	"elemental_bane_potion": {
		"name": "Elemental Bane Potion",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 60,
		"difficulty": 70,
		"materials": {"arcane_crystal": 3, "mana_blossom": 5, "void_essence": 1},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "bane", "monster_type": "elemental", "bonus_pct": 50, "duration_battles": 3},
		"specialist_only": true,
		"craft_time": 6.0
	},
	# Elixir of Rejuvenation (50% max HP heal)
	"elixir_of_rejuvenation": {
		"name": "Elixir of Rejuvenation",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 70,
		"difficulty": 80,
		"materials": {"essence_of_life": 2, "celestial_petal": 2, "dragon_blood": 2},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "heal_pct", "amount": 50},
		"specialist_only": true,
		"craft_time": 7.0
	},
	# New alchemy recipes — unused materials integration
	"potion_of_resilience": {
		"name": "Potion of Resilience",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 25,
		"difficulty": 30,
		"materials": {"cave_mushroom": 3, "bark": 2, "healing_herb": 2},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "buff", "stat": "defense", "amount": 10, "duration": 10},
		"craft_time": 3.0
	},
	"heartwood_salve": {
		"name": "Heartwood Salve",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 35,
		"difficulty": 40,
		"materials": {"heartwood_seed": 2, "spirit_blossom": 2, "healing_herb": 3},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "heal", "amount": 300},
		"specialist_only": true,
		"craft_time": 4.0
	},
	"deep_sea_tonic": {
		"name": "Deep Sea Tonic",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 45,
		"difficulty": 50,
		"materials": {"deep_sea_fish": 3, "abyssal_crab": 2, "arcane_crystal": 1},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "heal", "amount": 600},
		"craft_time": 4.0
	},
	"prismatic_elixir": {
		"name": "Prismatic Elixir",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 55,
		"difficulty": 65,
		"materials": {"prismatic_fish": 3, "celestial_petal": 2, "void_essence": 1},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "buff", "stat": "attack_defense", "bonus_pct": 20, "duration_battles": 8},
		"specialist_only": true,
		"craft_time": 6.0
	},
	"elixir_of_the_ancients": {
		"name": "Elixir of the Ancients",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 75,
		"difficulty": 85,
		"materials": {"ancient_relic": 2, "worldtree_seed": 2, "dragon_blood": 2},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "buff", "stat": "xp_bonus", "bonus_pct": 25, "duration_battles": 8},
		"specialist_only": true,
		"craft_time": 8.0
	},
	"voidpetal_elixir": {
		"name": "Voidpetal Elixir",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 70,
		"difficulty": 80,
		"materials": {"voidpetal": 4, "void_blossom": 2, "essence_of_life": 1},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "heal_pct", "amount": 40},
		"specialist_only": true,
		"craft_time": 7.0
	},
	"primordial_tonic": {
		"name": "Primordial Tonic",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 80,
		"difficulty": 90,
		"materials": {"primordial_fungus": 3, "creation_seed": 1, "essence_of_life": 2},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "heal_pct", "amount": 70},
		"specialist_only": true,
		"craft_time": 8.0
	},

	# ===== ENCHANTER SPECIALIST RECIPES =====
	"disenchant_item": {
		"name": "Disenchant Item",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 15,
		"difficulty": 20,
		"materials": {"magic_dust": 2},
		"output_type": "disenchant",
		"specialist_only": true,
		"craft_time": 3.0
	},
	"cut_rough_gem": {
		"name": "Cut Rough Gem",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 20,
		"difficulty": 25,
		"materials": {"rough_gem": 2},
		"output_type": "material",
		"output_item": "polished_gem",
		"output_quantity": 1,
		"specialist_only": true,
		"craft_time": 3.0
	},
	"cut_polished_gem": {
		"name": "Cut Polished Gem",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 40,
		"difficulty": 50,
		"materials": {"polished_gem": 2},
		"output_type": "material",
		"output_item": "flawless_gem",
		"output_quantity": 1,
		"specialist_only": true,
		"craft_time": 4.0
	},
	"cut_flawless_gem": {
		"name": "Cut Flawless Gem",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 60,
		"difficulty": 70,
		"materials": {"flawless_gem": 2},
		"output_type": "material",
		"output_item": "perfect_gem",
		"output_quantity": 1,
		"specialist_only": true,
		"craft_time": 5.0
	},
	# --- Supreme Runes (Skill 60-65, T7-T9 monster parts, specialist_only) ---
	"rune_supreme_attack": {
		"name": "Supreme Rune of Attack",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 60,
		"difficulty": 70,
		"materials": {"@attack:supreme": 5, "void_essence": 2, "primordial_spark": 1},
		"output_type": "rune",
		"target_slot": "weapon",
		"rune_stat": "attack_bonus",
		"rune_tier": "supreme",
		"rune_cap": 60,
		"specialist_only": true,
		"craft_time": 8.0
	},
	"rune_supreme_defense": {
		"name": "Supreme Rune of Defense",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 60,
		"difficulty": 70,
		"materials": {"@defense:supreme": 5, "void_essence": 2, "celestial_hide": 1},
		"output_type": "rune",
		"target_slot": "armor,shield",
		"rune_stat": "defense_bonus",
		"rune_tier": "supreme",
		"rune_cap": 60,
		"specialist_only": true,
		"craft_time": 8.0
	},
	"rune_supreme_hp": {
		"name": "Supreme Rune of Vitality",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 60,
		"difficulty": 70,
		"materials": {"@hp:supreme": 5, "void_essence": 2, "primordial_spark": 1},
		"output_type": "rune",
		"target_slot": "helm,armor,shield",
		"rune_stat": "hp_bonus",
		"rune_tier": "supreme",
		"rune_cap": 180,
		"specialist_only": true,
		"craft_time": 8.0
	},
	"rune_supreme_speed": {
		"name": "Supreme Rune of Speed",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 63,
		"difficulty": 73,
		"materials": {"@speed:supreme": 5, "void_essence": 2, "primordial_spark": 1},
		"output_type": "rune",
		"target_slot": "boots",
		"rune_stat": "speed_bonus",
		"rune_tier": "supreme",
		"rune_cap": 20,
		"specialist_only": true,
		"craft_time": 8.0
	},
	"rune_supreme_mana": {
		"name": "Supreme Rune of Mana",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 63,
		"difficulty": 73,
		"materials": {"@mana:supreme": 5, "void_essence": 2, "primordial_spark": 1},
		"output_type": "rune",
		"target_slot": "amulet,ring",
		"rune_stat": "mana_bonus",
		"rune_tier": "supreme",
		"rune_cap": 100,
		"specialist_only": true,
		"craft_time": 8.0
	},
	"rune_supreme_stamina": {
		"name": "Supreme Rune of Stamina",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 63,
		"difficulty": 73,
		"materials": {"@stamina:supreme": 5, "void_essence": 2, "primordial_spark": 1},
		"output_type": "rune",
		"target_slot": "armor,shield",
		"rune_stat": "stamina_bonus",
		"rune_tier": "supreme",
		"rune_cap": 45,
		"specialist_only": true,
		"craft_time": 8.0
	},
	"rune_supreme_energy": {
		"name": "Supreme Rune of Energy",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 63,
		"difficulty": 73,
		"materials": {"@energy:supreme": 5, "void_essence": 2, "primordial_spark": 1},
		"output_type": "rune",
		"target_slot": "boots,ring",
		"rune_stat": "energy_bonus",
		"rune_tier": "supreme",
		"rune_cap": 45,
		"specialist_only": true,
		"craft_time": 8.0
	},
	"rune_supreme_str": {
		"name": "Supreme Rune of Strength",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 65,
		"difficulty": 75,
		"materials": {"@str:supreme": 5, "void_essence": 2, "celestial_shard": 1},
		"output_type": "rune",
		"target_slot": "weapon,armor,ring,amulet",
		"rune_stat": "str_bonus",
		"rune_tier": "supreme",
		"rune_cap": 16,
		"specialist_only": true,
		"craft_time": 8.0
	},
	"rune_supreme_con": {
		"name": "Supreme Rune of Constitution",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 65,
		"difficulty": 75,
		"materials": {"@con:supreme": 5, "void_essence": 2, "celestial_shard": 1},
		"output_type": "rune",
		"target_slot": "armor,shield,helm,amulet",
		"rune_stat": "con_bonus",
		"rune_tier": "supreme",
		"rune_cap": 16,
		"specialist_only": true,
		"craft_time": 8.0
	},
	"rune_supreme_dex": {
		"name": "Supreme Rune of Dexterity",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 65,
		"difficulty": 75,
		"materials": {"@dex:supreme": 5, "void_essence": 2, "celestial_shard": 1},
		"output_type": "rune",
		"target_slot": "weapon,boots,ring",
		"rune_stat": "dex_bonus",
		"rune_tier": "supreme",
		"rune_cap": 16,
		"specialist_only": true,
		"craft_time": 8.0
	},
	"rune_supreme_int": {
		"name": "Supreme Rune of Intellect",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 65,
		"difficulty": 75,
		"materials": {"@int:supreme": 5, "void_essence": 2},
		"output_type": "rune",
		"target_slot": "weapon,helm,amulet,ring",
		"rune_stat": "int_bonus",
		"rune_tier": "supreme",
		"rune_cap": 16,
		"specialist_only": true,
		"craft_time": 8.0
	},
	"rune_supreme_wis": {
		"name": "Supreme Rune of Wisdom",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 65,
		"difficulty": 75,
		"materials": {"@wis:supreme": 5, "void_essence": 2},
		"output_type": "rune",
		"target_slot": "helm,amulet,shield,ring",
		"rune_stat": "wis_bonus",
		"rune_tier": "supreme",
		"rune_cap": 16,
		"specialist_only": true,
		"craft_time": 8.0
	},
	"rune_supreme_wits": {
		"name": "Supreme Rune of Cunning",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 65,
		"difficulty": 75,
		"materials": {"@wits:supreme": 5, "void_essence": 2},
		"output_type": "rune",
		"target_slot": "weapon,ring,amulet,boots",
		"rune_stat": "wits_bonus",
		"rune_tier": "supreme",
		"rune_cap": 16,
		"specialist_only": true,
		"craft_time": 8.0
	},
	# --- Proc Runes (Skill 75-80, specialist_only) ---
	"rune_lifesteal": {
		"name": "Rune of Lifesteal",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 75,
		"difficulty": 88,
		"materials": {"vampire_dust": 5, "void_essence": 3, "primordial_spark": 1},
		"output_type": "rune",
		"target_slot": "weapon",
		"rune_proc": "lifesteal",
		"rune_proc_value": 10,
		"rune_proc_chance": 1.0,
		"specialist_only": true,
		"craft_time": 10.0
	},
	"rune_shocking": {
		"name": "Rune of Shocking",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 75,
		"difficulty": 88,
		"materials": {"elemental_spark": 5, "void_essence": 3, "primordial_spark": 1},
		"output_type": "rune",
		"target_slot": "weapon",
		"rune_proc": "shocking",
		"rune_proc_value": 15,
		"rune_proc_chance": 0.25,
		"specialist_only": true,
		"craft_time": 10.0
	},
	"rune_reflect": {
		"name": "Rune of Damage Reflect",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 75,
		"difficulty": 88,
		"materials": {"gargoyle_core": 5, "void_essence": 3, "primordial_spark": 1},
		"output_type": "rune",
		"target_slot": "armor,shield",
		"rune_proc": "damage_reflect",
		"rune_proc_value": 15,
		"rune_proc_chance": 1.0,
		"specialist_only": true,
		"craft_time": 10.0
	},
	"rune_execute": {
		"name": "Rune of Execute",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 80,
		"difficulty": 92,
		"materials": {"death_incarnate_soul_shard": 5, "void_essence": 3, "primordial_spark": 2},
		"output_type": "rune",
		"target_slot": "weapon",
		"rune_proc": "execute",
		"rune_proc_value": 50,
		"rune_proc_chance": 0.25,
		"specialist_only": true,
		"craft_time": 10.0
	},
	"cut_celestial_gem": {
		"name": "Cut Celestial Gem",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 75,
		"difficulty": 85,
		"materials": {"perfect_gem": 2, "celestial_gem": 1},
		"output_type": "material",
		"output_item": "star_gem",
		"output_quantity": 1,
		"specialist_only": true,
		"craft_time": 6.0
	},

	# ===== SCRIBING RECIPES =====
	# Basic (everyone, skill_required <= 10)
	"craft_parchment": {
		"name": "Craft Parchment",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 1,
		"difficulty": 5,
		"materials": {"reed_fiber": 3, "sap": 1},
		"output_type": "material",
		"output_item": "parchment",
		"output_quantity": 2,
		"craft_time": 2.0
	},
	"craft_ink": {
		"name": "Craft Ink",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 1,
		"difficulty": 5,
		"materials": {"coal": 2, "common_mushroom": 1},
		"output_type": "material",
		"output_item": "ink",
		"output_quantity": 2,
		"craft_time": 2.0
	},
	"scroll_of_rage": {
		"name": "Scroll of Rage",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 3,
		"difficulty": 10,
		"materials": {"parchment": 1, "ink": 1, "vigor_root": 1},
		"output_type": "scroll",
		"effect": {"type": "buff", "stat": "attack", "bonus_pct": 20, "duration_battles": 3},
		"craft_time": 3.0
	},
	"scroll_of_stone_skin": {
		"name": "Scroll of Stone Skin",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 5,
		"difficulty": 15,
		"materials": {"parchment": 1, "ink": 1, "stone": 3},
		"output_type": "scroll",
		"effect": {"type": "buff", "stat": "defense", "bonus_pct": 20, "duration_battles": 3},
		"craft_time": 3.0
	},
	"scroll_of_haste": {
		"name": "Scroll of Haste",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 8,
		"difficulty": 20,
		"materials": {"parchment": 2, "ink": 1, "mana_blossom": 1},
		"output_type": "scroll",
		"effect": {"type": "buff", "stat": "speed", "bonus_pct": 25, "duration_battles": 3},
		"craft_time": 3.0
	},
	"scroll_of_forcefield": {
		"name": "Scroll of Forcefield",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 10,
		"difficulty": 25,
		"materials": {"parchment": 2, "ink": 2, "arcane_crystal": 1},
		"output_type": "scroll",
		"effect": {"type": "buff", "stat": "shield", "amount": 200, "duration_battles": 3},
		"craft_time": 4.0
	},

	# Scribe specialist-only (skill_required > 10)
	"craft_fine_parchment": {
		"name": "Craft Fine Parchment",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 15,
		"difficulty": 20,
		"materials": {"parchment": 3, "enchanted_resin": 1},
		"output_type": "material",
		"output_item": "fine_parchment",
		"output_quantity": 2,
		"specialist_only": true,
		"craft_time": 3.0
	},
	"craft_arcane_ink": {
		"name": "Craft Arcane Ink",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 15,
		"difficulty": 20,
		"materials": {"ink": 2, "arcane_moss": 1, "arcane_crystal": 1},
		"output_type": "material",
		"output_item": "arcane_ink",
		"output_quantity": 2,
		"specialist_only": true,
		"craft_time": 3.0
	},
	"craft_binding_thread": {
		"name": "Craft Binding Thread",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 10,
		"difficulty": 15,
		"materials": {"reed_fiber": 5, "sap": 2},
		"output_type": "material",
		"output_item": "binding_thread",
		"output_quantity": 2,
		"craft_time": 2.0
	},
	"scroll_of_precision": {
		"name": "Scroll of Precision",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 12,
		"difficulty": 25,
		"materials": {"parchment": 2, "ink": 2, "sage": 1},
		"output_type": "scroll",
		"effect": {"type": "buff", "stat": "crit_chance", "bonus_pct": 15, "duration_battles": 5},
		"specialist_only": true,
		"craft_time": 4.0
	},
	"scroll_of_vampirism": {
		"name": "Scroll of Vampirism",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 18,
		"difficulty": 30,
		"materials": {"fine_parchment": 1, "ink": 2, "nightmare_cap": 1},
		"output_type": "scroll",
		"effect": {"type": "buff", "stat": "lifesteal", "bonus_pct": 10, "duration_battles": 5},
		"specialist_only": true,
		"craft_time": 4.0
	},
	"scroll_of_weakness": {
		"name": "Scroll of Weakness",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 22,
		"difficulty": 35,
		"materials": {"fine_parchment": 1, "arcane_ink": 1, "shadowleaf": 2},
		"output_type": "scroll",
		"effect": {"type": "debuff", "stat": "monster_attack", "penalty_pct": 20, "duration_battles": 3},
		"specialist_only": true,
		"craft_time": 4.0
	},
	"craft_vellum": {
		"name": "Craft Vellum",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 30,
		"difficulty": 40,
		"materials": {"fine_parchment": 3, "dragonhide": 1},
		"output_type": "material",
		"output_item": "vellum",
		"output_quantity": 2,
		"specialist_only": true,
		"craft_time": 4.0
	},
	"craft_void_ink": {
		"name": "Craft Void Ink",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 45,
		"difficulty": 55,
		"materials": {"arcane_ink": 2, "kraken_ink": 2},
		"output_type": "material",
		"output_item": "void_ink",
		"output_quantity": 2,
		"specialist_only": true,
		"craft_time": 5.0
	},
	"area_map_small": {
		"name": "Area Map (Small)",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 15,
		"difficulty": 20,
		"materials": {"parchment": 3, "ink": 2},
		"output_type": "map",
		"effect": {"reveal_radius": 50},
		"specialist_only": true,
		"craft_time": 4.0
	},
	"area_map_large": {
		"name": "Area Map (Large)",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 35,
		"difficulty": 45,
		"materials": {"fine_parchment": 3, "arcane_ink": 2},
		"output_type": "map",
		"effect": {"reveal_radius": 150},
		"specialist_only": true,
		"craft_time": 6.0
	},
	"bestiary_page": {
		"name": "Bestiary Page",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 20,
		"difficulty": 30,
		"materials": {"fine_parchment": 2, "ink": 3, "magic_dust": 1},
		"output_type": "bestiary",
		"specialist_only": true,
		"craft_time": 4.0
	},
	"spell_tome_str": {
		"name": "Spell Tome: Strength",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 50,
		"difficulty": 65,
		"materials": {"vellum": 3, "void_ink": 2, "primordial_spark": 1},
		"output_type": "tome",
		"effect": {"stat": "strength", "amount": 1},
		"specialist_only": true,
		"craft_time": 8.0
	},
	"spell_tome_int": {
		"name": "Spell Tome: Intelligence",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 50,
		"difficulty": 65,
		"materials": {"vellum": 3, "void_ink": 2, "primordial_spark": 1},
		"output_type": "tome",
		"effect": {"stat": "intelligence", "amount": 1},
		"specialist_only": true,
		"craft_time": 8.0
	},
	"spell_tome_dex": {
		"name": "Spell Tome: Dexterity",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 50,
		"difficulty": 65,
		"materials": {"vellum": 3, "void_ink": 2, "primordial_spark": 1},
		"output_type": "tome",
		"effect": {"stat": "dexterity", "amount": 1},
		"specialist_only": true,
		"craft_time": 8.0
	},
	"spell_tome_con": {
		"name": "Spell Tome: Constitution",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 50,
		"difficulty": 65,
		"materials": {"vellum": 3, "void_ink": 2, "primordial_spark": 1},
		"output_type": "tome",
		"effect": {"stat": "constitution", "amount": 1},
		"specialist_only": true,
		"craft_time": 8.0
	},
	"scroll_of_time_stop": {
		"name": "Scroll of Time Stop",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 60,
		"difficulty": 75,
		"materials": {"vellum": 2, "void_ink": 2, "void_essence": 2},
		"output_type": "scroll",
		"effect": {"type": "buff", "stat": "time_stop", "duration_battles": 1},
		"specialist_only": true,
		"craft_time": 8.0
	},
	# Missing Buff Scrolls
	"scroll_of_thorns": {
		"name": "Scroll of Thorns",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 25,
		"difficulty": 32,
		"materials": {"fine_parchment": 1, "arcane_ink": 1, "thornberry": 3},
		"output_type": "scroll",
		"effect": {"type": "buff", "stat": "thorns", "amount": 8, "duration_battles": 3},
		"specialist_only": true,
		"craft_time": 4.0
	},
	# Missing Debuff Scrolls
	"scroll_of_vulnerability": {
		"name": "Scroll of Vulnerability",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 25,
		"difficulty": 32,
		"materials": {"fine_parchment": 1, "arcane_ink": 1, "arcane_crystal": 1},
		"output_type": "scroll",
		"effect": {"type": "debuff", "stat": "monster_defense", "debuff_pct": 20, "duration_battles": 3},
		"specialist_only": true,
		"craft_time": 4.0
	},
	"scroll_of_slow": {
		"name": "Scroll of Slow",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 28,
		"difficulty": 35,
		"materials": {"fine_parchment": 2, "arcane_ink": 1, "sage": 3},
		"output_type": "scroll",
		"effect": {"type": "debuff", "stat": "monster_speed", "debuff_pct": 20, "duration_battles": 3},
		"specialist_only": true,
		"craft_time": 4.0
	},
	"scroll_of_doom": {
		"name": "Scroll of Doom",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 45,
		"difficulty": 58,
		"materials": {"vellum": 1, "void_ink": 1, "void_spore": 2},
		"output_type": "scroll",
		"effect": {"type": "debuff", "stat": "doom", "amount": 10, "duration_battles": 2},
		"specialist_only": true,
		"craft_time": 6.0
	},
	# Special Scrolls
	"scroll_of_monster_select": {
		"name": "Scroll of Monster Select",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 35,
		"difficulty": 45,
		"materials": {"fine_parchment": 2, "arcane_ink": 2, "soul_shard": 1},
		"output_type": "scroll",
		"effect": {"type": "special", "stat": "monster_select", "duration_battles": 1},
		"specialist_only": true,
		"craft_time": 5.0
	},
	"scroll_of_target_farm": {
		"name": "Scroll of Target Farm",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 50,
		"difficulty": 62,
		"materials": {"vellum": 2, "void_ink": 1, "soul_shard": 2},
		"output_type": "scroll",
		"effect": {"type": "special", "stat": "target_farm", "duration_battles": 5},
		"specialist_only": true,
		"craft_time": 6.0
	},
	# Resurrection Scrolls (very expensive)
	"scroll_of_lesser_resurrect": {
		"name": "Scroll of Lesser Resurrection",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 70,
		"difficulty": 85,
		"materials": {"vellum": 3, "void_ink": 3, "essence_of_life": 2, "primordial_spark": 1},
		"output_type": "scroll",
		"effect": {"type": "buff", "stat": "resurrect", "amount": 25, "duration_battles": 1},
		"specialist_only": true,
		"craft_time": 10.0
	},
	"scroll_of_greater_resurrect": {
		"name": "Scroll of Greater Resurrection",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 85,
		"difficulty": 95,
		"materials": {"vellum": 5, "void_ink": 5, "essence_of_life": 3, "primordial_spark": 2},
		"output_type": "scroll",
		"effect": {"type": "buff", "stat": "resurrect", "amount": 50, "duration_battles": -1},
		"specialist_only": true,
		"craft_time": 12.0
	},
	# Missing Spell Tomes (WIS, WITS)
	"spell_tome_wis": {
		"name": "Spell Tome: Wisdom",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 50,
		"difficulty": 65,
		"materials": {"vellum": 3, "void_ink": 2, "primordial_spark": 1},
		"output_type": "tome",
		"effect": {"stat": "wisdom", "amount": 1},
		"specialist_only": true,
		"craft_time": 8.0
	},
	"spell_tome_wits": {
		"name": "Spell Tome: Wits",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 50,
		"difficulty": 65,
		"materials": {"vellum": 3, "void_ink": 2, "primordial_spark": 1},
		"output_type": "tome",
		"effect": {"stat": "wits", "amount": 1},
		"specialist_only": true,
		"craft_time": 8.0
	},
	# New scribing recipes — unused materials integration
	"scroll_of_sea_ward": {
		"name": "Scroll of Sea Ward",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 40,
		"difficulty": 50,
		"materials": {"fine_parchment": 2, "arcane_ink": 2, "leviathan_scale": 1},
		"output_type": "scroll",
		"effect": {"type": "buff", "stat": "shield", "amount": 500, "duration_battles": 3},
		"specialist_only": true,
		"craft_time": 5.0
	},
	"scroll_of_dragon_fury": {
		"name": "Scroll of Dragon Fury",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 40,
		"difficulty": 50,
		"materials": {"fine_parchment": 2, "arcane_ink": 2, "sea_dragon_fang": 1},
		"output_type": "scroll",
		"effect": {"type": "buff", "stat": "attack", "bonus_pct": 30, "duration_battles": 3},
		"specialist_only": true,
		"craft_time": 5.0
	},
	"craft_kraken_ink": {
		"name": "Craft Kraken Ink",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 35,
		"difficulty": 45,
		"materials": {"kraken_ink": 2, "arcane_ink": 1},
		"output_type": "material",
		"output_item": "void_ink",
		"output_quantity": 3,
		"specialist_only": true,
		"craft_time": 4.0
	},
	"worldtree_tome": {
		"name": "Worldtree Tome: Constitution",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 60,
		"difficulty": 75,
		"materials": {"vellum": 3, "void_ink": 2, "worldtree_heartwood": 2, "worldtree_seed": 1},
		"output_type": "tome",
		"effect": {"stat": "constitution", "amount": 2},
		"specialist_only": true,
		"craft_time": 10.0
	},

	# ===== CONSTRUCTION RECIPES =====
	# Basic (everyone)
	"craft_wooden_plank": {
		"name": "Wooden Plank",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 1,
		"difficulty": 3,
		"materials": {"common_wood": 3},
		"output_type": "material",
		"output_item": "wooden_plank",
		"output_quantity": 2,
		"craft_time": 1.5
	},
	"craft_rope": {
		"name": "Rope",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 1,
		"difficulty": 3,
		"materials": {"reed_fiber": 4},
		"output_type": "material",
		"output_item": "rope",
		"output_quantity": 2,
		"craft_time": 1.5
	},
	"craft_stone_block": {
		"name": "Stone Block",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 1,
		"difficulty": 5,
		"materials": {"stone": 3},
		"output_type": "material",
		"output_item": "stone_block",
		"output_quantity": 2,
		"craft_time": 2.0
	},
	"craft_stone_wall": {
		"name": "Stone Wall",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 3,
		"difficulty": 8,
		"materials": {"stone_block": 3},
		"output_type": "structure",
		"structure_type": "wall",
		"craft_time": 3.0
	},
	"craft_wooden_bridge": {
		"name": "Wooden Bridge",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 3,
		"difficulty": 8,
		"materials": {"wooden_plank": 4, "rope": 2},
		"output_type": "structure",
		"structure_type": "bridge",
		"craft_time": 3.0,
		"description": "Place over water to create a crossing. Anyone can build this."
	},
	"craft_workbench": {
		"name": "Workbench",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 5,
		"difficulty": 10,
		"materials": {"wooden_plank": 5, "stone_block": 3},
		"output_type": "structure",
		"structure_type": "workbench",
		"craft_time": 4.0
	},
	# Building-template kits — drop a fixed layout in one press. Recipe cost
	# is roughly equivalent to crafting the equivalent loose tiles plus a
	# small convenience tax. See KIT_LAYOUTS in server.gd for the layout.
	"craft_enclosure_kit_small": {
		"name": "Small Enclosure Kit",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 8,
		"difficulty": 18,
		"materials": {"stone_block": 32, "wooden_plank": 4, "iron_ore": 2},
		"output_type": "structure",
		"structure_type": "enclosure_kit_small",
		"specialist_only": true,
		"craft_time": 8.0,
		"description": "Places a 5x5 walled enclosure with a south-facing door, centered on you. Anchors a settler post with one press."
	},

	# Builder specialist-only
	"craft_door": {
		"name": "Wooden Door",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 5,
		"difficulty": 12,
		"materials": {"wooden_plank": 4, "iron_ore": 2},
		"output_type": "structure",
		"structure_type": "door",
		"specialist_only": true,
		"craft_time": 3.0
	},
	"portable_forge": {
		"name": "Portable Forge",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 15,
		"difficulty": 30,
		"materials": {"iron_ore": 10, "stone_block": 8, "coal": 5},
		"output_type": "structure",
		"structure_type": "forge",
		"specialist_only": true,
		"craft_time": 5.0
	},
	"alchemy_lab": {
		"name": "Alchemy Lab",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 15,
		"difficulty": 30,
		"materials": {"wooden_plank": 5, "healing_herb": 5, "stone_block": 3},
		"output_type": "structure",
		"structure_type": "apothecary",
		"specialist_only": true,
		"craft_time": 5.0
	},
	"enchanting_table": {
		"name": "Enchanting Table",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 15,
		"difficulty": 30,
		"materials": {"arcane_crystal": 3, "wooden_plank": 4, "magic_dust": 5},
		"output_type": "structure",
		"structure_type": "enchant_table",
		"specialist_only": true,
		"craft_time": 5.0
	},
	"writing_desk_build": {
		"name": "Writing Desk",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 15,
		"difficulty": 30,
		"materials": {"wooden_plank": 4, "ink": 3, "binding_thread": 2},
		"output_type": "structure",
		"structure_type": "writing_desk",
		"specialist_only": true,
		"craft_time": 5.0
	},
	"guard_post": {
		"name": "Guard Post",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 15,
		"difficulty": 25,
		"materials": {"stone_block": 3, "wooden_plank": 2, "iron_ore": 2},
		"output_type": "structure",
		"structure_type": "guard",
		"specialist_only": true,
		"craft_time": 4.0,
		"description": "A post where a guard can be stationed. Hire a guard to suppress nearby encounters."
	},
	"watch_tower": {
		"name": "Watch Tower",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 25,
		"difficulty": 40,
		"materials": {"steel_ore": 6, "heartwood": 3, "wooden_plank": 4, "stone_block": 5},
		"output_type": "structure",
		"structure_type": "tower",
		"specialist_only": true,
		"craft_time": 7.0
	},
	"travelers_inn": {
		"name": "Traveler's Inn",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 30,
		"difficulty": 45,
		"materials": {"wooden_plank": 8, "rope": 5, "heartwood": 2},
		"output_type": "structure",
		"structure_type": "inn",
		"specialist_only": true,
		"craft_time": 8.0
	},
	"quest_board_build": {
		"name": "Quest Board",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 35,
		"difficulty": 50,
		"materials": {"wooden_plank": 4, "fine_parchment": 3, "arcane_ink": 2},
		"output_type": "structure",
		"structure_type": "quest_board",
		"specialist_only": true,
		"craft_time": 7.0
	},
	"storage_chest": {
		"name": "Storage Chest",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 20,
		"difficulty": 35,
		"materials": {"wooden_plank": 4, "iron_ore": 5},
		"output_type": "structure",
		"structure_type": "storage",
		"specialist_only": true,
		"craft_time": 5.0
	},
	"upgrade_post": {
		"name": "Upgrade Post",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 45,
		"difficulty": 60,
		"materials": {"mithril_ore": 5, "wooden_plank": 5, "stone_block": 5},
		"output_type": "structure",
		"structure_type": "upgrade",
		"specialist_only": true,
		"craft_time": 8.0
	},
	"blacksmith_anvil": {
		"name": "Blacksmith Anvil",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 20,
		"difficulty": 35,
		"materials": {"iron_ore": 8, "stone_block": 5, "coal": 3},
		"output_type": "structure",
		"structure_type": "blacksmith",
		"specialist_only": true,
		"craft_time": 6.0
	},
	"healer_shrine": {
		"name": "Healer's Shrine",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 25,
		"difficulty": 40,
		"materials": {"stone_block": 6, "healing_herb": 8, "magic_dust": 3},
		"output_type": "structure",
		"structure_type": "healer",
		"specialist_only": true,
		"craft_time": 6.0
	},
	# Audit #12 Slice 6 (v0.9.505) — cosmetic structures for post variety.
	# Walkable (don't block movement) so they're decoration without claiming
	# tactical tiles. No specialty lock-in — low skill_required so any
	# Construction-trained player can build them.
	"banner_build": {
		"name": "Banner",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 12,
		"difficulty": 18,
		"materials": {"wooden_plank": 2, "leather": 2, "rope": 1},
		"output_type": "structure",
		"structure_type": "banner",
		"specialist_only": false,
		"craft_time": 2.5,
		"description": "A walkable banner pole that flies your colors over your settlement. Pure cosmetic — marks territory."
	},
	"lamp_post_build": {
		"name": "Lamp Post",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 15,
		"difficulty": 22,
		"materials": {"iron_ore": 2, "wooden_plank": 1, "magic_dust": 1},
		"output_type": "structure",
		"structure_type": "lamp_post",
		"specialist_only": false,
		"craft_time": 3.0,
		"description": "A glowing lamp post. Walkable, decorative. Marks paths and adds warmth to a settlement."
	},
	"torch_build": {
		"name": "Torch",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 8,
		"difficulty": 12,
		"materials": {"wooden_plank": 1, "magic_dust": 1, "rope": 1},
		"output_type": "structure",
		"structure_type": "torch",
		"specialist_only": false,
		"craft_time": 2.0,
		"description": "A small mounted torch. Walkable, casts a warm glow. The entry-level light source for your settlement."
	},
	"statue_build": {
		"name": "Statue",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 25,
		"difficulty": 35,
		"materials": {"stone_block": 6, "magic_dust": 1, "heartwood": 1},
		"output_type": "structure",
		"structure_type": "statue",
		"specialist_only": false,
		"craft_time": 5.0,
		"description": "A marble monument. Blocks movement — place as a centerpiece or memorial in your settlement."
	},
	"signpost_build": {
		"name": "Signpost",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 10,
		"difficulty": 15,
		"materials": {"wooden_plank": 3, "ink": 1, "rope": 1},
		"output_type": "structure",
		"structure_type": "signpost",
		"specialist_only": false,
		"craft_time": 2.5,
		"description": "A wooden signpost with carved letters. Bump into it to read; bump as the owner to edit the text (60 chars max). Useful for marking landmarks, telling travelers your post's purpose, or leaving messages."
	},
	# Audit #12 v0.9.515 — two more cosmetic Construction recipes. Brazier fills
	# the gap between Torch (skill 8) and Lamp Post (skill 15); Fountain is a
	# blocking centerpiece companion to Statue but cheaper at the iron/crystal
	# level.
	"brazier_build": {
		"name": "Brazier",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 13,
		"difficulty": 18,
		"materials": {"iron_ore": 2, "wooden_plank": 1, "magic_dust": 2},
		"output_type": "structure",
		"structure_type": "brazier",
		"specialist_only": false,
		"craft_time": 2.5,
		"description": "A standing iron brazier with a steady flame. Walkable. Mid-tier light source between Torch and Lamp Post."
	},
	"fountain_build": {
		"name": "Fountain",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 22,
		"difficulty": 30,
		"materials": {"stone_block": 4, "magic_dust": 2, "arcane_crystal": 1},
		"output_type": "structure",
		"structure_type": "fountain",
		"specialist_only": false,
		"craft_time": 4.5,
		"description": "A sculpted stone fountain. Blocks movement — place as a centerpiece in your settlement plaza."
	},
	# Audit #12 v0.9.516 — two more cosmetic Construction recipes. Bench is the
	# cheapest entry-level decoration anyone with even basic Construction can
	# afford. Well is mid-tier blocking centerpiece — sits below Fountain in cost.
	"bench_build": {
		"name": "Bench",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 6,
		"difficulty": 10,
		"materials": {"wooden_plank": 2, "rope": 1},
		"output_type": "structure",
		"structure_type": "bench",
		"specialist_only": false,
		"craft_time": 1.5,
		"description": "A simple wooden bench. Walkable. The cheapest entry-level decoration — anyone with even basic Construction skill can build one."
	},
	"well_build": {
		"name": "Well",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 18,
		"difficulty": 24,
		"materials": {"stone_block": 3, "wooden_plank": 1, "rope": 2},
		"output_type": "structure",
		"structure_type": "well",
		"specialist_only": false,
		"craft_time": 4.0,
		"description": "A round stone well with a rope-and-bucket draw. Blocks movement — evokes a settlement's communal water source."
	},
	# Audit #12 v0.9.520 — two more cosmetic recipes. Pylon is a mid-tier
	# wayfinding marker; Garden Plot is the cheapest decorative greenery.
	"pylon_build": {
		"name": "Pylon",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 11,
		"difficulty": 15,
		"materials": {"stone_block": 2, "magic_dust": 1},
		"output_type": "structure",
		"structure_type": "pylon",
		"specialist_only": false,
		"craft_time": 2.0,
		"description": "A pale stone pylon humming with faint arcane light. Walkable. Use it as a wayfinding marker or boundary stone."
	},
	"garden_plot_build": {
		"name": "Garden Plot",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 4,
		"difficulty": 8,
		"materials": {"wooden_plank": 1, "herb": 2},
		"output_type": "structure",
		"structure_type": "garden_plot",
		"specialist_only": false,
		"craft_time": 1.5,
		"description": "A tended patch of herbs and wildflowers. Walkable. The cheapest decoration — soothing greenery for your settlement."
	},
	# Audit #12 v0.9.521 — Tent (blocking) + Scarecrow (walkable).
	"tent_build": {
		"name": "Tent",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 7,
		"difficulty": 11,
		"materials": {"wooden_plank": 1, "leather": 3, "rope": 2},
		"output_type": "structure",
		"structure_type": "tent",
		"specialist_only": false,
		"craft_time": 2.0,
		"description": "A small leather travel tent. Blocks movement — create camping pockets inside your enclosure to break up sightlines."
	},
	"scarecrow_build": {
		"name": "Scarecrow",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 5,
		"difficulty": 8,
		"materials": {"wooden_plank": 2, "rope": 1, "herb": 1},
		"output_type": "structure",
		"structure_type": "scarecrow",
		"specialist_only": false,
		"craft_time": 1.5,
		"description": "A straw-stuffed sentinel watching over your garden. Walkable. Cheap, distinctive, slightly unsettling."
	},
	# Audit #12 v0.9.527 — two more cosmetic Construction recipes. Crate is a
	# blocking storage prop at mid-cheap skill; Cairn is the new cheapest entry
	# tier (skill 3) — even more entry-level than Garden Plot.
	"crate_build": {
		"name": "Crate",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 9,
		"difficulty": 13,
		"materials": {"wooden_plank": 3, "iron_ore": 1, "rope": 1},
		"output_type": "structure",
		"structure_type": "crate",
		"specialist_only": false,
		"craft_time": 2.0,
		"description": "A sturdy wooden storage crate. Blocks movement — stack a few to form makeshift barricades or mark a depot inside your enclosure."
	},
	"cairn_build": {
		"name": "Cairn",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 3,
		"difficulty": 6,
		"materials": {"stone_block": 3},
		"output_type": "structure",
		"structure_type": "cairn",
		"specialist_only": false,
		"craft_time": 1.0,
		"description": "A balanced pile of waystones. Walkable. The cheapest cosmetic — three stone blocks and a steady hand. Marks paths, boundaries, or memorials."
	},
	# Audit #12 v0.9.531 — two more cosmetic Construction recipes. Pedestal is
	# a polished marble display block (mid-tier blocking centerpiece); Cage is
	# a wrought-iron cage prop slightly higher skill.
	"pedestal_build": {
		"name": "Pedestal",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 14,
		"difficulty": 19,
		"materials": {"stone_block": 3, "magic_dust": 1},
		"output_type": "structure",
		"structure_type": "pedestal",
		"specialist_only": false,
		"craft_time": 2.5,
		"description": "A polished marble display pedestal. Blocks movement — place a few in your hall as plinths for trophies, monuments, or memorial markers."
	},
	"cage_build": {
		"name": "Cage",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 16,
		"difficulty": 22,
		"materials": {"iron_ore": 3, "wooden_plank": 1, "rope": 1},
		"output_type": "structure",
		"structure_type": "cage",
		"specialist_only": false,
		"craft_time": 3.0,
		"description": "A wrought-iron cage on a wooden frame. Blocks movement — decorative menagerie prop or aesthetic detention motif for your settlement."
	},
	# Audit #12 v0.9.533 — two more cosmetic Construction recipes. Hedge is a
	# soft-wall blocker (movement + line-of-sight) at low-mid skill; Shrine is
	# a high-skill gilded prestige centerpiece, blocking but eye-catching.
	"hedge_build": {
		"name": "Hedge",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 8,
		"difficulty": 12,
		"materials": {"wooden_plank": 1, "herb": 3, "rope": 1},
		"output_type": "structure",
		"structure_type": "hedge",
		"specialist_only": false,
		"craft_time": 2.0,
		"description": "A trimmed leafy hedge section. Blocks movement and line-of-sight — use it as a soft wall to break up sightlines without the harsh look of stone."
	},
	"shrine_build": {
		"name": "Shrine",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 19,
		"difficulty": 26,
		"materials": {"stone_block": 3, "magic_dust": 2, "arcane_crystal": 1, "heartwood": 1},
		"output_type": "structure",
		"structure_type": "shrine",
		"specialist_only": false,
		"craft_time": 4.0,
		"description": "A small gilded shrine etched with sigils. Blocks movement — a prestige centerpiece. Sits between Well (skill 18) and Fountain (22) in the high-tier blocking lineup."
	},
	# Audit #12 v0.9.534 — two more cosmetic Construction recipes. Lectern is a
	# scholarly blocking prop at mid-skill; Mosaic is the first walkable floor
	# decoration in the catalogue — purely visual, no movement/LOS effect.
	"lectern_build": {
		"name": "Lectern",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 12,
		"difficulty": 17,
		"materials": {"wooden_plank": 2, "ink": 1, "leather": 1},
		"output_type": "structure",
		"structure_type": "lectern",
		"specialist_only": false,
		"craft_time": 2.0,
		"description": "A wooden reading lectern with a scribed tome. Blocks movement — scholarly flavor for libraries, scribe halls, or sermon platforms inside your settlement."
	},
	"mosaic_build": {
		"name": "Mosaic",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 17,
		"difficulty": 23,
		"materials": {"stone_block": 3, "magic_dust": 1, "ink": 1},
		"output_type": "structure",
		"structure_type": "mosaic",
		"specialist_only": false,
		"craft_time": 3.0,
		"description": "An ornate floor mosaic of stone tesserae bound with arcane pigment. WALKABLE — the first floor decoration in the catalogue. Place a few in a row for a grand entryway path."
	},
	# Audit #12 v0.9.535 — two more cosmetic Construction recipes. Easel is a
	# cheap artistic blocking prop; Totem is a tall painted pillar (tribal /
	# folk aesthetic, mid-skill blocking).
	"easel_build": {
		"name": "Easel",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 6,
		"difficulty": 10,
		"materials": {"wooden_plank": 2, "ink": 1},
		"output_type": "structure",
		"structure_type": "easel",
		"specialist_only": false,
		"craft_time": 1.5,
		"description": "A wooden artist's easel holding a half-finished painting. Blocks movement. Low-cost flavor prop for studios, galleries, or scholarly corners."
	},
	"totem_build": {
		"name": "Totem",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 13,
		"difficulty": 18,
		"materials": {"wooden_plank": 3, "ink": 2, "leather": 1},
		"output_type": "structure",
		"structure_type": "totem",
		"specialist_only": false,
		"craft_time": 2.5,
		"description": "A tall painted totem carved with spirit faces. Blocks movement — tribal / folk aesthetic. Place a row along a settlement boundary for ceremonial flair."
	},
	# Audit #4 Slice 1A.ii (v0.9.500) — Player-built Companion Stable. Bumps
	# open the same Companion Stable UI as the NPC-post Stable (deposit /
	# withdraw / return-to-slot / check-out + 4 fusion modes). Lets players
	# get Sanctuary kennel access at their own settlement without relying on
	# a T5+ NPC post nearby. Skill 35 places this in the "high-value mid-game
	# structure" tier alongside quest_board / market_stall — significant
	# investment but reachable before the endgame.
	"companion_stable_build": {
		"name": "Companion Stable",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 35,
		"difficulty": 50,
		"materials": {"wooden_plank": 8, "iron_ore": 4, "heartwood": 2, "arcane_crystal": 2, "magic_dust": 3},
		"output_type": "structure",
		"structure_type": "companion_stable",
		"specialist_only": true,
		"craft_time": 7.0,
		"description": "A pet-keeper's outpost. Bump-interact to open your Sanctuary's kennel and fusion station — deposit, withdraw, register, and fuse companions without traveling to an NPC post."
	},
	"market_stall": {
		"name": "Market Stall",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 30,
		"difficulty": 45,
		"materials": {"wooden_plank": 8, "iron_ore": 4, "rope": 3},
		"output_type": "structure",
		"structure_type": "market",
		"specialist_only": true,
		"craft_time": 7.0
	},
	# New construction recipes — unused materials integration
	"elderwood_gatehouse": {
		"name": "Elderwood Gatehouse",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 40,
		"difficulty": 55,
		"materials": {"elderwood": 6, "stone_block": 5, "iron_ore": 4},
		"output_type": "structure",
		"structure_type": "door",
		"specialist_only": true,
		"craft_time": 8.0
	},
	"worldtree_outpost": {
		"name": "Worldtree Outpost",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 55,
		"difficulty": 70,
		"materials": {"worldtree_heartwood": 4, "elderwood": 4, "stone_block": 6, "void_essence": 2},
		"output_type": "structure",
		"structure_type": "tower",
		"specialist_only": true,
		"craft_time": 10.0
	},
	"creation_garden": {
		"name": "Creation Garden",
		"skill": CraftingSkill.CONSTRUCTION,
		"skill_required": 60,
		"difficulty": 75,
		"materials": {"creation_seed": 2, "worldtree_heartwood": 2, "stone_block": 4, "primordial_spark": 1},
		"output_type": "structure",
		"structure_type": "healer",
		"specialist_only": true,
		"craft_time": 10.0
	},

	# ===== ESCAPE SCROLLS (Scribing) =====
	"scroll_of_escape": {
		"name": "Scroll of Escape",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 8,
		"difficulty": 15,
		"materials": {"parchment": 2, "ink": 1, "moonpetal": 1},
		"output_type": "escape_scroll",
		"tier_max": 4,
		"craft_time": 3.0
	},
	"scroll_of_greater_escape": {
		"name": "Scroll of Greater Escape",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 16,
		"difficulty": 30,
		"materials": {"fine_parchment": 2, "arcane_ink": 1, "soul_shard": 1},
		"output_type": "escape_scroll",
		"tier_max": 7,
		"specialist_only": true,
		"craft_time": 4.0
	},
	"scroll_of_supreme_escape": {
		"name": "Scroll of Supreme Escape",
		"skill": CraftingSkill.SCRIBING,
		"skill_required": 24,
		"difficulty": 45,
		"materials": {"fine_parchment": 2, "arcane_ink": 1, "void_crystal": 1},
		"output_type": "escape_scroll",
		"tier_max": 9,
		"specialist_only": true,
		"craft_time": 5.0
	},

	# ===== DUNGEON-EXCLUSIVE CRYSTAL RECIPES =====
	# Enchanter: Mythic runes using dungeon crystals
	"void_rune": {
		"name": "Void Rune",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 25,
		"difficulty": 40,
		"materials": {"void_crystal": 2, "primordial_spark": 1},
		"output_type": "enchantment",
		"enchant_stat": "attack",
		"enchant_amount": 45,
		"specialist_only": true,
		"craft_time": 5.0
	},
	"abyssal_rune": {
		"name": "Abyssal Rune",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 30,
		"difficulty": 50,
		"materials": {"abyssal_shard": 2, "void_crystal": 1},
		"output_type": "enchantment",
		"enchant_stat": "defense",
		"enchant_amount": 50,
		"specialist_only": true,
		"craft_time": 6.0
	},
	"primordial_rune": {
		"name": "Primordial Rune",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 35,
		"difficulty": 60,
		"materials": {"primordial_essence": 2, "abyssal_shard": 1},
		"output_type": "enchantment",
		"enchant_stat": "max_hp",
		"enchant_amount": 180,
		"specialist_only": true,
		"craft_time": 7.0
	},

	# Blacksmith: Legendary upgrade using dungeon crystals
	"primordial_upgrade": {
		"name": "Primordial Upgrade (+10)",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 30,
		"difficulty": 55,
		"materials": {"primordial_essence": 1, "primordial_ore": 3},
		"output_type": "upgrade",
		"upgrade_amount": 10,
		"specialist_only": true,
		"craft_time": 6.0
	},

	# Alchemist: Endgame elixirs using dungeon crystals
	"elixir_of_the_void": {
		"name": "Elixir of the Void",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 28,
		"difficulty": 45,
		"materials": {"void_crystal": 1, "starbloom": 2, "essence_of_life": 1},
		"output_type": "consumable",
		"effect": {"type": "buff", "stat": "all_stats", "bonus_pct": 15, "duration_battles": 5},
		"specialist_only": true,
		"craft_time": 5.0
	},
	"elixir_of_the_abyss": {
		"name": "Elixir of the Abyss",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 32,
		"difficulty": 55,
		"materials": {"abyssal_shard": 1, "bloodthorn": 2, "primordial_spark": 1},
		"output_type": "consumable",
		"effect": {"type": "buff", "stat": "attack", "bonus_pct": 30, "duration_battles": 5},
		"specialist_only": true,
		"craft_time": 6.0
	},
}

# ===== GATHERING TOOLS =====
# Tools that improve gathering efficiency - equipped via inventory
const GATHERING_TOOLS = {
	# ===== FISHING RODS =====
	"wooden_fishing_rod": {
		"name": "Wooden Fishing Rod",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 1,
		"difficulty": 5,
		"materials": {"common_wood": 5, "sap": 2},
		"output_type": "tool",
		"tool_type": "fishing_rod",
		"bonuses": {"yield_bonus": 0, "speed_bonus": 0.0, "tier_bonus": 0},
		"tier": 1,
		"craft_time": 2.0
	},
	"bamboo_fishing_rod": {
		"name": "Bamboo Fishing Rod",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 15,
		"difficulty": 20,
		"materials": {"oak_wood": 6, "sap": 4, "seaweed": 3},
		"output_type": "tool",
		"tool_type": "fishing_rod",
		"bonuses": {"yield_bonus": 1, "speed_bonus": 0.1, "tier_bonus": 0},
		"tier": 2,
		"craft_time": 3.0
	},
	"reinforced_fishing_rod": {
		"name": "Reinforced Fishing Rod",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 30,
		"difficulty": 35,
		"materials": {"ash_wood": 5, "iron_ore": 3, "magic_kelp": 2},
		"output_type": "tool",
		"tool_type": "fishing_rod",
		"bonuses": {"yield_bonus": 1, "speed_bonus": 0.15, "tier_bonus": 1},
		"tier": 3,
		"craft_time": 4.0
	},
	"mithril_fishing_rod": {
		"name": "Mithril Fishing Rod",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 50,
		"difficulty": 55,
		"materials": {"ironwood": 4, "mithril_ore": 5, "freshwater_pearl": 3, "arcane_crystal": 1},
		"output_type": "tool",
		"tool_type": "fishing_rod",
		"bonuses": {"yield_bonus": 2, "speed_bonus": 0.2, "tier_bonus": 1},
		"tier": 4,
		"craft_time": 6.0
	},
	"masterwork_fishing_rod": {
		"name": "Masterwork Fishing Rod",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 70,
		"difficulty": 75,
		"materials": {"darkwood": 4, "adamantine_ore": 3, "black_pearl": 1, "void_essence": 1},
		"output_type": "tool",
		"tool_type": "fishing_rod",
		"bonuses": {"yield_bonus": 3, "speed_bonus": 0.25, "tier_bonus": 2},
		"tier": 5,
		"craft_time": 8.0
	},

	# ===== PICKAXES =====
	"stone_pickaxe": {
		"name": "Stone Pickaxe",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 1,
		"difficulty": 5,
		"materials": {"stone": 5, "common_wood": 3},
		"output_type": "tool",
		"tool_type": "pickaxe",
		"bonuses": {"yield_bonus": 0, "speed_bonus": 0.0, "tier_bonus": 0},
		"tier": 1,
		"craft_time": 2.0
	},
	"copper_pickaxe": {
		"name": "Copper Pickaxe",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 10,
		"difficulty": 15,
		"materials": {"copper_ore": 6, "oak_wood": 3},
		"output_type": "tool",
		"tool_type": "pickaxe",
		"bonuses": {"yield_bonus": 1, "speed_bonus": 0.1, "tier_bonus": 0},
		"tier": 2,
		"craft_time": 3.0
	},
	"iron_pickaxe": {
		"name": "Iron Pickaxe",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 25,
		"difficulty": 30,
		"materials": {"iron_ore": 8, "ash_wood": 3, "coal": 3},
		"output_type": "tool",
		"tool_type": "pickaxe",
		"bonuses": {"yield_bonus": 1, "speed_bonus": 0.15, "tier_bonus": 1},
		"tier": 3,
		"craft_time": 4.0
	},
	"steel_pickaxe": {
		"name": "Steel Pickaxe",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 40,
		"difficulty": 45,
		"materials": {"steel_ore": 8, "ironwood": 3, "coal": 5},
		"output_type": "tool",
		"tool_type": "pickaxe",
		"bonuses": {"yield_bonus": 2, "speed_bonus": 0.2, "tier_bonus": 1},
		"tier": 4,
		"craft_time": 5.0
	},
	"mithril_pickaxe": {
		"name": "Mithril Pickaxe",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 55,
		"difficulty": 60,
		"materials": {"mithril_ore": 10, "darkwood": 3, "flawless_gem": 1},
		"output_type": "tool",
		"tool_type": "pickaxe",
		"bonuses": {"yield_bonus": 2, "speed_bonus": 0.25, "tier_bonus": 2},
		"tier": 5,
		"craft_time": 6.0
	},
	"adamantine_pickaxe": {
		"name": "Adamantine Pickaxe",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 70,
		"difficulty": 75,
		"materials": {"adamantine_ore": 10, "worldtree_branch": 2, "perfect_gem": 1, "arcane_crystal": 2},
		"output_type": "tool",
		"tool_type": "pickaxe",
		"bonuses": {"yield_bonus": 3, "speed_bonus": 0.3, "tier_bonus": 2},
		"tier": 6,
		"craft_time": 8.0
	},

	# ===== AXES =====
	"stone_axe": {
		"name": "Stone Axe",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 1,
		"difficulty": 5,
		"materials": {"stone": 5, "common_wood": 3},
		"output_type": "tool",
		"tool_type": "axe",
		"bonuses": {"yield_bonus": 0, "speed_bonus": 0.0, "tier_bonus": 0},
		"tier": 1,
		"craft_time": 2.0
	},
	"copper_axe": {
		"name": "Copper Axe",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 10,
		"difficulty": 15,
		"materials": {"copper_ore": 6, "oak_wood": 3},
		"output_type": "tool",
		"tool_type": "axe",
		"bonuses": {"yield_bonus": 1, "speed_bonus": 0.1, "tier_bonus": 0},
		"tier": 2,
		"craft_time": 3.0
	},
	"iron_axe": {
		"name": "Iron Axe",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 25,
		"difficulty": 30,
		"materials": {"iron_ore": 8, "ash_wood": 3, "ragged_leather": 2},
		"output_type": "tool",
		"tool_type": "axe",
		"bonuses": {"yield_bonus": 1, "speed_bonus": 0.15, "tier_bonus": 1},
		"tier": 3,
		"craft_time": 4.0
	},
	"steel_axe": {
		"name": "Steel Axe",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 40,
		"difficulty": 45,
		"materials": {"steel_ore": 8, "ironwood": 3, "thick_leather": 2},
		"output_type": "tool",
		"tool_type": "axe",
		"bonuses": {"yield_bonus": 2, "speed_bonus": 0.2, "tier_bonus": 1},
		"tier": 4,
		"craft_time": 5.0
	},
	"mithril_axe": {
		"name": "Mithril Axe",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 55,
		"difficulty": 60,
		"materials": {"mithril_ore": 10, "darkwood": 3, "enchanted_leather": 2},
		"output_type": "tool",
		"tool_type": "axe",
		"bonuses": {"yield_bonus": 2, "speed_bonus": 0.25, "tier_bonus": 2},
		"tier": 5,
		"craft_time": 6.0
	},
	"adamantine_axe": {
		"name": "Adamantine Axe",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 70,
		"difficulty": 75,
		"materials": {"adamantine_ore": 10, "worldtree_branch": 2, "dragonhide": 1, "arcane_crystal": 2},
		"output_type": "tool",
		"tool_type": "axe",
		"bonuses": {"yield_bonus": 3, "speed_bonus": 0.3, "tier_bonus": 2},
		"tier": 6,
		"craft_time": 8.0
	},

	# ===== SICKLES =====
	"stone_sickle": {
		"name": "Stone Sickle",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 1,
		"difficulty": 5,
		"materials": {"stone": 4, "common_wood": 3},
		"output_type": "tool",
		"tool_type": "sickle",
		"bonuses": {"yield_bonus": 0, "speed_bonus": 0.0, "tier_bonus": 0},
		"tier": 1,
		"craft_time": 2.0
	},
	"copper_sickle": {
		"name": "Copper Sickle",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 10,
		"difficulty": 15,
		"materials": {"copper_ore": 5, "oak_wood": 2, "sap": 2},
		"output_type": "tool",
		"tool_type": "sickle",
		"bonuses": {"yield_bonus": 1, "speed_bonus": 0.1, "tier_bonus": 0},
		"tier": 2,
		"craft_time": 3.0
	},
	"iron_sickle": {
		"name": "Iron Sickle",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 25,
		"difficulty": 30,
		"materials": {"iron_ore": 7, "ash_wood": 2, "binding_thread": 2},
		"output_type": "tool",
		"tool_type": "sickle",
		"bonuses": {"yield_bonus": 1, "speed_bonus": 0.15, "tier_bonus": 1},
		"tier": 3,
		"craft_time": 4.0
	},
	"steel_sickle": {
		"name": "Steel Sickle",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 40,
		"difficulty": 45,
		"materials": {"steel_ore": 7, "ironwood": 2, "enchanted_leather": 1},
		"output_type": "tool",
		"tool_type": "sickle",
		"bonuses": {"yield_bonus": 2, "speed_bonus": 0.2, "tier_bonus": 1},
		"tier": 4,
		"craft_time": 5.0
	},
	"mithril_sickle": {
		"name": "Mithril Sickle",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 55,
		"difficulty": 60,
		"materials": {"mithril_ore": 8, "darkwood": 2, "phoenix_petal": 1},
		"output_type": "tool",
		"tool_type": "sickle",
		"bonuses": {"yield_bonus": 2, "speed_bonus": 0.25, "tier_bonus": 2},
		"tier": 5,
		"craft_time": 6.0
	},
	"adamantine_sickle": {
		"name": "Adamantine Sickle",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 70,
		"difficulty": 75,
		"materials": {"adamantine_ore": 8, "worldtree_branch": 1, "starbloom": 2, "arcane_crystal": 1},
		"output_type": "tool",
		"tool_type": "sickle",
		"bonuses": {"yield_bonus": 3, "speed_bonus": 0.3, "tier_bonus": 2},
		"tier": 6,
		"craft_time": 8.0
	},
}

# Trading post specializations (bonus to success chance)
const TRADING_POST_SPECIALIZATIONS = {
	"haven": {"blacksmithing": 5, "alchemy": 0, "enchanting": 0},
	"crossroads": {"blacksmithing": 0, "alchemy": 5, "enchanting": 0},
	"frostgate": {"blacksmithing": 10, "alchemy": 0, "enchanting": 0},
	"eastwatch": {"blacksmithing": 0, "alchemy": 0, "enchanting": 10},
	"south_gate": {"blacksmithing": 0, "alchemy": 10, "enchanting": 0},
	"west_shrine": {"blacksmithing": 0, "alchemy": 0, "enchanting": 15},
	"fire_mountain": {"blacksmithing": 20, "alchemy": 0, "enchanting": 0},
}

# ===== HELPER FUNCTIONS =====

static func get_skill_name(skill: CraftingSkill) -> String:
	match skill:
		CraftingSkill.BLACKSMITHING:
			return "blacksmithing"
		CraftingSkill.ALCHEMY:
			return "alchemy"
		CraftingSkill.ENCHANTING:
			return "enchanting"
		CraftingSkill.SCRIBING:
			return "scribing"
		CraftingSkill.CONSTRUCTION:
			return "construction"
		_:
			return "unknown"

static func get_skill_display_name(skill: CraftingSkill) -> String:
	match skill:
		CraftingSkill.BLACKSMITHING:
			return "Blacksmithing"
		CraftingSkill.ALCHEMY:
			return "Alchemy"
		CraftingSkill.ENCHANTING:
			return "Enchanting"
		CraftingSkill.SCRIBING:
			return "Scribing"
		CraftingSkill.CONSTRUCTION:
			return "Construction"
		_:
			return "Unknown"

static func get_skill_enum(skill_name: String) -> int:
	match skill_name.to_lower():
		"blacksmithing": return CraftingSkill.BLACKSMITHING
		"alchemy": return CraftingSkill.ALCHEMY
		"enchanting": return CraftingSkill.ENCHANTING
		"scribing": return CraftingSkill.SCRIBING
		"construction": return CraftingSkill.CONSTRUCTION
		_: return -1

# Recipe discovery threshold — recipes at or above this difficulty require a recipe scroll
# to learn before they can be crafted. Lower-difficulty recipes are always available.
const RECIPE_DISCOVERY_DIFFICULTY = 50

static func requires_discovery(recipe_id: String) -> bool:
	"""Check if a recipe must be discovered (via recipe scroll) before it can be crafted.
	Specialist-only recipes do NOT require discovery — the job commitment IS the gate."""
	var recipe = RECIPES.get(recipe_id, GATHERING_TOOLS.get(recipe_id, {}))
	if recipe.is_empty():
		return false
	if recipe.get("specialist_only", false):
		return false
	return recipe.get("difficulty", 0) >= RECIPE_DISCOVERY_DIFFICULTY

static func get_discoverable_recipes_for_tier(tier: int) -> Array:
	"""Get recipe IDs that require discovery and match a dungeon/loot tier.
	Tier roughly maps to recipe difficulty brackets."""
	var tier_difficulty_min = 40 + (tier - 1) * 8  # T1=40, T3=56, T5=72, T9=104
	var tier_difficulty_max = tier_difficulty_min + 15
	var result = []
	for recipe_id in RECIPES:
		var recipe = RECIPES[recipe_id]
		var diff = recipe.get("difficulty", 0)
		if diff >= RECIPE_DISCOVERY_DIFFICULTY and diff >= tier_difficulty_min and diff <= tier_difficulty_max:
			if not recipe.get("specialist_only", false):
				result.append(recipe_id)
	return result

static func get_recipe(recipe_id: String) -> Dictionary:
	return RECIPES.get(recipe_id, {})

static func get_tool(tool_id: String) -> Dictionary:
	"""Get a gathering tool by its ID"""
	return GATHERING_TOOLS.get(tool_id, {})

static func get_tools_for_type(tool_type: String, skill_level: int = 100) -> Array:
	"""Get all gathering tools of a specific type (fishing_rod, pickaxe, axe) available at skill level"""
	var result = []
	for tool_id in GATHERING_TOOLS:
		var tool = GATHERING_TOOLS[tool_id]
		if tool.tool_type == tool_type and tool.skill_required <= skill_level:
			result.append({"id": tool_id, "data": tool})
	result.sort_custom(func(a, b): return a.data.tier < b.data.tier)
	return result

static func get_material(material_id: String) -> Dictionary:
	return MATERIALS.get(material_id, {})

static func get_material_name(material_id: String) -> String:
	if material_id.begins_with("@"):
		var parts = material_id.replace("@", "").split(":")
		var stat_group = parts[0]
		var tier_group = parts[1] if parts.size() > 1 else "minor"
		var display = PART_GROUP_DISPLAY.get(stat_group, stat_group)
		var tier_range = RUNE_TIER_RANGES.get(tier_group, [1, 9])
		return "%s (T%d-T%d)" % [display, tier_range[0], tier_range[1]]
	var mat = MATERIALS.get(material_id, {})
	return mat.get("name", material_id.replace("_", " ").capitalize())

static func get_recipes_for_skill(skill: CraftingSkill) -> Array:
	"""Get all recipes for a specific skill (includes regular recipes and gathering tools)"""
	var result = []
	# Add regular recipes
	for recipe_id in RECIPES:
		if RECIPES[recipe_id].skill == skill:
			result.append({"id": recipe_id, "data": RECIPES[recipe_id]})
	# Add gathering tools (all are blacksmithing)
	if skill == CraftingSkill.BLACKSMITHING:
		for tool_id in GATHERING_TOOLS:
			result.append({"id": tool_id, "data": GATHERING_TOOLS[tool_id]})
	# Sort by skill_required
	result.sort_custom(func(a, b): return a.data.skill_required < b.data.skill_required)
	return result

static func get_available_recipes(skill: CraftingSkill, skill_level: int) -> Array:
	"""Get recipes the player can craft at their current skill level"""
	var result = []
	for recipe_id in RECIPES:
		var recipe = RECIPES[recipe_id]
		if recipe.skill == skill and recipe.skill_required <= skill_level:
			result.append({"id": recipe_id, "data": recipe})
	result.sort_custom(func(a, b): return a.data.skill_required < b.data.skill_required)
	return result

static func calculate_success_chance(skill_level: int, difficulty: int, post_bonus: int = 0, minigame_score: int = -1) -> int:
	"""Calculate base success chance (0-100). minigame_score: 0-3 from crafting challenge, -1 = legacy (no minigame)."""
	var base: int
	if minigame_score >= 0:
		# New formula: 35 base + score * 15
		base = 35 + (skill_level - difficulty) * 2 + post_bonus + (minigame_score * 15)
	else:
		# Legacy formula (instant craft)
		base = 50 + (skill_level - difficulty) * 2 + post_bonus
	return clampi(base, 5, 95)  # Always 5-95% chance

static func roll_quality(skill_level: int, difficulty: int, post_bonus: int = 0, minigame_score: int = -1, quality_shift: Dictionary = {}, no_poor: bool = false) -> CraftingQuality:
	"""Roll for crafting quality. quality_shift/no_poor come from BOOST_CONFIG.
	Implementation: compute the boosted distribution, then roll a single 0-99
	against the cumulative thresholds so the boost is honored exactly."""
	var success_chance = calculate_success_chance(skill_level, difficulty, post_bonus, minigame_score)
	var dist = quality_distribution(success_chance, quality_shift, no_poor)
	var roll = randi() % 100
	# Walk the buckets in worst→best order so cumulative thresholds map cleanly
	var cum = dist["poor"]
	if roll < cum:
		return CraftingQuality.POOR
	cum += dist["standard"]
	if roll < cum:
		return CraftingQuality.STANDARD
	cum += dist["fine"]
	if roll < cum:
		return CraftingQuality.FINE
	return CraftingQuality.MASTERWORK

static func quality_distribution(success_chance: int, quality_shift: Dictionary = {}, no_poor: bool = false) -> Dictionary:
	"""Audit #8 Layer 5 — return the % chance of each quality bucket given a
	success_chance value. Mirrors roll_quality's bucket logic exactly: walks
	all 100 possible roll values (0-99 from `randi() % 100`) and tallies which
	quality each one produces. Returns {poor, standard, fine, masterwork} %s
	(integers, summing to 100). Player-facing odds preview before crafting.

	quality_shift / no_poor come from BOOST_CONFIG and let the player buy a
	better distribution by spending extra materials."""
	var counts := {"poor": 0, "standard": 0, "fine": 0, "masterwork": 0}
	for roll in range(100):
		if roll > success_chance + 15:
			counts["poor"] += 1
		elif roll > success_chance - 15:
			counts["standard"] += 1
		elif roll > success_chance - 30:
			counts["fine"] += 1
		else:
			counts["masterwork"] += 1

	# Apply boost shifts (additive %-points), clamp, then renormalize to sum to 100.
	if quality_shift.size() > 0 or no_poor:
		for k in ["poor", "standard", "fine", "masterwork"]:
			counts[k] = max(0, counts[k] + int(quality_shift.get(k, 0)))
		if no_poor:
			counts["standard"] += counts["poor"]
			counts["poor"] = 0
		var total = counts["poor"] + counts["standard"] + counts["fine"] + counts["masterwork"]
		if total != 100 and total > 0:
			# Renormalize by scaling, then patch any rounding drift onto Standard
			var scaled := {}
			var running := 0
			for k in ["poor", "standard", "fine", "masterwork"]:
				scaled[k] = int(round(float(counts[k]) * 100.0 / float(total)))
				running += scaled[k]
			scaled["standard"] += 100 - running
			counts = scaled
	return counts

static func apply_specialist_discount(mat_mult: float, job_level: int, is_specialist: bool) -> float:
	"""Specialist (Halfling/Knight matched to the recipe's skill) gets a discount
	on Boost material cost. Lv 40+: -20%, Lv 20-39: -10%, below that: no discount.
	Non-specialists pay full mat_mult. The discount only applies to the EXTRA
	cost above 1.0× — base recipe cost is never reduced."""
	if mat_mult <= 1.0 or not is_specialist:
		return mat_mult
	var extra = mat_mult - 1.0
	var discount = 0.0
	if job_level >= 40:
		discount = 0.2
	elif job_level >= 20:
		discount = 0.1
	return 1.0 + extra * (1.0 - discount)

static func calculate_craft_xp(difficulty: int, quality: CraftingQuality) -> int:
	"""Calculate XP gained from crafting"""
	var base_xp = BASE_CRAFT_XP + difficulty
	# Bonus XP for quality
	match quality:
		CraftingQuality.POOR:
			return base_xp / 2
		CraftingQuality.STANDARD:
			return base_xp
		CraftingQuality.FINE:
			return int(base_xp * 1.5)
		CraftingQuality.MASTERWORK:
			return base_xp * 2
		_:
			return base_xp

static func get_post_specialization_bonus(post_id: String, skill_name: String) -> int:
	"""Get crafting bonus for a specific skill at a trading post"""
	if not TRADING_POST_SPECIALIZATIONS.has(post_id):
		return 0
	return TRADING_POST_SPECIALIZATIONS[post_id].get(skill_name.to_lower(), 0)

static func apply_quality_to_stats(base_stats: Dictionary, quality: CraftingQuality) -> Dictionary:
	"""Apply quality multiplier to item stats"""
	var multiplier = QUALITY_MULTIPLIERS.get(quality, 1.0)
	var result = {}
	for stat in base_stats:
		if stat == "level":
			result[stat] = base_stats[stat]  # Level doesn't scale
		else:
			result[stat] = int(base_stats[stat] * multiplier)
	return result

static func format_materials_list(materials: Dictionary, owned_materials: Dictionary) -> String:
	"""Format materials list with owned counts"""
	var lines = []
	for mat_id in materials:
		var required = materials[mat_id]
		if mat_id.begins_with("@"):
			var owned = DropTables.get_total_for_group(mat_id, owned_materials)
			var parts = mat_id.replace("@", "").split(":")
			var stat_group = parts[0]
			var tier_group = parts[1] if parts.size() > 1 else "minor"
			var display = PART_GROUP_DISPLAY.get(stat_group, stat_group)
			var tier_range = RUNE_TIER_RANGES.get(tier_group, [1, 9])
			var tier_label = "T%d-T%d" % [tier_range[0], tier_range[1]]
			var mat_name = "%s (%s)" % [display, tier_label]
			var color = "#00FF00" if owned >= required else "#FF4444"
			lines.append("[color=%s]%s: %d/%d[/color]" % [color, mat_name, owned, required])
		else:
			var owned = owned_materials.get(mat_id, 0)
			var mat_info = MATERIALS.get(mat_id, {"name": mat_id})
			var color = "#00FF00" if owned >= required else "#FF4444"
			lines.append("[color=%s]%s: %d/%d[/color]" % [color, mat_info.name, owned, required])
	return "\n".join(lines)
