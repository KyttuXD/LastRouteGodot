"""The SLIM (Alex, 3 px arms) variant of the player mannequin: identical rig, bones, pivots (sh_x 6.0, so its arm meshes swap in place
of the classic ones at runtime) and clips; only the arm cubes and sleeves are 3 px wide, per the Minecraft 64x64 slim UV layout.
Built by build.py as `player_mannequin_slim` (hunters/player_mannequin.py is the classic Steve body; player_clips.py has the clips)."""
from PIL import Image
from bb_skin import vanilla_cubes, vanilla_sk, eye_locators, SKINS

NAME = "player_mannequin_slim"
HEIGHT = 1.78
PLAYER = True
SK = vanilla_sk(sh_x=6.0)
EYES = eye_locators()
EXTRAS = []
MODEL_KW = {}


def build():
    skin = Image.open(SKINS / "player_mannequin_source.png").convert("RGBA")
    MODEL_KW.update(skin=skin)
    return vanilla_cubes(overlays=True, arm_w=3, face=False), (lambda k: None)


from bb_skin import U  # noqa: E402
DESIGN_TOP = 32 * U
