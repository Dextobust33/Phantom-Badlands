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

## Gear selling pays this share of the item's value in gold.
const SELL_VALUE_FRACTION: float = 0.5


## Gold for one kill. Scales with the monster's level so it keeps pace with the upgrade prices.
static func kill_gold(monster_level: int, is_boss: bool = false, empowered_mods: int = 0) -> int:
	var base: float = 5.0 + 1.5 * float(maxi(1, monster_level))
	var mult: float = 1.0 + 0.5 * float(maxi(0, empowered_mods))
	if is_boss:
		mult *= 4.0
	return maxi(1, int(round(base * mult)))


## Gold a dungeon pays when cleared (graded by the INSTANCE's tier, never the type's).
static func dungeon_clear_gold(dungeon_tier: int, floors: int) -> int:
	return maxi(1, int(round(120.0 * float(maxi(1, dungeon_tier)) * (1.0 + 0.25 * float(maxi(1, floors) - 1)))))


## Gold a quest pays on turn-in, from its level.
static func quest_gold(quest_level: int) -> int:
	return maxi(1, int(round(20.0 + 6.0 * float(maxi(1, quest_level)))))


## Gold lying on a dungeon floor, from the floor's loot level.
static func floor_gold(loot_level: int) -> int:
	return maxi(1, int(round(8.0 + 3.0 * float(maxi(1, loot_level)))))


## Gold a salvaged item pays (in addition to its materials): a share of its listed value.
static func salvage_gold(item: Dictionary) -> int:
	return maxi(1, int(floor(float(int(item.get("value", 10))) * SELL_VALUE_FRACTION)))


## The portion of a purse OR a gem stack that a corpse holds. Rolled, so a death is never certain
## to cost exactly half.
static func corpse_share(amount: int) -> int:
	if amount <= 0:
		return 0
	return int(float(amount) * randf_range(CORPSE_SHARE_MIN, CORPSE_SHARE_MAX))
