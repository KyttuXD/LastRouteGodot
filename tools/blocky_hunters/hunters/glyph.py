"""Cube-built emblems floating behind the head: Nyxie's moon and Solyth's sun.

The emblem is a pixel bitmap turned into boxes (one box per horizontal run), standing upright behind the head on
a Glyph bone that sways slowly in every clip. The art that was painted on the skin for it (the grey moon marks on
the head sides; the sun's ring and ray pieces) is removed, because it is geometry now."""
import math
from bb_core import Cube
from bb_skin import m

SWATCH = {"a": (52, 66, 2, 2), "b": (54, 66, 2, 2), "c": (56, 66, 2, 2)}
PIVOT = (0.0, 35.0, 5.0)
EXTRAS = [("Glyph", "Head", (m(PIVOT[0]), m(PIVOT[1]), m(PIVOT[2])), (3, 3, 1, 0.0, 10))]


def _paint_swatches(canvas, a, b, c):
    for key, col in (("a", a), ("b", b), ("c", c)):
        x, y, w, h = SWATCH[key]
        for j in range(h):
            for i in range(w):
                canvas.putpixel((x + i, y + j), (*col, 255))


def _boxes(bitmap, cx, cy, depth_of, zc, cell=1.0):
    """bitmap: rows of chars ('.', 'a', 'b', 'c'); centre of the bitmap lands on (cx, cy) in skin px,
    each bitmap cell is `cell` skin px wide."""
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
            cubes.append(Cube(f"glyph-{j}-{i}", "Glyph", (m(x0), m(y1 - cell), m(zc - d / 2)), (m(x1), m(y1), m(zc + d / 2)),
                              uv={f: sw for f in "ENWSUD"}))
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
    return _boxes(sun_bitmap(), PIVOT[0], PIVOT[1], lambda ch: 1.2 if ch in "bc" else 0.7, PIVOT[2], cell=0.75)


def moon(canvas, moon_c, star, clear, hair):
    _clear(canvas, clear, hair)
    _paint_swatches(canvas, star, moon_c, star)
    cubes = _boxes(moon_bitmap(), PIVOT[0], PIVOT[1], lambda ch: 1.2, PIVOT[2], cell=0.9)
    for k, (sx, sy) in enumerate(((-6.0, 3.2), (5.0, 5.0), (6.2, -3.4), (-4.6, -5.0))):    # a few stars around it
        cubes.append(Cube(f"star-{k}", "Glyph", (m(sx - .4), m(PIVOT[1] + sy - .4), m(PIVOT[2] - .25)),
                          (m(sx + .4), m(PIVOT[1] + sy + .4), m(PIVOT[2] + .25)), uv={f: SWATCH["a"] for f in "ENWSUD"}))
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
