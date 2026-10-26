"""eirys: the supplied Minecraft (Alex) skin skins/eirys_source.png on rig-split cubes at vanilla scale,
plus 3D cat ears and a cat tail (see hunters/cat.py)."""
from bb_skin import U, vanilla_sk, eye_locators, source_hunter
from hunters import cat

NAME = "eirys"
HEIGHT = 1.78
DESIGN_TOP = 32 * U
SK = vanilla_sk()
EXTRAS = cat.EXTRAS
EYES = eye_locators()
MODEL_KW = {}


def _modify(canvas):
    base = canvas.getpixel((12, 3))[:3]
    return cat.modify(canvas, base, (232, 160, 170), (150, 205, 185), clear=[(32, 36, 8, 12)])


def build():
    return source_hunter(NAME, globals(), _modify)
