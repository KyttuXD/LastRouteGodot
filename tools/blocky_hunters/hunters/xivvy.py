"""xivvy: the supplied Minecraft (Alex) skin skins/xivvy_source.png on rig-split cubes at vanilla scale,
plus butterfly wings. The wing art that was painted on the back of the skin (the dark butterfly on the
body back and on the jacket back) is removed from the texture, because the wings are real geometry now:
four thin double-sided cards (forewing + hindwing per side) on L-Wing/R-Wing bones that flap in every clip."""
from PIL import Image
from bb_core import Cube
from bb_paint import Palette
from bb_skin import U, m, vanilla_sk, eye_locators, source_hunter

NAME = "xivvy"
HEIGHT = 1.78
DESIGN_TOP = 32 * U
SK = vanilla_sk()
EYES = eye_locators()
MODEL_KW = {}

# bone, parent, pivot (x, y, z in skin px -> metres), sway (flap deg about Y, 0, cycles multiplier, phase)
_WP = [("L-Wing", "Chest", (-1.5, 24.0, 2.4), (16, 0, 1, 0.0)),
       ("R-Wing", "Chest", (1.5, 24.0, 2.4), (-16, 0, 1, 0.0)),
       ("L-HindWing", "L-Wing", (-1.5, 17.0, 2.5), (9, 0, 1, 0.8)),
       ("R-HindWing", "R-Wing", (1.5, 17.0, 2.5), (-9, 0, 1, 0.8))]
EXTRAS = [(n, par, (m(x), m(y), m(z)), sw) for n, par, (x, y, z), sw in _WP]

WING_AT = {"up_L": (24, 64), "up_R": (36, 64), "lo_L": (24, 79), "lo_R": (34, 79)}
UP, LO = (12, 14), (9, 9)


def _wing_image(size, upper, mirror, pal):
    """Pixel-art butterfly panel; a = 0 at the spine .. 1 at the tip, b = 0 top .. 1 bottom."""
    wing, edge, light = pal["wing"], pal["edge"], pal["light"]
    w, h = size
    im = Image.new("RGBA", size, (0, 0, 0, 0))
    for j in range(h):
        for i in range(w):
            a = (i + .5) / w
            a = 1 - a if mirror else a      # N-face u runs toward -X: the R wing is the mirrored one
            b = (j + .5) / h
            if upper:
                d = (((a - .52) / .52) ** 2 + ((b - .52) / .5) ** 2) ** .5
                if a < .12 or (a < .35 and b > .8):
                    continue
            else:
                d = (((a - .46) / .5) ** 2 + ((b - .42) / .46) ** 2) ** .5
                if a < .1 or (b > .78 and not (.3 < a < .52)):   # hindwing tail
                    continue
            if d > 1.0:
                continue
            if d > .78:
                c = edge
            elif (i * 3 + j * 2) % 7 == 0 and d < .7:
                c = light                    # veins
            else:
                c = wing if (i + j) % 2 == 0 or d < .45 else light    # dithered translucency
            im.putpixel((i, j), (*c, 255))
    return im


def _modify(canvas):
    pal = Palette(NAME)
    purple = canvas.getpixel((18, 24))[:3]
    # 1) take the painted butterfly off the skin: body back (32,20,8,11) -> torso colour,
    #    jacket back (32,36,8,11) -> transparent. The bottom belt row (y=31) stays.
    for y in range(20, 31):
        for x in range(32, 40):
            canvas.putpixel((x, y), (*purple, 255))
    for y in range(36, 47):
        for x in range(32, 40):
            canvas.putpixel((x, y), (0, 0, 0, 0))
    # 2) paint the wing panels into free atlas space
    colours = {"wing": pal.snap((180, 147, 210)), "light": pal.snap((205, 184, 232)), "edge": pal.snap((112, 79, 128))}
    for key, (x, y) in WING_AT.items():
        canvas.paste(_wing_image(UP if key.startswith("up") else LO, key.startswith("up"), key.endswith("R"), colours), (x, y))
    # 3) the cards: thin, double-sided, yawed back into a V, hinged at the spine
    cubes = []
    for side, s, yaw in (("L", -1, 24), ("R", 1, -24)):
        for tag, up, (x0, x1), (y0, y1), z, bone, pv in (
                ("fore", True, (1.5, 12.5), (17.0, 31.0), 2.45, f"{side}-Wing", (s * 1.5, 24.0, 2.4)),
                ("hind", False, (1.5, 10.5), (9.5, 18.5), 2.75, f"{side}-HindWing", (s * 1.5, 17.0, 2.5))):
            xs = sorted((s * x0, s * x1))
            rect = (*WING_AT[("up_" if up else "lo_") + side], *(UP if up else LO))
            cubes.append(Cube(f"{side}-{tag}wing", bone, (m(xs[0]), m(y0), m(z - .05)), (m(xs[1]), m(y1), m(z + .05)),
                              faces="NS", uv={"N": rect, "S": rect}, rot=(0, yaw, 0), pivot=(m(s * 1.5), m(pv[1]), m(2.4))))
    return cubes


def build():
    return source_hunter(NAME, globals(), _modify)
