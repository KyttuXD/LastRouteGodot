class_name LureWorld
extends Node3D

## Dead Air's attraction hall, the part the cameras look into: six blocky rooms (lobby, arcade, party room, ball pit, prize counter, storage)
## on a 3 x 2 grid and two vent ducts, far from the office. The grid is chosen so that every connection of LureData.GRAPH is two rooms
## side by side with a doorway in the wall between them, and every room's south side is open to the lane the feed cameras look over
## (the same layout idea as NightWatchBuilding). Built from shaded cubes (NightWatchArt), in named prop groups. Generated, so identical everywhere.

const A := preload("res://src/night_watch/night_watch_art.gd")
const CELL := 8.0
const ROOM_W := 6.0
const ROOM_H := 3.2
const ORIGIN := Vector3(-8.0, 0.0, -40.0)
const DOOR_GAP := 1.8
const DOOR_TOP := 2.5

const COLORS := {
	"lobby": Color(1.3, 1.05, 0.8), "arcade": Color(0.85, 0.8, 1.35), "party": Color(1.3, 0.8, 1.0), "ballpit": Color(0.8, 1.15, 1.35),
	"prize": Color(1.3, 1.15, 0.75), "storage": Color(0.95, 0.95, 0.9), "ventl": Color(0.85, 0.95, 1.05), "ventr": Color(0.85, 0.95, 1.05),
}

var rooms := {}   # room id -> Node3D (the room's centre on the floor)
var props := {}   # "room/prop" -> Node3D


func _ready() -> void:
	if rooms.is_empty():
		build()


func build() -> void:
	for id in LureData.ROOMS:
		var room := Node3D.new()
		room.name = "Room_%s" % id
		var grid: Vector2i = LureData.INFO[id]["grid"]
		room.position = ORIGIN + Vector3(grid.x * CELL, 0.0, grid.y * CELL)
		add_child(room)
		rooms[id] = room
		_build_room(room, String(id), COLORS.get(id, Color.WHITE))


func _c(parent: Node3D, size: Vector3, pos: Vector3, node_name: String, opts := {}) -> MeshInstance3D:
	var o := opts.duplicate()
	o["name"] = node_name
	return A.box(parent, size, pos, o)


func _group(room: Node3D, id: String, prop_name: String, pos := Vector3.ZERO) -> Node3D:
	var node := A.prop(room, prop_name, pos)
	props["%s/%s" % [id, prop_name]] = node
	return node


## A doorway in `side` ("N", "W", "E") of room `id` when the graph joins it to the room next to it on that side.
func has_doorway(side: String, id: String) -> bool:
	var g: Vector2i = LureData.INFO[id]["grid"]
	var d := Vector2i(0, -1) if side == "N" else (Vector2i(-1, 0) if side == "W" else Vector2i(1, 0))
	for other in LureData.GRAPH.get(id, []):
		if LureData.INFO[other].has("grid") and (LureData.INFO[other]["grid"] as Vector2i) == g + d:
			return true
	return false


func _wall(shell: Node3D, side: String, id: String, tint: Color) -> void:
	var half := ROOM_W * 0.5
	var along_x := side == "N"
	var centre := Vector3(0, ROOM_H * 0.5, -half) if side == "N" else Vector3(-half if side == "W" else half, ROOM_H * 0.5, 0)
	var thick := 0.2
	var wname := "Wall" + side
	if not has_doorway(side, id):
		_c(shell, Vector3(ROOM_W, ROOM_H, thick) if along_x else Vector3(thick, ROOM_H, ROOM_W), centre, wname, {"tint": tint})
		return
	var seg := (ROOM_W - DOOR_GAP) * 0.5
	var off := DOOR_GAP * 0.5 + seg * 0.5
	for sgn in [-1.0, 1.0]:
		var c := centre + (Vector3(sgn * off, 0, 0) if along_x else Vector3(0, 0, sgn * off))
		_c(shell, Vector3(seg, ROOM_H, thick) if along_x else Vector3(thick, ROOM_H, seg), c, wname if sgn < 0 else wname + "2", {"tint": tint})
	var lintel_h := ROOM_H - DOOR_TOP
	_c(shell, Vector3(DOOR_GAP, lintel_h, thick) if along_x else Vector3(thick, lintel_h, DOOR_GAP),
		Vector3(centre.x, DOOR_TOP + lintel_h * 0.5, centre.z), wname + "Lintel", {"tint": tint * Color(0.9, 0.9, 0.9)})


