# Phantasia Revival — Comprehensive Test Checklist

Use `/gmhelp` for admin commands. Promote your test account first:
```bash
godot --headless --script admin_tool.gd -- promote <username>
```

---

## 1. Authentication & Account

- [ ] Register new account (valid username/password)
- [ ] Register rejects short username (<3 chars)
- [ ] Register rejects duplicate username
- [ ] Register rejects short password (<4 chars)
- [ ] Login with correct credentials
- [ ] Login rejects wrong password
- [ ] Login rejects unknown username
- [ ] Logout account (returns to login screen)
- [ ] Change password (/changepassword or settings)
- [ ] Changed password works on next login

## 2. Character Lifecycle

- [ ] Create character — Fighter
- [ ] Create character — Barbarian
- [ ] Create character — Paladin
- [ ] Create character — Wizard
- [ ] Create character — Sorcerer
- [ ] Create character — Sage
- [ ] Create character — Thief
- [ ] Create character — Ranger
- [ ] Create character — Ninja
- [ ] Create each race (Human, Elf, Dwarf, Orc, Halfling, Undead)
- [ ] Select existing character from list
- [ ] Delete character (confirm dialog)
- [ ] Max 6 characters per account enforced
- [ ] Permadeath: character dies and is removed
- [ ] Permadeath: death message shows stats, cause, BP earned
- [ ] Permadeath: leaderboard entry created (non-admin)

## 3. House / Sanctuary

- [ ] House auto-created on first login
- [ ] View house main screen
- [ ] House storage: deposit item (Home Stone)
- [ ] House storage: withdraw item
- [ ] House storage: discard item
- [ ] House storage: capacity enforced (base 20 + upgrades)
- [ ] Registered companions: register via Home Stone
- [ ] Registered companions: checkout to new character
- [ ] Registered companions: return on death
- [ ] Registered companions: unregister
- [ ] Companion Kennel: walk onto K tile
- [ ] Kennel: view companions with bonuses
- [ ] Kennel: release companion
- [ ] Kennel: register companion to house
- [ ] Kennel: capacity enforced per upgrade level
- [ ] Fusion Station: walk onto F tile
- [ ] Fusion: 3 same-type → sub-tier+1
- [ ] Fusion: 8 mixed sub-tier 8 → random T9
- [ ] Fusion: rejects duplicate indices
- [ ] Fusion: rejects insufficient companions
- [ ] All 16 upgrade types purchasable with BP
- [ ] Upgrade costs correct per level
- [ ] Upgrade effects applied (test flee_chance, xp_bonus, stat bonuses)
- [ ] XP Bonus upgrade: kill monster → XP includes house bonus (`/setbp`, buy upgrade, compare XP)
- [ ] Gathering Bonus upgrade: fish/mine/chop → increased material quantity
- [ ] Baddie Points awarded on death (formula correct)
- [ ] House stats updated on death (characters_lost, highest_level, etc.)
- [ ] Home Stone (Egg): sends egg to house storage
- [ ] Home Stone (Supplies): sends consumables to storage — items stack with existing
- [ ] Home Stone (Equipment): sends equipped item to storage
- [ ] Home Stone (Companion): register OR kennel choice
- [ ] Home Stone stacking: send 2 same-type potions → single stacked entry (not 2 slots)
- [ ] `/setbp <n>` sets BP correctly (admin)

## 4. Inventory & Equipment

- [ ] View inventory (items listed with details)
- [ ] Equip weapon
- [ ] Equip armor
- [ ] Equip helm
- [ ] Equip shield
- [ ] Equip boots
- [ ] Equip ring
- [ ] Unequip item (returns to inventory)
- [ ] Item details view (stats, affixes, value)
- [ ] Sort inventory (by type, rarity, level, value, name)
- [ ] Salvage single item → receives ESS
- [ ] Salvage result message stays visible (not wiped)
- [ ] View materials (grouped by type)
- [ ] Materials view stays visible
- [ ] Auto-salvage settings (tier threshold)
- [ ] Auto-salvage affix filter: open via Salvage → Affix button
- [ ] Auto-salvage affix filter: select up to 2 affixes, Save sends to server
- [ ] Auto-salvage affix filter: matching items auto-salvaged on full inventory
- [ ] Auto-salvage affix filter: Clear removes affix filters
- [ ] Scroll of Finding: use → select option → scroll consumed, ability active
- [ ] Scroll of Finding: use → Cancel → scroll returned to inventory
- [ ] Scroll of Summoning: use → select monster → scroll consumed, next fight is chosen monster
- [ ] Scroll of Summoning: use → Cancel → scroll returned to inventory
- [ ] Lock/unlock items (locked items protected from salvage)
- [ ] Inventory full behavior (drop or reject)
- [ ] `/giveitem <tier>` gives item correctly (admin)
- [ ] `/giveitem <tier> weapon` gives weapon specifically (admin)
- [ ] `/giveconsumable <type> [tier]` gives specific consumable (admin)

