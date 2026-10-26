"""kathy: the supplied Minecraft (Alex) skin skins/kathy_source.png on rig-split cubes at vanilla scale,
plus a 3D ponytail (tie + four tapering segments on Pony-1..3 bones that swing in every clip).
The ponytail is painted with the skin's own hair colour (flat, exactly as her head hair is), so it
matches the hair on the skin; the tie uses the red of her bow."""
from bb_core import Cube
from bb_skin import U, m, vanilla_sk, eye_locators, source_hunter

NAME = "kathy"
HEIGHT = 1.78
DESIGN_TOP = 32 * U
SK = vanilla_sk()
EYES = eye_locators()
MODEL_KW = {}

# bone, parent, pivot (skin px), sway (fore-aft deg, side deg, cycle multiplier, phase)
_PONY = [("Pony-1", "Head", (0.0, 31.0, 4.6), (7, 3, 1, 0.0)),
         ("Pony-2", "Pony-1", (0.0, 27.0, 6.3), (9, 4, 1, 0.7)),
         ("Pony-3", "Pony-2", (0.0, 22.5, 6.6), (12, 5, 1, 1.4))]
EXTRAS = [(n, par, (m(x), m(y), m(z)), sw) for n, par, (x, y, z), sw in _PONY]
HAIR_SWATCH, TIE_SWATCH = (46, 66, 2, 2), (48, 66, 2, 2)     # free atlas texels, solid colours


def _modify(canvas):
    hair = canvas.getpixel((12, 3))[:3]            # the flat hair colour of her head (top of the head box)
    tie = canvas.getpixel((24, 18))[:3] if False else (220, 90, 95)   # the red of the bow on her skin
    # the hair that was painted down her back (body back + jacket back) is geometry now: shirt red / transparent
    shirt = canvas.getpixel((32, 20))[:3]
    for y0, clear in ((20, False), (36, True)):
        for y in range(y0, y0 + 12):
            for x in range(32, 40):
                p = canvas.getpixel((x, y))
                if p[3] and sum(abs(a - b) for a, b in zip(p[:3], hair)) < 25:
                    canvas.putpixel((x, y), (0, 0, 0, 0) if clear else (*shirt, 255))
    for (x, y, w, h), c in ((HAIR_SWATCH, hair), (TIE_SWATCH, tie)):
        for j in range(h):
            for i in range(w):
                canvas.putpixel((x + i, y + j), (*c, 255))

    def box(name, bone, y0, y1, w, d, zc, swatch, rot=(0, 0, 0), pivot=None, x=0.0):
        return Cube(name, bone, (m(x - w / 2), m(y0), m(zc - d / 2)), (m(x + w / 2), m(y1), m(zc + d / 2)),
                    uv={f: swatch for f in "ENWSUD"}, rot=rot,
                    pivot=(m(pivot[0]), m(pivot[1]), m(pivot[2])) if pivot else None)
    return [
        box("pony-tie", "Pony-1", 29.8, 32.2, 3.2, 2.2, 5.0, TIE_SWATCH),
        box("pony-1", "Pony-1", 26.8, 30.6, 4.2, 3.2, 6.1, HAIR_SWATCH, rot=(-10, 0, 0), pivot=(0, 30.6, 4.8)),
        box("pony-2", "Pony-2", 22.4, 27.0, 4.4, 3.2, 6.7, HAIR_SWATCH),
        box("pony-3", "Pony-3", 18.0, 22.6, 3.8, 3.0, 6.9, HAIR_SWATCH, x=-0.1),
        box("pony-tip", "Pony-3", 14.6, 18.0, 2.4, 2.4, 6.9, HAIR_SWATCH, x=-0.2),
    ]


def build():
    return source_hunter(NAME, globals(), _modify)
