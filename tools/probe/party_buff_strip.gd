extends SceneTree
## ⛑ EVERY PARTY MEMBER SHOWS THEIR OWN BUFFS, AND A DOUBLED BUFF SAYS SO.
##
## The player has had a status strip since solo combat. A teammate's card carried name, HP bar and
## resource bar and nothing else — so in a party you could watch an ally dying and have no way to
## see WHY: no poison, no blind, no shield, no mitigation. The member payload simply did not carry
## the fields.
##
## ⛑ AND THIS HAS GONE MISSING ONCE BEFORE, THE SAME WAY. On 2026-09-15 the whole strip was absent
## from party fights because only the SOLO combat_state carried these fields; the fix was to make
## `status_display_fields` one builder for both. The member payload now calls that same builder, so
## this probe checks the connection rather than the appearance — a second per-member status builder
## is exactly how the two would drift apart again.
##
## Run:
##   godot --headless --path . --script res://tools/probe/party_buff_strip.gd

const ScenePanel = preload("res://client/combat_scene_panel.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	print("===== THE SERVER SENDS IT, THROUGH THE SHARED BUILDER =====")
	var cm := FileAccess.get_file_as_string("res://shared/combat_manager.gd")
	ck(cm.find('"status": status_display_fields(ch, _party_member_view(combat, pid))["player_status"]') >= 0,
		"the member payload carries `status`, built by `status_display_fields`")
	ck(cm.count("func status_display_fields(") == 1,
		"...and there is exactly ONE such builder (a second is how solo and party drift)")

	print("\n===== THE CLIENT DRAWS IT, WITH THE PLAYER'S OWN CHIP BUILDER =====")
	var p = ScenePanel.new()
	get_root().add_child(p)
	await process_frame
	ck(p.has_method("_build_player_status_bbcode"), "the chip builder exists")

	# A member carrying two effects, one of them DOUBLED.
	var status := {
		"poison_turns": 3, "poison_damage": 12,
		"blind_turns": 0, "cloak": false, "forcefield_shield": 250,
		"buffs": [
			{"type": "iron_skin", "value": 20, "duration": 4},
			{"type": "iron_skin", "value": 20, "duration": 6},
			{"type": "haste", "value": 0, "duration": 2},
		],
		"mitigation_pct": 0, "mitigation_sources": [],
	}
	var bb: String = p._build_player_status_bbcode(status)
	var seen := bb.replace("[", "\n[")   # crude, but the assertions below read the payload not the markup
	print("  rendered: " + bb.substr(0, 150).replace("\n", " "))
	ck(bb.find("250") >= 0, "the member's shield value is drawn")
	ck(bb.find("12") >= 0 and bb.to_lower().find("poison") >= 0, "...and their poison")

	print("\n===== STACKING =====")
	# ⛑ GROUPED, NOT DE-DUPLICATED. Two identical chips read as a rendering glitch; dropping one
	# hides that the buff is worth twice as much. One chip, with the count.
	var occurrences := bb.to_lower().count("iron")
	ck(occurrences == 1, "a doubled buff draws ONE chip, not two (found %d)" % occurrences)
	ck(bb.find("\u00d72") >= 0, "...and it is marked \u00d72")
	ck(bb.find("6T") >= 0, "...showing the LONGEST remaining duration (6T, not 4T)")
	# The control: a single buff must NOT gain a count.
	var single := p._build_player_status_bbcode({
		"buffs": [{"type": "haste", "value": 0, "duration": 2}],
		"poison_turns": 0, "blind_turns": 0, "cloak": false,
		"forcefield_shield": 0, "mitigation_pct": 0, "mitigation_sources": [],
	})
	ck(single.find("\u00d7") < 0, "a single buff carries no count (the control)")

	print("")
	if fails == 0:
		print("[PROBE] PASS party members show their own status, stacks included")
	else:
		print("[PROBE] FAIL %d check(s)" % fails)
	quit(1 if fails > 0 else 0)
