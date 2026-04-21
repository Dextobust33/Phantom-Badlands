# Godot Engine Basics

This guide teaches you the fundamentals of the Godot game engine from the ground up. You will learn general Godot concepts alongside real examples from Phantom Badlands, so that by the end you can confidently navigate and modify the codebase.

**Prerequisites:** Programming experience in any language. No prior Godot or game development experience required.

**Godot version:** 4.6.stable (GDScript)

---

## 1. How Godot Works -- The Big Picture

Godot is a free, open-source game engine. Unlike a library that you import into your code, Godot provides a complete environment: an editor for building interfaces, a scripting language (GDScript), a rendering pipeline, input handling, audio, networking, and more.

Here are the core concepts:

**Nodes** are the building blocks. Everything in a Godot game is a Node -- buttons, text displays, containers, timers, audio players, even invisible logic holders. Each Node type provides specific functionality.

**Scenes** are saved trees of Nodes. A Scene is like a blueprint -- you design it once and can create instances of it. Scenes are stored as `.tscn` files.

**Scripts** are GDScript files (`.gd`) attached to Nodes. They define the behavior of that Node. GDScript is a Python-like language designed specifically for Godot.

**The Scene Tree** is the runtime hierarchy of all active Nodes. When your game runs, everything that exists is part of this tree. Nodes can find each other, send messages, and respond to events through the tree.

**A helpful analogy:** If you have web development experience, think of it this way:
- **Nodes** are like HTML elements (`<div>`, `<button>`, `<input>`, `<span>`)
- **The Scene Tree** is like the DOM -- a live hierarchy of all elements
- **Scripts** are like JavaScript attached to elements
- **Scenes** are like reusable Web Components
- **Signals** (covered later) are like event listeners

The key difference from web development: in Godot, there is a **game loop** running 60 times per second. Every frame, Godot updates the tree, processes input, runs your code, and renders the result. This frame-based loop is central to how everything works.

---

## 2. Nodes -- The Building Blocks

Everything in Godot is a Node. When you see a button on screen, that is a `Button` node. When you see formatted text, that is a `RichTextLabel` node. When you hear a sound, that is an `AudioStreamPlayer` node.

Each node type inherits from a parent type and adds specific functionality. Here are the node types used in Phantom Badlands:

### Control (Base UI Node)
The base class for all UI elements. Provides layout properties (anchors, margins, size), mouse handling, and focus management. Both the client and server root nodes are `Control` nodes.

```
# From client.tscn -- the root node of the entire client
[node name="ClientScene" type="Control"]
```

### VBoxContainer / HBoxContainer (Layout Containers)
Automatically arrange their children vertically (VBox) or horizontally (HBox). Think of them like CSS flexbox with `flex-direction: column` or `row`.

```
# The main layout of the client stacks elements vertically:
# StatsBar, TopSection, EnemyHealthBar, BottomStrip
[node name="RootContainer" type="VBoxContainer" parent="."]

# The top section splits horizontally: GameOutput on the left, Map on the right
[node name="TopSection" type="HBoxContainer" parent="RootContainer"]
```

### Label (Static Text)
Displays a single line or paragraph of plain text. No formatting, no scrolling. Good for headings and status displays.

```
# The level display at the top of the client
[node name="PlayerLevel" type="Label" parent="RootContainer/StatsBar/LevelRow"]
text = "Level 1"
```

### RichTextLabel (Formatted Text Display)
Displays text with BBCode formatting -- colors, bold, sizes, links. **This is the most important node type in our project.** The entire game output, chat, map, and server log all use RichTextLabel.

```
# The main game output area -- where all game text appears
[node name="GameOutput" type="RichTextLabel" parent="RootContainer/TopSection/GameOutputContainer"]
bbcode_enabled = true          # Enable BBCode formatting
scroll_following = true        # Auto-scroll to bottom when new text is added
selection_enabled = true       # Allow text selection with mouse
```

### LineEdit (Text Input)
A single-line text input field. The player types commands and chat messages into a LineEdit.

```
# The input field at the bottom of the chat panel
[node name="InputField" type="LineEdit" parent="RootContainer/BottomStrip/ChatPanel/InputRow"]
placeholder_text = "Type message or command..."
keep_editing_on_text_submit = true   # Don't lose focus after pressing Enter
```

### Button (Clickable Button)
A clickable button that emits a `pressed` signal when clicked. The action bar is made of 10 Button nodes.

```
# One of the 10 action bar buttons
[node name="Button" type="Button" parent="RootContainer/BottomStrip/CenterPanel/ActionBar/Action1"]
text = "---"     # Default text, updated dynamically by code
```

### Panel (Visual Container)
A container with a background. Used for overlay screens like the login panel, death screen, and leaderboard.

```
# The login screen -- a Panel centered on the window
[node name="LoginPanel" type="Panel" parent="."]
visible = false    # Hidden by default, shown when needed
```

### AudioStreamPlayer (Sound)
Plays audio files. Not visible on screen. Used for music and sound effects.

### Node (Bare Logic Holder)
The most basic node type. Has no visual representation, no UI, nothing -- it is just a place to attach a script. Used when you need pure logic.

```
# CombatManager is a plain Node -- it has no UI, just combat logic
class_name CombatManager
extends Node
```

### How to Think About Node Types

Each node type is a **specialization**. The inheritance chain looks like this:

```
Node                          # Base: has a name, can have children, runs _process()
  └── Control                 # Adds: UI layout, mouse input, focus
        ├── Label             # Adds: displays plain text
        ├── RichTextLabel     # Adds: displays BBCode-formatted text, scrolling
        ├── LineEdit          # Adds: text input, cursor, editing
        ├── Button            # Adds: click detection, pressed signal
        ├── Panel             # Adds: draws a background
        ├── VBoxContainer     # Adds: arranges children vertically
        └── HBoxContainer     # Adds: arranges children horizontally
```

When you create a node of type `Button`, you get everything that `Control` provides (layout, focus, mouse events) PLUS the button-specific features (click detection, text display, pressed signal). This is standard object-oriented inheritance.

---

## 3. Scenes -- Reusable Node Trees

A **Scene** is a tree of nodes saved to a `.tscn` file. Think of a scene as a blueprint or template. When you "instance" a scene, Godot creates all the nodes defined in that file.

