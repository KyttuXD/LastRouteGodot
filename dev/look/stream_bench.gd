extends Node

## Streaming benchmark (windowed, needs a GPU). Loads a Last Route or City run, then drives the runner along
## a fixed, seeded path at sprint speed (position-driven, so every run crosses the same chunks in the same frames) and records
## every frame's time plus periodic renderer/scene samples. Prints a BENCH summary and writes OUTDIR/stream_bench_<TAG>.json.
##
##   godot --path . res://dev/look/stream_bench.tscn -- OUTDIR TAG MODE [SECONDS] [SEED] [SPEED]
##
## MODE: route (Last Route, straight legs east/south/east through fresh chunks, extended with fresh ground when SPEED x
## SECONDS outruns it); levels (the route walk while a teleport steps up through every level and back down, see
## LEVEL_DWELL); ladder, sewer, flashlight, city. A layout-backed map scene can reuse the same loop shape with MODE city.
## SECONDS defaults to 90; pass 600 for the ten-minute memory soak. SPEED is metres per second (default 7.0, a sprint).
## Budgets live in tests/validate_stream_perf.gd, which reads the JSON this writes.

const SAMPLE_EVERY := 0.5
const HITCH_MS := 33.3

var _out_dir := "/tmp"
var _tag := "bench"
var _mode := "route"
var _seconds := 90.0
var _speed := 7.0
var _scene: Node
var _facility: StreamedFacilityView3D
var _player: PlayerController3D
var _path: Array[Vector3] = []
var _frames: PackedFloat32Array = PackedFloat32Array()
var _stream_frames := PackedByteArray()
var _samples: Array = []
var _last_usec := 0
var _elapsed := 0.0
var _sample_clock := 0.0
var _startup_ms := 0.0
var _running := false
var _hitch_log: Array = []
var _stream_cpu_max := 0.0
var _jumps: Array = []
var _loadavg := ""


## Startup log: every frame from the start of _ready() until the measured run begins (scene load, the settle frames and the
## wait for the spawn window to finish streaming). The first entry is the whole synchronous load; the rest show where the
## stalls are (ms, what the streaming system was doing). Reported as STARTUP lines and summary["startup"].
var _startup_log: Array = []
var _su_last := 0
var _startup_done := false   # set when the measured run begins: nothing after that (the run, the teleport probes) is startup


func _ready() -> void:
	_su_last = Time.get_ticks_usec()
	var args := OS.get_cmdline_user_args()
	var auto := PerfLog.autorun_args()
	if not auto.is_empty():
		args = auto
	_out_dir = args[0] if args.size() > 0 else "/tmp"
	_tag = args[1] if args.size() > 1 else "bench"
	_mode = args[2] if args.size() > 2 else "route"
	_seconds = float(args[3]) if args.size() > 3 else 90.0
	var seed_text: String = args[4] if args.size() > 4 and args[4] != "-" else ("CITY-LOOK" if _mode == "city" else "STREAM-BENCH")
	_speed = float(args[5]) if args.size() > 5 else 7.0
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_loadavg = _load_average()
	Backend.enable_offline_mode()
	Settings.fps_limit = 0
	Settings.vsync_enabled = false
	Settings._apply_display_performance()
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = seed_text
	var started := Time.get_ticks_usec()
	_scene = load("res://game/infinite_route/infinite_route_test.tscn").instantiate()
	add_child(_scene)
	_facility = _scene.get_node("%StreamedFacility")
	_player = _scene.get_node("%Player")
	# Startup: until the first frame is presented with the spawn window loaded.
	await get_tree().process_frame
	await get_tree().process_frame
	_startup_ms = (Time.get_ticks_usec() - started) / 1000.0
	_player.admin_god_mode = true
	_player.set_physics_process(false)
	_build_path()
	if OS.get_environment("BENCH_NOLIGHTS") != "":
		_facility.set_all_lights(false)
	# Finer A/B switches to attribute a lighting stall: the shared LampField pool only, the budgeted lights only
	# (re-hidden every 0.25 s as chunks stream in), or every Label3D sign.
	if OS.get_environment("BENCH_NOPOOL") != "":
		_facility._lamp_field.set_enabled(false)
	# BENCH_SOUNDMUTED=1: Sound.muted, so no cue is rendered or played and no bed starts (the audio cost without touching
	# the scene's _process); BENCH_NOSCENEPROC=1: the scene root's _process off, audio untouched. BENCH_NOAUDIO=1 does both.
	if OS.get_environment("BENCH_SOUNDMUTED") != "":
		Sound.set_muted(true)
	if OS.get_environment("BENCH_NOSCENEPROC") != "":
		_scene.set_process(false)
	if OS.get_environment("BENCH_NOAUDIO") != "":
		AudioServer.set_bus_mute(0, true)
		_scene.set_process(false)
	for _i in 30:
		await _settle()
	for _i in 1200:   # the start position's window (and, in the sewer, the jump down) fully streamed in first
		if not _streaming() and not (_facility.has_method("is_preloading") and _facility.is_preloading()):
			break
		await _settle()
	if _facility.has_method("take_frame_stream_cost"):
		_facility.take_frame_stream_cost()
	await _add_bench_hunters()
	_last_usec = Time.get_ticks_usec()
	_startup_done = true
	_running = true


