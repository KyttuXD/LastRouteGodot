#!/usr/bin/env python3
"""
Builds the Office Mode room as a Hytale-style Blockbench model.

Shares room_kit/room_paint with the camera-feed rooms so both use one texture
and geometry pipeline. Unit convention matches the hunter models: 64 units = 1
metre, floor at Y=0, per art/props-3d/README.md.

Group names are the integration contract -- the Godot side finds parts by name
to reflect simulation state, unlike the 2D office whose doorway/vent ColorRects
are static decoration.

Doors are modelled full-height in the CLOSED position with each group's origin
at the TOP of its opening, so Godot closes them by scaling Y from 0 to 1: a
roll-down shutter. Sliding a solid door up instead would need 2.2 m of hiding
space above the opening, and the header is only 0.8 m tall.

    python3 build_office_room.py [out.bbmodel]
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from room_kit import Room, recessed_panel, louvered_grille, M
from room_paint import ALL_MATERIALS, TEAL

W, D, H = 6.0, 5.0, 3.0      # room metres: width, depth, height
T = 0.15                     # wall thickness
DOOR_W, DOOR_H = 1.1, 2.2    # doorway opening
VENT_W, VENT_H = 0.8, 0.6

# -- camera console ----------------------------------------------------------
# Two big buttons, not eleven small ones. Laying the caps out as a floor plan
# read beautifully and aimed badly: seated, the cursor swings the head as well
# as the aiming ray, so the whole console is only about 64 x 55 pixels of
# cursor travel at this project's 480 x 270 base resolution, and eleven caps
# inside that are 3.6 cm dots you have to hunt for.
#
# The map did not have to go, though -- it just stopped being the thing you
# aim at. The plan is now a READOUT on the console's screen, showing where the
# live camera is and where the two buttons will take you, while PREV and NEXT
# are 36 cm slabs that are hard to miss.
PANEL_X0, PANEL_X1 = -0.10, 0.74   # across the desk, between monitor and lamp
PANEL_V = 0.56                     # extent up the board's own tilted face
PANEL_TILT = 34.0                  # degrees back from vertical
PANEL_FOOT_Y = 0.81                # front-bottom edge, just clear of the desk
PANEL_FOOT_Z = D / 2 - 0.98
BEZEL = 0.022                      # frame around the well
# Height of the button strip along the bottom of the board, measured from the
# inside of the bezel. Everything above it is screen.
STRIP = 0.15
BUTTON_W, BUTTON_H = 0.36, 0.11
BUTTON_RISE = 0.018                # how far a button stands off the board
# The arrow standing on each button. A stepped triangle rather than a painted
# one: at 12 texels per metre a 9 cm glyph is barely a texel across, so the
# only way to draw a readable shape at this scale is to build it. Raised and
# dark against a button that lights up, which is what makes it read from the
# seat -- roughly 8 of the 27 pixels the button occupies there.
GLYPH_W, GLYPH_H = 0.09, 0.07
GLYPH_RISE = 0.006
GLYPH_STEPS = 5


def _panel_origin():
    """Centre of the console's face, and the tilt in radians.

    The board is authored UPRIGHT about this point and tilted by its group
    rotation, because that is the only rotation the exporter carries into glTF.
    Everything below therefore works in two frames: the upright authoring frame
    and the tilted world one."""
    th = math.radians(PANEL_TILT)
    return (PANEL_FOOT_Y + (PANEL_V / 2) * math.cos(th),
            PANEL_FOOT_Z - (PANEL_V / 2) * math.sin(th), th)


def _tilt(oy, oz, dy, dz, th):
    """Authoring-frame offset -> world, matching a group rotation of -tilt
    about X. A button's own group rotates it about ITS centre, so its centre
    has to arrive here already rotated about the console's."""
    return (oy + dy * math.cos(th) + dz * math.sin(th),
            oz - dy * math.sin(th) + dz * math.cos(th))


