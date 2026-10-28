class_name MezzanineRouteGenerator
extends RefCounted

## The Mezzanine void (VoidRegion): one huge open shaft, levels -3..+1, no walls, ceilings, slabs or props inside its
## footprint. Every level of it is a chunk of this generator: the shared three-wide catwalk cross (UpperLevelTools) as
## grating, a railed DECK ledge round the footprint's edge (where the neighbouring chunks' seam openings let you in), and
## at the tower chunk a continuous spiral stair from the Inferno floor to the Mezzanine. Level +1 also hangs solid-decked
## balconies off the cross and is roofed over the whole footprint; level -3 has a floor over the whole footprint (the
## pit: drawn and solid, not walkable for navigation) and falling onto it is fatal. There are no windows to look out of
## (lore: glass stays dark). Outside the footprint level +1 does not exist.

const CHUNK_SIZE := StreamedRouteGenerator.CHUNK_SIZE
const LEVEL := 1
const SURFACE_LEVEL := 0

## Grid codes. OPEN is air (nobody walks there). GRATE is see-through catwalk, DECK a solid floor; both are walkable.
## PIT is the floor at the bottom of the void: drawn and solid like a deck, but navigation never uses it.
const GRATE := 0
const OPEN := 1
const DECK := 2
const PIT := 3

const BALCONY_HALF := 3          # 7 x 7 balcony decks
const BALCONY_KINDS := ["overlook", "gantry_office", "storage_platform"]
## Railings line every edge that drops to OPEN or PIT.
const RAIL_HEIGHT := 1.1

var world_seed: String
var surface: StreamedRouteGenerator
var _cache := {}


func _init(p_surface: StreamedRouteGenerator) -> void:
	surface = p_surface
	world_seed = p_surface.world_seed


static func is_walkable(code: int) -> bool:
	return code == GRATE or code == DECK


func is_chunk_allowed(coord: Vector3i) -> bool:
	return coord.y == LEVEL or VoidRegion.is_void_chunk(world_seed, coord)


func chunk_id(coord: Vector3i) -> String:
	return "%s:%d:%d:%d" % ["VOID" if VoidRegion.is_void_chunk(world_seed, coord) else "MEZZANINE", coord.x, coord.y, coord.z]


func chunk(coord: Vector3i) -> Dictionary:
	var key := chunk_id(coord)
	if not _cache.has(key):
		_cache[key] = _build_chunk(coord)
	return _cache[key]


func links_for(coord: Vector3i) -> Array:
	return chunk(coord)["links"]


func _build_chunk(coord: Vector3i) -> Dictionary:
	if VoidRegion.is_void_chunk(world_seed, coord):
		return _build_void_chunk(coord)
	if coord.y == LEVEL:
		return _build_deck_chunk(coord)
	return _schema(coord, UpperLevelTools.filled(OPEN), [], [], [])


## The ordinary +1 over a maze chunk: the catwalk cross, two or three balconies, the way up from level 0.
func _build_deck_chunk(coord: Vector3i) -> Dictionary:
	var grid := UpperLevelTools.filled(OPEN)
	UpperLevelTools.carve_cross(grid, GRATE)
	var rng := SeededRandom.new("%s:MEZZANINE:%d:%d" % [world_seed, coord.x, coord.z])
	var order := UpperLevelTools.shuffled_quadrants(rng)
	var balcony_count := 2 + rng.next_index(2)
	var wants_up := UpperLevelTools.wants_up(LEVEL, coord, rng)
	var rooms := []
	var links := []
	var features := []
	# The stairwell up from level 0 (the maze chunk below decided it and carved the same cells) takes its quadrant; the
	# balconies hang in the others.
	var well := surface.stairwell_between(coord.x, coord.z, LEVEL)
	var well_quadrant: int = int(well["quadrant"]) if not well.is_empty() else -1
	var free_order: Array = order.filter(func(q: int) -> bool: return q != well_quadrant)
	balcony_count = mini(balcony_count, free_order.size())
	for slot in balcony_count:
		var quadrant: int = free_order[slot]
		var qc: Vector2i = UpperLevelTools.QUADRANT_CENTERS[quadrant]
		var rect := Rect2i(qc - Vector2i(BALCONY_HALF, BALCONY_HALF), Vector2i.ONE * (BALCONY_HALF * 2 + 1))
		UpperLevelTools.carve(grid, rect, DECK)
		UpperLevelTools.connect_to_cross(grid, qc, GRATE, [DECK])
		var kind: String = BALCONY_KINDS[rng.next_index(BALCONY_KINDS.size())]
		rooms.append({"kind": kind, "rect": rect, "center": qc})
		if slot == 0 and wants_up:
			# Provisional: the Offices (+2) are not hooked up yet.
			var foot := UpperLevelTools.up_cell(quadrant)
			var up := LevelLink.make("stairs", coord, LEVEL + 1, foot, LEVEL, foot)
			up["provisional"] = true
			links.append(up)
			features.append({"type": "stairFoot", "cell": foot, "link": up["id"]})
	var stairwells := []
	if not well.is_empty():
		stairwells.append(well)
		_carve_stairwell_top(grid, well, LEVEL)
		links.append(well["link"])
		features.append({"type": "stairLanding", "cell": well["landing"], "link": (well["link"] as Dictionary)["id"]})
	features.append_array(_rails(grid))
	var data := _schema(coord, grid, rooms, links, features)
	data["stairwells"] = stairwells
	data["shaft_cells"] = _shaft_cells(stairwells, LEVEL)
	return data


