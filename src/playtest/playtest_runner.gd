extends Node

## Playtest harness. Run on a TEST machine (never the dev Mac), headless and fast:
##   godot --headless --fixed-fps 60 --path . res://scenes/playtest_runner.tscn -- --playtest-runner --game=last_route \
##     --scenario=survive --seed=ALPHA --minutes=3 --out=.playtest/alpha
## or windowed for screenshots: drop --headless/--fixed-fps and add --screenshots.
## Options: --game --scenario --seed --difficulty --minutes (GAME minutes) --bot-seed --out --name --max-stuck --max-soft-locks
##   --max-errors --max-unreachable --min-fps --target (scenario target number) --screenshots --keep-alive
## Scenarios: survive, explore_coverage (--target=chunks), collect_relays (--target=n), reach_depth (--target=n), menu_tour,
##   death_scene_tour (--hunters=a,b). Exit code 0 = pass, 1 = failed thresholds, 2 = could not run (skipped / error).

const SCENARIOS := ["survive", "explore_coverage", "collect_relays", "reach_depth", "menu_tour", "death_scene_tour", "probe", "coop_bot", "goto_check", "door_audit"]

var _driver := false
var _opts := {}
var _started_msec := 0
var _watchdog: Thread
var _finished := false


func _ready() -> void:
	if not _driver:
		# The scene this script sits in is replaced by the first scene change: run from a node under the root instead.
		var driver := Node.new()
		driver.name = "PlaytestDriver"
		driver.set_script(get_script())
		driver.set("_driver", true)
		get_tree().root.add_child.call_deferred(driver)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_opts = parse_args(OS.get_cmdline_user_args())
	_started_msec = Time.get_ticks_msec()
	_start_watchdog()
	await get_tree().process_frame
	await _run()


## Hard WALL-CLOCK deadline for every scenario (default 3x the game minutes + 120 s, 300 s for the menu tour, 45 min for the death tour; --deadline=SECONDS
## overrides). Runs on its own thread, so it still fires when the main thread is stuck: it writes a failing report that says what the scenario was
## doing ("stuck at ...") and kills this process.
func _start_watchdog() -> void:
	var seconds := float(_opts["deadline"])
	if seconds <= 0.0:
		match String(_opts["scenario"]):
			"menu_tour":
				seconds = 300.0
			"death_scene_tour":
				seconds = 2700.0
			_:
				seconds = float(_opts["minutes"]) * 60.0 * 3.0 + 120.0
	_watchdog = Thread.new()
	_watchdog.start(_watch.bind(seconds))


func _watch(seconds: float) -> void:
	var limit_msec := int(seconds * 1000.0)
	while not _finished:
		OS.delay_msec(500)
		if Time.get_ticks_msec() - _started_msec > limit_msec:
			var where := String(Playtest.status) if Playtest != null else ""
			var report := {"game": _opts["game"], "scenario": _opts["scenario"], "seed": _opts["seed"], "pass": false,
				"failures": ["wall-clock deadline of %d s exceeded: stuck at %s" % [int(seconds), where if where != "" else "unknown state"]],
				"scenario_failure": "deadline", "revision": Build.revision()}
			PlaytestReporter.write(_out_dir(report), report)
			print("PLAYTEST FAIL: %s/%s seed=%s  WALL-CLOCK DEADLINE %d s exceeded, stuck at %s" % [_opts["game"], _opts["scenario"], _opts["seed"], int(seconds), where])
			OS.kill(OS.get_process_id())
			return


static func parse_args(args: PackedStringArray) -> Dictionary:
	var out := {"game": "last_route", "scenario": "survive", "seed": "PLAYTEST", "difficulty": "standard", "minutes": 2.0,
		"bot_seed": 1, "out": "", "name": "", "target": 0, "probe_x": 0.0, "probe_y": -9999.0, "probe_z": 0.0, "probe_interact": "", "hunters": "", "hash_frames": 0, "role": "", "dir": "", "guests": 1, "port": 18511, "passive": false, "goal_x": 0, "goal_z": 0, "goal_kind": "relay", "deadline": 0.0, "screenshots": false, "keep_alive": false}
	out.merge(PlaytestReporter.DEFAULT_LIMITS, true)
	for arg in args:
		var text := String(arg)
		if not text.begins_with("--") or text == "--playtest-runner":
			continue
		var body := text.trim_prefix("--")
		var key := body.get_slice("=", 0).replace("-", "_")
		var value: Variant = body.get_slice("=", 1) if body.contains("=") else "true"
		if out.has(key):
			var current: Variant = out[key]
			if current is bool:
				value = String(value) != "false"
			elif current is int:
				value = int(value)
			elif current is float:
				value = float(value)
		out[key] = value
	return out