Phantom Badlands has three main scenes:

| Scene File | Purpose |
|-----------|---------|
| `client/client.tscn` | The game client -- everything the player sees and interacts with |
| `server/server.tscn` | The server control panel -- admin UI for managing the game server |
| `launcher/launcher.tscn` | The game launcher -- checks for updates, launches the client |

### How the Client Scene Is Structured

The client scene is the most complex. Here is its node tree (simplified to show the important parts):

```
ClientScene (Control)                    -- Root node, client.gd script attached here
├── RootContainer (VBoxContainer)        -- Main vertical layout (always visible)
│   ├── StatsBar (VBoxContainer)         -- Top bar: level, HP, XP, currency
│   │   ├── LevelRow (HBoxContainer)
│   │   │   ├── PlayerLevel (Label)      -- "Level 42"
│   │   │   └── MusicToggle (Button)     -- Music on/off
│   │   ├── PlayerHealthBar (Control)    -- Green HP bar with label
│   │   ├── ResourceBar (Control)        -- Stamina/Mana/Energy bar
│   │   ├── PlayerXPBar (Control)        -- XP progress bar
│   │   └── CurrencyDisplay (HBoxContainer)
│   │       ├── GoldContainer            -- "Valor: 1500"
│   │       └── RankContainer            -- "Rank: Adventurer"
│   │
│   ├── TopSection (HBoxContainer)       -- Main content area, splits left/right
│   │   ├── GameOutputContainer (Control)
│   │   │   ├── GameOutput (RichTextLabel)     -- THE main game text display
│   │   │   ├── BuffDisplayLabel (RichTextLabel) -- Overlay: active buffs
│   │   │   ├── CompanionArtOverlay (RichTextLabel) -- Overlay: companion art
│   │   │   └── ResourceBarsOverlay (RichTextLabel) -- Overlay: HP/resource bars
│   │   └── MapPanel (VBoxContainer)
│   │       └── MapDisplay (RichTextLabel)     -- World map (ASCII)
│   │
│   ├── EnemyHealthBar (HBoxContainer)   -- Shown during combat only
│   │
│   └── BottomStrip (HBoxContainer)      -- Bottom area, splits left/right
│       ├── CenterPanel (VBoxContainer)
│       │   └── ActionBar (HBoxContainer) -- 10 action buttons (Space,Q,W,E,R,1-5)
│       │       ├── Action1 (VBoxContainer) -- Button + "Space" hotkey label
│       │       ├── Action2 (VBoxContainer) -- Button + "Q" hotkey label
│       │       ├── ...
│       │       └── Action10 (VBoxContainer) -- Button + "5" hotkey label
│       └── ChatPanel (VBoxContainer)
│           ├── ChatTabBar (HBoxContainer) -- "Chat" and "Players" tabs
│           ├── ChatOutput (RichTextLabel)  -- Chat messages
│           ├── OnlinePlayersList (RichTextLabel) -- Online players (hidden by default)
│           └── InputRow (HBoxContainer)
│               ├── InputField (LineEdit)   -- Where the player types
│               └── SendButton (Button)     -- "Send" button
│
├── LoginPanel (Panel)                   -- Login/register screen (overlay)
├── CharacterSelectPanel (Panel)         -- Character selection (overlay)
├── CharacterCreatePanel (Panel)         -- New character creation (overlay)
├── DeathPanel (Panel)                   -- Death screen (overlay)
└── LeaderboardPanel (Panel)             -- High scores (overlay)
```

Notice the pattern: the `RootContainer` holds everything the player sees during gameplay. The overlay panels (Login, CharacterSelect, etc.) are siblings of `RootContainer` -- they float on top and are toggled visible/hidden based on game state.

### How Scene Files Look

Scene files (`.tscn`) are text files. Each node is defined with its type, parent path, and properties:

```
[node name="GameOutput" type="RichTextLabel" parent="RootContainer/TopSection/GameOutputContainer"]
bbcode_enabled = true
scroll_following = true
theme_override_font_sizes/normal_font_size = 14
```

You generally do not edit `.tscn` files by hand -- you use the Godot editor. But understanding the format helps when reading the project.

---

## 4. Scripts -- Adding Behavior to Nodes

A script is a `.gd` file attached to a node. The script defines what that node **does**. Without a script, a node just sits there with its default behavior (a button can be clicked, a label displays text, etc.). Scripts add custom logic.

### The extends Declaration

Every script starts by declaring which node type it extends:

```gdscript
# client.gd -- attached to the ClientScene node, which is a Control
extends Control

# character.gd -- not a node, it's a data container
class_name Character
extends Resource

# combat_manager.gd -- a logic-only node
class_name CombatManager
extends Node

# server.gd -- attached to the Server node, which is a Control
extends Control
```

The `extends` keyword tells Godot what type of node this script belongs to. A script that `extends Control` can only be attached to Control nodes (or nodes that inherit from Control, like Panel or Button). The script gets access to all the methods and properties of that node type.

### self Refers to the Node

Inside a script, `self` refers to the node the script is attached to. Since `client.gd` is attached to the `ClientScene` Control node, `self` inside `client.gd` IS the ClientScene node.

```gdscript
# Inside client.gd:
self.visible = true    # Makes the ClientScene node visible
# You can also omit "self" -- GDScript assumes it:
visible = true         # Same thing
```

### Referencing Child Nodes with @onready

The most important pattern you will see throughout this project is `@onready var`:

```gdscript
# These lines find child nodes by their path in the scene tree.
# The path is relative to the node this script is attached to (ClientScene).
@onready var game_output = $RootContainer/TopSection/GameOutputContainer/GameOutput
@onready var input_field = $RootContainer/BottomStrip/ChatPanel/InputRow/InputField
@onready var send_button = $RootContainer/BottomStrip/ChatPanel/InputRow/SendButton
@onready var action_bar = $RootContainer/BottomStrip/CenterPanel/ActionBar
@onready var map_display = $RootContainer/TopSection/MapPanel/MapDisplay
@onready var login_panel = $LoginPanel
@onready var enemy_health_bar = $RootContainer/EnemyHealthBar
```

