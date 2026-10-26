"""jyvra: the supplied Minecraft (Alex) skin skins/jyvra_source.png on rig-split cubes at vanilla scale,
plus 3D curved horns (see hunters/horn.py)."""
from bb_skin import U, vanilla_sk, eye_locators, source_hunter
from hunters import horn

NAME = "jyvra"
HEIGHT = 1.78
DESIGN_TOP = 32 * U
SK = vanilla_sk()
BASE = (3.0, 32.0, -1.0)
EXTRAS = horn.extras(BASE)
EYES = eye_locators()
MODEL_KW = {}


def _modify(canvas):
    return horn.modify(canvas, (247, 98, 118), (200, 60, 85), BASE, [1.4, 1.2],
                       [1.5, 1.0], [1.5, 1.0], 24, 16, 0, paint=[(247, 98, 118)])


def build():
    return source_hunter(NAME, globals(), _modify)
