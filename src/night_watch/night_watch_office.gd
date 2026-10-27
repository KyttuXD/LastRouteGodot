class_name NightWatchOffice
extends Node3D

## The security room: a walkable blocky 6 x 5 m room with a desk and monitor against the back wall, a chair, a desk lamp, a
## breaker box and a vent hatch, and a doorway on each side wall with a sliding slab, a control panel (DOOR and LIGHT buttons) on
## the wall beside it and a short dark hall behind it. Everything solid has a collision body on layer 1; the things you can aim at
## (stations) have a small body on layer 2 with a "station_id" meta and a prompt. Real lights are only the desk lamp and the two
## door lights (on only while held) plus a very dim light in each hall (the light budget of docs/REF_LOOK.md). No post effects.

const HALF_W := 3.0
const HALF_D := 2.5
const HEIGHT := 3.0
const DOOR_W := 1.7
const DOOR_H := 2.4
const SLAB_OPEN_Y := DOOR_H + 1.3
const SLAB_CLOSED_Y := DOOR_H * 0.5
## Where the player starts (in the room, facing the desk) and the desk seat.
const SPAWN := Vector3(0.0, 0.0, 0.9)
const SEAT := Vector3(0.0, 0.0, -1.05)
## The hall mouth the player cannot pass (so nobody stands among the hunters): x beyond this is the hunters' side.
const HALL_GUARD_X := 3.7

var slabs := {}          # "doorL"/"doorR" -> Node3D
var door_lights := {}    # "doorL"/"doorR" -> SpotLight3D
var lamp: OmniLight3D
var lamp_shade: MeshInstance3D
var monitor_screen: MeshInstance3D
## station id -> prompt; the walker shows the prompt of the aimed station
var prompts := {}
var button_meshes := {}  # "doorL_door", "doorL_light", ... -> MeshInstance3D
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