Let us break this down:
- `@onready` means "run this assignment when the node enters the scene tree" (i.e., when `_ready()` is called). Before that moment, child nodes might not exist yet.
- `$` is shorthand for `get_node()`. The path after `$` navigates the scene tree relative to the current node.
- `$RootContainer/TopSection/GameOutputContainer/GameOutput` means: starting from ClientScene, go into RootContainer, then TopSection, then GameOutputContainer, then find GameOutput.

After these `@onready` lines run, you can use the variables anywhere in the script:

```gdscript
# Write text to the game output
game_output.append_text("[color=#FFD700]Welcome to Phantom Badlands![/color]\n")

# Clear all text from the game output
game_output.clear()

# Hide the login panel
login_panel.visible = false

# Read what the player typed
var player_input = input_field.text
```

### Variables and Constants

Scripts can declare variables (state that changes) and constants (values that never change):

```gdscript
# From client.gd:
var connection = StreamPeerTCP.new()    # TCP connection to the server
var connected = false                    # Are we connected?
var buffer = ""                          # Incoming data buffer

# Constants
const KEYBIND_CONFIG_PATH = "user://keybinds.json"

# Enums (a set of named constants)
enum GameState {
    DISCONNECTED,
    CONNECTED,
    LOGIN_SCREEN,
    HOUSE_SCREEN,
    CHARACTER_SELECT,
    PLAYING,
    DEAD
}
var game_state = GameState.DISCONNECTED
```

### Functions

Functions are declared with `func`. GDScript uses indentation (like Python) to define blocks:

```gdscript
# A simple function that writes text to the game output
func display_game(text: String):
    if game_output:
        game_output.append_text(text + "\n")

# A function with a return value
func get_version() -> String:
    return "0.9.144"

# A function with default parameters
func send_message(type: String, data: Dictionary = {}):
    data["type"] = type
    var json = JSON.stringify(data)
    connection.put_data((json + "\n").to_utf8_buffer())
```

---

## 5. The Node Lifecycle -- _ready(), _process(), _input()

This section is **critical** for understanding how Phantom Badlands works. Godot calls specific functions on your script at specific times. These are called **virtual methods** or **lifecycle callbacks**.

### _ready() -- Called Once at Startup

`_ready()` is called **once** when the node first enters the scene tree. This happens when the game starts (or when a node is dynamically added later). Use it for initialization.

```gdscript
func _ready():
    # Set the window title
    DisplayServer.window_set_title("Phantom Badlands v" + get_version())

    # Load saved keybind configuration from disk
    _load_keybinds()

    # Set up the action bar buttons
    if action_bar:
        setup_action_bar()

    # Connect UI signals (buttons, input fields, etc.)
    send_button.pressed.connect(_on_send_button_pressed)
    input_field.gui_input.connect(_on_input_gui_input)
    login_button.pressed.connect(_on_login_button_pressed)
    register_button.pressed.connect(_on_register_button_pressed)

    # Initialize audio
    music_player.finished.connect(_on_music_finished)
```

**Important:** The `@onready` variables are available inside `_ready()` and any function called after it. They are NOT available before `_ready()` runs. If you try to access `game_output` in a variable declaration at the top of the file (without `@onready`), it will be `null`.

**The server's _ready() follows the same pattern:**

```gdscript
# From server.gd:
func _ready():
    # Parse command line arguments
    var args = OS.get_cmdline_args()
    for arg in args:
        if arg.begins_with("--port="):
            PORT = int(arg.substr(7))

    # Initialize the persistence system (database)
    persistence = PersistenceManagerScript.new()
    add_child(persistence)

    # Initialize the chunk-based world system
    chunk_manager = ChunkManagerScript.new()
    add_child(chunk_manager)
```

### _process(delta) -- Called Every Frame

`_process(delta)` is called **every frame** -- typically 60 times per second. The `delta` parameter is the time in seconds since the last frame (usually around 0.016 for 60 FPS).

**This is where the main game loop lives.** The client's `_process()` is the heart of the game:

```gdscript
func _process(delta):
    # Clear per-frame tracking
    action_triggered_this_frame.clear()
    item_selection_consumed_this_frame.clear()

    # 1. NETWORKING: Poll the TCP connection for server messages
    connection.poll()
    var status = connection.get_status()
    # ... read incoming data, parse JSON, handle messages ...

    # 2. ANIMATIONS: Update combat animation timers
    if combat_animation_active:
        combat_animation_timer -= delta
        if combat_animation_timer <= 0:
            stop_combat_animation()

    # 3. COMBAT QUEUE: Display combat messages with pacing
    if combat_phase_paused:
        combat_phase_timer -= delta
        if combat_phase_timer <= 0:
            combat_phase_paused = false
            _drain_combat_queue()

    # 4. INPUT: Check for Escape key
    if game_state == GameState.PLAYING:
        if Input.is_action_just_pressed("ui_cancel"):
            # Handle escape in various modes...

    # 5. ACTION BAR: Poll hotkeys (Space, Q, W, E, R, 1-5)
    # ... check each key, fire actions if pressed ...

    # 6. ITEM SELECTION: Poll number keys (1-9) for menus
    # ... check if player is selecting an item ...
```

**Why does this matter?** Because `_process()` runs every single frame, it is constantly:
- Checking the network for new messages from the server
- Checking if the player is pressing any hotkeys
- Updating timers and animations
- Managing the combat message queue

Understanding this loop is essential to understanding how input flows through the client.

**Using delta for time-based operations:**

The `delta` parameter ensures things happen at consistent speeds regardless of frame rate:

```gdscript
# Wrong: this moves 5 units per FRAME (speed depends on FPS)
position.x += 5

# Right: this moves 300 units per SECOND (consistent regardless of FPS)
position.x += 300 * delta
```

In Phantom Badlands (a text-based game), `delta` is mainly used for timers:

```gdscript
# Count down a timer by the time elapsed this frame
combat_animation_timer -= delta
if combat_animation_timer <= 0:
    stop_combat_animation()
```

### _input(event) -- Called on Input Events

`_input(event)` is called whenever an input event occurs -- a key is pressed, a key is released, the mouse moves, a mouse button is clicked, etc. The `event` parameter contains the details.

