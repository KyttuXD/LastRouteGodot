#!/usr/bin/env python3
"""
Geometry/model machinery shared by every Office Mode room.

Unit convention matches the hunter models: the Hytale character format uses 64
units per block and our hunters stand ~121 units (~1.9 m), so 64 units = 1
metre. Rooms are authored with the floor at Y=0 and centred on X/Z, matching
`art/props-3d/README.md`'s "1 grid tile = 1 metre, origin at base centre".
"""
import json, os, base64, io, hashlib
from room_paint import build_atlas, DENS, ATLAS, ALL_MATERIALS, TEAL

M = 64.0                     # units per metre
FACES = ("north", "south", "east", "west", "up", "down")

def _uuid(seed):
    h = hashlib.md5(seed.encode()).hexdigest()
    return f"{h[0:8]}-{h[8:12]}-{h[12:16]}-{h[16:20]}-{h[20:32]}"


class Room:
    """One room: cubes grouped into named bones, one packed texture atlas.

    Group names are the integration contract -- the Godot side finds parts by
    name to show simulation state, so they are chosen to describe what drives
    them, not what they look like."""

    def __init__(self, name, accent=TEAL, materials=None, seed=7, atlas=None,
                 rect_sets=None, atlas_size=None):
        self.name = name
        self.accent = accent
        if atlas is not None:
            # Merged-map mode: one shared atlas holding an accent variant per
            # room. `select()` switches which variant subsequent boxes sample.
            self.atlas = atlas
            self.rect_sets = rect_sets
            self.rects = next(iter(rect_sets.values()))
        else:
            self.atlas, self.rects = build_atlas(materials or ALL_MATERIALS, accent, seed)
            self.rect_sets = None
        self.atlas_size = atlas_size or self.atlas.size[0]
        self.elements, self.outliner, self.groups = [], [], []
        # Placement of the room currently being emitted, for merged maps:
        # (dx, dz) in metres and a quarter-turn count about Y.
        self.offset = (0.0, 0.0)
        self.turns = 0
        self.prefix = ""

    def select(self, key, offset=(0.0, 0.0), turns=0, prefix=""):
        """Point subsequent geometry at one room's accent, position and rotation."""
        if self.rect_sets:
            self.rects = self.rect_sets[key]
        self.offset = offset
        self.turns = turns % 4
        self.prefix = prefix

    # Rotating a room a quarter turn about Y sends each side wall to a new
    # compass direction, so the material chosen for a face has to follow it.
    _TURN = {"east": "north", "north": "west", "west": "south", "south": "east",
             "up": "up", "down": "down"}

    def _rot_face(self, face):
        for _ in range(self.turns):
            face = self._TURN[face]
        return face

    def _place(self, x, z):
        for _ in range(self.turns):
            x, z = z, -x
        return x + self.offset[0], z + self.offset[1]

    # -- texturing ---------------------------------------------------------
    def uv(self, mat, fw, fh, key):
        """Texture-pixel UV rect for one face.

        Pattern materials take a sub-rect at a fixed texels-per-metre density,
        so grain size stays constant whether the face is a 1.9 m wall stub or a
        full 6 m wall. Fitted materials map their whole patch."""
        x, y, w, h, kind = self.rects[mat]
        if kind == "fitted":
            return [x, y, x + w, y + h]
        uw = min(w, max(1.0, fw * DENS))
        uh = min(h, max(1.0, fh * DENS))
        seed = int(hashlib.md5(key.encode()).hexdigest()[:8], 16)
        ox = seed % max(1, int(w - uw) + 1)
        # Walls always sample from the top of the patch: the painter puts a
        # grime gradient down the panel, so a header stub must keep the clean
        # top end rather than a slice of floor grime.
        oy = 0 if mat == "wall" else (seed >> 8) % max(1, int(h - uh) + 1)
        return [x + ox, y + oy, x + ox + uw, y + oy + uh]

    # -- geometry ----------------------------------------------------------
    def box(self, name, x0, y0, z0, x1, y1, z1, mat="wall", overrides=None,
            color=0, rotation=None, origin=None):
        """Metres in, Blockbench units out. `mat` is the default material for
        all six faces; `overrides` re-materials specific ones."""
        x0, x1 = min(x0, x1), max(x0, x1)
        y0, y1 = min(y0, y1), max(y0, y1)
        z0, z1 = min(z0, z1), max(z0, z1)
        dx, dy, dz = x1 - x0, y1 - y0, z1 - z0
        dims = {"north": (dx, dy), "south": (dx, dy), "east": (dz, dy),
                "west": (dz, dy), "up": (dx, dz), "down": (dx, dz)}
        # Materials are chosen against the room's OWN axes, then the face keys
        # follow the room's rotation, so a wall keeps its art after a turn.
        faces = {}
        for f in FACES:
            m = (overrides or {}).get(f, mat)
            fw, fh = dims[f]
            faces[self._rot_face(f)] = {
                "uv": self.uv(m, fw, fh, self.name + self.prefix + name + f + m),
                "texture": 0}
        (px0, pz0), (px1, pz1) = self._place(x0, z0), self._place(x1, z1)
        x0, x1 = min(px0, px1), max(px0, px1)
        z0, z1 = min(pz0, pz1), max(pz0, pz1)
        rot = list(rotation or (0, 0, 0))
        org = list(origin or (0, 0, 0))
        for _ in range(self.turns):
            rot = [-rot[2], rot[1], rot[0]]
        if origin:
            ox, oz = self._place(org[0], org[2])
            org = [ox, org[1], oz]
        name = self.prefix + name
        return {
            "name": name, "box_uv": False, "render_order": "default", "locked": False,
            "export": True, "scope": 0, "allow_mirror_modeling": True,
            "shading_mode": "standard", "double_sided": False,
            "from": [x0 * M, y0 * M, z0 * M], "to": [x1 * M, y1 * M, z1 * M],
            # autouv MUST stay 0 -- with it on, Blockbench regenerates UVs on
            # load and silently discards every mapping computed above.
            "autouv": 0, "color": color, "stretch": [1, 1, 1], "inflate": 0,
            "origin": [o * M for o in org],
            "rotation": rot,
            "faces": faces, "type": "cube", "uuid": _uuid(self.name + name),
        }

    def add(self, group_name, parts, origin=(0, 0, 0), rotation=(0, 0, 0)):
        """A named bone holding `parts`.

        `rotation` is the GROUP's rotation, which the exporter turns into a
        glTF node rotation. Cube-level rotation is not a substitute: the
        exporter reads only `from`/`to` and emits axis-aligned boxes, so a cube
        tilted in Blockbench exports flat. Anything that has to be tilted in
        engine has to be tilted here, and its parts authored upright about this
        group's own origin."""
        group_name = self.prefix + group_name
        ox, oz = self._place(origin[0], origin[2])
        origin = (ox, origin[1], oz)
        rot = list(rotation)
        for _ in range(self.turns):
            rot = [-rot[2], rot[1], rot[0]]
        g = {
            "name": group_name, "uuid": _uuid(self.name + "grp" + group_name),
            "export": True, "locked": False, "scope": 0, "selected": False,
            "_static": {"properties": {}, "temp_data": {}},
            "origin": [o * M for o in origin], "rotation": rot, "color": 0,
            "is_piece": False, "original_position": [0, 0, 0],
            "original_offset": [0, 0, 0], "children": [], "reset": False,
            "shade": True, "mirror_uv": False, "visibility": True, "autouv": 0,
            "isOpen": True, "primary_selected": False,
        }
        self.groups.append(g)
        ids = []
        for p in parts:
            self.elements.append(p)
            ids.append(p["uuid"])
        self.outliner.append({"uuid": g["uuid"], "isOpen": True, "children": ids})
        return g

    # -- output ------------------------------------------------------------
    def save(self, out_path):
        os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
        png_path = os.path.splitext(out_path)[0] + ".png"
        self.atlas.save(png_path)
        buf = io.BytesIO()
        self.atlas.save(buf, format="PNG")
        b64 = base64.b64encode(buf.getvalue()).decode()
        base = os.path.basename(png_path)
        model = {
            "meta": {"format_version": "5.0", "model_format": "free", "box_uv": False},
            "name": self.name,
            "resolution": {"width": self.atlas_size, "height": self.atlas_size},
            "elements": self.elements,
            "groups": self.groups,
            "outliner": self.outliner,
            # id MUST equal the array index as a string: Blockbench resolves a
            # face's integer `texture` against each texture's id, not position.
            "textures": [{
                "path": png_path, "name": base, "folder": "", "namespace": "",
                "id": "0", "particle": False, "render_mode": "default",
                "render_sides": "auto", "frame_time": 1, "frame_order_type": "loop",
                "frame_order": "", "frame_interpolate": False, "visible": True,
                "internal": True, "saved": False, "uuid": _uuid(self.name + "tex"),
                "relative_path": "./" + base,
                "source": "data:image/png;base64," + b64,
            }],
        }
        with open(out_path, "w") as fh:
            json.dump(model, fh)
        return out_path, png_path

    # -- verification ------------------------------------------------------
    def check(self):
        """Catch the failure modes that have actually bitten this pipeline:
        autouv silently regenerating UVs, a face pointing at a texture index
        that does not exist, and UV rects running off the atlas."""
        problems = []
        for e in self.elements:
            if e["autouv"] != 0:
                problems.append(f"{e['name']}: autouv != 0")
            for f, v in e["faces"].items():
                if v["texture"] != 0:
                    problems.append(f"{e['name']}.{f}: texture != 0")
                u = v["uv"]
                sz = self.atlas_size
                if not (0 <= u[0] < u[2] <= sz and 0 <= u[1] < u[3] <= sz):
                    problems.append(f"{e['name']}.{f}: uv out of bounds {u}")
        return problems


