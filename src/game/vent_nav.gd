class_name VentNav
extends RefCounted

## Hunter pathing through the vents (KT 2026-10-28). The ducts are VentNetwork's layer; its grates are the links
## between a level and the ducts. A route is: walk to an entry grate, climb in, crawl the duct path, climb out at an
## exit grate, walk on. Who takes one:
##   - Verrine always (her whole hunt is the vent network);
##   - any other hunter only on Hard / Nightmare, and only when the vent route is much shorter (SHORTER_RATIO) than
##     the floor path she would otherwise walk.
##
##   var nav := VentNav.new(network)
##   var route := nav.route(from, to, level, floor_length, "kathy", "hard")   # {} = walk the floor

## A non-Verrine hunter takes the vents only when the vent route is at most this share of the floor route.
const SHORTER_RATIO := .5
## Entry/exit grates are looked for within this many cells of the start and the goal.
const GRATE_SEARCH := 10.0
## BFS budget, in duct cells, so a bad query can never stall a frame.
const MAX_CELLS := 6000
const VENT_MODES := ["hard", "nightmare"]

var network


func _init(p_network) -> void:
	network = p_network


static func uses_vents(hunter_id: String, difficulty_id: String) -> bool:
	return hunter_id == "verrine" or VENT_MODES.has(difficulty_id)


func _is_duct(cell: Vector2i) -> bool:
	var cx := floori(float(cell.x) / VentNetwork.CHUNK_SIZE)
	var cz := floori(float(cell.y) / VentNetwork.CHUNK_SIZE)
	var grid: Array = network.chunk(Vector3i(cx, 0, cz))["grid"]
	return int(grid[cell.y - cz * VentNetwork.CHUNK_SIZE][cell.x - cx * VentNetwork.CHUNK_SIZE]) == VentNetwork.DUCT


## The grates on `level` within `radius` cells of `point`, nearest first.
func grates_around(point: Vector2, level: int, radius: float = GRATE_SEARCH) -> Array:
	var found := []
	var reach := ceili(radius / VentNetwork.CHUNK_SIZE)
	var cx := floori(point.x / VentNetwork.CHUNK_SIZE)
	var cz := floori(point.y / VentNetwork.CHUNK_SIZE)
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			for link in network.chunk(Vector3i(cx + dx, 0, cz + dz))["links"]:
				if int(link["from_level"]) != level:
					continue
				var gap := point.distance_to(VentCrawl.grate_centre(link))
				if gap <= radius:
					found.append([gap, link])
	found.sort_custom(func(a, b): return a[0] < b[0])
	return found.map(func(pair): return pair[1])


## Duct cells (global centres) from one duct point to another, both ends included; [] when they do not connect
## within MAX_CELLS.
func duct_path(from: Vector2, to: Vector2) -> Array:
	var start := Vector2i(floori(from.x), floori(from.y))
	var goal := Vector2i(floori(to.x), floori(to.y))
	if not _is_duct(start) or not _is_duct(goal):
		return []
	var came := {start: start}
	var queue := [start]
	var head := 0
	while head < queue.size() and queue.size() < MAX_CELLS:
		var cell: Vector2i = queue[head]
		head += 1
		if cell == goal:
			break
		for step in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var next: Vector2i = cell + step
			if not came.has(next) and _is_duct(next):
				came[next] = cell
				queue.append(next)
	if not came.has(goal):
		return []
	var path := []
	var at := goal
	while at != start:
		path.push_front(Vector2(at) + Vector2(.5, .5))
		at = came[at]
	path.push_front(Vector2(start) + Vector2(.5, .5))
	return path


## The vent route from `from` to `to` on `level`, or {} when this hunter should walk the floor. `floor_length` is the
## length of her floor path in cells (INF when there is none).
func route(from: Vector2, to: Vector2, level: int, floor_length: float, hunter_id: String, difficulty_id: String) -> Dictionary:
	if not uses_vents(hunter_id, difficulty_id):
		return {}
	var entries := grates_around(from, level)
	var exits := grates_around(to, level)
	if entries.is_empty() or exits.is_empty():
		return {}
	var climbs := 2.0 * VentCrawl.CLIMB_SECONDS * VentCrawl.CRAWL_SPEED
	var best: Dictionary = {}
	for entry in entries.slice(0, 2):
		for exit in exits.slice(0, 2):
			if entry["id"] == exit["id"]:
				continue
			var path := duct_path(VentCrawl.grate_centre(entry), VentCrawl.grate_centre(exit))
			if path.is_empty():
				continue
			var length := from.distance_to(VentCrawl.grate_centre(entry)) + float(path.size()) + climbs \
				+ VentCrawl.grate_centre(exit).distance_to(to)
			if best.is_empty() or length < float(best["length"]):
				best = {"entry": entry, "exit": exit, "path": path, "length": length}
	if best.is_empty():
		return {}
	if hunter_id != "verrine" and float(best["length"]) > floor_length * SHORTER_RATIO:
		return {}
	return best
