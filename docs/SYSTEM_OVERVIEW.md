# Phantom Badlands - System Overview (AI Context Reference)

Dense reference for the Phantom Badlands codebase. Text-based multiplayer RPG, Godot 4.6, GDScript.

---

## 1. Data Flow Diagram

```
CLIENT (client.gd ~21k lines)                    SERVER (server.gd ~14k lines)
  StreamPeerTCP ──JSON+newline──►  TCPServer (port 9080)
  connection.put_data()            peers{peer_id: {connection, buffer}}
                  ◄──JSON+newline──  send_to_peer(peer_id, dict)

  _process() polls TCP             _process() polls all peer connections
  Parses JSON, dispatches by        handle_message() match on msg_type
  msg["type"] in match statement

SERVER SUBSYSTEMS:
  server.gd ──► PersistenceManager (persistence_manager.gd)
                  └── SQLite-backed JSON files under user://data/
  server.gd ──► CombatManager (combat_manager.gd)
                  └── Turn-based engine, ability system, party combat
  server.gd ──► WorldSystem (world_system.gd)
                  └── Procedural terrain, tile types, LOS, map gen, A* roads, merchant circuits
  server.gd ──► ChunkManager (chunk_manager.gd)
                  └── 32x32 chunks, delta JSON, tile storage
  server.gd ──► MonsterDatabase (monster_database.gd)
                  └── 9-tier monsters, stat scaling, abilities
  server.gd ──► DropTables (drop_tables.gd)
                  └── Loot gen, gathering catches, salvage, valor calc
  server.gd ──► CraftingDatabase (crafting_database.gd)
                  └── Recipes, materials, quality system
  server.gd ──► QuestDatabase (quest_database.gd)
                  └── Dynamic quests, seeded per post per day
  server.gd ──► DungeonDatabase (dungeon_database.gd)
                  └── Dungeon types, floors, bosses, sub-tiers
  server.gd ──► NpcPostDatabase (npc_post_database.gd)
                  └── Procedural NPC post placement (~18 from seed)
  server.gd ──► TradingPostDatabase (trading_post_database.gd)
                  └── Trading post categories, colors, shapes
```

### Common Operation Flows

```
MOVEMENT:
  C: {type:"move", direction:N/S/E/W}
  S: {type:"location", x, y, terrain, nearby_players, ...}
  S: {type:"character_update", character:{...}}

COMBAT:
  C: {type:"hunt"}
  S: {type:"combat_start", monster:{...}, use_client_art:true}
  C: {type:"combat", action:"attack"/"ability"/"flee"}
  S: {type:"combat_update", messages:[], monster:{...}}
  S: {type:"combat_end", result:"victory"/"defeat"/"fled", drops:[], xp:N}

CRAFTING:
  C: {type:"craft_list", skill:"blacksmithing"}
  S: {type:"craft_list", recipes:[], skill_level:N}
  C: {type:"craft_item", recipe_id:"iron_sword"}
  S: {type:"craft_challenge", question:str, options:[]} (if not auto-skip)
  C: {type:"craft_challenge_answer", answer:N}
  S: {type:"craft_result", success:bool, item:{}, quality:str}

GATHERING:
  C: {type:"gathering_start", gathering_type:"mining"}
  S: {type:"gathering_round", options:[], phase:"choosing"}
  C: {type:"gathering_choice", choice:N}
  S: {type:"gathering_result", correct:bool, material:{}} or {type:"gathering_complete"}

PARTY COMBAT:
  S: {type:"party_combat_start", monster:{}, party_members:[]}
  S: {type:"party_combat_update", current_turn:name, messages:[]}
  C: {type:"combat", action:"attack"}  (same as solo)
  S: {type:"party_combat_end", result:str, survivors:[]}
```

---

## 2. All Mode Flags (client.gd)

### Game State Enum
| Value | Meaning |
|-------|---------|
| `DISCONNECTED` | Not connected to server |
| `CONNECTED` | TCP connected, not logged in |
| `LOGIN_SCREEN` | Login/register UI |
| `HOUSE_SCREEN` | Sanctuary (between login and char select) |
| `CHARACTER_SELECT` | Picking/creating character |
| `PLAYING` | In game |
| `DEAD` | Permadeath screen |

### Primary Mode Booleans (only one should be active at a time in most cases)

| Flag | Line | Trigger | Controls |
|------|------|---------|----------|
| `inventory_mode` | 648 | I key / action bar | Item list, equip, salvage, sort, materials view |
| `ability_mode` | 680 | Abilities button (More) | Ability equip/unequip/keybind |
| `settings_mode` | 366 | S key / settings button | Key rebinding, auto-salvage config |
| `companions_mode` | 808 | More > Companions | Companion list, activate, release, inspect |
| `eggs_mode` | 818 | More > Eggs | Egg incubation list with ASCII art |
| `crafting_mode` | 749 | At station + Craft button | Recipe list, craft execution |
| `crafting_challenge_mode` | 766 | Server sends craft_challenge | Crafting minigame Q&A |
| `build_mode` | 772 | Build button (in own enclosure) | Place/demolish structures |
| `build_direction_mode` | 773 | After selecting item to place | Directional placement |
| `build_demolish_mode` | 775 | Demolish sub-action | Directional demolition |
| `storage_mode` | 791 | At storage chest | Deposit/withdraw items |
| `more_mode` | 797 | Tab key / More button | Submenu: companions, eggs, changelog, etc. |
| `job_mode` | 801 | Jobs button | Job info, commit to gathering/specialty |
| `market_mode` | 997 | Market button at trading post | Browse/list/buy on Open Market |
| `dungeon_mode` | 1018 | Enter dungeon | Dungeon navigation, floor exploration |
| `dungeon_list_mode` | 1023 | At dungeon entrance D | Viewing available dungeons |
| `title_mode` | 946 | Title system | Title menu and abilities |
| `title_ability_mode` | 948 | Selecting title ability | Target selection for title power |
| `title_stat_selection_mode` | 903 | Bless ability | Stat selection for Bless |
| `title_broadcast_mode` | 952 | Broadcast ability | Entering broadcast text |
| `quest_view_mode` | 910 | Viewing quest list at post | Quest accept/view |
| `quest_log_mode` | 917 | Quest Log button | Active quest tracker |
| `wish_selection_mode` | 921 | Wish Granter drops | Choosing a wish buff |
| `monster_select_mode` | 925 | Scroll of Summoning | Picking monster to summon |
| `monster_select_confirm_mode` | 928 | After picking monster | Confirm selection |
| `target_farm_mode` | 933 | Target Farm scroll | Choose monster type to farm |
| `home_stone_mode` | 939 | Using Home Stone item | Select what to send home |
| `gathering_mode` | 962 | Fish/Mine/Chop/Forage action | Visual minigame for gathering |
| `harvest_mode` | 983 | Post-combat Soldier harvest | Harvesting monster parts |
| `leaderboard_mode` | 959 | String: "fallen_heroes"/"monster_kills"/"trophy_hall" |
| `bug_report_mode` | 1032 | /bug command | Entering bug description |
| `teleport_mode` | 512 | Teleport command | Entering coordinates |
| `party_menu_mode` | 894 | Party management | View/manage party |
| `party_appoint_mode` | 893 | Appointing new leader | Selecting member |
| `rune_apply_mode` | 671 | Using a rune from inventory | Selecting gear slot |

