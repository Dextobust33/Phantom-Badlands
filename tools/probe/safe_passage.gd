extends SceneTree
## ⛑ THE SAFE PASSAGE SCROLL — the first of the Scribe's items.
##
## Scribing's agreed identity (owner, 2026-09-18): *the crafter who makes the world survivable*.
## Every item it makes reduces a RISK or a COST rather than adding power, which keeps it out of the
## weapon/armour balance question entirely and means it can never become mandatory — the failure
## mode of a crafter that makes power.
##
## ⛑ SIZED AGAINST THE MEASURED ROAD EFFECT, not invented. Roads already cut encounters from 67.2
## per 200 steps to 6.7, so this is the portable version of a road for the ground between them —
## deliberately not longer-lasting or safer than one.
##
## Run:
##   godot --headless --path . --script res://tools/probe/safe_passage.gd

const CD := preload("res://shared/crafting_database.gd")
const Char := preload("res://shared/character.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	print("===== THE RECIPES EXIST AND ARE SCRIBING =====")
	var found: Array = []
	for rid in CD.RECIPES:
		var r: Dictionary = CD.RECIPES[rid]
		var e = r.get("effect", null)
		if e is Dictionary and e.has("safe_passage"):
			found.append({"id": String(rid), "name": String(r.get("name", rid)),
				"steps": int(e.get("safe_passage", 0)), "skill": int(r.get("skill_required", 0)),
				"is_scribe": int(r.get("skill", -1)) == CD.CraftingSkill.SCRIBING})
	ck(found.size() >= 2, "there is a ladder, not a single scroll (%d)" % found.size())
	for f in found:
		print("    %-28s %3d steps, skill %d" % [String(f["name"]), int(f["steps"]), int(f["skill"])])
		ck(bool(f["is_scribe"]), "  %s is a Scribing recipe" % String(f["name"]))
		ck(String(f["name"]).to_lower().find("passage") >= 0,
			"  ...and its name says what it does")
	# The ladder must actually climb, or the higher recipe is a worse deal for more skill -
	# the exact fault found in Prismatic Elixir during the potion cull.
	if found.size() >= 2:
		found.sort_custom(func(a, b): return int(a["skill"]) < int(b["skill"]))
		ck(int(found[found.size() - 1]["steps"]) > int(found[0]["steps"]),
			"more skill buys more steps (%d -> %d)" % [int(found[0]["steps"]), int(found[found.size() - 1]["steps"])])

	print("\n===== THE CHARACTER CARRIES IT, AND IT SURVIVES A LOGOUT =====")
	var c = Char.new()
	c.initialize("probe", "Wizard", "Human")
	ck(c.safe_passage_steps == 0, "a fresh character has none")
	c.safe_passage_steps = 37
	var data: Dictionary = c.to_dict() if c.has_method("to_dict") else {}
	ck(data.has("safe_passage_steps") and int(data["safe_passage_steps"]) == 37,
		"it serialises (a scroll paid for with materials must not evaporate on logout)")

	print("\n===== THE SERVER SPENDS A STEP AND SKIPS THE ROLL =====")
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	ck(srv.find("elif character.safe_passage_steps > 0:") >= 0,
		"movement checks it BEFORE rolling an encounter")
	ck(srv.find("character.safe_passage_steps -= 1") >= 0, "...and spends a step")
	# ⛑ Spent whether or not an encounter was due: decrementing only on a roll that WOULD have
	# fired makes the scroll last wildly different lengths depending on terrain, and "40 steps"
	# has to mean 40 steps or a player cannot plan with it.
	ck(srv.find("if character.safe_passage_steps == 0:") >= 0,
		"...and says so when it runs out, rather than going quiet")
	ck(srv.find('elif effect.has("safe_passage"):') >= 0, "using the scroll grants the steps")
	ck(srv.find("character.safe_passage_steps += _sp_steps") >= 0,
		"...and ADDS, so a second scroll never throws away the remainder of the first")

	print("")
	if fails == 0:
		print("[PROBE] PASS the wilderness can be paid to look away")
	else:
		print("[PROBE] FAIL %d check(s)" % fails)
	quit(1 if fails > 0 else 0)
