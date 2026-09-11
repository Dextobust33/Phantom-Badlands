extends SceneTree
## The listing ROUND TRIP: list a card, read it back, remove it.
##
## 2026-09-11 — CARD LISTINGS NO LONGER MERGE. Every copy of a card is its own instance and can
## carry its own upgrades (see tools/probe/card_instances.gd). The old rule merged two listings of
## the same card by the same seller into one stack, summing quantity and valor, which would have
## kept the first copy's upgrades and thrown the second copy's away. Cards now sit beside equipment
## and eggs in the unique list: two copies listed are two rows, each with its own progress.
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

	var mk := func(picks: Array):
		return {"account_id": "acct1", "seller_name": "Seller",
			"item": {"type": "card", "card_id": cid, "name": name, "tier": DT.card_tier(cid),
				"instance": {"uses": 40, "picks": picks, "effect_rank": 0}, "upgrades": picks.size()},
			"base_valor": valor, "supply_category": "card",
			"listed_at": 0, "quantity": 1}

	var bad := 0
	var id1: String = pm.add_market_listing(post, mk.call(["executioner"]))
	var id2: String = pm.add_market_listing(post, mk.call(["swift", "power"]))
	var rows: Array = pm.get_market_listings(post)
	print("[MKTRT] listed two copies: rows=%d ids=%s,%s" % [rows.size(), id1, id2])
	if rows.size() != 2 or id1 == id2:
		print("[MKTRT] BROKEN: two card copies merged into one listing - one copy's upgrades would be lost"); bad += 1
	var seen := []
	for r in rows:
		if int(r.get("quantity", 0)) != 1 or int(r.get("base_valor", 0)) != valor:
			print("[MKTRT] BROKEN: a card listing is not a single copy at the card's own price"); bad += 1
		seen.append((r.get("item", {}).get("instance", {}).get("picks", []) as Array).duplicate())
	if not (["executioner"] in seen and ["swift", "power"] in seen):
		print("[MKTRT] BROKEN: each listing must keep ITS copy's upgrades (got %s)" % str(seen)); bad += 1

	var removed: Dictionary = pm.remove_market_listing(post, id1)
	var after_rm: Array = pm.get_market_listings(post)
	print("[MKTRT] removed one: got_back=%s  rows_left=%d" % [str(not removed.is_empty()), after_rm.size()])
	if removed.is_empty() or after_rm.size() != 1:
		print("[MKTRT] BROKEN: remove did not take exactly that listing"); bad += 1
	print("[MKTRT] %s" % ("PASS - card copies list separately, keep their upgrades, remove cleanly" if bad == 0 else "FAIL - %d problem(s)" % bad))
	quit(0 if bad == 0 else 1)