## A cube; `solid` adds a collision body of the same size on layer 1.
func _box(size: Vector3, pos: Vector3, color: Color, node_name := "", emissive := false, parent: Node3D = null, solid := false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _material(color, emissive)
	mesh.position = pos
	if node_name != "":
		mesh.name = node_name
	(parent if parent != null else self).add_child(mesh)
	if solid:
		_body(mesh, size, Vector3.ZERO, 1)
	return mesh


func _body(parent: Node3D, size: Vector3, pos: Vector3, layer: int, station_id := "") -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1 << (layer - 1)
	body.collision_mask = 0
	body.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	if station_id != "":
		body.set_meta("station_id", station_id)
	parent.add_child(body)
	return body


## A station: a small layer-2 body you can aim at, with its prompt.
func _station(id: String, prompt: String, size: Vector3, pos: Vector3) -> void:
	prompts[id] = prompt
	_body(self, size, pos, 2, id)


func build() -> void:
	var wall := Color(0.20, 0.22, 0.26)
	var floor_color := Color(0.14, 0.13, 0.15)
	_box(Vector3(HALF_W * 2.0 + 0.4, 0.2, HALF_D * 2.0 + 0.4), Vector3(0, -0.1, 0), floor_color, "Floor", false, null, true)
	_box(Vector3(HALF_W * 2.0 + 0.4, 0.2, HALF_D * 2.0 + 0.4), Vector3(0, HEIGHT + 0.1, 0), wall.darkened(0.4), "Ceiling")
	_box(Vector3(HALF_W * 2.0 + 0.4, HEIGHT, 0.2), Vector3(0, HEIGHT * 0.5, -HALF_D - 0.1), wall, "WallBack", false, null, true)
	_box(Vector3(HALF_W * 2.0 + 0.4, HEIGHT, 0.2), Vector3(0, HEIGHT * 0.5, HALF_D + 0.1), wall.darkened(0.2), "WallFront", false, null, true)
	# the two side walls, each in three pieces around the doorway
	var side_len := HALF_D * 2.0
	var piece := (side_len - DOOR_W) * 0.5
	for side in [-1.0, 1.0]:
		var x: float = side * (HALF_W + 0.1)
		var tag := "L" if side < 0.0 else "R"
		var door := "doorL" if side < 0.0 else "doorR"
		_box(Vector3(0.2, HEIGHT, piece), Vector3(x, HEIGHT * 0.5, -HALF_D + piece * 0.5), wall, "Wall%sA" % tag, false, null, true)
		_box(Vector3(0.2, HEIGHT, piece), Vector3(x, HEIGHT * 0.5, HALF_D - piece * 0.5), wall, "Wall%sB" % tag, false, null, true)
		_box(Vector3(0.2, HEIGHT - DOOR_H, DOOR_W), Vector3(x, DOOR_H + (HEIGHT - DOOR_H) * 0.5, 0), wall, "Wall%sTop" % tag)
		_box(Vector3(0.3, DOOR_H, 0.12), Vector3(x, DOOR_H * 0.5, -DOOR_W * 0.5 - 0.06), Color(0.30, 0.22, 0.16), "Frame%s1" % tag)
		_box(Vector3(0.3, DOOR_H, 0.12), Vector3(x, DOOR_H * 0.5, DOOR_W * 0.5 + 0.06), Color(0.30, 0.22, 0.16), "Frame%s2" % tag)
		# the slab in the doorway (its body rides along, so a shut door really blocks the way)
		var slab := Node3D.new()
		slab.name = "Slab" + tag
		slab.position = Vector3(side * HALF_W, SLAB_OPEN_Y, 0.0)
		add_child(slab)
		_box(Vector3(0.14, DOOR_H, DOOR_W - 0.04), Vector3.ZERO, Color(0.34, 0.36, 0.40), "SlabBody", false, slab, true)
		for i in 4:
			_box(Vector3(0.16, 0.08, DOOR_W - 0.02), Vector3(0, -DOOR_H * 0.5 + 0.3 + i * 0.6, 0), Color(0.55, 0.45, 0.12), "SlabStripe", false, slab)
		slabs[door] = slab
		# the hall behind the doorway: floor, walls, ceiling, a very dim light, and the guard the player cannot pass
		var hx: float = side * (HALF_W + 3.25)
		_box(Vector3(6.3, 0.2, 3.2), Vector3(hx, -0.1, 0), floor_color.darkened(0.2), "Hall%sFloor" % tag, false, null, true)
		_box(Vector3(6.3, 0.2, 3.2), Vector3(hx, HEIGHT + 0.1, 0), wall.darkened(0.5), "Hall%sCeiling" % tag)
		_box(Vector3(6.3, HEIGHT, 0.2), Vector3(hx, HEIGHT * 0.5, -1.7), wall.darkened(0.3), "Hall%sWallN" % tag, false, null, true)
		_box(Vector3(6.3, HEIGHT, 0.2), Vector3(hx, HEIGHT * 0.5, 1.7), wall.darkened(0.3), "Hall%sWallS" % tag, false, null, true)
		_box(Vector3(0.2, HEIGHT, 3.2), Vector3(side * (HALF_W + 6.4), HEIGHT * 0.5, 0), wall.darkened(0.5), "Hall%sEnd" % tag, false, null, true)
		_body(self, Vector3(0.3, HEIGHT, 3.2), Vector3(side * HALL_GUARD_X, HEIGHT * 0.5, 0.0), 1)
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
		door_lights[door] = spot
		# the control panel on the wall beside the door: a DOOR button above a LIGHT button
		var px: float = side * (HALF_W - 0.06)
		_box(Vector3(0.1, 0.7, 0.42), Vector3(px, 1.3, 1.55), Color(0.10, 0.10, 0.12), "Panel%s" % tag)
		for entry in [["door", 1.47, Color(0.2, 0.75, 0.3), "DOOR"], ["light", 1.15, Color(0.45, 0.45, 0.4), "LIGHT"]]:
			var bx: float = side * (HALF_W - 0.13)
			var b := _box(Vector3(0.06, 0.2, 0.26), Vector3(bx, float(entry[1]), 1.55), entry[2], "Button%s%s" % [tag, entry[3]], true)
			button_meshes["%s_%s" % [door, entry[0]]] = b
			var side_name := "LEFT" if side < 0.0 else "RIGHT"
			var text := "%s DOOR // SHUT / OPEN" % side_name if entry[0] == "door" else "%s DOOR LIGHT // HOLD" % side_name
			_station("%s_%s" % [door, entry[0]], text, Vector3(0.22, 0.26, 0.34), Vector3(bx, float(entry[1]), 1.55))
	# the desk against the back wall, the monitor, a keyboard, a cup, the chair and the desk lamp
	_box(Vector3(2.4, 0.08, 0.95), Vector3(0, 0.76, -1.95), Color(0.42, 0.30, 0.20), "DeskTop")
	for x in [-1.1, 1.1]:
		_box(Vector3(0.1, 0.76, 0.85), Vector3(x, 0.38, -1.95), Color(0.32, 0.23, 0.16), "DeskLeg")
	_body(self, Vector3(2.4, 0.9, 0.95), Vector3(0, 0.45, -1.95), 1)
	_box(Vector3(0.9, 0.58, 0.07), Vector3(0, 1.12, -2.2), Color(0.10, 0.10, 0.12), "MonitorCase")
	monitor_screen = _box(Vector3(0.8, 0.48, 0.02), Vector3(0, 1.12, -2.16), Color(0.20, 0.34, 0.30), "MonitorScreen", true)
	_box(Vector3(0.18, 0.12, 0.18), Vector3(0, 0.84, -2.2), Color(0.12, 0.12, 0.14), "MonitorStand")
	_box(Vector3(0.5, 0.03, 0.16), Vector3(0.0, 0.81, -1.6), Color(0.16, 0.16, 0.18), "Keyboard")
	_box(Vector3(0.24, 0.08, 0.24), Vector3(-0.9, 0.82, -1.7), Color(0.60, 0.55, 0.45), "Cup")
	_box(Vector3(0.45, 0.5, 0.45), Vector3(0.0, 0.25, -1.1), Color(0.25, 0.18, 0.14), "ChairSeat", false, null, true)
	_box(Vector3(0.45, 0.6, 0.08), Vector3(0.0, 0.8, -0.9), Color(0.25, 0.18, 0.14), "ChairBack")
	_station("monitor", "MONITOR // CAMERAS", Vector3(1.0, 0.7, 0.3), Vector3(0, 1.12, -2.0))
	_station("chair", "SIT AT DESK", Vector3(0.6, 0.9, 0.6), Vector3(0.0, 0.55, -1.0))
	# the desk lamp (a real warm light, switchable)
	_box(Vector3(0.18, 0.04, 0.18), Vector3(0.9, 0.82, -1.7), Color(0.12, 0.12, 0.14), "LampBase")
	_box(Vector3(0.04, 0.34, 0.04), Vector3(0.9, 1.0, -1.7), Color(0.12, 0.12, 0.14), "LampArm")
	lamp_shade = _box(Vector3(0.22, 0.14, 0.22), Vector3(0.9, 1.22, -1.7), Color(1.0, 0.82, 0.5), "LampShade", true)
	lamp = OmniLight3D.new()
	lamp.name = "DeskLamp"
	lamp.light_color = Color(1.0, 0.82, 0.55)
	lamp.light_energy = 1.1
	lamp.omni_range = 5.0
	lamp.position = Vector3(0.9, 1.35, -1.6)
	add_child(lamp)
	_station("lamp", "DESK LAMP", Vector3(0.4, 0.6, 0.4), Vector3(0.9, 1.0, -1.7))
	# a breaker box and a vent hatch on the walls (for the later modes: physical props now, with a prompt)
	_box(Vector3(0.6, 0.8, 0.14), Vector3(2.3, 1.5, -HALF_D + 0.07), Color(0.30, 0.32, 0.34), "BreakerBox", false, null, true)
	_box(Vector3(0.5, 0.12, 0.04), Vector3(2.3, 1.75, -HALF_D + 0.16), Color(0.75, 0.62, 0.15), "BreakerLabel", true)
	_station("breaker", "BREAKER BOX // NOT USED TONIGHT", Vector3(0.7, 0.9, 0.3), Vector3(2.3, 1.5, -HALF_D + 0.2))
	_box(Vector3(0.8, 0.5, 0.1), Vector3(-2.3, 0.45, -HALF_D + 0.05), Color(0.18, 0.18, 0.2), "VentHatch", false, null, true)
	for i in 4:
		_box(Vector3(0.7, 0.03, 0.05), Vector3(-2.3, 0.3 + i * 0.1, -HALF_D + 0.12), Color(0.08, 0.08, 0.1), "VentSlat")
	_station("vent", "VENT HATCH // SEALED", Vector3(0.9, 0.6, 0.3), Vector3(-2.3, 0.45, -HALF_D + 0.2))
	# a wall clock above the desk, and a poster
	_box(Vector3(0.5, 0.5, 0.06), Vector3(1.4, 2.2, -HALF_D + 0.04), Color(0.80, 0.78, 0.70), "ClockFace", true)
	_box(Vector3(0.9, 1.2, 0.05), Vector3(-1.4, 1.8, -HALF_D + 0.04), Color(0.45, 0.20, 0.32), "Poster")
	for key in slabs:
		_apply_slab(key)
	set_button("doorL_door", false)
	set_button("doorR_door", false)


## A panel button's colour: the DOOR button is red while the door is shut, green when open; the LIGHT button glows while held.
func set_button(id: String, on: bool) -> void:
	var mesh := button_meshes.get(id) as MeshInstance3D
	if mesh == null:
		return
	if id.ends_with("_door"):
		mesh.material_override = _material(Color(0.85, 0.15, 0.15) if on else Color(0.2, 0.75, 0.3), true)
	else:
		mesh.material_override = _material(Color(1.0, 0.9, 0.4) if on else Color(0.45, 0.45, 0.4), true)


func set_lamp(on: bool) -> void:
	lamp.visible = on
	lamp_shade.material_override = _material(Color(1.0, 0.82, 0.5) if on else Color(0.35, 0.3, 0.22), true)


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


## Where a hunter at a door stands, from how far into her wait she is (0 = just arrived, 1 = about to attack): she starts well
## down the hall (peek), steps up to the doorway (stand) and leans in at the threshold, in the doorway itself (lean).
func door_stand(door: String, slot: int, progress := 0.0) -> Vector3:
	var side := -1.0 if door == "doorL" else 1.0
	var near := lerpf(HALF_W + 1.9, HALF_W + 0.55, clampf(progress, 0.0, 1.0))
	return Vector3(side * (near + slot * 1.3), 0.0, -0.4 * slot)