## One level of the Mezzanine void (VoidRegion).
func _build_void_chunk(coord: Vector3i) -> Dictionary:
	var level := coord.y
	var grid := UpperLevelTools.filled(PIT if level == VoidRegion.BOTTOM_LEVEL else OPEN)
	UpperLevelTools.carve_cross(grid, GRATE)
	for z in CHUNK_SIZE:
		for x in CHUNK_SIZE:
			if VoidRegion.on_ledge(world_seed, coord, x, z):
				grid[z][x] = DECK
	var rng := SeededRandom.new("%s:MEZZANINE:%d:%d:%d" % [world_seed, coord.x, level, coord.z])
	var rooms := []
	var links := []
	var features := []
	var stairwells := []
	var tower := VoidRegion.tower_chunk(world_seed)
	var tower_here := coord.x == tower.x and coord.z == tower.y
	if tower_here:
		for upper in [level, level + 1]:
			var well := VoidRegion.tower_well(world_seed, upper)
			if well.is_empty():
				continue
			stairwells.append(well)
			links.append(well["link"])
		for well in stairwells:
			_carve_stairwell_top(grid, well, level)
		for well in stairwells:
			features.append({"type": "stairLanding", "cell": well["landing"], "link": (well["link"] as Dictionary)["id"]})
	if level == LEVEL:
		var order := UpperLevelTools.shuffled_quadrants(rng)
		var balcony_count := 2 + rng.next_index(2)
		var wants_up := UpperLevelTools.wants_up(LEVEL, coord, rng)
		var well_quadrant: int = int(Stairwells.quadrant_of(Stairwells.QUADRANT_AREAS[0])) if tower_here else -1
		var free_order: Array = order.filter(func(q: int) -> bool: return q != well_quadrant)
		balcony_count = mini(balcony_count, free_order.size())
		for slot in balcony_count:
			var quadrant: int = free_order[slot]
			var qc: Vector2i = UpperLevelTools.QUADRANT_CENTERS[quadrant]
			var rect := Rect2i(qc - Vector2i(BALCONY_HALF, BALCONY_HALF), Vector2i.ONE * (BALCONY_HALF * 2 + 1))
			UpperLevelTools.carve(grid, rect, DECK)
			UpperLevelTools.connect_to_cross(grid, qc, GRATE, [DECK])
			var kind: String = BALCONY_KINDS[rng.next_index(BALCONY_KINDS.size())]
			rooms.append({"kind": kind, "rect": rect, "center": qc})
			if slot == 0 and wants_up:
				# Provisional: the Offices (+2) are not hooked up yet.
				var foot := UpperLevelTools.up_cell(quadrant)
				var up := LevelLink.make("stairs", coord, LEVEL + 1, foot, LEVEL, foot)
				up["provisional"] = true
				links.append(up)
				features.append({"type": "stairFoot", "cell": foot, "link": up["id"]})
	features.append_array(_rails(grid))
	if level == LEVEL:
		features.append_array(_outer_rails(coord, grid))
	var data := _schema(coord, grid, rooms, links, features)
	data["stairwells"] = stairwells
	data["shaft_cells"] = _shaft_cells(stairwells, level)
	# the keys every maze chunk carries, empty: nothing is furnished, picked up or spawned in the void
	for key in ["region_props", "fixtures", "pickups", "hunter_spawns", "corridors", "suites", "stairs"]:
		data[key] = []
	data["safe_room"] = false
	data["safe_room_data"] = {}
	data["ambience_level"] = "void"   # the shaft's own bed on every level of it (LevelAmbience.key_for)
	data["void_cap"] = level == VoidRegion.TOP_LEVEL
	data["void_floor"] = level == VoidRegion.BOTTOM_LEVEL
	return data