# -- control strip -----------------------------------------------------------
# The nine shift controls, as physical buttons on the desk rather than a row of
# UI along the bottom of the screen. Office Mode is played from a chair looking
# at a desk; reaching for a doorm switch should be reaching for a switch.
#
# A separate board from the camera console, lower and flatter, sitting between
# the console and the player -- a keyboard's angle rather than a monitor's.
STRIP_X0, STRIP_X1 = -0.68, 0.68
STRIP_V = 0.34                     # up the board's own tilted face
STRIP_TILT = 58.0                  # nearly flat: it is under your hands
STRIP_FOOT_Y = 0.81
STRIP_FOOT_Z = D / 2 - 0.46        # just in front of the console's foot
KEY_W, KEY_H = 0.22, 0.115
KEY_RISE = 0.014
# Which control each key works, in two rows. Order follows the bar it replaces
# so the muscle memory carries over.
KEY_ROWS = [
    ["LeftDoor", "RightDoor", "DeskLight", "Vent", "Monitor"],
    ["Radio", "Breaker", "Reboot", "Flash"],
]


# A 7x5 bitmap per key, emitted as boxes. Same reasoning as the PREV/NEXT
# arrows: at 12 texels per metre a painted legend on a 22 cm key would be under
# three texels tall, so a readable mark has to be BUILT. Dark and raised
# against a cap that lights up, which is what makes it read from the seat.
GLYPH_CELL = 0.017
GLYPH_RISE = 0.005
KEY_GLYPHS = {
    # A door slab with the way it travels.
    "LeftDoor":  ["#..#...", "#.##...", "####...", "#.##...", "#..#..."],
    "RightDoor": ["...#..#", "...##.#", "...####", "...##.#", "...#..#"],
    # A shade over a cone of light.
    "DeskLight": [".#####.", "..###..", "...#...", ".......", "..###.."],
    # Louvres.
    "Vent":      ["#######", ".......", "#######", ".......", "#######"],
    # A screen on a stand.
    "Monitor":   ["#######", "#.....#", "#.....#", "#######", "...#..."],
    # Rising signal bars.
    "Radio":     ["......#", "....#.#", "..#.#.#", "..#.#.#", "#.#.#.#"],
    # A bolt.
    "Breaker":   ["...##..", "..##...", ".####..", "..##...", ".##...."],
    # An open ring: something that comes back round.
    "Reboot":    [".#####.", "#.....#", "#......", "#.....#", ".####.."],
    # A burst.
    "Flash":     ["...#...", ".#.#.#.", "..###..", ".#.#.#.", "...#..."],
}


def _glyph(room, group, bx, by, bz, rows):
    """One key's mark, as boxes.

    Horizontally adjacent cells merge into a single run rather than becoming a
    cube each -- nine glyphs at one box per cell would roughly halve again the
    prop budget for no visible difference."""
    height = len(rows)
    width = max(len(r) for r in rows)
    x0 = bx - width * GLYPH_CELL / 2
    y0 = by + height * GLYPH_CELL / 2
    z0 = bz + KEY_RISE / 2
    parts = []
    for r, row in enumerate(rows):
        c = 0
        while c < len(row):
            if row[c] != "#":
                c += 1
                continue
            run = c
            while run < len(row) and row[run] == "#":
                run += 1
            parts.append(room.box(
                f"{group}{r}_{c}",
                x0 + c * GLYPH_CELL, y0 - (r + 1) * GLYPH_CELL, z0 - 0.001,
                x0 + run * GLYPH_CELL, y0 - r * GLYPH_CELL, z0 + GLYPH_RISE,
                "recess", None, 0))
            c = run
    # Its own group, so it keeps the dark atlas material while the key beneath
    # takes the lit override -- and so Godot can reparent it and have it sink
    # along when the key goes down.
    room.add(group, parts, origin=(bx, by, bz), rotation=(-STRIP_TILT, 0, 0))


