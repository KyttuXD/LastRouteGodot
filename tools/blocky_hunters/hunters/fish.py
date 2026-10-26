"""Gills and a fin tail for the fish-folk hunters (Loxelle, Opalie).

Gills: three thin slats on each side of the head, on L-Gill/R-Gill bones that flutter.
Tail: three tapering segments hanging off the lower back (Tail-1..3) ending in a fan fin (Tail-Fin), all
swaying in every clip. Colours come from the skin: the head/hair colour for the body of the tail, and the
accent colour of the gill marks that were painted on the skin's second layer (those marks are cleared
from the hat layer, because they are geometry now)."""
from PIL import Image
from bb_core import Cube
from bb_skin import m

SWATCH = {"base": (46, 66, 2, 2), "accent": (48, 66, 2, 2), "light": (50, 66, 2, 2)}
FIN_AT, FIN_SIZE = (24, 64), (11, 8)

# bone, parent, pivot (skin px), sway (fore-aft deg, side deg, cycle multiplier, phase)
_B = [("L-Gill", "Head", (-4.4, 26.6, 0.0), (0, 9, 2, 0.0)),
      ("R-Gill", "Head", (4.4, 26.6, 0.0), (0, -9, 2, 0.5)),
      ("Tail-1", "Pelvis", (0.0, 12.6, 2.3), (7, 3, 1, 0.0)),
      ("Tail-2", "Tail-1", (0.0, 9.0, 3.6), (10, 4, 1, 0.6)),
      ("Tail-3", "Tail-2", (0.0, 5.8, 4.7), (13, 5, 1, 1.2)),
      ("Tail-Fin", "Tail-3", (0.0, 3.8, 5.3), (16, 8, 1, 1.8))]
EXTRAS = [(n, par, (m(x), m(y), m(z)), sw) for n, par, (x, y, z), sw in _B]


def _fin_image(base, accent, light):
    w, h = FIN_SIZE
    im = Image.new("RGBA", FIN_SIZE, (0, 0, 0, 0))
    for j in range(h):                      # fan hanging from the top centre: rays of accent, scalloped rim
        for i in range(w):
            dx, dy = (i + .5 - w / 2) / (w / 2), (j + .5) / h
            if dy < .12 or abs(dx) > .35 + dy * .75:
                continue
            if dy + .25 * abs(dx) > 1.0:
                continue
            if (i + (j // 3)) % 3 == 0 and dy > .25:
                c = accent
            elif dy > .8 or abs(dx) > .35 + dy * .75 - .2:
                c = light
            else:
                c = base
            im.putpixel((i, j), (*c, 255))
    return im


def modify(canvas, base, accent):
    """Edit the skin (clear the painted gill marks, add swatches + the fin) and return the extra cubes."""
    light = tuple(min(255, int(v * .6 + 255 * .4)) for v in base)
    for y in range(0, 16):                  # painted gill marks live on the hat layer: now geometry
        for x in range(32, 64):
            p = canvas.getpixel((x, y))
            if p[3] and p[:3] == accent:
                canvas.putpixel((x, y), (0, 0, 0, 0))
    for y in range(0, 16):                  # ... and on the head box itself: back to plain hair colour
        for x in range(0, 32):
            p = canvas.getpixel((x, y))
            if p[3] and p[:3] == accent:
                canvas.putpixel((x, y), (*base, 255))
    for key, c in (("base", base), ("accent", accent), ("light", light)):
        x, y, w, h = SWATCH[key]
        for j in range(h):
            for i in range(w):
                canvas.putpixel((x + i, y + j), (*c, 255))
    canvas.paste(_fin_image(base, accent, light), FIN_AT)

    def box(name, bone, y0, y1, w, d, zc, key, x=0.0, rot=(0, 0, 0), pivot=None):
        sw = SWATCH[key]
        return Cube(name, bone, (m(x - w / 2), m(y0), m(zc - d / 2)), (m(x + w / 2), m(y1), m(zc + d / 2)),
                    uv={f: sw for f in "ENWSUD"}, rot=rot,
                    pivot=(m(pivot[0]), m(pivot[1]), m(pivot[2])) if pivot else None)
    cubes = []
    for side, s in (("L", -1), ("R", 1)):   # gills: three slats flaring out of each side of the head
        for k, (y, key) in enumerate(((25.3, "accent"), (26.6, "base"), (27.9, "accent"))):
            cubes.append(box(f"{side}-gill-{k}", f"{side}-Gill", y, y + .7, 2.4, 2.8, 0.0, key,
                             x=s * 5.5, rot=(0, 0, -s * 14), pivot=(s * 4.4, y, 0)))
    cubes += [
        box("tail-1", "Tail-1", 9.0, 12.8, 3.6, 2.6, 3.7, "base", rot=(-14, 0, 0), pivot=(0, 12.6, 2.3)),
        box("tail-2", "Tail-2", 5.8, 9.2, 3.0, 2.2, 4.8, "base"),
        box("tail-3", "Tail-3", 3.6, 6.0, 2.2, 1.8, 5.6, "accent"),
    ]
    fin = (FIN_AT[0], FIN_AT[1], *FIN_SIZE)
    fw, fh = 8.0, 6.0                              # fan card size in skin px (the 11x8 texel art is stretched a bit)
    for tag, yaw in (("a", 0), ("b", 90)):         # two crossed cards so the fan reads from every side
        cubes.append(Cube(f"tail-fin-{tag}", "Tail-Fin", (m(-fw / 2), m(0.4), m(5.3 - .05)),
                          (m(fw / 2), m(0.4 + fh), m(5.3 + .05)), faces="NS", uv={"N": fin, "S": fin},
                          rot=(0, yaw, 0), pivot=(0, m(3.8), m(5.3))))
    return cubes
