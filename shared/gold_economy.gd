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

## The corpse keeps this share of the purse and of the carried gems (the rest is gone with the character).
const CORPSE_GOLD_FRACTION: float = 0.5
const CORPSE_GEM_FRACTION: float = 0.5

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


## The portion of a purse / gem stack a corpse holds.
static func corpse_gold(purse: int) -> int:
	return int(floor(float(maxi(0, purse)) * CORPSE_GOLD_FRACTION))

static func corpse_gems(gems: int) -> int:
	return int(floor(float(maxi(0, gems)) * CORPSE_GEM_FRACTION))
