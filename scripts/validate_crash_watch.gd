extends RefCounted

## CrashWatch (crash / freeze detection and reports): a clean quit leaves nothing, a crashed or frozen session is
## reported on the next launch, the freeze watchdog fires and recovers, errors are counted and rate limited, every
## buffer is bounded, nothing credential-shaped leaves the client, and only a real game run sends.
##
##   godot4 --headless res://scenes/validate.tscn -- crash_watch

const ROOT := "user://crashwatch_validate"
const REPORT_KEYS := ["schema", "kind", "build", "version", "os", "os_version", "device", "gpu", "renderer", "locale",
	"scene", "room_role", "device_id", "session_started", "session_ended", "counts", "breadcrumbs", "recent_errors",
	"log_tail"]

var _failures := 0
var _host: Node


func _fail(message: String) -> void:
	print("  FAIL  %s" % message)
	_failures += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func run(host: Node) -> int:
	_host = host
	_expect(CrashWatch.is_running(), "the CrashWatch autoload is not running in a validator boot")
	_wipe(ROOT)
	_clean_session()
	_crashed_session()
	_frozen_session()
	_live_freeze()
	_errors_and_limits()
	_wipe(ROOT)
	return _failures


func _watch() -> Node:
	var watch: Node = load("res://src/autoload/crash_watch.gd").new()
	watch.autostart = false
	watch.watchdog_thread = false   # the checks call check_stall() themselves
	watch.log_dir = ROOT.path_join("logs")
	watch.queue_dir = ROOT.path_join("queue")
	_host.add_child(watch)
	return watch


func _done(watch: Node, clean: bool) -> void:
	if clean:
		watch.stop()
	else:   # what a crash leaves: the process is gone, its files stay
		watch._stop_watchdog = true
		OS.remove_logger(watch._sink)
		watch._sink.close()
	watch.queue_free()


func _sentinel() -> String:
	return ROOT.path_join("logs").path_join("crashwatch_session.json")


func _clean_session() -> void:
	var first := _watch()
	first.start()
	_expect(FileAccess.file_exists(_sentinel()), "no session sentinel while running")
	_done(first, true)
	_expect(not FileAccess.file_exists(_sentinel()), "a clean quit left the sentinel behind")
	var second := _watch()
	second.start()
	_expect(second.previous_report.is_empty(), "a clean previous session was reported as %s" % second.previous_report.get("kind"))
	_expect(second.queued().is_empty(), "a clean previous session queued a report")
	_done(second, true)


func _crashed_session() -> void:
	var first := _watch()
	first.start()
	first.crumb("interact", "stream_door probe")
	first._write_sentinel()
	_done(first, false)
	_expect(FileAccess.file_exists(_sentinel()), "a crashed session did not leave its sentinel")
	# the crashed session's Godot log, rotated by the next launch; it carries a secret that must not leave
	var log := FileAccess.open(ROOT.path_join("logs").path_join("godot2026-10-28T20.00.00.log"), FileAccess.WRITE)
	log.store_string("x".repeat(40_000) + "\nlast line before the crash sessionToken=abcdef123456 hunter_id=opalie\n")
	log.close()
	var second := _watch()
	second.start()
	var report: Dictionary = second.previous_report
	_expect(String(report.get("kind", "")) == "crash", "a crashed session was reported as %s" % report.get("kind"))
	for key in REPORT_KEYS:
		_expect(report.has(key), "the crash report has no %s" % key)
	for key in report:
		_expect(key in REPORT_KEYS, "the crash report carries an unknown field %s" % key)
	_expect(String(report.get("schema", "")) == "lr.crash/1", "report schema %s" % report.get("schema"))
	var tail := String(report.get("log_tail", ""))
	_expect(tail.contains("last line before the crash"), "the report has no tail of the crashed session's log")
	_expect(tail.length() <= 32 * 1024, "the log tail is %d chars" % tail.length())
	_expect(not tail.contains("abcdef123456"), "a session token left the client in the log tail")
	_expect((report.get("breadcrumbs", []) as Array).any(func(line) -> bool: return String(line).contains("stream_door probe")),
		"the crashed session's breadcrumbs were lost")
	_expect(second.queued().size() == 1, "the crash report was not queued (%d)" % second.queued().size())
	_expect(not FileAccess.file_exists(_sentinel().replace("session", "freeze")), "a freeze dump appeared for a crash")
	_done(second, true)
	_wipe(ROOT.path_join("queue"))


