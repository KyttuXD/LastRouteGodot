class_name RefSurfaceMesh
extends RefCounted

## Accumulates a chunk's visible floor, ceiling and wall quads into one
## ArrayMesh (two surfaces: floor+ceiling, walls). Replaces per-tile GridMap
## visuals; the GridMap stays only as the collision structure.
## merge_adjacent() greedily joins coplanar unit quads with matching
## atlas layer + params before commit, cutting structural tris without changing
## collision (GridMap) or doorway openings.


# surface 0: floors + ceilings; surface 1: walls
var _v: Array[PackedVector3Array] = [PackedVector3Array(), PackedVector3Array()]
var _n: Array[PackedVector3Array] = [PackedVector3Array(), PackedVector3Array()]
var _uv: Array[PackedVector2Array] = [PackedVector2Array(), PackedVector2Array()]
var _uv2: Array[PackedVector2Array] = [PackedVector2Array(), PackedVector2Array()]
var _col: Array[PackedColorArray] = [PackedColorArray(), PackedColorArray()]
var _idx: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
## Maze culling: the TILE x TILE cell tile each quad's centre falls in, one entry per quad (6 indices), per surface.
const TILE := 15
var _quad_tile: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
var _merged := false


static func tile_of(centre: Vector3) -> int:
	return clampi(floori(centre.x / TILE), 0, 2) + 3 * clampi(floori(centre.z / TILE), 0, 2)


func _tag(surface: int, centre: Vector3) -> void:
	_quad_tile[surface].append(tile_of(centre))


func _quad(surface: int, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3,
		normal: Vector3, layer: float, params: Color) -> void:
	var base := _v[surface].size()
	_v[surface].append_array(PackedVector3Array([p0, p1, p2, p3]))
	_n[surface].append_array(PackedVector3Array([normal, normal, normal, normal]))
	_uv[surface].append_array(PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]))
	var l := Vector2(layer, 0)
	_uv2[surface].append_array(PackedVector2Array([l, l, l, l]))
	_col[surface].append_array(PackedColorArray([params, params, params, params]))
	# Godot front faces are clockwise as seen from the front: the cross product
	# of the first two edges must point against the normal.
	if (p1 - p0).cross(p2 - p0).dot(normal) < 0.0:
		_idx[surface].append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	else:
		_idx[surface].append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))
	_tag(surface, (p0 + p2) * .5)


func add_floor(x: int, z: int, layer: float, params: Color) -> void:
	_quad(0, Vector3(x, 0, z), Vector3(x + 1, 0, z), Vector3(x + 1, 0, z + 1),
		Vector3(x, 0, z + 1), Vector3.UP, layer, params)


## A floor quad through four arbitrary corners (a ramp's slope), facing up.
func add_quad_floor(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, layer: float, params: Color) -> void:
	var normal := (p3 - p0).cross(p1 - p0).normalized()
	if normal.y < 0.0:
		normal = -normal
	_quad(0, p0, p1, p2, p3, normal, layer, params)


## A floor quad at height `y` (the bed of a sewer channel below the walkways).
func add_floor_at(x: int, z: int, y: float, layer: float, params: Color) -> void:
	_quad(0, Vector3(x, y, z), Vector3(x + 1, y, z), Vector3(x + 1, y, z + 1),
		Vector3(x, y, z + 1), Vector3.UP, layer, params)


func add_ceiling(x: int, z: int, height: float, layer: float, params: Color) -> void:
	_quad(0, Vector3(x, height, z), Vector3(x + 1, height, z),
		Vector3(x + 1, height, z + 1), Vector3(x, height, z + 1),
		Vector3.DOWN, layer, params)