### Tutorial Overlay

| Flag | Type | Purpose |
|------|------|---------|
| `tutorial_active` | `bool` | Tutorial sequence in progress |
| `tutorial_step` | `int` | Current step index (0-6) |

`TUTORIAL_STEPS` constant defines 7 steps. Triggered on `character_created` when `is_first_character` is true. While active and not in combat, action bar slots 0-1 are overridden with Next/Skip buttons.

### Combat Mode Flags

| Flag | Line | Trigger | Controls |
|------|------|---------|----------|
| `in_combat` | 630 | combat_start received | Combat UI, action bar shows combat actions |
| `combat_item_mode` | 633 | Use Item in combat | Selecting consumable to use |
| `party_combat_active` | 897 | Our turn in party combat | Can take combat actions |
| `party_waiting_for_turn` | 896 | Not our turn | Shows "waiting" state |
| `party_combat_spectating` | 895 | Dead/fled in party combat | Watch-only mode |

### Location Flags (set by server `location` message)

| Flag | Line | Trigger | Controls |
|------|------|---------|----------|
| `at_merchant` | 735 | Bump into merchant NPC | Sell/buy/gamble UI |
| `at_trading_post` | 744 | Enter trading post | Shop/quests/market/recharge |
| `at_guard_post` | 714 | At guard post tile | Hire/feed/dismiss guard |
| `at_bounty` | 718 | At bounty target location | Engage button |
| `at_water` | 823 | Fishable water tile | Fish action (slot 4) |
| `at_ore_deposit` | 826 | Mineable ore tile | Mine action (slot 4) |
| `at_dense_forest` | 830 | Harvestable forest tile | Chop action (slot 4) |
| `at_foraging_spot` | 834 | Forageable node | Forage action (slot 4) |
| `at_dungeon_entrance` | 839 | D tile on map | Dungeon action (slot 4) |
| `at_corpse` | 845 | Player corpse location | Loot action |
| `in_own_enclosure` | 779 | Inside own player post | Build/name actions |
| `in_player_post` | 780 | Inside any player post | Safe zone indicator |

### Trade/Party Flags

| Flag | Line | Trigger | Controls |
|------|------|---------|----------|
| `in_trade` | 855 | Trade accepted | Trade window with tabs |
| `in_party` | 879 | Party formed | Party UI, snake movement |
| `house_mode` | 523 | String: "main"/"storage"/"companions"/"upgrades" | Sanctuary screen tabs |

---

## 3. All Message Types

### Client-to-Server (C->S)

