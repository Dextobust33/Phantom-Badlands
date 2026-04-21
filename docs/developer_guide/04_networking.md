# Chapter 4: Networking

This chapter explains how Phantom Badlands handles multiplayer communication between the client and server. By the end, you will understand the message format, the sending/receiving pipelines on both sides, and how to add new networked features.

---

## Table of Contents

1. [Networking Overview](#1-networking-overview)
2. [How TCP Works (Brief Primer)](#2-how-tcp-works-brief-primer)
3. [Message Format](#3-message-format)
4. [Client-Side Networking (client.gd)](#4-client-side-networking-clientgd)
5. [Server-Side Networking (server.gd)](#5-server-side-networking-servergd)
6. [The Message Lifecycle -- Complete Example](#6-the-message-lifecycle----complete-example)
7. [Client Message Handler -- handle_server_message()](#7-client-message-handler----handle_server_message)
8. [Security Layer](#8-security-layer)
9. [Adding a New Message Type -- Step by Step](#9-adding-a-new-message-type----step-by-step)
10. [Common Networking Pitfalls](#10-common-networking-pitfalls)

---

## 1. Networking Overview

Phantom Badlands uses **raw TCP sockets** for all client-server communication. It does **not** use Godot's built-in multiplayer API (`MultiplayerPeer`, RPCs, `@rpc` annotations, etc.).

### Why raw TCP instead of Godot's multiplayer API?

1. **Simplicity.** The game is text-based. There are no physics objects to synchronize, no interpolation requirements, and no need for Godot's high-level replication system. A plain request-response protocol is all that is needed.
2. **Control.** Raw sockets give the developer full control over the wire format, buffering, compression, and security. There is no hidden magic -- every byte that crosses the network is explicit in the code.
3. **Portability.** The protocol is just JSON over TCP. Any language or tool that can open a TCP connection can talk to the server. This makes debugging easy (you can even use `telnet` or `netcat` in a pinch).

### The one-sentence summary

> The client connects to the server on **port 9080**. All communication is **JSON dictionaries** sent as UTF-8 text, with each message separated by a **newline** (`\n`). Think of it like a chat protocol where every "line" is one JSON object.

**Key source files:**

| File | Role |
|------|------|
| `client/client.gd` | Client networking -- connect, send, receive, handle responses (~21 000 lines) |
| `server/server.gd` | Server networking -- listen, accept, route, respond (~14 000 lines) |

---

## 2. How TCP Works (Brief Primer)

If you have never worked with sockets before, here is the minimum you need to know.

### What TCP gives you

**TCP** (Transmission Control Protocol) is a reliable, ordered byte-stream protocol built into every operating system. When you send data over TCP:

- **Reliable delivery** -- the OS retransmits lost packets automatically. If the data does not arrive, you get a disconnect, not silent data loss.
- **Ordered delivery** -- bytes arrive in the exact order they were sent. Message A sent before message B will always arrive before message B.
- **Flow control** -- TCP automatically slows down if the receiver cannot keep up.

### What TCP does NOT give you

TCP is a **stream** of bytes, not a stream of messages. If you send two JSON objects back-to-back, the receiver might get them in a single read, or split across multiple reads, or half of one and half of another. TCP has no concept of "message boundaries."

That is why we use **newlines** (`\n`) as delimiters. Each JSON message is terminated with `\n`, and the receiver splits on newlines to reconstruct individual messages.

```
Sent by server (two messages):
    {"type":"location","x":5}\n{"type":"character_update","level":3}\n

Received by client (one read, both messages in a single chunk):
    {"type":"location","x":5}\n{"type":"character_update","level":3}\n

OR received as two separate reads:
    Read 1: {"type":"location","x":5}\n{"type":"ch
    Read 2: aracter_update","level":3}\n
```

In the second case, the first read contains one complete message and the beginning of a second. The receiver must buffer the incomplete fragment and wait for the rest to arrive. The project handles this with a `buffer` string that accumulates data across frames.

### Godot's TCP classes

| Class | Side | Purpose |
|-------|------|---------|
| `StreamPeerTCP` | Client | A single TCP connection. Call `connect_to_host()` to connect, `put_data()` to send, `get_data()` to receive. |
| `TCPServer` | Server | Listens on a port. Call `listen()` to start, `take_connection()` to accept an incoming client (returns a `StreamPeerTCP`). |

Both classes are non-blocking by default. You must call `poll()` each frame to advance the connection state machine, and check `get_status()` to know whether the connection is still alive.

---

## 3. Message Format

Every message in the project is a **JSON dictionary** with a `"type"` field that identifies what kind of message it is.

```json
{"type": "move", "direction": 8}
{"type": "combat", "action": "attack"}
{"type": "chat", "message": "Hello everyone!"}
```

The `"type"` field is always a string. The receiver reads `type`, then knows which fields to expect in the rest of the dictionary.

### Real examples from the project

**Client --> Server (requests):**

```json
{"type": "login", "username": "player1", "password": "secret123"}
{"type": "move", "direction": 8}
{"type": "combat", "action": "attack"}
{"type": "chat", "message": "Anyone want to party up?"}
{"type": "inventory_equip", "index": 3}
{"type": "gathering_start", "job": "fishing"}
```

**Server --> Client (responses):**

```json
{"type": "welcome", "message": "Welcome to Phantom Badlands!", "server_version": "0.1.0"}
{"type": "login_success", "username": "player1", "account_id": "abc123"}
{"type": "location", "at_water": false, "at_ore_deposit": true, "ore_tier": 3, "at_dungeon": false, "description": "..."}
{"type": "character_update", "character": {"level": 5, "current_hp": 87, "max_hp": 120, ...}, "full": true}
{"type": "combat_start", "monster_name": "Orc", "monster_level": 7, "monster_hp": -1}
{"type": "text", "message": "[color=#00FF00]You found a Health Potion![/color]"}
```

### Key observations

- Direction `8` means north (numpad layout: 8=N, 2=S, 4=W, 6=E).
- `monster_hp: -1` means the player has not encountered this monster type before, so the client shows "???" for the HP bar (the monster HP knowledge system).
- The `character_update` message contains either a full character dictionary or a delta of changed fields, controlled by the `"full"` flag.
- BBCode tags like `[color=#00FF00]` are used directly in text messages -- the client renders them in a `RichTextLabel`.

---

## 4. Client-Side Networking (client.gd)

All client networking lives in `client/client.gd`. Here is how each piece works.

### 4.1 Connecting

The client creates a `StreamPeerTCP` at the top of the file:

```gdscript
# client/client.gd, line 294
var connection = StreamPeerTCP.new()
```

When the player enters a server address and clicks Connect, `connect_to_server()` is called:

```gdscript
# client/client.gd, line 18629
func connect_to_server():
    var status = connection.get_status()

    # Don't re-connect if already connected or connecting
    if status == StreamPeerTCP.STATUS_CONNECTED:
        display_game("[color=#00FFFF]Already connected![/color]")
        return
    if status == StreamPeerTCP.STATUS_CONNECTING:
        display_game("[color=#00FFFF]Connection in progress...[/color]")
        return

    display_game("Connecting to %s:%d..." % [server_ip, server_port])
    var error = connection.connect_to_host(server_ip, server_port)
    if error != OK:
        display_game("[color=#FF0000]Failed to connect! Error: %d[/color]" % error)
        return

    display_game("Waiting for connection...")
```

`connect_to_host()` is **non-blocking**. It starts the TCP handshake in the background. The actual connection completes later, detected in `_process()`.

### 4.2 Detecting connection success (in _process)

Every frame, `_process()` checks the connection status:

```gdscript
# client/client.gd, line 2836
if status == StreamPeerTCP.STATUS_CONNECTED:
    if not connected:
        connected = true
        display_game("[color=#00FF00]Connected to server![/color]")
        game_state = GameState.CONNECTED
        show_login_panel()
```

The first time `STATUS_CONNECTED` is seen, the client flips the `connected` flag, hides the connection panel, and shows the login screen.

### 4.3 Sending messages

All outbound messages go through one function:

```gdscript
# client/client.gd, line 18671
func send_to_server(data: Dictionary):
    if not connected:
        display_game("[color=#FF0000]Not connected![/color]")
        return

    var json_str = JSON.stringify(data) + "\n"
    connection.put_data(json_str.to_utf8_buffer())
```

This converts the dictionary to a JSON string, appends a newline delimiter, converts to a UTF-8 byte buffer, and sends it.

**Usage examples from the codebase:**

```gdscript
# Move north
send_to_server({"type": "move", "direction": 8})

# Attack in combat
send_to_server({"type": "combat", "action": "attack"})

# Send a chat message
send_to_server({"type": "chat", "message": text})

# Use an inventory item
send_to_server({"type": "inventory_use", "index": item_index})

# Accept a quest
send_to_server({"type": "quest_accept", "quest_id": quest_id})

# Start gathering
send_to_server({"type": "gathering_start", "job": "mining"})
```

There are also convenience wrappers for common actions:

```gdscript
func send_move(direction: int):
    if not connected or not has_character:
        return
    send_to_server({"type": "move", "direction": direction})
```

### 4.4 Receiving messages (in _process)

Every frame, the client checks for incoming data and processes it:

```gdscript
# client/client.gd, line 2852
var available = connection.get_available_bytes()
if available > 0:
    var data = connection.get_data(available)
    if data[0] == OK:
        var raw_bytes: PackedByteArray = data[1]

        # Auto-detect: is the server using binary framing or plain text?
        if not server_binary_mode and raw_buffer.is_empty() and buffer.is_empty():
            if raw_bytes[0] != 0x7B:  # 0x7B = '{' character
                server_binary_mode = true

        if server_binary_mode:
            raw_buffer.append_array(raw_bytes)
            process_raw_buffer()
        else:
            buffer += raw_bytes.get_string_from_utf8()
            process_buffer()
```

The flow is:

1. **Check for data** -- `get_available_bytes()` returns how many bytes are waiting.
2. **Read all available bytes** -- `get_data(available)` returns a `[error_code, PackedByteArray]` tuple.
3. **Detect protocol** -- On the first byte ever received, if it is not `{` (the start of a JSON object), the server is using binary framing. Otherwise, it is plain newline-delimited JSON.
4. **Append to buffer** -- The raw bytes are added to either `raw_buffer` (binary mode) or `buffer` (text mode).
5. **Parse complete messages** -- `process_buffer()` or `process_raw_buffer()` extracts complete messages and passes them to `handle_server_message()`.

### 4.5 process_buffer() -- text mode

```gdscript
# client/client.gd, line 14933
func process_buffer():
    while "\n" in buffer:
        var pos = buffer.find("\n")
        var msg_str = buffer.substr(0, pos)
        buffer = buffer.substr(pos + 1)

        var json = JSON.new()
        if json.parse(msg_str) == OK:
            handle_server_message(json.data)
```

This is the core receive loop:
1. Look for a newline in the buffer.
2. Extract everything before the newline -- that is one complete JSON message.
3. Remove the consumed portion from the buffer (leave the rest for next time).
4. Parse the JSON string into a Dictionary.
5. Pass it to `handle_server_message()`.
6. Repeat until no more complete messages remain.

If only half a message has arrived (no newline yet), the loop exits and the partial data stays in `buffer` until the next frame brings more bytes.

### 4.6 Binary mode and compression

The server can optionally send messages in a binary frame format for better performance:

```
[4 bytes: frame length (big-endian uint32)]  [1 byte: flags]  [payload bytes]
```

- **Flag `0x00`** = plain JSON (UTF-8 bytes, no compression)
- **Flag `0x01`** = gzip-compressed JSON

The client detects binary mode automatically: if the first byte received is not `{`, it switches to `process_raw_buffer()` which reads the 4-byte length header, extracts the payload, decompresses if needed, and parses the JSON.

```gdscript
# client/client.gd, line 14943
func process_raw_buffer():
    while raw_buffer.size() >= 5:  # Minimum: 4-byte header + 1-byte flags
        # Read frame length (big-endian uint32)
        var frame_len = (raw_buffer[0] << 24) | (raw_buffer[1] << 16) | (raw_buffer[2] << 8) | raw_buffer[3]
        if raw_buffer.size() < 4 + frame_len:
            return  # Incomplete frame, wait for more data
        var flags = raw_buffer[4]
        var payload = raw_buffer.slice(5, 4 + frame_len)
        raw_buffer = raw_buffer.slice(4 + frame_len)  # Consume frame

        var json_bytes = payload
        if flags & 0x01:  # Gzip compressed
            json_bytes = payload.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)

        # Parse JSON and handle
        var json = JSON.new()
        if json.parse(json_bytes.get_string_from_utf8()) == OK:
            handle_server_message(json.data)
```

**Conceptually, this is still JSON messages.** The binary framing is just an optimization layer. The server compresses messages larger than 512 bytes and the client transparently decompresses them. You do not need to think about this when adding new features -- just use `send_to_server()` and `send_to_peer()` as normal.

---

## 5. Server-Side Networking (server.gd)

### 5.1 Starting the server

In `_ready()`, the server creates a `TCPServer` and starts listening:

```gdscript
# server/server.gd, line 49
var server = TCPServer.new()

# server/server.gd, line 329
func _ready():
    # ... initialization ...
    var error = server.listen(PORT)  # PORT defaults to 9080
    if error != OK:
        print("ERROR: Failed to start server on port %d" % PORT)
        return
    print("Server started on port %d" % PORT)
```

After this, the server is ready to accept connections.

### 5.2 Accepting connections (in _process)

Every frame, the server checks for new incoming connections:

```gdscript
# server/server.gd, line 818
if server.is_connection_available():
    var peer = server.take_connection()          # Returns a StreamPeerTCP
    var peer_ip = peer.get_connected_host()

    # ... security checks (IP bans, connection cap, rate limiting) ...

    # Accept the connection
    var peer_id = next_peer_id
    next_peer_id += 1

    peers[peer_id] = {
        "connection": peer,
        "authenticated": false,
        "account_id": "",
        "username": "",
        "character_name": "",
        "buffer": "",
        "connect_time": current_time,
        "ip": peer_ip
    }

    # Send welcome message
    send_to_peer(peer_id, {
        "type": "welcome",
        "message": "Welcome to Phantom Badlands!",
        "server_version": "0.1.0"
    })
```

### 5.3 What is a "peer"?

A **peer** is the server's representation of one connected client. Each peer gets:

- A unique **`peer_id`** (integer, starts at 1, increments forever).
- An entry in the **`peers`** dictionary containing the TCP connection, authentication state, buffer, etc.
- Optionally, an entry in the **`characters`** dictionary (once they select a character to play).

```gdscript
# The peers dictionary -- one entry per connected client
var peers = {}  # peer_id -> {connection, buffer, authenticated, account_id, username, ...}

# The characters dictionary -- one entry per player actively in-game
var characters = {}  # peer_id -> Character object
```

The relationship: every entry in `characters` has a corresponding entry in `peers`, but not every peer has a character (they might still be on the login screen).

### 5.4 Reading data from peers (in _process)

After accepting connections, the server loops over all existing peers to read incoming data:

```gdscript
# server/server.gd, line 878
for peer_id in peers.keys():
    var peer_data = peers[peer_id]
    var connection = peer_data.connection

    # CRITICAL: Poll each connection to advance its state!
    connection.poll()

    # Check if still connected
    if connection.get_status() != StreamPeerTCP.STATUS_CONNECTED:
        disconnected_peers.append(peer_id)
        continue

    # Read available data
    var available = connection.get_available_bytes()
    if available > 0:
        var data = connection.get_data(available)
        if data[0] == OK:
            var message = data[1].get_string_from_utf8()
            peer_data.buffer += message

            # Security: Check buffer size limit (64KB)
            if peer_data.buffer.length() > MAX_BUFFER_BYTES:
                disconnected_peers.append(peer_id)
                continue

            # Parse complete messages from the buffer
            process_buffer(peer_id)
```

Note the `connection.poll()` call. In Godot 4, `StreamPeerTCP` requires manual polling to advance the internal connection state machine. Without it, the connection status never updates and you get silent failures.

### 5.5 process_buffer() -- server side

The server's `process_buffer()` is nearly identical to the client's:

```gdscript
# server/server.gd, line 939
func process_buffer(peer_id: int):
    var peer_data = peers[peer_id]
    var buffer = peer_data.buffer
    var messages_this_frame = 0

    while "\n" in buffer:
        var newline_pos = buffer.find("\n")
        var message_str = buffer.substr(0, newline_pos)
        buffer = buffer.substr(newline_pos + 1)

        # Security: Cap messages per frame (max 10)
        messages_this_frame += 1
        if messages_this_frame > MAX_MESSAGES_PER_FRAME:
            break

        # Security: Drop oversized single messages (max 32KB)
        if message_str.length() > MAX_SINGLE_MESSAGE_BYTES:
            continue

        var json = JSON.new()
        var error = json.parse(message_str)
        if error == OK:
            handle_message(peer_id, json.data)

    peer_data.buffer = buffer
```

Same pattern: split on newlines, parse JSON, route to handler. The security additions (per-frame message cap, message size limit) prevent clients from flooding the server.

### 5.6 Message routing -- handle_message()

This is the **heart of the server**. It is a massive `match` statement that routes each message type to its handler function:

```gdscript
# server/server.gd, line 970
func handle_message(peer_id: int, message: Dictionary):
    var msg_type = message.get("type", "")

    # Security: Token bucket rate limiting
    if not _check_rate_limit(peer_id, msg_type):
        return  # Silently drop

    match msg_type:
        # === Authentication ===
        "register":
            handle_register(peer_id, message)
        "login":
            handle_login(peer_id, message)
        "list_characters":
            handle_list_characters(peer_id)
        "select_character":
            handle_select_character(peer_id, message)
        "create_character":
            handle_create_character(peer_id, message)

        # === Core Gameplay ===
        "move":
            handle_move(peer_id, message)
        "hunt":
            handle_hunt(peer_id)
        "combat":
            handle_combat_command(peer_id, message)
        "rest":
            handle_rest(peer_id)
        "chat":
            handle_chat(peer_id, message)

        # === Inventory ===
        "inventory_use":
            handle_inventory_use(peer_id, message)
        "inventory_equip":
            handle_inventory_equip(peer_id, message)
        "inventory_unequip":
            handle_inventory_unequip(peer_id, message)
        "inventory_discard":
            handle_inventory_discard(peer_id, message)
        "inventory_salvage":
            handle_inventory_salvage(peer_id, message)

        # === Quests ===
        "quest_accept":
            handle_quest_accept(peer_id, message)
        "quest_abandon":
            handle_quest_abandon(peer_id, message)
        "quest_turn_in":
            handle_quest_turn_in(peer_id, message)

        # === Gathering ===
        "gathering_start":
            handle_gathering_start(peer_id, message)
        "gathering_choice":
            handle_gathering_choice(peer_id, message)
        "gathering_end":
            handle_gathering_end(peer_id, message)

        # === Dungeons ===
        "dungeon_enter":
            handle_dungeon_enter(peer_id, message)
        "dungeon_move":
            handle_dungeon_move(peer_id, message)
        "dungeon_exit":
            handle_dungeon_exit(peer_id)

        # === Trading ===
        "trade_request":
            handle_trade_request(peer_id, message)
        "trade_offer":
            handle_trade_offer(peer_id, message)
        "trade_ready":
            handle_trade_ready(peer_id)

        # === Party ===
        "party_invite":
            handle_party_invite(peer_id, message)
        "party_invite_response":
            handle_party_invite_response(peer_id, message)
        "party_disband":
            handle_party_disband(peer_id)

        # ... 70+ more message types (market, house, companions, etc.)

        _:
            pass  # Unknown message type -- silently ignore
```

The full `match` block spans lines 977-1368 in `server.gd` and handles over **100 different message types**. Every message type maps to a dedicated handler function, keeping the routing clean despite the scale.

### 5.7 Sending messages to clients

```gdscript
# server/server.gd, line 4387
func send_to_peer(peer_id: int, data: Dictionary):
    if not peers.has(peer_id):
        return

    var connection = peers[peer_id].connection
    if connection.get_status() != StreamPeerTCP.STATUS_CONNECTED:
        return

    if USE_COMPRESSION:
        # Binary framing: [4-byte length][1-byte flags][payload]
        var json_bytes = JSON.stringify(data).to_utf8_buffer()
        var flags: int = 0x00  # Plain JSON
        var payload = json_bytes
        if json_bytes.size() > COMPRESSION_THRESHOLD:  # 512 bytes
            var compressed = json_bytes.compress(FileAccess.COMPRESSION_GZIP)
            if compressed.size() < json_bytes.size():
                payload = compressed
                flags = 0x01  # Gzip compressed
        # Build frame
        var frame_len = 1 + payload.size()
        var header = PackedByteArray()
        header.resize(5)
        header[0] = (frame_len >> 24) & 0xFF
        header[1] = (frame_len >> 16) & 0xFF
        header[2] = (frame_len >> 8) & 0xFF
        header[3] = frame_len & 0xFF
        header[4] = flags
        header.append_array(payload)
        connection.put_data(header)
    else:
        # Legacy: newline-delimited JSON
        var json_str = JSON.stringify(data) + "\n"
        connection.put_data(json_str.to_utf8_buffer())
```

There is also a broadcast helper for sending to all players:

```gdscript
func broadcast_chat(message: String, sender: String = "System"):
    for peer_id in characters.keys():
        send_to_peer(peer_id, {
            "type": "chat",
            "sender": sender,
            "message": message
        })
```

---

## 6. The Message Lifecycle -- Complete Example

Let us trace a complete round-trip: **the player moves north**.

### Step-by-step walkthrough

**1. Player presses W key**

In `client.gd` `_process()`, the input handler detects the key press and calls `send_move(8)` (8 = north in numpad layout).

**2. Client sends the message**

```gdscript
send_to_server({"type": "move", "direction": 8})
```

This becomes the bytes: `{"type":"move","direction":8}\n` sent over TCP.

**3. Server receives the bytes**

On the next server frame, `_process()` sees `connection.get_available_bytes() > 0`, reads the data, appends it to `peer_data.buffer`, and calls `process_buffer(peer_id)`.

**4. Server parses the message**

`process_buffer()` finds the `\n`, extracts the JSON string, parses it into `{"type": "move", "direction": 8}`, and calls `handle_message(peer_id, message)`.

**5. Server routes to handler**

`handle_message()` matches `"move"` and calls `handle_move(peer_id, message)`.

**6. Server processes the move**

`handle_move()` does a LOT of work:
- Validates the player can move (not in combat, not in dungeon, not gathering)
- Calculates new position via `world_system.move_player()`
- Checks for collisions with other players, NPCs, gathering nodes
- Updates `character.x` and `character.y`
- Regenerates HP and resources
- Processes egg incubation steps
- Checks for random encounters (wandering merchants, monsters, etc.)

**7. Server sends response messages**

At the end of `handle_move()`, the server sends multiple messages back:

```gdscript
send_location_update(peer_id)     # Map data, terrain flags, nearby players
send_character_update(peer_id)    # Updated HP, resources, position, inventory
```

These become two separate JSON messages sent to the client.

**8. Client receives the responses**

On the next client frame, `_process()` reads the incoming bytes, `process_buffer()` or `process_raw_buffer()` splits them into individual messages, and each one is passed to `handle_server_message()`.

**9. Client updates the UI**

- `"location"` handler updates the map panel, terrain flags (`at_water`, `at_ore_deposit`, etc.), and dungeon entrance status.
- `"character_update"` handler updates HP bars, resource bars, XP bar, currency display, and the companion art overlay.

### Sequence diagram

```
  CLIENT                                          SERVER
    |                                                |
    |  Player presses W key                          |
    |                                                |
    | --- {"type":"move","direction":8}\n ---------> |
    |                                                |
    |                       process_buffer() parses  |
    |                       handle_message() routes  |
    |                       handle_move() processes  |
    |                         - validate movement    |
    |                         - update position      |
    |                         - regen HP/resources   |
    |                         - check encounters     |
    |                         - process egg steps    |
    |                                                |
    | <--- {"type":"location","at_water":false,...}\n |
    | <--- {"type":"character_update","character":{  |
    |        "current_hp":95,"x":5,"y":11,...}}\n    |
    |                                                |
    |  handle_server_message() processes each:       |
    |    "location"  -> update_map()                 |
    |    "character_update" -> update HP/XP bars     |
    |                                                |
```

### Important: multiple messages per action

A single player action often triggers **multiple server responses**. Moving one tile can generate:

| Message | Purpose |
|---------|---------|
| `location` | Updated map, terrain info |
| `character_update` | Updated stats (HP regen, position) |
| `status_effect` | Poison tick, blind tick, buff expiry |
| `egg_hatched` | If an egg just hatched from the step |
| `text` | Informational messages (compass hints, warnings) |
| `combat_start` | If a random encounter triggered |
| `player_bump` | If walking into another player |

The client must be prepared to handle any combination of these in any frame.

---

## 7. Client Message Handler -- handle_server_message()

Located at line 14970 in `client/client.gd`, this function is the client-side counterpart to the server's `handle_message()`. It receives a Dictionary and matches on the `"type"` field.

```gdscript
func handle_server_message(message: Dictionary):
    var msg_type = message.get("type", "")

    match msg_type:
        "welcome":
            display_game("[color=#00FF00]%s[/color]" % message.get("message", ""))
            game_state = GameState.LOGIN_SCREEN

        "login_success":
            username = message.get("username", "")
            account_id = message.get("account_id", "")
            send_to_server({"type": "house_request"})
            game_state = GameState.HOUSE_SCREEN

        "location":
            if not dungeon_mode:
                update_map(message.get("description", ""))
            at_water = message.get("at_water", false)
            at_ore_deposit = message.get("at_ore_deposit", false)
            # ... update all location flags ...

        "character_update":
            if message.has("character"):
                var is_full = message.get("full", true)
                if is_full:
                    _set_character_data(message.character)
                else:
                    _merge_character_delta(message.character)
                update_player_hp_bar()
                update_resource_bar()
                update_player_xp_bar()

        "combat_start":
            _process_combat_start(message)

        "combat_message":
            # Display a combat log line
            _display_combat_msg(message.get("message", ""))

        "combat_end":
            in_combat = false
            # Process victory/defeat, update UI...

        "text":
            display_game(message.get("message", ""))

        # ... 100+ more message types ...
```

### Message categories

The handler processes messages in these major groups:

**Authentication and account management:**
| Type | Description |
|------|-------------|
| `welcome` | Server greeting on connect |
| `register_success` / `register_failed` | Account creation result |
| `login_success` / `login_failed` | Login result |
| `character_list` | Available characters for this account |
| `character_loaded` | Character data after selection |

**Game state updates:**
| Type | Description |
|------|-------------|
| `character_update` | Stats, inventory, position (full or delta) |
| `location` | Map display, terrain flags, nearby features |
| `text` | General text messages (loot, events, system info) |
| `error` | Error messages (red text) |
| `status_effect` | Poison, blind, buff timers |

**Combat:**
| Type | Description |
|------|-------------|
| `combat_start` | A fight begins (monster info, art) |
| `combat_message` | Round-by-round combat log |
| `combat_update` | Mid-combat stat changes (HP, resources) |
| `combat_end` | Fight over (victory/defeat, loot) |
| `enemy_hp_revealed` | Analyze ability showed enemy HP |

**Social:**
| Type | Description |
|------|-------------|
| `chat` | Global chat message from another player |
| `private_message` | Whisper from another player |
| `player_list` | List of online players |
| `player_bump` | Walked into another player (party invite?) |
| `trade_request` / `trade_update` | Player-to-player trade |

**UI and systems:**
| Type | Description |
|------|-------------|
| `ability_data` | Player's abilities and keybinds |
| `house_data` | Sanctuary (house) state |
| `dungeon_state` | Current dungeon floor layout |
| `market_data` | Open Market listings |
| `quest_board` | Available quests at a trading post |
| `egg_hatched` | A companion egg just hatched |

---

## 8. Security Layer

The server implements several layers of protection against malicious or misbehaving clients. All constants are defined at the top of `server/server.gd`.

### Rate limiting (token bucket)

Every peer has a "bucket" of tokens. Each message costs one token. Tokens refill over time.

```
Sustained rate:  20 messages/second  (RATE_LIMIT_TOKENS_PER_SEC)
Burst capacity:  30 messages          (RATE_LIMIT_TOKENS_MAX)
```

If a client exhausts their tokens, subsequent messages are silently dropped until tokens refill.

```gdscript
# server/server.gd, line 4655
func _check_rate_limit(peer_id: int, msg_type: String) -> bool:
    # Refill tokens based on elapsed time
    bucket.tokens = minf(RATE_LIMIT_TOKENS_MAX, bucket.tokens + elapsed * RATE_LIMIT_TOKENS_PER_SEC)
    # Consume one token
    if bucket.tokens < 1.0:
        return false  # Drop the message
    bucket.tokens -= 1.0
    return true
```

### Per-type cooldowns

Certain message types have minimum intervals:

| Message type | Cooldown |
|-------------|----------|
| `chat` | 800 ms |
| `private_message` | 800 ms |
| `register` | 5 seconds |

### Buffer limits

| Limit | Value | Effect |
|-------|-------|--------|
| Max buffer per peer | 64 KB | Disconnect if exceeded |
| Max single message | 32 KB | Message silently dropped |
| Max messages per frame | 10 | Remaining carried to next frame |
| Max chat message | 500 chars | Truncated |

### Login brute-force protection

```
Max failed attempts:  5 within 5 minutes
Lockout duration:     15 minutes
Tracking:            By IP address
```

After 5 failed login attempts from the same IP within a 5-minute window, that IP is locked out for 15 minutes.

### IP bans

The server maintains a `ban_list.json` file. Banned IPs are rejected immediately on connection before any data is exchanged. GMs can ban/unban IPs with `/banip` and `/unbanip` commands.

### Connection cap

The server accepts at most **200 simultaneous connections** (`MAX_TOTAL_CONNECTIONS`). Additionally, each IP is limited to **3 simultaneous connections** (`MAX_CONNECTIONS_PER_IP`), and new connections from the same IP are throttled to one every **5 seconds** (`CONNECTION_RATE_LIMIT`).

### Server-side validation

The server **never trusts client data**. Every handler validates:

- Is the peer authenticated?
- Do they have a character loaded?
- Are they in the correct state (not in combat, not in a dungeon, etc.)?
- Are the values within acceptable ranges?

For example, `handle_move()` checks:

```gdscript
func handle_move(peer_id: int, message: Dictionary):
    if not characters.has(peer_id):
        return
    if party_membership.has(peer_id) and not _is_party_leader(peer_id):
        send_to_peer(peer_id, {"type": "text", "message": "Your party leader controls movement."})
        return
    if combat_mgr.is_in_combat(peer_id):
        send_to_peer(peer_id, {"type": "error", "message": "You cannot move while in combat!"})
        return
    if pending_flocks.has(peer_id):
        send_to_peer(peer_id, {"type": "error", "message": "More enemies are approaching!"})
        return
    if active_gathering.has(peer_id):
        send_to_peer(peer_id, {"type": "error", "message": "You cannot move while gathering!"})
        return
    # ... only THEN process the actual movement
```

---

## 9. Adding a New Message Type -- Step by Step

This section walks through adding a hypothetical new feature: a `/ping` command that measures round-trip time.

### Step 1: Define the message format

Decide what data needs to cross the wire.

```
Client -> Server:  {"type": "ping", "client_time": 1708900000.0}
Server -> Client:  {"type": "pong", "client_time": 1708900000.0, "server_time": 1708900000.5}
```

### Step 2: Client -- send the message

In `client/client.gd`, add the command trigger. If this is a chat command:

```gdscript
# In process_command(), inside the match statement:
"ping":
    var now = Time.get_unix_time_from_system()
    send_to_server({"type": "ping", "client_time": now})
    display_game("[color=#808080]Ping sent...[/color]")
```

If the command keyword is new, add `"ping"` to the `command_keywords` array (around line 15835) so the input system routes it to `process_command()` instead of sending it as chat.

### Step 3: Server -- add to handle_message() match

In `server/server.gd`, add the new type to the `match` block:

```gdscript
# In handle_message(), inside the match statement:
"ping":
    handle_ping(peer_id, message)
```

### Step 4: Server -- write the handler function

```gdscript
func handle_ping(peer_id: int, message: Dictionary):
    # Validation: must have a character
    if not characters.has(peer_id):
        return

    var client_time = message.get("client_time", 0.0)
    var server_time = Time.get_unix_time_from_system()

    send_to_peer(peer_id, {
        "type": "pong",
        "client_time": client_time,
        "server_time": server_time
    })
```

### Step 5: Client -- handle the response

In `client/client.gd`, add a case in `handle_server_message()`:

```gdscript
# In handle_server_message(), inside the match statement:
"pong":
    var client_time = message.get("client_time", 0.0)
    var now = Time.get_unix_time_from_system()
    var round_trip_ms = int((now - client_time) * 1000)
    display_game("[color=#00FFFF]Pong! Round-trip: %d ms[/color]" % round_trip_ms)
```

### Step 6: Test it

1. Run the server and client.
2. Log in, select a character.
3. Type `/ping` in the chat input.
4. You should see: `Ping sent...` followed by `Pong! Round-trip: 12 ms` (or whatever the latency is).

### Checklist for any new message type

- [ ] Define message format (fields, types)
- [ ] Client: send with `send_to_server()` (or action bar trigger, or `_process()` input)
- [ ] Client: add command keyword to `command_keywords` array if using a `/command`
- [ ] Server: add `"type_name"` case in `handle_message()` match block
- [ ] Server: write handler function with validation
- [ ] Server: send response via `send_to_peer()`
- [ ] Client: add response type case in `handle_server_message()` match block
- [ ] Client: update UI (display text, update bars, change mode, etc.)
- [ ] If the response triggers a UI mode change, follow the Player-Visible Output Rule (see CLAUDE.md)

---

## 10. Common Networking Pitfalls

### Pitfall 1: Message arrives while client is in wrong mode (THE BIG BUG)

This is the most common and most subtle networking bug in the project. Here is the scenario:

1. Player opens their inventory. The `game_output` panel shows the inventory list.
2. Player uses an item. Client sends `{"type": "inventory_use", "index": 3}`.
3. Server processes the use and sends back a `"text"` message: `"You drank a Health Potion! +50 HP"`.
4. Server **also** sends a `"character_update"` with the new HP value.
5. Client receives the `"text"` message and displays it. Player sees "+50 HP" briefly.
6. Client receives the `"character_update"`. The handler sees `inventory_mode == true` and calls `display_inventory()`, which **clears** `game_output` and redraws the inventory list.
7. The "+50 HP" message is gone. The player never sees it.

**The fix:** State flags that prevent specific UI refreshes. See the "Player-Visible Output Rule" section in CLAUDE.md for the full pattern. The short version: set a flag like `awaiting_item_use_result = true` before sending the request, check that flag in the `character_update` handler to skip the refresh, and clear it after the result is displayed.

### Pitfall 2: Server sends multiple messages rapidly

A single server action can generate 2-5 messages in rapid succession. The client might receive all of them in a single `_process()` frame. Your code must not assume "one message per frame."

For example, after combat ends, the server might send:
```
{"type": "combat_end", "victory": true, ...}
{"type": "character_update", "character": {...}}
{"type": "text", "message": "You gained 150 XP!"}
{"type": "location", ...}
```

All four arrive in one read. `process_buffer()` will call `handle_server_message()` four times in a row within the same frame. Each handler must work correctly regardless of what was handled before it in that frame.

### Pitfall 3: Disconnect detection

TCP does not have instant disconnect detection. If the remote end disappears (network cable pulled, process killed), the local side might not know for seconds or minutes.

The project handles this by:
- Calling `connection.poll()` every frame to update the connection state.
- Checking `connection.get_status() != StreamPeerTCP.STATUS_CONNECTED` to detect disconnects.
- Running a periodic stale connection check on the server (`_check_stale_connections()` every 5 seconds) that kicks unauthenticated connections older than 90 seconds.

On the client side:

```gdscript
elif status == StreamPeerTCP.STATUS_ERROR:
    if connected:
        display_game("[color=#FF0000]Connection error![/color]")
        reset_connection_state()
```

### Pitfall 4: Never trust client data

The server must validate **everything**. Clients can send any JSON they want. Examples of what the server checks:

- **Authentication:** Most handlers start with `if not characters.has(peer_id): return` to reject messages from unauthenticated clients.
- **State validity:** `handle_move()` rejects moves during combat, gathering, or dungeon exploration.
- **Value ranges:** Item indices are bounds-checked against the actual inventory size. Directions are validated as legal numpad values.
- **Consistency:** When a player tries to equip an item, the server checks they actually own that item, it is the right type for the slot, and they meet any level requirements.

A compromised client could send `{"type": "move", "direction": 999}` or `{"type": "inventory_equip", "index": -1}`. The server must handle these gracefully (reject or ignore), never crash.

### Pitfall 5: Delta updates and desync

The server uses **delta updates** for `character_update` messages. Instead of sending the entire character dictionary every time, it computes the diff from the last sent state and only sends changed fields.

```json
// Full update (first time, or every 60 seconds as safety net):
{"type": "character_update", "character": {"level": 5, "current_hp": 95, "max_hp": 120, ...}, "full": true}

// Delta update (only changed fields):
{"type": "character_update", "character": {"current_hp": 87}, "full": false}
```

The client merges deltas into its stored `character_data`:

```gdscript
if is_full:
    _set_character_data(message.character)       # Replace entirely
else:
    _merge_character_delta(message.character)     # Merge changed fields
```

If a delta is lost or misapplied, the client's state can become inconsistent with the server. The safety net is a **forced full update every 60 seconds** (`FULL_UPDATE_INTERVAL`), which resets any accumulated drift.

### Pitfall 6: JSON float vs integer keys

JSON stores all numbers as floats. When the client or server parses `{"tier": 1}`, the value `1` becomes `1.0` (a float). But GDScript dictionary constants use integer keys:

```gdscript
const TIER_DATA = {1: "Bronze", 2: "Silver", 3: "Gold"}
```

`TIER_DATA.has(1.0)` returns `false` because `1` (int) and `1.0` (float) are different keys in GDScript. Always cast numeric values from JSON when using them as dictionary keys:

```gdscript
var tier = int(item.get("tier", 0))  # Cast to int!
if TIER_DATA.has(tier):
    # Now works correctly
```

### Pitfall 7: Serialization key mismatches

When the server serializes data for sending and the client reads it back, the key names must match exactly. A common bug:

```gdscript
# Server (sending):
monster_data["xp_reward"] = 150

# Client (receiving):
var xp = state.get("experience_reward", 0)  # WRONG KEY NAME -- always returns 0
```

Always grep the codebase for a key name before choosing it, and always use `.get("key", default)` instead of direct dictionary access (`dict.key`) for any data that crossed the network.

---

## Summary

The networking architecture of Phantom Badlands is deliberately simple:

1. **Transport:** Raw TCP sockets (`StreamPeerTCP` / `TCPServer`).
2. **Framing:** Newline-delimited JSON (with optional binary framing + gzip compression).
3. **Routing:** A `"type"` field in every message, matched to handler functions.
4. **Security:** Rate limiting, buffer limits, brute-force protection, server-side validation.

Every networked feature follows the same pattern:
- Client sends a request dictionary with `send_to_server()`.
- Server receives it in `handle_message()`, routes to a handler, validates, processes.
- Server sends one or more response dictionaries with `send_to_peer()`.
- Client receives them in `handle_server_message()`, updates the UI.

The complexity is not in the networking itself -- it is in the game logic inside each handler and in the careful management of client-side UI state to prevent incoming messages from clobbering what the player is looking at.
