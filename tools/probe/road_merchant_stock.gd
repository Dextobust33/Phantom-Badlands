extends SceneTree
## ⛑ A MERCHANT YOU MEET ON THE ROAD HAS SOMETHING TO SELL.
##
## Owner 2026-09-18: *"Current merchants also move way too slow from post to post and seem to
## pretty much never have anything for sale when you see them out and around."*
##
## Both halves were real and they COMPOUNDED, which is why it read as pointless rather than slow:
##
##   * **Stock.** `trigger_merchant_encounter` built the shop entirely from `merchant_inventory` -
##     market listings other players had posted, which the courier moves between posts. There was
##     an explicit "nothing to sell right now" branch and no fallback, so with a small or quiet
##     player base a road merchant was empty BY CONSTRUCTION, not by bad luck.
##   * **Speed.** `MERCHANT_SPEED` was 0.025 tiles/second - one tile every forty seconds - so a
##     merchant was very nearly stationary next to a player who moves a tile per keypress.
##
## Fixing only the speed would have given players more frequent encounters with nothing to buy.
##
## Run:
##   godot --headless --path . --script res://tools/probe/road_merchant_stock.gd

const WS := preload("res://shared/world_system.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var srv := FileAccess.get_file_as_string("res://server/server.gd")

	print("===== A ROAD MERCHANT HAS ITS OWN STOCK =====")
	ck(srv.find('"road_" + merchant_id, _road_area_lvl, hash(merchant_id), "potions")') >= 0,
		"a courier stocks CONSUMABLES, at the AREA level, keyed per merchant")
	# ⛑ THE THREE CONSTRAINTS ARE THE POINT, and the first version of this fix had none of
	# them: it called the post shop generator with `character.level`, which returns 4-12 items
	# scaled to the buyer - a gear vending machine on every courier. Owner: *"We don't want
	# players to just be able to buy all of their gear upgrades from a wandering merchant for
	# cheap and trivialize the drops and crafting work."*
	ck(srv.find("character.level, hash(merchant_id)") < 0,
		"...and NOT the player's level - deep country carries deep stock")
	ck(srv.find("func _is_equipment_item(") >= 0 and srv.find("if _is_equipment_item(_it):") >= 0,
		"equipment is refused from a courier's OWN stock, whatever the generator returns")
	ck(srv.find("ROAD_MERCHANT_MAX_OWN_ITEMS") >= 0,
		"...and the carry is capped - a courier is not a market stall")
	ck(srv.find('_road_it["shop_price"] = int(round(float(_road_it.get("shop_price", 1)) * ROAD_MERCHANT_MARKUP))') >= 0,
		"...at the road markup, so convenience is paid for")
	# The empty branch must now require BOTH to be empty, or the floor never shows.
	ck(srv.find("if carried_items.size() == 0 and own_stock.is_empty():") >= 0,
		'"nothing to sell" needs BOTH empty now - it was the normal case before')
	ck(srv.find("shop.append_array(own_stock)") >= 0,
		"and the floor is appended under the carried listings")
	ck(srv.find("var shop: Array = _flatten_carried_to_shop_items(carried_items)") >= 0,
		"...with player listings FIRST - they are the reason to stop a courier")

	print("\n===== AND IT MOVES =====")
	ck(WS.MERCHANT_SPEED >= 0.2,
		"MERCHANT_SPEED is %.3f tiles/s (was 0.025 - one tile every 40 seconds)" % WS.MERCHANT_SPEED)
	# ⛑ The RATIO is the thing, not the absolute. A courier that rests 5 minutes and then walks
	# for two hours is not making circuits; it is permanently in transit.
	var leg_200: float = 200.0 / WS.MERCHANT_SPEED
	var ratio: float = leg_200 / WS.MERCHANT_REST_TIME
	print("  a 200-tile leg takes %.1f min against a %.1f min rest (ratio %.1fx)" % [
		leg_200 / 60.0, WS.MERCHANT_REST_TIME / 60.0, ratio])
	ck(ratio <= 6.0,
		"travel is a small multiple of rest, not 25x it (ratio %.1fx)" % ratio)
	ck(ratio >= 1.0,
		"...but travel still costs MORE than resting, so a circuit means something (%.1fx)" % ratio)

	print("")
	if fails == 0:
		print("[PROBE] PASS a road merchant is worth stopping for")
	else:
		print("[PROBE] FAIL %d check(s)" % fails)
	quit(1 if fails > 0 else 0)
