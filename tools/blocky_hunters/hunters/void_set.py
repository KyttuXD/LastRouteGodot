"""The 12 Void hunters (void_black .. void_yellow) on the shared blocky rig.

Base: the supplied Void skin (skins/void_<colour>_source.png, the audited Alex-layout skins from
LastRoute-Archives/audits/voids-2026-09-09) on the standard vanilla cubes at VOID_HEIGHT (the roster calls Void
presentation "deliberately larger"). Lore keeps the base plain: humanoid cat, giant eyes, no snout/nose/mouth,
no flowers, no accessories in the sources. Each colour therefore adds ONE silhouette cue (cubes only) tied to
its gimmick in void_hunter_gimmick_chart.gd. The cues are design proposals, not lore (PLACEHOLDER in the doc).
All cue bones are named Cue-* so the height check skips them like horns/ears/wings."""
import types
from bb_core import Cube
from bb_skin import U, m, vanilla_sk, eye_locators, source_hunter

VOID_HEIGHT = 2.0
SLOTS = {"body": (46, 66), "accent": (48, 66), "dark": (50, 66), "light": (52, 66), "white": (54, 66)}

# colour -> (accent = skin's inner face colour, dark, light), body is sampled from the skin
PALETTE = {
    "black":  ("#1c1c1c", "#000000", "#808080"),
    "blue":   ("#3244ab", "#0a1050", "#a9d8ff"),
    "brown":  ("#8a5a2b", "#241208", "#b98a50"),
    "cyan":   ("#16d6cd", "#0b5f63", "#d5fbff"),
    "gray":   ("#808080", "#312f2f", "#c8c8c8"),
    "green":  ("#15bf25", "#043d0a", "#a6f2ab"),
    "orange": ("#ff8700", "#6b2c00", "#ffd9a0"),
    "pink":   ("#cd4a82", "#6e1c42", "#ffe0ee"),
    "purple": ("#933cbb", "#2a0040", "#d9a8f0"),
    "red":    ("#ef1515", "#3a0000", "#ff9a9a"),
    "white":  ("#9a9a9a", "#555555", "#ffffff"),
    "yellow": ("#ffb963", "#7a4a00", "#fff3a0"),
}


def _rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def _box(name, bone, x0, y0, z0, x1, y1, z1, key, rot=(0, 0, 0), pivot=None):
    """Cube in skin px; key = palette slot (all six faces one flat colour)."""
    uv = {f: SLOTS[key] + (2, 2) for f in "ENWSUD"}
    pv = tuple(m(v) for v in pivot) if pivot else None
    return Cube(name, bone, (m(x0), m(y0), m(z0)), (m(x1), m(y1), m(z1)), uv=uv, rot=rot, pivot=pv)


def _ctr(name, bone, cx, y0, cz, w, h, d, key, **kw):
    return _box(name, bone, cx - w / 2, y0, cz - d / 2, cx + w / 2, y0 + h, cz + d / 2, key, **kw)


def _mirror(fn):
    out = []
    for side, s in (("L", -1), ("R", 1)):
        out += fn(side, s)
    return out


# Each cue returns (cubes, extras). extras: (bone, parent, pivot px, sway) as in bb_rig.skeleton.
def _x(bone, parent, pv, sway=None):
    return (bone, parent, tuple(m(v) for v in pv), sway)


