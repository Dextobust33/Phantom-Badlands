# Admin/GM Command Reference

## Promoting an Account

Use the admin tool from the command line:

```bash
godot --headless --script admin_tool.gd -- promote <username>
godot --headless --script admin_tool.gd -- demote <username>
godot --headless --script admin_tool.gd -- info <username>   # Shows admin status
```

Admin status is stored in `accounts.json` as `is_admin: true`.

## Effects of Admin Status

- Admin accounts can use all `/gm*` commands in-game
- Admin characters are **excluded from all 3 leaderboards**:
  - Fallen Heroes (death leaderboard)
  - Monster Kills leaderboard
  - Trophy Hall of Fame
- Admin flag persists across characters (it's on the account, not the character)

## In-Game Commands

All commands are server-gated. Non-admin accounts receive "Admin access required."

Type `/gmhelp` in-game for a quick reference.

### Stats & Resources

| Command | Description | Example |
|---------|-------------|---------|
| `/setlevel <n>` | Set character to level N (recalculates all stats) | `/setlevel 50` |
| `/setgold <n>` | Set gold amount | `/setgold 100000` |
| `/setgems <n>` | Set gems amount | `/setgems 50` |
| `/setessence <n>` | Set salvage essence | `/setessence 5000` |
| `/setxp <n>` | Set XP directly (does not trigger level ups) | `/setxp 500000` |
| `/setbp <n>` | Set Baddie Points on your house | `/setbp 100000` |
| `/godmode` | Toggle invincibility (0 damage from monsters) | `/godmode` |
| `/heal` | Full HP/mana/stamina/energy restore, clears poison/blind | `/heal` |

### Items & Spawning

| Command | Description | Example |
|---------|-------------|---------|
| `/giveitem [tier] [slot]` | Give random item of tier 1-9. Optional slot: weapon, shield | `/giveitem 7` or `/giveitem 5 weapon` |
| `/giveegg [type]` | Give incubating egg. Random if no type specified | `/giveegg Dragon Wyrmling` |
| `/givecompanion [type] [tier]` | Give hatched companion directly | `/givecompanion Chimaera 5` |
| `/spawnmonster [type] [level]` | Force combat with specific monster | `/spawnmonster Orc 25` |
| `/givemats <id> <amount>` | Give crafting materials by ID | `/givemats iron_ore 50` |
| `/giveall` | Starter kit: 50k gold, 100 gems, 5k ESS, materials, items, egg | `/giveall` |

### World & Quests

| Command | Description | Example |
|---------|-------------|---------|
| `/tp <x> <y>` | Free teleport to any coordinates | `/tp 0 0` |
| `/completequest [n]` | Complete quest at index N, or all if no index | `/completequest` |
| `/resetquests` | Clear all active quests | `/resetquests` |
| `/broadcast <msg>` | Send server-wide announcement | `/broadcast Server restarting in 5 minutes` |

## Common Material IDs for /givemats

### Ores
`copper_ore`, `iron_ore`, `steel_ore`, `mithril_ore`, `adamantine_ore`, `orichalcum_ore`, `void_ore`, `celestial_ore`, `primordial_ore`

### Wood
`common_wood`, `oak_wood`, `ash_wood`, `ironwood`, `darkwood`, `worldtree_branch`

### Fish
`small_fish`, `medium_fish`, `large_fish`, `rare_fish`, `deep_sea_fish`, `legendary_fish`

### Herbs
`healing_herb`, `mana_blossom`, `vigor_root`, `shadowleaf`, `phoenix_petal`, `dragon_blood`, `essence_of_life`

### Leather
`ragged_leather`, `leather_scraps`, `thick_leather`, `enchanted_leather`, `dragonhide`, `void_silk`

### Enchanting
`magic_dust`, `arcane_crystal`, `soul_shard`, `enchanted_resin`, `celestial_shard`

### Gems & Minerals
`stone`, `coal`, `rough_gem`, `polished_gem`, `flawless_gem`, `perfect_gem`, `star_gem`

## Monster Types for /spawnmonster and /giveegg

Tier 1: Goblin, Giant Rat, Kobold, Skeleton, Wolf
Tier 2: Orc, Hobgoblin, Gnoll, Zombie, Giant Spider, Wight, Siren, Kelpie, Mimic
Tier 3: Ogre, Troll, Wraith, Wyvern, Minotaur, Gargoyle, Harpy, Shrieker
Tier 4: Giant, Dragon Wyrmling, Demon, Golem, Vampire, Basilisk, Banshee, Naga, Sphinx
Tier 5+: Lich, Hydra, Chimaera, Beholder, Mind Flayer, Dragon, Kraken, Phoenix, Tarrasque

## Notes

- `/setlevel` recalculates all base stats from level 1, applying proper per-level stat gains for the character's class
- `/godmode` uses metadata on the character object; it resets on server restart
- `/giveitem` without a slot picks randomly from the tier's drop table
- `/completequest` marks quests as completed but you still need to turn them in at a Trading Post
- Admin status persists in `accounts.json` — it survives server restarts
