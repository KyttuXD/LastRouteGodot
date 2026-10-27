#!/usr/bin/env python3
"""Convert an OSM clip into a Last Route City map (format LRCM1, see docs/CITY_OSM_MAPS.md).

Input is GeoJSON sequence written by osmium-tool (already installed on VPS 2, so no pyosmium is needed):

  osmium export --geometry-types=point,linestring,polygon -f geojsonseq -a type,id \\
      -o clip.geojsonseq clip.osm.pbf

  python3 -I osm_city_convert.py clip.geojsonseq OUT_DIR --name "Lower Manhattan" \\
      --bbox 40.7020,-74.0160,40.7110,-74.0040 [--version 1]

Standard library only. Deterministic: the same input and arguments give byte-identical output.
The output is OSM-derived (ODbL); it is never committed to the repo or bundled with the game."""
import argparse, base64, gzip, hashlib, json, math, os, struct, sys, zlib

CHUNK = 45
# Cell kinds = CityLayout constants (src/game/city_layout.gd), so the City renderer and route code read them unchanged.
RIM, ROAD, PAVE, PLAZA, GRASS, PATH, WATER, WALL, FLOOR, DOOR, HEDGE = 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
CROSS_NS, CROSS_EW, BRIDGE, ALLEY = 13, 14, 17, 19

# highway class -> (carriageway width m, pavement each side m, kind)
ROAD_CLASSES = {
    "motorway": (14, 0, ROAD), "trunk": (12, 2, ROAD), "primary": (11, 3, ROAD), "secondary": (9, 3, ROAD),
    "tertiary": (8, 2, ROAD), "unclassified": (6, 2, ROAD), "residential": (6, 2, ROAD), "living_street": (5, 1, ROAD),
    "motorway_link": (6, 0, ROAD), "trunk_link": (6, 0, ROAD), "primary_link": (6, 1, ROAD),
    "secondary_link": (6, 1, ROAD), "tertiary_link": (5, 1, ROAD), "service": (4, 0, ALLEY),
    "pedestrian": (6, 0, PLAZA), "footway": (2, 0, PATH), "path": (2, 0, PATH), "cycleway": (2, 0, PATH),
    "steps": (2, 0, PATH),
}
GREEN = {("leisure", "park"), ("leisure", "garden"), ("leisure", "pitch"), ("landuse", "grass"),
         ("landuse", "recreation_ground"), ("landuse", "cemetery"), ("natural", "wood"), ("natural", "scrub")}
PLAZA_AREAS = {("place", "square"), ("highway", "pedestrian"), ("amenity", "parking")}
LEVEL_M = 3.2
MAX_HEIGHT_M = 250.0


class Proj:
    """lat/lon -> cells (1 m). +x east, +z south; cell (0,0) is the bbox north-west corner."""
    def __init__(self, s, w, n, e):
        self.lat0, self.lon0 = n, w
        self.m_lat = 110574.0
        self.m_lon = 111320.0 * math.cos(math.radians((s + n) / 2))
        self.width = int(math.ceil((e - w) * self.m_lon / CHUNK)) * CHUNK
        self.height = int(math.ceil((n - s) * self.m_lat / CHUNK)) * CHUNK

    def fwd(self, lon, lat):
        return (lon - self.lon0) * self.m_lon, (self.lat0 - lat) * self.m_lat


def height_of(props):
    def num(v):
        try:
            return float(str(v).split(";")[0].replace("m", "").strip())
        except ValueError:
            return None
    h = num(props.get("height", ""))
    if h is None:
        lv = num(props.get("building:levels", ""))
        h = lv * LEVEL_M + 1.0 if lv else None
    if h is None:
        h = 12.0  # unknown: a 4-storey block
    return max(4.0, min(MAX_HEIGHT_M, h))


