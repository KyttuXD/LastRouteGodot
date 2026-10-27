#!/usr/bin/env python3
"""Playtest swarm driver (runs on the dev Mac, the GAME runs on the test machines).

  tools/playtest/swarm.py --game last_route --scenario survive --seeds 8 --minutes 5 --machines mini,kt-bee
  tools/playtest/swarm.py --seeds ALPHA,BRAVO,CHARLIE --machines mini --parallel 4 --worktree .

Fans the seeds out over the machines (mini = KT-Mini4-2 via mini-run.sh, kt-bee / ak-bee = Windows PCs via win-run.sh), runs the
headless playtest runner there in parallel, pulls the reports back and writes one summary (summary.md / summary.json) under
.playtest-results/<timestamp>/ . Exit code 0 only when every run passed. Stdlib only. Never runs Godot on this machine.
"""
import argparse
import concurrent.futures
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

SETUP = Path(os.environ.get("PLAYTEST_TOOLS_DIR", "/Users/kyttu/Developer/Claude-Setup"))
MINI_RUN = os.environ.get("MINI_RUN", str(SETUP / "mini-run.sh"))
WIN_RUN = os.environ.get("WIN_RUN", str(SETUP / "win-run.sh"))
MACHINES = {"mini": ("mini", None), "kt-bee": ("win", "KT-BEE"), "ak-bee": ("win", "AK-BEE")}
DEFAULT_PARALLEL = {"mini": 5, "kt-bee": 6, "ak-bee": 4}
RESULT_LINE = re.compile(r"PLAYTEST (PASS|FAIL|SKIP): (.*)")


def runner_cmd(machine: str, worktree: str, lane: str, *args: str, nosync: bool = True) -> list:
    kind, host = MACHINES[machine]
    env_prefix = ["env", "NOSYNC=1"] if nosync else []
    if kind == "mini":
        return env_prefix + [MINI_RUN, worktree, lane, *args]
    return env_prefix + [WIN_RUN, host, worktree, lane, *args]


def godot_args(game, scenario, seed, minutes, name, extra):
    inner = (f"--fixed-fps 60 res://scenes/playtest_runner.tscn -- --playtest-runner --game={game} --scenario={scenario} "
             f"--seed={seed} --minutes={minutes} --name={name} {extra}").strip()
    return ["--godot", inner]


def run_job(job):
    machine, seed, args = job["machine"], job["seed"], job["args"]
    started = time.time()
    proc = subprocess.run(runner_cmd(machine, args["worktree"], args["lane"], *godot_args(args["game"], args["scenario"], seed, args["minutes"], job["name"], args["extra"])),
                          capture_output=True, text=True)
    out = proc.stdout + proc.stderr
    line = ""
    for found in RESULT_LINE.finditer(out):
        line = found.group(0)
    return {"machine": machine, "seed": seed, "name": job["name"], "exit": proc.returncode, "line": line,
            "wall": round(time.time() - started, 1), "tail": out.strip().splitlines()[-6:]}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--game", default="last_route")
    parser.add_argument("--scenario", default="survive")
    parser.add_argument("--seeds", default="4", help="a number (SEED1..SEEDn) or a comma list")
    parser.add_argument("--minutes", default="5", help="game minutes per run")
    parser.add_argument("--machines", default="mini", help="comma list of: " + ", ".join(MACHINES))
    parser.add_argument("--parallel", type=int, default=0, help="runs at once per machine (default per machine)")
    parser.add_argument("--worktree", default=".", help="repo/worktree to test (synced to the machines)")
    parser.add_argument("--lane", default="playtest-swarm")
    parser.add_argument("--extra", default="", help="extra runner options, e.g. '--target=30 --max-stuck=5'")
    parser.add_argument("--out", default="")
    args = parser.parse_args()

    seeds = [f"SEED{i + 1}" for i in range(int(args.seeds))] if args.seeds.isdigit() else args.seeds.split(",")
    machines = [m.strip() for m in args.machines.split(",") if m.strip()]
    for machine in machines:
        if machine not in MACHINES:
            print(f"unknown machine {machine}", file=sys.stderr)
            return 2
    stamp = time.strftime("%Y%m%d-%H%M%S")
    out_dir = Path(args.out or f".playtest-results/{stamp}_{args.game}_{args.scenario}")
    out_dir.mkdir(parents=True, exist_ok=True)

    # 1. sync + import once per machine (in parallel), 2. run jobs, 3. pull reports
    print(f"swarm: {len(seeds)} seeds on {machines}, {args.minutes} game minutes each -> {out_dir}")
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(machines)) as pool:
        prep = list(pool.map(lambda m: (m, subprocess.run(runner_cmd(m, args.worktree, args.lane, "--import", nosync=False), capture_output=True, text=True).returncode), machines))
    for machine, code in prep:
        print(f"  prepared {machine}: {'ok' if code == 0 else 'FAILED (' + str(code) + ')'}")
    machines = [m for m, code in prep if code == 0]
    if not machines:
        return 2
    jobs = []
    for index, seed in enumerate(seeds):
        machine = machines[index % len(machines)]
        jobs.append({"machine": machine, "seed": seed, "name": f"{args.game}_{args.scenario}_{seed}",
                     "args": {"worktree": args.worktree, "lane": args.lane, "game": args.game, "scenario": args.scenario,
                              "minutes": args.minutes, "extra": args.extra}})
    results = []
    executors = {m: concurrent.futures.ThreadPoolExecutor(max_workers=args.parallel or DEFAULT_PARALLEL[m]) for m in machines}
    futures = [executors[job["machine"]].submit(run_job, job) for job in jobs]
    for future in concurrent.futures.as_completed(futures):
        result = future.result()
        results.append(result)
        print(f"  [{result['machine']:6}] {result['seed']:10} exit={result['exit']} {result['wall']:6.1f}s  {result['line'][:150]}")
    for pool in executors.values():
        pool.shutdown()
    for machine in machines:
        dest = out_dir / machine
        subprocess.run(runner_cmd(machine, args.worktree, args.lane, "--pull", ".playtest", str(dest)), capture_output=True, text=True)

    summary = aggregate(out_dir, results, args)
    print(summary["markdown_head"])
    (out_dir / "summary.json").write_text(json.dumps(summary["data"], indent=2))
    (out_dir / "summary.md").write_text(summary["markdown"])
    print(f"summary: {out_dir / 'summary.md'}")
    return 0 if summary["data"]["all_passed"] else 1


