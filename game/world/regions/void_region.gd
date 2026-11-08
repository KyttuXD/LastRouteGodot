class_name VoidRegion
extends RefCounted

## The Mezzanine void ("the void thing"): ONE huge shaft per map, SIZE x SIZE chunks, rare and chosen by the seed.
## Inside its footprint no level generates walls, ceilings, slabs or props: from the Inferno floor (-3) up to the roof
## over the Mezzanine (+1) it is one open vertical void with railed ledges round its edge on every level, grated
## catwalks crossing it, and a tower of spiral stairs at one inner corner. Everything keyed to it is pure seed maths, so
## every peer agrees. Outside the footprint level +1 does not exist and the maze, sewers and Inferno are as before.
## The view streams the WHOLE footprint on every level while the runner is in or beside it, so the shaft reads
## as one continuous region top to bottom rather than the 3x3 around the runner.
##
##   footprint(seed)             the chunk rectangle (x, z) of the void
##   contains(seed, x, z)        true for a chunk column inside it
##   is_void_chunk(seed, coord)  a chunk of the void (levels -3..+1)
##   tower_well(seed, upper)     the stairwell between level `upper` and `upper - 1` of the tower, or {}

## (2026-10-30, "i need the void/mezzanine removed entirely.. its too broken"): the void is switched off. No
## column is inside it, so no level builds a void chunk, the tower or the shaft; footprint() is still pure seed maths
## (kept so old tools/tests can read it) but contains() and is_void_chunk() are always false while this is false.
const ENABLED := false
const SIZE := 4
const TOP_LEVEL := 1
const BOTTOM_LEVEL := -3
## The void keeps off the spawn: no chunk within SPAWN_CLEAR chunks of (0, 0), and inside the sealed-map border.
const SPAWN_CLEAR := 2
## Width (cells) of the railed ledge along the footprint's edge, on every level.
const LEDGE := 3

static var _cache := {}


static func footprint(world_seed: String) -> Rect2i:
	if _cache.has(world_seed):
		return _cache[world_seed]
	var rng := SeededRandom.new("%s:VOID" % world_seed)
	var limit: int = SealRules.BORDER_RADIUS
	var options: Array[Vector2i] = []
	for x in range(-limit, limit - SIZE + 2):
		for z in range(-limit, limit - SIZE + 2):
			var rect := Rect2i(x, z, SIZE, SIZE)
			if not rect.intersects(Rect2i(-SPAWN_CLEAR, -SPAWN_CLEAR, SPAWN_CLEAR * 2 + 1, SPAWN_CLEAR * 2 + 1)):
				options.append(Vector2i(x, z))
	var at: Vector2i = options[rng.next_index(options.size())]
	var result := Rect2i(at.x, at.y, SIZE, SIZE)
	_cache[world_seed] = result
	return result


static func contains(world_seed: String, x: int, z: int) -> bool:
	if not ENABLED:
		return false
	return footprint(world_seed).has_point(Vector2i(x, z))


static func is_void_chunk(world_seed: String, coord: Vector3i) -> bool:
	return coord.y >= BOTTOM_LEVEL and coord.y <= TOP_LEVEL and contains(world_seed, coord.x, coord.z)


## The chunk holding the stair tower: the footprint's inner north-west chunk.
static func tower_chunk(world_seed: String) -> Vector2i:
	var rect := footprint(world_seed)
	return rect.position + Vector2i.ONE


## The tower's stairwell between `upper` and `upper - 1`: always a spiral in the chunk's north-west quadrant, so the
## landing is the same cell on every level and the tower is continuous from the Inferno floor to the Mezzanine.
static func tower_well(world_seed: String, upper: int) -> Dictionary:
	if upper <= BOTTOM_LEVEL or upper > TOP_LEVEL:
		return {}
	var tower := tower_chunk(world_seed)
	return Stairwells._geometry(tower.x, tower.y, upper, Stairwells.QUADRANT_AREAS[0], "spiral")


## True when the cell (x, z) of void chunk `coord` lies on the edge ledge (within LEDGE cells of the footprint's rim).
static func on_ledge(world_seed: String, coord: Vector3i, x: int, z: int) -> bool:
	var rect := footprint(world_seed)
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var gx := (coord.x - rect.position.x) * size + x
	var gz := (coord.z - rect.position.y) * size + z
	var total := SIZE * size
	return gx < LEDGE or gz < LEDGE or gx >= total - LEDGE or gz >= total - LEDGE
