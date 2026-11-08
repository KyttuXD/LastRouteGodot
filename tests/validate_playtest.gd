extends RefCounted

## Playtest system checks that need no scene change (the long bot scenarios are tools/build/playtest_check.sh): the bridge stays off
## unless asked for and never in release templates, the protocol answers, input injection round-trips through the real Input
## actions, the adapters are registered, thresholds fail the way they should, observation hashes are stable.

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	# 0. every playtest script must compile (a parse error in the scenarios file once made every run exit without playing)
	for path in ["res://dev/playtest/playtest_scenarios.gd", "res://dev/playtest/playtest_runner.gd", "res://dev/playtest/playtest_reporter.gd", "res://dev/playtest/playtest_flythrough.gd",
			"res://dev/playtest/bots/last_route_bot.gd", "res://dev/playtest/bots/night_watch_bot.gd"]:
		var script := load(path) as GDScript
		_expect(script != null and script.can_instantiate(), "%s must compile" % path)
	var scenario_methods: Array = []
	for method in (load("res://dev/playtest/playtest_scenarios.gd") as GDScript).get_script_method_list():
		scenario_methods.append(String(method["name"]))
	for wanted in ["play", "run_loop", "menu_tour", "death_tour", "coop_bot", "probe", "target_scenario_failure"]:
		_expect(scenario_methods.has(wanted), "PlaytestScenarios must define %s()" % wanted)

	# 0a. target scenarios fail on death / timeout short of the target — never PASS with unmet targets
	_expect(PlaytestScenarios.target_scenario_failure("explore_coverage", "died", 30, 5.0, {"chunks_visited": 8}) \
			== "explore_coverage: died before target 30 (got 8)",
		"explore_coverage death before target must fail")
	_expect(PlaytestScenarios.target_scenario_failure("collect_relays", "died", 10, 5.0, {"relays": 3}) \
			== "collect_relays: died before target 10 (got 3)",
		"collect_relays death before target must fail")
	_expect(PlaytestScenarios.target_scenario_failure("reach_depth", "died", 2, 5.0, {"max_depth": 0}) \
			== "reach_depth: died before target 2 (got 0)",
		"reach_depth death before target must fail")
	_expect(PlaytestScenarios.target_scenario_failure("explore_coverage", "time_limit", 30, 5.0, {"chunks_visited": 8}) \
			.begins_with("explore_coverage: target 30 not reached"),
		"explore_coverage timeout short of target must fail")
	_expect(PlaytestScenarios.target_scenario_failure("explore_coverage", "target_reached", 30, 5.0, {"chunks_visited": 30}) \
			.is_empty(),
		"explore_coverage on target must pass")
	_expect(PlaytestScenarios.target_scenario_failure("survive", "died", 30, 5.0, {}).is_empty(),
		"survive deaths must not use the target gate")

	# 0a. reserved private --room=AKIRI path: shell guests-only + coop_bot never hosts / never joins KATHY
	var multi_path := "res://tools/build/playtest_multi.sh"
	if FileAccess.file_exists(multi_path):
		var multi := FileAccess.get_file_as_string(multi_path)
		_expect(multi.contains("--room"), "playtest_multi.sh must accept --room=CODE for reserved private joins")
		_expect(multi.contains("KATHY"), "playtest_multi.sh must refuse KATHY")
		_expect(multi.contains("guests-only") or multi.contains("never host"), "playtest_multi.sh --room must be guests-only")
	var coop_src := FileAccess.get_file_as_string("res://dev/playtest/playtest_scenarios.gd")
	_expect(coop_src.contains("bots never host reserved room"), "coop_bot must refuse hosting a reserved private room")
	_expect(coop_src.contains("bots never join KATHY"), "coop_bot must refuse joining KATHY")
	_expect(coop_src.contains("reset_after_leaving"), "coop_bot must leave a reserved room cleanly when done")

	# 0b. the flythrough planner builds a camera track for every default area (or says the build has none), no scene needed
	var generator := StreamedRouteGenerator.new("FLYTHROUGH")
	for area in PlaytestFlythrough.DEFAULT_SET:
		# the renderer retries a boring tour with the next variant, so an area passes when ONE of the first six variants is clean (flythrough.py --variants)
		var problems: Array = []
		var unavailable := false
		for variant in 6:
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

	# 0c. bot chat (spoken by the room chat's TTS): lines fit the chat limit, the modes and their cooldowns hold
	for kind in BotChat.LINES:
		for line in BotChat.LINES[kind]:
			_expect(String(line).length() <= 80, "bot chat line over 80 characters: %s" % line)
			_expect(not String(line).to_lower().contains("kill yourself"), "bot chat line out of tone: %s" % line)
	_expect(BotChat.new("loud", 1).mode == "quiet", "an unknown bot chat mode must fall back to quiet")
	var quiet := BotChat.new("quiet", 7)
	var chatty := BotChat.new("on", 7)
	for _i in 20:
		_expect(quiet._cooldown() >= 90.0, "quiet bots must wait at least 90 s between lines")
		var c := chatty._cooldown()
		_expect(c >= 20.0 and c <= 48.0, "chatty bots wait 20-40 s plus up to 8 s of jitter (got %.1f)" % c)
	_expect(quiet._next_ok >= 8.0, "no bot speaks in its first seconds")
	# bots talk to each other: a filled line stays inside 80 characters; a callout makes the hearer avoid the spot, a claim
	# leaves the relay, a reply is never answered
	var obs := {"world": {"region": "research_lab_with_a_very_long_region_name"}, "player": {"pos": [0.0, 0.0, 0.0]}}
	for kind in ["hunter", "caught", "claim"]:
		for line in BotChat.LINES[kind]:
			quiet._target = Vector2(10, 0)
			_expect(not quiet._fill(String(line), obs).contains("{"), "a bot line kept a placeholder: %s" % line)
	quiet._target = Vector2(10, 0)
	_expect(quiet._fill("{dir}", obs) == "east", "+x should read east")
	quiet._target = Vector2(0, -10)
	_expect(quiet._fill("{dir}", obs) == "north", "-z should read north")
	var heard := {"avoid": null, "claim": null}
	var brain := PlaytestAdapters.create("last_route", host.get_tree()) as LastRouteBot
	quiet._adapter = brain
	quiet._on_message(9001, "BOT", {"preset": "bot_hunter", "target": Vector2(40, 40), "text": "Hunter near the lab!"})
	_expect(brain._avoided(Vector2(42, 40)) and not brain._avoided(Vector2(80, 40)), "a hunter callout did not make the bot avoid that spot")
	quiet._on_message(9001, "BOT", {"preset": "bot_relay", "target": Vector2(12.5, 7.5), "text": "I'll take the east relay."})
	_expect(float(brain._claimed.get("12,7", -1.0)) > brain._clock, "a relay claim was not left to its speaker")
	quiet._pending_reply = ""
	quiet._on_message(9001, "BOT", {"preset": "bot_reply", "text": "Got it, staying away."})
	_expect(quiet._pending_reply.is_empty(), "a bot answered a reply (chains)")
	# a revive callout spot lands on the brain even before a downed mark exists
	brain.help_at(Vector2(5, 8))
	_expect(not brain._help.is_empty() and (brain._help["at"] as Vector2).distance_to(Vector2(5, 8)) < .01, "help_at did not store the callout spot")
	_expect(float(brain._help.get("until", -1.0)) > brain._clock, "help_at expiry missing")
	# smooth looking: a command flickering between two path points comes out small; a turn eases in with no overshoot;
	# the meter counts dithering and a snap, and the reporter fails a jerky run
	var spring := LastRouteBot.LookSpring.new()
	var peak := 0.0
	for i in 120:
		peak = maxf(peak, absf(spring.step(.6 if (i / 2) % 2 == 0 else -.6, 1.0 / 60.0)))
	_expect(peak < .2, "a flickering look command still swings the camera (peak stick %.2f)" % peak)
	var turn := LastRouteBot.LookSpring.new()
	var top := 0.0
	var first := turn.step(.6, 1.0 / 60.0)
	for _i in 120:
		top = maxf(top, turn.step(.6, 1.0 / 60.0))
	_expect(first < .01 and top <= .6 + 1e-4 and top > .55, "a turn should ease in and settle without overshoot (first %.3f, top %.3f)" % [first, top])
	var smooth := LastRouteBot.LookMeter.new()
	var yaw := 0.0
	var rate := 0.0
	for _i in 60 * 30:
		rate = minf(rate + 3.0 / 60.0, 1.5)   # eases up to 1.5 rad/s
		yaw += rate / 60.0
		smooth.feed(wrapf(yaw, -PI, PI), 0.0, 1.0 / 60.0)
	var calm := smooth.result()
	_expect(int(calm["flips"]) == 0 and int(calm["yaw_acc_max"]) <= 300, "a smooth turn measured as jerky: %s" % [calm])
	var dither := LastRouteBot.LookMeter.new()
	for i in 60 * 30:
		dither.feed(.3 * sin(float(i) / 60.0 * TAU * 1.5), 0.0, 1.0 / 60.0)
	var jerky := dither.result()
	_expect(float(jerky["flips_per_min"]) > 12.0, "left-right dithering was not counted: %s" % [jerky])
	var verdict := PlaytestReporter.evaluate({"bot": {"look": jerky}}, PlaytestReporter.DEFAULT_LIMITS)
	_expect(verdict.any(func(f: String) -> bool: return f.begins_with("camera")), "the reporter passed a jerky camera: %s" % [verdict])
	verdict = PlaytestReporter.evaluate({"bot": {"look": calm}}, PlaytestReporter.DEFAULT_LIMITS)
	_expect(not verdict.any(func(f: String) -> bool: return f.begins_with("camera")), "the reporter failed a smooth camera: %s" % [verdict])
	brain.set_smartness(70)
	_expect(brain.smartness >= 70 - LastRouteBot.SMART_SPREAD and brain.smartness <= 70 + LastRouteBot.SMART_SPREAD, "smartness spread out of range")
	_ladder_avoidance(brain)

	# 1. off by default; no cost when off
	_expect(not Playtest.enabled, "the playtest bridge must be disabled without --playtest")
	_expect(not Playtest.is_physics_processing(), "a disabled bridge must not process every frame")
	_expect(not PlaytestBridge.requested(), "PlaytestBridge.requested() must be false without the flag")
	var denied: Dictionary = await Playtest.dispatch({"cmd": "observe"})
	_expect(not bool(denied.get("ok", true)), "a disabled bridge must refuse commands")
	var source := FileAccess.get_file_as_string("res://dev/playtest/playtest_bridge.gd")
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
	# a bot that stopped acting (hidden for good, hanging on a ladder) is neither stuck nor soft-locked: idle fails it
	var idle_report := {"bot": {"stuck_events": 0, "soft_locks": 0, "unreachable_goals": 0, "idle_max_s": 414.0}, "log": {"errors": 0}, "perf": {}}
	var idle_verdict := PlaytestReporter.evaluate(idle_report, limits)
	_expect(idle_verdict.size() == 1 and String(idle_verdict[0]).begins_with("idle"), "an idle bot must fail the run: %s" % [idle_verdict])
	idle_report["bot"]["idle_max_s"] = 30.0
	_expect(PlaytestReporter.evaluate(idle_report, limits).is_empty(), "a short pause must not fail the run")
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
		print("  playtest  bridge off by default and release-safe, protocol, input round trip, adapters, thresholds, hashes, ladder avoidance OK")
	return _failures


