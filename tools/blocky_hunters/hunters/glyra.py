"""glyra: the supplied Minecraft (Alex) skin skins/glyra_source.png on rig-split cubes at vanilla scale,
plus 3D curved horns (see hunters/horn.py)."""
from bb_skin import U, vanilla_sk, eye_locators, source_hunter
from hunters import horn

NAME = "glyra"
HEIGHT = 1.78
DESIGN_TOP = 32 * U
SK = vanilla_sk()
BASE = (2.6, 32.0, -0.4)
EXTRAS = horn.extras(BASE)
EYES = eye_locators()
MODEL_KW = {}


def _modify(canvas):
    return horn.modify(canvas, (112, 239, 203), (87, 180, 163), BASE, [1.6, 1.4, 1.0],
                       [1.8, 1.4, 1.0], [1.8, 1.4, 1.0], 18, 12, 0, paint=[(87, 180, 163)])


def build():
    return source_hunter(NAME, globals(), _modify)
