class_name RegionNames
extends RefCounted

## Biome / district / region names (MAZE, SEWER, HOTEL, a City district...) are for admins only. Players see the level
## number without the name everywhere the UI would print one (HUD level line, the City's zone panel, map region key, debug
## readouts). Each peer decides from its own admin state, so this is purely local and changes nothing in the room.

## Tests pin the answer: -1 = follow the admin state, 0 = player, 1 = admin.
static var override := -1


static func visible() -> bool:
	if override >= 0:
		return override == 1
	return Build.tools_enabled()


## The HUD level line: "LEVEL -1" for players, "LEVEL -1 // SEWER" for admins.
static func level_line(level: int, region: String) -> String:
	if visible() and not region.is_empty():
		return "LEVEL %+d // %s" % [level, region.to_upper()]
	return "LEVEL %+d" % level
