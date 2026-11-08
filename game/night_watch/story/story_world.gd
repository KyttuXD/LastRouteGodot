class_name StoryWorld
extends Node3D

## The Facility: five blocky rooms in a row (breaker room, gallery, control, workshop, auditorium) joined by doorways in their shared walls, and the lift car
## north of Control. Every room has its own look and its own station: Control has the terminal (the code is on the note beside it) and the desk you hide under,
## the gallery five lamps with a dial each, the workshop a bench of parts, the auditorium a stage crank, the breaker room six numbered switches, the lift a
## call button you hold. Built from shaded cubes (NightWatchArt), in named prop groups; every station is a NightWatchStation (shared interactable).

const A := preload("res://game/night_watch/night_watch_art.gd")
const CELL := 6.0
const ROOM_W := 5.6
const ROOM_D := 5.0
const HEIGHT := 3.6
const DOOR_GAP := 1.5
const DOOR_TOP := 3.2
const ORDER := ["breaker", "gallery", "control", "workshop", "auditorium"]
const TINTS := {
	"breaker": Color(1.1, 1.0, 0.8), "gallery": Color(0.85, 0.8, 1.3), "control": Color(0.85, 1.05, 1.2), "workshop": Color(1.25, 1.0, 0.8),
	"auditorium": Color(1.3, 0.8, 0.9), "lift": Color(0.9, 0.95, 1.0),
}
const DIAL_STEP := TAU / 6.0
const SPAWN_OFFSET := 1.5   # how far inside the room the player appears after a door

var rooms := {}          # room id -> Node3D (floor centre)
var props := {}
var stations := {}       # station id -> NightWatchStation
var dial_nodes := []     # [{"root", "pointer", "mark"}]
var part_nodes := []
var switch_nodes := []   # [{"root", "lever", "num"}]
var crank_handle: Node3D
var note_label: Label3D
var lift_slab: Node3D
var lift_progress := 0.0
var lift_open := false
var lamps := {}


func _ready() -> void:
	if rooms.is_empty():
		build()


func _c(parent: Node3D, size: Vector3, pos: Vector3, node_name: String, opts := {}) -> MeshInstance3D:
	var o := opts.duplicate()
	o["name"] = node_name
	return A.box(parent, size, pos, o)


func _group(id: String, prop_name: String, pos := Vector3.ZERO) -> Node3D:
	var node := A.prop(rooms[id], prop_name, pos)
	props["%s/%s" % [id, prop_name]] = node
	return node


func _station(id: String, prompt: String, parent: Node3D, pos: Vector3, focus := Vector3.ZERO) -> NightWatchStation:
	var st := NightWatchStation.new()
	st.name = "Station_" + id
	st.station_id = id
	st.prompt_text = prompt
	st.focus_local = focus
	st.position = pos
	parent.add_child(st)
	stations[id] = st
	return st


func build() -> void:
	for i in ORDER.size():
		var id: String = ORDER[i]
		if id == "control":
			_build_control_office()
			continue
		var room := Node3D.new()
		room.name = "Room_%s" % id
		room.position = Vector3((i - 2) * CELL, 0.0, 0.0)
		add_child(room)
		rooms[id] = room
		_build_room(id, room)
	var lift := Node3D.new()
	lift.name = "Room_lift"
	lift.position = Vector3(0.0, 0.0, -4.1)
	add_child(lift)
	rooms["lift"] = lift
	_build_lift(lift)
	_gallery_extras()
	_workshop_extras()
	_auditorium_extras()
	_breaker_extras()
	_decor()
	_door_stations()


## Which sides of a room have a doorway: L / R toward a neighbour, C (north) only in Control.
func has_door(id: String, dir: String) -> bool:
	var i := ORDER.find(id)
	if i < 0:
		return false
	if dir == "L":
		return i > 0
	if dir == "R":
		return i < ORDER.size() - 1
	return id == "control" and dir == "C"