```gdscript
func _input(event):
    # Only care about key presses (not releases, not mouse, etc.)
    if event is InputEventKey and event.pressed and not event.echo:
        # Handle numpad input for popup dialogs
        if ability_popup_active and ability_popup_input != null:
            # Route numpad keys to the popup input field
            # ...

        # Handle mode-specific keys
        if settings_mode:
            # Settings navigation (arrow keys, etc.)
            # ...

        if building_mode:
            # Building direction keys
            # ...
```

**The difference between _input() and _process():**

| Aspect | `_input(event)` | `_process(delta)` |
|--------|-----------------|-------------------|
| When called | Only when input happens | Every frame, always |
| What you get | Specific event details | Nothing (you poll) |
| Use for | Reacting to key presses/releases | Checking if keys are held |
| Fires | Once per press, once per release | 60 times per second |

### Execution Order Within a Frame

This is the order Godot processes things each frame:

```
Frame N:
  1. _input(event)     <-- Called for EACH input event that happened since last frame
  2. _process(delta)   <-- Called once per frame, always
  3. Rendering          <-- Godot draws everything to screen
```

Here is a concrete example of a typical sequence:

```
Frame 1:                              Frame 2:
  _input(key_press: Space)              _process(0.016)
  _process(0.016)                       [no input this frame]

Frame 3:                              Frame 4:
  _input(key_release: Space)            _process(0.016)
  _process(0.016)                       [no input this frame]
```

**Why Phantom Badlands uses both:**
- `_input()` handles things that need to respond ONCE to a key press (like settings navigation, building direction keys, keybind rebinding)
- `_process()` handles things that check if a key is HELD DOWN (like the action bar hotkeys, where you check `Input.is_physical_key_pressed()` every frame)

---

## 6. Signals -- Event Communication

Signals are Godot's built-in event system. They allow nodes to communicate without being tightly coupled. If you know JavaScript, signals are like `addEventListener` and `dispatchEvent`.

### How Signals Work

1. A node **emits** a signal when something happens (button clicked, text entered, timer expired)
2. Other code **connects** to that signal with a handler function
3. When the signal fires, the handler function is called

### Connecting to Built-in Signals

Most node types have built-in signals. Here are the ones used heavily in Phantom Badlands:

```gdscript
# In _ready(), we connect signals to handler functions:

# Button.pressed -- fires when the button is clicked
send_button.pressed.connect(_on_send_button_pressed)
login_button.pressed.connect(_on_login_button_pressed)
register_button.pressed.connect(_on_register_button_pressed)
music_toggle.pressed.connect(_on_music_toggle_pressed)

# LineEdit.text_submitted -- fires when the player presses Enter
password_field.text_submitted.connect(_on_password_submitted)

# LineEdit.gui_input -- fires on any input event while focused
input_field.gui_input.connect(_on_input_gui_input)

# RichTextLabel.meta_clicked -- fires when a BBCode link is clicked
online_players_list.meta_clicked.connect(_on_player_name_clicked)

# Control.focus_entered / focus_exited -- fires when a control gains/loses focus
input_field.focus_entered.connect(_on_input_focus_entered)
input_field.focus_exited.connect(_on_input_focus_exited)

# OptionButton.item_selected -- fires when the user picks an option
race_option.item_selected.connect(_on_race_selected)
class_option.item_selected.connect(_on_class_selected)

# AudioStreamPlayer.finished -- fires when a sound finishes playing
music_player.finished.connect(_on_music_finished)
```

### The Handler Functions

Each connected function receives the signal's parameters (if any):

```gdscript
# Button.pressed has no parameters
func _on_send_button_pressed():
    var text = input_field.text
    if text != "":
        handle_input_submitted(text)
        input_field.clear()

# LineEdit.text_submitted passes the submitted text
func handle_input_submitted(text: String):
    # Process the player's command or chat message
    # ...

# OptionButton.item_selected passes the selected index
func _on_race_selected(index: int):
    # Update the race description based on selection
    # ...

# RichTextLabel.meta_clicked passes the metadata value
func _on_player_name_clicked(meta):
    # meta contains whatever was set in the [url] BBCode tag
    var player_name = str(meta)
    # Show player info...
```

### The .bind() Method

You can pass extra arguments to a signal handler using `.bind()`:

```gdscript
# Both tabs connect to the same function, but with different arguments
chat_tab_button.pressed.connect(_on_chat_tab_pressed.bind("chat"))
players_tab_button.pressed.connect(_on_chat_tab_pressed.bind("players"))

func _on_chat_tab_pressed(tab_name: String):
    if tab_name == "chat":
        chat_output.visible = true
        online_players_list.visible = false
    elif tab_name == "players":
        chat_output.visible = false
        online_players_list.visible = true
```

### Custom Signals (Declaring Your Own)

You can declare and emit your own signals, though Phantom Badlands mostly uses built-in ones:

```gdscript
# Declare a custom signal
signal health_changed(new_hp: int, max_hp: int)

# Emit it when health changes
func take_damage(amount: int):
    current_hp -= amount
    health_changed.emit(current_hp, max_hp)

# Connect to it from another script
player_node.health_changed.connect(_on_player_health_changed)

func _on_player_health_changed(new_hp: int, max_hp: int):
    update_health_bar(new_hp, max_hp)
```

---

## 7. @onready and Node References

This section goes deeper into how scripts find and reference other nodes.

### @onready Timing

The `@onready` annotation delays a variable assignment until the node enters the scene tree. This is necessary because child nodes are not guaranteed to exist when the script is first loaded.

```gdscript
# WRONG -- game_output might not exist yet when this line runs
var game_output = $RootContainer/TopSection/GameOutputContainer/GameOutput  # Could be null!

# RIGHT -- @onready waits until _ready() time, when children definitely exist
@onready var game_output = $RootContainer/TopSection/GameOutputContainer/GameOutput
```

### The $ Shorthand

The `$` operator is shorthand for `get_node()`. Both do the same thing:

```gdscript
# These are equivalent:
@onready var game_output = $RootContainer/TopSection/GameOutputContainer/GameOutput
@onready var game_output = get_node("RootContainer/TopSection/GameOutputContainer/GameOutput")
```

The path is always **relative to the node the script is attached to**. Since `client.gd` is attached to `ClientScene`, all paths start from `ClientScene`.

### When to Use @onready vs get_node()

