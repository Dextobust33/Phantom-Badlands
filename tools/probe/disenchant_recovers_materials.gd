extends SceneTree
## Found while wiring gold into salvage: `_craft_disenchant` looped over get_salvage_value()'s return as
## if it were a flat {material: qty} dict, but that returns {"materials": {...}} - so Disenchant could
## never recover the materials it promises ("the same materials salvage would give").
const CharacterScript = preload("res://shared/character.gd")
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

class QuietServer extends "res://server/server.gd":
	func save_character(_p) -> void:
		pass

func _init() -> void:
	var srv = QuietServer.new()
	srv.drop_tables = load("res://shared/drop_tables.gd").new()
	get_root().add_child(srv.drop_tables)
	await process_frame
	var h = CharacterScript.new()
	h.initialize("Hero", "Fighter", "Human")
	var rune := {"type": "rune", "name": "Minor Rune of Attack", "target_slot": "weapon", "rune_stat": "attack_bonus", "rune_cap": 8}
	h.inventory = [{"name": "Rune Blade", "type": "weapon_sword", "rarity": "rare", "level": 20, "value": 400,
			"applied_runes": [{"id": "r1", "name": "Minor Rune of Attack", "item": rune}]}]
	var before: int = 0
	for k in h.crafting_materials:
		before += int(h.crafting_materials[k])
	var out: String = srv._craft_disenchant(h, {}, 1, "#FFFFFF")
	var after: int = 0
	for k in h.crafting_materials:
		after += int(h.crafting_materials[k])
	ck(after > before, "materials were recovered (%d -> %d)" % [before, after])
	ck(out.find("Recovered:") >= 0, "and the result says so")
	ck(h.crafting_materials.get("materials", null) == null, "no bogus 'materials' entry was created in the pack")
	ck(out.find("Runes returned") >= 0 and h.inventory.size() == 1 and String(h.inventory[0].get("type", "")) == "rune", "the rune came back (the item was unmade)")
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
