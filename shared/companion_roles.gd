extends RefCounted
## Companion ROLES and TACTICS (backlog item 14, slice S1; design in docs/design/companion_roles_s0.md).
##
## A companion's role comes from its SPECIES through ONE table (role_for_species), derived from data the
## species already carries (its aggro and attack bonus) plus a short theme override for healers - only 3 of
## 53 species were natural healers, so eight are picked by theme. A variant never changes the role.
##
## What a companion DOES on its turn is `choose_action`, a pure function of (role, tactics, what is going on),
## so it can be probed without running a fight. Every magnitude lives here so nothing is a second copy.

const ROLE_TANK := "tank"
const ROLE_HEALER := "healer"
const ROLE_DPS := "dps"
const ROLE_UTILITY := "utility"
const ROLE_JACK := "jack"
const ROLES: Array = [ROLE_TANK, ROLE_HEALER, ROLE_DPS, ROLE_UTILITY, ROLE_JACK]

const TACTIC_BALANCED := "balanced"
const TACTIC_ALL_OUT := "all_out"
const TACTIC_PROTECT := "protect"
const TACTIC_SUPPORT := "support"
const TACTICS: Array = [TACTIC_BALANCED, TACTIC_ALL_OUT, TACTIC_PROTECT, TACTIC_SUPPORT]

const ACT_ATTACK := "attack"
const ACT_STRIKE := "strike"
const ACT_TAUNT := "taunt"
const ACT_HEAL := "heal"
const ACT_BUFF := "buff"
const ACT_DEBUFF := "debuff"

## Species the roster would not call healers by its numbers, picked by theme (owner 2026-10-15: "theme-pick
## about 8"). They gain the Heal action; their aggro and HP are untouched.
const HEALER_SPECIES: Array = ["Phoenix", "Wight", "Siren", "Sphinx", "Troll", "Vampire", "Succubus", "Lich"]

# Thresholds of the derivation (aggro is a percent of monster hits the companion soaks).
const TANK_MIN_AGGRO := 45
const UTILITY_MAX_AGGRO := 18
const DPS_MIN_ATTACK := 7

# Magnitudes. CAPS from the design (S0 ruling 6): a heal never exceeds 15% of the target's max HP, a
# buff is at most +20%, and one buff type never stacks with itself (it refreshes instead).
const HEAL_PCT := 0.12
const HEAL_PCT_CAP := 0.15
const BUFF_PCT := 15
const BUFF_PCT_CAP := 20
const BUFF_ROUNDS := 2
const DEBUFF_PCT := 12
const DEBUFF_ROUNDS := 2
const TAUNT_AGGRO := 40
const TAUNT_TURNS := 2
const STRIKE_MULT := 1.5
## The Jack-of-all-trades does whatever is needed, at this share of a specialist's strength.
const JACK_STRENGTH := 0.6
## After a role action the companion makes this many ordinary attacks before it can act again.
const ACTION_COOLDOWN := 2

const HEAL_BELOW_BALANCED := 0.50
const HEAL_BELOW_PROTECT := 0.80
const HEAL_BELOW_SUPPORT := 0.60
const HEAL_BELOW_ALL_OUT := 0.25
const TAUNT_BELOW_BALANCED := 0.75
const TAUNT_BELOW_SUPPORT := 0.60


static func role_for_species(species: String, aggro: int, attack_bonus: int) -> String:
	if species in HEALER_SPECIES:
		return ROLE_HEALER
	if aggro >= TANK_MIN_AGGRO:
		return ROLE_TANK
	if aggro <= UTILITY_MAX_AGGRO:
		return ROLE_UTILITY
	if attack_bonus >= DPS_MIN_ATTACK:
		return ROLE_DPS
	return ROLE_JACK


static func role_of(companion: Dictionary) -> String:
	"""A companion dictionary's role. Reads the species' own data so a companion saved before roles
	existed has one without any migration."""
	if companion.is_empty():
		return ROLE_JACK
	var species: String = str(companion.get("monster_type", ""))
	var data: Dictionary = DropTables.COMPANION_DATA.get(species, {})
	var bonuses: Dictionary = companion.get("bonuses", data.get("bonuses", {}))
	return role_for_species(species, int(bonuses.get("aggro", data.get("bonuses", {}).get("aggro", 25))), int(bonuses.get("attack", 0)))


static func tactics_of(companion: Dictionary) -> String:
	var t: String = str(companion.get("tactics", TACTIC_BALANCED))
	return t if t in TACTICS else TACTIC_BALANCED