Use `@onready var` for nodes you reference frequently -- it looks up the node once and stores the result:

```gdscript
# Looked up once at startup, used hundreds of times throughout the code
@onready var game_output = $RootContainer/TopSection/GameOutputContainer/GameOutput
```

Use `get_node()` in runtime code when you need to find a node dynamically:

```gdscript
# Finding action bar buttons by index (the path changes based on the index)
func get_action_button(index: int) -> Button:
    var action_container = action_bar.get_child(index)
    return action_container.get_node("Button")
```

### Real Examples from the Project

Here is a selection of `@onready` declarations from `client.gd`, organized by what part of the UI they reference:

```gdscript
# Main display areas
@onready var game_output = $RootContainer/TopSection/GameOutputContainer/GameOutput
@onready var chat_output = $RootContainer/BottomStrip/ChatPanel/ChatOutput
@onready var map_display = $RootContainer/TopSection/MapPanel/MapDisplay

# Stat bars
@onready var player_health_bar = $RootContainer/StatsBar/PlayerHealthBar
@onready var resource_bar = $RootContainer/StatsBar/ResourceBar
@onready var player_xp_bar = $RootContainer/StatsBar/PlayerXPBar
@onready var player_level_label = $RootContainer/StatsBar/LevelRow/PlayerLevel
@onready var gold_label = $RootContainer/StatsBar/CurrencyDisplay/GoldContainer/GoldLabel

# Input
@onready var input_field = $RootContainer/BottomStrip/ChatPanel/InputRow/InputField
@onready var send_button = $RootContainer/BottomStrip/ChatPanel/InputRow/SendButton

# Action bar
@onready var action_bar = $RootContainer/BottomStrip/CenterPanel/ActionBar

# Overlay panels
@onready var login_panel = $LoginPanel
@onready var char_select_panel = $CharacterSelectPanel
@onready var char_create_panel = $CharacterCreatePanel

# Combat
@onready var enemy_health_bar = $RootContainer/EnemyHealthBar
```

And from `server.gd`:

```gdscript
# Server UI references
@onready var player_count_label = $VBox/StatusRow/PlayerCountLabel
@onready var player_list = $VBox/PlayerList
@onready var server_log = $VBox/ServerLog
@onready var restart_button = $VBox/ButtonRow/RestartButton
@onready var broadcast_input = $VBox/BroadcastRow/BroadcastInput
@onready var broadcast_button = $VBox/BroadcastRow/BroadcastButton
```

---

## 8. Resources vs Nodes

Godot has two main types of objects: **Nodes** and **Resources**. Understanding when to use each is important.

### Nodes

- Live in the scene tree
- Have lifecycle methods (`_ready()`, `_process()`, `_input()`)
- Can have children
- Can send and receive signals
- Have a visual or interactive presence (or hold logic that needs per-frame updates)

**Example:** The CombatManager extends Node because it needs to be part of the scene tree (the server adds it as a child node):

```gdscript
# combat_manager.gd
class_name CombatManager
extends Node

# The server creates and adds it to the tree:
# combat_manager = CombatManagerScript.new()
# add_child(combat_manager)
```

### Resources

- Pure data containers
- No scene tree, no lifecycle methods, no children
- Lightweight and efficient
- Can be saved/loaded, serialized, shared between nodes
- Good for: stats, configuration, item data, character data

**Example:** Character extends Resource because it is purely data -- stats, inventory, position. It does not need per-frame updates or a place in the scene tree:

```gdscript
# character.gd
class_name Character
extends Resource

@export var name: String = ""
@export var level: int = 1
@export var strength: int = 10
@export var current_hp: int = 100
@export var max_hp: int = 100
@export var x: int = 0
@export var y: int = 10
```

### preload() vs load()

Both load a script or resource file. The difference is timing:

```gdscript
# preload() -- loaded at COMPILE TIME (when the script is first parsed)
# Fast at runtime, but the file must exist and path must be a string literal
const CharacterScript = preload("res://shared/character.gd")

# load() -- loaded at RUNTIME (when this line of code executes)
# Slower, but the path can be dynamic or conditional
var _monster_art_script = null
func _get_monster_art():
    if _monster_art_script == null:
        _monster_art_script = load("res://client/monster_art.gd")
    return _monster_art_script
```

In the client code, you can see both patterns. `CharacterScript` is preloaded because it is always needed. The art scripts are loaded lazily (only when first used) to avoid initialization issues:

```gdscript
# Always needed -- preload at compile time
const CharacterScript = preload("res://shared/character.gd")

# Loaded on first use -- avoids initialization order issues
var _monster_art_script = null
func _get_monster_art():
    if _monster_art_script == null:
        _monster_art_script = load("res://client/monster_art.gd")
    return _monster_art_script

var _trader_art_script = null
func _get_trader_art():
    if _trader_art_script == null:
        _trader_art_script = load("res://client/trader_art.gd")
    return _trader_art_script
```

### The res:// Path Prefix

`res://` means "relative to the project root." When you see `res://shared/character.gd`, that means `<project_root>/shared/character.gd`. This is how Godot references files within the project.

There is also `user://` which points to the user data directory (different per OS). It is used for saving settings and save files:

```gdscript
const CONNECTION_CONFIG_PATH = "user://connection_settings.json"
const KEYBIND_CONFIG_PATH = "user://keybinds.json"
```

---

## 9. RichTextLabel and BBCode -- Our Main Display

Phantom Badlands is a **text-based** game. There are no sprites, no 3D models, no tile maps. Everything the player sees -- combat, inventory, the map, NPCs, ASCII art -- is rendered as styled text in a `RichTextLabel` using BBCode.

### What is BBCode?

BBCode (Bulletin Board Code) is a lightweight markup language for formatting text. If you have used forum software, you have probably seen it. In Godot's RichTextLabel, BBCode lets you add colors, bold text, sizes, alignment, and clickable links.

### Common BBCode Tags Used in This Project

