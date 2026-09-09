extends RefCounted
class_name DungeonSprites

## Floor-backed sprites for everything drawn ON the dungeon floor.
##
## The canvas is black and BBCode cannot composite two images into one cell, so a transparent
## sprite drawn over it punches a visible hole in the ground. Owner, on seeing that: "the glyphs
## make the floor very uneven... look at the borders and around the glyphs", and "the sprite for
## the player should be drawn above the floors so it appears like they are actually walking on
## them". Every entry here is therefore PRE-COMPOSITED onto the solid floor tile, offline, at
## 32x32 - a clean 2x at a 64px cell.
##
## GLYPH_TILE covers what has no art. Rather than choose a sprite for each of ~20 theme tiles and
## 7 loot kinds one at a time, every (character, colour) pair is RENDERED to a tile in Consolas -
## the font the grid already used - with a drop shadow so it reads against the floor. Each glyph
## keeps its meaning while becoming an image like any other, so nothing is left punching a hole.
##
## The pairs are SCRAPED from the source that emits them - `_get_dungeon_tile_display`,
## `DUNGEON_THEME_LEGEND` and the server's floor-loot entities - not hand-listed. A hand-written
## list produced 75 pairs and missed all 41 theme-legend entries, which showed up in play as a
## single "!" sitting in a black hole while everything around it was fine. Scraping finds 211.
##
## Both tables are GENERATED. Regenerate when tiles, loot kinds or the roster change; hand-editing
## a row makes it a second source of truth.

const MONSTER_DIR := "res://client/sprites/monster_floor32/"
const GLYPH_DIR := "res://client/sprites/glyph_floor32/"

## Monster display name -> baked sprite. The mapping to `mobs_pack` families came from comparing
## all 82 families against the roster. About two thirds are strong (Skeleton, Zombie,
## Mimic->Chest, Vampire->Count, Death Incarnate->Reaper, Wolf->Dog, Hydra->Snake); the humanoids
## - Goblin, Orc, Ogre, Troll, Giant, Kobold, Hobgoblin, Gnoll - are LOOSE, because the pack has
## almost no fantasy humanoids and no cheap pack was found covering them. Owner chose loose
## matches over leaving those as glyphs.
const MONSTER_SPRITE := {
	"Ancient Dragon": "ancient_dragon.png",
	"Avatar of Chaos": "avatar_of_chaos.png",
	"Balrog": "balrog.png",
	"Cerberus": "cerberus.png",
	"Chimaera": "chimaera.png",
	"Cosmic Horror": "cosmic_horror.png",
	"Death Incarnate": "death_incarnate.png",
	"Demon": "demon.png",
	"Demon Lord": "demon_lord.png",
	"Elder Lich": "elder_lich.png",
	"Elemental": "elemental.png",
	"Entropy": "entropy.png",
	"Gargoyle": "gargoyle.png",
	"Giant": "giant.png",
	"Giant Rat": "giant_rat.png",
	"Giant Spider": "giant_spider.png",
	"Gnoll": "gnoll.png",
	"Goblin": "goblin.png",
	"God Slayer": "god_slayer.png",
	"Gryphon": "gryphon.png",
	"Harpy": "harpy.png",
	"Hobgoblin": "hobgoblin.png",
	"Hydra": "hydra.png",
	"Iron Golem": "iron_golem.png",
	"Jabberwock": "jabberwock.png",
	"Kelpie": "kelpie.png",
	"Kobold": "kobold.png",
	"Lich": "lich.png",
	"Mimic": "mimic.png",
	"Minotaur": "minotaur.png",
	"Nazgul": "nazgul.png",
	"Ogre": "ogre.png",
	"Orc": "orc.png",
	"Phoenix": "phoenix.png",
	"Primordial Dragon": "primordial_dragon.png",
	"Shrieker": "shrieker.png",
	"Siren": "siren.png",
	"Skeleton": "skeleton.png",
	"Sphinx": "sphinx.png",
	"Succubus": "succubus.png",
	"The Nameless One": "the_nameless_one.png",
	"Time Weaver": "time_weaver.png",
	"Titan": "titan.png",
	"Troll": "troll.png",
	"Vampire": "vampire.png",
	"Void Walker": "void_walker.png",
	"Wight": "wight.png",
	"Wolf": "wolf.png",
	"World Serpent": "world_serpent.png",
	"Wraith": "wraith.png",
	"Wyvern": "wyvern.png",
	"Young Dragon": "young_dragon.png",
	"Zombie": "zombie.png",
}

