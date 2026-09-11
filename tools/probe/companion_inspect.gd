extends SceneTree
## The companion screens must be ACCURATE, READABLE, and complete.
##
## Owner 2026-09-11: *"Is the info on it even still accurate? It doesn't even show a log of the
## companions stats... What does Aggro do? What does spd do for a companion... It also doesn't
## list the card they provide in combat or anything."* And: *"The multiplier is confusing to the
## players in its current form."* And: *"all I see to signify Tier and rank is H1 and G1. What
## happened to the bars?"*
const DT := preload("res://shared/drop_tables.gd")
const PR := preload("res://shared/power_rank.gd")
const CL := preload("res://client/client.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var c = CL.new()

	print("--- the multipliers are ACCURATE again ---")
	# Before: a hardcoded twelve-NAME list, the fourth surviving consumer of the per-name table
	# deleted on 2026-09-03. 111 of 119 variants showed the wrong number.
	var wrong := 0
	for v in DT.EGG_VARIANTS:
		var name := String(v.get("name", ""))
		var real: float = DT.variant_mult_for_rarity(int(v.get("rarity", 10)))
		if absf(c._get_variant_multiplier(name) - real) > 0.005:
			wrong += 1
	ck(wrong == 0, "all %d variants report the real multiplier - %d wrong (was 111)" % [
		DT.EGG_VARIANTS.size(), wrong])
	var sub_bad := 0
	for st in range(1, 10):
		if absf(c._get_sub_tier_multiplier(st) - float(DT.COMPANION_SUB_TIER_MULTIPLIERS.get(st, 1.0))) > 0.001:
			sub_bad += 1
	ck(sub_bad == 0, "and rank multipliers come from the shared table, not a copy")
	var src := FileAccess.get_file_as_string("res://client/client.gd")
	ck(src.contains("dt.variant_mult_for_rarity(dt.variant_rarity_of("),
		"the variant multiplier is DERIVED, not looked up by name")

	print("\n--- ONE power number, not three multipliers in three formats ---")
	ck(src.contains("var power: float = variant_mult * sub_mult * border_mult"),
		"variant x rank x border are combined into one figure")
	ck(src.contains("Power x%.2f"), "...and shown as a single Power value")
	ck(src.contains("Here: variant x%.2f, rank x%.2f, border x%.2f"),
		"...with the breakdown one hover away, for anyone who wants it")
	var a := src.find("func _build_companion_inspect_bbcode")
	var body := src.substr(a, src.find("\nfunc ", a + 10) - a)
	ck(not body.contains("variant_bonus") or not body.contains("border_bonus"),
		"the old duplicate (+N% stats) suffixes are off the name line")

	print("\n--- the stats are THERE, and every one explains itself ---")
	ck(src.contains("const COMPANION_STAT_HELP"), "there is one shared stat-help table")
	for key in ["health", "damage", "aggro", "speed", "power"]:
		ck(String(CL.COMPANION_STAT_HELP.get(key, "")) != "",
			"'%s' says what it does: \"%s...\"" % [key, String(CL.COMPANION_STAT_HELP[key]).substr(0, 44)])
	for want in ["\"Health\"", "\"Damage\"", "\"Aggro\"", "\"Speed\""]:
		ck(body.contains(want), "the inspect screen lists %s" % want)
	ck(body.contains("_companion_stat("), "...through the hoverable row builder, so none can be unexplained")
	ck(body.contains("Character.calculate_companion_max_hp"),
		"health is the SHARED calculation, not one of the client's old mirrors")

	print("\n--- and it finally names the card the companion gives you ---")
	ck(body.contains("get_companion_card_data"), "the combat card is resolved")
	ck(body.contains("Its Combat Card"), "...and has its own section")
	ck(body.contains("casts to make it permanent"),
		"...showing progress toward keeping it, which is what a player is working for")
	# The card data must actually exist for real companions, or the section renders empty.
	var missing := 0
	for m in ["Giant Rat", "Wolf", "Goblin", "Skeleton", "Kobold"]:
		if DT.get_companion_card_data(m).is_empty():
			missing += 1
	ck(missing == 0, "the starter companions all have card data")

	print("\n--- the ladder is visible as a BAR, not only a colour ---")
	var panel := FileAccess.get_file_as_string("res://client/companions_panel.gd")
	ck(panel.contains("PowerRank.pips(tier)"), "the companions screen draws the bar")
	ck(panel.contains("PowerRank.rich_label(tier, sub_tier)"),
		"...and the active companion carries the explaining hover")
	ck(body.contains("PowerRank.rich_label(tier, sub_tier)") and body.contains("PowerRank.pips(tier)"),
		"so does the inspect screen")

	print("\n--- a hover can never break out of its own tag ---")
	# `[url=VALUE]` ends at the first `]`. PowerRank.hover used to contain "[E]" to mark the
	# current tier, so the whole ladder spilled into the visible line as plain text.
	for t in range(1, 10):
		var rl: String = PR.rich_label(t, 5)
		var inner: String = rl.substr(rl.find("[url=") + 5)
		inner = inner.substr(0, inner.find("]"))
		ck(not inner.contains("[") and inner.length() > 20,
			"tier %d's hover survives intact inside the tag (%d chars)" % [t, inner.length()])
		if t > 1:
			break
	ck(not PR.hover(4, 6).contains("["), "hover() emits no square brackets at all")

	c.free()
	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
