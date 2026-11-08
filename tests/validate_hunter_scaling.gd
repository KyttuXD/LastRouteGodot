extends RefCounted

## Hunter scaling benchmark: what does ONE frame cost with 0, 1, 4, 8, 16, 26 and 38 hunters awake on a real streamed route?
## Boots the real route scene (InfiniteRouteTest: streaming, HUD, minimap, remotes, audio), adds N hunters through the same
## world_state / _refresh_hunter_stream / _load_hunter path the game and the admin summon use (real HunterView3D, HunterBrain,
## StreamedHunterNavigation, HunterDirector, gimmicks), lets the scene's own _process / _physics_process run, and prints a
## scaling table plus a per-subsystem breakdown. It is a measuring tool first (no timing assertions unless HUNTER_BENCH_ASSERT=1);
## the only hard checks are sanity ones (the requested hunters really loaded and really moved).
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- hunter_scaling
##   HUNTER_BENCH_MODE=run godot --headless --path . res://tests/scenes/validate.tscn -- hunter_scaling
##
## Environment (all optional):
##   HUNTER_BENCH_COUNTS   "0,1,4,8,16,26,38"   hunters awake at each step; added cumulatively, roster order (A-Z first, then void_*)
##   HUNTER_BENCH_MODE     "stand" | "run" | "both"   stand: the runner stands still in god mode and the hunters converge (worst case for
##                         perception, separation and crowding). run: the runner sprints along fresh ground (adds chunk streaming and
##                         navigation rebuilds). Default "both".
##   HUNTER_BENCH_PLACE    "near" (2.5-7 m around the runner: every hunter is CROWD NEAR) | "spread" (14-45 m: mixes NEAR / MID / FAR).
##                         Default "near".
##   HUNTER_BENCH_FRAMES   measured frames per step (stand 300, run 600 by default)
##   HUNTER_BENCH_QUICK    "1": counts 0,8,38 / stand / no breakdown (about a minute), the shape a regression guard wants
##   HUNTER_BENCH_SPEED    runner speed in run mode, m/s (default 4)
##   HUNTER_BENCH_PARTS    "1" (default) subsystem breakdown + A/B toggles, "0" to skip
##   HUNTER_BENCH_FPS      engine frame cap while measuring (default 60; 0 = uncapped). Costs are normalised per 1/60 s of game time.
##   HUNTER_BENCH_ASSERT   "1": fail when 38 hunters cost more than HUNTER_BENCH_MAX_MS (default 40) per 1/60 s, or scale worse than
##                         HUNTER_BENCH_MAX_RATIO (default 2.2) x the linear extrapolation from 8 hunters.
##   HUNTER_BENCH_SEED     route seed (default "HUNTER-BENCH")
##   HUNTER_BENCH_STEP_BUDGET_USEC  override the route's per-half-step hunter budget (1 forces the owed-time catch-up every cycle; 0 = unbudgeted)
##
## How the numbers are taken (no engine edits, nothing in the game is instrumented):
##   cpu    = (frames over 50 ms are hitches: counted apart, not averaged) main-thread time inside the scene tree's _process callbacks (a probe at process_priority -100000 and another at
##            +100000 bracket every other node) + the physics step (Performance.TIME_PHYSICS_PROCESS, scripted physics + server),
##            per 1/60 s of game time. This is the cost a 60 fps frame must fit in; rendering is not part of it (headless).
##   parts  = the route's own functions timed one by one with Time.get_ticks_usec while the route's _process is switched off and the
##            same calls are made by hand (see _timed_step, which mirrors InfiniteRouteTest._update_hunters). "unexplained" is the
##            wall time of the real _update_hunters minus the sum of the timed parts.
##   A/B    = the same window re-measured with all AnimationPlayers inactive, then with every hunter's physics process off.

const StreamPerfSuite := preload("res://tests/validate_stream_perf.gd")
const DEFAULT_COUNTS := [0, 1, 4, 8, 16, 26, 38]
## Runner speed in "run" mode (m/s). Kept below the hunters' chase speed so they stay in the streamed window and loaded count stays N.
var _speed := 4.0
const STEP := 1.0 / 30.0
const WARM_FRAMES := 150
## A frame longer than max(this, 8 x the median frame) is a hitch (path-grid re-bake, model load, chunk build): counted, and left out of "steady".
const HITCH_US := 50000
const PARTS_STEPS := 60

var _failures := 0
var _route: Node
var _meter := Meter.new()
var _serial := 0
var _loop_index := 0


class Meter:
	var on := false
	var t_head := 0
	var frames_us: Array = []
	var delta_sum := 0.0
	var mon_proc_s := 0.0
	var mon_proc_n := 0
	var phys_s := 0.0
	var phys_n := 0
	## Frames over 150 ms: what the engine says about the frame before (script process, physics, navigation, objects).
	var hitch_log: Array = []

	func reset() -> void:
		hitch_log.clear()
		frames_us.clear()
		delta_sum = 0.0
		mon_proc_s = 0.0
		mon_proc_n = 0
		phys_s = 0.0
		phys_n = 0


class Probe extends Node:
	var meter: Meter
	var tail := false

	func _ready() -> void:
		process_priority = 100000 if tail else -100000
		process_physics_priority = 100000 if tail else -100000

	func _process(_delta: float) -> void:
		if meter == null or not meter.on:
			return
		var now := Time.get_ticks_usec()
		if tail:
			meter.frames_us.append(now - meter.t_head)
			meter.delta_sum += get_process_delta_time()
		else:
			meter.t_head = now
			var last_proc := Performance.get_monitor(Performance.TIME_PROCESS)
			meter.mon_proc_s += last_proc
			meter.mon_proc_n += 1
			if last_proc > 0.15:
				meter.hitch_log.append("process %.0f ms physics %.0f ms nav %.0f ms objects %d nodes %d bodies %d" % [
					last_proc * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
					Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0, int(Performance.get_monitor(Performance.OBJECT_COUNT)),
					int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))])

	func _physics_process(_delta: float) -> void:
		if meter == null or not meter.on or tail:
			return
		# the monitor holds the previous physics tick (scripted _physics_process plus the server step)
		meter.phys_s += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		meter.phys_n += 1