## Control is the Facility's office (ControlRoomOffice, the OFFICE CONTRACT): its stations and props join the world's.
func _build_control_office() -> void:
	var office := NightWatchOfficeRegistry.make("story") as ControlRoomOffice
	office.name = "Room_control"
	add_child(office)
	rooms["control"] = office
	for sid in office.stations:
		stations[sid] = office.stations[sid]
	for pname in office.props:
		props["control/%s" % pname] = office.props[pname]
	note_label = office.note_label
	lamps["control"] = office.room_light


func _wall_x(id: String, room: Node3D, side: float, tint: Color) -> void:
	var x: float = side * (ROOM_W * 0.5 + 0.1)
	var dir := "L" if side < 0.0 else "R"
	var shell := A.prop(room, "Wall" + dir, Vector3.ZERO)
	props["%s/Wall%s" % [id, dir]] = shell
	if not has_door(id, dir):
		_c(shell, Vector3(0.2, HEIGHT, ROOM_D), Vector3(x, HEIGHT * 0.5, 0), "Wall%sFull" % dir, {"solid": true, "tint": tint})
		return
	var seg := (ROOM_D - DOOR_GAP) * 0.5
	for sgn in [-1.0, 1.0]:
		_c(shell, Vector3(0.2, HEIGHT, seg), Vector3(x, HEIGHT * 0.5, sgn * (DOOR_GAP * 0.5 + seg * 0.5)), "Wall%sPiece" % dir, {"solid": true, "tint": tint})
	_c(shell, Vector3(0.2, HEIGHT - DOOR_TOP, DOOR_GAP), Vector3(x, DOOR_TOP + (HEIGHT - DOOR_TOP) * 0.5, 0), "Wall%sLintel" % dir, {"tint": tint * Color(0.9, 0.9, 0.9)})
	for sgn in [-1.0, 1.0]:
		_c(shell, Vector3(0.3, DOOR_TOP, 0.12), Vector3(x, DOOR_TOP * 0.5, sgn * (DOOR_GAP * 0.5 + 0.06)), "FramePost", {"tint": Color(0.75, 0.7, 0.65)})
	_c(shell, Vector3(0.12, 0.08, DOOR_GAP), Vector3(x - side * 0.1, DOOR_TOP - 0.05, 0), "HazardStripe", {"kind": "label", "tint": Color(0.85, 0.85, 0.85)})


