extends SceneTree
## Found 2026-10-14 comparing the simulator's L91 Sorcerer with the rank-1 Sorcerer's death record
## (live INT 205 / CON 57; reference INT 107 / CON 9). `level_up()` TRUNCATED fractional per-level
## stat gains and granted no stat point; `add_experience()` accumulated them and granted one. The
## reference player is built with `level_up()`. Both paths now share `_apply_level_stat_gains()`.
const CharacterScript = preload("res://shared/character.gd")
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _via_xp(klass: String, to_level: int):
	var c = CharacterScript.new()
	c.initialize("X", klass, "Dwarf")
	while c.level < to_level:
		c.add_experience(c.experience_to_next_level)
	return c

func _via_level_up(klass: String, to_level: int):
	var c = CharacterScript.new()
	c.initialize("X", klass, "Dwarf")
	while c.level < to_level:
		c.level_up()
	return c

func _init() -> void:
	for klass in ["Sorcerer", "Fighter", "Ranger"]:
		var a = _via_xp(klass, 60)
		var b = _via_level_up(klass, 60)
		var same: bool = a.strength == b.strength and a.constitution == b.constitution and a.dexterity == b.dexterity \
			and a.intelligence == b.intelligence and a.wisdom == b.wisdom and a.wits == b.wits
		ck(same, "%s L60: level_up() and the XP path give the same stats (STR %d/%d CON %d/%d DEX %d/%d INT %d/%d)" % [klass, a.strength, b.strength, a.constitution, b.constitution, a.dexterity, b.dexterity, a.intelligence, b.intelligence])
		ck(a.unspent_stat_points == b.unspent_stat_points, "%s: same stat-point bank (%d / %d)" % [klass, a.unspent_stat_points, b.unspent_stat_points])
	# The Sorcerer's small gains are no longer lost.
	var s = _via_level_up("Sorcerer", 91)
	ck(s.constitution >= 30, "a level_up() Sorcerer's CON grows (L91 CON %d; it was 9, i.e. none, before)" % s.constitution)
	ck(s.intelligence >= 200, "...and INT lands near what a real L91 Sorcerer had (INT %d vs the live record's 205)" % s.intelligence)
	# Opting out of auto-spend banks the point instead, on either path.
	var o = CharacterScript.new()
	o.initialize("X", "Fighter", "Human")
	o.auto_spend_stats = false
	for i in 9:
		o.level_up()
	ck(o.unspent_stat_points == 9, "auto-spend OFF: level_up() banks the points (%d)" % o.unspent_stat_points)
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
