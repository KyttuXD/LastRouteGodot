"""A floating square halo for the haloed hunters (Porcelle, Mavrine, Solyth).

Four flat bars forming a ring above the head, tilted back a little, on a Halo bone that wobbles gently in every
clip. The halo ring that was painted on the skin's hat layer is removed (it is geometry now)."""
from bb_core import Cube
from bb_skin import m

SWATCH = {"ring": (52, 66, 2, 2), "top": (54, 66, 2, 2)}
EXTRAS = [("Halo", "Head", (m(0.0), m(34.6), m(0.0)), (3, 3, 1, 0.0))]


def modify(canvas, color):
    light = tuple(min(255, int(v * .7 + 255 * .3)) for v in color)
    for y in range(0, 16):                          # the painted ring (hat layer) -> transparent
        for x in range(32, 64):
            p = canvas.getpixel((x, y))
            if p[3] and p[:3] == tuple(color):
                canvas.putpixel((x, y), (0, 0, 0, 0))
    for key, c in (("ring", color), ("top", light)):
        x, y, w, h = SWATCH[key]
        for j in range(h):
            for i in range(w):
                canvas.putpixel((x + i, y + j), (*c, 255))
    uv = {f: SWATCH["ring"] for f in "ENWSD"}
    uv["U"] = SWATCH["top"]
    y0, y1, half, t = 34.2, 34.9, 3.6, 0.9          # ring 7.2 px across, bars 0.9 px thick
    bars = [("back", (-half, y0, half - t), (half, y1, half)), ("front", (-half, y0, -half), (half, y1, -half + t)),
            ("left", (-half, y0, -half + t), (-half + t, y1, half - t)), ("right", (half - t, y0, -half + t), (half, y1, half - t))]
    return [Cube(f"halo-{n}", "Halo", (m(a[0]), m(a[1]), m(a[2])), (m(b[0]), m(b[1]), m(b[2])), uv=uv,
                 rot=(-8, 0, 0), pivot=(0, m(34.55), 0)) for n, a, b in bars]