## The route's navigation with meters on the calls that can stall a frame: the path-grid re-bake (AStarGrid2D re-filled with can_occupy
## per cell, whenever the streamed window or its wall set changes), find_path and line of sight. Installed for the whole run (a few
## microseconds per call); the per-cell counters of CountNav are only swapped in for a short census.
class RebakeNav extends StreamedHunterNavigation:
	var calls := {}
	var usec := {}
	var rebakes := 0
	var rebake_us := 0
	var rebake_max_us := 0
	var rebake_cells := 0

	func _tick(key: String, t0: int) -> void:
		calls[key] = int(calls.get(key, 0)) + 1
		usec[key] = int(usec.get(key, 0)) + (Time.get_ticks_usec() - t0)

	func refresh(route_level: int, coords: Array) -> void:
		var t := Time.get_ticks_usec()
		super.refresh(route_level, coords)
		_tick("refresh", t)

	var rebakes_for_window := 0   # the streamed window (set of chunks) changed
	var rebakes_for_walls := 0    # same window, but a gate / solid prop appeared or went away
	var rebakes_for_level := 0

	func _rebuild_path_grid_if_needed() -> void:
		var t := Time.get_ticks_usec()
		var window_changed := _path_grid_coords != _active_coords
		var level_changed := _path_grid_level != level
		super._rebuild_path_grid_if_needed()
		var spent := Time.get_ticks_usec() - t
		if spent > 400:   # a no-op check is a few microseconds; a bake is tens of milliseconds
			if level_changed:
				rebakes_for_level += 1
			elif window_changed:
				rebakes_for_window += 1
			else:
				rebakes_for_walls += 1
			rebakes += 1
			rebake_us += spent
			rebake_max_us = maxi(rebake_max_us, spent)
			rebake_cells += _path_grid.region.size.x * _path_grid.region.size.y

	func find_path(from_cell: Vector2i, to_cell: Vector2i) -> Array:
		var t := Time.get_ticks_usec()
		var result := super.find_path(from_cell, to_cell)
		_tick("find_path", t)
		calls["find_path_cells"] = int(calls.get("find_path_cells", 0)) + result.size()
		return result

	func has_line_of_sight(from: Vector2, to: Vector2) -> bool:
		var t := Time.get_ticks_usec()
		var result := super.has_line_of_sight(from, to)
		_tick("line_of_sight", t)
		calls["los_metres"] = int(calls.get("los_metres", 0)) + int(from.distance_to(to))
		return result

	func nearest_open_position(origin_x: float, origin_y: float, radius: float, blocked_cells = null) -> Dictionary:
		var t := Time.get_ticks_usec()
		var result := super.nearest_open_position(origin_x, origin_y, radius, blocked_cells)
		_tick("nearest_open_position", t)
		return result

	func snapshot() -> Dictionary:
		return {"rebakes": rebakes, "rebakes_window": rebakes_for_window, "rebakes_walls": rebakes_for_walls, "rebake_us": rebake_us, "rebake_max_us": rebake_max_us, "rebake_cells": rebake_cells,
			"path_calls": int(calls.get("find_path", 0)), "path_us": int(usec.get("find_path", 0)),
			"los_calls": int(calls.get("line_of_sight", 0)), "los_us": int(usec.get("line_of_sight", 0)),
			"refresh_calls": int(calls.get("refresh", 0)), "refresh_us": int(usec.get("refresh", 0))}


## Census variant: also counts the per-cell queries (slows them, so it only runs for a short census, never in a measurement).
class CountNav extends RebakeNav:
	func can_occupy(x: float, y: float, radius: float = 0.23, blocked_cells = null) -> bool:
		calls["can_occupy"] = int(calls.get("can_occupy", 0)) + 1
		return super.can_occupy(x, y, radius, blocked_cells)

	func is_floor(x: float, y: float) -> bool:
		calls["is_floor"] = int(calls.get("is_floor", 0)) + 1
		return super.is_floor(x, y)

	func blocks_sight(x: float, y: float) -> bool:
		calls["blocks_sight"] = int(calls.get("blocks_sight", 0)) + 1
		return super.blocks_sight(x, y)

	## A query outside the cached window: the chunk is generated / baked on the spot, on the main thread.
	func _chunk(coord: Vector3i) -> Dictionary:
		if _chunk_cache.has(coord):
			return super._chunk(coord)
		var t := Time.get_ticks_usec()
		var data := super._chunk(coord)
		_tick("chunk_cache_miss", t)
		return data


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


static func _env(key: String, fallback: String) -> String:
	var value := OS.get_environment(key)
	return fallback if value.is_empty() else value


func run(host: Node) -> int:
	# HUNTER_BENCH_QUICK=1: the regression-guard shape (0, 8 and 38 hunters, standing runner, no breakdown): about 1 minute
	var quick := _env("HUNTER_BENCH_QUICK", "0") == "1"
	var counts: Array = []
	for part in _env("HUNTER_BENCH_COUNTS", "0,8,38" if quick else "").split(",", false):
		counts.append(int(part))
	if counts.is_empty():
		counts = DEFAULT_COUNTS.duplicate()
	counts.sort()
	var mode := _env("HUNTER_BENCH_MODE", "stand" if quick else "both")
	var place := _env("HUNTER_BENCH_PLACE", "near")
	var parts_on := _env("HUNTER_BENCH_PARTS", "0" if quick else "1") == "1"
	var fps := int(_env("HUNTER_BENCH_FPS", "60"))
	_speed = float(_env("HUNTER_BENCH_SPEED", "4"))
	Engine.max_fps = fps
	var modes: Array = ["stand", "run"] if mode == "both" else [mode]
	var all_rows := {}
	for one_mode in modes:
		var frames := int(_env("HUNTER_BENCH_FRAMES", "600" if one_mode == "run" else "300"))
		all_rows[one_mode] = await _bench_mode(host, counts, String(one_mode), place, frames, parts_on)
	Engine.max_fps = 0
	if _env("HUNTER_BENCH_ASSERT", "0") == "1":
		for one_mode in all_rows:
			_check_scaling(String(one_mode), all_rows[one_mode])
	print("HSCALE_JSON %s" % JSON.stringify(_finite(all_rows)))
	return _failures


## JSON cannot carry NaN or infinity: swap them for -1.
static func _finite(value: Variant) -> Variant:
	if value is float:
		return -1.0 if is_nan(value) or is_inf(value) else value
	if value is Dictionary:
		var out := {}
		for key in value:
			out[key] = _finite(value[key])
		return out
	if value is Array:
		var out2: Array = []
		for item in value:
			out2.append(_finite(item))
		return out2
	return value


# ------------------------------------------------------------------------------------------------ one mode

