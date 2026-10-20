extends "res://server/persistence_manager.gd"
## In-memory houses so valor_ledger.gd never touches the real database.
var _h := {}
func get_house(account_id: String) -> Dictionary:
	if not _h.has(account_id):
		_h[account_id] = {"valor": 0, "total_valor_earned": 0}
	return _h[account_id]
func save_house(_account_id: String, _house: Dictionary) -> void:
	pass
func flush_valor_ledger() -> void:
	_valor_ledger_dirty = 0
