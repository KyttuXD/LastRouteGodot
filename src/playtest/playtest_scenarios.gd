class_name PlaytestScenarios
extends RefCounted

## Scenario loops. Each runs the bot frame by frame (observe -> decide -> inject) until its goal, a time limit, or the end of the run.

const SAMPLE_EVERY := 30


static func play(bridge: PlaytestBridge, adapter: BotAdapter, opts: Dictionary, report: Dictionary) -> Dictionary:
	var start := await bridge.start_run({"game": adapter.game_id, "seed": opts["seed"], "difficulty": opts["difficulty"],
		"bot_seed": opts["bot_seed"], "debug": true})
	if not bool(start.get("ok", false)):
		return {"scenario_failure": "start_run failed: %s" % start.get("error", "?"), "outcome": "error", "game_seconds": 0.0, "frames": 0}
	return await run_loop(bridge, adapter, opts, report)


## The frame loop shared by every playing scenario: observe -> decide -> inject, with death handling, perf sampling and targets.
static func run_loop(bridge: PlaytestBridge, adapter: BotAdapter, opts: Dictionary, report: Dictionary) -> Dictionary:
	var tree := bridge.get_tree()
	var scenario := String(opts["scenario"])
	var delta := 1.0 / float(Engine.physics_ticks_per_second)
	var limit_frames := int(float(opts["minutes"]) * 60.0 * float(Engine.physics_ticks_per_second))
	var target := int(opts["target"])
	var frames := 0
	var fps: Array = []
	var frame_ms: Array = []
	var deaths: Array = []
	var outcome := "time_limit"
	var failure := ""
	var last_over := false
	var shots := 0
	var peers_seen: Array = []
	var remotes_seen: Array = []
	var passive := bool(opts.get("passive", false))
	var observe_every := maxi(int(opts.get("observe_every", 0)), 1)
	var obs := {}
	while frames < limit_frames:
		await tree.physics_frame
		frames += 1
		if obs.is_empty() or frames % observe_every == 0:
			obs = bridge.observe()
		if frames % 120 == 0:
			bridge.status = "%s frame %d/%d, chunk %s, goal %s, scene %s" % [scenario, frames, limit_frames, obs.get("world", {}).get("chunk", "?"),
				(adapter.get("_goal") if adapter.get("_goal") != null else "?"), obs.get("scene", "")]
		if frames % SAMPLE_EVERY == 0 and float(obs.get("fps", 0.0)) > 0.0:
			fps.append(float(obs["fps"]))
			frame_ms.append(float(obs["frame_ms"]))
		if int(opts.get("hash_frames", 0)) > 0 and frames == int(opts["hash_frames"]):
			report["state_hash"] = PlaytestObserver.state_hash(obs)
		var over := adapter.run_over(obs)
		if over and not last_over:
			var death: Dictionary = obs.get("run", {}).get("death", {})
			deaths.append({"t": snappedf(frames * delta, .1), "hunter": String(death.get("hunter_id", "?")),
				"cause": "%s%s" % [death.get("via", ""), (" / " + String(death["detail"])) if not String(death.get("detail", "")).is_empty() else ""],
				"depth": int(obs["run"].get("depth", 1))})
			adapter.stats["deaths"] = int(adapter.stats["deaths"]) + 1
			adapter.add_event("death", deaths[-1])
			if scenario == "survive" or scenario == "death_scene_tour":
				# a few seconds on the death scene, then restart like a player would
				for _i in 180:
					await tree.physics_frame
					frames += 1
				bridge.input.release_all()
				adapter.after_run_over(obs)
				for _i in 60:
					await tree.physics_frame
					frames += 1
				last_over = false
				obs = {}   # the cached one still says the run is over
				continue
			if scenario == "coop_bot":
				# online: the host restarts the run for everyone and a caught runner spectates; the bot just waits (no restart/leave press)
				last_over = true
				continue
			outcome = "died"
			break
		last_over = over
		if obs.has("online") and frames % 60 == 0 and bool(obs["online"].get("active", false)):
			peers_seen.append(int(obs["online"]["peers"]))
			remotes_seen.append(int(obs["online"]["remotes"]))
		var act := adapter.decide(obs, delta) if not passive else {}
		bridge.input.apply(act)
		if bool(opts["screenshots"]) and frames % (60 * 20) == 0 and shots < 12:
			shots += 1
			bridge.screenshot(ProjectSettings.globalize_path("res://.playtest/shots/%s_%d.png" % [opts["seed"], shots]))
		match scenario:
			"explore_coverage":
				if target > 0 and int(adapter.stats["chunks_visited"]) >= target:
					outcome = "target_reached"
					break
			"collect_relays":
				if target > 0 and int(adapter.stats["relays"]) >= target:
					outcome = "target_reached"
					break
			"reach_depth":
				if target > 0 and int(adapter.stats["max_depth"]) >= target:
					outcome = "target_reached"
					break
	bridge.input.release_all()
	if outcome == "time_limit" and scenario in ["explore_coverage", "collect_relays", "reach_depth"] and target > 0:
		failure = "%s: target %d not reached in %.1f game minutes" % [scenario, target, float(opts["minutes"])]
	var online_summary: Dictionary = {}
	if peers_seen.size() > 0:
		online_summary = {"peers_min": peers_seen.min(), "peers_max": peers_seen.max(), "remotes_min": remotes_seen.min(), "remotes_max": remotes_seen.max()}
		report["online"] = online_summary
	var summary: Dictionary = {"outcome": outcome, "game_seconds": snappedf(frames * delta, .1), "frames": frames,
		"perf": PlaytestReporter.perf_summary(fps, frame_ms), "deaths": deaths, "scenario_failure": failure}
	return summary


## coop_bot: one client of a bot party. role=host creates the room against --backend and waits for --guests guests, role=guest reads the
## room code from --dir/code.txt and joins. Then everyone plays the route with the bot (or stands still with --passive) for --minutes.
## Driven by scripts/playtest_multi.sh on a test machine against a LOCAL backend (or the TEST instance; production needs the explicit flag).
static func coop_bot(bridge: PlaytestBridge, adapter: BotAdapter, opts: Dictionary, report: Dictionary) -> Dictionary:
	var tree := bridge.get_tree()
	var role := String(opts["role"])
	var shared := String(opts["dir"])
	if role not in ["host", "guest"] or shared.is_empty():
		return {"scenario_failure": "coop_bot needs --role=host|guest and --dir=<shared folder>", "outcome": "error", "game_seconds": 0.0, "frames": 0}
	# network phases wait in WALL-CLOCK time: a fixed-fps headless run plays frames faster than real time, and ENet/relay need real time
	var wait_for := func(condition: Callable, what: String, seconds: float) -> bool:
		var started_msec := Time.get_ticks_msec()
		while Time.get_ticks_msec() - started_msec < int(seconds * 1000.0):
			if condition.call():
				return true
			await tree.physics_frame
			OS.delay_msec(2)
		report["scenario_failure"] = "timed out waiting for %s" % what
		return false
	var read := func(name: String) -> String:
		return FileAccess.get_file_as_string(shared.path_join(name)).strip_edges()
	DirAccess.make_dir_recursive_absolute(shared)
	if role == "host":
		RoomState.create_local(RoomState.Mode.DEFAULT)
		RoomState.seed_text = String(opts["seed"])
		RoomState.set_map_scale(RoomState.Scale.INFINITE)
		# --room-code: a fixed code so testers can always join the same room (5 of A-H J-N P-Z 2-9; the backend's first claim wins)
		var fixed := String(opts.get("room_code", "")).to_upper()
		if not fixed.is_empty():
			RoomState.code = fixed
		var error := RoomState.host_primary_room(int(opts["port"]))
		if not error.is_empty():
			return {"scenario_failure": "host failed: %s" % error, "outcome": "error", "game_seconds": 0.0, "frames": 0}
		if not await wait_for.call(func(): return Backend.registered, "backend registration", 20.0):
			return {"outcome": "error", "game_seconds": 0.0, "frames": 0, "scenario_failure": String(report.get("scenario_failure", ""))}
		var code_file := FileAccess.open(shared.path_join("code.txt"), FileAccess.WRITE)
		code_file.store_string(RoomState.code)
		code_file.close()
		bridge.status = "coop_bot host waiting for guests (room %s)" % RoomState.code
		if not await wait_for.call(func(): return RoomState.roster().size() >= int(opts["guests"]) + 1, "%d guest(s) to join" % int(opts["guests"]), 60.0):
			return {"outcome": "error", "game_seconds": 0.0, "frames": 0, "scenario_failure": "%s; roster %s" % [report.get("scenario_failure", ""), RoomState.roster()]}
		RoomState.enter(tree)
	else:
		if not await wait_for.call(func(): return read.call("code.txt") != "", "the host's room code", 90.0):
			return {"outcome": "error", "game_seconds": 0.0, "frames": 0, "scenario_failure": String(report.get("scenario_failure", ""))}
		var code: String = read.call("code.txt")
		var box := [{}]
		var finished := [false]
		Backend.room_resolved.connect(func(_c: String, endpoint: Dictionary, err: String) -> void:
			box[0] = endpoint if err.is_empty() else {"error": err}
			finished[0] = true)
		Backend.resolve_room(code)
		if not await wait_for.call(func(): return finished[0], "room lookup", 15.0):
			return {"outcome": "error", "game_seconds": 0.0, "frames": 0, "scenario_failure": String(report.get("scenario_failure", ""))}
		var resolved: Dictionary = box[0]
		if resolved.has("error"):
			return {"scenario_failure": "room lookup: %s" % resolved["error"], "outcome": "error", "game_seconds": 0.0, "frames": 0}
		RoomState.create_local(RoomState.Mode.DEFAULT)
		var join_error := RoomState.join_room(String(resolved.get("address", "")), int(resolved.get("port", 0)), String(resolved.get("transport", "relay")), code)
		if not join_error.is_empty():
			return {"scenario_failure": "join failed: %s" % join_error, "outcome": "error", "game_seconds": 0.0, "frames": 0}
		bridge.status = "coop_bot guest waiting for the room roster (code %s)" % code
		if not await wait_for.call(func(): return RoomState.online and RoomState.peers.size() >= 2, "joining the room (never connected to the host: relay/ENet)", 90.0):
			return {"outcome": "error", "game_seconds": 0.0, "frames": 0, "scenario_failure": "%s; peers=%d online=%s" % [report.get("scenario_failure", ""), RoomState.peers.size(), RoomState.online]}
	bridge.status = "coop_bot %s waiting for the route scene" % role
	if not await wait_for.call(func(): return _scene(bridge) == "infinite_route_test.tscn", "the route scene", 90.0):
		return {"outcome": "error", "game_seconds": 0.0, "frames": 0, "scenario_failure": String(report.get("scenario_failure", ""))}
	if role == "guest":
		if not await wait_for.call(func(): return not bool(tree.current_scene.get("_awaiting_snapshot")), "the host snapshot", 180.0):
			return {"outcome": "error", "game_seconds": 0.0, "frames": 0, "scenario_failure": String(report.get("scenario_failure", ""))}
	adapter.attach()
	for _i in 60:
		await tree.physics_frame
	report["role"] = role
	if bool(opts.get("coop_check", false)):
		return await coop_check(bridge, adapter, opts, report)
	return await run_loop(bridge, adapter, opts, report)