## A wall face on the side of cell (x, z) toward `dir` (a unit step), spanning
## y0..y1. `room_height` is the ceiling of the room the face looks into: the
## texture repeats one storey at a time from the floor up, so v is measured
## from the bottom of a whole number of storeys. `room_floor` is that room's
## floor (below 0 for a face whose room starts a storey down, e.g. a ramp
## tunnel's side walls on its upper level, so they carry on the paint of the
## level below without a cornice and skirting at the storey line). `tiers` > 0
## fixes the number of repeats (a ramp tunnel's wall paints once, floor to vault).
func add_wall(x: int, z: int, dir: Vector2i, layer: float, params: Color,
		y1: float, y0: float = 0.0, room_height: float = -1.0, room_floor: float = 0.0, tiers: int = 0) -> void:
	var a: Vector3
	var b: Vector3
	if dir == Vector2i(0, 1):
		a = Vector3(x, 0, z + 1)
		b = Vector3(x + 1, 0, z + 1)
	elif dir == Vector2i(0, -1):
		a = Vector3(x + 1, 0, z)
		b = Vector3(x, 0, z)
	elif dir == Vector2i(1, 0):
		a = Vector3(x + 1, 0, z + 1)
		b = Vector3(x + 1, 0, z)
	else:
		a = Vector3(x, 0, z)
		b = Vector3(x, 0, z + 1)
	# The painted wall (skirting to cornice) is stretched over each repeat of the
	# room's height, so the cornice always meets the ceiling.
	var full := (y1 if room_height < 0.0 else room_height) - room_floor
	var repeats := float(tiers if tiers > 0 else RefLook.wall_tiers(full))
	var v_top := repeats * (1.0 - (y1 - room_floor) / full)
	var v_bottom := repeats * (1.0 - (y0 - room_floor) / full)
	var base := _v[1].size()
	var n := Vector3(dir.x, 0, dir.y)
	_v[1].append_array(PackedVector3Array([a + Vector3(0, y1, 0), b + Vector3(0, y1, 0),
		b + Vector3(0, y0, 0), a + Vector3(0, y0, 0)]))
	_n[1].append_array(PackedVector3Array([n, n, n, n]))
	_uv[1].append_array(PackedVector2Array([Vector2(0, v_top), Vector2(1, v_top),
		Vector2(1, v_bottom), Vector2(0, v_bottom)]))
	var l := Vector2(layer, 0)
	_uv2[1].append_array(PackedVector2Array([l, l, l, l]))
	_col[1].append_array(PackedColorArray([params, params, params, params]))
	if (b - a).cross((b - a) + Vector3(0, y0 - y1, 0)).dot(n) < 0.0:
		_idx[1].append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	else:
		_idx[1].append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))
	_tag(1, (a + b) * .5 + n * .5)   # the open cell the face looks into


## join adjacent axis-aligned unit quads that share atlas layer + tint.
## Ramps / non-AA floors are left alone. UVs scale with metre size so tiling matches.
func merge_adjacent() -> void:
	while not merge_step(0x7FFFFFFFFFFFFFFF):
		pass


## the same greedy merge, resumable. Works until Time.get_ticks_usec() passes `deadline_usec` (checking the
## clock every MERGE_CHECK units, so every call makes progress) and returns true once both surfaces are merged.
## Streaming calls it once per frame so a chunk's merge (tens of ms on a laptop) never lands in one frame.
const MERGE_CHECK := 48
var _m_surface := 0
var _m_stage := 0
var _m_q := 0
var _m_groups := {}
var _m_singles: Array = []
var _m_keys: Array = []
var _m_ki := 0
var _k_v := PackedVector3Array()
var _k_n := PackedVector3Array()
var _k_uv := PackedVector2Array()
var _k_uv2 := PackedVector2Array()
var _k_col := PackedColorArray()
var _k_idx := PackedInt32Array()
var _k_tile := PackedInt32Array()


func merge_step(deadline_usec: int) -> bool:
	if _merged:
		return true
	var work := 0
	while _m_surface < 2:
		var surface := _m_surface
		var count := _quad_tile[surface].size()
		if _m_stage == 0:
			if count < 2:
				_m_surface += 1
				continue
			_m_groups = {}
			_m_singles = []
			_k_v = PackedVector3Array()
			_k_n = PackedVector3Array()
			_k_uv = PackedVector2Array()
			_k_uv2 = PackedVector2Array()
			_k_col = PackedColorArray()
			_k_idx = PackedInt32Array()
			_k_tile = PackedInt32Array()
			_m_q = 0
			_m_stage = 1
		if _m_stage == 1:
			# group mergeable unit quads; non-mergeable emit as-is
			while _m_q < count:
				_classify_quad(surface, _m_q)
				_m_q += 1
				work += 1
				if work % MERGE_CHECK == 0 and Time.get_ticks_usec() >= deadline_usec:
					return false
			for q in _m_singles:
				_append_quad_copy(surface, q, _k_v, _k_n, _k_uv, _k_uv2, _k_col, _k_idx, _k_tile)
			_m_keys = _m_groups.keys()
			_m_ki = 0
			_m_stage = 2
		if _m_stage == 2:
			while _m_ki < _m_keys.size():
				var list: Array = _m_groups[_m_keys[_m_ki]]
				_m_ki += 1
				_merge_group(surface, list)
				work += list.size()
				if work >= MERGE_CHECK and Time.get_ticks_usec() >= deadline_usec:
					return false
			_v[surface] = _k_v
			_n[surface] = _k_n
			_uv[surface] = _k_uv
			_uv2[surface] = _k_uv2
			_col[surface] = _k_col
			_idx[surface] = _k_idx
			_quad_tile[surface] = _k_tile
			_m_groups = {}
			_m_singles = []
			_m_keys = []
			_m_stage = 0
			_m_surface += 1
	_merged = true
	return true


