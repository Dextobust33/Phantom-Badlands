extends SceneTree
## Every valor change is ledgered with a reason, and the two bypass shapes stay dead:
## (1) add_valor(-n) never shaves total_valor_earned, (2) no server call site omits its reason.
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _init() -> void:
	var P = load("res://server/persistence_manager.gd")
	var pm = P.new()
	# in-memory house: avoid touching the real database
	var houses := {}
	pm.set_script(load("res://tools/test_setup/valor_ledger_stub.gd"))
	pm.valor_ledger = {}
	pm._valor_ledger_loaded = true
	pm.add_valor("a", 100, "quest")
	ck(pm.valor_ledger.get("in:quest", {}).get("sum", 0) == 100, "an add is ledgered under its reason")
	ck(pm.spend_valor("a", 30, "healer"), "a spend succeeds")
	ck(pm.valor_ledger.get("out:healer", {}).get("sum", 0) == 30, "a spend is ledgered as out")
	var earned_before: int = int(pm.get_house("a").get("total_valor_earned", 0))
	pm.add_valor("a", -10, "oops")
	ck(int(pm.get_house("a").get("total_valor_earned", 0)) == earned_before, "a negative add does not shave 'earned'")
	ck(pm.valor_ledger.has("out:oops"), "...and is ledgered as out")
	# static scan: every call in server.gd carries a reason
	var src := FileAccess.get_file_as_string("res://server/server.gd")
	var rx := RegEx.new()
	rx.compile(r"persistence\.(add_valor|spend_valor)\(([^
]*)\)")
	var bare := 0
	for m in rx.search_all(src):
		var args: String = m.get_string(2)
		if not args.strip_edges().ends_with("\""):
			bare += 1
			print("    unlabelled: " + m.get_string(0).substr(0, 90))
	ck(bare == 0, "no server call omits its reason (%d bare)" % bare)
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
