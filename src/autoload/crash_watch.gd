extends Node

## Crash and freeze detection (KT, 2026-10-28: "log and detect any crashes somehow automatically").
##
## - Session sentinel: logs/crashwatch_session.json is written at boot (and refreshed every few seconds with the
##   breadcrumbs and error counts) and removed on a clean quit. Found at the next launch, the last session crashed or
##   was killed; a logs/crashwatch_freeze.json beside it means it froze first.
## - Errors: a Logger (OS.add_logger) counts every script error, push_error and warning and keeps the last few, rate
##   limited, in a ring and in logs/crashwatch_events.log (capped, rotated).
## - Breadcrumbs: the last BREADCRUMBS things that happened -- scene, level and region, room code, host or guest,
##   interactions and grabs (CrashWatch.crumb(), plus what this node polls).
## - Freeze watchdog: a thread that notices the main loop has not ticked for FREEZE_SECONDS and writes a dump.
## - Report: on the next launch (or when a freeze recovers) an lr.crash/1 report goes to a queue in user://, and is
##   POSTed to /api/v1/crash-reports when Settings.send_crash_reports is on, on a real (not headless/test) run.
##
## Godot's own file log (project.godot [debug] file_logging, user://logs/godot*.log, 5 files) supplies the log tail.

const SCHEMA := "lr.crash/1"
const ENDPOINT := "/api/v1/crash-reports"
const SENTINEL_NAME := "crashwatch_session.json"
const FREEZE_NAME := "crashwatch_freeze.json"
const EVENTS_NAME := "crashwatch_events.log"
const EVENTS_MAX_BYTES := 5 * 1024 * 1024
const EVENTS_FILES := 5
const QUEUE_MAX := 10
const BREADCRUMBS := 50
const RECENT_ERRORS := 50
const ERROR_LINES_PER_SECOND := 20
const LINE_CHARS := 400
const LOG_TAIL_BYTES := 32 * 1024
const FREEZE_SECONDS := 10.0
const SENTINEL_REFRESH_SECONDS := 5.0
const POLL_SECONDS := 0.5
const SEND_DELAY_SECONDS := 4.0

## Where the sentinel, dumps, events log and queue live (a validator points a private instance elsewhere).
var log_dir := "user://logs"
var queue_dir := "user://crash_queue"
## The autoload starts itself; test instances call start() / stop() by hand.
var autostart := true
## The freeze watchdog thread (a test instance drives check_stall() itself instead).
var watchdog_thread := true
## The report found at this launch (crash or freeze of the previous session), or {}.
var previous_report := {}

var _sink: CrashSink
var _crumbs: Array[String] = []
var _mutex := Mutex.new()
var _heartbeat_ms := 0
var _watchdog: Thread
var _stop_watchdog := false
var _suspended := false
var _freeze_started_ms := 0
var _session_started := 0
var _since_refresh := 0.0
var _since_poll := 0.0
var _seen := {}
var _sending := false
var _running := false
var _enqueued := 0