func _classify_quad(surface: int, q: int) -> void:
	var first := q * 4
	var p0 := _v[surface][first]
	var p1 := _v[surface][first + 1]
	var p2 := _v[surface][first + 2]
	var p3 := _v[surface][first + 3]
	var n := _n[surface][first]
	var info := _unit_aa(p0, p1, p2, p3, n)
	if info.is_empty():
		_m_singles.append(q)
		return
	var layer := _uv2[surface][first].x
	var params := _col[surface][first]
	var tile := _quad_tile[surface][q]
	var key := "%d|%.4f|%.4f|%.4f|%.4f|%.5f|%s|%d|%d" % [
		surface, n.x, n.y, n.z, float(info["plane"]), layer,
		_color_key(params), tile, int(info["kind"])]
	if surface == 1:
		# walls also need matching v range + absolute y span
		key += "|%.5f|%.5f|%.5f|%.5f" % [
			_uv[surface][first].y, _uv[surface][first + 2].y,
			float(info["y0"]), float(info["y1"])]
	var list: Array = _m_groups.get(key, [])
	if list.is_empty():
		_m_groups[key] = list
	list.append({"q": q, "info": info, "n": n, "layer": layer, "params": params, "tile": tile,
		"v_top": _uv[surface][first].y, "v_bot": _uv[surface][first + 2].y})


func _merge_group(surface: int, list: Array) -> void:
	if list.size() == 1:
		_append_quad_copy(surface, int(list[0]["q"]), _k_v, _k_n, _k_uv, _k_uv2, _k_col, _k_idx, _k_tile)
		return
	var kind: int = int(list[0]["info"]["kind"])
	var cells := {}
	for entry in list:
		var cell: Vector2i = entry["info"]["cell"]
		cells[cell] = entry
	var remaining := cells.keys()
	remaining.sort_custom(func(a, b): return a.x < b.x or (a.x == b.x and a.y < b.y))
	var used := {}
	for start_value in remaining:
		var start: Vector2i = start_value
		if used.has(start):
			continue
		var w := 1
		while cells.has(Vector2i(start.x + w, start.y)) and not used.has(Vector2i(start.x + w, start.y)):
			w += 1
		var h := 1
		while true:
			var ok := true
			for dx in w:
				var c := Vector2i(start.x + dx, start.y + h)
				if not cells.has(c) or used.has(c):
					ok = false
					break
			if not ok:
				break
			h += 1
		for dx in w:
			for dy in h:
				used[Vector2i(start.x + dx, start.y + dy)] = true
		var sample: Dictionary = cells[start]
		_emit_merged(surface, kind, start, w, h, sample, _k_v, _k_n, _k_uv, _k_uv2, _k_col, _k_idx, _k_tile)


static func _color_key(c: Color) -> String:
	return "%.4f,%.4f,%.4f,%.4f" % [c.r, c.g, c.b, c.a]


## Returns {kind, cell, plane} for a unit axis-aligned quad, or {} if not mergeable.
## kind 0 = floor/ceiling (XZ), 1 = wall along Z (constant X), 2 = wall along X (constant Z).
static func _unit_aa(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3) -> Dictionary:
	var x0 := minf(minf(p0.x, p1.x), minf(p2.x, p3.x))
	var x1 := maxf(maxf(p0.x, p1.x), maxf(p2.x, p3.x))
	var y0 := minf(minf(p0.y, p1.y), minf(p2.y, p3.y))
	var y1 := maxf(maxf(p0.y, p1.y), maxf(p2.y, p3.y))
	var z0 := minf(minf(p0.z, p1.z), minf(p2.z, p3.z))
	var z1 := maxf(maxf(p0.z, p1.z), maxf(p2.z, p3.z))
	var eps := 0.02
	# Horizontal floor/ceiling: constant Y, 1x1 in XZ, normal mostly Y
	if absf(n.y) > .9 and y1 - y0 < eps and is_equal_approx(x1 - x0, 1.0) and is_equal_approx(z1 - z0, 1.0):
		return {"kind": 0, "cell": Vector2i(floori(x0 + eps), floori(z0 + eps)), "plane": y0}
	# Wall facing ±X: constant X, 1m in Z, vertical span any
	if absf(n.x) > .9 and x1 - x0 < eps and is_equal_approx(z1 - z0, 1.0):
		return {"kind": 1, "cell": Vector2i(0, floori(z0 + eps)), "plane": x0, "y0": y0, "y1": y1}
	# Wall facing ±Z: constant Z, 1m in X
	if absf(n.z) > .9 and z1 - z0 < eps and is_equal_approx(x1 - x0, 1.0):
		return {"kind": 2, "cell": Vector2i(floori(x0 + eps), 0), "plane": z0, "y0": y0, "y1": y1}
	return {}