func _bench_mode(host: Node, counts: Array, mode: String, place: String, frames: int, parts_on: bool) -> Array:
	var tree := host.get_tree()
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = _env("HUNTER_BENCH_SEED", "HUNTER-BENCH")
	GameState.relays_collected = 0
	var route: Node = (load("res://game/infinite_route/infinite_route_test.tscn") as PackedScene).instantiate()
	tree.root.add_child(route)
	_route = route
	var head := Probe.new()
	head.meter = _meter
	var tail := Probe.new()
	tail.meter = _meter
	tail.tail = true
	tree.root.add_child(head)
	tree.root.add_child(tail)
	for _i in 40:
		await tree.process_frame
	var player: PlayerController3D = route.player
	player.admin_god_mode = true
	player.set_physics_process(false)
	# wait for the first hunter window (navigation of storey 0)
	for _i in 120:
		if route._navigations.has(0):
			break
		route._hunter_stream_signature = ""
		route._refresh_hunter_stream()
		await tree.process_frame
	Engine.max_fps = int(_env("HUNTER_BENCH_FPS", "60"))   # the scene's own settings reset the cap while it boots
	if _env("HUNTER_BENCH_STEP_BUDGET_USEC", "") != "":
		route._hunter_step_budget_usec = int(_env("HUNTER_BENCH_STEP_BUDGET_USEC", "0"))   # 1 = force the catch-up path every cycle
	var original_nav := route._navigations.get(0) as StreamedHunterNavigation
	if original_nav != null:
		var metered := RebakeNav.new(route.facility.generator, 0, route.world_state)
		metered.refresh(0, original_nav.active_coordinates())
		route._navigations[0] = metered
		route._navigation = metered
	var busy_before := StreamPerfSuite.other_godot_processes()
	var rows: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("HSCALE-%s" % place)
	var ids: Array = []
	ids.append_array(HunterRoster.A_Z_IDS)
	ids.append_array(HunterRoster.VOID_IDS)
	var have := 0
	var worst_ids := {}
	print("HSCALE mode=%s place=%s fps_cap=%d frames=%d seed=%s host=%s" % [mode, place, Engine.max_fps, frames, RoomState.seed_text, OS.get_name()])
	for want_value in counts:
		var want := int(want_value)
		_serial += 1
		if want > have:
			_add_hunters(route, ids.slice(have, mini(want, ids.size())), place, rng, have)
			have = mini(want, ids.size())
		for _i in WARM_FRAMES:
			_move_player(route, mode)
			await tree.process_frame
		var row := await _measure(host, route, mode, frames)
		row["n"] = want
		row["loaded"] = _loaded(route)
		_expect(int(row["loaded"]) >= mini(want, ids.size()) * (1 if mode != "run" else 0),
			"%s: asked for %d hunters, %d are loaded" % [mode, want, int(row["loaded"])])
		row["states"] = _state_census(route)
		if parts_on:
			var per_id := {}
			row["parts"] = await _parts(host, route, mode, per_id)
			row["brain_by_hunter_state"] = _summarise_ids(per_id)
			if want == int(counts.back()):
				worst_ids = per_id
			row["ab"] = await _ab(host, route, mode, frames / 3)
		rows.append(row)
		_print_row(mode, row)
	print("HSCALE other Godot processes on this machine: %d at the start, %d at the end (timings are only trustworthy at 0)" % [busy_before, StreamPerfSuite.other_godot_processes()])
	var units := _unit_costs(route)
	_print_summary(mode, rows, worst_ids, units)
	if not rows.is_empty():
		(rows.back() as Dictionary)["units"] = units
	route.queue_free()
	head.queue_free()
	tail.queue_free()
	await tree.process_frame
	await tree.process_frame
	return rows


## brain.update microseconds per 30 Hz step: the top hunters, and per brain state (us per call, calls per step).
func _summarise_ids(per_id: Dictionary) -> Dictionary:
	var hunters: Array = []
	var states := {}
	for key in per_id:
		var name := String(key)
		if name.begins_with("state:"):
			var state_name := name.trim_prefix("state:")
			states[state_name] = [float(per_id[key]) / maxf(1.0, float(per_id.get("count:" + state_name, 1))), float(per_id.get("count:" + state_name, 0)) / PARTS_STEPS]
		elif not name.begins_with("count:") and not name.begins_with("fp:") and not name.begins_with("co:"):
			hunters.append([float(per_id[key]) / PARTS_STEPS, name])
	hunters.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	var top := {}
	for i in mini(8, hunters.size()):
		top[String(hunters[i][1])] = hunters[i][0]
	return {"top": top, "states": states}


func _loaded(route: Node) -> int:
	var count := 0
	for view_value in route._hunter_views.values():
		if is_instance_valid(view_value) and (view_value as HunterView3D).brain != null:
			count += 1
	return count


func _move_player(route: Node, mode: String) -> void:
	if mode != "run":
		return
	var player: PlayerController3D = route.player
	player.global_position += Vector3(_speed * route.get_process_delta_time(), 0.0, 0.0)


func _add_hunters(route: Node, hunter_ids: Array, place: String, rng: RandomNumberGenerator, already: int) -> void:
	var navigation := route._navigations.get(0) as StreamedHunterNavigation
	if navigation == null:
		return
	var player_at: Vector2 = route.player.grid_position()
	var cells: Array = navigation.floor_cells()
	cells.sort()
	var low := 2.5 if place == "near" else 14.0
	var high := 7.0 if place == "near" else 45.0
	var pool: Array = []
	for cell in cells:
		var d := (Vector2(cell) + Vector2(.5, .5)).distance_to(player_at)
		if d >= low and d <= high:
			pool.append(cell)
	if pool.is_empty():
		pool = cells
	for hunter_id in hunter_ids:
		var cell: Vector2i = pool[rng.randi_range(0, pool.size() - 1)]
		var at := Vector2(cell) + Vector2(.5, .5)
		var entity_id := "BENCH:%s:%d" % [hunter_id, already]
		var state: Dictionary = route.world_state.ensure_hunter({
			"id": entity_id, "hunter_id": String(hunter_id),
			"origin_chunk": navigation.cell_chunk(cell, 0),
			"cell": StreamedHunterNavigation.local_cell(cell), "level": 0})
		if state.is_empty():
			continue
		state["position"] = at
		state["active"] = true
		state["state"] = HunterBrain.State.SEARCH
		state["has_last_known"] = true
		state["last_known"] = player_at
		route.world_state.hunters[entity_id] = state
	route._hunter_stream_signature = ""
	route._refresh_hunter_stream()
	for view_value in route._hunter_views.values():
		var view := view_value as HunterView3D
		if view != null and view.brain != null and not view.brain.active:
			view.brain.activate_at(player_at)
		if view != null:
			view.target_peer_id = 1


func _state_census(route: Node) -> String:
	var counts := {}
	var near := 0
	var mid := 0
	var far := 0
	for view_value in route._hunter_views.values():
		var view := view_value as HunterView3D
		if view == null or view.brain == null:
			continue
		var key := str(view.brain.state)
		counts[key] = int(counts.get(key, 0)) + 1
		match view.crowd_tier:
			HunterView3D.CrowdTier.NEAR: near += 1
			HunterView3D.CrowdTier.MID: mid += 1
			_: far += 1
	var names := {}
	for name in HunterBrain.State.keys():
		names[str(HunterBrain.State[name])] = String(name)
	var parts: Array = []
	for key in counts:
		parts.append("%s=%d" % [names.get(key, key), counts[key]])
	return "%s tiers N%d/M%d/F%d" % [" ".join(parts), near, mid, far]


# ------------------------------------------------------------------------------------------------ whole-frame measurement

