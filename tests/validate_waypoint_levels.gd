extends RefCounted

## B1 (docs/WAYPOINTS.md): a waypoint on a level other than 0 must route like it does on level 0. The live route is
## StreamedHunterNavigation.find_path over the streamed 3x3 window of that level. For every level, sample open floor pairs
## in the window, route them, and check the path is present, runs through open floor, and steps between neighbours. The same
## sample pairs are checked on level 0 and on every other level, so a level that routes worse than level 0 fails.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- waypoint_levels

const LEVELS := [0, -1, -2, -3, 1]
const SEEDS := ["WP-LEVEL-A", "WP-LEVEL-B"]
const PAIRS_PER_LEVEL := 24
const MIN_SPAN := 8
const MAX_SPAN := 40
const STEP_DIRECTIONS := [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]

var _failures := 0
var _report := []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	var totals := {}
	for seed_text in SEEDS:
		var generator := StreamedRouteGenerator.new(seed_text)
		for level in LEVELS:
			var outcome := _check_level(generator, seed_text, level)
			for key in outcome:
				totals[key] = int(totals.get(key, 0)) + int(outcome[key])
			_report.append("%s L%+d grid-mismatch %d" % [seed_text, level, _grid_mismatch(generator, level)])
			_report.append("%s L%+d routed %d/%d (empty %d, invalid %d)" % [seed_text, level,
				int(outcome["routed"]), int(outcome["pairs"]), int(outcome["empty"]), int(outcome["invalid"])])
	for line in _report:
		print("    %s" % line)
	_expect(int(totals.get("pairs", 0)) > 0, "no level produced a sample window (generator changed?)")
	_expect(int(totals.get("empty", 0)) == 0, "the live route found no path on %d sampled pair(s) (per level: %s)" % [
		int(totals.get("empty", 0)), "; ".join(PackedStringArray(_report))])
	_expect(int(totals.get("invalid", 0)) == 0, "the live route returned %d path(s) that leave open floor or skip cells" % int(totals.get("invalid", 0)))
	if _failures == 0:
		print("  waypoint_levels  live routes on levels %s match level 0 (%d pairs, all routed over open floor)" % [
			str(LEVELS), int(totals.get("pairs", 0))])
	return _failures


## One level's 3x3 window around the first chunk whose whole window is streamable on that level.
func _check_level(generator: StreamedRouteGenerator, seed_text: String, level: int) -> Dictionary:
	var outcome := {"pairs": 0, "routed": 0, "empty": 0, "invalid": 0}
	var centre := _streamable_centre(generator, level)
	if centre == Vector3i(0x7fffffff, 0, 0):
		return outcome
	var coords := []
	for z in range(centre.z - 1, centre.z + 2):
		for x in range(centre.x - 1, centre.x + 2):
			coords.append(Vector3i(x, level, z))
	var navigation := StreamedHunterNavigation.new(generator, level)
	navigation.refresh(level, coords)
	var side := StreamedRouteGenerator.CHUNK_SIZE
	var origin := Vector2i(centre.x - 1, centre.z - 1) * side
	var size := Vector2i(3, 3) * side
	var open_cells := []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:%d" % [seed_text, level])
	for _attempt in 4000:
		if open_cells.size() >= 40:
			break
		var cell := origin + Vector2i(rng.randi_range(0, size.x - 1), rng.randi_range(0, size.y - 1))
		if navigation.is_floor(cell.x + .5, cell.y + .5):
			open_cells.append(cell)
	var pairs := 0
	for index in range(0, open_cells.size() - 1, 2):
		if pairs >= PAIRS_PER_LEVEL:
			break
		var from_cell: Vector2i = open_cells[index]
		var reach := _distances(navigation, origin, size, from_cell)
		var target := Vector2i.ZERO
		var found := false
		for other_value in open_cells:
			var other: Vector2i = other_value
			if reach.has(other) and int(reach[other]) >= MIN_SPAN and int(reach[other]) <= MAX_SPAN:
				target = other
				found = true
				break
		if not found:
			continue
		pairs += 1
		var path: Array = navigation.find_path(from_cell, target)
		if path.is_empty():
			outcome["empty"] = int(outcome["empty"]) + 1
			continue
		if _path_valid(navigation, path):
			outcome["routed"] = int(outcome["routed"]) + 1
		else:
			outcome["invalid"] = int(outcome["invalid"]) + 1
	outcome["pairs"] = pairs
	return outcome


## Chunks of the level whose grid is not CHUNK_SIZE square (the discovered-floor grid skips them: _remember_discovered_chunk).
func _grid_mismatch(generator: StreamedRouteGenerator, level: int) -> int:
	var side := StreamedRouteGenerator.CHUNK_SIZE
	var bad := 0
	for z in range(-3, 4):
		for x in range(-3, 4):
			var coord := Vector3i(x, level, z)
			if not generator.is_chunk_allowed(coord):
				continue
			var grid: Array = generator.chunk(coord).get("grid", [])
			var ok := grid.size() == side
			if ok:
				for row_value in grid:
					if (row_value as Array).size() != side:
						ok = false
						break
			if not ok:
				bad += 1
	return bad


## The chunk whose 3x3 neighbourhood is entirely streamable on the level, nearest the origin (Vector3i.x = huge when none).
func _streamable_centre(generator: StreamedRouteGenerator, level: int) -> Vector3i:
	for radius in range(0, 12):
		for z in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				if maxi(absi(x), absi(z)) != radius:
					continue
				var ok := true
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						if not generator.is_chunk_allowed(Vector3i(x + dx, level, z + dz)):
							ok = false
				if ok:
					return Vector3i(x, level, z)
	return Vector3i(0x7fffffff, 0, 0)


## Breadth-first distances over open floor inside the window, 4-neighbour steps (an independent reference for the route).
func _distances(navigation: StreamedHunterNavigation, origin: Vector2i, size: Vector2i, start: Vector2i) -> Dictionary:
	var dist := {start: 0}
	var queue := [start]
	var head := 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		for step in STEP_DIRECTIONS:
			var next: Vector2i = cell + step
			if next.x < origin.x or next.y < origin.y or next.x >= origin.x + size.x or next.y >= origin.y + size.y:
				continue
			if dist.has(next) or not navigation.is_floor(next.x + .5, next.y + .5):
				continue
			dist[next] = int(dist[cell]) + 1
			queue.append(next)
	return dist


## Every cell is open floor and each step moves to a neighbour (diagonals allowed, as the live route uses them).
func _path_valid(navigation: StreamedHunterNavigation, path: Array) -> bool:
	for index in path.size():
		var cell: Vector2i = path[index]
		if not navigation.is_floor(cell.x + .5, cell.y + .5):
			return false
		if index > 0:
			var previous: Vector2i = path[index - 1]
			if absi(cell.x - previous.x) > 1 or absi(cell.y - previous.y) > 1 or cell == previous:
				return false
	return true