func _append_quad_copy(surface: int, q: int, keep_v: PackedVector3Array, keep_n: PackedVector3Array,
		keep_uv: PackedVector2Array, keep_uv2: PackedVector2Array, keep_col: PackedColorArray,
		keep_idx: PackedInt32Array, keep_tile: PackedInt32Array) -> void:
	var first := q * 4
	var base := keep_v.size()
	keep_v.append_array(_v[surface].slice(first, first + 4))
	keep_n.append_array(_n[surface].slice(first, first + 4))
	keep_uv.append_array(_uv[surface].slice(first, first + 4))
	keep_uv2.append_array(_uv2[surface].slice(first, first + 4))
	keep_col.append_array(_col[surface].slice(first, first + 4))
	for i in _idx[surface].slice(q * 6, q * 6 + 6):
		keep_idx.append(i - first + base)
	keep_tile.append(_quad_tile[surface][q])


func _emit_merged(surface: int, kind: int, start: Vector2i, w: int, h: int, sample: Dictionary,
		keep_v: PackedVector3Array, keep_n: PackedVector3Array, keep_uv: PackedVector2Array,
		keep_uv2: PackedVector2Array, keep_col: PackedColorArray, keep_idx: PackedInt32Array,
		keep_tile: PackedInt32Array) -> void:
	var n: Vector3 = sample["n"]
	var layer: float = sample["layer"]
	var params: Color = sample["params"]
	var tile: int = sample["tile"]
	var plane: float = float(sample["info"]["plane"])
	var p0: Vector3
	var p1: Vector3
	var p2: Vector3
	var p3: Vector3
	var u0 := 0.0
	var u1 := 1.0
	var v0 := 0.0
	var v1 := 1.0
	if kind == 0:
		# XZ rectangle at y=plane; start is min corner cell, w along X, h along Z
		p0 = Vector3(start.x, plane, start.y)
		p1 = Vector3(start.x + w, plane, start.y)
		p2 = Vector3(start.x + w, plane, start.y + h)
		p3 = Vector3(start.x, plane, start.y + h)
		u1 = float(w)
		v1 = float(h)
		if n.y < 0.0:
			# ceiling faces down: flip winding helper via _quad_push
			pass
	elif kind == 1:
		# constant X=plane, cell.y is Z; for walls we only expand along Z (w), h must be 1 in cell space
		# Our greedy used cell (0,z) with expand in x as w and y as h — for kind 1 cell.x is always 0,
		# so w is unused axis junk. Re-do: cell is Vector2i(0, z), expand only along z (the .y of cell).
		# When kind==1, start.x is 0, start.y is z0, w expands fake x (always 1 cell wide in x-key),
		# Actually cells are Vector2i(0, z) so greedy w expands x which are all 0 — only one column.
		# Expand h along z. Good: start.y = z0, h = length along Z, w should be 1.
		var z0 := start.y
		var z1 := start.y + h
		var y0: float = float(sample["info"].get("y0", 0.0))
		var y1: float = float(sample["info"].get("y1", 1.0))
		# Match add_wall corner order for +X / -X via normal sign
		if n.x > 0.0:
			p0 = Vector3(plane, y1, z1)
			p1 = Vector3(plane, y1, z0)
			p2 = Vector3(plane, y0, z0)
			p3 = Vector3(plane, y0, z1)
		else:
			p0 = Vector3(plane, y1, z0)
			p1 = Vector3(plane, y1, z1)
			p2 = Vector3(plane, y0, z1)
			p3 = Vector3(plane, y0, z0)
		u1 = float(h)
		v0 = float(sample["v_top"])
		v1 = float(sample["v_bot"])
	else:
		# kind 2: constant Z=plane, cell.x is X; expand w along X
		var x0 := start.x
		var x1 := start.x + w
		var y0b: float = float(sample["info"].get("y0", 0.0))
		var y1b: float = float(sample["info"].get("y1", 1.0))
		if n.z > 0.0:
			p0 = Vector3(x0, y1b, plane)
			p1 = Vector3(x1, y1b, plane)
			p2 = Vector3(x1, y0b, plane)
			p3 = Vector3(x0, y0b, plane)
		else:
			p0 = Vector3(x1, y1b, plane)
			p1 = Vector3(x0, y1b, plane)
			p2 = Vector3(x0, y0b, plane)
			p3 = Vector3(x1, y0b, plane)
		u1 = float(w)
		v0 = float(sample["v_top"])
		v1 = float(sample["v_bot"])
	var base := keep_v.size()
	keep_v.append_array(PackedVector3Array([p0, p1, p2, p3]))
	keep_n.append_array(PackedVector3Array([n, n, n, n]))
	keep_uv.append_array(PackedVector2Array([Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]))
	var l := Vector2(layer, 0)
	keep_uv2.append_array(PackedVector2Array([l, l, l, l]))
	keep_col.append_array(PackedColorArray([params, params, params, params]))
	if (p1 - p0).cross(p2 - p0).dot(n) < 0.0:
		keep_idx.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	else:
		keep_idx.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))
	keep_tile.append(tile)


