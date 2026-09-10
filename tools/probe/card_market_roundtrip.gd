extends SceneTree
## The listing ROUND TRIP: list a card, read it back, buy it, see it gone.
##
## The backlog records the card market as "built, compile-clean, never exercised end to end", and
## the merge rule is the reason to be careful: cards carry `supply_category: "card"`, which is NOT
## in the unique list, so two listings of the same card by the same seller MERGE - summing both
## quantity AND base_valor. If the buy side priced from `base_valor` directly, a stack of two
## would charge double for one card. (It does not: it divides by quantity for a per-unit rate.
## This proves the merge behaves as that arithmetic assumes.)
func _init() -> void:
	var PM = load("res://server/persistence_manager.gd")
	var pm = PM.new()
	get_root().add_child(pm)
	await process_frame
	# Work on the in-memory structure directly; this is about the merge/remove LOGIC, not SQLite.
	pm.market_data = {"listings": {}, "next_id": 1}
	var DT = load("res://shared/drop_tables.gd")
	var cid: String = String(DT.companion_card_id_for("Goblin"))
	var name: String = String(DT.card_display_name(cid))
	var valor: int = int(DT.calculate_card_valor(cid))
	var post: String = "post_test"

	var mk := func():
		return {"account_id": "acct1", "seller_name": "Seller",
			"item": {"type": "card", "card_id": cid, "name": name, "tier": DT.card_tier(cid)},
			"base_valor": valor, "supply_category": "card",
			"listed_at": 0, "quantity": 1}

	var id1: String = pm.add_market_listing(post, mk.call())
	var after_one: Array = pm.get_market_listings(post)
	print("[MKTRT] listed one: id=%s  rows=%d  qty=%d  base_valor=%d (card valor %d)"
		% [id1, after_one.size(), int(after_one[0].get("quantity", 0)), int(after_one[0].get("base_valor", 0)), valor])

	var id2: String = pm.add_market_listing(post, mk.call())
	var after_two: Array = pm.get_market_listings(post)
	var row: Dictionary = after_two[0]
	var qty: int = int(row.get("quantity", 0))
	var bv: int = int(row.get("base_valor", 0))
	var per_unit: int = int(bv / maxi(qty, 1))
	print("[MKTRT] listed a second: rows=%d  qty=%d  base_valor=%d  -> per-unit %d (want %d)"
		% [after_two.size(), qty, bv, per_unit, valor])
	var bad := 0
	if after_two.size() != 1 or qty != 2:
		print("[MKTRT] BROKEN: the second listing did not merge"); bad += 1
	if per_unit != valor:
		print("[MKTRT] BROKEN: per-unit price %d != card valor %d - a stack would mis-price" % [per_unit, valor]); bad += 1
	if id1 != id2:
		print("[MKTRT] note: merge returned a different id (%s vs %s)" % [id1, id2])

	var removed: Dictionary = pm.remove_market_listing(post, id1)
	var after_rm: Array = pm.get_market_listings(post)
	print("[MKTRT] removed: got_back=%s  rows_left=%d" % [str(not removed.is_empty()), after_rm.size()])
	if removed.is_empty() or after_rm.size() != 0:
		print("[MKTRT] BROKEN: remove did not clear the listing"); bad += 1
	print("[MKTRT] %s" % ("PASS - list, merge, price and remove all behave" if bad == 0 else "FAIL - %d problem(s)" % bad))
	quit(0 if bad == 0 else 1)