func _run() -> void:
	var bridge: PlaytestBridge = Playtest
	if not bridge.enabled:
		print("PLAYTEST runner: the bridge is not enabled (debug build with --playtest-runner required)")
		get_tree().quit(2)
		return
	var game := String(_opts["game"])
	var scenario := String(_opts["scenario"])
	var adapter := bridge.use_game(game)
	if adapter == null or not adapter.available():
		_finish(_blank_report(game, scenario, "skipped: no playtest bot for '%s'" % game), 2)
		return
	if not SCENARIOS.has(scenario):
		_finish(_blank_report(game, scenario, "unknown scenario '%s'" % scenario), 2)
		return
	var report := _blank_report(game, scenario, "")
	var log_start := bridge.log_sink.sequence()
	var result: Dictionary = {}
	match scenario:
		"menu_tour":
			result = await PlaytestScenarios.menu_tour(bridge, adapter, _opts, report)
		"probe":
			result = await PlaytestScenarios.probe(bridge, adapter, _opts, report)
		"coop_bot":
			result = await PlaytestScenarios.coop_bot(bridge, adapter, _opts, report)
		"goto_check":
			result = await PlaytestScenarios.goto_check(bridge, adapter, _opts, report)
		"door_audit":
			result = await PlaytestScenarios.door_audit(bridge, adapter, _opts, report)
		"death_scene_tour":
			result = await PlaytestScenarios.death_tour(bridge, adapter, _opts, report)
		_:
			result = await PlaytestScenarios.play(bridge, adapter, _opts, report)
	report["log"] = {"errors": bridge.log_sink.errors, "warnings": bridge.log_sink.warnings}
	report["log_lines"] = bridge.log_sink.since(log_start)
	report["events"] = adapter.events.duplicate()
	report["bot"] = adapter.stats.duplicate(true)
	report["wall_seconds"] = snappedf(float(Time.get_ticks_msec() - _started_msec) / 1000.0, .1)
	report.merge(result, true)
	var failures := PlaytestReporter.evaluate(report, _opts)
	report["failures"] = failures
	report["pass"] = failures.is_empty() and String(report.get("scenario_failure", "")) == ""
	_finish(report, 0 if bool(report["pass"]) else 1)


func _blank_report(game: String, scenario: String, error: String) -> Dictionary:
	return {"game": game, "scenario": scenario, "seed": _opts["seed"], "difficulty": _opts["difficulty"],
		"machine": "%s/%s" % [OS.get_name(), OS.get_model_name()], "protocol": PlaytestBridge.PROTOCOL,
		"revision": Build.revision(), "args": Array(OS.get_cmdline_user_args()), "scenario_failure": error, "pass": error.is_empty(), "failures": []}


func _out_dir(report: Dictionary) -> String:
	var name := String(_opts["name"])
	if name.is_empty():
		name = "%s_%s_%s" % [report.get("game", "game"), report.get("scenario", "run"), String(_opts["seed"]).validate_filename()]
	var out_dir := String(_opts["out"])
	if out_dir.is_empty():
		out_dir = ".playtest/%s" % name
	if not out_dir.is_absolute_path():
		out_dir = ProjectSettings.globalize_path("res://").path_join(out_dir)
	return out_dir


func _finish(report: Dictionary, code: int) -> void:
	_finished = true
	if _watchdog != null and _watchdog.is_started():
		_watchdog.wait_to_finish()
	var path := PlaytestReporter.write(_out_dir(report), report)
	print("PLAYTEST %s: %s/%s seed=%s game_s=%.1f frames=%d  stuck=%d soft_locks=%d unreachable=%d errors=%d deaths=%d relays=%d depth=%d chunks=%d" % [
		"PASS" if code == 0 else ("FAIL" if code == 1 else "SKIP"), report.get("game"), report.get("scenario"), report.get("seed"),
		float(report.get("game_seconds", 0.0)), int(report.get("frames", 0)),
		int(report.get("bot", {}).get("stuck_events", 0)), int(report.get("bot", {}).get("soft_locks", 0)),
		int(report.get("bot", {}).get("unreachable_goals", 0)), int(report.get("log", {}).get("errors", 0)),
		int(report.get("bot", {}).get("deaths", 0)), int(report.get("bot", {}).get("relays", 0)),
		int(report.get("bot", {}).get("max_depth", 0)), int(report.get("bot", {}).get("chunks_visited", 0))])
	for failure in report.get("failures", []):
		print("PLAYTEST   failure: %s" % failure)
	if not String(report.get("scenario_failure", "")).is_empty():
		print("PLAYTEST   note: %s" % report["scenario_failure"])
	print("PLAYTEST report: %s" % path)
	Playtest.input.release_all()
	if not bool(_opts["keep_alive"]):
		get_tree().quit(code)
