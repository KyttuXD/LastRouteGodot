#!/usr/bin/env python3
"""
Renders a room .bbmodel to a PNG, so geometry and texturing can be checked
without opening Blockbench or a GPU.

Godot's --headless mode uses a dummy rasteriser and there is no xvfb here, so
neither can produce a picture. These rooms are only axis-aligned textured boxes
though, which a small z-buffered rasteriser handles exactly: the same face
vertex order and UV convention as bbmodel_to_glb, nearest-neighbour texture
sampling to preserve the pixel art, and flat per-face shading so extruded
detail reads as depth.

    python3 render_room.py model.bbmodel out.png [--cam x,y,z] [--look x,y,z]
"""
import json, base64, io, sys, math
import numpy as np
from PIL import Image

M = 64.0

_FACE_VERTS = {
    "north": lambda a, b: [(b[0], a[1], a[2]), (a[0], a[1], a[2]), (a[0], b[1], a[2]), (b[0], b[1], a[2])],
    "south": lambda a, b: [(a[0], a[1], b[2]), (b[0], a[1], b[2]), (b[0], b[1], b[2]), (a[0], b[1], b[2])],
    "east":  lambda a, b: [(b[0], a[1], b[2]), (b[0], a[1], a[2]), (b[0], b[1], a[2]), (b[0], b[1], b[2])],
    "west":  lambda a, b: [(a[0], a[1], a[2]), (a[0], a[1], b[2]), (a[0], b[1], b[2]), (a[0], b[1], a[2])],
    "up":    lambda a, b: [(a[0], b[1], b[2]), (b[0], b[1], b[2]), (b[0], b[1], a[2]), (a[0], b[1], a[2])],
    "down":  lambda a, b: [(a[0], a[1], a[2]), (b[0], a[1], a[2]), (b[0], a[1], b[2]), (a[0], a[1], b[2])],
}
_NORMALS = {"north": (0, 0, -1), "south": (0, 0, 1), "east": (1, 0, 0),
            "west": (-1, 0, 0), "up": (0, 1, 0), "down": (0, -1, 0)}
# Key light high and slightly to one side, so up-faces read brightest and the
# insides of recesses fall off -- the whole point of the extruded detail.
_LIGHT = np.array([0.45, 0.82, -0.35])
_LIGHT = _LIGHT / np.linalg.norm(_LIGHT)


def _rot(p, deg, origin):
    """Blockbench cube rotation, applied about the cube's own origin."""
    rx, ry, rz = [math.radians(d) for d in deg]
    p = np.array(p, float) - np.array(origin, float)
    if rx:
        c, s = math.cos(rx), math.sin(rx)
        p = np.array([p[0], c * p[1] - s * p[2], s * p[1] + c * p[2]])
    if ry:
        c, s = math.cos(ry), math.sin(ry)
        p = np.array([c * p[0] + s * p[2], p[1], -s * p[0] + c * p[2]])
    if rz:
        c, s = math.cos(rz), math.sin(rz)
        p = np.array([c * p[0] - s * p[1], s * p[0] + c * p[1], p[2]])
    return p + np.array(origin, float)


def _group_poses(model):
    """cube uuid -> (rotation, origin) inherited from its GROUP.

    Group rotation is what the glTF exporter turns into a node rotation, and it
    is the only rotation that survives export -- cube-level rotation is dropped
    because the exporter emits axis-aligned boxes. A preview that ignored it
    would therefore show something the engine never renders, which is the
    opposite of what this script is for."""
    groups = {g["uuid"]: g for g in model.get("groups", [])}
    poses = {}

    def walk(entry, parent):
        g = groups.get(entry.get("uuid"))
        if g is None:
            return
        rot = list(g.get("rotation") or [0, 0, 0])
        org = [c / M for c in (g.get("origin") or [0, 0, 0])]
        pose = (rot, org) if any(rot) else parent
        for child in entry.get("children", []):
            if isinstance(child, dict):
                walk(child, pose)
            elif pose is not None:
                poses[child] = pose

    for entry in model.get("outliner", []):
        if isinstance(entry, dict):
            walk(entry, None)
    return poses


def load(path):
    model = json.load(open(path))
    tex = (model.get("textures") or [None])[0]
    atlas = Image.open(io.BytesIO(base64.b64decode(
        tex["source"].split(",", 1)[1]))).convert("RGBA")
    poses = _group_poses(model)
    tris = []
    for el in model["elements"]:
        if el.get("type") != "cube":
            continue
        a = [c / M for c in el["from"]]
        b = [c / M for c in el["to"]]
        rot = el.get("rotation") or [0, 0, 0]
        org = [c / M for c in (el.get("origin") or [0, 0, 0])]
        g_rot, g_org = poses.get(el.get("uuid"), ([0, 0, 0], [0, 0, 0]))
        for face, fd in el["faces"].items():
            if fd.get("texture") is None or not fd.get("uv"):
                continue
            u0, v0, u1, v1 = fd["uv"]
            u0, u1 = min(u0, u1), max(u0, u1)
            v0, v1 = min(v0, v1), max(v0, v1)
            vs = _FACE_VERTS[face](a, b)
            if any(rot):
                vs = [_rot(v, rot, org) for v in vs]
            n = _rot(_NORMALS[face], rot, (0, 0, 0)) if any(rot) \
                else np.array(_NORMALS[face], float)
            if any(g_rot):
                vs = [_rot(v, g_rot, g_org) for v in vs]
                n = _rot(n, g_rot, (0, 0, 0))
            uvs = [(u0, v1), (u1, v1), (u1, v0), (u0, v0)]
            for i0, i1, i2 in ((0, 1, 2), (0, 2, 3)):
                tris.append((np.array([vs[i0], vs[i1], vs[i2]], float),
                             np.array([uvs[i0], uvs[i1], uvs[i2]], float), n))
    return tris, atlas


