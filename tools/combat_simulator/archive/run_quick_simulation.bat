@echo off
echo === Phantasia Combat Simulator (Quick) ===
echo.
echo Running quick simulation with reduced parameters...
echo.

"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path "C:\Users\Dexto\Documents\phantasia-revival" --script "res://tools/combat_simulator/quick_simulation.gd"

echo.
echo Results saved to docs\simulation_results\
echo.
pause