## A stairwell of the tower on this level: its box is air (or pit floor at the bottom), the landing and doorway are
## deck, and a catwalk runs from the doorway to the cross.
static func _carve_stairwell_top(grid: Array, well: Dictionary, level: int) -> void:
	UpperLevelTools.carve(grid, well["box"], PIT if level == VoidRegion.BOTTOM_LEVEL else OPEN)
	var north: bool = well["north"]
	var door: Rect2i = well["door"]
	var hall_edge: int = UpperLevelTools.CENTER - UpperLevelTools.CROSS_HALF if north else UpperLevelTools.CENTER + UpperLevelTools.CROSS_HALF
	var lane := Stairwells.corridor(well, hall_edge)
	UpperLevelTools.carve(grid, Rect2i(lane.position.x, lane.position.y, lane.size.x, lane.size.y), GRATE)
	for cell in Stairwells.cells_for(well, level)["walk"]:
		grid[cell.y][cell.x] = DECK
	# the doorway row is deck too, so the landing meets the catwalk without a gap
	for x in range(door.position.x, door.end.x):
		grid[door.position.y][x] = DECK


static func _shaft_cells(stairwells: Array, level: int) -> Dictionary:
	var out := {}
	for well in stairwells:
		for cell in well["shaft"]:
			out[cell] = {"upper": int(well["upper"]) == level, "well": well}
	return out


## A railing on every walkable edge that drops to open air or the pit (chunk seams stay open: the cross continues next door).
static func _rails(grid: Array) -> Array:
	var rails := []
	for z in CHUNK_SIZE:
		for x in CHUNK_SIZE:
			if not is_walkable(int(grid[z][x])):
				continue
			for dir in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n: Vector2i = Vector2i(x, z) + dir
				if n.x < 0 or n.y < 0 or n.x >= CHUNK_SIZE or n.y >= CHUNK_SIZE:
					continue
				var beyond := int(grid[n.y][n.x])
				if beyond == OPEN or beyond == PIT:
					rails.append({"type": "catwalkRail", "cell": Vector2i(x, z), "side": dir})
	return rails


## Where the void's +1 ledge meets the ordinary +1 deck of the next chunk (the outside of the footprint), the ledge is
## railed on its outer edge except at the neighbour's catwalk lane (the cross, rows/columns 21-23), which opens onto it.
func _outer_rails(coord: Vector3i, grid: Array) -> Array:
	var rails := []
	var lane := range(UpperLevelTools.CENTER - UpperLevelTools.CROSS_HALF, UpperLevelTools.CENTER + UpperLevelTools.CROSS_HALF + 1)
	for dir in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var next := Vector3i(coord.x + dir.x, coord.y, coord.z + dir.y)
		if VoidRegion.is_void_chunk(world_seed, next):
			continue
		for i in CHUNK_SIZE:
			var cell := Vector2i(0 if dir == Vector2i.LEFT else CHUNK_SIZE - 1, i) if dir.x != 0 else Vector2i(i, 0 if dir == Vector2i.UP else CHUNK_SIZE - 1)
			if is_walkable(int(grid[cell.y][cell.x])) and not lane.has(i):
				rails.append({"type": "catwalkRail", "cell": cell, "side": dir})
	return rails


## Level-0 cells under see-through grating: where a hunter below can spot a runner above (and the reverse). None inside
## the void (nothing below its catwalks but more void).
func sight_cells(coord: Vector3i) -> Array:
	if VoidRegion.contains(world_seed, coord.x, coord.z):
		return []
	var data := chunk(Vector3i(coord.x, LEVEL, coord.z))
	var below: Array = surface.chunk(Vector3i(coord.x, SURFACE_LEVEL, coord.z))["grid"]
	var cells := []
	for z in CHUNK_SIZE:
		for x in CHUNK_SIZE:
			if int(data["mezzanine_grid"][z][x]) == GRATE and int(below[z][x]) == 0:
				cells.append(Vector2i(x, z))
	return cells


func _schema(coord: Vector3i, own: Array, rooms: Array, links: Array, features: Array) -> Dictionary:
	return UpperLevelTools.schema("mezzanine", chunk_id(coord), coord, own, is_walkable, "mezzanine_grid", rooms, links, features, 0.0)