## Engine errors and warnings, from any thread.
class CrashSink extends Logger:
	var errors := 0
	var warnings := 0
	var script_errors := 0
	var dropped := 0
	var recent: Array[String] = []
	var _mutex := Mutex.new()
	var _second := 0
	var _in_second := 0
	var _events: FileAccess
	var _events_path := ""

	func _init(events_path: String) -> void:
		_events_path = events_path

	func _log_message(_message: String, _error: bool) -> void:
		pass   # plain output is in Godot's own file log

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		var text := rationale if not rationale.is_empty() else code
		var kind := "W" if error_type == Logger.ERROR_TYPE_WARNING else ("S" if error_type == Logger.ERROR_TYPE_SCRIPT else "E")
		record(kind, "%s (%s:%d %s)" % [text, file.get_file(), line, function])

	func record(kind: String, text: String) -> void:
		_mutex.lock()
		if kind == "W":
			warnings += 1
		else:
			errors += 1
			if kind == "S":
				script_errors += 1
		var now := Time.get_ticks_msec() / 1000
		if now != _second:
			_second = now
			_in_second = 0
		_in_second += 1
		if _in_second > ERROR_LINES_PER_SECOND:
			dropped += 1   # counted, not kept: a per-frame error must not flood the ring or the disk
		else:
			var entry := "%s %d %s" % [kind, Time.get_ticks_msec(), text.left(LINE_CHARS)]
			recent.append(entry)
			if recent.size() > RECENT_ERRORS:
				recent.pop_front()
			_write_event(entry)
		_mutex.unlock()

	func counts() -> Dictionary:
		_mutex.lock()
		var out := {"errors": errors, "warnings": warnings, "script_errors": script_errors, "dropped": dropped}
		_mutex.unlock()
		return out

	func recent_copy() -> Array[String]:
		_mutex.lock()
		var out := recent.duplicate()
		_mutex.unlock()
		return out

	func write_line(line: String) -> void:
		_mutex.lock()
		_write_event(line)
		_mutex.unlock()

	func _write_event(line: String) -> void:
		if _events == null:
			_events = FileAccess.open(_events_path, FileAccess.READ_WRITE if FileAccess.file_exists(_events_path) \
				else FileAccess.WRITE)
			if _events == null:
				return
			_events.seek_end()
		if _events.get_position() > EVENTS_MAX_BYTES:
			_events.close()
			_events = null
			rotate(_events_path, EVENTS_FILES)
			_events = FileAccess.open(_events_path, FileAccess.WRITE)
			if _events == null:
				return
		_events.store_line(line)
		_events.flush()

	static func rotate(path: String, keep: int) -> void:
		for index in range(keep - 1, 0, -1):
			var older := "%s.%d" % [path, index]
			var newer := path if index == 1 else "%s.%d" % [path, index - 1]
			if FileAccess.file_exists(newer):
				DirAccess.rename_absolute(newer, older)

	func close() -> void:
		_mutex.lock()
		if _events != null:
			_events.close()
			_events = null
		_mutex.unlock()


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Engine.is_editor_hint():
		autostart = false   # the editor and --import: no sentinel, logger, watchdog or reports
	if autostart:
		start()


func _ready() -> void:
	if autostart and not previous_report.is_empty():
		get_tree().create_timer(SEND_DELAY_SECONDS, true, false, true).timeout.connect(send_queue)


func _exit_tree() -> void:
	if autostart:
		stop()


## Reads (and clears) what the last session left behind, queues its report, then marks this session as running.
func start() -> void:
	if _running:
		return
	_running = true
	DirAccess.make_dir_recursive_absolute(log_dir)
	DirAccess.make_dir_recursive_absolute(queue_dir)
	previous_report = _previous_session_report()
	if not previous_report.is_empty():
		enqueue(previous_report)
	_session_started = int(Time.get_unix_time_from_system())
	_heartbeat_ms = Time.get_ticks_msec()
	_sink = CrashSink.new(log_dir.path_join(EVENTS_NAME))
	OS.add_logger(_sink)
	crumb("boot", "%s %s %s" % [Build.revision(), OS.get_name(), OS.get_model_name()])
	_write_sentinel()
	_stop_watchdog = false
	if watchdog_thread:
		_watchdog = Thread.new()
		_watchdog.start(_watch)


## A clean end: the sentinel goes, so the next launch reports nothing.
func stop() -> void:
	if not _running:
		return
	_running = false
	_stop_watchdog = true
	if _watchdog != null and _watchdog.is_started():
		_watchdog.wait_to_finish()
	_watchdog = null
	if _sink != null:
		OS.remove_logger(_sink)
		_sink.close()
	DirAccess.remove_absolute(log_dir.path_join(SENTINEL_NAME))
	DirAccess.remove_absolute(log_dir.path_join(FREEZE_NAME))


func is_running() -> bool:
	return _running


