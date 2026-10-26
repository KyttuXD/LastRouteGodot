"""Xivvy: hyper and airy. Silver bob with a purple butterfly clip, purple tee with dark centre panel
and cuffs, cuffed charcoal shorts with cream belt, purple/white striped thigh-highs, black boots,
big translucent (dithered) butterfly wings on their own flapping bones."""
from bb_core import Cube
from bb_paint import Palette, hair_paint, solid, shade, face_cell
from hunters.common import DY, U, HEIGHT, DESIGN_TOP, m, px, sk, eyes, limbs  # noqa

NAME = "xivvy"
OUT_NAME = "xivvy_hd"
SK = sk()
EXTRAS = [
    ("L-Wing", "Chest", (m(-0.8), m(22.0 + DY), m(2.6)), (16, 0, 1, 0.0)),
    ("R-Wing", "Chest", (m(0.8), m(22.0 + DY), m(2.6)), (-16, 0, 1, 0.0)),
]
EYES = eyes()


def build():
    P = Palette(NAME)
    hair, hair_d, hair_l = P.snap((222, 220, 232)), P.snap((184, 182, 204)), P.snap((246, 246, 252))
    skin = P.snap((252, 224, 202))
    pur, pur_d = P.snap((160, 118, 184)), P.snap((94, 60, 100))
    gray, gray_l = P.snap((78, 80, 90)), P.snap((104, 106, 118))
    cream = P.snap((232, 222, 208))
    sd, sw = P.snap((112, 76, 128)), P.snap((232, 224, 244))
    boot = P.snap((60, 58, 72))
    wing, wing_d, wing_l = P.snap((180, 148, 210)), (112, 79, 128), (214, 194, 238)
    clip = P.snap((112, 79, 128))

    def hp(seed, glints=.06, c=None):
        return hair_paint(hair, hair_d, hair_l, cell=c or U, seed=seed, glints=glints)

    def stocking(f, p, n):
        return sd if int((p[1] / U - 2) / 1.5 + 1e-6) % 2 == 0 else sw

    def boot_p(f, p, n):
        return (88, 86, 104) if f == "U" else (shade(boot, .7) if f == "D" else boot)

    def sleeve(f, p, n):
        y = p[1] / U - DY
        return pur_d if 19.0 < y <= 20.2 else pur if y > 20.2 else skin

    def shorts(f, p, n):
        y = p[1] / U
        return gray_l if y < 11.2 and f in "NSEW" else gray

    def belly(f, p, n):
        y = p[1] / U - DY
        if y < 14.6:
            return gray
        if y < 15.7:
            return (150, 130, 110) if (f == "N" and abs(p[0] / U) < .9 and y < 15.2) else cream
        return pur_d if (f == "N" and abs(p[0] / U) < 1.6) else pur

    def chest(f, p, n):
        y = p[1] / U - DY
        if y > 23.2:
            return pur_d
        return pur_d if (f == "N" and abs(p[0] / U) < 1.6) else pur

    def wing_shape(upper):
        # card local coords: outward distance a (0..1) and height b (0..1)
        def painter(face, p, n):
            side = -1 if p[0] < 0 else 1
            a = (abs(p[0]) / U - 0.8) / 10.0
            b = (p[1] / U - (DY + (20.0 if upper else 12.0))) / (12.0 if upper else 9.0)
            if upper:
                d = ((a - .5) / .52) ** 2 + ((b - .62) / .42) ** 2
                if a > .2 and b < .15:
                    d += 1
            else:
                d = ((a - .42) / .44) ** 2 + ((b - .5) / .5) ** 2
            if d > 1.0:
                return None
            if d > .74:
                return wing_d
            ix, iy = int(abs(p[0]) / U * 2), int(p[1] / U * 2)
            vein = (ix + iy) % 7 == 0 and d < .6
            if vein:
                return wing_l
            return wing if (ix + iy) % 2 == 0 else wing_l
        return painter

    cubes = limbs(stocking, boot_p, sleeve, solid(skin), shoe_h=3.0, shoe_len=6.0, ankle=3.0)
    # cuffed shorts: pelvis block plus a cuff on each thigh
    cubes += [px("shorts", "Pelvis", 0, 14.5, 18.6, 8.6, 4.8, raw=True, paint=shorts),
              px("belly", "Belly", 0, 12, 18, 8, 4, paint=belly),
              px("chest", "Chest", 0, 18, 24, 8, 4, paint=chest)]
    for side, s in (("L", -1), ("R", 1)):
        cubes.append(px(f"{side}-shorts-leg", f"{side}-Thigh", s * 2.05, 12.6, 17.4, 4.5, 4.5, raw=True, paint=shorts))
    H = "Head"
    cubes.append(px("head", H, 0, 24, 32, 8, 8, paint=solid(skin)))
    cubes.append(Cube("face", H, (m(-4), m(24.6 + DY), m(-4.03)), (m(4), m(29.6 + DY), m(-4.03)), faces="N", group="face", px=U / 2))
    cubes += [
        px("hair-top", H, 0, 31.8, 32.9, 9.2, 9.2, paint=hp(1)),
        px("hair-tuft", H, 0.0, 32.8, 33.4, 6.0, 5.0, zc=0.4, paint=hp(2, .1)),
        px("bob-back", H, 0, 24.2, 32, 9.2, 1.3, zc=4.6, paint=hp(4)),
        px("bob-side-r", H, 4.6, 24.8, 32.0, 1.2, 9.0, paint=hp(5)),
        px("bob-side-l", H, -4.6, 24.8, 32.0, 1.2, 9.0, paint=hp(6)),
        px("bob-front-l", H, -4.5, 24.6, 29.5, 1.4, 2.0, zc=-3.6, rot=(0, 0, 5), paint=hp(7)),
        px("bob-front-r", H, 4.5, 24.6, 29.5, 1.4, 2.0, zc=-3.6, rot=(0, 0, -5), paint=hp(8)),
    ]
    for i, (x, y0, rz) in enumerate([(-3.4, 28.4, 8), (-1.7, 28.9, -4), (0.0, 29.2, 3), (1.8, 28.8, -6), (3.5, 28.3, -10)]):
        cubes.append(px(f"fringe-{i}", H, x, y0, 32.4, 2.3, 1.0, zc=-4.45, rot=(0, 0, rz), paint=hp(10 + i, .05)))
    # butterfly hair clip on viewer's right (-X)
    cubes += [px("clip-l", H, -4.9, 29.2, 31.4, 2.2, 1.0, zc=-2.8, rot=(0, 0, 35), paint=solid(clip)),
              px("clip-r", H, -4.9, 29.2, 31.4, 2.2, 1.0, zc=-2.8, rot=(0, 0, -35), paint=solid(shade(clip, 1.25))),
              px("clip-body", H, -4.9, 29.5, 31.0, 0.7, 1.1, zc=-2.8, paint=solid(shade(clip, .6)))]
    # wings: thin double-sided cards, yawed back into a V, hinged at the spine
    for side, s, bone in (("l", -1, "L-Wing"), ("r", 1, "R-Wing")):
        for tag, up, y0, y1, ya in (("up", True, 20.0, 32.0, 22), ("lo", False, 12.0, 21.0, 14)):
            x0, x1 = (s * 0.8, s * 11.0)
            cubes.append(Cube(f"wing-{side}-{tag}", bone,
                              (m(min(x0, x1)), m(y0 + DY - (DY if False else 0)) if False else m(y0 + DY - 0), m(2.6 if up else 2.9)),
                              (m(max(x0, x1)), m(y1 + DY - 0), m(2.8 if up else 3.1)),
                              faces="NS", px=U / 2, paint=wing_shape(up),
                              rot=(0, -s * ya, 0), pivot=(m(s * 0.8), m(22 + DY), m(2.6))))
    style = dict(skin=skin, dark=(60, 48, 80), iris_dark=(84, 68, 120), iris_mid=(150, 130, 192),
                 iris_light=(196, 182, 232), brow=hair_d, mouth=(190, 100, 120), blush=(246, 170, 176),
                 big_eyes=False)
    return cubes, (lambda k: face_cell(k, style))
