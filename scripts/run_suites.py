#!/usr/bin/env python3
"""Run the headless validator suites in parallel Godot processes and print one summary.

    python3 scripts/run_suites.py [--jobs N] [--backend] [--affected BASE_LIST] [suite ...]

With no suites, runs every suite in scripts/validate_runner.gd (the same set as
`validate.tscn` with no arguments). Each worker runs in its own APFS/copy clone of the
project (so res:// writes cannot clash), its own HOME (so user:// is private), its own
TMPDIR and its own VALIDATE_PORT_OFFSET (so ENet test ports cannot clash).

Suites are packed heaviest-first into N bins from the durations recorded by earlier runs
(.validate_timings.json, falling back to the median). A worker that dies mid-bin does not
take the rest of its bin with it: every suite without a verdict line is rerun alone once.

Trust rules: a suite PASSES only on its own `-- suite NAME PASS` line from the runner.
A missing verdict, a crash, a timeout or a parse error is a FAIL. Any FAIL -> exit 1.
Python 3.9 compatible (the mini's system python).
"""
import argparse
import json
import os
import re
import shutil
import statistics
import subprocess
import sys
import tempfile
import threading
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TIMINGS = os.environ.get("VALIDATE_TIMINGS") or os.path.join(ROOT, ".validate_timings.json")
# Suites that measure frame time or wall-clock budgets: they gave false spikes when run
# beside other work, so they run alone, one after another, after the parallel phase.
SERIAL = {"stream_perf", "prop_perf", "idle_stability", "quality_tiers", "lods"}
VERDICT = re.compile(r"^-- suite (\S+) (PASS|FAIL) ([0-9.]+)s")
# Compile/load errors. A GDScript runtime error does not stop a suite: the failing call just returns its default (0
# failures), so a broken project could print "PASS". None of these lines appear in a healthy full run (checked against
# the 2026-10-28 baseline), so any of them turns the suite it appears in -- or, before the first suite, every suite of
# that process -- into a FAIL. Plain "ERROR:" lines are NOT used: a healthy run prints dozens of them.
COMPILE_ERROR = re.compile(r"SCRIPT ERROR|Parse Error|Failed to load script|Compile Error|res://\S+:\d+ - ")


# Legacy names old lane trees still pass (validate_runner.gd SUITE_ALIASES): "biomes" became the four region shards.
ALIASES = {"biomes": ["regions_hospital", "regions_lab", "regions_greenhouse", "regions_mall"]}


def expand_aliases(names):
    out = []
    for n in names:
        out.extend(ALIASES.get(n.split("#")[0], [n]))
    return out


def all_suites():
    text = open(os.path.join(ROOT, "scripts", "validate_runner.gd")).read()
    block = re.search(r"const SUITES := \[(.*?)\]", text, re.S).group(1)
    return re.findall(r'"([^"]+)"', block)


def affected_suites(changed, known):
    """Map changed repo paths to suites: a suite's own script, or any suite whose script
    names the changed file (res:// path, file stem or its class_name). Heuristic and only
    for quick feedback -- the full run stays the push gate."""
    texts = {}
    for s in known:
        try:
            texts[s] = open(os.path.join(ROOT, "scripts", "validate_%s.gd" % s)).read()
        except OSError:
            texts[s] = ""
    autoloads = dict((m.group(2), m.group(1)) for m in re.finditer(
        r'^(\w+)="\*?res://([^"]+)"', open(os.path.join(ROOT, "project.godot")).read(), re.M))
    hit = []
    for path in changed:
        m = re.match(r"scripts/validate_(\w+)\.gd$", path)
        if m and m.group(1) in known:
            hit.append(m.group(1))
            continue
        needles = {"res://" + path, os.path.splitext(os.path.basename(path))[0], autoloads.get(path, "")}
        try:
            cn = re.search(r"^class_name\s+(\w+)", open(os.path.join(ROOT, path)).read(), re.M)
            if cn:
                needles.add(cn.group(1))
        except (OSError, UnicodeDecodeError):
            pass
        needles = {n for n in needles if len(n) > 3}
        for s, t in texts.items():
            if any(re.search(r"\b%s\b" % re.escape(n), t) for n in needles):
                hit.append(s)
    return [s for s in known if s in set(hit)]


def godot_bin():
    path = os.environ.get("GODOT_BIN") or shutil.which("godot4") or shutil.which("godot")
    if not path:
        sys.exit("Godot not found. Set GODOT_BIN.")
    return path