## goto_check: verification of one place. Start a run (god mode, no hunters bothering), optionally teleport to --probe-x/--probe-z, ask the navigation for a
## path to --goal-x/--goal-z, then let the bot walk there (--goal-kind=relay collects the relay at the goal, explore just arrives) for --minutes game minutes.
## Reports path found / arrived / seconds / stuck spots / door failures, so "unreachable relay" and "stuck spot" reports can be re-checked after a fix.
static func goto_check(bridge: PlaytestBridge, adapter: BotAdapter, opts: Dictionary, report: Dictionary) -> Dictionary:
	var tree := bridge.get_tree()
	var start := await bridge.start_run({"game": adapter.game_id, "seed": opts["seed"], "difficulty": opts["difficulty"], "bot_seed": opts["bot_seed"], "debug": true})
	if not bool(start.get("ok", false)):
		return {"scenario_failure": "start_run failed: %s" % start.get("error", "?"), "outcome": "error", "game_seconds": 0.0, "frames": 0}
	bridge.admin("god", {"on": true})
	bridge.admin("no_target", {"on": true})
	var frames := 0
	# SELF-CHECK 1: an option that was passed on the command line must have reached the scenario (a silently ignored --goal-x once made a run test nothing)
	var raw_args: PackedStringArray = OS.get_cmdline_user_args()
	var joined := " ".join(raw_args)
	var given := func(prefix: String) -> bool:
		for arg in raw_args:
			if String(arg).begins_with(prefix + "="):
				return true
		return false
	var lost: Array = []
	if given.call("--goal-x") and int(opts["goal_x"]) == 0 and joined.find("--goal-x=0") < 0:
		lost.append("--goal-x")
	if given.call("--goal-z") and int(opts["goal_z"]) == 0 and joined.find("--goal-z=0") < 0:
		lost.append("--goal-z")
	if (given.call("--probe-x") or given.call("--probe-z")) and float(opts["probe_x"]) == 0.0 and float(opts["probe_z"]) == 0.0 and joined.find("--probe-x=0") < 0 and joined.find("--probe-z=0") < 0:
		lost.append("--probe-x/--probe-z")
	if not lost.is_empty():
		return {"scenario_failure": "options were passed but not applied: %s (args seen: %s)" % [", ".join(lost), raw_args], "outcome": "error", "game_seconds": 0.0, "frames": 0}
	var requested := Vector2(float(opts["probe_x"]), float(opts["probe_z"]))
	if requested != Vector2.ZERO:
		var obs0 := bridge.observe()
		bridge.admin("teleport", {"x": requested.x, "y": float(obs0["player"]["pos"][1]), "z": requested.y})
		for _i in 150:
			await tree.physics_frame
			frames += 1
		# SELF-CHECK 2: the player must really be where the check asked (a teleport that is refused or snapped elsewhere invalidates the whole run)
		var after := bridge.observe()
		var at := Vector2(float(after["player"]["pos"][0]), float(after["player"]["pos"][2]))
		report["goto_requested_start"] = [requested.x, requested.y]
		report["goto_actual_start"] = [snappedf(at.x, .1), snappedf(at.y, .1)]
		if at.distance_to(requested) > 4.0:
			return {"scenario_failure": "teleport not applied: asked for (%.1f, %.1f) but the player is at (%.1f, %.1f)" % [requested.x, requested.y, at.x, at.y],
				"outcome": "error", "game_seconds": snappedf(frames / 60.0, .1), "frames": frames}
	var goal := Vector2i(int(opts["goal_x"]), int(opts["goal_z"]))
	var paths: Dictionary = adapter.path_report(goal)
	var kind := String(opts["goal_kind"])
	var note := ""
	if kind == "relay" and not bool(paths.get("relay_at_goal", false)):
		# the map changes between builds: a relay that is not at that cell any more is a place to ARRIVE at, not a relay to collect
		kind = "explore"
		note = "no relay at this cell in this build: checked arrival only"
	adapter.forced_goal = goal
	adapter.forced_kind = kind
	var relays_before := GameState.relays_collected
	var delta := 1.0 / float(Engine.physics_ticks_per_second)
	var limit := int(float(opts["minutes"]) * 60.0 * 60.0)
	var arrived := false
	var arrived_at := -1.0
	var run_frames := 0
	var blocked := false
	var first_pos: Array = [0.0, 0.0, 0.0]
	var min_distance := 1e9
	while run_frames < limit:
		await tree.physics_frame
		frames += 1
		run_frames += 1
		var obs := bridge.observe()
		var pos: Array = obs["player"]["pos"]
		var distance := Vector2(float(pos[0]), float(pos[2])).distance_to(Vector2(goal) + Vector2(.5, .5))
		min_distance = minf(min_distance, distance)
		if run_frames % 120 == 0:
			bridge.status = "goto_check at %s, %.1f m from the goal" % [pos, distance]
		if kind == "relay" and GameState.relays_collected > relays_before:
			arrived = true
		elif kind != "relay" and distance < 1.6:
			arrived = true
		if arrived:
			arrived_at = snappedf(run_frames * delta, .1)
			break
		# cannot-move detection: nothing but standing still for 6 game seconds although a path exists -> say WHY (colliders, nav cells) and stop early
		if run_frames == 360 and Vector2(float(pos[0]), float(pos[2])).distance_to(Vector2(float(first_pos[0]), float(first_pos[2]))) < .3 and distance > 2.0 and int(paths.get("direct_len", 0)) > 0:
			report["blocked_diagnosis"] = adapter.collision_report()
			bridge.input.release_all()
			blocked = true
			break
		if run_frames == 1:
			first_pos = pos
		bridge.input.apply(adapter.decide(obs, delta))
	bridge.input.release_all()
	adapter.forced_goal = Vector2i(-99999, -99999)
	report["goto_check"] = {"path": paths, "arrived": arrived, "seconds": arrived_at, "note": note, "checked_as": kind, "closest_m": snappedf(min_distance, .1), "start": [opts["probe_x"], opts["probe_z"]],
		"goal": [goal.x, goal.y], "goal_kind": opts["goal_kind"], "stuck_spots": adapter.stats.get("stuck_events", 0), "door_failures": adapter.stats.get("door_failures", 0)}
	return {"outcome": "arrived" if arrived else "not_arrived", "game_seconds": snappedf(frames * delta, .1), "frames": frames,
		"scenario_failure": "" if arrived else ("blocked: the bot could not move from its start although a path of %s cells exists (see blocked_diagnosis)" % paths.get("direct_len", "?") if blocked else "did not reach %s in %.1f game minutes (closest %.1f m, path from player %s)" % [goal, float(opts["minutes"]), min_distance, paths.get("direct_len", "?")])}


## door_audit: tours chunks around the spawn (god mode), collects every closed ROOM_DOOR the streamed world shows, and for each one stands in front,
## looks at it and presses interact like a player. Fails when a door cannot be focused or does not open (--target = max doors, default 40).
static func door_audit(bridge: PlaytestBridge, adapter: BotAdapter, opts: Dictionary, report: Dictionary) -> Dictionary:
	var tree := bridge.get_tree()
	var start := await bridge.start_run({"game": adapter.game_id, "seed": opts["seed"], "difficulty": opts["difficulty"], "bot_seed": opts["bot_seed"], "debug": true})
	if not bool(start.get("ok", false)):
		return {"scenario_failure": "start_run failed: %s" % start.get("error", "?"), "outcome": "error", "game_seconds": 0.0, "frames": 0}
	bridge.admin("god", {"on": true})
	bridge.admin("no_target", {"on": true})
	var frames := 0
	var limit := int(opts["target"]) if int(opts["target"]) > 0 else 40
	var doors := {}
	var obs0 := bridge.observe()
	var y: float = float(obs0["player"]["pos"][1])
	var origin := Vector2(float(obs0["player"]["pos"][0]), float(obs0["player"]["pos"][2]))
	for step in [Vector2(0, 0), Vector2(45, 0), Vector2(-45, 0), Vector2(0, 45), Vector2(0, -45), Vector2(45, 45), Vector2(-45, -45), Vector2(45, -45), Vector2(-45, 45)]:
		if doors.size() >= limit:
			break
		bridge.status = "door_audit collecting doors around %s" % [origin + step]
		var spot := bridge.admin("teleport", {"x": origin.x + step.x, "y": y, "z": origin.y + step.y})
		for _i in 150:
			await tree.physics_frame
			frames += 1
		var obs := bridge.observe()
		for item in obs.get("interactables", []):
			if String(item["kind"]) == "ROOM_DOOR" and not bool(item["door_open"]):
				var key := "%d,%d" % [roundi(float(item["pos"][0]) * 2.0), roundi(float(item["pos"][2]) * 2.0)]
				if not doors.has(key) and doors.size() < limit:
					doors[key] = item["pos"]
	var rows: Array = []
	var failures: Array = []
	var index := 0
	for key in doors:
		index += 1
		bridge.status = "door_audit door %d/%d at %s" % [index, doors.size(), doors[key]]
		var result: Dictionary = await adapter.audit_door(doors[key])
		rows.append(result)
		frames += 170
		if not bool(result.get("opened", false)):
			failures.append("door at %s: %s" % [doors[key], "never focused" if not bool(result.get("focused", false)) else "focused but did not open"])
	bridge.input.release_all()
	report["door_audit"] = {"doors": rows.size(), "opened": rows.filter(func(r): return bool(r.get("opened", false))).size(),
		"never_focused": rows.filter(func(r): return not bool(r.get("focused", false))).size(), "failures": failures, "rows": rows}
	return {"outcome": "door_audit_done", "game_seconds": snappedf(frames / 60.0, .1), "frames": frames,
		"scenario_failure": "" if failures.is_empty() else "%d of %d doors could not be opened: %s" % [failures.size(), rows.size(), "; ".join(failures.slice(0, 4))]}