| Type | Key Fields | Purpose |
|------|-----------|---------|
| `register` | username, password | Create account |
| `login` | username, password | Authenticate |
| `list_characters` | - | Get character list |
| `select_character` | index | Load character |
| `create_character` | name, class, race | New character |
| `delete_character` | index | Delete character |
| `request_character_list` | - | Alias for list_characters |
| `chat` | message | Public chat |
| `private_message` | target, message | Whisper |
| `move` | direction (0-3) | N/S/E/W movement |
| `hunt` | - | Start random encounter |
| `combat` | action (attack/ability/flee) + ability_name | Combat turn |
| `combat_use_item` | item_index | Use item in combat |
| `wish_select` | choice | Choose wish buff |
| `continue_flock` | - | Continue flock chain |
| `rest` | - | Rest to heal |
| `get_players` | - | Online player list |
| `examine_player` | target | View player info |
| `logout_character` | - | Return to char select |
| `logout_account` | - | Full logout |
| `change_password` | old_password, new_password | Change password |
| `inventory_use` | index | Use inventory item |
| `inventory_equip` | index | Equip item |
| `inventory_unequip` | slot | Unequip slot |
| `inventory_discard` | index | Discard item |
| `inventory_sort` | sort_type | Sort inventory |
| `inventory_lock` | index | Toggle lock on item |
| `inventory_salvage` | index/indices | Salvage item(s) |
| `auto_salvage_settings` | max_rarity | Set auto-salvage threshold |
| `auto_salvage_affix_settings` | affixes[] | Set affix auto-salvage filter |
| `merchant_sell` | index | Sell item to merchant |
| `merchant_sell_all` | - | Sell all unlocked items |
| `merchant_sell_gems` | quantity | Sell monster gems |
| `merchant_gamble` | tier | Gamble for item |
| `merchant_buy` | index | Buy from merchant |
| `merchant_recharge` | - | Recharge at merchant |
| `merchant_leave` | - | Leave merchant |
| `trading_post_shop` | - | Enter TP shop |
| `trading_post_quests` | - | View quest board |
| `trading_post_recharge` | - | Recharge at TP |
| `trading_post_wits_training` | - | Train wits (Trickster) |
| `trading_post_leave` | - | Leave trading post |
| `quest_accept` | quest_index | Accept quest |
| `quest_abandon` | quest_index | Abandon quest |
| `quest_turn_in` | quest_index | Turn in quest |
| `get_quest_log` | - | Get active quests |
| `get_abilities` | - | Get ability list |
| `equip_ability` | slot, ability_name | Equip ability to slot |
| `unequip_ability` | slot | Remove ability from slot |
| `set_ability_keybind` | slot, key | Set ability hotkey |
| `activate_companion` | name | Set active companion |
| `dismiss_companion` | - | Dismiss active companion |
| `release_companion` | index | Release companion |
| `release_all_companions` | - | Release all non-active |
| `toggle_egg_freeze` | index | Freeze/unfreeze egg |
| `gathering_start` | gathering_type | Begin mining/logging/etc |
| `gathering_choice` | choice | Minigame answer |
| `gathering_end` | - | Cancel gathering |
| `harvest_start` | - | Begin monster harvest |
| `harvest_choice` | choice | Harvest minigame answer |
| `equip_tool` | index | Equip gathering tool |
| `unequip_tool` | slot | Unequip tool |
| `job_info` | - | Get job status |
| `job_commit` | category, job_name | Commit to job |
| `craft_list` | skill | List recipes for skill |
| `craft_item` | recipe_id | Craft a recipe |
| `craft_challenge_answer` | answer | Crafting minigame answer |
| `use_rune` | rune_index, target_slot | Apply rune to gear |
| `build_place` | item_index, direction | Place structure |
| `build_demolish` | direction | Demolish structure |
| `name_post` | enclosure_index, name | Name player post |
| `inn_rest` | - | Rest at Inn |
| `storage_access` | - | Open storage chest |
| `storage_deposit` | index | Put item in storage |
| `storage_withdraw` | slot | Take item from storage |
| `guard_hire` | level | Hire guard |
| `guard_feed` | - | Feed guard |
| `guard_dismiss` | - | Dismiss guard |
| `dungeon_list` | - | List available dungeons |
| `dungeon_enter` | dungeon_id | Enter dungeon |
| `dungeon_move` | direction | Move in dungeon |
| `dungeon_exit` | - | Exit dungeon |
| `dungeon_go_back` | - | Previous floor |
| `dungeon_rest` | - | Rest in dungeon |
| `dungeon_state` | - | Request dungeon state |
| `hotzone_confirm` | confirm | Confirm hotzone entry |
| `loot_corpse` | confirm | Loot player corpse |
| `claim_title` | title | Claim realm title |
| `title_ability` | ability | Use title ability |
| `get_title_menu` | - | Get title menu data |
| `forge_crown` | - | Forge Crown of the North |
| `trade_request` | target | Initiate trade |
| `trade_response` | accept | Accept/decline trade |
| `trade_offer` | index | Add item to trade |
| `trade_remove` | index | Remove item from trade |
| `trade_add_companion` | index | Add companion to trade |
| `trade_remove_companion` | index | Remove companion |
| `trade_add_egg` | index | Add egg to trade |
| `trade_remove_egg` | index | Remove egg |
| `trade_ready` | - | Mark ready to trade |
| `trade_cancel` | - | Cancel trade |
| `pilgrimage_donate` | amount | Donate valor |
| `summon_response` | accept | Accept/decline summon |
| `start_crucible` | - | Start crucible combat |
| `blacksmith_choice` | action, slot_index, affix_index | Blacksmith repair/upgrade |
| `healer_choice` | action | Healer heal/cure |
| `rescue_npc_response` | action, item_index | Rescue NPC response |
| `engage_bounty` | - | Fight bounty target |
| `bug_report` | description | Submit bug report |
| `watch_request` | target | Request to watch player |
| `watch_approve` | target | Approve watch request |
| `watch_deny` | target | Deny watch request |
| `watch_stop` | - | Stop watching |
| `toggle_cloak` | - | Toggle invisibility |
| `toggle_swap_attack` | attack_style | Change attack approach |
| `teleport` | x, y | Teleport to coords |
| `home_stone_select` | selections | Home Stone item choices |
| `home_stone_cancel` | - | Cancel Home Stone |
| `home_stone_companion_response` | choice | Register vs Kennel |
| `monster_select_confirm` | monster_name | Confirm summoned monster |
| `monster_select_cancel` | - | Cancel scroll |
| `target_farm_select` | monster_name | Confirm farm target |
| `target_farm_cancel` | - | Cancel farm scroll |
| `market_browse` | category, page | Browse market listings |
| `market_list_item` | index | List item on market |
| `market_list_egg` | index | List egg on market |
| `market_list_material` | material, quantity | List materials |
| `market_list_all` | list_type | Bulk list items |
| `market_buy` | listing_id, post_id, quantity | Buy from market |
| `market_cancel` | listing_id, post_id | Cancel listing |
| `market_cancel_all` | - | Cancel all listings |
| `market_my_listings` | - | View own listings |
| `house_request` | - | Get house data |
| `house_upgrade` | upgrade_id | Buy house upgrade |
| `house_discard_item` | index | Discard from storage |
| `house_unregister_companion` | slot | Unregister companion |
| `house_register_from_storage` | index | Register from storage |
| `house_kennel_release` | index | Release from kennel |
| `house_kennel_register` | index | Register from kennel |
| `house_fusion` | indices[] | Fuse companions |
| `party_invite` | target | Invite to party |
| `party_invite_response` | accept | Accept/decline invite |
| `party_lead_choice_response` | choice | Lead or Follow |
| `party_disband` | - | Disband party (leader) |
| `party_leave` | - | Leave party |
| `party_appoint_leader` | index | Appoint new leader |
| `gm_*` | varies | Admin/GM commands |

### Server-to-Client (S->C)