func _measure(host: Node, route: Node, mode: String, frames: int) -> Dictionary:
	var tree := host.get_tree()
	_meter.reset()
	var nav_before := _nav_snapshot(route)
	_meter.on = true
	HunterPerf.reset()
	HunterPerf.on = true
	var wall := Time.get_ticks_usec()
	var nodes := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	for _i in frames:
		_move_player(route, mode)
		await tree.process_frame
	_meter.on = false
	HunterPerf.on = false
	var hunter_steps := int(HunterPerf.calls.get("route.hunter_step", 0))
	var wall_s := (Time.get_ticks_usec() - wall) / 1e6
	var summary := _summarise(_meter, wall_s, nodes)
	var nav_after := _nav_snapshot(route)
	for key in nav_after:
		summary[key] = int(nav_after[key]) - int(nav_before.get(key, 0))
	summary["rebake_max_us"] = nav_after.get("rebake_max_us", 0)
	# hunter steps taken per hunter per game second: 30 whatever the staggering (the host steps every hunter once per 1/30 s)
	summary["hunter_steps"] = hunter_steps
	summary["hitch_log"] = _meter.hitch_log.duplicate()
	var peaks := {}
	for key in HunterPerf.peak:
		if int(HunterPerf.peak[key]) >= 4000:
			peaks[key] = float(HunterPerf.peak[key]) / 1000.0
	summary["perf_peaks_ms"] = peaks
	var totals := {}
	for key in HunterPerf.usec:
		if int(HunterPerf.usec[key]) >= 20000 and String(key).begins_with(("sound.")) or String(key).begins_with("route."):
			totals[key] = [float(HunterPerf.usec[key]) / 1000.0, int(HunterPerf.calls.get(key, 0))]
	summary["perf_totals_ms"] = totals
	summary["steps_per_hunter_s"] = float(hunter_steps) / maxf(.001, float(summary["game_all_s"])) / maxf(1.0, float(_loaded(route)))
	# seconds of brain time handed out per hunter per game second: 1.0 when every hunter is stepped on schedule (or repaid what it was owed)
	summary["dt_per_hunter_s"] = float(HunterPerf.sums.get("route.hunter_dt", 0.0)) / maxf(.001, float(summary["game_all_s"])) / maxf(1.0, float(_loaded(route)))
	# the same cost with the path-grid re-bakes taken out (they run inside the measured frames)
	var rebake_ms := float(summary.get("rebake_us", 0)) / 1000.0
	summary["cpu_no_rebake_ms"] = float(summary["cpu_ms"]) - rebake_ms / maxf(1.0, float(summary["game_all_s"]) * 60.0)
	return summary


func _nav_snapshot(route: Node) -> Dictionary:
	var navigation = route._navigations.get(0)
	if navigation != null and navigation.has_method("snapshot"):
		return navigation.snapshot()
	return {}


func _summarise(meter: Meter, wall_s: float, nodes: float) -> Dictionary:
	var spans: Array = meter.frames_us.duplicate()
	spans.sort()
	var n := maxi(1, spans.size())
	var median := float(spans[n / 2]) if not spans.is_empty() else 0.0
	var hitch_limit := maxf(float(HITCH_US), median * 8.0)
	var all_us := 0.0
	var kept_us := 0.0
	var hitches := 0
	var hitch_us := 0.0
	var kept := 0
	for span in spans:
		all_us += float(span)
		if float(span) > hitch_limit:
			hitches += 1
			hitch_us += float(span)
		else:
			kept_us += float(span)
			kept += 1
	var game_all_s := maxf(meter.delta_sum, 0.001)
	var game_kept_s := maxf(game_all_s * float(kept) / float(n), 0.001)
	var phys_ms := (meter.phys_s / maxf(1.0, float(meter.phys_n))) * 1000.0
	var ticks_per_sixtieth := float(meter.phys_n) / (game_all_s * 60.0)
	var proc_all := all_us / 1000.0 / (game_all_s * 60.0)
	var proc_steady := kept_us / 1000.0 / (game_kept_s * 60.0)
	return {
		"proc_ms": proc_all, "phys_ms": phys_ms * ticks_per_sixtieth, "cpu_ms": proc_all + phys_ms * ticks_per_sixtieth,
		"steady_ms": proc_steady + phys_ms * ticks_per_sixtieth,
		"p50": median / 1000.0, "p95": float(spans[int(n * .95)]) / 1000.0, "max": float(spans[n - 1]) / 1000.0,
		"mon_proc": meter.mon_proc_s / maxf(1.0, float(meter.mon_proc_n)) * 1000.0,
		"hitches": hitches, "hitch_ms": hitch_us / 1000.0,
		"frames": n, "game_s": game_all_s, "game_all_s": game_all_s, "wall_s": wall_s, "fps": n / maxf(wall_s, .001),
		"phys_tick_ms": phys_ms, "ticks_per_frame": float(meter.phys_n) / float(n),
		"nodes": nodes, "bodies": Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		"pairs": Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
	}


# ------------------------------------------------------------------------------------------------ subsystem breakdown

static func _add(parts: Dictionary, key: String, t0: int) -> void:
	parts[key] = int(parts.get(key, 0)) + (Time.get_ticks_usec() - t0)


## The route's _process switched off; its pieces called by hand and timed. Returns microseconds per 1/30 s step.
func _parts(host: Node, route: Node, mode: String, per_id: Dictionary) -> Dictionary:
	var tree := host.get_tree()
	var out := {}
	route.set_process(false)
	# 1. the real _update_hunters, by hand (what the route does at 30 Hz)
	var t_real := 0
	for _i in PARTS_STEPS:
		_move_player(route, mode)
		var t := Time.get_ticks_usec()
		route._update_hunters(STEP, route.facility.current_chunk_data())
		t_real += Time.get_ticks_usec() - t
		await tree.process_frame
		await tree.process_frame
	out["update_hunters_real"] = t_real / float(PARTS_STEPS)
	# 2. the same step, mirrored piece by piece
	var parts := {}
	HunterPerf.reset()
	HunterPerf.on = true
	for _i in PARTS_STEPS:
		_move_player(route, mode)
		_timed_step(route, STEP, parts, per_id)
		await tree.process_frame
		await tree.process_frame
	HunterPerf.on = false
	var perf := {}
	for key in HunterPerf.usec:
		perf[key] = [float(HunterPerf.usec[key]) / PARTS_STEPS, float(HunterPerf.calls.get(key, 0)) / PARTS_STEPS]
	out["hunter_perf"] = perf
	var sum := 0.0
	for key in parts:
		out[key] = float(parts[key]) / PARTS_STEPS
		sum += float(parts[key]) / PARTS_STEPS
	out["_sum_parts"] = sum
	out["census"] = await _census(host, route, mode)
	# 3. per-frame things outside the 30 Hz step
	var t_audio := 0
	var t_view := 0
	var t_report := 0
	var t_hud := 0
	var t_refresh := 0
	var t_signature := 0
	var view_parts := {}
	var views: Array = route._hunter_views.values()
	for view in views:
		(view as HunterView3D).set_process(false)
	for _i in PARTS_STEPS:
		_loop_index = _i
		_move_player(route, mode)
		var data: Dictionary = route.facility.current_chunk_data()
		var t := Time.get_ticks_usec()
		route._update_hunter_audio(1.0 / 60.0, data)
		t_audio += Time.get_ticks_usec() - t
		t = Time.get_ticks_usec()
		for view in views:
			if is_instance_valid(view):
				_timed_view_process(view as HunterView3D, 1.0 / 60.0, view_parts)
		t_view += Time.get_ticks_usec() - t
		t = Time.get_ticks_usec()
		route._collect_hunter_report()
		route._remotes.broadcast_hunters(route._hunter_report)
		t_report += Time.get_ticks_usec() - t
		t = Time.get_ticks_usec()
		var centers: Array[Vector3i] = [route.facility.current_chunk_coord()]
		route._build_hunter_stream_signature(centers)
		t_signature += Time.get_ticks_usec() - t
		if _loop_index % 6 == 0:   # a forced refresh walks every spawn candidate in the window: sample it
			t = Time.get_ticks_usec()
			route._hunter_stream_signature = ""
			route._refresh_hunter_stream()
			t_refresh += Time.get_ticks_usec() - t
		t = Time.get_ticks_usec()
		if route.has_method("_map_due"):
			route._update_hud(route._map_due())
		t_hud += Time.get_ticks_usec() - t
		await tree.process_frame
	for view in views:
		if is_instance_valid(view):
			(view as HunterView3D).set_process(true)
	for key in view_parts:
		out["v " + String(key)] = float(view_parts[key]) / PARTS_STEPS
	out["audio_per_frame"] = t_audio / float(PARTS_STEPS)
	out["view_process_per_frame"] = t_view / float(PARTS_STEPS)
	out["report_pack_per_call"] = t_report / float(PARTS_STEPS)
	out["hud_per_frame"] = t_hud / float(PARTS_STEPS)
	out["stream_signature_per_call"] = t_signature / float(PARTS_STEPS)
	out["stream_refresh_forced_per_call"] = t_refresh / float(PARTS_STEPS / 6)
	route.set_process(true)
	return out


