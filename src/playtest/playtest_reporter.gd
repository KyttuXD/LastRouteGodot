class_name PlaytestReporter
extends RefCounted

## Turns a finished scenario into report.json + report.md (and events.jsonl) and decides pass/fail against thresholds.

const DEFAULT_LIMITS := {"max_stuck": 3, "max_soft_locks": 0, "max_errors": 0, "max_unreachable": 6, "min_fps": 0.0, "max_pitch_median_deg": 15.0}


static func evaluate(report: Dictionary, limits: Dictionary) -> Array:
	var failures: Array = []
	var bot: Dictionary = report.get("bot", {})
	if int(bot.get("soft_locks", 0)) > int(limits["max_soft_locks"]):
		failures.append("soft_locks %d > %d" % [int(bot.get("soft_locks", 0)), int(limits["max_soft_locks"])])
	if int(bot.get("stuck_events", 0)) > int(limits["max_stuck"]):
		failures.append("stuck_events %d > %d" % [int(bot.get("stuck_events", 0)), int(limits["max_stuck"])])
	if int(bot.get("unreachable_goals", 0)) > int(limits["max_unreachable"]):
		failures.append("unreachable_goals %d > %d" % [int(bot.get("unreachable_goals", 0)), int(limits["max_unreachable"])])
	var log_errors := int(report.get("log", {}).get("errors", 0))
	if log_errors > int(limits["max_errors"]):
		failures.append("engine errors %d > %d" % [log_errors, int(limits["max_errors"])])
	# a bot that walks looking at the floor or the ceiling draws a different game (KT: every tester stared down)
	var median: Variant = pitch_median(bot.get("pitch_hist", {}))
	if median != null:
		bot["pitch_median_deg"] = median
		if absf(float(median)) > float(limits["max_pitch_median_deg"]):
			failures.append("camera pitch median %d deg, more than %d from level" % [int(median), int(limits["max_pitch_median_deg"])])
	if report.get("scenario_failure", "") != "":
		failures.append(String(report["scenario_failure"]))
	var fps_p5 := float(report.get("perf", {}).get("fps_p5", 0.0))
	if float(limits["min_fps"]) > 0.0 and fps_p5 > 0.0 and fps_p5 < float(limits["min_fps"]):
		failures.append("fps p5 %.1f < %.1f" % [fps_p5, float(limits["min_fps"])])
	return failures


## The median of a whole-degree histogram {"-3": frames, ...}, or null when it is empty.
static func pitch_median(hist: Dictionary) -> Variant:
	var total := 0
	for key in hist:
		total += int(hist[key])
	if total == 0:
		return null
	var degrees: Array = hist.keys().map(func(k: Variant) -> int: return int(k))
	degrees.sort()
	var seen := 0
	for deg in degrees:
		seen += int(hist[str(deg)])
		if seen * 2 >= total:
			return deg
	return degrees[-1]


static func perf_summary(fps: Array, frame_ms: Array) -> Dictionary:
	if fps.is_empty():
		return {}
	var sorted_fps := fps.duplicate()
	sorted_fps.sort()
	var sorted_ms := frame_ms.duplicate()
	sorted_ms.sort()
	var avg := 0.0
	for value in fps:
		avg += float(value)
	return {"fps_avg": snappedf(avg / fps.size(), .1), "fps_p5": float(sorted_fps[int(sorted_fps.size() * .05)]),
		"frame_ms_p95": float(sorted_ms[mini(sorted_ms.size() - 1, int(sorted_ms.size() * .95))]),
		"frame_ms_max": float(sorted_ms[-1]), "samples": fps.size()}


static func write(out_dir: String, report: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var json_path := out_dir.path_join("report.json")
	var file := FileAccess.open(json_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	var md := FileAccess.open(out_dir.path_join("report.md"), FileAccess.WRITE)
	if md != null:
		md.store_string(markdown(report))
		md.close()
	var events := FileAccess.open(out_dir.path_join("events.jsonl"), FileAccess.WRITE)
	if events != null:
		for event in report.get("events", []):
			events.store_line(JSON.stringify(event))
		events.close()
	return json_path


static func markdown(report: Dictionary) -> String:
	var bot: Dictionary = report.get("bot", {})
	var lines: PackedStringArray = []
	lines.append("# Playtest: %s / %s" % [report.get("game", "?"), report.get("scenario", "?")])
	lines.append("")
	lines.append("**Result: %s**  seed `%s`  difficulty %s  machine `%s`" % [
		"PASS" if bool(report.get("pass", false)) else "FAIL", report.get("seed", ""), report.get("difficulty", ""), report.get("machine", "")])
	lines.append("")
	if not (report.get("failures", []) as Array).is_empty():
		lines.append("## Failures")
		for failure in report["failures"]:
			lines.append("- %s" % failure)
		lines.append("")
	lines.append("## Summary")
	lines.append("- game time: %.1f s (%d frames), wall time %.1f s" % [report.get("game_seconds", 0.0), report.get("frames", 0), report.get("wall_seconds", 0.0)])
	lines.append("- outcome: %s, deaths %d, max depth %d, relays %d" % [report.get("outcome", "?"), int(bot.get("deaths", 0)), int(bot.get("max_depth", 1)), int(bot.get("relays", 0))])
	lines.append("- distance %.0f m, chunks visited %d" % [float(bot.get("distance_m", 0.0)), int(bot.get("chunks_visited", 0))])
	lines.append("- stuck events %d, soft-locks %d, unreachable goals %d, failed interactions %d" % [int(bot.get("stuck_events", 0)), int(bot.get("soft_locks", 0)), int(bot.get("unreachable_goals", 0)), int(bot.get("interact_failures", 0))])
	var perf: Dictionary = report.get("perf", {})
	if not perf.is_empty():
		lines.append("- perf: fps avg %.1f, p5 %.1f, frame p95 %.1f ms, max %.1f ms" % [perf.get("fps_avg", 0.0), perf.get("fps_p5", 0.0), perf.get("frame_ms_p95", 0.0), perf.get("frame_ms_max", 0.0)])
	var log: Dictionary = report.get("log", {})
	lines.append("- engine log: %d errors, %d warnings" % [int(log.get("errors", 0)), int(log.get("warnings", 0))])
	lines.append("")
	var deaths: Array = report.get("deaths", [])
	if not deaths.is_empty():
		lines.append("## Deaths")
		for death in deaths:
			lines.append("- t=%.1f s by `%s` (%s)" % [float(death.get("t", 0.0)), death.get("hunter", "?"), death.get("cause", "")])
		lines.append("")
	var events: Array = report.get("events", [])
	var interesting: Array = events.filter(func(e): return String(e.get("kind", "")) in ["stuck", "soft_lock", "unreachable_goal", "interact_failed"])
	if not interesting.is_empty():
		lines.append("## Problems (first 30)")
		for event in interesting.slice(0, 30):
			lines.append("- `%s` frame %d %s" % [event.get("kind", ""), int(event.get("frame", 0)), JSON.stringify(event)])
		lines.append("")
	var errors: Array = report.get("log_lines", [])
	if not errors.is_empty():
		lines.append("## Engine errors/warnings (first 30)")
		for entry in errors.slice(0, 30):
			lines.append("- [%s] %s" % [entry.get("kind", ""), entry.get("text", "")])
		lines.append("")
	return "\n".join(lines)
