"""Shared helpers: geometry is authored in original Minecraft-skin pixels (1 px = U metres)."""
from bb_core import Cube

DY = 5.0                 # extra leg length in skin px (taller than a vanilla skin: 17 px legs)
U = 1.78 / (32.8 + DY)   # metres per skin pixel so feet-to-hair is 1.78 m
HEIGHT = 1.78
DESIGN_TOP = (32.8 + DY) * U


def m(v):
    return v * U


def ymap(y0, y1, raw):
    """Design y (vanilla skin px) -> final px: legs stretch 1.5x, everything above the hips shifts up."""
    if raw:
        return y0, y1
    if y0 >= 12:
        return y0 + DY, y1 + DY
    if y1 <= 12:
        f = lambda y: y if y <= 2 else 2 + 1.5 * (y - 2) if y <= 7 else 9.5 + 1.5 * (y - 7)
        return f(y0), f(y1)
    return y0, y1


def px(name, bone, cx, y0, y1, w, d, zc=0.0, rot=(0, 0, 0), pivot=None, raw=False, **kw):
    y0, y1 = ymap(y0, y1, raw)
    if pivot and not raw:
        pivot = (pivot[0], pivot[1] + DY, pivot[2])
    lo = (m(cx - w / 2), m(y0), m(zc - d / 2))
    hi = (m(cx + w / 2), m(y1), m(zc + d / 2))
    return Cube(name, bone, lo, hi, rot=rot, pivot=tuple(m(v) for v in pivot) if pivot else None, px=U / 2, **kw)


# Standard Hytale/Minecraft joint heights in skin px (each hunter may override a few)
SK_PX = dict(hip_y=17, hip_x=2.05, thigh_y=17, knee_y=9.5, ankle_y=2, belly_y=17, chest_y=23,
             neck_y=29, sh_x=5.5, sh_y=28, elbow_y=22, wrist_y=18.5)


def sk(**over):
    d = dict(SK_PX)
    d.update(over)
    return {k: m(v) for k, v in d.items()}


def eyes(y=27.0 + DY, x=2.6, z=-4.1):
    return {"L": (m(-x), m(y), m(z)), "R": (m(x), m(y), m(z))}


def limbs(stocking, shoe_p, sleeve, skin, shoe_h=2.0, shoe_len=6.0, ankle=2.0, knee=7.0, thigh_top=12.0,
          cuff=None):
    """Legs (thigh, calf, shoe) and arms (sleeve+arm, forearm, hand) of the standard body."""
    cubes = []
    for side, s in (("L", -1), ("R", 1)):
        x = s * 2.05
        cubes += [
            px(f"{side}-thigh", f"{side}-Thigh", x, knee, thigh_top, 4.0, 4.0, paint=stocking),
            px(f"{side}-calf", f"{side}-Calf", x, ankle, knee, 3.8, 3.8, paint=stocking),
            px(f"{side}-shoe", f"{side}-Foot", x, 0, shoe_h, 4.2, shoe_len, zc=-(shoe_len - 4.0) / 2, paint=shoe_p),
        ]
        ax = s * 5.5
        cubes += [
            px(f"{side}-arm", f"{side}-Arm", ax, 17, 23, 3, 3.4, paint=sleeve),
            px(f"{side}-forearm", f"{side}-Forearm", ax, 13.5, 17, 2.8, 3.0, paint=skin),
            px(f"{side}-hand", f"{side}-Hand", ax + s * .1, 11 + DY, 13.5 + DY, 3.2, 3.4, raw=True, paint=skin),
        ]
    return cubes
