# Combat Simulation Results

This directory contains output from the combat simulator tool.

## Files

- `YYYY-MM-DD_results.json` - Raw simulation data in JSON format
- `YYYY-MM-DD_summary.md` - Human-readable Markdown summary

## Running the Simulator

### Quick Run (Windows)
```batch
tools\combat_simulator\run_simulation.bat
```

### Manual Run
```bash
"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" ^
    --headless --path "C:\Users\Dexto\Documents\phantasia-revival" ^
    --script "res://tools/combat_simulator/simulator.gd"
```

## Understanding the Results

### Class Performance Table

| Column | Meaning |
|--------|---------|
| Avg Win Rate | Average percentage of fights won across all matchups |
| Avg Damage Taken | Average HP lost per fight (before death effects) |
| Avg Rounds | Average number of combat rounds |
| Best Matchup | Monster/level combination with highest win rate |
| Worst Matchup | Monster/level combination with lowest win rate |

### Monster Danger Rankings

| Column | Meaning |
|--------|---------|
| Avg Win Rate vs | Average player win rate against this monster |
| Empirical Lethality | Calculated danger from simulation data |
| Formula Lethality | Danger calculated by current formula |
| Delta | Percentage difference (positive = more dangerous than formula suggests) |

### Lethality Comparison

Monsters with **large positive delta** are more dangerous than the formula predicts.
These may need their abilities weighted higher in the lethality formula.

Monsters with **large negative delta** are easier than expected.
These may have overweighted abilities or undertuned stats.

### Ability Impact Analysis

Shows how monster abilities affect player win rates.
Higher "Avg Impact" means the ability significantly reduces player success.

## Configuration

Default settings in `simulator.gd`:

```gdscript
CLASSES = ["Fighter", "Barbarian", "Paladin", "Wizard", "Sorcerer", "Sage", "Thief", "Ranger", "Ninja"]
LEVELS = [5, 10, 25, 50, 75, 100]
GEAR_QUALITIES = ["poor", "average", "good"]
MONSTER_LEVEL_OFFSETS = [-5, 0, 5, 10, 20]
ITERATIONS = 1000
```

Modify these in the script to:
- Test specific classes/levels
- Change iteration count for faster/more accurate runs
- Add more monster level offsets for difficulty analysis

## Balance Recommendations

After reviewing results:

1. **High Delta Monsters** (>25%): Consider adjusting lethality weights
2. **Low Class Win Rates** (<70% at same level): May need buffs
3. **High Class Win Rates** (>95% at same level): May need nerfs
4. **Ability Outliers**: Abilities with >20% win rate impact may need tuning

## Technical Notes

- Simulation uses `shared/combat_manager.gd` damage formulas
- Equipment bonuses from `shared/character.gd` equipment system
- Monster stats from `shared/monster_database.gd`
- Balance config from `server/balance_config.json`

The simulator is deterministic per run but uses `randi()` for combat rolls,
so results will vary slightly between runs. Use higher iterations for
more stable results.
