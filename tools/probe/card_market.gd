extends SceneTree
## Smoke test for the CARD MARKET, which the backlog records as "built, compile-clean, never
## exercised end to end".
##
## Every tradeable card has to survive the listing path: it is looked up for a DISPLAY NAME, a
## TIER and a VALOR PRICE, and a listing is built from those three. A card that returns an empty
## name lists as a blank row; one that prices at 0 is given away free. Both are silent - the
## listing succeeds either way - which is exactly the shape this codebase keeps finding, so every
## card is put through the real functions rather than a sample.
func _init() -> void:
	var DT = load("res://shared/drop_tables.gd")
	var ids: Array = []
	for mt in DT.COMPANION_CARD_DATA.keys():
		ids.append(DT.companion_card_id_for(String(mt)))
	for slug in DT.DUNGEON_CARD_DATA.keys():
		ids.append("dungeon_card_" + String(slug))
	print("[CARDMKT] tradeable cards: %d" % ids.size())
	var bad: Array = []
	var min_v := 1 << 30
	var max_v := 0
	for cid in ids:
		var name: String = String(DT.card_display_name(String(cid)))
		var tier: int = int(DT.card_tier(String(cid)))
		var valor: int = int(DT.calculate_card_valor(String(cid)))
		if name == "" or name == String(cid):
			bad.append("%s: display name is '%s'" % [cid, name])
		if tier <= 0:
			bad.append("%s: tier %d" % [cid, tier])
		if valor <= 0:
			bad.append("%s: valor %d - would be listed for nothing" % [cid, valor])
		min_v = mini(min_v, valor)
		max_v = maxi(max_v, valor)
	print("[CARDMKT] valor range across all cards: %d .. %d" % [min_v, max_v])
	for b in bad:
		print("[CARDMKT] BROKEN ", b)
	print("[CARDMKT] %s" % ("PASS - every tradeable card names, tiers and prices itself"
		if bad.is_empty() else "FAIL - %d problem(s)" % bad.size()))
	quit(0 if bad.is_empty() else 1)
