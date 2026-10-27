class_name DayshiftMap
extends RefCounted

## Salvage Run's MAP (NightWatchMapRegistry): a ship and its scrap yard around the cargo bay. West of the bay: the gantry, the dock, the airlock and, off the dock, the engine room and the bridge.
## East of the bay: the gantry and the cargo hold. South of everything, the open scrap yard with the crane, which the bay's window looks onto and which both docks open onto. Ravelle comes in
## from the airlock along the gantry to the left door, Ceryth from the hold along the gantry to the right door, Ysolde from the crane across the yard to the window. Centres are in building space
## (the cargo bay at the origin, +z south). Not Classic's building: a long east-west ship with a yard.

static func map_layout() -> Dictionary:
	return {
		"rooms": {
			"airlock": Vector3(-29, 0, 0), "dockL": Vector3(-20, 0, 0), "gantryL": Vector3(-12, 0, 0), "engine": Vector3(-20, 0, -15.5), "bridge": Vector3(-6, 0, -16),
			"hold": Vector3(20, 0, 0), "gantryR": Vector3(12, 0, 0), "yard": Vector3(0, 0, 18), "crane": Vector3(10, 0, 20),
		},
		"edges": [
			["airlock", "dockL"], ["dockL", "gantryL"], ["dockL", "engine"], ["engine", "bridge"], ["dockL", "yard"],
			["hold", "gantryR"], ["hold", "yard"], ["yard", "crane"],
		],
		"entrances": ["gantryL", "gantryR", "yard"],
		"theme": "a ship and its scrap yard: gantry, dock, airlock, engine room and bridge to the west, gantry and cargo hold to the east, the open scrap yard with the crane to the south",
	}
