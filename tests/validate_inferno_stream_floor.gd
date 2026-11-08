extends RefCounted

## The Inferno (level -3) always has a collider under the runner's feet while the stream window moves (docs/INFERNO_CAVERNS.md).
## Nothing exists below level -3 (StreamedRouteGenerator.is_chunk_allowed) and the player has no kill plane, so one missing
## floor chunk is a fall with no end. This drives the real streamed route (real physics, real stream queue):
##   - teleports (admin style and raw position sets) onto many Inferno cells, far and near a chunk edge, from level 0 and from
##     the Inferno itself, and asserts a collider under the feet on every physics tick afterwards;
##   - walks long cell-to-cell paths across chunk borders at sprint speed and faster, at 60 and 30 frames a second (the stream
##     budget is per frame), asserting the feet never lose their floor and the chunk under and ahead of the runner is loaded;
##   - walks the collector -> Inferno ramp down and up, asserting the slope collider (it belongs to the level above) is live
##     under the runner the whole way and the Inferno landing floor takes over.
## Prints one "INFO" line per scenario (numbers for the report) and a FAIL line for every lost floor.
##
## A real-time soak (about 5 minutes a seed: walks are paced at 60 physics ticks a second). Not in the runner's SUITES list; run it by name.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- inferno_stream_floor
##   INFERNO_FLOOR_SEEDS=A,B          seeds (default STREAM-BENCH and REFLOOK)
##   INFERNO_FLOOR_FULL=1             the whole walk / cold-ramp matrix (10 walks, 7 cold ramps) instead of the lean one
##   INFERNO_FLOOR_PARTS="tele walk"  any of cost tele walk ramp cold net (default: all)
##   INFERNO_FLOOR_MATRIX / _COLD     "PROFILE:FPS:SPEED;..." / "PROFILE:SPEED;..." to pick walks or cold ramps
##   INFERNO_FLOOR_STRICT_NET=1       make the missing world-bottom safety net a failure (it is a known gap: INFO only)

const StreamPerf := preload("res://tests/validate_stream_perf.gd")
const INFERNO := StreamedRouteGenerator.INFERNO_LEVEL
const SIZE := StreamedRouteGenerator.CHUNK_SIZE
const LEVEL_H := StreamedFacilityView3D.LEVEL_HEIGHT
const FLOOR_Y := float(INFERNO) * LEVEL_H
const SEEDS := ["STREAM-BENCH", "REFLOOK"]
const FELL_BELOW := 0.45          # metres under the Inferno floor that count as fallen through
## Stream budgets by device tier (QualityTier.budgets, QualityGovernor.degrade): [stream_budget_ms, stream_budget_max_ms, burst_ms, prebuild_linked_levels].
## The Framework 13 (integrated GPU) is MEDIUM or LOW, not the HIGH desktop the headless default assumes.
const PROFILES := {"HIGH": [4.0, 9.0, 14.0, true], "MEDIUM": [3.0, 6.0, 12.0, true], "LOW": [2.0, 4.0, 16.0, false],
	"MEDIUM_N2": [2.0, 4.0, 12.0, true], "LOW_N2": [1.5, 3.0, 16.0, false],
	# a machine k times slower than this one behaves like the tier budget divided by k (the budget is wall-clock milliseconds)
	"STARVE1": [1.0, 2.0, 2.0, false], "STARVE05": [0.5, 1.0, 1.0, false], "STARVE025": [0.25, 0.5, 0.5, false]}
## "PROFILE:FPS:SPEED" walks: sprint (relaxed) 6.75 m/s, the stream_perf pace 9, a stim / admin dash 14.
## "PROFILE:SPEED" cold ramp descents: walk from the neighbouring collector chunk, down the ramp, onto the Inferno landing.
const COLD := ["HIGH:6.75", "LOW_N2:6.75", "STARVE1:6.75"]
const FULL_COLD := ["HIGH:6.75", "MEDIUM:6.75", "LOW:6.75", "LOW_N2:6.75", "LOW:9", "STARVE1:6.75", "STARVE05:6.75", "STARVE025:6.75"]
const MATRIX := ["HIGH:60:6.75", "LOW_N2:60:6.75", "LOW:30:9"]
const FULL_MATRIX := ["HIGH:60:6.75", "MEDIUM:60:6.75", "LOW:60:6.75", "HIGH:60:9", "MEDIUM:60:9", "LOW:60:9", "MEDIUM:30:6.75",
	"LOW:30:6.75", "LOW_N2:60:6.75", "HIGH:60:14", "STARVE1:60:6.75", "STARVE05:60:6.75"]

var _failures := 0
var _seed_text := ""


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  [%s] %s" % [_seed_text, message])
		_failures += 1


func _note(line: String) -> void:
	print("  INFO  [%s] %s" % [_seed_text, line])