| Type | Key Fields | Purpose |
|------|-----------|---------|
| `welcome` | motd | Server greeting |
| `server_message` | message | System message |
| `server_broadcast` | message | Broadcast to all |
| `register_success/failed` | message | Registration result |
| `login_success/failed` | message, account_id | Login result |
| `character_list` | characters[] | Available characters |
| `character_loaded` | character:{} | Full character data |
| `character_created` | character:{} | New character data |
| `character_deleted` | - | Deletion confirmed |
| `character_update` | character:{} | Stats/inventory refresh |
| `text` | message | Generic server text (BBCode) |
| `error` | message | Error text |
| `chat` | sender, message, level | Public chat message |
| `private_message` | sender, message | Whisper received |
| `private_message_sent` | target, message | Whisper confirmed |
| `location` | x, y, terrain, description, nearby, map, hotspots | Movement result |
| `player_list` | players[] | Online player list |
| `examine_result` | player_data | Player info for popup |
| `combat_start` | monster:{}, use_client_art, message | Combat initiated |
| `combat_update` | messages[], monster:{} | Combat round result |
| `combat_end` | result, drops[], xp, gold, messages | Combat finished |
| `combat_message` | message | Mid-combat text |
| `party_combat_start` | monster:{}, party_members[] | Party combat begin |
| `party_combat_update` | current_turn, messages[] | Party combat round |
| `party_combat_end` | result, survivors[] | Party combat done |
| `status_effect` | effect, message, damage, turns | Poison/blind/buff |
| `ability_data` | abilities[] | Ability list |
| `ability_equipped/unequipped` | slot, ability | Ability change confirm |
| `keybind_changed` | slot, key | Keybind set confirm |
| `merchant_start` | merchant:{}, inventory:[] | Enter merchant |
| `merchant_end` | - | Leave merchant |
| `merchant_message` | message | Merchant result text |
| `merchant_inventory` | items[] | Merchant stock refresh |
| `gamble_result` | item:{}, message | Gambling outcome |
| `trading_post_start` | post_data | Enter trading post |
| `trading_post_end` | - | Leave trading post |
| `trading_post_message` | message | TP result text |
| `shop_inventory` | items[] | TP shop stock |
| `quest_list` | quests[] | Available quests |
| `quest_accepted/abandoned` | quest | Quest state change |
| `quest_turned_in` | quest, rewards | Quest complete |
| `quest_log` | quests[] | Active quest data |
| `quest_progress` | quest, progress | Quest step update |
| `quest_board_interact` | - | At quest board |
| `market_start` | - | Enter market mode |
| `market_browse_result` | listings[], page, total_pages | Market search results |
| `market_list_success` | listing, base_valor | Item listed |
| `market_list_all_success` | count, total_valor | Bulk listing done |
| `market_buy_success` | item, price | Purchase complete |
| `market_cancel_success` | - | Listing cancelled |
| `market_cancel_all_success` | count | All cancelled |
| `market_my_listings_result` | listings[] | Own listings |
| `market_error` | message | Market error |
| `craft_list` | recipes[], skill_level | Available recipes |
| `craft_challenge` | question, options[] | Crafting minigame |
| `craft_result` | success, item, quality, xp | Craft outcome |
| `gathering_round` | options[], phase | Gathering minigame round |
| `gathering_result` | correct, material | Gathering pick result |
| `gathering_complete` | materials[] | Gathering session done |
| `harvest_round` | options[], phase | Harvest minigame round |
| `harvest_result` | correct, part | Harvest pick result |
| `harvest_complete` | parts[] | Harvest session done |
| `dungeon_list` | dungeons[] | Available dungeons |
| `dungeon_state` | floor_map, position, floor | Dungeon room state |
| `dungeon_level_warning` | dungeon_id, min_level | Level warning |
| `dungeon_floor_change` | floor, map | New dungeon floor |
| `dungeon_treasure` | items[] | Treasure found |
| `dungeon_complete` | rewards | Dungeon cleared |
| `dungeon_exit` | - | Left dungeon |
| `blacksmith_encounter` | options, costs | Blacksmith NPC |
| `blacksmith_upgrade_select_item` | items[] | Select item for upgrade |
| `blacksmith_upgrade_select_affix` | affixes[] | Select stat for upgrade |
| `blacksmith_done` | - | Blacksmith interaction end |
| `healer_encounter` | options, costs | Healer NPC |
| `healer_done` | - | Healer interaction end |
| `rescue_npc_encounter` | npc_type, rewards | Rescue quest NPC |
| `special_encounter` | type, message | Special world encounter |
| `lucky_find` | item | Found item on ground |
| `treasure_chest` | items[] | Treasure chest from gathering |
| `companion_egg` | egg:{} | Egg dropped from combat |
| `egg_hatched` | companion:{} | Egg hatched |
| `house_data` | house:{} | Full house data |
| `house_update` | house:{} | House data refresh |
| `home_stone_select` | options[], stone_type | Home Stone UI |
| `home_stone_companion_choice` | - | Register vs Kennel choice |
| `build_result` | success, message | Build action result |
| `name_post_prompt` | enclosure_index | Name post prompt |
| `post_named` | name | Post named confirm |
| `guard_post_interact` | guard_data | At guard post |
| `guard_result` | success, message | Guard action result |
| `storage_contents` | items[] | Storage chest contents |
| `inn_rest_result` | message | Inn rest result |
| `station_interact` | station, skill | At crafting station |
| `throne_interact` | - | At throne tile |
| `trade_request_received` | from_name | Incoming trade request |
| `trade_started` | partner_name | Trade window open |
| `trade_update` | my_items[], partner_items[], ready | Trade state |
| `trade_cancelled` | reason | Trade ended |
| `trade_complete` | received_items[] | Trade done |
| `party_invite_received` | from_name, level, class | Party invite |
| `party_formed` | members[] | Party created |
| `party_update` | members[] | Party state change |
| `party_member_joined/left` | name | Member change |
| `party_disbanded` | reason | Party ended |
| `party_lead_choice` | partner_name | Lead or Follow? |
| `party_leader_changed` | new_leader | New leader appointed |
| `party_bump` | name, level, class | Bump-to-invite prompt |
| `permadeath` | character_name, bp_earned | Character died |
| `leaderboard` | entries[] | Fallen heroes board |
| `monster_kills_leaderboard` | entries[] | Kill count board |
| `trophy_leaderboard` | entries[] | Trophy hall board |
| `cloak_toggle` | cloaked | Cloak state change |
| `job_info_response` | jobs:{} | Job status data |
| `job_committed` | job_name, category | Job commitment confirmed |
| `title_menu` | titles[], current | Title system menu |
| `title_achieved/claimed/lost` | title | Title state change |
| `watch_request/approved/denied` | player | Watch system |
| `watch_character` | character:{} | Watched player update |
| `watch_location` | x, y, map | Watched player location |
| `watch_output` | message | Watched player's game text |
| `watch_combat_start` | monster:{} | Watched player combat |
| `watcher_left/watched_player_left` | name | Watch ended |
| `password_changed/change_failed` | message | Password result |
| `logout_character/account_success` | - | Logout confirmed |
| `wish_choice` | options[] | Wish selection |
| `wish_granted` | wish | Wish applied |
| `monster_select_prompt` | monsters[] | Scroll summon selection |
| `target_farm_select` | monsters[] | Farm target selection |
| `enemy_hp_revealed` | monster, hp | HP knowledge update |
| `summon_request` | from_name, location | Jarl summon |
| `hotzone_warning` | zone_info | Danger zone warning |
| `corpse_looted` | items[] | Corpse loot result |
| `scroll/area_map/spell_tome/bestiary_page` | data | Scribing outputs |
| `enhancement_scroll` | stats | Enhancement scroll applied |
| `rune` | rune_data | Rune crafted |
| `crafting_material/monster_part` | material | Material from combat |

