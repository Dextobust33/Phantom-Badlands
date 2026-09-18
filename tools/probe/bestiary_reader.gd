extends SceneTree
## ⛑ THE BESTIARY IS REACHABLE WHERE IT MATTERS, AND SAYS SOMETHING USEFUL WHEN IT GETS THERE.
##
## Owner 2026-09-18: *"it may be beneficial for us to add an inspect button or something in combat
## where if players have the bestiary for a certain monster they can view all the info on it while
## in or out of battle, and also compare that monster to others they know."*
##
## ⛑ THE PANEL ALREADY EXISTED AND WAS REACHABLE ONLY FROM THE MENU, out of combat — which is the
## wrong moment, because what a monster can DO matters while it is doing it. Sixth time in this arc
## that the capability was built and the route was not (party invite, Duel for Valor, the fight log,
## the death log, the bestiary page itself, now this).
##
## ⛑ AND THE CLIENT HAS NO MONSTER DATA. It carries `known_enemy_hp` — HP it has personally seen —
## and nothing else. So "compare this to what I know" could not be assembled client-side however the
## UI were written, and a panel comparing KILL COUNTS would answer a question nobody asked. The
## stats had to travel with the summary.
##
## Run:
##   godot --headless --path . --script res://tools/probe/bestiary_reader.gd

const BestiaryUI := preload("res://client/bestiary_panel.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	var cli := FileAccess.get_file_as_string("res://client/client.gd")
	var cmb := FileAccess.get_file_as_string("res://client/combat_scene_panel.gd")
	var mdb := FileAccess.get_file_as_string("res://shared/monster_database.gd")

	print("===== THE STATS TRAVEL =====")
	ck(mdb.find("func base_stats_for_name(") >= 0,
		"a species can be looked up by NAME (the bestiary only ever has a name)")
	ck(srv.find("func _enrich_bestiary_summary(") >= 0, "the summary is enriched before sending")
	for f in ["base_hp", "base_strength", "base_defense", "base_speed", "abilities", "has_page"]:
		ck(srv.find('e["%s"]' % f) >= 0, "  ...it carries %s" % f)

	print("\n===== A PAGE BEATS THE UPGRADE TIER =====")
	# The whole reason to craft one: buy the full entry for ONE species without buying the tier.
	ck(srv.find('e["has_page"] = persistence.has_bestiary_page(account_id, nm)') >= 0,
		"the server marks which species the account holds a page for")
	var pnl := FileAccess.get_file_as_string("res://client/bestiary_panel.gd")
	ck(pnl.find("if (level >= 2 or has_page) and int(entry.get(\"base_hp\", 0)) > 0:") >= 0,
		"...and a page shows the stats even at a locked upgrade level")
	ck(pnl.find('parts.append("[color=#DD99DD]%s[/color]" % ", ".join(names))') >= 0,
		"...and its ABILITIES, which is the part that changes how you fight it")

	print("\n===== IT OPENS FROM THE FIGHT, ON THE RIGHT CREATURE =====")
	ck(cmb.find("signal bestiary_requested(monster_name: String)") >= 0, "the combat panel can ask")
	ck(cmb.find('_bestiary_button.visible = _monster_name != ""') >= 0,
		"...the button shows whenever there is a named foe")
	# ⛑ Deliberately NOT gated on owning a page: a player who knows nothing should be able to
	# press it and be told so, which is the moment they learn the page exists.
	ck(pnl.find('unknown.text = "[color=#C8A24A]You have never killed a %s.') >= 0,
		"...and an unknown creature says so rather than showing a silent list")
	ck(cli.find("func _on_bestiary_requested(") >= 0, "the client routes it")
	ck(cli.find("bestiary_panel.open({\"level\": 0, \"entries\": [], \"unique_count\": 0, \"total_kills\": 0}, _bestiary_focus)") >= 0,
		"...and passes the focus through")

	print("\n===== FOCUS PINS IT TO THE TOP, BESIDE THE OTHERS =====")
	var p = BestiaryUI.new()
	get_root().add_child(p)
	await process_frame
	p.open({"level": 3, "unique_count": 2, "total_kills": 9, "entries": [
		{"name": "Goblin", "kills": 7, "highest_level": 4, "base_hp": 15, "base_strength": 8,
		 "base_defense": 5, "base_speed": 22, "has_page": false, "abilities": []},
		{"name": "Wight", "kills": 2, "highest_level": 30, "base_hp": 400, "base_strength": 60,
		 "base_defense": 30, "base_speed": 18, "has_page": true, "abilities": ["arcane_hoarder"]},
	]}, "Wight")
	await process_frame
	ck(p.visible, "the panel opens")
	var rows: Array = p._body_vbox.get_children()
	ck(rows.size() >= 2, "both creatures are listed - the comparison is the list itself (%d rows)" % rows.size())
	# The focused one must be FIRST, not merely present.
	var first_text := ""
	for r in rows:
		for c in r.get_children():
			if c is RichTextLabel:
				first_text = c.get_parsed_text()
				break
		if first_text != "":
			break
	ck(first_text.find("Wight") >= 0, "the focused creature is first (got '%s')" % first_text.substr(0, 40))
	ck(first_text.find("400") >= 0, "...showing its real stats, not its kill count alone")

	print("")
	if fails == 0:
		print("[PROBE] PASS you can ask what you are fighting, mid-fight")
	else:
		print("[PROBE] FAIL %d check(s)" % fails)
	quit(1 if fails > 0 else 0)
