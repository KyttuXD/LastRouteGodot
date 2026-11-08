extends RefCounted

## The discovered-floor grid behind the waypoint route (infinite_route_test.gd, _ensure_waypoint_grid): rebuilt over a region with
## the cells the player has seen as open. Pure helpers on an AStarGrid2D, so tests/validate_waypoints.gd can check them headlessly.
## Preloaded (no class_name) so no global class cache entry is needed.


## Rebuilds `grid` over `region`: a cell is open when `is_open.call(cell)` is true, solid otherwise. Every cell is set again on each
## call, so a cell that was solid on an earlier build reads open after it is discovered.
static func rebuild(grid: AStarGrid2D, region: Rect2i, is_open: Callable) -> void:
	grid.region = region
	grid.cell_size = Vector2.ONE
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	grid.update()
	# update() keeps the solid flags of an unchanged region, so a cell solid on the earlier build would stay solid
	grid.fill_solid_region(region, false)
	for z in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var cell := Vector2i(x, z)
			if not is_open.call(cell):
				grid.set_point_solid(cell, true)


## The cell path from `from` to `to` over open cells, when `to` is open and reachable. When `to` is closed (unexplored floor, or
## outside the discovered box) or walled off from `from`, the path runs to the reachable open cell nearest `to` instead, so the
## route follows known floor as far as it goes. Empty when `from` is closed or outside the grid.
static func discovered_path(grid: AStarGrid2D, from: Vector2i, to: Vector2i) -> Array:
	return path_to(grid, from, reachable_target(grid, components(grid), from, to))


## The connected components of the open cells (the grid's own 4-neighbour movement): open cell -> component id. Built once per
## grid build, so a route to any destination can ask which side of the walls each cell is on (B2).
static func components(grid: AStarGrid2D) -> Dictionary:
	var result := {}
	var region := grid.region
	if region.size == Vector2i.ZERO:
		return result
	var next_id := 0
	for z in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var start := Vector2i(x, z)
			if result.has(start) or grid.is_point_solid(start):
				continue
			result[start] = next_id
			var queue: Array[Vector2i] = [start]
			var head := 0
			while head < queue.size():
				var cell: Vector2i = queue[head]
				head += 1
				for step in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
					var next: Vector2i = cell + step
					if not region.has_point(next) or result.has(next) or grid.is_point_solid(next):
						continue
					result[next] = next_id
					queue.append(next)
			next_id += 1
	return result


## The cell a route from `from` runs to, on `from`'s side of the walls: `to` itself when it is open and in the same component, else
## the open cell of that component nearest `to` (the frontier). `to` when `from` has no open component (the route is then empty).
## A closer open cell behind a wall (another component) is never chosen: the route would stop there and the floor line would run
## straight through the wall from it (B2).
static func reachable_target(grid: AStarGrid2D, components: Dictionary, from: Vector2i, to: Vector2i) -> Vector2i:
	if not components.has(from):
		return to
	var id: int = components[from]
	if int(components.get(to, -1)) == id:
		return to
	var best := from
	var best_distance := INF
	for cell_value in components:
		var cell: Vector2i = cell_value
		if int(components[cell]) != id:
			continue
		var distance := Vector2(cell).distance_squared_to(Vector2(to))
		if distance < best_distance:
			best_distance = distance
			best = cell
	return best


## The cell a route to `to` runs to: `to` itself when it is open, else the open cell nearest it (the frontier). `to` when the grid
## has no open cell. The scan is the costly part, so a caller routing to the same waypoint keeps the result until the grid changes.
static func route_target(grid: AStarGrid2D, to: Vector2i) -> Vector2i:
	if grid.region.size == Vector2i.ZERO:
		return to
	if grid.is_in_boundsv(to) and not grid.is_point_solid(to):
		return to
	return nearest_open_cell(grid, to)


## The cell path from `from` to `target` over open cells (Array of Vector2i), empty when `from` or `target` is closed or outside the grid, or
## when no path exists.
static func path_to(grid: AStarGrid2D, from: Vector2i, target: Vector2i) -> Array:
	if grid.region.size == Vector2i.ZERO or not grid.is_in_boundsv(from) or grid.is_point_solid(from):
		return []
	if not grid.is_in_boundsv(target) or grid.is_point_solid(target):
		return []
	var result := []
	for cell in grid.get_id_path(from, target):
		result.append(cell)
	return result


## The open cell of the grid nearest `to` (Euclidean, first found on ties), or `to` itself when the grid has no open cell.
static func nearest_open_cell(grid: AStarGrid2D, to: Vector2i) -> Vector2i:
	var best := to
	var best_distance := INF
	var region := grid.region
	for z in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var cell := Vector2i(x, z)
			if grid.is_point_solid(cell):
				continue
			var distance := Vector2(cell).distance_squared_to(Vector2(to))
			if distance < best_distance:
				best_distance = distance
				best = cell
	return best