func _build_room(room: Node3D, id: String, tint: Color) -> void:
	var half := ROOM_W * 0.5
	var shell := _group(room, id, "Shell")
	_c(shell, Vector3(ROOM_W, 0.2, ROOM_W), Vector3(0, -0.1, 0), "Floor", {"tint": tint * Color(0.95, 0.95, 0.95)})
	_c(shell, Vector3(ROOM_W, 0.2, ROOM_W), Vector3(0, ROOM_H + 0.1, 0), "Ceiling", {"tint": tint * Color(0.6, 0.6, 0.6)})
	_wall(shell, "N", id, tint)
	_wall(shell, "W", id, tint * Color(1.05, 1.05, 1.05))
	_wall(shell, "E", id, tint * Color(1.05, 1.05, 1.05))
	_c(shell, Vector3(ROOM_W, 0.24, 0.08), Vector3(0, 0.12, -half + 0.14), "Baseboard", {"tint": Color(0.7, 0.7, 0.75)})
	for sx in [-half + 0.14, half - 0.14]:
		_c(shell, Vector3(0.08, 0.24, ROOM_W), Vector3(sx, 0.12, 0), "Baseboard", {"tint": Color(0.7, 0.7, 0.75)})
		_c(shell, Vector3(0.08, 0.12, ROOM_W), Vector3(sx, ROOM_H - 0.06, 0), "CrownTrim", {"tint": Color(0.85, 0.85, 0.9)})
	_c(shell, Vector3(ROOM_W, 0.12, 0.08), Vector3(0, ROOM_H - 0.06, -half + 0.14), "CrownTrim", {"tint": Color(0.85, 0.85, 0.9)})
	_c(shell, Vector3(ROOM_W - 0.4, 0.11, 0.11), Vector3(0, ROOM_H - 0.22, -half + 0.2), "PipeRoom", {"kind": "metal"})
	_c(shell, Vector3(1.4, 0.05, 1.4), Vector3(0, ROOM_H - 0.04, 0), "CeilingPanel", {})
	_c(shell, Vector3(ROOM_W, 0.02, 0.3), Vector3(0, 0.01, 0.8), "FloorStripe", {"kind": "label", "tint": Color(0.8, 0.8, 0.8)})
	# an air grille on the north wall and a little clutter in every room
	var detail := _group(room, id, "Details")
	_c(detail, Vector3(0.7, 0.4, 0.06), Vector3(1.9, 2.5, -half + 0.14), "VentGrille", {"kind": "metal"})
	for i in 3:
		_c(detail, Vector3(0.6, 0.03, 0.04), Vector3(1.9, 2.4 + i * 0.1, -half + 0.19), "VentSlat", {"kind": "plastic"})
	_c(detail, Vector3(0.3, 0.02, 0.3), Vector3(2.0, 0.01, 1.6), "FloorDrain", {"kind": "metal", "tint": Color(0.6, 0.6, 0.65)})
	_c(detail, Vector3(0.2, 0.2, 0.2), Vector3(-2.4, 0.1, 2.0), "ClutterBox", {"kind": "wood", "tint": Color(0.9, 0.85, 0.8)})
	match id:
		"lobby":
			_lobby(room, id)
		"arcade":
			_arcade(room, id)
		"party":
			_party(room, id)
		"ballpit":
			_ballpit(room, id)
		"prize":
			_prize(room, id)
		"storage":
			_storage(room, id, half)
		"ventl", "ventr":
			_duct(room, id, half)