def black():    # LIGHT EATER: dark pockets drifting round the shoulders
    c = [_ctr("mote-1", "Cue-Motes", -9.4, 23.0, 0.5, 3.4, 3.4, 3.4, "accent"),
         _ctr("mote-1-core", "Cue-Motes", -9.4, 24.0, -1.4, 1.4, 1.4, 0.6, "dark"),
         _ctr("mote-2", "Cue-Motes", 9.2, 16.0, -1.0, 2.8, 2.8, 2.8, "accent"),
         _ctr("mote-3", "Cue-Motes", -4.5, 34.0, 1.5, 2.4, 2.4, 2.4, "accent"),
         _ctr("mote-rim-1", "Cue-Motes", -9.4, 26.8, 0.5, 1.4, 1.0, 1.4, "light"),
         _ctr("mote-rim-2", "Cue-Motes", 9.2, 18.8, -1.0, 1.2, 1.0, 1.2, "light"),
         _ctr("mote-4", "Cue-Motes", 6.5, 30.0, 4.5, 2.0, 2.0, 2.0, "accent")]
    return c, [_x("Cue-Motes", "Chest", (0, 22, 0), (4, 6, 1, 0.0, 5))]


def blue():     # COLD TRAIL: icicle crown + a trailing ice tail
    c = []
    for i, (x, h) in enumerate(((0, 7.0), (-2.6, 4.6), (2.6, 4.6))):
        c += [_ctr(f"ice-{i}a", "Cue-Crown", x, 32, 0, 2.2, h * .6, 2.2, "light"),
              _ctr(f"ice-{i}b", "Cue-Crown", x, 32 + h * .6, 0, 1.2, h * .4, 1.2, "white")]
    c += [_ctr("trail-1", "Cue-Trail-1", 0, 10.6, 3.6, 2.0, 2.4, 3.0, "accent"),
          _ctr("trail-2", "Cue-Trail-2", 0, 9.0, 6.4, 1.6, 2.0, 3.6, "light"),
          _ctr("trail-3", "Cue-Trail-2", 0, 8.2, 10.0, 1.2, 1.6, 2.4, "white")]
    return c, [_x("Cue-Crown", "Head", (0, 32, 0)),
               _x("Cue-Trail-1", "Pelvis", (0, 11.4, 2.3), (7, 4, 1, 0.0)),
               _x("Cue-Trail-2", "Cue-Trail-1", (0, 10.4, 5.0), (10, 7, 1, 0.9))]


def brown():    # BARRIER BREAKER: a board strapped across the back, plank shoulder guards, nail heads
    c = [_box("board-a", "Chest", -4.6, 11.0, 2.2, 4.6, 28.0, 3.6, "accent"),
         _box("board-b", "Chest", -1.2, 9.0, 3.4, 1.2, 25.0, 4.4, "light", rot=(0, 0, 38), pivot=(0, 17, 3.9)),
         _ctr("nail-1", "Chest", -3.2, 20.5, 4.5, 0.9, 0.9, 0.9, "dark"), _ctr("nail-2", "Chest", 3.2, 20.5, 4.5, 0.9, 0.9, 0.9, "dark"),
         _ctr("nail-3", "Chest", -3.2, 13.5, 4.5, 0.9, 0.9, 0.9, "dark"), _ctr("nail-4", "Chest", 3.2, 13.5, 4.5, 0.9, 0.9, 0.9, "dark")]
    for side, s in (("L", -1), ("R", 1)):
        c += [_ctr(f"pad-{side}", f"{side}-Arm", s * 5.6, 22.0, 0, 5.4, 2.0, 5.4, "accent"),
              _ctr(f"pad-up-{side}", f"{side}-Arm", s * 5.6, 24.0, 0, 3.2, 2.4, 3.8, "light"),
              _ctr(f"pad-nail-{side}", f"{side}-Arm", s * 5.6, 26.4, -1.2, 0.9, 0.7, 0.9, "dark")]
    return c, []


