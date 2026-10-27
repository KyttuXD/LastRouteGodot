"""javelle: the supplied Minecraft (Alex) skin skins/javelle_source.png on rig-split cubes at vanilla scale,
plus 3D curved horns (see hunters/horn.py)."""
from hunters import chain, pony
from bb_skin import U, vanilla_sk, eye_locators, source_hunter
from hunters import horn

NAME = "javelle"
HEIGHT = 1.78
DESIGN_TOP = 32 * U
SK = vanilla_sk()
BASE = (3.0, 32.0, -1.0)
_TAILS = [chain.chain(side, "Pig", 5.2, 2.6, 30.6, [(22.0, 30.6, 3.4, 3.0), (14.6, 22.2, 3.6, 3.0), (8.0, 14.8, 3.2, 2.8), (3.5, 8.2, 2.2, 2.4)])
          for side in ("L", "R")]
EXTRAS = horn.extras(BASE) + _TAILS[0][0] + _TAILS[1][0]
EYES = eye_locators()
MODEL_KW = {}


def _modify(canvas):
    return horn.modify(canvas, (247, 98, 118), (200, 60, 85), BASE, [1.4, 1.2],
                       [1.5, 1.0], [1.5, 1.0], 24, 16, 0, paint=[(247, 98, 118)])


def build():
    return source_hunter(NAME, globals(), _with_tails)


def _with_tails(canvas):
    pony.apply(canvas, build=False)               # her sheet has twin tails, not a centre ponytail
    chain.paint(canvas, canvas.getpixel((12, 3))[:3])
    return _modify(canvas) + _TAILS[0][1] + _TAILS[1][1]
