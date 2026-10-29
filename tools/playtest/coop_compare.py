#!/usr/bin/env python3
"""Line up a coop_check run's peers (tools/playtest/coop_airs.sh output) and judge the five co-op checks.

  tools/playtest/coop_compare.py <out-dir>        # <out-dir>/<machine>/{report.json, coop_samples.jsonl, shots/}

Every peer sampled its own view once a wall second (epoch ms); rows are matched across peers by the nearest epoch (machine clocks are
NTP-synced, so expect up to a few hundred ms of skew). Prints a pass/fail table and writes <out-dir>/coop_compare.json.
"""
import json
import sys
from pathlib import Path

out = Path(sys.argv[1])
peers = {}
for d in sorted(p for p in out.iterdir() if p.is_dir()):
    rep = d / "report.json"
    smp = d / "coop_samples.jsonl"
    if not rep.exists() or not smp.exists():
        print("%-8s no report/samples" % d.name)
        continue
    report = json.loads(rep.read_text())
    rows = [json.loads(line) for line in smp.read_text().splitlines() if line.strip()]
    peers[d.name] = {"report": report, "rows": rows, "me": report.get("coop_check", {}).get("me"), "role": report.get("role"),
                     "done": report.get("coop_check", {}).get("done", {}), "steps": report.get("coop_check", {}).get("steps", [])}

if not peers:
    sys.exit("no peers")
host = next((n for n, p in peers.items() if p["role"] == "host"), None)
guest_ids = sorted(p["me"] for p in peers.values() if p["role"] == "guest" and p["me"])
A = guest_ids[0] if guest_ids else None
B = guest_ids[1] if len(guest_ids) > 1 else A
C = guest_ids[2] if len(guest_ids) > 2 else A
by_id = {p["me"]: n for n, p in peers.items()}
results = []


def row_near(name, epoch):
    rows = peers[name]["rows"]
    return min(rows, key=lambda r: abs(r["epoch_ms"] - epoch)) if rows else None


def check(name, ok, detail):
    results.append({"check": name, "pass": bool(ok), "detail": detail})


# 0. connection: every peer sampled for most of the run and saw every other runner
for n, p in peers.items():
    seen = set()
    for r in p["rows"]:
        seen.update(r.get("remotes", {}).keys())
    others = {str(x["me"]) for m, x in peers.items() if m != n}
    errors = p["report"].get("log", {}).get("errors", "?")
    check("connected: " + n, others <= seen and len(p["rows"]) > 30,
          "%d samples, saw runners %s (want %s), %s engine errors, %s" % (len(p["rows"]), sorted(seen), sorted(others), errors,
                                                                       p["report"].get("scenario_failure") or "no failure"))

# 1. grab on guest A: same style everywhere, and A's HUD hidden while held
if A in by_id:
    a = by_id[A]
    held = [r for r in peers[a]["rows"] if r.get("grab_playing") or r.get("grab_state")]
    if not held:
        check("1 grab on guest A (%s)" % a, False, "A was never grabbed (no grab state in its samples)")
    else:
        style = (held[0].get("grab_state") or [held[0].get("grab_style")])[0]
        hud = [r.get("hud_hidden") for r in held]
        start = held[0]["epoch_ms"]
        views = []
        ok = all(hud)
        for n in peers:
            if n == a:
                continue
            seen = [r for r in peers[n]["rows"] if (r.get("remotes", {}).get(str(A), {}) or {}).get("grab")]
            if not seen:
                views.append("%s: never saw A's grab" % n)
                ok = False
                continue
            styles = sorted({str(r["remotes"][str(A)]["grab"][0]) for r in seen})
            lag = seen[0]["epoch_ms"] - start
            views.append("%s: %s, first seen %+d ms, %d s held" % (n, "/".join(styles), lag, len(seen)))
            ok = ok and styles == [str(style)]
        check("1 grab on guest A (%s)" % a, ok, "style %s, %d s held on A, A's HUD hidden %d/%d samples; %s"
              % (style, len(held), sum(1 for h in hud if h), len(hud), "; ".join(views)))

# 2. locker inspection at C: the inspecting Dovelle leans in on every peer, C stays hidden and is not caught
if C in by_id:
    c = by_id[C]
    hide = next((s for s in peers[c]["steps"] if s.get("step") == "hide"), {})
    insp = next((s for s in peers[host]["steps"] if s.get("step") == "inspect"), {}) if host else {}
    views = []
    ok = bool(hide.get("ok")) and bool(insp.get("ok"))
    for n in peers:
        lean = [r for r in peers[n]["rows"] if any(h.get("id") == "dovelle" and h.get("inspect") in ("LEAN", "LINGER")
                                                   for h in r.get("hunters", {}).values())]
        phases = sorted({h.get("inspect") for r in peers[n]["rows"] for h in r.get("hunters", {}).values()
                         if h.get("id") == "dovelle" and h.get("inspect")})
        views.append("%s: lean seen %d s, phases %s" % (n, len(lean), phases or "none"))
        ok = ok and bool(lean)
    caught = [r for r in peers[c]["rows"] if 110 <= r["t"] <= 200 and r.get("run_over")]
    hidden = [r for r in peers[c]["rows"] if 112 <= r["t"] <= 195 and r.get("hidden")]
    ok = ok and not caught
    check("2 locker inspect at guest C (%s)" % c, ok, "hide %s, inspect %s, C hidden %d s, caught: %s; %s"
          % (hide.get("ok", hide.get("why")), insp.get("ok", insp.get("why")), len(hidden), bool(caught), "; ".join(views)))

