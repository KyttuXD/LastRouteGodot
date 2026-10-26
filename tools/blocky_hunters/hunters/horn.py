"""Curved cube horns for the horned hunters (Glyra, Jyvra, Umbriel).

Each horn is a chain of stacked, tapering, progressively tilted cubes (the cube-style way to curve something).
Both horns hang off static L-Horn/R-Horn bones. Size and colour come from the hunter's module; any horn art
painted on the skin's face is cleared by that module."""
import math
from bb_core import Cube
from bb_skin import m

SWATCH = {"base": (46, 66, 2, 2), "tip": (48, 66, 2, 2)}


def extras(base_xyz):
    x, y, z = base_xyz
    return [("L-Horn", "Head", (m(-x), m(y), m(z)), None), ("R-Horn", "Head", (m(x), m(y), m(z)), None)]


def modify(canvas, color, tip, base_xyz, lengths, widths, depths, lean, curl, pitch=0.0, paint=()):
    """paint: colours of the horn art painted on the skin; removed (hat layer -> transparent, head box -> hair)."""
    hair = canvas.getpixel((12, 3))[:3]
    for y in range(0, 16):
        for x in range(0, 64):
            p = canvas.getpixel((x, y))
            if p[3] and p[:3] in paint:
                canvas.putpixel((x, y), (0, 0, 0, 0) if x >= 32 else (*hair, 255))
    for key, c in (("base", color), ("tip", tip)):
        x, y, w, h = SWATCH[key]
        for j in range(h):
            for i in range(w):
                canvas.putpixel((x + i, y + j), (*c, 255))
    cubes = []
    bx, by, bz = base_xyz
    for side, s in (("L", -1), ("R", 1)):
        px_, py_ = s * bx, by                        # chain start (x outward-signed, y up)
        for i, (L, w, d) in enumerate(zip(lengths, widths, depths)):
            theta = lean + curl * i                   # degrees from vertical, toward outward
            dx, dy = s * math.sin(math.radians(theta)), math.cos(math.radians(theta))
            cx, cy = px_ + dx * L / 2, py_ + dy * L / 2
            key = "tip" if i == len(lengths) - 1 else "base"
            sw = SWATCH[key]
            cubes.append(Cube(f"{side}-horn-{i}", f"{side}-Horn",
                              (m(cx - w / 2), m(cy - L / 2), m(bz - d / 2)), (m(cx + w / 2), m(cy + L / 2), m(bz + d / 2)),
                              uv={f: sw for f in "ENWSUD"}, rot=(-pitch, 0, -s * theta)))
            px_, py_ = px_ + dx * L * .9, py_ + dy * L * .9
    return cubes
