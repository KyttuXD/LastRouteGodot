import sys
import os as _os, sys as _sys
# The toolchain used to live in a scratch directory that was deleted.
# It lives here now; resolve siblings relative to this file, never a path.
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
_sys.path.insert(0, _os.path.join(_os.path.dirname(_os.path.abspath(__file__)), _os.pardir, "office"))
from mc_to_hytale import convert
from special_characters import add_side_disc_glyph

def extra(data, im, packer):
    # Sun glyph: physically attached to the RIGHT (east) side of the head per
    # the design doc ("source-right side-mounted"), never centered/floating.
    add_side_disc_glyph(data, im, packer, glyph_box=(32, 8, 40, 16), side="east",
                         tex_name="SunGlyph", size=8, offset_z=0)

result = convert(
    _os.path.join(_os.environ.get("SKINS_DIR", "./skins"), "Syttu.png"),
    _os.path.join(_os.environ.get("OUT_DIR", "./out"), "Solyth.bbmodel"),
    extra_fn=extra,
)
print(result)
