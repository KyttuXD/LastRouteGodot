class_name NightWatchBuilding
extends Node3D

## The building the cameras look into: the eight rooms of Classic (NightWatchData.ROOMS) as small blocky rooms laid out on a
## grid far from the office, each with a camera mount and two floor spots for hunters. Pure cubes and flat colours (no
## textures, no post effects); the feed camera has its own brighter ambient so the rooms read on the monitor while the
## office stays dark. Everything is generated, so it is the same on every machine.

const CELL := 8.0
const ROOM_W := 6.0
const ROOM_H := 3.2
## Where the building sits relative to the office (north of it, out of sight of the office camera).
const ORIGIN := Vector3(-8.0, 0.0, -40.0)

const COLORS := {
	"stage": Color(0.42, 0.20, 0.34), "dining": Color(0.36, 0.30, 0.22), "backstage": Color(0.24, 0.26, 0.36),
	"westhall": Color(0.28, 0.30, 0.34), "closet": Color(0.30, 0.24, 0.20), "kitchen": Color(0.30, 0.38, 0.38),
	"easthall": Color(0.28, 0.30, 0.34), "corner": Color(0.34, 0.26, 0.36),
}

var rooms := {}   # room id -> Node3D (the room's centre on the floor)
var _materials := {}


func _ready() -> void:
	if rooms.is_empty():
		build()


func build() -> void:
	for id in NightWatchData.ROOMS:
		var info: Dictionary = NightWatchData.ROOMS[id]
		if int(info["cam"]) == 0:
			continue
		var room := Node3D.new()
		room.name = "Room_%s" % id
		var grid: Vector2i = info["grid"]
		room.position = ORIGIN + Vector3(grid.x * CELL, 0.0, grid.y * CELL)
		add_child(room)
		rooms[id] = room
		_build_room(room, String(id), COLORS.get(id, Color(0.3, 0.3, 0.3)))


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


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, emissive := false, node_name := "") -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _material(color, emissive)
	mesh.position = pos
	if node_name != "":
		mesh.name = node_name
	parent.add_child(mesh)
	return mesh