## 5. Abilities

- [ ] View ability list (all unlocked abilities shown)
- [ ] Equip ability to slot
- [ ] Unequip ability from slot
- [ ] Ability keybinds (map ability to key)
- [ ] Keybind persists across sessions
- [ ] All 9 Warrior abilities usable in combat
- [ ] All 6 Mage abilities usable in combat
- [ ] All 5 Trickster abilities usable in combat
- [ ] Ability resource costs deducted (stamina/mana/energy)
- [ ] Cooldowns enforced

## 6. Combat

- [ ] Hunt action triggers encounter
- [ ] Monster art displays correctly
- [ ] Attack action deals damage
- [ ] Defend action reduces damage taken
- [ ] Flee action (success/failure)
- [ ] Use item in combat (potion/scroll)
- [ ] Victory: XP awarded, level up if applicable
- [ ] Victory: loot drops received
- [ ] Victory: companion XP awarded
- [ ] Defeat: permadeath triggered
- [ ] Companion bonuses applied (HP, attack, defense, etc.)
- [ ] Variant monsters (rare, uncommon, etc.) spawn correctly
- [ ] Flock encounters (2-4 consecutive fights)
- [ ] Monster abilities trigger (enrage, heal, poison, etc.)
- [ ] Equipment wear/durability (corrosive, sunder)
- [ ] Combat rate limit: rapid-click attack → only processes every 300ms (no double actions)
- [ ] Wish Granter: defeat → wish options appear (no "gems" option, has "experience" option)
- [ ] Wish Granter: select Experience → XP awarded
- [ ] Wish Granter in dungeon: defeat in dungeon → wish buttons appear (not dungeon nav)
- [ ] `/godmode` toggle — take 0 damage (admin)
- [ ] `/spawnmonster <type> <level>` spawns correct monster (admin)
- [ ] `/spawnwish` spawns 1HP Wish Granter with 100% wish chance (admin)
- [ ] `/heal` restores all resources (admin)

## 7. Quests & Trading Posts

- [ ] Arrive at trading post (safe zone indicator)
- [ ] View trading post shop
- [ ] Buy item from shop
- [ ] View available quests
- [ ] Accept quest
- [ ] Quest progress tracks correctly (kill count, etc.)
- [ ] Abandon quest
- [ ] Turn in completed quest (rewards given)
- [ ] Quest reward colors correct (gold, XP, items)
- [ ] Recharge at trading post (HP/mana/stamina/energy)
- [ ] Wits training at trading post
- [ ] Trading post categories displayed correctly (haven, market, etc.)
- [ ] Trading post map colors correct per category
- [ ] Trading post ASCII art varies by category
- [ ] KILL_TIER quest type works
- [ ] BOSS_HUNT quest type works (bounty at location)
- [ ] RESCUE quest type works
- [ ] RESCUE quest description includes dungeon entrance hint ("Look for D near this post")
- [ ] Dynamic quest generation (seeded per post per day)
- [ ] `/completequest` marks quests done (admin)
- [ ] `/resetquests` clears quest log (admin)

## 8. Gathering

### Fishing
- [ ] Fish action available at water tiles
- [ ] Fishing minigame (wait → reaction phase)
- [ ] Catch result displayed
- [ ] Fishing skill increases
- [ ] Various catch types (fish, materials)

### Mining
- [ ] Mine action at ore deposits
- [ ] Mining minigame (multi-reaction for higher tiers)
- [ ] Tier 1-9 ore deposits scale by distance
- [ ] Mining skill increases
- [ ] Gem/mineral bonus catches

### Logging
- [ ] Chop action at dense forest
- [ ] Logging minigame
- [ ] Tier 1-6 forests scale by distance
- [ ] Logging skill increases
- [ ] Sap/resin bonus catches

- [ ] `/givemats <id> <amount>` gives materials (admin)

