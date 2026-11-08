import sys
import os as _os, sys as _sys
# The toolchain used to live in a scratch directory that was deleted.
# It lives here now; resolve siblings relative to this file, never a path.
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
_sys.path.insert(0, _os.path.join(_os.path.dirname(_os.path.abspath(__file__)), _os.pardir, "office"))
from mc_to_hytale import convert
from special_characters import add_back_wings

def extra(data, im, packer):
    # Wings mount from the BACK at shoulder-blade height, never from the
    # sides of the head -- explicit rejection criterion in the design doc.
    add_back_wings(data, im, packer, wing_box=(32, 36, 40, 48), tex_name="Wings", span=20, height=22)

result = convert(
    _os.path.join(_os.environ.get("SKINS_DIR", "./skins"), "Xyttu.png"),
    _os.path.join(_os.environ.get("OUT_DIR", "./out"), "Xivvy.bbmodel"),
    extra_fn=extra,
)
print(result)
