class_name CitySurface
extends RefCounted

## Batches every floor, wall, ceiling and small prop of one City chunk into three surfaces of one ArrayMesh:
## GROUND (floors, wet cobbles), SOLID (facades, kiosks, street furniture) and RIM (the dome's tall dark wall, which
## repeats its texture). Quads are written in chunk-local metres; tiles come from CityAtlas.

enum Mat { GROUND, SOLID, RIM }

const FACE_DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

static var _materials: Array = []

var _vertices := [PackedVector3Array(), PackedVector3Array(), PackedVector3Array()]
var _normals := [PackedVector3Array(), PackedVector3Array(), PackedVector3Array()]
var _uvs := [PackedVector2Array(), PackedVector2Array(), PackedVector2Array()]
var _indices := [PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]


static func materials() -> Array:
	if not _materials.is_empty():
		return _materials
	var albedo := load(CityAtlas.ALBEDO_PATH) as Texture2D
	var emission := load(CityAtlas.EMISSION_PATH) as Texture2D
	for roughness in [0.42, 0.92]:
		var material := StandardMaterial3D.new()
		material.albedo_texture = albedo
		material.emission_enabled = true
		material.emission_texture = emission
		material.emission_energy_multiplier = 1.05
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
		material.roughness = roughness
		_materials.append(material)
	var rim := StandardMaterial3D.new()
	rim.albedo_texture = load(CityAtlas.RIM_PATH) as Texture2D
	rim.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
	rim.roughness = 0.95
	_materials.append(rim)
	return _materials


func is_empty() -> bool:
	return (_vertices[0] as PackedVector3Array).is_empty() and (_vertices[1] as PackedVector3Array).is_empty() \
		and (_vertices[2] as PackedVector3Array).is_empty()


## A quad p0..p3 (bottom-left, bottom-right, top-right, top-left seen from the front) facing `normal`.
func quad(mat: int, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, normal: Vector3, tile: int,
		repeat_v: float = 1.0) -> void:
	var uv := CityAtlas.uv_rect(tile)
	var v: PackedVector3Array = _vertices[mat]
	var n: PackedVector3Array = _normals[mat]
	var t: PackedVector2Array = _uvs[mat]
	var idx: PackedInt32Array = _indices[mat]
	var base := v.size()
	v.append(p0); v.append(p1); v.append(p2); v.append(p3)
	for _i in 4:
		n.append(normal)
	if mat == Mat.RIM:
		t.append(Vector2(0, repeat_v)); t.append(Vector2(1, repeat_v)); t.append(Vector2(1, 0)); t.append(Vector2(0, 0))
	else:
		t.append(Vector2(uv.position.x, uv.end.y)); t.append(Vector2(uv.end.x, uv.end.y))
		t.append(Vector2(uv.end.x, uv.position.y)); t.append(Vector2(uv.position.x, uv.position.y))
	# Godot draws clockwise triangles as front faces.
	if (p1 - p0).cross(p2 - p0).dot(normal) > 0.0:
		idx.append(base); idx.append(base + 2); idx.append(base + 1)
		idx.append(base); idx.append(base + 3); idx.append(base + 2)
	else:
		idx.append(base); idx.append(base + 1); idx.append(base + 2)
		idx.append(base); idx.append(base + 2); idx.append(base + 3)


func floor_quad(x: int, z: int, tile: int, y: float = 0.0, mat: int = Mat.GROUND) -> void:
	quad(mat, Vector3(x, y, z + 1), Vector3(x + 1, y, z + 1), Vector3(x + 1, y, z), Vector3(x, y, z), Vector3.UP, tile)


func ceiling_quad(x: int, z: int, y: float, tile: int) -> void:
	quad(Mat.SOLID, Vector3(x, y, z), Vector3(x + 1, y, z), Vector3(x + 1, y, z + 1), Vector3(x, y, z + 1),
		Vector3.DOWN, tile)


func top_quad(x: int, z: int, y: float, tile: int) -> void:
	floor_quad(x, z, tile, y, Mat.SOLID)


## The face of cell (x, z) on side `dir`, from y0 to y1, one metre wide.
func wall_face(x: int, z: int, dir: Vector2i, y0: float, y1: float, tile: int, mat: int = Mat.SOLID,
		repeat_v: float = 1.0) -> void:
	var normal := Vector3(dir.x, 0, dir.y)
	var right := (-normal).cross(Vector3.UP)
	var center := Vector3(x + .5, 0, z + .5) + normal * .5
	quad(mat, center - right * .5 + Vector3(0, y0, 0), center + right * .5 + Vector3(0, y0, 0),
		center + right * .5 + Vector3(0, y1, 0), center - right * .5 + Vector3(0, y1, 0), normal, tile, repeat_v)


## An axis-aligned box (no underside): sides use `side_tile`, the top `top_tile`.
func box(origin: Vector3, size: Vector3, side_tile: int, top_tile: int = -1, mat: int = Mat.SOLID) -> void:
	var lo := origin
	var hi := origin + size
	var top := side_tile if top_tile < 0 else top_tile
	quad(mat, Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z),
		Vector3(lo.x, hi.y, hi.z), Vector3(0, 0, 1), side_tile)
	quad(mat, Vector3(hi.x, lo.y, lo.z), Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, hi.y, lo.z),
		Vector3(hi.x, hi.y, lo.z), Vector3(0, 0, -1), side_tile)
	quad(mat, Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z),
		Vector3(hi.x, hi.y, hi.z), Vector3(1, 0, 0), side_tile)
	quad(mat, Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z),
		Vector3(lo.x, hi.y, lo.z), Vector3(-1, 0, 0), side_tile)
	quad(mat, Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z),
		Vector3(lo.x, hi.y, lo.z), Vector3.UP, top)


func build() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var mats := materials()
	for mat in 3:
		var v: PackedVector3Array = _vertices[mat]
		if v.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = _normals[mat]
		arrays[Mesh.ARRAY_TEX_UV] = _uvs[mat]
		arrays[Mesh.ARRAY_INDEX] = _indices[mat]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mats[mat])
	return mesh