```
[color=#FF0000]Red text (damage, enemies, warnings)[/color]
[color=#00FF00]Green text (healing, success, nature)[/color]
[color=#FFD700]Gold text (currency, titles, headers)[/color]
[color=#00BFFF]Blue text (mana, water, info)[/color]
[color=#A335EE]Purple text (rare items, magical beings)[/color]
[color=#808080]Gray text (disabled options, flavor text)[/color]

[b]Bold text (emphasis)[/b]
[center]Centered text (headers, ASCII art)[/center]
[font_size=14]Custom font size[/font_size]
[font_size=20]Larger text for headers[/font_size]

[url=action_name]Clickable link text[/url]
```

### How Display Functions Work

The core display pattern in Phantom Badlands is simple:

```gdscript
# Write a line of text to the game output
func display_game(text: String):
    if game_output:
        game_output.append_text(text + "\n")
```

This function is called hundreds of times throughout the codebase. Every time the game needs to show something to the player, it calls `display_game()` with BBCode-formatted text:

```gdscript
# Welcome message with gold color
display_game("[color=#FFD700]Welcome to Phantom Badlands![/color]")

# Combat damage in red
display_game("[color=#FF0000]The Orc hits you for 15 damage![/color]")

# Healing in green
display_game("[color=#00FF00]You drink a healing potion. +50 HP![/color]")

# Item found with rarity color
display_game("You found: [color=#A335EE]Enchanted Sword of Fire[/color]")

# A divider line in gray
display_game("[color=#808080]────────────────────────────────[/color]")
```

### The Clear-Then-Rebuild Pattern

When the game needs to show a new "screen" (like opening inventory, or viewing a merchant), it clears the output and rebuilds it:

```gdscript
func display_inventory():
    game_output.clear()   # Wipe everything

    display_game("[color=#FFD700]===== INVENTORY =====[/color]")
    display_game("")

    # Loop through items and display each one
    for i in range(items.size()):
        var item = items[i]
        display_game("[%d] %s" % [i + 1, item.name])

    display_game("")
    display_game("[color=#808080]Select an item (1-9) or press Space to close[/color]")
```

This pattern is used everywhere:
- `display_inventory()` -- shows the player's items
- `display_companions()` -- shows the player's companions
- `display_settings_menu()` -- shows game settings
- `display_market_browse()` -- shows market listings
- And dozens more

### The Clearing Problem

Because this project clears and rebuilds text frequently, there is a critical design challenge: when the server sends a message that triggers a UI refresh (like a `character_update`), it can accidentally wipe out text the player was reading. This is documented extensively in the project guidelines (see the CLAUDE.md section on "Player-Visible Output Rule"). If you add a new feature that displays text, you must protect it from being cleared by incoming messages.

---

## 10. Input Handling in Detail

Phantom Badlands handles input in two complementary ways: **polling** in `_process()` and **events** in `_input()`.

### Polling with Input.is_physical_key_pressed()

Polling means checking the state of a key every frame. This is done in `_process()`:

```gdscript
# Check if the Space key is currently held down
if Input.is_physical_key_pressed(KEY_SPACE):
    # Do something
```

This returns `true` every frame the key is held. To ensure an action only fires once per press, the project uses a **meta flag** pattern:

```gdscript
# In _process():
if Input.is_physical_key_pressed(KEY_SPACE):
    if not get_meta("hotkey_0_pressed", false):  # First frame of press?
        set_meta("hotkey_0_pressed", true)        # Mark as handled
        trigger_action(0)                          # Fire the action ONCE
else:
    set_meta("hotkey_0_pressed", false)           # Key released, reset flag
```

Here is how this works frame by frame:

```
Frame 1: Space pressed   -> meta is false -> set true, FIRE ACTION
Frame 2: Space still held -> meta is true  -> skip (already fired)
Frame 3: Space still held -> meta is true  -> skip
Frame 4: Space released   -> reset meta to false
Frame 5: Space pressed    -> meta is false -> set true, FIRE ACTION again
```

This is how the action bar works. All 10 hotkeys (Space, Q, W, E, R, 1, 2, 3, 4, 5) are polled every frame with this pattern.

### Events with _input()

Event-based input uses `_input(event)` which is called once per input event:

```gdscript
func _input(event):
    if event is InputEventKey and event.pressed and not event.echo:
        # This runs ONCE when a key is first pressed
        # event.keycode tells you which key
        # event.echo is true for auto-repeat (holding a key)

        if event.keycode == KEY_UP:
            navigate_settings_up()
        elif event.keycode == KEY_DOWN:
            navigate_settings_down()
```

**Key properties of InputEventKey:**
- `event.pressed` -- `true` for press, `false` for release
- `event.echo` -- `true` for auto-repeat (key held down)
- `event.keycode` -- which key (KEY_SPACE, KEY_Q, KEY_1, etc.)
- `event.physical_keycode` -- the physical key regardless of keyboard layout

### Why Both Methods Are Used

The project uses both approaches because they solve different problems:

**Polling in _process() is used for the action bar** because:
- The action bar runs every frame regardless of what else is happening
- It needs to check all 10 keys in a consistent loop
- The meta flag pattern gives precise control over press/release behavior

**Events in _input() are used for mode-specific keys** because:
- Settings mode needs arrow key navigation that fires once per press
- Building mode needs direction keys
- Keybind rebinding needs to capture the exact key that was pressed
- These handlers need to run BEFORE `_process()` to prevent the action bar from also firing

### Key Constants

Godot uses constants for key identification:

```gdscript
KEY_SPACE   # Spacebar
KEY_Q       # Q key
KEY_W       # W key
KEY_E       # E key
KEY_R       # R key
KEY_1       # Number row 1
KEY_2       # Number row 2
# ... through KEY_9
KEY_KP_1    # Numpad 1
KEY_KP_2    # Numpad 2
# ... through KEY_KP_9
KEY_UP      # Arrow up
KEY_DOWN    # Arrow down
KEY_ESCAPE  # Escape key
```

The project's keybind system maps these to actions:

```gdscript
var default_keybinds = {
    "action_0": KEY_SPACE,   # Primary action
    "action_1": KEY_Q,       # Action slot 2
    "action_2": KEY_W,       # Action slot 3
    "action_3": KEY_E,       # Action slot 4
    "action_4": KEY_R,       # Action slot 5 (contextual)
    "action_5": KEY_1,       # Action slot 6
    "action_6": KEY_2,       # Action slot 7
    "action_7": KEY_3,       # Action slot 8
    "action_8": KEY_4,       # Action slot 9
    "action_9": KEY_5,       # Action slot 10
    "item_1": KEY_1,         # Item selection 1
    "item_2": KEY_2,         # Item selection 2
    # ... etc
    "move_8": KEY_KP_8,      # Move North
    "move_2": KEY_KP_2,      # Move South
    # ... etc
}
```