## probe: start a run, teleport to --probe-x/--probe-z (and --probe-y for another level), wait for the chunk to stream in, then take four screenshots turning 90 degrees
## each time and list what is nearby. For looking at a stuck spot a bot found (needs a windowed run to get images).
static func probe(bridge: PlaytestBridge, adapter: BotAdapter, opts: Dictionary, report: Dictionary) -> Dictionary:
	var tree := bridge.get_tree()
	var start := await bridge.start_run({"game": adapter.game_id, "seed": opts["seed"], "difficulty": opts["difficulty"], "bot_seed": opts["bot_seed"], "debug": true})
	if not bool(start.get("ok", false)):
		return {"scenario_failure": "start_run failed: %s" % start.get("error", "?"), "outcome": "error", "game_seconds": 0.0, "frames": 0}
	var obs := bridge.observe()
	var y: float = float(obs["player"]["pos"][1])
	# --probe-y picks another level (e.g. -3.96 for the sewer under the maze)
	if float(opts.get("probe_y", -9999.0)) > -9000.0:
		y = float(opts["probe_y"])
	var result := bridge.admin("teleport", {"x": float(opts["probe_x"]), "y": y, "z": float(opts["probe_z"])})
	var frames := await _await_streamed(tree)
	obs = bridge.observe()
	var shots: Array = []
	var dir := String(opts["out"]) if not String(opts["out"]).is_empty() else ".playtest/probe"
	var shot_dir := ProjectSettings.globalize_path("res://").path_join(dir) if not dir.is_absolute_path() else dir
	DirAccess.make_dir_recursive_absolute(shot_dir)
	var interact_result := {}
	if String(opts.get("probe_interact", "")) != "" and adapter.has_method("probe_interact"):
		interact_result = await adapter.probe_interact(String(opts["probe_interact"]), 150)
		for _j in 20:
			await tree.physics_frame
			frames += 1
		shots.append(bridge.screenshot(shot_dir.path_join("probe_after_interact.png")))
	for i in 4:
		var shot := bridge.screenshot(shot_dir.path_join("probe_%d.png" % i))
		shots.append(shot)
		bridge.input.apply({"look": [1.0, 0.0]})
		for _j in 34:
			await tree.physics_frame
			frames += 1
		bridge.input.apply({"look": [0.0, 0.0]})
		for _j in 6:
			await tree.physics_frame
			frames += 1
	bridge.input.release_all()
	var rows: Array = []
	for item in obs.get("interactables", []):
		if float(item["dist"]) < 8.0:
			rows.append(item)
	return {"outcome": "probed", "game_seconds": snappedf(frames / 60.0, .1), "frames": frames,
		"probe": {"teleport": result, "player": obs.get("player", {}), "interactables_near": rows, "hunters": obs.get("hunters", []), "world": obs.get("world", {}), "screenshots": shots, "interact": interact_result}}


const TOUR_SKIP := ["quit", "delete", "clear", "sign out", "abandon", "leave route", "reset", "remove", "kick", "wipe", "overwrite"]


static func _frames(bridge: PlaytestBridge, count: int) -> void:
	for _i in count:
		await bridge.get_tree().physics_frame


## A step the tour/tour-like scenarios take: names it for the watchdog ("stuck at ...") and refuses to go on after the budget is spent.
static func _status(bridge: PlaytestBridge, text: String) -> void:
	bridge.status = "%s (scene %s, frame %d)" % [text, _scene(bridge), Engine.get_physics_frames()]


static func _scene(bridge: PlaytestBridge) -> String:
	var scene := bridge.get_tree().current_scene
	return scene.scene_file_path.get_file() if scene != null else ""


## menu_tour: hub -> Last Route menu -> every safe button (modals closed with Esc) -> solo lobby -> every safe button -> a real route for a few
## seconds -> leave -> lobby -> back to games -> hub. Fails when a press logs an error, a scene never loads, or the way back to the hub is lost.
static func menu_tour(bridge: PlaytestBridge, adapter: BotAdapter, opts: Dictionary, report: Dictionary) -> Dictionary:
	var tree := bridge.get_tree()
	var steps: Array = []
	var problems: Array = []
	var frames := 0
	tree.change_scene_to_file(GameRegistry.HUB_SCENE)
	await _frames(bridge, 30)
	if _scene(bridge) != "game_hub.tscn":
		problems.append("could not boot to the hub (%s)" % _scene(bridge))
	var press := func(button: String, expect: String = "") -> bool:
		_status(bridge, "menu_tour pressing '%s'" % button)
		var before_errors := bridge.log_sink.errors
		var reply: Dictionary = await bridge.press(button)
		await _frames(bridge, 20)
		var scene := _scene(bridge)
		steps.append({"press": button, "ok": bool(reply.get("ok", false)), "scene": scene, "new_errors": bridge.log_sink.errors - before_errors})
		if not bool(reply.get("ok", false)):
			problems.append("press '%s' failed: %s" % [button, reply.get("error", "?")])
			return false
		if bridge.log_sink.errors > before_errors:
			problems.append("press '%s' logged %d engine error(s)" % [button, bridge.log_sink.errors - before_errors])
		if expect != "" and scene != expect:
			problems.append("after '%s' expected %s but on %s" % [button, expect, scene])
			return false
		return true
	await press.call("Launch_last_route", "main_menu.tscn")
	# every safe button of the Last Route menu, re-checked at press time (buttons enable/disable as the menu changes)
	var names: Array = []
	for entry in PlaytestObserver.ui(tree)["buttons"]:
		var label := String(entry["text"]).to_lower()
		var button_name := String(entry["name"])
		if TOUR_SKIP.any(func(word): return label.contains(word) or button_name.to_lower().contains(word)):
			continue
		names.append(button_name)
	for button_name in names:
		if _scene(bridge) != "main_menu.tscn":
			await _return_to_menu(bridge, press, problems)
		var current: Array = PlaytestObserver.ui(tree)["buttons"].filter(func(b): return String(b["name"]) == button_name)
		if current.is_empty() or bool(current[0]["disabled"]):
			steps.append({"press": button_name, "ok": true, "scene": _scene(bridge), "skipped": "not visible or disabled"})
			continue
		await press.call(button_name)
		if _scene(bridge) == "main_menu.tscn":
			for _k in 3:
				bridge.input.pulse("ui_cancel")
				await _frames(bridge, 6)
		else:
			await _return_to_menu(bridge, press, problems)
	# solo route and back out
	_status(bridge, "menu_tour starting a solo route")
	var started := await adapter.start_run({"seed": opts["seed"], "difficulty": opts["difficulty"], "debug": true})
	if not bool(started.get("ok", false)):
		problems.append("could not start a route: %s" % started.get("error", "?"))
	else:
		await _frames(bridge, 240)
		adapter.leave_run()
		await _frames(bridge, 40)
		if _scene(bridge) != "room_lobby.tscn":
			problems.append("leaving the route did not reach the lobby (%s)" % _scene(bridge))
		else:
			await press.call("BackToMenuButton", "game_hub.tscn")
	if _scene(bridge) == "main_menu.tscn":
		await press.call("QuitButton", "game_hub.tscn")
	if _scene(bridge) != "game_hub.tscn":
		problems.append("the tour did not end on the hub (%s)" % _scene(bridge))
	report["menu_tour"] = steps
	return {"outcome": "tour_done", "game_seconds": snappedf(frames / 60.0, .1), "frames": frames, "scenario_failure": "; ".join(problems)}


## Back to the Last Route menu from wherever a button left us (lobby -> hub -> Last Route card).
static func _return_to_menu(bridge: PlaytestBridge, press: Callable, problems: Array) -> void:
	for _attempt in 3:
		var scene := _scene(bridge)
		if scene == "main_menu.tscn":
			return
		if scene == "room_lobby.tscn":
			await press.call("BackToMenuButton")
		elif scene == "game_hub.tscn":
			await press.call("Launch_last_route")
		else:
			bridge.get_tree().change_scene_to_file(GameRegistry.HUB_SCENE)
			await _frames(bridge, 30)
	if _scene(bridge) != "main_menu.tscn":
		problems.append("could not get back to the Last Route menu (%s)" % _scene(bridge))


