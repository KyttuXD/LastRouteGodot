import sys
import os as _os, sys as _sys
# The toolchain used to live in a scratch directory that was deleted.
# It lives here now; resolve siblings relative to this file, never a path.
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
_sys.path.insert(0, _os.path.join(_os.path.dirname(_os.path.abspath(__file__)), _os.pardir, "office"))
from mc_to_hytale import convert
from special_characters import add_gill_plates

def extra(data, im, packer):
    add_gill_plates(data, im, packer, gill_box_left=(0, 8, 2, 14), gill_box_right=(6, 8, 8, 14),
                     count_per_side=3, tex_name="Gills")

result = convert(
    _os.path.join(_os.environ.get("SKINS_DIR", "./skins"), "Lyttu.png"),
    _os.path.join(_os.environ.get("OUT_DIR", "./out"), "Loxelle.bbmodel"),
    extra_fn=extra,
)
print(result)