def recessed_panel(room, group, x0, y0, x1, y1, z_front, inset=0.05,
                   proud=0.025, depth=0.05, face_mat="screen",
                   frame_mat="metal", color=3, facing="north"):
    """A screen or panel set BEHIND a raised bezel, instead of painted flat.

    The bezel bars run the full depth so they double as the cavity walls --
    what sells the recess is that the display plane is genuinely further back
    than the frame around it, so it catches light differently and casts into
    its own housing.

    `facing` names the side the panel is VIEWED from, as a Blockbench face key:
    "north" is the -Z side, "south" the +Z side. It is not cosmetic. Build it
    facing away and the recess forms on the wrong side (the display ends up
    flush with the bezel from where you actually stand), and the display's
    texture rect ends up on a face nobody sees."""
    s = 1.0 if facing == "south" else -1.0
    z_lip, z_back = z_front + s * proud, z_front - s * depth
    zf, zb = min(z_lip, z_back), max(z_lip, z_back)
    parts = [
        room.box(f"{group}BezelTop", x0, y1 - inset, zf, x1, y1, zb, frame_mat, None, 8),
        room.box(f"{group}BezelBot", x0, y0, zf, x1, y0 + inset, zb, frame_mat, None, 8),
        room.box(f"{group}BezelL", x0, y0, zf, x0 + inset, y1, zb, frame_mat, None, 8),
        room.box(f"{group}BezelR", x1 - inset, y0, zf, x1, y1, zb, frame_mat, None, 8),
    ]
    room.add(group, parts)
    # The display surface gets its OWN group, so it becomes its own glTF node
    # and can take its own material -- a live feed, an emissive screen. Merged
    # into the bezel group it would share the frame's material and could not
    # be driven separately.
    #
    # Every face takes the display material, not just the visible one. Godot's
    # material_override replaces the material on the WHOLE mesh but keeps each
    # face's own UVs, so a display whose sides carry frame-material UVs samples
    # the live texture at some unrelated few-pixel patch of the atlas. Making
    # the whole slab one material means the mesh's UV bounds ARE the display
    # rect, which is what lets the engine remap a viewport onto it exactly.
    z_face = z_back + s * 0.02
    fa, fb = min(z_back, z_face), max(z_back, z_face)
    room.add(f"{group}Screen", [
        room.box(f"{group}Face", x0 + inset, y0 + inset, fa,
                 x1 - inset, y1 - inset, fb, face_mat, None, color)])