## Maze culling: one mesh per 15 x 15 cell tile (tile index -> ArrayMesh), so tiles no line of sight reaches can be
## hidden. Same geometry as build(), split by tile: every quad owns 4 consecutive vertices and 6 indices.
## Each tile's arrays are filled as locals: a packed array read back out of a Dictionary (`part["v"] as ...`) is a copy,
## so appending to it left every tile mesh empty (no walls, floors or ceilings at all with culling on).
func build_tiles(floor_material: Material, wall_material: Material) -> Dictionary:
	merge_adjacent()
	var out := {}
	var materials := [floor_material, wall_material]
	var quads := {}   # tile -> [floor quad indices, wall quad indices] (plain Arrays: shared, not copied)
	for surface in 2:
		for q in _quad_tile[surface].size():
			var t := _quad_tile[surface][q]
			if not quads.has(t):
				quads[t] = [[], []]
			((quads[t] as Array)[surface] as Array).append(q)
	for t in quads:
		var mesh := ArrayMesh.new()
		for surface in 2:
			var list: Array = (quads[t] as Array)[surface]
			if list.is_empty():
				continue
			var v := PackedVector3Array()
			var n := PackedVector3Array()
			var uv := PackedVector2Array()
			var uv2 := PackedVector2Array()
			var col := PackedColorArray()
			var idx := PackedInt32Array()
			for q_value in list:
				var q: int = q_value
				var first := q * 4
				var base := v.size()
				v.append_array(_v[surface].slice(first, first + 4))
				n.append_array(_n[surface].slice(first, first + 4))
				uv.append_array(_uv[surface].slice(first, first + 4))
				uv2.append_array(_uv2[surface].slice(first, first + 4))
				col.append_array(_col[surface].slice(first, first + 4))
				for i in _idx[surface].slice(q * 6, q * 6 + 6):
					idx.append(i - first + base)
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = v
			arrays[Mesh.ARRAY_NORMAL] = n
			arrays[Mesh.ARRAY_TEX_UV] = uv
			arrays[Mesh.ARRAY_TEX_UV2] = uv2
			arrays[Mesh.ARRAY_COLOR] = col
			arrays[Mesh.ARRAY_INDEX] = idx
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(mesh.get_surface_count() - 1, materials[surface])
		out[t] = mesh
	return out


func build(floor_material: Material, wall_material: Material) -> ArrayMesh:
	merge_adjacent()
	var mesh := ArrayMesh.new()
	var materials := [floor_material, wall_material]
	for surface in 2:
		if _v[surface].is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _v[surface]
		arrays[Mesh.ARRAY_NORMAL] = _n[surface]
		arrays[Mesh.ARRAY_TEX_UV] = _uv[surface]
		arrays[Mesh.ARRAY_TEX_UV2] = _uv2[surface]
		arrays[Mesh.ARRAY_COLOR] = _col[surface]
		arrays[Mesh.ARRAY_INDEX] = _idx[surface]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, materials[surface])
	return mesh
