extends SceneTree
## How many distinguishable companions exist, counting every variation as its own?
##
## Owner asked 2026-09-11. Counted from the live tables rather than estimated, because the axes
## multiply and a guess would be worthless. Each axis is reported separately so the number can be
## re-derived if the definition of "unique" differs from the one used here.
const DT := preload("res://shared/drop_tables.gd")

func _init() -> void:
	var dt = DT.new()
	var species: Dictionary = DT.COMPANION_DATA
	var variants: Array = DT.EGG_VARIANTS
	var borders: Array = DT.BORDER_TIERS

	# --- axis 1: species -----------------------------------------------------------------
	var tiers := {}
	for k in species:
		var t: int = int(species[k].get("tier", 1))
		tiers[t] = int(tiers.get(t, 0)) + 1
	print("SPECIES: %d" % species.size())
	var tk: Array = tiers.keys()
	tk.sort()
	var tline: Array = []
	for t in tk:
		tline.append("T%d:%d" % [t, tiers[t]])
	print("   by tier — %s   (a species has ONE fixed tier, so tier is not a separate axis)"
		% ", ".join(tline))

	# --- axis 2: cosmetic variant (colour + pattern) --------------------------------------
	var pats := {}
	var names := {}
	for v in variants:
		pats[String(v.get("pattern", "?"))] = true
		names[String(v.get("name", "?"))] = true
	print("\nCOSMETIC VARIANTS: %d  (%d distinct names, %d patterns)"
		% [variants.size(), names.size(), pats.size()])
	print("   patterns: %s" % ", ".join(pats.keys()))

	# --- axis 3: sub-tier ------------------------------------------------------------------
	# 1-8 from dungeon depth; 9 is reachable only by fusion (mini(sub+1, 9)).
	print("\nSUB-TIER: 9  (1-8 from the dungeon it came out of, 9 only by fusing)")

	# --- axis 4: border --------------------------------------------------------------------
	var bnames: Array = []
	for b in borders:
		bnames.append("%s" % String(b.get("name", "?")))
	print("\nBORDER TIERS: %d  (%s)" % [borders.size(), ", ".join(bnames)])

	# --- the totals ------------------------------------------------------------------------
	var s: int = species.size()
	var v: int = variants.size()
	var sub := 9
	var b: int = borders.size()
	print("\n=== HOW MANY COMPANIONS ===")
	print("  species alone .................. %s" % _c(s))
	print("  x cosmetic variant ............. %s" % _c(s * v))
	print("  x sub-tier ..................... %s" % _c(s * v * sub))
	print("  x border tier .................. %s" % _c(s * v * sub * b))
	print("")
	print("  Sub-tier 9 needs fusion, so what a player can find in the wild is")
	print("  species x variant x sub-tier(1-8) = %s" % _c(s * v * 8))
	quit(0)


func _c(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out