func run(host: Node) -> int:
	# the quality governor re-applies the tier budgets whenever it steps a notch (a busy test machine would trigger it)
	var governor_mode: int = PlatformProfile.governor.process_mode if PlatformProfile.governor != null else 0
	if PlatformProfile.governor != null:
		PlatformProfile.governor.process_mode = Node.PROCESS_MODE_DISABLED
	var saved_budget := [PlatformProfile.stream_budget_ms, PlatformProfile.stream_budget_max_ms, PlatformProfile.stream_budget_burst_ms,
		PlatformProfile.prebuild_linked_levels]
	var seeds: Array = SEEDS
	var env_seeds := OS.get_environment("INFERNO_FLOOR_SEEDS")
	if not env_seeds.is_empty():
		seeds = Array(env_seeds.split(","))
	var full := OS.get_environment("INFERNO_FLOOR_FULL") != ""
	for seed_text in seeds:
		_seed_text = String(seed_text)
		var rig := await _boot(host, _seed_text)
		if rig.is_empty():
			continue
		var parts := OS.get_environment("INFERNO_FLOOR_PARTS")
		if parts.is_empty():
			parts = "cost tele walk ramp cold storm wake net"
		if parts.contains("cost"):
			_build_cost(rig)
		if parts.contains("tele"):
			await _teleports(host, rig)
		var matrix: Array = FULL_MATRIX if full else MATRIX
		var env_matrix := OS.get_environment("INFERNO_FLOOR_MATRIX")
		if not env_matrix.is_empty():
			matrix = Array(env_matrix.split(";"))
		if parts.contains("walk"):
			for entry in matrix:
				var fields := String(entry).split(":")
				await _walk(host, rig, float(fields[2]), int(fields[1]), String(fields[0]))
		if parts.contains("ramp"):
			await _ramp(host, rig)
		if parts.contains("cold"):
			var cold: Array = FULL_COLD if full else COLD
			if not OS.get_environment("INFERNO_FLOOR_COLD").is_empty():
				cold = Array(OS.get_environment("INFERNO_FLOOR_COLD").split(";"))
			for entry in cold:
				var fields := String(entry).split(":")
				await _ramp_cold(host, rig, float(fields[1]), String(fields[0]))
		if parts.contains("wake"):
			await _wake_probe(host, rig)
		if parts.contains("storm"):
			for name in String(OS.get_environment("INFERNO_FLOOR_STORM") if not OS.get_environment("INFERNO_FLOOR_STORM").is_empty() else "HIGH;LOW_N2;STARVE1").split(";"):
				await _teleport_storm(host, rig, name)
		if parts.contains("net"):
			await _net_probe(host, rig)
		Engine.max_fps = 0
		(rig["scene"] as Node).queue_free()
		await host.get_tree().process_frame
		await host.get_tree().process_frame
	if PlatformProfile.governor != null:
		PlatformProfile.governor.process_mode = governor_mode as Node.ProcessMode
	PlatformProfile.stream_budget_ms = saved_budget[0]
	PlatformProfile.stream_budget_max_ms = saved_budget[1]
	PlatformProfile.stream_budget_burst_ms = saved_budget[2]
	PlatformProfile.prebuild_linked_levels = saved_budget[3]
	if _failures == 0:
		print("inferno_stream_floor OK")
	return _failures


## ------------------------------------------------------------------ rig

