#!/usr/bin/env python3
"""Last Route flythrough videos: one command renders every named area of a commit to small H.264 clips.

  tools/playtest/flythrough.py                          # default set, current HEAD  -> captures/videos/<commit>/<area>.mp4
  tools/playtest/flythrough.py --commit main            # any rev: its tree is exported and rendered, your checkout is untouched
  tools/playtest/flythrough.py --working-tree --areas hospital,sewer_tunnels
  tools/playtest/flythrough.py --list

The GAME runs on KT-Mini4-2 (windowed, Godot Movie Maker, 1280x720 at 30 fps, real GPU renderer) through mini-run.sh; this Mac only exports the
tree, pulls the .avi back and encodes it with ffmpeg (trim to the clip, fade in/out, x264 crf 27, +faststart). Never runs Godot here.
Videos go to <repo>/captures/videos/<commit>/ (gitignored) together with index.md and index.json. Stdlib only.
"""
import argparse
import statistics
import json
import os
import shutil
import subprocess
import sys
import tempfile
import queue
import shlex
import threading
import time
from pathlib import Path

SETUP = Path(os.environ.get("PLAYTEST_TOOLS_DIR", "/Users/kyttu/Developer/Claude-Setup"))
MINI_RUN = os.environ.get("MINI_RUN", str(SETUP / "mini-run.sh"))
REPO = Path(__file__).resolve().parents[2]

DEFAULT_SET = ["hospital", "lab", "greenhouse", "mall", "prison", "mansion", "hotel", "sewer_tunnels", "sewer_junction",
               "sewer_valve_room", "sewer_ladder", "inferno"]
ALL_AREAS = DEFAULT_SET + ["descent_ladder", "maze", "apartment", "beach", "gothic", "carnival", "sewer_pump_room", "sewer_overflow"]
BLURB = {
    "hospital": "Hospital district: halls, wards and the nurses' station", "lab": "Research lab district", "greenhouse": "Greenhouse district",
    "mall": "Mall / arcade district", "prison": "Prison cell blocks", "mansion": "Mansion halls", "hotel": "Hotel corridors",
    "maze": "The plain maze", "apartment": "Apartment district", "beach": "Beach district", "gothic": "Gothic wing", "carnival": "Carnival",
    "inferno": "Inferno (-3)", "sewer_tunnels": "Sewer -1: the long tunnels", "sewer_junction": "Sewer -1: junction plaza orbit",
    "sewer_valve_room": "Sewer -1: valve room", "sewer_pump_room": "Sewer -1: pump room", "sewer_overflow": "Sewer -1: overflow chamber",
    "sewer_ladder": "Sewer -1: the ladder climb up to the maze", "descent_ladder": "Maze manhole: climb down the ladder into the sewer",
}


BENCH_RUN = os.environ.get("BENCH_RUN", str(SETUP / "bench-run.sh"))
CONF = SETUP / "dist_machines.conf"


class WorkerBusy(Exception):
    """bench-run.sh refused the machine (battery, throttled, unreachable, already running Godot): hand the area to another worker."""


class Worker:
    """One render machine. key 'mini' = KT-Mini4-2 through mini-run.sh; any other dist_machines.conf key goes through the TOOLS lane's bench-run.sh
    (windows visible or off-screen as configured, auto-closing). KT-FW13 is refused here."""

    def __init__(self, key, src, lane):
        self.key, self.src, self.lane = key, src, lane
        self.host = ""
        if key != "mini":
            for line in CONF.read_text().splitlines():
                parts = line.split()
                if len(parts) > 2 and parts[0] == key:
                    self.host = parts[2]
            if not self.host or "FW13" in self.host:
                sys.exit("machine '%s' is not usable for renders (see dist_machines.conf; KT-FW13 never)" % key)

    def prepare(self, working_tree=False):
        if self.key == "mini":
            prep = mini(self.src, self.lane, "--cmd", "mkdir -p .playtest/fly; find .playtest/fly -name '*.avi' -delete", nosync=False, timeout=900)
            if prep.returncode != 0:
                sys.exit("sync to the mini failed:\n" + (prep.stdout + prep.stderr)[-800:])

    def scene(self, cmd, timeout):
        if self.key == "mini":
            return mini(self.src, self.lane, "--scene", cmd, timeout=timeout)
        env = dict(os.environ, BENCH_TIMEOUT=str(timeout))
        return sh([BENCH_RUN, self.key, str(self.src), self.lane, "--cooldown", "0", "--", *shlex.split(cmd)], env=env, timeout=timeout + 600)

    def pull(self, rel, local):
        if self.key == "mini":
            mini(self.src, self.lane, "--pull", rel, str(local))
        else:
            Path(local).mkdir(parents=True, exist_ok=True)
            sh(["scp", "-q", "%s:Developer/lanes/%s/%s" % (self.host, self.lane, rel), str(local) + "/"])

    def sh(self, command):
        if self.key == "mini":
            return mini(self.src, self.lane, "--cmd", command)
        return sh(["ssh", "-o", "BatchMode=yes", self.host, "cd ~/Developer/lanes/%s && %s" % (self.lane, command)])