## Smart bots detour every ladder the path actually crosses, including one the midpoint's nearest-ladder lookup cannot see.
## The ladder a level goal means to climb stays on the path. Below LADDER_SMART the choice is still a roll, so a slip stays possible.
func _ladder_avoidance(brain: LastRouteBot) -> void:
	_expect(LastRouteBot.LADDER_SMART == 70 - LastRouteBot.SMART_SPREAD,
		"LADDER_SMART should stay the bottom of the default smartness band")
	brain.smartness = LastRouteBot.LADDER_SMART
	var certain := true
	for _i in 40:
		if not brain._should_route_around_ladders():
			certain = false
	_expect(certain, "smartness at LADDER_SMART must always route around ladders")
	brain.smartness = 100
	certain = true
	for _i in 20:
		if not brain._should_route_around_ladders():
			certain = false
	_expect(certain, "smartness 100 must always route around ladders")
	brain.smartness = 0
	var slipped := true
	for _i in 20:
		if brain._should_route_around_ladders():
			slipped = false
	_expect(slipped, "smartness 0 must keep the path and be able to walk onto a ladder")
	brain.smartness = LastRouteBot.LADDER_SMART - 1
	brain.rng.seed = 20261028
	var avoids := 0
	var slips := 0
	for _i in 160:
		if brain._should_route_around_ladders():
			avoids += 1
		else:
			slips += 1
	_expect(avoids > 0 and slips > 0, "a less-smart bot must sometimes detour and sometimes slip (avoided %d, slipped %d)" % [avoids, slips])

	# Hazard sits on the path near its start, a second hazard further along, and a decoy is the ladder nearest the middle
	# but metres off the path. A midpoint-only search returns the decoy and leaves both hazards in the route.
	var hazard := LevelLink.make("ladder", Vector3i(0, 0, 0), 0, Vector2i(8, 20), -1, Vector2i(8, 20))
	var later := LevelLink.make("ladder", Vector3i(0, 0, 0), 0, Vector2i(40, 20), -1, Vector2i(40, 20))
	var decoy := LevelLink.make("ladder", Vector3i(2, 0, 0), 0, Vector2i(1, 30), -1, Vector2i(1, 30))
	var world := _PlantedLadders.new()
	world.planted = [hazard, later, decoy]
	var nav := _ClearNav.new()
	var long_path: Array = []
	for x in range(2, 181):
		long_path.append(Vector2i(x, 20))
	var short_path: Array = []
	for x in range(2, 30):
		short_path.append(Vector2i(x, 20))
	var hazard_at := LadderTraffic.ladder_point(hazard, 0)
	var later_at := LadderTraffic.ladder_point(later, 0)
	var decoy_at := LadderTraffic.ladder_point(decoy, 0)
	var mid: Vector2 = brain._cell_centre(long_path[long_path.size() / 2])
	var nearest: Dictionary = LadderTraffic.nearest_ladder(world, 0, mid, ["ladder"])
	_expect(String(nearest.get("id", "")) == String(decoy["id"]),
		"fixture: the midpoint's nearest ladder should be the off-path decoy, not a hazard")
	_expect(_path_near_ladder(brain, long_path, hazard_at) and _path_near_ladder(brain, long_path, later_at),
		"fixture: the path must cross both hazards")
	_expect(not _path_near_ladder(brain, long_path, decoy_at), "fixture: the path must stay clear of the decoy")
	_expect(not _path_near_ladder(brain, short_path, later_at), "fixture: the short path must miss the later hazard")

	brain.stats.erase("ladder_detours")
	brain._goal = {"kind": "explore", "key": "explore:0,0"}
	var routed: Array = brain._around_ladders(nav, long_path, 0, world)
	_expect(not _path_near_ladder(brain, routed, hazard_at) and not _path_near_ladder(brain, routed, later_at),
		"a non-level goal must leave every ladder the path crosses")
	_expect(int(brain.stats.get("ladder_detours", 0)) > 0, "routing around a ladder must count a detour")

	var before := int(brain.stats.get("ladder_detours", 0))
	brain._goal = {"kind": "level", "key": "level:%s" % hazard["id"], "link": hazard}
	var kept: Array = brain._around_ladders(nav, short_path, 0, world)
	_expect(_path_near_ladder(brain, kept, hazard_at), "the ladder a level goal means to climb must stay on the path")
	_expect(int(brain.stats.get("ladder_detours", 0)) == before, "an intended ladder must not count as a detour")

	brain._goal = {"kind": "level", "key": "level:%s" % hazard["id"], "link": hazard}
	var others: Array = brain._around_ladders(nav, long_path, 0, world)
	_expect(not _path_near_ladder(brain, others, later_at),
		"walking to one ladder must still route around a different ladder on the way")

	var stairs := LevelLink.make("stairs", Vector3i(0, 0, 0), 1, Vector2i(12, 12), 0, Vector2i(12, 12))
	brain._goal = {"kind": "level", "key": "level:%s" % stairs["id"], "link": stairs}
	var around_stairs: Array = brain._around_ladders(nav, long_path, 0, world)
	_expect(not _path_near_ladder(brain, around_stairs, hazard_at) and not _path_near_ladder(brain, around_stairs, later_at),
		"a stair level change must still walk around ladders")
	brain._goal = {}


