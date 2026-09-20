extends SceneTree
## ⛑ DOES DESCENDING INTO A PHANTOM ASSEMBLE A REAL ONE?
##
## The model, the investment record, the feed surface, the generation hooks and the reward side all
## exist and are all inert until something creates an instance carrying a `phantom` block. This is
## the piece that does — so it is the piece where every earlier assumption is either honoured or
## quietly lost.
##
## ⚡ THE FAILURE THIS GUARDS IS "IT WORKS, BUT IT IS AN ORDINARY DUNGEON". Miss the `phantom` block
## and you get a perfectly playable dungeon with none of the investment in it; miss `floor_override`
## and a 20-floor frontier Phantom is however many floors a Goblin Caves has; read the investment
## from the wrong post and a player descends into somebody else's. All three look fine from inside.
##
## WHAT THIS ASSERTS:
##   1. the feature is still HELD, and the descent refuses while it is
##   2. the instance carries everything the generators need
##   3. depth comes from the POST's distance, not from the dungeon type
##   4. you can only descend into a post you own, while standing in it
##
## Run:
##   godot --headless --path . --script res://tools/probe/you_can_descend_into_your_own_phantom.gd

const PM := preload("res://shared/phantom_model.gd")

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


func _init() -> void:
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	var NL := "\n"
	var i := srv.find("func handle_enter_phantom(")
	if i < 0:
		_fail("handle_enter_phantom does not exist - nothing can create a Phantom")
		_finish()
		return
	var j := srv.find(NL + "func ", i + 8)
	var body := srv.substr(i, (j - i) if j > i else 6000)

	print("")
	print("===== 1. STILL HELD =====")
	if body.find("if not PHANTOM_POSTS_ENABLED:") < 0:
		_fail("the descent does not check the feature flag, so a hand-sent message reaches it "
			+ "while the feature is supposed to be held")
	else:
		_ok("the descent refuses while the feature is held")

	print("")
	print("===== 2. THE INSTANCE CARRIES WHAT THE GENERATORS READ =====")
	# Each of these is read by a generator that falls back to ORDINARY behaviour when it is
	# absent - which is why a missing one produces a working dungeon rather than an error.
	var needed := {
		"\"phantom\":": "the block every generator checks for - without it this is just a dungeon",
		"\"investment\":": "what was fed to the post; without it the levels and species are ordinary",
		"\"max_depth\":": "how deep it goes; the reward curve is a fraction of this",
		"\"local_level\":": "the top floor, which must equal the country outside",
		"\"floor_override\":": "how many floors are actually BUILT - without it a frontier Phantom "
			+ "is however many floors its borrowed dungeon type has",
	}
	for key in needed.keys():
		if body.find(key) < 0:
			_fail("the instance has no %s - %s" % [key, needed[key]])
		else:
			_ok("carries %s" % key)

	print("")
	print("===== 3. DEPTH COMES FROM THE POST, NOT THE DUNGEON TYPE =====")
	if body.find("max_depth_for(") < 0:
		_fail("depth is not computed from the post's distance, so pushing further out buys nothing "
			+ "- which is the entire outward pull this feature exists to create")
	else:
		_ok("depth comes from how far out the post is")
	# And the two must agree: the floors BUILT and the depth the model scales against.
	if body.find("\"floor_override\": max_depth") < 0:
		_fail("the built floor count and the model's max_depth are not the same number. The reward "
			+ "curve is a fraction of max_depth, so if they disagree the bottom floor is not the "
			+ "bottom of the curve and the best rewards are unreachable")
	else:
		_ok("the floors built and the depth scaled against are the same number")
	print("  for reference:")
	for dist in [0.0, 900.0, 2200.0]:
		print("    a post %4.0f tiles out -> %2d floors, certain egg on floor %d"
			% [dist, PM.max_depth_for(dist), PM.guaranteed_egg_depth(PM.max_depth_for(dist))])

	print("")
	print("===== 4. ONLY YOUR OWN POST, ONLY FROM INSIDE IT =====")
	# `_post_index_here` checks BOTH: that the tile belongs to an enclosure, and that the
	# enclosure is this player's. Descending into someone else's investment would be theft, and
	# descending from anywhere would remove the journey the whole loop is built on.
	if body.find("_post_index_here(peer_id)") < 0:
		_fail("the descent does not check which post you are standing in - it could open somebody "
			+ "else's Phantom, or one you are nowhere near")
	else:
		_ok("you must be standing in a post you own")
	if body.find("get_post_investment(username, idx)") < 0:
		_fail("the investment is not read from the post being descended into")
	else:
		_ok("the investment read is that post's own")
	# The ordinary in-dungeon / in-combat guards, so this cannot be used to escape a fight.
	for guard in ["character.in_dungeon", "combat_mgr.is_in_combat(peer_id)"]:
		if body.find(guard) < 0:
			_fail("the descent does not check %s" % guard)
		else:
			_ok("refuses when %s" % guard)

	_finish()


func _finish() -> void:
	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS descending builds a real Phantom, as deep as the post is far out, from")
	print("       the investment of the post you are standing in.")
	quit()
