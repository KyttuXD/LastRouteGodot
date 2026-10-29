#!/usr/bin/env python3
"""Render sequencer shots (tools/playtest/shots/*.json, src/playtest/playtest_sequencer.gd) on the mini into captures/videos/<commit>/.

  tools/playtest/shots.py --shots nyxie_peek,elise_sprint [--commit HEAD | --working-tree] [--keep-avi]

Same pipeline as flythrough.py (git archive -> mini --scene windowed Movie Maker render -> ffmpeg), one clip per shot, <shot>.mp4 next to the
flythrough clips so tools/playtest/trailer.py can cut them. A shot whose camera was inside geometry is reported and not kept.
"""
import argparse
import os
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import flythrough as fl  # noqa: E402


GODOT = "/Applications/Godot.app/Contents/MacOS/Godot"
LOCAL_LANE = Path.home() / "Developer/lanes/shot-local"


def local_sync(src):
    LOCAL_LANE.mkdir(parents=True, exist_ok=True)
    subprocess.run(["rsync", "-a", "--delete", "--exclude", ".git", "--exclude", ".claude", "--exclude", "captures", "--exclude", "._*", "--exclude", ".DS_Store",
                    "--exclude", ".godot", "--exclude", ".playtest", str(src) + "/", str(LOCAL_LANE) + "/"], check=True)
    (LOCAL_LANE / ".playtest/fly").mkdir(parents=True, exist_ok=True)
    # always re-import: a merge that adds script classes leaves a stale class cache, and every scene then fails to parse
    subprocess.run([GODOT, "--headless", "--path", str(LOCAL_LANE), "--import"], capture_output=True)


def local_scene(godot_args, timeout):
    guard = str(fl.SETUP / "guard.pl")
    return subprocess.run(["perl", guard, str(timeout), GODOT, "--path", str(LOCAL_LANE), *godot_args.split()], capture_output=True, text=True, timeout=timeout + 60)


