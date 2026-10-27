class_name NightWatchOffice
extends Node3D

## The office: a blocky 6 x 5 m room with a desk and monitor, a doorway on each side wall (a sliding slab each) and a short
## dark hall behind each doorway. The player's seat is at the desk; the camera can look a little left and right to see the
## doors. Real lights are only the desk lamp and the two door lights (held), plus a very dim light in each hall so a hunter at
## a door is at least a silhouette (the light budget from docs/REF_LOOK.md). No post effects.

const HALF_W := 3.0
const HALF_D := 2.5
const HEIGHT := 3.0
const DOOR_W := 1.7
const DOOR_H := 2.4
const SLAB_OPEN_Y := DOOR_H + 1.3
const SLAB_CLOSED_Y := DOOR_H * 0.5
const SEAT := Vector3(0.0, 1.25, 0.9)

var slabs := {}          # "doorL"/"doorR" -> Node3D
var door_lights := {}    # "doorL"/"doorR" -> SpotLight3D
var lamp: OmniLight3D
var camera: Camera3D
var monitor_screen: MeshInstance3D
var _materials := {}
## 0 = open, 1 = shut, per door: the slab slides toward its target in the scene's _process.
var slab_progress := {"doorL": 0.0, "doorR": 0.0}


func _ready() -> void:
	if slabs.is_empty():
		build()


func _material(color: Color, emissive := false) -> StandardMaterial3D:
	var key := "%s%s" % [color.to_html(), emissive]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if emissive:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_materials[key] = m
	return m


func _box(size: Vector3, pos: Vector3, color: Color, node_name := "", emissive := false, parent: Node3D = null) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _material(color, emissive)
	mesh.position = pos
	if node_name != "":
		mesh.name = node_name
	(parent if parent != null else self).add_child(mesh)
	return mesh