def control_strip(room):
    """A tilted board of nine keys, each its own group so Godot can light it,
    press it in, and resolve a ray against it."""
    th = math.radians(STRIP_TILT)
    hv = STRIP_V / 2
    cx = (STRIP_X0 + STRIP_X1) / 2
    oy = STRIP_FOOT_Y + hv * math.cos(th)
    oz = STRIP_FOOT_Z - hv * math.sin(th)

    room.add("CtrlPanel", [
        room.box("CtrlPanelBody", STRIP_X0, oy - hv, oz - 0.016,
                 STRIP_X1, oy + hv, oz + 0.014, "metal", None, 8),
        room.box("CtrlPanelLipL", STRIP_X0, oy - hv, oz + 0.013,
                 STRIP_X0 + 0.018, oy + hv, oz + 0.034, "metal", None, 8),
        room.box("CtrlPanelLipR", STRIP_X1 - 0.018, oy - hv, oz + 0.013,
                 STRIP_X1, oy + hv, oz + 0.034, "metal", None, 8),
    ], origin=(cx, oy, oz), rotation=(-STRIP_TILT, 0, 0))

    dz = 0.015 + KEY_RISE / 2
    placed = {}
    for r, row in enumerate(KEY_ROWS):
        # Rows run back to front, so the first row is the far one.
        dy = hv - 0.03 - KEY_H / 2 - r * (KEY_H + 0.022)
        span = len(row) * KEY_W + (len(row) - 1) * 0.02
        for i, key in enumerate(row):
            bx = cx - span / 2 + KEY_W / 2 + i * (KEY_W + 0.02)
            by, bz = _tilt(oy, oz, dy, dz, th)
            placed[key] = (bx, by, bz)
            room.add("Ctrl" + key, [
                room.box("Ctrl" + key, bx - KEY_W / 2, by - KEY_H / 2, bz - KEY_RISE / 2,
                         bx + KEY_W / 2, by + KEY_H / 2, bz + KEY_RISE / 2,
                         "emissive", None, 4)],
                origin=(bx, by, bz), rotation=(-STRIP_TILT, 0, 0))
            if key in KEY_GLYPHS:
                _glyph(room, "Ctrl%sGlyph" % key, bx, by, bz, KEY_GLYPHS[key])
    return placed


def _arrow(room, name, bx, by, bz, sign):
    """A stepped triangle pointing left (sign -1) or right (+1).

    Columns of growing height, tip first. Everything in this pipeline is an
    axis-aligned box -- the exporter drops cube rotation -- so a diagonal edge
    is a staircase, which suits pixel art anyway."""
    z0 = bz + BUTTON_RISE / 2
    step = GLYPH_W / GLYPH_STEPS
    parts = []
    for i in range(GLYPH_STEPS):
        height = GLYPH_H * (i + 1) / GLYPH_STEPS
        x0 = (bx - GLYPH_W / 2 + i * step) if sign < 0 \
            else (bx + GLYPH_W / 2 - (i + 1) * step)
        parts.append(room.box(f"{name}{i}", x0, by - height / 2, z0 - 0.001,
                              x0 + step, by + height / 2, z0 + GLYPH_RISE,
                              "recess", None, 0))
    # Its own group, so it keeps the dark atlas material while the button under
    # it takes the lit override -- and so Godot can reparent it to the button
    # and have it sink along when the button is pressed.
    room.add(name, parts, origin=(bx, by, bz), rotation=(-PANEL_TILT, 0, 0))


