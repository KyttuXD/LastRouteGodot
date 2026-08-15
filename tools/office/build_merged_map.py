#!/usr/bin/env python3
"""
Merges the office and all six camera rooms into ONE fully connected 3D map.

The floor plan is not invented: `OfficeConfig.CAMERA_GRAPH` already states
which rooms connect to which, and the office's own doors open onto the two
halls. The graph is symmetric, so cam1/3/6 form the west wing and cam2/4/5 the
east, with ELECTRICAL and LOADING shared on the centre line.

Every link is PHYSICALLY walkable, not just adjacent:
  * where two rooms share a wall, that wall is cut with a real opening
  * where the graph links rooms no rectangle layout can make share a wall
    (ELECTRICAL touches both vents, LOADING touches storage AND archive),
    an actual corridor is built between them
so a hunter can travel the whole map on foot. The vents are 1.3 m tall, which
is why that route is a crawl rather than a walk.

Each camera also gets an empty `Nav_camN` group at floor level in the middle of
its room. Those are the waypoints the Godot side moves hunters between --
`office_simulation.gd` already computes which camera a threat is at, via
`_camera_at_progress(start, destination, progress)` over this same graph, so
the 3D layer only has to interpolate between these markers rather than run
any AI of its own.

    python3 build_merged_map.py [out.bbmodel]
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from room_kit import Room, corridor, M
from room_paint import build_multi_atlas, hexc, ALL_MATERIALS, TEAL
import build_camera_rooms as CR
import build_office_room as OR
import office_layout as LAY

DOOR = (1.2, 2.2)          # walkable opening
CRAWL = (0.9, 1.1)         # vent opening -- forces a crawl

# key -> (accent, builder, quarter turns, openings). The room's POSITION is not
# here: it comes from office_layout.ROOM_XZ, which the desk console's button
# plan is also drawn from, so the map and the map-of-the-map cannot drift.
#
# Openings are given in each room's OWN axes; `turns` rotates them with the
# room. The halls are quarter-turned so they run along X out of the office's
# side doors -- EastHall uses 3 turns rather than 1 so that BOTH halls face the
# office with the same local wall, keeping the two wings mirror images.
PLAN = {
    "Office":     (TEAL, OR.build, 0, (("north", 1.1, *CRAWL),)),
    "WestHall":   (hexc("785457"), CR.build_hall, 1,
                   (("north", 0.0, *DOOR), ("east", -5.35, *DOOR), ("west", -2.0, *DOOR))),
    "EastHall":   (hexc("785457"), CR.build_hall, 3,
                   (("north", 0.0, *DOOR), ("west", -5.35, *DOOR), ("east", -2.0, *DOOR))),
    "Storage":    (hexc("5d6970"), CR.build_storage, 0,
                   (("north", 0.0, *DOOR), ("south", 0.0, *DOOR))),
    "Archive":    (hexc("766154"), CR.build_archive, 0,
                   (("north", 0.0, *DOOR), ("south", 0.0, *DOOR))),
    "Electrical": (hexc("8a7045"), CR.build_electrical, 0,
                   (("west", 0.0, *DOOR), ("east", 0.0, *DOOR))),
    "Loading":    (hexc("6b5d70"), CR.build_loading, 0,
                   (("west", 0.0, *DOOR), ("east", 0.0, *DOOR))),
    # South wing, off the two halls: the rooms hunters cross rather than hide in.
    "Arcade":     (hexc("6d4f7a"), CR.build_arcade, 0,
                   (("north", 0.0, *DOOR), ("east", 0.0, *DOOR))),
    "DiningA":    (hexc("7a5a4a"), CR.build_dining, 0,
                   (("west", 0.0, *DOOR), ("east", 0.0, *DOOR))),
    "DiningB":    (hexc("4a6a7a"), CR.build_dining, 0,
                   (("west", 0.0, *DOOR), ("north", 0.0, *DOOR))),
}

# Corridors for the graph edges no shared wall can express.
# (group, from (x,z), to (x,z), height, width)
# Walk-height hallways (2.6 m tall, 2.2 m wide) everywhere a person travels.
# The one exception is OfficeDuct: 1.0 m, so it can only be crawled.
CORRIDORS = [
    # Each passage is split around the Electrical junction. A corridor has
    # solid side walls and no opening support, so an unbroken passage would
    # seal off the branch that crosses it -- which is exactly what left
    # ELECTRICAL unreachable.
    ("WestPassageN", (-14.35, -1.50), (-14.35, -4.90), 2.6, 2.2),
    ("WestPassageS", (-14.35, -7.10), (-14.35, -10.50), 2.6, 2.2),
    ("EastPassageN", (14.35, -1.50), (14.35, -4.90), 2.6, 2.2),
    ("EastPassageS", (14.35, -7.10), (14.35, -10.50), 2.6, 2.2),
    ("LinkElecW", (-13.25, -6.0), (-2.50, -6.0), 2.6, 2.2),        # passage -> Electrical
    ("LinkElecE", (13.25, -6.0), (2.50, -6.0), 2.6, 2.2),          # passage -> Electrical
    ("LinkBayW1", (-14.35, -16.50), (-14.35, -18.40), 2.6, 2.2),   # Storage -> south
    ("LinkBayW2", (-13.25, -19.50), (-4.50, -19.50), 2.6, 2.2),    #         -> Loading
    ("LinkBayE1", (14.35, -15.50), (14.35, -18.40), 2.6, 2.2),     # Archive -> south
    ("LinkBayE2", (13.25, -19.50), (4.50, -19.50), 2.6, 2.2),      #         -> Loading
    # The only duct in the map: office back wall to Electrical, crawl-only.
    # 1.4 m, not 1.0. Measured on the rig: a hands-and-knees crawl pose is
    # 85.1 units = 1.26 m tall, so a 1.0 m duct is one nothing can actually
    # crawl through. 1.4 m clears that with headroom while staying far under
    # the 1.80 m standing height, so it is still crawl-only.
    ("OfficeDuct", (1.10, 2.50), (1.10, -4.00), 1.4, 1.1),
    # South wing
    ("LinkArcade", (-11.0, 1.50), (-11.0, 6.00), 2.6, 2.2),
    ("LinkDineB", (11.0, 1.50), (11.0, 5.50), 2.6, 2.2),
    ("LinkArcDine", (-7.00, 9.0), (-4.50, 9.0), 2.6, 2.2),
    ("LinkDineAB", (4.50, 9.0), (6.50, 9.0), 2.6, 2.2),
]

CAM_ROOM = LAY.CAM_ROOM
CAM_POINT = LAY.CAM_POINT


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "office_map.bbmodel"
    # Pack one variant per DISTINCT accent: the halls share one and so do the
    # vents, so this is 7 variants rather than 9.
    specs = {}
    for _k, (accent, *_rest) in PLAN.items():
        specs.setdefault(str(accent), accent)
    atlas, rect_sets = build_multi_atlas(specs, ALL_MATERIALS, size=1024)
    room = Room("office_map", TEAL, atlas=atlas, rect_sets=rect_sets, atlas_size=1024)

    # The halls' solid door panels would plug the openings just cut in those
    # same walls, so the merged map leaves them off.
    CR.DRAW_DOOR_PANELS = False
    CR.DRAW_END_GRILLES = False

    footprints = {}
    for key, (accent, builder, turns, openings) in PLAN.items():
        offset = LAY.ROOM_XZ[key]
        # Mirror the west hall's camera so both halls watch their doorway from
        # the same side; the two are the same model at opposite quarter-turns.
        CR.HALL_CAM_SIDE = -1 if key == "WestHall" else 1
        room.select(str(accent), offset=offset, turns=turns, prefix=key + "_")
        W, D, H, t = builder(room, openings=openings)
        if turns % 2:
            W, D = D, W
        footprints[key] = (offset, W, D, H)

    room.select(next(iter(specs)))
    room.offset, room.turns, room.prefix = (0.0, 0.0), 0, ""
    # Corner filling. Two corridors meeting at a right angle each stop at the
    # junction centre line, so neither covers the corner square -- and a
    # corridor ending on another's flank leaves the same notch at a T. Pad any
    # end that lands on ANOTHER corridor; ends that meet a room stay flush, so
    # no stub pokes through a wall.
    # Branches that T into a passage must not be padded at that end -- padding
    # pushes their side walls across the passage instead of filling a corner.
    NOPAD = {"LinkElecW", "LinkElecE", "LinkBayW2", "LinkBayE2",
             "LinkBayW1", "LinkBayE1",
             "WestPassageN", "WestPassageS", "EastPassageN", "EastPassageS"}

    def seg_dist(px, pz, ax, az, bx, bz):
        dx, dz = bx - ax, bz - az
        L2 = dx * dx + dz * dz
        t = 0.0 if L2 == 0 else max(0.0, min(1.0, ((px - ax) * dx + (pz - az) * dz) / L2))
        cx, cz = ax + t * dx, az + t * dz
        return ((px - cx) ** 2 + (pz - cz) ** 2) ** 0.5

    for i, (name, (ax, az), (bx, bz), h, wid) in enumerate(CORRIDORS):
        pads = []
        for (px, pz) in ((ax, az), (bx, bz)):
            touching = name not in NOPAD and any(
                seg_dist(px, pz, ox, oz, qx, qz) <= max(wid, ow) * 0.75
                for j, (_n, (ox, oz), (qx, qz), _h, ow) in enumerate(CORRIDORS)
                if j != i)
            pads.append(wid / 2 if touching else 0.0)
        corridor(room, name, ax, az, bx, bz, h=h, width=wid, pad=tuple(pads))

    # T-junction patches. A corridor carries side walls down its whole length,
    # so where a branch joins a passage the two seal each other out. The
    # passages are left split at the junction and the square between them gets
    # floor and ceiling ONLY -- no side walls, so both routes stay open.
    for nm, (jx0, jz0, jx1, jz1) in (
            ("JunctElecW", (-15.45, -7.10, -13.25, -4.90)),
            ("JunctElecE", (13.25, -7.10, 15.45, -4.90)),
            ("JunctBayW", (-15.45, -20.60, -13.25, -18.40)),
            ("JunctBayE", (13.25, -20.60, 15.45, -18.40))):
        room.add(nm, [
            room.box(f"{nm}Floor", jx0, -0.15, jz0, jx1, 0.0, jz1,
                     "wall", {"up": "floor"}, 6),
            room.box(f"{nm}Ceil", jx0, 2.6, jz0, jx1, 2.75, jz1,
                     "wall", {"down": "ceiling"}, 6),
        ] + ([] if nm.startswith("JunctElec") else [
            # An L-corner also needs its OUTER wall closed, or the turn opens
            # onto nothing -- the notch visible in the corner screenshots.
            room.box(f"{nm}OuterS", jx0, 0.0, jz0 - 0.15, jx1, 2.6, jz0,
                     "wall", None, 7),
            room.box(f"{nm}OuterX",
                     (jx0 - 0.15) if nm.endswith("W") else jx1, 0.0, jz0 - 0.15,
                     jx0 if nm.endswith("W") else (jx1 + 0.15), 2.6, jz1,
                     "wall", None, 7)]))

    # Nav waypoints: one empty group per camera, at floor level in the middle
    # of its room. Godot interpolates hunters between these.
    for cam, key in sorted(CAM_ROOM.items()):
        (ox, oz), W, D, H = footprints[key]
        room.add(f"Nav_{cam}", [], origin=(ox, 0.0, oz))
    for cam, (ox, oz) in sorted(CAM_POINT.items()):
        room.add(f"Nav_{cam}", [], origin=(ox, 0.0, oz))

    problems = room.check() + OR.console_problems(room, prefix="Office_")
    path, png = room.save(out)
    xs = [c for e in room.elements for c in (e["from"][0], e["to"][0])]
    zs = [c for e in room.elements for c in (e["from"][2], e["to"][2])]
    print(f"wrote {path}\n     + {png}")
    print(f"  {len(room.elements)} cubes, {len(room.groups)} groups")
    print(f"  extent {(max(xs)-min(xs))/M:.1f} x {(max(zs)-min(zs))/M:.1f} m")
    for key, ((ox, oz), W, D, H) in footprints.items():
        cams = [c for c, k in CAM_ROOM.items() if k == key] or ["-"]
        print(f"    {key:11s} ({ox:+6.1f},{oz:+6.1f})  {W:4.1f} x {D:4.1f} m   {','.join(cams)}")
    print(f"  {len(CORRIDORS)} corridors, {len(CAM_ROOM)+len(CAM_POINT)} nav waypoints")
    # The console's plan is drawn from the building that was just placed, not
    # from a second copy of the layout kept in the Godot tree by hand.
    gd = None
    for i, a in enumerate(sys.argv):
        if a == "--gd":
            gd = LAY.write_gdscript(sys.argv[i + 1], footprints, CORRIDORS)
    if gd:
        print(f"  plan   {gd}")
    if problems:
        print(f"  !! {len(problems)} problems")
        for p in problems[:6]:
            print("     ", p)
        return 1
    print("  clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