func _build_room(id: String, room: Node3D) -> void:
	var tint: Color = TINTS[id]
	var shell := _group(id, "Shell")
	_c(shell, Vector3(ROOM_W + 0.4, 0.2, ROOM_D + 0.4), Vector3(0, -0.1, 0), "Floor", {"solid": true, "tint": tint * Color(0.95, 0.95, 0.95)})
	_c(shell, Vector3(ROOM_W + 0.4, 0.2, ROOM_D + 0.4), Vector3(0, HEIGHT + 0.1, 0), "Ceiling", {"tint": tint * Color(0.6, 0.6, 0.6)})
	var north_w := ROOM_W + 0.4
	if id == "control":
		var seg := (ROOM_W - DOOR_GAP) * 0.5
		for sgn in [-1.0, 1.0]:
			_c(shell, Vector3(seg, HEIGHT, 0.2), Vector3(sgn * (DOOR_GAP * 0.5 + seg * 0.5), HEIGHT * 0.5, -ROOM_D * 0.5 - 0.1), "WallNorthPiece", {"solid": true, "tint": tint})
		_c(shell, Vector3(DOOR_GAP, HEIGHT - DOOR_TOP, 0.2), Vector3(0, DOOR_TOP + (HEIGHT - DOOR_TOP) * 0.5, -ROOM_D * 0.5 - 0.1), "WallNorthLintel", {"tint": tint})
	else:
		_c(shell, Vector3(north_w, HEIGHT, 0.2), Vector3(0, HEIGHT * 0.5, -ROOM_D * 0.5 - 0.1), "WallNorth", {"solid": true, "tint": tint})
	_c(shell, Vector3(north_w, HEIGHT, 0.2), Vector3(0, HEIGHT * 0.5, ROOM_D * 0.5 + 0.1), "WallSouth", {"solid": true, "tint": tint * Color(0.9, 0.9, 0.95)})
	_wall_x(id, room, -1.0, tint * Color(1.05, 1.05, 1.05))
	_wall_x(id, room, 1.0, tint * Color(1.05, 1.05, 1.05))
	for z in [-ROOM_D * 0.5 + 0.04, ROOM_D * 0.5 - 0.04]:
		_c(shell, Vector3(ROOM_W, 0.2, 0.08), Vector3(0, 0.1, z), "Baseboard", {"tint": Color(0.7, 0.7, 0.75)})
		_c(shell, Vector3(ROOM_W, 0.1, 0.08), Vector3(0, HEIGHT - 0.05, z), "CrownTrim", {"tint": Color(0.8, 0.8, 0.85)})
	_c(shell, Vector3(ROOM_W - 0.6, 0.1, 0.1), Vector3(0, HEIGHT - 0.2, ROOM_D * 0.5 - 0.2), "PipeRoom", {"kind": "metal"})
	_c(shell, Vector3(1.2, 0.05, 1.2), Vector3(0, HEIGHT - 0.04, 0), "CeilingPanel", {})
	var lamp := OmniLight3D.new()
	lamp.name = "RoomLight"
	lamp.light_color = Color(1.0, 0.92, 0.75)
	lamp.light_energy = 1.1
	lamp.omni_range = 7.0
	lamp.position = Vector3(0, HEIGHT - 0.4, 0)
	room.add_child(lamp)
	lamps[id] = lamp
	_c(_group(id, "Details"), Vector3(0.3, 0.02, 0.3), Vector3(2.0, 0.01, 1.8), "FloorDrain", {"kind": "metal", "tint": Color(0.6, 0.6, 0.65)})
	_c(_group(id, "Sign", Vector3(0, 2.4, ROOM_D * 0.5 - 0.1)), Vector3(1.4, 0.3, 0.05), Vector3.ZERO, "SignPlate", {"kind": "plastic"})
	_c(props["%s/Sign" % id], Vector3(1.2, 0.18, 0.03), Vector3(0, 0, -0.04), "SignText", {"tint": tint})


func _build_lift(lift: Node3D) -> void:
	var car := A.prop(lift, "LiftCar")
	props["lift/LiftCar"] = car
	_c(car, Vector3(3.2, 0.2, 3.2), Vector3(0, -0.1, 0), "Floor", {"solid": true, "kind": "metal", "tint": Color(0.9, 0.9, 0.95)})
	_c(car, Vector3(3.2, 0.2, 3.2), Vector3(0, HEIGHT + 0.1, 0), "Ceiling", {"tint": Color(0.6, 0.6, 0.65)})
	_c(car, Vector3(0.2, HEIGHT, 3.2), Vector3(-1.6, HEIGHT * 0.5, 0), "WallWest", {"solid": true, "kind": "metal", "tint": Color(0.9, 0.95, 1.0)})
	_c(car, Vector3(0.2, HEIGHT, 3.2), Vector3(1.6, HEIGHT * 0.5, 0), "WallEast", {"solid": true, "kind": "metal", "tint": Color(0.9, 0.95, 1.0)})
	_c(car, Vector3(3.2, HEIGHT, 0.2), Vector3(0, HEIGHT * 0.5, -1.7), "WallNorth", {"solid": true, "kind": "metal", "tint": Color(0.85, 0.9, 1.0)})
	for x in [-1.45, 1.45]:
		_c(car, Vector3(0.1, 2.0, 0.06), Vector3(x, 1.2, -1.6), "LiftRail", {"kind": "metal", "tint": Color(1.2, 1.2, 1.25)})
	_c(car, Vector3(1.0, 0.25, 0.04), Vector3(0, 2.5, -1.58), "SignFloorNumber", {"tint": Color(0.5, 1.0, 0.6)})
	var lamp := OmniLight3D.new()
	lamp.name = "LiftLight"
	lamp.light_color = Color(0.85, 0.95, 1.0)
	lamp.light_energy = 0.9
	lamp.omni_range = 4.5
	lamp.position = Vector3(0, 2.6, 0)
	lift.add_child(lamp)
	lamps["lift"] = lamp
	# the call button panel on the east wall, and the lift door in Control's north wall (a slab that rises)
	var panel := A.prop(lift, "CallPanel")
	props["lift/CallPanel"] = panel
	_c(panel, Vector3(0.1, 0.5, 0.36), Vector3(1.48, 1.3, 0.2), "PanelHousing", {})
	_c(panel, Vector3(0.06, 0.22, 0.22), Vector3(1.4, 1.3, 0.2), "CallButton", {"kind": "red"})
	_station("lift_button", "CALL BUTTON // HOLD E", lift, Vector3(1.4, 1.3, 0.2), Vector3(0, 0, 0))
	lift_slab = Node3D.new()
	lift_slab.name = "LiftSlab"
	add_child(lift_slab)
	lift_slab.position = Vector3(0.0, DOOR_TOP * 0.5, -ROOM_D * 0.5 - 0.1)
	_c(lift_slab, Vector3(DOOR_GAP - 0.04, DOOR_TOP, 0.12), Vector3.ZERO, "SlabBody", {"kind": "metal", "tint": Color(0.9, 0.9, 0.95)})
	for i in 3:
		_c(lift_slab, Vector3(DOOR_GAP - 0.02, 0.08, 0.14), Vector3(0, -0.8 + i * 0.8, 0), "SlabStripe", {"kind": "label", "tint": Color(0.8, 0.8, 0.8)})
	set_lift_open(false)


