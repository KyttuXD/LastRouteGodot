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
	while frames < limit_frames:
		await tree.physics_frame
		frames += 1
		var obs := bridge.observe()
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
		if not await wait_for.call(func(): return RoomState.online and RoomState.peers.size() >= 2, "joining the room (never connected to the host: relay/ENet)", 30.0):
			return {"outcome": "error", "game_seconds": 0.0, "frames": 0, "scenario_failure": "%s; peers=%d online=%s" % [report.get("scenario_failure", ""), RoomState.peers.size(), RoomState.online]}
	bridge.status = "coop_bot %s waiting for the route scene" % role
	if not await wait_for.call(func(): return _scene(bridge) == "infinite_route_test.tscn", "the route scene", 90.0):
		return {"outcome": "error", "game_seconds": 0.0, "frames": 0, "scenario_failure": String(report.get("scenario_failure", ""))}
	if role == "guest":
		if not await wait_for.call(func(): return not bool(tree.current_scene.get("_awaiting_snapshot")), "the host snapshot", 60.0):
			return {"outcome": "error", "game_seconds": 0.0, "frames": 0, "scenario_failure": String(report.get("scenario_failure", ""))}
	adapter.attach()
	for _i in 60:
		await tree.physics_frame
	report["role"] = role
	return await run_loop(bridge, adapter, opts, report)


## probe: start a run, teleport to --probe-x/--probe-z, wait for the chunk to stream in, then take four screenshots turning 90 degrees
## each time and list what is nearby. For looking at a stuck spot a bot found (needs a windowed run to get images).
static func probe(bridge: PlaytestBridge, adapter: BotAdapter, opts: Dictionary, report: Dictionary) -> Dictionary:
	var tree := bridge.get_tree()
	var start := await bridge.start_run({"game": adapter.game_id, "seed": opts["seed"], "difficulty": opts["difficulty"], "bot_seed": opts["bot_seed"], "debug": true})
	if not bool(start.get("ok", false)):
		return {"scenario_failure": "start_run failed: %s" % start.get("error", "?"), "outcome": "error", "game_seconds": 0.0, "frames": 0}
	var obs := bridge.observe()
	var y: float = float(obs["player"]["pos"][1])
	var result := bridge.admin("teleport", {"x": float(opts["probe_x"]), "y": y, "z": float(opts["probe_z"])})
	var frames := 0
	for _i in 120:
		await tree.physics_frame
		frames += 1
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