---

## 4. Variable Naming Conventions

| Pattern | Meaning | Examples |
|---------|---------|---------|
| `pending_X_action: String` | Sub-state within a mode. Value = current sub-action name | `pending_inventory_action = "equip_confirm"`, `pending_market_action = "browse"`, `pending_companion_action = "inspect"` |
| `awaiting_X_result: bool` | Waiting for server response; blocks UI refresh | `awaiting_item_use_result`, `awaiting_craft_result` |
| `X_select` | Item/companion selection mode within a parent mode | `sort_select`, `salvage_select`, `affix_filter_select`, `rune_apply` |
| `X_confirm` | Confirmation dialog active | `equip_confirm`, `release_confirm`, `salvage_consumables_confirm`, `monster_select_confirm_mode` |
| `pending_X_warning` | Server warning awaiting user decision | `pending_dungeon_warning`, `pending_hotzone_warning` |
| `pending_X_request/invite` | Incoming request from another player | `pending_trade_request`, `pending_party_invite`, `pending_summon_from` |
| `X_mode: bool` | Primary mode flag (see Section 2) | `inventory_mode`, `crafting_mode`, `dungeon_mode` |
| `at_X: bool` | Location-based context flag | `at_merchant`, `at_water`, `at_ore_deposit` |
| `in_X: bool` | Active engagement state | `in_combat`, `in_trade`, `in_party` |
| `party_X` | Party system state | `party_combat_active`, `party_waiting_for_turn`, `party_combat_spectating` |
| `house_mode: String` | Sanctuary screen tab | `""`, `"main"`, `"storage"`, `"companions"`, `"upgrades"` |
| `blacksmith_upgrade_mode: String` | Blacksmith upgrade sub-flow | `""`, `"select_item"`, `"select_affix"` |
| `gathering_phase: String` | Gathering minigame state | `"choosing"`, `"result"`, `"complete"` |
| `leaderboard_mode: String` | Leaderboard tab | `"fallen_heroes"`, `"monster_kills"`, `"trophy_hall"` |

### Key `pending_inventory_action` States
`""`, `"equip_confirm"`, `"unequip_item"`, `"sort_select"`, `"salvage_select"`, `"salvage_all_confirm"`, `"salvage_below_confirm"`, `"salvage_consumables_confirm"`, `"viewing_materials"`, `"awaiting_salvage_result"`, `"affix_filter_select"`, `"rune_apply"`

**Bulk salvage confirmations:** `"salvage_all_confirm"` and `"salvage_below_confirm"` are confirmation prompts before executing bulk salvage operations. Action bar shows Confirm/Cancel.

### Key `pending_market_action` States
`""`, `"browse"`, `"list_select"`, `"list_material"`, `"list_material_qty"`, `"list_confirm"`, `"inspect"`, `"buy_confirm"`, `"my_listings"`

**Inspect sub-state:** `pending_market_action = "inspect"` sits between browse and buy_confirm. Shows item details with Buy/Back action bar. Variable: `market_inspected_listing: Dictionary` holds the selected listing data.

### Key `pending_house_action` States
`""`, `"withdraw_select"`, `"checkout_select"`, `"kennel_view"`, `"kennel_release"`, `"kennel_register"`, `"fusion_select"`, etc.

---

## 5. Recipe/Crafting Pipeline

### Skills and Stations

| Skill | Enum | Station Tile | Station Name |
|-------|------|-------------|-------------|
| Blacksmithing | 0 | `forge` | Forge |
| Alchemy | 1 | `apothecary` | Apothecary |
| Enchanting | 2 | `enchant_table` | Enchanting Table |
| Scribing | 3 | `writing_desk` | Writing Desk |
| Construction | 4 | `workbench` | Workbench |

### Recipe Structure
```
recipe_id: {
    name, skill (enum), skill_required (int), difficulty (int),
    materials: {material_id: qty, ...},
    output_type: str,           # See table below
    specialist_only: bool,      # Requires committed specialty job
    base_stats: {},             # For equipment output
    output_slot: str,           # Equipment slot
    effect: {},                 # For upgrades/enchantments
    max_upgrades: int,          # Upgrade cap bracket
    craft_time: float
}
```

### Output Types

| output_type | Produces | Skill(s) |
|-------------|----------|----------|
| `weapon` | Equipment (weapon slot) | Blacksmithing |
| `armor` | Equipment (any armor slot) | Blacksmithing |
| `consumable` | Potions, food, scrolls | Alchemy |
| `enhancement` | Enhancement scrolls (+stat) | Enchanting |
| `material` | Processed materials (ingots, etc.) | Any |
| `rune` | Stat runes (apply to gear) | Enchanting |
| `upgrade` | +N levels to equipped item | Blacksmithing, Enchanting |
| `self_repair` | Repair own equipment | Blacksmithing (specialist) |
| `reforge` | Reroll equipment stats | Blacksmithing (specialist) |
| `transmute` | Convert material tier up | Alchemy (specialist) |
| `extract` | Extract essence from items | Alchemy (specialist) |
| `disenchant` | Break down enchanted items | Enchanting (specialist) |
| `scroll` | Scrolls (summoning, etc.) | Scribing |
| `area_map` | Reveals map area | Scribing |
| `spell_tome` | Permanent stat boost | Scribing |
| `bestiary_page` | Monster knowledge | Scribing |
| `structure` | Buildable structures | Construction |

### Quality System
| Quality | Multiplier | Color |
|---------|-----------|-------|
| Failed | 0.0x (materials lost) | #808080 |
| Poor | 0.5x | #FFFFFF |
| Standard | 1.0x | #00FF00 |
| Fine | 1.25x | #0070DD |
| Masterwork | 1.5x | #A335EE |

### Crafting Minigame
- 10 questions per skill, 3 choices each (index 0 always correct, shuffled)
- Auto-skip if skill - difficulty >= 30
- XP per craft: base 25, scaled by difficulty