def louvered_grille(room, group, x0, y0, x1, y1, z_front, slats=5,
                    depth=0.07, tilt=-22.0, slat_mat="metal", color=4):
    """Real angled slats over a dark back plate, replacing a painted vent.

    The gaps between slats are the point: they expose the `recess` plate set
    back behind them, so the dark stripes are actual depth the camera can see
    into rather than a texture that stays flat as the view moves."""
    parts = [room.box(f"{group}Back", x0, y0, z_front + depth,
                      x1, y1, z_front + depth + 0.02, "recess", None, 0)]
    pitch = (y1 - y0) / slats
    for i in range(slats):
        cy = y0 + pitch * (i + 0.5)
        h = pitch * 0.62
        parts.append(room.box(
            f"{group}Slat{i}", x0 + 0.02, cy - h / 2, z_front,
            x1 - 0.02, cy + h / 2, z_front + 0.03, slat_mat, None, color,
            rotation=(tilt, 0, 0), origin=(0, cy, z_front + 0.015)))
    room.add(group, parts)


def shell(room, w, d, h, t=0.15, floor_mat="floor", ceil_mat="ceiling",
          wall_mat="wall", ceiling=True, openings=()):
    """Floor, ceiling and four walls for a w x d x h metre box, floor at Y=0.

    `openings` cuts real doorways so rooms actually connect, rather than
    abutting as sealed boxes. Each entry is (wall, offset, width, height)
    where wall is one of north/south/east/west in the room's OWN axes and
    offset runs along that wall from its centre. The wall is emitted as a
    segment either side plus a header above, exactly like the office's own
    doorways -- a hunter has to be able to walk through this."""
    hw, hd = w / 2, d / 2
    room.add("Floor", [room.box("Floor", -hw, -t, -hd, hw, 0.0, hd,
                                wall_mat, {"up": floor_mat}, 6)])
    if ceiling:
        room.add("Ceiling", [room.box("Ceiling", -hw, h, -hd, hw, h + t, hd,
                                      wall_mat, {"down": ceil_mat}, 6)])

    cuts = {}
    for wall, off, ow, oh in openings:
        cuts.setdefault(wall, []).append((off, ow, oh))

    def run(wall, lo, hi, fixed0, fixed1, along_x):
        """Emit one wall as segments around its openings."""
        parts = []
        spans = sorted(cuts.get(wall, []))
        cursor = lo
        for i, (off, ow, oh) in enumerate(spans):
            a, b = off - ow / 2, off + ow / 2
            a, b = max(lo, a), min(hi, b)
            if a > cursor:
                parts.append((cursor, a, 0.0, h))
            parts.append((a, b, oh, h))          # header above the opening
            cursor = b
        if cursor < hi:
            parts.append((cursor, hi, 0.0, h))
        out = []
        for i, (p0, p1, y0, y1) in enumerate(parts):
            if p1 - p0 <= 1e-6 or y1 - y0 <= 1e-6:
                continue
            if along_x:
                out.append(room.box(f"Wall{wall.title()}{i}", p0, y0, fixed0,
                                    p1, y1, fixed1, wall_mat, None, 7))
            else:
                out.append(room.box(f"Wall{wall.title()}{i}", fixed0, y0, p0,
                                    fixed1, y1, p1, wall_mat, None, 7))
        return out

    room.add("Walls",
             run("north", -hw, hw, hd - t, hd, True)
             + run("south", -hw, hw, -hd, -hd + t, True)
             + run("west", -hd, hd, -hw, -hw + t, False)
             + run("east", -hd, hd, hw - t, hw, False))