def camera_console(room):
    """The desk console: a tilted board, a screen, and PREV / NEXT.

    Each button is its own group so it becomes its own glTF node -- that is
    what lets Godot light them separately, sink one when it is pressed, and
    give the aiming ray something per-button to resolve against."""
    oy, oz, th = _panel_origin()
    hv = PANEL_V / 2
    cx = (PANEL_X0 + PANEL_X1) / 2

    # Body, then a bezel frame standing proud of it, then the screen set into
    # the well between them. Each layer overlaps the last by a millimetre;
    # sharing a plane exactly would z-fight along every seam.
    room.add("CamPanel", [
        room.box("CamPanelBody", PANEL_X0, oy - hv, oz - 0.018,
                 PANEL_X1, oy + hv, oz + 0.016, "metal", None, 8),
        room.box("CamPanelBezelTop", PANEL_X0, oy + hv - BEZEL, oz + 0.015,
                 PANEL_X1, oy + hv, oz + 0.042, "metal", None, 8),
        room.box("CamPanelBezelBot", PANEL_X0, oy - hv, oz + 0.015,
                 PANEL_X1, oy - hv + BEZEL, oz + 0.042, "metal", None, 8),
        room.box("CamPanelBezelL", PANEL_X0, oy - hv, oz + 0.015,
                 PANEL_X0 + BEZEL, oy + hv, oz + 0.042, "metal", None, 8),
        room.box("CamPanelBezelR", PANEL_X1 - BEZEL, oy - hv, oz + 0.015,
                 PANEL_X1, oy + hv, oz + 0.042, "metal", None, 8),
        # A raised lip between the screen and the buttons, so the two halves of
        # the console read as separate things rather than one flat face.
        room.box("CamPanelLedge", PANEL_X0 + BEZEL, oy - hv + BEZEL + STRIP,
                 oz + 0.015, PANEL_X1 - BEZEL, oy - hv + BEZEL + STRIP + 0.012,
                 oz + 0.038, "metal", None, 8),
    ], origin=(cx, oy, oz), rotation=(-PANEL_TILT, 0, 0))

    # One material on every face, so the mesh's UV bounds are exactly the
    # screen patch and Godot can remap a live viewport onto it -- see the note
    # in room_kit.recessed_panel.
    screen_bottom = oy - hv + BEZEL + STRIP + 0.012
    room.add("CamPanelScreen", [
        room.box("CamPanelFace", PANEL_X0 + BEZEL, screen_bottom, oz + 0.014,
                 PANEL_X1 - BEZEL, oy + hv - BEZEL, oz + 0.030, "screen", None, 3)],
        origin=(cx, oy, oz), rotation=(-PANEL_TILT, 0, 0))

    dz = 0.031 + BUTTON_RISE / 2
    by, bz = _tilt(oy, oz, -hv + BEZEL + STRIP / 2, dz, th)
    placed = {}
    for name, bx, sign in (
            ("CamPrev", PANEL_X0 + BEZEL + 0.014 + BUTTON_W / 2, -1),
            ("CamNext", PANEL_X1 - BEZEL - 0.014 - BUTTON_W / 2, 1)):
        placed[name] = (bx, by, bz)
        room.add(name, [
            room.box(name, bx - BUTTON_W / 2, by - BUTTON_H / 2, bz - BUTTON_RISE / 2,
                     bx + BUTTON_W / 2, by + BUTTON_H / 2, bz + BUTTON_RISE / 2,
                     "emissive", None, 4)],
            origin=(bx, by, bz), rotation=(-PANEL_TILT, 0, 0))
        _arrow(room, name + "Glyph", bx, by, bz, sign)
    return placed