### Caps
| Cap Type | Limit |
|----------|-------|
| Max upgrade levels per item | 50 |
| Max enchantment types per item | 3 |
| Enchant ATK/DEF cap | 60 |
| Enchant max_hp cap | 200 |
| Enchant max_mana cap | 150 |
| Enchant speed cap | 15 |
| Enchant stat cap (STR/CON/DEX/INT/WIS/WITS) | 20 |
| Enchant stamina/energy cap | 50 |
| Upgrade bracket: +1 recipes | up to +10 |
| Upgrade bracket: +5 recipes | up to +30 |
| Upgrade bracket: +10 recipes | up to +50 |

### Crafting Disconnect Refund
`active_crafts` dictionary (server.gd) now stores `consumed_materials` alongside each in-progress craft. If a player disconnects mid-craft, materials are refunded to their `crafting_materials` inventory.

### Specialty Job Gating
- Gathering jobs: fishing, mining, logging, foraging (commit at level 5)
- Specialty jobs: blacksmith, alchemist, enchanter, scribe, constructor (commit at level 5)
- `specialist_only: true` recipes require committed specialty job matching the skill
- Job trial cap: level 5 (can try all before committing)

### Monster Part Groups (for Runes)
| Stat | Part Suffixes |
|------|--------------|
| attack | _fang, _tooth, _claw, _horn, _mandible |
| defense | _hide, _scale, _plate, _chitin |
| hp | _heart |
| speed | _fin, _gear |
| mana | _soul_shard |
| stamina | _core |
| energy | _charm, _spark, _ember |
| str | _ichor, _venom_sac |
| con | _bone |
| dex | _tentacle |
| int | _dust, _eye |
| wis | _essence, _pearl |
| wits | _ear |

Rune tier ranges: minor (monster T1-2), greater (T3-6), supreme (T7-9)

---

## 6. Key Constants & Configs

### Monster Tiers (monster_database.gd)

| Tier | Level Range | Example Monsters |
|------|------------|------------------|
| 1 | 1-5 | Goblin, Rat, Slime |
| 2 | 6-15 | Wolf, Skeleton, Orc |
| 3 | 16-30 | Troll, Ogre, Wyvern |
| 4 | 31-50 | Golem, Vampire, Wraith |
| 5 | 51-100 | Dragon, Lich, Demon |
| 6 | 101-500 | Elder Dragon, Archlich |
| 7 | 501-2000 | Void creatures |
| 8 | 2001-5000 | Celestial beings |
| 9 | 5001+ | Primordial entities |

### XP Formulas

| Formula | Location |
|---------|----------|
| XP to next level | `pow(level+1, 2.2) * 50` (character.gd:1752) |
| Monster XP reward | `pow(level+1, 2.2) * 1.11` adjusted by lethality (monster_database.gd:1571) |
| XP scaling (higher monster) | `1.0 + sqrt(gap_ratio) * 0.7` where `gap_ratio = level_diff / reference_gap` |
| Reference gap | `10.0 + player_level * 0.05` |
| XP penalty (lower monster) | `max(0.4, 1.0 - penalty)` — floor at 40% |
| Companion XP per kill | `max(1, int(base_xp * 0.10))` |
| Companion XP to next level | `pow(level+1, 2.0) * 15` (max level 10000) |

### Combat Formulas (combat_manager.gd + balance_config.json)

**Player Attack:**
```
weapon_damage = equipment_bonuses.attack
base_damage = max(1, strength + weapon_damage)
crit: 5% base (Thief 15%, Ninja 12%), 1.5x multiplier
variance: +/-15%
```

**Monster Attack:**
```
base_damage = monster.strength + 1d6
equipment_reduction = min(0.4, equip_defense / 400)     # Equipment cap 40%
raw = base_damage * (1 - equipment_reduction)
defense_ratio = defense / (defense + 100)
damage_reduction = defense_ratio * 0.6                    # Defense cap 60%
total = raw * (1 - damage_reduction)
level_diff_mult = pow(1.035, min(level_diff, 100))       # Higher level = more damage
min_damage = max(1, monster_level / 5)
```

**Lethality Formula (for XP calibration):**
```
lethality = (HP * 2.5) + (STR * 7.5) + (DEF * 2.5) + (Speed * 5.0)
lethality *= (1 + sum of ability_modifiers from balance_config.json)
```

### balance_config.json Key Sections
| Section | Contents |
|---------|---------|
| `combat` | str_multiplier, crit base/max, defense formula constants, equipment defense cap |
| `lethality` | HP/STR/DEF/Speed weights, per-ability modifiers (30 abilities) |
| `monster_abilities` | Percent values for poison, lifesteal, regen, reflect, dodge, etc. |
| `monster_spawning` | Tier bleed chance |
| `rewards` | XP/gold lethality multipliers |

### House Upgrades (persistence_manager.gd)

| Upgrade | Effect/Level | Max Level | Cost Range (BP) |
|---------|-------------|-----------|----------------|
| `house_size` | +1 layout tier | 3 | 5k-50k |
| `storage_slots` | +10 slots | 8 | 500-64k |
| `companion_slots` | +1 registered slot | 8 | 2k-80k |
| `egg_slots` | +1 incubation slot | 9 | 500-60k |
| `kennel_capacity` | see table below | 9 | 1k-100k |
| `flee_chance` | +2% flee chance | 5 | 1k-20k |
| `starting_valor` | +50 valor on new char | 10 | 250-8k |
| `xp_bonus` | +1% XP | 10 | 1.5k-100k |
| `gathering_bonus` | +5% gathering | 4 | 800-12k |
| `hp_bonus` | +5% max HP | 5 | 2k-75k |
| `resource_max` | +5% max resource | 5 | 2k-75k |
| `resource_regen` | +5% resource regen | 5 | 3k-120k |
| `str/con/dex/int/wis/wits_bonus` | +1 per level | 10 | 1k-50k each |

**Kennel Capacity Table:** [30, 50, 80, 120, 175, 250, 325, 400, 450, 500]

### Baddie Points Formula (earned on permadeath)
```
+1 per 100 XP earned
+5 per monster gem
+1 per 10 monsters killed
+10 per completed quest
Level milestones: +50 (Lv10), +150 (Lv25), +400 (Lv50), +1000 (Lv100)
```

### Persistence Files (user://data/)

