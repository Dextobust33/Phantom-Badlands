extends SceneTree
func _init():
	var DB = load("res://shared/path_database.gd")
	var n = DB.find_node("warrior_2_5")
	print("warrior_2_5: %s | tier %d | keystone %s | prereq %s" % [n.get("name"), n.get("tier"), n.get("keystone", false), DB.get_prereq_id("warrior_2_5")])
	var ck = DB.find_node("ck_Ninja")
	print("ck_Ninja: %s | class_lock %s | prereq '%s'" % [ck.get("name"), ck.get("class_lock"), DB.get_prereq_id("ck_Ninja")])
	var t1 = DB.find_node("mage_1_1")
	print("mage_1_1: %s | prereq '%s' (expect empty)" % [t1.get("name"), DB.get_prereq_id("mage_1_1")])
	print("unknown: %s (expect {})" % [DB.find_node("nope")])
	var count = 0
	for arch in DB.TREES:
		for b in DB.TREES[arch]["branches"]:
			count += b["nodes"].size()
		count += DB.TREES[arch]["class_keystones"].size()
	print("total nodes: %d (expect 54 = 3*(15+3))" % count)
	quit()