# 3. music box: B's wind resets the box's clock on every peer, Glyra's mood the same everywhere
if B in by_id:
    b = by_id[B]
    wind = next((s for s in peers[b]["steps"] if s.get("step") == "wind"), {})
    if not wind.get("ok"):
        check("3 music box wind by guest B (%s)" % b, False, "wind: %s" % wind.get("why", wind))
    else:
        box, at = wind["box"], wind["epoch_ms"]
        views = []
        ok = True
        for n in peers:
            before = [r["boxes"][box] for r in peers[n]["rows"] if box in r.get("boxes", {}) and at - 6000 <= r["epoch_ms"] < at]
            after = [r["boxes"][box] for r in peers[n]["rows"] if box in r.get("boxes", {}) and at + 500 <= r["epoch_ms"] <= at + 6000]
            moods = sorted({h.get("mood") for r in peers[n]["rows"] if at <= r["epoch_ms"] <= at + 20000
                            for h in r.get("hunters", {}).values() if h.get("mood")})
            if not after:
                views.append("%s: box not in its samples (too far?)" % n)
                continue
            reset = not before or max(after) > min(before) + 1.0
            views.append("%s: clock %s -> %s s, Glyra mood %s" % (n, before[-1] if before else "-", after[0], moods or "-"))
            ok = ok and reset
        check("3 music box wind by guest B (%s)" % b, ok, "box %s; %s" % (box, "; ".join(views)))

# 4. chase styles and Kathy's beam: the same hunter at the same second looks the same on host and guests
if host:
    pairs = mism_style = mism_beam = mism_state = 0
    examples = []
    for n in peers:
        if n == host:
            continue
        for r in peers[n]["rows"]:
            h = row_near(host, r["epoch_ms"])
            if h is None or abs(h["epoch_ms"] - r["epoch_ms"]) > 600:
                continue
            for key, hv in h.get("hunters", {}).items():
                gv = r.get("hunters", {}).get(key)
                if gv is None or hv.get("state") != "CHASE":
                    continue
                pairs += 1
                if gv.get("chase_style") != hv.get("chase_style"):
                    mism_style += 1
                    examples.append("%s %s style %s vs host %s" % (n, hv["id"], gv.get("chase_style"), hv.get("chase_style")))
                if hv["id"] == "kathy" and gv.get("beam") != hv.get("beam"):
                    mism_beam += 1
                    examples.append("%s kathy beam %s vs host %s at t=%s" % (n, gv.get("beam"), hv.get("beam"), r["t"]))
                if gv.get("state") != hv.get("state"):
                    mism_state += 1
    check("4 chase style / Kathy beam", pairs > 0 and mism_style == 0 and mism_beam <= max(1, pairs // 20),
          "%d chase samples compared: style mismatches %d, beam mismatches %d, state mismatches %d; %s"
          % (pairs, mism_style, mism_beam, mism_state, "; ".join(examples[:4]) or "-"))

# 5. death screens on guest A and the host
for label, name, after in (("guest A", by_id.get(A), 238), ("host", host, 478)):
    if not name:
        continue
    flow = [r for r in peers[name]["rows"] if r["t"] >= after and (r.get("death_flow") or r.get("run_over"))]
    check("5 death screen on %s (%s)" % (label, name), bool(flow),
          "death flow / run over from t=%s (%d samples)" % (flow[0]["t"] if flow else "-", len(flow)))

# CrashWatch markers pulled by coop_airs.sh (<machine>/crash/): a session sentinel = not a clean quit, a freeze dump, queued reports
for d in sorted(p for p in out.iterdir() if p.is_dir()):
    for f in sorted((d / "crash").glob("*.json")) if (d / "crash").exists() else []:
        kind = ("crash: did not quit cleanly" if f.name == "crashwatch_session.json" else
                "freeze: main loop stalled and never came back" if f.name == "crashwatch_freeze.json" else
                "report: " + f.stem.rsplit("-", 1)[-1])
        try:
            crumbs = [str(c) for c in json.loads(f.read_text()).get("breadcrumbs", [])][-3:]
        except (OSError, ValueError, AttributeError):
            crumbs = []
        check("crash marker: " + d.name, False, kind + (" | last: " + " / ".join(c[:80] for c in crumbs) if crumbs else ""))

w = max(len(r["check"]) for r in results)
for r in results:
    print("%-*s  %s  %s" % (w, r["check"], "PASS" if r["pass"] else "FAIL", r["detail"]))
(out / "coop_compare.json").write_text(json.dumps(results, indent=1))
