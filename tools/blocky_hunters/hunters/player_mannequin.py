"""The PLAYER body on the hunters' rig: the wooden mannequin skin (skins/player_mannequin_source.png, a standard 64x64
Minecraft skin, copy of LastRoute-3D-refs/mannequin-skin-player.png) on classic (Steve) proportions: head 8^3,
body 8x12x4, 4 px arms, 4 px legs, both skin layers (the second layer is empty in this skin but is honoured when it is not).
Same bone names, hierarchy and rest pose as every hunter; no expression cells, no hunter extras, so the atlas stays 64x64
and the .glb tiny. Not a hunter: built by build.py as `player_mannequin` (see player_clips.py for its clip set)."""
from PIL import Image
from bb_skin import vanilla_cubes, vanilla_sk, eye_locators, SKINS

NAME = "player_mannequin"
HEIGHT = 1.78
PLAYER = True
SK = vanilla_sk(sh_x=6.0)
EYES = eye_locators()
EXTRAS = []
MODEL_KW = {}


def build():
    skin = Image.open(SKINS / "player_mannequin_source.png").convert("RGBA")
    MODEL_KW.update(skin=skin)
    return vanilla_cubes(overlays=True, arm_w=4, face=False), (lambda k: None)


from bb_skin import U  # noqa: E402
DESIGN_TOP = 32 * U