Notice that keys 1-5 serve double duty: they are both action bar hotkeys AND item selection keys. The code carefully manages which system gets priority based on the current game state. This is documented in the project's pitfall guide (see CLAUDE.md, Pitfall #10).

---

## 11. Networking in Godot (TCP)

Phantom Badlands uses **raw TCP sockets** for networking. This is a lower-level approach than Godot's built-in multiplayer system, giving full control over the protocol.

### The Basics

The client and server communicate over TCP on port 9080. Messages are JSON objects, one per line (newline-delimited JSON).

### Client Side (StreamPeerTCP)

The client uses `StreamPeerTCP` to connect to the server:

```gdscript
# Create the TCP connection object (done once, at variable declaration time)
var connection = StreamPeerTCP.new()

# Connect to the server
connection.connect_to_host("localhost", 9080)
```

**Sending a message to the server:**

```gdscript
# Create a JSON message and send it
var message = {"type": "move", "direction": "north"}
var json_string = JSON.stringify(message) + "\n"    # Newline delimiter
connection.put_data(json_string.to_utf8_buffer())   # Convert string to bytes, send
```

**Receiving messages from the server (in _process()):**

```gdscript
func _process(delta):
    connection.poll()    # Check for new data

    if connection.get_status() == StreamPeerTCP.STATUS_CONNECTED:
        if connection.get_available_bytes() > 0:
            # Read all available bytes
            var data = connection.get_data(connection.get_available_bytes())
            var text = data[1].get_string_from_utf8()

            # Split by newlines (each line is one JSON message)
            var lines = text.split("\n")
            for line in lines:
                if line.strip_edges() != "":
                    var parsed = JSON.parse_string(line)
                    if parsed != null:
                        handle_server_message(parsed)
```

**Handling a parsed message:**

```gdscript
func handle_server_message(msg: Dictionary):
    match msg.get("type", ""):
        "text":
            # Server sent a text message to display
            display_game(msg.get("text", ""))
        "character_update":
            # Server sent updated character data
            update_character_display(msg)
        "combat_update":
            # Server sent combat state
            process_combat_update(msg)
        "location":
            # Server sent map/location data
            update_map(msg)
        # ... many more message types
```

### Server Side (TCPServer)

The server uses `TCPServer` to listen for connections:

```gdscript
var server = TCPServer.new()

func _ready():
    # Start listening on port 9080
    server.listen(9080)
    print("Server listening on port %d" % 9080)

func _process(delta):
    # Check for new connections
    if server.is_connection_available():
        var peer = server.take_connection()
        # Store the connection, assign a peer ID, etc.

    # Check each connected client for incoming messages
    for peer_id in connected_peers:
        var peer_connection = connected_peers[peer_id]
        if peer_connection.get_available_bytes() > 0:
            # Read and process the message
            # ...
```

### Message Format

All messages are JSON dictionaries with a `"type"` field that identifies the message:

```json
// Client -> Server (player wants to move north)
{"type": "move", "direction": "north"}

// Client -> Server (player attacks in combat)
{"type": "combat_action", "action": "attack"}

// Server -> Client (display text to the player)
{"type": "text", "text": "[color=#00FF00]You found 50 gold![/color]"}

// Server -> Client (update character stats)
{"type": "character_update", "hp": 85, "max_hp": 100, "level": 5}
```

This simple protocol (newline-delimited JSON over TCP) makes it easy to add new message types. To add a new feature, you define a new message type, add a handler on the receiving side, and you are done.

---

## 12. The project.godot File

The `project.godot` file is the configuration file for the entire project. It lives in the project root and contains settings that Godot needs to run the game.

### What It Contains

Here is our project's `project.godot`:

```ini
config_version=5

[application]
config/name="PhantomBadlands"
run/main_scene="uid://dbwq54oox3iif"   # Points to client/client.tscn
config/features=PackedStringArray("4.6", "GL Compatibility")
config/icon="res://icon.svg"

[display]
window/size/viewport_width=1280
window/size/viewport_height=720

[editor_plugins]
enabled=PackedStringArray("res://addons/godot-sqlite/plugin.cfg")

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
environment/defaults/default_clear_color=Color(0.08, 0.08, 0.1, 1)
```

### Key Settings Explained

**`config/name`** -- The project name. Shows up in the Godot editor's project list and can be used at runtime.

**`run/main_scene`** -- Which scene to load when the game starts. This is the client scene. When you run the server, you override this with a command-line argument.

**`window/size/viewport_width` and `viewport_height`** -- The window size: 1280x720 pixels.

**`renderer/rendering_method`** -- The rendering backend. "GL Compatibility" is the most widely compatible (works on older hardware). For a text-based game, rendering performance is not a concern.

**`default_clear_color`** -- The background color when nothing is drawn. Our dark blue-gray: `Color(0.08, 0.08, 0.1, 1)`.

**`editor_plugins`** -- Plugins enabled in the editor. We use `godot-sqlite` for database operations on the server.

### Changing Settings

You can edit `project.godot` in a text editor, but it is safer to change settings through the Godot editor (Project > Project Settings). The editor validates values and presents them in a GUI.

---

## 13. Running and Testing

### Running from the Command Line

Phantom Badlands requires running a server and a client separately. The Godot executable can run specific scenes with the `--path` and scene arguments.

**Start the server:**

```bash
"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" \
    --path "C:\Users\Dexto\Documents\phantasia-revival" \
    server/server.tscn
```

**Start the client:**

```bash
"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" \
    --path "C:\Users\Dexto\Documents\phantasia-revival" \
    client/client.tscn
```

**Typical workflow:** Start the server first (it takes a moment to initialize the world and database), wait a few seconds, then start the client. The client will connect to `localhost:9080` by default.

### Validating Scripts Without Running

You can check a script for syntax errors without launching the game:

```bash
"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" \
    --headless \
    --path "C:\Users\Dexto\Documents\phantasia-revival" \
    --check-only \
    --script "res://shared/character.gd"
```

