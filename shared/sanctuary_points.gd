extends RefCounted
## SANCTUARY POINTS (Baddie Points) EARNED BY PLAYING - owner ruling 2026-10-20 (docs/design/economy.md 4.7).
##
## Sanctuary upgrades used to be paid only at DEATH. Under permadeath a character lives for hours, so the owner's
## target - roughly one unlock every 20-30 minutes of play - was unreachable at any price. Points now also accrue as
## you play; death keeps the flat attempt payment, the XP, gem and level-milestone terms (kills and quests are paid as
## they happen, so those two terms came out of the death award rather than being paid twice).
##
## ⚠ EVERY RATE HERE IS A FIRST GUESS. The live server has logged no play for a week, so fights-per-hour is unmeasured;
## the target is ~3,250 points an hour (ladder average rung ~1,350 / 25 min). Retune from `valor_ledger.json`
## ("bp_in:*" rows) once there is a week of play.
const POINTS_PER_WIN := 16.0
const BOSS_MULT := 4.0
const POINTS_PER_QUEST := 120
const POINTS_PER_DUNGEON_TIER := 150     # x tier x (1 + 0.25 x (floors - 1)), like the dungeon's gold


## Points for one won fight. A trivial monster pays near nothing so farming weak ones is not the fast route; a
## monster above you pays up to 1.5x.
static func win_points(monster_level: int, player_level: int, is_boss: bool = false) -> int:
	var rel: float = clampf(1.0 + float(monster_level - player_level) / 20.0, 0.1, 1.5)
	var mult: float = BOSS_MULT if is_boss else 1.0
	return maxi(1, int(round(POINTS_PER_WIN * rel * mult)))


static func dungeon_points(dungeon_tier: int, floors: int) -> int:
	return maxi(1, int(round(float(POINTS_PER_DUNGEON_TIER) * float(maxi(1, dungeon_tier)) * (1.0 + 0.25 * float(maxi(1, floors) - 1)))))
