"""porcelle: the supplied Minecraft (Alex) skin skins/porcelle_source.png on rig-split cubes at vanilla scale,
plus small 3D horns (hunters/horn.py) and a floating halo (hunters/halo.py); the painted horn marks and the
halo ring are removed from the skin."""
from hunters import pony
from bb_skin import U, vanilla_sk, eye_locators, source_hunter
from hunters import halo, horn

NAME = "porcelle"
HEIGHT = 1.78
DESIGN_TOP = 32 * U
SK = vanilla_sk()
BASE = (3.1, 31.8, -3.0)
EXTRAS = horn.extras(BASE) + halo.EXTRAS + pony.EXTRAS
EYES = eye_locators()
MODEL_KW = {}


def _modify(canvas):
    cubes = horn.modify(canvas, (222, 104, 255), (170, 60, 210), BASE, [1.6, 1.4, 1.0], [1.6, 1.2, 0.9],
                        [1.6, 1.2, 0.9], 26, 14, 0, paint=[(222, 104, 255)])
    return cubes + halo.modify(canvas, (247, 223, 190))


def build():
    return source_hunter(NAME, globals(), lambda canvas: _modify(canvas) + pony.apply(canvas))
