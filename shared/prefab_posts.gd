class_name PrefabPosts
extends RefCounted
## ⚑ VALOR-PURCHASED PREFAB POSTS — the front half of the Phantom loop.
##
## Owner 2026-09-17: *"players can purchase a semi-randomized buildable player post from the build
## menu and place it on a valid placement spot. It will cost a substantial amount of valor to buy.
## The cheapest will only have a market and a phantom surrounded by walls with one door and enough
## room to move around inside. More expensive ones will be larger and have more player structures
## like quest boards, workstations, etc."*
##
## And from the 2026-09-02 design: *"Building a post piece by piece is too slow to support this
## loop... Valor's current sinks are bounties, PvP payouts and repairs, so this becomes its major
## sink — size it against those."*
##
## ⛑ THE PHANTOM ITSELF IS NOT HERE YET, AND NO TIER MENTIONS ONE. A post whose whole point is the
## Phantom, sold before the Phantom exists, is a promise taken in Valor and not returned. These
## tiers are worth their price for the post alone — walls, a market, and at the top the stations a
## settlement needs — and the Phantom is added to the layouts when it works. Selling first and
## building after is the one thing this feature must not do.
##
## ⚑ PRICES ARE SET AGAINST WHAT PLAYERS ACTUALLY HOLD, measured on the live server 2026-09-19
## across 13 accounts:
##
##     68294  63835  47194  24550   1396   338   163    99    29   and FOUR at zero
##
## A hard split: four established accounts between 24K and 68K, everyone else under 1.5K. So the
## ladder is priced to be a real commitment for the top of that list and a visible goal for the
## rest — Waystation is reachable today by four players, Bastion by none.
##
## ⛑ WHAT THIS PRICING DOES **NOT** KNOW: the valor EARN rate. It is measured against holdings, a
## stock, not a flow - so it says how many players could buy today, and nothing about how long a
## new player would take to save. That is the number to measure before calling these final, and it
## is why they are one table in one file rather than scattered through the server.

## One rung. `stations` are the interactable tiles placed inside; `radius` is the half-width of the
## walled square, so a radius of 2 is the 5x5 the existing crafted kit builds.
const TIERS: Array = [
	{
		"id": "prefab_post_waystation",
		"name": "Waystation Charter",
		"valor": 12000,
		"radius": 3,          # 7x7 - "enough room to move around inside"
		"stations": ["market"],
		"blurb": "A walled yard with one door and a market. The smallest claim that still counts as a place.",
	},
	{
		"id": "prefab_post_outpost",
		"name": "Outpost Charter",
		"valor": 30000,
		"radius": 4,          # 9x9
		"stations": ["market", "quest_board", "workbench"],
		"blurb": "Room enough for a board and a bench, and walls that take a while to walk around.",
	},
	{
		"id": "prefab_post_bastion",
		"name": "Bastion Charter",
		"valor": 75000,
		"radius": 5,          # 11x11
		"stations": ["market", "quest_board", "workbench", "forge", "storage"],
		"blurb": "A settlement in everything but age. Everything a founder needs, and the walls to keep it.",
	},
]


static func tiers() -> Array:
	return TIERS


static func by_id(id: String) -> Dictionary:
	for t in TIERS:
		if String(t.get("id", "")) == id:
			return t
	return {}


static func is_prefab(id: String) -> bool:
	return not by_id(id).is_empty()


## Build the KIT_LAYOUTS-shaped tile list for a tier: a walled square with ONE door on the south
## face, and the stations spaced along the inside of the north wall.
##
## ⛑ GENERATED RATHER THAN HAND-LISTED. The existing `enclosure_kit_small` spells out all sixteen
## of its tiles, which is fine for one 5x5 and becomes a transcription exercise at 11x11 - and a
## wall with one tile missing is a post that monsters walk into. Deriving it means the perimeter
## cannot have a hole, at any size.
static func layout_for(id: String) -> Array:
	var t: Dictionary = by_id(id)
	if t.is_empty():
		return []
	var r: int = int(t.get("radius", 3))
	var out: Array = []
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var on_edge: bool = absi(dx) == r or absi(dy) == r
			if not on_edge:
				continue
			# ONE door, centred on the south face. The owner's words: "surrounded by walls with
			# one door". More than one is a different building.
			if dx == 0 and dy == -r:
				out.append({"dx": dx, "dy": dy, "type": "door"})
			else:
				out.append({"dx": dx, "dy": dy, "type": "wall"})
	# Stations along the inside of the north wall, spread evenly and never on the wall itself.
	var stations: Array = t.get("stations", [])
	var inner: int = r - 1
	var span: int = inner * 2 + 1
	for i in range(stations.size()):
		# Centre the row: for n stations across `span` columns, step them out from the middle.
		var offset: int = int(round((float(i) - float(stations.size() - 1) * 0.5) * 2.0))
		var sx: int = clampi(offset, -inner, inner)
		out.append({"dx": sx, "dy": inner, "type": String(stations[i])})
	return out