func build() -> void:
	var wall := Color(0.20, 0.22, 0.26)
	var floor_color := Color(0.14, 0.13, 0.15)
	_box(Vector3(HALF_W * 2.0 + 0.4, 0.2, HALF_D * 2.0 + 0.4), Vector3(0, -0.1, 0), floor_color, "Floor")
	_box(Vector3(HALF_W * 2.0 + 0.4, 0.2, HALF_D * 2.0 + 0.4), Vector3(0, HEIGHT + 0.1, 0), wall.darkened(0.4), "Ceiling")
	_box(Vector3(HALF_W * 2.0 + 0.4, HEIGHT, 0.2), Vector3(0, HEIGHT * 0.5, -HALF_D - 0.1), wall, "WallBack")
	_box(Vector3(HALF_W * 2.0 + 0.4, HEIGHT, 0.2), Vector3(0, HEIGHT * 0.5, HALF_D + 0.1), wall.darkened(0.2), "WallFront")
	# the two side walls, each in three pieces around the doorway
	var side_len := HALF_D * 2.0
	var piece := (side_len - DOOR_W) * 0.5
	for side in [-1.0, 1.0]:
		var x: float = side * (HALF_W + 0.1)
		var tag := "L" if side < 0.0 else "R"
		_box(Vector3(0.2, HEIGHT, piece), Vector3(x, HEIGHT * 0.5, -HALF_D + piece * 0.5), wall, "Wall%sA" % tag)
		_box(Vector3(0.2, HEIGHT, piece), Vector3(x, HEIGHT * 0.5, HALF_D - piece * 0.5), wall, "Wall%sB" % tag)
		_box(Vector3(0.2, HEIGHT - DOOR_H, DOOR_W), Vector3(x, DOOR_H + (HEIGHT - DOOR_H) * 0.5, 0), wall, "Wall%sTop" % tag)
		# door frame
		_box(Vector3(0.3, DOOR_H, 0.12), Vector3(x, DOOR_H * 0.5, -DOOR_W * 0.5 - 0.06), Color(0.30, 0.22, 0.16), "Frame%s1" % tag)
		_box(Vector3(0.3, DOOR_H, 0.12), Vector3(x, DOOR_H * 0.5, DOOR_W * 0.5 + 0.06), Color(0.30, 0.22, 0.16), "Frame%s2" % tag)
		# the slab in the doorway
		var slab := Node3D.new()
		slab.name = "Slab" + tag
		slab.position = Vector3(side * HALF_W, SLAB_OPEN_Y, 0.0)
		add_child(slab)
		_box(Vector3(0.14, DOOR_H, DOOR_W - 0.04), Vector3.ZERO, Color(0.34, 0.36, 0.40), "SlabBody", false, slab)
		for i in 4:
			_box(Vector3(0.16, 0.08, DOOR_W - 0.02), Vector3(0, -DOOR_H * 0.5 + 0.3 + i * 0.6, 0), Color(0.55, 0.45, 0.12), "SlabStripe", false, slab)
		slabs["doorL" if side < 0.0 else "doorR"] = slab
		# the hall behind the doorway: floor, walls, ceiling, very dim light
		var hx: float = side * (HALF_W + 3.25)
		_box(Vector3(6.3, 0.2, 3.2), Vector3(hx, -0.1, 0), floor_color.darkened(0.2), "Hall%sFloor" % tag)
		_box(Vector3(6.3, 0.2, 3.2), Vector3(hx, HEIGHT + 0.1, 0), wall.darkened(0.5), "Hall%sCeiling" % tag)
		_box(Vector3(6.3, HEIGHT, 0.2), Vector3(hx, HEIGHT * 0.5, -1.7), wall.darkened(0.3), "Hall%sWallN" % tag)
		_box(Vector3(6.3, HEIGHT, 0.2), Vector3(hx, HEIGHT * 0.5, 1.7), wall.darkened(0.3), "Hall%sWallS" % tag)
		_box(Vector3(0.2, HEIGHT, 3.2), Vector3(side * (HALF_W + 6.4), HEIGHT * 0.5, 0), wall.darkened(0.5), "Hall%sEnd" % tag)
		var dim := OmniLight3D.new()
		dim.name = "Hall%sGlow" % tag
		dim.light_color = Color(0.45, 0.55, 0.9)
		dim.light_energy = 0.14
		dim.omni_range = 5.0
		dim.position = Vector3(side * (HALF_W + 3.6), 2.4, 0)
		add_child(dim)
		# the door light: a spot from the desk side toward the hall, on only while held
		var spot := SpotLight3D.new()
		spot.name = "DoorLight" + tag
		spot.light_color = Color(1.0, 0.95, 0.82)
		spot.light_energy = 5.0
		spot.spot_range = 9.0
		spot.spot_angle = 34.0
		spot.shadow_enabled = false
		add_child(spot)
		spot.transform = Transform3D(Basis.IDENTITY, Vector3(side * 1.7, 1.55, 0.7)).looking_at(Vector3(side * (HALF_W + 4.2), 1.0, 0.0), Vector3.UP)
		spot.visible = false
		door_lights["doorL" if side < 0.0 else "doorR"] = spot
	# the desk, the monitor and the lamp
	_box(Vector3(2.4, 0.08, 0.95), Vector3(0, 0.76, -0.45), Color(0.42, 0.30, 0.20), "DeskTop")
	for x in [-1.1, 1.1]:
		_box(Vector3(0.1, 0.76, 0.85), Vector3(x, 0.38, -0.45), Color(0.32, 0.23, 0.16), "DeskLeg")
	_box(Vector3(0.9, 0.58, 0.07), Vector3(0, 1.12, -0.7), Color(0.10, 0.10, 0.12), "MonitorCase")
	monitor_screen = _box(Vector3(0.8, 0.48, 0.02), Vector3(0, 1.12, -0.655), Color(0.20, 0.34, 0.30), "MonitorScreen", true)
	_box(Vector3(0.18, 0.12, 0.18), Vector3(0, 0.84, -0.7), Color(0.12, 0.12, 0.14), "MonitorStand")
	_box(Vector3(0.5, 0.03, 0.16), Vector3(0.0, 0.81, -0.1), Color(0.16, 0.16, 0.18), "Keyboard")
	_box(Vector3(0.24, 0.08, 0.24), Vector3(0.9, 0.82, -0.2), Color(0.60, 0.55, 0.45), "Cup")
	_box(Vector3(0.4, 0.5, 0.4), Vector3(0.0, 0.25, 1.15), Color(0.25, 0.18, 0.14), "Chair")
	# a wall clock above the desk, and a poster
	_box(Vector3(0.5, 0.5, 0.06), Vector3(1.6, 2.1, -HALF_D + 0.04), Color(0.80, 0.78, 0.70), "ClockFace", true)
	_box(Vector3(0.9, 1.2, 0.05), Vector3(-1.4, 1.7, -HALF_D + 0.04), Color(0.45, 0.20, 0.32), "Poster")
	lamp = OmniLight3D.new()
	lamp.name = "DeskLamp"
	lamp.light_color = Color(1.0, 0.82, 0.55)
	lamp.light_energy = 0.9
	lamp.omni_range = 4.5
	lamp.position = Vector3(0.9, 1.5, -0.2)
	add_child(lamp)
	camera = Camera3D.new()
	camera.name = "OfficeCamera"
	camera.position = SEAT
	camera.fov = 74.0
	add_child(camera)
	for key in slabs:
		_apply_slab(key)


## Move the slabs toward their targets (1 = shut). Returns true if anything moved.
func animate(shut: Dictionary, delta: float) -> bool:
	var moved := false
	for key in slabs:
		var target := 1.0 if bool(shut.get(key, false)) else 0.0
		var current: float = slab_progress[key]
		if not is_equal_approx(current, target):
			slab_progress[key] = move_toward(current, target, delta * 7.0)
			moved = true
			_apply_slab(key)
	return moved


func snap_slabs(shut: Dictionary) -> void:
	for key in slabs:
		slab_progress[key] = 1.0 if bool(shut.get(key, false)) else 0.0
		_apply_slab(key)


func _apply_slab(key: String) -> void:
	var slab := slabs[key] as Node3D
	slab.position.y = lerpf(SLAB_OPEN_Y, SLAB_CLOSED_Y, float(slab_progress[key]))


func set_light(key: String, on: bool) -> void:
	(door_lights[key] as SpotLight3D).visible = on


func door_stand(door: String, slot: int) -> Vector3:
	var side := -1.0 if door == "doorL" else 1.0
	return Vector3(side * (HALF_W + 1.5 + slot * 1.3), 0.0, -0.5 * slot)


## Look direction limits for the seated player (radians): yaw left/right and pitch.
const MAX_YAW := 1.25
const MAX_PITCH := 0.6


func look(yaw: float, pitch: float) -> void:
	camera.rotation = Vector3(clampf(pitch, -MAX_PITCH, MAX_PITCH), clampf(yaw, -MAX_YAW, MAX_YAW), 0.0)
