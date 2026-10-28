#!/usr/bin/env python3
"""Render sequencer shots (tools/playtest/shots/*.json, src/playtest/playtest_sequencer.gd) on the mini into captures/videos/<commit>/.

  tools/playtest/shots.py --shots nyxie_peek,elise_sprint [--commit HEAD | --working-tree] [--keep-avi]

Same pipeline as flythrough.py (git archive -> mini --scene windowed Movie Maker render -> ffmpeg), one clip per shot, <shot>.mp4 next to the
flythrough clips so tools/playtest/trailer.py can cut them. A shot whose camera was inside geometry is reported and not kept.
"""
import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import flythrough as fl  # noqa: E402


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--shots", default="all")
    ap.add_argument("--commit", default="HEAD")
    ap.add_argument("--working-tree", action="store_true")
    ap.add_argument("--seed", default="FLYTHROUGH")
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("--crf", type=int, default=24)
    ap.add_argument("--timeout", type=int, default=900)
    ap.add_argument("--out", default="")
    args = ap.parse_args()
    shot_dir = fl.REPO / "tools/playtest/shots"
    names = sorted(p.stem for p in shot_dir.glob("*.json")) if args.shots == "all" else [s for s in args.shots.split(",") if s]
    rev = fl.git("rev-parse", "--short=8", "HEAD") + "-wt" if args.working_tree else fl.git("rev-parse", "--short=8", args.commit)
    common = Path(fl.git("rev-parse", "--path-format=absolute", "--git-common-dir"))
    out_dir = Path(args.out) if args.out else common.parent / "captures" / "videos" / rev
    out_dir.mkdir(parents=True, exist_ok=True)
    lane = "shot-" + rev
    tmp = Path(tempfile.mkdtemp(prefix="shots-"))
    ok_all = True
    try:
        if args.working_tree:
            src = fl.REPO
        else:
            src = tmp / "src"
            src.mkdir()
            archive = subprocess.Popen(["git", "archive", rev], cwd=fl.REPO, stdout=subprocess.PIPE)
            subprocess.run(["tar", "-x", "-C", str(src)], stdin=archive.stdout, check=True)
            archive.wait()
        prep = fl.mini(src, lane, "--cmd", "mkdir -p .playtest/fly; find .playtest/fly -name '*.avi' -delete", nosync=False, timeout=900)
        if prep.returncode != 0:
            sys.exit("sync to the mini failed:\n" + (prep.stdout + prep.stderr)[-800:])
        for name in names:
            avi_rel = ".playtest/fly/%s.avi" % name
            cmd = ("--write-movie %s --fixed-fps %d --resolution 1280x720 res://scenes/playtest_runner.tscn -- --playtest-runner --game=last_route "
                   "--scenario=sequence --shot=%s --seed=%s --fps=%d --clean=true --deadline=%d --name=fly_%s"
                   % (avi_rel, args.fps, name, args.seed, args.fps, args.timeout - 60, name))
            run = fl.mini(src, lane, "--scene", cmd, timeout=args.timeout)
            local = tmp / name
            fl.mini(src, lane, "--pull", ".playtest/fly_%s/report.json" % name, str(local))
            report_file = local / "report.json"
            report = json.loads(report_file.read_text()) if report_file.exists() else {}
            info = report.get("flythrough", {})
            if not info.get("available"):
                print("  %-16s FAILED: %s | %s" % (name, report.get("scenario_failure") or info.get("reason") or "no report", " / ".join((run.stdout + run.stderr).strip().splitlines()[-3:])))
                ok_all = False
                continue
            fl.mini(src, lane, "--pull", avi_rel, str(local))
            avi = local / ("%s.avi" % name)
            mp4 = out_dir / ("%s.mp4" % name)
            good, err = fl.encode(avi, mp4, int(info["clip_start_frame"]), int(info["clip_frames"]), int(info["fps"]), args.crf, 1280)
            fl.mini(src, lane, "--cmd", "rm -f %s" % avi_rel)
            if not good:
                print("  %-16s ENCODE FAILED %s" % (name, err[-200:]))
                ok_all = False
                continue
            fl.contact_sheet(mp4, out_dir / ("%s_sheet.jpg" % name))
            inside = float(info.get("inside_geometry_s", 0))
            print("  %-16s %5.1f s  %.1f MB  inside geometry %.1f s  min view depth %s m  stage forward %s  %s" % (
                name, info["seconds"], mp4.stat().st_size / 1e6, inside, info.get("min_view_depth_m"), info.get("stage_forward"),
                "REJECT" if inside > 0.05 else "ok"), flush=True)
            print("      clips:", {k: v[:12] for k, v in info.get("actor_clips", {}).items()})
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("clips in", out_dir)
    return 0 if ok_all else 1


if __name__ == "__main__":
    sys.exit(main())
