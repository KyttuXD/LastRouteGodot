"""loxelle: the supplied Minecraft (Alex) skin skins/loxelle_source.png on rig-split cubes at vanilla scale,
plus 3D gills and a fin tail (see hunters/fish.py); the gill marks painted on the skin are removed."""
from bb_skin import U, vanilla_sk, eye_locators, source_hunter
from hunters import fish

NAME = "loxelle"
HEIGHT = 1.78
DESIGN_TOP = 32 * U
SK = vanilla_sk()
EXTRAS = fish.EXTRAS
EYES = eye_locators()
MODEL_KW = {}
ACCENT = (114, 0, 0)


def _modify(canvas):
    base = canvas.getpixel((12, 3))[:3]            # head / hair colour
    return fish.modify(canvas, base, ACCENT)


def build():
    return source_hunter(NAME, globals(), _modify)
