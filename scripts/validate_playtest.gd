extends RefCounted

## Playtest system checks that need no scene change (the long bot scenarios are scripts/playtest_check.sh): the bridge stays off
## unless asked for and never in release templates, the protocol answers, input injection round-trips through the real Input
## actions, the adapters are registered, thresholds fail the way they should, observation hashes are stable.

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	# 0. every playtest script must compile (a parse error in the scenarios file once made every run exit without playing)
	for path in ["res://src/playtest/playtest_scenarios.gd", "res://src/playtest/playtest_runner.gd", "res://src/playtest/playtest_reporter.gd", "res://src/playtest/playtest_flythrough.gd",
			"res://src/playtest/bots/last_route_bot.gd", "res://src/playtest/bots/night_watch_bot.gd"]:
		var script := load(path) as GDScript
		_expect(script != null and script.can_instantiate(), "%s must compile" % path)
	var scenario_methods: Array = []
	for method in (load("res://src/playtest/playtest_scenarios.gd") as GDScript).get_script_method_list():
		scenario_methods.append(String(method["name"]))
	for wanted in ["play", "run_loop", "menu_tour", "death_tour", "coop_bot", "probe"]:
		_expect(scenario_methods.has(wanted), "PlaytestScenarios must define %s()" % wanted)

	# 0b. the flythrough planner builds a camera track for every default area (or says the build has none), no scene needed
	var generator := StreamedRouteGenerator.new("FLYTHROUGH")
	for area in PlaytestFlythrough.DEFAULT_SET:
		# the renderer retries a boring tour with the next variant, so an area passes when ONE of the first three variants is clean
		var problems: Array = []
		var unavailable := false
		for variant in 3:
			var planned: Dictionary = PlaytestFlythrough.plan(generator, String(area), 30, 0.0, variant)
			if bool(planned.get("unavailable", false)):
				print("  note  flythrough area %s unavailable on this build: %s" % [area, planned.get("error", "")])
				unavailable = true
				break
			problems = []
			if not bool(planned.get("ok", false)):
				problems.append("plan failed (%s)" % planned.get("error", ""))
			else:
				var track: PlaytestFlythrough.Track = planned["track"]
				var info: Dictionary = planned["info"]
				if track.size() < 30 * 16 or track.size() > 30 * 60:
					problems.append("lasts %.1f s (want 16-60)" % (float(track.size()) / 30.0))
				var biggest_jump := 0.0
				for i in range(2, track.size()):
					if track.cuts.has(i) or track.cuts.has(i - 1) or track.ground[i] != track.ground[i - 1] or track.ground[i - 1] != track.ground[i - 2]:
						continue    # a planned hard cut to another shot
					biggest_jump = maxf(biggest_jump, absf(track.pos[i].distance_to(track.pos[i - 1]) - track.pos[i - 1].distance_to(track.pos[i - 2])))
				if biggest_jump >= .12:
					problems.append("camera speed jumps by %.2f m/frame" % biggest_jump)
				var motion: Dictionary = info["motion"]
				if float(motion["max_yaw_step"]) >= .06:
					problems.append("turns %.3f rad in one frame (a snap)" % float(motion["max_yaw_step"]))
				if float(motion["max_wobble"]) >= 1.4:
					problems.append("zig-zags (%.2f rad of back-and-forth)" % float(motion["max_wobble"]))
				if info.has("planned_tight_s") and float(info["planned_tight_s"]) >= 1.0:
					problems.append("faces a wall closer than 1.5 m while moving for %.1f s" % float(info["planned_tight_s"]))
			if problems.is_empty():
				break
		if not unavailable:
			_expect(problems.is_empty(), "flythrough %s has no clean variant: %s" % [area, "; ".join(problems)])

	# 1. off by default; no cost when off
	_expect(not Playtest.enabled, "the playtest bridge must be disabled without --playtest")
	_expect(not Playtest.is_physics_processing(), "a disabled bridge must not process every frame")
	_expect(not PlaytestBridge.requested(), "PlaytestBridge.requested() must be false without the flag")
	var denied: Dictionary = await Playtest.dispatch({"cmd": "observe"})
	_expect(not bool(denied.get("ok", true)), "a disabled bridge must refuse commands")
	var source := FileAccess.get_file_as_string("res://src/playtest/playtest_bridge.gd")
	_expect(source.contains("OS.is_debug_build()") and source.contains("template_release"), "requested() must exclude release builds")
	_expect(not Playtest.is_in_group("never"), "sanity")

	# 2. an enabled bridge instance answers the protocol
	var bridge := PlaytestBridge.new()
	host.add_child(bridge)
	bridge.enabled = true
	var hello: Dictionary = await bridge.dispatch({"cmd": "hello"})
	_expect(bool(hello.get("ok", false)) and int(hello.get("protocol", 0)) == PlaytestBridge.PROTOCOL, "hello must answer with the protocol version")
	_expect((hello.get("games", []) as Array).has("last_route"), "hello must list last_route")
	var unknown: Dictionary = await bridge.dispatch({"cmd": "nope"})
	_expect(not bool(unknown.get("ok", true)), "an unknown command must fail")
	var observed: Dictionary = await bridge.dispatch({"cmd": "observe"})
	_expect(bool(observed.get("ok", false)) and (observed["obs"] as Dictionary).has("frame") and (observed["obs"] as Dictionary).has("ui"), "observe must return the base observation")
	var logged: Dictionary = await bridge.dispatch({"cmd": "log", "since": 0})
	_expect(bool(logged.get("ok", false)) and logged.has("seq"), "log must answer")
	var stepped: Dictionary = await bridge.dispatch({"cmd": "step", "frames": 2, "observe": false})
	_expect(bool(stepped.get("ok", false)), "step must advance and answer")
	var refused: Dictionary = await bridge.dispatch({"cmd": "start_run", "game": "city"})
	_expect(not bool(refused.get("ok", true)), "starting a game without an available bot must fail cleanly")

	# 3. input injection goes through the real Input actions
	var input := PlaytestInput.new()
	input.apply({"move": [0.0, 1.0], "look": [0.5, 0.0], "hold": {"sprint": true}})
	_expect(Input.get_action_strength("move_up") > .99, "move forward must press move_up")
	_expect(absf(Input.get_action_strength("look_right") - .5) < .01, "look 0.5 must press look_right at half strength")
	_expect(Input.is_action_pressed("sprint"), "hold sprint must press sprint")
	input.apply({"pulse": ["interact"]})
	_expect(Input.is_action_pressed("interact"), "a pulse must press the action")
	input.begin_frame()
	_expect(not Input.is_action_pressed("interact"), "a pulse must release on the next frame")
	input.release_all()
	_expect(Input.get_action_strength("move_up") == 0.0 and not Input.is_action_pressed("sprint"), "release_all must release everything")
	_expect(is_equal_approx(PlaytestInput.look_strength(1.0, 2.8, 1.0 / 60.0), 1.0) and is_equal_approx(PlaytestInput.look_strength(.001, 2.8, 1.0 / 60.0), .001 / (2.8 / 60.0)), "look_strength must clamp and scale")

	# 4. adapters and the registry hook
	_expect(not GameRegistry.get_game("last_route").get("playtest_bot", "").is_empty(), "last_route must register a playtest bot in GameRegistry")
	var lr := PlaytestAdapters.create("last_route", host.get_tree())
	_expect(lr != null and lr.available(), "the Last Route bot must exist and be available")
	for stub in ["city", "night_watch"]:
		var adapter := PlaytestAdapters.create(stub, host.get_tree())
		_expect(adapter != null or PlaytestAdapters.script_path(stub).is_empty(), "%s adapter lookup must not crash" % stub)
		if adapter != null and not adapter.available():
			var reply: Dictionary = await adapter.start_run({})
			_expect(not bool(reply.get("ok", true)), "%s stub must refuse to start" % stub)

	# 5. reporter thresholds
	var limits := PlaytestReporter.DEFAULT_LIMITS
	var clean := {"bot": {"stuck_events": 0, "soft_locks": 0, "unreachable_goals": 0}, "log": {"errors": 0}, "perf": {}}
	_expect(PlaytestReporter.evaluate(clean, limits).is_empty(), "a clean report must pass")
	var bad := {"bot": {"stuck_events": 9, "soft_locks": 1, "unreachable_goals": 20}, "log": {"errors": 2}, "perf": {}}
	_expect(PlaytestReporter.evaluate(bad, limits).size() == 4, "a report over every limit must fail 4 ways")
	_expect(PlaytestReporter.markdown({"game": "g", "scenario": "s", "bot": {}, "pass": true}).begins_with("# Playtest"), "report markdown must render")

	# 6. observation hash is stable and rounds to 1 cm
	var a := {"frame": 5, "player": {"pos": [1.2345, 0.0, 2.0]}}
	var b := {"frame": 5, "player": {"pos": [1.2349, 0.0, 2.0]}}
	var c := {"frame": 5, "player": {"pos": [1.30, 0.0, 2.0]}}
	_expect(PlaytestObserver.state_hash(a) == PlaytestObserver.state_hash(b), "positions within 1 cm must hash the same")
	_expect(PlaytestObserver.state_hash(a) != PlaytestObserver.state_hash(c), "a moved player must hash differently")

	# 7. the playtest bridge adds nothing to normal key bindings or the release feature
	_expect(not OS.has_feature("playtest_in_release"), "no release feature flag may enable the playtest bridge")

	bridge.queue_free()
	if _failures == 0:
		print("  playtest  bridge off by default and release-safe, protocol, input round trip, adapters, thresholds, hashes OK")
	return _failures
