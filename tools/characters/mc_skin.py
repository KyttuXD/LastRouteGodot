"""Minecraft skin -> Blockbench model, with no dependencies outside the stdlib.

This replaces a converter that used to live in a scratch directory and was
deleted with it. It lives in the repository now, which is the whole point: the
models in `art/props-3d/characters/` are build products, and a build product
whose builder is gone is a dead end.

What it makes is a plain six-box Minecraft figure -- head, body, two arms, two
legs -- at real MC proportions, plus the transparent second "overlay" layer for
whichever parts actually use it. Nothing anatomical: no separate forearms,
hands, calves, eyelids. That matters, because a 64x64 skin has exactly six UV
islands, and mapping it onto a rig with twenty-one parts leaves fifteen of them
sampling whatever happens to be under their coordinates -- which is what the
previous mannequin did, and why it came out a uniform tan with its limbs
scattered.

Scale: the figure is 32 texture pixels tall and the project wants a 1.7 m
character in a world where 64 Blockbench units = 1 m, so one skin pixel is
3.4 units. Feet sit at y=0, matching how the scene mounts a body at the
CharacterBody3D's own origin.
"""
import base64
import json
import struct
import zlib

# Blockbench units per skin pixel: 32 px tall -> 1.7 m at 64 units/m.
PIXEL = 1.7 * 64.0 / 32.0

# name -> (from, size, uv origin, pivot), all in skin pixels, y up, front = -Z.
# These are the vanilla player proportions and the vanilla 64x64 UV origins.
PARTS = [
    ("Head",     (-4, 24, -4), (8, 8, 8),  (0, 0),   (0, 24, 0)),
    ("Body",     (-4, 12, -2), (8, 12, 4), (16, 16), (0, 24, 0)),
    ("RightArm", (-8, 12, -2), (4, 12, 4), (40, 16), (-5, 22, 0)),
    ("LeftArm",  (4, 12, -2),  (4, 12, 4), (32, 48), (5, 22, 0)),
    ("RightLeg", (-4, 0, -2),  (4, 12, 4), (0, 16),  (-2, 12, 0)),
    ("LeftLeg",  (0, 0, -2),   (4, 12, 4), (16, 48), (2, 12, 0)),
]
# The second layer, drawn as a slightly larger shell around the same box.
OVERLAY_UV = {"Head": (32, 0), "Body": (16, 32), "RightArm": (40, 32),
              "LeftArm": (48, 48), "RightLeg": (0, 32), "LeftLeg": (0, 48)}
OVERLAY_INFLATE = 0.5


def read_png_rgba(path):
    """Decode a non-interlaced 8-bit PNG to (width, height, rows of RGBA).

    Enough of the format to answer one question -- is this region of the skin
    transparent -- without adding Pillow as a build dependency.
    """
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit("%s: not a PNG" % path)
    pos, idat, width = 8, b"", None
    palette, trns, depth, ctype = b"", b"", 8, 6
    while pos < len(data):
        (length,) = struct.unpack_from(">I", data, pos)
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            width, height, depth, ctype, _comp, _filt, interlace = \
                struct.unpack(">IIBBBBB", body)
            if depth != 8 or interlace:
                raise SystemExit("%s: need an 8-bit non-interlaced PNG" % path)
        elif kind == b"PLTE":
            palette = body
        elif kind == b"tRNS":
            trns = body
        elif kind == b"IDAT":
            idat += body
        elif kind == b"IEND":
            break
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ctype]
    raw = zlib.decompress(idat)
    stride = width * channels
    out, prev, at = [], bytearray(stride), 0
    for _y in range(height):
        filt = raw[at]
        line = bytearray(raw[at + 1:at + 1 + stride])
        at += 1 + stride
        for i in range(stride):
            a = line[i - channels] if i >= channels else 0
            b = prev[i]
            if filt == 1:
                line[i] = (line[i] + a) & 0xFF
            elif filt == 2:
                line[i] = (line[i] + b) & 0xFF
            elif filt == 3:
                line[i] = (line[i] + (a + b) // 2) & 0xFF
            elif filt == 4:
                c = prev[i - channels] if i >= channels else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc
                                      else b if pb <= pc else c)) & 0xFF
        prev = line
        row = []
        for x in range(width):
            px = line[x * channels:(x + 1) * channels]
            if ctype == 6:
                row.append(tuple(px))
            elif ctype == 2:
                row.append((px[0], px[1], px[2], 255))
            elif ctype == 4:
                row.append((px[0], px[0], px[0], px[1]))
            elif ctype == 0:
                row.append((px[0], px[0], px[0], 255))
            else:
                i = px[0]
                alpha = trns[i] if i < len(trns) else 255
                row.append((palette[i * 3], palette[i * 3 + 1],
                            palette[i * 3 + 2], alpha))
        out.append(row)
    return width, height, out


