"""Cube-style hunter builder: cubes -> atlas texture -> rigged glTF (.glb) + Blockbench .bbmodel.

A hunter is a list of `Cube`s attached to bones of the shared rig (see rig.py).
Cube geometry is authored in *design metres* in world rest pose, feet at y = 0,
facing -Z (the way the game walks the hunter). Every cube face is painted
per-texel by a painter function that receives the texel's 3D position, so
stripes, checks and belts stay continuous across cubes and faces.
"""
import json, math, struct, hashlib
from dataclasses import dataclass, field
from typing import Callable, Optional
from PIL import Image

PX = 1.0 / 32.0          # default texel size: 1 texel = 3.125 cm of design space
ATLAS_W, ATLAS_H = 128, 256
FACE_CELL = (16, 10)     # shared expression cell size (texels)
FACE_COLS, FACE_ROWS = 3, 3

# face -> (u axis, u sign, v axis, v sign, normal axis, normal sign); u x v = -normal
FACES = {
    "N": (0, -1, 1, -1, 2, -1),   # front (-Z)
    "S": (0, +1, 1, -1, 2, +1),   # back
    "E": (2, -1, 1, -1, 0, +1),
    "W": (2, +1, 1, -1, 0, -1),
    "U": (0, -1, 2, -1, 1, +1),
    "D": (0, -1, 2, +1, 1, -1),
}


def rot_matrix(rx, ry, rz):
    """Euler degrees, applied X then Y then Z (matches Blockbench)."""
    a, b, c = (math.radians(v) for v in (rx, ry, rz))
    ca, sa, cb, sb, cc, sc = math.cos(a), math.sin(a), math.cos(b), math.sin(b), math.cos(c), math.sin(c)
    rxm = [[1, 0, 0], [0, ca, -sa], [0, sa, ca]]
    rym = [[cb, 0, sb], [0, 1, 0], [-sb, 0, cb]]
    rzm = [[cc, -sc, 0], [sc, cc, 0], [0, 0, 1]]
    return mm(rzm, mm(rym, rxm))


