"""nyxie: the supplied Minecraft (Alex) skin skins/nyxie_source.png on rig-split cubes at vanilla scale,
plus a 3D moon glyph with a few stars floating behind her head (hunters/glyph.py); the grey moon marks painted
on the sides of her head are removed."""
from bb_skin import U, vanilla_sk, eye_locators, source_hunter
from hunters import glyph

NAME = "nyxie"
HEIGHT = 1.78
DESIGN_TOP = 32 * U
SK = vanilla_sk()
EXTRAS = glyph.EXTRAS
EYES = eye_locators()
MODEL_KW = {}


def _modify(canvas):
    hair = canvas.getpixel((12, 3))[:3]
    return glyph.moon(canvas, (214, 214, 226), (255, 244, 191), [(128, 128, 128)], hair)


def build():
    return source_hunter(NAME, globals(), _modify)