def cyan():     # POWER INTERFERENCE: twin antennae + a battery pack on the back
    c = []
    ex = []
    for side, s in (("L", -1), ("R", 1)):
        b = f"Cue-Antenna-{side}"
        c += [_ctr(f"ant-{side}-1", b, s * 2.2, 32, 0, 0.9, 2.6, 0.9, "dark", rot=(0, 0, -s * 14), pivot=(s * 2.2, 32, 0)),
              _ctr(f"ant-{side}-2", b, s * 3.1, 34.4, 0, 0.9, 2.4, 0.9, "dark", rot=(0, 0, -s * 24), pivot=(s * 2.2, 32, 0)),
              _ctr(f"ant-{side}-tip", b, s * 4.3, 36.6, 0, 1.8, 1.8, 1.8, "accent", rot=(0, 0, -s * 24), pivot=(s * 2.2, 32, 0))]
        ex.append(_x(b, "Head", (s * 2.2, 32, 0), (6, 4, 1, 0.5 * s)))
    c += [_box("pack", "Chest", -2.8, 13.5, 2.1, 2.8, 21.5, 3.9, "dark"),
          _box("pack-band", "Chest", -2.9, 16.5, 2.0, 2.9, 18.0, 4.0, "accent"),
          _box("pack-cell", "Chest", -1.0, 19.0, 3.9, 1.0, 20.6, 4.3, "light")]
    return c, ex


def gray():     # UNOBSERVED PURSUIT: a second, closed face on the back of the head (it watches behind)
    c = [_box("nape-frame", "Head", -6.0, 23.0, 4.1, 6.0, 33.5, 4.7, "dark"),
         _box("nape-plate", "Head", -3.2, 25.0, 4.7, 3.2, 31.0, 5.2, "accent"),
         _box("nape-mark-L", "Head", -2.4, 28.0, 5.2, -1.4, 30.6, 5.5, "white"),
         _box("nape-mark-R", "Head", 1.4, 28.0, 5.2, 2.4, 30.6, 5.5, "white"),
         _box("nape-eye-L", "Head", -2.6, 26.0, 5.2, -1.2, 27.4, 5.5, "dark"),
         _box("nape-eye-R", "Head", 1.2, 26.0, 5.2, 2.6, 27.4, 5.5, "dark"),
         _box("collar", "Chest", -3.6, 23.4, -2.6, 3.6, 25.4, 2.6, "light")]
    return c, []


def green():    # TOXIC DENIAL: spore sacs on the shoulders and spores bobbing round her
    c = [_ctr(f"spore-{i}", "Cue-Spores", x, y, z, s, s, s, k)
         for i, (x, y, z, s, k) in enumerate(((-8.4, 27.5, 1.0, 2.6, "light"), (8.6, 19.0, 0.5, 3.0, "accent"),
                                              (0.0, 35.0, 2.0, 2.2, "light"), (-7.0, 14.0, 3.0, 2.0, "accent"),
                                              (6.0, 28.5, 4.0, 1.2, "light")))]
    ex = [_x("Cue-Spores", "Chest", (0, 22, 0), (5, 7, 1, 0.0, 6))]
    for side, s in (("L", -1), ("R", 1)):
        x = s * 5.5
        c += [_ctr(f"sac-{side}", f"{side}-Arm", x, 22.2, 0, 4.4, 2.2, 4.2, "dark"),
              _ctr(f"sac-top-{side}", f"{side}-Arm", x, 24.4, 0, 2.6, 1.4, 2.6, "accent"),
              _ctr(f"sac-spot-{side}", f"{side}-Arm", x + s * .8, 25.8, -.5, 1.0, 0.8, 1.0, "light")]
    return c, ex


def orange():   # BURST CHARGE: swept-back crest blades and rear thruster vents
    c, ex = [], []
    for side, s in (("L", -1), ("R", 1)):
        b = f"Cue-Crest-{side}"
        for i, (y, w, d, dz) in enumerate(((32.0, 2.4, 2.6, 0.6), (34.0, 2.0, 2.2, 2.6), (36.0, 1.5, 1.8, 4.8), (37.6, 1.0, 1.4, 7.0))):
            c.append(_ctr(f"crest-{side}-{i}", b, s * 2.4, y, dz, w, 1.8, d, "accent" if i < 3 else "light"))
        ex.append(_x(b, "Head", (s * 2.4, 32, 0), (3, 2, 1, 0.4 * s)))
        c += [_ctr(f"vent-{side}", "Chest", s * 2.0, 14.5, 3.2, 2.4, 6.0, 2.2, "dark"),
              _ctr(f"vent-core-{side}", "Chest", s * 2.0, 15.5, 4.3, 1.4, 2.0, 0.6, "light")]
    return c, ex