func _lobby(room: Node3D, id: String) -> void:
	var desk := _group(room, id, "ReceptionDesk", Vector3(0, 0, -1.9))
	_c(desk, Vector3(2.6, 1.0, 0.8), Vector3(0, 0.5, 0), "FrontBody", {"kind": "wood", "tint": Color(1.2, 0.9, 0.8)})
	_c(desk, Vector3(2.7, 0.06, 0.9), Vector3(0, 1.03, 0), "FrontTop", {"kind": "metal", "tint": Color(1.2, 1.2, 1.25)})
	_c(desk, Vector3(0.3, 0.2, 0.05), Vector3(0.7, 1.15, 0.1), "BellBase", {"kind": "metal"})
	var sign_group := _group(room, id, "WelcomeSign", Vector3(0, 2.4, -2.75))
	_c(sign_group, Vector3(3.0, 0.5, 0.06), Vector3.ZERO, "SignPlate", {"kind": "plastic"})
	_c(sign_group, Vector3(2.7, 0.3, 0.03), Vector3(0, 0, 0.04), "SignWelcome", {"tint": Color(1.0, 0.8, 0.5)})
	var rope := _group(room, id, "Ropes", Vector3(0, 0, 0.6))
	for x in [-1.6, 1.6]:
		_c(rope, Vector3(0.08, 0.9, 0.08), Vector3(x, 0.45, 0), "RopePost", {"kind": "metal"})
	_c(rope, Vector3(3.2, 0.05, 0.05), Vector3(0, 0.8, 0), "RopeCord", {"kind": "fabric", "tint": Color(1.4, 0.6, 0.6)})


func _arcade(room: Node3D, id: String) -> void:
	for i in 4:
		var cab := _group(room, id, "Cabinet%d" % i, Vector3(-2.2 + i * 1.5, 0, -2.2))
		_c(cab, Vector3(0.9, 1.8, 0.8), Vector3(0, 0.9, 0), "CabinetBody", {"kind": "plastic", "tint": Color(0.7 + 0.2 * i, 0.8, 1.4 - 0.15 * i)})
		_c(cab, Vector3(0.7, 0.5, 0.04), Vector3(0, 1.4, 0.42), "CabinetScreen", {"tint": Color(0.5 + 0.2 * i, 1.0, 0.8)})
		_c(cab, Vector3(0.8, 0.1, 0.4), Vector3(0, 0.95, 0.5), "CabinetDeck", {"kind": "metal"})
		_c(cab, Vector3(0.1, 0.1, 0.1), Vector3(-0.18, 1.05, 0.55), "CabinetStick", {"kind": "red"})
	var claw := _group(room, id, "ClawMachine", Vector3(2.3, 0, 0.6))
	_c(claw, Vector3(1.0, 0.8, 1.0), Vector3(0, 0.4, 0), "ClawBase", {"kind": "metal", "tint": Color(1.2, 0.9, 0.9)})
	_c(claw, Vector3(1.0, 1.1, 1.0), Vector3(0, 1.35, 0), "ClawGlass", {"kind": "glass"})
	for i in 5:
		_c(claw, Vector3(0.2, 0.2, 0.2), Vector3(-0.3 + (i % 3) * 0.3, 0.9, -0.2 + (i / 3) * 0.3), "ClawPlush", {"kind": "fabric", "tint": Color(1.2 + 0.1 * i, 0.9, 1.3 - 0.1 * i)})


func _party(room: Node3D, id: String) -> void:
	for x in [-1.6, 1.6]:
		var table := _group(room, id, "PartyTable%d" % (0 if x < 0 else 1), Vector3(x, 0, -0.5))
		_c(table, Vector3(1.8, 0.08, 1.0), Vector3(0, 0.75, 0), "TableTop", {})
		_c(table, Vector3(1.86, 0.03, 1.06), Vector3(0, 0.8, 0), "TableCloth", {"kind": "fabric", "tint": Color(1.4, 0.7, 1.2)})
		for lx in [-0.8, 0.8]:
			_c(table, Vector3(0.1, 0.75, 0.1), Vector3(lx, 0.375, 0), "TableLeg", {})
		_c(table, Vector3(0.3, 0.2, 0.3), Vector3(0, 0.92, 0), "CakeBox", {"kind": "label", "tint": Color(1.3, 1.1, 1.0)})
		for i in 3:
			_c(table, Vector3(0.22, 0.5, 0.22), Vector3(-0.5 + i * 0.5, 1.1, -0.6), "HatCone", {"kind": "fabric", "tint": Color(1.2 + 0.2 * i, 0.8, 1.4 - 0.3 * i)})
	var banner := _group(room, id, "Banner", Vector3(0, 2.5, -2.75))
	_c(banner, Vector3(4.0, 0.5, 0.05), Vector3.ZERO, "BannerCloth", {"kind": "fabric", "tint": Color(1.3, 0.7, 1.1)})
	for i in 6:
		_c(room, Vector3(0.3, 0.38, 0.3), Vector3(-2.4 + i * 0.95, 2.1 + (i % 2) * 0.3, 1.8 - (i % 3) * 0.6), "Balloon%d" % i, {"kind": "red" if i % 2 == 0 else "light", "tint": Color(1.0, 0.7 + 0.1 * (i % 3), 1.2 - 0.15 * (i % 3))})