## BENCH_HUNTERS=<n> (1..38, roster order: the 26 A-Z hunters, then the 12 void_*): n awake hunters around the start, through the same
## world_state / stream path the game and the admin summon use, so every hunter is the real HunterView3D + brain + navigation.
## BENCH_HUNTER_PLACE=near (2.5-7 m, a crowd in your face; default) | spread (14-45 m). A hunter walks at 3-5 m/s: use a slow runner
## (speed 4 or less) or the crowd falls out of the residency window and the count drops (the HITCH / sample lines print hunters=).
## Headless counterpart with a per-subsystem table: tests/validate_hunter_scaling.gd (docs/PERF_PASS.md, "Hunter scaling").
func _add_bench_hunters() -> void:
	var wanted := int(OS.get_environment("BENCH_HUNTERS")) if OS.get_environment("BENCH_HUNTERS") != "" else 0
	if wanted <= 0:
		return
	var navigation = _scene._navigations.get(0)
	for _i in 120:
		if navigation != null:
			break
		_scene._hunter_stream_signature = ""
		_scene._refresh_hunter_stream()
		await _settle()
		navigation = _scene._navigations.get(0)
	if navigation == null:
		print("BENCH_HUNTERS: no navigation window yet, no hunters added")
		return
	GameState.escape_grace = 1000.0   # the runner cannot be grabbed (the test scene ignores admin god mode without a proven login)
	var ids: Array = []
	ids.append_array(HunterRoster.A_Z_IDS)
	ids.append_array(HunterRoster.VOID_IDS)
	var near := OS.get_environment("BENCH_HUNTER_PLACE") != "spread"
	var low := 2.5 if near else 14.0
	var high := 7.0 if near else 45.0
	var player_at: Vector2 = _player.grid_position()
	var cells: Array = navigation.floor_cells()
	cells.sort()
	var pool: Array = []
	for cell in cells:
		var gap := (Vector2(cell) + Vector2(.5, .5)).distance_to(player_at)
		if gap >= low and gap <= high:
			pool.append(cell)
	if pool.is_empty():
		pool = cells
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("BENCH-HUNTERS")
	for index in mini(wanted, ids.size()):
		var cell: Vector2i = pool[rng.randi_range(0, pool.size() - 1)]
		var entity_id := "BENCH:%s:%d" % [ids[index], index]
		var state: Dictionary = _scene.world_state.ensure_hunter({"id": entity_id, "hunter_id": String(ids[index]),
			"origin_chunk": navigation.cell_chunk(cell, 0), "cell": StreamedHunterNavigation.local_cell(cell), "level": 0})
		if state.is_empty():
			continue
		state["position"] = Vector2(cell) + Vector2(.5, .5)
		state["active"] = true
		state["state"] = HunterBrain.State.SEARCH
		state["has_last_known"] = true
		state["last_known"] = player_at
		_scene.world_state.hunters[entity_id] = state
	_scene._hunter_stream_signature = ""
	_scene._refresh_hunter_stream()
	for view_value in _scene._hunter_views.values():
		var view := view_value as HunterView3D
		if view != null and view.brain != null:
			if not view.brain.active:
				view.brain.activate_at(player_at)
			view.target_peer_id = 1
	for _i in 60:
		await _settle()
	print("BENCH_HUNTERS requested=%d loaded=%d place=%s" % [wanted, _hunter_count(), "near" if near else "spread"])


## Machine load before the run: macOS sysctl, Linux /proc/loadavg, Windows has none ("n/a").
static func _load_average() -> String:
	if OS.get_name() == "macOS":
		var out := []
		OS.execute("sysctl", ["-n", "vm.loadavg"], out)
		return String(out[0]).strip_edges() if not out.is_empty() else "n/a"
	if OS.get_name() in ["Linux", "FreeBSD"] and FileAccess.file_exists("/proc/loadavg"):
		return FileAccess.get_file_as_string("/proc/loadavg").strip_edges()
	return "n/a"


func _settle() -> void:
	await get_tree().process_frame
	var pause = _scene.get("pause_menu")
	if pause != null and pause.has_method("close") and pause.is_open():
		pause.close()
	get_tree().paused = false


## Ladder mode: a real ladder near the spawn; the runner climbs down (2 s), stays 6 s, climbs up (2 s), stays 6 s.
const LADDER_CLIMB := 2.0
const LADDER_STAY := 6.0
var _ladder_top := Vector3.ZERO
var _trips: Array = []
var _trip_level := 0


func _find_ladder() -> bool:
	var gen := _facility.generator
	var size := StreamedRouteGenerator.CHUNK_SIZE
	for ring in 4:
		for z in range(-ring, ring + 1):
			for x in range(-ring, ring + 1):
				var links: Array = gen.sewer().links_for(Vector3i(x, 0, z))
				if links.is_empty():
					continue
				var cell: Vector2i = links[0]["from_cell"]
				_ladder_top = Vector3(x * size + cell.x + .5, .05, z * size + cell.y + .5)
				return true
	return false


func _ladder_point(t: float) -> Vector3:
	var cycle := 2.0 * (LADDER_CLIMB + LADDER_STAY)
	var u := fmod(t, cycle)
	var bottom := _ladder_top + Vector3(0, SewerRouteGenerator.LEVEL * StreamedFacilityView3D.LEVEL_HEIGHT, 0)
	if u < LADDER_STAY:
		return _ladder_top
	u -= LADDER_STAY
	if u < LADDER_CLIMB:
		return _ladder_top.lerp(bottom, u / LADDER_CLIMB)
	u -= LADDER_CLIMB
	if u < LADDER_STAY:
		return bottom
	return bottom.lerp(_ladder_top, (u - LADDER_STAY) / LADDER_CLIMB)