## What the 30 Hz step asks of the navigation, per step, and what one call costs. Counting navigation swapped in for PARTS_STEPS steps.
func _census(host: Node, route: Node, mode: String) -> Dictionary:
	var tree := host.get_tree()
	var original := route._navigations.get(0) as StreamedHunterNavigation
	if original == null:
		return {}
	var counting := CountNav.new(route.facility.generator, 0, route.world_state)
	counting.refresh(0, original.active_coordinates())
	route._navigations[0] = counting
	route._navigation = counting
	# a fresh navigation bakes its path grid on the first path request: that one-off is the "window move" cost, not a per-step one
	var cells: Array = counting.floor_cells()
	cells.sort()
	var t_cold := Time.get_ticks_usec()
	counting.find_path(cells[cells.size() / 2], cells[cells.size() / 2 + 1])
	var cold_ms := (Time.get_ticks_usec() - t_cold) / 1000.0
	counting.calls.clear()
	counting.usec.clear()
	var census_parts := {}
	var census_ids := {}
	for _i in PARTS_STEPS:
		_move_player(route, mode)
		_timed_step(route, STEP, census_parts, census_ids)
		await tree.process_frame
		await tree.process_frame
	route._navigations[0] = original
	route._navigation = original
	var callers: Array = []
	for key in census_ids:
		if String(key).begins_with("fp:"):
			callers.append([float(census_ids[key]) / PARTS_STEPS, String(key).trim_prefix("fp:"),
				float(census_ids.get("co:" + String(key).trim_prefix("fp:"), 0)) / PARTS_STEPS])
	callers.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	var top_callers := {}
	for i in mini(5, callers.size()):
		top_callers[String(callers[i][1])] = [callers[i][0], callers[i][2]]
	var out := {"top_find_path_callers": top_callers, "cold_path_grid_bake_ms_with_counting": cold_ms, "rebakes_in_census": counting.rebakes - 1,
		"rebake_ms_in_census": (counting.rebake_us - counting.rebake_max_us) / 1000.0 if counting.rebakes > 1 else 0.0}
	for key in counting.calls:
		out[key] = float(counting.calls[key]) / PARTS_STEPS
	for key in counting.usec:
		out[key + "_us"] = float(counting.usec[key]) / PARTS_STEPS
	return out


## Unit costs on the live navigation window: one line-of-sight march, one path, one forced path-grid rebuild (what a window move costs).
func _unit_costs(route: Node) -> Dictionary:
	var navigation := route._navigations.get(0) as StreamedHunterNavigation
	var out := {}
	if navigation == null:
		return out
	var cells: Array = navigation.floor_cells()
	cells.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for span in [8.0, 20.0, 40.0]:
		var pairs: Array = []
		while pairs.size() < 60:
			var a: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
			var b: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
			var d := Vector2(a).distance_to(Vector2(b))
			if d >= span * .8 and d <= span * 1.2:
				pairs.append([a, b])
		var t := Time.get_ticks_usec()
		for pair in pairs:
			navigation.has_line_of_sight(Vector2(pair[0]) + Vector2(.5, .5), Vector2(pair[1]) + Vector2(.5, .5))
		out["los_%d_us" % int(span)] = (Time.get_ticks_usec() - t) / float(pairs.size())
		t = Time.get_ticks_usec()
		var path_cells := 0
		for pair in pairs:
			path_cells += navigation.find_path(pair[0], pair[1]).size()
		out["path_%d_us" % int(span)] = (Time.get_ticks_usec() - t) / float(pairs.size())
		out["path_%d_cells" % int(span)] = path_cells / float(pairs.size())
	var t2 := Time.get_ticks_usec()
	for _i in 2000:
		navigation.can_occupy(60.5, 60.5)
	out["can_occupy_us"] = (Time.get_ticks_usec() - t2) / 2000.0
	# a window move: the grid is rebuilt by the next find_path
	navigation._path_grid_coords.clear()
	var a2: Vector2i = cells[cells.size() / 2]
	var b2: Vector2i = cells[cells.size() / 2 + 1]
	t2 = Time.get_ticks_usec()
	navigation.find_path(a2, b2)
	out["path_grid_rebuild_ms"] = (Time.get_ticks_usec() - t2) / 1000.0
	out["window_cells"] = cells.size()
	return out


## Mirror of HunterView3D._process, piece by piece (each piece skipped when the view no longer has it).
func _timed_view_process(view: HunterView3D, delta: float, parts: Dictionary) -> void:
	for name in ["_update_lens_cull", "_end_grab_pose", "_update_crowd_tier"]:
		if view.has_method(name):
			var t := Time.get_ticks_usec()
			if name == "_end_grab_pose":
				view.call(name, delta)
			else:
				view.call(name)
			_add(parts, "1 " + String(name).trim_prefix("_"), t)
	if not view.has_method("_crowd_tick"):
		return
	var t2 := Time.get_ticks_usec()
	var ran: bool = view._crowd_tick(delta)
	_add(parts, "2 crowd_tick (animation step)", t2)
	if not ran:
		return
	delta = view._crowd_delta
	t2 = Time.get_ticks_usec()
	view._doorway.restore()
	view._chase.restore()
	_add(parts, "3 restore doorway+chase", t2)
	for name in ["_update_head_look", "_update_chase_style", "_update_nw_layers", "_update_beam_visual", "_update_expression", "_update_stars", "_update_doorway"]:
		if view.has_method(name):
			var t := Time.get_ticks_usec()
			view.call(name, delta)
			_add(parts, "4 " + String(name).trim_prefix("_update_"), t)


