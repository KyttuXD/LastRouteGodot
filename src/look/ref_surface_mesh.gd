class_name RefSurfaceMesh
extends RefCounted

## Accumulates a chunk's visible floor, ceiling and wall quads into one
## ArrayMesh (two surfaces: floor+ceiling, walls). Replaces per-tile GridMap
## visuals; the GridMap stays only as the collision structure.


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


## Maze culling: one mesh per 15 x 15 cell tile (tile index -> ArrayMesh), so tiles no line of sight reaches can be
## hidden. Same geometry as build(), split by tile: every quad owns 4 consecutive vertices and 6 indices.
## Each tile's arrays are filled as locals: a packed array read back out of a Dictionary (`part["v"] as ...`) is a copy,
## so appending to it left every tile mesh empty (no walls, floors or ceilings at all with culling on).
func build_tiles(floor_material: Material, wall_material: Material) -> Dictionary:
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