## 9. Crafting

- [ ] View crafting recipes (/craft or action bar)
- [ ] Recipes filtered by available materials
- [ ] Craft single item
- [ ] Craft multiple (if supported)
- [ ] Materials consumed on craft
- [ ] Product added to inventory
- [ ] Quality system (Poor/Normal/Good/Excellent/Masterwork)
- [ ] Crafting skill progression

## 10. Dungeons

- [ ] View dungeon list
- [ ] Enter dungeon at entrance (D tile on map)
- [ ] Level warning for under-leveled characters
- [ ] Navigate dungeon (N/S/E/W within dungeon)
- [ ] Dungeon encounters use boss monster type
- [ ] Treasure rooms give loot
- [ ] Boss fight at final floor
- [ ] Boss victory rewards (egg, loot)
- [ ] Exit dungeon (button or death)
- [ ] Dungeon sub-tier system (affects companion tier)
- [ ] Sub-tier display in dungeon info
- [ ] Hotzone dungeon confirmation
- [ ] Go Back option in dungeon
- [ ] Rest in dungeon (partial heal)
- [ ] Dungeon state preserved across combat

## 11. Companions & Eggs

- [ ] View companions (More → Companions)
- [ ] View eggs (More → Eggs)
- [ ] Companion inspection (select → detailed view)
- [ ] Companion abilities listed in inspection
- [ ] Sort companions (level, tier, variant, damage, name, type)
- [ ] Activate companion (add to active party)
- [ ] Dismiss companion
- [ ] Release companion (permanently remove)
- [ ] Release all companions
- [ ] Companion leveling from combat XP
- [ ] Companion max level 10000 enforced
- [ ] Companion bonuses displayed in list view
- [ ] Egg incubation progress (hatch steps)
- [ ] Egg hatching → companion created
- [ ] Egg freezing / unfreezing
- [ ] Frozen egg shows [FROZEN] and PAUSED status
- [ ] Frozen eggs not processed by step counter
- [ ] Egg variants affect appearance and hatch time
- [ ] Companion trading (add/remove in trade window)
- [ ] Egg trading
- [ ] `/giveegg [type]` gives egg (admin)
- [ ] `/givecompanion [type] [tier]` gives companion (admin)
- [ ] `/debughatch` instant-hatches eggs

## 12. NPC Encounters

- [ ] Merchant encounter while traveling
- [ ] Merchant buy items
- [ ] Merchant sell items
- [ ] Merchant sell all
- [ ] Merchant gamble
- [ ] Merchant sell gems
- [ ] Merchant recharge (repair equipment)
- [ ] Blacksmith encounter (wandering)
- [ ] Blacksmith upgrade option
- [ ] Healer encounter (wandering)
- [ ] Healer heal option
- [ ] Rescue NPC encounter (from RESCUE quest)

## 13. Player Trading

- [ ] Request trade with nearby player (/trade <name>)
- [ ] Accept trade request
- [ ] Decline trade request
- [ ] Add item to trade
- [ ] Remove item from trade
- [ ] Add companion to trade
- [ ] Remove companion from trade
- [ ] Add egg to trade
- [ ] Remove egg from trade
- [ ] Both players ready → trade executes
- [ ] Cancel trade (either side)
- [ ] Trade window tabs (Items, Companions, Eggs)
- [ ] Active companions cannot be traded
- [ ] Registered house companions cannot be traded

## 14. PvP (Crucible)

- [ ] Start crucible (/crucible)
- [ ] Crucible combat (player vs scaled monster)
- [ ] Crucible victory rewards
- [ ] Crucible defeat handling
- [ ] Title abilities: Summon, Tax, Gift, Tribute
- [ ] Watch/unwatch combat (/watch, /unwatch)
- [ ] Spectator sees combat updates

## 15. Leaderboards

- [ ] Fallen Heroes leaderboard displays
- [ ] Monster Kills leaderboard displays
- [ ] Trophy Hall leaderboard displays
- [ ] Trophy Hall: "Most Trophies Collected" section shows top collectors ranked
- [ ] Trophy Hall: "First Discoveries" section shows first collector per trophy type
- [ ] Trophy Hall: timestamps work (first collector is correct, not all timestamp 0)
- [ ] Admin character death → NOT on Fallen Heroes
- [ ] Admin character trophies → NOT in Trophy Hall
- [ ] Non-admin deaths appear normally
- [ ] Leaderboard ranks numbered correctly