## Adds a breadcrumb ("interact", "stream_door d12"). Safe from any thread.
func crumb(kind: String, text: String = "") -> void:
	var line := "%d %s %s" % [Time.get_ticks_msec(), kind, text.left(LINE_CHARS - 40)]
	_mutex.lock()
	_crumbs.append(line)
	if _crumbs.size() > BREADCRUMBS:
		_crumbs.pop_front()
	_mutex.unlock()
	if _sink != null:
		_sink.write_line("# " + line)


func breadcrumbs() -> Array[String]:
	_mutex.lock()
	var out := _crumbs.duplicate()
	_mutex.unlock()
	return out


func counts() -> Dictionary:
	return _sink.counts() if _sink != null else {"errors": 0, "warnings": 0, "script_errors": 0, "dropped": 0}


func _process(delta: float) -> void:
	if not _running:
		return
	_heartbeat_ms = Time.get_ticks_msec()
	if _freeze_started_ms != 0:
		_freeze_recovered()
	_since_poll += delta
	if _since_poll >= POLL_SECONDS:
		_since_poll = 0.0
		_poll_context()
	_since_refresh += delta
	if _since_refresh >= SENTINEL_REFRESH_SECONDS:
		_since_refresh = 0.0
		_write_sentinel()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			if OS.has_feature("mobile"):
				_suspended = true   # a backgrounded phone stops ticking without being frozen
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN:
			_heartbeat_ms = Time.get_ticks_msec()
			_suspended = false


## Breadcrumbs for what changed since the last poll: scene, room, role, level, region, being held.
func _poll_context() -> void:
	var tree := get_tree()
	var scene := tree.current_scene if tree != null else null
	_note("scene", scene.scene_file_path.get_file().get_basename() if scene != null else "")
	_note("room", ("%s %s" % [RoomState.code, "host" if RoomState.is_host else "guest"]) if RoomState.online else "offline")
	_note("level", str(GameState.depth))
	_note("grab", "held" if GameState.escape_active else "free")
	var facility = scene.get("facility") if scene != null and "facility" in scene else null
	if facility != null and facility.has_method("current_chunk_data"):
		_note("region", String((facility.current_chunk_data() as Dictionary).get("region", "")))


func _note(kind: String, value: String) -> void:
	if _seen.has(kind) and String(_seen[kind]) == value:
		return
	_seen[kind] = value
	crumb(kind, value)


# --- watchdog -----------------------------------------------------------------------------------------------------------
func _watch() -> void:
	while not _stop_watchdog:
		OS.delay_msec(500)
		check_stall(Time.get_ticks_msec())


## Watchdog thread: the main loop has not ticked for FREEZE_SECONDS -> one dump (the session may never come back).
func check_stall(now_ms: int) -> bool:
	if _suspended or _freeze_started_ms != 0 or not _running:
		return false
	var stalled := now_ms - _heartbeat_ms
	if stalled < int(FREEZE_SECONDS * 1000.0):
		return false
	_freeze_started_ms = _heartbeat_ms if _heartbeat_ms != 0 else -1   # nonzero: one dump per freeze
	crumb("freeze", "main loop stalled %.1f s" % (stalled / 1000.0))
	_write_json(log_dir.path_join(FREEZE_NAME), {"stalled_ms": stalled, "at_unix": int(Time.get_unix_time_from_system()),
		"breadcrumbs": breadcrumbs(), "recent_errors": _sink.recent_copy() if _sink != null else [], "counts": counts()})
	return true


## Main thread, first tick after a freeze: report it now (it did come back) and drop the dump.
func _freeze_recovered() -> void:
	var seconds := (Time.get_ticks_msec() - _freeze_started_ms) / 1000.0
	_freeze_started_ms = 0
	crumb("freeze", "recovered after %.1f s" % seconds)
	DirAccess.remove_absolute(log_dir.path_join(FREEZE_NAME))
	var report := build_report("freeze", {"breadcrumbs": breadcrumbs(), "recent_errors": _sink.recent_copy(),
		"counts": counts(), "scene": String(_seen.get("scene", "")), "room": String(_seen.get("room", "")),
		"started": _session_started, "ended": int(Time.get_unix_time_from_system())}, "")
	report["breadcrumbs"].append("freeze lasted %.1f s" % seconds)
	enqueue(report)
	if autostart:
		send_queue()


