"""haelith: the supplied Minecraft (Alex) skin skins/haelith_source.png on rig-split cubes at vanilla scale,
plus 3D wolf ears and a bushy wolf tail (see hunters/wolf.py); the ear and tail art painted on the skin is removed."""
from hunters import pony
from bb_skin import U, vanilla_sk, eye_locators, source_hunter
from hunters import wolf

NAME = "haelith"
HEIGHT = 1.78
DESIGN_TOP = 32 * U
SK = vanilla_sk()
EXTRAS = wolf.EXTRAS + pony.EXTRAS
EYES = eye_locators()
MODEL_KW = {}


def _modify(canvas):
    return wolf.modify(canvas, canvas.getpixel((12, 3))[:3])


def build():
    return source_hunter(NAME, globals(), lambda canvas: _modify(canvas) + pony.apply(canvas))
