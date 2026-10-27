class_name NightWatchDescentMap
extends RefCounted

## The Descent's MAP (docs/NIGHT_WATCH_OFFICES.md, "Maps"): a stairwell and shaft, seen in plan, never Classic's building. The car (the office) hangs in the
## shaft; outside each caged window runs a sill, and from the sills Elise comes down (or up) the stairwell: a flight of landings on the left, a pipe gallery
## and a fuse closet on the right, a signal hall at the bottom joining the two. The 3D set (NightWatchDescentWorld) shows the stairwell landings, the pipe runs
## and the fuse cabinets in the shaft; Elise herself walks the sill continuously (closeness 0..100 from SILL_FAR to SILL_NEAR, descent_game.gd), so the two sill
## rooms are where the map meets the office: they are the entrances, and the office spec's window entrances (sim_room "L" / "R") stand at their ends.
## Metres, building space (x right, z back from the car), levels are 3 m apart in y.

static func map_layout() -> Dictionary:
	var rooms := {
		"car": Vector3(0, 0, 0),
		"sill_l": Vector3(-1.2, 0, -3.6),
		"sill_r": Vector3(1.2, 0, -3.6),
		"shaft": Vector3(0, -3, -6),
		"stair_1": Vector3(-6, 0, -6),
		"stair_2": Vector3(-6, -3, -10),
		"stair_3": Vector3(-6, -6, -14),
		"stair_4": Vector3(-6, -9, -18),
		"pipe_gallery": Vector3(6, -3, -7),
		"fuse_closet": Vector3(7, -6, -12),
		"signal_hall": Vector3(0, -9, -17),
	}
	var edges := [
		["car", "sill_l"], ["car", "sill_r"], ["sill_l", "shaft"], ["sill_r", "shaft"],
		["sill_l", "stair_1"], ["stair_1", "stair_2"], ["stair_2", "stair_3"], ["stair_3", "stair_4"], ["stair_4", "signal_hall"],
		["sill_r", "pipe_gallery"], ["pipe_gallery", "fuse_closet"], ["fuse_closet", "signal_hall"],
	]
	return {"rooms": rooms, "edges": edges, "entrances": ["sill_l", "sill_r"],
		"theme": "service elevator shaft: a car with two caged windows, sills, a stairwell of landings down the left, a pipe gallery and fuse closet on the right, a signal hall at the bottom"}
