"""Kathy in original Minecraft-skin / Hytale proportions (head 8, torso 12, legs 12 skin px).

Purple high ponytail + red bow, red top with pink heart, navy pleated skirt, purple/white
striped thigh-highs, black loafers, amber eyes. Geometry is written in skin pixels (1 px = U m)."""
from bb_core import Cube
from bb_paint import Palette, hair_paint, layered, heart, solid, shade, face_cell

NAME = "kathy"
OUT_NAME = "kathy_hd"
from hunters.common import DY, U, HEIGHT, DESIGN_TOP, m, px, sk, eyes, limbs  # noqa

SK = sk()
EXTRAS = [
    ("Pony-1", "Head", (0.0, m(31.2 + DY), m(4.6)), (7, 3, 1, 0.0)),
    ("Pony-2", "Pony-1", (0.0, m(26.0 + DY), m(4.8)), (9, 4, 1, 0.7)),
    ("Pony-3", "Pony-2", (0.0, m(21.0 + DY), m(4.8)), (12, 5, 1, 1.4)),
]
EYES = eyes()


def build():
    P = Palette(NAME)
    hair, hair_d, hair_l = P.snap((152, 126, 172)), P.snap((126, 100, 152)), P.snap((178, 152, 198))
    skin = P.snap((252, 218, 190))
    red, red_d = P.snap((190, 60, 66)), P.snap((140, 38, 48))
    pink = P.snap((238, 146, 164))
    navy = P.snap((60, 68, 105)); navy_d = shade(navy, .8)
    gold = (214, 170, 80)
    sp, sw = P.snap((150, 125, 165)), P.snap((224, 212, 235))
    shoe = (38, 34, 44)
    bow, bow_d = P.snap((190, 52, 60)), (140, 30, 44)
    cell = U / 2

    def hp(seed, glints=.07, c=None):
        return hair_paint(hair, hair_d, hair_l, cell=c or U, seed=seed, glints=glints)
    strand = hp(3, .05, (U, 2 * U, U))

    def stocking(f, p, n):                      # 1 skin px stripes from the shoe up
        k = int((p[1] / U - 2) / 1.5 + 1e-6)
        return sp if k % 2 == 0 else sw

    def shoe_p(f, p, n):
        return (62, 56, 72) if f == "U" else (shade(shoe, .7) if f == "D" else shoe)

    def sleeve(f, p, n):
        y = p[1] / U - DY
        return red if y > 19.6 else (red_d if y > 19.0 else skin)

    def skirt(f, p, n):
        if f == "U":
            return navy
        k = int((p[0] / U + 8) + 1e-6) if f in "NS" else int((p[2] / U + 8) + 1e-6)
        return navy if k % 2 == 0 else navy_d

    def belly(f, p, n):
        y = p[1] / U - DY
        if y < 15.5:
            return gold if (f == "N" and abs(p[0] / U) < .5 and y > 14.6) else navy
        return red

    def chest(f, p, n):
        y = p[1] / U - DY
        hp_ = heart(0.0, m(20.9 + DY), m(1.35), pink)(f, p, n)
        if hp_:
            return hp_
        if y > 23.0:
            return gold if (f == "N" and abs(p[0] / U) < .6 and y < 23.6) else red_d
        return red

    cubes = []
    for side, s in (("L", -1), ("R", 1)):
        x = s * 2.05
        cubes += [
            px(f"{side}-thigh", f"{side}-Thigh", x, 7, 12, 4.0, 4.0, paint=stocking),
            px(f"{side}-calf", f"{side}-Calf", x, 2, 7, 3.8, 3.8, paint=stocking),
            px(f"{side}-shoe", f"{side}-Foot", x, 0, 2, 4.2, 6.0, zc=-1.0, paint=shoe_p),
        ]
    cubes += [
        px("skirt-hem", "Pelvis", 0, 14.2, 16.4, 9.8, 6.6, raw=True, paint=skirt),
        px("skirt-top", "Pelvis", 0, 16.4, 19.7, 8.6, 5.4, raw=True, paint=skirt),
        px("belly", "Belly", 0, 12, 18, 8, 4, paint=belly),
        px("chest", "Chest", 0, 18, 24, 8, 4, paint=chest),
    ]
    for side, s in (("L", -1), ("R", 1)):
        x = s * 5.5
        cubes += [
            px(f"{side}-arm", f"{side}-Arm", x, 17, 23, 3, 3.4, paint=sleeve),
            px(f"{side}-forearm", f"{side}-Forearm", x, 13.5, 17, 2.8, 3.0, paint=solid(skin)),
            px(f"{side}-hand", f"{side}-Hand", x + s * .1, 11 + DY, 13.5 + DY, 3.2, 3.4, raw=True, paint=solid(skin)),
        ]
    # head: 8x8x8 skin cube, expression quad on its front, hair as slightly larger cubes
    H = "Head"
    cubes.append(px("head", H, 0, 24, 32, 8, 8, paint=solid(skin)))
    cubes.append(Cube("face", H, (m(-4), m(24.6 + DY), m(-4.03)), (m(4), m(29.6 + DY), m(-4.03)), faces="N", group="face", px=U / 2))
    cubes += [
        px("hair-top", H, 0, 31.8, 32.9, 9.0, 9.0, paint=hp(1)),
        px("hair-tuft", H, -0.6, 32.8, 33.4, 4.4, 4.6, zc=1.0, rot=(0, 0, 6), paint=hp(2, .1)),
        px("hair-back", H, 0, 27.0, 32, 9.0, 1.0, zc=4.5, paint=hp(4)),
        px("hair-side-ru", H, 4.5, 29.4, 32.0, 1.0, 9.0, paint=hp(5)),
        px("hair-side-lu", H, -4.5, 29.4, 32.0, 1.0, 9.0, paint=hp(6)),
        px("hair-side-rl", H, 4.5, 26.6, 29.4, 1.0, 5.0, zc=2.0, paint=hp(7)),
        px("hair-side-ll", H, -4.5, 26.6, 29.4, 1.0, 5.0, zc=2.0, paint=hp(8)),
    ]
    for i, (x, y0, rz) in enumerate([(-3.4, 28.8, 10), (-1.7, 29.2, -6), (0.0, 29.5, 4), (1.8, 29.0, 8), (3.5, 28.6, -10)]):
        cubes.append(px(f"fringe-{i}", H, x, y0, 32.4, 2.3, 1.0, zc=-4.45, rot=(0, 0, rz), paint=hp(10 + i, .06)))
    cubes += [
        px("lock-l", H, -4.55, 23.0, 30.0, 1.3, 2.2, zc=-3.2, paint=strand),
        px("lock-l2", H, -4.6, 19.5, 23.0, 1.1, 1.8, zc=-3.1, rot=(0, 0, -4), paint=strand),
        px("lock-r", H, 4.55, 25.5, 30.0, 1.2, 2.2, zc=-3.2, paint=strand),
    ]
    cubes += [
        px("pony-tie", "Pony-1", 0, 30.0, 32.2, 2.6, 2.2, zc=4.7, paint=solid(bow)),
        px("pony-1", "Pony-1", 0, 26.0, 30.2, 3.6, 3.0, zc=5.9, rot=(-10, 0, 0), pivot=(0, 30.2, 4.7), paint=strand),
        px("pony-2", "Pony-2", 0, 21.0, 26.0, 3.8, 2.8, zc=6.1, paint=strand),
        px("pony-3", "Pony-3", -0.1, 16.0, 21.0, 3.4, 2.6, zc=6.1, rot=(0, 0, -3), paint=strand),
        px("pony-tip", "Pony-3", -0.3, 13.0, 16.0, 2.0, 2.0, zc=6.1, rot=(0, 0, -6), paint=strand),
    ]
    cubes += [
        px("bow-l", H, 4.9, 29.0, 31.8, 2.4, 1.4, zc=-2.6, rot=(0, 0, 30), paint=solid(bow)),
        px("bow-r", H, 4.9, 29.0, 31.8, 2.4, 1.4, zc=-2.6, rot=(0, 0, -30), paint=solid(bow_d)),
        px("bow-knot", H, 4.9, 29.9, 30.9, 1.2, 1.6, zc=-2.6, paint=solid(shade(bow, .7))),
    ]
    style = dict(skin=skin, dark=(64, 36, 52), iris_dark=(122, 60, 30), iris_mid=(205, 124, 44),
                 iris_light=(242, 178, 80), brow=hair_d, mouth=(190, 92, 96), blush=(246, 162, 150),
                 big_eyes=False)
    return cubes, (lambda k: face_cell(k, style))
