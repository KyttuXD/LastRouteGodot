"""porcelle: the supplied Minecraft (Alex) skin skins/porcelle_source.png on rig-split cubes at vanilla scale,
plus small 3D horns (hunters/horn.py) and a floating halo (hunters/halo.py); the painted horn marks and the
halo ring are removed from the skin."""
from hunters import chain
from hunters import pony
from bb_skin import U, vanilla_sk, eye_locators, source_hunter
from hunters import halo, horn

NAME = "porcelle"
HEIGHT = 1.78
DESIGN_TOP = 32 * U
SK = vanilla_sk()
BASE = (3.1, 31.8, -3.0)
_BRAIDS = [chain.chain(side, "Pig", 6.2, 0.0, 28.0, [(21.0, 28.0, 2.8, 2.8), (15.5, 21.2, 2.6, 2.6), (10.5, 15.7, 2.6, 2.6), (5.5, 10.7, 2.4, 2.4), (2.5, 5.7, 2.0, 2.0)], beads=True)
           for side in ("L", "R")]
EXTRAS = horn.extras(BASE) + halo.EXTRAS + _BRAIDS[0][0] + _BRAIDS[1][0]
EYES = eye_locators()
MODEL_KW = {}


def _modify(canvas):
    cubes = horn.modify(canvas, (222, 104, 255), (170, 60, 210), BASE, [1.6, 1.4, 1.0], [1.6, 1.2, 0.9],
                        [1.6, 1.2, 0.9], 26, 14, 0, paint=[(222, 104, 255)])
    return cubes + halo.modify(canvas, (247, 223, 190))


def build():
    return source_hunter(NAME, globals(), _with_braids)


def _with_braids(canvas):
    pony.apply(canvas, build=False)               # her sheet has twin braided pigtails, not a centre ponytail
    chain.paint(canvas, canvas.getpixel((12, 3))[:3])
    return _modify(canvas) + _BRAIDS[0][1] + _BRAIDS[1][1]