class Raster:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.kind = bytearray([PAVE]) * (w * h)   # an urban default: open pavement between features
        self.prio = bytearray(w * h)
        self.bid = [0] * (w * h)                 # building number + 1

    def put(self, x, z, kind, prio, bid=0):
        if 0 <= x < self.w and 0 <= z < self.h:
            i = z * self.w + x
            if prio >= self.prio[i]:
                self.kind[i] = kind; self.prio[i] = prio
                if bid: self.bid[i] = bid

    def polygon(self, rings, kind, prio, bid=0):
        """Even-odd scanline fill of cell centres; rings = list of [(x, z), ...] (outer + holes)."""
        zs = [p[1] for r in rings for p in r]
        z0, z1 = max(0, int(math.floor(min(zs)))), min(self.h - 1, int(math.ceil(max(zs))))
        cells = []
        for z in range(z0, z1 + 1):
            cz = z + 0.5
            xs = []
            for r in rings:
                for (ax, az), (bx, bz) in zip(r, r[1:] + r[:1]):
                    if (az <= cz < bz) or (bz <= cz < az):
                        xs.append(ax + (cz - az) * (bx - ax) / (bz - az))
            xs.sort()
            for a, b in zip(xs[0::2], xs[1::2]):
                for x in range(max(0, int(math.ceil(a - 0.5))), min(self.w - 1, int(math.floor(b - 0.5))) + 1):
                    self.put(x, z, kind, prio, bid); cells.append((x, z))
        return cells

    def thick_line(self, pts, half, kind, prio):
        for (ax, az), (bx, bz) in zip(pts, pts[1:]):
            x0, x1 = int(min(ax, bx) - half - 1), int(max(ax, bx) + half + 1)
            z0, z1 = int(min(az, bz) - half - 1), int(max(az, bz) + half + 1)
            dx, dz = bx - ax, bz - az
            ll = dx * dx + dz * dz or 1e-9
            for z in range(max(0, z0), min(self.h - 1, z1) + 1):
                for x in range(max(0, x0), min(self.w - 1, x1) + 1):
                    px, pz = x + 0.5 - ax, z + 0.5 - az
                    t = max(0.0, min(1.0, (px * dx + pz * dz) / ll))
                    ex, ez = px - t * dx, pz - t * dz
                    if ex * ex + ez * ez <= half * half:
                        self.put(x, z, kind, prio)


def rings_of(geom, proj):
    t = geom["type"]
    polys = [geom["coordinates"]] if t == "Polygon" else geom["coordinates"] if t == "MultiPolygon" else []
    return [[[proj.fwd(*c) for c in ring[:-1]] for ring in poly] for poly in polys]


PREVIEW_COLORS = {RIM: (14, 14, 20), ROAD: (60, 60, 68), PAVE: (120, 118, 112), PLAZA: (150, 138, 120),
                  GRASS: (70, 120, 60), PATH: (160, 150, 110), WATER: (40, 80, 130), BRIDGE: (120, 90, 70),
                  ALLEY: (80, 78, 80)}


