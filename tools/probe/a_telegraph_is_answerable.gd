extends SceneTree
## ⛑ DOES A TELEGRAPHED BOSS HIT ACTUALLY GIVE YOU A TURN TO ANSWER IT?
##
## The design's constraint #4 (`docs/design/dungeon_revamp.md`): *"a telegraphed hit only lands next
## turn unless the player responds… **NO unavoidable damage**."*
##
## ⚡ IT WAS BEING BROKEN BY EVERY BOSS IN THE GAME. 19 cyclical bursts fired the instant
## `combat.round % N == 0`, subtracting HP directly and printing the message AFTERWARDS — a receipt,
## not a warning. Two constants described themselves as "telegraphed" and neither was.
##
## WHAT THIS ASSERTS, for every converted burst:
##   1. the round it used to land on now produces a WIND-UP and no damage
##   2. it lands on the NEXT monster turn
##   3. a player who braced takes measurably less than one who did not
##   4. stunning the boss CANCELS it outright
##
## ⛑ AND IT NAMES THE ONES STILL UNCONVERTED. A probe that only checks the converted set would
## report a clean pass while most bosses still hit out of nowhere, so the unconverted bursts are
## listed as a visible queue. That half is ADVISORY — the gate is that a converted burst behaves.
##
## Run:
##   godot --headless --path . --script res://tools/probe/a_telegraph_is_answerable.gd

const CombatManagerScript := preload("res://shared/combat_manager.gd")
const CharacterScript := preload("res://shared/character.gd")
const MonsterDB := preload("res://shared/monster_database.gd")

var _fails: Array = []

## The abilities that are deliberately NOT telegraphed, each judged against "is this a single big moment of damage the player could answer?"
## (owner 2026-10-22 closed the queue by deciding every one). A telegraphed heal, tick or aura is not a decision, and winding up everything would make
## every boss the same metronome. A NEW cyclical ability that is in neither this table nor TELEGRAPHED_BURSTS fails section 4: it has not been decided.
const NOT_BURSTS := {
	"boss_iron_discipline": "a heal (10%) - the answer is burst damage, not a guard",
	"boss_soul_forge": "a heal (15%)",
	"boss_temporal_rewind": "a heal (25%) that also clears its debuffs",
	"boss_contagion_aura": "a passive stacking tick, not a moment",
	"boss_coil_squeeze": "a passive stacking tick",
	"boss_decay": "a passive stacking tick",
	"boss_three_heads": "a steady chip every turn",
	"boss_triple_threat": "a rotating debuff, not damage",
	"boss_element_cycle": "a rotating debuff, not one blow",
	"boss_riddle_curse": "a persistent stacking debuff",
	"boss_chaotic_surge": "a random effect each turn; winding it up would remove the point of it",
	"boss_dragons_hoard": "strips ONE buff and grows the boss; a stacking effect",
	"boss_wind_shear": "a one-round damage debuff, shown the turn it applies",
	"boss_lullaby": "a status (skip a turn); stun-cancel already answers it through Web/stun rules",
	"boss_madness_aura": "a status over two turns",
	"boss_void_step": "the boss phases out and your next hit does nothing: it already warns, and the answer is what you cast, not a guard",
}

## State a burst needs before its own round can fire: stack bursts release on their LAST stack, Death Mark needs the mark on the player.
const SETUPS := {
	"boss_sonic_echo": {"sonic_echo_stacks": 3},
	"boss_infernal_curse": {"infernal_curse_stacks": 4},
	"boss_death_mark": {"player_death_marked": true},
}


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