def pink():     # FALSE COMFORT: an anglerfish-style lure with a soft "safe light" bulb
    c = [_ctr("stalk-1", "Cue-Lure", 0, 32, 0.0, 1.2, 5.6, 1.2, "accent"),
         _ctr("stalk-2", "Cue-Lure", 0, 37.0, -2.2, 1.2, 1.2, 5.2, "accent"),
         _ctr("bulb", "Cue-Lure", 0, 35.2, -6.4, 3.6, 3.6, 3.6, "white"),
         _ctr("bulb-halo", "Cue-Lure", 0, 34.6, -6.4, 4.8, 0.8, 4.8, "light")]
    return c, [_x("Cue-Lure", "Head", (0, 32, 0), (5, 3, 1, 0.0))]


def purple():   # DARK PHASE: fading afterimage slabs trailing behind
    c = [_box("echo-1", "Cue-Phase", -4.8, 12.0, 2.6, 4.8, 24.0, 3.4, "accent"),
         _box("echo-2", "Cue-Phase", -1.2, 13.5, 5.0, 6.8, 22.5, 5.8, "dark"),
         _box("echo-3", "Cue-Phase", -6.6, 14.5, 7.2, 0.4, 21.5, 7.8, "accent"),
         _box("echo-head", "Cue-Phase", -2.6, 25.0, 4.6, 2.6, 31.0, 5.2, "dark")]
    return c, [_x("Cue-Phase", "Chest", (0, 18, 2), (2, 7, 1, 0.0, 9))]


def red():      # BERSERK RESPONSE: dorsal spines, shoulder spikes, knuckle-forearm blades
    c = []
    for i, y in enumerate((14.0, 17.4, 20.8)):
        c += [_ctr(f"spine-{i}a", "Chest", 0, y, 2.9, 3.2 - .4 * i, 3.0, 2.4, "dark"),
              _ctr(f"spine-{i}b", "Chest", 0, y + 1.2, 4.6, 1.8, 1.8, 1.8, "accent")]
    for side, s in (("L", -1), ("R", 1)):
        c += [_ctr(f"spike-{side}", f"{side}-Arm", s * 7.0, 22.4, 0, 2.4, 3.6, 2.4, "dark", rot=(0, 0, -s * 28), pivot=(s * 6.2, 22.4, 0)),
              _ctr(f"spike-tip-{side}", f"{side}-Arm", s * 8.4, 25.4, 0, 1.4, 2.4, 1.4, "accent", rot=(0, 0, -s * 28), pivot=(s * 6.2, 22.4, 0)),
              _ctr(f"blade-{side}", f"{side}-Forearm", s * 7.7, 13.6, 0.2, 1.2, 4.4, 2.2, "accent")]
    return c, []


def white():    # SOUND HUNTER: oversized listening ears
    c, ex = [], []
    for side, s in (("L", -1), ("R", 1)):
        b = f"Cue-Ear-{side}"
        roll = -s * 10
        pv = (s * 2.9, 32, 0)
        c += [_ctr(f"ear-{side}-a", b, s * 2.9, 32.0, 0, 3.4, 3.4, 1.6, "body", rot=(0, 0, roll), pivot=pv),
              _ctr(f"ear-{side}-b", b, s * 3.3, 35.2, 0, 2.6, 3.0, 1.4, "body", rot=(0, 0, roll), pivot=pv),
              _ctr(f"ear-{side}-c", b, s * 3.6, 38.0, 0, 1.4, 1.8, 1.2, "body", rot=(0, 0, roll), pivot=pv),
              _ctr(f"ear-{side}-in", b, s * 2.9, 32.4, -0.9, 2.0, 5.2, 0.3, "accent", rot=(0, 0, roll), pivot=pv)]
        ex.append(_x(b, "Head", pv, (6, 8, 2, 0.8 * s)))
    return c, ex


