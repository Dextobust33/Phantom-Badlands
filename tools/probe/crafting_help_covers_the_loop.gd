extends SceneTree
## Does the crafting help actually cover the loop now, and are its numbers the REAL ones?
const CD := preload("res://shared/crafting_database.gd")
const DT := preload("res://shared/drop_tables.gd")
const CH := preload("res://shared/character.gd")
func _init() -> void:
	var cli := FileAccess.get_file_as_string("res://client/client.gd")
	var terms := ["rune", "enchant", "affix", "rework", "commission", "quality", "specialist",
		"commit", "reforge", "disenchant", "Masterwork", "salvage", "tool"]
	var missing: Array = []
	for t in terms:
		if cli.findn(t) < 0:
			missing.append(t)
	# The help TOPICS specifically, not the whole client.
	var i := cli.find('"title": "GATHERING"')
	var j := cli.find('"title": "GUARDS & TOWERS"')
	var topics := cli.substr(i, maxi(0, j - i)) if i >= 0 and j > i else ""
	print("crafting help topics: %d chars (was 1242 for one thin topic)" % topics.length())
	var gone: Array = []
	for t in terms:
		if topics.findn(t) < 0:
			gone.append(t)
	print("concepts still unmentioned: %s" % ("none" if gone.is_empty() else ", ".join(gone)))
	# ⛑ THE NUMBERS MUST BE GENERATED. A figure typed into help text is a second copy waiting to
	# go stale, and three constants moved on the day this was written.
	print("")
	print("generated values the help pulls from code:")
	print("  rework cap ............ %d  (DropTables.MAX_AFFIX_REROLLS)" % DT.MAX_AFFIX_REROLLS)
	print("  commit XP bonus ....... %d%%  (Character.COMMITTED_JOB_XP_BONUS)" % int(CH.COMMITTED_JOB_XP_BONUS * 100.0))
	var lo: Dictionary = CD.roll_quality_detailed(1, 35)
	var hi: Dictionary = CD.roll_quality_detailed(60, 35)
	print("  success 1 -> 60 ....... %d%% -> %d%%" % [int(lo.get("success_chance", 0)), int(hi.get("success_chance", 0))])
	print("  masterwork 1 -> 60 .... %s%% -> %s%%" % [str(lo.get("distribution", {}).get("masterwork", 0)), str(hi.get("distribution", {}).get("masterwork", 0))])
	if not gone.is_empty():
		print("[PROBE] FAIL the help still omits: %s" % ", ".join(gone))
		quit(1)
		return
	# ⛑ AND THE FIGURES MUST NOT BE TYPED. The first draft of this help wrote "5%% to 95%%" as
	# prose, which is exactly what the backlog entry for it warned against - three of the constants
	# behind this arc moved on the day it was written. Any literal skill figure in the topic text
	# is a second copy of a number the code already owns.
	if topics.find("_craft_skill_figure(") < 0:
		print("[PROBE] FAIL the crafting topic no longer generates its skill figures")
		quit(1)
		return
	print("[PROBE] PASS every concept in the gather-craft loop is covered, numbers generated")
	quit()
