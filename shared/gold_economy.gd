extends RefCounted
## GOLD - the per-character, run-bound currency. Owner direction 2026-10-14 (playtest sheet item 50).
##
## Gold is NOT Valor. Valor is the ACCOUNT's currency (market, healer, Sanctuary) and survives death;
## gold belongs to one character, is earned by playing, spends on GEAR POWER at the blacksmith and
## enchanter, and mostly dies with its owner - a PORTION (and a portion of the gems) can be
## recovered from the corpse. The old `character.gold` field is a retired migration artefact that
## converts to Valor on login, so gold lives in `gold_purse`.
##
## ⚠ EVERY NUMBER HERE IS A FIRST GUESS. Nothing below was measured against real play - there is no
## data yet on kills-per-level, gems-per-hour or how long a character lives. They are constants in
## ONE table so the first telemetry (and the balance batch) can retune them in one place.

## What a monster gem sells for. Fixed by the owner: 1 gem = 1,000 gold.
const GEM_GOLD_VALUE: int = 1000

## What a corpse keeps of the purse and of the carried gems: a random 10-50% (the rule gems already
## followed - gold takes the same one, so there is one rule, not two). The rest is gone with the
## character.
const CORPSE_SHARE_MIN: float = 0.10
const CORPSE_SHARE_MAX: float = 0.50

## Salvage gold per item level, by rarity. NOT from the item's `value` field: that is the MARKET price
## scale (an L50 epic lists at 26,000, an L200 epic at 401,000) and would pay thousands of gold per
## salvage against ~80 for a kill. Level x rarity keeps a salvage worth a handful of kills.
const SALVAGE_GOLD_PER_LEVEL := {
	"common": 0.5, "uncommon": 1.0, "rare": 2.0, "epic": 4.0, "legendary": 8.0, "artifact": 16.0,
}


## Gold for one kill. Scales with the monster's level so it keeps pace with the upgrade prices.
static func kill_gold(monster_level: int, is_boss: bool = false, empowered_mods: int = 0) -> int:
	var base: float = 5.0 + 1.5 * float(maxi(1, monster_level))
	var mult: float = 1.0 + 0.5 * float(maxi(0, empowered_mods))
	if is_boss:
		mult *= 4.0
	return maxi(1, int(round(base * mult)))


## ===== TEMPERING - the gold sink (blacksmith) =====
## Gold buys per-ITEM tiers: weapons gain damage (attack_bonus), everything else gains HP (hp_bonus).
## Capped per item (the old uncapped blacksmith upgrade was removed on purpose - owner 2026-09-18: "we
## don't want a player to just be able to keep buffing their same item infinitely"), and the power
## lives ON the item, so it is lost with a lost item and travels with a traded one.
## WARNING: costs and gains are first guesses - player power, so they belong to the BALANCE BATCH.
const TEMPER_MAX_TIERS: int = 5
const TEMPER_COST_PER_LEVEL: float = 10.0
const TEMPER_COST_GROWTH: float = 1.8


## Gold for the NEXT tier (tier_to is 1-based: the tier being bought).
static func temper_cost(item_level: int, tier_to: int) -> int:
	return maxi(1, int(round(TEMPER_COST_PER_LEVEL * float(maxi(1, item_level)) * pow(TEMPER_COST_GROWTH, float(maxi(1, tier_to) - 1)))))


## What one tier adds to an item worn in `slot`: {"stat": ..., "amount": ...}.
static func temper_gain(slot: String, item_level: int) -> Dictionary:
	var lvl: float = float(maxi(1, item_level))
	if slot == "weapon":
		return {"stat": "attack_bonus", "amount": maxi(2, int(round(0.12 * lvl)))}
	if slot == "ring" or slot == "amulet":
		return {"stat": "hp_bonus", "amount": maxi(6, int(round(0.55 * lvl)))}
	return {"stat": "hp_bonus", "amount": maxi(10, int(round(0.9 * lvl)))}


## ===== REWORK - the enchanter's gold sink =====
## Rework is gear power, so by the owner's rule (Valor = market/services, gold = gear power) it is
## priced in GOLD, rising with each rework on the item. A committed Enchanter works for free, as they
## always did for Valor - the materials are the Enchanter's real cost.
static func rework_gold(item_level: int, reworks_done: int) -> int:
	return maxi(1, int(round(4.0 * float(maxi(1, item_level)) * (1.0 + 0.6 * float(maxi(0, reworks_done))))))


## Gold a dungeon pays when cleared (graded by the INSTANCE's tier, never the type's).
static func dungeon_clear_gold(dungeon_tier: int, floors: int) -> int:
	return maxi(1, int(round(120.0 * float(maxi(1, dungeon_tier)) * (1.0 + 0.25 * float(maxi(1, floors) - 1)))))


## Gold a quest pays on turn-in, from its level.
static func quest_gold(quest_level: int) -> int:
	return maxi(1, int(round(20.0 + 6.0 * float(maxi(1, quest_level)))))


## Gold lying on a dungeon floor, from the floor's loot level.
static func floor_gold(loot_level: int) -> int:
	return maxi(1, int(round(8.0 + 3.0 * float(maxi(1, loot_level)))))


## Gold a salvaged item pays (in addition to its materials), from its level and rarity.
static func salvage_gold(item: Dictionary) -> int:
	var per: float = float(SALVAGE_GOLD_PER_LEVEL.get(String(item.get("rarity", "common")), 0.5))
	return maxi(1, int(round(per * float(maxi(1, int(item.get("level", 1)))))))


## The portion of a purse OR a gem stack that a corpse holds. Rolled, so a death is never certain
## to cost exactly half.
static func corpse_share(amount: int) -> int:
	if amount <= 0:
		return 0
	return int(float(amount) * randf_range(CORPSE_SHARE_MIN, CORPSE_SHARE_MAX))
