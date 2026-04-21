# 05 - Client Architecture

This guide explains how `client/client.gd` works in Phantom Badlands. The file is approximately 27,800 lines long and constitutes the entire client application. By the end of this document, you should understand the code well enough to find any section, add new features, and avoid the common pitfalls that break the UI.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Game States](#2-game-states)
3. [Mode Flags -- The Heart of the State Machine](#3-mode-flags----the-heart-of-the-state-machine)
4. [The Action Bar -- 10-Slot Contextual Menu](#4-the-action-bar----10-slot-contextual-menu)
5. [The Main Loop -- _process(delta)](#5-the-main-loop----processdelta)
6. [Input Handling -- _input(event)](#6-input-handling----inputevent)
7. [Message Handling -- handle_server_message()](#7-message-handling----handle_server_message)
8. [Display Functions Pattern](#8-display-functions-pattern)
9. [The "Output Disappears" Problem](#9-the-output-disappears-problem----most-important-section)
10. [The Number Key Conflict](#10-the-number-key-conflict)
11. [Pagination](#11-pagination)
12. [Audio System](#12-audio-system)
13. [Keybind System](#13-keybind-system)
14. [Finding Things in client.gd](#14-finding-things-in-clientgd)

---

## 1. Overview

`client/client.gd` is a single GDScript file attached to the root `Control` node of `client.tscn`. It is the **entire** client -- every line of UI rendering, every network message handler, every input response, and every piece of game state display lives in this one file.

**What it handles:**

- All UI panels (login, character select, death screen, main game)
- All user input (keyboard, mouse clicks, text commands)
- All networking (TCP connection, message sending/receiving, JSON parsing)
- All game state display (inventory, combat, map, companions, crafting, etc.)
- Sound effects and background music
- Keybind management and settings

**How it is organized:**

The file is organized roughly by feature rather than by architectural layer. Variables are declared at the top (lines 1-900), then `_ready()` initializes everything, then the main loop and input handlers appear, followed by thousands of lines of feature-specific functions. Think of it as a massive state machine that responds to two things: server messages arriving over TCP, and user input from the keyboard and mouse.

**Key helper files loaded at runtime:**

```gdscript
# Lazy-loaded ASCII art scripts (avoid circular initialization)
var _monster_art_script = null
func _get_monster_art():
    if _monster_art_script == null:
        _monster_art_script = load("res://client/monster_art.gd")
    return _monster_art_script

# Also: trader_art.gd, trading_post_art.gd
# And preloaded: shared/character.gd for item display helpers
const CharacterScript = preload("res://shared/character.gd")
```

**UI Layout:**

The client uses a three-panel layout:

```
+------------------------------------------+
|  GameOutput (left)  |  MapDisplay (right) |
|  (text/ASCII art)   |  (terrain map)      |
+------------------------------------------+
|  ActionBar (10 buttons across the bottom) |
+------------------------------------------+
|  ChatOutput / OnlinePlayersList (bottom)  |
|  InputField (text entry for chat/cmds)    |
+------------------------------------------+
```

The key `@onready` node references (around line 400):

```gdscript
@onready var game_output = $RootContainer/TopSection/GameOutputContainer/GameOutput
@onready var chat_output = $RootContainer/BottomStrip/ChatPanel/ChatOutput
@onready var map_display = $RootContainer/TopSection/MapPanel/MapDisplay
@onready var input_field = $RootContainer/BottomStrip/ChatPanel/InputRow/InputField
@onready var action_bar = $RootContainer/BottomStrip/CenterPanel/ActionBar
@onready var enemy_health_bar = $RootContainer/EnemyHealthBar
@onready var player_health_bar = $RootContainer/StatsBar/PlayerHealthBar
```

All text display uses `RichTextLabel` with BBCode for colors and formatting.

---

## 2. Game States

The client tracks a high-level state using an enum (line 388):

```gdscript
enum GameState {
    DISCONNECTED,      # Not connected to server
    CONNECTED,         # TCP connected but not logged in
    LOGIN_SCREEN,      # Showing login/register form
    HOUSE_SCREEN,      # In Sanctuary (between login and character select)
    CHARACTER_SELECT,  # Picking a character
    PLAYING,           # In the game world
    DEAD               # Character died (permadeath)
}
var game_state = GameState.DISCONNECTED
```

### What happens in each state:

**DISCONNECTED** -- The client shows a connection panel. No panels are visible except the connection UI. The TCP `StreamPeerTCP` is not connected.

**CONNECTED** -- TCP handshake succeeded. The client transitions to showing the login panel. The server sends a `"welcome"` message.

**LOGIN_SCREEN** -- The login/register form is visible. The player enters username and password. On success, the server sends `"login_success"`, and the client requests house data before transitioning to `HOUSE_SCREEN`.

**HOUSE_SCREEN** -- The Sanctuary screen. This is a roguelite meta-progression hub that persists across character deaths. The player walks around an ASCII house (29x19 grid) and can access storage, companion kennel, fusion station, and upgrades. The player must walk to the door (`D` tile) to reach character select. The main game UI (game_output, map_display, action_bar) is visible here, reused for house display.

**CHARACTER_SELECT** -- Shows the character list panel. The player picks an existing character or creates a new one. On selection, the server sends `"character_loaded"` and the state moves to `PLAYING`.

**PLAYING** -- The main game. All mode flags (combat, inventory, merchant, etc.) operate within this state. The three-panel layout is active. Movement, combat, and all features are available.

**DEAD** -- Permadeath screen. Shows death stats (level reached, monsters killed, gold earned). The action bar offers "Continue" and "Save Log". Pressing continue returns to `HOUSE_SCREEN`.

### Panel visibility:

Each state shows different panels through `hide_all_panels()` followed by making the relevant panel visible:

```gdscript
func show_login_panel():
    hide_all_panels()
    if login_panel:
        login_panel.visible = true
    # ... setup fields

func show_game_ui():
    hide_all_panels()
    game_state = GameState.PLAYING

func show_house_panel():
    hide_all_panels()
    game_state = GameState.HOUSE_SCREEN
```

---

## 3. Mode Flags -- The Heart of the State Machine

Within the `PLAYING` state, the client uses approximately 30+ boolean and string mode flags to track what the player is currently doing. These flags control:

- What is displayed in `game_output`
- How keyboard input is interpreted
- What buttons appear on the action bar
- How incoming server messages are handled

### Combat modes (lines 648-655):

```gdscript
var in_combat = false               # Actively fighting a monster
var flock_pending = false            # Chain encounter queued (another monster after this one)
var combat_item_mode = false         # Selecting an item to use during combat
var combat_outsmart_failed = false   # Track if outsmart already failed this combat
var pending_variable_ability = ""    # Ability waiting for resource amount input
var current_enemy_is_boss = false    # Boss fight (triggers pulsing border effect)
```

### UI modes -- each shows a different "screen" (various locations):

```gdscript
var inventory_mode: bool = false     # Backpack/equipment view
var settings_mode: bool = false      # Settings menu
var ability_mode: bool = false       # Ability management
var companions_mode: bool = false    # Companion list
var eggs_mode: bool = false          # Egg incubation view
var more_mode: bool = false          # "More" submenu hub
var crafting_mode: bool = false      # Crafting interface
var build_mode: bool = false         # Building/construction
var job_mode: bool = false           # Job overview
var storage_mode: bool = false       # Player enclosure storage
var market_mode: bool = false        # Open market browsing
```

### Location modes -- at a specific interactable place:

```gdscript
var at_merchant: bool = false        # At NPC merchant
var at_trading_post: bool = false    # At trading post
var at_water: bool = false           # At fishable water tile
var at_ore_deposit: bool = false     # At mineable ore deposit
var at_dense_forest: bool = false    # At harvestable forest
var at_foraging_spot: bool = false   # At forageable node
var at_dungeon_entrance: bool = false # At dungeon entrance (D tile)
var at_guard_post: bool = false      # At guard post
var at_corpse: bool = false          # At lootable corpse
```

### Pending action states -- sub-states within modes:

These are string variables that track which sub-view or sub-action is active within a parent mode. They are the key to preventing output from being cleared (more on this in Section 9).

```gdscript
var pending_inventory_action: String = ""
    # Values: "equip_item", "unequip_item", "use_item", "inspect_item",
    #         "inspect_equipped_item", "equip_confirm", "discard_item",
    #         "salvage_select", "sort_select", "viewing_materials",
    #         "awaiting_salvage_result", "lock_item", "rune_apply",
    #         "affix_filter_select", "salvage_all_confirm", etc.

var pending_companion_action: String = ""
    # Values: "inspect", "inspect_select", "release_select",
    #         "release_confirm", "release_all_warn", "release_all_confirm"

var pending_merchant_action: String = ""
    # Values: "buy", "sell", "buy_inspect", "buy_equip_prompt",
    #         "upgrade", "gamble", "gamble_again"

var pending_market_action: String = ""
    # Values: "browse", "inspect", "buy_confirm", "list_select",
    #         "list_material", "list_egg", "my_listings"

var pending_more_action: String = ""
    # Values: "changelog", "bestiary", "viewing_materials"

var pending_house_action: String = ""
    # Values: "withdraw_select", "checkout_select", "discard_select",
    #         "register_select", "unregister_select", "release_select",
    #         "same_confirm", "mixed_confirm"
```

### The critical rule: one mode at a time

Only one major mode should be active at a time. When the player opens inventory, `inventory_mode = true` and all other modes should be false. When they close inventory, `inventory_mode = false` and the client returns to the default movement state.

The action bar checks modes in a strict priority order (first match wins). If multiple modes are accidentally left true, only the highest-priority one will show its buttons, and the others will be in an inconsistent state.

When implementing a new feature, **always** clear the mode flag when exiting:

```gdscript
# Opening a mode:
inventory_mode = true
display_inventory()
update_action_bar()

# Closing a mode:
inventory_mode = false
pending_inventory_action = ""
display_location()       # Or whatever the parent view should show
update_action_bar()
```

---

## 4. The Action Bar -- 10-Slot Contextual Menu

The action bar is a row of 10 buttons at the bottom of the screen. It is the primary way players interact with the game. Every mode provides its own set of action bar buttons.

### Default key bindings (line 317):

| Slot | Key     | Variable     |
|------|---------|-------------|
| 0    | Space   | `action_0`  |
| 1    | Q       | `action_1`  |
| 2    | W       | `action_2`  |
| 3    | E       | `action_3`  |
| 4    | R       | `action_4`  |
| 5    | 1       | `action_5`  |
| 6    | 2       | `action_6`  |
| 7    | 3       | `action_7`  |
| 8    | 4       | `action_8`  |
| 9    | 5       | `action_9`  |

Note that slots 5-9 share keys with item selection keys 1-5. This overlap is intentional but requires careful handling (see Section 10).

### How the action bar works:

**Step 1: Data structure.** The `current_actions` array holds 10 action definitions:

```gdscript
var current_actions: Array[Dictionary] = []

# Each entry looks like:
{
    "label": "Attack",         # Text shown on the button
    "action_type": "combat",   # How to handle the action
    "action_data": "attack",   # Payload passed to the handler
    "enabled": true            # Whether the button is clickable
}
```

The `action_type` field determines routing:
- `"local"` -- Handled client-side by `execute_local_action(action_data)`
- `"combat"` -- Sent to server as a combat command
- `"server"` -- Sent to server as a generic message type
- `"flock"` -- Continues to the next chain encounter
- `"none"` -- Disabled/placeholder (not clickable)

**Step 2: Rebuilding.** `update_action_bar()` (line 4723) rebuilds the entire `current_actions` array based on the current game state. It checks mode flags in priority order:

```
settings_mode
  -> DEAD state
    -> HOUSE_SCREEN state
      -> in_trade
        -> in_combat / flock_pending / pending_continue
          -> at_merchant
            -> inventory_mode
              -> at_trading_post
                -> market_mode
                  -> dungeon modes
                    -> companions_mode
                      -> eggs_mode
                        -> crafting_mode
                          -> ability_mode
                            -> build_mode
                              -> gathering modes
                                -> more_mode
                                  -> job_mode
                                    -> default movement
```

Each branch fills all 10 slots. Unused slots get placeholder entries:

```gdscript
{"label": "---", "action_type": "none", "action_data": "", "enabled": false}
```

**Step 3: Display.** After `current_actions` is rebuilt, the function updates each button's text, enabled state, and hotkey label.

### The two execution paths (CRITICAL):

Every action bar button must handle **both** input paths:

**Path 1 -- Keyboard:** Detected in `_process()` by polling `Input.is_physical_key_pressed()` for each of the 10 action keys. When a key is detected as newly pressed, `trigger_action(index)` is called.

**Path 2 -- Mouse click:** The button's `pressed` signal connects to `_on_action_button_pressed(index)`, which also calls `trigger_action(index)`.

Both paths converge at `trigger_action()` (line 7219):

```gdscript
func _on_action_button_pressed(index: int):
    # Release button focus so Space key works correctly
    var focused = get_viewport().gui_get_focus_owner()
    if focused and focused is Button:
        focused.release_focus()
    trigger_action(index)

func trigger_action(index: int):
    if index < 0 or index >= current_actions.size():
        return

    var action = current_actions[index]
    if not action.enabled:
        return

    match action.action_type:
        "combat":
            # Variable cost check, then send combat command
            if action.get("cost", -1) == 0 and action.get("resource_type", "") != "":
                prompt_variable_cost_ability(action.action_data, action.get("resource_type", "mana"))
            else:
                send_combat_command(action.action_data)
        "local":
            execute_local_action(action.action_data)
        "server":
            send_to_server({"type": action.action_data})
        "flock":
            continue_flock_encounter()
```

### execute_local_action() -- The click handler (line 9001):

This is a massive `match` statement that handles hundreds of `action_data` strings. It is where all client-side button logic lives.

```gdscript
func execute_local_action(action: String):
    # Dynamic action prefixes (checked before the match):
    if action.begins_with("party_appoint_"):
        # ... handle party leader appointment
        return
    if action.begins_with("egg_toggle_freeze_"):
        # ... handle egg freeze toggle
        return
    if action.begins_with("gathering_pick_"):
        # ... handle gathering choice
        return

    match action:
        "status":
            display_character_status()
        "help":
            show_help()
        "settings":
            open_settings()
        "open_inventory":
            inventory_mode = true
            display_inventory()
            update_action_bar()
        "close_inventory":
            inventory_mode = false
            pending_inventory_action = ""
            clear_game_output()
            update_action_bar()
        "attack":
            send_to_server({"type": "combat", "action": "attack"})
        # ... hundreds more cases
```

**When adding a new button:**

1. Add the button definition in `update_action_bar()` under the appropriate mode branch
2. Add a handler in `execute_local_action()` if the `action_type` is `"local"`
3. Both keyboard and click paths will converge at `trigger_action()` and route to your handler

### Some modes handle keyboard input outside the action bar

Certain modes are excluded from action bar hotkey polling and instead handle keys directly in `_input()`. These modes are listed in the `should_process_action_bar` condition (line 2639):

```gdscript
var should_process_action_bar = (game_state == GameState.PLAYING or ...)
    and not settings_mode
    and not combat_item_mode
    and not monster_select_mode
    and not target_farm_mode
    and not title_mode
    # ...
```

For these excluded modes, you must implement keyboard handling in `_input()` **and** click handling via `execute_local_action()`. Both paths must work.

---

## 5. The Main Loop -- _process(delta)

`_process(delta)` (line 1859) runs every frame. It is the central nervous system of the client. Here is what it does, in order:

### Phase 1: Frame cleanup

```gdscript
func _process(delta):
    # Clear per-frame tracking arrays
    action_triggered_this_frame.clear()
    item_selection_consumed_this_frame.clear()
```

These arrays prevent the same key press from triggering both an action bar button and an item selection in the same frame.

### Phase 2: Network polling

```gdscript
    connection.poll()
    var status = connection.get_status()
```

The TCP connection is polled every frame. This is how Godot's `StreamPeerTCP` works -- you must call `poll()` to check for new data.

### Phase 3: Combat animation timers

```gdscript
    if combat_animation_active:
        combat_animation_timer -= delta
        if combat_animation_timer <= 0:
            stop_combat_animation()

    if combat_phase_paused:
        combat_phase_timer -= delta
        if combat_phase_timer <= 0:
            combat_phase_paused = false
            _drain_combat_queue()
```

Combat messages can be displayed with a phased delay for dramatic effect. The timer controls when the next message appears.

### Phase 4: Escape key handling

```gdscript
    if game_state == GameState.PLAYING:
        if Input.is_action_just_pressed("ui_cancel"):
            if rebinding_action != "":
                # Cancel keybind rebinding
            elif settings_mode:
                close_settings()
            elif watching_player != "":
                stop_watching()
            # ... other escape handlers
```

### Phase 5: Item selection key polling

This is one of the most complex parts. When the player is in a mode that uses numbered lists (inventory, merchant sell, etc.), number keys 1-9 select items from the list:

```gdscript
    # Inventory item selection (simplified for clarity)
    if inventory_mode and pending_inventory_action != ""
       and pending_inventory_action not in ["equip_confirm", "sort_select", ...]:
        for i in range(9):
            if is_item_select_key_pressed(i):
                if not get_meta("itemkey_%d_pressed" % i, false):
                    set_meta("itemkey_%d_pressed" % i, true)
                    _consume_item_select_key(i)     # CRITICAL: prevents double-trigger
                    select_inventory_item(selection_index)
            else:
                set_meta("itemkey_%d_pressed" % i, false)
```

The same pattern repeats for merchant sell selection, trade item selection, market browse selection, blacksmith selection, and many more. Each block checks its own mode flags and has its own pressed-state meta keys.

### Phase 6: Action bar hotkey polling

```gdscript
    if should_process_action_bar:
        for i in range(10):
            var action_key = "action_%d" % i
            var key = keybinds.get(action_key, default_keybinds.get(action_key, KEY_SPACE))

            if Input.is_physical_key_pressed(key) and not Input.is_key_pressed(KEY_SHIFT):
                # Skip if this key was consumed by item selection this frame
                if key in item_selection_consumed_this_frame:
                    continue
                if not get_meta("hotkey_%d_pressed" % i, false):
                    set_meta("hotkey_%d_pressed" % i, true)
                    if i < current_actions.size():
                        var action = current_actions[i]
                        if action.get("enabled", false) and action.get("action_type", "none") != "none":
                            trigger_action(i)
            else:
                set_meta("hotkey_%d_pressed" % i, false)
```

This is the "press-once" pattern. The meta key `hotkey_N_pressed` ensures an action fires exactly once per key press, not every frame the key is held down.

### Phase 7: Movement

```gdscript
    # World movement (only when not in any mode)
    if connected and has_character and not input_field.has_focus()
       and not in_combat and not inventory_mode and not settings_mode
       and not [many other modes...]:
        var current_time = Time.get_ticks_msec() / 1000.0
        if current_time - last_move_time >= MOVE_COOLDOWN:
            # Check numpad keys for 8-direction movement
            # Check arrow keys for 4-direction movement
            if move_dir > 0:
                send_move(move_dir)
                last_move_time = current_time
```

Movement is gated by `MOVE_COOLDOWN` (0.5 seconds) and is blocked by every UI mode. This prevents accidental movement while the player is in a menu.

### Phase 8: Network data processing

```gdscript
    if status == StreamPeerTCP.STATUS_CONNECTED:
        var available = connection.get_available_bytes()
        if available > 0:
            var data = connection.get_data(available)
            if data[0] == OK:
                var raw_bytes = data[1]
                if server_binary_mode:
                    raw_buffer.append_array(raw_bytes)
                    process_raw_buffer()
                else:
                    buffer += raw_bytes.get_string_from_utf8()
                    process_buffer()
```

The client supports two protocols: legacy newline-delimited JSON and binary-framed messages (with optional gzip compression). Both converge on `handle_server_message()`.

---

## 6. Input Handling -- _input(event)

`_input(event)` (line 2880) handles keyboard events that need immediate, event-based response rather than per-frame polling.

### Why some modes use _input() instead of _process():

1. They need to **capture** specific key events (the exact moment a key goes down)
2. They handle keys that **conflict** with the action bar (so action bar polling is disabled for them)
3. They need to call `get_viewport().set_input_as_handled()` to prevent the event from propagating
4. They handle key presses that should work **once** even if held, like typing into rebind fields

### What _input() handles (in order):

**Popup numpad input** -- When a popup with a LineEdit is open (ability cost, gambling, upgrade), numpad keys are routed to the text field:

```gdscript
if event is InputEventKey and event.pressed and not event.echo:
    var popup_input: LineEdit = null
    if ability_popup_active and ability_popup_input != null:
        popup_input = ability_popup_input
    # ... check other popups

    if popup_input != null:
        var numpad_map = {
            KEY_KP_0: "0", KEY_KP_1: "1", KEY_KP_2: "2", ...
        }
        if numpad_map.has(event.keycode):
            # Insert the character at caret position
            popup_input.text = ...
            get_viewport().set_input_as_handled()
            return
```

**Combat phase skip** -- Any key press during combat message animation skips the delay.

**Keybind rebinding** -- When `rebinding_action != ""`, the next key press is captured as the new binding:

```gdscript
if rebinding_action != "" and event is InputEventKey and event.pressed:
    if keycode == KEY_ESCAPE:
        rebinding_action = ""  # Cancel
    else:
        complete_rebinding(keycode)
    get_viewport().set_input_as_handled()
    return
```

**Settings mode** -- The full settings menu keyboard handling lives here. Each submenu (action keys, movement keys, item keys, UI scale, sound) has its own block:

```gdscript
if settings_mode and not rebinding_action and event is InputEventKey and event.pressed:
    if settings_submenu == "":
        # Main settings: Q=Actions, W=Movement, E=Items, R=Reset, 1=Game, etc.
        if keycode == key_action_0:
            set_meta("hotkey_0_pressed", true)  # Prevent double-trigger!
            close_settings()
        elif keycode == key_action_1:
            settings_submenu = "action_keys"
            display_action_keybinds()
            update_action_bar()
    # ... more submenus
    get_viewport().set_input_as_handled()
```

**Build direction input** -- WASD keys for choosing which direction to place a structure.

**Title mode, combat item mode, monster select mode** -- Each has its own keyboard handling block in `_input()` because they are excluded from action bar polling.

### The critical pattern: marking hotkeys as pressed on mode exit

When a mode handled by `_input()` closes via a hotkey, you **must** mark that hotkey as pressed to prevent the action bar from also triggering on the same key:

```gdscript
# Exiting settings mode via Space key:
if keycode == key_action_0:
    set_meta("hotkey_0_pressed", true)  # CRITICAL: prevents action bar from also firing
    close_settings()
```

Without this, the Space key would close settings AND trigger whatever action is in slot 0 of the new mode (like opening inventory).

---

## 7. Message Handling -- handle_server_message()

`handle_server_message()` (line 14970) is the client's message dispatcher. Every JSON message from the server passes through this function.

### Structure:

```gdscript
func handle_server_message(message: Dictionary):
    var msg_type = message.get("type", "")

    match msg_type:
        "welcome":
            display_game("[color=#00FF00]%s[/color]" % message.get("message", ""))
            game_state = GameState.LOGIN_SCREEN

        "login_success":
            username = message.get("username", "")
            send_to_server({"type": "house_request"})
            game_state = GameState.HOUSE_SCREEN

        "character_loaded":
            has_character = true
            _set_character_data(message.get("character", {}))
            show_game_ui()
            display_character_status()

        "character_update":
            # THE MOST IMPORTANT AND DANGEROUS HANDLER (see Section 9)
            ...

        "location":
            update_map(message.get("description", ""))
            at_water = message.get("at_water", false)
            at_ore_deposit = message.get("at_ore_deposit", false)
            # ... update all location flags, then update action bar

        "text":
            # Display a text message in game_output
            var text = message.get("message", "")
            display_game(text)

        "combat_start":
            _process_combat_start(message)

        "combat_message":
            # Queued for phased display with optional delay
            var combat_msg = message.get("message", "")
            combat_msg_queue.append({"raw": combat_msg})

        "combat_end":
            # Exit combat, show rewards, check for chain encounter
            ...

        "error":
            display_game("[color=#FF0000]Error: %s[/color]" % message.get("message", ""))

        # ... 100+ more message types
```

### Key message types and what they do:

| Message Type | Purpose | Triggers UI Refresh? |
|---|---|---|
| `character_update` | All stat/inventory/equipment changes | YES -- the most dangerous one |
| `location` | Map data, terrain flags, nearby entities | Yes (map panel) |
| `text` | Freeform text to display | No (just appends) |
| `combat_start` | Enter combat mode | Yes (shows monster) |
| `combat_end` | Exit combat, show rewards | Yes |
| `combat_message` | Combat log line | No (appends to queue) |
| `inventory_update` | Targeted inventory change | Sometimes |
| `house_data` / `house_update` | Sanctuary data | Yes (house display) |
| `market_listings` | Market browse results | Yes (market display) |
| `craft_result` | Crafting outcome | Yes (result display) |

### The `character_update` handler -- the most critical code in the client

This handler (line 15439) fires after almost every server-side action that changes the player's state. It updates all character data and then checks which mode the client is in to refresh the appropriate display:

```gdscript
"character_update":
    if message.has("character"):
        var is_full = message.get("full", true)
        if is_full:
            _set_character_data(message.character)
        else:
            _merge_character_delta(message.character)

        # Update all stat bars
        update_player_level()
        update_player_hp_bar()
        update_resource_bar()
        update_player_xp_bar()
        update_currency_display()
        update_companion_art_overlay()

        # Re-display current mode (THIS IS WHERE THINGS GO WRONG)
        if inventory_mode:
            if pending_inventory_action == "equip_item":
                # Rebuild equippable list
            elif pending_inventory_action == "viewing_materials":
                pass  # Don't refresh -- keep showing materials
            elif pending_inventory_action == "awaiting_salvage_result":
                pass  # Don't refresh -- keep showing salvage result
            # ... many more pending_inventory_action checks
            else:
                display_inventory()  # DEFAULT: clears game_output and redraws
                update_action_bar()

        if at_merchant and pending_merchant_action == "sell":
            display_merchant_sell_list()

        if companions_mode:
            if pending_companion_action in ["inspect", "inspect_select"]:
                pass  # Don't refresh
            else:
                display_companions()

        if gathering_mode:
            pass  # Don't refresh during gathering

        if market_mode:
            if pending_market_action == "list_material":
                display_market_list_materials()
            elif pending_market_action != "":
                pass  # Don't refresh for other market sub-modes
        # ... more mode checks
```

The pattern here is critical to understand: every mode check must either refresh appropriately OR skip the refresh when the player is in a sub-state that should not be cleared. This is explained in full detail in Section 9.

---

## 8. Display Functions Pattern

All display functions follow the same general pattern:

```gdscript
func display_inventory():
    """Display the player's inventory and equipped items"""
    if not has_character:
        return

    # Step 1: Clear previous output
    game_output.clear()

    # Step 2: Get data
    var inventory = character_data.get("inventory", [])
    var equipped = character_data.get("equipped", {})

    # Step 3: Show header
    display_game("[color=#FFD700]===== INVENTORY =====[/color]")

    # Step 4: Render content with BBCode formatting
    display_game("[color=#00FFFF]Equipped:[/color]")
    for slot in ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]:
        var item = equipped.get(slot)
        if item != null:
            var color = _get_item_rarity_color(item.get("rarity", "common"))
            display_game("  %s: [color=%s]%s[/color] Lv%d" % [slot, color, item.name, item.level])
        else:
            display_game("  %s: [color=#808080](empty)[/color]" % slot)

    # Step 5: Paginated item list
    display_game("")
    display_game("[color=#00FFFF]Backpack:[/color]")
    var start = inventory_page * INVENTORY_PAGE_SIZE
    for i in range(start, min(start + INVENTORY_PAGE_SIZE, inventory.size())):
        var item = inventory[i]
        display_game("  [%d] %s" % [i - start + 1, item.get("name", "Unknown")])

    # Step 6: Controls help text
    display_game("")
    display_game("[color=#808080]Space=Back  Q=Equip  W=Use  E=Inspect[/color]")

    # Step 7: Update action bar to match this mode
    update_action_bar()
```

### The display_game() helper (line 21964):

```gdscript
func display_game(text: String):
    if game_output:
        game_output.append_text(text + "\n")
```

This simply appends text with a newline to the `game_output` RichTextLabel. BBCode is interpreted automatically because the node has `bbcode_enabled = true`.

### clear_game_output() (line 22037):

```gdscript
func clear_game_output():
    """Clear game output and reset any special background"""
    _reset_game_output_background()
    if game_output:
        game_output.clear()
```

### Key display functions and where to find them:

| Function | Purpose | Approximate Line |
|---|---|---|
| `display_inventory()` | Backpack and equipment | 12727 |
| `display_character_status()` | Full stat sheet | 18757 |
| `display_companions()` | Companion list | Search for it |
| `display_eggs()` | Egg incubation view | Search for it |
| `display_settings_menu()` | Settings options | Search for it |
| `display_house_main()` | Sanctuary home screen | Search for it |
| `display_more_menu()` | More menu hub | Search for it |
| `display_combat_status()` | Combat HP bars, monster info | Search for it |
| `display_materials()` | Gathered materials list | Search for it |
| `display_market_main()` | Market main menu | Search for it |

---

## 9. The "Output Disappears" Problem -- MOST IMPORTANT SECTION

This is the single most common bug when adding new features. If you only read one section of this guide, read this one.

### The Problem

1. Player does something (uses an item, salvages gear, views materials)
2. Client displays the result in `game_output`
3. Within 1-2 seconds, the server sends a `character_update` (because stats changed)
4. The `character_update` handler checks: "Are we in inventory mode? Yes. Call `display_inventory()`."
5. `display_inventory()` calls `game_output.clear()` -- the player's result is **gone**

The player sees their result for a split second, then it vanishes. This affects **every** mode:

- Inventory: salvage results, material views, item use feedback
- Merchant: buy/sell confirmation messages
- Trading post: trade results
- Companions: activation/dismissal feedback
- Crafting: craft results
- Any mode where the server sends a `character_update` after the action

### The Fix -- The Three-Part Pattern

Every new action that shows output the player needs to read requires three things:

**Part 1: Set a pending flag before displaying output**

```gdscript
# When the player triggers the action:
pending_inventory_action = "my_new_action"

# Display the result:
game_output.clear()
display_game("[color=#FFD700]===== MY ACTION RESULT =====[/color]")
display_game("You found 5 items worth 150 gold!")
update_action_bar()
```

**Part 2: Add a bypass in the character_update handler**

Find the `character_update` handler (line 15439) and add your pending state to the bypass list:

```gdscript
# In the "character_update" match arm, find the inventory_mode block:
if inventory_mode:
    if pending_inventory_action == "equip_item":
        # ... existing handler
    elif pending_inventory_action == "viewing_materials":
        pass  # Don't refresh
    elif pending_inventory_action == "my_new_action":  # ADD THIS
        pass  # Don't refresh -- keep showing our output
    else:
        display_inventory()  # Default: refresh
```

**Part 3: Add your state to the item selection exclusion list**

In `_process()`, around line 1935, there is a long condition that checks which `pending_inventory_action` values should **not** process item selection keys. Add your new state:

```gdscript
if ... and pending_inventory_action not in [
    "equip_confirm", "sort_select", "salvage_select",
    "viewing_materials", "awaiting_salvage_result",
    "my_new_action"   # ADD THIS
] and not monster_select_mode:
```

Without this exclusion, pressing number keys 1-9 while viewing your action result would be processed as item selections, causing unexpected behavior.

**Part 4: Add a "Back" handler to return to the parent view**

In `execute_local_action()`, add a handler for the back button:

```gdscript
"my_action_back":
    pending_inventory_action = ""
    display_inventory()
    update_action_bar()
```

And in `update_action_bar()`, add action bar buttons for your new state:

```gdscript
elif pending_inventory_action == "my_new_action":
    current_actions = [
        {"label": "Back", "action_type": "local", "action_data": "my_action_back", "enabled": true},
        # ... other buttons as needed
        {"label": "---", "action_type": "none", "action_data": "", "enabled": false},
        # ... fill remaining slots
    ]
```

### Verification checklist

After implementing the fix:

1. Trigger your new action
2. Confirm the output displays correctly
3. Wait 2-3 seconds (server messages will arrive)
4. The output should **still** be visible
5. Press Back -- should return to the parent view
6. Press number keys -- should not trigger unintended selections

### Where refreshes happen -- quick reference

Search `client.gd` for these patterns to find where to add bypasses:

- `if inventory_mode:` in the `character_update` handler
- `if at_merchant and pending_merchant_action ==` in `character_update`
- `if companions_mode:` in `character_update`
- `if market_mode:` in `character_update`
- Any `display_xxx()` call triggered by incoming messages
- Any `game_output.clear()` call in message handlers

---

## 10. The Number Key Conflict

Keys 1-5 serve **two purposes** simultaneously:

| Key | Action Bar Slot | Item Selection |
|-----|----------------|----------------|
| 1   | Slot 5         | Item #1        |
| 2   | Slot 6         | Item #2        |
| 3   | Slot 7         | Item #3        |
| 4   | Slot 8         | Item #4        |
| 5   | Slot 9         | Item #5        |

When the player is in a numbered list (inventory, merchant sell, etc.), pressing "1" should select item #1, NOT trigger action bar slot 5. When the player is in movement mode, pressing "1" should trigger action bar slot 5, NOT select an item.

### How it is resolved:

**Same-frame protection:** `item_selection_consumed_this_frame` tracks which keycodes were consumed by item selection handlers. The action bar polling checks this array and skips any consumed keys:

```gdscript
# In action bar polling:
if key in item_selection_consumed_this_frame:
    continue  # Skip -- item selection already handled this key
```

**Cross-frame protection:** When an item selection handler fires, it marks the corresponding action bar hotkey as "already pressed" so the next frame does not see it as a new press:

```gdscript
func _consume_item_select_key(item_index: int):
    """Mark an item selection key as consumed to prevent action bar double-trigger."""
    var keycode = get_item_select_keycode(item_index)
    # Same-frame: add to consumed list
    item_selection_consumed_this_frame.append(keycode)
    # Cross-frame: mark corresponding action bar slot as pressed
    for ab_slot in range(10):
        var ab_key = keybinds.get("action_%d" % ab_slot, ...)
        if ab_key == keycode:
            set_meta("hotkey_%d_pressed" % ab_slot, true)
            break
```

### The mandatory rule:

**Every** place in `_process()` that calls `is_item_select_key_pressed(i)` and triggers an action **must** also call `_consume_item_select_key(i)`:

```gdscript
# CORRECT pattern:
if is_item_select_key_pressed(i):
    if not get_meta("mykey_%d_pressed" % i, false):
        set_meta("mykey_%d_pressed" % i, true)
        _consume_item_select_key(i)    # MANDATORY
        do_the_actual_action(i)
else:
    set_meta("mykey_%d_pressed" % i, false)
```

Missing the `_consume_item_select_key(i)` call will cause double-triggers: the item gets selected AND the action bar button fires.

### Mode exit double-trigger

Another variant of this problem occurs when a mode exits because of a key press. For example, if pressing "1" in inventory mode discards an item and sets `inventory_mode = false`, the action bar sees the still-held "1" key on the next frame and fires slot 5 (which might open settings).

The fix is to mark the action bar hotkey as pressed when exiting the mode:

```gdscript
# When exiting a mode via key press:
var action_slot = i + 5  # KEY_1 = slot 5, KEY_2 = slot 6, etc.
set_meta("hotkey_%d_pressed" % action_slot, true)
```

---

## 11. Pagination

Many display screens use pagination for long lists. The pattern is consistent:

### Variables:

```gdscript
var inventory_page: int = 0
var crafting_page: int = 0
var companions_page: int = 0
var eggs_page: int = 0
var market_page: int = 0
# etc.

const INVENTORY_PAGE_SIZE: int = 9    # Items per page (keys 1-9)
const COMPANIONS_PAGE_SIZE = 5
const EGGS_PAGE_SIZE = 3              # Fewer per page (ASCII art takes space)
const CRAFTING_PAGE_SIZE = 5
```

### Action bar buttons:

Prev/Next page buttons appear in the action bar when a list has multiple pages:

```gdscript
# In update_action_bar(), within the inventory mode section:
{"label": "Prev", "action_type": "local", "action_data": "inventory_prev_page",
 "enabled": inventory_page > 0},
{"label": "Next", "action_type": "local", "action_data": "inventory_next_page",
 "enabled": (inventory_page + 1) * INVENTORY_PAGE_SIZE < total_items},
```

### Handlers in execute_local_action():

```gdscript
"inventory_prev_page":
    if inventory_page > 0:
        inventory_page -= 1
        display_inventory()
        update_action_bar()
"inventory_next_page":
    inventory_page += 1
    display_inventory()
    update_action_bar()
```

### How display functions use pagination:

```gdscript
# Calculate page bounds
var start_index = page * PAGE_SIZE
var end_index = min(start_index + PAGE_SIZE, total_items)

# Display only items for this page
for i in range(start_index, end_index):
    var display_num = i - start_index + 1  # 1-based for player display
    display_game("[%d] %s" % [display_num, items[i].name])

# Show page indicator
display_game("[color=#808080]Page %d/%d[/color]" % [page + 1, total_pages])
```

When items are removed (sold, discarded, etc.), always clamp the page to prevent showing an empty page:

```gdscript
var total_pages = max(1, ceili(float(items.size()) / PAGE_SIZE))
if page >= total_pages:
    page = total_pages - 1
```

---

## 12. Audio System

The client has a simple audio system:

### Background music:

```gdscript
var music_player: AudioStreamPlayer  # Created in _ready()
var music_muted: bool = true         # Starts muted
const MUSIC_VOLUME_DB = -10.0
```

Music is procedurally generated and loops. The toggle button (`music_toggle`) switches between muted and playing. The music player is set up in `_ready()`:

```gdscript
music_player = AudioStreamPlayer.new()
music_player.volume_db = MUSIC_VOLUME_DB
add_child(music_player)
music_player.finished.connect(_on_music_finished)
```

### Sound effects:

Sound effects are loaded from WAV files in the `audio/` directory. There are dedicated functions for each sound type:

```gdscript
play_combat_sound()        # Generic combat hit
play_damage_sound()        # Player takes damage
play_death_sound()         # Monster or player death
play_loot_sound()          # Item pickup
play_level_up_sound()      # Level up fanfare
play_ui_click()            # Button click
# etc.
```

Volume is adjustable in the settings menu through the "Sound" submenu. Settings are persisted to `user://settings.json`.

---

## 13. Keybind System

All keys are fully rebindable. The system uses two dictionaries:

```gdscript
var default_keybinds = {
    "action_0": KEY_SPACE,   # Primary action
    "action_1": KEY_Q,       # Second action
    "action_2": KEY_W,       # Third action
    "action_3": KEY_E,       # Fourth action
    "action_4": KEY_R,       # Fifth action (contextual)
    "action_5": KEY_1,       # Extended slots (shared with item keys)
    "action_6": KEY_2,
    "action_7": KEY_3,
    "action_8": KEY_4,
    "action_9": KEY_5,
    "item_1": KEY_1,         # Item selection keys
    "item_2": KEY_2,
    # ... through item_9
    "move_1": KEY_KP_1,      # 8-direction numpad movement
    "move_2": KEY_KP_2,
    # ... through move_9
    "move_up": KEY_UP,       # Arrow key movement
    "move_down": KEY_DOWN,
    "move_left": KEY_LEFT,
    "move_right": KEY_RIGHT,
    "hunt": KEY_KP_5,        # Hunt in place
}

var keybinds: Dictionary = {}  # Active keybinds (loaded from file or defaults)
```

### Loading and saving:

Keybinds are loaded from `user://keybinds.json` on startup in `_load_keybinds()`. If the file does not exist, defaults are used. When the player rebinds a key, the new binding is saved immediately.

### How keybinds are used in code:

```gdscript
# Always look up the active binding, falling back to default:
var key = keybinds.get("action_0", default_keybinds.get("action_0", KEY_SPACE))

# Check if it is pressed:
if Input.is_physical_key_pressed(key):
    # Handle the press
```

### Rebinding flow:

1. Player enters Settings > Action Keys (or Movement Keys, or Item Keys)
2. Player presses a number key to select which binding to change
3. `start_rebinding("action_N")` sets `rebinding_action = "action_N"`
4. The next key press is captured in `_input()` and passed to `complete_rebinding(keycode)`
5. The new binding is stored in `keybinds` and saved to disk

---

## 14. Finding Things in client.gd

With 27,800+ lines, navigation is essential. Here is a reference map of where things live:

### Major sections by line number:

| Line Range | Contents |
|---|---|
| 1-30 | Script header, lazy-loaded art helpers |
| 30-300 | ASCII art recolor utilities, helper functions |
| 294-397 | Core variables: connection, buffer, keybinds, GameState enum |
| 400-470 | `@onready` UI node references |
| 470-520 | Account and house data variables |
| 520-900 | Mode flags, pending actions, all state variables |
| 900-1350 | Constants: consumable tiers, theme colors, race/class descriptions |
| 1365-1394 | Ability system constants (Mage, Warrior, Trickster ability slots) |
| 1395-1560 | `_ready()` -- initialization, signal connections |
| 1560-1858 | Helper functions: music, window resize, font scaling |
| 1859-2878 | `_process(delta)` -- main loop |
| 2880-3200 | `_input(event)` -- event-based input handling |
| 3200-3630 | Panel show/hide functions, character select/create UI |
| 3630-4580 | Game UI helpers, shortcut buttons, action bar setup |
| 4584-4722 | `setup_action_bar()` -- button creation and styling |
| 4723-7210 | `update_action_bar()` -- the massive state-to-buttons mapper |
| 7212-7240 | `_on_action_button_pressed()` and `trigger_action()` |
| 7240-9000 | Various combat, UI, and helper functions |
| 9001-12700 | `execute_local_action()` -- all click/keyboard action handlers |
| 12727-14930 | Display functions: inventory, companions, market, crafting, etc. |
| 14933-14968 | `process_buffer()` and `process_raw_buffer()` -- network parsing |
| 14970-17800 | `handle_server_message()` -- all server message handlers |
| 17800-18670 | Keybind system, action bar hotkey update, key helpers |
| 18671-18756 | `send_to_server()`, `send_move()`, movement helpers |
| 18757-21960 | More display functions: character status, help, changelog |
| 21964-22050 | `display_game()`, `clear_game_output()`, combat animation |
| 22050-27864 | Remaining display functions, GM commands, utilities |

### Tips for navigating:

1. **Search by function name.** All major functions use descriptive names: `display_inventory()`, `handle_combat_start()`, `execute_local_action()`.

2. **Search by action_data string.** If you know the button's action data (e.g., `"open_inventory"`), search for that string to find both where the button is defined (in `update_action_bar()`) and where it is handled (in `execute_local_action()`).

3. **Search by message type.** To find how a server message is handled, search for `"message_type_name":` (with the colon and quotes) in `handle_server_message()`.

4. **Search by mode flag.** To find everything related to a feature, search for its mode flag (e.g., `companions_mode`) to see where it is set, checked, and cleared.

5. **Search by variable name.** Variables are declared near the top (lines 1-900). Search for `var my_variable` to find the declaration, then search for just `my_variable` to find all uses.

6. **Use the `pending_*_action` pattern.** If you need to understand a mode's sub-states, search for its pending action variable (e.g., `pending_inventory_action`). Every assignment to that variable reveals a sub-state transition.

### Common search patterns:

```
# Find where a mode opens:
inventory_mode = true

# Find where it closes:
inventory_mode = false

# Find the action bar layout for a mode:
# Search in update_action_bar() for the mode flag check:
if inventory_mode:

# Find what happens when a button is clicked:
# Search in execute_local_action() for the action_data:
"open_inventory":

# Find how a server message is processed:
# Search in handle_server_message():
"combat_start":
```

---

## Appendix A: Networking

### Connection setup:

```gdscript
var connection = StreamPeerTCP.new()
var connected = false
var buffer = ""                # Legacy text buffer (newline-delimited JSON)
var raw_buffer = PackedByteArray()  # Binary framing buffer
var server_binary_mode = false      # Auto-detected from first byte
```

### Message format:

The client supports two protocols, auto-detected from the first byte of data:

**Legacy text mode:** Each message is a JSON object followed by a newline character (`\n`). Parsed by `process_buffer()`:

```gdscript
func process_buffer():
    while "\n" in buffer:
        var pos = buffer.find("\n")
        var msg_str = buffer.substr(0, pos)
        buffer = buffer.substr(pos + 1)
        var json = JSON.new()
        if json.parse(msg_str) == OK:
            handle_server_message(json.data)
```

**Binary framing:** Each message has a 4-byte big-endian length prefix, a 1-byte flags byte, and a payload. If flag bit 0 is set, the payload is gzip-compressed. Parsed by `process_raw_buffer()`:

```gdscript
func process_raw_buffer():
    while raw_buffer.size() >= 5:
        var frame_len = (raw_buffer[0] << 24) | (raw_buffer[1] << 16) | ...
        var flags = raw_buffer[4]
        var payload = raw_buffer.slice(5, 4 + frame_len)
        raw_buffer = raw_buffer.slice(4 + frame_len)
        if flags & 0x01:
            payload = payload.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
        # Parse JSON and dispatch
        handle_server_message(json.data)
```

### Sending messages:

```gdscript
func send_to_server(data: Dictionary):
    if not connected:
        display_game("[color=#FF0000]Not connected![/color]")
        return
    var json_str = JSON.stringify(data) + "\n"
    connection.put_data(json_str.to_utf8_buffer())
```

All outbound messages are JSON dictionaries with a `"type"` field:

```gdscript
send_to_server({"type": "move", "direction": 8})
send_to_server({"type": "combat", "action": "attack"})
send_to_server({"type": "use_item", "index": 3})
```

---

## Appendix B: Adding a New Feature -- Checklist

When adding a new feature that involves a new mode or sub-mode, follow this checklist:

1. **Declare state variables** near the top of the file (lines 400-900):
   ```gdscript
   var my_feature_mode: bool = false
   var pending_my_feature_action: String = ""
   ```

2. **Add action bar layout** in `update_action_bar()` (line 4723+):
   ```gdscript
   elif my_feature_mode:
       current_actions = [ ... 10 action definitions ... ]
   ```

3. **Add action handlers** in `execute_local_action()` (line 9001+):
   ```gdscript
   "open_my_feature":
       my_feature_mode = true
       display_my_feature()
       update_action_bar()
   "close_my_feature":
       my_feature_mode = false
       pending_my_feature_action = ""
       clear_game_output()
       update_action_bar()
   ```

4. **Add display function** somewhere in the display functions area:
   ```gdscript
   func display_my_feature():
       game_output.clear()
       display_game("[color=#FFD700]===== MY FEATURE =====[/color]")
       # ... render content
       update_action_bar()
   ```

5. **Add character_update bypass** (line 15439+) if your feature shows output that should persist:
   ```gdscript
   if my_feature_mode:
       pass  # Don't refresh during my feature
   ```

6. **Block movement** by adding `not my_feature_mode` to the movement condition (around line 2781).

7. **Block action bar if needed** by adding your mode to `should_process_action_bar` exclusions (line 2639) if your mode handles keys in `_input()`.

8. **Handle number key conflicts** by calling `_consume_item_select_key(i)` in any number-key selection handler, and by adding your pending state to the item selection exclusion list (line 1935).

9. **Handle server messages** in `handle_server_message()` if your feature receives new message types from the server.

10. **Call `update_action_bar()`** after every state change that affects what buttons should be shown.

---

## Appendix C: Common Mistakes Quick Reference

| Mistake | Symptom | Fix |
|---|---|---|
| Forgot `update_action_bar()` | Buttons show stale labels | Always call after state changes |
| Forgot character_update bypass | Output disappears after 1-2 seconds | Add pending flag + bypass check |
| Forgot `_consume_item_select_key()` | Pressing "1" selects item AND triggers action bar | Add the call in the selection handler |
| Forgot to mark hotkey pressed on mode exit | Closing mode also triggers next mode's button | `set_meta("hotkey_N_pressed", true)` |
| Only added keyboard path | Clicking action bar button does nothing | Also add handler in `execute_local_action()` |
| Only added click path | Hotkey does nothing | Ensure the mode is not excluded from action bar polling, or add `_input()` handler |
| Left mode flag true on exit | Wrong buttons shown, wrong input handling | Always set `mode = false` and clear pending action |
| Forgot to block movement | Player walks while in menu | Add `not my_mode` to movement guard condition |
| Used `game_output.clear()` in a message handler | Cleared output the player was reading | Use pending flags to skip the clear |
| Added action_data to action bar but not execute_local_action | Click does nothing, no error | Always add both the button definition AND the handler |
