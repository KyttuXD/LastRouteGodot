"""Kathy's scythe as a cube-style 3D prop: assets/props_3d/kathy_scythe.glb (+ atlas png + .bbmodel).

Design = the 32x32 icon LastRoute-3D-refs/kathy-scythe-icon.png: brown wooden shaft, gold socket, a curved blade
of purple with a bright red cutting edge along the inner curve, black-purple back edge. Built from boxes only
(a blade of 8 stacked, angled boxes), painted per texel from the icon's own palette.

Origin = the grip point (a `Grip` node at (0,0,0), shaft along +Y, blade curving forward = -Z, the way the hunters
face), so it can be added under a hunter's `R-HandProp` with identity transform: blade up and forward.

  python3 tools/blocky_hunters/build_scythe.py"""
import math, pathlib, sys
HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from bb_core import Cube, Model, hash01
import bb_gltf

REPO = HERE.parent.parent
OUT = REPO / "assets" / "props_3d"

# palette sampled from the icon
WOOD = [(158, 76, 32), (113, 52, 21), (97, 45, 18), (78, 39, 17), (170, 84, 37)]
GOLD, GOLD_D, GOLD_L = (244, 173, 19), (170, 110, 12), (255, 214, 90)
PURPLE, PURPLE_D, PURPLE_L, VIOLET = (62, 33, 103), (32, 20, 58), (91, 35, 142), (156, 78, 204)
RED, RED_M, RED_D, CRIMSON = (233, 19, 23), (197, 5, 17), (139, 3, 22), (142, 3, 57)
BLACK = (22, 12, 34)
LEATHER, LEATHER_L = (46, 30, 24), (96, 62, 40)


def shaft_paint(face, p, n):
    y = p[1]
    row = int((y + 0.6) / 0.025)
    if -0.16 <= y <= 0.22:                                 # grip wrap: dark leather with diagonal bands
        return LEATHER_L if (row + (1 if face in "NW" else 0)) % 3 == 0 else LEATHER
    c = WOOD[int(hash01(row, 3) * 3)]
    if face in "EN" and hash01(row, 9) < .45:
        c = WOOD[4]                                        # lit side
    return c


def knob_paint(face, p, n):
    return GOLD if p[1] > -0.495 else (GOLD_D if face != "U" else GOLD_L) if p[1] > -0.51 else (50, 34, 26)


def gold_paint(face, p, n):
    if face == "U":
        return GOLD_L
    return GOLD_D if hash01(n[0], n[1], 5) < .25 else GOLD


def blade_paint(i, N, y_hi, w, z_lo, L):
    def paint(face, p, n):
        s = (z_lo + L - p[2]) / L                           # 0 at the root end of this segment, 1 at its tip end
        t = (i + max(0.0, min(1.0, s))) / N                 # along the whole blade
        v = (y_hi - p[1]) / w                               # 0 = back edge, 1 = cutting edge
        h = hash01(n[0], n[1], i, 1 if face == "E" else 2)
        if face == "U":
            return PURPLE_D if h < .7 else PURPLE
        if face in "NS":
            return BLACK
        if face == "D":                                     # the cutting edge itself
            return RED if h < .55 else RED_M if h < .8 else RED_D
        if v > .74 - .1 * t:                                # red edge band along the inner curve
            if t < .22 and h < .4:
                return CRIMSON
            return RED if h < .5 else RED_M if h < .8 else RED_D
        if v > .6:
            return (103, 11, 83) if h < .5 else PURPLE_D
        if v < .12:
            return PURPLE_D
        if t > .88:
            return BLACK if h < .5 else PURPLE_D
        if t < .5 and v < .38 and h < .38:
            return VIOLET if h < .2 else (111, 49, 150)     # purple sheen toward the root
        return PURPLE if (n[0] + n[1]) % 2 == 0 else (PURPLE_L if h < .22 else (74, 27, 103))
    return paint


def build_cubes():
    cubes = []
    cubes.append(Cube("shaft", "Grip", (-0.025, -0.47, -0.025), (0.025, 1.04, 0.025), paint=shaft_paint, px=0.025))
    cubes.append(Cube("knob", "Grip", (-0.04, -0.55, -0.04), (0.04, -0.45, 0.04), paint=knob_paint, px=0.02))
    cubes.append(Cube("collar", "Grip", (-0.04, 0.94, -0.04), (0.04, 1.05, 0.04), paint=gold_paint, px=0.02))
    cubes.append(Cube("socket", "Grip", (-0.032, 0.99, -0.11), (0.032, 1.11, -0.03), paint=gold_paint, px=0.02))
    # blade: 8 boxes along an arc that starts forward and a little up, then curls down and back toward the shaft
    N, L, th0, dth = 8, 0.10, 14.0, -15.0
    y, z = 1.05, -0.085                                      # start of the cutting-edge line, at the socket
    for i in range(N):
        th = th0 + dth * i
        w = max(0.03, 0.17 * (1 - i / N) ** 0.85 + 0.02)
        a = math.radians(th)
        d = (math.sin(a), -math.cos(a))                      # (dy, dz): direction of travel
        nrm = (math.cos(a), math.sin(a))                     # towards the back (convex) edge
        cy = y + d[0] * L / 2 + nrm[0] * w / 2
        cz = z + d[1] * L / 2 + nrm[1] * w / 2
        Lc = L * 1.13                                        # overlap so the stack has no gaps
        lo = (-0.02, cy - w / 2, cz - Lc / 2)
        hi = (0.02, cy + w / 2, cz + Lc / 2)
        cubes.append(Cube(f"blade-{i}", "Grip", lo, hi, rot=(th, 0, 0), px=0.014,
                          paint=blade_paint(i, N, hi[1], w, lo[2], Lc)))
        y, z = y + d[0] * L, z + d[1] * L
    return cubes


def main():
    bones = [{"name": "Grip", "parent": None, "pivot": (0.0, 0.0, 0.0), "rot": (0, 0, 0, 1), "sway": None}]
    model = Model("kathy_scythe", bones, build_cubes(), scale=1.0, atlas_size=(64, 128))
    OUT.mkdir(parents=True, exist_ok=True)
    size = bb_gltf.write_glb(model, bones, {}, OUT / "kathy_scythe.glb", scale=1.0)
    model.atlas.img.save(OUT / "kathy_scythe_atlas.png")
    bb_gltf.write_bbmodel(model, bones, OUT / "kathy_scythe.bbmodel")
    ys = [c.hi[1] for c in model.cubes] + [c.lo[1] for c in model.cubes]
    print("kathy_scythe: %d tris, %d cubes, %.1f KB, %.2f m long (y %.2f..%.2f)" % (
        model.triangle_count(), len(model.cubes), size / 1024, max(ys) - min(ys), min(ys), max(ys)))


if __name__ == "__main__":
    main()