def preview_checks(name, args, src, lane, out_dir, tmp):
    """Quick low-res run to the shot's `expect` moment: returns (passed, checks, still path). Refuses nothing itself: the caller decides."""
    # fixed fps like the render: the clip's clock and the game's movement agree, so preview distances are the render's
    base = ("--fixed-fps %d --resolution 960x540 res://scenes/playtest_runner.tscn -- --playtest-runner --game=last_route --scenario=sequence --shot=%s --shot-file=tools/playtest/shots/%s.json --preview --seed=%s --fps=%d --clean=true --deadline=250 --name=pre_%s"
            % (args.fps, name, name, args.seed, args.fps, name))
    if args.local:
        # never read the previous run's report or stills by accident
        shutil.rmtree(LOCAL_LANE / (".playtest/pre_%s" % name), ignore_errors=True)
        for old in (LOCAL_LANE / ".playtest/preview").glob(name + "_*.png") if (LOCAL_LANE / ".playtest/preview").exists() else []:
            old.unlink()
        run = local_scene(base, 300)
        report_file = LOCAL_LANE / (".playtest/pre_%s/report.json" % name)
        if not report_file.exists():
            errors = [l for l in (run.stdout + run.stderr).splitlines() if "ERROR" in l or "at: " in l][:12]
            print("  %-16s preview run produced no report:\n      %s" % (name, "\n      ".join(errors) or "(no error lines)"))
        still = LOCAL_LANE / (".playtest/preview")
    else:
        fl.mini(src, lane, "--scene", base, timeout=400)
        local = tmp / ("pre_" + name)
        fl.mini(src, lane, "--pull", ".playtest/pre_%s/report.json" % name, str(local))
        fl.mini(src, lane, "--pull", ".playtest/preview/", str(local))
        report_file, still = local / "report.json", local
    report = json.loads(report_file.read_text()) if report_file.exists() else {}
    checks = report.get("flythrough", {}).get("checks", {})
    if report and not checks:
        print("  %-16s preview did not reach its beats: %s" % (name, report.get("flythrough", {}).get("reason") or report.get("scenario_failure") or "?"))
    saved = None
    if still.exists():
        for png in sorted(still.glob(name + "*.png")):
            shutil.copy(png, out_dir / png.name.replace(name, name + "_preview", 1))
            saved = out_dir / png.name.replace(name, name + "_preview", 1)
    return bool(checks.get("pass", not checks)) and bool(checks), checks, saved


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--shots", default="all")
    ap.add_argument("--commit", default="HEAD")
    ap.add_argument("--working-tree", action="store_true")
    ap.add_argument("--seed", default="FLYTHROUGH")
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("--crf", type=int, default=24)
    ap.add_argument("--timeout", type=int, default=900)
    ap.add_argument("--local", action="store_true", help="render on THIS Mac (KT-Mini4-1) through guard.pl instead of the mini")
    ap.add_argument("--force", action="store_true", help="render even when the preview self-check fails")
    ap.add_argument("--check-only", action="store_true", help="run the self-check preview only (writes <shot>_preview.png), no render")
    ap.add_argument("--out", default="")
    args = ap.parse_args()
    fl.HW = "h264_videotoolbox" in fl.sh(["ffmpeg", "-hide_banner", "-encoders"]).stdout
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
        if args.local:
            local_sync(src)
        prep = None if args.local else fl.mini(src, lane, "--cmd", "mkdir -p .playtest/fly; find .playtest/fly -name '*.avi' -delete", nosync=False, timeout=900)
        if prep is not None and prep.returncode != 0:
            sys.exit("sync to the mini failed:\n" + (prep.stdout + prep.stderr)[-800:])
        for name in names:
            spec = json.loads((shot_dir / (name + ".json")).read_text())
            if spec.get("expect") or spec.get("expects"):
                passed, checks, still = preview_checks(name, args, src, lane, out_dir, tmp)
                print("  %-16s self-check %s   preview: %s" % (name, "PASS" if passed else "FAIL", still))
                for row in checks.get("rows", []):
                    print("      %s %s - %s" % ("ok  " if row["pass"] else "FAIL", row["name"], row["detail"]))
                if not passed and not args.force:
                    print("  %-16s NOT RENDERED (self-check failed; --force overrides)" % name)
                    ok_all = False
                    continue
            if args.check_only:
                continue
            avi_rel = ".playtest/fly/%s.avi" % name
            cmd = ("--write-movie %s --fixed-fps %d --resolution 1280x720 res://scenes/playtest_runner.tscn -- --playtest-runner --game=last_route "
                   "--scenario=sequence --shot=%s --shot-file=tools/playtest/shots/%s.json --seed=%s --fps=%d --clean=true --deadline=%d --name=fly_%s"
                   % (avi_rel, args.fps, name, name, args.seed, args.fps, args.timeout - 60, name))
            local = tmp / name
            if args.local:
                run = local_scene(cmd, args.timeout)
                local.mkdir(parents=True, exist_ok=True)
                for rel in (".playtest/fly_%s/report.json" % name, avi_rel):
                    shutil.copy(LOCAL_LANE / rel, local / Path(rel).name)
            else:
                run = fl.mini(src, lane, "--scene", cmd, timeout=args.timeout)
                fl.mini(src, lane, "--pull", ".playtest/fly_%s/report.json" % name, str(local))
            report_file = local / "report.json"
            report = json.loads(report_file.read_text()) if report_file.exists() else {}
            info = report.get("flythrough", {})
            if not info.get("available"):
                print("  %-16s FAILED: %s | %s" % (name, report.get("scenario_failure") or info.get("reason") or "no report", " / ".join((run.stdout + run.stderr).strip().splitlines()[-3:])))
                ok_all = False
                continue
            if not args.local:
                fl.mini(src, lane, "--pull", avi_rel, str(local))
            avi = local / ("%s.avi" % name)
            mp4 = out_dir / ("%s.mp4" % name)
            good, err = fl.encode(avi, mp4, int(info["clip_start_frame"]), int(info["clip_frames"]), int(info["fps"]), args.crf, 1280,
                                  float(spec.get("fade_in", .6)), float(spec.get("fade_out", .9)))
            if args.local:
                (LOCAL_LANE / avi_rel).unlink(missing_ok=True)
            else:
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