static func next_tactics(current: String) -> String:
	var i: int = TACTICS.find(current)
	return TACTICS[(i + 1) % TACTICS.size()]


static func role_label(role: String) -> String:
	match role:
		ROLE_TANK: return "Tank"
		ROLE_HEALER: return "Healer"
		ROLE_DPS: return "Striker"
		ROLE_UTILITY: return "Utility"
	return "All-rounder"


static func tactics_label(tactics: String) -> String:
	match tactics:
		TACTIC_ALL_OUT: return "All out"
		TACTIC_PROTECT: return "Protect"
		TACTIC_SUPPORT: return "Support"
	return "Balanced"


static func tactics_blurb(tactics: String) -> String:
	match tactics:
		TACTIC_ALL_OUT: return "attacks; heals only to save you"
		TACTIC_PROTECT: return "guards you: heals early, draws hits"
		TACTIC_SUPPORT: return "buffs and weakens before attacking"
	return "attacks, and helps when you need it"


static func role_blurb(role: String) -> String:
	match role:
		ROLE_TANK: return "draws the monster's hits"
		ROLE_HEALER: return "heals you"
		ROLE_DPS: return "lands a heavy strike"
		ROLE_UTILITY: return "buffs you and weakens the enemy"
	return "fills whatever gap you have, at 60% strength"


static func strength_of(role: String) -> float:
	return JACK_STRENGTH if role == ROLE_JACK else 1.0


static func heal_fraction(role: String) -> float:
	return minf(HEAL_PCT_CAP, HEAL_PCT * strength_of(role))


static func buff_value(role: String) -> int:
	return mini(BUFF_PCT_CAP, int(round(float(BUFF_PCT) * strength_of(role))))


static func debuff_value(role: String) -> int:
	return int(round(float(DEBUFF_PCT) * strength_of(role)))


static func taunt_value(role: String) -> int:
	return int(round(float(TAUNT_AGGRO) * strength_of(role)))


static func choose_action(role: String, tactics: String, ctx: Dictionary) -> String:
	"""What the companion does this turn. ctx: owner_hp_pct (0-1), cooldown (int, 0 = ready),
	taunt_active (bool), buff_active (bool), debuff_active (bool)."""
	if int(ctx.get("cooldown", 0)) > 0:
		return ACT_ATTACK
	var hp: float = float(ctx.get("owner_hp_pct", 1.0))
	var heal_below: float = HEAL_BELOW_BALANCED
	match tactics:
		TACTIC_ALL_OUT: heal_below = HEAL_BELOW_ALL_OUT
		TACTIC_PROTECT: heal_below = HEAL_BELOW_PROTECT
		TACTIC_SUPPORT: heal_below = HEAL_BELOW_SUPPORT
	var taunt_ok: bool = false
	match tactics:
		TACTIC_PROTECT: taunt_ok = not bool(ctx.get("taunt_active", false))
		TACTIC_BALANCED: taunt_ok = hp < TAUNT_BELOW_BALANCED and not bool(ctx.get("taunt_active", false))
		TACTIC_SUPPORT: taunt_ok = hp < TAUNT_BELOW_SUPPORT and not bool(ctx.get("taunt_active", false))
	var can_buff: bool = not bool(ctx.get("buff_active", false))
	var can_debuff: bool = not bool(ctx.get("debuff_active", false))
	var needs_heal: bool = hp < heal_below
	match role:
		ROLE_TANK:
			return ACT_TAUNT if taunt_ok else ACT_ATTACK
		ROLE_HEALER:
			return ACT_HEAL if needs_heal else ACT_ATTACK
		ROLE_DPS:
			return ACT_ATTACK if tactics == TACTIC_PROTECT else ACT_STRIKE
		ROLE_UTILITY:
			if tactics == TACTIC_ALL_OUT:
				return ACT_DEBUFF if can_debuff else ACT_ATTACK
			if tactics == TACTIC_PROTECT:
				return ACT_BUFF if can_buff else ACT_ATTACK
			if can_buff and (tactics == TACTIC_SUPPORT or hp < TAUNT_BELOW_BALANCED):
				return ACT_BUFF
			return ACT_DEBUFF if can_debuff else ACT_ATTACK
		_:
			# Jack: heal if you are low, else taunt if that applies, else a buff, else attack.
			if needs_heal:
				return ACT_HEAL
			if taunt_ok:
				return ACT_TAUNT
			if tactics == TACTIC_SUPPORT and can_buff:
				return ACT_BUFF
			return ACT_ATTACK