# --- session files ------------------------------------------------------------------------------------------------------
func _write_sentinel() -> void:
	_write_json(log_dir.path_join(SENTINEL_NAME), {"running": true, "started": _session_started,
		"refreshed": int(Time.get_unix_time_from_system()), "build": Build.revision(),
		"scene": String(_seen.get("scene", "")), "room": String(_seen.get("room", "")),
		"breadcrumbs": breadcrumbs(), "recent_errors": _sink.recent_copy() if _sink != null else [], "counts": counts()})


## The last session's crash or freeze as an lr.crash/1 report (and its files cleared), or {} after a clean quit.
func _previous_session_report() -> Dictionary:
	var sentinel := _read_json(log_dir.path_join(SENTINEL_NAME))
	var freeze := _read_json(log_dir.path_join(FREEZE_NAME))
	DirAccess.remove_absolute(log_dir.path_join(SENTINEL_NAME))
	DirAccess.remove_absolute(log_dir.path_join(FREEZE_NAME))
	if sentinel.is_empty():
		return {}
	var kind := "freeze" if not freeze.is_empty() else "crash"
	var session := sentinel.duplicate()
	if not freeze.is_empty():
		session["breadcrumbs"] = freeze.get("breadcrumbs", sentinel.get("breadcrumbs", []))
		session["recent_errors"] = freeze.get("recent_errors", sentinel.get("recent_errors", []))
		session["counts"] = freeze.get("counts", sentinel.get("counts", {}))
	session["ended"] = int(sentinel.get("refreshed", 0))
	return build_report(kind, session, previous_log_tail())


