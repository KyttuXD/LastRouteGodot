class_name CityDomeFrame
extends Node3D

## The dome's structure and the world beyond it, built once: dark pylons ringing the rim with cyan beacons, truss ribs
## and rings arching over the city, and a skyline ring of towers (lit windows) with viaduct spans outside the dome.
## Coordinates are route space: the city centre is cell (22.5, 22.5).

const CENTER := Vector3(22.5, 0.0, 22.5)
const AXES := Vector3(116.0, 64.0, 69.0)    # x radius, apex height, z radius of the dome ellipsoid
const RIBS := 8
const RINGS := [0.28, 0.58, 0.86]
const PYLONS := 16
const TOWERS := 96

var _metal := StandardMaterial3D.new()
var _beacon := StandardMaterial3D.new()
var _tower := StandardMaterial3D.new()
var _window := StandardMaterial3D.new()


func _ready() -> void:
	_metal.albedo_color = Color(0.06, 0.07, 0.10)
	_metal.roughness = 0.9
	_beacon.albedo_color = Color(0.3, 0.9, 0.9)
	_beacon.emission_enabled = true
	_beacon.emission = Color(0.3, 0.95, 0.95)
	_beacon.emission_energy_multiplier = 2.4
	_tower.albedo_color = Color(0.045, 0.055, 0.11)
	_tower.roughness = 1.0
	_window.albedo_color = Color(1.0, 0.7, 0.3)
	_window.emission_enabled = true
	_window.emission = Color(1.0, 0.68, 0.28)
	_window.emission_energy_multiplier = 2.0
	_build_frame()
	_build_skyline()


func _dome_point(phi: float, lift: float) -> Vector3:
	# lift 0 = the rim on the ground, 1 = the apex.
	var angle := lift * PI * .5
	return CENTER + Vector3(AXES.x * cos(phi) * cos(angle), AXES.y * sin(angle), AXES.z * sin(phi) * cos(angle))


func _build_frame() -> void:
	var metal := _Beams.new()
	var beacons := _Beams.new()
	for rib in RIBS:
		var phi := TAU * float(rib) / float(RIBS) + .2
		var previous := _dome_point(phi, 0.0)
		for step in range(1, 25):
			var point := _dome_point(phi, float(step) / 24.0)
			metal.beam(previous, point, .55)
			if step % 6 == 0:
				beacons.cube(point, .9)
			previous = point
	for lift in RINGS:
		var previous := _dome_point(0.0, lift)
		for step in range(1, 65):
			var point := _dome_point(TAU * float(step) / 64.0, lift)
			metal.beam(previous, point, .45)
			if step % 8 == 0:
				beacons.cube(point, .8)
			previous = point
	for pylon in PYLONS:
		var phi := TAU * float(pylon) / float(PYLONS) + .2
		var base := CENTER + Vector3(AXES.x * 1.0 * cos(phi), 0, AXES.z * 1.0 * sin(phi))
		metal.cube_tall(base, 3.2, 70.0)
		beacons.cube(base + Vector3(0, 70.5, 0), 1.6)
	_add_mesh(metal.build(), _metal)
	_add_mesh(beacons.build(), _beacon)


func _build_skyline() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261027
	var towers := _Beams.new()
	var windows := _Beams.new()
	for index in TOWERS:
		var phi := TAU * (float(index) + rng.randf() * .8) / float(TOWERS)
		var spread := 1.32 + rng.randf() * .9
		var base := CENTER + Vector3(AXES.x * spread * cos(phi), 0, AXES.z * spread * sin(phi))
		var width := 5.0 + rng.randf() * 9.0
		var height := 26.0 + rng.randf() * 70.0
		towers.cube_tall(base, width, height)
		if rng.randf() < .35:
			towers.cube_tall(base + Vector3(0, height, 0), width * .45, 12.0 + rng.randf() * 22.0)
		var toward := (CENTER - base).normalized()
		for _w in 16:
			var along := Vector3(-toward.z, 0, toward.x) * (rng.randf() - .5) * (width * .8)
			var point := base + toward * (width * .5 + .2) + along + Vector3(0, 4.0 + rng.randf() * (height - 6.0), 0)
			windows.cube(point, .9 + rng.randf() * .6)
	# Three arched viaducts: long low beams between ring towers, lifted into a gentle arch.
	for arch in 3:
		var phi0 := TAU * float(arch) / 3.0 + .6
		var spread := 1.55
		var previous := CENTER + Vector3(AXES.x * spread * cos(phi0), 36.0, AXES.z * spread * sin(phi0))
		for step in range(1, 17):
			var phi := phi0 + float(step) * .018
			var lift := 36.0 + sin(float(step) / 16.0 * PI) * 8.0
			var point := CENTER + Vector3(AXES.x * spread * cos(phi), lift, AXES.z * spread * sin(phi))
			towers.beam(previous, point, 1.6)
			previous = point
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