## 16. Settings & UI

- [ ] Keybinds: Action bar keys (Space, Q, W, E, R)
- [ ] Keybinds: Item selection keys (1-5)
- [ ] Keybinds: Ability keys
- [ ] UI scale adjustment
- [ ] Sound toggle
- [ ] Auto-salvage tier setting (cycle OFF/Com/Unc/Rar)
- [ ] Auto-salvage affix filter setting (Salvage → Affix)
- [ ] Combat button swap (attack/defend position)
- [ ] Online players list clickable (popup info)
- [ ] Map display updates correctly
- [ ] Three-panel layout renders properly

## 17. Chat & Commands

- [ ] Chat message sent and received
- [ ] Whisper/PM sent (/whisper, /w, /msg, /tell)
- [ ] Reply to last whisper (/reply, /r)
- [ ] /who — online players list
- [ ] /examine <player> — player info
- [ ] /help — help page displays
- [ ] /clear — clears output
- [ ] /bug <description> — bug report sent
- [ ] /search <term> — help search
- [ ] /companion — companion info
- [ ] /fish, /craft, /dungeon — mode shortcuts
- [ ] /donate — pilgrimage donation
- [ ] /materials — view crafting materials
- [ ] Unknown command shows error message

## 18. Action Bar

- [ ] Correct buttons in exploration mode (Hunt, Rest, More, etc.)
- [ ] Correct buttons in combat mode (Attack, Defend, Ability, Item, Flee)
- [ ] Correct buttons in inventory mode
- [ ] Correct buttons in merchant mode
- [ ] Correct buttons in trading post mode
- [ ] Correct buttons in dungeon mode
- [ ] Contextual slot 4 (Fish at water, Mine at ore, Chop at forest, Dungeon at D)
- [ ] No hotkey cascading between menu transitions
- [ ] Number keys don't double-trigger in sub-menus
- [ ] Mode exit via hotkey doesn't trigger action bar

## 19. Admin Commands

- [ ] `/gmhelp` shows command list
- [ ] `/setlevel <n>` sets level with correct stats
- [ ] `/setgold <n>` sets gold
- [ ] `/setgems <n>` sets gems
- [ ] `/setessence <n>` sets salvage essence
- [ ] `/setxp <n>` sets XP
- [ ] `/setbp <n>` sets Baddie Points
- [ ] `/godmode` toggle — shows ENABLED/DISABLED
- [ ] `/godmode` — take 0 damage in combat
- [ ] `/heal` — full restore
- [ ] `/giveitem [tier]` — receive item
- [ ] `/giveitem [tier] [slot]` — receive specific slot
- [ ] `/giveegg` — receive random egg
- [ ] `/giveegg <type>` — receive specific egg
- [ ] `/givecompanion` — receive random companion
- [ ] `/givecompanion <type> <tier>` — receive specific companion
- [ ] `/spawnmonster` — fight random monster at your level
- [ ] `/spawnmonster <type> <level>` — fight specific monster
- [ ] `/givemats <id> <amount>` — receive materials
- [ ] `/giveall` — starter kit received
- [ ] `/tp <x> <y>` — teleported to coordinates
- [ ] `/completequest` — all quests marked complete
- [ ] `/completequest <n>` — specific quest marked complete
- [ ] `/resetquests` — quest log cleared
- [ ] `/broadcast <msg>` — all players see announcement
- [ ] `/giveconsumable <type> [tier]` — receive specific consumable
- [ ] `/spawnwish` — spawns 1HP wish granter, guaranteed wish on kill
- [ ] Non-admin gets "Admin access required" for all GM commands
- [ ] Admin promote/demote via admin_tool.gd works

## 20. Networking

- [ ] Client connects to server
- [ ] Client reconnects after disconnect
- [ ] Multiple clients connected simultaneously
- [ ] Character state persists across logout/login
- [ ] Auto-save triggers periodically
- [ ] Server shutdown saves all characters

---

## Test Session Template

**Date:** ____________________
**Tester:** ____________________
**Version:** ____________________
**Admin Account:** ____________________

**Quick Start:**
1. Promote test account: `godot --headless --script admin_tool.gd -- promote <username>`
2. Start server, then client
3. Login, create character
4. `/giveall` for resources
5. `/setlevel 50` for mid-game testing
6. Work through checklist sections

**Notes:**
