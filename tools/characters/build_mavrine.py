import sys
import os as _os, sys as _sys
# The toolchain used to live in a scratch directory that was deleted.
# It lives here now; resolve siblings relative to this file, never a path.
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
_sys.path.insert(0, _os.path.join(_os.path.dirname(_os.path.abspath(__file__)), _os.pardir, "office"))
from mc_to_hytale import convert
from special_characters import add_square_halo

def extra(data, im, packer):
    add_square_halo(data, im, packer, name="Halo", inner_gap=4)

result = convert(
    _os.path.join(_os.environ.get("SKINS_DIR", "./skins"), "Myttu.png"),
    _os.path.join(_os.environ.get("OUT_DIR", "./out"), "Mavrine.bbmodel"),
    extra_fn=extra,
)
print(result)