## death_scene_tour: for each hunter (--hunters=a,b or all A-Z and Void) summon it next to the standing, passive bot and wait for the catch:
## records who killed, how long it took, the death line shown, and fails on a missing line or an engine error. Hunters that never kill
## (non-lethal by design) are listed, not failed. Windowed runs also screenshot the death moment.
static func death_tour(bridge: PlaytestBridge, adapter: BotAdapter, opts: Dictionary, report: Dictionary) -> Dictionary:
	var tree := bridge.get_tree()
	var start := await bridge.start_run({"game": adapter.game_id, "seed": opts["seed"], "difficulty": opts["difficulty"], "debug": true})
	if not bool(start.get("ok", false)):
		return {"scenario_failure": "start_run failed: %s" % start.get("error", "?"), "outcome": "error", "game_seconds": 0.0, "frames": 0}
	var ids: Array = String(opts["hunters"]).split(",", false) if String(opts["hunters"]) != "" else (HunterRoster.A_Z_IDS + HunterRoster.VOID_IDS)
	var rows: Array = []
	var problems: Array = []
	var frames := 0
	for hunter_id in ids:
		var scene := tree.current_scene
		if scene == null or not scene.has_method("_admin_summon_hunter"):
			problems.append("route scene lost before %s" % hunter_id)
			break
		var errors_before := bridge.log_sink.errors
		# only the hunter under test may be around: remove whoever is still loaded from the last round
		var leftovers: Array = []
		var views: Dictionary = scene.get("_hunter_views")
		for key in views:
			var existing: HunterView3D = views[key]
			if existing != null and is_instance_valid(existing) and existing.brain != null:
				leftovers.append(String(existing.brain.hunter_id))
		for old_id in leftovers:
			scene.call("_admin_remove_hunter", old_id)
		for _i in 30:
			await tree.physics_frame
			frames += 1
		_status(bridge, "death_scene_tour waiting for %s to catch the bot" % hunter_id)
		scene.call("_admin_summon_hunter", String(hunter_id))
		var killed := false
		var waited := 0
		var line := ""
		while waited < 60 * 40:
			await tree.physics_frame
			frames += 1
			waited += 1
			var obs := bridge.observe()
			if adapter.run_over(obs):
				killed = true
				var cause: Dictionary = obs["run"].get("death", {})
				var picked: Dictionary = scene.call("_death_moment_for", String(cause.get("hunter_id", hunter_id)), cause) if scene.has_method("_death_moment_for") else {}
				line = String(picked.get("text", picked.get("line", "")))
				if line.is_empty() and not picked.is_empty():
					line = JSON.stringify(picked).left(120)
				rows.append({"hunter": hunter_id, "killed_by": cause.get("hunter_id", "?"), "seconds": snappedf(waited / 60.0, .1), "line": line})
				if String(cause.get("hunter_id", "")) != String(hunter_id):
					rows[-1]["note"] = "killed by %s, not the summoned hunter" % cause.get("hunter_id", "?")
				if line.is_empty():
					problems.append("%s: no death line" % hunter_id)
				if bool(opts["screenshots"]):
					for _i in 90:
						await tree.physics_frame
						frames += 1
					bridge.screenshot(ProjectSettings.globalize_path("res://.playtest/death/%s.png" % hunter_id))
				for _i in 120:
					await tree.physics_frame
					frames += 1
				adapter.after_run_over(obs)
				for _i in 90:
					await tree.physics_frame
					frames += 1
				break
		if not killed:
			rows.append({"hunter": hunter_id, "killed_by": "", "seconds": -1, "line": "", "note": "did not catch the passive bot in 40 s"})
			scene.call("_admin_remove_hunter", String(hunter_id)) if scene.has_method("_admin_remove_hunter") else null
		if bridge.log_sink.errors > errors_before:
			problems.append("%s: %d engine error(s) during the encounter" % [hunter_id, bridge.log_sink.errors - errors_before])
	report["death_tour"] = rows
	var no_kill := rows.filter(func(row): return String(row["killed_by"]) == "")
	adapter.stats["deaths"] = rows.size() - no_kill.size()
	return {"outcome": "death_tour_done", "game_seconds": snappedf(frames / 60.0, .1), "frames": frames, "scenario_failure": "; ".join(problems),
		"death_tour_summary": {"hunters": ids.size(), "killed": rows.size() - no_kill.size(), "no_kill": no_kill.map(func(row): return row["hunter"])}}


# ------------------------------------------------------------------------------------------------ soak
const SOAK_LEVELS := [0, 1, -1, -2, -3]
const SOAK_SAVE_DIR := "user://playtest_soak_saves"


## soak: a long run on the real streamed route for leak hunting (the measuring is PerfLog's, --soak-log). Plays like survive (chases,
## catches, restarts, hiding) and on timers, in game seconds:
##   --level-every=150   change level along 0, +1, -1, -2, -3 through real level links (the bot does not climb yet: it is put at the
##                       far end of the nearest link, one storey at a time, so every storey streams in and out); --hop-every=20 overrides
##   --save-every=600    save the run (the route's own payload, into a scratch save folder, cloud off), leave to the menu, CONTINUE it
##   --pause-every=60    open and close the pause menu, flip the graphics quality and put it back
##   --seam-every=90     sprint across the nearest chunk seam
##   a music box within 2.5 m is wound (interact held), at most once per box
##   --hunters=all | N | id,id   summoned again after every restart and resume (the stress variant)
## Stuck and unreachable limits scale with the length (the defaults are per 2 minutes) unless given.
static func soak(bridge: PlaytestBridge, adapter: BotAdapter, opts: Dictionary, report: Dictionary) -> Dictionary:
	var tree := bridge.get_tree()
	var hz := float(Engine.physics_ticks_per_second)
	var saves_dir := RunSaves.save_dir
	var saves_cloud := RunSaves.cloud_disabled
	RunSaves.save_dir = SOAK_SAVE_DIR   # never the player's own run
	RunSaves.cloud_disabled = true
	var quality := String(Settings.graphics_quality)
	var start := await bridge.start_run({"game": adapter.game_id, "seed": opts["seed"], "difficulty": opts["difficulty"],
		"bot_seed": opts["bot_seed"], "debug": true})
	if not bool(start.get("ok", false)):
		RunSaves.save_dir = saves_dir
		RunSaves.cloud_disabled = saves_cloud
		return {"scenario_failure": "start_run failed: %s" % start.get("error", "?"), "outcome": "error", "game_seconds": 0.0, "frames": 0}
	var given := " ".join(OS.get_cmdline_user_args())
	var scale := maxf(float(opts["minutes"]) / 2.0, 1.0)
	for key in ["max_stuck", "max_unreachable"]:
		if not given.contains("--" + key.replace("_", "-")):
			opts[key] = int(ceil(float(opts[key]) * scale))
	var every := {"level": float(opts["hop_every"]) if float(opts["hop_every"]) > 0.0 else float(opts["level_every"]),
		"save": float(opts["save_every"]), "pause": float(opts["pause_every"]), "seam": float(opts["seam_every"])}
	var due := every.duplicate()
	var counts := {"level_changes": 0, "level_failed": 0, "save_loads": 0, "save_load_failed": 0, "pauses": 0, "setting_flips": 0,
		"seam_sprints": 0, "music_boxes": 0, "deaths": 0, "hunters_summoned": 0}
	var levels_seen := {}
	var actions: Array = []
	var wound := {}
	var cycle := 0
	var override := {}
	var fps: Array = []
	var frame_ms: Array = []
	var limit := int(float(opts["minutes"]) * 60.0 * hz)
	var frames := 0
	var last_over := false
	counts["hunters_summoned"] = int(counts["hunters_summoned"]) + _soak_hunters(tree, String(opts["hunters"]))
	# a full observation every tick costs more than the game on old machines (PERF: 4-13 fps instead of 90+), so the soak looks
	# every 3rd tick unless --observe-every says otherwise; the bot steers on the last one in between
	var observe_every := int(opts["observe_every"]) if int(opts["observe_every"]) > 0 else 3
	var obs := {}
	while frames < limit:
		await tree.physics_frame
		frames += 1
		var t := float(frames) / hz
		if obs.is_empty() or frames % observe_every == 0 or not _soak_route(tree.current_scene):
			obs = bridge.observe()
		var scene := tree.current_scene
		var level := int(obs.get("world", {}).get("level", 0))
		levels_seen[level] = int(levels_seen.get(level, 0)) + 1
		if frames % 120 == 0:
			bridge.status = "soak %d/%d s, level %d, %s" % [int(t), int(limit / hz), level, counts]
		if frames % SAMPLE_EVERY == 0 and float(obs.get("fps", 0.0)) > 0.0:
			fps.append(float(obs["fps"]))
			frame_ms.append(float(obs["frame_ms"]))
		var over := adapter.run_over(obs)
		if over and not last_over:
			counts["deaths"] = int(counts["deaths"]) + 1
			adapter.add_event("death", {"t": snappedf(t, .1), "level": level})
			for _i in 180:
				await tree.physics_frame
			frames += 180
			bridge.input.release_all()
			adapter.after_run_over(obs)
			for _i in 120:
				await tree.physics_frame
			frames += 120
			override = {}
			obs = {}   # the cached one still says the run is over
			counts["hunters_summoned"] = int(counts["hunters_summoned"]) + _soak_hunters(tree, String(opts["hunters"]))
			continue
		last_over = over
		if over or not _soak_route(scene):
			continue
		# timed actions, one per frame at most
		var did := ""
		if every["save"] > 0.0 and t >= float(due["save"]):
			due["save"] = t + float(every["save"])
			did = "save_load"
			var saved := await _soak_save_load(bridge, adapter, opts)
			frames += int(saved.get("frames", 0))
			counts["save_loads" if bool(saved["ok"]) else "save_load_failed"] = int(counts["save_loads" if bool(saved["ok"]) else "save_load_failed"]) + 1
			saved["t"] = snappedf(t, .1)
			actions.append(saved)
			counts["hunters_summoned"] = int(counts["hunters_summoned"]) + _soak_hunters(tree, String(opts["hunters"]))
		elif every["level"] > 0.0 and t >= float(due["level"]):
			due["level"] = t + float(every["level"])
			did = "level"
			cycle = (cycle + 1) % SOAK_LEVELS.size()
			var moved := await _soak_level(bridge, scene, int(SOAK_LEVELS[cycle]))
			frames += int(moved.get("frames", 0))
			counts["level_changes" if bool(moved["ok"]) else "level_failed"] = int(counts["level_changes" if bool(moved["ok"]) else "level_failed"]) + 1
			moved["t"] = snappedf(t, .1)
			actions.append(moved)
		elif every["pause"] > 0.0 and t >= float(due["pause"]):
			due["pause"] = t + float(every["pause"])
			did = "pause"
			frames += await _soak_pause(tree, scene, quality)
			counts["pauses"] = int(counts["pauses"]) + 1
			counts["setting_flips"] = int(counts["setting_flips"]) + 1
		elif every["seam"] > 0.0 and t >= float(due["seam"]):
			due["seam"] = t + float(every["seam"])
			did = "seam"
			override = _soak_seam(scene, frames + int(4.0 * hz))
			counts["seam_sprints"] = int(counts["seam_sprints"]) + 1
		elif frames % 30 == 0 and override.is_empty():
			var box := _soak_music_box(scene, wound)
			if box != null:
				did = "music_box"
				wound[box.get_instance_id()] = true
				override = {"until": frames + int(2.6 * hz), "hold_interact": true, "aim": box.global_position + Vector3.UP * .3}
				counts["music_boxes"] = int(counts["music_boxes"]) + 1
		if not did.is_empty():
			adapter.add_event("soak_" + did, {"t": snappedf(t, .1), "level": level})
		# the bot plays, unless an action is steering
		scene = tree.current_scene   # a save/load replaced it
		var player: PlayerController3D = scene.get("player") if _soak_route(scene) else null
		if not override.is_empty() and frames < int(override["until"]) and player != null:
			if override.has("aim"):
				var to: Vector3 = (override["aim"] as Vector3) - player.first_person_camera.global_position
				player._yaw = PlaytestFlythrough.yaw_for(to.x, to.z)
				player._pitch = PlaytestFlythrough.pitch_for(to.normalized())
				player._apply_look_rotation()
				Input.action_press("interact")
				bridge.input.apply({})
			else:
				player._yaw = float(override["yaw"])
				player._apply_look_rotation()
				bridge.input.apply({"move": [0.0, 1.0], "hold": {"sprint": true}})
			continue
		if not override.is_empty():
			if bool(override.get("hold_interact", false)):
				Input.action_release("interact")
			override = {}
		bridge.input.apply(adapter.decide(obs, 1.0 / hz))
	bridge.input.release_all()
	Input.action_release("interact")
	if Settings.graphics_quality != quality:
		Settings.set_graphics_quality(quality)
	RunSaves.clear()
	RunSaves.save_dir = saves_dir
	RunSaves.cloud_disabled = saves_cloud
	var seen := {}
	for key in levels_seen:
		seen[str(key)] = snappedf(float(levels_seen[key]) / hz, .1)
	report["soak"] = {"counts": counts, "seconds_per_level": seen, "actions": actions}
	var failure := ""
	if int(counts["save_load_failed"]) > 0:
		failure = "%d save/load cycle(s) did not resume the run" % int(counts["save_load_failed"])
	return {"outcome": "time_limit", "game_seconds": snappedf(float(frames) / hz, .1), "frames": frames,
		"perf": PlaytestReporter.perf_summary(fps, frame_ms), "deaths": [], "scenario_failure": failure}