## lr.crash/1 (backend/crash_reports.mjs). `session`: the sentinel's fields; `log_tail`: the end of that session's log.
func build_report(kind: String, session: Dictionary, log_tail: String) -> Dictionary:
	var crumbs: Array = (session.get("breadcrumbs", []) as Array).slice(-BREADCRUMBS)
	var recent: Array = (session.get("recent_errors", []) as Array).slice(-RECENT_ERRORS)
	var room := String(session.get("room", ""))
	return {
		"schema": SCHEMA,
		"kind": kind,
		"build": String(session.get("build", Build.revision())),
		"version": Build.VERSION,
		"os": OS.get_name(),
		"os_version": OS.get_version(),
		"device": OS.get_model_name(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"locale": OS.get_locale(),
		"scene": String(session.get("scene", "")),
		"room_role": room.get_slice(" ", 1) if room.contains(" ") else room,
		"device_id": "",   # filled in when it is sent (Backend is not up yet when the previous session is read)
		"session_started": int(session.get("started", 0)),
		"session_ended": int(session.get("ended", 0)),
		"counts": session.get("counts", {}),
		"breadcrumbs": crumbs.map(func(line) -> String: return scrub(String(line)).left(LINE_CHARS)),
		"recent_errors": recent.map(func(line) -> String: return scrub(String(line)).left(LINE_CHARS)),
		"log_tail": scrub(log_tail.right(LOG_TAIL_BYTES)),
	}


## The last LOG_TAIL_BYTES of the previous session's Godot log (rotated to godot<stamp>.log when this one started).
func previous_log_tail() -> String:
	var newest := ""
	var newest_time := 0
	var dir := DirAccess.open(log_dir)
	if dir == null:
		return ""
	for name in dir.get_files():
		if not name.begins_with("godot") or not name.ends_with(".log") or name == "godot.log":
			continue
		var modified := FileAccess.get_modified_time(log_dir.path_join(name))
		if modified >= newest_time:
			newest_time = modified
			newest = name
	if newest.is_empty():
		return ""
	var file := FileAccess.open(log_dir.path_join(newest), FileAccess.READ)
	if file == null:
		return ""
	file.seek(maxi(0, file.get_length() - LOG_TAIL_BYTES))
	# a killed process can leave NUL padding (and the cut can split a UTF-8 sequence): NUL bytes dropped, plain ASCII.
	# Keep NUL out of this script's own constants too: one in a string literal made every import print parse errors.
	var bytes := file.get_buffer(mini(file.get_length(), LOG_TAIL_BYTES))
	var at := bytes.find(0)
	while at != -1:
		bytes.remove_at(at)
		at = bytes.find(0, at)
	return bytes.get_string_from_ascii()


## Client-side redaction before anything is queued (the server scrubs again).
static func scrub(text: String) -> String:
	var out := text
	for pattern in ["(?i)\\b(bearer|basic)\\s+[A-Za-z0-9._~+/=-]{8,}",
			"(?i)\\b(session(?:_?token)?|token|password|passwd|secret|api_?key|admin_?ticket|host_?token|authorization)\\b\\s*[\"']?\\s*[:=]\\s*[\"']?[^\\s\"',;&}]{4,}",
			"\\b[A-Fa-f0-9]{40,}\\b"]:
		var regex := RegEx.create_from_string(pattern)
		out = regex.sub(out, "[redacted]", true)
	return out


# --- queue and send -----------------------------------------------------------------------------------------------------
func enqueue(report: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(queue_dir)
	_enqueued += 1   # two reports in one millisecond must not share a name
	var name := "%d-%04d-%s.json" % [Time.get_unix_time_from_system() * 1000.0, _enqueued % 10000,
		String(report.get("kind", "crash"))]
	var path := queue_dir.path_join(name)
	_write_json(path, report)
	var files := queued()
	while files.size() > QUEUE_MAX:
		DirAccess.remove_absolute(queue_dir.path_join(files.pop_front()))
	crumb("report", "%s queued" % report.get("kind", ""))
	return path


## Queued report file names, oldest first.
func queued() -> Array[String]:
	var dir := DirAccess.open(queue_dir)
	var out: Array[String] = []
	if dir == null:
		return out
	for name in dir.get_files():
		if name.ends_with(".json"):
			out.append(name)
	out.sort()
	return out


## Reports go out only from a real game run with the setting on: never from the editor, headless validators,
## playtest bots or a test instance (those leave them queued for the harness to collect).
func sending_allowed() -> bool:
	return autostart and Settings.send_crash_reports and DisplayServer.get_name() != "headless" \
		and not OS.has_feature("editor") and not PlaytestBridge.requested() and not Backend.base_url.is_empty()


## Sends the queue, oldest first, one at a time; a report the server refuses as malformed is dropped, anything else
## that fails stays queued for the next launch.
func send_queue() -> void:
	if _sending or not sending_allowed():
		return
	var files := queued()
	if files.is_empty():
		return
	_sending = true
	var name: String = files[0]
	var report = JSON.parse_string(FileAccess.get_file_as_string(queue_dir.path_join(name)))
	if not report is Dictionary:
		DirAccess.remove_absolute(queue_dir.path_join(name))
		_sending = false
		send_queue()
		return
	if String(report.get("device_id", "")).is_empty() and Backend.moderation != null:
		report["device_id"] = Backend.moderation.device_id()   # the server's per-client rate limit key
	var body := JSON.stringify(report)
	var request := HTTPRequest.new()
	request.timeout = 15.0
	add_child(request)
	request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, _data: PackedByteArray) -> void:
		request.queue_free()
		_sending = false
		if result == HTTPRequest.RESULT_SUCCESS and (code == 201 or code == 400):
			DirAccess.remove_absolute(queue_dir.path_join(name))
			send_queue())
	if request.request(Backend.base_url.trim_suffix("/") + ENDPOINT, ["Content-Type: application/json"],
			HTTPClient.METHOD_POST, body) != OK:
		request.queue_free()
		_sending = false


# --- files --------------------------------------------------------------------------------------------------------------
func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(data))
	file.close()
	DirAccess.rename_absolute(path + ".tmp", path)


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