## Mirror of InfiniteRouteTest._update_hunters with a timer around each piece (keep in step with it; pieces that no longer exist are skipped).
var _nav_meter: RebakeNav
var _rb_mark := 0


func _nav_calls() -> Array:
	if _nav_meter == null:
		return [0, 0]
	return [int(_nav_meter.calls.get("find_path", 0)), int(_nav_meter.calls.get("can_occupy", 0))]


## Census only (CountNav): which hunter's brain.update asked for the A* searches and capsule probes.
func _attribute_nav_calls(per_id: Dictionary, hunter_id: String, before: Array) -> void:
	if _nav_meter == null:
		return
	var now := _nav_calls()
	per_id["fp:" + hunter_id] = int(per_id.get("fp:" + hunter_id, 0)) + int(now[0]) - int(before[0])
	per_id["co:" + hunter_id] = int(per_id.get("co:" + hunter_id, 0)) + int(now[1]) - int(before[1])


## Microseconds since t0 without any path-grid re-bake that ran inside (the bake is reported as its own part, whoever happened to trigger it).
func _spent_since(t0: int) -> int:
	var spent := Time.get_ticks_usec() - t0
	if _nav_meter != null:
		spent -= _nav_meter.rebake_us - _rb_mark
	return spent


func _note_rebake(parts: Dictionary) -> void:
	if _nav_meter == null:
		return
	var rebake := _nav_meter.rebake_us - _rb_mark
	_rb_mark = _nav_meter.rebake_us
	if rebake > 0:
		parts["00 path-grid re-bake (inside any call)"] = int(parts.get("00 path-grid re-bake (inside any call)", 0)) + rebake


func _sec(parts: Dictionary, key: String, t0: int) -> void:
	var spent := Time.get_ticks_usec() - t0
	if _nav_meter != null:
		var rebake := _nav_meter.rebake_us - _rb_mark
		_rb_mark = _nav_meter.rebake_us
		if rebake > 0:
			spent -= rebake
			parts["00 path-grid re-bake (inside any call)"] = int(parts.get("00 path-grid re-bake (inside any call)", 0)) + rebake
	parts[key] = int(parts.get(key, 0)) + spent


func _timed_step(route: Node, delta: float, parts: Dictionary, per_id: Dictionary) -> void:
	var data: Dictionary = route.facility.current_chunk_data()
	_nav_meter = route._navigations.get(0) as RebakeNav
	_rb_mark = _nav_meter.rebake_us if _nav_meter != null else 0
	var t := Time.get_ticks_usec()
	var local_safe: bool = route._player_in_intact_safe_room(data)
	var local_target: Dictionary = route._hunter_target(local_safe)
	_sec(parts, "01 target+safe-room check", t)
	t = Time.get_ticks_usec()
	route._direct_hunters(delta, local_target)
	_sec(parts, "02 director tick+separate (+best_target per hunter)", t)
	var breach_rooms := {}
	for entity_id_value in route._hunter_views.keys().duplicate():
		var entity_id := String(entity_id_value)
		var view := route._hunter_views.get(entity_id) as HunterView3D
		if view == null or not is_instance_valid(view) or view.brain == null:
			continue
		var level := int(route._hunter_levels.get(entity_id, 0))
		var navigation := route._navigations.get(level) as StreamedHunterNavigation
		if navigation == null:
			continue
		t = Time.get_ticks_usec()
		var target: Dictionary = route._target_for_hunter(entity_id, view.brain.position, local_target, -level)
		_sec(parts, "03 target_for_hunter", t)
		t = Time.get_ticks_usec()
		var ladder: bool = route._hunter_ladder_step(entity_id, view, level, navigation, target, local_target, delta)
		_sec(parts, "04 ladder step", t)
		if ladder:
			view.sync_from_brain()
			route._store_hunter(entity_id, view)
			continue
		t = Time.get_ticks_usec()
		var safe_context: Dictionary = route._safe_context_for_target(target, level)
		_sec(parts, "05 safe context", t)
		t = Time.get_ticks_usec()
		route._operate_hunter_room_door(view, level)
		_sec(parts, "06 room door", t)
		t = Time.get_ticks_usec()
		var napping: bool = route._naps.update(entity_id, view.brain, navigation, target, delta, route._nap_rng.randf(), RoomState.difficulty_id())
		var seated := false
		if not napping and not route._naps.naps.has(entity_id):
			seated = route._seats.update(entity_id, view.brain, navigation, target, delta, route._nap_rng.randf(), RoomState.difficulty_id())
		_sec(parts, "07 naps+seats update", t)
		if napping or seated:
			continue
		var captured := false
		if not target.is_empty():
			t = Time.get_ticks_usec()
			route._apply_light_sight(view, target, navigation)
			_sec(parts, "08 light sight", t)
			t = Time.get_ticks_usec()
			var state_name := str(HunterBrain.State.keys()[view.brain.state])
			var calls_before := _nav_calls()
			captured = view.brain.update(delta, navigation, target, maxi(1, -level + 1), GameState.relays_collected)
			var spent := _spent_since(t)
			parts["09 brain.update (perception+nav+gimmick)"] = int(parts.get("09 brain.update (perception+nav+gimmick)", 0)) + spent
			_note_rebake(parts)
			per_id[view.brain.hunter_id] = int(per_id.get(view.brain.hunter_id, 0)) + spent
			per_id["state:%s" % state_name] = int(per_id.get("state:%s" % state_name, 0)) + spent
			per_id["count:%s" % state_name] = int(per_id.get("count:%s" % state_name, 0)) + 1
			_attribute_nav_calls(per_id, view.brain.hunter_id, calls_before)
			view.set_look_target(view.brain.presentation_look_target())
		else:
			t = Time.get_ticks_usec()
			var state_name := str(HunterBrain.State.keys()[view.brain.state])
			view.brain.update_without_target(delta, navigation, maxi(1, -level + 1), GameState.relays_collected)
			var spent := _spent_since(t)
			parts["09 brain.update (perception+nav+gimmick)"] = int(parts.get("09 brain.update (perception+nav+gimmick)", 0)) + spent
			_note_rebake(parts)
			per_id[view.brain.hunter_id] = int(per_id.get(view.brain.hunter_id, 0)) + spent
			per_id["state:%s" % state_name] = int(per_id.get("state:%s" % state_name, 0)) + spent
			per_id["count:%s" % state_name] = int(per_id.get("count:%s" % state_name, 0)) + 1
		t = Time.get_ticks_usec()
		route._hunter_emoter.tick(entity_id, view.brain, delta, {"target_distance": view.brain.position.distance_to(
			target["position"]) if not target.is_empty() else INF})
		_sec(parts, "10 emoter tick", t)
		t = Time.get_ticks_usec()
		view.sync_from_brain()
		_sec(parts, "11 view.sync_from_brain", t)
		t = Time.get_ticks_usec()
		for hunter_event_value in view.brain.world_events:
			route._apply_gimmick_signal(hunter_event_value, view, target)
			route._apply_streamed_hunter_world_event(hunter_event_value, level, navigation)
		view.brain.world_events.clear()
		_sec(parts, "12 world events", t)
		t = Time.get_ticks_usec()
		route._store_hunter(entity_id, view)
		_sec(parts, "13 store_hunter (world_state)", t)
		if not captured and not target.is_empty():
			t = Time.get_ticks_usec()
			route._update_hide_check(entity_id, view, target, navigation, delta)
			_sec(parts, "14 hide check", t)
		if not captured:
			t = Time.get_ticks_usec()
			route._hunter_flips_light(entity_id, view, delta)
			_sec(parts, "15 flips light", t)
	t = Time.get_ticks_usec()
	route._update_safe_room_breaches(delta, breach_rooms)
	_sec(parts, "16 safe room breaches", t)


