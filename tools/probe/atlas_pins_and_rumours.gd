extends SceneTree
## ⛑ THE THREE THINGS THE OWNER DECIDED, ASSERTED ON THE REAL PANEL.
##
## Owner 2026-09-17, on merging the Atlas into the quest board: the Atlas **shows** quests and
## never accepts them, a quest **pins its dungeon**, and rumours **display** and name where they
## were heard (reading (a) - the accept still happens at a post).
##
## A live capture could not show any of it: the test character had no dungeon quest and no
## rumours, so the pinned section and the rumour section were simply absent from the frame. An
## empty section looks exactly like a working one, which is the shape that has cost this project
## repeatedly - so the panel is driven directly with a payload that contains both.
##
## It builds the REAL `QuestBoardPanel` and calls the REAL `open_atlas`, then walks the resulting
## node tree. Nothing here re-implements the renderer.
##
## Run:
##   godot --headless --path . --script res://tools/probe/atlas_pins_and_rumours.gd

const PanelScript := preload("res://client/quest_board_panel.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _all_text(n: Node, out: Array) -> void:
	"""Every string the panel put on screen, flattened - labels and button captions alike."""
	if n is RichTextLabel:
		out.append((n as RichTextLabel).get_parsed_text())
	elif n is Button:
		out.append("[button]" + (n as Button).text + ("[disabled]" if (n as Button).disabled else ""))
	for c in n.get_children():
		_all_text(c, out)


func _init() -> void:
	var panel = PanelScript.new()
	root.add_child(panel)
	# _ready() builds the layout, and it has NOT fired yet: inside a SceneTree _init the root
	# window is not far enough along for add_child to deliver NOTIFICATION_READY. Without this
	# the first run reported eleven failures that were all one null label.
	if panel._title_label == null:
		panel._build_layout()

	var payload := {
		"discovered": 2, "total": 53,
		"cartography_rank": 4, "cartography_max_rank": 8, "cartography_sense_rank": 8,
		"cartography_xp": 300, "cartography_next_xp": 500,
		"at_post": false,
		"entries": [
			# a DISCOVERED dungeon that a quest points at
			{"id": "wolf_den", "state": 3, "tier": 2, "rank": 4, "name": "Wolf Den",
			 "level_min": 6, "level_max": 12, "clears": 1,
			 "monsters": ["Wolf", "Giant Rat"], "boss": "Alpha Wolf", "companion": "Wolf"},
			# a DISCOVERED dungeon nothing wants
			{"id": "goblin_caves", "state": 3, "tier": 1, "rank": 2, "name": "Goblin Caves",
			 "level_min": 1, "level_max": 10, "clears": 0,
			 "monsters": ["Goblin"], "boss": "Goblin King", "companion": "Goblin"},
			# a RUMOUR, with the post it was heard at
			{"id": "vampire_crypt", "state": 1, "tier": 5, "rank": 0, "from_post": "Iron Peak"},
		],
		"pins": {
			"wolf_den": {"name": "Clear the Wolf Den", "progress": 0, "target": 1, "post": "Haven"},
		},
	}
	panel.open_atlas(payload)

	var text: Array = []
	_all_text(panel, text)
	var blob: String = "\n".join(text)

	print("===== 1. A QUEST PINS ITS DUNGEON =====")
	ck(blob.contains("Wanted"), "there is a Wanted section")
	ck(blob.contains("Clear the Wolf Den"), "...naming the quest")
	ck(blob.contains("0 / 1"), "...with its progress")
	ck(blob.contains("hand in at Haven"), "...and WHERE to hand it in, since this tab cannot")
	# The pinned dungeon must appear ABOVE the unpinned one: it is what the player opened the
	# screen to find, so grade order does not get to bury it.
	var i_wolf: int = blob.find("Wolf Den")
	var i_gob: int = blob.find("Goblin Caves")
	ck(i_wolf >= 0 and i_gob >= 0 and i_wolf < i_gob,
		"the pinned dungeon sorts above the unpinned one")

	print("\n===== 2. RUMOURS DISPLAY, AND NAME WHERE THEY WERE HEARD =====")
	ck(blob.contains("Rumours"), "there is a Rumours section")
	ck(blob.contains("heard at Iron Peak"), "...and the row names the post")
	ck(not blob.contains("Vampire"), "a rumour does NOT leak the dungeon's name")

	print("\n===== 3. THE ATLAS SHOWS QUESTS AND NEVER ACCEPTS THEM =====")
	# The owner's rule, as a property of the screen rather than a promise in a comment: the verb
	# on this tab is Locate. An Accept or Turn In button here would move the accept off the post.
	ck(not blob.contains("[button]Accept"), "no Accept button on the Dungeons tab")
	ck(not blob.contains("[button]Turn In"), "no Turn In button on the Dungeons tab")
	ck(blob.contains("[button]Locate"), "Locate IS the verb here")
	# ...and it is correctly refused away from a post, rather than offered and then failing.
	ck(blob.contains("[button]Locate[disabled]"),
		"Locate is disabled away from a post, not silently broken")

	print("\n===== 4. AND BOTH DOORS ARE ALWAYS PRESENT =====")
	ck(blob.contains("[button]Quests"), "the Quests tab is reachable from here")
	ck(blob.contains("[button]Dungeons[disabled]"),
		"the Dungeons tab shows as the one you are on")

	print("\n===== VERDICT =====")
	print("  all checks PASS" if fails == 0 else "  %d check(s) FAIL" % fails)
	quit(0)
