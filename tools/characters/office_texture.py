#!/usr/bin/env python3
"""
Paints the office texture atlas.

Colours are lifted from the 2D office (`scenes/office.tscn`) so the 3D room
reads as the same place, then brightened ~2.5x: those Color() values are flat
unlit fills, and a 3D room multiplies them down again under its own lights.
Authoring them at face value gives a room that renders essentially black.

Two kinds of patch:
  "pattern"  a continuous surface (floor, walls, desk). Authored large; every
             face samples a sub-rect at a fixed texels-per-metre density, so a
             1.9 m wall stub and a 6 m wall have identical grain.
  "fitted"   a discrete object (door, vent cover, screen). Authored at the
             face's own aspect ratio and mapped whole.
"""
import random
from PIL import Image, ImageDraw

DENS = 12.0          # texels per metre for pattern materials
ATLAS = 256

def _c(r, g, b, lift=1.0):
    """tscn Color() 0-1 floats -> 8-bit, optionally brightened.

    Only the near-black STRUCTURAL colours get lifted: they are flat unlit
    fills in 2D, and a lit 3D room multiplies them down again, so used at face
    value the room renders black. The accent colours are already display-bright
    and must be left alone -- lifting them saturates every channel, which turns
    the amber lamp pure white and the hazard red pink."""
    return tuple(min(255, int(v * 255 * lift)) for v in (r, g, b))

STRUCT = 3.0                                  # lift for the near-black fills
VOID       = _c(0.012, 0.016, 0.022, STRUCT)  # near-black backdrop
WALL       = _c(0.055, 0.062, 0.075, STRUCT)  # office wall panel
WALL_HI    = _c(0.09,  0.10,  0.12,  STRUCT)  # lighter band / trim
DESK       = _c(0.075, 0.065, 0.055, STRUCT)  # warm dark laminate
GREEN      = _c(0.10,  0.13,  0.12,  STRUCT)
TEAL       = _c(0.20,  0.45,  0.45)           # UI accent, used for signage
TEAL_HI    = _c(0.45,  0.60,  0.62)
RED        = _c(0.85,  0.30,  0.35)           # alarm / hazard
AMBER      = _c(0.90,  0.80,  0.40)           # lamp glow

# Floor and ceiling are keyed off the wall rather than the near-black VOID, so
# the room reads as dim rather than as a void with three grey slabs in it.
FLOOR_BASE   = tuple(int(v * 0.60) for v in WALL)
CEILING_BASE = tuple(int(v * 0.45) for v in WALL)

def _shade(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c)

def _speckle(d, w, h, base, rng, amount=0.30, n=None):
    """Per-pixel grain. Keeps flat fills from looking like plastic."""
    for _ in range(n if n is not None else int(w * h * amount)):
        x, y = rng.randrange(w), rng.randrange(h)
        d.point((x, y), _shade(base, rng.uniform(0.78, 1.22)))

# --- per-material painters -------------------------------------------------

def paint_floor(w, h, rng):
    im = Image.new("RGBA", (w, h), FLOOR_BASE)
    d = ImageDraw.Draw(im)
    _speckle(d, w, h, FLOOR_BASE, rng, 0.5)
    step = int(DENS)                      # one seam per metre
    for x in range(0, w, step):
        d.line([(x, 0), (x, h)], _shade(FLOOR_BASE, 0.55))
    for y in range(0, h, step):
        d.line([(0, y), (w, y)], _shade(FLOOR_BASE, 0.55))
    # scuffed patches where a chair would have worn the floor
    for _ in range(8):
        cx, cy = rng.randrange(w), rng.randrange(h)
        r = rng.randint(2, 5)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], _shade(FLOOR_BASE, 1.35))
    return im

