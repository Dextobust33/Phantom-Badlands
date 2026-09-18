extends SceneTree
## ⛑ THE SCRIBE'S ITEMS — each reduces a RISK or a COST, none adds power.
##
## Owner-agreed identity 2026-09-18: *the crafter who makes the world survivable*. That is what
## keeps Scribing out of the weapon/armour balance question entirely and means it can never become
## mandatory — the failure mode of a crafter that makes power.
##
## ⛑ AND THE BESTIARY PAGE WAS ALREADY BUILT. A recipe with that exact id existed, revealing a
## RANDOM unknown monster's HP to the CHARACTER — which permadeath erases, so a page bought with
## materials was worth exactly one life. It was extended rather than duplicated: the foe in front
## of you first, and written to the ACCOUNT. Fifth shipped-but-unticked item found this way; the
## parser caught the duplicate id, which is luckier than it should have been.
##
## Run:
##   godot --headless --path . --script res://tools/probe/scribe_items.gd

const CD := preload("res://shared/crafting_database.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	var chr := FileAccess.get_file_as_string("res://shared/character.gd")
	var per := FileAccess.get_file_as_string("res://server/persistence_manager.gd")

	print("===== THE RECIPES EXIST, ONCE EACH =====")
	var names := {}
	for rid in CD.RECIPES:
		var r: Dictionary = CD.RECIPES[rid]
		if int(r.get("skill", -1)) == CD.CraftingSkill.SCRIBING:
			names[String(r.get("name", rid))] = int(r.get("skill_required", 0))
	for want in ["Safe Passage Scroll", "Remains Ledger", "Waypoint Seal", "Bestiary Page"]:
		ck(names.has(want), "%s is a Scribing recipe (skill %s)" % [want, str(names.get(want, "-"))])
	ck(CD.RECIPES.has("bestiary_page"), "the bestiary page kept its ORIGINAL id - not duplicated")

	print("\n===== REMAINS LEDGER: THE SEARCH BECOMES A WALK =====")
	# ⛑ A corpse does NOT lie where you died - it spawns at a random spot at HALF your distance
	# from origin, and the death notice gives a compass direction and a distance rounded to ten.
	ck(srv.find("func _latest_remains_for(") >= 0, "there is a lookup for your own remains")
	ck(srv.find('corpse["account_id"] = String(peers[peer_id].get("account_id", ""))') >= 0,
		"new corpses are stamped with the ACCOUNT - under permadeath the asker is a different character")
	ck(srv.find('elif String(c.get("account_id", "")) == "" and String(c.get("character_name", "")) == current_name:') >= 0,
		"...and pre-2026-09-18 corpses fall back to the character name rather than vanishing")
	ck(srv.find("func _remains_ledger_text(") >= 0, "it reports location AND contents")
	ck(srv.find('out += "[color=#9ACD32]Still on them:') >= 0,
		"...because knowing WHERE is only half the decision")

	print("\n===== WAYPOINT SEAL: ONE MARK, ONE RETURN =====")
	ck(chr.find("@export var waypoint_set: bool = false") >= 0, "the character carries one waypoint")
	ck(chr.find('waypoint_set = bool(data.get("waypoint_set", false))') >= 0, "...and it survives a logout")
	ck(srv.find("elif not character.waypoint_set:") >= 0, "first use marks the spot")
	ck(srv.find("character.waypoint_set = false") >= 0, "...second use spends it")
	# ⛑ Refused underground both ways: marking would store a coordinate that is not where the
	# player is, and returning would bypass every exit rule a dungeon has.
	ck(srv.find('"message": "[color=#FF6666]The seal will not take underground.') >= 0,
		"refused in a dungeon, so it cannot become a free escape")

	print("\n===== BESTIARY PAGE: IT OUTLIVES YOU =====")
	ck(per.find("func grant_bestiary_page(") >= 0, "the account can hold pages")
	ck(srv.find("persistence.grant_bestiary_page(String(peers[peer_id].get(\"account_id\", \"\")), chosen)") >= 0,
		"using a page writes to the ACCOUNT, not just the character")
	ck(srv.find("if _forced != \"\" and not character.knows_monster(_forced, 9999):") >= 0,
		"...and it records the foe in front of you before any random unknown")

	print("\n===== AND THEY GIVE THE ORPHANED MATERIALS SOMEWHERE TO GO =====")
	# Nine materials had no destination at all; five of them were wood.
	var used := {}
	for rid in CD.RECIPES:
		var m = CD.RECIPES[rid].get("materials", {})
		if m is Dictionary:
			for k in m.keys():
				used[String(k)] = true
	for orphan in ["silverleaf", "black_pearl", "ironwood", "worldtree_branch"]:
		ck(used.has(orphan), "  %s now has a recipe that wants it" % orphan)

	print("")
	if fails == 0:
		print("[PROBE] PASS the Scribe makes the world survivable")
	else:
		print("[PROBE] FAIL %d check(s)" % fails)
	quit(1 if fails > 0 else 0)