static func _soak_route(scene: Node) -> bool:
	return scene != null and scene.get("player") is PlayerController3D and scene.get("facility") != null


## --hunters: all (every A-Z and Void hunter), a count (the first N), or ids. The route's own admin summon (peer 1 offline).
static func _soak_hunters(tree: SceneTree, wanted: String) -> int:
	var scene := tree.current_scene
	if wanted.is_empty() or not _soak_route(scene) or not scene.has_method("_admin_summon_hunter_authoritative"):
		return 0
	var roster: Array = HunterRoster.A_Z_IDS + HunterRoster.VOID_IDS
	var ids: Array = roster if wanted == "all" else (roster.slice(0, int(wanted)) if wanted.is_valid_int() else Array(wanted.split(",", false)))
	for id in ids:
		scene.call("_admin_summon_hunter_authoritative", 1, String(id))
	return ids.size()


## Moves one storey at a time toward `target` through the nearest real level link (within 3 chunks) to the next storey, landing at
## its far end; noclip holds the runner until that storey's floor has streamed in.
static func _soak_level(bridge: PlaytestBridge, scene: Node, target: int) -> Dictionary:
	var tree := bridge.get_tree()
	var facility: StreamedFacilityView3D = scene.get("facility")
	var player: PlayerController3D = scene.get("player")
	var from := facility.current_level()
	var path: Array = [from]
	var frames := 0
	var cs := float(StreamedRouteGenerator.CHUNK_SIZE)
	for _hop in 6:
		var here := facility.current_level()
		if here == target:
			break
		var step := here + signi(target - here)
		var centre := facility.current_chunk_coord()
		var best := {}
		var best_d := INF
		for dz in range(-3, 4):
			for dx in range(-3, 4):
				var coord := Vector3i(centre.x + dx, here, centre.z + dz)
				if not facility.generator.is_chunk_allowed(coord):
					continue
				for link_value in facility.generator.vertical_links(coord):
					var link: Dictionary = link_value
					if LevelLink.cell_on(link, here) == Vector2i(-1, -1) or int(LevelLink.other_end(link, here)["level"]) != step:
						continue
					var d := float(dx * dx + dz * dz)
					if d < best_d:
						best_d = d
						best = link
		if best.is_empty():
			return {"action": "level", "ok": false, "from": from, "to": target, "path": path, "frames": frames,
				"why": "no link from %d to %d within 3 chunks" % [here, step]}
		var far: Dictionary = LevelLink.other_end(best, here)
		var cell: Vector2i = far["cell"]
		var chunk: Vector3i = best["chunk"]
		var landing := facility.global_position + Vector3(float(chunk.x) * cs + float(cell.x) + .5,
			float(step) * StreamedFacilityView3D.LEVEL_HEIGHT + .1, float(chunk.z) * cs + float(cell.y) + .5)
		player.set_admin_noclip(true)
		bridge.admin("teleport", {"x": landing.x, "y": landing.y, "z": landing.z})
		frames += await _await_streamed(tree, func() -> void:
			player.global_position = landing
			player.velocity = Vector3.ZERO)
		# step off the link (the bot does not use ladders: left on one it climbs straight back) onto the most open floor beside it
		var space := player.get_world_3d().direct_space_state
		var off := Vector3.ZERO
		var room := 0.0
		for k in 8:
			var dir := Vector3(sin(TAU * float(k) / 8.0), 0.0, cos(TAU * float(k) / 8.0))
			var ray := PhysicsRayQueryParameters3D.create(landing + Vector3.UP, landing + Vector3.UP + dir * 4.0)
			ray.exclude = [player.get_rid()]
			var hit := space.intersect_ray(ray)
			var clear := 4.0 if hit.is_empty() else landing.distance_to((hit["position"] as Vector3) - Vector3.UP)
			if clear > room:
				room = clear
				off = dir * minf(1.6, clear - .5)
		player.global_position = landing + off
		player.set_admin_noclip(false)
		# where it landed (world x/z, chunk, link id), so a bad spot can be visited again
		path.append({"link": best["id"], "to": step, "chunk": [chunk.x, chunk.z],
			"at": [snappedf(player.global_position.x, .1), snappedf(player.global_position.y, .1), snappedf(player.global_position.z, .1)]})
	# let go and see that the runner stays there, standing on that storey's floor (not falling back through it)
	for _i in 60:
		await tree.physics_frame
	frames += 60
	var floor_y := facility.global_position.y + float(target) * StreamedFacilityView3D.LEVEL_HEIGHT
	var ok := facility.current_level() == target and absf(player.global_position.y - floor_y) < 1.5
	return {"action": "level", "ok": ok, "from": from, "to": target, "path": path, "frames": frames,
		"settled": [facility.current_level(), snappedf(player.global_position.y - floor_y, .01)]}


## Saves the run (the route's own save payload, into the soak's scratch folder), leaves to the menu and resumes it through the title's
## CONTINUE path; ok when the resumed runner is back on the saved level within 6 m of the saved spot.
static func _soak_save_load(bridge: PlaytestBridge, adapter: BotAdapter, opts: Dictionary) -> Dictionary:
	var tree := bridge.get_tree()
	var scene := tree.current_scene
	var player: PlayerController3D = scene.get("player")
	var facility: StreamedFacilityView3D = scene.get("facility")
	var at := player.global_position
	var level := facility.current_level()
	var written := RunSaves.write(scene.call("_build_route_save_payload"), "LEVEL %+d" % level)
	if not bool(written.get("ok", false)):
		return {"action": "save_load", "ok": false, "why": "write: %s" % written.get("message", "?"), "frames": 0}
	bridge.input.release_all()
	adapter.leave_run()
	var frames := 0
	for _i in 600:
		await tree.physics_frame
		frames += 1
		if not _soak_route(tree.current_scene):
			break
	for _i in 60:
		await tree.physics_frame
	frames += 60
	var queued := RunSaves.queue_continue()
	if not bool(queued.get("ok", false)):
		return {"action": "save_load", "ok": false, "why": "continue: %s" % queued.get("message", "?"), "frames": frames}
	var start := await bridge.start_run({"game": adapter.game_id, "seed": opts["seed"], "difficulty": opts["difficulty"],
		"bot_seed": opts["bot_seed"], "debug": true})
	frames += 120
	if not bool(start.get("ok", false)):
		return {"action": "save_load", "ok": false, "why": "start_run: %s" % start.get("error", "?"), "frames": frames}
	var resumed := tree.current_scene
	var back: PlayerController3D = resumed.get("player")
	var back_level := (resumed.get("facility") as StreamedFacilityView3D).current_level()
	var gap := Vector2(back.global_position.x - at.x, back.global_position.z - at.z).length()
	return {"action": "save_load", "ok": back_level == level and gap <= 6.0, "level": level, "resumed_level": back_level,
		"gap_m": snappedf(gap, .1), "frames": frames}


