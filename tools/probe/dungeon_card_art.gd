extends SceneTree
## ⛑ DOES EVERY DUNGEON CARD HAVE A FACE?
##
## `companion_card_art_bbcode` returned art for `companion_card_` ids and "" for everything else,
## so every dungeon card drew a blank art box. Four blanks before the full 53-card pass; 53 after
## it, which would have made "no picture" the most common card face in the collection.
##
## A blank art box is the quietest kind of missing content: the card works, the layout is fine,
## and nothing anywhere reports it. So this asks all 106 collectible cards for their art and
## fails on any that has none.
##
## Run:
##   godot --headless --path . --script res://tools/probe/dungeon_card_art.gd

const DT := preload("res://shared/drop_tables.gd")
const DDB := preload("res://shared/dungeon_database.gd")
const CSP := preload("res://client/combat_scene_panel.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	print("===== 1. EVERY DUNGEON CARD DRAWS SOMETHING =====")
	var blank: Array = []
	var ok := 0
	for slug in DT.DUNGEON_CARD_DATA.keys():
		var cid := "dungeon_card_" + String(slug)
		var art: String = CSP.card_art_bbcode(cid)
		if art.strip_edges() == "":
			var d: String = String(DT.DUNGEON_CARD_DATA[slug].get("dungeon", ""))
			blank.append("%s (%s -> %s)" % [slug, d,
				String(DDB.get_dungeon(d).get("boss_egg", "?"))])
		else:
			ok += 1
	for b in blank:
		print("           BLANK: " + String(b))
	print("           %d/%d dungeon cards have art" % [ok, DT.DUNGEON_CARD_DATA.size()])
	ck(blank.is_empty(), "no dungeon card draws an empty box (%d blank)" % blank.size())

	print("\n===== 2. AND COMPANION CARDS STILL DO =====")
	# The change widened a function that companion cards depend on. Proving the new path works
	# says nothing about whether the old one survived.
	var cblank: Array = []
	var cok := 0
	for slug in DT.COMPANION_CARD_DATA.keys():
		var cid := "companion_card_" + String(slug)
		if CSP.card_art_bbcode(cid).strip_edges() == "":
			cblank.append(String(slug))
		else:
			cok += 1
	for b in cblank:
		print("           BLANK: " + String(b))
	print("           %d/%d companion cards have art" % [cok, DT.COMPANION_CARD_DATA.size()])
	ck(cblank.is_empty(), "companion card art is unchanged (%d blank)" % cblank.size())

	print("\n===== 3. IT IS THE RIGHT MONSTER =====")
	# Art that resolves is not art that is correct - the lookup goes card -> dungeon -> boss
	# SPECIES, and a boss's own NAME ("Goblin King") has no art while its species does.
	var bad: Array = []
	for slug in ["venom_fang", "filthbite", "all_things_stop"]:
		if not DT.DUNGEON_CARD_DATA.has(slug):
			continue
		var d: String = String(DT.DUNGEON_CARD_DATA[slug].get("dungeon", ""))
		var species: String = String(DDB.get_dungeon(d).get("boss_egg", ""))
		var want: String = MonsterArt.get_monster_ascii_art(species)
		var got: String = CSP.card_art_bbcode("dungeon_card_" + slug)
		print("           %-16s %-22s -> %s" % [slug, species, "matches" if want != "" and want in got else "DIFFERENT"])
		if want == "" or not (want in got):
			bad.append("%s should show %s" % [slug, species])
	ck(bad.is_empty(), "the art is the dungeon's own boss species (%d wrong)" % bad.size())

	print("\n===== 4. ONE IMPLEMENTATION, TWO NAMES =====")
	# The old name is kept for anything reaching it through `has_method`. It must FORWARD, not be
	# a second copy - a second copy is how the two faces of one card drift apart.
	var src := FileAccess.get_file_as_string("res://client/combat_scene_panel.gd")
	var i := src.find("static func companion_card_art_bbcode")
	var body := src.substr(i, 400) if i >= 0 else ""
	ck(i >= 0, "the old name still exists for existing callers")
	ck(body.contains("return card_art_bbcode(card_name)"),
		"and it forwards rather than duplicating the lookup")
	ck(not body.contains("MonsterArt.get_monster_ascii_art"),
		"  (no second copy of the art lookup under the old name)")

	print("\n===== VERDICT =====")
	print("  all checks PASS" if fails == 0 else "  %d check(s) FAIL" % fails)
	quit(1 if fails > 0 else 0)
