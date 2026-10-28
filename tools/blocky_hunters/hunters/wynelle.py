"""wynelle: the supplied Minecraft (Alex) skin skins/wynelle_source.png on rig-split cubes at vanilla scale, with
her three pigtails in 3D: the centre strand from hunters/pony.py (replacing the strand painted down her back)
plus a long pigtail tied high on each side of the head (L-Pig-1..4 / R-Pig-1..4), all swinging in every clip."""
from bb_core import Cube
from bb_skin import U, m, vanilla_sk, eye_locators, source_hunter
from hunters import pony

NAME = "wynelle"
HEIGHT = 1.78
DESIGN_TOP = 32 * U
SK = vanilla_sk()
EYES = eye_locators()
MODEL_KW = {}

# per side: bone chain hanging from a tie high on the side of the head (skin px)
_PIG = [(1, 30.2, 3.0, 24.6, 3.6), (2, 24.6, 3.6, 18.2, 3.8), (3, 18.2, 3.8, 14.0, 3.8)]
EXTRAS = list(pony.EXTRAS)
for _side, _s in (("L", -1), ("R", 1)):
    for _i, _y, _z, _, _ in _PIG:
        _parent = "Head" if _i == 1 else f"{_side}-Pig-{_i - 1}"
        EXTRAS.append((f"{_side}-Pig-{_i}", _parent, (m(_s * 5.0), m(_y), m(_z)), (6, 5, 1, 0.5 * _i + (0 if _s < 0 else 0.6))))


def _modify(canvas):
    measured = pony.measure(canvas)
    cubes = pony.apply(canvas)                      # centre strand
    colour = measured[0] if measured else canvas.getpixel((12, 3))[:3]
    sw = pony.SWATCH["hair"]
    tie = pony.SWATCH["tie"]
    for side, s in (("L", -1), ("R", 1)):
        cubes.append(Cube(f"{side}-pig-tie", f"{side}-Pig-1", (m(s * 5.0 - 0.7), m(29.5), m(2.2)), (m(s * 5.0 + 0.7), m(31.1), m(4.0)),
                          uv={f: tie for f in "ENWSUD"}))
        spans = [(24.6, 30.2, 3.2, 3.0), (18.2, 24.8, 3.4, 3.0), (14.0, 18.4, 2.6, 2.6)]
        for i, (y0, y1, w, d) in enumerate(spans):
            x = s * (5.7 + 0.35 * i)
            zc = 3.5 + 0.1 * i
            cubes.append(Cube(f"{side}-pig-{i + 1}", f"{side}-Pig-{i + 1}", (m(x - w / 2), m(y0), m(zc - d / 2)),
                              (m(x + w / 2), m(y1), m(zc + d / 2)), uv={f: sw for f in "ENWSUD"}))
    return cubes


def build():
    return source_hunter(NAME, globals(), _modify)
