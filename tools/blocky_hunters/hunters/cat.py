"""Cat ears and a cat tail for the cat-folk hunters (Ilyra, Eirys).

Ears: two stepped ears on the top of the head (L-Ear/R-Ear bones, they twitch), pink inside on the front.
Tail: four segments curling up behind (Tail-1..4), swishing in every clip, the last one a lighter tip.
Colours come from the skin: the head/hair colour for ears and tail; any ear marks painted on the skin's face
are cleared by the hunter's own module."""
from bb_core import Cube
from bb_skin import m

SWATCH = {"base": (46, 66, 2, 2), "inner": (48, 66, 2, 2), "tip": (50, 66, 2, 2)}

_B = [("L-Ear", "Head", (-2.8, 32.0, -0.4), (0, 10, 3, 0.0)),
      ("R-Ear", "Head", (2.8, 32.0, -0.4), (0, -10, 3, 1.3)),
      ("Tail-1", "Pelvis", (0.0, 11.4, 2.3), (9, 3, 1, 0.0)),
      ("Tail-2", "Tail-1", (0.0, 11.6, 5.0), (12, 6, 1, 0.7)),
      ("Tail-3", "Tail-2", (0.0, 14.4, 6.2), (14, 8, 1, 1.4)),
      ("Tail-4", "Tail-3", (0.0, 17.2, 6.4), (16, 9, 1, 2.0))]
EXTRAS = [(n, par, (m(x), m(y), m(z)), sw) for n, par, (x, y, z), sw in _B]


def modify(canvas, base, inner, tip, clear=()):
    """clear: skin rects (x, y, w, h) holding the ear/tail art that is geometry now: made transparent."""
    for (rx, ry, rw, rh) in clear:
        for y in range(ry, ry + rh):
            for x in range(rx, rx + rw):
                canvas.putpixel((x, y), (0, 0, 0, 0))
    for key, c in (("base", base), ("inner", inner), ("tip", tip)):
        x, y, w, h = SWATCH[key]
        for j in range(h):
            for i in range(w):
                canvas.putpixel((x + i, y + j), (*c, 255))

    def box(name, bone, x, y0, y1, w, d, zc, faces_uv, rot=(0, 0, 0), pivot=None):
        return Cube(name, bone, (m(x - w / 2), m(y0), m(zc - d / 2)), (m(x + w / 2), m(y1), m(zc + d / 2)),
                    uv=faces_uv, rot=rot, pivot=(m(pivot[0]), m(pivot[1]), m(pivot[2])) if pivot else None)
    plain = {f: SWATCH["base"] for f in "ENWSUD"}
    front_inner = dict(plain, N=SWATCH["inner"])
    tipped = {f: SWATCH["tip"] for f in "ENWSUD"}
    cubes = []
    for side, s in (("L", -1), ("R", 1)):
        roll = -s * 8                                   # ears lean slightly outward
        cubes.append(box(f"{side}-ear-base", f"{side}-Ear", s * 2.8, 32.0, 33.8, 2.8, 1.6, -0.4, front_inner,
                         rot=(0, 0, roll), pivot=(s * 2.8, 32.0, -0.4)))
        cubes.append(box(f"{side}-ear-tip", f"{side}-Ear", s * 2.9, 33.8, 35.3, 1.8, 1.2, -0.4, front_inner,
                         rot=(0, 0, roll), pivot=(s * 2.8, 32.0, -0.4)))
    cubes += [
        box("tail-1", "Tail-1", 0.0, 10.4, 12.4, 1.9, 3.0, 3.8, plain),
        box("tail-2", "Tail-2", 0.0, 11.0, 14.6, 1.8, 1.8, 5.9, plain),
        box("tail-3", "Tail-3", 0.0, 14.4, 17.4, 1.6, 1.6, 6.3, plain),
        box("tail-4", "Tail-4", 0.0, 17.2, 19.6, 1.5, 1.5, 6.5, tipped),
    ]
    return cubes
