extends SceneTree
## Owner sheet 2026-10-13, item 49: "Title help menu doesn't seem accurate." Audited every claim the Title menu and
## the TITLES & ENDGAME help make against titles.gd and the server's claim/forge handlers. Found: (1) the menu read
## gold_cost keys the tables no longer use, so no Valor cost was ever shown; (2) the menu offered a claim within one
## tile of the seat while the claim demands exactly (0,0); (3) the help omitted that a High King usurps and that the
## Jarl needs no High King on the throne, and named only the Fire Mt button (it becomes Forge).
const Titles := preload("res://shared/titles.gd")
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _init() -> void:
	var c = load("res://client/client.gd").new()
	var n := 0
	for tbl in [Titles.JARL_ABILITIES, Titles.HIGH_KING_ABILITIES, Titles.ELDER_ABILITIES, Titles.ETERNAL_ABILITIES]:
		for k in tbl:
			var a: Dictionary = tbl[k]
			var parts: Array = c._title_ability_cost_parts(a)
			var text := " ".join(parts)
			n += 1
			var priced: bool = a.has("valor_cost_percent") or int(a.get("valor_cost", 0)) > 0 or int(a.get("gem_cost", 0)) > 0 or int(a.get("cooldown", 0)) > 0
			if priced:
				ck(not parts.is_empty(), "%s shows a cost: %s" % [a.get("name", k), text])
			if a.has("valor_cost_percent"):
				ck(text.find("%d%%" % int(a["valor_cost_percent"])) >= 0, "%s quotes its %d%% valor" % [a.get("name", k), int(a["valor_cost_percent"])])
			elif int(a.get("valor_cost", 0)) > 0:
				ck(text.find("valor") >= 0, "%s quotes its flat valor" % a.get("name", k))
	ck(n >= 10, "audited %d title abilities" % n)
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	var h := srv.find("\nfunc handle_get_title_menu(")
	var body := srv.substr(h, srv.find("\nfunc ", h + 10) - h)
	ck(body.find("\n\tif character.x == 0 and character.y == 0:\n") >= 0 and body.find("abs(character.x) <= 1") < 0, "the menu offers a claim only at exactly (0,0), as the claim requires")
	var cl := FileAccess.get_file_as_string("res://client/client.gd")
	ck(cl.find("[b]usurps[/b] the sitting High King") >= 0, "help says a High King usurps")
	ck(cl.find("press [color=#FFD700]Fire Mt[/color], then [color=#FFD700]Forge[/color]") >= 0, "help names both forge buttons")
	ck(cl.find("(only while no High King rules)") >= 0, "help says Jarl needs no High King")
	ck(cl.find("ability.get(\"gold_cost\"") < 0, "the menu no longer reads gold_cost")
	print("\n[TITLEMENU] %s" % ("PASS" if fails == 0 else "FAIL - %d" % fails))
	quit(0 if fails == 0 else 1)
