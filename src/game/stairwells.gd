class_name Stairwells
extends RefCounted

## Enclosed stairwells between two levels (docs/SEWERS.md, "Stairwells"):
## LevelLink kinds "stairs" (a switchback: two ~2 m half-flights about a 180
## degree mid landing) and "spiral" (a helical slope about a central post).
## Pure seed maths, like the ramps: the upper and lower level of every pair
## agree on the footprint without reading each other, so the maze, the sewer
## and the upper levels (+1..+3, built by the upper-levels lane) all carve the
## same cells. Both kinds enter and leave by the same doorway column on both
## levels, on the side facing the chunk's central hall; the bottom landing and
## the top landing are the same cell one storey apart.
##
## Placement (per chunk column and upper level): 0 <-> -1 is sparse (ladders
## stay the main way down); +1..+3 follow the upper-levels lane's rules: one
## quadrant, clear of the spine x/z 21..23 and the duct lines 6 and 38, inside
## 2..41, thinning going up, and always one at chunk (0, 0).

const CHANCE := {0: .12, 1: .75, 2: .45, 3: .35}   # +1: the maze vetoes about a quarter of them (_maze_stairwell_fits)
const SPIRAL_SHARE := {0: .5, 1: 1.0, 2: .6, 3: .7}   # +1 is all spirals: the maze's banks are too shallow for a switchback
## The 9 x 9 cell area a stairwell (walls included) may use in each quadrant:
## inside 2..41, clear of the spine and of the duct lines 6 and 38.
const QUADRANT_AREAS := [Rect2i(7, 7, 9, 9), Rect2i(29, 7, 9, 9), Rect2i(7, 29, 9, 9), Rect2i(29, 29, 9, 9)]
## The maze's own areas for 0 <-> -1: every maze region runs main halls along
## rows 9-11 and 33-35 right across the chunk, and the sewer's cross tunnel
## fills rows and columns 18-26, so a stairwell fits only in the outer room
## bands (rows 0-8 and 36-44), inside one room column, its doorway opening
## straight onto a main hall (the chunk border is its back wall). The inner
## columns keep off the sewer's walkways (18-20, 24-26) and leave the landing
## more than a thin wall away from the maze's spine.
const MAZE_AREAS := [Rect2i(2, 0, 7, 9), Rect2i(11, 0, 7, 9), Rect2i(27, 0, 7, 9), Rect2i(36, 0, 7, 9),
	Rect2i(2, 36, 7, 9), Rect2i(11, 36, 7, 9), Rect2i(27, 36, 7, 9), Rect2i(36, 36, 7, 9)]
## The maze's areas for 0 <-> +1: the middle banks either side of the five-wide centre hall (rows 13-19 north, 26-32 south).
## A well here is always a spiral (7 x 7: a switchback is 9 deep and the banks are 8), its box inside one room of the
## bank (x 12-18 left, 26-32 right: clear of the duct lines 6 and 38 and of the spine), its doorway opening straight onto
## the centre hall.
const MAZE_UP_AREAS := [Rect2i(11, 11, 9, 9), Rect2i(25, 11, 9, 9), Rect2i(11, 25, 9, 9), Rect2i(25, 25, 9, 9)]
const RISE := 4.0                    # LEVEL_HEIGHT


## The stairwell from `upper_level` down one storey in column (x, z), or {}.
## `avoid` lists quadrants the caller already uses (the sewer's ramps / falls);
## `fits` (well -> bool), when given, vetoes a candidate, and the free areas
## are tried in a seeded order until one fits. `areas` are the candidate
## footprint areas (QUADRANT_AREAS, or MAZE_AREAS for the maze's own).
static func plan(world_seed: String, x: int, z: int, upper_level: int, avoid: Array = [],
		fits: Callable = Callable(), areas: Array = QUADRANT_AREAS) -> Dictionary:
	if not CHANCE.has(upper_level):
		return {}
	var rng := SeededRandom.new("%s:STAIRS:%d:%d:%d" % [world_seed, x, z, upper_level])
	var guaranteed := upper_level >= 1 and x == 0 and z == 0
	if rng.next_float() >= float(CHANCE[upper_level]) and not guaranteed:
		return {}
	var free := areas.filter(func(area: Rect2i) -> bool: return not avoid.has(quadrant_of(area)))
	var spiral := rng.next_float() < float(SPIRAL_SHARE[upper_level])
	while not free.is_empty():
		var area: Rect2i = free.pop_at(rng.next_index(free.size()))
		var well := _geometry(x, z, upper_level, area, "spiral" if spiral else "stairs")
		if not fits.is_valid() or fits.call(well):
			return well
	return {}


