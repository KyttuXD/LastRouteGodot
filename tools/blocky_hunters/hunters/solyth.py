"""solyth: the supplied Minecraft (Alex) skin skins/solyth_source.png on rig-split cubes at vanilla scale,
plus a 3D sun glyph (her sun-disc: a glowing disc with eight rays) floating upright beside her head
(hunters/glyph.py), and her square halo (hunters/halo.py) above it. The ring and ray pieces painted on the skin are removed. """
from bb_skin import U, vanilla_sk, eye_locators, source_hunter
from hunters import glyph, halo

NAME = "solyth"
HEIGHT = 1.78
DESIGN_TOP = 32 * U
SK = vanilla_sk()
EXTRAS = glyph.EXTRAS + halo.EXTRAS
EYES = eye_locators()
MODEL_KW = {}


def _modify(canvas):
    # rays orange, disc yellow, bright core pale yellow
    cubes = glyph.sun(canvas, (235, 236, 162), (237, 160, 30), (250, 205, 40), None,
                      [(235, 236, 162), (197, 130, 19), (166, 104, 41)])
    return cubes + halo.modify(canvas, (235, 236, 162))


def build():
    return source_hunter(NAME, globals(), _modify)
