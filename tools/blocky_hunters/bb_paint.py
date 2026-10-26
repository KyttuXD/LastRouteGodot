"""Palette-from-sheet and painter helpers for the cube hunters.

Colours are *snapped* to the k-means palette of the hunter's anime sheet, so the
texture is built from the sheet's own colours; stripes, checks, hearts, belts
and the face are then drawn by rule (crisp, no resampling blur).
"""
import numpy as np
from PIL import Image
from bb_core import hash01, FACE_CELL

SHEETS = "/Volumes/BIG-HDD-2/Game Stuff/LastRoute-NewSprites/roster-generated/roster-cutouts/"


class Palette:
    def __init__(self, name, k=48, seed=7):
        im = Image.open(SHEETS + f"{name}-luma-uni-1.png").convert("RGB")
        im = im.resize((im.width // 3, im.height // 3), Image.NEAREST)
        px = np.asarray(im).reshape(-1, 3).astype(np.float32)
        rng = np.random.default_rng(seed)
        sub = px[rng.choice(len(px), 40000, replace=False)]
        cent = sub[rng.choice(len(sub), k, replace=False)]
        for _ in range(14):
            d = ((sub[:, None, :] - cent[None]) ** 2).sum(2)
            lab = d.argmin(1)
            for i in range(k):
                m = sub[lab == i]
                if len(m):
                    cent[i] = m.mean(0)
        self.centres = cent

    def snap(self, rgb, tol=46):
        c = np.array(rgb, dtype=np.float32)
        d = np.sqrt(((self.centres - c) ** 2).sum(1))
        i = d.argmin()
        return tuple(int(v) for v in (self.centres[i] if d[i] < tol else c))


def shade(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c[:3])


def mix(a, b, t):
    return tuple(int(a[i] * (1 - t) + b[i] * t) for i in range(3))


def solid(c):
    return lambda f, p, n: c


def with_alpha(c, a):
    return (*c[:3], a)


def hair_paint(base, dark, light, cell=0.0625, glints=0.12, seed=0, flow_axis=1):
    """Reference-style hair: large checker clumps of two tones plus sparse light glints.
    The checker lives in 3D, so it carries on over the cube edges."""
    cs = cell if isinstance(cell, tuple) else (cell, cell, cell)

    def f(face, p, n):
        cx, cy, cz = (int(np.floor(v / c + 1e-6)) for v, c in zip(p, cs))
        par = (cx + cy + cz) & 1
        col = dark if par else base
        h = hash01(cx, cy, cz, seed)
        if h < glints:
            col = light
        elif h > 0.93:
            col = shade(dark, 0.85)
        return col
    return f


def stripes(a, b, y0, step, axis=1, top=None):
    def f(face, p, n):
        k = int(np.floor((p[axis] - y0) / step + 1e-6))
        return a if k % 2 == 0 else b
    return f


def layered(*layers):
    """layers: callables (face,p,n) -> colour or None; first non-None wins."""
    def f(face, p, n):
        for l in layers:
            c = l(face, p, n)
            if c is not None:
                return c
        return None
    return f


def when(cond, painter):
    return lambda face, p, n: painter(face, p, n) if cond(face, p, n) else None


def heart(cx, cy, size, col, front="N"):
    """Pixel heart in world xy for the front (or back) face."""
    def f(face, p, n):
        if face != front:
            return None
        x, y = (p[0] - cx) / size, (p[1] - cy) / size
        v = (x * x + y * y - 1) ** 3 - x * x * y ** 3
        return col if v < 0 else None
    return f


# ---- face cells --------------------------------------------------------------

EYE_NEUTRAL = [
    ".DDD.",
    "DIIID",
    "DIWMD",
    "DMMMD",
    ".LLL.",
]
EYE_BIG = [
    ".DDDD.",
    "DIIIID",
    "DIWIMD",
    "DIIMMD",
    "DMMMLD",
    ".LLLL.",
]
EYE_STUN = [
    "D...D",
    ".D.D.",
    "..D..",
    ".D.D.",
    "D...D",
]
EYE_ANGRY = [
    "DD...",
    ".DDDD",
    "DIIMD",
    ".LLL.",
]


def _blit(img, pat, x, y, cols, flip=False):
    for j, row in enumerate(pat):
        r = row[::-1] if flip else row
        for i, ch in enumerate(r):
            if ch in cols:
                xx, yy = x + i, y + j
                if 0 <= xx < img.width and 0 <= yy < img.height:
                    img.putpixel((xx, yy), cols[ch])


class _Safe:
    """Image wrapper: out-of-cell pixel writes are ignored instead of raising."""
    def __init__(self, img):
        self.img, self.width, self.height = img, img.width, img.height

    def putpixel(self, xy, c):
        if 0 <= xy[0] < self.width and 0 <= xy[1] < self.height:
            self.img.putpixel(xy, c)


def face_cell(k, st):
    """Expression cell k (0 neutral, 1 blink, 2 stun, 3 chase, 4 scream, 5 happy), style dict st."""
    w, h = FACE_CELL
    real = Image.new("RGBA", (w, h), (*st["skin"], 255))
    img = _Safe(real)
    d = st["dark"]
    cols = {"D": d, "I": st["iris_dark"], "M": st["iris_mid"], "L": st["iris_light"], "W": (255, 255, 255)}
    lx, rx = st.get("eye_lx", 1), st.get("eye_rx", 10)
    ey = st.get("eye_y", 1)
    brow = st["brow"]
    mouth = st["mouth"]
    blush = st["blush"]

    def brows(dy=0, tilt=0):
        for i in range(4):
            for xs in (lx, rx):
                img.putpixel((xs + i + (0 if xs == lx else 1), max(0, ey - 2 + dy + (i * tilt // 3 if xs == lx else (3 - i) * tilt // 3))), brow)

    def cheeks():
        for xs in (lx - 1, rx + 2):
            for i in range(3):
                img.putpixel((xs + i, ey + 6), blush)

    cx = w // 2
    if k == 0:
        _blit(img, EYE_BIG if st.get("big_eyes") else EYE_NEUTRAL, lx, ey, cols)
        _blit(img, EYE_BIG if st.get("big_eyes") else EYE_NEUTRAL, rx - (1 if st.get("big_eyes") else 0), ey, cols, flip=True)
        brows()
        cheeks()
        img.putpixel((cx - 1, ey + 7), mouth)
        img.putpixel((cx, ey + 7), mouth)
        img.putpixel((cx - 2, ey + 6), mouth)
        img.putpixel((cx + 1, ey + 6), mouth)
    elif k == 1:  # blink
        for xs in (lx, rx):
            for i in range(5):
                img.putpixel((xs + i, ey + 3), d)
        for xs in (lx + 1, rx + 1):
            img.putpixel((xs, ey + 4), d)
            img.putpixel((xs + 2, ey + 4), d)
        brows()
        cheeks()
        img.putpixel((cx - 1, ey + 7), mouth)
        img.putpixel((cx, ey + 7), mouth)
    elif k == 2:  # stunned: X eyes, wobbly o mouth
        _blit(img, EYE_STUN, lx, ey + 1, cols)
        _blit(img, EYE_STUN, rx, ey + 1, cols)
        brows(-1)
        for (x, y) in ((cx - 1, ey + 7), (cx, ey + 7), (cx - 2, ey + 8), (cx + 1, ey + 8), (cx - 1, ey + 9), (cx, ey + 9)):
            img.putpixel((x, y), mouth)
    elif k == 3:  # chase: narrowed, angry
        _blit(img, EYE_ANGRY, lx, ey + 1, cols)
        _blit(img, EYE_ANGRY, rx, ey + 1, cols, flip=True)
        for i in range(4):
            img.putpixel((lx + i, ey - 1 + i // 2), brow)
            img.putpixel((rx + 4 - i, ey - 1 + i // 2), brow)
        for x in range(cx - 2, cx + 2):
            img.putpixel((x, ey + 8), mouth)
        img.putpixel((cx - 2, ey + 9), mouth)
        img.putpixel((cx + 1, ey + 9), mouth)
    elif k == 4:  # scream: wide eyes, gaping mouth
        _blit(img, EYE_BIG, lx - 1, ey - 1, cols)
        _blit(img, EYE_BIG, rx + 0, ey - 1, cols, flip=True)
        brows(-2)
        for y in range(ey + 6, ey + 10):
            for x in range(cx - 2, cx + 2):
                img.putpixel((x, y), (60, 20, 30))
        for x in range(cx - 1, cx + 1):
            img.putpixel((x, ey + 9), (220, 90, 110))
    else:  # happy ^ ^
        for xs in (lx, rx):
            pts = ((0, 3), (1, 2), (2, 1), (3, 2), (4, 3))
            for (i, j) in pts:
                img.putpixel((xs + i, ey + j), d)
        cheeks()
        for x in range(cx - 2, cx + 2):
            img.putpixel((x, ey + 7), mouth)
        img.putpixel((cx - 1, ey + 8), mouth)
        img.putpixel((cx, ey + 8), mouth)
    return real
