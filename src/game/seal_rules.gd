class_name SealRules
extends RefCounted

## The sealed-map rules every level reads (KT: "more sealed", approved 2026-10-28): how much of a chunk is open with
## no seal broken, how many seals it carries, where its relays sit and how many tools keep up, all by ring distance
## from spawn. One table for every level (maze 0, the upper levels +1..+5, the sewer lane's -1..-3); a level may
## override single values in LEVEL_OVERRIDES. Each level themes its seals with its own prop kinds (LEVEL_SEALS); the
## props lane owns the interactables and the shared "stream_breach" event that opens them.

## [first ring, open share, seals per chunk]. Ring = Chebyshev chunk distance from spawn.
const RINGS := [
	[0, 0.75, 1.5],
	[2, 0.50, 2.5],
	[5, 0.35, 3.5],
	[9, 0.25, 5.0],
]
## Sealed ground: chained wings (each with 0-2 further seals onward) vs single hidden rooms.
const WING_SHARE := 0.75
const WING_ONWARD_SEALS := Vector2i(0, 2)
## Relays: every chunk keeps at least one reachable with zero seals opened; the second sits behind a seal this often;
## some chunks add a bonus relay deep in chained wings.
const ZERO_BREAK_RELAYS := 1
const SECOND_RELAY_SEALED := 0.80
const BONUS_RELAY_CHANCE := 0.25
## Tools keep pace: a guaranteed tool on open ground in every chunk past GUARANTEED_TOOL_RING, and a second-tool
## chance from SECOND_TOOL_RING out.
const GUARANTEED_TOOL_RING := 2
const SECOND_TOOL_RING := 5
const SECOND_TOOL_CHANCE := 0.5
const TOOL_MIX := {"crowbar": 0.45, "axe": 0.30, "lockpick": 0.25}
## Seal kinds and their share (props lane interactables).
const SEAL_MIX := {"barricade": 0.40, "locked_door": 0.25, "weak_wall": 0.20, "vent_grate": 0.15}
## Opening a seal draws nearby hunters to investigate for this long (on top of each hit's noise burst).
const INVESTIGATE_SECONDS := 20.0
## Per-level flavour: each seal kind's themed form on that level ("" = that kind does not occur there).
const LEVEL_SEALS := {
	0: {"barricade": "boardedDoorway", "locked_door": "lockedDoor", "weak_wall": "weakWall", "vent_grate": "ventGrate"},
	1: {"barricade": "", "locked_door": "lockedCatwalkGate", "weak_wall": "", "vent_grate": "ventGrate"},
	2: {"barricade": "barricadedSuite", "locked_door": "lockedOfficeDoor", "weak_wall": "weakWall", "vent_grate": "ventGrate"},
	3: {"barricade": "chainedShelving", "locked_door": "lockedRecordVault", "weak_wall": "", "vent_grate": "ventGrate"},
	4: {"barricade": "boardedHatch", "locked_door": "", "weak_wall": "weakPlaster", "vent_grate": "ventGrate"},
	5: {"barricade": "vineChokedDoorway", "locked_door": "", "weak_wall": "", "vent_grate": ""},
}
## Single values a level changes (key -> value), e.g. {5: {"tool_mix": {"axe": 1.0}}} once the Overgrowth exists.
const LEVEL_OVERRIDES := {
	5: {"tool_mix": {"axe": 1.0}},
}


static func ring(coord: Vector3i) -> int:
	return maxi(absi(coord.x), absi(coord.z))


static func _band(coord: Vector3i) -> Array:
	var r := ring(coord)
	var band: Array = RINGS[0]
	for entry in RINGS:
		if r >= int(entry[0]):
			band = entry
	return band


static func open_share(coord: Vector3i) -> float:
	return float(_band(coord)[1])


static func seals_per_chunk(coord: Vector3i) -> float:
	return float(_band(coord)[2])


static func tool_mix(level: int) -> Dictionary:
	return (LEVEL_OVERRIDES.get(level, {}) as Dictionary).get("tool_mix", TOOL_MIX)


## The seal mix a level actually uses: SEAL_MIX restricted to the kinds that level themes, renormalised.
static func seal_mix(level: int) -> Dictionary:
	var themed: Dictionary = LEVEL_SEALS.get(level, LEVEL_SEALS[0])
	var total := 0.0
	for kind in SEAL_MIX:
		if String(themed.get(kind, "")) != "":
			total += float(SEAL_MIX[kind])
	var mix := {}
	for kind in SEAL_MIX:
		if String(themed.get(kind, "")) != "":
			mix[kind] = float(SEAL_MIX[kind]) / total
	return mix


static func seal_prop(level: int, kind: String) -> String:
	return String((LEVEL_SEALS.get(level, LEVEL_SEALS[0]) as Dictionary).get(kind, ""))


static func guaranteed_tool(coord: Vector3i) -> bool:
	return ring(coord) >= GUARANTEED_TOOL_RING


static func second_tool_chance(coord: Vector3i) -> float:
	return SECOND_TOOL_CHANCE if ring(coord) >= SECOND_TOOL_RING else 0.0