def build(room, openings=()):
    hw, hd = W / 2, D / 2

    room.add("Floor", [room.box("Floor", -hw, -T, -hd, hw, 0.0, hd,
                                "wall", {"up": "floor"}, 6)])
    room.add("Ceiling", [room.box("Ceiling", -hw, H, -hd, hw, H + T, hd,
                                  "wall", {"down": "ceiling"}, 6)])
    # The player faces -Z, so the wall behind the desk is the +Z one.
    room.add("BackWall", [room.box("BackWall", -hw, 0, hd - T, hw, H, hd, "wall", None, 7)])
    room.add("FrontWall", [room.box("FrontWall", -hw, 0, -hd, hw, H, -hd + T, "wall", None, 7)])

    for side, sx in (("Left", -1), ("Right", 1)):
        x0, x1 = (-hw, -hw + T) if sx < 0 else (hw - T, hw)
        dz0, dz1 = -DOOR_W / 2, DOOR_W / 2
        room.add(f"{side}Wall", [
            room.box(f"{side}Wall_Front", x0, 0, -hd, x1, H, dz0, "wall", None, 7),
            room.box(f"{side}Wall_Back", x0, 0, dz1, x1, H, hd, "wall", None, 7),
            room.box(f"{side}Wall_Above", x0, DOOR_H, dz0, x1, H, dz1, "wall", None, 7),
        ])
        # Trim straddles the inner wall face so the opening reads as a real jamb.
        inner = x1 if sx < 0 else x0
        tx0, tx1 = inner - 0.03, inner + 0.03
        room.add(f"{side}DoorFrame", [
            room.box(f"{side}Jamb_Front", tx0, 0, dz0 - 0.06, tx1, DOOR_H + 0.06, dz0, "metal", None, 8),
            room.box(f"{side}Jamb_Back", tx0, 0, dz1, tx1, DOOR_H + 0.06, dz1 + 0.06, "metal", None, 8),
            room.box(f"{side}Lintel", tx0, DOOR_H, dz0 - 0.06, tx1, DOOR_H + 0.06, dz1 + 0.06, "metal", None, 8),
        ])
        # Inset into the wall slot so it never z-fights the wall faces.
        room.add(f"{side}Door", [
            room.box(f"{side}Door", x0 + 0.02, 0.0, dz0, x1 - 0.02, DOOR_H, dz1,
                     "metal", {"east": "door", "west": "door"}, 4)
        ], origin=(inner, DOOR_H, 0))

    # Vent: real angled slats over a dark back plate, so the dark stripes are
    # depth the camera can look into rather than paint that stays flat.
    vx = W / 2 - 1.4
    room.add("VentFrame", [
        room.box("VentFrame", vx - VENT_W / 2 - 0.06, 2.1 - 0.06, hd - T - 0.03,
                 vx + VENT_W / 2 + 0.06, 2.1 + VENT_H + 0.06, hd - T, "metal", None, 8)])
    louvered_grille(room, "Vent", vx - VENT_W / 2, 2.1,
                    vx + VENT_W / 2, 2.1 + VENT_H, hd - T - 0.10, slats=5)

    room.add("Desk", [
        room.box("DeskTop", -1.1, 0.72, hd - 1.5, 1.1, 0.80, hd - 0.35, "desk", None, 5),
        room.box("DeskLegL", -1.05, 0.0, hd - 1.45, -0.9, 0.72, hd - 0.45, "metal", None, 5),
        room.box("DeskLegR", 0.9, 0.0, hd - 1.45, 1.05, 0.72, hd - 0.45, "metal", None, 5),
    ])
    # Off to the player's left, not dead centre. The camera tablet is its own
    # UI overlay, so this screen is decoration -- centred on the desk it filled
    # the whole forward view from the seat and hid the room the mode is about.
    room.add("MonitorStand", [
        room.box("MonitorStand", -0.72, 0.80, hd - 1.0, -0.48, 0.95, hd - 0.9, "metal", None, 8)])
    # Screen set behind a raised bezel instead of painted on a slab. It faces
    # SOUTH: the seat is at +Z looking toward -Z, so the side of the monitor
    # the player can actually see is its +Z one. Built the default way round,
    # the recess and the screen's texture rect both ended up on the far side.
    recessed_panel(room, "Monitor", -1.05, 0.95, -0.15, 1.45, hd - 1.02,
                   facing="south")

    camera_console(room)
    control_strip(room)

    room.add("DeskLamp", [
        # Shifted out to the desk's edge to make room for the camera console;
        # the console needs every centimetre of width it can get.
        room.box("LampBase", 0.86, 0.80, hd - 1.15, 1.02, 0.86, hd - 0.99, "metal", None, 8),
        room.box("LampArm", 0.92, 0.86, hd - 1.10, 0.96, 1.20, hd - 1.06, "metal", None, 8),
        room.box("LampHead", 0.80, 1.20, hd - 1.20, 1.08, 1.30, hd - 0.92, "lamp", None, 4),
    ])
    return W, D, H, T