| File | Contents |
|------|---------|
| `accounts.json` | Account credentials, account IDs |
| `characters/` | Per-character JSON save files |
| `leaderboard.json` | Fallen heroes leaderboard |
| `monster_kills_leaderboard.json` | Monster kill rankings |
| `realm_state.json` | Realm state (title holders, etc.) |
| `corpses.json` | Player corpses on map |
| `houses.json` | All Sanctuary data |
| `player_tiles.json` | Player-placed structures |
| `player_posts.json` | Named player posts/enclosures |
| `market_data.json` | Open Market listings |
| `world/paths.json` | Road network paths, graph, post positions |
| `guards.json` | Hired guard data |
| `player_storage.json` | Storage chest contents |

### Gathering Tier Tables (drop_tables.gd)

**Fishing:** `FISHING_CATCHES` keyed by water type ("shallow", "deep", etc.)
**Mining:** `MINING_CATCHES` keyed by tier 1-9 (based on distance from origin)
**Logging:** `LOGGING_CATCHES` keyed by tier 1-6
**Foraging:** `FORAGING_CATCHES` keyed by tier 1-6

### Salvage Values (drop_tables.gd)

| Rarity | Base ESS | Per Level |
|--------|----------|-----------|
| Common | 5 | +1 |
| Uncommon | 10 | +2 |
| Rare | 25 | +3 |
| Epic | 50 | +5 |
| Legendary | 100 | +8 |
| Artifact | 200 | +12 |

### Market Markup (persistence_manager.gd)
```
Supply >= 20 items: 1.15x markup
Supply <= 2 items: 1.50x markup
Linear interpolation between: 1.50 - ((count-2)/18 * 0.35)
```

### Merchant Shop Markup
| Type | Multiplier |
|------|-----------|
| Starter post | 1.5x |
| Normal | 2.5x |
| Affix specialty | 3.5x |
| Elite | 4.0x |

### Classes and Paths

| Path | Classes | Resource | Primary Stats |
|------|---------|----------|--------------|
| Warrior | Fighter, Barbarian, Paladin | Stamina | STR, CON |
| Mage | Wizard, Sorcerer, Sage | Mana | INT, WIS |
| Trickster | Thief, Ranger, Ninja | Energy | DEX, WITS |

### Races
| Race | Passive |
|------|---------|
| Human | +10% XP |
| Elf | +25% mana, poison resistance |
| Dwarf | Last Stand (survive lethal hit once per combat) |
| Orc | Bonus damage at low HP |
| Halfling | Bonus dodge and crit chance |

### World System Constants
| Constant | Value | Location |
|----------|-------|----------|
| Chunk size | 32x32 tiles | chunk_manager.gd |
| World bounds | -2000 to 2000 | chunk_manager.gd |
| Map display radius | 11 tiles | world_system.gd |
| TCP port | 9080 | server.gd / client.gd |
| Party max size | 4 | server.gd |
| Max player enclosures | 5 | server.gd |
| Max enclosure size | 11x11 | server.gd |
| Sanctuary viewport | 21x9 (min) | client.gd |
| Road check interval | 60 seconds | server.gd |
| Merchant count | 10 | world_system.gd |
| Merchant speed | 0.02 tiles/sec | world_system.gd |
| A* max nodes | 50,000 | world_system.gd |
| Build cooldown | 0.5s per player | server.gd (`build_cooldown` dict) |

### Key File Locations

| File | Lines | Purpose |
|------|-------|---------|
| `client/client.gd` | ~21000 | Client UI, networking, action bar, all modes |
| `server/server.gd` | ~14000 | Server logic, message routing, game systems |
| `shared/character.gd` | ~3300 | Player stats, inventory, equipment, jobs |
| `shared/combat_manager.gd` | ~6000 | Turn-based combat engine, abilities |
| `shared/world_system.gd` | ~2400 | Terrain gen, tile types, LOS, map display |
| `shared/chunk_manager.gd` | ~500 | Chunk loading/saving, delta system |
| `shared/monster_database.gd` | ~1600 | Monster definitions, stat scaling |
| `shared/drop_tables.gd` | ~4200 | Loot gen, catches, salvage, valor calc |
| `shared/crafting_database.gd` | ~2200 | Recipes, materials, quality |
| `shared/quest_database.gd` | ~800 | Quest definitions, dynamic generation |
| `shared/dungeon_database.gd` | ~600 | Dungeon types, floors, bosses |
| `shared/npc_post_database.gd` | ~300 | NPC post placement |
| `shared/trading_post_database.gd` | ~400 | Trading post categories |
| `server/persistence_manager.gd` | ~1400 | Data persistence, house system |
| `server/balance_config.json` | ~100 | Combat tuning values |
| `client/monster_art.gd` | ~3000 | ASCII art for monsters/eggs |
| `client/trader_art.gd` | ~500 | Trading post ASCII art |
| `client/trading_post_art.gd` | ~600 | Trading post category art |

---

## 7. Phase 5: Dungeon Expansion

### Dungeon Step Pressure System

Each dungeon floor has a step limit that creates urgency. Lower-tier dungeons are more lenient; higher-tier dungeons demand efficiency.

**Step Limits by Tier (`DUNGEON_STEP_LIMITS` in `dungeon_database.gd`):**

| Tier | Base Steps | Boss Floor (+50%) |
|------|-----------|-------------------|
| 1 | 100 | 150 |
| 2 | 95 | 142 |
| 3 | 90 | 135 |
| 4 | 85 | 127 |
| 5 | 80 | 120 |
| 6 | 75 | 112 |
| 7 | 70 | 105 |
| 8 | 65 | 97 |
| 9 | 60 | 90 |

**Pressure Phases (server.gd `handle_dungeon_move`):**
- 0-74% steps: normal exploration
- 75-89% steps: warning text ("The walls tremble...")
- 90-99% steps: earthquake warning + damage (5% max HP)
- 100% steps: collapse — ejects player with penalties

**Collapse Penalties (`_collapse_dungeon()`):**
- Lose 30% of materials gathered during this dungeon run (tracked in `dungeon_gathered_materials`)
- +15 wear applied to all equipped items
- Forcible ejection from dungeon

**Flawless Run Bonus:** Completing a dungeon without collapse grants +20% XP on completion rewards.

### Dungeon Tile: RESOURCE

New `TileType.RESOURCE = 8` added to the dungeon tile enum:

| Property | Value |
|----------|-------|
| Enum value | `TileType.RESOURCE` (8) |
| Display char | `&` |
| Color | `#00FFCC` (cyan-green) |

Resource nodes are placed in dungeon rooms by the floor generation algorithm. When the player steps on a `&` tile, the server sends a `dungeon_resource_prompt` message and the client shows Gather/Skip buttons.

