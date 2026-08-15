import sys
import os as _os, sys as _sys
# The toolchain used to live in a scratch directory that was deleted.
# It lives here now; resolve siblings relative to this file, never a path.
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
_sys.path.insert(0, _os.path.join(_os.path.dirname(_os.path.abspath(__file__)), _os.pardir, "office"))
from mc_to_hytale import convert
from special_characters import add_ear_pair, add_lower_back_tail

def extra(data, im, packer):
    add_ear_pair(data, im, packer, (8, 0, 10, 4), (10, 0, 12, 4),
                 ear_size=(3.5, 6.5, 1.2), spread_x=6, forward_z=-9, tex_name="Ears")
    add_lower_back_tail(data, im, packer, region_box=(12, 0, 16, 4),
                         segments=5, base_y=48, curl=True, length=26, size=4, tex_name="Tail")

result = convert(
    "/home/kyttu/Documents/Skins Yttu/Hyttu.png",
    "/home/kyttu/Documents/blockbench test/conv_test/Haelith.bbmodel",
    extra_fn=extra,
)
print(result)