## The pause menu opened and closed again, the graphics quality flipped to another tier and back.
static func _soak_pause(tree: SceneTree, scene: Node, quality: String) -> int:
	# the player's own pause key, so the menu opens the way it does in play
	var menu: PauseMenu = scene.get("pause_menu")
	Playtest.input.pulse("pause")
	for _i in 60:
		await tree.physics_frame
	var other := "LOW" if quality != "LOW" else "MEDIUM"
	Settings.set_graphics_quality(other)
	for _i in 30:
		await tree.physics_frame
	Settings.set_graphics_quality(quality)
	if menu != null and menu.is_open():
		Playtest.input.pulse("pause")
	for _i in 10:
		await tree.physics_frame
	if menu != null and menu.is_open():
		menu.close()   # the key did not close it: count it in the report through the log, never leave a run paused
	for _i in 10:
		await tree.physics_frame
	return 110


## Faces the nearest chunk seam (x or z) and sprints at it until `until`.
static func _soak_seam(scene: Node, until: int) -> Dictionary:
	var player: PlayerController3D = scene.get("player")
	var cs := float(StreamedRouteGenerator.CHUNK_SIZE)
	var p := player.global_position
	var fx := fposmod(p.x, cs)
	var fz := fposmod(p.z, cs)
	var options := [[fx, Vector3(-1, 0, 0)], [cs - fx, Vector3(1, 0, 0)], [fz, Vector3(0, 0, -1)], [cs - fz, Vector3(0, 0, 1)]]
	options.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var dir: Vector3 = options[0][1]
	return {"until": until, "yaw": PlaytestFlythrough.yaw_for(dir.x, dir.z)}


## An unwound music box within 2.5 m on this storey, in line of sight.
static func _soak_music_box(scene: Node, wound: Dictionary) -> RouteInteractable3D:
	var player: PlayerController3D = scene.get("player")
	for node in scene.get_tree().get_nodes_in_group("interactable"):
		var it := node as RouteInteractable3D
		if it == null or it.kind != RouteInteractable3D.Kind.MUSIC_BOX or wound.has(it.get_instance_id()) or not it.is_visible_in_tree():
			continue
		var gap := it.global_position - player.global_position
		if absf(gap.y) < 1.5 and Vector2(gap.x, gap.z).length() <= 2.5:
			return it
	return null



# ------------------------------------------------------------------------------------------------ coop_check
## coop_bot --coop-check: a scripted live co-op test. No runner is a target until its scripted catch, so nothing ends early. Every peer plays with the bot and, on the same timeline (seconds since it entered the
## route), does its part; every peer writes a state sample each wall-clock second (epoch ms) to <out>/coop_samples.jsonl and screenshots
## at the key moments, so tools/playtest/coop_compare.py can line the peers up afterwards.
##   guests are ordered by peer id: A (first), B (second or A), C (third or A)
##   t 50   host summons Glyra beside B          t 60   B winds the nearest music box (its own interaction)
##   t 110  C hides in the nearest slatted locker t 118  host summons Dovelle beside C and has her inspect that locker (lean in)
##   t 235  A stands still                        t 240  host summons Kathy beside A: a real catch (grab, death flow) on A
##   t 470  host stands still                     t 480  host summons Kathy beside itself: the host's own catch
const COOP_SHOTS := [5.0, 58.0, 63.0, 68.0, 116.0, 124.0, 130.0, 138.0, 242.0, 244.5, 247.0, 252.0, 300.0, 360.0, 420.0, 482.0, 484.5, 488.0, 540.0]


static func coop_check(bridge: PlaytestBridge, adapter: BotAdapter, opts: Dictionary, report: Dictionary) -> Dictionary:
	var tree := bridge.get_tree()
	var role := String(report.get("role", "host"))
	var me := tree.get_multiplayer().get_unique_id()
	var out := String(opts["out"]) if String(opts["out"]) != "" else ProjectSettings.globalize_path("res://.playtest/%s" % opts["name"])
	DirAccess.make_dir_recursive_absolute(out.path_join("shots"))
	var samples := FileAccess.open(out.path_join("coop_samples.jsonl"), FileAccess.WRITE)
	var started := Time.get_ticks_msec()
	var limit := float(opts["minutes"]) * 60.0
	var hz := float(Engine.physics_ticks_per_second)
	var shot_i := 0
	var next_sample := 0.0
	var done := {}
	var passive_until := -1.0
	var hidden_spot := {}
	var steps: Array = []
	var fps: Array = []
	var frame_ms: Array = []
	var frames := 0
	var obs := {}
	# hunters leave every runner alone until its scripted catch (A from t 235, the host from t 470): a windowed debug build only
	# honours no-target with admin rights, so the harness takes the screenshot rig's debug-only stand-in for them
	Build.capture_rig = true
	var roles := []                # A, B, C fixed once every expected guest is in (a player joining later never takes a role)
	var gate_ok := false           # every expected peer's live state seen in the route
	var overlay := _coop_overlay(tree)
	var next_shot := 30.0
	var host_catch := String(opts.get("host_catch", "true")) != "false"
	# no progress for 3 s while it should be moving: back off (1 s), then re-path from open floor, then (still stuck after ~9 s) hop to
	# the host; each step is an event with a screenshot (KT saw a bot wedged in a carnival booth doorway for minutes)
	var stuck := {"at": Vector3.INF, "since": 0.0, "stage": 0, "back_until": -1.0}
	var stuck_log: Array = []
	# host: every guest request as it arrives (the game drops refused ones silently), guard verdicts, and each peer's
	# refusal-relevant state once a second, to <out>/coop_host_requests.jsonl
	var reqlog: FileAccess = FileAccess.open(out.path_join("coop_host_requests.jsonl"), FileAccess.WRITE) if role == "host" else null
	var hooked := []
	while true:
		await tree.physics_frame
		frames += 1
		var t := float(Time.get_ticks_msec() - started) / 1000.0
		if t >= limit:
			break
		var scene := tree.current_scene
		if not _soak_route(scene):
			continue
		var guests := _coop_guests(scene)
		if roles.is_empty() and guests.size() >= int(opts["guests"]):
			roles = guests.slice(0, 3)
			report["coop_roles"] = roles
		var a := int(roles[0]) if roles.size() > 0 else -1
		var b := int(roles[1]) if roles.size() > 1 else a
		var c := int(roles[2]) if roles.size() > 2 else a
		var player: PlayerController3D = scene.get("player")
		# the hard check: inside the route, within 60 s, the host hears every expected guest live and a guest hears the host
		var live := _coop_live(scene)
		if not gate_ok:
			gate_ok = (live.size() >= int(opts["guests"])) if role == "host" else live.has(1)
			if gate_ok:
				report["coop_gate"] = {"t": snappedf(t, .1), "live": live}
			elif t > 60.0 and String(opts.get("gate_strict", "true")) == "false":
				# a long-lived room for testers: note it and carry on rather than take the room down
				report["coop_gate"] = {"t": snappedf(t, .1), "live": live, "failed": true}
				adapter.add_event("coop_gate_failed", {"t": snappedf(t, .1), "live": live})
				gate_ok = true
			elif t > 60.0:
				bridge.screenshot(out.path_join("shots/%s_gate_failed.png" % _coop_name(role, opts)))
				samples.close()
				Build.capture_rig = false
				return {"outcome": "error", "game_seconds": snappedf(t, .1), "frames": frames, "deaths": [],
					"scenario_failure": "co-op gate: after 60 s in the route %s hears %s (want %s)" % [role, live,
						"%d guests" % int(opts["guests"]) if role == "host" else "the host"]}
		if reqlog != null and not hooked.has(scene.get_instance_id()):
			hooked.append(scene.get_instance_id())
			_coop_hook_requests(scene, reqlog, started)
		if reqlog != null and t >= next_sample:
			_coop_peer_states(scene, reqlog, t)
		player.admin_no_target = not ((me == a and t >= 235.0) or (role == "host" and t >= 470.0))
		# the timeline, each step once
		var step := ""
		if role == "host" and t >= 50.0 and not done.has("glyra"):
			step = "glyra"
			scene.call("_admin_summon_hunter_authoritative", b, "glyra")
		elif me == b and t >= 60.0 and not done.has("wind"):
			step = "wind"
			steps.append(await _coop_wind(bridge, scene, player))
		elif me == c and t >= 110.0 and not done.has("hide"):
			step = "hide"
			hidden_spot = await _coop_hide(bridge, scene, player)
			steps.append(hidden_spot)
			passive_until = 200.0
		elif role == "host" and t >= 118.0 and not done.has("summon_c"):
			step = "summon_c"
			scene.call("_admin_summon_hunter_authoritative", c, "dovelle")
		elif role == "host" and t >= 120.0 and not done.has("inspect"):
			step = "inspect"
			steps.append(_coop_inspect(scene, c))
		elif me == a and t >= 235.0 and not done.has("still_a"):
			step = "still_a"
			passive_until = 330.0
		elif role == "host" and t >= 240.0 and not done.has("catch_a"):
			step = "catch_a"
			scene.call("_admin_summon_hunter_authoritative", a, "kathy")
		elif host_catch and role == "host" and t >= 470.0 and not done.has("still_host"):
			step = "still_host"
			passive_until = 560.0
		elif host_catch and role == "host" and t >= 480.0 and not done.has("catch_host"):
			step = "catch_host"
			scene.call("_admin_summon_hunter_authoritative", me, "kathy")
		if not step.is_empty():
			done[step] = snappedf(t, .1)
			adapter.add_event("coop_" + step, {"t": snappedf(t, .1), "epoch_ms": int(Time.get_unix_time_from_system() * 1000.0)})
		# sample every wall second
		if t >= next_sample:
			next_sample += 1.0
			overlay.text = _coop_overlay_text(scene, role, me, roles)
			var row := _coop_sample(scene, role, me, t)
			row["run_over"] = adapter.run_over(obs) if not obs.is_empty() else null
			samples.store_line(JSON.stringify(row))
			samples.flush()
		if shot_i < COOP_SHOTS.size() and t >= float(COOP_SHOTS[shot_i]):
			bridge.screenshot(out.path_join("shots/%s_%04d.png" % [_coop_name(role, opts), int(COOP_SHOTS[shot_i])]))
			shot_i += 1
		if t >= next_shot:
			next_shot += 30.0
			bridge.screenshot(out.path_join("shots/%s_%04d_roster.png" % [_coop_name(role, opts), int(t)]))
		if frames % 3 == 0 or obs.is_empty():
			obs = bridge.observe()
		if frames % SAMPLE_EVERY == 0 and float(obs.get("fps", 0.0)) > 0.0:
			fps.append(float(obs["fps"]))
			frame_ms.append(float(obs["frame_ms"]))
		# a caught runner spectates (co-op): nothing to steer; a passive window stands still (and stays in the locker)
		if adapter.run_over(obs) or t < passive_until:
			bridge.input.apply({})
			continue
		# guests keep with the host (within 8 m) so the room is visible on every screen and the minimap; the host just plays
		var host_state: Dictionary = (scene.get("_remotes").get("_states") as Dictionary).get(1, {}) if role == "guest" else {}
		var host_at: Variant = host_state.get("position") if host_state.get("position") is Vector2 else null
		if role == "guest" and adapter.has_method("follow"):
			adapter.call("follow", host_at, 8.0)
		var here := player.global_position
		var far_from_host := host_at != null and Vector2(here.x, here.z).distance_to(host_at) > 8.0
		if player.hidden or not (far_from_host or role == "host"):
			stuck["at"] = here
			stuck["since"] = t
			stuck["stage"] = 0
		elif (stuck["at"] as Vector3).distance_to(here) > .5:
			stuck["at"] = here
			stuck["since"] = t
			stuck["stage"] = 0
		elif t - float(stuck["since"]) > 3.0 * float(int(stuck["stage"]) + 1):
			var stage := int(stuck["stage"]) + 1
			stuck["stage"] = stage
			var what := "back_off" if stage == 1 else ("repath" if stage == 2 else "hop_to_host")
			var entry := {"t": snappedf(t, .1), "what": what, "pos": [snappedf(here.x, .01), snappedf(here.y, .01), snappedf(here.z, .01)],
				"cell": [floori(here.x), floori(here.z)], "level": (scene.get("facility") as StreamedFacilityView3D).current_level(),
				"region": String((scene.get("facility") as StreamedFacilityView3D).current_chunk_data().get("region", "")),
				"focus": obs.get("focus", {}), "near": (obs.get("interactables", []) as Array).slice(0, 3)}
			var shot := out.path_join("shots/%s_stuck_%04d_%s.png" % [_coop_name(role, opts), int(t), what])
			bridge.screenshot(shot)
			entry["shot"] = shot.get_file()
			stuck_log.append(entry)
			adapter.add_event("coop_stuck", entry)
			if stage == 1:
				stuck["back_until"] = t + 1.0
			elif stage == 2:
				adapter.forced_goal = Vector2i(-99999, -99999)
				adapter.set("_path", [])
				adapter.set("_goal", {})
			elif host_at != null:
				var to: Vector2 = host_at
				bridge.admin("teleport", {"x": to.x + .8, "y": here.y, "z": to.y + .8})
				stuck["since"] = t
				stuck["stage"] = 0
		if t < float(stuck["back_until"]):
			bridge.input.apply({"move": [0.0, -1.0], "look": [.4, 0.0]})
			continue
		bridge.input.apply(adapter.decide(obs, 1.0 / hz))
	bridge.input.release_all()
	samples.close()
	if reqlog != null:
		reqlog.close()
	Build.capture_rig = false
	overlay.queue_free()
	report["coop_stuck"] = stuck_log
	report["coop_check"] = {"done": done, "steps": steps, "me": me, "guests": _coop_guests(tree.current_scene) if _soak_route(tree.current_scene) else []}
	return {"outcome": "time_limit", "game_seconds": snappedf(float(frames) / hz, .1), "frames": frames,
		"perf": PlaytestReporter.perf_summary(fps, frame_ms), "deaths": [], "scenario_failure": ""}