def box_uv(u, v, w, h, d):
    """The vanilla six-face unwrap for one box, in texture pixels.

    Front is north (-Z) because that is the way a Godot character faces.
    """
    return {
        "up":    [u + d, v, u + d + w, v + d],
        "down":  [u + d + w, v, u + d + 2 * w, v + d],
        "east":  [u, v + d, u + d, v + d + h],
        "north": [u + d, v + d, u + d + w, v + d + h],
        "west":  [u + d + w, v + d, u + 2 * d + w, v + d + h],
        "south": [u + 2 * d + w, v + d, u + 2 * d + 2 * w, v + d + h],
    }


def _opaque(rows, u, v, w, h, d):
    """Whether a box's unwrap has any non-transparent pixel in it."""
    height = len(rows)
    for x0, y0, x1, y1 in box_uv(u, v, w, h, d).values():
        for y in range(y0, min(y1, height)):
            for x in range(x0, min(x1, len(rows[y]))):
                if rows[y][x][3] > 0:
                    return True
    return False


def _cube(name, origin, size, uv, inflate=0.0):
    lo = [(origin[i] - inflate) * PIXEL for i in range(3)]
    hi = [(origin[i] + size[i] + inflate) * PIXEL for i in range(3)]
    faces = {f: {"uv": box, "texture": 0}
             for f, box in box_uv(uv[0], uv[1], *size).items()}
    return {"name": name, "type": "cube", "uuid": name,
            "from": lo, "to": hi, "faces": faces}


def build(skin_path, name="mannequin"):
    """A Blockbench model of this skin: one bone per part, cubes under it."""
    width, height, rows = read_png_rgba(skin_path)
    if width != 64 or height not in (32, 64):
        raise SystemExit("%s: expected a 64x32 or 64x64 skin, got %dx%d"
                         % (skin_path, width, height))
    legacy = height == 32

    elements, outliner = [], []
    for part, origin, size, uv, pivot in PARTS:
        cubes = [_cube(part, origin, size, uv)]
        # A 64x32 skin has no second layer at all, and on a 64x64 one the
        # layer is often empty -- an inflated shell of fully transparent
        # pixels is invisible geometry that still costs a draw and still
        # z-fights, so it is only emitted where there is something to see.
        if not legacy and _opaque(rows, *OVERLAY_UV[part], *size):
            cubes.append(_cube(part + "Overlay", origin, size,
                               OVERLAY_UV[part], OVERLAY_INFLATE))
        elements += cubes
        outliner.append({"name": part, "uuid": part,
                         "origin": [c * PIXEL for c in pivot],
                         "children": [c["uuid"] for c in cubes]})

    return {
        "meta": {"format_version": "4.5", "model_format": "free",
                 "box_uv": False},
        "name": name,
        "resolution": {"width": width, "height": height},
        "elements": elements,
        "outliner": outliner,
        "groups": [{"name": g["name"], "uuid": g["uuid"], "origin": g["origin"]}
                   for g in outliner],
        "textures": [{"name": name, "id": "0", "source":
                      "data:image/png;base64," +
                      base64.b64encode(open(skin_path, "rb").read()).decode()}],
        "animations": [],
    }


if __name__ == "__main__":
    import sys
    model = build(sys.argv[1])
    json.dump(model, open(sys.argv[2], "w"))
    print("%d elements, %d bones" % (len(model["elements"]),
                                     len(model["outliner"])))