def png_preview(r, buildings, boundary, size):
    """Small top-down minimap (RGB PNG, stdlib only): ground colours, buildings shaded by height, boundary in yellow."""
    by_id = {b["id"]: b for b in buildings}
    scale = max(r.w, r.h) / size
    w, h = max(1, int(r.w / scale)), max(1, int(r.h / scale))
    rows = []
    for py in range(h):
        row = bytearray([0])
        for px in range(w):
            i = int(py * scale) * r.w + int(px * scale)
            b = by_id.get(r.bid[i])
            if b and r.kind[i] in (WALL, DOOR):
                t = min(1.0, b["height"] / 120.0)
                c = (int(150 + 90 * t), int(120 + 60 * t), int(110 + 30 * t))
            else:
                c = PREVIEW_COLORS.get(r.kind[i], (110, 108, 104))
            row += bytes(c)
        rows.append(row)
    for rings in boundary:
        ring = rings[0]
        for (ax, az), (bx, bz) in zip(ring, ring[1:] + ring[:1]):
            n = int(max(abs(bx - ax), abs(bz - az)) / scale) + 1
            for k in range(n + 1):
                x = int((ax + (bx - ax) * k / n) / scale); z = int((az + (bz - az) * k / n) / scale)
                if 0 <= x < w and 0 <= z < h:
                    rows[z][1 + 3 * x:4 + 3 * x] = bytes((250, 210, 60))
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    raw = b"".join(bytes(row) for row in rows)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src"); ap.add_argument("out")
    ap.add_argument("--name", required=True); ap.add_argument("--id", default="")
    ap.add_argument("--bbox", required=True, help="south,west,north,east")
    ap.add_argument("--version", type=int, default=1)
    ap.add_argument("--max-km2", type=float, default=2.0)
    ap.add_argument("--boundary", help="GeoJSON file with the (Multi)Polygon outline; cells outside become RIM")
    ap.add_argument("--meta", default="{}", help="JSON catalog metadata copied into the manifest (city, state, ...)")
    a = ap.parse_args()
    s, w, n, e = map(float, a.bbox.split(","))
    proj = Proj(s, w, n, e)
    area = proj.width * proj.height / 1e6
    if area > a.max_km2:
        sys.exit("area %.2f km2 is over the %.1f km2 limit" % (area, a.max_km2))
    feats = []
    with open(a.src) as f:
        for line in f:
            line = line.strip().lstrip("\x1e")
            if line:
                feats.append(json.loads(line))
    feats.sort(key=lambda ft: (ft["properties"].get("@type", ""), ft["properties"].get("@id", 0), ft["geometry"]["type"]))
    r = Raster(proj.width, proj.height)
    buildings, shops, roads = [], [], []

    def inside(xs, zs, pad=10):
        return max(xs) >= -pad and min(xs) <= proj.width + pad and max(zs) >= -pad and min(zs) <= proj.height + pad

    # pass 1: areas (water < green < plaza), then roads, then buildings last (they win)
    for ft in feats:
        p, g = ft["properties"], ft["geometry"]
        if g["type"] not in ("Polygon", "MultiPolygon") or "building" in p or "building:part" in p:
            continue
        kind = None
        if p.get("natural") == "water" or p.get("waterway") == "riverbank" or p.get("water"):
            kind, prio = WATER, 1
        elif any((k, p.get(k)) in GREEN for k in ("leisure", "landuse", "natural")):
            kind, prio = GRASS, 2
        elif any((k, p.get(k)) in PLAZA_AREAS for k in ("place", "highway", "amenity")):
            kind, prio = PLAZA, 3
        if kind is None:
            continue
        for rings in rings_of(g, proj):
            if inside([q[0] for q in rings[0]], [q[1] for q in rings[0]]):
                r.polygon(rings, kind, prio)
    for ft in feats:
        p, g = ft["properties"], ft["geometry"]
        hw = p.get("highway")
        if g["type"] != "LineString" or hw not in ROAD_CLASSES:
            continue
        pts = [proj.fwd(*c) for c in g["coordinates"]]
        if not inside([q[0] for q in pts], [q[1] for q in pts]):
            continue
        width, pave, kind = ROAD_CLASSES[hw]
        if p.get("tunnel") in ("yes", "building_passage"):
            continue  # underground: not drawn on level 0
        bridge = p.get("bridge") not in (None, "no")
        if pave and not bridge:
            r.thick_line(pts, width / 2 + pave, PAVE, 4)
        r.thick_line(pts, width / 2, BRIDGE if bridge else kind, 5 if kind != PATH else 4)
        roads.append({"osm": p.get("@id"), "class": hw, "name": p.get("name", ""), "oneway": p.get("oneway") == "yes",
                      "bridge": bridge, "width": width,
                      "pts": [[round(x, 1), round(z, 1)] for x, z in pts]})
    door_nodes = []
    for ft in feats:
        p, g = ft["properties"], ft["geometry"]
        if g["type"] == "Point":
            x, z = proj.fwd(*g["coordinates"])
            if not (0 <= x < proj.width and 0 <= z < proj.height):
                continue
            if "entrance" in p or p.get("door"):
                door_nodes.append((int(x), int(z)))
            if "shop" in p or p.get("amenity") in ("cafe", "restaurant", "fast_food", "bank", "pharmacy", "bar"):
                shops.append({"osm": p.get("@id"), "cell": [int(x), int(z)], "kind": p.get("shop") or p.get("amenity"),
                              "name": p.get("name", "")})
    for ft in feats:
        p, g = ft["properties"], ft["geometry"]
        if g["type"] not in ("Polygon", "MultiPolygon") or "building" not in p:
            continue
        for rings in rings_of(g, proj):
            if not inside([q[0] for q in rings[0]], [q[1] for q in rings[0]], 0):
                continue
            bid = len(buildings) + 1
            cells = r.polygon(rings, WALL, 9, bid)
            if len(cells) < 4:
                continue
            xs, zs = [c[0] for c in cells], [c[1] for c in cells]
            lv = p.get("building:levels")
            buildings.append({"id": bid, "osm": p.get("@id"), "type": p.get("building"), "name": p.get("name", ""),
                              "height": round(height_of(p), 1), "levels": lv or "", "min_height": p.get("min_height", ""),
                              "rect": [min(xs), min(zs), max(xs) - min(xs) + 1, max(zs) - min(zs) + 1],
                              "cells": len(cells), "doors": []})
    # doors: OSM entrance nodes inside a footprint win; otherwise the wall cell nearest the building centre that faces
    # open ground (the CityDoor hook); one per building.
    by_id = {b["id"]: b for b in buildings}
    for x, z in door_nodes:
        for dx, dz in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
            xx, zz = x + dx, z + dz
            if 0 <= xx < r.w and 0 <= zz < r.h and r.bid[zz * r.w + xx] in by_id:
                b = by_id[r.bid[zz * r.w + xx]]
                if [xx, zz] not in b["doors"]:
                    b["doors"].append([xx, zz]); r.kind[zz * r.w + xx] = DOOR
                break
    for b in buildings:
        if b["doors"]:
            continue
        bx, bz, bw, bh = b["rect"]
        cx, cz = bx + bw / 2, bz + bh / 2
        best = None
        for z in range(bz, bz + bh):
            for x in range(bx, bx + bw):
                if r.bid[z * r.w + x] != b["id"]:
                    continue
                for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    xx, zz = x + dx, z + dz
                    if 0 <= xx < r.w and 0 <= zz < r.h and r.kind[zz * r.w + xx] in (PAVE, ROAD, PLAZA, ALLEY, PATH):
                        d = (x - cx) ** 2 + (z - cz) ** 2
                        if best is None or d < best[0]:
                            best = (d, x, z)
        if best:
            b["doors"].append([best[1], best[2]]); r.kind[best[2] * r.w + best[1]] = DOOR
    boundary = []
    if a.boundary:
        gj = json.load(open(a.boundary))
        geoms = [f["geometry"] for f in gj.get("features", [gj])] if gj.get("type") == "FeatureCollection" else [gj.get("geometry", gj)]
        for g in geoms:
            boundary += rings_of(g, proj)
        mask = Raster(proj.width, proj.height)
        mask.kind = bytearray(proj.width * proj.height)
        for rings in boundary:
            mask.polygon(rings, 1, 1)
        for i in range(proj.width * proj.height):
            if not mask.kind[i]:
                r.kind[i] = RIM; r.bid[i] = 0
        keep = {r.bid[i] for i in range(proj.width * proj.height)}
        buildings[:] = [b for b in buildings if b["id"] in keep]
        by_id = {b["id"]: b for b in buildings}
    os.makedirs(a.out, exist_ok=True)
    preview = png_preview(r, buildings, boundary, 160)
    cw, ch = proj.width // CHUNK, proj.height // CHUNK
    chunks = {}
    for cz in range(ch):
        for cx in range(cw):
            kinds = bytearray(); heights = bytearray()
            for z in range(cz * CHUNK, cz * CHUNK + CHUNK):
                row = slice(z * r.w + cx * CHUNK, z * r.w + cx * CHUNK + CHUNK)
                kinds += r.kind[row]
                for bid in r.bid[row]:
                    heights.append(min(255, int(round(by_id[bid]["height"]))) if bid in by_id else 0)
            raw = b"LRC1" + struct.pack("<HH", CHUNK, CHUNK) + bytes(kinds) + bytes(heights)
            data = gzip.compress(raw, mtime=0)
            name = "c_%d_%d.bin" % (cx, cz)
            with open(os.path.join(a.out, name), "wb") as f:
                f.write(data)
            chunks["%d_%d" % (cx, cz)] = hashlib.sha256(data).hexdigest()
    side = {"buildings": buildings, "shops": shops, "roads": roads}
    side_bytes = gzip.compress(json.dumps(side, separators=(",", ":"), sort_keys=True).encode(), mtime=0)
    with open(os.path.join(a.out, "features.json.gz"), "wb") as f:
        f.write(side_bytes)
    manifest = {
        "format": "LRCM1", "id": a.id or a.name.lower().replace(" ", "-"), "name": a.name, "version": a.version,
        "bbox": {"south": s, "west": w, "north": n, "east": e},
        "size_cells": [proj.width, proj.height], "chunk": CHUNK, "chunks_xz": [cw, ch],
        "attribution": "Map data © OpenStreetMap contributors, ODbL 1.0 (openstreetmap.org/copyright)",
        "licence": "ODbL-1.0", "source": os.path.basename(a.src), "meta": json.loads(a.meta),
        "shape": "boundary" if boundary else "bbox",
        "boundary_cells": [[[round(x), round(z)] for x, z in ring] for rings in boundary for ring in rings[:1]][:8],
        "preview_png": base64.b64encode(preview).decode(),
        "stats": {"buildings": len(buildings), "roads": len(roads), "shops": len(shops), "area_km2": round(area, 3)},
        "files": dict(sorted({**{"c_%s.bin" % k: v for k, v in chunks.items()},
                              "features.json.gz": hashlib.sha256(side_bytes).hexdigest()}.items())),
    }
    with open(os.path.join(a.out, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1, sort_keys=True)
    print("%s: %dx%d cells, %d chunks, %d buildings, %d roads, %d shops" % (
        a.name, proj.width, proj.height, len(chunks), len(buildings), len(roads), len(shops)))


if __name__ == "__main__":
    main()
