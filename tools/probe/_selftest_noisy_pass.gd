extends SceneTree
## Self-test for tools/probe_run.py: prints PASS and exits 0 while hitting a script error. The runner
## MUST fail it - that is the whole class this tool exists to catch.
func _init() -> void:
	var d: Dictionary = {}
	var x = d["missing_key"]
	print("[SELFTEST] PASS (but a script error happened above)")
	quit(0)