static func _coop_hook_requests(scene: Node, sink: FileAccess, started: int) -> void:
	var remotes: Object = scene.get("_remotes")
	if remotes == null:
		return
	var write := func(kind: String, peer: int, data: Variant) -> void:
		sink.store_line(JSON.stringify({"epoch_ms": int(Time.get_unix_time_from_system() * 1000.0),
			"t": snappedf(float(Time.get_ticks_msec() - started) / 1000.0, .01), "kind": kind, "peer": peer, "data": data}))
		sink.flush()
	remotes.connect("world_event_requested", func(peer: int, event: Dictionary) -> void: write.call("world_event_requested", peer, event))
	remotes.connect("interaction_requested", func(peer: int, event: Dictionary) -> void: write.call("interaction_accepted", peer, event))
	remotes.connect("guest_violation", func(peer: int, reason: String, strikes: int, kicked: bool) -> void:
		write.call("guest_violation", peer, {"reason": reason, "strikes": strikes, "kicked": kicked}))


## Each guest's standing with the host once a second: trolled, guard strikes / lagging, and requests in the rate window.
static func _coop_peer_states(scene: Node, sink: FileAccess, t: float) -> void:
	var remotes: Object = scene.get("_remotes")
	if remotes == null:
		return
	var guard: Object = remotes.get("guard")
	var times: Dictionary = remotes.get("_interaction_times")
	var trolls: Dictionary = remotes.get("troll_peers")
	var rows := {}
	for id in RoomState.peers:
		if int(id) == 1:
			continue
		rows[str(id)] = {"troll": trolls.has(int(id)), "strikes": int(guard.call("strikes", int(id))) if guard != null else -1,
			"lagging": bool(guard.call("lagging", int(id))) if guard != null else false,
			"rate_window": (times.get(int(id), []) as Array).size(), "name": RoomState.peer_display_name(int(id))}
	sink.store_line(JSON.stringify({"epoch_ms": int(Time.get_unix_time_from_system() * 1000.0), "t": snappedf(t, .01), "kind": "peers", "data": rows}))
	sink.flush()


static func _coop_name(role: String, opts: Dictionary) -> String:
	return role if role == "host" else "guest%d" % int(opts["bot_seed"])


## Peers whose state reached this one in the last 2 s (the host is peer 1).
static func _coop_live(scene: Node) -> Array:
	var ids: Array = []
	var remotes: Object = scene.get("_remotes")
	if remotes == null:
		return ids
	var now := Time.get_ticks_usec()
	var states: Dictionary = remotes.get("_states")
	for id in states:
		if now - int((states[id] as Dictionary).get("received_usec", 0)) < 2000000:
			ids.append(int(id))
	ids.sort()
	return ids


## A corner readout drawn into every screenshot: the room code, this peer, and every runner it hears (distance, storey).
static func _coop_overlay(tree: SceneTree) -> Label:
	var layer := CanvasLayer.new()
	layer.layer = 120
	layer.name = "CoopCheckOverlay"
	tree.root.add_child(layer)
	var label := Label.new()
	label.position = Vector2(12, 120)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(1, 1, .6))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	layer.add_child(label)
	label.tree_exiting.connect(layer.queue_free)
	return label


static func _coop_overlay_text(scene: Node, role: String, me: int, roles: Array) -> String:
	var player: PlayerController3D = scene.get("player")
	var facility: StreamedFacilityView3D = scene.get("facility")
	var lines := ["CO-OP TEST // ROOM %s // %s peer %d // level %+d" % [RoomState.code, role.to_upper(), me, facility.current_level()],
		"roster %d: %s   roles A/B/C %s" % [RoomState.peers.size(), _coop_guests(scene), roles]]
	var states: Dictionary = (scene.get("_remotes") as Object).get("_states")
	var now := Time.get_ticks_usec()
	for id in states:
		var st: Dictionary = states[id]
		var at = st.get("position")
		var d := Vector2(player.global_position.x, player.global_position.z).distance_to(at) if at is Vector2 else -1.0
		lines.append("  peer %d  %5.1f m  level %+d  %s" % [int(id), d, -int(st.get("depth", 0)),
			"live" if now - int(st.get("received_usec", 0)) < 2000000 else "STALE"])
	return "\n".join(lines)


static func _coop_guests(scene: Node) -> Array:
	var ids: Array = []
	for id in RoomState.peers:
		if int(id) != 1:
			ids.append(int(id))
	ids.sort()
	return ids


