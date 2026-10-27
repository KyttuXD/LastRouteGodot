extends Node

## Playtest harness. Run on a TEST machine (never the dev Mac), headless and fast:
##   godot --headless --fixed-fps 60 --path . res://scenes/playtest_runner.tscn -- --playtest-runner --game=last_route \
##     --scenario=survive --seed=ALPHA --minutes=3 --out=.playtest/alpha
## or windowed for screenshots: drop --headless/--fixed-fps and add --screenshots.
## Options: --game --scenario --seed --difficulty --minutes (GAME minutes) --bot-seed --out --name --max-stuck --max-soft-locks
##   --max-errors --max-unreachable --min-fps --target (scenario target number) --screenshots --keep-alive
## Scenarios: survive, explore_coverage (--target=chunks), collect_relays (--target=n), reach_depth (--target=n), menu_tour,
##   death_scene_tour. Exit code 0 = pass, 1 = failed thresholds, 2 = could not run (skipped / error).

const SCENARIOS := ["survive", "explore_coverage", "collect_relays", "reach_depth", "menu_tour", "death_scene_tour"]

var _driver := false
var _opts := {}
var _started_msec := 0


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
	await get_tree().process_frame
	await _run()


static func parse_args(args: PackedStringArray) -> Dictionary:
	var out := {"game": "last_route", "scenario": "survive", "seed": "PLAYTEST", "difficulty": "standard", "minutes": 2.0,
		"bot_seed": 1, "out": "", "name": "", "target": 0, "screenshots": false, "keep_alive": false}
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
		"revision": Build.revision(), "scenario_failure": error, "pass": error.is_empty(), "failures": []}


func _finish(report: Dictionary, code: int) -> void:
	var name := String(_opts["name"])
	if name.is_empty():
		name = "%s_%s_%s" % [report.get("game", "game"), report.get("scenario", "run"), String(_opts["seed"]).validate_filename()]
	var out_dir := String(_opts["out"])
	if out_dir.is_empty():
		out_dir = ".playtest/%s" % name
	if not out_dir.is_absolute_path():
		out_dir = ProjectSettings.globalize_path("res://").path_join(out_dir)
	var path := PlaytestReporter.write(out_dir, report)
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
