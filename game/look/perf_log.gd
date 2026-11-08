class_name PerfLog
extends Node

## On-device frame log (phones and the Quest by default: PlatformProfile.perf_log; `--perflog` anywhere). Every frame's
## time goes into a histogram; frames over SPIKE_MS are kept with a cause tag:
##   stream:<step>  chunk building/unloading on the main thread (StreamedFacilityView3D build phase)
##   level_change   the game's chunk_changed listeners (hunter navigation, minimap) after crossing a chunk or level
##   script         other main-thread script work (Performance.TIME_PROCESS took most of the frame)
##   render         the rest: GPU/driver, first-use shader/pipeline compiles, texture uploads
## Written every WRITE_EVERY seconds to user://perf/perf_log.json (and a readable perf_log.txt). Pull it with
##   adb pull /sdcard/Android/data/<package>/files/perf   (or `adb shell run-as <package> cat files/perf/perf_log.txt`)
##   xcrun devicectl device copy from --device <udid> --domain-type appDataContainer \
##     --domain-identifier org.kyttuslab.lastroute.phone --source Documents/perf --destination ./perf

## Auto-run for devices nobody can tap remotely: a file user://perf_autorun.cfg holding the stream_bench arguments
## (e.g. "ladder 66" or "route 66 - 7.0") makes the boot jump straight into the benchmark, which logs as usual and quits.
## Push it with `adb shell run-as <package> sh -c 'echo route 66 > files/perf_autorun.cfg'` or devicectl `copy to`.
const AUTORUN_FILE := "user://perf_autorun.cfg"
const BENCH_SCENE := "res://dev/look/stream_bench.tscn"


## Called once at boot by PlatformProfile: attaches the log when enabled and starts an auto-run when one is queued.
static func install(root: Node, enabled: bool) -> void:
	if enabled:
		var perf := PerfLog.new()
		perf.name = "PerfLog"
		root.add_child.call_deferred(perf)
	# Player Release builds leave tools/ out (export exclude filter): only an internal build has the bench scene.
	if FileAccess.file_exists(AUTORUN_FILE) and ResourceLoader.exists(BENCH_SCENE):
		root.get_tree().change_scene_to_file.call_deferred(BENCH_SCENE)


## The queued auto-run's benchmark arguments (OUTDIR TAG MODE SECONDS ...), consumed so a crash cannot loop it.
static func autorun_args() -> PackedStringArray:
	if not FileAccess.file_exists(AUTORUN_FILE):
		return PackedStringArray()
	var words := FileAccess.get_file_as_string(AUTORUN_FILE).strip_edges().split(" ", false)
	DirAccess.remove_absolute(AUTORUN_FILE)
	var args := PackedStringArray(["user://perf", "device_%s" % (words[0] if words.size() > 0 else "route")])
	args.append_array(words)
	return args


## Section timing for profiling builds: PerfLog.section("name", start_usec) adds the elapsed time to a named bucket;
## the summary lists every bucket's average and worst per frame. Costs nothing unless something calls it.
static var _sections := {}
static func section(name: String, start_usec: int) -> void:
	var ms := (Time.get_ticks_usec() - start_usec) / 1000.0
	var entry: Array = _sections.get(name, [0.0, 0.0, 0, 0.0])   # total ms, worst ms, calls, this frame
	entry[0] += ms
	entry[1] = maxf(entry[1], ms)
	entry[2] += 1
	entry[3] += ms
	_sections[name] = entry


const SPIKE_MS := 33.3
const BUCKETS := [16.7, 20.0, 25.0, 33.3, 50.0, 100.0]
const WRITE_EVERY := 10.0
const MAX_SPIKES := 400

var _last_usec := 0
var _histogram := []
var _spikes: Array = []
var _frames := 0
var _total_ms := 0.0
var _worst_ms := 0.0
var _started_msec := 0
var _write_clock := 0.0
var _facility: Node
var _find_clock := 0.0
var _per_second: Array = []
var _second_frames := 0
var _second_ms := 0.0
## live readouts for the admin FPS/spike overlay (PerfOverlay).
var _last_frame_ms := 0.0
var _last_spike: Dictionary = {}
var _spike_flash_left := 0.0
static var _instance: PerfLog




func _ready() -> void:
	_instance = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000   # after the streamed view, so its build cost this frame is already counted
	_histogram.resize(BUCKETS.size() + 1)
	_histogram.fill(0)
	_started_msec = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute("user://perf")


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_usec == 0:
		_last_usec = now
		return
	var ms := (now - _last_usec) / 1000.0
	_last_usec = now
	_last_frame_ms = ms
	_spike_flash_left = maxf(0.0, _spike_flash_left - delta)
	_frames += 1
	_total_ms += ms
	_worst_ms = maxf(_worst_ms, ms)
	var bucket := BUCKETS.size()
	for i in BUCKETS.size():
		if ms <= BUCKETS[i]:
			bucket = i
			break
	_histogram[bucket] += 1
	_second_frames += 1
	_second_ms += ms
	if _second_ms >= 1000.0:
		_per_second.append(snappedf(1000.0 * _second_frames / _second_ms, .1))
		if _per_second.size() > 600:
			_per_second.pop_front()
		_second_frames = 0
		_second_ms = 0.0
	var cost := _stream_cost()
	for key in _sections:
		var entry: Array = _sections[key]
		entry[3] = 0.0
	if ms > SPIKE_MS:
		var spike := _spike(ms, cost)
		_last_spike = spike
		_spike_flash_left = 1.2
		if _spikes.size() < MAX_SPIKES:
			_spikes.append(spike)
	_write_clock += delta
	if _write_clock >= WRITE_EVERY:
		_write_clock = 0.0
		write()


