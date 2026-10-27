class_name ControlRoomOffice
extends NightWatchOfficeBase

## The Facility's office: the control room (the OFFICE CONTRACT, docs/NIGHT_WATCH_OFFICES.md). A 5.6 x 5 m room with a wall of monitors on each side of the lift
## door (north), a task board, the log-in terminal with its number note on the desk against the south wall, and the chair you hide under in Control. The left
## and right doorways lead to the gallery and the workshop; the lift door is in the north wall (StoryWorld puts the sliding lift slab and the car there). The
## door buttons, the terminal and the hide spot are NightWatchStations (the shared interactables); the monitor wall's station tells you the next task.
## Cubes only through NightWatchArt; one real light (the room light).

const A := preload("res://src/night_watch/night_watch_art.gd")
const ROOM_W := 5.6
const ROOM_D := 5.0
const HEIGHT := 3.0
const DOOR_GAP := 1.5
const DOOR_TOP := 2.3
const SPAWN := Vector3(0.0, 0.0, 0.6)

var note_label: Label3D
var room_light: OmniLight3D
var screens: Array = []


func _make_spec() -> NightWatchOfficeSpec:
	return make_spec()


static func make_spec() -> NightWatchOfficeSpec:
	return NightWatchOfficeSpec.make({
		"id": "control_room", "title": "Control room", "mode_ids": ["story"],
		"footprint": Rect2(-ROOM_W * 0.5 + 0.3, -ROOM_D * 0.5 + 0.3, ROOM_W - 0.6, ROOM_D - 0.6),
		"spawn": SPAWN,
		"entrances": [
			{"id": "doorL", "kind": "door_slab", "position": Vector3(-ROOM_W * 0.5, 0.0, 0.0), "outward": Vector3(-1, 0, 0), "sim_room": "gallery", "blockable": false},
			{"id": "doorR", "kind": "door_slab", "position": Vector3(ROOM_W * 0.5, 0.0, 0.0), "outward": Vector3(1, 0, 0), "sim_room": "workshop", "blockable": false},
			{"id": "lift", "kind": "lift", "position": Vector3(0.0, 0.0, -ROOM_D * 0.5), "outward": Vector3(0, 0, -1), "sim_room": "lift", "blockable": false},
		],
		"required_stations": ["terminal", "hide_spot", "door_control_L", "door_control_R", "door_control_C"],
		"has_monitor": false,   # the monitor wall tells you the next task; there is no camera monitor in the Facility
		"mood": {"kind": "cold_monitor", "ambient": Color(0.38, 0.40, 0.55), "lamp": Color(1.0, 0.92, 0.75), "accent": Color(0.5, 1.0, 0.7)},
		"tone_cue": "static",
		"controls": ["nw_fac_beacon", "nw_fac_hide"],
		"references": {"2d_screenshot": "docs/night_watch_offices/control_room_2d.png"},
	})


func _c(parent: Node3D, size: Vector3, pos: Vector3, node_name: String, opts := {}) -> MeshInstance3D:
	var o := opts.duplicate()
	o["name"] = node_name
	return A.box(parent, size, pos, o)


func _prop(prop_name: String, pos := Vector3.ZERO) -> Node3D:
	var node := A.prop(self, prop_name, pos)
	props[prop_name] = node
	return node


func _body(size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)


func _station(id: String, prompt: String, pos: Vector3) -> NightWatchStation:
	var st := NightWatchStation.new()
	st.name = "Station_" + id
	st.station_id = id
	st.prompt_text = prompt
	st.position = pos
	add_child(st)
	stations[id] = st
	return st


func build() -> void:
	_shell()
	_monitor_wall()
	_desk()
	_extras()
	_doors()


