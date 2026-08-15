import sys
import os as _os, sys as _sys
# The toolchain used to live in a scratch directory that was deleted.
# It lives here now; resolve siblings relative to this file, never a path.
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
_sys.path.insert(0, _os.path.join(_os.path.dirname(_os.path.abspath(__file__)), _os.pardir, "office"))
from mc_to_hytale import convert, color_dist
from special_characters import add_side_disc_glyph, add_orbiting_stars

STAR_COLOR = (255, 244, 191)   # pale gold star pixels
PLATE_COLOR = (128, 128, 128)  # charcoal temple plate

def find_pixels(im, box, target, tol=24):
    """1x1 boxes for every pixel in `box` matching `target` -- used to erase
    scattered art (stars) that became standalone objects."""
    x0, y0, x1, y1 = box
    out = []
    for y in range(y0, y1):
        for x in range(x0, x1):
            p = im.getpixel((x, y))
            if p[3] > 10 and color_dist(p[:3], target) <= tol:
                out.append((x, y, x + 1, y + 1))
    return out

def extra(data, im, packer):
    # Moon plate: physical-LEFT (west) side only, never mirrored. Sized to the
    # actual glyph cluster rather than a full head-height slab.
    add_side_disc_glyph(data, im, packer, glyph_box=(52, 9, 56, 15), side="west",
                         tex_name="MoonPlate", size=6, offset_z=-1)
    # Two orbiting gold star drones. Every gold pixel across the whole head
    # overlay is cleared so the hair shell stops re-rendering them.
    star_clears = find_pixels(im, (32, 0, 64, 16), STAR_COLOR)
    add_orbiting_stars(data, im, packer, star_box=(41, 9, 42, 10), count=2,
                        tex_name="Stars", radius=18, base_y=126,
                        clear_boxes=star_clears)

result = convert(
    "/home/kyttu/Documents/Skins Yttu/Nyttu.png",
    "/home/kyttu/Documents/blockbench test/conv_test/Nyxie.bbmodel",
    extra_fn=extra,
)
print(result)