def yellow():   # POWER CUT: a stepped lightning bolt crest + a fuse box with prongs
    c = [_box("bolt-1", "Cue-Bolt", -2.2, 32.0, -1.1, 0.6, 35.0, 1.1, "dark"),
         _box("bolt-2", "Cue-Bolt", -0.8, 35.0, -1.1, 2.2, 37.2, 1.1, "accent"),
         _box("bolt-3", "Cue-Bolt", -2.0, 37.2, -1.1, 0.8, 39.8, 1.1, "dark"),
         _box("bolt-tip", "Cue-Bolt", -0.8, 39.8, -1.1, 0.8, 41.6, 1.1, "light"),
         _box("fuse-box", "Chest", -2.6, 14.0, 2.1, 2.6, 21.0, 3.8, "dark"),
         _box("fuse-plate", "Chest", -2.0, 15.5, 3.8, 2.0, 19.5, 4.1, "accent"),
         _box("prong-L", "Chest", -1.4, 21.0, 2.6, -0.6, 23.0, 3.4, "light"),
         _box("prong-R", "Chest", 0.6, 21.0, 2.6, 1.4, 23.0, 3.4, "light")]
    return c, [_x("Cue-Bolt", "Head", (0, 32, 0))]


CUES = {n: f for n, f in (("black", black), ("blue", blue), ("brown", brown), ("cyan", cyan), ("gray", gray),
                          ("green", green), ("orange", orange), ("pink", pink), ("purple", purple),
                          ("red", red), ("white", white), ("yellow", yellow))}
IDS = [f"void_{c}" for c in CUES]


GLOW_REGIONS = [(8, 8, 8, 8), (0, 64, 24, 16)]      # the face on the head box, and the 3x2 expression cells


def _glow_colour(eye):
    """Eyes glow in their own colour; dark accents (black, gray, brown) are lifted to a readable hue-true glow."""
    top = max(eye)
    if top >= 140:
        return tuple(eye)
    if top > 40:
        return tuple(min(255, int(v * 200 / top)) for v in eye)
    return (150, 150, 165)                              # near-black accent: cool grey glow


def _eye_glow(atlas, eye):
    """Emissive mask: only the giant eyes' inner pixels (the skin's inner_face_accent), in every expression cell."""
    from PIL import Image
    glow = _glow_colour(eye)
    out = Image.new("RGBA", atlas.size, (0, 0, 0, 255))
    for rx, ry, rw, rh in GLOW_REGIONS:
        for y in range(ry, ry + rh):
            for x in range(rx, rx + rw):
                if atlas.getpixel((x, y))[:4] == (*eye, 255):
                    out.putpixel((x, y), (*glow, 255))
    return out


