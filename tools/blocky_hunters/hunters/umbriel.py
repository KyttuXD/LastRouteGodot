"""umbriel: the supplied Minecraft (Alex) skin skins/umbriel_source.png on rig-split cubes at vanilla scale,
plus 3D curved horns (see hunters/horn.py)."""
from hunters import chain, pony
from bb_skin import U, vanilla_sk, eye_locators, source_hunter
from hunters import horn

NAME = "umbriel"
HEIGHT = 1.78
DESIGN_TOP = 32 * U
SK = vanilla_sk()
BASE = (3.0, 31.6, -3.0)
_BRAID = chain.chain("L", "Braid", 3.4, -3.3, 28.5, [(21.0, 28.0, 2.6, 2.4), (16.8, 21.2, 2.4, 2.4), (13.0, 17.0, 2.0, 2.0)], zigzag=0.35, beads=True)
EXTRAS = horn.extras(BASE) + pony.EXTRAS + _BRAID[0]
EYES = eye_locators()
MODEL_KW = {}


def _modify(canvas):
    hair = canvas.getpixel((12, 3))[:3]
    for y in range(8, 12):                          # the horns painted on her forehead are geometry now
        for x in range(8, 16):
            p = canvas.getpixel((x, y))
            if p[3] and p[:3] != hair:
                canvas.putpixel((x, y), (*hair, 255))
    return horn.modify(canvas, (28, 29, 31), (75, 75, 85), BASE, [2.4, 2.2, 2.0, 1.6],
                       [2.2, 1.8, 1.4, 1.0], [2.2, 1.8, 1.4, 1.0], 32, 14, 12, paint=[(28, 29, 31)])


def build():
    return source_hunter(NAME, globals(), _with_braid)


def _with_braid(canvas):
    cubes = _modify(canvas) + pony.apply(canvas)
    chain.paint(canvas, canvas.getpixel((12, 3))[:3])
    return cubes + _BRAID[1]