## A boss carrying exactly one telegraphed ability, at a round where it is about to fire.
func _boss_fight(cm, db, ability: String, period: int) -> Dictionary:
	var ch = CharacterScript.new()
	ch.initialize("Probe", "Barbarian", "Human")   # no innate damage_reduction to muddy the read
	# ⚑ PINNED, NOT RANDOM. `generate_monster` rolls a random species AND random empowered modifiers,
	# and one of those is Juggernaut - "immune to stun, shrugs it off and acts anyway" (v0.9.651), which
	# is correct game behaviour and made check 3 ("a stun cancels it") fail about 1 run in 25 for a reason
	# that has nothing to do with the telegraph. Seeded per fight so a failure reproduces, and the monster
	# carries no modifiers: this probe is about the burst's wind-up, not the monster lottery.
	seed(hash("%s|%d" % [ability, period]))
	var mon: Dictionary = db.generate_monster(20, 20)
	mon["empowered_mods"] = []
	mon["abilities"] = [ability]
	mon["max_hp"] = 999999
	mon["current_hp"] = 999999
	# ⛑ DECLAW THE ORDINARY ATTACK so only the BURST moves the bar. A level-20 boss hits for about
	# a level-1 Barbarian's entire 127 HP, so the wind-up round was killing the subject outright
	# and the resolve then short-circuited on "you are dead" - which read as "the burst vanished".
	# The burst is a share of the PLAYER's max HP, so weakening the monster does not touch it.
	mon["strength"] = 1
	mon["attack"] = 1
	cm.start_combat(0, ch, mon)
	if not cm.active_combats.has(0):
		return {}
	# ⛑ HP AFTER `start_combat`, NOT BEFORE. Setting it first does not stick, and a character on
	# 0 HP makes the monster turn return "you are dead" before any of this runs - which presented
	# as "the burst never landed" and cost a debugging round.
	ch.current_hp = ch.get_total_max_hp()
	var combat: Dictionary = cm.active_combats[0]
	combat["round"] = period        # the round it used to land on
	var setup: Dictionary = SETUPS.get(ability, {})
	for k in setup:
		combat[k] = setup[k]
	return {"combat": combat, "char": ch, "monster": combat.monster}


func _init() -> void:
	var cm := CombatManagerScript.new()
	var db := MonsterDB.new()

	var PERIODS := {
		"boss_aerial_dive": 4,
		"boss_labyrinth_charge": 5,
		"boss_tremor_stomp": 3,
		"boss_titan_earthquake": 4,
		"boss_soul_siphon": 3,
		"boss_sonic_echo": 4,
		"boss_hatchling_swarm": 4,
		"boss_infernal_curse": 5,
		"boss_primordial_roar": 5,
		"boss_divine_punishment": 4,
		"boss_death_mark": 3,
	}

	print("")
	print("===== 1. THE ROUND IT USED TO LAND ON NOW ANNOUNCES INSTEAD =====")
	print("  (the boss still makes its ORDINARY attack that round - the BURST is what is deferred,")
	print("   so 'hp lost' here is the normal hit and is not the thing under test)")
	for ability in PERIODS.keys():
		var f: Dictionary = _boss_fight(cm, db, String(ability), int(PERIODS[ability]))
		if f.is_empty():
			_fail("%s - could not start a fight" % ability)
			continue
		var combat: Dictionary = f["combat"]
		var ch = f["char"]
		var hp_before: int = int(ch.current_hp)
		var res: Dictionary = cm._process_monster_turn_inner(combat)
		var lost: int = hp_before - int(ch.current_hp)
		var queued := String(combat.get("pending_burst_ability", "")) == String(ability)
		# ⛑ BOTH KEYS. This function returns `messages` AND a joined `message`, and CLAUDE.md's
		# Pitfall #9 is one side writing one and the other reading the other.
		var blob := String(res.get("message", ""))
		for m in res.get("messages", []):
			blob += "