def clone_project(dst):
    """Copy-on-write clone on APFS (cp -c); plain copy elsewhere. Includes .godot."""
    if sys.platform == "darwin" and subprocess.call(["cp", "-cR", ROOT + "/.", dst]) == 0:
        return
    shutil.copytree(ROOT, dst, dirs_exist_ok=True, ignore=shutil.ignore_patterns(".git", "build", ".playtest"))


def collect_crash_markers(home):
    """What CrashWatch (src/autoload/crash_watch.gd) left in a run's user://: the session sentinel (Godot did not quit
    cleanly: crash or kill), an unrecovered freeze dump, and queued reports (a freeze it came back from, or an earlier
    crash it found at boot). Returned as one line each and removed, so the next run starts clean."""
    found = []
    for dirpath, _dirs, files in os.walk(home):
        for name in sorted(files):
            path = os.path.join(dirpath, name)
            if name == "crashwatch_session.json":
                kind = "crash: did not quit cleanly"
            elif name == "crashwatch_freeze.json":
                kind = "freeze: main loop stalled and never came back"
            elif os.path.basename(dirpath) == "crash_queue" and name.endswith(".json"):
                kind = "report: %s" % name.rsplit("-", 1)[-1][:-5]
            else:
                continue
            detail = ""
            try:
                with open(path, encoding="utf-8") as f:
                    data = json.load(f)
                crumbs = [str(c) for c in data.get("breadcrumbs", [])][-3:]
                if crumbs:
                    detail = " | last: " + " / ".join(c[:80] for c in crumbs)
            except (OSError, ValueError, AttributeError):
                pass
            found.append(kind + detail)
            try:
                os.remove(path)
            except OSError:
                pass
    return found


