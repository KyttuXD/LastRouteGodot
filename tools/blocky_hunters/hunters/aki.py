"""aki: the supplied Minecraft (Alex) skin skins/aki_source.png on rig-split cubes at vanilla scale, plus a
3D ponytail (hunters/pony.py) replacing the hair strand painted down her back."""
from bb_skin import U, vanilla_sk, eye_locators, source_hunter
from hunters import pony

NAME = "aki"
HEIGHT = 1.78
DESIGN_TOP = 32 * U
SK = vanilla_sk()
EXTRAS = pony.EXTRAS
EYES = eye_locators()
MODEL_KW = {}


def build():
    return source_hunter(NAME, globals(), pony.apply)
