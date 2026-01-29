# Balance Revert Notes (v0.8.84)

This file documents balance changes made in v0.8.79-v0.8.84 and how to revert them.

## Changes Made

### 1. Player Damage Penalty (combat_manager.gd ~line 3131)
**Current (v0.8.83):**
```gdscript
# 1.5% per level, max 25%
var lvl_penalty = min(0.25, lvl_diff * 0.015)
```

**Original:**
```gdscript
# 3% per level, max 50%
var lvl_penalty = min(0.50, lvl_diff * 0.03)
```

### 2. Monster Damage Scaling (combat_manager.gd ~line 3267)
**Current (v0.8.83):** Exponential - `pow(1.04, min(level_diff, 75))`
This is the ORIGINAL formula - no revert needed.

**Brief v0.8.82 change (reverted):**
```gdscript
# Linear: 3% per level, max 50%
var level_bonus = min(0.50, level_diff * 0.03)
total = int(total * (1.0 + level_bonus))
```

### 3. Monster Gear Estimation (monster_database.gd ~line 1461)
**Current (v0.8.83):**
```gdscript
var effective_item_level = int(player_level * 0.95)  # 95% of player level
var rarity_mult = 2.0  # Rare (blue)
```

**Original:**
```gdscript
var effective_item_level = int(player_level * 0.5)  # 50% of player level
var rarity_mult = 1.0  # Common
```

### 4. Monster Initiative (combat_manager.gd ~line 341)
**Current (v0.8.80+):**
```gdscript
var monster_initiative_chance = int(monster_speed / 2.0)  # Base from speed
monster_initiative_chance -= int(player_dex / 10.0)  # DEX reduces
monster_initiative_chance = max(5, monster_initiative_chance)  # Min 5%
```

**Original:**
```gdscript
var monster_initiative_chance = 0
if speed_diff > 0:
    monster_initiative_chance = min(30, speed_diff * 2)
# Only had chance when monster speed > player dex
```

### 5. Magic Bolt Suggestions (client.gd ~line 3704)
**Current (v0.8.84):**
```gdscript
# Must match combat_manager.gd player damage penalty
var level_penalty = minf(0.25, level_diff * 0.015)  # 1.5% per level, max 25%
```

**Original:**
```gdscript
var level_penalty = minf(0.40, level_diff * 0.015)  # 1.5% per level, max 40%
```

### 6. Trading Post Healing Cost (server.gd ~line 4800)
**Current (v0.8.80):**
```gdscript
var distance_multiplier = 7.0 * (1.0 + (distance_from_origin / 50.0))
```

**Original:**
```gdscript
var distance_multiplier = 1.0 + (distance_from_origin / 200.0)
```

## Quick Revert Commands

To fully revert to pre-v0.8.79 balance:

1. **Player damage**: Change `0.015` to `0.03` and `0.25` to `0.50`
2. **Gear estimate**: Change `0.95` to `0.5` and `2.0` to `1.0`
3. **Initiative**: Restore original formula (speed_diff based only)
4. **Trading post**: Change `7.0 *` to `1.0 *` and `/50.0` to `/200.0`

## Git Revert

To revert all balance changes at once:
```bash
git revert --no-commit 6cbb6b1  # v0.8.83
git revert --no-commit f26a429  # v0.8.82
git revert --no-commit 15c5421  # v0.8.80
git revert --no-commit b67a86f  # v0.8.79
git commit -m "Revert balance changes v0.8.79-v0.8.83"
```

Or selectively revert specific commits as needed.
