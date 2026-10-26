class_name RefSurfaceMesh
extends RefCounted

## Accumulates a chunk's visible floor, ceiling and wall quads into one
## ArrayMesh (two surfaces: floor+ceiling, walls). Replaces per-tile GridMap
## visuals; the GridMap stays only as the collision structure.

const WALL_H := 3.88
const CEILING_Y := 3.78

# surface 0: floors + ceilings; surface 1: walls
var _v: Array[PackedVector3Array] = [PackedVector3Array(), PackedVector3Array()]
var _n: Array[PackedVector3Array] = [PackedVector3Array(), PackedVector3Array()]
var _uv: Array[PackedVector2Array] = [PackedVector2Array(), PackedVector2Array()]
var _uv2: Array[PackedVector2Array] = [PackedVector2Array(), PackedVector2Array()]
var _col: Array[PackedColorArray] = [PackedColorArray(), PackedColorArray()]
var _idx: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]


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


func add_floor(x: int, z: int, layer: float, params: Color) -> void:
	_quad(0, Vector3(x, 0, z), Vector3(x + 1, 0, z), Vector3(x + 1, 0, z + 1),
		Vector3(x, 0, z + 1), Vector3.UP, layer, params)


func add_ceiling(x: int, z: int, layer: float, params: Color) -> void:
	_quad(0, Vector3(x, CEILING_Y, z), Vector3(x + 1, CEILING_Y, z),
		Vector3(x + 1, CEILING_Y, z + 1), Vector3(x, CEILING_Y, z + 1),
		Vector3.DOWN, layer, params)


## A wall face on the side of cell (x, z) toward `dir` (a unit step). Texture
## v runs 0 at the top to 1 at the floor.
func add_wall(x: int, z: int, dir: Vector2i, layer: float, params: Color) -> void:
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
	var up := Vector3(0, WALL_H, 0)
	# corners: top-left, top-right, bottom-right, bottom-left as seen from the room
	_quad(1, a + up, b + up, b, a, Vector3(dir.x, 0, dir.y), layer, params)


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
