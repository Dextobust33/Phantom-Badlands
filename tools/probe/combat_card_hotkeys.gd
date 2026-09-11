extends SceneTree
## The three cards in hand must always sit on keys 1, 2, 3.
##
## Owner 2026-09-06: *"now that outsmart has been removed our card numbers shifted to R, 1, and 2.
## This is odd. It should be 1, 2, 3 still."* Retiring a card must not renumber the hand — the
## hand is always three cards, whatever else occupies the bar.
##
## The backlog said to treat it as live until REPRODUCED. This is that reproduction attempt.
const CLIENT := "res://client/client.gd"

# The action bar's ten slots, in order. Slots 4..9 are what _get_combat_hand_actions fills.
const KEYS := ["Space", "Q", "W", "E", "R", "1", "2", "3", "4", "5"]

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var c = load(CLIENT).new()
	for hand in [["power_strike", "cleave", "bull_rush"], ["magic_bolt"], []]:
		c.set("combat_hand", hand)
		var acts: Array = c._get_combat_hand_actions()
		# These fill bar slots 4..9, i.e. keys R,1,2,3,4,5.
		var labelled: Array = []
		for i in range(acts.size()):
			var a: Dictionary = acts[i]
			var key: String = KEYS[4 + i] if 4 + i < KEYS.size() else "?"
			labelled.append("%s=%s" % [key, String(a.get("label", "?"))])
		print("      hand %d card(s): %s" % [hand.size(), ", ".join(labelled)])

		ck(acts.size() >= 1, "the bar got some entries")
		# R must NEVER hold a card. That is the whole complaint.
		var r_slot: Dictionary = acts[0]
		ck(String(r_slot.get("action_type", "")) != "combat",
			"key R holds no card (it is '%s')" % String(r_slot.get("label", "")))
		# and each held card must land on 1, 2, 3 in order
		for n in range(hand.size()):
			if 1 + n >= acts.size():
				ck(false, "card %d has no slot" % (n + 1))
				continue
			var a2: Dictionary = acts[1 + n]
			ck(String(a2.get("action_data", "")) == String(hand[n]),
				"card %d ('%s') is on key %s" % [n + 1, String(hand[n]), KEYS[5 + n]])

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