## Levels mode (up/down testing): the runner walks the route path while a teleport steps one storey at a time through
## every level, up to the top and down to the bottom, and back to 0. Each stop lasts LEVEL_DWELL seconds, so every change
## is measured by _track_trip. Teleports skip the real links (no pre-built landing chunks), so this is the harsh case.
var _ab_clock := 0.0
var _prev_nodes := 0
var _prev_hunters := 0
const LEVEL_DWELL := 3.0
var _level_sequence: Array[int] = []


static func _make_level_sequence() -> Array[int]:
	var seq: Array[int] = []
	var top := StreamedRouteGenerator.top_level()
	var bottom := StreamedRouteGenerator.INFERNO_LEVEL
	for level in range(0, top + 1):
		seq.append(level)
	for level in range(top - 1, bottom - 1, -1):
		seq.append(level)
	for level in range(bottom + 1, 1):
		seq.append(level)
	return seq


func _level_y_at(t: float) -> float:
	var index := int(t / LEVEL_DWELL) % _level_sequence.size()
	return _level_sequence[index] * StreamedFacilityView3D.LEVEL_HEIGHT + .05


func _build_path() -> void:
	if _mode == "flashlight" or _mode == "flashshots":
		_path = [_player.global_position, _player.global_position]
		return
	if _mode == "ladder":
		if not _find_ladder():
			push_error("stream_bench: no ladder near the spawn")
		_path = [_ladder_top, _ladder_top]
		return
	var start := _player.global_position
	var size := float(StreamedRouteGenerator.CHUNK_SIZE)
	if _mode == "sewer":
		# Along the sewer's main tunnel walkway (cells 18-20 of every chunk row), four chunks east and back, looping.
		var y := SewerRouteGenerator.LEVEL * StreamedFacilityView3D.LEVEL_HEIGHT + .05
		var a := Vector3(floorf(start.x / size) * size + 2.5, y, floorf(start.z / size) * size + 19.5)
		_path = [a, a + Vector3(4 * size, 0, 0), a]
		_player.global_position = a
		return
	if _mode == "city":
		# Clockwise round the inner chunk ring and back through the middle: every chunk enters and leaves the stream window.
		var a := Vector3(-1.5 * size, start.y, -0.5 * size)
		_path = [start, Vector3(0, start.y, -0.5 * size), Vector3(1.5 * size, start.y, -0.5 * size),
			Vector3(1.5 * size, start.y, 0.6 * size), Vector3(-1.5 * size, start.y, 0.6 * size), a, start]
	else:
		if _mode == "levels":
			_level_sequence = _make_level_sequence()
			_seconds = maxf(_seconds, LEVEL_DWELL * _level_sequence.size())
		_path = [start, start + Vector3(4 * size, 0, 0), start + Vector3(4 * size, 0, 3 * size),
			start + Vector3(9 * size, 0, 3 * size), start + Vector3(9 * size, 0, -2 * size)]
		# A faster SPEED outruns the fixed path (the runner would stand still at its end): keep adding fresh ground,
		# a north/south excursion at every new column further east, until the path covers SPEED x SECONDS.
		var needed := _speed * _seconds
		var length := 0.0
		for i in _path.size() - 1:
			length += _path[i].distance_to(_path[i + 1])
		var excursion := 1.0
		while length < needed:
			var east: Vector3 = _path[-1] + Vector3(5 * size, 0, 0)
			var turn: Vector3 = east + Vector3(0, 0, 4 * size * excursion)
			_path.append_array([east, turn])
			length += 5 * size + 4 * size
			excursion = -excursion


func _point_at(distance: float) -> Dictionary:
	var travelled := 0.0
	var loop := 0.0
	for i in _path.size() - 1:
		loop += _path[i].distance_to(_path[i + 1])
	if _mode in ["city", "sewer"] and loop > 0.0:
		distance = fmod(distance, loop)
	for i in _path.size() - 1:
		var leg := _path[i].distance_to(_path[i + 1])
		if travelled + leg >= distance or i == _path.size() - 2:
			var t := clampf((distance - travelled) / maxf(leg, .001), 0.0, 1.0)
			return {"pos": _path[i].lerp(_path[i + 1], t), "dir": (_path[i + 1] - _path[i]).normalized()}
		travelled += leg
	return {"pos": _path[-1], "dir": Vector3.FORWARD}


