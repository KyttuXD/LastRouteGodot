#!/usr/bin/env python3
"""Check stream_bench results against the budgets in tools/build/perf_budgets.json.

    python3 tools/build/perf_report.py [--profile air|proxy] [--budgets FILE] DIR_OR_JSON [...]

Reads every stream_bench_*.json (written by dev/look/stream_bench.gd) under the given paths and prints one
PASS/FAIL line per metric, then a verdict per file. Exit code 1 if any file fails. Python 3.8+, no dependencies.
"""
import argparse
import json
import os
import sys


def find_jsons(paths):
    out = []
    for p in paths:
        if os.path.isdir(p):
            for root, _dirs, files in os.walk(p):
                out += [os.path.join(root, f) for f in files if f.startswith("stream_bench_") and f.endswith(".json")]
        elif p.endswith(".json"):
            out.append(p)
    return sorted(out)


def checks(summary, b):
    frames = max(int(summary.get("frames", 0)), 1)
    peak = summary.get("peak", {})
    mean = summary.get("mean", {})
    trips = summary.get("trips", [])
    worst_trip = max([t.get("max_ms", 0.0) for t in trips], default=0.0)
    rows = [
        ("avg fps", summary.get("avg_fps", 0.0), ">=", b["avg_fps_min"]),
        ("1% low fps", summary.get("low1_fps", 0.0), ">=", b["low1_fps_min"]),
        ("p95 ms", summary.get("p95_ms", 0.0), "<=", b["p95_ms_max"]),
        ("p99 ms", summary.get("p99_ms", 0.0), "<=", b["p99_ms_max"]),
        ("max frame ms", summary.get("max_ms", 0.0), "<=", b["max_ms_max"]),
        ("hitch share (>33 ms)", summary.get("hitches_33", 0) / frames, "<=", b["hitch_share_max"]),
        ("draw calls (mean)", mean.get("draw_calls", 0.0), "<=", b["draw_calls_mean_max"]),
        ("visible lights (peak)", peak.get("lights_visible", 0.0), "<=", b["lights_visible_peak_max"]),
        ("memory MB (peak)", peak.get("mem_mb", 0.0), "<=", b["mem_mb_peak_max"]),
        ("memory growth MB", summary.get("mem_growth_mb", 0.0), "<=", b["mem_growth_mb_max"]),
    ]
    if trips:
        rows.append(("worst level-change frame ms", worst_trip, "<=", b["trip_max_ms_max"]))
    if summary.get("mode") == "play":
        # a play run that collected nothing or never switched the flashlight on measured nothing: fail loudly
        rows.append(("relays collected (>=1)", summary.get("collects", 0), ">=", 1))
        rows.append(("flashlight on (1=yes)", 1.0 if summary.get("flashlight_on") else 0.0, ">=", 1))
        rows.append(("worst relay-collect frame ms", summary.get("collect_frame_ms", summary.get("collect_frame_ms_max", 0.0)), "<=", b["collect_frame_ms_max"]))
    if summary.get("mode") == "flashlight":
        rows.append(("worst flashlight-toggle frame ms", summary.get("toggle_frame_ms_max", 0.0), "<=", b["toggle_frame_ms_max"]))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--profile", default="air", choices=["air", "proxy"])
    ap.add_argument("--budgets", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "perf_budgets.json"))
    args = ap.parse_args()
    with open(args.budgets, encoding="utf-8") as f:
        budgets = json.load(f)[args.profile]
    files = find_jsons(args.paths)
    if not files:
        print("no stream_bench_*.json found", file=sys.stderr)
        return 2
    failed_any = False
    for path in files:
        with open(path, encoding="utf-8") as f:
            summary = json.load(f)["summary"]
        print("== %s  (mode=%s speed=%s seconds=%s, profile=%s)" % (
            path, summary.get("mode"), summary.get("speed"), summary.get("seconds"), args.profile))
        bad = 0
        for name, value, op, limit in checks(summary, budgets):
            ok = value >= limit if op == ">=" else value <= limit
            bad += 0 if ok else 1
            print("  %s  %-30s %10.2f %s %g" % ("PASS" if ok else "FAIL", name, value, op, limit))
        print("  -> %s" % ("PASS" if bad == 0 else "FAIL (%d metric%s)" % (bad, "" if bad == 1 else "s")))
        failed_any = failed_any or bad > 0
    return 1 if failed_any else 0


if __name__ == "__main__":
    sys.exit(main())
