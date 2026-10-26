"""aki: the supplied Minecraft (Alex) skin skins/aki_source.png on rig-split cubes at vanilla scale.
Only the expression cells are added to the texture; the skin itself is untouched."""
from bb_skin import U, vanilla_sk, eye_locators, source_hunter

NAME = "aki"
HEIGHT = 1.78
DESIGN_TOP = 32 * U
SK = vanilla_sk()
EXTRAS = []
EYES = eye_locators()
MODEL_KW = {}


def build():
    return source_hunter(NAME, globals())