func _gallery_extras() -> void:
	var wall := _group("gallery", "Lamps", Vector3(0, 0, -ROOM_D * 0.5 + 0.2))
	_c(wall, Vector3(4.8, 1.6, 0.1), Vector3(0, 1.4, 0), "LampBoard", {"tint": Color(0.7, 0.7, 0.8)})
	for i in 5:
		var root := Node3D.new()
		root.name = "Dial%d" % i
		root.position = Vector3(-2.0 + i * 1.0, 1.4, 0.12)
		wall.add_child(root)
		_c(root, Vector3(0.7, 0.7, 0.06), Vector3.ZERO, "DialFace", {"kind": "plastic", "tint": Color(1.3, 1.3, 1.4)})
		var mark := Node3D.new()
		mark.name = "MarkPivot"
		root.add_child(mark)
		_c(mark, Vector3(0.1, 0.12, 0.05), Vector3(0, 0.3, 0.05), "DialMarkGlow", {"tint": Color(1.0, 0.8, 0.3)})
		var pointer := Node3D.new()
		pointer.name = "PointerPivot"
		root.add_child(pointer)
		_c(pointer, Vector3(0.08, 0.26, 0.06), Vector3(0, 0.13, 0.06), "DialNeedle", {"kind": "red"})
		_c(root, Vector3(0.14, 0.14, 0.1), Vector3.ZERO, "DialHub", {"kind": "metal"})
		_station("dial_%d" % i, "LAMP DIAL // TURN ONE STEP", wall, root.position + Vector3(0, 0, 0.1), Vector3.ZERO)
		dial_nodes.append({"root": root, "pointer": pointer, "mark": mark})


