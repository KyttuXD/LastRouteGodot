"""Axolotl-style gills and a wide paddle tail for the fish-folk hunters (Loxelle, Opalie).

Gills: three feathery fronds fanned out sideways from each side of the head (thin cards in the vertical plane,
fanned up / level / down), on L-Gill/R-Gill bones that flutter.
Tail: three flat, widening segments running straight back from the lower back (Tail-1..3) ending in a wide flat
paddle fin (Tail-Fin) with a light centre stripe; the chain wags side to side (yaw) in every clip.
Colours come from the skin: the head/hair colour for the body of the tail and fronds, and the accent colour of
the gill marks that were painted on the skin (cleared from the head, because they are geometry now)."""
from PIL import Image
from bb_core import Cube
from bb_skin import m

SWATCH = {"base": (46, 66, 2, 2), "accent": (48, 66, 2, 2), "light": (50, 66, 2, 2)}
GILL_AT = {"L": (24, 64), "R": (36, 64)}
GILL_SIZE = (10, 5)
PADDLE_AT, PADDLE_SIZE = (24, 70), (22, 13)

# bone, parent, pivot (skin px), sway (fore-aft deg, side deg, cycle multiplier, phase, yaw deg)
_B = [("L-Gill", "Head", (-4.4, 27.4, 0.0), (0, 9, 2, 0.0)),
      ("R-Gill", "Head", (4.4, 27.4, 0.0), (0, -9, 2, 0.5)),
      ("Tail-1", "Pelvis", (0.0, 11.2, 2.3), (3, 0, 1, 0.0, 8)),
      ("Tail-2", "Tail-1", (0.0, 10.8, 4.6), (3, 0, 1, 0.6, 12)),
      ("Tail-3", "Tail-2", (0.0, 10.4, 7.0), (4, 0, 1, 1.2, 15)),
      ("Tail-Fin", "Tail-3", (0.0, 10.0, 9.4), (4, 0, 1, 1.8, 18))]
EXTRAS = [(n, par, (m(x), m(y), m(z)), sw) for n, par, (x, y, z), sw in _B]


def _frond(base, accent, light, outward_right):
    """Pinnate feather, 10x5 texels: stem along the middle row, leaflets tapering toward the tip."""
    w, h = GILL_SIZE
    im = Image.new("RGBA", GILL_SIZE, (0, 0, 0, 0))
    for i in range(w):
        t = i if outward_right else w - 1 - i           # 0 at the head, w-1 at the tip
        reach = 2 - (1 if t > 6 else 0) - (1 if t > 8 else 0)
        for j in range(h):
            dj = abs(j - h // 2)
            if dj == 0:
                c = accent
            elif dj <= reach and (t + dj) % 2 == 0:
                c = light if dj == reach else base
            elif dj == 1 and t < 9:
                c = base
            else:
                continue
            im.putpixel((i, j), (*c, 255))
    return im


def _paddle(base, accent, light):
    """Wide rounded paddle, 22x13 texels. Image top = the back tip, bottom = where it joins the tail."""
    w, h = PADDLE_SIZE
    im = Image.new("RGBA", PADDLE_SIZE, (0, 0, 0, 0))
    for j in range(h):
        v = 1 - (j + .5) / h                              # 0 at the joint .. 1 at the tip
        half = (0.34 + 0.66 * min(1.0, v * 2.2)) if v < .62 else (1.0 - ((v - .62) / .38) ** 2) ** .5
        for i in range(w):
            u = abs((i + .5) - w / 2) / (w / 2)
            if u > half:
                continue
            if u > half - .16:
                c = accent                                # outline
            elif u < .12:
                c = light                                 # centre stripe
            elif (i + j) % 4 == 0:
                c = accent if u > .5 else light           # rays
            else:
                c = base
            im.putpixel((i, j), (*c, 255))
    return im


def modify(canvas, base, accent):
    """Edit the skin (clear the painted gill marks, add swatches + gill/paddle art) and return the extra cubes."""
    light = tuple(min(255, int(v * .6 + 255 * .4)) for v in base)
    for region, repl in (((32, 64), None), ((0, 32), base)):     # hat layer: transparent; head box: hair colour
        for y in range(0, 16):
            for x in range(*region):
                p = canvas.getpixel((x, y))
                if p[3] and p[:3] == accent:
                    canvas.putpixel((x, y), (0, 0, 0, 0) if repl is None else (*repl, 255))
    for key, c in (("base", base), ("accent", accent), ("light", light)):
        x, y, w, h = SWATCH[key]
        for j in range(h):
            for i in range(w):
                canvas.putpixel((x + i, y + j), (*c, 255))
    canvas.paste(_frond(base, accent, light, False), GILL_AT["L"])     # L side: outward = +u on the N face
    canvas.paste(_frond(base, accent, light, True), GILL_AT["R"])
    canvas.paste(_paddle(base, accent, light), PADDLE_AT)

    def box(name, bone, y0, y1, w, z0, z1, key):
        sw = SWATCH[key]
        return Cube(name, bone, (m(-w / 2), m(y0), m(z0)), (m(w / 2), m(y1), m(z1)), uv={f: sw for f in "ENWSUD"})
    cubes = []
    for side, s in (("L", -1), ("R", 1)):                 # gills: three fronds fanned up / level / down
        rect = (*GILL_AT[side], *GILL_SIZE)
        for k, (ang, dz) in enumerate(((30, -0.5), (0, 0.0), (-30, 0.5))):
            x0, x1 = sorted((s * 4.3, s * 9.6))
            cubes.append(Cube(f"{side}-gill-{k}", f"{side}-Gill", (m(x0), m(27.4 - 1.4), m(dz - .05)),
                              (m(x1), m(27.4 + 1.4), m(dz + .05)), faces="NS", uv={"N": rect, "S": rect},
                              rot=(0, 0, s * ang), pivot=(m(s * 4.4), m(27.4), m(dz))))
    cubes += [
        box("tail-1", "Tail-1", 10.2, 12.2, 3.6, 2.2, 4.6, "base"),
        box("tail-2", "Tail-2", 9.9, 11.7, 4.6, 4.6, 7.0, "base"),
        box("tail-3", "Tail-3", 9.6, 11.2, 5.6, 7.0, 9.4, "accent"),
    ]
    pw, pd = PADDLE_SIZE[0] / 2, PADDLE_SIZE[1] / 2        # texels are half a skin px: 11 x 6.5 px
    rect = (*PADDLE_AT, *PADDLE_SIZE)
    cubes.append(Cube("tail-paddle", "Tail-Fin", (m(-pw / 2), m(9.75), m(9.4)), (m(pw / 2), m(9.95), m(9.4 + pd)),
                      faces="UD", uv={"U": rect, "D": rect}, rot=(30, 0, 0), pivot=(0, m(10.0), m(9.4))))   # droops
    return cubes
