extends SceneTree
## Owner sheet 2026-10-13, item 24: "Players aren't able to properly leave the posts. We still have remnants
## of party lead vs follow and rotation." The Dragon Quest IX model (v0.9.833) made everyone walk their own
## path, but four pieces of the old model were left running: a post-EXIT gate (only the leader may leave, and
## only with everyone beside them), the Lead/Follow question when a party forms, leadership rotating after every
## fight and gather, and a follower lock with no callers. Source-level: each must be gone, and the replacement
## (inviter leads at once) present.
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _init() -> void:
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	ck(srv.find("only your party leader can lead the party out") < 0, "no 'only the leader can lead the party out' gate")
	ck(srv.find("must be beside you before the party leaves the post") < 0, "no 'stand beside me to leave' straggler gate")
	ck(srv.find("func _party_rotate_leader(") < 0 and srv.find("_party_rotate_leader(") < 0, "leadership never rotates")
	ck(srv.find("func _party_follower_locked(") < 0 and srv.find("func _party_follower_denied(") < 0, "the dead follower lock is gone")
	ck(srv.find("\"type\": \"party_lead_choice\"") < 0, "the server never asks Lead or Follow")
	ck(srv.find("\n\t\thandle_party_lead_choice_response(inviter_id, {\"choice\": \"lead\", \"partner_peer_id\": peer_id})\n") >= 0, "an accepted invite forms the party with the inviter leading")
	var cl := FileAccess.get_file_as_string("res://client/client.gd")
	ck(cl.find("\"action_data\": \"party_control_mode\"") < 0, "the Lead: Rotate/Fixed button is gone from the Party menu")
	ck(cl.find("Leadership rotates after every fight") < 0, "the help no longer says leadership rotates")
	print("\n[PARTYREMNANTS] %s" % ("PASS" if fails == 0 else "FAIL - %d" % fails))
	quit(0 if fails == 0 else 1)