## What this peer sees, for the cross-peer comparison: its runner, every hunter view (state, inspect phase, chase style and its blend,
## Kathy's beam), every remote runner's grab packet, the music boxes' clocks and Glyra's mood.
static func _coop_sample(scene: Node, role: String, me: int, t: float) -> Dictionary:
	var player: PlayerController3D = scene.get("player")
	var hud: Object = scene.get("hud")
	var grab: Object = scene.get("grab")
	var row := {"epoch_ms": int(Time.get_unix_time_from_system() * 1000.0), "t": snappedf(t, .01), "role": role, "me": me,
		"fps": Engine.get_frames_per_second(),
		"pos": [snappedf(player.global_position.x, .01), snappedf(player.global_position.y, .01), snappedf(player.global_position.z, .01)],
		"hidden": player.hidden, "grab_state": player.grab_state.duplicate(),
		"grab_playing": grab != null and not (grab.get("current") as Dictionary).is_empty(), "grab_style": str(grab.get("style")) if grab != null else "",
		"hud_hidden": bool(hud.call("hud_is_hidden")) if hud != null and hud.has_method("hud_is_hidden") else null,
		"death_flow": bool(hud.call("death_flow_active")) if hud != null and hud.has_method("death_flow_active") else null,
		"spectating": player.spectator_mode}
	var hunters := {}
	for key in (scene.get("_hunter_views") as Dictionary):
		var view := (scene.get("_hunter_views") as Dictionary)[key] as HunterView3D
		if view == null or not is_instance_valid(view) or view.brain == null:
			continue
		var brain := view.brain
		var beam := view.get("_kathy_beam") as SpotLight3D
		var chase: Object = view.get("_chase")
		var entry := {"id": brain.hunter_id, "state": HunterBrain.State.keys()[brain.state],
			"pos": [snappedf(view.global_position.x, .01), snappedf(view.global_position.z, .01)],
			"inspect": HunterBrain.Inspect.keys()[brain.inspect_phase] if brain.state == HunterBrain.State.INSPECT else "",
			"chase_style": str(brain.get("chase_style")), "chase_weight": snappedf(float(chase.get("weight")), .01) if chase != null else 0.0,
			"beam": beam != null and is_instance_valid(beam) and beam.is_visible_in_tree() and beam.light_energy > .01,
			"beam_energy": snappedf(beam.light_energy, .01) if beam != null and is_instance_valid(beam) else 0.0}
		if brain.gimmick is GlyraGimmick:
			entry["mood"] = MusicBoxes.Mood.keys()[(brain.gimmick as GlyraGimmick).mood]
		hunters[str(key)] = entry
	row["hunters"] = hunters
	var remotes := {}
	var remote_node: Object = scene.get("_remotes")
	if remote_node != null:
		var states: Dictionary = remote_node.get("_states")
		for id in states:
			var st: Dictionary = states[id]
			remotes[str(id)] = {"grab": st.get("grab", []), "hidden": st.get("hidden", null), "pos": str(st.get("position", ""))}
	row["remotes"] = remotes
	var boxes := {}
	var clocks: MusicBoxes = scene.get("_music_boxes")
	for node in scene.get_tree().get_nodes_in_group("interactable"):
		var it := node as RouteInteractable3D
		if it != null and it.kind == RouteInteractable3D.Kind.MUSIC_BOX and it.music_box_id != "" and clocks != null \
				and it.global_position.distance_to(player.global_position) < 40.0:
			boxes[it.music_box_id] = snappedf(clocks.seconds_left(it.music_box_id), .1)
	row["boxes"] = boxes
	return row


## B: walk-free wind of the nearest music box: put in front of it, faced at it, and its own interaction (what holding E calls).
static func _coop_wind(bridge: PlaytestBridge, scene: Node, player: PlayerController3D) -> Dictionary:
	var best: RouteInteractable3D = null
	var best_d := INF
	for node in scene.get_tree().get_nodes_in_group("interactable"):
		var it := node as RouteInteractable3D
		if it == null or it.kind != RouteInteractable3D.Kind.MUSIC_BOX or it.music_box_id == "" or absf(it.global_position.y - player.global_position.y) > 2.0:
			continue
		var d := it.global_position.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = it
	if best == null:
		return {"step": "wind", "ok": false, "why": "no music box on this storey in the loaded chunks"}
	var stand := _coop_stand(player, best.global_position)
	bridge.admin("teleport", {"x": stand.x, "y": stand.y, "z": stand.z})
	await _await_streamed(bridge.get_tree())
	var to := best.global_position - player.first_person_camera.global_position
	player._yaw = PlaytestFlythrough.yaw_for(to.x, to.z)
	player._pitch = PlaytestFlythrough.pitch_for(to.normalized())
	player._apply_look_rotation()
	var said := best.activate(player)
	return {"step": "wind", "ok": true, "box": best.music_box_id, "said": said, "epoch_ms": int(Time.get_unix_time_from_system() * 1000.0),
		"at": [snappedf(best.global_position.x, .1), snappedf(best.global_position.z, .1)]}


## C: into the nearest slatted hiding spot (a locker), through its own interaction.
static func _coop_hide(bridge: PlaytestBridge, scene: Node, player: PlayerController3D) -> Dictionary:
	var nav: StreamedHunterNavigation = scene.get("_navigation")
	var best: RouteInteractable3D = null
	var best_d := INF
	for node in scene.get_tree().get_nodes_in_group("interactable"):
		var it := node as RouteInteractable3D
		if it == null or it.kind != RouteInteractable3D.Kind.HIDING_SPOT or absf(it.global_position.y - player.global_position.y) > 2.0:
			continue
		var slatted := false
		if nav != null:
			for spot_value in nav.hiding_spots:
				var spot: Dictionary = spot_value
				if Vector2i(int(spot.get("x", 0)), int(spot.get("y", 0))) == Vector2i(floori(it.global_position.x), floori(it.global_position.z)):
					slatted = HunterInspect.slatted(String(spot.get("style", "")))
		var d := it.global_position.distance_to(player.global_position)
		if slatted and d < best_d:
			best_d = d
			best = it
	if best == null:
		return {"step": "hide", "ok": false, "why": "no slatted hiding spot on this storey in the loaded chunks"}
	var yaw := best.hiding_outward_yaw()
	var out_dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var stand := best.global_position + out_dir * .9
	bridge.admin("teleport", {"x": stand.x, "y": player.global_position.y, "z": stand.z})
	await _await_streamed(bridge.get_tree())
	var said := best.activate(player)
	for _i in 60:
		await bridge.get_tree().physics_frame
	return {"step": "hide", "ok": player.hidden, "said": said, "cell": [floori(best.global_position.x), floori(best.global_position.z)],
		"epoch_ms": int(Time.get_unix_time_from_system() * 1000.0)}


## Host: the Dovelle summoned beside C is sent to inspect C's locker, the way the route does when she passes one unseen
## (HunterInspect never finds the hider).
static func _coop_inspect(scene: Node, peer: int) -> Dictionary:
	var target: Dictionary = scene.call("_target_state_for_peer", peer)
	if target.is_empty():
		return {"step": "inspect", "ok": false, "why": "peer %d not found" % peer}
	var at: Vector2 = target.get("position", Vector2.ZERO)
	var view: HunterView3D = null
	var best := INF
	for key in (scene.get("_hunter_views") as Dictionary):
		var candidate := (scene.get("_hunter_views") as Dictionary)[key] as HunterView3D
		if candidate != null and candidate.brain != null and candidate.brain.hunter_id == "dovelle" and candidate.brain.position.distance_to(at) < best:
			best = candidate.brain.position.distance_to(at)
			view = candidate
	var nav: StreamedHunterNavigation = scene.get("_navigation")
	if view == null or nav == null:
		return {"step": "inspect", "ok": false, "why": "no Dovelle view near peer %d" % peer}
	var cell := Vector2i(floori(at.x), floori(at.y))
	for spot_value in nav.hiding_spots:
		var spot: Dictionary = spot_value
		if Vector2(Vector2i(int(spot.get("x", 0)), int(spot.get("y", 0)))).distance_to(Vector2(cell)) <= 1.5:
			var started := view.brain.start_inspect(spot.get("prop_at", at), HunterInspect.door_direction(float(spot.get("yaw", 0.0))), nav)
			return {"step": "inspect", "ok": started, "spot": [spot.get("x"), spot.get("y")], "dovelle_gap_m": snappedf(best, .1),
				"epoch_ms": int(Time.get_unix_time_from_system() * 1000.0)}
	return {"step": "inspect", "ok": false, "why": "no hiding spot at C's cell %s" % cell}


## A standing point 1.2 m from `target` on the side of open floor (four axis directions, chest-height ray).
static func _coop_stand(player: PlayerController3D, target: Vector3) -> Vector3:
	var space := player.get_world_3d().direct_space_state
	for dir in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var from: Vector3 = target + Vector3.UP * .8
		var ray := PhysicsRayQueryParameters3D.create(from, from + dir * 1.6)
		ray.exclude = [player.get_rid()]
		if space.intersect_ray(ray).is_empty():
			return Vector3(target.x, player.global_position.y, target.z) + dir * 1.2
	return Vector3(target.x + 1.2, player.global_position.y, target.z)


## After a teleport: frames until the storey around the runner has streamed in (facility.is_preloading() clear, at most 12 s), then
## 0.3 s more, so a screenshot or a "landed" check never sees a half-built storey (PERF: up to ~2 s in Mezzanine well columns,
## ~3.7 s on a first hop). `hold` runs every frame meanwhile (keep the runner in place under noclip).
static func _await_streamed(tree: SceneTree, hold: Callable = Callable()) -> int:
	var frames := 0
	var started := Time.get_ticks_msec()
	var clear_since := -1
	while Time.get_ticks_msec() - started < 12000:
		await tree.physics_frame
		frames += 1
		if hold.is_valid():
			hold.call()
		var scene := tree.current_scene
		var facility: Object = scene.get("facility") if scene != null else null
		var busy := facility != null and facility.has_method("is_preloading") and bool(facility.call("is_preloading"))
		if frames < 20 or busy:
			clear_since = -1
			continue
		if clear_since < 0:
			clear_since = Time.get_ticks_msec()
		if Time.get_ticks_msec() - clear_since >= 300:
			break
	return frames