func _ballpit(room: Node3D, id: String) -> void:
	var pit := _group(room, id, "BallPit", Vector3(0, 0, -0.6))
	_c(pit, Vector3(4.4, 0.6, 3.0), Vector3(0, 0.3, 0), "PitBox", {"kind": "plastic", "tint": Color(0.7, 0.9, 1.6)})
	_c(pit, Vector3(4.0, 0.12, 2.6), Vector3(0, 0.64, 0), "PitFloor", {"kind": "label", "tint": Color(0.7, 1.0, 1.4)})
	var seed_i := 0
	for x in 8:
		for z in 5:
			seed_i += 1
			_c(pit, Vector3(0.34, 0.34, 0.34), Vector3(-1.75 + x * 0.5, 0.8 + (seed_i % 3) * 0.05, -1.0 + z * 0.5), "PitBall", {"kind": ["red", "green", "light", "glass"][seed_i % 4]})
	var slide := _group(room, id, "Slide", Vector3(2.4, 0, 1.5))
	_c(slide, Vector3(0.6, 1.4, 0.6), Vector3(0, 0.7, 0), "SlideTower", {"kind": "plastic", "tint": Color(1.5, 0.8, 0.8)})
	_c(slide, Vector3(0.5, 0.08, 1.8), Vector3(0, 0.7, 1.1), "SlideRamp", {"kind": "plastic", "tint": Color(1.6, 1.2, 0.6), "rotation": Vector3(0.45, 0, 0)})


func _prize(room: Node3D, id: String) -> void:
	var counter := _group(room, id, "PrizeCounter", Vector3(0, 0, -1.5))
	_c(counter, Vector3(3.6, 1.0, 0.9), Vector3(0, 0.5, 0), "CounterBody", {})
	_c(counter, Vector3(3.7, 0.06, 1.0), Vector3(0, 1.03, 0), "CounterTop", {"kind": "metal", "tint": Color(1.2, 1.2, 1.25)})
	_c(counter, Vector3(3.2, 0.6, 0.04), Vector3(0, 1.4, 0.4), "CounterGlass", {"kind": "glass"})
	var shelves := _group(room, id, "PrizeShelves", Vector3(0, 0, -2.6))
	for y in [0.9, 1.6, 2.3]:
		_c(shelves, Vector3(4.6, 0.05, 0.4), Vector3(0, y, 0), "ShelfBoard", {})
		for i in 6:
			_c(shelves, Vector3(0.4, 0.4, 0.3), Vector3(-2.0 + i * 0.8, y + 0.23, 0), "PrizeToy", {"kind": "fabric", "tint": Color(0.8 + 0.2 * (i % 3), 1.2 - 0.2 * (i % 2), 0.8 + 0.25 * ((i + int(y * 3)) % 3))})
	var tickets := _group(room, id, "TicketMachine", Vector3(2.3, 0, 0.8))
	_c(tickets, Vector3(0.6, 1.2, 0.5), Vector3(0, 0.6, 0), "TicketBody", {"kind": "plastic", "tint": Color(1.4, 0.8, 0.8)})
	_c(tickets, Vector3(0.3, 0.5, 0.06), Vector3(0, 0.5, 0.28), "TicketStrip", {"kind": "label", "tint": Color(1.2, 1.2, 1.1)})


