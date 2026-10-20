extends RefCounted
## THE MASTER SMITH - the gold sink worth saving for (owner rulings 2026-10-20, docs/design/economy.md 4.6).
##
## A visiting master offers THREE pieces of gear far above what the player's level drops, for gold only. The visit is
## ANNOUNCED, lasts a limited time, and an offer can be LOCKED to hold it while the player earns the gold. Gold is
## run-bound, so saving carries the risk of dying with it - intended.
##
## ⚠ EVERY NUMBER IS A FIRST GUESS (docs/design/economy.md section 4). Constants live here so the first telemetry
## (`gold_in` / `gold_out:master_smith` in the valor ledger) can retune them in one place.
const GoldEconomyScript = preload("res://shared/gold_economy.gd")

const SLOTS := ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]
const RARITY_LADDER := ["common", "uncommon", "rare", "epic", "legendary", "artifact"]

## Seconds of play between visits (random in this range). ~90-120 minutes.
const CLOCK_MIN := 5400.0
const CLOCK_MAX := 7200.0
## How long an unlocked offer waits at its post, in real seconds.
const OFFER_WINDOW := 1800
## Price: this many kills' gold at the player's level (a saved-up purchase at every level).
const PRICE_IN_KILLS := 800
## Item level above the player's, and the rarity floor.
const LEVEL_MULT := 1.25
const LEVEL_ADD := 5
const MIN_RARITY := "epic"
## Below this level the visit does not happen (a new character has no gold worth saving).
const MIN_LEVEL := 10


static func price(player_level: int) -> int:
	return PRICE_IN_KILLS * GoldEconomyScript.kill_gold(maxi(1, player_level))


static func next_clock(rng: RandomNumberGenerator = null) -> float:
	if rng == null:
		return randf_range(CLOCK_MIN, CLOCK_MAX)
	return rng.randf_range(CLOCK_MIN, CLOCK_MAX)


## One rarity step above the best piece worn, never below MIN_RARITY and capped at artifact.
static func offer_rarity(equipped: Dictionary) -> String:
	var best := RARITY_LADDER.find(MIN_RARITY) - 1
	for slot in SLOTS:
		var it = equipped.get(slot)
		if it is Dictionary:
			best = maxi(best, RARITY_LADDER.find(String(it.get("rarity", "common"))))
	return RARITY_LADDER[clampi(best + 1, RARITY_LADDER.find(MIN_RARITY), RARITY_LADDER.size() - 1)]


static func offer_level(player_level: int) -> int:
	return int(float(player_level) * LEVEL_MULT) + LEVEL_ADD


## Three DISTINCT slots, weakest-worn first (an empty slot is weakest), so the offer is never junk for the player.
static func pick_slots(equipped: Dictionary, count: int = 3) -> Array:
	var scored: Array = []
	for slot in SLOTS:
		var it = equipped.get(slot)
		var score := -1
		if it is Dictionary:
			score = RARITY_LADDER.find(String(it.get("rarity", "common"))) * 1000 + int(it.get("level", 1))
		scored.append({"slot": slot, "score": score, "tie": randf()})
	scored.sort_custom(func(a, b): return a.score < b.score or (a.score == b.score and a.tie < b.tie))
	var out: Array = []
	for i in range(mini(count, scored.size())):
		out.append(String(scored[i].slot))
	return out


## Build an offer. `make_item` is Callable(slot, level, rarity) -> item dict (drop_tables._generate_item in the game).
static func build_offer(character, post: Dictionary, now_unix: int, make_item: Callable) -> Dictionary:
	var rarity: String = offer_rarity(character.equipped)
	var level: int = offer_level(character.level)
	var items: Array = []
	for slot in pick_slots(character.equipped, 3):
		var it: Dictionary = make_item.call(slot, level, rarity)
		if not it.is_empty():
			items.append(it)
	if items.is_empty():
		return {}
	return {
		"post_x": int(post.get("x", 0)), "post_y": int(post.get("y", 0)),
		"post_name": String(post.get("name", "a trading post")),
		"expires": now_unix + OFFER_WINDOW, "locked": false,
		"price": price(character.level), "items": items,
	}


static func is_live(offer: Dictionary, now_unix: int) -> bool:
	if offer.is_empty():
		return false
	return bool(offer.get("locked", false)) or now_unix < int(offer.get("expires", 0))
