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
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

SETUP = Path(os.environ.get("PLAYTEST_TOOLS_DIR", "/Users/kyttu/Developer/Claude-Setup"))
MINI_RUN = os.environ.get("MINI_RUN", str(SETUP / "mini-run.sh"))
REPO = Path(__file__).resolve().parents[2]

DEFAULT_SET = ["hospital", "lab", "greenhouse", "mall", "prison", "mansion", "hotel", "sewer_tunnels", "sewer_junction",
               "sewer_valve_room", "sewer_ladder", "inferno"]
ALL_AREAS = DEFAULT_SET + ["maze", "apartment", "beach", "gothic", "carnival", "sewer_pump_room", "sewer_overflow"]
BLURB = {
    "hospital": "Hospital district: halls, wards and the nurses' station", "lab": "Research lab district", "greenhouse": "Greenhouse district",
    "mall": "Mall / arcade district", "prison": "Prison cell blocks", "mansion": "Mansion halls", "hotel": "Hotel corridors",
    "maze": "The plain maze", "apartment": "Apartment district", "beach": "Beach district", "gothic": "Gothic wing", "carnival": "Carnival",
    "inferno": "Inferno (-3)", "sewer_tunnels": "Sewer -1: the long tunnels", "sewer_junction": "Sewer -1: junction plaza orbit",
    "sewer_valve_room": "Sewer -1: valve room", "sewer_pump_room": "Sewer -1: pump room", "sewer_overflow": "Sewer -1: overflow chamber",
    "sewer_ladder": "Sewer -1: the ladder climb up to the maze",
}


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


def encode(avi: Path, mp4: Path, start_frame: int, frames: int, fps: int, crf: int, scale_w: int) -> tuple:
    start = start_frame / fps
    length = frames / fps
    fade_out = max(length - 0.9, 0.0)
    vf = f"scale={scale_w}:-2:flags=lanczos,fade=t=in:st=0:d=0.6,fade=t=out:st={fade_out:.2f}:d=0.9,format=yuv420p"
    af = f"afade=t=in:st=0:d=0.6,afade=t=out:st={fade_out:.2f}:d=0.9"
    base = ["ffmpeg", "-y", "-loglevel", "error", "-i", str(avi), "-ss", f"{start:.3f}", "-t", f"{length:.3f}", "-vf", vf]
    audio = ["-af", af, "-c:a", "aac", "-b:a", "64k", "-ac", "1"]
    video = ["-c:v", "libx264", "-preset", "slow", "-crf", str(crf), "-movflags", "+faststart", "-r", str(fps)]
    out = sh([*base, *audio, *video, str(mp4)])
    if out.returncode != 0:  # no audio stream in the capture: render picture only
        out = sh([*base, "-an", *video, str(mp4)])
    return out.returncode == 0, out.stderr.strip()


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
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()

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
    try:
        if args.working_tree:
            src = REPO
        else:
            src = tmp / "src"
            src.mkdir()
            archive = subprocess.Popen(["git", "archive", rev], cwd=REPO, stdout=subprocess.PIPE)
            subprocess.run(["tar", "-x", "-C", str(src)], stdin=archive.stdout, check=True)
            archive.wait()
            if not (src / "src/playtest/playtest_flythrough.gd").exists():
                sys.exit("commit %s has no flythrough scenario (src/playtest/playtest_flythrough.gd)" % rev)
        print("rendering %d area(s) of %s on KT-Mini4-2 -> %s" % (len(areas), rev, out_dir), flush=True)
        prep = mini(src, lane, "--cmd", "mkdir -p .playtest/fly; find .playtest/fly -name '*.avi' -delete", nosync=False, timeout=900)
        if prep.returncode != 0:
            sys.exit("sync to the mini failed:\n" + (prep.stdout + prep.stderr)[-800:])
        for area in areas:
            began = time.time()
            avi_rel = ".playtest/fly/%s.avi" % area
            cmd = ("--write-movie %s --fixed-fps %d --resolution 1280x720 res://scenes/playtest_runner.tscn -- --playtest-runner --game=last_route "
                   "--scenario=flythrough --area=%s --seed=%s --fps=%d --seconds=%s --hunters=%s --deadline=%d --name=fly_%s"
                   % (avi_rel, args.fps, area, args.seed, args.fps, args.seconds, args.hunters, args.timeout - 120, area))
            run = mini(src, lane, "--scene", cmd, timeout=args.timeout)
            log = run.stdout + run.stderr
            result = {"area": area, "blurb": BLURB.get(area, ""), "ok": False, "render_wall_s": round(time.time() - began)}
            local = tmp / area
            pulled_report = mini(src, lane, "--pull", ".playtest/fly_%s/report.json" % area, str(local))
            report_file = local / "report.json"
            report = json.loads(report_file.read_text()) if report_file.exists() else {}
            info = report.get("flythrough", {})
            if not info.get("available", False):
                result["skipped"] = info.get("reason") or report.get("scenario_failure") or "no report (see log tail)"
                result["log_tail"] = log.strip().splitlines()[-4:]
                print("  %-18s SKIPPED: %s" % (area, result["skipped"]), flush=True)
                results.append(result)
                continue
            mini(src, lane, "--pull", avi_rel, str(local))
            avi = local / ("%s.avi" % area)
            if not avi.exists():
                result["skipped"] = "the capture file was not written"
                result["log_tail"] = log.strip().splitlines()[-4:]
                print("  %-18s FAILED: no capture" % area, flush=True)
                results.append(result)
                continue
            mp4 = out_dir / ("%s.mp4" % area)
            ok, err = encode(avi, mp4, int(info["clip_start_frame"]), int(info["clip_frames"]), int(info["fps"]), args.crf, args.width)
            if args.keep_avi:
                shutil.copy(avi, out_dir / avi.name)
            mini(src, lane, "--cmd", "rm -f %s" % avi_rel)
            result.update({"ok": ok, "file": str(mp4), "size_mb": round(mp4.stat().st_size / 1e6, 2) if ok else 0, "seconds": info.get("seconds"),
                           "level": info.get("level"), "chunk": info.get("chunk"), "start": info.get("start"), "goal": info.get("goal"),
                           "biome_at_end": info.get("current_biome"), "encode_error": "" if ok else err[-300:]})
            print("  %-18s %s  %5.1f s  %s MB  (render %d s)" % (area, "OK " if ok else "ENC-FAIL", info.get("seconds", 0), result["size_mb"], result["render_wall_s"]), flush=True)
            results.append(result)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    (out_dir / "index.json").write_text(json.dumps({"commit": rev, "seed": args.seed, "fps": args.fps, "areas": results}, indent=2))
    lines = ["# Last Route flythroughs - commit %s" % rev, "", "Seed `%s`, %d fps, 1280x720 source. Re-render: `tools/playtest/flythrough.py --commit %s`." % (args.seed, args.fps, rev), ""]
    for r in results:
        if r.get("ok"):
            lines.append("- **%s** (%s) - [%s.mp4](%s.mp4), %.0f s, %s MB%s" % (r["area"], r["blurb"], r["area"], r["area"], r.get("seconds") or 0, r["size_mb"],
                         (", level %s chunk %s" % (r.get("level"), r.get("chunk"))) if r.get("chunk") else ""))
        else:
            lines.append("- %s - not rendered: %s" % (r["area"], r.get("skipped") or r.get("encode_error")))
    (out_dir / "index.md").write_text("\n".join(lines) + "\n")
    good = sum(1 for r in results if r.get("ok"))
    print("%d/%d clips in %s" % (good, len(results), out_dir))
    return 0 if good else 1


if __name__ == "__main__":
    sys.exit(main())
