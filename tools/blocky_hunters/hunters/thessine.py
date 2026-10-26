"""thessine: the supplied Minecraft (Alex) skin skins/thessine_source.png on rig-split cubes at vanilla scale, with the
long hair strand down her back in 3D (hunters/pony.py) and the side braid over her left shoulder (hunters/chain.py)."""
from bb_skin import U, vanilla_sk, eye_locators, source_hunter
from hunters import chain, pony

NAME = "thessine"
HEIGHT = 1.78
DESIGN_TOP = 32 * U
SK = vanilla_sk()
_BRAID = chain.chain("L", "Braid", 3.4, -3.3, 28.5, [(21.0, 28.0, 2.6, 2.4), (16.8, 21.2, 2.4, 2.4), (13.0, 17.0, 2.0, 2.0)], zigzag=0.35, beads=True)
EXTRAS = pony.EXTRAS + _BRAID[0]
EYES = eye_locators()
MODEL_KW = {}


def _modify(canvas):
    cubes = pony.apply(canvas)
    chain.paint(canvas, canvas.getpixel((12, 3))[:3])
    return cubes + _BRAID[1]


def build():
    return source_hunter(NAME, globals(), _modify)