func _workshop_extras() -> void:
	var bench := _group("workshop", "Bench", Vector3(0, 0, -ROOM_D * 0.5 + 0.7))
	_c(bench, Vector3(4.6, 0.9, 0.9), Vector3(0, 0.45, 0), "BenchBody", {})
	_c(bench, Vector3(4.7, 0.06, 1.0), Vector3(0, 0.93, 0), "BenchTop", {"kind": "wood", "tint": Color(1.2, 1.1, 1.0)})
	for i in 6:
		var part := Node3D.new()
		part.name = "Part%d" % i
		part.position = Vector3(-2.0 + i * 0.8, 0.96, 0.0)
		bench.add_child(part)
		_c(part, Vector3(0.3, 0.2, 0.3), Vector3(0, 0.1, 0), "PartBlock", {"kind": ["metal", "red", "green"][i % 3], "tint": Color(1.1, 1.1, 1.1)})
		_c(part, Vector3(0.1, 0.12, 0.1), Vector3(0, 0.26, 0), "PartKnob", {"kind": "plastic"})
		_station("part_%d" % i, "TAKE THE PART", bench, part.position + Vector3(0, 0.15, 0.0), Vector3.ZERO)
		part_nodes.append(part)
	var racks := _group("workshop", "Racks", Vector3(2.4, 0, 1.4))
	_c(racks, Vector3(0.5, 2.0, 1.6), Vector3(0, 1.0, 0), "RackBody", {"kind": "metal"})
	for y in [0.5, 1.0, 1.5]:
		_c(racks, Vector3(0.52, 0.05, 1.5), Vector3(0, y, 0), "RackShelf", {"kind": "metal", "tint": Color(1.1, 1.1, 1.1)})


func _auditorium_extras() -> void:
	var stage := _group("auditorium", "Stage", Vector3(0, 0, -1.4))
	_c(stage, Vector3(4.2, 0.4, 1.8), Vector3(0, 0.2, 0), "PlatformDeck", {})
	_c(stage, Vector3(4.3, 0.06, 1.9), Vector3(0, 0.42, 0), "PlatformEdge", {"tint": Color(1.2, 1.2, 1.2)})
	for x in [-2.4, 2.4]:
		_c(stage, Vector3(0.5, 2.4, 0.14), Vector3(x, 1.4, -0.9), "CurtainDrape", {"tint": Color(1.1, 0.35, 0.4)})
	var crank := _group("auditorium", "Crank", Vector3(0.0, 0.0, 0.2))
	_c(crank, Vector3(0.5, 0.9, 0.5), Vector3(0, 0.45, 0), "CrankBox", {"kind": "metal", "tint": Color(0.9, 0.9, 0.95)})
	crank_handle = Node3D.new()
	crank_handle.name = "CrankHandlePivot"
	crank_handle.position = Vector3(0, 0.95, 0.3)
	crank.add_child(crank_handle)
	_c(crank_handle, Vector3(0.7, 0.08, 0.08), Vector3(0.3, 0, 0), "CrankArm", {"kind": "metal"})
	_c(crank_handle, Vector3(0.1, 0.25, 0.1), Vector3(0.62, 0.1, 0), "CrankGrip", {"kind": "red"})
	_station("crank", "STAGE CRANK // TURN", crank, Vector3(0, 1.0, 0.3), Vector3.ZERO)
	for row in 2:
		for col in 4:
			var seat := _group("auditorium", "Seat%d_%d" % [row, col], Vector3(-1.8 + col * 1.2, 0, 1.2 + row * 0.9))
			_c(seat, Vector3(0.5, 0.08, 0.5), Vector3(0, 0.45, 0), "ChairSeat", {})
			_c(seat, Vector3(0.5, 0.5, 0.08), Vector3(0, 0.75, 0.22), "ChairBack", {})


func _breaker_extras() -> void:
	var board := _group("breaker", "Breakers", Vector3(0, 0, -ROOM_D * 0.5 + 0.2))
	_c(board, Vector3(4.6, 1.8, 0.12), Vector3(0, 1.4, 0), "BreakerBoard", {"kind": "metal", "tint": Color(0.8, 0.8, 0.85)})
	for i in 6:
		var root := Node3D.new()
		root.name = "Switch%d" % i
		root.position = Vector3(-1.9 + i * 0.76, 1.4, 0.1)
		board.add_child(root)
		_c(root, Vector3(0.3, 0.7, 0.06), Vector3.ZERO, "SwitchPlate", {"kind": "plastic", "tint": Color(1.3, 1.3, 1.35)})
		var lever := Node3D.new()
		lever.name = "LeverPivot"
		lever.position = Vector3(0, 0, 0.05)
		root.add_child(lever)
		_c(lever, Vector3(0.08, 0.3, 0.08), Vector3(0, 0.15, 0), "SwitchLever", {"kind": "red"})
		var num := Label3D.new()
		num.name = "SwitchNumber"
		num.text = ""
		num.font_size = 40
		num.pixel_size = 0.004
		num.modulate = Color(1.0, 0.85, 0.3)
		num.position = Vector3(0, 0.5, 0.06)
		root.add_child(num)
		_station("switch_%d" % i, "BREAKER // FLIP", board, root.position + Vector3(0, 0, 0.1), Vector3.ZERO)
		switch_nodes.append({"root": root, "lever": lever, "num": num})


