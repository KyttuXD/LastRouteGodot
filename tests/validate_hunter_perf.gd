extends RefCounted

## Hunter performance pass (docs/PERF_PASS.md, "Hunter scaling"): the fast paths must give the answers the slow ones did, and the
## cost of an all-hunters crowd must stay bounded.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- hunter_perf
##   HUNTER_PERF_SCALING=0 ...        skip the crowd benchmark (equivalence checks only, a few seconds)
##   godot --headless --path . res://tests/scenes/validate.tscn -- hunter_perf
##
## Equivalence (exact, no tolerance): StreamedHunterNavigation.can_occupy / is_floor / blocks_sight / has_line_of_sight against
## verbatim copies of the implementations they replaced, over thousands of random and grid-aligned points (negative coordinates,
## chunk edges, cells outside the window, blocked-cell sets, sluice gates, solid props); the path grid fast bake against the old
## "can_occupy per cell" bake; Ysolde's flee_target (and its cache) against the old ring search.
## Scaling guard: the real route scene with 0, 8 and 38 hunters (tests/validate_hunter_scaling.gd, quick shape) with generous
## bounds, so a slow regression (a per-hunter scan, a quadratic term, a re-bake storm) fails while normal machine noise does not.

const ScalingSuite := preload("res://tests/validate_hunter_scaling.gd")

var _failures := 0
var _compared := 0   # answers compared against the originals


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


# ---- the replaced implementations, verbatim -------------------------------------------------------------------------------

func _ref_is_floor(nav: StreamedHunterNavigation, x: float, y: float) -> bool:
	var cell := Vector2i(floori(x), floori(y))
	var coord := nav.cell_chunk(cell, nav.level)
	var local := StreamedHunterNavigation.local_cell(cell)
	var data := nav._chunk(coord)
	var grid: Array = data.get("grid", [])
	return local.y >= 0 and local.y < grid.size() \
		and local.x >= 0 and local.x < (grid[local.y] as Array).size() \
		and (int(grid[local.y][local.x]) == 0 or nav._open_gate_cells.has(cell)) \
		and not nav._solid_prop_cells.has(cell)


func _ref_can_occupy(nav: StreamedHunterNavigation, x: float, y: float, radius: float, blocked_cells = null) -> bool:
	for sample in [Vector2(x, y), Vector2(x - radius, y - radius),
			Vector2(x + radius, y - radius), Vector2(x - radius, y + radius),
			Vector2(x + radius, y + radius)]:
		if not _ref_is_floor(nav, sample.x, sample.y):
			return false
		if blocked_cells != null and blocked_cells.has(Vector2i(floori(sample.x), floori(sample.y))):
			return false
	return true


func _ref_blocks_sight(nav: StreamedHunterNavigation, x: float, y: float) -> bool:
	var cell := Vector2i(floori(x), floori(y))
	var data := nav._chunk(nav.cell_chunk(cell, nav.level))
	var grid: Array = data.get("grid", [])
	var local := StreamedHunterNavigation.local_cell(cell)
	if local.y < 0 or local.y >= grid.size() or local.x < 0 or local.x >= (grid[local.y] as Array).size():
		return true
	if nav._opaque_prop_cells.has(cell):
		return true
	if int(grid[local.y][local.x]) == 0 or nav._open_gate_cells.has(cell):
		return false
	for key in StreamedHunterNavigation.SEE_THROUGH_CODES:
		var typed: Array = data.get(key, [])
		if local.y < typed.size() and local.x < (typed[local.y] as Array).size() \
				and (StreamedHunterNavigation.SEE_THROUGH_CODES[key] as Array).has(int(typed[local.y][local.x])):
			return false
	return true


func _ref_line_of_sight(nav: StreamedHunterNavigation, from: Vector2, to: Vector2) -> bool:
	var distance := from.distance_to(to)
	var steps := maxi(1, ceili(distance * 6.0))
	for index in range(steps + 1):
		var point := from.lerp(to, float(index) / float(steps))
		if _ref_blocks_sight(nav, point.x, point.y):
			return false
	return true


func _ref_sweep(nav: StreamedHunterNavigation, from: Vector2, to: Vector2, step: float, radius: float) -> bool:
	var distance := from.distance_to(to)
	var steps := maxi(1, ceili(distance / step))
	for index in range(1, steps + 1):
		var point := from.lerp(to, float(index) / float(steps))
		if not _ref_can_occupy(nav, point.x, point.y, radius):
			return false
	return true