### Dungeon Gathering Flow

```
CLIENT                                        SERVER
  Player steps on & tile ──►
                              ◄── {type:"dungeon_resource_prompt", materials:[...]}
  dungeon_resource_prompt = true
  Action bar: [Gather] [Skip]
  Player presses Gather ──►  {type:"dungeon_gather_confirm"}
                              Server rolls materials from tier-scaled table
                              _track_dungeon_material(peer_id, material_id, qty)
                              ◄── {type:"dungeon_gather_result", materials:[{id, name, qty}]}
  awaiting_dungeon_gather_result = true
  Displays gathered materials
  Player moves ──►            awaiting_dungeon_gather_result = false
```

**Dungeon-Exclusive Materials (crafting_database.gd `MATERIALS`):**

| Material | Type | Tier | Value | Dungeon Source |
|----------|------|------|-------|---------------|
| `void_crystal` | crystal | 7 | 600 | T7 dungeon nodes (60% weight) |
| `abyssal_shard` | crystal | 8 | 1200 | T8 dungeon nodes (60% weight) |
| `primordial_essence` | crystal | 9 | 2500 | T9 dungeon nodes (50% weight) |

These materials are used in high-tier crafting recipes: escape scrolls, enchantments (void/abyssal/primordial), upgrade recipes, and elite consumables.

### Hidden Trap System

Traps are server-side only — there is no trap tile type in the dungeon grid. Traps are invisible until triggered.

**Constants (dungeon_database.gd):**
- `TRAPS_PER_FLOOR`: {1:1, 2:1, 3:2, 4:2, 5:3, 6:3, 7:4, 8:4, 9:4}
- `TRAP_TYPES`: ["rust", "thief", "teleport"]
- `TRAP_WEIGHTS`: {"rust": 40, "thief": 30, "teleport": 30}

**Trap Effects:**
| Type | Effect |
|------|--------|
| `rust` | Applies wear damage to equipped items |
| `thief` | Steals 1-3 gathered dungeon materials (or 1 inventory item) |
| `teleport` | Randomly repositions player on the current floor |

**How traps work:**
1. `_generate_dungeon_traps()` places traps on empty floor tiles during dungeon creation
2. Server stores traps in `dungeon_traps[instance_id][floor_num]` as `[{x, y, type, triggered}]`
3. On each move, `_check_dungeon_trap()` checks the player's position against untriggered traps
4. When triggered, trap is marked `triggered = true` and appears as `x` on the client map
5. Client receives triggered trap positions via `triggered_traps` in `dungeon_state` messages
6. `_get_triggered_traps()` returns only triggered traps for client display (with color `#FF4444`)

### Escape Scroll System

Escape scrolls are the only safe way to exit a dungeon. There is no free entrance/exit or flee option.

**Entry Warning:** On entering any dungeon, the server sends a warning:
- "WARNING: There is NO free exit from dungeons!"
- "The only safe way out is an Escape Scroll."
- If under-leveled, an additional level warning is shown

**Scroll Tiers (crafting_database.gd, scribing skill):**

| Recipe | Materials | Tier Max | Specialist |
|--------|-----------|----------|------------|
| `scroll_of_escape` | parchment x2, ink x1, moonpetal x1 | T1-4 | No |
| `scroll_of_greater_escape` | fine_parchment x2, arcane_ink x1, soul_shard x1 | T1-7 | Yes |
| `scroll_of_supreme_escape` | fine_parchment x2, arcane_ink x1, void_crystal x1 | T1-9 | Yes |

**Scroll Drop:** 20% chance from dungeon treasure chests (`roll_escape_scroll_drop()` in dungeon_database.gd). Drop tier matches dungeon tier.

**Client Action Bar:** Dungeon mode shows an "Escape" button (slot 3) when the player has an escape scroll. The button finds and uses the first escape scroll in inventory.

**Server Flow (`_use_escape_scroll()`):**
1. Validates player is in dungeon and not in combat
2. Checks `tier_max >= dungeon_tier`
3. Consumes the scroll from inventory
4. Clears `dungeon_gathered_materials` (no penalty — clean exit)
5. Sends `dungeon_exit` message with reason "escape_scroll"

### Dungeon Rest System

Resting in dungeons consumes food-type crafting materials from the player's `crafting_materials` inventory.

**Food Material Types (`DUNGEON_REST_FOOD_MATERIAL_TYPES`):** `["plant", "herb", "fungus", "fish"]`

**Rest Effects:**
- Mages: +5-12.5% max mana, +3-5% max HP
- Non-mages: +5-12.5% max HP

**Action Bar:** Rest button label changes dynamically based on whether the player has food materials.

### New Variables

**Server (`server.gd`):**

| Variable | Type | Purpose |
|----------|------|---------|
| `dungeon_traps` | `Dictionary` | `instance_id -> {floor_num: [{x, y, type, triggered}]}` |
| `dungeon_gathered_materials` | `Dictionary` | `peer_id -> {material_id: qty}` — materials gathered this dungeon run |

**Client (`client.gd`):**

| Variable | Type | Purpose |
|----------|------|---------|
| `dungeon_triggered_traps` | `Array` | Triggered trap positions for map display |
| `dungeon_resource_prompt` | `bool` | Waiting for gather/skip choice at resource node |
| `awaiting_dungeon_gather_result` | `bool` | Protects gather result display from refresh |

### New Message Types

| Direction | Type | Key Fields | Purpose |
|-----------|------|-----------|---------|
| S->C | `dungeon_resource_prompt` | materials[] | Prompt player to gather at resource node |
| C->S | `dungeon_gather_confirm` | - | Player chose to gather |
| C->S | `dungeon_gather_skip` | - | Player chose to skip |
| S->C | `dungeon_gather_result` | materials[] | Gathered materials result |

### Server UI: MapWipeButton

The server scene (`server.tscn`) includes a MapWipeButton with a 2-step ConfirmationDialog:

1. `MapWipeButton` — opens `MapWipeDialog` ("Confirm Map Wipe - Step 1 of 2")
2. On confirm, opens `MapWipeFinalDialog` ("FINAL CONFIRMATION - Map Wipe")
3. On final confirm, calls `_execute_map_wipe(-1)`

**What map wipe preserves:** Characters, Sanctuary, inventories, companions
**What map wipe deletes:** World chunks, guards, player posts, market data, dungeon instances
