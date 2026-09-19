extends SceneTree
## ⛑ DOES THE DUNGEON TELEGRAPH ITS PRIZE?
##
## Owner's original brainstorm for this arc: *"the theme carries to the egg/companion you get
## there, so you know what you're hunting."* Slice 2 made every monster in a modified dungeon share
## one look; this is the other half — the egg its boss leaves wears the same colours, and so does
## the companion that hatches from it.
##
## WHAT THIS ASSERTS:
##   1. an egg from a modified dungeon carries that dungeon's look
##   2. an egg from an ORDINARY dungeon still rolls its own variant — the feature must not flatten
##      the existing cosmetic variety, which is the whole egg-collecting hook
##   3. ⚑ HATCH TIME IS UNCHANGED. `get_egg_for_monster` scales hatch steps off `variant.rarity`
##      (rarity 1 takes 2.5x as long as rarity 15). A themed variant carrying an invented rarity
##      would quietly turn a cosmetic feature into a change in how long eggs take — the kind of
##      side effect nobody would connect back to "the egg matches the dungeon" three weeks later.
##
## Run:
##   godot --headless --path . --script res://tools/probe/the_egg_matches_its_dungeon.gd

const DropTablesScript := preload("res://shared/drop_tables.gd")
const DungeonDB := preload("res://shared/dungeon_database.gd")

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


## The variant dict the server builds for a themed egg — mirrors `_grant_boss_egg`.
func _themed_variant(mods: Array) -> Dictionary:
	var look: Dictionary = DungeonDB.dungeon_look_for(mods)
	if look.is_empty():
		return {}
	return {
		"name": String(look.get("name", "")),
		"color": String(look.get("color", "")),
		"color2": String(look.get("color2", "")),
		"pattern": String(look.get("pattern", "solid")),
	}


func _init() -> void:
	var dt := DropTablesScript.new()
	# A species that definitely has companion data, taken from the table rather than named.
	var species := ""
	for k in DropTablesScript.COMPANION_DATA.keys():
		species = String(k)
		break
	if species == "":
		_fail("no COMPANION_DATA at all - nothing to hatch")
		_finish()
		return
	var mod_ids: Array = DungeonDB.DUNGEON_MODIFIERS.keys()
	var mods: Array = [String(mod_ids[0]), String(mod_ids[1])]
	var look: Dictionary = DungeonDB.dungeon_look_for(mods)

	print("")
	print("===== 1. AN EGG FROM A MODIFIED DUNGEON WEARS ITS COLOURS =====")
	var themed: Dictionary = dt.get_egg_for_monster(species, _themed_variant(mods), 3, 3)
	if themed.is_empty():
		_fail("no egg was produced for %s" % species)
	else:
		# ⛑ THE EGG FLATTENS ITS VARIANT into `variant` / `variant_color` / `variant_pattern`
		# rather than nesting a dict. The first cut of this probe read `egg.variant` as a
		# Dictionary and died on a String - the shape has to be read, not assumed.
		print("  dungeon look : %s / %s / %s" % [look.get("name", ""), look.get("color", ""), look.get("pattern", "")])
		print("  egg variant  : %s / %s / %s" % [themed.get("variant", ""),
			themed.get("variant_color", ""), themed.get("variant_pattern", "")])
		if String(themed.get("variant_color", "")) != String(look.get("color", "")):
			_fail("the egg's colour (%s) is not the dungeon's (%s)" % [themed.get("variant_color", ""), look.get("color", "")])
		elif String(themed.get("variant_pattern", "")) != String(look.get("pattern", "")):
			_fail("the egg's pattern (%s) is not the dungeon's (%s)" % [themed.get("variant_pattern", ""), look.get("pattern", "")])
		else:
			_ok("the egg carries the dungeon's colour and pattern")

	print("")
	print("===== 2. AN ORDINARY DUNGEON'S EGG STILL ROLLS ITS OWN =====")
	# ⛑ The egg-collecting hook is VARIETY. If theming flattened every egg to one look, a feature
	# meant to make dungeons distinct would have made companions less so.
	var seen := {}
	for i in range(40):
		var plain: Dictionary = dt.get_egg_for_monster(species, {}, 3, 3)
		seen[String(plain.get("variant", ""))] = true
	print("  %d distinct variants across 40 unmodified-dungeon eggs" % seen.size())
	if seen.size() < 2:
		_fail("every ordinary egg rolled the same variant - the cosmetic pool is not being used")
	else:
		_ok("ordinary eggs still roll from the full cosmetic pool")

	print("")
	print("===== 3. HATCH TIME IS UNTOUCHED =====")
	var a: Dictionary = dt.get_egg_for_monster(species, {}, 3, 3)
	var b: Dictionary = dt.get_egg_for_monster(species, _themed_variant(mods), 3, 3)
	var base_steps := int(a.get("hatch_steps", 0))
	var themed_steps := int(b.get("hatch_steps", 0))
	# The unthemed egg rolls a random variant, so compare against the DEFAULT-rarity case rather
	# than one sample: rarity 10 is what an absent key falls back to.
	var default_steps := int(dt.get_egg_for_monster(species, {"name": "x", "color": "#FFFFFF",
		"pattern": "solid"}, 3, 3).get("hatch_steps", 0))
	print("  themed egg     %d steps" % themed_steps)
	print("  default rarity %d steps  (what an absent `rarity` key falls back to)" % default_steps)
	print("  a random roll  %d steps  (varies with whatever variant it drew)" % base_steps)
	if themed_steps != default_steps:
		_fail("a themed egg hatches in %d steps against the default %d - the look changed the TIME"
			% [themed_steps, default_steps])
	else:
		_ok("a themed egg hatches in exactly the default time - the look is cosmetic")

	_finish()


func _finish() -> void:
	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS a modified dungeon's egg wears its colours, ordinary eggs keep their")
	print("       variety, and theming an egg does not change how long it takes to hatch.")
	quit()