class Worker:
    def __init__(self, idx, base):
        self.idx = idx
        self.dir = os.path.join(base, "w%d" % idx)
        self.proj = os.path.join(self.dir, "proj")
        os.makedirs(os.path.join(self.dir, "home"))
        os.makedirs(os.path.join(self.dir, "tmp"))
        os.makedirs(self.proj)
        clone_project(self.proj)
        self.env = dict(os.environ)
        self.crash_markers = []   # [(suites, marker line)], from collect_crash_markers after each Godot run
        home, tmp = os.path.join(self.dir, "home"), os.path.join(self.dir, "tmp")
        # user:// lives under HOME (macOS), XDG_DATA_HOME (Linux) or APPDATA (Windows): move all three
        self.env.update(HOME=home, XDG_DATA_HOME=home, APPDATA=home, TMPDIR=tmp, TEMP=tmp, TMP=tmp,
                        VALIDATE_PORT_OFFSET=str(100 + 37 * idx))

    def run(self, suites, timeout, log_path):
        """Run suites in one Godot process. Returns ({suite: (verdict, secs)}, {suite: [lines]}, rc)."""
        cmd = [godot_bin(), "--headless", "--path", self.proj, "res://scenes/validate.tscn", "--"] + suites
        env = dict(self.env, VALIDATE_TIMEOUT=str(timeout))
        verdicts, lines_by, current = {}, {}, None
        with open(log_path, "a") as log:
            log.write("$ %s\n" % " ".join(cmd))
            proc = subprocess.Popen(cmd, cwd=self.proj, env=env, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace", **_group_kwargs())
            killer = threading.Timer(timeout + 60, lambda: _kill_group(proc))
            killer.start()
            state = {"last": time.time(), "stalled": False}
            watcher = threading.Thread(target=_stall_watch, args=(proc, state), daemon=True)
            watcher.start()
            broken, preamble = {}, []
            written, flooded = 0, False
            for line in proc.stdout:
                state["last"] = time.time()
                if flooded:
                    continue   # drain the pipe until the killed process closes it; write nothing more
                written += len(line)
                if written > LOG_CAP:
                    flooded = True
                    log.write("\n[run_suites] log flood: over %d MB; killing this Godot\n" % (LOG_CAP // 1048576))
                    _kill_group(proc)
                    if current and current not in verdicts:
                        verdicts[current] = ("FAIL", 0.0)
                        lines_by.setdefault(current, []).append(
                            "  FAIL  log flood: over %d MB of output (a per-frame error?); killed. Last line: %s"
                            % (LOG_CAP // 1048576, line.strip()[:200]))
                        print("[w%d] FAIL %s (log flood)" % (self.idx, current), flush=True)
                    continue
                log.write(line)
                stripped = line.rstrip("\n")
                if stripped.startswith("== ") and stripped[3:] in suites:
                    current = stripped[3:]
                m = VERDICT.match(stripped)
                if m:
                    verdicts[m.group(1)] = (m.group(2), float(m.group(3)))
                    print("[w%d] %s %s %ss" % (self.idx, m.group(2), m.group(1), m.group(3)), flush=True)
                if COMPILE_ERROR.search(stripped):
                    if current:
                        broken.setdefault(current, []).append(stripped)
                    else:
                        preamble.append(stripped)
                if current and ("FAIL" in stripped or "SCRIPT ERROR" in stripped or "ERROR:" in stripped):
                    lines_by.setdefault(current, []).append(stripped)
            rc = proc.wait()
            killer.cancel()
            state["done"] = True
            for marker in collect_crash_markers(os.path.join(self.dir, "home")):
                self.crash_markers.append((list(suites), marker))
                print("[w%d] CRASHMARK %s: %s" % (self.idx, ",".join(suites)[:120], marker), flush=True)
            if state["stalled"] and current and current not in verdicts:
                # a blocking Godot ALERT (or any hang without CPU use) inside this suite: a test FAIL, not a hang
                verdicts[current] = ("FAIL", 0.0)
                lines_by.setdefault(current, []).append(
                    "  FAIL  STALL: no output for %ds and no CPU use (blocking Godot ALERT?); killed" % STALL)
                print("[w%d] FAIL %s (stall)" % (self.idx, current), flush=True)
            # compile/load errors override a PASS: before the first suite they hit every suite this process ran
            for suite in suites:
                errors = (preamble + broken.get(suite, [])) if suite in verdicts else broken.get(suite, [])
                if errors and verdicts.get(suite, ("", 0))[0] == "PASS":
                    verdicts[suite] = ("FAIL", verdicts[suite][1])
                    lines_by.setdefault(suite, []).extend(
                        ["  FAIL  compile/load error while this suite ran (a PASS here would be false):"] + errors[:10])
                    print("[w%d] FAIL %s (compile/load error)" % (self.idx, suite), flush=True)
        return verdicts, lines_by, rc


STALL = int(os.environ.get("GUARD_STALL_INNER", "30"))
# A per-frame SCRIPT ERROR once wrote 63 GB into one worker log and filled the mini's disk. Past this many bytes a
# worker's output is a flood: the suite is killed and FAILs as "log flood".
LOG_CAP = int(os.environ.get("VALIDATE_LOG_CAP_MB", "50")) * 1024 * 1024
KEEP_LOG_BYTES = 1024 * 1024   # trimmed tail of each worker log kept in <project>/.validate-logs after the run
SWEEP_AGE_S = 2 * 3600


def _pid_alive(pid):
    if pid <= 0:
        return False
    if os.name == "nt":
        out = subprocess.run(["tasklist", "/FI", "PID eq %d" % pid, "/NH"], capture_output=True, text=True).stdout
        return str(pid) in out
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def _remove_tree(path):
    """rmtree that also works on Windows, where read-only files (the project clone's) make plain rmtree fail -- and
    ignore_errors hid that, so Windows run folders piled up in %TEMP%."""
    import stat

    def clear_and_retry(func, target, _exc):
        try:
            os.chmod(target, stat.S_IWRITE)
            func(target)
        except OSError:
            pass
    shutil.rmtree(path, onerror=clear_and_retry)


def sweep_old_runs():
    """Remove lr-validate-* run folders older than 2 h whose owning run_suites is gone (crashed or killed runs)."""
    root = tempfile.gettempdir()
    now = time.time()
    for name in os.listdir(root):
        if not name.startswith("lr-validate-"):
            continue
        path = os.path.join(root, name)
        try:
            if not os.path.isdir(path):
                continue
            # age = newest write anywhere in it: a live run keeps appending to its logs (the folder's own mtime doesn't
            # move), and a run started by an older run_suites has no .owner-pid to protect it
            newest = os.path.getmtime(path)
            for sub in (path, os.path.join(path, "logs")):
                for entry in os.listdir(sub) if os.path.isdir(sub) else []:
                    try:
                        newest = max(newest, os.path.getmtime(os.path.join(sub, entry)))
                    except OSError:
                        pass
            if now - newest < SWEEP_AGE_S:
                continue
            owner = 0
            try:
                owner = int(open(os.path.join(path, ".owner-pid")).read().strip() or 0)
            except (OSError, ValueError):
                pass
            if _pid_alive(owner):
                continue
            _remove_tree(path)
            print("swept stale run folder %s%s" % (path, "" if not os.path.exists(path) else " (partly: files in use)"), flush=True)
        except OSError:
            continue


def keep_trimmed_logs(logs_dir):
    """Copy the tail of each worker log into <project>/.validate-logs (replaced every run), so the temp folder can go."""
    keep = os.path.join(ROOT, ".validate-logs")
    shutil.rmtree(keep, ignore_errors=True)
    os.makedirs(keep, exist_ok=True)
    for name in sorted(os.listdir(logs_dir)) if os.path.isdir(logs_dir) else []:
        src = os.path.join(logs_dir, name)
        with open(src, "rb") as f:
            f.seek(max(0, os.path.getsize(src) - KEEP_LOG_BYTES))
            tail = f.read()
        with open(os.path.join(keep, name), "wb") as out:
            out.write(tail)
    return keep


def _cpu_seconds(pid):
    """CPU seconds of every process in pid's process group (POSIX), None where not measurable."""
    if os.name == "nt":
        return None
    try:
        out = subprocess.run(["ps", "-A", "-o", "pgid=,time="], capture_output=True, text=True).stdout
    except OSError:
        return None
    total = 0.0
    for row in out.splitlines():
        parts = row.split()
        if len(parts) != 2 or parts[0] != str(pid):
            continue
        m = re.match(r"(?:(\d+)-)?(?:(\d+):)?(\d+):(\d+(?:\.\d+)?)$", parts[1])
        if m:
            total += int(m.group(1) or 0) * 86400 + int(m.group(2) or 0) * 3600 + int(m.group(3)) * 60 + float(m.group(4))
    return total


def _stall_watch(proc, state):
    """Kill this Godot (its own group) when it prints nothing for STALL s and its CPU time stops growing.
    Windows is covered by the outer guard.ps1, which measures the whole process tree."""
    if STALL <= 0 or os.name == "nt":
        return
    cpu_mark = None
    while proc.poll() is None and not state.get("done"):
        time.sleep(5)
        quiet = time.time() - state["last"]
        if quiet < STALL / 2:
            cpu_mark = None
            continue
        if cpu_mark is None:
            cpu_mark = _cpu_seconds(proc.pid)
            continue
        if quiet >= STALL:
            now = _cpu_seconds(proc.pid)
            if now is not None and now - cpu_mark < 0.3:
                state["stalled"] = True
                _kill_group(proc)
                return
            state["last"] = time.time()
            cpu_mark = None


def _group_kwargs():
    if os.name == "nt":
        return {"creationflags": subprocess.CREATE_NEW_PROCESS_GROUP}
    return {"start_new_session": True}


def _kill_group(proc):
    """Kill exactly this Godot and its children, by its own PID / process group."""
    try:
        if os.name == "nt":
            subprocess.call(["taskkill", "/PID", str(proc.pid), "/T", "/F"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        else:
            os.killpg(proc.pid, 9)  # the group we created for exactly this Godot (start_new_session)
    except OSError:
        pass


def pack(suites, durations, n):
    known = [durations[s] for s in suites if s in durations]
    default = statistics.median(known) if known else 10.0
    order = sorted(suites, key=lambda s: -durations.get(s, default))
    bins = [[0.0, []] for _ in range(n)]
    for s in order:
        b = min(bins, key=lambda x: x[0])
        b[0] += durations.get(s, default)
        b[1].append(s)
    return [b[1] for b in bins if b[1]]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("suites", nargs="*")
    ap.add_argument("--jobs", type=int, default=int(os.environ.get("VALIDATE_JOBS", "5")))
    ap.add_argument("--backend", action="store_true", help="also run the node backend tests (as validate_all.sh does)")
    ap.add_argument("--timeout", type=int, default=int(os.environ.get("MINI_TIMEOUT", "1500")))
    ap.add_argument("--no-serial", action="store_true", help="run perf suites in the pool too (faster, noisier)")
    ap.add_argument("--affected", help="file listing changed repo paths; run only suites that touch them")
    ap.add_argument("--json", help="write the per-suite results here")
    args = ap.parse_args()

    known = all_suites()
    wanted = expand_aliases(args.suites) if args.suites else known
    if args.affected:
        changed = [l.strip() for l in open(args.affected) if l.strip()]
        wanted = affected_suites(changed, known)
        print("affected: %d changed file(s) -> %d suite(s): %s" % (len(changed), len(wanted), " ".join(wanted) or "(none)"))
        if not wanted:
            print("RESULT: PASS (nothing affected; run --full before pushing)")
            return 0
    # "suite#i/n" is shard i of n of a known suite (the runner sets VALIDATE_SHARD for it)
    # a suite outside SUITES still runs by name when its script exists ("regions", the whole unsharded suite)
    unknown = [s for s in wanted if s.split("#")[0] not in known and not s.startswith("res://")
               and not os.path.exists(os.path.join(ROOT, "scripts", "validate_%s.gd" % s.split("#")[0]))]
    durations = {}
    if os.path.exists(TIMINGS):
        try:
            durations = json.load(open(TIMINGS))
        except ValueError:
            pass
    serial = [] if args.no_serial else [s for s in wanted if s in SERIAL]
    pool = [s for s in wanted if s not in serial and s not in unknown]
    bins = pack(pool, durations, max(1, args.jobs))

    sweep_old_runs()
    base = tempfile.mkdtemp(prefix="lr-validate-")
    with open(os.path.join(base, ".owner-pid"), "w") as f:
        f.write(str(os.getpid()))
    logs = os.path.join(base, "logs")
    os.makedirs(logs)
    try:
        return _run_all(args, known, wanted, unknown, serial, bins, base, logs, durations)
    finally:
        try:
            kept = keep_trimmed_logs(logs)
            print("logs (trimmed): %s" % kept)
        except OSError:
            pass
        _remove_tree(base)   # always: success, failure or exception


def _run_all(args, known, wanted, unknown, serial, bins, base, logs, durations):
    t0 = time.time()
    workers = [Worker(i, base) for i in range(max(len(bins), 1))]
    results, fail_lines = {}, {}
    lock = threading.Lock()

    def run_bin(w, suites):
        log = os.path.join(logs, "w%d.log" % w.idx)
        verdicts, lines_by, rc = w.run(suites, args.timeout, log)
        missing = [s for s in suites if s not in verdicts]
        if missing and len(suites) > 1:
            # the process died or quit early; give each unreported suite its own run
            for s in missing:
                v, lb, _ = w.run([s], args.timeout, log)
                verdicts.update(v)
                for k, lst in lb.items():
                    lines_by.setdefault(k, []).extend(lst)
        with lock:
            for s in suites:
                if s in verdicts:
                    results[s] = verdicts[s]
                else:
                    results[s] = ("FAIL", 0.0)
                    lines_by.setdefault(s, []).append("  FAIL  no verdict (crash, timeout or parse error; exit %d) -- see %s" % (rc, log))
                if results[s][0] == "FAIL":
                    fail_lines[s] = lines_by.get(s, []) or ["  FAIL  (no FAIL line captured) -- see %s" % log]

    backend = None
    if args.backend:
        node = os.environ.get("NODE_BIN", "node")
        tests = sorted(os.path.join(ROOT, "backend", f) for f in os.listdir(os.path.join(ROOT, "backend")) if f.endswith(".test.mjs"))
        backend = subprocess.Popen([node, "--test"] + tests, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   text=True, encoding="utf-8", errors="replace")

    threads = [threading.Thread(target=run_bin, args=(workers[i], b)) for i, b in enumerate(bins)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    for s in serial:  # alone on the machine (well, alone among our processes)
        run_bin(workers[0], [s])

    if backend:
        out, _ = backend.communicate()
        results["backend"] = ("PASS" if backend.returncode == 0 else "FAIL", 0.0)
        if backend.returncode != 0:
            fail_lines["backend"] = [l for l in out.splitlines() if "not ok" in l or "Error" in l][:40]
    for s in unknown:
        results[s] = ("FAIL", 0.0)
        fail_lines[s] = ["  FAIL  no suite named %s" % s]
    wall = time.time() - t0

    for s, (v, secs) in results.items():
        if s.split("#")[0] in known and secs > 0:
            durations[s] = secs
    try:
        json.dump(durations, open(TIMINGS, "w"), indent=1, sort_keys=True)
    except OSError:
        pass

    markers = [(w.idx, suites, m) for w in workers for suites, m in w.crash_markers]
    print("\n==== SUMMARY (%d suites, %d workers, %.0fs wall) ====" % (len(results), len(bins), wall))
    for s in sorted(results, key=lambda k: (results[k][0] == "PASS", -results[k][1])):
        print("%-4s %7.1fs  %s" % (results[s][0], results[s][1], s))
    failed = [s for s in results if results[s][0] != "PASS"]
    for s in failed:
        print("\n-- %s" % s)
        for line in fail_lines.get(s, [])[:30]:
            print("   " + line)
    if markers:
        print("\n-- crash markers (CrashWatch: crashes, kills and freezes; informational)")
        for idx, suites, marker in markers:
            print("   [w%d] %s: %s" % (idx, ",".join(suites)[:120], marker))
    if args.json:
        json.dump({"wall": wall, "jobs": len(bins), "results": results, "fail_lines": fail_lines,
                   "crash_markers": [{"worker": i, "suites": su, "marker": m} for i, su, m in markers]},
                  open(args.json, "w"), indent=1)
    print("RESULT: %s (%d failed of %d)" % ("FAIL" if failed else "PASS", len(failed), len(results)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
