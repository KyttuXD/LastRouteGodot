class_name CitySurface
extends RefCounted

## Batches every floor, wall, ceiling and small prop of one City chunk into three surfaces of one ArrayMesh:
## GROUND (floors, wet cobbles), SOLID (facades, kiosks, street furniture) and RIM (the dome's tall dark wall, which
## repeats its texture). Quads are written in chunk-local metres; tiles come from CityAtlas.

enum Mat { GROUND, SOLID, RIM }

const FACE_DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

const TILE_SHADER_CODE := """
shader_type spatial;
// One layer per atlas tile: mipmaps are per layer, so a distant facade never blends in its neighbour tiles
// (a 2D atlas with mipmaps smears windows, bricks and glow into each other with distance).
uniform sampler2DArray tiles : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2DArray glow : source_color, filter_nearest_mipmap, repeat_enable;
uniform float roughness_value = 0.9;
uniform float glow_energy = 1.05;
varying flat float layer;

void vertex() { layer = UV2.x; }

void fragment() {
	ALBEDO = texture(tiles, vec3(UV, layer)).rgb;
	ROUGHNESS = roughness_value;
	EMISSION = texture(glow, vec3(UV, layer)).rgb * glow_energy;
}
"""

static var _materials: Array = []
static var _tile_arrays: Array = []


## The atlas cut into one image per tile (own mip chain each) as two Texture2DArrays: colour and emission.
static func tile_arrays() -> Array:
	if not _tile_arrays.is_empty():
		return _tile_arrays
	for path in [CityAtlas.ALBEDO_PATH, CityAtlas.EMISSION_PATH]:
		var sheet := (load(path) as Texture2D).get_image()
		if sheet.is_compressed():
			sheet.decompress()
		sheet.convert(Image.FORMAT_RGBA8)
		var layers: Array[Image] = []
		for index in CityAtlas.NAMES.size():
			var tile := sheet.get_region(Rect2i((index % CityAtlas.COLUMNS) * CityAtlas.TILE_PX,
				(index / CityAtlas.COLUMNS) * CityAtlas.TILE_PX, CityAtlas.TILE_PX, CityAtlas.TILE_PX))
			tile.generate_mipmaps()
			layers.append(tile)
		var array := Texture2DArray.new()
		array.create_from_images(layers)
		_tile_arrays.append(array)
	return _tile_arrays


static func materials() -> Array:
	if not _materials.is_empty():
		return _materials
	var arrays := tile_arrays()
	var shader := Shader.new()
	shader.code = TILE_SHADER_CODE
	for roughness in [0.42, 0.92]:
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("tiles", arrays[0])
		material.set_shader_parameter("glow", arrays[1])
		material.set_shader_parameter("roughness_value", roughness)
		_materials.append(material)
	var rim := StandardMaterial3D.new()
	rim.albedo_texture = load(CityAtlas.RIM_PATH) as Texture2D
	rim.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
	rim.roughness = 0.95
	_materials.append(rim)
	return _materials


var _vertices := [PackedVector3Array(), PackedVector3Array(), PackedVector3Array()]
var _normals := [PackedVector3Array(), PackedVector3Array(), PackedVector3Array()]
var _uvs := [PackedVector2Array(), PackedVector2Array(), PackedVector2Array()]
var _layers := [PackedVector2Array(), PackedVector2Array(), PackedVector2Array()]   # UV2.x = atlas tile layer
var _indices := [PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]


func is_empty() -> bool:
	return (_vertices[0] as PackedVector3Array).is_empty() and (_vertices[1] as PackedVector3Array).is_empty() \
		and (_vertices[2] as PackedVector3Array).is_empty()


## A quad p0..p3 (bottom-left, bottom-right, top-right, top-left seen from the front) facing `normal`.
func quad(mat: int, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, normal: Vector3, tile: int,
		repeat_v: float = 1.0, repeat_u: float = 1.0) -> void:
	var v: PackedVector3Array = _vertices[mat]
	var layers: PackedVector2Array = _layers[mat]
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
		# One tile is one metre: a face larger (or smaller) than that repeats (or crops) the tile instead of stretching it.
		t.append(Vector2(0, repeat_v)); t.append(Vector2(repeat_u, repeat_v)); t.append(Vector2(repeat_u, 0)); t.append(Vector2(0, 0))
	for _i in 4:
		layers.append(Vector2(float(tile), 0.0))
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
		Vector3(lo.x, hi.y, hi.z), Vector3(0, 0, 1), side_tile, size.y, size.x)
	quad(mat, Vector3(hi.x, lo.y, lo.z), Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, hi.y, lo.z),
		Vector3(hi.x, hi.y, lo.z), Vector3(0, 0, -1), side_tile, size.y, size.x)
	quad(mat, Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z),
		Vector3(hi.x, hi.y, hi.z), Vector3(1, 0, 0), side_tile, size.y, size.z)
	quad(mat, Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z),
		Vector3(lo.x, hi.y, lo.z), Vector3(-1, 0, 0), side_tile, size.y, size.z)
	quad(mat, Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z),
		Vector3(lo.x, hi.y, lo.z), Vector3.UP, top, size.z, size.x)
	if lo.y > .05:
		# Anything off the ground (canopies, awnings, balconies) is seen from below: give it an underside.
		quad(mat, Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z),
			Vector3(lo.x, lo.y, hi.z), Vector3.DOWN, side_tile, size.z, size.x)


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
		arrays[Mesh.ARRAY_TEX_UV2] = _layers[mat]
		arrays[Mesh.ARRAY_INDEX] = _indices[mat]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mats[mat])
	return mesh