def void_expressions(face, eye, body):
    """13 cells (same order as bb_skin.expressions_from_face) from the composited 8x8 Void face. The face has two
    2x2 eyes (cols 1-2 / 5-6, rows 4-5) in a grey frame (rows 3-6) and two white marks above (cols 1 / 6, rows 1-2).
    No mouth, nose or snout is ever drawn: expressions are eyes and marks only."""
    frame = face.getpixel((0, 3))
    dim = tuple(int(v * .3) for v in body[:3]) + (255,)
    wipe = {(x, y): dim for y in (4, 5) for x in (1, 2, 5, 6)}

    def make(pix, marks=None):
        im = face.copy()
        for (x, y), c in {**wipe, **pix}.items():
            im.putpixel((x, y), c)
        for (x, y), c in (marks or {}).items():
            im.putpixel((x, y), c)
        return im
    white, bodyc = face.getpixel((1, 1)), face.getpixel((2, 1))
    E = (*eye, 255)
    both = lambda pts: {p: c for p, c in pts}
    open_all = {(x, y): E for y in (4, 5) for x in (1, 2, 5, 6)}
    cells = [face.copy()]                                                              # 0 neutral
    cells.append(make({(x, 5): frame for x in (1, 2, 5, 6)} | {(x, 4): dim for x in (1, 2, 5, 6)}))   # 1 blink: lids shut
    cells.append(make({(1, 4): E, (2, 5): E, (5, 5): E, (6, 4): E}))                   # 2 stun: mismatched sparks
    slant = {(1, 1): bodyc, (2, 1): white, (1, 2): white, (6, 1): bodyc, (5, 1): white, (6, 2): white}
    cells.append(make({(x, 5): E for x in (1, 2, 5, 6)}, slant))                       # 3 chase: narrowed, brows slanted
    wide = {(x, y): E for y in (3, 4, 5, 6) for x in (1, 2, 5, 6)}
    cells.append(make(wide))                                                           # 4 scream: eyes wide open
    cells.append(make({**{(x, 4): E for x in (1, 2, 5, 6)}, **{(x, 5): frame for x in (1, 2, 5, 6)}}))   # 5 happy: squint
    ring = [(0, 0), (1, 0), (1, 1), (0, 1)]
    for t in range(4):                                                                 # 6-9 derp: iris circles the eye
        pix = {}
        for ex, off in ((1, 0), (5, 2)):
            for j, (dx, dy) in enumerate(ring):
                pix[(ex + dx, 4 + dy)] = E if j == (t + off) % 4 else dim
        cells.append(make(pix))
    cells.append(make({}))                                                             # 10 blank: eyes out
    shut = {(x, y): (dim if y == 4 else frame) for y in (4, 5) for x in (1, 2)}
    shut_r = {(x, y): (dim if y == 4 else frame) for y in (4, 5) for x in (5, 6)}
    cells.append(make({**shut, **{(x, y): E for y in (4, 5) for x in (5, 6)}}))        # 11 wink_right
    cells.append(make({**shut_r, **{(x, y): E for y in (4, 5) for x in (1, 2)}}))      # 12 wink_left
    return cells


def module(name):
    colour = name.split("_", 1)[1]
    cues, cue_extras = CUES[colour]()
    ns = types.SimpleNamespace(NAME=name, HEIGHT=VOID_HEIGHT, DESIGN_TOP=32 * U, SK=vanilla_sk(),
                               EXTRAS=cue_extras, EYES=eye_locators(), MODEL_KW={})
    state = {}

    def build():
        from PIL import Image
        from bb_skin import load_source, vanilla_cubes, vanilla_kw
        canvas = load_source(name)
        body = canvas.getpixel((22, 25))[:3]
        acc, dark, light = (_rgb(h) for h in PALETTE[colour][0:3])
        for key, rgb in (("body", body), ("accent", acc), ("dark", dark), ("light", light), ("white", (255, 255, 255))):
            x, y = SLOTS[key]
            for j in range(2):
                for i in range(2):
                    canvas.putpixel((x + i, y + j), (*rgb, 255))
        # the face lives on two layers in the source (frames on the head box, eyes/marks on the overlay): flatten it
        # onto the head box and drop the overlay face, so the expression quad and the box agree
        face = canvas.crop((8, 8, 16, 16))
        face.alpha_composite(canvas.crop((40, 8, 48, 16)))
        canvas.paste(face, (8, 8))
        for y in range(8, 16):
            for x in range(40, 48):
                canvas.putpixel((x, y), (0, 0, 0, 0))
        state["eye"] = face.getpixel((1, 4))[:3]
        cells = void_expressions(face, state["eye"], (*body, 255))
        ns.MODEL_KW.update(vanilla_kw(canvas))
        return vanilla_cubes(overlays=True) + list(cues), (lambda k: cells[k] if k < len(cells) else None)
    ns.build = build
    ns.emissive = lambda atlas: _eye_glow(atlas, state["eye"])
    return ns
