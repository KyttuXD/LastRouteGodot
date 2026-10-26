"""Aki: shy bookworm. Long crimson hair, pink tee with small heart and darker cuffs, plum pleated
skirt, black belt with gold buckle, lavender striped thigh-highs, dark loafers, amber eyes."""
from bb_core import Cube
from bb_paint import Palette, hair_paint, heart, solid, shade, face_cell
from hunters.common import DY, U, HEIGHT, DESIGN_TOP, m, px, sk, eyes, limbs  # noqa

NAME = "aki"
OUT_NAME = "aki_hd"
SK = sk()
EXTRAS = [
    ("Hair-Back-1", "Head", (0.0, m(30.0 + DY), m(4.6)), (4, 2, 1, 0.0)),
    ("Hair-Back-2", "Hair-Back-1", (0.0, m(23.0 + DY), m(5.0)), (6, 3, 1, 0.8)),
    ("Hair-Back-3", "Hair-Back-2", (0.0, m(16.0 + DY), m(5.0)), (8, 3, 1, 1.6)),
]
EYES = eyes()


def build():
    P = Palette(NAME)
    hair, hair_d, hair_l = P.snap((158, 34, 66)), P.snap((120, 22, 52)), P.snap((190, 62, 92))
    skin = P.snap((252, 224, 200))
    pink, pink_d = P.snap((236, 190, 212)), P.snap((178, 132, 162))
    heart_c = P.snap((232, 140, 172))
    plum, plum_d = P.snap((120, 74, 100)), shade(P.snap((120, 74, 100)), .82)
    gold, belt = (214, 170, 80), (40, 36, 40)
    sl, sw = P.snap((206, 192, 228)), P.snap((238, 230, 248))
    shoe = (50, 38, 46)

    def hp(seed, glints=.07, c=None):
        return hair_paint(hair, hair_d, hair_l, cell=c or U, seed=seed, glints=glints)
    strand = hp(3, .06, (U, 2 * U, U))

    def stocking(f, p, n):
        return sl if int((p[1] / U - 2) / 1.5 + 1e-6) % 2 == 0 else sw

    def shoe_p(f, p, n):
        return (84, 66, 78) if f == "U" else (shade(shoe, .7) if f == "D" else shoe)

    def sleeve(f, p, n):
        y = p[1] / U - DY
        return pink if y > 20.2 else pink_d if y > 19.0 else skin

    def skirt(f, p, n):
        if f == "U":
            return plum
        k = int((p[0] / U + 8) + 1e-6) if f in "NS" else int((p[2] / U + 8) + 1e-6)
        return plum if k % 2 == 0 else plum_d

    def belly(f, p, n):
        y = p[1] / U - DY
        if y < 14.6:
            return plum
        if y < 15.7:
            return gold if (f == "N" and abs(p[0] / U) < .7 and y < 15.2) else belt
        return pink

    def chest(f, p, n):
        y = p[1] / U - DY
        h = heart(0.0, m(20.6 + DY), m(1.0), heart_c)(f, p, n)
        if h:
            return h
        return shade(pink, .85) if y > 23.2 else pink

    cubes = limbs(stocking, shoe_p, sleeve, solid(skin))
    cubes += [
        px("skirt-hem", "Pelvis", 0, 14.0, 16.2, 9.8, 6.6, raw=True, paint=skirt),
        px("skirt-top", "Pelvis", 0, 16.2, 19.7, 8.6, 5.4, raw=True, paint=skirt),
        px("belly", "Belly", 0, 12, 18, 8, 4, paint=belly),
        px("chest", "Chest", 0, 18, 24, 8, 4, paint=chest),
    ]
    H = "Head"
    cubes.append(px("head", H, 0, 24, 32, 8, 8, paint=solid(skin)))
    cubes.append(Cube("face", H, (m(-4), m(24.6 + DY), m(-4.03)), (m(4), m(29.6 + DY), m(-4.03)), faces="N", group="face", px=U / 2))
    cubes += [
        px("hair-top", H, 0, 31.8, 32.9, 9.0, 9.0, paint=hp(1)),
        px("hair-tuft", H, 0.8, 32.8, 33.3, 4.0, 4.4, zc=0.5, rot=(0, 0, -5), paint=hp(2, .1)),
        px("hair-side-ru", H, 4.5, 28.0, 32.0, 1.0, 9.0, paint=hp(5)),
        px("hair-side-lu", H, -4.5, 28.0, 32.0, 1.0, 9.0, paint=hp(6)),
        px("hair-back-head", H, 0, 24.5, 32, 9.0, 1.0, zc=4.5, paint=hp(4)),
    ]
    # long side curtains framing the face, falling past the shoulders
    for side, s in (("l", -1), ("r", 1)):
        cubes += [
            px(f"curtain-{side}1", H, s * 4.55, 22.0, 28.0, 1.6, 3.4, zc=-2.4, paint=strand),
            px(f"curtain-{side}2", H, s * 4.7, 15.0, 22.0, 1.4, 3.0, zc=-1.8, rot=(0, 0, -s * 4), paint=strand),
        ]
    # side-swept fringe: longer on viewer's right (-X)
    for i, (x, y0, rz) in enumerate([(-3.4, 28.0, 14), (-1.7, 28.6, 8), (0.0, 29.3, -4), (1.8, 28.9, -8), (3.5, 28.5, -12)]):
        cubes.append(px(f"fringe-{i}", H, x, y0, 32.4, 2.3, 1.0, zc=-4.45, rot=(0, 0, rz), paint=hp(10 + i, .06)))
    # long hair down the back, three swaying segments
    cubes += [
        px("back-1", "Hair-Back-1", 0, 23.0, 30.0, 9.0, 2.2, zc=5.5, paint=hp(30, .05, (U, 2 * U, U))),
        px("back-2", "Hair-Back-2", 0, 16.0, 23.0, 8.4, 2.2, zc=5.6, paint=hp(31, .05, (U, 2 * U, U))),
        px("back-3", "Hair-Back-3", 0, 9.0, 16.0, 7.6, 2.2, zc=5.6, paint=hp(32, .05, (U, 2 * U, U))),
    ]
    style = dict(skin=skin, dark=(70, 30, 44), iris_dark=(120, 62, 30), iris_mid=(205, 126, 44),
                 iris_light=(244, 184, 84), brow=hair_d, mouth=(196, 96, 104), blush=(246, 160, 160),
                 big_eyes=False)
    return cubes, (lambda k: face_cell(k, style))