def render(tris, atlas, W=560, H=420, eye=(0, 1.6, -7.0), look=(0, 1.3, 0), fov=58.0):
    eye, look = np.array(eye, float), np.array(look, float)
    fwd = look - eye
    fwd /= np.linalg.norm(fwd)
    right = np.cross(fwd, np.array([0.0, 1.0, 0.0]))
    right /= np.linalg.norm(right)
    up = np.cross(right, fwd)
    f = (W / 2) / math.tan(math.radians(fov) / 2)

    tw, th = atlas.size
    tex = np.asarray(atlas, dtype=np.float32)
    color = np.zeros((H, W, 3), np.float32)
    zbuf = np.full((H, W), np.inf, np.float32)

    NEAR = 0.05

    def clip_near(cam, uvs):
        """Sutherland-Hodgman against the near plane, returning triangles.

        Rejecting any triangle with a vertex behind the camera -- which this
        used to do -- deletes the whole surface, and a room's floor is one
        large quad whose far end is usually behind you. That made floors
        vanish and read as holes in the preview when nothing was wrong with
        the model."""
        poly = [(cam[i], uvs[i]) for i in range(3)]
        out = []
        for i in range(len(poly)):
            cur, nxt = poly[i], poly[(i + 1) % len(poly)]
            cin, nin = cur[0][2] >= NEAR, nxt[0][2] >= NEAR
            if cin:
                out.append(cur)
            if cin != nin:
                t = (NEAR - cur[0][2]) / (nxt[0][2] - cur[0][2])
                out.append((cur[0] + (nxt[0] - cur[0]) * t,
                            cur[1] + (nxt[1] - cur[1]) * t))
        if len(out) < 3:
            return []
        return [(np.array([out[0][0], out[k][0], out[k + 1][0]]),
                 np.array([out[0][1], out[k][1], out[k + 1][1]]))
                for k in range(1, len(out) - 1)]

    for verts, uvs0, n in tris:
        rel = verts - eye
        cam0 = np.stack([rel @ right, rel @ up, rel @ fwd], axis=1)
        for cam, uvs in ([(cam0, uvs0)] if np.all(cam0[:, 2] >= NEAR)
                         else clip_near(cam0, uvs0)):
            sx = W / 2 + f * cam[:, 0] / cam[:, 2]
            sy = H / 2 - f * cam[:, 1] / cam[:, 2]
            x0, x1 = int(max(0, np.floor(sx.min()))), int(min(W - 1, np.ceil(sx.max())))
            y0, y1 = int(max(0, np.floor(sy.min()))), int(min(H - 1, np.ceil(sy.max())))
            if x1 < x0 or y1 < y0:
                continue
            ax, ay = sx[0], sy[0]
            e1 = (sx[1] - ax, sy[1] - ay)
            e2 = (sx[2] - ax, sy[2] - ay)
            det = e1[0] * e2[1] - e1[1] * e2[0]
            if abs(det) < 1e-9:
                continue
            ys, xs = np.mgrid[y0:y1 + 1, x0:x1 + 1]
            px, py = xs + 0.5 - ax, ys + 0.5 - ay
            w1 = (px * e2[1] - py * e2[0]) / det
            w2 = (py * e1[0] - px * e1[1]) / det
            w0 = 1.0 - w1 - w2
            inside = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
            if not inside.any():
                continue
            iz = w0 / cam[0, 2] + w1 / cam[1, 2] + w2 / cam[2, 2]
            z = 1.0 / np.where(iz == 0, 1e-9, iz)
            # perspective-correct UV
            u = (w0 * uvs[0, 0] / cam[0, 2] + w1 * uvs[1, 0] / cam[1, 2] + w2 * uvs[2, 0] / cam[2, 2]) * z
            v = (w0 * uvs[0, 1] / cam[0, 2] + w1 * uvs[1, 1] / cam[1, 2] + w2 * uvs[2, 1] / cam[2, 2]) * z
            sub = zbuf[y0:y1 + 1, x0:x1 + 1]
            win = inside & (z < sub)
            if not win.any():
                continue
            ui = np.clip(u[win].astype(int), 0, tw - 1)
            vi = np.clip(v[win].astype(int), 0, th - 1)
            texel = tex[vi, ui]
            vis = texel[:, 3] > 8                       # respect cut-out alpha
            if not vis.any():
                continue
            lam = 0.35 + 0.65 * max(0.0, float(np.dot(n, _LIGHT)))
            idx = np.where(win)
            iy, ix = idx[0][vis], idx[1][vis]
            color[y0 + iy, x0 + ix] = texel[vis, :3] * lam
            zbuf[y0 + iy, x0 + ix] = z[win][vis]
    return Image.fromarray(np.clip(color, 0, 255).astype(np.uint8))


def _vec(s):
    return tuple(float(x) for x in s.split(","))


if __name__ == "__main__":
    args = sys.argv[1:]
    src, dst = args[0], args[1]
    eye, look = (0, 1.6, -7.0), (0, 1.3, 0)
    for i, a in enumerate(args):
        if a == "--cam":
            eye = _vec(args[i + 1])
        if a == "--look":
            look = _vec(args[i + 1])
    tris, atlas = load(src)
    render(tris, atlas, eye=eye, look=look).save(dst)
    print(f"{dst}  {len(tris)} tris")
