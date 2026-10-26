"""Cube-built emblems floating behind the head: Nyxie's moon and Solyth's sun.

The emblem is a pixel bitmap turned into boxes (one box per horizontal run), standing upright behind the head on
a Glyph bone that sways slowly in every clip. The art that was painted on the skin for it (the grey moon marks on
the head sides; the sun's ring and ray pieces) is removed, because it is geometry now."""
import math
from bb_core import Cube
from bb_skin import m

SWATCH = {"a": (52, 66, 2, 2), "b": (54, 66, 2, 2), "c": (56, 66, 2, 2)}
SIDE_X, GLYPH_Y, GLYPH_Z = 8.6, 33.2, 0.0              # one glyph beside each side of the head, facing outward
SIDES = (("R", 1, -90),)                                # one glyph only, on the character's right side
EXTRAS = [("R-Glyph", "Head", (m(SIDE_X), m(GLYPH_Y), m(GLYPH_Z)), (3, 3, 1, 0.5, -10))]


def _paint_swatches(canvas, a, b, c):
    for key, col in (("a", a), ("b", b), ("c", c)):
        x, y, w, h = SWATCH[key]
        for j in range(h):
            for i in range(w):
                canvas.putpixel((x + i, y + j), (*col, 255))


def _boxes(bitmap, cell=1.0, depth_of=lambda ch: 1.0):
    """bitmap: rows of chars ('.', 'a', 'b', 'c'), each cell `cell` skin px wide. Built once per side, centred on
    that side's Glyph bone and turned to face outward (about the bone pivot)."""
    h, w = len(bitmap), len(bitmap[0])
    cubes = []
    for side, s, yaw in SIDES:
        cx, cy, zc = s * SIDE_X, GLYPH_Y, GLYPH_Z
        pv = (m(cx), m(cy), m(zc))
        cubes += _side_boxes(bitmap, side, cx, cy, zc, cell, depth_of, yaw, pv)
    return cubes


def _side_boxes(bitmap, side, cx, cy, zc, cell, depth_of, yaw, pv):
    h, w = len(bitmap), len(bitmap[0])
    cubes = []
    for j, row in enumerate(bitmap):
        i = 0
        while i < w:
            ch = row[i]
            if ch == ".":
                i += 1
                continue
            k = i
            while k < w and row[k] == ch:
                k += 1
            x0, x1 = cx + (i - w / 2) * cell, cx + (k - w / 2) * cell
            y1 = cy + (h / 2 - j) * cell
            d = depth_of(ch)
            sw = SWATCH[ch]
            cubes.append(Cube(f"{side}-glyph-{j}-{i}", f"{side}-Glyph", (m(x0), m(y1 - cell), m(zc - d / 2)),
                              (m(x1), m(y1), m(zc + d / 2)), uv={f: sw for f in "ENWSUD"}, rot=(0, yaw, 0), pivot=pv))
            i = k
    return cubes


def sun_bitmap():
    n, c = 15, 7
    rows = []
    for j in range(n):
        row = ""
        for i in range(n):
            dx, dy = i - c, j - c
            d = math.hypot(dx, dy)
            if d <= 3.7:
                row += "c" if d <= 2.0 else "b"
            elif (dx == 0 or dy == 0) and 5 <= max(abs(dx), abs(dy)) <= 7:
                row += "a"
            elif abs(dx) == abs(dy) and 4 <= abs(dx) <= 5:
                row += "a"
            else:
                row += "."
        rows.append(row)
    return rows


def moon_bitmap():
    n = 11
    rows = []
    for j in range(n):
        row = ""
        for i in range(n):
            d1 = math.hypot(i - 5, j - 5)
            d2 = math.hypot(i - 7.4, j - 4.2)
            row += ("b" if d1 <= 4.9 and d2 > 4.4 else ".")
        rows.append(row[::-1])           # opens to the viewer's right when seen from the front
    return rows


def sun(canvas, ring, ray, disc, ray2, clear):
    _clear(canvas, clear)
    _paint_swatches(canvas, ray, disc, ring)
    return _boxes(sun_bitmap(), cell=0.75, depth_of=lambda ch: 1.2 if ch in "bc" else 0.7)


def moon(canvas, moon_c, star, clear, hair):
    _clear(canvas, clear, hair)
    _paint_swatches(canvas, star, moon_c, star)
    cubes = _boxes(moon_bitmap(), cell=0.9, depth_of=lambda ch: 1.2)
    for side, s, yaw in SIDES:                                 # a few stars around the moon
        cx = s * SIDE_X
        pv = (m(cx), m(GLYPH_Y), m(GLYPH_Z))
        for k, (sx, sy) in enumerate(((-5.0, 3.0), (4.4, 4.6), (5.2, -3.2), (-3.8, -4.6))):
            cubes.append(Cube(f"{side}-star-{k}", f"{side}-Glyph", (m(cx + sx - .4), m(GLYPH_Y + sy - .4), m(GLYPH_Z - .25)),
                              (m(cx + sx + .4), m(GLYPH_Y + sy + .4), m(GLYPH_Z + .25)), uv={f: SWATCH["a"] for f in "ENWSUD"},
                              rot=(0, yaw, 0), pivot=pv))
    return cubes


def _clear(canvas, colours, hair=None):
    """Remove painted art of the given colours: hat layer -> transparent, head box -> hair colour."""
    for y in range(0, 16):
        for x in range(0, 64):
            p = canvas.getpixel((x, y))
            if p[3] and p[:3] in colours:
                if x >= 32:
                    canvas.putpixel((x, y), (0, 0, 0, 0))
                elif hair is not None:
                    canvas.putpixel((x, y), (*hair, 255))
