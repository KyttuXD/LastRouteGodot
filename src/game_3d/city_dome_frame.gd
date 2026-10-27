class_name CityDomeFrame
extends Node3D

## The world beyond the city's rim, built once: a ring of far towers (lit windows) standing behind the rim wall. There is no
## dome shell any more (no ribs, rings, pylons or viaducts): the sky is open and the rim wall alone bounds the city.
## Coordinates are route space: the city centre is cell (22.5, 22.5).

const CENTER := Vector3(22.5, 0.0, 22.5)
const AXES := Vector3(116.0, 64.0, 69.0)    # x radius and z radius of the ring the towers stand on (y unused)
const TOWERS := 96

var _tower := StandardMaterial3D.new()
var _window := StandardMaterial3D.new()


func _ready() -> void:
	_tower.albedo_color = Color(0.045, 0.055, 0.11)
	_tower.roughness = 1.0
	_window.albedo_color = Color(1.0, 0.7, 0.3)
	_window.emission_enabled = true
	_window.emission = Color(1.0, 0.68, 0.28)
	_window.emission_energy_multiplier = 2.0
	_build_skyline()


func _build_skyline() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261027
	var towers := _Beams.new()
	var windows := _Beams.new()
	for index in TOWERS:
		var phi := TAU * (float(index) + rng.randf() * .8) / float(TOWERS)
		var spread := 1.2 + rng.randf() * .9
		var base := CENTER + Vector3(AXES.x * spread * cos(phi), 0, AXES.z * spread * sin(phi))
		var width := 5.0 + rng.randf() * 9.0
		var height := 26.0 + rng.randf() * 70.0
		towers.cube_tall(base, width, height)
		if rng.randf() < .35:
			towers.cube_tall(base + Vector3(0, height, 0), width * .45, 12.0 + rng.randf() * 22.0)
		# Windows sit on the box face that looks at the city. The towers are axis-aligned boxes, so offsetting along the
		# radial direction put diagonal towers' windows off the wall, glowing in the air beside or inside the box.
		var toward := (CENTER - base).normalized()
		toward = Vector3(signf(toward.x), 0, 0) if absf(toward.x) >= absf(toward.z) else Vector3(0, 0, signf(toward.z))
		for _w in 16:
			var along := Vector3(-toward.z, 0, toward.x) * (rng.randf() - .5) * (width * .8)
			var point := base + toward * (width * .5 + .2) + along + Vector3(0, 4.0 + rng.randf() * (height - 6.0), 0)
			windows.cube(point, .9 + rng.randf() * .6)
	_add_mesh(towers.build(), _tower)
	_add_mesh(windows.build(), _window)


func _add_mesh(mesh: ArrayMesh, material: Material) -> void:
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


## A small prism and cube builder for the frame (no UVs needed: flat colours).
class _Beams:
	var _vertices := PackedVector3Array()
	var _normals := PackedVector3Array()
	var _indices := PackedInt32Array()

	func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
		var normal := (b - a).cross(c - a).normalized()
		var base := _vertices.size()
		_vertices.append(a); _vertices.append(b); _vertices.append(c); _vertices.append(d)
		for _i in 4:
			_normals.append(normal)
		_indices.append(base); _indices.append(base + 1); _indices.append(base + 2)
		_indices.append(base); _indices.append(base + 2); _indices.append(base + 3)
		# Both sides: the frame is seen from inside and outside.
		_indices.append(base); _indices.append(base + 2); _indices.append(base + 1)
		_indices.append(base); _indices.append(base + 3); _indices.append(base + 2)

	func beam(from: Vector3, to: Vector3, thickness: float) -> void:
		var axis := (to - from)
		if axis.length() < .001:
			return
		var forward := axis.normalized()
		var side := forward.cross(Vector3.UP)
		if side.length() < .01:
			side = forward.cross(Vector3.RIGHT)
		side = side.normalized() * thickness * .5
		var up := forward.cross(side).normalized() * thickness * .5
		var corners := [-side - up, side - up, side + up, -side + up]
		for i in 4:
			var j := (i + 1) % 4
			_quad(from + corners[i], from + corners[j], to + corners[j], to + corners[i])

	func cube(center: Vector3, size: float) -> void:
		cube_tall(center - Vector3(0, size * .5, 0), size, size)

	func cube_tall(base: Vector3, width: float, height: float) -> void:
		var h := width * .5
		var lo := base + Vector3(-h, 0, -h)
		var hi := base + Vector3(h, height, h)
		_quad(Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z))
		_quad(Vector3(hi.x, lo.y, lo.z), Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z))
		_quad(Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z))
		_quad(Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, hi.y, lo.z))
		_quad(Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z))

	func build() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		if _vertices.is_empty():
			return mesh
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _vertices
		arrays[Mesh.ARRAY_NORMAL] = _normals
		arrays[Mesh.ARRAY_INDEX] = _indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh
