"""Hanging hair chains from the anime sheets: twin tails (Javelle), braided pigtails (Porcelle), and the side braid
or lock over one shoulder (Quenelle, Thessine, Umbriel, Solyth).

A chain is a tie plus stacked segments, one bone per segment (so it swings in every clip), in the hunter's own
flat hair colour. `beads` makes a braid look (alternate segments slightly narrower)."""
from bb_core import Cube
from bb_skin import m

SWATCH = {"hair": (58, 68, 2, 2), "tie": (60, 68, 2, 2)}


def paint(canvas, colour, tie=None):
    tie = tie or tuple(int(v * .5) for v in colour)
    for key, c in (("hair", colour), ("tie", tie)):
        x, y, w, h = SWATCH[key]
        for j in range(h):
            for i in range(w):
                canvas.putpixel((x + i, y + j), (*c, 255))


def chain(side, name, x, z, tie_y, spans, zigzag=0.0, beads=False, drift=0.0, tie=True, sway=(6, 5)):
    """side 'L'/'R' (L = -X). spans: list of (y_bottom, y_top, width, depth). Returns (extras, cubes).
    Bones are {side}-{name}-1..N, parented in a chain starting on the Head."""
    extras, cubes = [], []
    s = -1 if side == "L" else 1
    sw, tw = SWATCH["hair"], SWATCH["tie"]
    for i, (y0, y1, w, d) in enumerate(spans):
        bone = f"{side}-{name}-{i + 1}"
        parent = "Head" if i == 0 else f"{side}-{name}-{i}"
        cx = s * x + s * drift * i + (zigzag * (1 if i % 2 else -1))
        zc = z + 0.1 * i
        width = w * (0.8 if beads and i % 2 else 1.0)
        extras.append((bone, parent, (m(s * x), m(y1), m(z)), (sway[0], sway[1], 1, 0.5 * i + (0 if s < 0 else 0.6))))
        cubes.append(Cube(f"{side}-{name.lower()}-{i + 1}", bone, (m(cx - width / 2), m(y0), m(zc - d / 2)),
                          (m(cx + width / 2), m(y1), m(zc + d / 2)), uv={f: sw for f in "ENWSUD"}))
        if beads and i < len(spans) - 1:               # a little tie between braid sections
            cubes.append(Cube(f"{side}-{name.lower()}-bead-{i + 1}", bone, (m(cx - w / 2 - .2), m(y0 - .5), m(zc - d / 2 - .2)),
                              (m(cx + w / 2 + .2), m(y0 + .3), m(zc + d / 2 + .2)), uv={f: tw for f in "ENWSUD"}))
    if tie:
        y1 = spans[0][1]
        cubes.append(Cube(f"{side}-{name.lower()}-tie", f"{side}-{name}-1", (m(s * x - .9), m(y1 - .8), m(z - spans[0][3] / 2 - .1)),
                          (m(s * x + .9), m(y1 + .8), m(z + spans[0][3] / 2 + .1)), uv={f: tw for f in "ENWSUD"}))
    return extras, cubes
