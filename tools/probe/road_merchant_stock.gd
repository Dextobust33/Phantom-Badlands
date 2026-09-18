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
	ck(srv.find('var own_stock: Array = get_or_generate_merchant_inventory(') >= 0,
		"the encounter generates the merchant's own wares")
	ck(srv.find('"road_" + merchant_id') >= 0,
		"...keyed per merchant, so its stock is stable while you stand there")
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
