#!/usr/bin/env python3
"""
Proves the merged office map is actually WALKABLE, not merely adjacent.

Rooms can abut perfectly and still be sealed off -- that was true of the first
merged build, where every wall was solid and the map was nine boxes touching.
This flood-fills a 2D occupancy grid at hunter height from the office seat and
asserts every camera waypoint is reachable, which is the only thing that makes
"hunters walk from room to room" possible.

Height matters: the test runs at 0.55 m, below the vents' 1.3 m ceiling, so a
route that only exists as a crawl still counts.

    python3 check_map_connectivity.py map.bbmodel
"""
import json, sys
from collections import deque

M = 64.0
CELL = 0.12          # metres per grid cell
HEIGHT = 0.55        # sample plane: above the floor, under the vent ceiling

# Modelled closed but opened at runtime, so they are not walls. The office
# shutters are the obvious case -- with them counted, nothing outside the
# office is reachable and the test says the map is broken when it is not.
DYNAMIC = ("Office_LeftDoor", "Office_RightDoor")


def build_grid(model):
    solids = []
    for e in model["elements"]:
        if e["name"] in DYNAMIC:
            continue
        a = [c / M for c in e["from"]]
        b = [c / M for c in e["to"]]
        if a[1] <= HEIGHT <= b[1]:
            solids.append((a[0], a[2], b[0], b[2]))
    xs = [c / M for e in model["elements"] for c in (e["from"][0], e["to"][0])]
    zs = [c / M for e in model["elements"] for c in (e["from"][2], e["to"][2])]
    x0, z0 = min(xs) - 1, min(zs) - 1
    w = int((max(xs) + 1 - x0) / CELL)
    h = int((max(zs) + 1 - z0) / CELL)
    grid = bytearray(w * h)
    for (ax, az, bx, bz) in solids:
        i0, i1 = max(0, int((ax - x0) / CELL)), min(w - 1, int((bx - x0) / CELL))
        j0, j1 = max(0, int((az - z0) / CELL)), min(h - 1, int((bz - z0) / CELL))
        for j in range(j0, j1 + 1):
            row = j * w
            for i in range(i0, i1 + 1):
                grid[row + i] = 1
    return grid, w, h, x0, z0


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "office_map.bbmodel"
    model = json.load(open(path))
    grid, w, h, x0, z0 = build_grid(model)
    navs = {g["name"][4:]: (g["origin"][0] / M, g["origin"][2] / M)
            for g in model.get("groups", []) if g["name"].startswith("Nav_")}
    if not navs:
        print("no Nav_* waypoints in this model")
        return 1

    def cell(p):
        return int((p[0] - x0) / CELL), int((p[1] - z0) / CELL)

    si, sj = cell((0.0, 1.0))                 # the office seat
    if grid[sj * w + si]:
        print("start cell (office seat) is inside geometry")
        return 1
    seen = bytearray(w * h)
    seen[sj * w + si] = 1
    q = deque([(si, sj)])
    reached = 0
    while q:
        i, j = q.popleft()
        reached += 1
        for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ni, nj = i + di, j + dj
            if 0 <= ni < w and 0 <= nj < h and not seen[nj * w + ni] \
                    and not grid[nj * w + ni]:
                seen[nj * w + ni] = 1
                q.append((ni, nj))

    print(f"grid {w}x{h} @ {CELL} m, sampled at y={HEIGHT} m")
    print(f"reachable floor from the office seat: {reached} cells "
          f"({reached * CELL * CELL:.0f} m2)\n")
    bad = []
    for cam in sorted(navs):
        ci, cj = cell(navs[cam])
        # A waypoint can land inside a crate; accept any free cell within 1 m.
        r = int(1.0 / CELL)
        ok = any(0 <= ci + di < w and 0 <= cj + dj < h and seen[(cj + dj) * w + ci + di]
                 for dj in range(-r, r + 1) for di in range(-r, r + 1))
        print(f"  {cam}  {'reachable  ' if ok else 'UNREACHABLE'} "
              f"({navs[cam][0]:+6.1f}, {navs[cam][1]:+6.1f})")
        if not ok:
            bad.append(cam)
    if bad:
        print(f"\nUNREACHABLE: {', '.join(bad)}")
        return 1
    print(f"\nall {len(navs)} cameras walkable from the office")
    return 0


if __name__ == "__main__":
    sys.exit(main())
