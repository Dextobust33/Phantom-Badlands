extends SceneTree
## Item 14 S5: ROLE FUSION at the Stable - three companions of one tier + gold become one companion of the role you
## pick. Drives the real server handler. Also: the early Strikers and a role for every species at every tier.
## Run:  godot --headless --path . --script res://tools/probe/role_fusion.gd
const ServerScript = preload("res://server/server.gd")
const CharacterScript = preload("res://shared/character.gd")
const RolesScript = preload("res://shared/companion_roles.gd")
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

class StubConn:
	func get_status() -> int:
		return 0

class StubChunks extends "res://shared/chunk_manager.gd":
	func get_tile(_x, _y) -> Dictionary:
		return {"type": "companion_stable"}

func _k(i: int, species: String, tier: int, sub: int) -> Dictionary:
	return {"id": "k%d" % i, "name": species + str(i), "monster_type": species, "level": 20 + i, "xp": 0, "tier": tier, "sub_tier": sub,
		"variant": "Normal", "bonuses": {}, "border_tier": i}

func _setup(gold: int, kennel: Array):
	var pm = load("res://server/persistence_manager.gd").new()
	get_root().add_child(pm)
	var srv = ServerScript.new()
	srv.persistence = pm
	srv.chunk_manager = StubChunks.new()
	srv.drop_tables = load("res://shared/drop_tables.gd").new()
	var house: Dictionary = pm.create_house("acct1")
	house.companion_kennel["companions"] = kennel
	pm.houses_data["houses"]["acct1"] = house
	var hero = CharacterScript.new()
	hero.name = "Dexto"
	hero.class_type = "warrior"
	hero.level = 30
	hero.gold_purse = gold
	srv.characters = {1: hero}
	srv.peers = {1: {"authenticated": true, "account_id": "acct1", "connection": StubConn.new()}}
	return [srv, pm, hero]

func _inputs(n: int) -> Array:
	var a: Array = []
	for i in n:
		a.append({"source": "kennel", "index": i})
	return a

func _init() -> void:
	await process_frame
	print("--- roles ---")
	for sp in ["Wolf", "Gnoll", "Orc"]:
		ck(RolesScript.role_of_species(sp) == RolesScript.ROLE_DPS, "%s is a Striker by name" % sp)
	var by := {}
	var drop = load("res://shared/drop_tables.gd")
	for r in RolesScript.ROLES:
		for t in range(1, 10):
			var pool: Array = RolesScript.species_for_role(String(r), t)
			if pool.is_empty():
				ck(false, "role %s has a species for tier %d" % [r, t])
			for sp in pool:
				if RolesScript.role_of_species(String(sp)) != r:
					ck(false, "%s listed for %s but is %s" % [sp, r, RolesScript.role_of_species(String(sp))])
	ck(RolesScript.role_fusion_cost(3) == 3000, "cost is 1,000 gold per tier")

	print("--- the fusion ---")
	var kennel := [_k(0, "Goblin", 2, 5), _k(1, "Skeleton", 2, 3), _k(2, "Zombie", 2, 7)]
	var s = _setup(5000, kennel.duplicate(true))
	var srv = s[0]; var pm = s[1]; var hero = s[2]
	srv.handle_stable_fusion(1, {"fusion_type": "role:healer", "inputs": _inputs(3)})
	var h = pm.get_house("acct1")
	var out: Array = h.companion_kennel.companions
	ck(out.size() == 1, "three went in, one came out (%d in the kennel)" % out.size())
	if out.size() == 1:
		var o: Dictionary = out[0]
		ck(RolesScript.role_of(o) == RolesScript.ROLE_HEALER, "the result is a Healer (%s)" % str(o.get("monster_type")))
		ck(int(o.get("tier", 0)) == 2, "the inputs' grade is kept (tier %d)" % int(o.get("tier", 0)))
		ck(int(o.get("sub_tier", 0)) == 3, "rank is the LOWEST of the three (%d)" % int(o.get("sub_tier", 0)))
		ck(int(o.get("level", 0)) >= 22, "the best level carries (%d)" % int(o.get("level", 0)))
		ck(int(o.get("border_tier", 0)) == 2, "the best border carries (%d)" % int(o.get("border_tier", 0)))
	ck(hero.gold_purse == 5000 - 2000, "it cost 2,000 gold (purse %d)" % hero.gold_purse)

	print("--- refusals leave everything alone ---")
	var s2 = _setup(500, kennel.duplicate(true))
	s2[0].handle_stable_fusion(1, {"fusion_type": "role:tank", "inputs": _inputs(3)})
	ck(s2[1].get_house("acct1").companion_kennel.companions.size() == 3, "too little gold: nothing consumed")
	ck(s2[2].gold_purse == 500, "...and no gold taken")
	var mixed := [_k(0, "Goblin", 2, 5), _k(1, "Skeleton", 3, 3), _k(2, "Zombie", 2, 7)]
	var s3 = _setup(9999, mixed)
	s3[0].handle_stable_fusion(1, {"fusion_type": "role:tank", "inputs": _inputs(3)})
	ck(s3[1].get_house("acct1").companion_kennel.companions.size() == 3 and s3[2].gold_purse == 9999, "different tiers: refused, nothing taken")
	var s4 = _setup(9999, kennel.duplicate(true))
	s4[0].handle_stable_fusion(1, {"fusion_type": "role:wizard", "inputs": _inputs(3)})
	ck(s4[1].get_house("acct1").companion_kennel.companions.size() == 3, "an unknown role is refused")
	var s5 = _setup(9999, kennel.duplicate(true))
	s5[0].handle_stable_fusion(1, {"fusion_type": "role:tank", "inputs": _inputs(2)})
	ck(s5[1].get_house("acct1").companion_kennel.companions.size() == 3, "two inputs: refused")

	print("")
	print(("PASS - role_fusion" if fails == 0 else "FAIL - role_fusion: %d check(s)" % fails))
	quit(1 if fails > 0 else 0)