## Ysolde's ring search before the perf pass (candidates tried in ring order, best score replaced strictly).
func _ref_flee_target(generator, from: Vector2, threat: Vector2, keep: float):
	var start := Vector2i(floori(from.x), floori(from.y))
	var best = null
	var best_score := from.distance_to(threat) + .75
	for ring in range(3, int(keep) + 1, 2):
		for dz in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring:
					continue
				var cell := start + Vector2i(dx, dz)
				var centre := Vector2(cell) + Vector2(.5, .5)
				if not generator.can_occupy(centre.x, centre.y):
					continue
				var score := centre.distance_to(threat)
				if score <= best_score:
					continue
				var exits := 0
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if generator.can_occupy(centre.x + d.x, centre.y + d.y):
						exits += 1
				if exits < 2:
					continue
				var path: Array = generator.find_path(start, cell)
				if path.is_empty():
					continue
				var gap := from.distance_to(threat)
				var approaches := false
				for step_cell in path:
					if (Vector2(step_cell) + Vector2(.5, .5)).distance_to(threat) < gap - .5:
						approaches = true
						break
				if approaches:
					continue
				best = centre
				best_score = score
	return best


# ---- checks ------------------------------------------------------------------------------------------------------------

func _make_nav(seed_text: String, coords: Array) -> StreamedHunterNavigation:
	var generator := StreamedRouteGenerator.new(seed_text)
	var nav := StreamedHunterNavigation.new(generator, 0)
	nav.refresh(0, coords)
	return nav


func _check_probes(nav: StreamedHunterNavigation, label: String, rng: RandomNumberGenerator) -> void:
	var blocked := {}
	for i in 400:
		blocked[Vector2i(rng.randi_range(-70, 140), rng.randi_range(-70, 140))] = true
	# some solid props and an opened gate, so those branches are exercised too
	var cells: Array = nav.floor_cells()
	if cells.size() > 40:
		for i in 12:
			nav._solid_prop_cells[cells[rng.randi_range(0, cells.size() - 1)]] = true
		for i in 4:
			nav._open_gate_cells[Vector2i(rng.randi_range(-40, 130), rng.randi_range(-40, 130))] = true
		for i in 6:
			nav._opaque_prop_cells[cells[rng.randi_range(0, cells.size() - 1)]] = true
	var radii := [0.23, GameConfig.HUNTER_RADIUS, 0.05, 0.45]
	var mismatches := 0
	var trials := 0
	for i in 2500:
		var x := rng.randf_range(-60.0, 150.0)
		var y := rng.randf_range(-60.0, 150.0)
		if i % 5 == 0:
			# grid aligned: the float32 rounding of x +/- radius decides the cell
			x = float(rng.randi_range(-45, 135)) + [0.0, 0.23, 0.77, 0.5, 1.0 - 0.23][rng.randi_range(0, 4)]
			y = float(rng.randi_range(-45, 135)) + [0.0, 0.23, 0.77, 0.5, 1.0 - 0.23][rng.randi_range(0, 4)]
		var radius: float = radii[i % radii.size()]
		var use_blocked = blocked if i % 3 == 0 else null
		trials += 1
		if nav.can_occupy(x, y, radius, use_blocked) != _ref_can_occupy(nav, x, y, radius, use_blocked):
			mismatches += 1
		if nav.is_floor(x, y) != _ref_is_floor(nav, x, y):
			mismatches += 1
		if nav.blocks_sight(x, y) != _ref_blocks_sight(nav, x, y):
			mismatches += 1
	for i in 600:
		var a := Vector2(rng.randf_range(-20.0, 110.0), rng.randf_range(-20.0, 110.0))
		var b := a + Vector2(rng.randf_range(-30.0, 30.0), rng.randf_range(-30.0, 30.0))
		trials += 1
		if nav.has_line_of_sight(a, b) != _ref_line_of_sight(nav, a, b):
			mismatches += 1
	for i in 500:
		var a := Vector2(rng.randf_range(-20.0, 110.0), rng.randf_range(-20.0, 110.0))
		var b := a + Vector2(rng.randf_range(-14.0, 14.0), rng.randf_range(-14.0, 14.0))
		var radius: float = radii[i % radii.size()]
		trials += 1
		if nav.sweep_clear(a, b, 0.15, radius) != _ref_sweep(nav, a, b, 0.15, radius):
			mismatches += 1
	_compared += trials
	_expect(mismatches == 0, "%s: %d of %d navigation probes differ from the original implementations" % [label, mismatches, trials])


