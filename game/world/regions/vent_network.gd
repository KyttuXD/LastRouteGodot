class_name VentNetwork
extends RefCounted

## The vents: crawl-only ducts threaded between the levels. Ducts run one cell wide on a fixed lattice (x = 6 and 38,
## z = 6 and 38 in every chunk) so they continue across every seam, and they live on their own layer (VENT_LEVEL) so
## nothing on a real level has to make room for them. Each chunk opens a few grates from a duct cell into a walkable
## cell of every level 0..+4 (a ceiling grate on level 0, wall grates above, a floor grate in the attic): LevelLink
## kind "grate" until the sewer adds "vent".
## Only a crawling body fits (DUCT_HEIGHT): a crouched runner, and a hunter on hands and knees (hunters crawl the
## 1.25 m ducts; Verrine always, the others on Hard and Nightmare). Nobody stands up in one.

const CHUNK_SIZE := StreamedRouteGenerator.CHUNK_SIZE
const VENT_LEVEL := 100
const LINES := [6, 38]
## Storey height and the slab under the next floor (StreamedFacilityView3D.LEVEL_HEIGHT / SLAB).
const LEVEL_HEIGHT := 4.0
const SLAB := 0.1
## Storey 0's ducts run in the plenum between its ordinary ceilings and the next built floor ("make the ducts go
## between the levels themselves, with visible ducts being for taller areas only"). Corridors top out at 4.6 m and rooms
## at 4.4 m (RefLook.CORRIDOR_RANGE / ROOM_RANGE / the gothic range), so a duct whose sheet-metal underside sits above
## PLENUM_CLEARANCE is hidden over them and shows only where it crosses a taller hall or glasshouse (4.8 to 7.5 m). The
## next floor that can stand over storey 0 is the offices at 8 m (the mezzanine decks at 4 m get no ducts: has_ducts).
const PLENUM_CLEARANCE := 4.6
## The duct's floor above the storey floor.
const DUCT_FLOOR := 4.8
## Inside height of a duct, floor to roof: 1.2 m (1.3 m outside with the sheet metal, about 1.25 m wanted). A
## crawling hunter (HUNTER_CRAWL_HEIGHT) and a crouched runner fit; nothing standing does.
const DUCT_HEIGHT := 1.2
## The upper storeys have no plenum yet (4 m floor to floor, the ceiling at the slab): their grates' ducts are still
## logical, under the ceiling at the old height (PlayerController3D.VENT_STOREYS has only storey 0 physical).
const UPPER_DUCT_FLOOR := 2.7
## The body height a hunter crawls at in a duct (WORLD's VentCrawl uses this for the hunter's crawl capsule).
const HUNTER_CRAWL_HEIGHT := 1.15
const GRATES_PER_LEVEL := 1
const SOLID := 1
const DUCT := 0
const MOUNTS := {0: "ceiling", 1: "wall", 2: "wall", 3: "wall", 4: "floor"}
## the ducts are real. On storey 0 a duct line is a sheet-metal box in the plenum: floor DUCT_FLOOR above the storey
## floor, DUCT_HEIGHT inside. A link's "duct_level" is the storey whose duct it opens into and "duct_y" the world height
## of that duct's floor.


static func is_duct_cell(cell: Vector2i) -> bool:
	return LINES.has(cell.x) or LINES.has(cell.y)


## True for a lattice cell storey 0 can crawl: a duct cell of a chunk with a plenum (has_ducts).
func crawlable(cell: Vector2i) -> bool:
	var cx := floori(float(cell.x) / CHUNK_SIZE)
	var cz := floori(float(cell.y) / CHUNK_SIZE)
	var data := chunk(Vector3i(cx, 0, cz))
	return bool(data["ducted"]) and int((data["grid"] as Array)[cell.y - cz * CHUNK_SIZE][cell.x - cx * CHUNK_SIZE]) == DUCT


## World height of the duct floor on `level` (see UPPER_DUCT_FLOOR).
static func duct_floor_y(level: int) -> float:
	return float(level) * LEVEL_HEIGHT + (DUCT_FLOOR if level == 0 else UPPER_DUCT_FLOOR)

var world_seed: String
var surface: StreamedRouteGenerator
## Level number -> that level's generator (0 is the maze).
var levels := {}
var _cache := {}


func _init(p_surface: StreamedRouteGenerator, p_upper: Array) -> void:
	surface = p_surface
	levels[0] = p_surface
	for generator in p_upper:
		levels[int(generator.LEVEL)] = generator
	world_seed = p_surface.world_seed


func chunk_id(coord: Vector3i) -> String:
	return "VENT:%d:%d" % [coord.x, coord.z]


func chunk(coord: Vector3i) -> Dictionary:
	var key := chunk_id(coord)
	if not _cache.has(key):
		_cache[key] = _build_chunk(coord)
	return _cache[key]


## The grates touching `level` in this chunk.
func grates_for(coord: Vector3i, level: int) -> Array:
	var result := []
	for link in chunk(coord)["links"]:
		if int(link["from_level"]) == level:
			result.append(link)
	return result


func _level_grid(coord: Vector3i, level: int) -> Array:
	return levels[level].chunk(Vector3i(coord.x, level, coord.z))["grid"]


## False where storey 0 has no plenum for a duct: under a mezzanine deck (its catwalks stand at 4 m, in the duct band)
## and in the void. The lattice (the chunk's "grid") and the upper storeys' logical grates stay; storey 0 gets no duct,
## no grate, and no crawling there ("ducted" false: VentCrawl and VentNav stop at the chunk's edge, the view caps the line).
func has_ducts(coord: Vector3i) -> bool:
	var column := Vector3i(coord.x, StreamedRouteGenerator.MEZZANINE_LEVEL, coord.z)
	return not surface.is_void_column(column) and not surface.is_chunk_allowed(column)


func _build_chunk(coord: Vector3i) -> Dictionary:
	var grid := []
	for z in CHUNK_SIZE:
		var row := []
		row.resize(CHUNK_SIZE)
		row.fill(SOLID)
		grid.append(row)
	var ducted := has_ducts(coord)
	for line in LINES:
		for i in CHUNK_SIZE:
			grid[line][i] = DUCT
			grid[i][line] = DUCT
	var rng := SeededRandom.new("%s:VENT:%d:%d" % [world_seed, coord.x, coord.z])
	var links := []
	var chunk_coord := Vector3i(coord.x, 0, coord.z)
	for level in MOUNTS:
		if not levels.has(level) or (level == 0 and not ducted):
			continue
		var level_grid := _level_grid(coord, level)
		var candidates := []
		for line in LINES:
			for i in range(2, CHUNK_SIZE - 2):
				for cell in [Vector2i(i, line), Vector2i(line, i)]:
					if int(level_grid[cell.y][cell.x]) == 0:
						candidates.append(cell)
		for n in mini(GRATES_PER_LEVEL, candidates.size()):
			var cell: Vector2i = candidates[rng.next_index(candidates.size())]
			var link := LevelLink.make("grate", chunk_coord, level, cell, VENT_LEVEL, cell)
			link["mount"] = MOUNTS[level]
			link["duct_level"] = level
			link["duct_y"] = duct_floor_y(level)
			links.append(link)
	return {"chunk_id": chunk_id(coord), "coord": chunk_coord, "level": VENT_LEVEL, "grid": grid,
		"links": links, "duct_height": DUCT_HEIGHT, "duct_floor": DUCT_FLOOR,
		"edges": {"west": LINES, "east": LINES, "north": LINES, "south": LINES}, "ducted": ducted}