## Same window with the animation, then the hunters' physics, switched off.
func _ab(host: Node, route: Node, mode: String, frames: int) -> Dictionary:
	var tree := host.get_tree()
	var out := {}
	var players: Array = []
	for view_value in route._hunter_views.values():
		if is_instance_valid(view_value):
			for found in (view_value as Node).find_children("*", "AnimationMixer", true, false):
				players.append(found)
	for found in players:
		(found as AnimationMixer).active = false
	var no_anim := await _measure(host, route, mode, frames)
	for found in players:
		(found as AnimationMixer).active = true
	out["animation_ms"] = no_anim["cpu_ms"]
	for view_value in route._hunter_views.values():
		if is_instance_valid(view_value):
			(view_value as HunterView3D).set_physics_process(false)
	var no_physics := await _measure(host, route, mode, frames)
	for view_value in route._hunter_views.values():
		if is_instance_valid(view_value):
			(view_value as HunterView3D).set_physics_process(true)
	out["no_physics_cpu_ms"] = no_physics["cpu_ms"]
	out["no_physics_phys_ms"] = no_physics["phys_ms"]
	out["animators"] = players.size()
	return out


# ------------------------------------------------------------------------------------------------ output

func _print_row(mode: String, row: Dictionary) -> void:
	var rebakes := int(row.get("rebakes", 0))
	print("HSCALE %-5s N=%2d loaded=%2d  cpu %6.2f ms/60th (proc %6.2f + phys %5.2f = %.1f ms x %.1f ticks/frame) steady %6.2f no-rebake %6.2f | frame p50 %5.1f p95 %6.1f max %6.0f ms, hitches %d (%.0f ms) | path-grid rebakes %d [window %d, walls %d] (%.0f ms total, max %.0f ms, avg %.0fk cells), find_path %d calls %.1f ms, los %d calls %.1f ms, nav.refresh %d calls %.1f ms | bodies %d pairs %d nodes %d [%s]" % [
		mode, int(row["n"]), int(row["loaded"]), float(row["cpu_ms"]), float(row["proc_ms"]), float(row["phys_ms"]),
		float(row["phys_tick_ms"]), float(row["ticks_per_frame"]), float(row["steady_ms"]), float(row.get("cpu_no_rebake_ms", 0.0)),
		float(row["p50"]), float(row["p95"]), float(row["max"]), int(row["hitches"]), float(row["hitch_ms"]),
		rebakes, int(row.get("rebakes_window", 0)), int(row.get("rebakes_walls", 0)), float(row.get("rebake_us", 0)) / 1000.0, float(row.get("rebake_max_us", 0)) / 1000.0,
		float(row.get("rebake_cells", 0)) / maxf(1.0, float(rebakes)) / 1000.0,
		int(row.get("path_calls", 0)), float(row.get("path_us", 0)) / 1000.0, int(row.get("los_calls", 0)), float(row.get("los_us", 0)) / 1000.0,
		int(row.get("refresh_calls", 0)), float(row.get("refresh_us", 0)) / 1000.0, int(row["bodies"]), int(row["pairs"]), int(row["nodes"]), String(row["states"])])
	if row.has("parts"):
		var parts: Dictionary = row["parts"]
		var keys := parts.keys()
		keys.sort()
		var line := ""
		for key in keys:
			var name := String(key)
			if name.begins_with("_") or name.ends_with("_real") or name == "census" or name == "hunter_perf":
				continue
			if name.begins_with("v "):
				continue
			if name[0].is_valid_int():
				line += "%s %.0f | " % [name.substr(0, 2) + name.get_slice(" ", 1), float(parts[key])]
			else:
				line += "%s %.0f | " % [name, float(parts[key])]
		print("HSCALE %-5s N=%2d   us/30Hz-step: real %.0f, parts-sum %.0f  || %s" % [mode, int(row["n"]),
			float(parts.get("update_hunters_real", 0.0)), float(parts.get("_sum_parts", 0.0)), line])
	if row.has("hitch_log") and not (row["hitch_log"] as Array).is_empty():
		print("HSCALE %-5s N=%2d   frames over 150 ms (script process time of that frame, physics, ...): %s" % [mode, int(row["n"]), " || ".join(row["hitch_log"])])
	if row.has("perf_peaks_ms") and not (row["perf_peaks_ms"] as Dictionary).is_empty():
		var peak_line := ""
		for key in row["perf_peaks_ms"]:
			peak_line += "%s %.1f ms | " % [key, float(row["perf_peaks_ms"][key])]
		print("HSCALE %-5s N=%2d   slowest single spans (>= 4 ms): %s" % [mode, int(row["n"]), peak_line])
	if row.has("perf_totals_ms") and not (row["perf_totals_ms"] as Dictionary).is_empty():
		var total_line := ""
		for key in row["perf_totals_ms"]:
			total_line += "%s %.0f ms in %d calls | " % [key, float(row["perf_totals_ms"][key][0]), int(row["perf_totals_ms"][key][1])]
		print("HSCALE %-5s N=%2d   totals over the measured frames: %s" % [mode, int(row["n"]), total_line])
	if row.has("parts") and (row["parts"] as Dictionary).has("hunter_perf"):
		var perf: Dictionary = (row["parts"] as Dictionary)["hunter_perf"]
		var perf_line := ""
		var perf_keys := perf.keys()
		perf_keys.sort_custom(func(a, b) -> bool: return float(perf[a][0]) > float(perf[b][0]))
		for key in perf_keys:
			perf_line += "%s %.0f us (%.1f calls) | " % [key, float(perf[key][0]), float(perf[key][1])]
		print("HSCALE %-5s N=%2d   HunterPerf per 30Hz step: %s" % [mode, int(row["n"]), perf_line])
	if row.has("brain_by_hunter_state"):
		var summary: Dictionary = row["brain_by_hunter_state"]
		var top_line := ""
		for id in summary["top"]:
			top_line += "%s %.0f | " % [id, float(summary["top"][id])]
		var state_line := ""
		for st in summary["states"]:
			state_line += "%s %.0f us x %.1f/step | " % [st, float(summary["states"][st][0]), float(summary["states"][st][1])]
		print("HSCALE %-5s N=%2d   brain.update us/step by hunter: %s|| by state: %s" % [mode, int(row["n"]), top_line, state_line])
	if row.has("parts"):
		var vline := ""
		var vkeys: Array = (row["parts"] as Dictionary).keys()
		vkeys.sort()
		for key in vkeys:
			if String(key).begins_with("v "):
				vline += "%s %.0f | " % [String(key).substr(2), float((row["parts"] as Dictionary)[key])]
		if not vline.is_empty():
			print("HSCALE %-5s N=%2d   view._process pieces, us per frame (all hunters): %s" % [mode, int(row["n"]), vline])
	if row.has("parts") and (row["parts"] as Dictionary).has("census"):
		var census: Dictionary = (row["parts"] as Dictionary)["census"]
		var keys2 := census.keys()
		keys2.sort()
		var line2 := ""
		for key in keys2:
			if census[key] is Dictionary:
				continue
			line2 += "%s %.1f | " % [key, float(census[key])]
		print("HSCALE %-5s N=%2d   navigation calls per 30Hz step: %s" % [mode, int(row["n"]), line2])
		var callers_line := ""
		var top_callers: Dictionary = census.get("top_find_path_callers", {})
		for id in top_callers:
			callers_line += "%s %.1f find_path + %.0f can_occupy | " % [id, float(top_callers[id][0]), float(top_callers[id][1])]
		print("HSCALE %-5s N=%2d   find_path per step by hunter: %s" % [mode, int(row["n"]), callers_line])
	if row.has("ab"):
		var ab: Dictionary = row["ab"]
		print("HSCALE %-5s N=%2d   A/B cpu ms/60th: all on %.2f | animation off %.2f (%d animators) | hunter physics off %.2f (phys %.2f)" % [
			mode, int(row["n"]), float(row["cpu_ms"]), float(ab["animation_ms"]), int(ab["animators"]),
			float(ab["no_physics_cpu_ms"]), float(ab["no_physics_phys_ms"])])


