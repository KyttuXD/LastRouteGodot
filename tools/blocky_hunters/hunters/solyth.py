"""solyth: the supplied Minecraft (Alex) skin skins/solyth_source.png on rig-split cubes at vanilla scale,
plus a 3D sun glyph (her sun-disc: a glowing disc with eight rays) floating upright behind her head
(hunters/glyph.py). The ring and ray pieces painted on the skin are removed. Her square halo is replaced by it."""
from bb_skin import U, vanilla_sk, eye_locators, source_hunter
from hunters import chain, glyph

NAME = "solyth"
HEIGHT = 1.78
DESIGN_TOP = 32 * U
SK = vanilla_sk()
_LOCK = chain.chain("L", "Lock", 3.6, -3.3, 28.5, [(21.0, 28.5, 3.2, 2.4), (14.5, 21.2, 3.2, 2.4), (9.0, 14.7, 2.8, 2.2), (5.5, 9.2, 1.8, 2.0)], drift=0.1, tie=False)
EXTRAS = glyph.EXTRAS + _LOCK[0]
EYES = eye_locators()
MODEL_KW = {}


def _modify(canvas):
    # rays orange, disc yellow, bright core pale yellow
    return glyph.sun(canvas, (235, 236, 162), (237, 160, 30), (250, 205, 40), None,
                     [(235, 236, 162), (197, 130, 19), (166, 104, 41)])


def build():
    return source_hunter(NAME, globals(), _with_lock)


def _with_lock(canvas):
    cubes = _modify(canvas)
    chain.paint(canvas, canvas.getpixel((12, 3))[:3])
    return cubes + _LOCK[1]