func _stream_cost() -> Array:
	_find_clock -= get_process_delta_time()
	if (_facility == null or not is_instance_valid(_facility)) and _find_clock <= 0.0:
		_find_clock = 2.0
		var scene := get_tree().current_scene
		_facility = scene.find_child("StreamedFacility", true, false) if scene != null else null
	if _facility == null or not is_instance_valid(_facility) or not _facility.has_method("take_frame_stream_cost"):
		return [0.0, ""]
	return _facility.take_frame_stream_cost()


func _spike(ms: float, cost: Array) -> Dictionary:
	var stream_ms := float(cost[0])
	var step := String(cost[1])
	var process_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var tag := "render"
	if stream_ms >= ms * .4:
		tag = "level_change" if step.begins_with("chunk_changed") or step.begins_with("refresh") else "stream:" + step
	elif process_ms >= ms * .6:
		tag = "script"
	var entry := {"t": snappedf((Time.get_ticks_msec() - _started_msec) / 1000.0, .01), "ms": snappedf(ms, .1),
		"tag": tag, "stream_ms": snappedf(stream_ms, .1), "process_ms": snappedf(process_ms, .1)}
	if _facility != null and is_instance_valid(_facility) and _facility.has_method("current_chunk_coord"):
		entry["chunk"] = str(_facility.current_chunk_coord())
	return entry



## Live FPS from the rolling second bucket (falls back to Engine when cold).
func live_fps() -> float:
	if _second_ms > 50.0 and _second_frames > 0:
		return snappedf(1000.0 * _second_frames / _second_ms, .1)
	return float(Engine.get_frames_per_second())


func last_frame_ms() -> float:
	return snappedf(_last_frame_ms, .1)


func last_spike() -> Dictionary:
	return _last_spike.duplicate()


func spike_flash_left() -> float:
	return _spike_flash_left


func spike_count() -> int:
	return _spikes.size()


static func instance() -> PerfLog:
	return _instance


static func ensure(root: Node) -> PerfLog:
	if _instance != null and is_instance_valid(_instance):
		return _instance
	var perf := PerfLog.new()
	perf.name = "PerfLog"
	root.add_child(perf)
	return perf


func summary() -> Dictionary:
	var tags := {}
	for spike in _spikes:
		tags[spike["tag"]] = int(tags.get(spike["tag"], 0)) + 1
	var sorted := _per_second.duplicate()
	sorted.sort()
	return {
		"device": OS.get_model_name(), "os": OS.get_name(), "profile": PlatformProfile.summary(),
		"seconds": snappedf((Time.get_ticks_msec() - _started_msec) / 1000.0, .1), "frames": _frames,
		"avg_fps": snappedf(1000.0 * _frames / maxf(_total_ms, .001), .1), "worst_ms": snappedf(_worst_ms, .1),
		"lowest_second_fps": sorted[0] if not sorted.is_empty() else 0.0,
		"histogram_ms_upper": BUCKETS + ["inf"], "histogram": _histogram, "spike_tags": tags,
		"sections": _section_summary(),
	}


func _section_summary() -> Dictionary:
	var out := {}
	for key in _sections:
		var entry: Array = _sections[key]
		out[key] = {"avg_ms_per_frame": snappedf(float(entry[0]) / maxf(_frames, 1), .01), "worst_ms": snappedf(float(entry[1]), .1),
			"calls": entry[2]}
	return out


func write() -> void:
	var data := {"summary": summary(), "spikes": _spikes, "fps_per_second": _per_second}
	var file := FileAccess.open("user://perf/perf_log.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data))
		file.close()
	var text := FileAccess.open("user://perf/perf_log.txt", FileAccess.WRITE)
	if text == null:
		return
	var s: Dictionary = data["summary"]
	text.store_line("%s %s | %s | %.0f s, %d frames, avg %.1f fps, worst %.1f ms, lowest 1 s %.1f fps" % [
		s["device"], s["os"], s["profile"], s["seconds"], s["frames"], s["avg_fps"], s["worst_ms"], s["lowest_second_fps"]])
	text.store_line("histogram (frames up to ms): %s -> %s" % [str(s["histogram_ms_upper"]), str(s["histogram"])])
	text.store_line("spikes by cause: %s" % str(s["spike_tags"]))
	var sections: Dictionary = s["sections"]
	var names := sections.keys()
	names.sort_custom(func(a, b) -> bool: return float(sections[a]["avg_ms_per_frame"]) > float(sections[b]["avg_ms_per_frame"]))
	for key in names:
		text.store_line("  section %-32s avg %.2f ms/frame, worst %.1f ms, %d calls" % [key, sections[key]["avg_ms_per_frame"],
			sections[key]["worst_ms"], sections[key]["calls"]])
	for spike in _spikes:
		text.store_line("  t=%.2f %.1f ms %s (stream %.1f, process %.1f) %s" % [spike["t"], spike["ms"], spike["tag"],
			spike["stream_ms"], spike["process_ms"], spike.get("chunk", "")])
	text.close()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_EXIT_TREE:
		write()