func _boot(host: Node, seed_text: String) -> Dictionary:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = seed_text
	var scene: Node = (load("res://game/infinite_route/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(scene)
	var facility: StreamedFacilityView3D = scene.get_node("%StreamedFacility")
	var player: PlayerController3D = scene.get_node("%Player")
	for _i in 900:
		await host.get_tree().physics_frame
		if scene.get("_start_gate") == null:
			break
	if scene.get("_start_gate") != null:
		_expect(false, "the start gate never opened")
		scene.queue_free()
		return {}
	player.admin_god_mode = true
	return {"scene": scene, "facility": facility, "player": player, "generator": facility.generator}


## chunk-local grid cell -> walkable (open floor) on level -3 for a world cell
func _open(rig: Dictionary, wx: int, wz: int, cache: Dictionary) -> bool:
	var coord := Vector3i(floori(float(wx) / SIZE), INFERNO, floori(float(wz) / SIZE))
	if not cache.has(coord):
		cache[coord] = (rig["generator"] as StreamedRouteGenerator).chunk(coord)["grid"]
	var grid: Array = cache[coord]
	return int(grid[posmod(wz, SIZE)][posmod(wx, SIZE)]) == 0


## {"cells": [Vector2i world cells], "dist": farthest} BFS path from `start` to the farthest reachable cell within `reach` chunks
func _far_path(rig: Dictionary, start: Vector2i, reach: int, cache: Dictionary) -> Array:
	var origin_chunk := Vector2i(floori(float(start.x) / SIZE), floori(float(start.y) / SIZE))
	var parent := {start: start}
	var dist := {start: 0}
	var queue: Array[Vector2i] = [start]
	var head := 0
	var best := start
	while head < queue.size():
		var cell := queue[head]
		head += 1
		for step in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = cell + step
			if parent.has(n):
				continue
			var chunk := Vector2i(floori(float(n.x) / SIZE), floori(float(n.y) / SIZE))
			if absi(chunk.x - origin_chunk.x) > reach or absi(chunk.y - origin_chunk.y) > reach:
				continue
			if not _open(rig, n.x, n.y, cache):
				continue
			parent[n] = cell
			dist[n] = int(dist[cell]) + 1
			queue.append(n)
			if int(dist[n]) > int(dist[best]):
				best = n
	var path: Array[Vector2i] = []
	var at := best
	while at != start:
		path.append(at)
		at = parent[at]
	path.append(start)
	path.reverse()
	return path


## A walkable start for the chunk (its landing cell, else any open cell near the middle).
func _start_cell(rig: Dictionary, coord: Vector2i, cache: Dictionary) -> Vector2i:
	var generator: StreamedRouteGenerator = rig["generator"]
	var landing := generator.dump_landing(Vector3i(coord.x, INFERNO, coord.y))
	if landing.x >= 0:
		return Vector2i(coord.x * SIZE + landing.x, coord.y * SIZE + landing.y)
	for radius in range(0, 22):
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var wx := coord.x * SIZE + SIZE / 2 + dx
				var wz := coord.y * SIZE + SIZE / 2 + dz
				if _open(rig, wx, wz, cache):
					return Vector2i(wx, wz)
	return Vector2i(-99999, -99999)


## ------------------------------------------------------------------ probes

## True when a collider lies within a step under the feet (the floor the runner stands on or is about to land on).
func _support(player: PlayerController3D, at: Vector3 = Vector3.INF) -> bool:
	var p := player.global_position if at == Vector3.INF else at
	var query := PhysicsRayQueryParameters3D.create(p + Vector3(0, .3, 0), p - Vector3(0, .6, 0), 1)
	query.exclude = [player.get_rid()]
	return not player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _chunk_at(p: Vector3, level: int = INFERNO) -> Vector3i:
	return Vector3i(floori(p.x / SIZE), level, floori(p.z / SIZE))


func _diag(facility: StreamedFacilityView3D, p: Vector3) -> String:
	var coord := _chunk_at(p)
	var level_chunks := []
	for c in facility._loaded:
		if (c as Vector3i).y == INFERNO:
			level_chunks.append(c)
	var active: Variant = facility._active_build.get("coord", "none") if not facility._active_build.is_empty() else "none"
	var phase: Variant = facility._active_build.get("phase", -1) if not facility._active_build.is_empty() else -1
	return "pos %s chunk %s loaded_here=%s dormant_here=%s level=%d loaded(-3)=%d pending_loads=%d active=%s phase=%s wanted_here=%s" % [
		p.snappedf(.01), coord, facility._loaded.has(coord), facility._dormant.has(coord), facility.current_level(),
		level_chunks.size(), facility._pending_loads.size(), active, phase, facility._wanted_now.has(coord)]


## ------------------------------------------------------------------ what one chunk costs to generate and to build

func _build_cost(rig: Dictionary) -> void:
	var facility: StreamedFacilityView3D = rig["facility"]
	var generator: StreamedRouteGenerator = rig["generator"]
	var lines: Array[String] = []
	for level in [0, -1, -2, INFERNO]:
		var gen_ms := 0.0
		var build_ms := 0.0
		var samples := 0
		for i in 3:
			var coord := Vector3i(40 + i, level, 40 + level)
			var t0 := Time.get_ticks_usec()
			generator.chunk(coord)
			var t1 := Time.get_ticks_usec()
			facility._load_chunk(coord)
			var t2 := Time.get_ticks_usec()
			facility._unload_chunk(coord)
			gen_ms += (t1 - t0) / 1000.0
			build_ms += (t2 - t1) / 1000.0
			samples += 1
		lines.append("level %d gen %.0f ms build %.0f ms" % [level, gen_ms / samples, build_ms / samples])
	_note("one chunk, mean of 3 (sync full build; %d other Godot runs on this machine): %s" % [StreamPerf.other_godot_processes(), "; ".join(lines)])


## ------------------------------------------------------------------ teleports

func _teleports(host: Node, rig: Dictionary) -> void:
	var facility: StreamedFacilityView3D = rig["facility"]
	var player: PlayerController3D = rig["player"]
	var scene: Node = rig["scene"]
	var cache := {}
	var targets: Array[Vector3] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_seed_text)
	for column in [Vector2i(0, 0), Vector2i(3, 1), Vector2i(-4, 2), Vector2i(2, -5), Vector2i(-6, -6), Vector2i(7, 7), Vector2i(0, 9), Vector2i(-11, 3)]:
		var cell := _start_cell(rig, column, cache)
		if cell.x < -90000:
			continue
		targets.append(Vector3(cell.x + .5, FLOOR_Y + .05, cell.y + .5))
		# and one close to a chunk edge: scan outwards for an open cell within 2 of the chunk's west/north seam
		for z in range(column.y * SIZE + 2, column.y * SIZE + SIZE - 2):
			if _open(rig, column.x * SIZE + 1, z, cache) and _open(rig, column.x * SIZE + 2, z, cache):
				targets.append(Vector3(column.x * SIZE + 1.5, FLOOR_Y + .05, z + .5))
				break
	var lost := 0
	var worst_unsupported := 0
	var slow_first := 0
	var count := 0
	for style in ["admin", "raw", "from_level0"]:
		for target in targets:
			count += 1
			if style == "from_level0":
				# the player is on the maze first (a different window), then jumps to the Inferno by the admin path
				scene._admin_teleport_to(Vector3(target.x, 0.05, target.z))
				for _i in 20:
					await host.get_tree().physics_frame
				scene._admin_teleport_to(target)
			elif style == "admin":
				scene._admin_teleport_to(target)
			else:
				player.velocity = Vector3.ZERO
				player.global_position = target       # verrine / hunter / vent exit style: the stream refreshes next _process
			var unsupported := 0
			var longest_unsupported := 0
			var fell := false
			var first_support := -1
			for tick in 60:
				await host.get_tree().physics_frame
				var supported := _support(player) or player.is_on_floor()
				if supported and first_support < 0:
					first_support = tick
				if not supported:
					unsupported += 1
					longest_unsupported += 1
				else:
					worst_unsupported = maxi(worst_unsupported, longest_unsupported)
					longest_unsupported = 0
				if player.global_position.y < FLOOR_Y - FELL_BELOW:
					fell = true
					_expect(false, "teleport (%s) to %s: fell through at tick %d (%s)" % [style, target.snappedf(.1), tick, _diag(facility, player.global_position)])
					break
			slow_first = maxi(slow_first, first_support)
			if fell:
				lost += 1
	_note("teleports: %d targets x 3 styles = %d runs, %d fell through, worst %d unsupported ticks, floor first seen by tick %d" % [
		targets.size(), count, lost, worst_unsupported, slow_first])


## ------------------------------------------------------------------ walking the stream window

func _walk(host: Node, rig: Dictionary, speed: float, fps: int, profile: String = "HIGH") -> void:
	var facility: StreamedFacilityView3D = rig["facility"]
	var budget: Array = PROFILES[profile]
	PlatformProfile.stream_budget_ms = float(budget[0])
	PlatformProfile.stream_budget_max_ms = float(budget[1])
	PlatformProfile.stream_budget_burst_ms = float(budget[2])
	PlatformProfile.prebuild_linked_levels = bool(budget[3])
	var player: PlayerController3D = rig["player"]
	var scene: Node = rig["scene"]
	var cache := {}
	Engine.max_fps = fps
	var legs := 0
	var fell_legs := 0
	var missing_under := 0
	var unsupported_ticks := 0
	var unloaded_ahead := 0
	var no_floor_ahead := 0
	var crossings := 0
	var distance := 0.0
	var min_gap := INF
	var start := _start_cell(rig, Vector2i(0, 0), cache)
	if start.x < -90000:
		return
	scene._admin_teleport_to(Vector3(start.x + .5, FLOOR_Y + .05, start.y + .5))
	for _i in 40:
		await host.get_tree().physics_frame
	for _i in 6000:
		if not facility.is_streaming():
			break
		await host.get_tree().physics_frame
	var here := start
	var lag_ticks: Array[int] = []
	var pending_since := -1
	var tick_now := 0
	for leg in 2:
		var path := _far_path(rig, here, 2, cache)
		if path.size() < 40:
			break
		legs += 1
		var travelled := 0.0
		var last_chunk := _chunk_at(player.global_position)
		var dt := 1.0 / 60.0
		var total := float(path.size() - 1)
		var failed := false
		while travelled < total and not failed:
			travelled += speed * dt
			var index := mini(int(travelled), path.size() - 1)
			var frac := travelled - float(index)
			var a: Vector2i = path[index]
			var b: Vector2i = path[mini(index + 1, path.size() - 1)]
			var at2 := Vector2(a.x + .5, a.y + .5).lerp(Vector2(b.x + .5, b.y + .5), clampf(frac, 0.0, 1.0))
			var p := player.global_position
			player.global_position = Vector3(at2.x, p.y, at2.y)
			await host.get_tree().physics_frame
			p = player.global_position
			distance += speed * dt
			var chunk := _chunk_at(p)
			tick_now += 1
			if chunk != last_chunk:
				crossings += 1
				last_chunk = chunk
				if pending_since < 0:
					pending_since = tick_now
			if pending_since >= 0 and not facility._own_storey_pending():
				lag_ticks.append(tick_now - pending_since)
				pending_since = -1
			if not facility._loaded.has(chunk):
				missing_under += 1
			var ahead_index := mini(int(travelled + 3.0), path.size() - 1)
			var ahead_cell: Vector2i = path[ahead_index]
			var ahead := Vector3(ahead_cell.x + .5, p.y, ahead_cell.y + .5)
			if not facility._loaded.has(_chunk_at(ahead)):
				unloaded_ahead += 1
			if not _support(player, ahead):
				no_floor_ahead += 1
			if not (_support(player) or player.is_on_floor()):
				unsupported_ticks += 1
			# the nearest wanted chunk of this level that is not built yet: how close the window came to the runner
			for coord_value in facility._wanted_now:
				var coord: Vector3i = coord_value
				if coord.y == INFERNO and not facility._loaded.has(coord):
					min_gap = minf(min_gap, facility._distance_to_chunk(coord))
			if p.y < FLOOR_Y - FELL_BELOW:
				failed = true
				fell_legs += 1
				_expect(false, "walk %s %.2f m/s @%d fps leg %d: fell through after %.0f m (%s)" % [profile, speed, fps, leg, distance, _diag(facility, p)])
		if failed:
			scene._admin_teleport_to(Vector3(start.x + .5, FLOOR_Y + .05, start.y + .5))
			for _i in 30:
				await host.get_tree().physics_frame
			here = start
		else:
			here = path[path.size() - 1]
	var lag_max := 0
	var lag_sum := 0
	for lag in lag_ticks:
		lag_max = maxi(lag_max, lag)
		lag_sum += lag
	var lag_mean := float(lag_sum) / maxf(1.0, float(lag_ticks.size()))
	# the STARVE profiles are sweeps for the report (a machine many times slower than any tier), they only have to keep the floor
	if not profile.begins_with("STARVE"):
		_expect(missing_under == 0, "walk %s %.2f m/s @%d fps: %d ticks with no chunk loaded under the runner" % [profile, speed, fps, missing_under])
	_note("walk %s %.2f m/s @%d fps (%d other Godot runs, governor notch %d): %d legs %.0f m, %d border crossings, %d fell, %d unsupported ticks, %d ticks chunk-under missing, %d ticks chunk 3 m ahead unloaded, %d ticks no floor 3 m ahead, nearest unbuilt wanted chunk %.1f m, stream lag after a border crossing: mean %.0f ticks (%.1f m) max %.0f ticks (%.1f m) of the 45 m the runner has, %d chunks loaded %d dormant" % [
		profile, speed, fps, StreamPerf.other_godot_processes(), PlatformProfile.notch, legs, distance, crossings, fell_legs, unsupported_ticks, missing_under, unloaded_ahead, no_floor_ahead,
		min_gap if min_gap != INF else -1.0, lag_mean, lag_mean * speed / 60.0, float(lag_max), float(lag_max) * speed / 60.0,
		facility.loaded_chunk_count(), facility.dormant_chunk_count()])
	Engine.max_fps = 0


## ------------------------------------------------------------------ the collector -> Inferno ramp

func _ramp(host: Node, rig: Dictionary) -> void:
	var facility: StreamedFacilityView3D = rig["facility"]
	var player: PlayerController3D = rig["player"]
	var scene: Node = rig["scene"]
	var generator: StreamedRouteGenerator = rig["generator"]
	var found := {}
	var column := Vector2i.ZERO
	for ring in range(0, 8):
		for z in range(-ring, ring + 1):
			for x in range(-ring, ring + 1):
				if found.is_empty() and maxi(absi(x), absi(z)) == ring:
					var ramp := generator.sewer().ramp_between(x, z, SewerRouteGenerator.LOWER_LEVEL)
					if not ramp.is_empty():
						found = ramp
						column = Vector2i(x, z)
	if found.is_empty():
		_note("ramp: no collector -> Inferno ramp within 7 chunks")
		return
	var top_x := float(found["top_x"])
	var bottom_x := float(found["bottom_x"])
	var row := float(found["row"]) + .5
	var origin := Vector2(column.x * SIZE, column.y * SIZE)
	var top := Vector3(origin.x + top_x, float(SewerRouteGenerator.LOWER_LEVEL) * LEVEL_H, origin.y + row)
	var bottom := Vector3(origin.x + bottom_x, FLOOR_Y, origin.y + row)
	var dir := signf(bottom_x - top_x)
	# stand 5 cells inside the collector, then walk the slope down, 25 cells on along the Inferno connector, and back
	var from := top - Vector3(dir * 5.0, 0, 0)
	var to := bottom + Vector3(dir * 6.0, 0, 0)
	scene._admin_teleport_to(from + Vector3(0, .05, 0))
	for _i in 200:
		await host.get_tree().physics_frame
		if not facility.is_streaming() and not facility.is_preloading():
			break
	var cache := {}
	var lost := 0
	var slope_ticks := 0
	var slope_not_live := 0
	var levels := {}
	var dormant_slope := 0
	var trips := 0
	for trip in 4:
		var a: Vector3 = from if trip % 2 == 0 else to
		var b: Vector3 = to if trip % 2 == 0 else from
		var length := a.distance_to(b)
		var travelled := 0.0
		while travelled < length:
			travelled += 6.75 / 60.0
			var t := minf(travelled / length, 1.0)
			var xz := Vector2(lerpf(a.x, b.x, t), lerpf(a.z, b.z, t))
			# height of the walked surface at this x: flat on the landings, the slope between top_x and bottom_x
			var local_x := xz.x - origin.x
			var u := clampf((local_x - top_x) / (bottom_x - top_x), 0.0, 1.0)
			var y := lerpf(float(SewerRouteGenerator.LOWER_LEVEL) * LEVEL_H, FLOOR_Y, u)
			player.global_position = Vector3(xz.x, y + .06, xz.y)
			player.velocity = Vector3.ZERO
			await host.get_tree().physics_frame
			levels[facility.current_level()] = true
			var on_slope := u > 0.0 and u < 1.0
			if on_slope:
				slope_ticks += 1
				var upper := Vector3i(column.x, SewerRouteGenerator.LOWER_LEVEL, column.y)
				var root: Node3D = facility._loaded.get(upper)
				if root == null or root.get_node_or_null("Ramp") == null or not root.get_node("Ramp").is_inside_tree() \
						or not root.is_processing() and root.process_mode == Node.PROCESS_MODE_DISABLED:
					slope_not_live += 1
					if facility._dormant.has(upper):
						dormant_slope += 1
			if not (_support(player) or player.is_on_floor()):
				lost += 1
			if player.global_position.y < y - 1.2:
				_expect(false, "ramp trip %d: fell through at u=%.2f (%s)" % [trip, u, _diag(facility, player.global_position)])
				player.global_position = Vector3(xz.x, y + .06, xz.y)
				break
		trips += 1
		for _i in 90:
			await host.get_tree().physics_frame
	_expect(slope_not_live == 0, "ramp: %d slope ticks with the upper chunk's Ramp collider not live (%d with the chunk dormant)" % [slope_not_live, dormant_slope])
	_expect(lost == 0, "ramp: %d ticks with no collider under the runner on the slope/landings" % lost)
	_note("ramp at %s: %d trips, %d slope ticks, %d ticks unsupported, %d slope ticks collider not live, levels seen %s, %d dormant" % [
		column, trips, slope_ticks, lost, slope_not_live, levels.keys(), facility.dormant_chunk_count()])


## ------------------------------------------------------------------ the cold approach to the Inferno ramp

## Open cells of the collector (level -2) or the ramp's own slope cells: a walkable BFS between two world cells.
func _collector_open(rig: Dictionary, cell: Vector2i, cache: Dictionary) -> bool:
	var generator: StreamedRouteGenerator = rig["generator"]
	var level := SewerRouteGenerator.LOWER_LEVEL
	var coord := Vector3i(floori(float(cell.x) / SIZE), level, floori(float(cell.y) / SIZE))
	if not cache.has(coord):
		cache[coord] = {"grid": generator.chunk(coord)["grid"], "ramp": generator.sewer().ramp_cells(coord.x, coord.z, level)}
	var lx := posmod(cell.x, SIZE)
	var lz := posmod(cell.y, SIZE)
	# a ramp cell is walkable on its upper level only (the slope's collider); on the lower level it is the open tunnel under it
	var ramp_cell: Dictionary = (cache[coord]["ramp"] as Dictionary).get(Vector2i(lx, lz), {})
	if not ramp_cell.is_empty():
		return bool(ramp_cell["upper"])
	return int((cache[coord]["grid"] as Array)[lz][lx]) == 0


func _collector_path(rig: Dictionary, start: Vector2i, goal: Vector2i, cache: Dictionary) -> Array:
	var open := func(cell: Vector2i) -> bool:
		return _collector_open(rig, cell, cache)
	if not open.call(start) or not open.call(goal):
		_note("collector path: start %s open=%s, goal %s open=%s" % [start, open.call(start), goal, open.call(goal)])
	var parent := {start: start}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size() and not parent.has(goal):
		var cell := queue[head]
		head += 1
		for step in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = cell + step
			if parent.has(n) or absi(n.x - start.x) > SIZE * 2 or absi(n.y - start.y) > SIZE * 2 or not open.call(n):
				continue
			parent[n] = cell
			queue.append(n)
	if not parent.has(goal):
		_note("collector path: %s -> %s explored %d cells, no route" % [start, goal, parent.size()])
		return []
	var path: Array[Vector2i] = []
	var at := goal
	while at != start:
		path.append(at)
		at = parent[at]
	path.append(start)
	path.reverse()
	return path


func _ramp_cold(host: Node, rig: Dictionary, speed: float, profile: String) -> void:
	var facility: StreamedFacilityView3D = rig["facility"]
	var player: PlayerController3D = rig["player"]
	var scene: Node = rig["scene"]
	var generator: StreamedRouteGenerator = rig["generator"]
	var budget: Array = PROFILES[profile]
	PlatformProfile.stream_budget_ms = float(budget[0])
	PlatformProfile.stream_budget_max_ms = float(budget[1])
	PlatformProfile.stream_budget_burst_ms = float(budget[2])
	PlatformProfile.prebuild_linked_levels = bool(budget[3])
	Engine.max_fps = 60
	var found := {}
	var column := Vector2i.ZERO
	for ring in range(0, 8):
		for z in range(-ring, ring + 1):
			for x in range(-ring, ring + 1):
				if found.is_empty() and maxi(absi(x), absi(z)) == ring:
					var ramp := generator.sewer().ramp_between(x, z, SewerRouteGenerator.LOWER_LEVEL)
					if not ramp.is_empty():
						found = ramp
						column = Vector2i(x, z)
	if found.is_empty():
		return
	var link: Dictionary = found["link"]
	var top_cell: Vector2i = link["from_cell"]
	var bottom_cell: Vector2i = link["to_cell"]
	var origin := column * SIZE
	var goal := origin + top_cell
	var cache := {}
	var path := []
	var start_chunk := Vector2i.ZERO
	var start := Vector2i.ZERO
	for neighbour in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		start_chunk = column + neighbour
		# the neighbour's tunnel crossing (every sewer chunk has its cross at x = z = 22)
		start = start_chunk * SIZE + Vector2i(SIZE / 2, SIZE / 2)
		var picked := false
		for radius in range(0, 9):
			for dz in range(-radius, radius + 1):
				for dx in range(-radius, radius + 1):
					if not picked and maxi(absi(dx), absi(dz)) == radius and _collector_open(rig, start + Vector2i(dx, dz), cache):
						start += Vector2i(dx, dz)
						picked = true
		path = _collector_path(rig, start, goal, cache)
		if not path.is_empty():
			break
	if path.is_empty():
		_note("ramp cold: no collector path into the ramp column %s" % column)
		return
	# a cold start: leave the column far behind first so no parked chunk of the previous run is left to revive
	scene._admin_teleport_to(Vector3((column.x + 25) * SIZE + 22.5, 0.05, (column.y + 25) * SIZE + 22.5))
	for _i in 6000:
		await host.get_tree().physics_frame
		if not facility.is_streaming() and not facility.is_preloading():
			break
	scene._admin_teleport_to(Vector3(start.x + .5, float(SewerRouteGenerator.LOWER_LEVEL) * LEVEL_H + .05, start.y + .5))
	for _i in 40:
		await host.get_tree().physics_frame
	for _i in 6000:
		if not facility.is_streaming() and not facility.is_preloading():
			break
		await host.get_tree().physics_frame
	_note("cold ramp start state: %s; loaded chunks %s; paused %s, player physics %s, start gate %s, input_frozen %s, on_floor %s, support %s" % [
		_diag(facility, player.global_position), facility._loaded.keys(), host.get_tree().paused, player.is_physics_processing(),
		scene.get("_start_gate"), player.input_frozen, player.is_on_floor(), _support(player)])
	var inferno_chunk := Vector3i(column.x, INFERNO, column.y)
	var built_at_start := facility._loaded.has(inferno_chunk) or facility._dormant.has(inferno_chunk)
	# the slope: from the top landing cell along x to the bottom landing cell, then on across the Inferno landing
	var top_x := float(found["top_x"])
	var bottom_x := float(found["bottom_x"])
	var dir := signf(bottom_x - top_x)
	var row := float(found["row"]) + .5
	var walk: Array[Vector2] = []
	for cell in path:
		walk.append(Vector2(cell.x + .5, cell.y + .5))
	var last := walk[walk.size() - 1]
	walk.append(Vector2(origin.x + bottom_x + dir * 6.0, origin.y + row))
	var travelled := 0.0
	var total := 0.0
	for i in range(1, walk.size()):
		total += walk[i - 1].distance_to(walk[i])
	var lost := 0
	var fell := false
	var first_unsupported := -1.0
	var ticks := 0
	var inferno_ready_tick := -1
	var foot_tick := -1
	var foot_ready := false
	var low_y := 1.0e9
	var last_unsupported_cell := Vector2i.ZERO
	var past_foot := false
	while travelled < total and not fell:
		travelled += speed / 60.0
		ticks += 1
		var remaining := travelled
		var at2 := walk[0]
		for i in range(1, walk.size()):
			var seg := walk[i - 1].distance_to(walk[i])
			if remaining <= seg:
				at2 = walk[i - 1].lerp(walk[i], remaining / maxf(seg, .001))
				break
			remaining -= seg
			at2 = walk[i]
		var local_x := at2.x - origin.x
		var u := clampf((local_x - top_x) / (bottom_x - top_x), 0.0, 1.0)
		var inside_column := floori(at2.x / SIZE) == column.x and floori(at2.y / SIZE) == column.y 			and absf(at2.y - (origin.y + row)) <= 1.5      # on the ramp's three rows, not just in its column
		var y := float(SewerRouteGenerator.LOWER_LEVEL) * LEVEL_H
		if inside_column and (u > 0.0 or (dir * (local_x - bottom_x)) > 0.0):
			y = lerpf(float(SewerRouteGenerator.LOWER_LEVEL) * LEVEL_H, FLOOR_Y, u)
		if inside_column and u >= 1.0:
			past_foot = true
		if past_foot:
			y = FLOOR_Y
		player.global_position = Vector3(at2.x, y + .06, at2.y)
		player.velocity = Vector3.ZERO
		await host.get_tree().physics_frame
		low_y = minf(low_y, player.global_position.y - y)
		if inferno_ready_tick < 0 and facility._loaded.has(inferno_chunk):
			inferno_ready_tick = ticks
		if u >= 1.0 and foot_tick < 0 and inside_column:
			foot_tick = ticks
			foot_ready = facility._loaded.has(inferno_chunk)
		if not (_support(player) or player.is_on_floor()):
			lost += 1
			if first_unsupported < 0.0:
				first_unsupported = travelled
				var deep := PhysicsRayQueryParameters3D.create(player.global_position + Vector3(0, 2.0, 0), player.global_position - Vector3(0, 6.0, 0), 1)
				deep.exclude = [player.get_rid()]
				var hit := player.get_world_3d().direct_space_state.intersect_ray(deep)
				_note("cold ramp: first unsupported tick at %s (world cell %s, u=%.2f, y_expected=%.2f, in column %s); deep ray hit %s" % [
					player.global_position.snappedf(.01), Vector2i(floori(at2.x), floori(at2.y)), u, y, inside_column,
					("%s at y=%.2f" % [(hit["collider"] as Node).get_path(), (hit["position"] as Vector3).y]) if not hit.is_empty() else "nothing"])
			last_unsupported_cell = Vector2i(floori(at2.x), floori(at2.y))
		if player.global_position.y < y - 1.5:
			fell = true
			_expect(false, "cold ramp %s %.2f m/s: fell through at u=%.2f after %.0f m (%s)" % [profile, speed, u, travelled, _diag(facility, player.global_position)])
	_expect(not fell, "cold ramp %s: fell" % profile)
	_expect(lost == 0, "cold ramp %s %.2f m/s: %d ticks with no collider under the runner (first after %.0f m of %.0f); Inferno chunk %s loaded at tick %d, foot reached at tick %d (loaded then: %s)" % [
		profile, speed, lost, first_unsupported, total, inferno_chunk, inferno_ready_tick, foot_tick, foot_ready])
	_note("cold ramp: last unsupported world cell %s" % last_unsupported_cell)
	_note("cold ramp %s %.2f m/s @60 fps: %.0f m walk from chunk %s, Inferno chunk already built at start %s, built at tick %d, foot reached at tick %d (built then: %s), %d unsupported ticks, fell %s" % [
		profile, speed, total, start_chunk, built_at_start, inferno_ready_tick, foot_tick, foot_ready, lost, fell])
	Engine.max_fps = 0


## ------------------------------------------------------------------ is there a world-bottom safety net?

## The floor under the runner is taken away (what a chunk freed or never built under her looks like). Nothing is below level -3
## (is_chunk_allowed) and the runner has no kill plane or respawn (hunters have FALL_RECOVERY_DEPTH), so she should fall for good:
## the stream clamps the level to -3, never re-centres on the same chunk and never reloads it. Reported as INFO; with
## INFERNO_FLOOR_STRICT_NET=1 it is an expectation (the runner must be back on a floor within 4 s).
func _net_probe(host: Node, rig: Dictionary) -> void:
	var facility: StreamedFacilityView3D = rig["facility"]
	var player: PlayerController3D = rig["player"]
	var scene: Node = rig["scene"]
	var cache := {}
	var start := _start_cell(rig, Vector2i(0, 0), cache)
	# plain floor, not the landing pile or a prop that lifts her: walk the path out of the landing until she stands on the slab
	var candidates := _far_path(rig, start, 1, cache)
	var standing_y := FLOOR_Y
	var under := Vector3i.ZERO
	for index in range(0, mini(candidates.size(), 60), 12):
		var cell: Vector2i = candidates[index]
		scene._admin_teleport_to(Vector3(cell.x + .5, FLOOR_Y + .05, cell.y + .5))
		for _i in 6000:
			await host.get_tree().physics_frame
			if not facility.is_streaming():
				break
		for _i in 30:
			await host.get_tree().physics_frame
		under = _chunk_at(player.global_position)
		standing_y = player.global_position.y
		if absf(standing_y - FLOOR_Y) < .15:
			break
	facility._unload_chunk(under)
	if facility._dormant.has(under):
		facility._free_dormant(under)   # a parked copy keeps its GridMap colliders (process_mode only stops the scripts): it would hold her up
	var lowest := standing_y
	var recovered_at := -1
	for tick in 300:
		await host.get_tree().physics_frame
		lowest = minf(lowest, player.global_position.y)
		if tick > 10 and recovered_at < 0 and (_support(player) or player.is_on_floor()):
			recovered_at = tick
	_note("net probe: floor under the runner (chunk %s) removed at y %.2f; after 5 s she is at y %.2f (lowest %.2f), level %d, chunk back in _loaded %s, pending_loads %s, recovered at tick %d" % [
		under, standing_y, player.global_position.y, lowest, facility.current_level(), facility._loaded.has(under),
		facility._pending_loads.has(under), recovered_at])
	if OS.get_environment("INFERNO_FLOOR_STRICT_NET") != "":
		_expect(recovered_at >= 0 and recovered_at <= 240, "no safety net: the runner fell to y %.1f (%.0f m under the Inferno floor) and never got a floor back" % [
			player.global_position.y, FLOOR_Y - player.global_position.y])
	# put the world back for whatever runs next
	scene._admin_teleport_to(Vector3(start.x + .5, FLOOR_Y + .05, start.y + .5))
	for _i in 60:
		await host.get_tree().physics_frame


## ------------------------------------------------------------------ teleports while the stream is still busy

## Back-to-back teleports between levels with the queue never drained (an admin hopping around, revives, hunters moving the
## runner), each ending on an Inferno cell: the floor must be under her within a few ticks every time, whatever the budget.
func _teleport_storm(host: Node, rig: Dictionary, profile: String) -> void:
	var facility: StreamedFacilityView3D = rig["facility"]
	var player: PlayerController3D = rig["player"]
	var scene: Node = rig["scene"]
	var budget: Array = PROFILES[profile]
	PlatformProfile.stream_budget_ms = float(budget[0])
	PlatformProfile.stream_budget_max_ms = float(budget[1])
	PlatformProfile.stream_budget_burst_ms = float(budget[2])
	PlatformProfile.prebuild_linked_levels = bool(budget[3])
	Engine.max_fps = 60
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("storm:" + _seed_text + profile)
	var cache := {}
	var cycles := 0
	var fell := 0
	var unsupported_runs := 0
	var worst_first_support := 0
	for cycle in 14:
		cycles += 1
		# somewhere else first: another level, another column, a short random stay (the queue stays busy)
		var level: int = [0, -1, -2, -3][rng.randi() % 4]
		var column := Vector2i(rng.randi_range(-6, 6), rng.randi_range(-6, 6))
		scene._admin_teleport_to(Vector3(column.x * SIZE + 22.5, float(level) * LEVEL_H + .05, column.y * SIZE + 22.5))
		for _i in rng.randi_range(2, 90):
			await host.get_tree().physics_frame
		# then the Inferno, on a walkable cell of a random column (raw set on odd cycles, the admin path on even ones)
		var target_column := Vector2i(rng.randi_range(-8, 8), rng.randi_range(-8, 8))
		var cell := _start_cell(rig, target_column, cache)
		if cell.x < -90000:
			continue
		var target := Vector3(cell.x + .5, FLOOR_Y + .05, cell.y + .5)
		if cycle % 2 == 0:
			scene._admin_teleport_to(target)
		else:
			player.velocity = Vector3.ZERO
			player.global_position = target
		var first_support := -1
		var lost_floor := false
		for tick in 45:
			await host.get_tree().physics_frame
			var supported := _support(player) or player.is_on_floor()
			if supported and first_support < 0:
				first_support = tick
			if player.global_position.y < FLOOR_Y - FELL_BELOW:
				lost_floor = true
				_expect(false, "storm %s cycle %d: teleport to the Inferno at %s from level %d column %s: fell through at tick %d (%s)" % [
					profile, cycle, target.snappedf(.1), level, column, tick, _diag(facility, player.global_position)])
				break
		if lost_floor:
			fell += 1
			scene._admin_teleport_to(Vector3(22.5, 0.05, 22.5))   # out of the hole
			for _i in 30:
				await host.get_tree().physics_frame
		elif first_support < 0:
			unsupported_runs += 1
		else:
			worst_first_support = maxi(worst_first_support, first_support)
	Engine.max_fps = 0
	_note("teleport storm %s: %d cycles, %d fell through, %d never supported, floor first seen by tick <= %d" % [
		profile, cycles, fell, unsupported_runs, worst_first_support])


## ------------------------------------------------------------------ parked (dormant) chunks and waking them

## A chunk is parked with process_mode DISABLED and woken with INHERIT (StreamedFacilityView3D._make_dormant / _revive). Does the
## floor under the runner (a GridMap in the chunk) and the slope under her (a StaticBody3D in the level-above chunk) survive that?
## Reports whether a parked chunk still holds a collider (it does for the floor / does not for the body are both legitimate), and
## requires the collider back on the very next ticks after the wake.
func _wake_probe(host: Node, rig: Dictionary) -> void:
	var facility: StreamedFacilityView3D = rig["facility"]
	var player: PlayerController3D = rig["player"]
	var scene: Node = rig["scene"]
	var cache := {}
	var start := _start_cell(rig, Vector2i(0, 0), cache)
	scene._admin_teleport_to(Vector3(start.x + .5, FLOOR_Y + .05, start.y + .5))
	for _i in 6000:
		await host.get_tree().physics_frame
		if not facility.is_streaming():
			break
	for _i in 20:
		await host.get_tree().physics_frame
	var under := _chunk_at(player.global_position)
	var cycles := 0
	var held_while_parked := 0
	var lost_after_wake := 0
	player.set_physics_process(false)    # a fixed point: only the probes below read the physics world
	for cycle in 6:
		cycles += 1
		facility._make_dormant(under)
		for _i in 3:
			await host.get_tree().physics_frame
		if _support(player):
			held_while_parked += 1
		facility._revive(under)
		var back := -1
		for tick in 6:
			await host.get_tree().physics_frame
			if _support(player) and back < 0:
				back = tick
		if back < 0:
			lost_after_wake += 1
			_expect(false, "wake: cycle %d: the floor under the runner (%s) did not come back within 6 ticks of _revive" % [cycle, under])
		elif back > 1:
			_note("wake: cycle %d: the floor came back only on tick %d" % [cycle, back])
	player.set_physics_process(true)
	_note("wake probe: chunk %s parked and woken %d times: a parked floor still held the runner %d times, lost after a wake %d times" % [
		under, cycles, held_while_parked, lost_after_wake])
