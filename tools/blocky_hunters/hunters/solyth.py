"""solyth: the supplied Minecraft (Alex) skin skins/solyth_source.png on rig-split cubes at vanilla scale,
plus a 3D floating halo (see hunters/halo.py); the halo ring painted on the skin is removed."""
from bb_skin import U, vanilla_sk, eye_locators, source_hunter
from hunters import halo

NAME = "solyth"
HEIGHT = 1.78
DESIGN_TOP = 32 * U
SK = vanilla_sk()
EXTRAS = halo.EXTRAS
EYES = eye_locators()
MODEL_KW = {}


def _modify(canvas):
    return halo.modify(canvas, (235, 236, 162))


def build():
    return source_hunter(NAME, globals(), _modify)
