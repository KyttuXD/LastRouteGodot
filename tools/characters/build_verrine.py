import sys
import os as _os, sys as _sys
# The toolchain used to live in a scratch directory that was deleted.
# It lives here now; resolve siblings relative to this file, never a path.
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
_sys.path.insert(0, _os.path.join(_os.path.dirname(_os.path.abspath(__file__)), _os.pardir, "office"))
from mc_to_hytale import convert
from special_characters import add_asymmetric_ear_pair, add_lower_back_tail

def extra(data, im, packer):
    # Asymmetric canine ears: left taller/upright, right shorter/folded --
    # per design doc, never symmetric, never mirrored between profiles.
    add_asymmetric_ear_pair(
        data, im, packer,
        l_box=(8, 0, 10, 4), r_box=(10, 0, 12, 4),
        l_size=(3.5, 8), r_size=(3.5, 5),
        l_pos=(-5.25, 120, -9.25), r_pos=(5.25, 120, -8),
    )
    add_lower_back_tail(data, im, packer, region_box=(12, 0, 16, 4),
                         segments=5, base_y=48, curl=True, length=30, size=6, tex_name="Tail")

result = convert(
    _os.path.join(_os.environ.get("SKINS_DIR", "./skins"), "Vyttu.png"),
    _os.path.join(_os.environ.get("OUT_DIR", "./out"), "Verrine.bbmodel"),
    extra_fn=extra,
)
print(result)