func _shell() -> void:
	var tint := Color(0.85, 1.05, 1.2)
	var shell := _prop("Shell")
	_c(shell, Vector3(ROOM_W + 0.4, 0.2, ROOM_D + 0.4), Vector3(0, -0.1, 0), "Floor", {"solid": true, "tint": tint * Color(0.95, 0.95, 0.95)})
	_c(shell, Vector3(ROOM_W + 0.4, 0.2, ROOM_D + 0.4), Vector3(0, HEIGHT + 0.1, 0), "Ceiling", {"tint": tint * Color(0.6, 0.6, 0.6)})
	_c(shell, Vector3(ROOM_W + 0.4, HEIGHT, 0.2), Vector3(0, HEIGHT * 0.5, ROOM_D * 0.5 + 0.1), "WallSouth", {"solid": true, "tint": tint * Color(0.9, 0.9, 0.95)})
	var seg := (ROOM_W - DOOR_GAP) * 0.5
	for sgn in [-1.0, 1.0]:
		_c(shell, Vector3(seg, HEIGHT, 0.2), Vector3(sgn * (DOOR_GAP * 0.5 + seg * 0.5), HEIGHT * 0.5, -ROOM_D * 0.5 - 0.1), "WallNorthPiece", {"solid": true, "tint": tint})
	_c(shell, Vector3(DOOR_GAP, HEIGHT - DOOR_TOP, 0.2), Vector3(0, DOOR_TOP + (HEIGHT - DOOR_TOP) * 0.5, -ROOM_D * 0.5 - 0.1), "WallNorthLintel", {"tint": tint})
	for side in [-1.0, 1.0]:
		var dir := "L" if side < 0.0 else "R"
		var x: float = side * (ROOM_W * 0.5 + 0.1)
		var wall := _prop("Wall" + dir)
		var piece := (ROOM_D - DOOR_GAP) * 0.5
		for sgn in [-1.0, 1.0]:
			_c(wall, Vector3(0.2, HEIGHT, piece), Vector3(x, HEIGHT * 0.5, sgn * (DOOR_GAP * 0.5 + piece * 0.5)), "Wall%sPiece" % dir, {"solid": true, "tint": tint * Color(1.05, 1.05, 1.05)})
			_c(wall, Vector3(0.3, DOOR_TOP, 0.12), Vector3(x, DOOR_TOP * 0.5, sgn * (DOOR_GAP * 0.5 + 0.06)), "FramePost", {"tint": Color(0.75, 0.7, 0.65)})
		_c(wall, Vector3(0.2, HEIGHT - DOOR_TOP, DOOR_GAP), Vector3(x, DOOR_TOP + (HEIGHT - DOOR_TOP) * 0.5, 0), "Wall%sLintel" % dir, {"tint": tint})
		_c(wall, Vector3(0.12, 0.08, DOOR_GAP), Vector3(x - side * 0.1, DOOR_TOP - 0.05, 0), "HazardStripe", {"kind": "label", "tint": Color(0.85, 0.85, 0.85)})
	for z in [-ROOM_D * 0.5 + 0.04, ROOM_D * 0.5 - 0.04]:
		_c(shell, Vector3(ROOM_W, 0.2, 0.08), Vector3(0, 0.1, z), "Baseboard", {"tint": Color(0.7, 0.7, 0.75)})
		_c(shell, Vector3(ROOM_W, 0.1, 0.08), Vector3(0, HEIGHT - 0.05, z), "CrownTrim", {"tint": Color(0.8, 0.8, 0.85)})
	_c(shell, Vector3(ROOM_W - 0.6, 0.1, 0.1), Vector3(0, HEIGHT - 0.2, ROOM_D * 0.5 - 0.2), "PipeRoom", {"kind": "metal"})
	_c(shell, Vector3(1.2, 0.05, 1.2), Vector3(0, HEIGHT - 0.04, 0), "CeilingPanel", {})
	_c(shell, Vector3(ROOM_W, 0.02, 0.3), Vector3(0, 0.01, 0.8), "FloorStripe", {"kind": "label", "tint": Color(0.8, 0.8, 0.8)})
	room_light = OmniLight3D.new()
	room_light.name = "RoomLight"
	room_light.light_color = Color(1.0, 0.92, 0.75)
	room_light.light_energy = 1.1
	room_light.omni_range = 7.0
	room_light.position = Vector3(0, HEIGHT - 0.4, 0)
	add_child(room_light)


