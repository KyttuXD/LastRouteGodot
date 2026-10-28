extends Node

## Streaming benchmark (windowed, needs a GPU: run it on the mini). Loads a Last Route or City run, then drives the runner along
## a fixed, seeded path at sprint speed (position-driven, so every run crosses the same chunks in the same frames) and records
## every frame's time plus periodic renderer/scene samples. Prints a BENCH summary and writes OUTDIR/stream_bench_<TAG>.json.
##
##   mini-run.sh <dir> <lane> --scene res://tools/look/stream_bench.tscn -- OUTDIR TAG MODE [SECONDS] [SEED] [SPEED]
##
## MODE: route (Last Route, straight legs east/south/east through fresh chunks); a layout-backed map scene can reuse
## the same loop shape with MODE city.
## SECONDS defaults to 90; pass 600 for the ten-minute memory soak. SPEED is metres per second (default 7.0, a sprint).
## Budgets live in scripts/validate_stream_perf.gd, which reads the JSON this writes.

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


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out_dir = args[0] if args.size() > 0 else "/tmp"
	_tag = args[1] if args.size() > 1 else "bench"
	_mode = args[2] if args.size() > 2 else "route"
	_seconds = float(args[3]) if args.size() > 3 else 90.0
	var seed_text: String = args[4] if args.size() > 4 and args[4] != "-" else ("CITY-LOOK" if _mode == "city" else "STREAM-BENCH")
	_speed = float(args[5]) if args.size() > 5 else 7.0
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var out := []
	OS.execute("sysctl", ["-n", "vm.loadavg"], out)
	_loadavg = String(out[0]).strip_edges() if not out.is_empty() else ""
	Backend.enable_offline_mode()
	Settings.fps_limit = 0
	Settings.vsync_enabled = false
	Settings._apply_display_performance()
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = seed_text
	var started := Time.get_ticks_usec()
	_scene = load("res://scenes/infinite_route_test.tscn").instantiate()
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
	if OS.get_environment("BENCH_NOAUDIO") != "":
		AudioServer.set_bus_mute(0, true)
		_scene.set_process(false)
	for _i in 30:
		await _settle()
	if _facility.has_method("take_frame_stream_cost"):
		_facility.take_frame_stream_cost()
	_last_usec = Time.get_ticks_usec()
	_running = true


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


func _build_path() -> void:
	if _mode == "ladder":
		if not _find_ladder():
			push_error("stream_bench: no ladder near the spawn")
		_path = [_ladder_top, _ladder_top]
		return
	var start := _player.global_position
	var size := float(StreamedRouteGenerator.CHUNK_SIZE)
	if _mode == "city":
		# Clockwise round the inner chunk ring and back through the middle: every chunk enters and leaves the stream window.
		var a := Vector3(-1.5 * size, start.y, -0.5 * size)
		_path = [start, Vector3(0, start.y, -0.5 * size), Vector3(1.5 * size, start.y, -0.5 * size),
			Vector3(1.5 * size, start.y, 0.6 * size), Vector3(-1.5 * size, start.y, 0.6 * size), a, start]
	else:
		_path = [start, start + Vector3(4 * size, 0, 0), start + Vector3(4 * size, 0, 3 * size),
			start + Vector3(9 * size, 0, 3 * size), start + Vector3(9 * size, 0, -2 * size)]


func _point_at(distance: float) -> Dictionary:
	var travelled := 0.0
	var loop := 0.0
	for i in _path.size() - 1:
		loop += _path[i].distance_to(_path[i + 1])
	if _mode == "city" and loop > 0.0:
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
		return
	var now := Time.get_ticks_usec()
	var frame_ms := (now - _last_usec) / 1000.0
	_last_usec = now
	_frames.append(frame_ms)
	var cost: Array = _facility.take_frame_stream_cost() if _facility.has_method("take_frame_stream_cost") else [0.0, ""]
	if frame_ms > HITCH_MS:
		_hitch_log.append({"t": snappedf(_elapsed, .01), "ms": snappedf(frame_ms, .1),
			"stream_cpu_ms": snappedf(float(cost[0]), .1), "step": cost[1],
			"process_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, .1),
			"physics_ms": snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, .1)})
	_stream_cpu_max = maxf(_stream_cpu_max, float(cost[0]))
	_stream_frames.append(1 if _streaming() else 0)
	_elapsed += delta
	var point := _point_at(_elapsed * _speed)
	var dir: Vector3 = point["dir"]
	_player.global_position = point["pos"]
	_player._yaw = atan2(-dir.x, -dir.z)
	if _mode == "ladder":
		_player.global_position = _ladder_point(_elapsed)
		_player._yaw = _elapsed * .6   # look around: the whole window is on screen over a stay
		_track_trip(frame_ms)
	_player._pitch = 0.0
	_player._apply_look_rotation()
	_sample_clock += delta
	if _sample_clock >= SAMPLE_EVERY:
		_sample_clock = 0.0
		_samples.append(_sample())
	if _elapsed >= _seconds:
		_running = false
		if _mode == "ladder":
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
			"mean_ms": snappedf(total / maxf(frames.size(), 1), .01), "builds": trip.get("builds", 0), "loaded_max": trip["loaded_max"]})
	return out


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
		"avg_ms": snappedf(total / maxf(_frames.size(), 1), .01),
		"p50_ms": snappedf(_percentile(sorted, .5), .01), "p95_ms": snappedf(_percentile(sorted, .95), .01),
		"p99_ms": snappedf(_percentile(sorted, .99), .01), "max_ms": snappedf(sorted[-1] if not sorted.is_empty() else 0.0, .01),
		"stream_frames": stream_sorted.size(), "stream_max_ms": snappedf(stream_sorted[-1] if not stream_sorted.is_empty() else 0.0, .01),
		"stream_p99_ms": snappedf(_percentile(stream_sorted, .99), .01),
		"hitches_33": hitches, "stream_cpu_max_ms": snappedf(_stream_cpu_max, .1), "jump_ms": _jumps, "trips": _trip_summary(), "loadavg": _loadavg, "stream_hitches_33": stream_hitches,
		"peak": peak, "mean": mean, "last": last,
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
	for trip in summary["trips"]:
		print("TRIP to=%d t=%.1f max=%.1f over33=%d mean=%.2f builds=%d loaded_max=%d" % [trip["to"], trip["t"], trip["max_ms"],
			trip["over33"], trip["mean_ms"], trip["builds"], trip["loaded_max"]])
	for hitch in _hitch_log.slice(0, 40):
		print("HITCH t=%.2f ms=%.1f stream_cpu=%.1f step=%s process=%.1f physics=%.1f" % [hitch["t"], hitch["ms"], hitch["stream_cpu_ms"],
			hitch["step"], hitch["process_ms"], hitch["physics_ms"]])
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