def mm(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def mv(m, v):
    return tuple(sum(m[i][k] * v[k] for k in range(3)) for i in range(3))


def hash01(*ints):
    h = 2166136261
    for v in ints:
        h = ((h ^ (int(v) & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF
        h ^= h >> 13
        h = (h * 0x5bd1e995) & 0xFFFFFFFF
    return (h ^ (h >> 15)) / 4294967295.0


@dataclass
class Cube:
    name: str
    bone: str
    lo: tuple
    hi: tuple
    paint: Optional[Callable] = None          # paint(face, p, ctx) -> colour
    rot: tuple = (0, 0, 0)
    pivot: Optional[tuple] = None             # rotation pivot, default cube centre
    px: float = PX
    faces: str = "NSEWUD"
    group: str = ""                           # "face" for the expression quad
    uv: Optional[dict] = None                 # fixed face -> (x, y, w, h) rects (vanilla skin box UV)
    post: Optional[Callable] = None           # post(imgs) hand-drawn details

    def size(self):
        return tuple(self.hi[i] - self.lo[i] for i in range(3))

    def center(self):
        return tuple((self.hi[i] + self.lo[i]) / 2 for i in range(3))

    def face_px(self, f):
        s = self.size()
        ua, _, va, _, _, _ = FACES[f]
        return max(1, round(s[ua] / self.px)), max(1, round(s[va] / self.px))


class Atlas:
    def __init__(self, w=ATLAS_W, h=ATLAS_H):
        self.w, self.h = w, h
        self.img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        self.occ = [[False] * w for _ in range(h)]

    def place(self, rw, rh, gap=1):
        for y in range(0, self.h - rh + 1):
            for x in range(0, self.w - rw + 1):
                if self._free(x, y, rw + gap, rh + gap):
                    self._take(x, y, rw + gap, rh + gap)
                    return x, y
        raise RuntimeError("atlas full (%dx%d) placing %dx%d" % (self.w, self.h, rw, rh))

    def _free(self, x, y, w, h):
        for yy in range(y, min(y + h, self.h)):
            row = self.occ[yy]
            for xx in range(x, min(x + w, self.w)):
                if row[xx]:
                    return False
        return True

    def _take(self, x, y, w, h):
        for yy in range(y, min(y + h, self.h)):
            for xx in range(x, min(x + w, self.w)):
                self.occ[yy][xx] = True


class Model:
    def __init__(self, name, rig, cubes, scale=1.0, face_painter=None, extras=None, skin=None, face_cell=None,
                 face_at=None):
        self.name, self.rig, self.cubes, self.scale = name, rig, cubes, scale
        self.face_painter = face_painter
        self.extras = extras or {}
        self.face_cell = face_cell or FACE_CELL
        self.face_at = face_at
        self.atlas = Atlas(*skin.size) if skin is not None else Atlas()
        if skin is not None:
            self.atlas.img = skin.copy()
            for y in range(skin.height):          # a vanilla skin is fully laid out: nothing to pack
                self.atlas.occ[y] = [True] * skin.width
        self.face_origin = None
        self.uv = {}       # (cube idx, face) -> (x, y, w, h) texel rect
        self._paint_all()

    # ---- texturing -------------------------------------------------------
    def _paint_all(self):
        atlas = self.atlas
        # shared expression sheet first: fixed 3x2 block of 18x12 cells
        fc = [c for c in self.cubes if c.group == "face"]
        if fc:
            cw, ch = self.face_cell
            bw, bh = cw * FACE_COLS, ch * FACE_ROWS
            self.face_origin = self.face_at or atlas.place(bw, bh)
            for k in range(FACE_COLS * FACE_ROWS):
                cell = self.face_painter(k)
                if cell is None:
                    continue
                ox = self.face_origin[0] + (k % FACE_COLS) * cw
                oy = self.face_origin[1] + (k // FACE_COLS) * ch
                atlas.img.paste(cell, (ox, oy))
        order = sorted(range(len(self.cubes)),
                       key=lambda i: -max(self.cubes[i].face_px(f)[1] for f in self.cubes[i].faces))
        for i in order:
            c = self.cubes[i]
            if c.group == "face":
                continue
            if c.uv:
                for f in c.faces:
                    self.uv[(i, f)] = c.uv[f]
                continue
            imgs = {}
            for f in c.faces:
                w, h = c.face_px(f)
                imgs[f] = Image.new("RGBA", (w, h), (0, 0, 0, 0))
                self._paint_face(c, f, imgs[f])
            if c.post:
                c.post(imgs)
            for f in c.faces:
                w, h = imgs[f].size
                x, y = atlas.place(w, h)
                atlas.img.paste(imgs[f], (x, y))
                self.uv[(i, f)] = (x, y, w, h)
        for i, c in enumerate(self.cubes):
            if c.group == "face":
                self.uv[(i, "N")] = (self.face_origin[0], self.face_origin[1], self.face_cell[0], self.face_cell[1])

    def _paint_face(self, c, f, img):
        if c.paint is None:
            return
        ua, us, va, vs, na, ns = FACES[f]
        w, h = img.size
        size = c.size()
        px = img.load()
        for j in range(h):
            for i in range(w):
                p = [0.0, 0.0, 0.0]
                p[na] = c.hi[na] if ns > 0 else c.lo[na]
                fu, fv = (i + .5) / w, (j + .5) / h
                p[ua] = (c.lo[ua] + fu * size[ua]) if us > 0 else (c.hi[ua] - fu * size[ua])
                p[va] = (c.lo[va] + fv * size[va]) if vs > 0 else (c.hi[va] - fv * size[va])
                col = c.paint(f, tuple(p), (i, j, w, h))
                if col is not None:
                    px[i, j] = tuple(int(round(v)) for v in (col if len(col) == 4 else (*col, 255)))

    # ---- geometry --------------------------------------------------------
    def cube_faces(self, ci):
        """Yield (face, 4 world corners TL,TR,BR,BL, normal) in design metres."""
        c = self.cubes[ci]
        piv = c.pivot or c.center()
        m = rot_matrix(*c.rot)
        size = c.size()
        for f in c.faces:
            ua, us, va, vs, na, ns = FACES[f]
            def pt(fu, fv):
                p = [0.0, 0.0, 0.0]
                p[na] = c.hi[na] if ns > 0 else c.lo[na]
                p[ua] = (c.lo[ua] + fu * size[ua]) if us > 0 else (c.hi[ua] - fu * size[ua])
                p[va] = (c.lo[va] + fv * size[va]) if vs > 0 else (c.hi[va] - fv * size[va])
                d = tuple(p[k] - piv[k] for k in range(3))
                r = mv(m, d)
                return tuple(r[k] + piv[k] for k in range(3))
            n = [0, 0, 0]
            n[na] = ns
            yield f, [pt(0, 0), pt(1, 0), pt(1, 1), pt(0, 1)], mv(m, tuple(n))

    # ---- output ----------------------------------------------------------
    def triangle_count(self):
        return sum(2 for ci in range(len(self.cubes)) for _ in self.cubes[ci].faces)

    def texture_png(self):
        import io
        b = io.BytesIO()
        self.atlas.img.save(b, "PNG", optimize=True)
        return b.getvalue()


def quat_from_euler(rx, ry, rz):
    """Degrees XYZ (applied X, then Y, then Z) -> (x, y, z, w)."""
    m = rot_matrix(rx, ry, rz)
    return quat_from_matrix(m)


def quat_from_matrix(m):
    tr = m[0][0] + m[1][1] + m[2][2]
    if tr > 0:
        s = math.sqrt(tr + 1) * 2
        return ((m[2][1] - m[1][2]) / s, (m[0][2] - m[2][0]) / s, (m[1][0] - m[0][1]) / s, s / 4)
    i = max(range(3), key=lambda k: m[k][k])
    j, k = (i + 1) % 3, (i + 2) % 3
    s = math.sqrt(m[i][i] - m[j][j] - m[k][k] + 1) * 2
    q = [0, 0, 0, 0]
    q[i] = s / 4
    q[3] = (m[k][j] - m[j][k]) / s
    q[j] = (m[j][i] + m[i][j]) / s
    q[k] = (m[k][i] + m[i][k]) / s
    return tuple(q)


def quat_mul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw * bx + ax * bw + ay * bz - az * by,
            aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw,
            aw * bw - ax * bx - ay * by - az * bz)