func _check_path_grid(nav: StreamedHunterNavigation, label: String) -> void:
	# the fast bake must fill the very map the per-cell can_occupy bake did (checked after the bake, so every chunk of the box exists)
	var probe := nav.path_grid_region()
	_expect(probe.size.x > 0, "%s: no path grid region" % label)
	var wrong := 0
	for z in range(probe.position.y, probe.end.y):
		for x in range(probe.position.x, probe.end.x):
			var cell := Vector2i(x, z)
			var solid := nav.path_grid_is_solid(cell)
			if solid != (not _ref_can_occupy(nav, x + .5, z + .5, 0.23)):
				wrong += 1
	_compared += probe.size.x * probe.size.y
	_expect(wrong == 0, "%s: %d of %d path grid cells differ from the can_occupy bake" % [label, wrong, probe.size.x * probe.size.y])
	# a stable window must not re-bake again and again
	var region := nav.path_grid_region()
	nav.find_path(Vector2i(probe.position.x + 3, probe.position.y + 3), Vector2i(probe.position.x + 20, probe.position.y + 20))
	_expect(nav.path_grid_region() == region, "%s: the path grid region moved without the window moving" % label)


func _check_flee(nav: StreamedHunterNavigation, rng: RandomNumberGenerator) -> void:
	var cells: Array = nav.floor_cells()
	var compared := 0
	var wrong := 0
	for i in 60:
		var at: Vector2 = Vector2(cells[rng.randi_range(0, cells.size() - 1)]) + Vector2(.5, .5)
		var cache := {}   # one start, the runner moving around it: the first call fills the cache, the others read it
		for k in 4:
			var threat := at + Vector2(rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0))
			var expected = _ref_flee_target(nav, at, threat, YsoldeGimmick.AVOID_DISTANCE)
			var got = YsoldeGimmick.flee_target(nav, at, threat, YsoldeGimmick.AVOID_DISTANCE, cache)
			var plain = YsoldeGimmick.flee_target(nav, at, threat, YsoldeGimmick.AVOID_DISTANCE)
			compared += 1
			if got != expected or plain != expected:
				wrong += 1
	_compared += compared
	_expect(wrong == 0, "flee_target differs from the original ring search in %d of %d cases" % [wrong, compared])


func run(host: Node) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("HUNTER-PERF")
	var window := []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			window.append(Vector3i(dx, 0, dz))
	var nav := _make_nav("HUNTER-PERF-A", window)
	_check_probes(nav, "3x3 window", rng)
	_check_path_grid(nav, "3x3 window")
	_check_flee(nav, rng)
	# a window with a hole and an edge far from the rest: the bounding box then contains chunks outside the window
	var holey := [Vector3i(-1, 0, -1), Vector3i(0, 0, -1), Vector3i(1, 0, 1), Vector3i(2, 0, 1), Vector3i(2, 0, 2)]
	var nav2 := _make_nav("HUNTER-PERF-B", holey)
	_check_probes(nav2, "window with a hole", rng)
	_check_path_grid(nav2, "window with a hole")
	if OS.get_environment("HUNTER_PERF_SCALING") != "0":
		await _scaling_guard(host)
	if _failures == 0:
		print("  hunter_perf  %d answers of the fast navigation probes, path grid bake and Ysolde's search match the originals%s" % [_compared,
			"; 38 hunters stay within the crowd budget" if OS.get_environment("HUNTER_PERF_SCALING") != "0" else ""])
	return _failures


## 0, 8 and 38 hunters on the real route (standing runner, hunters converging: the worst case). The bounds are generous (a loaded
## CI machine moves these numbers by 30%): they catch a hunter system that scales badly again, not a few percent.
func _scaling_guard(host: Node) -> void:
	OS.set_environment("HUNTER_BENCH_QUICK", "1")
	OS.set_environment("HUNTER_BENCH_ASSERT", "1")
	OS.set_environment("HUNTER_BENCH_MAX_MS", OS.get_environment("HUNTER_PERF_MAX_MS") if not OS.get_environment("HUNTER_PERF_MAX_MS").is_empty() else "24")
	OS.set_environment("HUNTER_BENCH_MAX_RATIO", OS.get_environment("HUNTER_PERF_MAX_RATIO") if not OS.get_environment("HUNTER_PERF_MAX_RATIO").is_empty() else "2.0")
	var suite = ScalingSuite.new()
	_failures += await suite.run(host)
	# the overload path: a budget of 1 microsecond makes every cycle skip all but one hunter per half step, so each is stepped every
	# few cycles with the time it is owed; the brain time handed out per game second must still be 1.0 per hunter
	OS.set_environment("HUNTER_BENCH_COUNTS", "0,12")
	OS.set_environment("HUNTER_BENCH_STEP_BUDGET_USEC", "1")
	OS.set_environment("HUNTER_BENCH_FRAMES", "240")
	var budget_suite = ScalingSuite.new()
	_failures += await budget_suite.run(host)
	for key in ["HUNTER_BENCH_COUNTS", "HUNTER_BENCH_STEP_BUDGET_USEC", "HUNTER_BENCH_FRAMES"]:
		OS.set_environment(key, "")