def sh(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def git(*args, cwd=REPO):
    out = sh(["git", *args], cwd=cwd)
    if out.returncode != 0:
        sys.exit("git %s failed: %s" % (" ".join(args), out.stderr.strip()))
    return out.stdout.strip()


def mini(src, lane, *args, timeout=1500, nosync=True):
    env = dict(os.environ, MINI_TIMEOUT=str(timeout))
    if nosync:
        env["NOSYNC"] = "1"
    else:
        env.pop("NOSYNC", None)
    return sh([MINI_RUN, str(src), lane, *args], env=env, timeout=timeout + 120)


HW = False


def encode(avi: Path, mp4: Path, start_frame: int, frames: int, fps: int, crf: int, scale_w: int, fade_in: float = 0.6, fade_out: float = 0.9) -> tuple:
    start = start_frame / fps
    length = frames / fps
    # fade_out 0 = the clip ends on its last frame (a hard cut in the trailer)
    out_at = max(length - fade_out, 0.0)
    vfades = (f",fade=t=in:st=0:d={fade_in}" if fade_in > 0 else "") + (f",fade=t=out:st={out_at:.2f}:d={fade_out}" if fade_out > 0 else "")
    afades = [f"afade=t=in:st=0:d={max(fade_in, .02)}"] + ([f"afade=t=out:st={out_at:.2f}:d={fade_out}"] if fade_out > 0 else [])
    vf = f"scale={scale_w}:-2:flags=lanczos{vfades},format=yuv420p"
    af = ",".join(afades)
    # -ss BEFORE -i: the clip's timestamps start at 0, so the fades land on the clip (MJPEG frames are all key frames, the seek is exact)
    base = ["ffmpeg", "-y", "-loglevel", "error", "-ss", f"{start:.3f}", "-i", str(avi), "-t", f"{length:.3f}", "-vf", vf]
    audio = ["-af", af, "-c:a", "aac", "-b:a", "64k", "-ac", "1"]
    if HW:
        video = ["-c:v", "h264_videotoolbox", "-b:v", "%dM" % (14 if scale_w >= 1900 else 6), "-movflags", "+faststart", "-r", str(fps)]
    else:
        video = ["-c:v", "libx264", "-preset", "slow", "-crf", str(crf), "-movflags", "+faststart", "-r", str(fps)]
    out = sh([*base, *audio, *video, str(mp4)])
    if out.returncode != 0:  # no audio stream in the capture: render picture only
        out = sh([*base, "-an", *video, str(mp4)])
    return out.returncode == 0, out.stderr.strip()


def frame_metrics(mp4: Path, seconds: float) -> dict:
    """Sample one frame per second and flag the boring ones: blank (almost one colour / black) or flat (one featureless surface filling the view)."""
    bad = []
    stats = []
    t = 1.0
    while t < seconds - 1.0:
        raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-ss", f"{t:.2f}", "-i", str(mp4), "-frames:v", "1", "-vf", "scale=96:54,format=gray",
                              "-f", "rawvideo", "-"], capture_output=True).stdout
        if len(raw) == 96 * 54:
            px = list(raw)
            mean = sum(px) / len(px)
            sd = statistics.pstdev(px)
            grad = [abs(px[y * 96 + x] - px[y * 96 + x + 1]) + abs(px[y * 96 + x] - px[(y + 1) * 96 + x]) for y in range(53) for x in range(95)]
            flat_share = sum(1 for g in grad if g < 4) / len(grad)
            blank = mean < 9 or sd < 5
            flat = flat_share > .86 and not blank
            stats.append((round(t, 1), round(mean), round(sd, 1), round(flat_share, 2)))
            if blank or flat:
                bad.append((round(t, 1), "blank" if blank else "flat wall"))
        t += 1.0
    return {"bad_seconds": len(bad), "bad": bad, "samples": len(stats)}


