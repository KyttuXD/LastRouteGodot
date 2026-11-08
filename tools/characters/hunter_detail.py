#!/usr/bin/env python3
"""
Adds grain and edge shading to a converted hunter's packed texture atlas.

The atlases are measurably flat: 9-23 distinct colours, the top 4 covering
76-89% of opaque pixels, binary alpha, and a within-face luminance std of 0.00
for ~65% of faces. There is no gradient or dithering anywhere in any of the 27.

Why this is done PER COLOUR REGION and not per cube face
--------------------------------------------------------
Face UV rects alias each other heavily -- 101 overlapping pairs out of 140
textured faces on a typical model. The torso's up/down caps are slices of the
*north* region, the four eyelids share one 2x2 swatch that itself sits inside
R-Arm.north, and an overlay cube inherits its base cube's cap UVs. So a face
cannot be assumed to own its pixels, and per-face directional shading would
darken the front of the chest while trying to shade the underside of it.

Everything here is therefore keyed off pixel position and colour, never off
face identity, which makes it immune to that aliasing:

  bevel  each contiguous same-colour region is lit from above -- its top edge
         lifted, its bottom edge dropped, its sides dropped slightly. On blocky
         art this is what reads as form.
  grain  a deterministic per-pixel luminance jitter, so large flat fills stop
         looking like plastic.

Protected pixels are left exactly as they were:
  * the face -- Head.north, UV [8,8,16,16], the same 8x8 rect in all 27 models,
    holding a 4 px pupil and a 4 px iris that any noise would destroy
  * tiny packed swatches (<=9 px) such as the 2x2 neck and foot patches, which
    get stretched across a whole cube face -- one jittered pixel there becomes
    a quarter of a foot
"""
import json, base64, io, hashlib
from PIL import Image

# Tuned for atlases this small: the whole model is ~2000 opaque pixels, so the
# effect has to be legible per-pixel without turning into visible noise.
GRAIN = 0.055           # +/- luminance jitter on interior pixels
EDGE_TOP = 1.10         # lit from above
EDGE_BOTTOM = 0.86
EDGE_SIDE = 0.93
MIN_REGION = 6          # smaller regions would be all edge and no interior
MAX_SWATCH_AREA = 9     # a UV rect this small is a stretched swatch, not art


def _norm_rect(uv):
    """UV rects come in v-flipped (up/down faces) and sometimes x-reversed, and
    are frequently fractional -- the torso rows are divided proportionally."""
    x0, y0, x1, y1 = uv
    x0, x1 = min(x0, x1), max(x0, x1)
    y0, y1 = min(y0, y1), max(y0, y1)
    import math
    return (int(math.floor(x0)), int(math.floor(y0)),
            int(math.ceil(x1)), int(math.ceil(y1)))


def protected_mask(model, w, h):
    """Pixels that must not be touched."""
    prot = [[False] * h for _ in range(w)]

    def mark(x0, y0, x1, y1):
        for x in range(max(0, x0), min(w, x1)):
            for y in range(max(0, y0), min(h, y1)):
                prot[x][y] = True

    for el in model.get("elements", []):
        for face, fd in (el.get("faces") or {}).items():
            if fd.get("texture") is None or not fd.get("uv"):
                continue
            x0, y0, x1, y1 = _norm_rect(fd["uv"])
            if x1 <= x0 or y1 <= y0:
                continue
            # The face: same rect in every model, holds pupil and iris.
            if el.get("name") == "Head" and face == "north":
                mark(x0, y0, x1, y1)
            # A swatch this small is stretched over a whole cube face.
            elif (x1 - x0) * (y1 - y0) <= MAX_SWATCH_AREA:
                mark(x0, y0, x1, y1)
    return prot


def _regions(px, w, h):
    """Contiguous 4-connected runs of one exact colour, among opaque pixels."""
    seen = [[False] * h for _ in range(w)]
    out = []
    for sx in range(w):
        for sy in range(h):
            if seen[sx][sy] or px[sx, sy][3] == 0:
                continue
            col = px[sx, sy]
            stack, cells = [(sx, sy)], []
            seen[sx][sy] = True
            while stack:
                x, y = stack.pop()
                cells.append((x, y))
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < w and 0 <= ny < h and not seen[nx][ny] \
                            and px[nx, ny] == col:
                        seen[nx][ny] = True
                        stack.append((nx, ny))
            out.append((col, cells))
    return out


def _jitter(x, y, seed):
    """Deterministic per-pixel noise -- rebuilding a model must not reshuffle
    its grain, or every rebuild would show a spurious texture diff."""
    h = hashlib.md5(f"{seed}:{x},{y}".encode()).digest()
    return (h[0] / 255.0) * 2.0 - 1.0


def add_detail(img, model, seed, grain=GRAIN, bevel=True):
    """Return a new atlas with grain and per-region edge shading applied."""
    img = img.convert("RGBA")
    w, h = img.size
    px = img.load()
    prot = protected_mask(model, w, h)
    out = img.copy()
    opx = out.load()
    touched = 0

    for col, cells in _regions(px, w, h):
        member = set(cells)
        big = len(cells) >= MIN_REGION
        for (x, y) in cells:
            if prot[x][y]:
                continue
            f = 1.0
            if bevel and big:
                if (x, y - 1) not in member:
                    f *= EDGE_TOP
                if (x, y + 1) not in member:
                    f *= EDGE_BOTTOM
                if (x - 1, y) not in member or (x + 1, y) not in member:
                    f *= EDGE_SIDE
            f *= 1.0 + grain * _jitter(x, y, seed)
            r, g, b, a = col
            opx[x, y] = (max(0, min(255, int(r * f))),
                         max(0, min(255, int(g * f))),
                         max(0, min(255, int(b * f))),
                         a)                      # alpha stays binary
            touched += 1
    return out, touched


def _tex_entry(model):
    texs = model.get("textures") or []
    return texs[0] if texs else None


def load_atlas(model):
    t = _tex_entry(model)
    if not t or not str(t.get("source", "")).startswith("data:image/png;base64,"):
        return None
    return Image.open(io.BytesIO(base64.b64decode(t["source"].split(",", 1)[1])))


def store_atlas(model, img):
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    _tex_entry(model)["source"] = "data:image/png;base64," + \
        base64.b64encode(buf.getvalue()).decode()


def process_file(path, seed=None, grain=GRAIN, bevel=True, out_path=None):
    model = json.load(open(path))
    img = load_atlas(model)
    if img is None:
        return None
    before = img.copy()
    new, touched = add_detail(img, model, seed or model.get("name", path), grain, bevel)
    store_atlas(model, new)
    with open(out_path or path, "w") as fh:
        json.dump(model, fh)
    return before, new, touched