def aggregate(out_dir: Path, results: list, args) -> dict:
    reports = []
    for path in sorted(out_dir.glob("*/**/report.json")):
        try:
            reports.append((path, json.loads(path.read_text())))
        except Exception:
            continue
    rows, problems, totals = [], {}, {"stuck": 0, "soft_locks": 0, "unreachable": 0, "errors": 0, "deaths": 0, "relays": 0}
    for path, report in reports:
        bot = report.get("bot", {})
        rows.append({"seed": report.get("seed"), "pass": report.get("pass"), "machine": report.get("machine"), "game_s": report.get("game_seconds"),
                     "deaths": bot.get("deaths", 0), "relays": bot.get("relays", 0), "chunks": bot.get("chunks_visited", 0), "stuck": bot.get("stuck_events", 0),
                     "soft_locks": bot.get("soft_locks", 0), "unreachable": bot.get("unreachable_goals", 0), "errors": report.get("log", {}).get("errors", 0),
                     "fps_p5": report.get("perf", {}).get("fps_p5"), "failures": report.get("failures", []), "dir": str(path.parent)})
        totals["stuck"] += bot.get("stuck_events", 0)
        totals["soft_locks"] += bot.get("soft_locks", 0)
        totals["unreachable"] += bot.get("unreachable_goals", 0)
        totals["errors"] += report.get("log", {}).get("errors", 0)
        totals["deaths"] += bot.get("deaths", 0)
        totals["relays"] += bot.get("relays", 0)
        for event in report.get("events", []):
            if event.get("kind") in ("stuck", "soft_lock", "unreachable_goal", "door_failed", "interact_failed"):
                at = event.get("at") or event.get("to") or event.get("from") or []
                key = (report.get("seed"), event["kind"], tuple(round(float(v)) for v in at[:3]) if at else ())
                problems.setdefault(key, event)
        for line in report.get("log_lines", [])[:5]:
            problems.setdefault(("log", line.get("text", "")[:80]), line)
    failed_runs = [r for r in results if r["exit"] not in (0,)]
    all_passed = bool(rows) and all(r["pass"] for r in rows) and not [r for r in results if r["exit"] == 2]
    lines = [f"# Playtest swarm: {args.game} / {args.scenario}", "",
             f"{len(rows)} reports from {len(results)} runs, {args.minutes} game minutes each. **{'ALL PASSED' if all_passed else 'FAILURES'}**", "",
             "| seed | result | machine | deaths | relays | chunks | stuck | soft-locks | unreachable | errors | fps p5 |", "|---|---|---|---|---|---|---|---|---|---|---|"]
    for row in rows:
        lines.append(f"| {row['seed']} | {'PASS' if row['pass'] else 'FAIL'} | {row['machine']} | {row['deaths']} | {row['relays']} | {row['chunks']} | {row['stuck']} | {row['soft_locks']} | {row['unreachable']} | {row['errors']} | {row['fps_p5']} |")
    lines += ["", f"Totals: stuck spots {totals['stuck']}, soft-locks {totals['soft_locks']}, unreachable goals {totals['unreachable']}, engine errors {totals['errors']}, deaths {totals['deaths']}, relays {totals['relays']}", ""]
    if problems:
        lines.append("## Distinct problems")
        for key, event in list(problems.items())[:60]:
            lines.append(f"- `{key[0]}` {event.get('kind', '')} {json.dumps({k: v for k, v in event.items() if k not in ('frame',)})[:220]}")
        lines.append("")
    if failed_runs:
        lines.append("## Runs with a non-zero exit")
        for run in failed_runs:
            lines.append(f"- {run['machine']} {run['seed']} exit {run['exit']}: {run['line'] or ' | '.join(run['tail'])[:240]}")
    markdown = "\n".join(lines)
    return {"markdown": markdown, "markdown_head": "\n".join(lines[:16]), "data": {"rows": rows, "totals": totals, "all_passed": all_passed,
            "problems": [list(map(str, k)) + [event] for k, event in problems.items()]}}


if __name__ == "__main__":
    sys.exit(main())
