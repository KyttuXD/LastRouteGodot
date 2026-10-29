class_name VentNetwork
extends RefCounted

## The vents: crawl-only ducts threaded between the levels. Ducts run one cell wide on a fixed lattice (x = 6 and 38,
## z = 6 and 38 in every chunk) so they continue across every seam, and they live on their own layer (VENT_LEVEL) so
## nothing on a real level has to make room for them. Each chunk opens a few grates from a duct cell into a walkable
## cell of every level 0..+4 (a ceiling grate on level 0, wall grates above, a floor grate in the attic): LevelLink
## kind "grate" until the sewer lane adds "vent".
## Only a crawling body fits (DUCT_HEIGHT): a crouched runner, and a hunter on hands and knees (KT: hunters crawl the
## 1.25 m ducts; Verrine always, the others on Hard and Nightmare). Nobody stands up in one.

const CHUNK_SIZE := StreamedRouteGenerator.CHUNK_SIZE
const VENT_LEVEL := 100
const LINES := [6, 38]
## Storey height and the slab under the next floor (StreamedFacilityView3D.LEVEL_HEIGHT / SLAB).
const LEVEL_HEIGHT := 4.0
const SLAB := 0.1
## The duct's floor above the storey floor: the headroom under a duct (a 2.67 m hunter walks under it).
const DUCT_FLOOR := 2.7
## Inside height of a duct, floor to the slab: 1.2 m (1.3 m outside with the sheet metal; KT asked for about 1.25 m, and
## 1.25 inside would leave 2.65 m under the duct, less than a hunter). A crawling hunter (HUNTER_CRAWL_HEIGHT) and a
## crouched runner fit; nothing standing does.
const DUCT_HEIGHT := LEVEL_HEIGHT - SLAB - DUCT_FLOOR
## The body height a hunter crawls at in a duct (WORLD's VentCrawl uses this for the hunter's crawl capsule).
const HUNTER_CRAWL_HEIGHT := 1.15
const GRATES_PER_LEVEL := 1
const SOLID := 1
const DUCT := 0
const MOUNTS := {0: "ceiling", 1: "wall", 2: "wall", 3: "wall", 4: "floor"}
## KT: the ducts are real. On each storey a duct line is a sheet-metal box hung under the ceiling: floor DUCT_FLOOR above
## the storey floor, top at the slab; rooms and halls under it keep DUCT_FLOOR of headroom. A link's "duct_level" is the
## storey whose duct it opens into and "duct_y" the world height of that duct's floor.


static func is_duct_cell(cell: Vector2i) -> bool:
	return LINES.has(cell.x) or LINES.has(cell.y)

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


func _build_chunk(coord: Vector3i) -> Dictionary:
	var grid := []
	for z in CHUNK_SIZE:
		var row := []
		row.resize(CHUNK_SIZE)
		row.fill(SOLID)
		grid.append(row)
	for line in LINES:
		for i in CHUNK_SIZE:
			grid[line][i] = DUCT
			grid[i][line] = DUCT
	var rng := SeededRandom.new("%s:VENT:%d:%d" % [world_seed, coord.x, coord.z])
	var links := []
	var chunk_coord := Vector3i(coord.x, 0, coord.z)
	for level in MOUNTS:
		if not levels.has(level):
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
			link["duct_y"] = float(level) * LEVEL_HEIGHT + DUCT_FLOOR
			links.append(link)
	return {"chunk_id": chunk_id(coord), "coord": chunk_coord, "level": VENT_LEVEL, "grid": grid,
		"links": links, "duct_height": DUCT_HEIGHT, "duct_floor": DUCT_FLOOR,
		"edges": {"west": LINES, "east": LINES, "north": LINES, "south": LINES}}