## A wall of monitors on each side of the lift door: two rows of four, in a steel bank with a ledge of switches under it.
func _monitor_wall() -> void:
	for side in [-1.0, 1.0]:
		var bank := _prop("MonitorBank%s" % ("L" if side < 0.0 else "R"), Vector3(side * 1.85, 0.0, -ROOM_D * 0.5 + 0.2))
		_c(bank, Vector3(2.0, 1.5, 0.12), Vector3(0, 1.75, 0), "BankFrame", {"kind": "metal", "tint": Color(0.7, 0.72, 0.8)})
		_c(bank, Vector3(2.0, 0.5, 0.3), Vector3(0, 0.75, 0.1), "BankLedge", {"kind": "metal", "tint": Color(0.8, 0.82, 0.9)})
		_body(Vector3(2.0, 0.9, 0.35), Vector3(side * 1.85, 0.45, -ROOM_D * 0.5 + 0.3))
		for row in 2:
			for col in 2:
				var screen := _c(bank, Vector3(0.84, 0.6, 0.05), Vector3(-0.47 + col * 0.94, 1.45 + row * 0.7, 0.08), "WallScreen", {"tint": Color(0.5 + 0.25 * ((row + col) % 2), 1.0, 0.8)})
				screens.append(screen)
		for i in 6:
			_c(bank, Vector3(0.08, 0.05, 0.08), Vector3(-0.8 + i * 0.32, 1.03, 0.2), "BankSwitch", {"kind": "red" if i % 3 == 0 else "plastic"})
	_station("monitor", "MONITOR WALL // WHAT IS NEXT ON THE LIST", Vector3(-1.85, 1.6, -ROOM_D * 0.5 + 0.4))


func _desk() -> void:
	var desk := _prop("Desk", Vector3(-1.2, 0, 1.9))
	_c(desk, Vector3(2.0, 0.08, 0.9), Vector3(0, 0.76, 0), "DeskTop", {})
	for x in [-0.9, 0.9]:
		_c(desk, Vector3(0.1, 0.76, 0.8), Vector3(x, 0.38, 0), "DeskLeg", {})
	_c(desk, Vector3(0.6, 0.45, 0.06), Vector3(0.0, 1.05, -0.1), "TerminalScreen", {})
	_c(desk, Vector3(0.7, 0.04, 0.3), Vector3(0.0, 0.8, 0.2), "KeypadBase", {"kind": "plastic"})
	for i in 3:
		for j in 4:
			_c(desk, Vector3(0.1, 0.03, 0.05), Vector3(-0.2 + i * 0.2, 0.83, 0.1 + j * 0.06), "KeypadKeys", {"kind": "metal", "tint": Color(1.1, 1.1, 1.15)})
	_body(Vector3(2.0, 0.9, 0.9), Vector3(-1.2, 0.45, 1.9))
	var note := _prop("Note", Vector3(-0.2, 0.8, 1.9))
	_c(note, Vector3(0.42, 0.012, 0.3), Vector3(0, 0.01, 0), "NotePaper", {"kind": "label", "tint": Color(1.2, 1.2, 1.1), "ao": 1.0})
	note_label = Label3D.new()
	note_label.name = "NoteCode"
	note_label.font_size = 36
	note_label.pixel_size = 0.004
	note_label.modulate = Color(0.1, 0.08, 0.05)
	note_label.outline_size = 0
	note_label.rotation = Vector3(-PI * 0.5, 0, 0)
	note_label.position = Vector3(0, 0.025, 0)
	note.add_child(note_label)
	_station("terminal", "TERMINAL // KEY IN THE CODE ON THE NOTE", Vector3(-1.2, 1.0, 1.7))
	var chair := _prop("DeskChair", Vector3(1.4, 0, 1.6))
	_c(chair, Vector3(0.5, 0.08, 0.5), Vector3(0, 0.45, 0), "ChairSeat", {})
	_c(chair, Vector3(0.5, 0.5, 0.08), Vector3(0, 0.75, 0.22), "ChairBack", {})
	_c(chair, Vector3(0.08, 0.45, 0.08), Vector3(0, 0.22, 0), "ChairColumn", {"kind": "metal"})
	_station("hide_spot", "HIDE UNDER THE DESK // HOLD H", Vector3(1.4, 0.6, 1.8))