## Lockers, crates, pipes and a cabinet so every room has something in it besides its station.
func _decor() -> void:
	for id in ORDER:
		if id == "control":
			continue
		var clutter := _group(id, "Clutter", Vector3(-2.2, 0, 1.6))
		_c(clutter, Vector3(0.7, 0.7, 0.7), Vector3(0, 0.35, 0), "CrateBox", {"tint": Color(0.9 + 0.1 * ORDER.find(id), 0.85, 0.8)})
		_c(clutter, Vector3(0.74, 0.06, 0.74), Vector3(0, 0.5, 0), "CrateBand", {"kind": "metal", "tint": Color(0.8, 0.8, 0.85)})
		_c(clutter, Vector3(0.4, 0.4, 0.4), Vector3(0.6, 0.2, 0.3), "CrateBox", {"tint": Color(0.8, 0.8, 0.9)})
		var cab := _group(id, "Cabinet", Vector3(2.3, 0, -1.9) if id != "gallery" and id != "breaker" else Vector3(2.3, 0, 1.4))
		_c(cab, Vector3(0.6, 1.8, 0.7), Vector3(0, 0.9, 0), "LockerBody", {"tint": Color(0.75, 0.85, 1.0)})
		_c(cab, Vector3(0.04, 1.6, 0.6), Vector3(-0.32, 0.9, 0), "LockerDoor", {"kind": "metal", "tint": Color(0.9, 0.9, 0.95)})
		_c(cab, Vector3(0.05, 0.08, 0.14), Vector3(-0.35, 1.0, 0.2), "LockerHandle", {"kind": "plastic"})
		var pipes := _group(id, "Pipes", Vector3(0, HEIGHT - 0.35, -ROOM_D * 0.5 + 0.25))
		_c(pipes, Vector3(ROOM_W - 0.4, 0.14, 0.14), Vector3.ZERO, "PipeRun", {"kind": "metal"})
		for x in [-2.0, 0.0, 2.0]:
			_c(pipes, Vector3(0.18, 0.2, 0.18), Vector3(x, 0, 0), "PipeClamp", {"kind": "metal", "tint": Color(0.8, 0.8, 0.85)})


func _door_stations() -> void:
	for id in ORDER:
		if id == "control":
			continue
		for dir in ["L", "R"]:
			if not has_door(id, dir):
				continue
			var to: String = StoryData.ROOMS[id]["exits"][dir]
			var sgn := -1.0 if dir == "L" else 1.0
			_station("door_%s_%s" % [id, dir], "GO %s // %s" % ["LEFT" if dir == "L" else "RIGHT", StoryData.ROOMS[to]["label"]], rooms[id],
				Vector3(sgn * (ROOM_W * 0.5 - 0.15), 1.2, 1.15), Vector3.ZERO)
			var plate := A.prop(rooms[id], "DoorPlate%s" % dir, Vector3(sgn * (ROOM_W * 0.5 - 0.1), 1.2, 1.15))
			props["%s/DoorPlate%s" % [id, dir]] = plate
			_c(plate, Vector3(0.06, 0.3, 0.3), Vector3.ZERO, "DoorButton", {"kind": "green"})
	_station("door_lift_C", "LIFT DOOR // GO OUT TO CONTROL", rooms["lift"], Vector3(-1.4, 1.2, 1.4), Vector3.ZERO)
	var plate3 := A.prop(rooms["lift"], "DoorPlateC", Vector3(-1.4, 1.2, 1.4))
	props["lift/DoorPlateC"] = plate3
	_c(plate3, Vector3(0.06, 0.3, 0.3), Vector3.ZERO, "DoorButton", {"kind": "green"})