## "<char>|<#colour>" -> baked glyph tile.
const GLYPH_TILE := {
	"!|#00FF00": "u0021_00FF00",
	"!|#00FFCC": "u0021_00FFCC",
	"!|#1EFF00": "u0021_1EFF00",
	"!|#87CEEB": "u0021_87CEEB",
	"!|#A335EE": "u0021_A335EE",
	"!|#AAAAAA": "u0021_AAAAAA",
	"!|#FF0000": "u0021_FF0000",
	"!|#FF4444": "u0021_FF4444",
	"!|#FF6347": "u0021_FF6347",
	"!|#FFAA00": "u0021_FFAA00",
	"!|#FFD700": "u0021_FFD700",
	"!|#FFFF00": "u0021_FFFF00",
	"$|#00FF00": "u0024_00FF00",
	"$|#00FFCC": "u0024_00FFCC",
	"$|#1EFF00": "u0024_1EFF00",
	"$|#A335EE": "u0024_A335EE",
	"$|#AAAAAA": "u0024_AAAAAA",
	"$|#FF0000": "u0024_FF0000",
	"$|#FF4444": "u0024_FF4444",
	"$|#FFAA00": "u0024_FFAA00",
	"$|#FFD700": "u0024_FFD700",
	"$|#FFFF00": "u0024_FFFF00",
	"%|#D8D8C8": "u0025_D8D8C8",
	"&|#00FF00": "u0026_00FF00",
	"&|#00FFCC": "u0026_00FFCC",
	"&|#1EFF00": "u0026_1EFF00",
	"&|#A335EE": "u0026_A335EE",
	"&|#AAAAAA": "u0026_AAAAAA",
	"&|#FF0000": "u0026_FF0000",
	"&|#FF4444": "u0026_FF4444",
	"&|#FFAA00": "u0026_FFAA00",
	"&|#FFD700": "u0026_FFD700",
	"&|#FFFF00": "u0026_FFFF00",
	"*|#00FF00": "u002a_00FF00",
	"*|#00FFCC": "u002a_00FFCC",
	"*|#1EFF00": "u002a_1EFF00",
	"*|#A335EE": "u002a_A335EE",
	"*|#AAAAAA": "u002a_AAAAAA",
	"*|#FF0000": "u002a_FF0000",
	"*|#FF4444": "u002a_FF4444",
	"*|#FFAA00": "u002a_FFAA00",
	"*|#FFD700": "u002a_FFD700",
	"*|#FFFF00": "u002a_FFFF00",
	"+|#660000": "u002b_660000",
	",|#7FBF3F": "u002c_7FBF3F",
	"/|#48D1CC": "u002f_48D1CC",
	":|#9370DB": "u003a_9370DB",
	";|#8B0000": "u003b_8B0000",
	"=|#20B2AA": "u003d_20B2AA",
	">|#00FF00": "u003e_00FF00",
	">|#00FFCC": "u003e_00FFCC",
	">|#1EFF00": "u003e_1EFF00",
	">|#A335EE": "u003e_A335EE",
	">|#AAAAAA": "u003e_AAAAAA",
	">|#FF0000": "u003e_FF0000",
	">|#FF4444": "u003e_FF4444",
	">|#FFAA00": "u003e_FFAA00",
	">|#FFD700": "u003e_FFD700",
	">|#FFFF00": "u003e_FFFF00",
	"?|#00FF00": "u003f_00FF00",
	"?|#00FFCC": "u003f_00FFCC",
	"?|#1EFF00": "u003f_1EFF00",
	"?|#5AC8FF": "u003f_5AC8FF",
	"?|#A335EE": "u003f_A335EE",
	"?|#AAAAAA": "u003f_AAAAAA",
	"?|#FF0000": "u003f_FF0000",
	"?|#FF4444": "u003f_FF4444",
	"?|#FFAA00": "u003f_FFAA00",
	"?|#FFD700": "u003f_FFD700",
	"?|#FFFF00": "u003f_FFFF00",
	"?|#FFFFFF": "u003f_FFFFFF",
	"B|#00FF00": "u0042_00FF00",
	"B|#00FFCC": "u0042_00FFCC",
	"B|#1EFF00": "u0042_1EFF00",
	"B|#A335EE": "u0042_A335EE",
	"B|#AAAAAA": "u0042_AAAAAA",
	"B|#FF0000": "u0042_FF0000",
	"B|#FF4444": "u0042_FF4444",
	"B|#FFAA00": "u0042_FFAA00",
	"B|#FFD700": "u0042_FFD700",
	"B|#FFFF00": "u0042_FFFF00",
	"D|#FFFFAA": "u0044_FFFFAA",
	"E|#00FF00": "u0045_00FF00",
	"E|#00FFCC": "u0045_00FFCC",
	"E|#1EFF00": "u0045_1EFF00",
	"E|#A335EE": "u0045_A335EE",
	"E|#AAAAAA": "u0045_AAAAAA",
	"E|#FF0000": "u0045_FF0000",
	"E|#FF4444": "u0045_FF4444",
	"E|#FFAA00": "u0045_FFAA00",
	"E|#FFD700": "u0045_FFD700",
	"E|#FFFF00": "u0045_FFFF00",
	"F|#FF4500": "u0046_FF4500",
	"G|#FFD700": "u0047_FFD700",
	"H|#909090": "u0048_909090",
	"I|#4488FF": "u0049_4488FF",
	"N|#444466": "u004e_444466",
	"O|#FF00AA": "u004f_FF00AA",
	"Q|#2A0033": "u0051_2A0033",
	"R|#1A0033": "u0052_1A0033",
	"S|#707070": "u0053_707070",
	"T|#F0E68C": "u0054_F0E68C",
	"U|#884466": "u0055_884466",
	"V|#228B22": "u0056_228B22",
	"W|#FF00FF": "u0057_FF00FF",
	"Y|#AA66FF": "u0059_AA66FF",
	"Z|#003344": "u005a_003344",
	"^|#FF4500": "u005e_FF4500",
	"a|#B0E0E6": "u0061_B0E0E6",
	"b|#F4A460": "u0062_F4A460",
	"c|#DAA520": "u0063_DAA520",
	"d|#BDB76B": "u0064_BDB76B",
	"e|#FF6600": "u0065_FF6600",
	"f|#FFE4B5": "u0066_FFE4B5",
	"g|#8B4513": "u0067_8B4513",
	"h|#B080FF": "u0068_B080FF",
	"i|#ADD8E6": "u0069_ADD8E6",
	"j|#6644AA": "u006a_6644AA",
	"k|#66CC00": "u006b_66CC00",
	"l|#FF80CC": "u006c_FF80CC",
	"m|#3CB371": "u006d_3CB371",
	"n|#CD853F": "u006e_CD853F",
	"o|#FFA500": "u006f_FFA500",
	"p|#7BA821": "u0070_7BA821",
	"q|#4169E1": "u0071_4169E1",
	"r|#A0A0A0": "u0072_A0A0A0",
	"s|#9ACD32": "u0073_9ACD32",
	"t|#DAA520": "u0074_DAA520",
	"u|#556B2F": "u0075_556B2F",
	"v|#5D4037": "u0076_5D4037",
	"w|#00FF00": "u0077_00FF00",
	"w|#00FFCC": "u0077_00FFCC",
	"w|#1EFF00": "u0077_1EFF00",
	"w|#A335EE": "u0077_A335EE",
	"w|#AAAAAA": "u0077_AAAAAA",
	"w|#FF0000": "u0077_FF0000",
	"w|#FF4444": "u0077_FF4444",
	"w|#FFAA00": "u0077_FFAA00",
	"w|#FFD700": "u0077_FFD700",
	"w|#FFFF00": "u0077_FFFF00",
	"x|#B22222": "u0078_B22222",
	"y|#8B2500": "u0079_8B2500",
	"z|#DC143C": "u007a_DC143C",
	"~|#87CEEB": "u007e_87CEEB",
	"¢|#00FF00": "u00a2_00FF00",
	"¢|#00FFCC": "u00a2_00FFCC",
	"¢|#1EFF00": "u00a2_1EFF00",
	"¢|#A335EE": "u00a2_A335EE",
	"¢|#AAAAAA": "u00a2_AAAAAA",
	"¢|#FF0000": "u00a2_FF0000",
	"¢|#FF4444": "u00a2_FF4444",
	"¢|#FFAA00": "u00a2_FFAA00",
	"¢|#FFD700": "u00a2_FFD700",
	"¢|#FFFF00": "u00a2_FFFF00",
	"¤|#FFE96A": "u00a4_FFE96A",
	"·|#303030": "u00b7_303030",
	"·|#5A5A66": "u00b7_5A5A66",
	"×|#00FF00": "u00d7_00FF00",
	"×|#00FFCC": "u00d7_00FFCC",
	"×|#1EFF00": "u00d7_1EFF00",
	"×|#A335EE": "u00d7_A335EE",
	"×|#AAAAAA": "u00d7_AAAAAA",
	"×|#FF0000": "u00d7_FF0000",
	"×|#FF4444": "u00d7_FF4444",
	"×|#FFAA00": "u00d7_FFAA00",
	"×|#FFD700": "u00d7_FFD700",
	"×|#FFFF00": "u00d7_FFFF00",
	"▪|#00FF00": "u25aa_00FF00",
	"▪|#00FFCC": "u25aa_00FFCC",
	"▪|#1EFF00": "u25aa_1EFF00",
	"▪|#A335EE": "u25aa_A335EE",
	"▪|#AAAAAA": "u25aa_AAAAAA",
	"▪|#FF0000": "u25aa_FF0000",
	"▪|#FF4444": "u25aa_FF4444",
	"▪|#FFAA00": "u25aa_FFAA00",
	"▪|#FFD700": "u25aa_FFD700",
	"▪|#FFFF00": "u25aa_FFFF00",
	"▲|#7AE07A": "u25b2_7AE07A",
	"◆|#00FF00": "u25c6_00FF00",
	"◆|#00FFCC": "u25c6_00FFCC",
	"◆|#1EFF00": "u25c6_1EFF00",
	"◆|#A335EE": "u25c6_A335EE",
	"◆|#AAAAAA": "u25c6_AAAAAA",
	"◆|#FF0000": "u25c6_FF0000",
	"◆|#FF4444": "u25c6_FF4444",
	"◆|#FF5AF0": "u25c6_FF5AF0",
	"◆|#FFAA00": "u25c6_FFAA00",
	"◆|#FFD700": "u25c6_FFD700",
	"◆|#FFFF00": "u25c6_FFFF00",
	"◉|#00FF00": "u25c9_00FF00",
	"◉|#00FFCC": "u25c9_00FFCC",
	"◉|#1EFF00": "u25c9_1EFF00",
	"◉|#A335EE": "u25c9_A335EE",
	"◉|#AAAAAA": "u25c9_AAAAAA",
	"◉|#FF0000": "u25c9_FF0000",
	"◉|#FF4444": "u25c9_FF4444",
	"◉|#FFAA00": "u25c9_FFAA00",
	"◉|#FFD700": "u25c9_FFD700",
	"◉|#FFFF00": "u25c9_FFFF00",
	"♦|#FFD700": "u2666_FFD700",
	"✦|#00FF00": "u2726_00FF00",
	"✦|#00FFCC": "u2726_00FFCC",
	"✦|#1EFF00": "u2726_1EFF00",
	"✦|#5AC8FF": "u2726_5AC8FF",
	"✦|#A335EE": "u2726_A335EE",
	"✦|#AAAAAA": "u2726_AAAAAA",
	"✦|#FF0000": "u2726_FF0000",
	"✦|#FF4444": "u2726_FF4444",
	"✦|#FFAA00": "u2726_FFAA00",
	"✦|#FFD700": "u2726_FFD700",
	"✦|#FFFF00": "u2726_FFFF00",
}


static func monster_path(display_name: String) -> String:
	"""The baked sprite for a monster, or "" if it has none.

	Matches the BASE name inside the display name, so a pre-rolled "Venomous Orc" or an elite
	"* Orc Champion" still resolves to the Orc. Longest match wins, so "Ancient Dragon" is not
	beaten by "Dragon"."""
	if display_name == "":
		return ""
	if MONSTER_SPRITE.has(display_name):
		return MONSTER_DIR + String(MONSTER_SPRITE[display_name]) + ".png"
	var best := ""
	for k in MONSTER_SPRITE.keys():
		var n := String(k)
		if display_name.findn(n) >= 0 and n.length() > best.length():
			best = n
	if best == "":
		return ""
	return MONSTER_DIR + String(MONSTER_SPRITE[best]) + ".png"


static func glyph_path(glyph: String, color: String) -> String:
	"""The baked tile for a glyph in a colour, or "" if that pair was never baked."""
	var k: String = glyph + "|" + color
	if not GLYPH_TILE.has(k):
		return ""
	return GLYPH_DIR + String(GLYPH_TILE[k]) + ".png"
