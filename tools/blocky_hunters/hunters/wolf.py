"""Wolf ears and a bushy wolf tail (Verrine, Haelith, Quirith).

Ears: tall pointed stepped ears (L-Ear/R-Ear bones, they twitch), lighter inside on the front.
Tail: four fat segments hanging down behind (Tail-1..4), swinging in every clip, with a pale tip.
The ear and tail art painted on the skin (ear marks on the head sides, the tail piece on the jacket back) is
removed from the texture, because it is geometry now."""
from bb_core import Cube
from bb_skin import m

SWATCH = {"base": (46, 66, 2, 2), "inner": (48, 66, 2, 2), "tip": (50, 66, 2, 2)}
_B = [("L-Ear", "Head", (-2.9, 32.0, -0.4), (0, 8, 3, 0.0)),
      ("R-Ear", "Head", (2.9, 32.0, -0.4), (0, -8, 3, 1.1)),
      ("Tail-1", "Pelvis", (0.0, 12.4, 2.3), (8, 3, 1, 0.0)),
      ("Tail-2", "Tail-1", (0.0, 8.8, 4.4), (11, 5, 1, 0.7)),
      ("Tail-3", "Tail-2", (0.0, 4.7, 5.0), (13, 6, 1, 1.4)),
      ("Tail-4", "Tail-3", (0.0, 1.8, 5.4), (14, 7, 1, 2.0))]
EXTRAS = [(n, par, (m(x), m(y), m(z)), sw) for n, par, (x, y, z), sw in _B]


def strip_art(canvas, hair):
    """Remove the painted ear marks (head side faces + hat layer sides/back) and the jacket-back tail piece."""
    skin = (255, 233, 219)
    for (rx, ry, rw, rh), is_hat in (((0, 8, 8, 8), False), ((16, 8, 8, 8), False),
                                      ((32, 8, 8, 8), True), ((48, 8, 8, 8), True), ((56, 8, 8, 8), True)):
        for y in range(ry, ry + rh):
            for x in range(rx, rx + rw):
                p = canvas.getpixel((x, y))
                if p[3] and p[:3] != tuple(hair) and p[:3] != skin:
                    canvas.putpixel((x, y), (0, 0, 0, 0) if is_hat else (*hair, 255))
    for y in range(36, 48):
        for x in range(32, 40):
            canvas.putpixel((x, y), (0, 0, 0, 0))


def modify(canvas, base, tip=(232, 236, 245)):
    strip_art(canvas, base)
    inner = tuple(int(v * .55 + 255 * .45) for v in base)
    for key, c in (("base", base), ("inner", inner), ("tip", tip)):
        x, y, w, h = SWATCH[key]
        for j in range(h):
            for i in range(w):
                canvas.putpixel((x + i, y + j), (*c, 255))

    def box(name, bone, x, y0, y1, w, d, zc, uv, rot=(0, 0, 0), pivot=None):
        return Cube(name, bone, (m(x - w / 2), m(y0), m(zc - d / 2)), (m(x + w / 2), m(y1), m(zc + d / 2)),
                    uv=uv, rot=rot, pivot=(m(pivot[0]), m(pivot[1]), m(pivot[2])) if pivot else None)
    plain = {f: SWATCH["base"] for f in "ENWSUD"}
    front = dict(plain, N=SWATCH["inner"])
    tipped = {f: SWATCH["tip"] for f in "ENWSUD"}
    cubes = []
    for side, s in (("L", -1), ("R", 1)):
        roll, b = -s * 6, f"{side}-Ear"
        pv = (s * 2.9, 32.0, -0.4)
        cubes += [box(f"{side}-ear-base", b, s * 2.9, 32.0, 34.4, 3.0, 1.8, -0.4, front, rot=(0, 0, roll), pivot=pv),
                  box(f"{side}-ear-mid", b, s * 2.85, 34.4, 36.2, 2.2, 1.4, -0.4, front, rot=(0, 0, roll), pivot=pv),
                  box(f"{side}-ear-tip", b, s * 2.8, 36.2, 37.6, 1.2, 1.0, -0.4, plain, rot=(0, 0, roll), pivot=pv)]
    cubes += [
        box("tail-1", "Tail-1", 0.0, 8.4, 12.6, 3.0, 2.8, 3.8, plain, rot=(-10, 0, 0), pivot=(0, 12.4, 2.3)),
        box("tail-2", "Tail-2", 0.0, 4.4, 8.8, 3.8, 3.4, 4.9, plain),
        box("tail-3", "Tail-3", 0.0, 1.4, 4.8, 3.6, 3.2, 5.4, plain),
        box("tail-4", "Tail-4", 0.0, 0.3, 1.8, 2.4, 2.4, 5.6, tipped),
    ]
    return cubes
