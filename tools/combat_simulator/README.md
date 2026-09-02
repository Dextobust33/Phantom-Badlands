# Combat Simulator

Tests monster lethality against all 9 character classes to calibrate XP rewards. Runs headless simulations of thousands of fights and outputs analysis comparing empirical danger vs formula predictions.

## Run

```bash
"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path "C:\Users\Dexto\Documents\phantasia-revival" --script "res://tools/combat_simulator/simulator.gd" 2>&1
```

## Output

- `docs/simulation_results/YYYY-MM-DD_results.json` — Raw simulation data
- `docs/simulation_results/YYYY-MM-DD_summary.md` — Human-readable analysis

## Key files

- `simulator.gd` — entry point
- `combat_engine.gd` — damage formulas + abilities
- `simulated_character.gd`
- `gear_generator.gd`
- `results_writer.gd`

## Expanding

1. Add new abilities in `combat_engine.gd` — see `WARRIOR_ABILITIES`, `MAGE_ABILITIES`, `TRICKSTER_ABILITIES` constants
2. Update `simulate_single_combat()` AI to use new abilities strategically
3. Adjust lethality weights in `server/balance_config.json` based on results
4. Empirical lethality: `(1 / win_rate) × (1 + damage_ratio) × 100`
5. Formula: `lethality = (HP×hp_w + STR×str_w + DEF×def_w + Speed×spd_w) × (1 + ability_modifiers)`

## Latest results

`docs/simulation_results/2026-02-06_summary.md` — All classes 89–96% win rate, balance good at Lv5–5000.