func _path_near_ladder(brain: LastRouteBot, path: Array, ladder: Vector2) -> bool:
	for cell in path:
		if brain._cell_centre(cell).distance_to(ladder) < LastRouteBot.LADDER_AVOID:
			return true
	return false


## Ladders planted for the avoidance check. vertical_links ignores the real sewer and returns only these.
class _PlantedLadders extends StreamedRouteGenerator:
	var planted: Array = []

	func vertical_links(coord: Vector3i, _cached_only: bool = false) -> Array:
		var out: Array = []
		for link in planted:
			var chunk: Vector3i = link["chunk"]
			if chunk.x == coord.x and chunk.z == coord.z and (coord.y == 0 or coord.y == SEWER_LEVEL):
				out.append(link)
		return out


## Open floor whose paths bow onto a rail far from the y=20 hazards, so a legal detour exists on the north side.
class _ClearNav extends StreamedHunterNavigation:
	const RAIL_Y := 80

	func _init() -> void:
		super(StreamedRouteGenerator.new("LADDER-AVOID"))

	func nearest_open_position(origin_x: float, origin_y: float, radius: float = 0.23, blocked_cells = null) -> Dictionary:
		var cell := Vector2i(floori(origin_x), floori(origin_y))
		return {"x": float(cell.x) + .5, "y": float(cell.y) + .5, "cell": cell}

	func find_path(from_cell: Vector2i, to_cell: Vector2i) -> Array:
		var out: Array = []
		_append_line(out, from_cell, Vector2i(from_cell.x, RAIL_Y))
		_append_line(out, Vector2i(from_cell.x, RAIL_Y), Vector2i(to_cell.x, RAIL_Y))
		_append_line(out, Vector2i(to_cell.x, RAIL_Y), to_cell)
		return out

	func _append_line(out: Array, a: Vector2i, b: Vector2i) -> void:
		var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
		var cursor := a
		if out.is_empty() or (out[-1] as Vector2i) != cursor:
			out.append(cursor)
		if step == Vector2i.ZERO:
			return
		while cursor != b:
			cursor += step
			out.append(cursor)