def paint_ceiling(w, h, rng):
    im = Image.new("RGBA", (w, h), CEILING_BASE)
    d = ImageDraw.Draw(im)
    _speckle(d, w, h, CEILING_BASE, rng, 0.35)
    step = int(DENS * 1.5)                # 1.5 m ceiling tiles
    for x in range(0, w, step):
        d.line([(x, 0), (x, h)], _shade(CEILING_BASE, 0.5))
    for y in range(0, h, step):
        d.line([(0, y), (w, y)], _shade(CEILING_BASE, 0.5))
    # dead strip-lights, unlit
    for y in range(step // 2, h, step * 2):
        d.rectangle([step // 2, y - 1, w - step // 2, y + 1], _shade(WALL_HI, 1.3))
    return im

def paint_wall(w, h, rng):
    im = Image.new("RGBA", (w, h), WALL)
    d = ImageDraw.Draw(im)
    # grime gathers toward the floor -- v grows downward, so darken with y
    for y in range(h):
        f = 1.0 - 0.35 * (y / max(1, h - 1)) ** 2
        d.line([(0, y), (w, y)], _shade(WALL, f))
    _speckle(d, w, h, WALL, rng, 0.4)
    seam = int(DENS * 1.5)                # panel joint every 1.5 m
    for x in range(0, w, seam):
        d.line([(x, 0), (x, h)], _shade(WALL, 0.6))
        d.line([(x + 1, 0), (x + 1, h)], _shade(WALL, 1.35))
    rail = int(h * 0.62)                  # chair rail
    d.rectangle([0, rail, w, rail + 1], WALL_HI)
    d.line([(0, rail + 2), (w, rail + 2)], _shade(WALL, 0.5))
    return im

def paint_door(w, h, rng):
    """Heavy steel roll-down shutter: ribs, rivets, hazard chevrons."""
    im = Image.new("RGBA", (w, h), _shade(WALL_HI, 1.15))
    d = ImageDraw.Draw(im)
    _speckle(d, w, h, _shade(WALL_HI, 1.15), rng, 0.3)
    for y in range(0, h, 4):              # horizontal shutter slats
        d.line([(0, y), (w, y)], _shade(WALL_HI, 0.55))
        d.line([(0, y + 1), (w, y + 1)], _shade(WALL_HI, 1.5))
    for y in range(2, h, 8):              # rivets down both edges
        d.point((1, y), _shade(WALL_HI, 1.9))
        d.point((w - 2, y), _shade(WALL_HI, 1.9))
    band = h - 7                          # hazard chevrons along the bottom
    d.rectangle([0, band, w, h], _shade(AMBER, 0.34))
    for x in range(-h, w, 6):
        d.line([(x, h), (x + 6, band)], RED, width=2)
    d.rectangle([0, band - 1, w, band - 1], _shade(WALL_HI, 1.6))
    return im

def paint_metal(w, h, rng):
    im = Image.new("RGBA", (w, h), _shade(WALL_HI, 1.0))
    d = ImageDraw.Draw(im)
    _speckle(d, w, h, _shade(WALL_HI, 1.0), rng, 0.5)
    d.rectangle([0, 0, w - 1, h - 1], outline=_shade(WALL_HI, 0.55))
    return im

def paint_vent(w, h, rng):
    im = Image.new("RGBA", (w, h), _shade(VOID, 1.2))
    d = ImageDraw.Draw(im)
    for y in range(1, h - 1, 3):          # louver slats over darkness
        d.rectangle([1, y, w - 2, y], _shade(WALL_HI, 1.45))
        d.rectangle([1, y + 1, w - 2, y + 1], _shade(VOID, 0.6))
    d.rectangle([0, 0, w - 1, h - 1], outline=_shade(WALL_HI, 0.9))
    return im

def paint_desk(w, h, rng):
    im = Image.new("RGBA", (w, h), DESK)
    d = ImageDraw.Draw(im)
    _speckle(d, w, h, DESK, rng, 0.55)
    for _ in range(14):                   # wood-ish grain streaks
        y = rng.randrange(h)
        x0 = rng.randrange(w)
        d.line([(x0, y), (min(w, x0 + rng.randint(4, 14)), y)], _shade(DESK, rng.uniform(0.7, 1.4)))
    d.rectangle([0, 0, w - 1, h - 1], outline=_shade(DESK, 1.6))
    return im

def paint_screen(w, h, rng):
    """Idle monitor: dark glass, scanlines, a faint camera-feed wash."""
    im = Image.new("RGBA", (w, h), _shade(VOID, 0.8))
    d = ImageDraw.Draw(im)
    d.rectangle([1, 1, w - 2, h - 2], _shade(TEAL, 0.30))
    for y in range(1, h - 1, 2):
        d.line([(1, y), (w - 2, y)], _shade(TEAL, 0.16))
    _speckle(d, w, h, _shade(TEAL, 0.30), rng, 0.18)
    d.rectangle([0, 0, w - 1, h - 1], outline=_shade(WALL_HI, 1.1))
    d.point((w - 3, h - 3), TEAL_HI)      # power LED
    return im

def paint_lamp(w, h, rng):
    im = Image.new("RGBA", (w, h), AMBER)
    d = ImageDraw.Draw(im)
    _speckle(d, w, h, AMBER, rng, 0.4)
    return im

# --- atlas -----------------------------------------------------------------
# name -> (painter, width, height, kind)
MATERIALS = {
    "floor":   (paint_floor,   72, 60, "pattern"),
    "ceiling": (paint_ceiling, 72, 60, "pattern"),
    "wall":    (paint_wall,    72, 36, "pattern"),
    "desk":    (paint_desk,    32, 20, "pattern"),
    "door":    (paint_door,    22, 44, "fitted"),
    "vent":    (paint_vent,    16, 12, "fitted"),
    "screen":  (paint_screen,  18, 10, "fitted"),
    "metal":   (paint_metal,   16, 16, "pattern"),
    "lamp":    (paint_lamp,     8,  8, "fitted"),
}

def build_atlas(seed=7):
    """Shelf-pack every material into one atlas. Returns (image, rects)."""
    rng = random.Random(seed)
    im = Image.new("RGBA", (ATLAS, ATLAS), (0, 0, 0, 0))
    rects = {}
    x = y = shelf_h = 0
    for name, (fn, w, h, kind) in sorted(MATERIALS.items(), key=lambda kv: -kv[1][2]):
        if x + w > ATLAS:
            x, y, shelf_h = 0, y + shelf_h, 0
        if y + h > ATLAS:
            raise RuntimeError("atlas overflow")
        im.paste(fn(w, h, rng), (x, y))
        rects[name] = (x, y, w, h, kind)
        x += w
        shelf_h = max(shelf_h, h)
    return im, rects
