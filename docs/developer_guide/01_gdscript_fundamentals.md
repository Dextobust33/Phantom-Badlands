# GDScript Fundamentals for Phantom Badlands

Welcome to GDScript! This guide assumes you understand general programming concepts (variables, loops, functions, OOP basics like classes and inheritance) but are brand new to Godot and GDScript. We will start from the very basics and build up, using standalone examples first, then real examples from the Phantom Badlands codebase so you can see how these concepts apply in practice.

---

## 1. What is GDScript?

GDScript is Godot Engine's built-in scripting language. If you have used Python, GDScript will feel immediately familiar -- it uses indentation for blocks, has similar syntax for loops and conditionals, and reads almost like pseudocode. But GDScript is not Python; it is a purpose-built language designed specifically for game development inside Godot.

### Key Characteristics

- **Indentation-based blocks** -- like Python, whitespace matters. Use tabs (Godot's default) or spaces consistently.
- **Dynamically typed by default** -- you can declare `var x = 5` without specifying a type.
- **Optional static typing** -- you can add type hints like `var x: int = 5` for better error checking and editor autocomplete.
- **Built for Godot's node system** -- every script typically attaches to a node in the scene tree, extending that node's behavior.
- **No semicolons** -- lines end when the line ends. No `;` required.
- **No curly braces** -- blocks are defined by indentation (one tab level per block).

### How GDScript Differs from Other Languages

| Feature | GDScript | Python | C# / Java |
|---|---|---|---|
| Typing | Dynamic + optional hints | Dynamic + optional hints | Static (required) |
| Blocks | Indentation (tabs) | Indentation (spaces/tabs) | Curly braces `{}` |
| Entry point | `_ready()`, `_process()` | `if __name__ == "__main__":` | `Main()` / `static void main()` |
| Inheritance | `extends Node` | `class Foo(Bar):` | `class Foo : Bar` / `class Foo extends Bar` |
| Access modifiers | None (everything public) | Convention only (`_` prefix) | `public`, `private`, `protected` |
| Null | `null` | `None` | `null` / `null` |
| Boolean | `true` / `false` | `True` / `False` | `true` / `false` |
| Logical operators | `and`, `or`, `not` | `and`, `or`, `not` | `&&`, `\|\|`, `!` |
| String format | `"Hello %s" % name` | `f"Hello {name}"` | `$"Hello {name}"` / `String.format()` |

### A Minimal GDScript File

```gdscript
# Every script extends something. This one extends Node.
extends Node

# This runs once when the node enters the scene tree.
func _ready():
    print("Hello, Phantom Badlands!")
```

That is a complete, valid GDScript file. It extends `Node` (the most basic building block in Godot), and when the node loads into the game, `_ready()` fires and prints a message.

---

## 2. Variables and Data Types

### Declaring Variables with `var`

The `var` keyword declares a variable. You can optionally add a type hint after a colon.

```gdscript
# No type hint -- GDScript infers the type
var player_name = "Adventurer"
var health = 100
var speed = 3.5
var is_alive = true

# With type hints -- recommended for clarity and editor help
var player_name: String = "Adventurer"
var health: int = 100
var speed: float = 3.5
var is_alive: bool = true
```

Type hints do not change runtime behavior in most cases, but they give you better autocompletion in the Godot editor and catch type errors earlier.

### Basic Types

| Type | Description | Example |
|---|---|---|
| `int` | Whole numbers | `42`, `-7`, `0` |
| `float` | Decimal numbers | `3.14`, `-0.5`, `1.0` |
| `String` | Text | `"Hello"`, `'World'` |
| `bool` | True or false | `true`, `false` |
| `null` | Absence of value | `null` |
| `Vector2` | 2D coordinates (float) | `Vector2(1.5, 3.0)` |
| `Vector2i` | 2D coordinates (integer) | `Vector2i(10, 20)` |
| `Array` | Ordered list | `[1, 2, 3]` |
| `Dictionary` | Key-value map | `{"name": "Orc", "hp": 50}` |

### Constants with `const`

Constants are values that never change. By convention, they use `UPPER_SNAKE_CASE`.

```gdscript
const MAX_SPEED = 200
const GRAVITY = 9.8
const GAME_TITLE = "Phantom Badlands"
```

You **cannot** reassign a constant after declaration. Attempting `MAX_SPEED = 300` will produce a compile error.

### Static Variables with `static var`

A `static var` belongs to the class itself, not to any individual instance. All instances share the same value. (We will cover this more in the Scope section.)

```gdscript
static var total_monsters_spawned: int = 0
```

### `null` -- The Absence of Value

`null` means "no value" or "nothing." It is similar to `None` in Python or `null` in C#/Java.

```gdscript
var target = null  # No target selected yet

if target == null:
    print("No target!")
```

### Real Project Examples

From `shared/character.gd` -- the Character class that represents every player in the game:

```gdscript
# Basic character info -- these are all class-level variables with type hints
@export var character_id: int = 0        # Unique ID for this character
@export var name: String = ""            # Player-chosen name
@export var race: String = "Human"       # Human, Elf, Dwarf, or Ogre
@export var class_type: String = ""      # Fighter, Wizard, Thief, etc.
@export var level: int = 1               # Current level (starts at 1)
@export var experience: int = 0          # XP toward next level

# Primary stats -- integers representing the character's attributes
@export var strength: int = 10
@export var constitution: int = 10
@export var dexterity: int = 10
@export var intelligence: int = 10
@export var wisdom: int = 10
@export var wits: int = 10

# Current resource pools
@export var current_hp: int = 100
@export var max_hp: int = 100
@export var current_mana: int = 50
@export var max_mana: int = 50
```

And constants used for game balance:

```gdscript
# From shared/character.gd
const MAX_INVENTORY_SIZE = 40    # Maximum items a player can carry
const MAX_STACK_SIZE = 99        # Maximum stack for stackable items
const MAX_ABILITY_SLOTS = 6      # How many abilities can be equipped
const MAX_ACTIVE_QUESTS = 5      # Maximum simultaneous quests

# From shared/world_system.gd
const WORLD_MIN_X = -2000        # Left edge of the world
const WORLD_MAX_X = 2000         # Right edge of the world
const DEFAULT_VISION_RADIUS = 11 # How far the player can see
```

Notice the pattern: `@export var` for data that should be saved/loaded, `const` for values that are fixed at compile time and never change.

---

## 3. Scope and Visibility

This section is the most important in the guide. Scope determines **where a variable can be accessed**. If you have been fuzzy on this concept, read this section carefully -- it will click.

### The Three Levels of Scope in GDScript

Think of scope as nested boxes. A variable declared in an outer box is visible to everything inside it, but a variable declared in an inner box is invisible to everything outside.

```
+-------------------------------------------------------+
|  CLASS SCOPE (the whole script file)                   |
|                                                        |
|  var health: int = 100    <-- visible everywhere       |
|  var in_combat: bool = false                           |
|                                                        |
|  +---------------------------------------------------+ |
|  |  FUNCTION SCOPE (inside a specific function)      | |
|  |                                                   | |
|  |  func take_damage(amount: int):                   | |
|  |      var reduced = amount - 5                     | |
|  |      health -= reduced  # CAN access 'health'    | |
|  |                                                   | |
|  |  +-----------------------------------------------+| |
|  |  |  BLOCK SCOPE (inside if/for/while)            || |
|  |  |                                               || |
|  |  |  if reduced > 0:                              || |
|  |  |      var message = "Ouch!"                    || |
|  |  |      print(message)  # 'message' exists here  || |
|  |  |                                               || |
|  |  +-----------------------------------------------+| |
|  |  # 'message' does NOT exist here!                 | |
|  |  # print(message)  <-- ERROR                      | |
|  +---------------------------------------------------+ |
|                                                        |
|  func heal():                                          |
|      # 'reduced' does NOT exist here -- it was local   |
|      # to take_damage()                                |
|      health += 20  # CAN access 'health' (class-level) |
|                                                        |
+-------------------------------------------------------+
```

Let us break this down with concrete rules.

### Rule 1: Class-Level Variables -- Accessible Everywhere in the Script

Variables declared at the top of a script (outside any function) are **class-level** (also called **instance variables** or **member variables**). Every function in the script can read and modify them.

```gdscript
extends Node

# Class-level variables -- accessible from ANY function in this file
var player_name: String = "Hero"
var health: int = 100
var is_poisoned: bool = false

func take_damage(amount: int):
    health -= amount           # Can access 'health' -- it's class-level
    if health <= 0:
        print(player_name + " has fallen!")  # Can access 'player_name' too

func cure_poison():
    is_poisoned = false        # Can access 'is_poisoned'
    print(player_name + " is cured!")  # Can access 'player_name'
```

### Rule 2: Local Variables -- Only Exist Inside Their Function

Variables declared inside a function (with `var`) only exist while that function is running. When the function ends, the variable is gone.

```gdscript
func calculate_damage() -> int:
    var base_damage = 10        # Local to this function
    var crit_bonus = 5          # Local to this function
    var total = base_damage + crit_bonus
    return total

func show_damage():
    # print(base_damage)  <-- ERROR! 'base_damage' doesn't exist here
    # It was local to calculate_damage()
    var result = calculate_damage()  # But we can call the function
    print(result)
```

### Rule 3: Function Parameters Are Local Too

Parameters passed to a function are local variables that exist only inside that function.

```gdscript
func take_damage(amount: int):
    # 'amount' is a local variable -- it only exists inside take_damage()
    health -= amount

func heal(amount: int):
    # This is a DIFFERENT 'amount' -- also local, only inside heal()
    health += amount

# Outside both functions, 'amount' does not exist
```

### Rule 4: Block Scope (if/for/while) in GDScript

Variables declared inside an `if`, `for`, or `while` block are scoped to that block. This is a difference from Python, where variables "leak" out of blocks.

```gdscript
func check_health():
    if health < 50:
        var warning = "Low HP!"  # Only exists inside this if-block
        print(warning)

    # print(warning)  <-- ERROR in GDScript! 'warning' is out of scope

    for i in range(3):
        var message = "Step %d" % i  # Only exists inside this for-loop
        print(message)

    # print(message)  <-- ERROR! 'message' is out of scope
```

If you need a variable after the block, declare it before the block:

```gdscript
func check_health():
    var warning = ""  # Declared at function scope, accessible everywhere in this func

    if health < 50:
        warning = "Low HP!"  # Assigning to the existing variable (not creating a new one)

    print(warning)  # Works! 'warning' was declared at function scope
```

### Rule 5: No Public/Private Keywords -- Everything is Public

GDScript has **no access modifiers** like `public`, `private`, or `protected`. Every variable and function in a script can be accessed from outside.

Instead, GDScript uses a **naming convention**: a leading underscore `_` means "this is intended to be private -- do not call it from outside this class."

```gdscript
extends Node

# "Public" -- intended to be used from outside
var health: int = 100
var player_name: String = ""

func take_damage(amount: int):
    var reduced = _calculate_reduction(amount)  # Calls the "private" helper
    health -= reduced

# "Private" by convention -- the underscore signals "internal use only"
# Other scripts CAN still call this, but they SHOULD NOT.
func _calculate_reduction(amount: int) -> int:
    return max(0, amount - 5)
```

This convention is heavily used in Phantom Badlands. For example, in `shared/character.gd`:

```gdscript
# Public: other scripts are expected to call this
func calculate_derived_stats():
    var primary_stat_bonus = _get_primary_stat_for_hp()  # calls private helper
    max_hp = 50 + (constitution * 5) + primary_stat_bonus

# Private: only called from within this class
func _get_primary_stat_for_hp() -> int:
    match class_type:
        "Fighter", "Barbarian", "Paladin":
            return strength
        "Wizard", "Sorcerer", "Sage":
            return int(intelligence * 0.5)
        "Thief", "Ranger", "Ninja":
            return int(wits * 0.5)
        _:
            return strength
```

### Rule 6: `@export` -- Making Variables Visible in the Godot Inspector

The `@export` annotation makes a variable editable in Godot's Inspector panel (a visual properties editor in the Godot IDE). It does not change how the variable works in code -- it just adds editor visibility.

```gdscript
# Without @export -- only accessible through code
var secret_value: int = 42

# With @export -- shows up in the Godot editor's Inspector panel
# You can tweak this value visually without changing code
@export var strength: int = 10
@export var player_name: String = "Hero"
@export var is_boss: bool = false
```

In Phantom Badlands, `@export` is used heavily in `shared/character.gd` because the Character class extends `Resource`, and exported properties get automatically serialized (saved/loaded):

```gdscript
class_name Character
extends Resource

# All of these are exported so they can be serialized to/from save files
@export var character_id: int = 0
@export var name: String = ""
@export var level: int = 1
@export var strength: int = 10
@export var inventory: Array = []
@export var in_combat: bool = false
@export var poison_active: bool = false
```

### Rule 7: `@onready` -- Delayed Initialization

`@onready` delays a variable's initialization until the node enters the scene tree (when `_ready()` would run). This is important because child nodes might not exist yet when the script first loads.

```gdscript
extends Node

# WITHOUT @onready -- might fail if the child node isn't ready yet
# var label = $UI/HealthLabel  # Could crash!

# WITH @onready -- safely waits until the scene tree is built
@onready var label = $UI/HealthLabel      # '$' is shorthand for get_node()
@onready var timer = $CooldownTimer
@onready var sprite = $PlayerSprite
```

The `$` symbol is Godot shorthand for `get_node()`. So `$UI/HealthLabel` means "get the child node at path UI/HealthLabel." The `@onready` ensures this lookup happens after all nodes are loaded, not at parse time.

### Rule 8: Static Variables and Functions

`static` members belong to the **class** itself, not to any individual instance. You do not need to create an instance to use them.

```gdscript
# In shared/character.gd
class_name Character
extends Resource

# Static function -- called on the CLASS, not on an instance
static func get_themed_item_name(item_name: String, slot: String, class_type: String) -> String:
    # Can access class constants (like CLASS_EQUIPMENT_THEMES)
    # But CANNOT access instance variables (like self.strength)
    if not CLASS_EQUIPMENT_THEMES.has(class_type):
        return item_name
    # ... transform the name ...
    return result
```

Calling a static function:

```gdscript
# You call it on the CLASS NAME, not on an instance
var themed = Character.get_themed_item_name("Iron Weapon", "weapon", "Ranger")
# Result: "Iron Bow" (Rangers use bows)
```

Static functions **cannot** access instance variables (like `self.health`) because there is no instance -- they belong to the class blueprint, not to any specific character.

### Real Project Example: Scope in Action

Here is `from_dict()` from `shared/character.gd`, showing how class-level and local variables interact:

```gdscript
# Class-level variables (declared at the top of character.gd)
@export var character_id: int = 0
@export var name: String = ""
@export var level: int = 1
@export var strength: int = 10

func from_dict(data: Dictionary):
    # 'data' is a local parameter -- only exists inside this function
    character_id = data.get("id", 0)      # Writes to class-level 'character_id'
    name = data.get("name", "")           # Writes to class-level 'name'
    level = data.get("level", 1)          # Writes to class-level 'level'

    # 'stats' is a LOCAL variable -- only exists inside from_dict()
    var stats = data.get("stats", {})

    # Writing local dict values into class-level variables
    strength = stats.get("strength", 10)  # 'strength' is class-level
```

### Summary Table: Scope Rules

| Where Declared | Visible To | Lifetime | Example |
|---|---|---|---|
| Top of script (class-level) | All functions in the script | As long as the instance exists | `var health: int = 100` |
| Inside a function (local) | Only that function | Until the function returns | `var damage = 10` |
| Function parameter | Only that function | Until the function returns | `func attack(target):` |
| Inside if/for/while block | Only that block | Until the block ends | `if x: var y = 1` |
| `static var` | The class and all instances | As long as the class is loaded | `static var count = 0` |
| `const` | The class and all instances | Forever (compile-time constant) | `const MAX_HP = 999` |

---

## 4. Collections: Arrays and Dictionaries

Arrays and Dictionaries are the workhorses of GDScript. In Phantom Badlands, virtually all game data lives in Arrays of Dictionaries.

### Arrays

An Array is an ordered list of values. It can hold any mix of types (though in practice, you usually store one type).

```gdscript
# Creating arrays
var empty_list = []
var numbers = [1, 2, 3, 4, 5]
var names = ["Fighter", "Wizard", "Thief"]
var mixed = [42, "hello", true, null]  # Legal but uncommon
```

**Common Array operations:**

```gdscript
var inventory = ["Sword", "Shield", "Potion"]

# Access by index (0-based)
print(inventory[0])       # "Sword"
print(inventory[2])       # "Potion"
print(inventory[-1])      # "Potion" (negative index = from the end)

# Size
print(inventory.size())   # 3
print(inventory.is_empty()) # false

# Add items
inventory.append("Helmet")       # Adds to the end: ["Sword", "Shield", "Potion", "Helmet"]
inventory.insert(1, "Ring")      # Inserts at index 1: ["Sword", "Ring", "Shield", ...]

# Remove items
inventory.erase("Shield")        # Removes first occurrence of "Shield"
inventory.remove_at(0)           # Removes item at index 0

# Search
print(inventory.has("Sword"))    # true or false
print(inventory.find("Potion"))  # Returns index, or -1 if not found

# Random selection
var random_item = inventory.pick_random()  # Returns a random element

# Iteration
for item in inventory:
    print(item)

# Index-based iteration
for i in range(inventory.size()):
    print("%d: %s" % [i, inventory[i]])
```

**Reverse iteration (for safe removal):**

When removing items from an array while iterating, always go backwards to avoid skipping elements:

```gdscript
# From shared/character.gd -- removing expired buffs
for i in range(active_buffs.size() - 1, -1, -1):  # Counts backwards: 4, 3, 2, 1, 0
    if active_buffs[i].duration <= 0:
        active_buffs.remove_at(i)
```

### Dictionaries

A Dictionary is an unordered collection of key-value pairs. Think of it as a lookup table.

```gdscript
# Creating dictionaries
var empty_dict = {}
var player = {
    "name": "Adventurer",
    "level": 5,
    "class": "Fighter",
    "is_alive": true
}

# Access by key -- two ways
print(player["name"])     # "Adventurer"
print(player.name)        # "Adventurer" (dot syntax -- only works for string keys)

# BUT! Dot syntax and bracket syntax CRASH if the key doesn't exist:
# print(player["weapon"])   <-- ERROR: key not found
# print(player.weapon)      <-- ERROR: key not found
```

### The `.get()` Method -- CRITICAL for This Project

This is one of the most important patterns in Phantom Badlands. The `.get()` method lets you safely access dictionary values with a default fallback if the key is missing.

```gdscript
# SAFE access with .get(key, default)
var weapon = player.get("weapon", "Fists")  # Returns "Fists" if "weapon" key missing
var level = player.get("level", 1)          # Returns the actual level (5)

# UNSAFE access -- will crash if key is missing
var weapon = player["weapon"]  # CRASH if no "weapon" key!
var weapon = player.weapon     # CRASH if no "weapon" key!
```

**Why `.get()` matters so much:** In a networked game, data comes from the server as JSON. Fields might be missing (older save files, new features not yet in the data, network issues). Using `.get()` with a sensible default prevents crashes.

Real example from `shared/character.gd`:

```gdscript
func from_dict(data: Dictionary):
    # Every single field uses .get() with a default value
    # If the server doesn't send "race", we default to "Human"
    character_id = data.get("id", 0)
    name = data.get("name", "")
    race = data.get("race", "Human")
    class_type = data.get("class", "Fighter")
    level = data.get("level", 1)

    var stats = data.get("stats", {})       # Default to empty dict
    strength = stats.get("strength", 10)    # Default to 10
    wisdom = stats.get("wisdom", 10)
    # Support legacy save files that used "charisma" instead of "wits"
    wits = stats.get("wits", stats.get("charisma", 10))
```

That last line shows a powerful pattern: **nested `.get()` calls** for handling renamed fields. If `"wits"` is missing, try `"charisma"`, and if that is also missing, default to `10`.

### Other Dictionary Operations

```gdscript
var monster = {"name": "Goblin", "hp": 30, "strength": 8}

# Check if key exists
if monster.has("hp"):
    print("HP: %d" % monster["hp"])

# Add or update a key
monster["defense"] = 5        # Adds new key "defense"
monster["hp"] = 25            # Updates existing key

# Remove a key
monster.erase("defense")

# Get all keys or values
var keys = monster.keys()     # ["name", "hp", "strength"]
var values = monster.values() # ["Goblin", 25, 8]

# Iterate over a dictionary
for key in monster:
    print("%s = %s" % [key, str(monster[key])])

# Or with explicit key-value:
for key in monster.keys():
    var value = monster[key]
    print("%s: %s" % [key, str(value)])
```

### Nested Dictionaries -- A Core Pattern

Phantom Badlands uses deeply nested dictionaries for game data. Here is a simplified example:

```gdscript
# From shared/drop_tables.gd -- consumable tiers
const CONSUMABLE_TIERS = {
    1: {"name": "Minor", "healing": 25, "level_min": 1, "level_max": 10},
    2: {"name": "Lesser", "healing": 50, "level_min": 11, "level_max": 25},
    3: {"name": "Standard", "healing": 75, "level_min": 26, "level_max": 50},
}

# Accessing nested values:
var tier_data = CONSUMABLE_TIERS[2]          # Gets the tier 2 dictionary
var tier_name = CONSUMABLE_TIERS[2]["name"]  # "Lesser"
var healing = CONSUMABLE_TIERS[2]["healing"] # 50
```

### The JSON Float vs. Integer Key Problem

This is a **critical gotcha** in this project. When data travels over the network as JSON, **all numbers become floats**. But GDScript dictionary keys distinguish between `int` and `float`:

```gdscript
# This dictionary uses INTEGER keys
const TIER_DATA = {
    1: "Minor",
    2: "Lesser",
    3: "Standard"
}

# After receiving from JSON, the key is a FLOAT
var tier_from_json = 2.0  # JSON parsed this as 2.0, not 2

# This FAILS silently:
print(TIER_DATA.has(tier_from_json))   # false! int 2 != float 2.0
print(TIER_DATA.has(2))                # true

# THE FIX: Always cast to int when using JSON numbers as dict keys
var tier = int(tier_from_json)         # Converts 2.0 to 2
print(TIER_DATA.has(tier))             # true!
```

Real project pattern from `shared/drop_tables.gd`:

```gdscript
# When reading item data that came from the server (JSON):
var level = int(item.get("level", 1))    # Cast to int!
var tier_index = clampi(int(level / 15), 0, 8)  # clampi works with ints
```

**Rule of thumb:** Any number that came from JSON and will be used as a dictionary key must be wrapped in `int()`.

### Array of Dictionaries -- The Most Common Data Structure

Almost all game data in Phantom Badlands is stored as arrays of dictionaries. Inventory, quests, buffs, companions -- they all follow this pattern:

```gdscript
# Inventory is an Array where each element is a Dictionary representing an item
@export var inventory: Array = []

# Each item looks like this:
var sword = {
    "name": "Iron Sword",
    "type": "weapon_melee",
    "level": 5,
    "rarity": "uncommon",
    "affixes": {"attack_bonus": 12, "speed_bonus": 3}
}

# Add to inventory
inventory.append(sword)

# Search inventory for a specific item
for item in inventory:
    if item.get("name", "") == "Iron Sword":
        print("Found it! Level %d" % item.get("level", 0))
        break
```

---

## 5. Control Flow

### if / elif / else

```gdscript
var health = 45

if health >= 70:
    print("Healthy")
elif health >= 30:
    print("Wounded")
elif health > 0:
    print("Critical")
else:
    print("Dead")
```

GDScript uses `elif` (not `else if` or `elseif`).

**Truthy/falsy values:** In GDScript, `0`, `0.0`, `""` (empty string), `[]` (empty array), `{}` (empty dict), and `null` are all falsy. Everything else is truthy.

```gdscript
var items = []

if items:
    print("Has items")      # This does NOT print -- empty array is falsy
else:
    print("Inventory empty") # This prints

# More explicit (and preferred in this project):
if items.is_empty():
    print("Inventory empty")
```

### for Loops

GDScript has several `for` loop patterns:

```gdscript
# Range-based (like Python's range)
for i in range(5):          # 0, 1, 2, 3, 4
    print(i)

for i in range(2, 7):       # 2, 3, 4, 5, 6
    print(i)

for i in range(10, 0, -1):  # 10, 9, 8, 7, 6, 5, 4, 3, 2, 1 (counting down)
    print(i)

# Iterating over an array
var classes = ["Fighter", "Wizard", "Thief"]
for cls in classes:
    print(cls)

# Iterating over a dictionary (iterates keys)
var stats = {"strength": 14, "dexterity": 12, "intelligence": 8}
for stat_name in stats:
    print("%s: %d" % [stat_name, stats[stat_name]])

# Iterating with index using range
for i in range(classes.size()):
    print("%d. %s" % [i + 1, classes[i]])
```

Real project example -- iterating equipment slots:

```gdscript
# From shared/character.gd
@export var equipped: Dictionary = {
    "weapon": null,
    "armor": null,
    "helm": null,
    "shield": null,
    "boots": null,
    "ring": null,
    "amulet": null
}

# Iterate over all equipment slots
for slot in equipped.keys():
    var item = equipped[slot]
    if item != null:
        print("Wearing %s in %s slot" % [item.get("name", "???"), slot])
```

### while Loops

```gdscript
var count = 0
while count < 10:
    print(count)
    count += 1
```

Real project example -- leveling up (a character might gain multiple levels at once):

```gdscript
# From shared/character.gd
while experience >= experience_to_next_level:
    experience -= experience_to_next_level
    level += 1
    experience_to_next_level = _calculate_xp_for_level(level)
    _apply_level_up_stats()
```

### match Statements (Switch/Case)

`match` is GDScript's equivalent of `switch/case`. It is heavily used in this project for message routing and class-based logic.

```gdscript
# Basic match
var command = "attack"

match command:
    "attack":
        print("You swing your weapon!")
    "flee":
        print("You run away!")
    "heal":
        print("You drink a potion!")
    _:                       # The underscore _ is the "default" case
        print("Unknown command: " + command)
```

**Important:** Unlike C# or Java, GDScript `match` does **not** fall through. Each branch is independent -- no `break` statement needed.

Real project example -- determining HP bonus based on class:

```gdscript
# From shared/character.gd
func _get_primary_stat_for_hp() -> int:
    match class_type:
        "Fighter", "Barbarian", "Paladin":    # Multiple values in one branch
            return strength
        "Wizard", "Sorcerer", "Sage":
            return int(intelligence * 0.5)
        "Thief", "Ranger", "Ninja":
            return int(wits * 0.5)
        _:
            return strength  # Default fallback
```

Real project example -- message routing on the server. The server receives messages from clients and dispatches them using `match`:

```gdscript
# Simplified from server/server.gd
func handle_message(peer_id: int, msg_type: String, data: Dictionary):
    match msg_type:
        "move":
            handle_move(peer_id, data)
        "attack":
            handle_attack(peer_id, data)
        "chat":
            handle_chat(peer_id, data)
        "use_item":
            handle_use_item(peer_id, data)
        "quest_accept":
            handle_quest_accept(peer_id, data)
        _:
            print("Unknown message type: " + msg_type)
```

This pattern -- receiving a string and routing to a handler function -- appears hundreds of times in the codebase.

---

## 6. Functions

### Basic Function Declaration

Functions are declared with `func`. Indentation defines the function body.

```gdscript
# Simple function, no parameters, no return
func greet():
    print("Welcome to Phantom Badlands!")

# Function with parameters
func greet_player(player_name: String):
    print("Welcome, " + player_name + "!")

# Function with a return value (-> specifies return type)
func calculate_damage(strength: int, weapon_power: int) -> int:
    return strength * 2 + weapon_power

# Function with default parameters
func heal(amount: int = 20):
    current_hp += amount
    current_hp = mini(current_hp, max_hp)  # Don't exceed max HP
```

### Return Types

The `-> Type` syntax after the parameter list declares what the function returns. This is optional but recommended.

```gdscript
func get_name() -> String:
    return name

func is_alive() -> bool:
    return current_hp > 0

func get_stats() -> Dictionary:
    return {"strength": strength, "dexterity": dexterity}

func get_inventory() -> Array:
    return inventory
```

If a function does not explicitly return a value (or has no `-> Type`), it implicitly returns `null`.

### Default Parameters

Parameters can have default values. When the function is called without those arguments, the defaults are used.

```gdscript
func spawn_monster(monster_type: String, level: int = 1, is_boss: bool = false):
    print("Spawning %s (Lv.%d, boss=%s)" % [monster_type, level, str(is_boss)])

# All of these are valid calls:
spawn_monster("Goblin")              # level=1, is_boss=false
spawn_monster("Orc", 5)             # is_boss=false
spawn_monster("Dragon", 50, true)    # All arguments specified
```

Real project example:

```gdscript
# From shared/character.gd
func knows_monster(monster_name: String, monster_level: int = 0) -> bool:
    """Check if the player knows this monster's HP based on previous kills."""
    if not known_monsters.has(monster_name):
        return false
    var max_level_killed = known_monsters[monster_name]
    return monster_level <= max_level_killed
```

### Static Functions

Static functions belong to the class, not to any instance. They are called on the class name and cannot access instance variables (`self` is not available).

```gdscript
class_name DungeonDatabase
extends Node

# Static function -- called as DungeonDatabase.get_step_limit(...)
static func get_step_limit(tier: int, is_boss_floor: bool) -> int:
    """Get step limit for a dungeon floor based on tier."""
    var base = DUNGEON_STEP_LIMITS.get(tier, 400)
    if is_boss_floor:
        base = int(base * 1.5)
    return base

# Calling it from another script:
# var limit = DungeonDatabase.get_step_limit(3, false)
```

Static functions **can** access class constants (declared with `const`) and other static members, but they **cannot** access `var` instance variables.

### The Underscore Convention for Private Functions

As covered in the Scope section, functions starting with `_` are meant to be internal:

```gdscript
# Public API -- other scripts should call this
func calculate_derived_stats():
    var primary_stat_bonus = _get_primary_stat_for_hp()
    max_hp = 50 + (constitution * 5) + primary_stat_bonus
    max_mana = int((intelligence * 3) + (wisdom * 1.5))

# Private helper -- only called from within this class
func _get_primary_stat_for_hp() -> int:
    match class_type:
        "Fighter", "Barbarian", "Paladin":
            return strength
        _:
            return int(intelligence * 0.5)
```

### Docstrings

GDScript supports multi-line strings with triple quotes `"""` used as documentation:

```gdscript
func get_salvage_value(item: Dictionary) -> Dictionary:
    """Calculate salvage materials based on what it would cost to craft the item.
    Returns ~50% of the crafting materials, randomly varied."""
    # ... function body ...
```

These are just string literals at the start of the function -- GDScript does not have a formal docstring system, but this convention is used throughout Phantom Badlands for developer documentation.

---

## 7. Classes, Inheritance, and Resources

### Every Script Extends Something

In GDScript, the first line of every script is (almost always) an `extends` statement. This determines what your script inherits from.

```gdscript
extends Node          # Most basic -- a generic node in the scene tree
extends Resource      # A data container (not in the scene tree)
extends CharacterBody2D  # A 2D physics character (for platformers, etc.)
```

If you omit `extends`, your script implicitly extends `RefCounted` (a simple reference-counted object).

### The `class_name` Keyword

`class_name` gives your script a globally accessible name. Without it, you would need to `preload()` the script to use it.

```gdscript
# shared/character.gd
class_name Character
extends Resource

# Now ANY script in the project can do:
# var c = Character.new()
# var slot = Character.get_item_slot_from_type("weapon_melee")
```

```gdscript
# shared/combat_manager.gd
class_name CombatManager
extends Node

# Other scripts can reference CombatManager by name
```

### Node vs. Resource -- Two Key Base Classes

Understanding the difference between `Node` and `Resource` is fundamental in Godot:

**Node** -- Lives in the scene tree. Has a position in the node hierarchy. Can have children. Participates in Godot's processing loop (`_ready()`, `_process()`). Used for game objects, UI elements, managers.

```gdscript
# Nodes -- they live in the scene tree and can have children
class_name CombatManager
extends Node           # A manager that processes combat logic

class_name WorldSystem
extends Node           # Manages the procedural world

class_name MonsterDatabase
extends Node           # Loaded as a child of the server node
```

**Resource** -- A data container. Does NOT live in the scene tree. Cannot have children. No `_process()`. Used for data that needs to be saved, loaded, or shared.

```gdscript
# Resources -- they are pure data, not scene tree entities
class_name Character
extends Resource       # Player data: stats, inventory, position
```

In Phantom Badlands, `Character` extends `Resource` because a character is really just a bundle of data (stats, inventory, position) that gets serialized and sent over the network. The server and client scripts (which extend `Node`) create Character instances and manipulate them.

### How Scripts Attach to Nodes

In Godot, you create nodes in the scene tree (visually or via code), and attach scripts to them. The script extends the node's type and adds behavior.

For example, the server scene (`server.tscn`) has a root `Node` with `server.gd` attached:

```gdscript
# server/server.gd
extends Node

# This script is attached to the root node of server.tscn
# When the scene loads, _ready() fires

func _ready():
    print("Server starting up...")
    _start_network()
    _load_world()
```

### The `preload()` Pattern

`preload()` loads a script or resource at compile time. This is how scripts reference other scripts:

```gdscript
# Load another script's class at compile time
const TitlesScript = preload("res://shared/titles.gd")
const TradingPostDatabaseScript = preload("res://shared/trading_post_database.gd")

# Now you can create instances:
func _ready():
    var trading_post_db = TradingPostDatabaseScript.new()
    add_child(trading_post_db)  # Add as child node if it extends Node
```

The `res://` prefix means "relative to the project root." So `res://shared/titles.gd` points to the `shared/titles.gd` file in the project.

**`preload()` vs `load()`:**
- `preload()` -- loads at compile time, slightly faster, the path must be a constant string
- `load()` -- loads at runtime, can use variable paths

### Creating Instances

```gdscript
# Creating a new Character (extends Resource)
var new_character = Character.new()
new_character.initialize("Aragorn", "Ranger", "Human")

# Creating a new Node-based object
var combat_manager = CombatManager.new()
add_child(combat_manager)  # Must add to scene tree for it to work
```

### Inheritance with `super()`

When overriding a parent method, use `super()` to call the parent's version:

```gdscript
extends Node

func _ready():
    super()  # Call the parent Node's _ready() first (if it has one)
    print("Child ready!")
```

In practice, `super()` is not used extensively in Phantom Badlands because most scripts extend basic types like `Node` or `Resource` whose built-in methods do not need to be called explicitly. But it is available when you need it.

### Real Project Class Hierarchy

Here is how the main classes in Phantom Badlands relate:

```
Resource
  └── Character          (shared/character.gd -- player data)

Node
  ├── Server             (server/server.gd -- networking + game logic)
  ├── Client             (client/client.gd -- UI + networking)
  ├── CombatManager      (shared/combat_manager.gd -- combat engine)
  ├── WorldSystem        (shared/world_system.gd -- terrain generation)
  ├── MonsterDatabase    (shared/monster_database.gd -- monster definitions)
  ├── QuestDatabase      (shared/quest_database.gd -- quest definitions)
  ├── DungeonDatabase    (shared/dungeon_database.gd -- dungeon layouts)
  ├── DropTables         (shared/drop_tables.gd -- item generation)
  ├── CraftingDatabase   (shared/crafting_database.gd -- crafting recipes)
  └── ChunkManager       (shared/chunk_manager.gd -- world streaming)
```

---

## 8. Enums

Enums define a set of named integer constants. They make code more readable than raw numbers.

### Basic Enum

```gdscript
# Simple enum -- values auto-increment from 0
enum Direction {
    NORTH,   # 0
    SOUTH,   # 1
    EAST,    # 2
    WEST     # 3
}

# Using the enum
var facing = Direction.NORTH

if facing == Direction.NORTH:
    print("Heading north!")
```

### Enums with Explicit Values

```gdscript
enum Rarity {
    COMMON = 0,
    UNCOMMON = 1,
    RARE = 2,
    EPIC = 3,
    LEGENDARY = 4,
    ARTIFACT = 5
}
```

### Real Project Examples

From `shared/combat_manager.gd`:

```gdscript
# Combat actions the player can take
enum CombatAction {
    ATTACK,     # 0 - Basic attack
    FLEE,       # 1 - Run away
    SPECIAL,    # 2 - Special move
    OUTSMART,   # 3 - Use wits to outmaneuver
    ABILITY     # 4 - Use a class ability
}
```

From `shared/monster_database.gd`:

```gdscript
# Monster class affinities -- determines which player class has advantage
enum ClassAffinity {
    NEUTRAL,    # 0 - No advantage
    PHYSICAL,   # 1 - Weak to Warriors, resistant to Mages
    MAGICAL,    # 2 - Weak to Mages, resistant to Warriors
    CUNNING     # 3 - Weak to Tricksters, resistant to others
}
```

From `shared/world_system.gd`:

```gdscript
# Terrain types for the procedural world
enum Terrain {
    THRONE,
    CITY,
    TRADING_POST,
    PLAINS,
    FOREST,
    DEEP_FOREST,
    MOUNTAINS,
    SWAMP,
    DESERT,
    VOLCANO,
    DARK_CIRCLE,
    VOID,
    WATER,
    DEEP_WATER
}
```

### Using Enums in match Statements

```gdscript
func describe_terrain(terrain: WorldSystem.Terrain) -> String:
    match terrain:
        WorldSystem.Terrain.PLAINS:
            return "Open grasslands stretch before you."
        WorldSystem.Terrain.FOREST:
            return "Trees surround you on all sides."
        WorldSystem.Terrain.MOUNTAINS:
            return "Rocky peaks tower above."
        WorldSystem.Terrain.WATER:
            return "Water glistens nearby."
        _:
            return "You stand in unfamiliar territory."
```

### Enums as Dictionary Keys

Enums can be used as dictionary keys for clean lookup tables:

```gdscript
# From shared/crafting_database.gd
const QUALITY_MULTIPLIERS = {
    CraftingQuality.FAILED: 0.0,
    CraftingQuality.POOR: 0.5,
    CraftingQuality.STANDARD: 1.0,
    CraftingQuality.FINE: 1.25,
    CraftingQuality.MASTERWORK: 1.5
}

# Usage:
var quality = CraftingQuality.FINE
var multiplier = QUALITY_MULTIPLIERS[quality]  # 1.25
```

---

## 9. String Formatting and BBCode

### The `%` Operator for String Formatting

GDScript uses C-style `%` formatting (similar to Python's old-style `%` formatting):

```gdscript
# Single value
var name = "Goblin"
print("You encounter a %s!" % name)  # "You encounter a Goblin!"

# Multiple values -- use an array
var monster = "Orc"
var damage = 25
print("%s deals %d damage!" % [monster, damage])  # "Orc deals 25 damage!"
```

**Common format specifiers:**

| Specifier | Meaning | Example |
|---|---|---|
| `%s` | String (or auto-convert to string) | `"Hello %s" % "World"` |
| `%d` | Integer (decimal) | `"Level %d" % 5` |
| `%f` | Float | `"Speed %.2f" % 3.14159` (gives "3.14") |
| `%x` | Hexadecimal | `"Color: %x" % 255` (gives "ff") |
| `%%` | Literal percent sign | `"50%% chance"` |

**Padding and alignment:**

```gdscript
# Right-align in a field of 10 characters
print("%10s" % "Hello")     # "     Hello"

# Left-align with -
print("%-10s" % "Hello")    # "Hello     "

# Zero-pad numbers
print("%05d" % 42)           # "00042"
```

### String Methods

```gdscript
var text = "Welcome to Phantom Badlands"

# Searching
text.find("Phantom")        # Returns 11 (index of first occurrence)
text.find("missing")        # Returns -1 (not found)
text.begins_with("Welcome") # true
text.ends_with("lands")     # true
"phantom" in text.to_lower() # true (case-insensitive search)

# Splitting
var parts = "Fighter,Wizard,Thief".split(",")  # ["Fighter", "Wizard", "Thief"]

# Case conversion
text.to_lower()  # "welcome to phantom badlands"
text.to_upper()  # "WELCOME TO PHANTOM BADLANDS"

# Substring
text.substr(0, 7)    # "Welcome" (start index, length)
text.length()        # 27

# Replacing
text.replace("Phantom", "PHANTOM")  # "Welcome to PHANTOM Badlands"

# Stripping whitespace
"  hello  ".strip_edges()  # "hello"
```

### BBCode for Colored Text

Phantom Badlands uses `RichTextLabel` for all game output, which supports BBCode markup for colors and formatting. This is how the game creates its colorful text interface.

```gdscript
# Color text using BBCode
var colored = "[color=#FF0000]Critical Hit![/color]"  # Red text
var green = "[color=#00FF00]You found a treasure![/color]"  # Green text
var bold = "[b]Important![/b]"  # Bold text

# Combining BBCode with string formatting
var damage = 50
var msg = "[color=#FF4444]%s deals %d damage![/color]" % ["Goblin", damage]

# Common color codes used in the project:
# #FF0000 - Red (damage, danger, bosses)
# #00FF00 - Green (healing, nature monsters, success)
# #0070DD - Blue (rare items, magical monsters)
# #A335EE - Purple (epic items, magical beings)
# #FFD700 - Gold (legendary, special)
# #FF8C00 - Orange (warnings)
# #808080 - Gray (disabled, undead)
# #FFFFFF - White (normal text)
```

Real project patterns:

```gdscript
# Displaying an item with rarity color
var rarity_colors = {
    "common": "#FFFFFF",
    "uncommon": "#00FF00",
    "rare": "#0070DD",
    "epic": "#A335EE",
    "legendary": "#FF8C00",
    "artifact": "#FFD700"
}

var item_name = "Iron Sword"
var rarity = "rare"
var color = rarity_colors.get(rarity, "#FFFFFF")
var display = "[color=%s]%s[/color]" % [color, item_name]
# Result: "[color=#0070DD]Iron Sword[/color]" -- displays as blue text
```

```gdscript
# Displaying monster quality colors from crafting
# From shared/crafting_database.gd
const QUALITY_COLORS = {
    CraftingQuality.FAILED: "#808080",     # Gray
    CraftingQuality.POOR: "#FFFFFF",       # White
    CraftingQuality.STANDARD: "#00FF00",   # Green
    CraftingQuality.FINE: "#0070DD",       # Blue
    CraftingQuality.MASTERWORK: "#A335EE"  # Purple
}
```

### Appending to RichTextLabel

In the game, text is displayed by appending BBCode to a `RichTextLabel` node:

```gdscript
# game_output is a RichTextLabel node
game_output.append_text("[color=#00FF00]You gained 50 XP![/color]\n")
game_output.append_text("[color=#FFD700]Level Up! You are now level 5![/color]\n")
game_output.append_text("You see a [color=#FF0000]Goblin[/color] ahead.\n")
```

---

## 10. Type Casting

### Explicit Type Conversion

GDScript provides functions to convert between types:

```gdscript
# Convert to integer
int(3.7)       # 3 (truncates, does not round)
int("42")      # 42
int(true)      # 1
int(false)     # 0

# Convert to float
float(5)       # 5.0
float("3.14")  # 3.14

# Convert to string
str(42)        # "42"
str(3.14)      # "3.14"
str(true)      # "true"
str([1, 2, 3]) # "[1, 2, 3]"

# Convert to boolean
bool(0)        # false
bool(1)        # true
bool("")       # false
bool("hello")  # true
bool(null)     # false
```

### Why Casting Matters -- The JSON Problem (Again)

The most important casting in this project is `int()` for JSON data:

```gdscript
# Data arrives from the server as JSON
var server_data = {"tier": 3.0, "level": 15.0, "count": 1.0}

# BAD: Using the raw float value as a dict key
var tier_info = TIER_DATA.get(server_data["tier"])  # May fail! 3.0 != 3

# GOOD: Cast to int first
var tier = int(server_data.get("tier", 1))
var tier_info = TIER_DATA.get(tier)  # Works! 3 == 3
```

### The `is` Keyword -- Type Checking

`is` checks whether a value is a specific type:

```gdscript
var value = 42

if value is int:
    print("It's an integer!")

if value is float:
    print("It's a float!")  # Does NOT print -- 42 is an int

# Checking node types
if node is Node2D:
    print("It's a 2D node!")

# Checking custom classes
if character is Character:
    print("It's a Character resource!")
```

### The `as` Keyword -- Safe Casting

`as` attempts to cast a value to a specific type. If the cast fails, it returns `null` instead of crashing:

```gdscript
var node = get_node("SomeNode")

# Try to cast to a specific type
var character = node as CharacterBody2D
if character != null:
    character.move_and_slide()
else:
    print("Node is not a CharacterBody2D!")
```

`as` is most useful for node types in Godot's scene tree. For basic types (`int`, `float`, `String`), use the conversion functions instead.

---

## 11. Common Patterns in This Project

Now that you know the language fundamentals, here are the patterns you will encounter most frequently when working on Phantom Badlands.

### Pattern 1: Safe Dictionary Access with `.get()`

This is the single most common pattern in the codebase. Every time data comes from the network or from a save file, use `.get()`:

```gdscript
# ALWAYS do this:
var name = data.get("name", "Unknown")
var level = int(data.get("level", 1))
var stats = data.get("stats", {})
var items = data.get("inventory", [])

# NEVER do this with data from the network:
var name = data["name"]     # Crashes if "name" key is missing
var name = data.name        # Crashes if "name" key is missing
```

### Pattern 2: `int()` Casting for Dictionary Keys from JSON

```gdscript
# When the key is a number and came from JSON:
var tier = int(item.get("tier", 1))
if CONSUMABLE_TIERS.has(tier):
    var tier_data = CONSUMABLE_TIERS[tier]
```

### Pattern 3: Array of Dictionaries for Game Data

Inventory, quests, buffs, companions -- everything uses this pattern:

```gdscript
# Character's active quests
@export var active_quests: Array = []
# Each quest: {quest_id: String, progress: int, target: int, started_at: int}

# Adding a quest
active_quests.append({
    "quest_id": "kill_goblins_01",
    "progress": 0,
    "target": 10,
    "started_at": int(Time.get_unix_time_from_system())
})

# Finding a quest
for quest in active_quests:
    if quest.get("quest_id") == "kill_goblins_01":
        quest["progress"] += 1  # Update progress
        break
```

### Pattern 4: Constant Lookup Tables

Game data is stored as nested `const` dictionaries at the top of a script:

```gdscript
# From shared/world_system.gd -- tile rendering data
const TILE_RENDER = {
    "empty":    {"char": ".", "color": "#6B5B45", "blocks_move": false, "blocks_los": false},
    "stone":    {"char": "o", "color": "#998877", "blocks_move": true, "blocks_los": true},
    "tree":     {"char": "T", "color": "#228B22", "blocks_move": true, "blocks_los": true},
    "water":    {"char": "~", "color": "#4488FF", "blocks_move": true, "blocks_los": false},
}

# Look up a tile's properties
var tile_type = "tree"
var render_data = TILE_RENDER.get(tile_type, TILE_RENDER["empty"])
var character = render_data["char"]    # "T"
var color = render_data["color"]       # "#228B22"
var blocks = render_data["blocks_move"] # true
```

### Pattern 5: Class Method Using `match` for Branching

```gdscript
# From shared/character.gd
func get_class_passive() -> Dictionary:
    match class_type:
        "Fighter":
            return {
                "name": "Tactical Discipline",
                "description": "20% reduced stamina costs, +15% defense",
                "effects": {"stamina_cost_reduction": 0.20, "defense_bonus_percent": 0.15}
            }
        "Wizard":
            return {
                "name": "Arcane Precision",
                "description": "+15% spell damage, +10% spell crit chance",
                "effects": {"spell_damage_bonus": 0.15, "spell_crit_bonus": 0.10}
            }
        "Thief":
            return {
                "name": "Backstab",
                "description": "+35% crit damage, +10% base crit chance",
                "effects": {"crit_damage_bonus": 0.35, "crit_chance_bonus": 0.10}
            }
        _:
            return {"name": "None", "description": "", "effects": {}}
```

### Pattern 6: String Formatting with BBCode for UI Output

```gdscript
# Display a monster encounter
var monster_name = "Orc Warrior"
var monster_level = 15
var color = "#FF4444"
var text = "[color=%s]%s[/color] (Level %d)" % [color, monster_name, monster_level]
game_output.append_text(text + "\n")

# Display a loot drop
var item_name = "Steel Sword"
var rarity_color = "#0070DD"
var msg = "You found: [color=%s]%s[/color]!" % [rarity_color, item_name]
game_output.append_text(msg + "\n")
```

### Pattern 7: Iterating with Conditions

```gdscript
# Find all available dungeons for the player's level
var player_level = 25
var available = []
for dungeon_id in DUNGEON_TYPES:
    var dungeon = DUNGEON_TYPES[dungeon_id]
    if player_level >= dungeon.min_level and player_level <= dungeon.max_level:
        available.append(dungeon_id)
```

### Pattern 8: Serialization and Deserialization

Converting game objects to dictionaries (for network transmission) and back:

```gdscript
# SERIALIZE: Convert a character to a dictionary for sending over the network
func to_dict() -> Dictionary:
    return {
        "id": character_id,
        "name": name,
        "class": class_type,
        "level": level,
        "stats": {
            "strength": strength,
            "constitution": constitution,
            "dexterity": dexterity,
        },
        "current_hp": current_hp,
        "max_hp": max_hp,
        "inventory": inventory
    }

# DESERIALIZE: Rebuild a character from a dictionary received from the network
func from_dict(data: Dictionary):
    character_id = data.get("id", 0)
    name = data.get("name", "")
    class_type = data.get("class", "Fighter")
    level = data.get("level", 1)

    var stats = data.get("stats", {})
    strength = stats.get("strength", 10)
    constitution = stats.get("constitution", 10)
    dexterity = stats.get("dexterity", 10)

    current_hp = data.get("current_hp", 100)
    max_hp = data.get("max_hp", 100)
    inventory = data.get("inventory", [])
```

**Critical rule:** The keys used in `to_dict()` MUST exactly match the keys read in `from_dict()`. If `to_dict()` writes `"class"` but `from_dict()` reads `"class_type"`, the data will silently be lost and the default will be used.

### Pattern 9: Clamping Values to Valid Ranges

```gdscript
# clampi(value, min, max) -- clamp an integer to a range
var tier_index = clampi(int(level / 15), 0, 8)  # Keep between 0 and 8

# mini(a, b) -- return the smaller value
current_hp = mini(current_hp + healing, max_hp)  # Don't exceed max HP

# maxi(a, b) -- return the larger value
var damage = maxi(0, raw_damage - defense)  # Damage can't go below 0
```

---

## 12. Quick Reference Cheat Sheet

### Variable Declaration

```gdscript
var x = 5                    # Inferred type
var x: int = 5               # Explicit type hint
const MAX = 100              # Constant (compile-time)
static var count: int = 0    # Shared across all instances
@export var hp: int = 100    # Visible in Godot Inspector, serializable
@onready var label = $Label  # Initialize after scene tree is ready
```

### Operators

```gdscript
# Arithmetic
+  -  *  /  %  **           # Add, subtract, multiply, divide, modulo, power

# Comparison
==  !=  <  >  <=  >=

# Logical
and  or  not                 # (not && || !)

# Assignment shortcuts
+=  -=  *=  /=

# String
+                            # Concatenation: "Hello " + "World"
%                            # Formatting: "Level %d" % 5
in                           # Containment: "x" in "text"
```

### Array Methods

```gdscript
var a = [1, 2, 3]
a.append(4)                  # Add to end -> [1, 2, 3, 4]
a.insert(0, 0)              # Insert at index -> [0, 1, 2, 3, 4]
a.erase(2)                  # Remove first occurrence of value 2
a.remove_at(0)              # Remove by index
a.pop_back()                # Remove and return last element
a.pop_front()               # Remove and return first element
a.size()                    # Number of elements
a.is_empty()                # true if no elements
a.has(3)                    # true if 3 is in the array
a.find(3)                   # Index of first 3, or -1
a.sort()                    # Sort in place (ascending)
a.reverse()                 # Reverse in place
a.duplicate()               # Shallow copy
a.duplicate(true)           # Deep copy (copies nested structures)
a.pick_random()             # Random element
a.shuffle()                 # Randomize order in place
a.slice(1, 3)               # Sub-array from index 1 to 3 (exclusive)
a.clear()                   # Remove all elements
```

### Dictionary Methods

```gdscript
var d = {"a": 1, "b": 2}
d.get("a", 0)               # Safe access with default: returns 1
d.get("z", 0)               # Key missing, returns default: 0
d.has("a")                   # true
d.keys()                     # ["a", "b"]
d.values()                   # [1, 2]
d.size()                     # 2
d.is_empty()                 # false
d.erase("a")                # Remove key "a"
d.merge({"c": 3})           # Add entries from another dict
d.duplicate()                # Shallow copy
d.duplicate(true)            # Deep copy
d.clear()                    # Remove all entries
```

### String Methods

```gdscript
var s = "Hello World"
s.length()                   # 11
s.to_lower()                 # "hello world"
s.to_upper()                 # "HELLO WORLD"
s.find("World")              # 6 (index of first match, or -1)
s.begins_with("Hello")      # true
s.ends_with("World")         # true
s.replace("World", "Godot") # "Hello Godot"
s.split(" ")                 # ["Hello", "World"]
s.substr(0, 5)               # "Hello" (start, length)
s.strip_edges()              # Remove leading/trailing whitespace
s.is_empty()                 # false
s.left(5)                    # "Hello" (first N characters)
s.right(5)                   # "World" (last N characters)
"123".is_valid_int()         # true
"3.14".is_valid_float()      # true
str(42)                      # "42" (convert anything to string)
```

### Math Functions

```gdscript
# Integer math
mini(3, 7)                   # 3 (minimum of two ints)
maxi(3, 7)                   # 7 (maximum of two ints)
absi(-5)                     # 5 (absolute value, int)
clampi(15, 0, 10)            # 10 (clamp int to range)
wrapi(12, 0, 10)             # 2 (wrap around, like modulo but handles negatives)

# Float math
minf(3.0, 7.0)              # 3.0
maxf(3.0, 7.0)              # 7.0
absf(-5.5)                   # 5.5
clampf(1.5, 0.0, 1.0)       # 1.0
lerpf(0.0, 100.0, 0.5)      # 50.0 (linear interpolation: 50% between 0 and 100)
snappedf(3.7, 0.5)          # 3.5 (snap to nearest 0.5)
ceil(3.2)                    # 4.0
floor(3.8)                   # 3.0
round(3.5)                   # 4.0
sqrt(16.0)                   # 4.0
pow(2.0, 10.0)               # 1024.0

# Random numbers
randi_range(1, 100)          # Random integer between 1 and 100 (inclusive)
randf_range(0.0, 1.0)       # Random float between 0.0 and 1.0
randi() % 6 + 1             # Random integer 1-6 (dice roll)

# Type conversion
int(3.7)                     # 3
float(5)                     # 5.0
str(42)                      # "42"
bool(1)                      # true
```

### Control Flow Quick Reference

```gdscript
# Conditional
if condition:
    pass
elif other_condition:
    pass
else:
    pass

# Ternary (one-line if)
var label = "alive" if hp > 0 else "dead"

# For loop variants
for i in range(10):          # 0 through 9
for item in array:           # Each element
for key in dictionary:       # Each key
for i in range(5, 0, -1):   # 5, 4, 3, 2, 1 (countdown)

# While loop
while condition:
    pass

# Match (switch/case)
match value:
    1:
        pass
    2, 3:                    # Multiple values
        pass
    _:                       # Default
        pass
```

### Function Quick Reference

```gdscript
# Basic function
func do_thing():
    pass

# With parameters and return type
func add(a: int, b: int) -> int:
    return a + b

# Default parameters
func greet(name: String = "Adventurer"):
    print("Hello, " + name)

# Static function (called on class, not instance)
static func utility_function() -> int:
    return 42
```

### Class Quick Reference

```gdscript
# Defining a class
class_name MyClass
extends Node               # or Resource, or any other base

# Constants
const MAX_VALUE = 100

# Class-level variables
var instance_var: int = 0
static var class_var: int = 0

# Constructor
func _init():
    pass

# Called when node enters scene tree
func _ready():
    pass

# Called every frame (delta = seconds since last frame)
func _process(delta: float):
    pass
```

---

## Next Steps

Now that you understand GDScript fundamentals, here are good next steps for working on Phantom Badlands:

1. **Read `shared/character.gd`** -- It is the most approachable file in the project and demonstrates nearly every pattern covered here.
2. **Read the CLAUDE.md file** at the project root -- It has critical project-specific rules about the action bar, player-visible output, and common pitfalls.
3. **Explore the `docs/` folder** -- `QUICK_REFERENCE.md` for a bird's-eye view, `CODE_GUIDE.md` for modification patterns, and `architecture.md` for system architecture.
4. **Try running the game** -- Launch the server and client following the instructions in CLAUDE.md, create a character, and walk around. Seeing the game run makes the code much easier to understand.

Good luck, and welcome to the Phantom Badlands codebase!
