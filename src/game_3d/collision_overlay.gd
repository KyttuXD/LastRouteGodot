class_name CollisionOverlay
extends Node3D

## Admin "SHOW COLLISION": draws what the player capsule collides with, on top of the world. Red boxes are the solid props'
## colliders (collider_size, at their placement offset and yaw), green rectangles the door keep-clear zones (1.5 m either
## side of every room door, across its width). Rebuilt when the loaded chunk set changes.

var _mesh_instance: MeshInstance3D
var _signature := ""
var enabled := false


func _ready() -> void:
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "CollisionLines"
	_mesh_instance.visible = false
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance)


func set_enabled(value: bool) -> void:
	enabled = value
	if _mesh_instance != null:
		_mesh_instance.visible = value
	if not value:
		_signature = ""


## chunks: [{coord: Vector3i, data: Dictionary}] for every loaded chunk.
func refresh(chunks: Array, level_height: float) -> void:
	if not enabled or _mesh_instance == null:
		return
	var signature := ""
	for entry in chunks:
		signature += "%s;" % [entry["coord"]]
	if signature == _signature:
		return
	_signature = signature
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	for entry in chunks:
		var coord: Vector3i = entry["coord"]
		var base := Vector3(coord.x * StreamedRouteGenerator.CHUNK_SIZE, coord.y * level_height + 0.02,
			coord.z * StreamedRouteGenerator.CHUNK_SIZE)
		var world := CollisionWorld.from_chunk(entry["data"])
		for rect in world.rects:
			_box(vertices, colors, base, rect, Color(1.0, 0.25, 0.2))
		for zone in world.door_zones:
			_zone(vertices, colors, base, zone["rect"], Color(0.2, 1.0, 0.35))
	var mesh := ArrayMesh.new()
	if not vertices.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_COLOR] = colors
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.vertex_color_use_as_albedo = true
		material.no_depth_test = true
		material.render_priority = 100
		mesh.surface_set_material(0, material)
	_mesh_instance.mesh = mesh


static func _line(vertices: PackedVector3Array, colors: PackedColorArray, a: Vector3, b: Vector3, color: Color) -> void:
	vertices.append(a)
	vertices.append(b)
	colors.append(color)
	colors.append(color)


func _box(vertices: PackedVector3Array, colors: PackedColorArray, base: Vector3, rect: Dictionary, color: Color) -> void:
	var half: Vector2 = rect["half"]
	var centre: Vector2 = rect["center"]
	var yaw := float(rect["yaw"])
	var c := cos(yaw)
	var s := sin(yaw)
	var height := float(rect.get("height", 1.0))
	var corners: Array[Vector3] = []
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var local := Vector2(half.x * sx, half.y * sz)
			var w := centre + Vector2(local.x * c + local.y * s, -local.x * s + local.y * c)
			corners.append(base + Vector3(w.x, 0, w.y))
	# corners order: (-,-) (-,+) (+,-) (+,+) -> ring -,- / -,+ / +,+ / +,-
	var ring := [corners[0], corners[1], corners[3], corners[2]]
	for i in 4:
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[(i + 1) % 4]
		_line(vertices, colors, a, b, color)
		_line(vertices, colors, a + Vector3.UP * height, b + Vector3.UP * height, color)
		_line(vertices, colors, a, a + Vector3.UP * height, color)


func _zone(vertices: PackedVector3Array, colors: PackedColorArray, base: Vector3, rect: Rect2, color: Color) -> void:
	var p0 := base + Vector3(rect.position.x, 0.03, rect.position.y)
	var p1 := base + Vector3(rect.end.x, 0.03, rect.position.y)
	var p2 := base + Vector3(rect.end.x, 0.03, rect.end.y)
	var p3 := base + Vector3(rect.position.x, 0.03, rect.end.y)
	_line(vertices, colors, p0, p1, color)
	_line(vertices, colors, p1, p2, color)
	_line(vertices, colors, p2, p3, color)
	_line(vertices, colors, p3, p0, color)
