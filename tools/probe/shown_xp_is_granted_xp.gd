extends SceneTree
## Owner sheet 2026-10-13, item 43: "Not sure the XP it shows you get when crafting something matches what
## the job actually gets." The craft result reported the amount OFFERED to add_experience / add_job_xp, but
## both apply a multiplier on the way in (race x Sanctuary x Mentee; committed-job +50%). The functions now
## return what they granted and the two craft sites report that. This pins the returned number to the real
## change in the character's bars, and the server sites to using it.
const CharacterScript := preload("res://shared/character.gd")
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _init() -> void:
	# character XP: Human (+race bonus) with a Sanctuary xp bonus, so the multiplier is not 1.0
	var ch = CharacterScript.new()
	ch.initialize("Probe", "Fighter", "Human")
	ch.house_bonuses["xp_bonus"] = 5
	var before: int = ch.experience
	var r: Dictionary = ch.add_experience(10)
	ck(not bool(r.get("leveled_up", false)), "no level-up muddying the delta")
	ck(int(r.get("xp_gained", -1)) == ch.experience - before, "add_experience reports the XP the bar really moved by (%d vs %d)" % [int(r.get("xp_gained", -1)), ch.experience - before])
	ck(int(r.get("xp_gained", -1)) != 10, "...and that is NOT the 10 that was offered (multiplier is live: got %d)" % int(r.get("xp_gained", -1)))
	# job XP: committed specialty job pays +50%
	var cj = CharacterScript.new()
	cj.initialize("Probe2", "Fighter", "Human")
	cj.specialty_job = "blacksmith"
	cj.specialty_job_committed = true
	var jb: int = int(cj.job_xp.get("blacksmith", 0))
	var jr: Dictionary = cj.add_job_xp("blacksmith", 20)
	var moved: int = int(cj.job_xp.get("blacksmith", 0)) - jb
	if not bool(jr.get("leveled_up", false)):
		ck(int(jr.get("xp_granted", -1)) == moved, "add_job_xp reports the job XP the bar really moved by (%d vs %d)" % [int(jr.get("xp_granted", -1)), moved])
	ck(int(jr.get("xp_granted", -1)) == 30, "a committed job pays 20 offered as 30 granted (got %d)" % int(jr.get("xp_granted", -1)))
	# the server's two craft sites must report the granted figures (statements, not prose)
	var src := FileAccess.get_file_as_string("res://server/server.gd")
	var a := "craft_char_xp = int(character.add_experience(craft_char_xp).get(\"xp_gained\", craft_char_xp))"
	var b := "job_xp_gained = int(job_result.get(\"xp_granted\", job_xp_gained))"
	ck(src.count(a) == 2, "both craft sites report the character XP granted (%d of 2)" % src.count(a))
	ck(src.count("\n\t\t\t\t" + b) == 2, "both craft sites report the job XP granted (%d of 2)" % src.count("\n\t\t\t\t" + b))
	print("\n[SHOWNXP] %s" % ("PASS" if fails == 0 else "FAIL - %d" % fails))
	quit(0 if fails == 0 else 1)