# --- the things the scene drives ----------------------------------------------------------------------------------------

func set_lift_open(on: bool) -> void:
	lift_open = on


func animate(delta: float) -> void:
	var target := 1.0 if lift_open else 0.0
	lift_progress = move_toward(lift_progress, target, delta * 2.0)
	lift_slab.position.y = lerpf(DOOR_TOP * 0.5, DOOR_TOP + 1.3, lift_progress)


func snap() -> void:
	lift_progress = 1.0 if lift_open else 0.0
	lift_slab.position.y = lerpf(DOOR_TOP * 0.5, DOOR_TOP + 1.3, lift_progress)


## Show the current puzzle on its station (dials with their marks, parts on the bench, the numbered breakers, the crank's turns, the note's code).
func show_puzzle(z: Dictionary) -> void:
	var kind := String(z.get("kind", ""))
	note_label.text = _spaced(String(z["code"])) if kind == "code" else ""
	for i in dial_nodes.size():
		var d: Dictionary = dial_nodes[i]
		var show := kind == "dials" and i < int(z.get("n", 0))
		(d["root"] as Node3D).visible = show
		(stations["dial_%d" % i] as NightWatchStation).disabled = not show
		if show:
			(d["pointer"] as Node3D).rotation.z = -int(z["pos"][i]) * DIAL_STEP
			(d["mark"] as Node3D).rotation.z = -int(z["target"][i]) * DIAL_STEP
	for i in part_nodes.size():
		var shown := kind == "collect" and i < int(z.get("n", 0)) and not (z["taken"] as Array).has(i)
		(part_nodes[i] as Node3D).visible = shown
		(stations["part_%d" % i] as NightWatchStation).disabled = not shown
	for i in switch_nodes.size():
		var s: Dictionary = switch_nodes[i]
		var live := kind == "switches" and i < int(z.get("n", 0))
		(s["root"] as Node3D).visible = live
		(stations["switch_%d" % i] as NightWatchStation).disabled = not live
		if live:
			var rank: int = (z["order"] as Array).find(i)
			(s["num"] as Label3D).text = str(rank + 1)
			(s["lever"] as Node3D).rotation.z = 0.0 if rank >= int(z["next"]) else PI * 0.8
	(stations["crank"] as NightWatchStation).disabled = kind != "crank"
	crank_handle.rotation.y = (int(z.get("done", 0)) * 0.5) if kind == "crank" else 0.0
	(stations["terminal"] as NightWatchStation).disabled = kind != "code"


func _spaced(code: String) -> String:
	var out := []
	for ch in code:
		out.append(ch)
	return " ".join(out)


## Where the player stands after walking through a door: `dir` is the door they took ("L", "R" or "C") from the room before `to`.
func arrival(to: String, dir: String) -> Vector3:
	var c := (rooms[to] as Node3D).global_position
	if dir == "C":
		return c + (Vector3(0.0, 0.0, 1.0) if to == "lift" else Vector3(0.0, 0.0, -ROOM_D * 0.5 + 1.4))
	return c + Vector3((1.0 if dir == "L" else -1.0) * (ROOM_W * 0.5 - SPAWN_OFFSET), 0.0, 0.0)


## The doorway of `room` in direction `dir`, on the floor (the lift door is in Control's north wall).
func door_point(room: String, dir: String) -> Vector3:
	if dir == "C":
		return Vector3(0.0, 0.0, -ROOM_D * 0.5 - 0.1)
	var c := (rooms[room] as Node3D).global_position
	return c + Vector3((-1.0 if dir == "L" else 1.0) * (ROOM_W * 0.5 + 0.1), 0.0, 0.0)
