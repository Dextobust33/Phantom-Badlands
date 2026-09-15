extends SceneTree
## "Two upgrade screens pop up back to back for the same card" - and nowhere to see the second copy.
##
## Owner 2026-09-14, clarified 2026-09-15: *"It was a card in their deck they just had no way of
## seeing a second copy of the card. For example Ambush was used to level up and the upgrade screen
## came up and the player chose an upgrade. Then it immediately showed another upgrade screen for
## Ambush again."* And: *"it also may have been after a dungeon where the player could have possibly
## had a second copy of the card added to their deck but not known or been able to see or remove one."*
##
## Two faults, both measured before fixing:
##   1. A card that levelled in a PARTY fight (every Warden fight) queued its upgrade choice and
##      nothing announced it - the flush was on the item-use and disconnect paths but not the
##      card-command path. Choices piled up and then arrived back to back.
##   2. Every surface named a copy by its CARD. Two copies level independently, so two screens for
##      two copies read "Ambush" twice, and the deck screen showed one tile "x2" with no way to see,
##      thin or restore a particular copy.
const PEER := 1

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


class RecServer extends "res://server/server.gd":
	var announced: Array = []
	func send_to_peer(peer_id: int, message: Dictionary):
		if String(message.get("type", "")) == "rank_up_choice":
			announced.append(String(message.get("ability", "")))
		super.send_to_peer(peer_id, message)


func _init() -> void:
	print("===== 1. A PARTY LEVEL-UP IS ANNOUNCED THE ROUND IT HAPPENS =====")
	var sv = RecServer.new()
	get_root().add_child(sv)
	await process_frame
	await process_frame
	sv.set_process(false)
	sv.set_physics_process(false)
	var made: Dictionary = sv.persistence.create_account("ccv%d" % (Time.get_ticks_usec() % 100000), "probe-password")
	sv.peers[PEER] = {"authenticated": true, "account_id": String(made.get("account_id", "")), "character_name": "",
		"connection": StreamPeerTCP.new()}
	var nm := "Ccv"
	var u: int = Time.get_ticks_usec()
	for i in range(4):
		nm += char(97 + (u % 26))
		u /= 26
	sv.handle_create_character(PEER, {"name": nm, "class": "Ninja", "race": "Human"})
	await process_frame
	var ch = sv.characters[PEER]
	sv._handle_warden_interact(PEER, ch)
	ch.ability_uses["ambush"] = 9
	var mon: Dictionary = sv.monster_db.generate_monster(1, 1)
	mon["max_hp"] = 99999
	mon["current_hp"] = 99999
	mon["strength"] = 1
	ck(sv._start_guided_overworld_combat(PEER, ch, mon), "the Warden's (party) fight starts")
	var c = sv.combat_mgr.active_party_combats.get(PEER, {})
	c.member_states[PEER]["hand"] = ["ambush"] + (c.member_states[PEER].get("hand", []) as Array)
	ch.current_energy = ch.get_total_max_energy()
	sv.announced.clear()
	sv._handle_party_combat_command(PEER, "ambush")
	await process_frame
	ck(ch.pending_rank_choices.size() == 1, "Ambush's 10th use queues exactly one choice (%d)" % ch.pending_rank_choices.size())
	ck(sv.announced == ["ambush"], "and the upgrade screen is SENT that round, once (%s)" % str(sv.announced))
	sv.announced.clear()
	c.member_states[PEER]["hand"] = (c.member_states[PEER].get("hand", []) as Array)
	sv._handle_party_combat_command(PEER, "attack")
	await process_frame
	ck(sv.announced.is_empty(), "  and not sent again the next round (%s)" % str(sv.announced))
	sv.combat_mgr.active_party_combats.erase(PEER)
	sv.combat_mgr.party_combat_membership.erase(PEER)

	print("\n===== 2. EACH COPY CAN BE THINNED AND RESTORED BY NAME =====")
	var CharacterScript = load("res://shared/character.gd")
	var k = CharacterScript.new()
	k.initialize("Copies", "Fighter", "Human")
	k.initialize_deck_collection_if_needed()
	for extra in ["power_strike", "shield_bash", "war_cry", "fortify"]:
		if not k.combat_deck_collection.has(extra):
			k.combat_deck_collection[extra] = 1
	if not k.combat_deck_collection.has("cleave"):
		k.combat_deck_collection["cleave"] = 1
	var second: String = k.grant_card_copy("cleave")
	ck(second == "cleave#2", "a second Cleave exists as its own copy (%s)" % second)
	# Copy ONE is the invested one, so "least invested" would pick copy TWO. A check that passes
	# here can only be honouring the name. (The first cut invested copy two and passed on the old
	# code by coincidence - the least-invested copy happened to be copy one.)
	k.ability_uses["cleave"] = 40
	k.ability_uses["cleave#2"] = 5
	var r1: Dictionary = k.cull_ability_card("cleave#1")
	ck(bool(r1.get("ok", false)) and int(k.combat_deck_collection.get("cleave", -1)) == 0 and int(k.combat_deck_collection.get("cleave#2", 0)) == 1,
		"'cleave#1' takes out copy ONE - not whichever is least invested (%s)" % str(r1))
	var r2: Dictionary = k.add_ability_copy("cleave#1")
	ck(bool(r2.get("ok", false)) and int(k.combat_deck_collection.get("cleave", 0)) == 1, "'cleave#1' puts copy one back (%s)" % str(r2))
	var r3: Dictionary = k.cull_ability_card("cleave#2")
	ck(bool(r3.get("ok", false)) and int(k.combat_deck_collection.get("cleave#2", -1)) == 0, "'cleave#2' takes out copy two")
	ck(int(k.ability_uses.get("cleave#2", 0)) == 5, "  and it keeps its own progress while benched")
	var r4: Dictionary = k.add_ability_copy("cleave#3")
	ck(not bool(r4.get("ok", true)), "a copy you do not own cannot be added by name (%s)" % str(r4.get("reason", "")))

	print("\n===== 3. THE CLIENT NAMES THE COPY =====")
	var cl = load("res://client/client.gd").new()
	cl.character_data = {"class": "Fighter", "combat_deck_collection": {"cleave": 1, "cleave#2": 1, "power_strike": 1}}
	ck(cl._card_copy_label("cleave#2") == " · copy 2", "copy two is labelled (%s)" % cl._card_copy_label("cleave#2"))
	ck(cl._card_copy_label("cleave") == " · copy 1", "  and so is copy one, when there are two (%s)" % cl._card_copy_label("cleave"))
	ck(cl._card_copy_label("power_strike") == "", "a card owned once carries no label")
	var inst: Array = cl._card_instances_sorted("cleave")
	ck(inst.size() == 2 and int(inst[0]["n"]) == 1 and String(inst[1]["key"]) == "cleave#2",
		"the deck screen gets both copies, in order (%s)" % str(inst))
	var src := FileAccess.get_file_as_string("res://client/client.gd")
	ck(src.contains("_ms_ability_label = _ability_display_name(ability_name) + _card_copy_label(ability_name)"),
		"the upgrade screen's title carries the copy label")
	cl.free()

	print("")
	print("RESULT: %s (%d failing)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