" + String(m)
		var announced: bool = blob.find("⚠") >= 0
		print("  %-26s queued=%-6s announced=%-6s ordinary hit=%d"
			% [ability, str(queued), str(announced), lost])
		if not queued:
			_fail("%s did not queue a burst on its own round" % ability)
		if not announced:
			_fail("%s queued silently - the player is never told it is coming" % ability)
		cm.active_combats.erase(0)

	print("")
	print("===== 2. IT LANDS NEXT TURN, AND BRACING SOFTENS IT =====")
	for ability in PERIODS.keys():
		var raw_hit := 0
		var braced_hit := 0
		for braced in [false, true]:
			var f: Dictionary = _boss_fight(cm, db, String(ability), int(PERIODS[ability]))
			if f.is_empty():
				continue
			var combat: Dictionary = f["combat"]
			var ch = f["char"]
			cm._process_monster_turn_inner(combat)          # wind-up
			if braced:
				cm.process_brace(combat)                     # the player answers
			combat["round"] = int(combat["round"]) + 1
			ch.current_hp = ch.get_total_max_hp()            # isolate the burst from the ordinary hit
			var hp_before: int = int(ch.current_hp)
			cm._process_monster_turn_inner(combat)          # resolve
			var lost: int = hp_before - int(ch.current_hp)
			if braced:
				braced_hit = lost
			else:
				raw_hit = lost
			cm.active_combats.erase(0)
		print("  %-26s unbraced=%-6d braced=%-6d" % [ability, raw_hit, braced_hit])
		if raw_hit <= 0:
			_fail("%s never landed on the following turn - the hit vanished entirely" % ability)
		elif braced_hit >= raw_hit:
			_fail("%s: bracing changed nothing (%d vs %d) - it is still unavoidable"
				% [ability, braced_hit, raw_hit])

	print("")
	print("===== 3. STUNNING THE BOSS CANCELS IT =====")
	for ability in PERIODS.keys():
		var f: Dictionary = _boss_fight(cm, db, String(ability), int(PERIODS[ability]))
		if f.is_empty():
			continue
		var combat: Dictionary = f["combat"]
		var ch = f["char"]
		cm._process_monster_turn_inner(combat)               # wind-up
		combat["monster_stunned"] = 1                        # the player stuns it
		combat["round"] = int(combat["round"]) + 1
		ch.current_hp = ch.get_total_max_hp()
		var hp_before: int = int(ch.current_hp)
		cm._process_monster_turn_inner(combat)               # would have resolved
		var lost: int = hp_before - int(ch.current_hp)
		print("  %-26s hp lost after a stun = %d" % [ability, lost])
		if lost > 0:
			_fail("%s landed through a stun - the counterplay does not work" % ability)
		cm.active_combats.erase(0)

	print("")
	print("===== 4. ADVISORY: WHAT IS STILL UNCONVERTED =====")
	# ⛑ NOT A GATE, BUT IT MUST BE VISIBLE. Converting five of nineteen and declaring the class
	# fixed is exactly how a half-done sweep gets forgotten.
	var src := FileAccess.get_file_as_string("res://shared/combat_manager.gd")
	var rx := RegEx.new()
	rx.compile("if (ABILITY_BOSS_[A-Z_]+) in [a-z_]*abilities[a-z_]* and combat")
	var cyclical: Array = []
	for m in rx.search_all(src):
		cyclical.append(String(m.get_string(1)))
	var converted: Array = CombatManagerScript.TELEGRAPHED_BURSTS.keys()
	print("  %d cyclical boss abilities; %d telegraph, %d still land the moment the counter hits:"
		% [cyclical.size(), converted.size(), maxi(0, cyclical.size() - converted.size())])
	var undecided: Array = []
	var seen: Dictionary = {}
	for c in cyclical:
		var id := String(c).replace("ABILITY_", "").to_lower()
		if seen.has(id):
			continue
		seen[id] = true
		if CombatManagerScript.TELEGRAPHED_BURSTS.has(id):
			continue
		if NOT_BURSTS.has(id):
			print("    decided, not a burst: %-22s %s" % [id, NOT_BURSTS[id]])
		else:
			undecided.append(id)
			print("    UNDECIDED: %s" % id)
	if not undecided.is_empty():
		_fail("%d cyclical boss abilities are neither telegraphed nor decided: %s" % [undecided.size(), ", ".join(undecided)])

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS every converted burst winds up, lands a turn later, softens when you guard")
	print("       and vanishes when you stun it.")
	quit()
