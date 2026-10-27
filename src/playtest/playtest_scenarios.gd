class_name PlaytestScenarios
extends RefCounted

## Scenario loops. Each runs the bot frame by frame (observe -> decide -> inject) until its goal, a time limit, or the end of the run.

const SAMPLE_EVERY := 30


static func play(bridge: PlaytestBridge, adapter: BotAdapter, opts: Dictionary, report: Dictionary) -> Dictionary:
	var tree := bridge.get_tree()
	var scenario := String(opts["scenario"])
	var start := await bridge.start_run({"game": adapter.game_id, "seed": opts["seed"], "difficulty": opts["difficulty"],
		"bot_seed": opts["bot_seed"], "debug": true})
	if not bool(start.get("ok", false)):
		return {"scenario_failure": "start_run failed: %s" % start.get("error", "?"), "outcome": "error", "game_seconds": 0.0, "frames": 0}
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
	while frames < limit_frames:
		await tree.physics_frame
		frames += 1
		var obs := bridge.observe()
		if frames % SAMPLE_EVERY == 0 and float(obs.get("fps", 0.0)) > 0.0:
			fps.append(float(obs["fps"]))
			frame_ms.append(float(obs["frame_ms"]))
		var over := adapter.run_over(obs)
		if over and not last_over:
			var death: Dictionary = obs.get("run", {}).get("death", {})
			deaths.append({"t": snappedf(frames * delta, .1), "hunter": String(death.get("by", death.get("hunter", death.get("hunter_id", "?")))),
				"cause": String(death.get("cause", death.get("kind", ""))), "depth": int(obs["run"].get("depth", 1))})
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
			outcome = "died"
			break
		last_over = over
		var act := adapter.decide(obs, delta)
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
	var summary: Dictionary = {"outcome": outcome, "game_seconds": snappedf(frames * delta, .1), "frames": frames,
		"perf": PlaytestReporter.perf_summary(fps, frame_ms), "deaths": deaths, "scenario_failure": failure}
	return summary


static func menu_tour(bridge: PlaytestBridge, adapter: BotAdapter, opts: Dictionary, report: Dictionary) -> Dictionary:
	return {"scenario_failure": "menu_tour is added in stage 3", "outcome": "error", "game_seconds": 0.0, "frames": 0}
