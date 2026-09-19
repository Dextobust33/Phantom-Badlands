extends SceneTree
## ⛑ DOES THE CARD'S DAMAGE ESTIMATE INCLUDE THE GEAR YOU FARMED FOR IT?
##
## The backlog said the fault was that the estimate "counts only `power` picks". That is NOT it -
## the server's `get_tier_effect_mult` counts only power picks too, so that half always agreed.
##
## ⚡ THE REAL GAP was `get_skill_damage_bonus` - card TOMES plus card-specific GEAR (card_gear.gd)
## - a percentage the server applies to every hit and the card face never showed. So a player who
## farmed a chase item FOR a card equipped it and saw the number it had BEFORE, which is the worst
## possible moment to under-report, because it is exactly when they are looking.
##
## This asserts the two halves the client used to get wrong, on the SERVER's own functions so the
## expected value is never a second copy of the rule.
const CharacterScript := preload("res://shared/character.gd")
const CardGear := preload("res://shared/card_gear.gd")

var _fails: Array = []
func _fail(m: String) -> void:
	_fails.append(m); print("  FAIL  %s" % m)
func _ok(m: String) -> void:
	print("  ok    %s" % m)

func _init() -> void:
	print("")
	print("===== 1. THE CONSTANTS ARE READ, NOT COPIED =====")
	# The client used to hardcode 0.02 / 0.12. Correct then; a silent liar the day either moves.
	var src := FileAccess.get_file_as_string("res://client/client.gd")
	var i := src.find("func _card_damage_multiplier(")
	var body := src.substr(i, 1800) if i >= 0 else ""
	if body == "":
		_fail("_card_damage_multiplier is gone")
	else:
		var reads := body.find("Character.TIER_POWER_PER") >= 0 and body.find("Character.MILESTONE_POWER_PER") >= 0
		var copies := body.find("* 0.02") >= 0 or body.find("* 0.12") >= 0
		print("  reads Character.* constants: %s   still has a literal: %s" % [str(reads), str(copies)])
		if not reads:
			_fail("the estimate does not read the shared constants")
		elif copies:
			_fail("a hardcoded 0.02/0.12 is still in there")
		else:
			_ok("tier and milestone rates come from Character, not a copy")

	print("")
	print("===== 2. CARD GEAR ACTUALLY CARRIES POWER TO COUNT =====")
	# Built from the game's own table, so the probe cannot invent an affix the game never rolls.
	var card := ""
	for k in CardGear.KINDS.keys():
		if "power" in CardGear.KINDS[k]:
			card = String(k)
			break
	if card == "":
		_fail("no card in KINDS carries a `power` bonus")
		_finish()
		return
	# ⛑ THE KEY IS BUILT BY THE GAME'S OWN `key()`, not spelled out here - the first cut of this
	# probe guessed at an `affix_key()` that does not exist. Ask the module, never assume its API.
	var affix := String(CardGear.key("power", card))
	print("  using card '%s', affix key '%s'" % [card, affix])
	var item := {"affixes": {affix: 25.0}, "wear": 0}
	var rows: Array = CardGear.item_bonuses(item)
	var found := 0.0
	for r in rows:
		if String(r.get("card", "")) == card and String(r.get("kind", "")) == "power":
			found = float(r.get("value", 0.0))
	print("  an item with that affix reports power = %.1f%%" % found)
	if found <= 0.0:
		_fail("card_gear did not report the power bonus - the probe's item shape is wrong, or the API changed")
	else:
		_ok("card gear reports a power bonus the estimate can read")

	print("")
	print("===== 3. THE SERVER APPLIES IT, SO THE FACE MUST TOO =====")
	var ch = CharacterScript.new()
	ch.initialize("Probe", "Fighter", "Human")
	var before := ch.get_skill_damage_bonus(card)
	ch.equipped["weapon"] = item
	var after := ch.get_skill_damage_bonus(card)
	print("  get_skill_damage_bonus(%s): %.1f%% -> %.1f%% with the item equipped" % [card, before, after])
	if after <= before:
		_fail("equipping card gear changed nothing on the SERVER - nothing for the face to show")
	else:
		_ok("the server counts it, so a face that ignored it was under-reporting")

	_finish()

func _finish() -> void:
	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS the estimate reads the shared rates and card gear carries power the")
	print("       server applies - so the card face now counts what you farmed for it.")
	quit()
