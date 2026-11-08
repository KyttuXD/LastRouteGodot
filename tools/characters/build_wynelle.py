import sys
import os as _os, sys as _sys
# The toolchain used to live in a scratch directory that was deleted.
# It lives here now; resolve siblings relative to this file, never a path.
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
_sys.path.insert(0, _os.path.join(_os.path.dirname(_os.path.abspath(__file__)), _os.pardir, "office"))
from mc_to_hytale import convert, rect_to_uv, add_free_cube, add_bone_group, find_element
from special_characters import FLAT

def extra(data, im, packer):
    # Three distinct tied hair masses: left pigtail, right pigtail, rear
    # ponytail -- each a flat double-sided plane on its own bone (pivoted at
    # its tie/servo cuff) so all three can sway independently and never read
    # as one merged curtain, per the design doc's invariant.
    hair_crop = im.crop((40, 0, 44, 3))
    off = packer.add(hair_crop)
    uv = rect_to_uv(off[0], off[1], off[0] + 4, off[1] + 3, "north")
    head = find_element(data, "Head")
    top_y = head["to"][1]
    specs = [
        # name, pivot (tie point), width, height, plane axis
        ("L-Pigtail", (-15, top_y - 2, -2), 4, 9, "x"),
        ("R-Pigtail", (15, top_y - 2, -2), 4, 9, "x"),
        ("Rear-Ponytail", (0, top_y - 4, 13), 8, 19, "z"),
    ]
    for name, pivot, w, h, axis in specs:
        px, py, pz = pivot
        bone = f"{name}-Bone"
        add_bone_group(data, bone, origin=[px, py, pz], parent_group_name="Head")
        if axis == "x":
            frm = [px - FLAT / 2, py - h, pz - w / 2]
            to = [px + FLAT / 2, py, pz + w / 2]
            faces = {"east": uv, "west": uv}
        else:
            frm = [px - w / 2, py - h, pz - FLAT / 2]
            to = [px + w / 2, py, pz + FLAT / 2]
            faces = {"north": uv, "south": uv}
        add_free_cube(
            data, name, frm=frm, to=to, origin=[px, py, pz],
            faces_uv=faces, tex_index=0, parent_group_name=bone, double_sided=True,
        )

result = convert(
    _os.path.join(_os.environ.get("SKINS_DIR", "./skins"), "Wyttu.png"),
    _os.path.join(_os.environ.get("OUT_DIR", "./out"), "Wynelle.bbmodel"),
    extra_fn=extra,
)
print(result)
