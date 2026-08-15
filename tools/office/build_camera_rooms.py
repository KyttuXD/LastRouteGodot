#!/usr/bin/env python3
"""
Builds the six Office Mode camera-feed rooms as Hytale-style Blockbench models.

`OfficeConfig.CAMERA_VIEWS` defines eight cameras across six distinct layouts,
each with its own accent colour. The layouts are what get modelled -- WEST/EAST
HALL share `hall`, VENT A/B share `vent` -- so six rooms cover all eight feeds,
and Godot picks the model by `view["layout"]`.

Each room carries a `CameraMount` group whose ORIGIN is the security camera's
viewpoint. That is the import contract: Godot reads the group origin, puts its
Camera3D there and aims it at the room centre, so framing is authored here
rather than hand-tuned per feed in the editor.

    python3 build_camera_rooms.py [outdir]
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import random
from room_kit import Room, shell, corridor, recessed_panel, louvered_grille, M
from room_paint import hexc, ALL_MATERIALS

# layout -> (accent hex, cameras using it), straight out of OfficeConfig.
LAYOUTS = {
    "hall":       ("785457", ["cam1 WEST HALL", "cam2 EAST HALL"]),
    "storage":    ("5d6970", ["cam3 STORAGE"]),
    "archive":    ("766154", ["cam4 ARCHIVE"]),
    "vent":       ("54756a", ["cam5 VENT A", "cam6 VENT B"]),
    "electrical": ("8a7045", ["cam7 ELECTRICAL"]),
    "loading":    ("6b5d70", ["cam8 LOADING"]),
    # Layouts OfficeConfig names but that had no standalone feed model: they
    # existed only inside the merged map, so three cameras had nothing to draw.
    "passage":    ("54756a", ["cam5 EAST PASSAGE", "cam6 WEST PASSAGE"]),
    "arcade":     ("6d4f7a", ["cam9 ARCADE"]),
    "dining":     ("7a5a4a", ["cam10 DINING A", "cam11 DINING B"]),
}

# --- shared props ----------------------------------------------------------

# The merged map cuts real openings in the walls these panels sit on, so it
# turns them off -- a solid door would plug the hole a hunter walks through.
DRAW_DOOR_PANELS = True
# Likewise the vent's end grilles: standalone they cap the duct, but in the
# merged map those ends are where a hunter crawls through into the next room,
# and the grille's dark back plate would seal it.
DRAW_END_GRILLES = True
# Which side of the corridor the hall camera hangs on. The two halls are the
# same model placed with opposite quarter-turns, so an identical local mount
# lands on OPPOSITE sides of the door in world space. The merged map flips one
# of them so both cameras watch each doorway from the same side.
HALL_CAM_SIDE = 1


def camera_mount(room, pos, target, name="CameraMount"):
    """Housing + lens in a ceiling corner, plus the point it aims at.

    Position alone is not enough: a ceiling-corner camera aimed at the room
    origin stares down at bare floor, and two of these rooms framed an empty
    corner. So the aim is authored here too, as an empty `CameraTarget` group
    whose origin is the look-at point. Godot reads both and the framing is
    fixed in the model rather than hand-tuned per feed in the editor."""
    x, y, z = pos
    # Drop off the ceiling. Mounted flush at 2.65-2.85 m the camera looks
    # steeply down and the floor takes most of the frame whatever it aims at.
    # 2.2 m is still above head height but gives a near-level view along the
    # room, which is what makes someone walking through it readable.
    y = min(y, 2.5)
    pos = (x, y, z)          # the group ORIGIN is the viewpoint Godot reads
    # Aim at least eye height. Several feeds were pointed at ~1.0 m and, from a
    # mount near the ceiling, that put the floor across most of the frame --
    # a camera should show the room, and anything walking through it.
    # Push the aim point ACROSS the room, not just up. A target 1-2 m from a
    # ceiling mount makes the camera stare at the floor beneath itself; the
    # same direction extended to ~6 m looks along the room instead, which is
    # what a feed has to show for a threat crossing it to be visible.
    import math as _m
    tx, ty, tz = target
    dx, dz = tx - x, tz - z
    dist = _m.hypot(dx, dz)
    if dist > 0.01:
        tx, tz = x + dx / dist * 4.5, z + dz / dist * 4.5
    # 2.5 m mount aiming at 1.1 m from 4.5 m away is about 17 degrees down:
    # steep enough that the floor and anything standing on it fill the frame,
    # shallow enough that the shot is not just the floor under the camera.
    target = (tx, 1.1, tz)
    sx = -0.12 if x > 0 else 0.12          # tuck the body back toward the wall
    sz = -0.12 if z > 0 else 0.12
    room.add(name, [
        room.box("CamBody", x + sx - 0.12, y - 0.10, z + sz - 0.12,
                 x + sx + 0.12, y + 0.10, z + sz + 0.12, "metal", None, 8),
        room.box("CamLens", x - 0.05, y - 0.05, z - 0.05,
                 x + 0.05, y + 0.05, z + 0.05, "metal", None, 4),
    ], origin=pos)
    room.add("CameraTarget", [], origin=target)

def ceiling_lights(room, w, h, zs, name="Lights"):
    parts = []
    for i, z in enumerate(zs):
        parts.append(room.box(f"Light{i}", -w * 0.16, h - 0.08, z - 0.22,
                              w * 0.16, h - 0.02, z + 0.22, "lamp", None, 4))
    room.add(name, parts)

def wall_sign(room, x, y, z, facing, name="Sign"):
    """Room identity plate in the camera's accent -- the feed's colour cue."""
    t = 0.04
    if facing in ("north", "south"):
        p = room.box("SignPlate", x - 0.45, y - 0.16, z - t, x + 0.45, y + 0.16, z + t,
                     "metal", {facing: "sign"}, 3)
    else:
        p = room.box("SignPlate", x - t, y - 0.16, z - 0.45, x + t, y + 0.16, z + 0.45,
                     "metal", {facing: "sign"}, 3)
    room.add(name, [p])

def door_panel(room, x, y0, z, w, h, facing, name):
    """A shut door read as a flat panel on the wall -- no opening cut."""
    if not DRAW_DOOR_PANELS:
        return
    t = 0.05
    if facing in ("north", "south"):
        p = room.box(name, x - w / 2, y0, z - t, x + w / 2, y0 + h, z + t,
                     "metal", {facing: "door"}, 4)
    else:
        p = room.box(name, x - t, y0, z - w / 2, x + t, y0 + h, z + w / 2,
                     "metal", {facing: "door"}, 4)
    room.add(name, [p])

def conduit_run(room, y, x, z0, z1, name="Conduit", n=3):
    parts = []
    for i in range(n):
        yy = y + i * 0.10
        parts.append(room.box(f"Pipe{i}", x - 0.04, yy - 0.04, z0,
                              x + 0.04, yy + 0.04, z1, "conduit", None, 8))
    room.add(name, parts)

def crate_stack(room, cx, cz, rng, name, levels=2, size=0.7):
    parts = []
    y = 0.0
    for i in range(levels):
        s = size * (1.0 - 0.08 * i)
        jx, jz = rng.uniform(-0.08, 0.08), rng.uniform(-0.08, 0.08)
        parts.append(room.box(f"{name}Box{i}", cx + jx - s / 2, y, cz + jz - s / 2,
                              cx + jx + s / 2, y + s, cz + jz + s / 2, "crate", None, 5))
        y += s
    room.add(name, parts)

def shelving(room, cx, cz, rng, name, along="z", length=2.4, depth=0.5, height=2.0):
    """Steel shelving: front face gets the fitted `shelf` art, sides metal."""
    if along == "z":
        box = (cx - depth / 2, 0, cz - length / 2, cx + depth / 2, height, cz + length / 2)
        face = "east" if cx < 0 else "west"
    else:
        box = (cx - length / 2, 0, cz - depth / 2, cx + length / 2, height, cz + depth / 2)
        face = "north" if cz > 0 else "south"
    room.add(name, [room.box(name, *box, "metal", {face: "shelf"}, 6)])

def hazard_floor(room, cx, cz, w, d, name="HazardZone"):
    room.add(name, [room.box(name, cx - w / 2, 0.005, cz - d / 2,
                             cx + w / 2, 0.02, cz + d / 2, "metal",
                             {"up": "hazard"}, 4)])

# --- rooms -----------------------------------------------------------------

# Parts that are MEANT to sit inside the wall slab -- signage, door panels,
# grilles, conduit brackets, ribs, breaker boxes. Everything else poking past
# the inner wall face is a modelling error, not a design choice.
WALL_EMBEDDED = ("Sign", "Door", "Grille", "Rib", "Pipe", "Conduit", "Breaker",
                 "Riser", "Bay", "Light", "Cam", "Trans", "Wall", "Floor", "Ceiling")

def check_inside(room, W, D, H, t, tol=0.02):
    """Flag props that punch through the shell.

    Anything reaching past the OUTER wall face is visibly broken on a camera
    feed -- a shelf standing half outside the room."""
    problems = []
    for e in room.elements:
        if e["name"].startswith(WALL_EMBEDDED):
            continue
        x0, y0, z0 = [c / M for c in e["from"]]
        x1, y1, z1 = [c / M for c in e["to"]]
        if (x0 < -W / 2 + t - tol or x1 > W / 2 - t + tol
                or z0 < -D / 2 + t - tol or z1 > D / 2 - t + tol
                or y0 < -tol or y1 > H + tol):
            problems.append(
                f"{e['name']}: [{x0:+.2f},{x1:+.2f}] x [{z0:+.2f},{z1:+.2f}] "
                f"y[{y0:.2f},{y1:.2f}] outside inner shell "
                f"[{-W/2+t:+.2f},{W/2-t:+.2f}] x [{-D/2+t:+.2f},{D/2-t:+.2f}] y[0,{H:.2f}]")
    return problems


def build_hall(room, openings=()):
    """A long corridor. Both halls use it; the accent separates them."""
    W, D, H = 3.0, 12.0, 3.0
    shell(room, W, D, H, openings=openings)
    rng = random.Random(1)
    ceiling_lights(room, W, H, [-4.0, 0.0, 4.0])
    door_panel(room, 0, 0, D / 2 - 0.16, 1.2, 2.2, "north", "DoorFar")
    door_panel(room, 0, 0, -D / 2 + 0.16, 1.2, 2.2, "south", "DoorNear")
    wall_sign(room, -W / 2 + 0.17, 2.3, -3.0, "east")
    conduit_run(room, 2.55, W / 2 - 0.22, -D / 2 + 0.2, D / 2 - 0.2)
    # A couple of crates against the wall so the corridor is not a bare tube.
    crate_stack(room, -W / 2 + 0.55, 2.6, rng, "CratesA", 2, 0.6)
    crate_stack(room, W / 2 - 0.55, -2.2, rng, "CratesB", 1, 0.7)
    # Look straight down the corridor, not at the floor under the lens.
    camera_mount(room, (HALL_CAM_SIDE * (W / 2 - 0.3), H - 0.35, -D / 2 + 0.4),
                 (0.0, 1.2, 4.0))
    return W, D, H, 0.15

def build_storage(room, openings=()):
    W, D, H = 7.0, 6.0, 3.2
    shell(room, W, D, H, openings=openings)
    rng = random.Random(2)
    ceiling_lights(room, W, H, [-1.6, 1.6])
    door_panel(room, 0, 0, -D / 2 + 0.16, 1.2, 2.2, "south", "Door")
    wall_sign(room, 0, 2.5, -D / 2 + 0.2, "south")
    for i, z in enumerate((-1.6, 0.0, 1.6)):
        shelving(room, -W / 2 + 0.42, z, rng, f"ShelfL{i}")
        shelving(room, W / 2 - 0.42, z, rng, f"ShelfR{i}")
    for i, (x, z) in enumerate(((-0.9, 0.6), (0.5, -0.4), (1.4, 1.5), (-1.7, -1.4))):
        crate_stack(room, x, z, rng, f"Crates{i}", rng.randint(1, 3), rng.uniform(0.6, 0.8))
    camera_mount(room, (W / 2 - 0.3, H - 0.35, 0.0), (-W / 2, 1.1, 0.0))
    return W, D, H, 0.15

def build_archive(room, openings=()):
    W, D, H = 6.0, 5.0, 3.0
    shell(room, W, D, H, openings=openings)
    rng = random.Random(3)
    ceiling_lights(room, W, H, [-1.2, 1.2])
    door_panel(room, 0, 0, -D / 2 + 0.16, 1.2, 2.2, "south", "Door")
    wall_sign(room, W / 2 - 0.2, 2.4, 0.0, "west")
    # Cabinet banks along the back wall, boxes stacked on top of them.
    for i in range(6):
        # 2 and 3 are skipped: the merged map puts a doorway in the middle of
        # this wall, and a cabinet parked across it seals the room off.
        if i in (2, 3):
            continue
        x = -2.3 + i * 0.92
        room.add(f"Cabinet{i}", [room.box(f"Cabinet{i}", x - 0.42, 0, D / 2 - 0.78,
                                          x + 0.42, 1.35, D / 2 - 0.18,
                                          "metal", {"north": "cabinet"}, 8)])
        if rng.random() > 0.4:
            s = rng.uniform(0.35, 0.5)
            room.add(f"CabBox{i}", [room.box(f"CabBox{i}", x - s / 2, 1.35, D / 2 - 0.62,
                                             x + s / 2, 1.35 + s, D / 2 - 0.30,
                                             "crate", None, 5)])
    for i, z in enumerate((-1.0, 0.8)):
        shelving(room, -W / 2 + 0.42, z, rng, f"ArchShelf{i}", length=1.8)
    # Reading table under the camera.
    room.add("Table", [
        room.box("TableTop", -0.9, 0.72, -1.4, 0.9, 0.78, -0.4, "desk", None, 5),
        room.box("TableLegL", -0.85, 0, -1.35, -0.72, 0.72, -0.48, "metal", None, 5),
        room.box("TableLegR", 0.72, 0, -1.35, 0.85, 0.72, -0.48, "metal", None, 5),
    ])
    # Aimed at the cabinet bank on the back wall -- the room's content.
    camera_mount(room, (-W / 2 + 0.3, H - 0.35, 0.0), (W / 2, 1.1, 0.0))
    return W, D, H, 0.15

def build_vent(room, openings=()):
    """A crawlable duct. Deliberately cramped -- it is a hiding route."""
    W, D, H = 1.3, 9.0, 1.3
    shell(room, W, D, H, t=0.08, floor_mat="duct", ceil_mat="duct",
          wall_mat="duct", openings=openings)
    rng = random.Random(4)
    # Stiffening ribs every 1.5 m give the duct depth cues down its length.
    ribs = []
    for i in range(-3, 4):
        z = i * 1.4
        ribs.append(room.box(f"Rib{i}", -W / 2 + 0.06, 0.0, z - 0.05,
                             -W / 2 + 0.14, H, z + 0.05, "metal", None, 8))
        ribs.append(room.box(f"RibR{i}", W / 2 - 0.14, 0.0, z - 0.05,
                             W / 2 - 0.06, H, z + 0.05, "metal", None, 8))
    room.add("Ribs", ribs)
    # Grilles at both ends: the light source, and where a threat enters.
    # Real slats -- looking down a duct at a flat painted grille is exactly
    # where a decal gives itself away.
    if DRAW_END_GRILLES:
        louvered_grille(room, "GrilleFar", -0.45, 0.25, 0.45, 1.05, D / 2 - 0.16, slats=6)
        louvered_grille(room, "GrilleNear", -0.45, 0.25, 0.45, 1.05, -D / 2 + 0.02,
                        slats=6, tilt=22.0)
    wall_sign(room, -W / 2 + 0.10, 1.05, -2.4, "east")
    # Straight down the duct: the whole point of this feed is the far grille.
    camera_mount(room, (0.0, H - 0.14, -D / 2 + 0.35), (0.0, 0.62, 4.2))
    return W, D, H, 0.08

def build_electrical(room, openings=()):
    W, D, H = 5.0, 4.0, 3.0
    shell(room, W, D, H, openings=openings)
    rng = random.Random(5)
    ceiling_lights(room, W, H, [0.0])
    door_panel(room, 0, 0, -D / 2 + 0.16, 1.2, 2.2, "south", "Door")
    wall_sign(room, -W / 2 + 0.2, 2.4, 0.6, "east")
    # Breaker banks across the back wall -- the room's whole reason to exist.
    for i in range(4):
        x = -1.65 + i * 1.1
        room.add(f"BreakerBox{i}", [room.box(f"BreakerBox{i}", x - 0.42, 1.0, D / 2 - 0.34,
                                             x + 0.42, 2.2, D / 2 - 0.18, "metal", None, 8)])
        # z_front + depth must land exactly on the housing's front face
        # (D/2-0.34); any deeper and the panel is buried inside its own box.
        recessed_panel(room, f"Breaker{i}", x - 0.40, 1.02, x + 0.40, 2.18,
                       D / 2 - 0.38, inset=0.04, proud=0.02, depth=0.04,
                       face_mat="panel", color=8)
    conduit_run(room, 2.35, 0, D / 2 - 0.30, D / 2 - 0.30, n=1)
    for i, x in enumerate((-1.65, -0.55, 0.55, 1.65)):
        room.add(f"Riser{i}", [room.box(f"Riser{i}", x - 0.05, 2.2, D / 2 - 0.34,
                                        x + 0.05, H, D / 2 - 0.24, "conduit", None, 8)])
    # Transformer housing, humming away in the corner.
    room.add("Transformer", [
        room.box("TransBody", -W / 2 + 0.35, 0, -1.5, -W / 2 + 1.25, 1.5, -0.3,
                 "metal", None, 8),
        room.box("TransFins", -W / 2 + 0.30, 0.25, -1.4, -W / 2 + 0.36, 1.25, -0.4,
                 "conduit", None, 8),
    ])
    hazard_floor(room, 0, D / 2 - 1.0, 4.2, 0.9)
    camera_mount(room, (W / 2 - 0.3, H - 0.35, -0.6), (-W / 2, 1.1, 0.6))
    return W, D, H, 0.15

def build_loading(room, openings=()):
    W, D, H = 9.0, 7.0, 4.5
    shell(room, W, D, H, openings=openings)
    rng = random.Random(6)
    ceiling_lights(room, W, H, [-2.0, 0.0, 2.0])
    # Roller shutter filling most of the back wall: the bay door.
    room.add("BayDoor", [room.box("BayDoor", -2.4, 0, D / 2 - 0.22,
                                  2.4, 3.4, D / 2 - 0.14, "metal",
                                  {"north": "door"}, 4)])
    door_panel(room, -W / 2 + 0.20, 0, -1.5, 1.1, 2.2, "east", "SideDoor")
    wall_sign(room, W / 2 - 0.2, 3.0, -1.0, "west")
    hazard_floor(room, 0, D / 2 - 1.6, 5.4, 1.6)
    # Pallets with crate stacks on them, scattered across the bay.
    for i, (x, z) in enumerate(((-3.0, -1.0), (-1.2, 0.6), (0.9, -1.8),
                                (2.6, 0.9), (3.4, -2.2))):
        room.add(f"Pallet{i}", [room.box(f"Pallet{i}", x - 0.6, 0, z - 0.6,
                                         x + 0.6, 0.14, z + 0.6, "crate", None, 5)])
        crate_stack(room, x, z, rng, f"BayCrates{i}", rng.randint(1, 3), rng.uniform(0.65, 0.85))
    for i, z in enumerate((-2.1, 1.9)):
        shelving(room, -W / 2 + 0.42, z, rng, f"BayShelf{i}", length=2.2, height=2.4)
    conduit_run(room, 3.9, W / 2 - 0.22, -D / 2 + 0.2, D / 2 - 0.2, n=2)
    camera_mount(room, (-W / 2 + 0.3, H - 0.4, 0.0), (W / 2, 1.1, 0.0))
    return W, D, H, 0.15

def build_passage(room, openings=()):
    """A walk-height connecting passage -- what cam5/cam6 actually watch since
    those ducts became hallways. Narrow and long, so the feed reads as a
    throughway rather than a room."""
    W, D, H = 2.2, 9.0, 2.6
    shell(room, W, D, H, openings=openings)
    rng = random.Random(13)
    ceiling_lights(room, W, H, [-2.6, 0.0, 2.6])
    wall_sign(room, -W / 2 + 0.17, 2.0, -2.0, "east")
    conduit_run(room, 2.15, W / 2 - 0.20, -D / 2 + 0.2, D / 2 - 0.2, n=3)
    crate_stack(room, -W / 2 + 0.5, 1.8, rng, "PassCrate", 1, 0.55)
    camera_mount(room, (W / 2 - 0.28, H - 0.3, -D / 2 + 0.35), (0.0, 1.1, 3.2))
    return W, D, H, 0.15

def build_dining(room, openings=()):
    """A party/dining room: long tables with chairs, checkered floor, banners.

    Deliberately open in the middle -- this is a room hunters cross, and a
    camera watching it needs a clear sightline down the tables."""
    W, D, H = 9.0, 7.0, 3.2
    shell(room, W, D, H, floor_mat="party", openings=openings)
    rng = random.Random(11)
    ceiling_lights(room, W, H, [-2.0, 0.0, 2.0])
    wall_sign(room, 0, 2.5, D / 2 - 0.2, "north")
    for i, z in enumerate((-1.8, 0.6)):
        room.add(f"Table{i}", [room.box(f"Table{i}", -2.6, 0.68, z - 0.45,
                                        2.6, 0.76, z + 0.45, "desk", None, 5)])
        legs = []
        for lx in (-2.4, 2.3):
            legs.append(room.box(f"Table{i}Leg{lx:+.0f}", lx, 0, z - 0.35,
                                 lx + 0.14, 0.68, z + 0.35, "metal", None, 5))
        room.add(f"Table{i}Legs", legs)
        chairs = []
        for j, cx in enumerate((-1.8, -0.6, 0.6, 1.8)):
            for sgn in (-1, 1):
                cz = z + sgn * 0.85
                chairs.append(room.box(f"Chair{i}_{j}{'A' if sgn < 0 else 'B'}",
                                       cx - 0.22, 0, cz - 0.22, cx + 0.22, 0.45,
                                       cz + 0.22, "party", None, 3))
        room.add(f"Chairs{i}", chairs)
    # Banners strung along the side walls, in the room's accent.
    banners = []
    for i, z in enumerate((-2.2, 0.0, 2.2)):
        banners.append(room.box(f"BannerL{i}", -W / 2 + 0.16, 2.35, z - 0.5,
                                -W / 2 + 0.20, 2.75, z + 0.5, "party", None, 3))
        banners.append(room.box(f"BannerR{i}", W / 2 - 0.20, 2.35, z - 0.5,
                                W / 2 - 0.16, 2.75, z + 0.5, "party", None, 3))
    room.add("Banners", banners)
    camera_mount(room, (W / 2 - 0.3, H - 0.35, 0.0), (-W / 2, 1.1, 0.0))
    return W, D, H, 0.15

def build_arcade(room, openings=()):
    """An arcade: cabinets down both walls, their marquees the only real light."""
    W, D, H = 8.0, 6.0, 3.2
    shell(room, W, D, H, floor_mat="party", openings=openings)
    rng = random.Random(12)
    ceiling_lights(room, W, H, [-1.4, 1.4])
    wall_sign(room, 0, 2.5, D / 2 - 0.2, "north")
    for side, sx in (("L", -1), ("R", 1)):
        # Paired either side of a clear centre. At -0.6 and 0.7 the two middle
        # cabinets closed on the mid-wall doorway from both sides and left a
        # 0.46 m gap -- narrower than the 1.2 m opening, so the room was sealed.
        for i, z in enumerate((-2.3, -1.3, 1.3, 2.3)):
            cx = sx * (W / 2 - 0.55)
            body = room.box(f"Cab{side}{i}", cx - 0.38, 0, z - 0.42,
                            cx + 0.38, 1.85, z + 0.42, "metal", None, 8)
            # Screen faces into the room, on whichever side the cabinet stands.
            face = "east" if sx < 0 else "west"
            # MINUS sx: the screen faces INTO the room. With +sx it was offset
            # outward and buried inside the wall behind the cabinet.
            screen = room.box(f"Cab{side}{i}Screen",
                              cx - sx * 0.38, 0.95, z - 0.30,
                              cx - sx * 0.44, 1.55, z + 0.30,
                              "metal", {face: "arcade"}, 4)
            room.add(f"Cabinet{side}{i}", [body, screen])
    # Diagonal, not square-on: from a corner across the room, so the cabinet
    # rows recede along the frame instead of presenting as a flat wall.
    camera_mount(room, (-W / 2 + 0.35, H - 0.35, -D / 2 + 0.5), (W / 2, 1.1, D / 2))
    return W, D, H, 0.15

BUILDERS = {
    "dining": build_dining, "arcade": build_arcade, "passage": build_passage,
    "hall": build_hall, "storage": build_storage, "archive": build_archive,
    "vent": build_vent, "electrical": build_electrical, "loading": build_loading,
}

def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else "camera_rooms"
    ok = True
    for i, (layout, (accent_hex, cams)) in enumerate(LAYOUTS.items()):
        room = Room(layout, hexc(accent_hex), ALL_MATERIALS, seed=7 + i)
        dims = BUILDERS[layout](room)
        problems = room.check() + check_inside(room, *dims)
        path, png = room.save(os.path.join(outdir, f"{layout}.bbmodel"))
        xs = [c for e in room.elements for c in (e["from"][0], e["to"][0])]
        ys = [c for e in room.elements for c in (e["from"][1], e["to"][1])]
        zs = [c for e in room.elements for c in (e["from"][2], e["to"][2])]
        mount = next(g for g in room.groups if g["name"] == "CameraMount")
        print(f"{layout:11s} #{accent_hex}  {len(room.elements):3d} cubes  "
              f"{len(room.groups):2d} groups  "
              f"{(max(xs)-min(xs))/M:4.1f} x {(max(zs)-min(zs))/M:4.1f} x "
              f"{(max(ys)-min(ys))/M:4.1f} m")
        print(f"{'':11s} cams: {', '.join(cams)}")
        print(f"{'':11s} camera viewpoint: "
              f"({mount['origin'][0]/M:+.2f}, {mount['origin'][1]/M:.2f}, "
              f"{mount['origin'][2]/M:+.2f}) m")
        if problems:
            ok = False
            print(f"{'':11s} !! {len(problems)} PROBLEMS")
            for p in problems[:6]:
                print(f"{'':13s} {p}")
    print(f"\n{'all rooms clean' if ok else 'PROBLEMS FOUND'} -> {outdir}")
    return 0 if ok else 1

if __name__ == "__main__":
    sys.exit(main())
