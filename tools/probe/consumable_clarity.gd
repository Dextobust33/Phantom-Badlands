extends SceneTree
## ⛑ HOW MANY CONSUMABLES ARE THERE, AND DOES THE NAME TELL YOU WHAT IT DOES?
##
## Owner 2026-09-18: *"there are too many of them and with names that make people not sure what
## they even give (especially in combat, you have to hover to try and remember what each of them
## give in the combat item list)"* - and, on quality: *"there were a lot of items that could get
## quality that didn't benefit enough to justify even having it."*
##
## Both are testable. A name is self-describing if it carries the EFFECT or a number; a quality
## tier is worth having if the gap between Standard and Masterwork is big enough to notice.
##
## ⛑ THE COMBAT LIST IS THE PLACE THIS HURTS, and it shows names only. So the test is not "is
## there a description somewhere" - there is, on hover - it is whether the NAME ALONE distinguishes
## one potion from the next at the moment you are choosing under pressure.
##
## Run:
##   godot --headless --path . --script res://tools/probe/consumable_clarity.gd

const CD := preload("res://shared/crafting_database.gd")

# Words that tell a player what the thing DOES, rather than what it is made of or how grand it is.
const EFFECT_WORDS := ["health", "healing", "heal", "mana", "stamina", "energy", "cure", "antidote",
	"strength", "defense", "speed", "regen", "restore", "revive", "escape", "invis", "shield",
	"resist", "poison", "fire", "frost", "luck", "xp", "experience"]
# Words that say only "this one is better", which is the shape the owner is describing.
const GRADE_WORDS := ["minor", "lesser", "greater", "major", "superior", "supreme", "grand",
	"master", "elixir", "draught", "tonic", "philter", "flask", "vial", "potion"]


func _init() -> void:
	var consumables: Array = []
	for rid in CD.RECIPES:
		var r: Dictionary = CD.RECIPES[rid]
		if String(r.get("output_type", "")) != "consumable":
			continue
		consumables.append({"id": String(rid), "name": String(r.get("name", rid)),
			"skill": int(r.get("skill_required", 0))})

	print("consumable recipes: %d" % consumables.size())
	print("")
	print("===== DOES THE NAME SAY WHAT IT DOES? =====")
	var named := 0
	var graded_only := 0
	var opaque: Array = []
	for c in consumables:
		var low := String(c["name"]).to_lower()
		var has_effect := false
		for w in EFFECT_WORDS:
			if low.find(w) >= 0:
				has_effect = true
				break
		var has_grade := false
		for w in GRADE_WORDS:
			if low.find(w) >= 0:
				has_grade = true
				break
		if has_effect:
			named += 1
		elif has_grade:
			graded_only += 1
			opaque.append(String(c["name"]))
		else:
			opaque.append(String(c["name"]))
	print("  %d of %d name their effect" % [named, consumables.size()])
	print("  %d of %d say only how GOOD they are, not what they DO" % [graded_only, consumables.size()])
	if not opaque.is_empty():
		print("")
		print("  cannot be told apart by name alone:")
		for n in opaque:
			print("    %s" % n)

	print("")
	print("===== HOW MANY DO THE SAME JOB? =====")
	# ⛑ "Too many" is a claim about DUPLICATION, not about the raw count. Six healing potions with
	# different names is a different problem from six potions that each do something different.
	var by_effect: Dictionary = {}
	for c in consumables:
		var low := String(c["name"]).to_lower()
		var eff := "(unclassified)"
		for w in EFFECT_WORDS:
			if low.find(w) >= 0:
				eff = w
				break
		if not by_effect.has(eff):
			by_effect[eff] = []
		by_effect[eff].append(String(c["name"]))
	var effs: Array = by_effect.keys()
	effs.sort()
	for e in effs:
		var lst: Array = by_effect[e]
		if lst.size() >= 2:
			print("  %-10s x%d   %s" % [String(e), lst.size(), ", ".join(lst)])

	print("")
	print("===== WHAT QUALITY IS WORTH ON ONE =====")
	# Standard 1.0 -> Masterwork 1.5. On a potion that restores a flat amount, that is the whole
	# benefit; the owner's point is whether it is ever enough to notice.
	print("  quality ladder: Poor %.2fx  Standard %.2fx  Fine %.2fx  Masterwork %.2fx" % [
		float(CD.QUALITY_MULTIPLIERS[CD.CraftingQuality.POOR]),
		float(CD.QUALITY_MULTIPLIERS[CD.CraftingQuality.STANDARD]),
		float(CD.QUALITY_MULTIPLIERS[CD.CraftingQuality.FINE]),
		float(CD.QUALITY_MULTIPLIERS[CD.CraftingQuality.MASTERWORK])])
	print("  so the whole spread a player can influence is Standard->Masterwork = +50%,")
	print("  and Fine->Masterwork = +20%. On a 50 HP potion that is +25 HP and +10 HP.")

	print("")
	print("[PROBE] measurement only - the shape is the finding.")
	quit()