func _storage(room: Node3D, id: String, half: float) -> void:
	for p in [[-1.8, -2.1], [-0.8, -2.2], [-1.3, -1.9]]:
		var stack := _group(room, id, "Crates%d" % props.size(), Vector3(p[0], 0, p[1]))
		_c(stack, Vector3(0.9, 0.9, 0.9), Vector3(0, 0.45, 0), "CrateBox", {})
		_c(stack, Vector3(0.94, 0.08, 0.94), Vector3(0, 0.6, 0), "CrateBand", {"kind": "metal", "tint": Color(0.8, 0.8, 0.85)})
	var rack := _group(room, id, "Rack", Vector3(1.4, 0, -2.3))
	for x in [-1.0, 1.0]:
		_c(rack, Vector3(0.08, 2.2, 0.5), Vector3(x, 1.1, 0), "RackPost", {"kind": "metal"})
	for y in [0.4, 1.1, 1.8]:
		_c(rack, Vector3(2.1, 0.05, 0.5), Vector3(0, y, 0), "RackShelf", {"kind": "metal"})
		for i in 3:
			_c(rack, Vector3(0.5, 0.4, 0.4), Vector3(-0.7 + i * 0.7, y + 0.22, 0), "RackBox", {"tint": Color(0.9 + 0.1 * i, 0.85, 0.8)})
	# the two vent mouths, one in each side wall: the way into the ducts
	for sgn in [-1.0, 1.0]:
		var mouth := _group(room, id, "VentMouth%s" % ("L" if sgn < 0 else "R"), Vector3(sgn * (half - 0.16), 0.6, 1.0))
		_c(mouth, Vector3(0.1, 0.8, 1.0), Vector3.ZERO, "MouthGrille", {"kind": "metal", "tint": Color(0.7, 0.7, 0.75)})
		for i in 4:
			_c(mouth, Vector3(0.14, 0.04, 0.9), Vector3(0, -0.3 + i * 0.2, 0), "MouthSlat", {"kind": "plastic"})


func _duct(room: Node3D, id: String, half: float) -> void:
	var duct := _group(room, id, "Duct", Vector3(0, 0, -0.4))
	_c(duct, Vector3(ROOM_W - 1.0, 1.1, 1.3), Vector3(0, 0.55, 0), "DuctTube", {"kind": "metal", "tint": Color(0.9, 0.95, 1.05)})
	for x in [-2.0, 0.0, 2.0]:
		_c(duct, Vector3(0.14, 1.2, 1.4), Vector3(x, 0.55, 0), "DuctBand", {"kind": "metal", "tint": Color(0.7, 0.7, 0.75)})
	_c(duct, Vector3(0.5, 0.6, 0.06), Vector3(0, 0.55, 0.68), "DuctHatch", {"kind": "plastic"})
	var stack := _group(room, id, "DuctRiser", Vector3(-2.2 if id == "ventl" else 2.2, 0, -2.2))
	_c(stack, Vector3(0.8, 3.0, 0.8), Vector3(0, 1.5, 0), "RiserTube", {"kind": "metal", "tint": Color(0.8, 0.85, 0.95)})
	_c(stack, Vector3(0.9, 0.12, 0.9), Vector3(0, 2.2, 0), "RiserBand", {"kind": "metal"})


## World position of hunter slot 0 or 1 in a room.
func stand_position(room_id: String, slot: int) -> Vector3:
	var room := rooms.get(room_id) as Node3D
	if room == null:
		return Vector3.ZERO
	var offset := Vector3(-0.6, 0.0, 0.4) if slot == 0 else Vector3(1.0, 0.0, -0.6)
	if room_id.begins_with("vent"):
		offset = Vector3(-0.6 if slot == 0 else 1.0, 0.0, 0.9)
	return room.global_position + offset


## The feed camera's mount: high in the open (south) corner of the room, looking in.
func camera_transform(room_id: String) -> Transform3D:
	var room := rooms.get(room_id) as Node3D
	if room == null:
		return Transform3D.IDENTITY
	var from := room.global_position + Vector3(-1.2, 2.9, 4.4)
	var target := room.global_position + Vector3(0.0, 0.8, -0.8)
	return Transform3D(Basis.IDENTITY, from).looking_at(target, Vector3.UP)