def contact_sheet(mp4: Path, sheet: Path) -> None:
    sh(["ffmpeg", "-y", "-loglevel", "error", "-i", str(mp4), "-vf", "fps=1/3,scale=320:-2,tile=4x3", "-frames:v", "1", "-q:v", "4", str(sheet)])


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--commit", default="HEAD", help="rev to render (exported with git archive; default HEAD)")
    ap.add_argument("--working-tree", action="store_true", help="render the checkout as it is on disk instead of a commit")
    ap.add_argument("--areas", default="default", help="comma list, 'default' or 'all' (see --list)")
    ap.add_argument("--seed", default="FLYTHROUGH")
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("--seconds", type=float, default=0.0, help="override the clip length (default ~35 s)")
    ap.add_argument("--hunters", choices=["hide", "show"], default="hide", help="show = leave the hunters in the shot")
    ap.add_argument("--out", default="", help="output folder (default <repo>/captures/videos/<commit>)")
    ap.add_argument("--crf", type=int, default=27)
    ap.add_argument("--width", type=int, default=1280)
    ap.add_argument("--timeout", type=int, default=1500, help="per-area wall-clock limit on the mini, seconds")
    ap.add_argument("--keep-avi", action="store_true", help="keep the raw captures next to the mp4s")
    ap.add_argument("--variants", type=int, default=3, help="tries per area: a clip that stares at walls or goes blank is re-planned with the next variant")
    ap.add_argument("--clean", action="store_true", help="capture-only clean scene: hide pickups, tools and the waypoint trail (visibility only)")
    ap.add_argument("--keep", default="", help="with --clean: kinds to keep visible (relay,battery,coin,tool_pickup,music_box)")
    ap.add_argument("--no-bob", action="store_true", help="no head bob (dolly style)")
    ap.add_argument("--machines", default="mini", help="comma list of dist_machines.conf keys rendering in parallel, one area per machine at a time (mini,local,neo,mbp,t480; never fw)")
    ap.add_argument("--final", action="store_true", help="final quality: 1920x1080 at 60 fps (default is the 720p/30 draft)")
    ap.add_argument("--no-cache", action="store_true", help="re-render areas even when the runtime tree and settings match an earlier render")
    ap.add_argument("--software-encode", action="store_true", help="libx264 instead of h264_videotoolbox")
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()
    if args.final:
        args.fps, args.width, args.crf = 60, 1920, 22
    args.resolution = "1920x1080" if args.final else "1280x720"
    global HW
    HW = not args.software_encode and "h264_videotoolbox" in sh(["ffmpeg", "-hide_banner", "-encoders"]).stdout

    if args.list:
        for name in ALL_AREAS:
            print("%-18s %s%s" % (name, BLURB.get(name, ""), "   [default]" if name in DEFAULT_SET else ""))
        return 0
    if not shutil.which("ffmpeg"):
        sys.exit("ffmpeg not found on this Mac")
    areas = DEFAULT_SET if args.areas == "default" else ALL_AREAS if args.areas == "all" else [a for a in args.areas.split(",") if a]
    for area in areas:
        if area not in ALL_AREAS:
            sys.exit("unknown area '%s' (see --list)" % area)

    if args.working_tree:
        rev = git("rev-parse", "--short=8", "HEAD") + "-wt"
    else:
        rev = git("rev-parse", "--short=8", args.commit)
    common = Path(git("rev-parse", "--path-format=absolute", "--git-common-dir"))
    out_dir = Path(args.out) if args.out else common.parent / "captures" / "videos" / rev
    out_dir.mkdir(parents=True, exist_ok=True)
    lane = "fly-" + rev
    tmp = Path(tempfile.mkdtemp(prefix="flythrough-"))
    results = []
    cache_dir = common.parent / "captures" / "videos" / ".cache"
    cache_key = None
    if not args.working_tree and not args.no_cache:
        trees = [git("rev-parse", "%s:%s" % (rev, d)) if sh(["git", "cat-file", "-e", "%s:%s" % (rev, d)], cwd=REPO).returncode == 0 else "-" for d in ("src", "assets", "data", "scenes", "project.godot")]
        cache_key = "-".join(t[:10] for t in trees) + "_%s_%d_%s_%s_%s_%s_%s" % (args.resolution, args.fps, args.seed, args.hunters, args.clean, args.keep or "n", args.no_bob)
    try:
        if args.working_tree:
            src = REPO
        else:
            src = tmp / "src"
            src.mkdir()
            archive = subprocess.Popen(["git", "archive", rev], cwd=REPO, stdout=subprocess.PIPE)
            subprocess.run(["tar", "-x", "-C", str(src)], stdin=archive.stdout, check=True)
            archive.wait()
            (src / ".playtest/fly").mkdir(parents=True, exist_ok=True)
            (src / ".playtest/fly/.keep").write_text("")
            if not (src / "src/playtest/playtest_flythrough.gd").exists():
                sys.exit("commit %s has no flythrough scenario (src/playtest/playtest_flythrough.gd)" % rev)
        def render_area(area, w):
            began_area = time.time()
            result = {"area": area, "blurb": BLURB.get(area, ""), "ok": False, "attempts": []}
            best = None
            for variant in range(max(args.variants, 1)):
                began = time.time()
                avi_rel = ".playtest/fly/%s.avi" % area
                cmd = ("--write-movie %s --fixed-fps %d --disable-vsync --resolution %s res://scenes/playtest_runner.tscn -- --playtest-runner --game=last_route "
                       "--scenario=flythrough --area=%s --seed=%s --fps=%d --seconds=%s --hunters=%s --variant=%d --bob=%s --clean=%s --keep=%s --deadline=%d --name=fly_%s"
                       % (avi_rel, args.fps, args.resolution, area, args.seed, args.fps, args.seconds, args.hunters, variant, "false" if args.no_bob else "true",
                          "true" if args.clean else "false", args.keep or "none", args.timeout - 120, area))
                run = w.scene(cmd, args.timeout)
                if run.returncode == 75:
                    raise WorkerBusy((run.stdout + run.stderr).strip().splitlines()[-1] if (run.stdout + run.stderr).strip() else "refused")
                log = run.stdout + run.stderr
                local = tmp / ("%s_%d" % (area, variant))
                w.pull(".playtest/fly_%s/report.json" % area, local)
                report_file = local / "report.json"
                report = json.loads(report_file.read_text()) if report_file.exists() else {}
                info = report.get("flythrough", {})
                if not info.get("available", False):
                    result["skipped"] = info.get("reason") or report.get("scenario_failure") or "no report (see log tail)"
                    result["log_tail"] = log.strip().splitlines()[-4:]
                    break
                w.pull(avi_rel, local)
                avi = local / ("%s.avi" % area)
                if not avi.exists():
                    result["skipped"] = "the capture file was not written"
                    result["log_tail"] = log.strip().splitlines()[-4:]
                    break
                mp4 = tmp / ("%s_v%d.mp4" % (area, variant))
                ok, err = encode(avi, mp4, int(info["clip_start_frame"]), int(info["clip_frames"]), int(info["fps"]), args.crf, args.width)
                w.sh("rm -f %s" % avi_rel)
                if not ok:
                    result["skipped"] = "encode failed: " + err[-200:]
                    break
                quality = frame_metrics(mp4, float(info.get("seconds", 0)))
                tight = float(info.get("worst_tight_run_s", 0))
                overlap = float(info.get("prop_overlap_s", 0))
                floor_step = float(info.get("max_floor_step_m", 0))
                door_clip = float(info.get("door_clip_s", 0))
                inside = float(info.get("inside_geometry_s", 0))
                beats = info.get("door_beats", [])
                door_seen = min([b["visible_s"] for b in beats], default=9.0)
                after = info.get("after_interaction", [])
                bounce = max([a["back_m"] for a in after], default=0.0)
                reversal = max([a["yaw_reversal_deg"] for a in after], default=0.0)
                attempt = {"variant": variant, "bad_seconds": quality["bad_seconds"], "bad": quality["bad"], "tight_run_s": tight, "prop_overlap_s": overlap, "door_clip_s": door_clip, "door_beats": beats, "bounce_back_m": bounce, "yaw_reversal_deg": reversal, "inside_geometry_s": inside, "blocked_s": info.get("blocked_s"), "doors_opened": info.get("doors_opened"), "max_floor_step_m": floor_step, "rooms": info.get("rooms"),
                           "render_wall_s": round(time.time() - began), "chunk": info.get("chunk")}
                result["attempts"].append(attempt)
                score = quality["bad_seconds"] + 6.0 * max(tight - 0.3, 0.0) + 6.0 * max(overlap - 0.3, 0.0) + (3.0 if floor_step > 0.15 else 0.0) + 6.0 * max(door_clip - 0.1, 0.0) + 6.0 * max(0.6 - door_seen, 0.0) + 6.0 * max(bounce - 0.10, 0.0) + (3.0 if reversal > 20 else 0.0)
                print("    %s try %d: %d boring s %s, view<1.5 m %.1f s, inside props %.1f s, in a door %.1f s (%s opened, seen %s s, bounce %.2f m, yaw back %.0f deg), floor step %.2f m, rooms %s" % (area, variant, quality["bad_seconds"], quality["bad"][:4], tight, overlap, door_clip, info.get("doors_opened"), [b["visible_s"] for b in beats], bounce, reversal, floor_step, info.get("rooms")), flush=True)
                if inside > 0.05:
                    print("    %s try %d REJECTED: the camera was inside geometry for %.2f s" % (area, variant, inside), flush=True)
                    continue
                if best is None or score < best["score"]:
                    best = {"score": score, "mp4": mp4, "info": info, "attempt": attempt}
                if quality["bad_seconds"] <= 2 and tight <= 0.3 and overlap <= 0.3 and floor_step <= 0.15 and door_clip <= 0.1 and door_seen >= 0.6 and bounce <= 0.10 and reversal <= 20:
                    break
            if best is None:
                result["skipped"] = result.get("skipped") or "DROPPED: every variant had the camera inside geometry"
                print("  %-18s SKIPPED: %s" % (area, result.get("skipped")), flush=True)
                return result
            info = best["info"]
            result["worker"] = w.key
            result["wall_s"] = round(time.time() - began_area)
            mp4 = out_dir / ("%s.mp4" % area)
            shutil.copy(best["mp4"], mp4)
            contact_sheet(mp4, out_dir / ("%s_sheet.jpg" % area))
            clean_pass = (best["attempt"]["bad_seconds"] <= 2 and best["attempt"]["tight_run_s"] <= 0.3 and best["attempt"]["prop_overlap_s"] <= 0.3
                          and best["attempt"]["max_floor_step_m"] <= 0.15 and best["attempt"]["door_clip_s"] <= 0.1 and min([b["visible_s"] for b in best["attempt"].get("door_beats", [])], default=9.0) >= 0.6)
            result.update({"ok": True, "quality": "pass" if clean_pass else "WARN: boring stretches remain", "file": str(mp4), "sheet": str(out_dir / ("%s_sheet.jpg" % area)),
                           "size_mb": round(mp4.stat().st_size / 1e6, 2), "seconds": info.get("seconds"), "level": info.get("level"), "chunk": info.get("chunk"),
                           "rooms": info.get("rooms"), "variant": best["attempt"]["variant"], "biome_at_end": info.get("current_biome")})
            print("  %-18s %s  %5.1f s  %s MB  variant %d  %s" % (area, "OK ", info.get("seconds", 0), result["size_mb"], best["attempt"]["variant"], result["quality"]), flush=True)
            return result

        def cached(area):
            if cache_key is None:
                return None
            d = cache_dir / cache_key
            meta = d / (area + ".json")
            if meta.exists() and (d / (area + ".mp4")).exists():
                r = json.loads(meta.read_text())
                shutil.copy(d / (area + ".mp4"), out_dir / (area + ".mp4"))
                if (d / (area + "_sheet.jpg")).exists():
                    shutil.copy(d / (area + "_sheet.jpg"), out_dir / (area + "_sheet.jpg"))
                r.update({"file": str(out_dir / (area + ".mp4")), "sheet": str(out_dir / (area + "_sheet.jpg")), "cached": True, "wall_s": 0})
                return r
            return None

        def store(area, r):
            if cache_key is None or not r.get("ok"):
                return
            d = cache_dir / cache_key
            d.mkdir(parents=True, exist_ok=True)
            shutil.copy(out_dir / (area + ".mp4"), d / (area + ".mp4"))
            if (out_dir / (area + "_sheet.jpg")).exists():
                shutil.copy(out_dir / (area + "_sheet.jpg"), d / (area + "_sheet.jpg"))
            (d / (area + ".json")).write_text(json.dumps(r))

        todo = queue.Queue()
        for area in areas:
            hit = cached(area)
            if hit is not None:
                print("  %-18s cached (same runtime tree and settings)" % area, flush=True)
                results.append(hit)
            else:
                todo.put(area)
        lock = threading.Lock()
        t_all = time.time()

        def work(w):
            while True:
                try:
                    area = todo.get_nowait()
                except queue.Empty:
                    return
                try:
                    r = render_area(area, w)
                except WorkerBusy as why:
                    print("  [%s] unavailable (%s): handing %s back" % (w.key, why, area), flush=True)
                    todo.put(area)
                    return
                store(area, r)
                with lock:
                    results.append(r)

        keys = [k for k in args.machines.split(",") if k]
        workers = [Worker(k, src, lane) for k in keys]
        for w in workers:
            w.prepare(working_tree=args.working_tree)
        print("rendering %d area(s) of %s on %s" % (todo.qsize(), rev, ",".join(keys)), flush=True)
        threads = [threading.Thread(target=work, args=(w,)) for w in workers]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        while not todo.empty():   # every other machine dropped out: finish on the mini
            work(workers[0] if workers[0].key == "mini" else Worker("mini", src, lane))
        print("render wall time %.0f s for %d clip(s) (draft=%s)" % (time.time() - t_all, len(results), not args.final), flush=True)
        order = {a: n for n, a in enumerate(areas)}
        results.sort(key=lambda r: order.get(r["area"], 99))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
        # keep only this commit's lane on the mini (each holds a copy of the project and its import cache)
        mini(REPO, lane, "--cmd", "cd .. && for d in fly-*; do [ \"$d\" != \"%s\" ] && rm -rf \"$d\"; done; true" % lane, timeout=300)

    (out_dir / "index.json").write_text(json.dumps({"commit": rev, "seed": args.seed, "fps": args.fps, "areas": results}, indent=2))
    lines = ["# Last Route flythroughs - commit %s" % rev, "", "Seed `%s`, %d fps, 1280x720 source. Re-render: `tools/playtest/flythrough.py --commit %s`." % (args.seed, args.fps, rev), ""]
    for r in results:
        if r.get("ok"):
            lines.append("- **%s** (%s) - [%s.mp4](%s.mp4) ([sheet](%s_sheet.jpg)), %.0f s, %s MB%s, quality %s%s" % (r["area"], r["blurb"], r["area"], r["area"], r["area"], r.get("seconds") or 0, r["size_mb"],
                         (", level %s chunk %s" % (r.get("level"), r.get("chunk"))) if r.get("chunk") else "", r.get("quality"),
                         (", rooms %s" % r.get("rooms")) if r.get("rooms") else ""))
        else:
            lines.append("- %s - not rendered: %s" % (r["area"], r.get("skipped")))
    (out_dir / "index.md").write_text("\n".join(lines) + "\n")
    good = sum(1 for r in results if r.get("ok"))
    print("%d/%d clips in %s" % (good, len(results), out_dir))
    return 0 if good else 1


if __name__ == "__main__":
    sys.exit(main())