def console_problems(room, prefix=""):
    """The console standing in the desk furniture beside it, or its own
    buttons off the board.

    Props planted inside other props is a mistake this desk has made more than
    once -- the arcade cabinets in their own doorway, the archive cabinets in
    theirs -- so the console checks itself rather than waiting to be noticed."""
    problems = []
    named = {e["name"]: e for e in room.elements}
    board = named.get(prefix + "CamPanelBody")
    for name in (prefix + "CamPrev", prefix + "CamNext"):
        button = named.get(name)
        if button is None:
            problems.append(f"{name} missing")
        elif board is not None and not (
                board["from"][0] <= button["from"][0]
                and button["to"][0] <= board["to"][0]
                and board["from"][1] <= button["from"][1]
                and button["to"][1] <= board["to"][1]):
            problems.append(f"{name} hangs off the console body")
    prev, nxt = named.get(prefix + "CamPrev"), named.get(prefix + "CamNext")
    if prev is not None and nxt is not None and prev["to"][0] >= nxt["from"][0]:
        problems.append("CamPrev and CamNext overlap")

    # An arrow hanging over the edge of the button it labels reads as damage.
    for base in ("CamPrev", "CamNext"):
        button = named.get(prefix + base)
        if button is None:
            continue
        steps = [e for e in room.elements
                 if e["name"].startswith(prefix + base + "Glyph")]
        if len(steps) != GLYPH_STEPS:
            problems.append(f"{base} has {len(steps)} arrow steps, expected {GLYPH_STEPS}")
        for e in steps:
            if not all(button["from"][k] <= e["from"][k] and e["to"][k] <= button["to"][k]
                       for k in (0, 1)):
                problems.append(f"{e['name']} hangs off {base}")

    # The console shares the desk with the monitor on one side and the lamp on
    # the other.
    mine = [e for e in room.elements
            if e["name"].startswith(prefix + "Cam")
            and not e["name"].startswith(prefix + "Camera")
            and "Glyph" not in e["name"]]
    for other in ("MonitorBezelR", "MonitorStand", "LampBase", "LampArm", "LampHead"):
        oe = named.get(prefix + other)
        if oe is None:
            continue
        for e in mine:
            if all(e["from"][k] < oe["to"][k] and oe["from"][k] < e["to"][k]
                   for k in range(3)):
                problems.append(f"{e['name']} intersects {other}")
    return problems


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "office_room.bbmodel"
    room = Room("office_room", TEAL, ALL_MATERIALS, seed=7)
    build(room)
    problems = room.check() + console_problems(room)
    path, png = room.save(out)
    print(f"wrote {path}\n     + {png}")
    print(f"  room {W}x{D}x{H} m  ({W*M:.0f}x{D*M:.0f}x{H*M:.0f} units at {M:.0f}/m)")
    print(f"  {len(room.elements)} cubes in {len(room.groups)} groups")
    print(f"  console {PANEL_X1 - PANEL_X0:.2f} x {PANEL_V:.2f} m at {PANEL_TILT:.0f} deg")
    print(f"  buttons PREV/NEXT, {BUTTON_W * 100:.0f} x {BUTTON_H * 100:.0f} cm each, "
          f"{GLYPH_W * 100:.0f} x {GLYPH_H * 100:.0f} cm arrows in {GLYPH_STEPS} steps")
    if problems:
        print(f"  !! {len(problems)} problems")
        for p in problems[:8]:
            print("    ", p)
        return 1
    print("  clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
