extends SceneTree
## ⛑ SMITE'S DAMAGE REDUCTION IS REAL NOW - AND IT REACHES EVERY ATTACK.
##
## An Eternal player's Smite did `target.add_buff("smite_debuff", 25, 10)` with the comment
## *"-25% damage for 10 rounds"*, and that line was the ONLY reference to the key in the whole
## codebase. The poison half of Smite worked. The damage half had never existed, for as long as
## Smite has.
##
## Three things have to hold, and each was a way to get this wrong:
##
##   1. It applies to ABILITIES. The obvious place to put it was beside the five
##      `get_buff_value("damage")` reads - but those are per-ability (magic bolt, blast,
##      cataclysm, unmaking, basic attacks), so a penalty there would have reached five cards and
##      silently missed every other one. It goes in the shared ability funnel instead.
##   2. It applies to BASIC ATTACKS, which take a different path entirely.
##   3. It SURVIVES A POSITIVE DAMAGE BUFF. This is the one that killed the tempting one-liner:
##      reusing the `damage` key with a value of -25 reads correctly, because `get_buff_value`
##      sums - but `add_buff` refreshes an existing entry with `max(buff.value, value)`, so a
##      -25 arriving while War Cry is up is thrown away and the player takes no penalty at all.
##      A separate key is not tidiness; it is the fix.
##
## Run:
##   godot --headless --path . --script res://tools/probe/smite_damage_penalty.gd

const CM := preload("res://shared/combat_manager.gd")
const Char := preload("res://shared/character.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _mk() -> Character:
	var c: Character = Char.new()
	c.name = "Probe"
	c.class_type = "Warrior"
	c.level = 20
	return c


func _init() -> void:
	var cm = CM.new()

	print("===== 1. EVERY ABILITY, THROUGH THE SHARED FUNNEL =====")
	# ⛑ SAMPLED, NOT COMPARED ONCE. The first version of this called the funnel a single time
	# each and read 1250 against 750 as a 40% cut. The funnel ROLLS: abilities crit, and they
	# glance for 60% on a failed accuracy check. One call against one call compares two dice.
	var clean: Character = _mk()
	var smited: Character = _mk()
	smited.add_buff("damage_penalty", 25, 10)
	var monster2 := {"name": "Dummy", "defense": 0, "level": 20, "empowered_mods": [], "current_hp": 99999}
	var n := 4000
	var sum_clean := 0
	var sum_smited := 0
	for i in range(n):
		sum_clean += cm.apply_ability_damage_modifiers(1000, 20, monster2, clean, {}, null)
		sum_smited += cm.apply_ability_damage_modifiers(1000, 20, monster2, smited, {}, null)
	var mean_clean: float = float(sum_clean) / float(n)
	var mean_smited: float = float(sum_smited) / float(n)
	var pct: float = 100.0 * (1.0 - mean_smited / maxf(1.0, mean_clean))
	print("           ability damage over %d casts: clean %.1f, smited %.1f" % [n, mean_clean, mean_smited])
	ck(mean_smited < mean_clean, "a smited attacker deals less ability damage")
	# Crit and glance are symmetric noise on BOTH samples, so the gap is the penalty. 2pp of slack
	# for the sampling error rather than a tight band that would fail on a quiet day.
	ck(abs(pct - 25.0) <= 2.0, "...and it is the 25%% the ability claims (measured %.1f%%)" % pct)

	print("\n===== 2. AND IT SURVIVES A POSITIVE DAMAGE BUFF =====")
	# THE TRAP. `add_buff` refreshes with max(value), so a penalty sharing the `damage` key with
	# War Cry would be discarded outright. Prove the two coexist.
	var both: Character = _mk()
	both.add_buff("damage", 50, 10)
	both.add_buff("damage_penalty", 25, 10)
	ck(both.get_buff_value("damage") == 50, "the positive buff is intact (%d)" % both.get_buff_value("damage"))
	ck(both.get_buff_value("damage_penalty") == 25,
		"...and the penalty is NOT swallowed by it (%d)" % both.get_buff_value("damage_penalty"))
	var sum_both := 0
	for i in range(n):
		sum_both += cm.apply_ability_damage_modifiers(1000, 20, monster2, both, {}, null)
	var mean_both: float = float(sum_both) / float(n)
	ck(mean_both < mean_clean,
		"a buffed AND smited attacker still pays the penalty (%.1f vs %.1f)" % [mean_both, mean_clean])

	print("\n===== 2b. AND THE BASIC-ATTACK PATH, WHICH IS A DIFFERENT FUNNEL =====")
	# Abilities and attacks take separate routes - `analyze_bonus` is applied in both places
	# for exactly this reason. A penalty in one funnel only would be half a fix, and the half
	# it missed would be invisible to section 1.
	var atk_clean := 0
	var atk_smited := 0
	for i in range(n):
		atk_clean += int(cm.calculate_damage(clean, monster2, {}).get("damage", 0))
		atk_smited += int(cm.calculate_damage(smited, monster2, {}).get("damage", 0))
	var m_atk_clean: float = float(atk_clean) / float(n)
	var m_atk_smited: float = float(atk_smited) / float(n)
	var apct: float = 100.0 * (1.0 - m_atk_smited / maxf(1.0, m_atk_clean))
	print("           basic attacks over %d swings: clean %.1f, smited %.1f" % [n, m_atk_clean, m_atk_smited])
	ck(abs(apct - 25.0) <= 2.0, "basic attacks pay the same 25%% (measured %.1f%%)" % apct)

	print("\n===== 3. THE KEY THAT DID NOTHING IS GONE FROM THE SERVER =====")
	# Source scan, and honest about being one: it proves the old key is no longer written, not
	# that the new one is wired - sections 1 and 2 do that by calling the real funnel.
	var f := FileAccess.open("res://server/server.gd", FileAccess.READ)
	var src := f.get_as_text()
	f.close()
	ck(not src.contains('add_buff("smite_debuff"'), "Smite no longer writes the dead key")
	ck(src.contains('add_buff("damage_penalty"'), "...it writes the one both funnels consume")

	print("\n===== 4. AND NOTHING ELSE STILL WRITES THE DEAD KEY =====")
	# Looks for the WRITE, not the word. The first version grepped for "smite_debuff" and failed
	# on combat_manager - because the comment explaining the fix names the key it replaced. A
	# detector that trips on its own documentation is noise.
	for path in ["res://shared/combat_manager.gd", "res://shared/character.gd", "res://client/client.gd"]:
		var f2 := FileAccess.open(path, FileAccess.READ)
		var t := f2.get_as_text()
		f2.close()
		ck(not t.contains('add_buff("smite_debuff"'), "%s never writes it" % path.get_file())

	print("\n===== VERDICT =====")
	print("  all checks PASS" if fails == 0 else "  %d check(s) FAIL" % fails)
	quit(0)