## The task board, a vent, a filing cabinet and a cable run: what makes it a control room and not a box with a desk.
func _extras() -> void:
	var board := _prop("TaskBoard", Vector3(2.0, 1.7, ROOM_D * 0.5 - 0.1))
	_c(board, Vector3(1.4, 1.0, 0.06), Vector3.ZERO, "BoardFrame", {"kind": "wood"})
	_c(board, Vector3(1.28, 0.88, 0.03), Vector3(0, 0, -0.04), "BoardPaper", {"kind": "label", "tint": Color(1.2, 1.2, 1.1)})
	for i in 5:
		_c(board, Vector3(0.9, 0.05, 0.02), Vector3(-0.1, 0.32 - i * 0.16, -0.06), "BoardLabel", {"tint": Color(0.7, 0.7, 0.7)})
	var vent := _prop("VentGrille", Vector3(-2.2, 0.5, -ROOM_D * 0.5 + 0.1))
	_c(vent, Vector3(0.8, 0.5, 0.06), Vector3.ZERO, "VentFrame", {"kind": "metal"})
	for i in 4:
		_c(vent, Vector3(0.7, 0.04, 0.05), Vector3(0, -0.15 + i * 0.1, 0.04), "VentLouver", {"kind": "metal", "tint": Color(0.7, 0.7, 0.75)})
	var cabinet := _prop("Cabinet", Vector3(2.3, 0.0, -0.2))
	_c(cabinet, Vector3(0.5, 1.5, 0.7), Vector3(0.0, 0.75, 0), "LockerBody", {"tint": Color(0.75, 0.85, 1.0)})
	for i in 3:
		_c(cabinet, Vector3(0.04, 0.4, 0.6), Vector3(-0.27, 0.3 + i * 0.45, 0), "LockerDoor", {"kind": "metal", "tint": Color(0.9, 0.9, 0.95)})
	_body(Vector3(0.5, 1.5, 0.7), Vector3(2.3, 0.75, -0.2))
	var cables := _prop("Cables", Vector3(0, 0.03, -1.9))
	for i in 3:
		_c(cables, Vector3(0.05, 0.04, 1.4), Vector3(-0.3 + i * 0.3, 0, 0), "CableRun", {"kind": "plastic", "tint": Color(0.6 + 0.2 * i, 0.6, 0.8)})


func _doors() -> void:
	for side in [-1.0, 1.0]:
		var dir := "L" if side < 0.0 else "R"
		var to := "GALLERY" if side < 0.0 else "WORKSHOP"
		var plate := _prop("DoorPlate%s" % dir, Vector3(side * (ROOM_W * 0.5 - 0.1), 1.2, 1.15))
		_c(plate, Vector3(0.06, 0.3, 0.3), Vector3.ZERO, "DoorButton", {"kind": "green"})
		_station("door_control_%s" % dir, "GO %s // %s" % ["LEFT" if side < 0.0 else "RIGHT", to], Vector3(side * (ROOM_W * 0.5 - 0.15), 1.2, 1.15))
	var plate2 := _prop("DoorPlateC", Vector3(1.5, 1.2, -ROOM_D * 0.5 + 0.1))
	_c(plate2, Vector3(0.3, 0.3, 0.06), Vector3.ZERO, "DoorButton", {"kind": "green"})
	_station("door_control_C", "LIFT DOOR // GO IN", Vector3(1.5, 1.2, -ROOM_D * 0.5 + 0.1))
