extends SceneTree
## The per-class path value lever (PathDatabase.CLASS_SCALE): every numeric path effect of a class is multiplied by its entry; durations and counts never are;
## an absent class is exactly 1.0; the simulator override wins over the table.
const PD = preload("res://shared/path_database.gd")
const CharacterScript = preload("res://shared/character.gd")
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _build(klass: String):
	var ch = CharacterScript.new()
	ch.initialize("T", klass, "Human")
	ch.path_ranks = {"warrior_1_1": 4, "warrior_3_2": 1}   # +5% attack damage per rank; +2 round buffs (a duration)
	ch.path_nodes = ch.path_ranks.keys()
	ch._path_fx_dirty = true
	return ch

func _init() -> void:
	var table: Dictionary = PD.CLASS_SCALE
	ck(table.has("Paladin") and float(table["Paladin"]) != 1.0 and not table.has("Sage"), "the table scales the Paladin (and leaves Sage alone) (x%s)" % str(table.get("Paladin", "?")))
	var pal = _build("Paladin")
	var fig = _build("Sage")
	var s: float = PD.class_scale("Paladin")
	ck(abs(pal.get_path_effect_total("attack_damage_pct") - 20.0 * s) < 0.001, "a Paladin's four ranks of +5%% become %.1f%% (20 x %.2f)" % [pal.get_path_effect_total("attack_damage_pct"), s])
	ck(abs(fig.get_path_effect_total("attack_damage_pct") - 20.0) < 0.001, "a Sage, absent from the table, is exactly 20%")
	ck(pal.get_path_effect_total("buff_duration_bonus") == 2.0 and fig.get_path_effect_total("buff_duration_bonus") == 2.0, "a duration is never scaled (2 rounds for both)")
	pal.set_path_scale_override(1.0)
	ck(abs(pal.get_path_effect_total("attack_damage_pct") - 20.0) < 0.001, "the simulator override beats the table (back to 20%)")
	pal.set_path_scale_override(-1.0)
	ck(abs(pal.get_path_effect_total("attack_damage_pct") - 20.0 * s) < 0.001, "...and a negative override hands control back to the table")
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