def corridor(room, group, x0, z0, x1, z1, h=2.4, t=0.15, width=1.6, pad=(0.0, 0.0)):
    """A short connecting passage between two rooms, on the XZ plane.

    The camera graph links rooms that no rectangle layout can make share a
    wall (ELECTRICAL touches both vents; LOADING touches storage AND archive),
    so those links need an actual walkable tube rather than a wished-for
    adjacency."""
    # `pad` extends an end along the corridor's own axis. Two corridors meeting
    # at a right angle otherwise leave a square notch at the outer corner --
    # each one stops at the junction centre line, so neither covers it. Padding
    # the cornering end by half the width makes them overlap and fill it.
    along_x = abs(x1 - x0) >= abs(z1 - z0)
    p0, p1 = (pad, pad) if isinstance(pad, (int, float)) else pad
    # `pad` is given in ARGUMENT order (the pad for (x0,z0) then for (x1,z1)),
    # but a/b below are min/max. For any segment running in the negative
    # direction those are opposite, so the pads must be swapped to stay with
    # their own endpoint -- otherwise a corridor grows out of the wrong end,
    # burrowing into the room it should stop at and missing the junction it
    # was meant to reach.
    if along_x:
        a, b = min(x0, x1), max(x0, x1)
        lo_pad, hi_pad = (p0, p1) if x0 <= x1 else (p1, p0)
        a, b = a - lo_pad, b + hi_pad
        cz = (z0 + z1) / 2
        hwid = width / 2
        parts = [
            room.box(f"{group}Floor", a, -t, cz - hwid, b, 0.0, cz + hwid,
                     "wall", {"up": "floor"}, 6),
            room.box(f"{group}Ceil", a, h, cz - hwid, b, h + t, cz + hwid,
                     "wall", {"down": "ceiling"}, 6),
            room.box(f"{group}SideA", a, 0, cz - hwid - t, b, h, cz - hwid, "wall", None, 7),
            room.box(f"{group}SideB", a, 0, cz + hwid, b, h, cz + hwid + t, "wall", None, 7),
        ]
    else:
        a, b = min(z0, z1), max(z0, z1)
        lo_pad, hi_pad = (p0, p1) if z0 <= z1 else (p1, p0)
        a, b = a - lo_pad, b + hi_pad
        cx = (x0 + x1) / 2
        hwid = width / 2
        parts = [
            room.box(f"{group}Floor", cx - hwid, -t, a, cx + hwid, 0.0, b,
                     "wall", {"up": "floor"}, 6),
            room.box(f"{group}Ceil", cx - hwid, h, a, cx + hwid, h + t, b,
                     "wall", {"down": "ceiling"}, 6),
            room.box(f"{group}SideA", cx - hwid - t, 0, a, cx - hwid, h, b, "wall", None, 7),
            room.box(f"{group}SideB", cx + hwid, 0, a, cx + hwid + t, h, b, "wall", None, 7),
        ]
    room.add(group, parts)
