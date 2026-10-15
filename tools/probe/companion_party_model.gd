extends SceneTree
## Item 14 S2: the column companions (companion_party). The list stores IDS and every read validates them, so the
## many places that release / trade / register / lose a companion never have to know it exists.
## Run:  godot --headless --path . --script res://tools/probe/companion_party_model.gd
const CharacterScript = preload("res://shared/character.gd")
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _ch(level: int):
	var ch = CharacterScript.new()
	ch.initialize("Tester", "Fighter", "Human")
	ch.level = level
	for i in 6:
		ch.collected_companions.append({"id": "c%d" % i, "name": "Wolf Pup %d" % i, "monster_type": "Wolf", "tier": 1, "sub_tier": 1,
			"level": 10, "xp": 0, "bonuses": {"attack": 3, "aggro": 25}, "variant": "Normal", "border_tier": 0})
	return ch

func _init() -> void:
	print("--- slots unlock by level ---")
	for pair in [[1, 0], [9, 0], [10, 1], [24, 1], [25, 2], [50, 3], [99, 3], [100, 4], [5000, 4]]:
		ck(_ch(int(pair[0])).companion_slots_unlocked() == int(pair[1]), "level %d -> %d column slot(s)" % [int(pair[0]), int(pair[1])])

	print("--- adding ---")
	var a = _ch(5)
	ck(a.add_to_companion_party("c0") != "", "below level 10 nothing can be fielded (%s)" % a.add_to_companion_party("c0"))
	var b = _ch(100)
	ck(b.add_to_companion_party("c0") == "" and b.add_to_companion_party("c1") == "", "two companions fielded")
	ck(b.add_to_companion_party("c0") != "", "the same one twice is refused")
	ck(b.add_to_companion_party("nope") != "", "an id you do not own is refused")
	b.activate_hatched_companion("c2")
	ck(b.add_to_companion_party("c2") != "", "the active (beside-you) companion cannot also be in the column")
	ck(b.add_to_companion_party("c3") == "" and b.add_to_companion_party("c4") == "", "fills to four")
	ck(b.add_to_companion_party("c5") != "", "a fifth column companion is refused (slots full)")
	ck(b.get_companion_party_ids().size() == 4, "four fielded")

	print("--- the list heals itself when a companion leaves the collection (release, trade, register...) ---")
	var c = _ch(100)
	c.add_to_companion_party("c0"); c.add_to_companion_party("c1"); c.add_to_companion_party("c2")
	c.collected_companions.remove_at(1)    # what release / trade / checkout-return do: remove from the collection only
	var ids: Array = c.get_companion_party_ids()
	ck(ids == ["c0", "c2"], "c1 vanished from the party without anything telling the party (%s)" % str(ids))
	ck(c.companion_party == ["c0", "c2"], "...and the stored list was pruned too")

	print("--- activating a fielded companion moves it to slot 0 ---")
	var d = _ch(100)
	d.add_to_companion_party("c0"); d.add_to_companion_party("c1")
	d.activate_hatched_companion("c0")
	ck(d.get_companion_party_ids() == ["c1"], "c0 left the column when it became the active companion (%s)" % str(d.get_companion_party_ids()))
	ck(str(d.active_companion.get("id", "")) == "c0", "...and is the active one")

	print("--- level drop / unlock cap ---")
	var e = _ch(100)
	for i in 4:
		e.add_to_companion_party("c%d" % i)
	e.level = 25
	ck(e.get_companion_party_ids().size() == 2, "a character who now has 2 slots only fields 2 (%d)" % e.get_companion_party_ids().size())

	print("--- save round trip ---")
	var f = _ch(100)
	f.add_to_companion_party("c3"); f.add_to_companion_party("c1")
	var g = CharacterScript.new()
	g.initialize("Copy", "Fighter", "Human")
	g.from_dict(f.to_dict())
	ck(g.get_companion_party_ids() == ["c3", "c1"], "the party survives to_dict/from_dict in order (%s)" % str(g.get_companion_party_ids()))

	print("--- each fielded companion has its OWN HP pool ---")
	var h = _ch(100)
	h.add_to_companion_party("c0"); h.add_to_companion_party("c1")
	var full: int = h.get_party_companion_max_hp("c0")
	ck(full > 0 and h.get_party_companion_combat_hp("c0") == full, "starts at full (%d)" % full)
	h.set_party_companion_combat_hp("c0", 0)
	ck(h.is_party_companion_ko("c0") and not h.is_party_companion_ko("c1"), "c0 knocked out, c1 untouched")
	h.set_party_companion_combat_hp("c1", full * 5)
	ck(h.get_party_companion_combat_hp("c1") == h.get_party_companion_max_hp("c1"), "HP is clamped to its max")
	ck(h.active_companion.is_empty(), "no active companion was created or disturbed")
	var snap: Dictionary = h.active_companion.duplicate(true)
	h.add_to_companion_party("c2")
	ck(h.active_companion == snap, "fielding never touches the active_companion slot")

	print("")
	print(("PASS - companion_party_model" if fails == 0 else "FAIL - companion_party_model: %d check(s)" % fails))
	quit(1 if fails > 0 else 0)
