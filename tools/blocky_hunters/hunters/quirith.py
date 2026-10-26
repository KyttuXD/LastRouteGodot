"""quirith: the supplied Minecraft (Alex) skin skins/quirith_source.png on rig-split cubes at vanilla scale,
plus 3D wolf ears and a bushy wolf tail (see hunters/wolf.py); the ear and tail art painted on the skin is removed."""
from bb_skin import U, vanilla_sk, eye_locators, source_hunter
from hunters import chain, wolf

NAME = "quirith"
HEIGHT = 1.78
DESIGN_TOP = 32 * U
SK = vanilla_sk()
_BRAID = chain.chain("L", "Braid", 3.4, -3.3, 28.5, [(21.0, 28.0, 2.6, 2.4), (16.8, 21.2, 2.4, 2.4), (13.0, 17.0, 2.0, 2.0)], zigzag=0.35, beads=True)
EXTRAS = wolf.EXTRAS + _BRAID[0]
EYES = eye_locators()
MODEL_KW = {}


def _modify(canvas):
    return wolf.modify(canvas, canvas.getpixel((12, 3))[:3])


def build():
    return source_hunter(NAME, globals(), _with_braid)


def _with_braid(canvas):
    cubes = _modify(canvas)
    chain.paint(canvas, canvas.getpixel((12, 3))[:3])   # after wolf.modify: the swatches live in separate texels
    return cubes + _BRAID[1]
