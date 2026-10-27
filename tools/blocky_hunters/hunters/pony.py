"""3D ponytails for the hunters whose skin paints a strand of hair down the back.

The strand painted on the body back (and jacket back) is measured (colour, width, length), removed from the
skin, and rebuilt as a tie plus four tapering, bone-swinging segments hanging from the back of the head
(Pony-1..3). Colour is the strand's own colour, flat, exactly like the hair on the skin."""
from collections import Counter
from bb_core import Cube
from bb_skin import m

HAIRY = ("aki briselle ceryth ferryn glyra haelith javelle loxelle mavrine nyxie opalie porcelle ravelle thessine "
         "umbriel wynelle ysolde zellia").split()
SWATCH = {"hair": (58, 66, 2, 2), "tie": (60, 66, 2, 2)}
EXTRAS = [("Pony-1", "Head", (m(0.0), m(31.0), m(4.6)), (7, 3, 1, 0.0)),
          ("Pony-2", "Pony-1", (m(0.0), m(27.0), m(6.3)), (9, 4, 1, 0.7)),
          ("Pony-3", "Pony-2", (m(0.0), m(22.5), m(6.6)), (12, 5, 1, 1.4))]


def measure(canvas):
    """Return (strand colour, top width px, length rows) of the hair strand painted on the body back, or None."""
    rect = [(x, y) for y in range(20, 32) for x in range(32, 40)]
    px = {p: canvas.getpixel(p)[:3] for p in rect if canvas.getpixel(p)[3]}
    near = lambda a, b, tol=30: sum(abs(i - j) for i, j in zip(a, b)) < tol
    hair = canvas.getpixel((12, 3))[:3]
    dark = lambda c: sum(c) < 100
    if sum(1 for c in px.values() if near(c, hair)) >= 10:
        # the strand is her own hair colour: the body is the commonest *other* colour (the shirt, not the strand)
        colour = hair
        rest = [c for c in px.values() if not near(c, hair) and not dark(c)]
        if not rest:
            return None
        body = Counter(rest).most_common(1)[0][0]
        strand = [p for p, c in px.items() if near(c, hair)]
        far = strand
    else:
        body = Counter(px.values()).most_common(1)[0][0]
        far = [p for p, c in px.items() if sum(abs(i - j) for i, j in zip(c, body)) > 40 and sum(c) > 60]
        if len(far) < 10:
            return None
        colour = Counter(px[p] for p in far).most_common(1)[0][0]
        strand = [p for p in far if near(px[p], colour)]
    rows = max(y for _, y in strand) - 20 + 1
    top = [p for p in strand if p[1] < 24]
    width = max(2.5, min(5.0, len(top) / 3.0 + 1.0)) if top else 3.2
    return colour, body, width, rows, strand


def apply(canvas, build=True):
    """Remove the painted strand (body back -> body colour, jacket back -> transparent) and return the cubes."""
    got = measure(canvas)
    if got is None:
        return []
    colour, body, width, rows, strand = got
    for x, y in strand:
        canvas.putpixel((x, y), (*body, 255))
    for y in range(36, 48):                        # same colour on the jacket back layer
        for x in range(32, 40):
            p = canvas.getpixel((x, y))
            if p[3] and sum(abs(a - b) for a, b in zip(p[:3], colour)) < 30:
                canvas.putpixel((x, y), (0, 0, 0, 0))
    if not build:
        return []
    tie = tuple(int(v * .55) for v in colour)
    for key, c in (("hair", colour), ("tie", tie)):
        x, y, w, h = SWATCH[key]
        for j in range(h):
            for i in range(w):
                canvas.putpixel((x + i, y + j), (*c, 255))
    length = 9.0 + rows                             # ponytails hang 17-21 px
    seg = [(length * .30, 1.0), (length * .30, 0.95), (length * .25, 0.8), (length * .15, 0.55)]

    def box(name, bone, y0, y1, w, d, zc, key, rot=(0, 0, 0), pivot=None):
        sw = SWATCH[key]
        return Cube(name, bone, (m(-w / 2), m(y0), m(zc - d / 2)), (m(w / 2), m(y1), m(zc + d / 2)),
                    uv={f: sw for f in "ENWSUD"}, rot=rot, pivot=(m(pivot[0]), m(pivot[1]), m(pivot[2])) if pivot else None)
    cubes = [box("pony-tie", "Pony-1", 29.8, 32.2, width * .75, 2.2, 5.0, "tie")]
    top = 30.8
    bones = ["Pony-1", "Pony-2", "Pony-3", "Pony-3"]
    zcs = [6.1, 6.7, 6.9, 6.9]
    for i, ((L, f), bone, zc) in enumerate(zip(seg, bones, zcs)):
        cubes.append(box(f"pony-{i + 1}", bone, top - L, top, width * f, 3.0 - i * .25, zc, "hair",
                         rot=(-10, 0, 0) if i == 0 else (0, 0, 0), pivot=(0, top, 4.8) if i == 0 else None))
        top -= L
    return cubes
