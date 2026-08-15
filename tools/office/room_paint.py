#!/usr/bin/env python3
"""
Shared texture painting for the Office Mode rooms (office + 8 camera feeds).

Colours come from the game's own data so the 3D rooms read as the same place
as the 2D ones: the structural greys from `scenes/office.tscn`, and each camera
room's accent from `OfficeConfig.CAMERA_VIEWS[cam]["accent"]`. The 2D feed
already tints itself with that accent (`view["accent"].darkened(0.55)`), so
carrying it into the 3D room keeps every feed's colour identity intact.

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
TEAL       = _c(0.20,  0.45,  0.45)           # UI accent
TEAL_HI    = _c(0.45,  0.60,  0.62)
RED        = _c(0.85,  0.30,  0.35)           # alarm / hazard
AMBER      = _c(0.90,  0.80,  0.40)           # lamp glow

FLOOR_BASE   = tuple(int(v * 0.60) for v in WALL)
CEILING_BASE = tuple(int(v * 0.45) for v in WALL)

# Two structural palettes. Office Mode's greys come from `scenes/office.tscn`
# and must stay cool, or the 3D rooms stop matching the 2D game they mirror.
# Last Route's maze is a different place: measured across both teaser posters
# its lit surfaces run warm -- mid tone (25,18,18), brightest (46,37,31), red
# minus blue between +5 and +15, where the office palette sits at -15 to -23.
#
# The swap preserves LUMINANCE and changes only hue, so a room keeps the
# brightness it was tuned for and simply stops being blue.
_OFFICE = {"VOID": VOID, "WALL": WALL, "WALL_HI": WALL_HI, "DESK": DESK,
           "FLOOR_BASE": FLOOR_BASE, "CEILING_BASE": CEILING_BASE}
_MAZE_HUE = (1.00, 0.76, 0.70)          # measured R:G:B of the teasers' lit surfaces

def _reluma(c, ratio=_MAZE_HUE):
    """Recolour to `ratio`'s hue at c's original luminance."""
    lum = 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]
    denom = 0.299 * ratio[0] + 0.587 * ratio[1] + 0.114 * ratio[2]
    k = lum / denom if denom else 0.0
    return tuple(max(0, min(255, int(k * v))) for v in ratio)

_MAZE = {k: _reluma(v) for k, v in _OFFICE.items()}

def use_palette(name):
    """Switch the structural palette. The painters read these at call time, so
    this must be set before building and reset after."""
    global VOID, WALL, WALL_HI, DESK, FLOOR_BASE, CEILING_BASE
    src = _MAZE if name == "maze" else _OFFICE
    VOID, WALL, WALL_HI = src["VOID"], src["WALL"], src["WALL_HI"]
    DESK, FLOOR_BASE, CEILING_BASE = src["DESK"], src["FLOOR_BASE"], src["CEILING_BASE"]

def hexc(s):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))

def _shade(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c)

def _mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def _speckle(d, w, h, base, rng, amount=0.30):
    """Per-pixel grain. Keeps flat fills from looking like plastic."""
    for _ in range(int(w * h * amount)):
        x, y = rng.randrange(w), rng.randrange(h)
        d.point((x, y), _shade(base, rng.uniform(0.78, 1.22)))

# --- painters --------------------------------------------------------------
# Every painter takes (w, h, rng, accent). `accent` is the room's identity
# colour; structural surfaces take only a light tint of it so the room reads
# as its own place without turning monochrome.

def paint_floor(w, h, rng, accent):
    base = _mix(FLOOR_BASE, accent, 0.10)
    im = Image.new("RGBA", (w, h), base)
    d = ImageDraw.Draw(im)
    _speckle(d, w, h, base, rng, 0.5)
    step = int(DENS)                      # one seam per metre
    for x in range(0, w, step):
        d.line([(x, 0), (x, h)], _shade(base, 0.55))
    for y in range(0, h, step):
        d.line([(0, y), (w, y)], _shade(base, 0.55))
    for _ in range(8):                    # scuffs
        cx, cy = rng.randrange(w), rng.randrange(h)
        r = rng.randint(2, 5)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], _shade(base, 1.35))
    return im

def paint_ceiling(w, h, rng, accent):
    base = _mix(CEILING_BASE, accent, 0.08)
    im = Image.new("RGBA", (w, h), base)
    d = ImageDraw.Draw(im)
    _speckle(d, w, h, base, rng, 0.35)
    step = int(DENS * 1.5)
    for x in range(0, w, step):
        d.line([(x, 0), (x, h)], _shade(base, 0.5))
    for y in range(0, h, step):
        d.line([(0, y), (w, y)], _shade(base, 0.5))
    for y in range(step // 2, h, step * 2):   # dead strip-lights
        d.rectangle([step // 2, y - 1, w - step // 2, y + 1], _shade(WALL_HI, 1.3))
    return im

def paint_wall(w, h, rng, accent):
    base = _mix(WALL, accent, 0.12)
    im = Image.new("RGBA", (w, h), base)
    d = ImageDraw.Draw(im)
    # grime gathers toward the floor -- v grows downward, so darken with y
    for y in range(h):
        f = 1.0 - 0.35 * (y / max(1, h - 1)) ** 2
        d.line([(0, y), (w, y)], _shade(base, f))
    _speckle(d, w, h, base, rng, 0.4)
    seam = int(DENS * 1.5)
    for x in range(0, w, seam):
        d.line([(x, 0), (x, h)], _shade(base, 0.6))
        d.line([(x + 1, 0), (x + 1, h)], _shade(base, 1.35))
    rail = int(h * 0.62)
    d.rectangle([0, rail, w, rail + 1], _mix(WALL_HI, accent, 0.35))
    d.line([(0, rail + 2), (w, rail + 2)], _shade(base, 0.5))
    return im

def paint_door(w, h, rng, accent):
    """Heavy steel roll-down shutter: slats, rivets, hazard chevrons."""
    base = _shade(WALL_HI, 1.15)
    im = Image.new("RGBA", (w, h), base)
    d = ImageDraw.Draw(im)
    _speckle(d, w, h, base, rng, 0.3)
    for y in range(0, h, 4):
        d.line([(0, y), (w, y)], _shade(base, 0.55))
        d.line([(0, y + 1), (w, y + 1)], _shade(base, 1.5))
    for y in range(2, h, 8):
        d.point((1, y), _shade(base, 1.9))
        d.point((w - 2, y), _shade(base, 1.9))
    band = h - 7
    d.rectangle([0, band, w, h], _shade(AMBER, 0.34))
    for x in range(-h, w, 6):
        d.line([(x, h), (x + 6, band)], RED, width=2)
    d.rectangle([0, band - 1, w, band - 1], _shade(base, 1.6))
    return im

def paint_metal(w, h, rng, accent):
    im = Image.new("RGBA", (w, h), WALL_HI)
    d = ImageDraw.Draw(im)
    _speckle(d, w, h, WALL_HI, rng, 0.5)
    d.rectangle([0, 0, w - 1, h - 1], outline=_shade(WALL_HI, 0.55))
    return im

def paint_vent(w, h, rng, accent):
    im = Image.new("RGBA", (w, h), _shade(VOID, 1.2))
    d = ImageDraw.Draw(im)
    for y in range(1, h - 1, 3):
        d.rectangle([1, y, w - 2, y], _shade(WALL_HI, 1.45))
        d.rectangle([1, y + 1, w - 2, y + 1], _shade(VOID, 0.6))
    d.rectangle([0, 0, w - 1, h - 1], outline=_shade(WALL_HI, 0.9))
    return im

def paint_desk(w, h, rng, accent):
    im = Image.new("RGBA", (w, h), DESK)
    d = ImageDraw.Draw(im)
    _speckle(d, w, h, DESK, rng, 0.55)
    for _ in range(14):
        y, x0 = rng.randrange(h), rng.randrange(w)
        d.line([(x0, y), (min(w, x0 + rng.randint(4, 14)), y)],
               _shade(DESK, rng.uniform(0.7, 1.4)))
    d.rectangle([0, 0, w - 1, h - 1], outline=_shade(DESK, 1.6))
    return im

def paint_screen(w, h, rng, accent):
    im = Image.new("RGBA", (w, h), _shade(VOID, 0.8))
    d = ImageDraw.Draw(im)
    d.rectangle([1, 1, w - 2, h - 2], _shade(TEAL, 0.30))
    for y in range(1, h - 1, 2):
        d.line([(1, y), (w - 2, y)], _shade(TEAL, 0.16))
    _speckle(d, w, h, _shade(TEAL, 0.30), rng, 0.18)
    d.rectangle([0, 0, w - 1, h - 1], outline=_shade(WALL_HI, 1.1))
    d.point((w - 3, h - 3), TEAL_HI)
    return im

def paint_lamp(w, h, rng, accent):
    im = Image.new("RGBA", (w, h), AMBER)
    _speckle(ImageDraw.Draw(im), w, h, AMBER, rng, 0.4)
    return im

# --- camera-room materials -------------------------------------------------

def paint_crate(w, h, rng, accent):
    """Wooden shipping crate: plank courses and a corner brace."""
    base = _mix(DESK, accent, 0.18)
    im = Image.new("RGBA", (w, h), base)
    d = ImageDraw.Draw(im)
    _speckle(d, w, h, base, rng, 0.5)
    for y in range(0, h, max(3, h // 4)):
        d.line([(0, y), (w, y)], _shade(base, 0.6))
        d.line([(0, y + 1), (w, y + 1)], _shade(base, 1.3))
    d.rectangle([0, 0, w - 1, h - 1], outline=_shade(base, 0.5))
    d.line([(0, 0), (w - 1, h - 1)], _shade(base, 1.25))   # diagonal brace
    return im

def paint_shelf(w, h, rng, accent):
    """Steel shelving seen face-on: uprights, shelf lips, dark gaps between."""
    im = Image.new("RGBA", (w, h), _shade(VOID, 1.1))
    d = ImageDraw.Draw(im)
    for y in range(0, h, max(4, h // 4)):
        d.rectangle([0, y, w - 1, y + 1], _shade(WALL_HI, 1.25))
    d.rectangle([0, 0, 1, h - 1], _shade(WALL_HI, 1.0))
    d.rectangle([w - 2, 0, w - 1, h - 1], _shade(WALL_HI, 1.0))
    _speckle(d, w, h, _shade(VOID, 1.1), rng, 0.25)
    return im

def paint_cabinet(w, h, rng, accent):
    """Filing cabinet front: drawer faces, each with a handle and label."""
    base = _mix(WALL_HI, accent, 0.25)
    im = Image.new("RGBA", (w, h), base)
    d = ImageDraw.Draw(im)
    _speckle(d, w, h, base, rng, 0.35)
    n = max(2, h // 6)
    for i in range(n):
        y0 = int(i * h / n)
        y1 = int((i + 1) * h / n) - 1
        d.rectangle([1, y0 + 1, w - 2, y1 - 1], _shade(base, 1.12))
        d.rectangle([1, y1, w - 2, y1], _shade(base, 0.55))
        cy = (y0 + y1) // 2
        d.rectangle([w // 2 - 2, cy, w // 2 + 1, cy], _shade(base, 1.7))   # handle
        d.point((2, cy), _mix(base, accent, 0.8))                          # label tab
    return im

def paint_duct(w, h, rng, accent):
    """Inside of a ventilation duct: ribbed galvanised sheet."""
    base = _mix(_shade(WALL_HI, 0.85), accent, 0.22)
    im = Image.new("RGBA", (w, h), base)
    d = ImageDraw.Draw(im)
    _speckle(d, w, h, base, rng, 0.45)
    for x in range(0, w, 4):              # stiffening ribs across the duct
        d.line([(x, 0), (x, h)], _shade(base, 0.62))
        d.line([(x + 1, 0), (x + 1, h)], _shade(base, 1.3))
    return im

def paint_panel(w, h, rng, accent):
    """Electrical breaker panel: two banks of breakers, a few thrown."""
    base = _shade(WALL_HI, 0.9)
    im = Image.new("RGBA", (w, h), base)
    d = ImageDraw.Draw(im)
    _speckle(d, w, h, base, rng, 0.3)
    d.rectangle([0, 0, w - 1, h - 1], outline=_shade(base, 1.5))
    for col in (0, 1):
        x = 2 + col * (w // 2)
        for y in range(3, h - 3, 3):
            on = rng.random() > 0.25
            d.rectangle([x, y, x + w // 2 - 4, y + 1],
                        _mix(WALL_HI, AMBER if on else RED, 0.55))
    return im

def paint_conduit(w, h, rng, accent):
    """Cable/conduit run: a lit core so pipes read against a dark wall."""
    base = _shade(WALL_HI, 0.8)
    im = Image.new("RGBA", (w, h), base)
    d = ImageDraw.Draw(im)
    for y in range(h):
        f = 1.45 - 0.9 * abs(y - (h - 1) / 2) / max(1, (h - 1) / 2)
        d.line([(0, y), (w, y)], _shade(base, f))
    _speckle(d, w, h, base, rng, 0.25)
    return im

def paint_hazard(w, h, rng, accent):
    """Floor hazard marking: diagonal amber/black stripes."""
    im = Image.new("RGBA", (w, h), _shade(VOID, 1.4))
    d = ImageDraw.Draw(im)
    for x in range(-h, w, 8):
        d.line([(x, h), (x + h, 0)], _shade(AMBER, 0.72), width=4)
    _speckle(d, w, h, _shade(AMBER, 0.72), rng, 0.12)
    return im

def paint_arcade(w, h, rng, accent):
    """An arcade cabinet's marquee and screen: bright attract-mode blocks over
    a dark CRT, so the machine reads as ON in an otherwise unlit room."""
    im = Image.new("RGBA", (w, h), _shade(VOID, 0.9))
    d = ImageDraw.Draw(im)
    d.rectangle([1, 1, w - 2, max(2, h // 5)], _mix(accent, AMBER, 0.5))   # marquee
    sy = h // 4
    d.rectangle([2, sy, w - 3, h - 3], _shade(TEAL, 0.22))                 # screen
    for _ in range(int(w * h * 0.10)):                                     # sprites
        x, y = rng.randrange(2, max(3, w - 3)), rng.randrange(sy, max(sy + 1, h - 3))
        d.point((x, y), rng.choice((TEAL_HI, AMBER, RED, _mix(accent, TEAL_HI, 0.6))))
    for y in range(sy, h - 3, 2):
        d.line([(2, y), (w - 3, y)], _shade(TEAL, 0.12))                   # scanlines
    d.rectangle([0, 0, w - 1, h - 1], outline=_shade(WALL_HI, 1.2))
    return im

def paint_party(w, h, rng, accent):
    """Party/dining trim: a checker in the room's accent, for tablecloths,
    floor tiles and wall banners."""
    im = Image.new("RGBA", (w, h), _shade(WALL, 1.1))
    d = ImageDraw.Draw(im)
    step = max(2, w // 8)
    for j in range(0, h, step):
        for i in range(0, w, step):
            if ((i // step) + (j // step)) % 2:
                d.rectangle([i, j, i + step - 1, j + step - 1], accent)
            else:
                d.rectangle([i, j, i + step - 1, j + step - 1], _mix(accent, RED, 0.45))
    _speckle(d, w, h, accent, rng, 0.15)
    return im

def paint_emissive(w, h, rng, accent):
    """A lit indicator band in the prop's own accent.

    RouteInteractable3D shows state by toggling an OmniLight3D it creates
    itself -- "rather than recoloring the model" -- so this does not need a
    real emissive material. It only needs to read as the lit part when that
    light is on, which a bright accent with a brighter core does."""
    core = _mix(accent, (255, 255, 255), 0.45)
    im = Image.new("RGBA", (w, h), accent)
    d = ImageDraw.Draw(im)
    d.rectangle([0, h // 3, w - 1, h - 1 - h // 3], core)
    _speckle(d, w, h, accent, rng, 0.2)
    return im

def paint_frost(w, h, rng, accent):
    """Ice crust for the heater station's FROZEN state -- Wynelle's doing."""
    base = _mix((198, 226, 240), accent, 0.15)
    im = Image.new("RGBA", (w, h), base)
    d = ImageDraw.Draw(im)
    for _ in range(int(w * h * 0.12)):        # crystal flecks
        x, y = rng.randrange(w), rng.randrange(h)
        d.point((x, y), _shade(base, rng.uniform(1.05, 1.35)))
    for _ in range(6):                        # rime running down
        x = rng.randrange(w)
        d.line([(x, 0), (x + rng.randint(-1, 1), h)], _shade(base, 0.78))
    _speckle(d, w, h, base, rng, 0.25)
    return im

def paint_recess(w, h, rng, accent):
    """The dark inside of a recess -- behind vent slats, under a screen bezel.

    This is what makes an extruded detail read as a hole rather than a decal:
    the surfaces you glimpse through the gap have to be genuinely darker than
    anything lit, not just a dark colour painted on a flat face."""
    base = _shade(VOID, 0.75)
    im = Image.new("RGBA", (w, h), base)
    _speckle(ImageDraw.Draw(im), w, h, base, rng, 0.2)
    return im

def paint_sign(w, h, rng, accent):
    """Room identity plate in the camera's own accent colour."""
    im = Image.new("RGBA", (w, h), _shade(VOID, 1.3))
    d = ImageDraw.Draw(im)
    d.rectangle([1, 1, w - 2, h - 2], accent)
    d.rectangle([1, 1, w - 2, h - 2], outline=_shade(accent, 1.5))
    for i in range(2, w - 2, 3):          # illegible stencilled lettering
        d.rectangle([i, h // 2 - 1, i + 1, h // 2 + 1], _shade(accent, 0.35))
    return im

# --- atlas -----------------------------------------------------------------
# name -> (painter, width, height, kind)
BASE_MATERIALS = {
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

EXTRA_MATERIALS = {
    "crate":   (paint_crate,   16, 16, "pattern"),
    "shelf":   (paint_shelf,   24, 32, "fitted"),
    "cabinet": (paint_cabinet, 16, 28, "fitted"),
    "duct":    (paint_duct,    48, 24, "pattern"),
    "panel":   (paint_panel,   16, 24, "fitted"),
    "conduit": (paint_conduit, 16,  8, "pattern"),
    "hazard":  (paint_hazard,  32, 16, "pattern"),
    "sign":    (paint_sign,    24,  8, "fitted"),
    "recess":  (paint_recess,  16, 16, "pattern"),
    "emissive": (paint_emissive, 16, 12, "pattern"),
    "frost":   (paint_frost,   24, 24, "pattern"),
    "arcade":  (paint_arcade,  14, 22, "fitted"),
    "party":   (paint_party,   32, 32, "pattern"),
}

ALL_MATERIALS = {**BASE_MATERIALS, **EXTRA_MATERIALS}

def build_multi_atlas(specs, materials=None, size=512, seed=7):
    """Pack SEVERAL accent variants of the material set into one atlas.

    The merged map needs every room in a single texture, but each room keeps
    its own accent -- that colour identity is what the 2D feed already uses
    (`view["accent"].darkened(0.55)`), so flattening them to one tint would
    make every feed look like the same corridor.

    specs: {room_key: accent_rgb}.  Returns (image, {room_key: rects})."""
    mats = materials or ALL_MATERIALS
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out = {}
    x = y = shelf_h = 0
    for i, (key, accent) in enumerate(specs.items()):
        rng = random.Random(seed + i)
        rects = {}
        for name, (fn, w, h, kind) in sorted(mats.items(), key=lambda kv: -kv[1][2]):
            if x + w > size:
                x, y, shelf_h = 0, y + shelf_h, 0
            if y + h > size:
                raise RuntimeError(f"atlas overflow packing '{key}/{name}'")
            im.paste(fn(w, h, rng, accent), (x, y))
            rects[name] = (x, y, w, h, kind)
            x += w
            shelf_h = max(shelf_h, h)
        out[key] = rects
    return im, out


def build_atlas(materials=None, accent=TEAL, seed=7):
    """Shelf-pack the requested materials into one atlas.

    Returns (image, rects) where rects maps name -> (x, y, w, h, kind)."""
    mats = materials or BASE_MATERIALS
    rng = random.Random(seed)
    im = Image.new("RGBA", (ATLAS, ATLAS), (0, 0, 0, 0))
    rects = {}
    x = y = shelf_h = 0
    # Tallest first, so the shelf packer wastes as little vertical space as it can.
    for name, (fn, w, h, kind) in sorted(mats.items(), key=lambda kv: -kv[1][2]):
        if x + w > ATLAS:
            x, y, shelf_h = 0, y + shelf_h, 0
        if y + h > ATLAS:
            raise RuntimeError(f"atlas overflow packing '{name}'")
        im.paste(fn(w, h, rng, accent), (x, y))
        rects[name] = (x, y, w, h, kind)
        x += w
        shelf_h = max(shelf_h, h)
    return im, rects