func _process(delta: float) -> void:
	if not _running:
		if _startup_done:
			return
		var su_now := Time.get_ticks_usec()
		var su_cost: Array = [0.0, ""]
		if _facility != null and _facility.has_method("take_frame_stream_cost"):
			su_cost = _facility.take_frame_stream_cost()
		_startup_log.append({"i": _startup_log.size(), "t": snappedf((su_now - _su_last) / 1000.0, .1),
			"ms": snappedf((su_now - _su_last) / 1000.0 - (float(_startup_log[-1]["t"]) if not _startup_log.is_empty() else 0.0), .1),
			"step": su_cost[1], "stream_cpu_ms": snappedf(float(su_cost[0]), .1),
			"proc_prev": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, .1),   # the PREVIOUS frame's script time
			"phys_prev": snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, .1),   # and its physics time
			"nav_prev": snappedf(Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0, .1),
			"chunks": _facility.loaded_chunk_count() if _facility != null else 0})
		return
	var now := Time.get_ticks_usec()
	var frame_ms := (now - _last_usec) / 1000.0
	_last_usec = now
	_frames.append(frame_ms)
	var nodes_now := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var hunters_now := _hunter_count()
	var cost: Array = _facility.take_frame_stream_cost() if _facility.has_method("take_frame_stream_cost") else [0.0, ""]
	if frame_ms > HITCH_MS:
		_hitch_log.append({"t": snappedf(_elapsed, .01), "ms": snappedf(frame_ms, .1),
			"stream_cpu_ms": snappedf(float(cost[0]), .1), "step": cost[1],
			"process_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, .1),
			"physics_ms": snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, .1),
			"pos": [snappedf(_player.global_position.x, .1), snappedf(_player.global_position.y, .1), snappedf(_player.global_position.z, .1)],
			"chunk": str(_facility.current_chunk_coord()), "pending_loads": _facility._pending_loads.size(),
			"nodes": nodes_now, "nodes_prev": _prev_nodes, "hunters": hunters_now, "hunters_prev": _prev_hunters,
			"frame": Engine.get_process_frames()})
	_prev_nodes = nodes_now
	_prev_hunters = hunters_now
	_stream_cpu_max = maxf(_stream_cpu_max, float(cost[0]))
	_stream_frames.append(1 if _streaming() else 0)
	_elapsed += delta
	var point := _point_at(_elapsed * _speed)
	var dir: Vector3 = point["dir"]
	_player.global_position = point["pos"]
	_player._yaw = atan2(-dir.x, -dir.z)
	if _mode == "play":
		# Hunters spawn and chase as relays are collected; a capture ends the run (death flow, no results file). The test
		# scene ignores admin god mode without a proven admin login, so hold the game's own post-escape immunity instead:
		# hunters keep spawning, navigating and chasing, the runner just cannot be grabbed.
		GameState.escape_grace = 1000.0
		_track_play(frame_ms)
	if _mode == "levels":
		var at: Vector3 = _player.global_position
		_player.global_position = Vector3(at.x, _level_y_at(_elapsed), at.z)
		_track_trip(frame_ms)
	if _mode == "flashshots":
		_track_flashshots()
	if _mode == "flashlight":
		_track_flashlight(frame_ms)
	if _mode == "ladder":
		_player.global_position = _ladder_point(_elapsed)
		_player._yaw = _elapsed * .6   # look around: the whole window is on screen over a stay
		_track_trip(frame_ms)
	_player._pitch = 0.0
	_player._apply_look_rotation()
	_ab_clock += delta
	if _ab_clock >= .25:
		_ab_clock = 0.0
		if OS.get_environment("BENCH_NOBUDGET") != "":
			for node in get_tree().get_nodes_in_group(LampField.BUDGET_GROUP):
				(node as Light3D).visible = false
		if OS.get_environment("BENCH_NOLABELS") != "":
			for node in _scene.find_children("*", "Label3D", true, false):
				(node as Label3D).visible = false
	_sample_clock += delta
	if _sample_clock >= SAMPLE_EVERY:
		_sample_clock = 0.0
		_samples.append(_sample())
	if _elapsed >= _seconds:
		_running = false
		if _mode == "ladder" or _mode == "levels" or _mode == "flashshots":
			_finish()
		else:
			_jump_probes()


## Per level change: frames in the 4 s after arriving (max, count over 33 ms, mean), chunk builds and lights then.
func _track_trip(frame_ms: float) -> void:
	var level := _facility.current_level()
	if level != _trip_level:
		_trip_level = level
		_trips.append({"to": level, "t": snappedf(_elapsed, .01), "builds0": _builds(), "frames": PackedFloat32Array(),
			"loaded_max": 0, "lights_shadow_max": 0})
	if _trips.is_empty():
		return
	var trip: Dictionary = _trips[-1]
	if _elapsed - float(trip["t"]) <= 4.0:
		var frames: PackedFloat32Array = trip["frames"]
		frames.append(frame_ms)
		trip["frames"] = frames
		trip["loaded_max"] = maxi(int(trip["loaded_max"]), _facility.loaded_chunk_count())
	trip["builds"] = _builds() - int(trip["builds0"])


func _trip_summary() -> Array:
	var out := []
	for trip in _trips:
		var frames: PackedFloat32Array = trip["frames"]
		var worst := 0.0
		var over := 0
		var total := 0.0
		for f in frames:
			worst = maxf(worst, f)
			total += f
			if f > HITCH_MS:
				over += 1
		out.append({"to": trip["to"], "t": trip["t"], "max_ms": snappedf(worst, .1), "over33": over,
			"dip_fps": snappedf(_min_window_fps(frames), .1),
			"mean_ms": snappedf(total / maxf(frames.size(), 1), .01), "builds": trip.get("builds", 0), "loaded_max": trip["loaded_max"]})
	return out


