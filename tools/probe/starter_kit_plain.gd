extends SceneTree
## ⛑ DOES THE FIRST ITEM A PLAYER IS EVER HANDED READ LIKE A STARTER ITEM?
##
## Backlog, verified live 2026-09-15: *"THE STARTER KIT IS STILL NAMED LIKE ENDGAME LOOT."*
## `get_starter_kit_item` ran the full affix generator, so a brand-new character was given
## "Rusty Weapon of Wisdom", "Void-touched Wood Shield" and "Mystic Cloth Helm" — and this got
## MORE visible once the floor pieces gained per-slot sprites, because the player is looking
## straight at the thing.
##
## The same entry recorded the trap: *"do not rename without changing the roll ... a plain name
## over rolled affixes puts a name on the item that its own stats contradict."* Common has carried
## ONE affix since 2026-09-03, and at level 5 that affix is worth about as much as the item's whole
## base — so dropping it is a real loss of power, and the level has to pay for it.
##
## Run:
##   godot --headless --path . --script res://tools/probe/starter_kit_plain.gd

const DT := preload("res://shared/drop_tables.gd")
const CH := preload("res://shared/character.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


## One number for "how much is this item worth to a level-1 character", weighted the way a
## low-level exchange actually cares: attack and defence decide it, HP is a buffer, the six stats
## are small this early. Summing raw stats across kinds is what made an earlier measurement in
## this repo unsound, so the weights are explicit rather than implied.
func _power(item: Dictionary) -> float:
	var b: Dictionary = CH.item_stat_bonuses(item)
	return float(b.get("attack", 0)) + float(b.get("defense", 0)) \
		+ float(b.get("max_hp", 0)) * 0.20 \
		+ float(b.get("strength", 0) + b.get("constitution", 0) + b.get("dexterity", 0)
			+ b.get("intelligence", 0) + b.get("wisdom", 0) + b.get("wits", 0)) * 0.5 \
		+ float(b.get("max_mana", 0) + b.get("max_stamina", 0) + b.get("max_energy", 0)) * 0.10


func _init() -> void:
	var dt = DT.new()
	var slots: Array = DT.STARTER_KIT_SLOT_MAP.keys()

	print("===== 1. WHAT A NEW PLAYER IS ACTUALLY HANDED =====")
	# Every affix word in the game, read off the pools rather than listed here - a hand-written
	# list of forbidden words is a second copy that goes stale the moment the pools grow.
	var affix_words: Array = []
	for row in DT.PREFIX_POOL:
		affix_words.append(String(row.get("name", "")))
	for row in DT.SUFFIX_POOL:
		affix_words.append(String(row.get("name", "")))
	# The rarity decorations `_generate_item` prepends, which are the other half of the problem
	# ("Mystic Cloth Helm" came from a rarity UPGRADE, not from an affix).
	for w in ["Masterwork ", "Mythical ", "Divine ", "Focused ", "Wild "]:
		affix_words.append(w)

	var bad: Array = []
	var seen: Dictionary = {}
	for _i in range(300):
		for sl in slots:
			var it: Dictionary = dt.get_starter_kit_item(String(sl))
			var nm: String = String(it.get("name", ""))
			seen[nm] = true
			if String(it.get("rarity", "")) != "common":
				bad.append("%s rarity=%s" % [nm, it.get("rarity", "")])
			if not (it.get("affixes", {}) as Dictionary).is_empty():
				bad.append("%s carries affixes %s" % [nm, str(it.get("affixes", {}))])
			for w in affix_words:
				if w != "" and w in nm:
					bad.append("%s contains the affix word '%s'" % [nm, w])
	for k in seen.keys():
		print("           " + String(k))
	for b in bad:
		print("           BAD: " + String(b))
	# 300 draws x 6 slots. The point of sampling rather than asking once: the old fault was
	# partly a RARITY UPGRADE, which fires on a minority of rolls, so a single draw could look
	# clean and the next player get "Mystic Cloth Helm".
	ck(bad.is_empty(), "1800 draws, none decorated, none affixed (%d bad)" % bad.size())
	ck(seen.size() == slots.size(),
		"and the kit is DETERMINISTIC now - %d distinct names for %d slots" % [seen.size(), slots.size()])

	print("\n===== 2. IT IS NOT A NERF =====")
	# ⛑ Renaming alone was the forbidden fix; dropping the affix without paying for it is the
	# other half of the same mistake. `plain=false` at level 5 is exactly the OLD behaviour, and
	# it is still reachable, so this compares against the real thing rather than a number copied
	# out of a commit message.
	var n := 400
	var old_p := 0.0
	var new_p := 0.0
	for _i in range(n):
		for sl in slots:
			var e := {"item_type": String(DT.STARTER_KIT_SLOT_MAP[sl]), "rarity": "common"}
			old_p += _power(dt._generate_item(e, 5))
			new_p += _power(dt.get_starter_kit_item(String(sl)))
	old_p /= float(n)
	new_p /= float(n)
	print("           old (affixed, level 5): %.1f" % old_p)
	print("           new (plain,  level 10): %.1f   %.2fx" % [new_p, new_p / maxf(0.01, old_p)])
	ck(new_p >= old_p * 0.92, "the plain kit is not weaker (%.2fx)" % (new_p / maxf(0.01, old_p)))
	ck(new_p <= old_p * 1.15, "and not a stealth buff either (%.2fx)" % (new_p / maxf(0.01, old_p)))

	print("\n===== 3. THE PLAIN PATH IS NOT REACHABLE BY ACCIDENT =====")
	# It must stay opt-in: every other generator call has to keep rolling affixes, or this would
	# have quietly flattened all the loot in the game.
	var affixed := 0
	for _i in range(200):
		var it: Dictionary = dt.roll_dungeon_chest_equipment(3, 50)
		if it.is_empty():
			continue
		if not (it.get("affixes", {}) as Dictionary).is_empty():
			affixed += 1
	ck(affixed > 50, "ordinary dungeon loot still rolls affixes (%d of ~110)" % affixed)
	# And a consumable must not be handed the plain branch - it has its own naming and tier path.
	var potion: Dictionary = dt._generate_item({"item_type": "potion_minor"}, 10, "", [], true)
	ck(bool(potion.get("is_consumable", false)),
		"a consumable asked for plainly still goes down the consumable path")

	print("\n===== VERDICT =====")
	print("  all checks PASS" if fails == 0 else "  %d check(s) FAIL" % fails)
	quit(1 if fails > 0 else 0)