## Footprint, landings, shaft cells and the walk path, laid out with the doorway
## on the +z side and mirrored for quadrants south of the hall (doorway at -z).
static func _geometry(x: int, z: int, upper_level: int, area: Rect2i, kind: String) -> Dictionary:
	var quadrant := quadrant_of(area)
	var north := area.position.y < 22
	var wide := 7                                  # walls included
	var deep := 9 if kind == "stairs" else 7
	var box := Rect2i(area.position.x + (area.size.x - wide) / 2,
		area.position.y + (area.size.y - deep if north else 0), wide, deep)
	var interior := box.grow(-1)
	# canonical rows run 0 (far end) .. interior.size.y - 1 (doorway end)
	var flip := func(row: int) -> int:
		return interior.position.y + row if north else interior.end.y - 1 - row
	var col := func(c: int) -> int:
		return interior.position.x + c
	var last := interior.size.y - 1
	var landing := Vector2i(col.call(2), flip.call(last))
	var door_z: int = box.end.y - 1 if north else box.position.y
	# doorless openings are three wide (the switchback's spans its whole landing)
	var door := Rect2i(col.call(0) if kind == "stairs" else col.call(1), door_z, 5 if kind == "stairs" else 3, 1)
	var outward := 1 if north else -1
	var lower_landing := {}
	var upper_landing := {}
	var shaft := {}
	var path: Array[Vector3] = []
	var flights := []
	if kind == "stairs":
		# bottom landing: the doorway end, two rows, full width (also the top landing one storey up)
		for row in [last - 1, last]:
			for c in 5:
				lower_landing[Vector2i(col.call(c), flip.call(row))] = true
				upper_landing[Vector2i(col.call(c), flip.call(row))] = true
		for row in range(0, last - 1):
			for c in 5:
				shaft[Vector2i(col.call(c), flip.call(row))] = true
		# flight A up the left (cols 0-1) from the landing to the mid landing (rows 0-1, height 2),
		# flight B back down the right (cols 3-4) to the top landing; the middle column between
		# the flights is a solid divider
		var near_edge := float(flip.call(last - 1)) + (0.0 if north else 1.0)
		var far_edge := float(flip.call(2)) + (0.0 if north else 1.0)
		var mid_edge := float(flip.call(1)) + (1.0 if north else 0.0)
		flights = [
			{"x0": float(col.call(0)), "x1": float(col.call(2)), "z_low": near_edge, "z_high": far_edge, "y_low": 0.0, "y_high": RISE * .5},
			{"x0": float(col.call(3)), "x1": float(col.call(5)), "z_low": far_edge, "z_high": near_edge, "y_low": RISE * .5, "y_high": RISE},
		]
		var landing_c := Vector2(float(col.call(2)) + .5, float(flip.call(last)) + .5)
		var mid_z := float(flip.call(0)) + (1.0 if north else 0.0)
		path = [Vector3(landing_c.x, 0.0, landing_c.y), Vector3(float(col.call(1)), 0.0, near_edge),
			Vector3(float(col.call(1)), RISE * .5, far_edge), Vector3(float(col.call(1)), RISE * .5, (mid_edge + mid_z) * .5),
			Vector3(float(col.call(4)), RISE * .5, (mid_edge + mid_z) * .5), Vector3(float(col.call(4)), RISE * .5, far_edge),
			Vector3(float(col.call(4)), RISE, near_edge), Vector3(landing_c.x, RISE, landing_c.y)]
	else:
		# a three-cell landing at the doorway end; the helix starts and ends just past it
		for c in [1, 2, 3]:
			lower_landing[Vector2i(col.call(c), flip.call(last))] = true
			upper_landing[Vector2i(col.call(c), flip.call(last))] = true
		for row in range(0, last + 1):
			for c in 5:
				var cell := Vector2i(col.call(c), flip.call(row))
				if not lower_landing.has(cell):
					shaft[cell] = true
		var center := Vector2(interior.position.x + 2.5, interior.position.y + 2.5)
		# 270 degrees from the landing round to the landing, one storey up
		var start_angle := 45.0 if north else 225.0
		for i in 13:
			var t := float(i) / 12.0
			var angle := deg_to_rad(start_angle + 270.0 * t * (1.0 if north else 1.0))
			var dir := Vector2(sin(angle), cos(angle))
			path.append(Vector3(center.x + dir.x * 1.6, RISE * t, center.y + dir.y * 1.6))
		path.push_front(Vector3(landing.x + .5, 0.0, landing.y + .5))
		path.append(Vector3(landing.x + .5, RISE, landing.y + .5))
	var chunk := Vector3i(x, 0, z)
	var link := LevelLink.make(kind, chunk, upper_level, landing, upper_level - 1, landing)
	link["path"] = path
	return {"kind": kind, "upper": upper_level, "quadrant": quadrant, "north": north, "box": box, "interior": interior,
		"door": door, "outward": outward, "landing": landing, "lower_landing": lower_landing,
		"upper_landing": upper_landing, "shaft": shaft, "flights": flights, "link": link,
		"spiral_center": Vector2(interior.position.x + 2.5, interior.position.y + 2.5),
		"spiral_start": 45.0 if north else 225.0}


## Which quadrant of the chunk (0 NW, 1 NE, 2 SW, 3 SE) an area lies in.
static func quadrant_of(area: Rect2i) -> int:
	return (1 if area.get_center().x > 22 else 0) + (2 if area.get_center().y > 22 else 0)


## The corridor from a stairwell's doorway to a level's hall: `hall_edge` is the
## first row of the hall (the sewer tunnel's walkway, or the maze's central hall).
static func corridor(well: Dictionary, hall_edge: int) -> Rect2i:
	var door: Rect2i = well["door"]
	var x0 := door.position.x + door.size.x / 2 - 1
	if bool(well["north"]):
		return Rect2i(x0, door.position.y + 1, 3, maxi(0, hall_edge - door.position.y - 1))
	return Rect2i(x0, hall_edge + 1, 3, maxi(0, door.position.y - hall_edge - 1))


## Cells of a stairwell for one of its levels: "walk" (landing, doorway) and
## "shaft" (open well cells: stairs on the lower level, void on the upper).
static func cells_for(well: Dictionary, level: int) -> Dictionary:
	var upper := level == int(well["upper"])
	var out := {"walk": [], "shaft": []}
	for cell in (well["upper_landing"] if upper else well["lower_landing"]):
		out["walk"].append(cell)
	var door: Rect2i = well["door"]
	for cx in range(door.position.x, door.end.x):
		out["walk"].append(Vector2i(cx, door.position.y))
	for cell in well["shaft"]:
		out["shaft"].append(cell)
	return out