## Play mode (lights + flashlight + relay collecting): the route walk with the flashlight switched on (it stays on; shadows
## follow the graphics tier) and, once a second, the nearest uncollected relay within COLLECT_REACH metres is collected through
## the same RouteInteractable3D.activate() call a player's interact press makes. Each collect keeps its own cost and the worst
## frame in the next 0.5 s; the lights themselves are in the normal samples (BENCH_NOLIGHTS=1 turns them off for an A/B).
const COLLECT_REACH := 8.0
var _collects: Array = []
var _collect_clock := 0.0
var _play_started := false
func _track_play(frame_ms: float) -> void:
	if not _play_started:
		_play_started = true
		var slot: int = _player.inventory_order.find("flashlight")
		if slot >= 0 and OS.get_environment("BENCH_NOFLASH") == "":   # BENCH_NOFLASH=1: A/B without the flashlight
			_player.select_inventory_slot(slot)
			_player._set_flashlight(true)
	if not _collects.is_empty() and _elapsed - float(_collects[-1]["t"]) <= .5:
		_collects[-1]["max_ms"] = maxf(float(_collects[-1]["max_ms"]), frame_ms)
	_collect_clock += get_process_delta_time()
	if _collect_clock < 1.0 or OS.get_environment("BENCH_NOCOLLECT") != "":   # BENCH_NOCOLLECT=1: A/B without collecting
		return
	_collect_clock = 0.0
	var best: RouteInteractable3D = null
	var best_d := COLLECT_REACH
	for id in _facility._pickup_nodes.keys():
		var node := _facility._pickup_nodes[id] as RouteInteractable3D
		if node == null or not is_instance_valid(node) or node.completed or node.kind != RouteInteractable3D.Kind.RELAY:
			continue
		var d := node.global_position.distance_to(_player.global_position)
		if d < best_d:
			best_d = d
			best = node
	if best == null:
		return
	var hunters_before := _hunter_count()
	var t0 := Time.get_ticks_usec()
	var steps := ""
	var result := ""
	if OS.get_environment("BENCH_COLLECT_PROFILE") != "":
		# the RELAY branch of activate(), step by step (BENCH_COLLECT_PROFILE=1), to see which part is slow
		best._take()
		var t1 := Time.get_ticks_usec()
		Sound.collect()
		var t2 := Time.get_ticks_usec()
		best.changed.emit({"what": "pickup", "cell": best.source_cell, "kind": best.kind})
		var t3 := Time.get_ticks_usec()
		steps = "take=%.1f sound=%.1f emit=%.1f" % [(t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0]
	else:
		result = best.activate(_player)
	_collects.append({"t": _elapsed, "activate_ms": snappedf((Time.get_ticks_usec() - t0) / 1000.0, .01),
		"max_ms": 0.0, "result": (steps if not steps.is_empty() else result).substr(0, 60), "completed": best.completed,
		"hunters_before": hunters_before, "hunters_after": _hunter_count()})


## Hunter views the room currently holds (HunterView3D per streamed hunter); -1 when the scene does not expose them.
func _hunter_count() -> int:
	var views = _scene.get("_hunter_views")
	return views.size() if views is Dictionary else -1


## Flashshots mode (flashlight visuals): the runner stands at the spawn and a fixed script saves the rendered root viewport as
## PNG (OUTDIR/shot_<TAG>_<label>.png) with the flashlight off, then on, then turned 90 and 180 degrees, then off again, and
## prints the flashlight's state with every shot (FLASH lines). The images come from Godot itself, so they need no OS
## screen-recording permission and show exactly what the game renders on that GPU/driver/tier.
var _fs_index := 0
var _fs_wait := -1
var _fs_label := ""
var _fs_yaw := 0.0
const FS_STEPS := [
	{"t": 2.5, "label": "1_off", "action": "none"},
	{"t": 4.0, "label": "2_on", "action": "on"},
	{"t": 6.0, "label": "3_on_yaw90", "action": "yaw"},
	{"t": 8.0, "label": "4_on_yaw180", "action": "yaw"},
	{"t": 10.0, "label": "5_on_yaw270", "action": "yaw"},
	{"t": 12.0, "label": "6_off_again", "action": "off"},
]


var _fs_follow: Node3D
var _fs_ref: Node3D


func _track_flashshots() -> void:
	_player._yaw = _fs_yaw
	if _fs_follow != null and is_instance_valid(_fs_ref):
		_fs_follow.global_transform = _fs_ref.global_transform   # a light kept in the world, following the camera pivot
	if _fs_wait > 0:
		_fs_wait -= 1
		if _fs_wait == 0:
			_fs_shot()
		return
	if _fs_index >= FS_STEPS.size() or _elapsed < float(FS_STEPS[_fs_index]["t"]):
		return
	var step: Dictionary = FS_STEPS[_fs_index]
	_fs_index += 1
	match String(step["action"]):
		"on":
			_player.select_inventory_slot(_player.inventory_order.find("flashlight"))
			_player._set_flashlight(true)
			_fs_variant()
		"off":
			_player._set_flashlight(false)
		"yaw":
			_fs_yaw += PI / 2.0
	_fs_label = String(step["label"])
	_fs_wait = 5   # let the change reach the screen: a few frames, then capture


## BENCH_SPOT=<variant> changes the flashlight once it is switched on, to find what a driver gets wrong:
##   omni (an OmniLight3D of the same energy/range in the spot's place), att1 (spot_angle_attenuation 1.0), energy1 (energy 1.0),
##   wide (spot_angle 70), shadow (shadow_enabled on).
func _fs_variant() -> void:
	var v := OS.get_environment("BENCH_SPOT")
	var light: SpotLight3D = _player.flashlight
	match v:
		"omni":
			var o := OmniLight3D.new()
			o.name = "BenchOmniFlash"
			o.light_energy = light.light_energy
			o.omni_range = light.spot_range
			o.position = light.position
			light.get_parent().add_child(o)
			light.visible = false
		"att1":
			light.spot_angle_attenuation = 1.0
		"energy1":
			light.light_energy = 1.0
		"wide":
			light.spot_angle = 70.0
		"shadow":
			light.shadow_enabled = true
		"world_spot", "world_omni":
			# the same light, but NOT a child of the camera pivot: placed in the world root and moved to follow it
			_fs_ref = Marker3D.new()
			_fs_ref.position = light.position
			light.get_parent().add_child(_fs_ref)
			if v == "world_spot":
				light.reparent(_scene, true)
				_fs_follow = light
			else:
				var w := OmniLight3D.new()
				w.light_energy = light.light_energy
				w.omni_range = light.spot_range
				_scene.add_child(w)
				_fs_follow = w
				light.visible = false
	print("FLASH variant=%s" % (v if v != "" else "none"))


func _fs_shot() -> void:
	var img := get_viewport().get_texture().get_image()
	var path := _out_dir.path_join("shot_%s_%s.png" % [_tag, _fs_label])
	var err := img.save_png(path)
	var light: SpotLight3D = _player.flashlight
	# mean brightness of the frame, so a black or washed-out frame is visible in the log without opening the image
	var small := img.duplicate()
	small.resize(8, 8, Image.INTERPOLATE_BILINEAR)
	var sum := 0.0
	for y in 8:
		for x in 8:
			sum += small.get_pixel(x, y).get_luminance()
	print("FLASH shot=%s saved=%s size=%s luma=%.3f | enabled=%s visible=%s energy=%.2f range=%.1f angle=%.1f shadow=%s color=%s charge=%.1f yaw=%.2f renderer=%s" % [
		_fs_label, str(err == OK), str(img.get_size()), sum / 64.0, str(_player.flashlight_enabled), str(light.visible),
		light.light_energy, light.spot_range, light.spot_angle, str(light.shadow_enabled), str(light.light_color),
		_player.lamp_charge, _player._yaw, RenderingServer.get_current_rendering_method()])


## Flashlight mode: the runner stands at the spawn and toggles the flashlight every 1.5 s; each toggle's worst frame in
## the next 0.5 s is kept (the first toggle used to compile the shadowed SpotLight's shaders and allocate its atlas).
var _toggles: Array = []
var _toggle_clock := 0.0
func _track_flashlight(frame_ms: float) -> void:
	_path = [_path[0], _path[0]]
	if not _toggles.is_empty() and _elapsed - float(_toggles[-1]["t"]) <= .5:
		_toggles[-1]["max_ms"] = maxf(float(_toggles[-1]["max_ms"]), frame_ms)
	_toggle_clock += get_process_delta_time()
	if _toggle_clock >= 1.5:
		_toggle_clock = 0.0
		# exactly what the flashlight key does (PlayerController3D input): select the slot, then toggle
		_player.select_inventory_slot(_player.inventory_order.find("flashlight"))
		_player._set_flashlight(not _player.flashlight_enabled)
		_toggles.append({"t": _elapsed, "on": _player.flashlight_enabled, "beam": _player.flashlight.visible, "max_ms": 0.0})


func _sample() -> Dictionary:
	var lights := 0
	var shadow_lights := 0
	var visible_lights := 0
	for node in _scene.find_children("*", "Light3D", true, false):
		var light := node as Light3D
		lights += 1
		if light.is_visible_in_tree():
			visible_lights += 1
			if light.shadow_enabled:
				shadow_lights += 1
	return {
		"t": snappedf(_elapsed, .01),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"physics_active": Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		"physics_pairs": Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
		"mem_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"vmem_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"lights": lights, "lights_visible": visible_lights, "lights_shadow": shadow_lights,
		"chunks": _facility.loaded_chunk_count(),
		"dormant": _facility.dormant_chunk_count() if _facility.has_method("dormant_chunk_count") else 0,
		"prebuilt": _facility.prebuilt_chunk_count() if _facility.has_method("prebuilt_chunk_count") else 0,
	}


static func _percentile(sorted: PackedFloat32Array, p: float) -> float:
	if sorted.is_empty():
		return 0.0
	return sorted[clampi(int(round(p * (sorted.size() - 1))), 0, sorted.size() - 1)]


## FPS of the slowest `share` of frames (1% low, 0.1% low): the average frame time of that slice, as FPS.
static func _low_fps(sorted: PackedFloat32Array, share: float) -> float:
	if sorted.is_empty():
		return 0.0
	var count := maxi(1, int(ceil(sorted.size() * share)))
	var total := 0.0
	for i in count:
		total += sorted[sorted.size() - 1 - i]
	return 1000.0 * count / maxf(total, .001)


## Lowest FPS over any 0.5 s window of consecutive frames.
static func _std(frames: PackedFloat32Array) -> float:
	if frames.size() < 2:
		return 0.0
	var mean := 0.0
	for f in frames:
		mean += f
	mean /= frames.size()
	var acc := 0.0
	for f in frames:
		acc += (f - mean) * (f - mean)
	return sqrt(acc / (frames.size() - 1))


static func _min_window_fps(frames: PackedFloat32Array, window_ms: float = 500.0) -> float:
	var best := INF
	var start := 0
	var acc := 0.0
	for i in frames.size():
		acc += frames[i]
		while acc - frames[start] >= window_ms and start < i:
			acc -= frames[start]
			start += 1
		if acc >= window_ms * .95:
			best = minf(best, 1000.0 * (i - start + 1) / acc)
	return best if best != INF else 0.0


## Startup frames: the whole load, how many frames were slow, and the worst ones with what streaming was doing.
## "stall_max_ms" skips frame 0 (the synchronous scene load, which startup_ms already reports).
func _startup_summary() -> Dictionary:
	var rows := _startup_log.duplicate()
	# TIME_PROCESS read on frame i+1 is frame i's script time: what is left of the frame is rendering, driver, GPU and waits.
	for i in rows.size():
		var script_ms: float = float(rows[i + 1]["proc_prev"]) if i + 1 < rows.size() else 0.0
		var phys_ms: float = float(rows[i + 1]["phys_prev"]) + float(rows[i + 1]["nav_prev"]) if i + 1 < rows.size() else 0.0
		rows[i]["process_ms"] = script_ms
		rows[i]["physics_ms"] = phys_ms
		rows[i]["other_ms"] = snappedf(maxf(0.0, float(rows[i]["ms"]) - script_ms - phys_ms), .1)
	var slow := rows.filter(func(r): return float(r["ms"]) > HITCH_MS)
	var tail := rows.slice(1)
	tail.sort_custom(func(a, b): return float(a["ms"]) > float(b["ms"]))
	var total := 0.0
	for r in rows:
		total += float(r["ms"])
	return {"frames": rows.size(), "total_ms": snappedf(total, .1), "first_frame_ms": rows[0]["ms"] if not rows.is_empty() else 0.0,
		"slow_frames": slow.size(), "stall_max_ms": tail[0]["ms"] if not tail.is_empty() else 0.0,
		"worst": tail.slice(0, 12)}


static func _max_of(rows: Array, key: String) -> float:
	var worst := 0.0
	for row in rows:
		worst = maxf(worst, float(row.get(key, 0.0)))
	return snappedf(worst, .1)


func _summary() -> Dictionary:
	var sorted := _frames.duplicate()
	sorted.sort()
	var stream_sorted := PackedFloat32Array()
	var hitches := 0
	var stream_hitches := 0
	var total := 0.0
	for i in _frames.size():
		total += _frames[i]
		if _frames[i] > HITCH_MS:
			hitches += 1
			if _stream_frames[i] == 1:
				stream_hitches += 1
		if _stream_frames[i] == 1:
			stream_sorted.append(_frames[i])
	stream_sorted.sort()
	var peak := {}
	var last: Dictionary = _samples[-1] if not _samples.is_empty() else {}
	for sample in _samples:
		for key in sample:
			peak[key] = maxf(float(peak.get(key, 0.0)), float(sample[key]))
	var mean := {}
	for sample in _samples:
		for key in sample:
			mean[key] = float(mean.get(key, 0.0)) + float(sample[key]) / _samples.size()
	return {
		"tag": _tag, "mode": _mode, "seconds": _seconds, "speed": _speed, "frames": _frames.size(),
		"startup_ms": snappedf(_startup_ms, .1),
		"avg_fps": snappedf(_frames.size() / maxf(total / 1000.0, .001), .1),
		"low1_fps": snappedf(_low_fps(sorted, .01), .1), "low01_fps": snappedf(_low_fps(sorted, .001), .1),
		"min_window_fps": snappedf(_min_window_fps(_frames), .1),
		"avg_ms": snappedf(total / maxf(_frames.size(), 1), .01),
		"p50_ms": snappedf(_percentile(sorted, .5), .01), "p95_ms": snappedf(_percentile(sorted, .95), .01),
		"p99_ms": snappedf(_percentile(sorted, .99), .01), "max_ms": snappedf(sorted[-1] if not sorted.is_empty() else 0.0, .01),
		"stream_frames": stream_sorted.size(), "stream_max_ms": snappedf(stream_sorted[-1] if not stream_sorted.is_empty() else 0.0, .01),
		"stream_p99_ms": snappedf(_percentile(stream_sorted, .99), .01),
		"hitches_33": hitches, "stream_cpu_max_ms": snappedf(_stream_cpu_max, .1), "jump_ms": _jumps, "trips": _trip_summary(), "loadavg": _loadavg, "stream_hitches_33": stream_hitches,
		"collects": _collects.size(), "collect_activate_ms_max": _max_of(_collects, "activate_ms"),
		"collect_frame_ms_max": _max_of(_collects, "max_ms"), "toggle_frame_ms_max": _max_of(_toggles, "max_ms"),
		"flashlight_on": _player.flashlight_enabled, "relays_collected": GameState.relays_collected,
		"peak": peak, "mean": mean, "last": last,
		"startup": _startup_summary(),
		"mem_growth_mb": snappedf(float(last.get("mem_mb", 0.0)) - float(_samples[min(4, _samples.size() - 1)].get("mem_mb", 0.0)), .1) if _samples.size() > 1 else 0.0,
	}


## Level changes and teleports: the main-thread cost of the stream refresh that follows them (it used to build the whole
## window synchronously). Route: up a level, back down, then 5 chunks east. City: a teleport across the map.
func _jump_probes() -> void:
	var size := float(StreamedRouteGenerator.CHUNK_SIZE)
	var base := _player.global_position
	var moves: Array = [Vector3(0, 0, 0)]
	if _mode == "city":
		moves = [Vector3(-3 * size, 0, 0), Vector3(3 * size, 0, 0)]
	else:
		moves = [Vector3(0, StreamedFacilityView3D.LEVEL_HEIGHT, 0), Vector3.ZERO, Vector3(5 * size, 0, 0)]
	for move in moves:
		_player.global_position = base + move
		var t0 := Time.get_ticks_usec()
		_facility._refresh_stream(false)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		_jumps.append(snappedf(ms, .1))
		for _i in 240:
			await get_tree().process_frame
			if not _streaming():
				break
	_finish()


func _finish() -> void:
	var summary := _summary()
	var file := FileAccess.open(_out_dir.path_join("stream_bench_%s.json" % _tag), FileAccess.WRITE)
	file.store_string(JSON.stringify({"summary": summary, "samples": _samples, "hitch_log": _hitch_log, "frames": Array(_frames)}))
	file.close()
	print("BENCH %s stream_cpu_max=%.1f jump_ms=%s loadavg=%s" % [_tag, _stream_cpu_max, str(_jumps), _loadavg])
	var line := "BENCH %s mode=%s startup_ms=%.0f fps=%.1f p50=%.2f p95=%.2f p99=%.2f max=%.2f stream_max=%.2f hitches33=%d stream_hitches33=%d" % [
		_tag, _mode, summary["startup_ms"], summary["avg_fps"], summary["p50_ms"], summary["p95_ms"], summary["p99_ms"],
		summary["max_ms"], summary["stream_max_ms"], summary["hitches_33"], summary["stream_hitches_33"]]
	print(line)
	for collect in _collects:
		print("COLLECT t=%.1f activate_ms=%.2f frame_max=%.1f done=%s hunters=%d->%d result=%s" % [collect["t"], collect["activate_ms"],
			collect["max_ms"], str(collect["completed"]), collect["hunters_before"], collect["hunters_after"], collect["result"]])
	print("PLAY %s collects=%d relays_collected=%d flashlight_on=%s hunters_final=%d" % [_tag, _collects.size(), GameState.relays_collected,
		str(_player.flashlight_enabled), _hunter_count()])
	for toggle in _toggles:
		print("TOGGLE t=%.1f on=%s beam=%s max=%.1f" % [toggle["t"], str(toggle["on"]), str(toggle.get("beam")), toggle["max_ms"]])
	for trip in summary["trips"]:
		print("TRIP to=%d t=%.1f max=%.1f over33=%d mean=%.2f builds=%d loaded_max=%d dip_fps=%.1f" % [trip["to"], trip["t"], trip["max_ms"],
			trip["over33"], trip["mean_ms"], trip["builds"], trip["loaded_max"], trip["dip_fps"]])
	var su: Dictionary = summary["startup"]
	print("STARTUP %s frames=%d total_ms=%.0f first_frame_ms=%.0f slow_frames=%d stall_max_ms=%.0f" % [_tag, su["frames"], su["total_ms"],
		su["first_frame_ms"], su["slow_frames"], su["stall_max_ms"]])
	for w in su["worst"]:
		print("STARTUP_FRAME %s i=%d at=%.0fms ms=%.1f script=%.1f physics+nav=%.1f other(render/driver/wait)=%.1f step=%s stream_cpu=%.1f chunks=%d" % [_tag,
			w["i"], w["t"], w["ms"], w["process_ms"], w["physics_ms"], w["other_ms"], w["step"], w["stream_cpu_ms"], w["chunks"]])
	print("FPS %s mode=%s avg=%.1f low1=%.1f low01=%.1f min_window=%.1f std_ms=%.2f renderer=%s scale3d=%.2f res=%s vsync=%s" % [_tag, _mode,
		summary["avg_fps"], summary["low1_fps"], summary["low01_fps"], summary["min_window_fps"], _std(_frames),
		RenderingServer.get_current_rendering_method(), get_viewport().scaling_3d_scale, str(get_viewport().get_visible_rect().size),
		str(DisplayServer.window_get_vsync_mode())])
	print("GPU %s adapter=%s vendor=%s api=%s window=%s scale=%.2f hidpi=%s tier=%s" % [_tag, RenderingServer.get_video_adapter_name(),
		RenderingServer.get_video_adapter_vendor(), RenderingServer.get_video_adapter_api_version(),
		str(DisplayServer.window_get_size()), DisplayServer.screen_get_scale(), str(ProjectSettings.get_setting("display/window/dpi/allow_hidpi")),
		PlatformProfile.tier_readout()])
	for hitch in _hitch_log.slice(0, 40):
		print("HITCH t=%.2f ms=%.1f stream_cpu=%.1f step=%s process=%.1f physics=%.1f pos=%s chunk=%s pending=%d nodes=%d(prev %d) hunters=%d(prev %d)" % [hitch["t"], hitch["ms"], hitch["stream_cpu_ms"],
			hitch["step"], hitch["process_ms"], hitch["physics_ms"], str(hitch["pos"]), hitch["chunk"], hitch["pending_loads"],
			hitch["nodes"], hitch["nodes_prev"], hitch["hunters"], hitch["hunters_prev"]])
	var peak: Dictionary = summary["peak"]
	var mean: Dictionary = summary["mean"]
	print("BENCH %s draw_calls avg=%.0f peak=%.0f objects avg=%.0f nodes peak=%.0f lights_visible avg=%.1f shadow avg=%.1f peak=%.0f mem_mb=%.0f growth=%.1f vmem_mb=%.0f chunks peak=%.0f dormant peak=%.0f prebuilt peak=%.0f" % [
		_tag, mean.get("draw_calls", 0), peak.get("draw_calls", 0), mean.get("objects", 0), peak.get("nodes", 0),
		mean.get("lights_visible", 0), mean.get("lights_shadow", 0), peak.get("lights_shadow", 0), peak.get("mem_mb", 0),
		summary["mem_growth_mb"], peak.get("vmem_mb", 0), peak.get("chunks", 0), peak.get("dormant", 0), peak.get("prebuilt", 0)])
	get_tree().quit(0)


func _streaming() -> bool:
	if _facility.has_method("is_streaming"):
		return _facility.is_streaming()
	return not (_facility._pending_loads.is_empty() and _facility._pending_unloads.is_empty() and _facility._active_build.is_empty())


func _builds() -> int:
	var value = _facility.get("chunk_builds")
	return int(value) if value != null else -1
