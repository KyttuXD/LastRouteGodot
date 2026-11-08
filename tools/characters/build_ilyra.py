import sys
import os as _os, sys as _sys
# The toolchain used to live in a scratch directory that was deleted.
# It lives here now; resolve siblings relative to this file, never a path.
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
_sys.path.insert(0, _os.path.join(_os.path.dirname(_os.path.abspath(__file__)), _os.pardir, "office"))
from mc_to_hytale import convert
from special_characters import add_ear_pair, add_lower_back_tail

def extra(data, im, packer):
    # Cat ears: crop the small overlay-top accent pixels (violet w/ dark tips),
    # mirrored L/R from the same source patch since Minecraft art doesn't
    # separately author each ear -- position matches the design doc's "rise
    # through the hair" placement at the head's top-front.
    ear_box_l = (40, 5, 44, 8)  # left half of head_overlay top strip incl. accent dots
    ear_box_r = (44, 5, 48, 8)
    add_ear_pair(data, im, packer, ear_box_l, ear_box_r,
                 ear_size=(3.5, 6, 1.2), spread_x=6, forward_z=-9, tex_name="Ears")
    # Tail: curled S-shape from the lower back, violet to match hair.
    add_lower_back_tail(data, im, packer, region_box=(8, 0, 12, 4),
                         segments=5, base_y=48, curl=True, length=26, size=4.5, tex_name="Tail")

result = convert(
    _os.path.join(_os.environ.get("SKINS_DIR", "./skins"), "Iyttu.png"),
    _os.path.join(_os.environ.get("OUT_DIR", "./out"), "Ilyra.bbmodel"),
    extra_fn=extra,
)
print(result)