func _frozen_session() -> void:
	var first := _watch()
	first.start()
	first._heartbeat_ms = Time.get_ticks_msec() - 11_000
	_expect(first.check_stall(Time.get_ticks_msec()), "a main loop stalled 11 s was not flagged")
	_done(first, false)   # it never came back: killed while frozen
	var second := _watch()
	second.start()
	_expect(String(second.previous_report.get("kind", "")) == "freeze",
		"a session killed while frozen was reported as %s" % second.previous_report.get("kind"))
	_done(second, true)
	_wipe(ROOT.path_join("queue"))


func _live_freeze() -> void:
	var watch := _watch()
	watch.start()
	var now := Time.get_ticks_msec()
	watch._heartbeat_ms = now - 9_000
	_expect(not watch.check_stall(now), "a 9 s stall was flagged (threshold 10 s)")
	watch._heartbeat_ms = now - 12_000
	_expect(watch.check_stall(now), "a 12 s stall was not flagged")
	_expect(not watch.check_stall(now + 500), "one freeze wrote more than one dump")
	watch._process(0.016)   # the main loop is back
	var freezes: Array = watch.queued().filter(func(name) -> bool: return String(name).ends_with("-freeze.json"))
	_expect(freezes.size() == 1, "a recovered freeze queued %d reports" % freezes.size())
	_expect(not FileAccess.file_exists(ROOT.path_join("logs").path_join("crashwatch_freeze.json")),
		"the freeze dump stayed after the freeze recovered")
	watch._suspended = true
	watch._heartbeat_ms = Time.get_ticks_msec() - 60_000
	_expect(not watch.check_stall(Time.get_ticks_msec()), "a backgrounded (suspended) app counted as frozen")
	watch._suspended = false
	watch._heartbeat_ms = Time.get_ticks_msec()
	_done(watch, true)
	_wipe(ROOT.path_join("queue"))


func _errors_and_limits() -> void:
	var watch := _watch()
	watch.start()
	var before: Dictionary = watch.counts()
	push_error("crashwatch validator probe (expected)")
	_expect(int(watch.counts().get("errors", 0)) == int(before.get("errors", 0)) + 1, "push_error was not counted")
	for i in 100:
		watch._sink.record("E", "flood %d" % i)
	var counts: Dictionary = watch.counts()
	var recent: Array = watch._sink.recent_copy()
	_expect(int(counts.get("errors", 0)) >= 101, "flooded errors were not all counted (%d)" % counts.get("errors"))
	_expect(int(counts.get("dropped", 0)) >= 60, "a flood of errors was not rate limited (dropped %d)" % counts.get("dropped"))
	_expect(recent.size() <= 50, "the recent error ring holds %d" % recent.size())
	for i in 80:
		watch.crumb("probe", str(i))
	_expect(watch.breadcrumbs().size() == 50, "the breadcrumb ring holds %d (cap 50)" % watch.breadcrumbs().size())
	for i in 15:
		watch.enqueue({"schema": "lr.crash/1", "kind": "crash", "n": i})
	_expect(watch.queued().size() == 10, "the offline queue holds %d (cap 10)" % watch.queued().size())
	_expect(not watch.sending_allowed(), "a test instance (and a headless run) would send reports")
	_expect(not CrashWatch.sending_allowed(), "the headless validator boot would send reports")
	var scrubbed: String = CrashWatch.scrub("Bearer abcdefghijkl password=hunter22 admin_ticket: tkt99999 " + "a1".repeat(30))
	for secret in ["abcdefghijkl", "hunter22", "tkt99999", "a1a1a1a1a1a1"]:
		_expect(not scrubbed.contains(secret), "%s survived the client scrub: %s" % [secret, scrubbed])
	# rotation keeps EVENTS_FILES files
	var events := ROOT.path_join("rotate.log")
	for i in 7:
		var file := FileAccess.open(events, FileAccess.WRITE)
		file.store_string(str(i))
		file.close()
		load("res://src/autoload/crash_watch.gd").CrashSink.rotate(events, 5)
	var kept: Array = Array(DirAccess.get_files_at(ROOT)).filter(func(name) -> bool: return String(name).begins_with("rotate.log"))
	_expect(kept.size() == 4, "rotation kept %d files (cap: 4 rotated)" % kept.size())
	_done(watch, true)


func _wipe(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_wipe(path.path_join(sub))
	for file in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
