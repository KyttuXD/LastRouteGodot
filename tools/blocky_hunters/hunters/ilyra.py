"""ilyra: the supplied Minecraft (Alex) skin skins/ilyra_source.png on rig-split cubes at vanilla scale,
plus 3D cat ears and a cat tail (see hunters/cat.py)."""
from bb_skin import U, vanilla_sk, eye_locators, source_hunter
from hunters import cat

NAME = "ilyra"
HEIGHT = 1.78
DESIGN_TOP = 32 * U
SK = vanilla_sk()
EXTRAS = cat.EXTRAS
EYES = eye_locators()
MODEL_KW = {}


def _modify(canvas):
    # the cat ears that were painted on her forehead (rows 8-10 of the face) are geometry now
    base = canvas.getpixel((12, 3))[:3]
    for y in range(8, 11):
        for x in range(8, 16):
            p = canvas.getpixel((x, y))
            if p[3] and p[:3] != base:
                canvas.putpixel((x, y), (*base, 255))
    return cat.modify(canvas, base, (219, 146, 193), (190, 190, 205))


def build():
    return source_hunter(NAME, globals(), _modify)