The `--headless` flag runs without opening a window. The `--check-only` flag validates the script and exits. This is useful for catching errors quickly after making changes.

### Reading Console Output

When running from the command line, Godot prints errors and `print()` statements to the terminal. You can redirect output to a file:

```bash
"path/to/godot.exe" --path "project/path" server/server.tscn 2>&1 | tee server_log.txt
```

Common things you will see in the console:
- `print()` statements from your code (debugging output)
- `SCRIPT ERROR:` messages when something goes wrong at runtime
- `Parser Error:` messages when a script has syntax errors
- Resource loading messages

### Using print() for Debugging

The simplest debugging tool in GDScript:

```gdscript
# Print a simple message
print("Player connected!")

# Print a variable
print("Player HP: ", current_hp)

# Print a dictionary
print("Message received: ", message)

# Formatted string
print("Player %s moved to (%d, %d)" % [player_name, x, y])
```

Output appears in the terminal where you launched Godot (or in the Godot editor's Output panel if running from the editor).

---

## 14. Common Godot Errors and What They Mean

When something goes wrong, Godot prints error messages. Here is how to read them and what the common ones mean.

### Error Message Format

```
SCRIPT ERROR: Invalid call. Nonexistent function 'clear' in base 'Nil'.
  at: display_inventory (res://client/client.gd:5230)
```

This tells you:
- **What happened:** Invalid call -- you tried to call a function that does not exist on that object
- **The details:** The function `clear` does not exist on `Nil` (meaning the object is null)
- **Where:** In the function `display_inventory`, in the file `client.gd`, at line 5230

### "Identifier not declared in the current scope"

```
Parser Error: Identifier "game_outpt" not declared in the current scope.
```

**What it means:** You used a variable name that does not exist. This is almost always a typo.

**How to fix:** Check your spelling. In this example, `game_outpt` should be `game_output`. GDScript is case-sensitive, so `gameOutput` and `game_output` are different names.

### "Invalid call. Nonexistent function"

```
SCRIPT ERROR: Invalid call. Nonexistent function 'pop_meta' in base 'RichTextLabel'.
```

**What it means:** You called a method that does not exist on that node type. This can happen when:
- You misspelled the method name
- You are using documentation for a different Godot version (API changes between versions)
- The variable points to a different node type than you expected

**How to fix:** Check the Godot documentation for the correct method name for your Godot version (4.6). In this example, the correct method is `pop()`, not `pop_meta()`.

### "Node not found"

```
SCRIPT ERROR: Node not found: "RootContainer/TopSection/GameOuput" (relative to "/root/ClientScene").
```

**What it means:** The `$` path does not match any node in the scene tree. Common causes:
- Typo in the path (notice `GameOuput` vs `GameOutput`)
- The node was renamed in the scene editor but not in the script
- The node has not been added to the tree yet

**How to fix:** Verify the exact node name in the `.tscn` file or scene editor. Every part of the path must match exactly, including capitalization.

### "Invalid get index on base: 'Nil'"

```
SCRIPT ERROR: Invalid get index 'text' (on base: 'Nil').
  at: handle_input_submitted (res://client/client.gd:15840)
```

**What it means:** You tried to access a property on a `null` value. The variable exists but contains nothing.

**Common causes:**
- An `@onready` variable pointing to a node path that does not exist (the variable is null)
- A function returned null instead of an expected object
- A dictionary lookup returned null

**How to fix:** Check why the variable is null. Add a null check before using it:

```gdscript
# Defensive coding:
if game_output != null:
    game_output.clear()
else:
    print("ERROR: game_output is null!")
```

### "Constant has the same name as a previously declared constant"

```
Parser Error: Constant "MAX_ITEMS" has the same name as a previously declared constant.
```

**What it means:** You declared a constant that already exists somewhere in the same file.

**How to fix:** Search the file for the constant name before adding a new one. In a large file like `client.gd` (21,000+ lines), it is easy to accidentally redeclare something. Use your editor's search function.

### "Cannot convert from TYPE_A to TYPE_B"

```
SCRIPT ERROR: Cannot convert from 'float' to 'int'.
```

**What it means:** You passed a value of one type where a different type was expected. GDScript is dynamically typed but still enforces type compatibility in some contexts.

**How to fix:** Use explicit conversion:

```gdscript
var tier = int(item.get("tier", 0))     # Convert float to int
var name = str(player_id)                # Convert int to string
var ratio = float(current) / float(max)  # Convert ints to float for division
```

### Tips for Debugging

1. **Read the error message carefully.** It always tells you the file name and line number.
2. **Use print() liberally.** Print variables before the line that crashes to see their values.
3. **Check for null.** The most common crash is accessing a property on a null object.
4. **Check variable names.** Typos are the most common parser error.
5. **Check Godot version.** Some methods changed between Godot 4.x versions. The project uses 4.6.

---

## Summary

Here is a quick reference of everything covered:

| Concept | What It Is | Key Example |
|---------|-----------|-------------|
| **Node** | Building block of everything | `RichTextLabel`, `Button`, `VBoxContainer` |
| **Scene** | Saved tree of nodes (.tscn) | `client/client.tscn` |
| **Script** | GDScript file attached to a node | `client/client.gd extends Control` |
| **Scene Tree** | Runtime hierarchy of all nodes | ClientScene > RootContainer > TopSection > ... |
| **_ready()** | Called once at startup | Connect signals, initialize state |
| **_process(delta)** | Called every frame (60/s) | Poll network, check input, update timers |
| **_input(event)** | Called on input events | Handle specific key presses |
| **Signal** | Event communication system | `button.pressed.connect(handler)` |
| **@onready** | Delayed variable assignment | `@onready var x = $Path/To/Node` |
| **Resource** | Pure data container | `Character extends Resource` |
| **BBCode** | Text formatting in RichTextLabel | `[color=#FF0000]Red[/color]` |
| **StreamPeerTCP** | TCP client connection | Newline-delimited JSON messages |
| **TCPServer** | TCP server listener | Accepts client connections on port 9080 |

With these fundamentals, you can now read and understand the Phantom Badlands codebase. The next step is to learn GDScript syntax and patterns in detail -- see the GDScript guide for that.