func _build_room(room: Node3D, id: String, tint: Color) -> void:
	var half := ROOM_W * 0.5
	# floor, ceiling, four walls (the south wall is open toward the camera side so the feed sees in)
	_box(room, Vector3(ROOM_W, 0.2, ROOM_W), Vector3(0, -0.1, 0), tint.darkened(0.35), false, "Floor")
	_box(room, Vector3(ROOM_W, 0.2, ROOM_W), Vector3(0, ROOM_H + 0.1, 0), tint.darkened(0.5), false, "Ceiling")
	_box(room, Vector3(ROOM_W, ROOM_H, 0.2), Vector3(0, ROOM_H * 0.5, -half), tint, false, "WallN")
	_box(room, Vector3(0.2, ROOM_H, ROOM_W), Vector3(-half, ROOM_H * 0.5, 0), tint.lightened(0.05), false, "WallW")
	_box(room, Vector3(0.2, ROOM_H, ROOM_W), Vector3(half, ROOM_H * 0.5, 0), tint.lightened(0.05), false, "WallE")
	# a lit ceiling panel so the room reads as a place with a light in it
	_box(room, Vector3(1.4, 0.05, 1.4), Vector3(0, ROOM_H - 0.04, 0), Color(1.0, 0.92, 0.7), true, "CeilingPanel")
	# floor stripe and a baseboard so the room has some scale on the feed
	_box(room, Vector3(ROOM_W, 0.02, 0.3), Vector3(0, 0.01, 0.8), tint.lightened(0.25), false, "FloorStripe")
	_box(room, Vector3(ROOM_W, 0.25, 0.08), Vector3(0, 0.125, -half + 0.14), tint.darkened(0.25), false, "Baseboard")
	match id:
		"stage":
			_box(room, Vector3(4.2, 0.45, 2.0), Vector3(0, 0.225, -1.8), Color(0.55, 0.32, 0.22), false, "Platform")
			_box(room, Vector3(0.5, 2.6, 0.12), Vector3(-2.4, 1.4, -2.7), Color(0.55, 0.10, 0.16), false, "CurtainL")
			_box(room, Vector3(0.5, 2.6, 0.12), Vector3(2.4, 1.4, -2.7), Color(0.55, 0.10, 0.16), false, "CurtainR")
		"dining":
			for x in [-1.8, 1.8]:
				for z in [-1.2, 1.4]:
					_box(room, Vector3(1.2, 0.08, 1.2), Vector3(x, 0.75, z), Color(0.62, 0.46, 0.30), false, "Table")
					_box(room, Vector3(0.12, 0.75, 0.12), Vector3(x, 0.375, z), Color(0.40, 0.30, 0.20), false, "TableLeg")
		"backstage":
			_box(room, Vector3(0.9, 0.9, 0.9), Vector3(-1.8, 0.45, -1.9), Color(0.50, 0.38, 0.26), false, "Crate")
			_box(room, Vector3(0.9, 0.9, 0.9), Vector3(-0.8, 0.45, -2.0), Color(0.46, 0.34, 0.24), false, "Crate")
			_box(room, Vector3(0.9, 0.9, 0.9), Vector3(-1.3, 1.35, -1.95), Color(0.52, 0.40, 0.28), false, "Crate")
		"westhall", "easthall":
			_box(room, Vector3(0.2, 2.2, 1.0), Vector3(-half + 0.2 if id == "westhall" else half - 0.2, 1.1, 1.8), Color(0.18, 0.2, 0.24), false, "Locker")
			_box(room, Vector3(0.9, 0.06, 4.8), Vector3(0, 0.03, 0), Color(0.2, 0.22, 0.28), false, "Runner")
		"closet":
			_box(room, Vector3(0.5, 2.4, 3.6), Vector3(-2.4, 1.2, -0.4), Color(0.40, 0.30, 0.22), false, "Shelves")
			_box(room, Vector3(0.6, 0.6, 0.6), Vector3(1.6, 0.3, -2.2), Color(0.48, 0.36, 0.26), false, "Box")
		"kitchen":
			_box(room, Vector3(4.6, 0.9, 0.9), Vector3(0, 0.45, -2.3), Color(0.55, 0.58, 0.60), false, "Counter")
			_box(room, Vector3(1.0, 1.1, 1.0), Vector3(2.1, 0.55, 1.5), Color(0.62, 0.64, 0.66), false, "Fridge")
		"corner":
			_box(room, Vector3(0.7, 3.2, 0.7), Vector3(-2.0, 1.6, -2.0), Color(0.40, 0.32, 0.42), false, "Pillar")
			_box(room, Vector3(1.6, 0.5, 0.7), Vector3(2.0, 0.25, -2.3), Color(0.46, 0.36, 0.40), false, "Bench")


## World position of hunter slot 0 or 1 in a room (the second one stands a little to the side and further back).
func stand_position(room_id: String, slot: int) -> Vector3:
	var room := rooms.get(room_id) as Node3D
	if room == null:
		return Vector3.ZERO
	var offset := Vector3(-0.6, 0.0, 0.4) if slot == 0 else Vector3(1.0, 0.0, -0.6)
	if room_id == "stage":
		offset += Vector3(0.0, 0.45, -1.4)
	return room.global_position + offset


## The feed camera's mount: high in the open (south) corner of the room, looking in.
func camera_transform(room_id: String) -> Transform3D:
	var room := rooms.get(room_id) as Node3D
	if room == null:
		return Transform3D.IDENTITY
	var from := room.global_position + Vector3(-1.2, 2.9, 4.4)
	var target := room.global_position + Vector3(0.0, 0.8, -0.8)
	return Transform3D(Basis.IDENTITY, from).looking_at(target, Vector3.UP)