func _print_summary(mode: String, rows: Array, per_id: Dictionary, units: Dictionary) -> void:
	print("HSCALE ---- %s scaling (cpu ms per 1/60 s of game time) ----" % mode)
	var base := 0.0
	var eight := 0.0
	for row in rows:
		if int(row["n"]) == 0:
			base = float(row["cpu_ms"])
		if int(row["n"]) == 8:
			eight = float(row["cpu_ms"])
	for row in rows:
		var n := int(row["n"])
		var extra := float(row["cpu_ms"]) - base
		print("HSCALE   N=%2d  cpu %6.2f  over empty route %+6.2f  per hunter %5.2f%s" % [n, float(row["cpu_ms"]), extra,
			extra / float(n) if n > 0 else 0.0,
			("  vs linear-from-8 %.2fx" % (extra / maxf(.01, (eight - base) * float(n) / 8.0))) if n > 8 and eight > base else ""])
	if not units.is_empty():
		var line := ""
		for key in units:
			line += "%s %.1f | " % [key, float(units[key])]
		print("HSCALE   unit costs (us unless named): %s" % line)
	if not per_id.is_empty():
		var items: Array = []
		var by_state := ""
		for id in per_id:
			if String(id).begins_with("state:"):
				var name := String(id).trim_prefix("state:")
				by_state += "%s %.0f us/call x %d | " % [name, float(per_id[id]) / maxf(1.0, float(per_id.get("count:" + name, 1))), int(per_id.get("count:" + name, 0))]
				continue
			if String(id).begins_with("count:"):
				continue
			items.append([int(per_id[id]), String(id)])
		print("HSCALE   brain.update by state (largest N): %s" % by_state)
		items.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]))
		var line := ""
		for i in mini(10, items.size()):
			line += "%s %.0f us/step | " % [items[i][1], float(items[i][0]) / PARTS_STEPS]
		print("HSCALE   heaviest brain.update by hunter (largest N): %s" % line)


func _check_scaling(mode: String, rows: Array) -> void:
	var max_ms := float(_env("HUNTER_BENCH_MAX_MS", "40"))
	var max_ratio := float(_env("HUNTER_BENCH_MAX_RATIO", "2.2"))
	var base := 0.0
	var eight := 0.0
	var top := 0.0
	var top_n := 0
	for row in rows:
		var n := int(row["n"])
		if n == 0:
			base = float(row["cpu_ms"])
		elif n == 8:
			eight = float(row["cpu_ms"])
		if n >= top_n:
			top_n = n
			top = float(row["cpu_ms"])
	if top_n >= 26:
		_expect(top <= max_ms, "%s: %d hunters cost %.1f ms per 1/60 s (limit %.0f)" % [mode, top_n, top, max_ms])
	# Frame pacing at the largest crowd: the old tree spiralled (8 physics ticks a frame, 120-160 ms frames, 0.5-0.8 s path-grid
	# re-bakes); a healthy one stays far below these generous limits even on a loaded machine.
	var last: Dictionary = rows.back() if not rows.is_empty() else {}
	for row in rows:
		# the schedule: while the simulation keeps up, every loaded hunter is stepped 30 times per game second (staggered or not)
		var n_row := int(row["n"])
		if n_row >= 1 and n_row <= 16 and float(row["ticks_per_frame"]) <= 1.5:
			var rate := float(row.get("steps_per_hunter_s", 0.0))
			_expect(_env("HUNTER_BENCH_STEP_BUDGET_USEC", "") != "" or (rate > 27.0 and rate < 33.0), "%s: %d hunters are stepped %.1f times per game second (expected 30)" % [mode, n_row, rate])
			var dt_rate := float(row.get("dt_per_hunter_s", 0.0))
			_expect(dt_rate > 0.9 and dt_rate < 1.1, "%s: %d hunters were given %.2f s of brain time per game second (expected 1.0)" % [mode, n_row, dt_rate])
	if top_n >= 26 and not last.is_empty():
		var max_p50 := float(_env("HUNTER_BENCH_MAX_P50", "100"))
		var max_ticks := float(_env("HUNTER_BENCH_MAX_TICKS", "6"))
		var max_rebake := float(_env("HUNTER_BENCH_MAX_REBAKE_MS", "150"))
		_expect(float(last["p50"]) <= max_p50, "%s: %d hunters, median frame %.1f ms (limit %.0f)" % [mode, top_n, float(last["p50"]), max_p50])
		_expect(float(last["ticks_per_frame"]) <= max_ticks, "%s: %d hunters, %.1f physics ticks per frame (limit %.0f): the simulation cannot keep up" % [
			mode, top_n, float(last["ticks_per_frame"]), max_ticks])
		_expect(float(last.get("rebake_max_us", 0)) / 1000.0 <= max_rebake, "%s: %d hunters, a path-grid re-bake took %.0f ms (limit %.0f)" % [
			mode, top_n, float(last.get("rebake_max_us", 0)) / 1000.0, max_rebake])
	if eight > base and top_n > 8:
		var linear := (eight - base) * float(top_n) / 8.0
		_expect(top - base <= linear * max_ratio, "%s: %d hunters add %.1f ms, %.2fx the linear extrapolation from 8 (%.1f); limit %.1fx" % [
			mode, top_n, top - base, (top - base) / maxf(.01, linear), linear, max_ratio])
