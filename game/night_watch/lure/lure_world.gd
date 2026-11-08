class_name LureWorld
extends Node3D

## Dead Air's radio station, the part the cameras look into (LureMap has the floor plan): eight enclosed rooms of different sizes (reception, two studios, the live
## room, the tape library, the transmitter room and two crawlspaces) with doorways in the walls they share, each with its own props, far from the booth. Rooms are keyed
## by the rules' sim ids (lobby, arcade, ...) and built from shaded cubes (NightWatchArt). A feed camera sits high in a corner of each room. Generated, so identical everywhere.

const A := preload("res://game/night_watch/night_watch_art.gd")
const HEIGHT := 3.6
const DOOR_GAP := 1.6
const DOOR_TOP := 3.2
const TINTS := {
	"reception": Color(1.3, 1.05, 0.8), "studio": Color(0.9, 0.85, 1.3), "live": Color(1.2, 0.85, 0.95), "tapes": Color(1.2, 1.15, 0.8),
	"transmitter": Color(0.85, 1.05, 1.15), "crawl": Color(0.85, 0.95, 1.05),
}
const LABELS := {"lobby": "RECEPTION", "arcade": "STUDIO A", "party": "STUDIO B", "ballpit": "LIVE ROOM", "prize": "TAPE LIBRARY", "storage": "TRANSMITTER ROOM"}

var rooms := {}        # sim room id -> Node3D (the room's centre on the floor)
var map_ids := {}      # sim room id -> station room id
var props := {}        # "sim id/prop" -> Node3D


func _ready() -> void:
	if rooms.is_empty():
		build()


func build() -> void:
	for map_id in LureMap.ROOMS:
		var def: Array = LureMap.ROOMS[map_id]
		var sim_id: String = def[0]
		var room := Node3D.new()
		room.name = "Room_%s" % map_id
		room.position = LureMap.center(map_id)
		add_child(room)
		rooms[sim_id] = room
		map_ids[sim_id] = map_id
		_build_room(sim_id, map_id, room, String(def[5]))


func _c(parent: Node3D, size: Vector3, pos: Vector3, node_name: String, opts := {}) -> MeshInstance3D:
	var o := opts.duplicate()
	o["name"] = node_name
	return A.box(parent, size, pos, o)


func _group(room: Node3D, id: String, prop_name: String, pos := Vector3.ZERO) -> Node3D:
	var node := A.prop(room, prop_name, pos)
	props["%s/%s" % [id, prop_name]] = node
	return node


## The door centres along each wall of a room, in the room's local coordinates: {"N": [x...], "S": [x...], "W": [z...], "E": [z...]}.
func _doors_of(map_id: String) -> Dictionary:
	var out := {"N": [], "S": [], "W": [], "E": []}
	var c := LureMap.center(map_id) - LureMap.ORIGIN
	var rc := LureMap.rect(map_id)
	for e in LureMap.EDGES:
		if e[0] != map_id and e[1] != map_id:
			continue
		var other: String = e[1] if e[0] == map_id else e[0]
		var d := LureMap.door_between(map_id, other)
		if d.is_empty():
			continue
		var p: Vector2 = d["point"]
		if d["along"] == "z":
			out["W" if is_equal_approx(p.x, rc.position.x) else "E"].append(p.y - c.z)
		else:
			out["N" if is_equal_approx(p.y, rc.position.y) else "S"].append(p.x - c.x)
	return out


## One wall: slabs either side of each doorway and a lintel over it. The wall sits just inside the room, so two neighbours' walls stand side by side.
func _wall(shell: Node3D, side: String, hw: float, hd: float, doors: Array, tint: Color) -> void:
	var along_x := side == "N" or side == "S"
	var length := hw * 2.0 if along_x else hd * 2.0
	var half := length * 0.5
	var fixed := (hd - 0.1) * (-1.0 if side == "N" else 1.0) if along_x else (hw - 0.1) * (-1.0 if side == "W" else 1.0)
	var cuts := doors.duplicate()
	cuts.sort()
	var cursor := -half
	var wname := "Wall" + side
	for dc in cuts:
		var lo: float = float(dc) - DOOR_GAP * 0.5
		_wall_piece(shell, along_x, fixed, cursor, lo, wname, tint)
		_lintel(shell, along_x, fixed, float(dc), wname + "Lintel", tint)
		cursor = float(dc) + DOOR_GAP * 0.5
	_wall_piece(shell, along_x, fixed, cursor, half, wname, tint)


func _wall_piece(shell: Node3D, along_x: bool, fixed: float, a: float, b: float, wname: String, tint: Color) -> void:
	if b - a < 0.05:
		return
	var mid := (a + b) * 0.5
	var size := Vector3(b - a, HEIGHT, 0.2) if along_x else Vector3(0.2, HEIGHT, b - a)
	var pos := Vector3(mid, HEIGHT * 0.5, fixed) if along_x else Vector3(fixed, HEIGHT * 0.5, mid)
	_c(shell, size, pos, wname, {"solid": true, "tint": tint})


func _lintel(shell: Node3D, along_x: bool, fixed: float, at: float, wname: String, tint: Color) -> void:
	var h := HEIGHT - DOOR_TOP
	var size := Vector3(DOOR_GAP, h, 0.2) if along_x else Vector3(0.2, h, DOOR_GAP)
	var pos := Vector3(at, DOOR_TOP + h * 0.5, fixed) if along_x else Vector3(fixed, DOOR_TOP + h * 0.5, at)
	_c(shell, size, pos, wname, {"tint": tint * Color(0.9, 0.9, 0.9)})


func _build_room(sim_id: String, map_id: String, room: Node3D, theme: String) -> void:
	var rc := LureMap.rect(map_id)
	var hw := rc.size.x * 0.5
	var hd := rc.size.y * 0.5
	var tint: Color = TINTS[theme]
	var height := 2.6 if theme == "crawl" else HEIGHT
	var shell := _group(room, sim_id, "Shell")
	_c(shell, Vector3(rc.size.x, 0.2, rc.size.y), Vector3(0, -0.1, 0), "Floor", {"tint": tint * Color(0.95, 0.95, 0.95)})
	_c(shell, Vector3(rc.size.x, 0.2, rc.size.y), Vector3(0, height + 0.1, 0), "Ceiling", {"tint": tint * Color(0.6, 0.6, 0.6)})
	var doors := _doors_of(map_id)
	for side in ["N", "S", "W", "E"]:
		_wall(shell, side, hw, hd, doors[side], tint * (Color(1.05, 1.05, 1.05) if side in ["W", "E"] else Color.WHITE))
	_c(shell, Vector3(rc.size.x - 0.6, 0.12, 0.12), Vector3(0, height - 0.22, -hd + 0.3), "PipeRoom", {"kind": "metal"})
	_c(shell, Vector3(1.4, 0.05, 1.4), Vector3(0, height - 0.04, 0), "CeilingPanel", {})
	_c(shell, Vector3(0.05, 0.05, 0.05), Vector3(-hw + 0.3, height - 0.5, hd - 0.4), "LedSmoke", {})
	_c(shell, Vector3(rc.size.x, 0.02, 0.3), Vector3(0, 0.01, 0.8), "FloorStripe", {"kind": "label", "tint": Color(0.8, 0.8, 0.8)})
	_c(_group(room, sim_id, "Details"), Vector3(0.7, 0.4, 0.06), Vector3(hw - 1.0, 2.4, -hd + 0.14), "VentGrille", {"kind": "metal"})
	match theme:
		"reception":
			_reception(room, sim_id, hw, hd)
		"studio":
			_studio(room, sim_id, hw, hd, map_id == "studio_a")
		"live":
			_live(room, sim_id, hw, hd)
		"tapes":
			_tapes(room, sim_id, hw, hd)
		"transmitter":
			_transmitter(room, sim_id, hw, hd)
		"crawl":
			_crawl(room, sim_id, hw, hd)


func _reception(room: Node3D, id: String, hw: float, hd: float) -> void:
	var desk := _group(room, id, "ReceptionDesk", Vector3(0, 0, -hd + 1.0))
	_c(desk, Vector3(3.2, 1.0, 0.8), Vector3(0, 0.5, 0), "FrontBody", {"kind": "wood", "tint": Color(1.2, 0.9, 0.8)})
	_c(desk, Vector3(3.3, 0.06, 0.9), Vector3(0, 1.03, 0), "FrontTop", {"kind": "metal", "tint": Color(1.2, 1.2, 1.25)})
	_c(desk, Vector3(0.4, 0.25, 0.3), Vector3(0.8, 1.19, 0), "SwitchboardBody", {"kind": "plastic"})
	var sign_group := _group(room, id, "StationSign", Vector3(0, 2.5, -hd + 0.2))
	_c(sign_group, Vector3(3.4, 0.5, 0.06), Vector3.ZERO, "SignPlate", {"kind": "plastic"})
	_c(sign_group, Vector3(3.0, 0.3, 0.03), Vector3(0, 0, 0.04), "SignOnAirLogo", {"tint": Color(1.0, 0.45, 0.35)})
	var sofa := _group(room, id, "Sofa", Vector3(hw - 1.2, 0, 0.8))
	_c(sofa, Vector3(0.9, 0.45, 2.2), Vector3(0, 0.225, 0), "SofaSeat", {"kind": "fabric", "tint": Color(0.9, 0.6, 0.7)})
	_c(sofa, Vector3(0.2, 0.8, 2.2), Vector3(0.4, 0.65, 0), "SofaBack", {"kind": "fabric", "tint": Color(0.8, 0.5, 0.65)})
	var posters := _group(room, id, "Posters", Vector3(-hw + 0.15, 1.7, 0.4))
	for i in 3:
		_c(posters, Vector3(0.04, 0.8, 0.55), Vector3(0, 0, -1.2 + i * 1.2), "PosterPage", {"kind": "fabric", "tint": Color(1.0 + 0.2 * i, 0.8, 1.3 - 0.2 * i)})


func _studio(room: Node3D, id: String, hw: float, hd: float, tall_left: bool) -> void:
	var foam := _group(room, id, "Foam", Vector3(0, 0, 0))
	var wall_x := -hw + 0.18 if tall_left else hw - 0.18
	for iz in 6:
		for iy in 3:
			var shade := 0.55 + 0.1 * ((iz + iy) % 2)
			_c(foam, Vector3(0.12, 0.5, 0.5), Vector3(wall_x, 0.8 + iy * 0.55, -hd + 1.0 + iz * 1.5), "FoamWedge", {"kind": "fabric", "tint": Color(shade, shade * 0.9, shade * 1.3), "ao": 0.9})
	var mic := _group(room, id, "MicStand", Vector3(0, 0, -hd * 0.3))
	_c(mic, Vector3(0.4, 0.04, 0.4), Vector3(0, 0.02, 0), "MicBase", {"kind": "metal"})
	_c(mic, Vector3(0.05, 1.5, 0.05), Vector3(0, 0.75, 0), "MicPole", {"kind": "metal"})
	_c(mic, Vector3(0.16, 0.22, 0.16), Vector3(0, 1.55, 0.1), "MicHead", {"kind": "plastic"})
	var desk := _group(room, id, "GuestDesk", Vector3(0, 0, hd * 0.2))
	_c(desk, Vector3(2.4, 0.08, 0.9), Vector3(0, 0.75, 0), "DeskTop", {})
	for x in [-1.0, 1.0]:
		_c(desk, Vector3(0.1, 0.75, 0.8), Vector3(x, 0.375, 0), "DeskLeg", {})
	for x in [-0.8, 0.8]:
		_c(desk, Vector3(0.45, 0.06, 0.45), Vector3(x, 0.45, 0.9), "StoolSeat", {"kind": "fabric", "tint": Color(1.2, 0.8, 0.8)})
		_c(desk, Vector3(0.06, 0.45, 0.06), Vector3(x, 0.22, 0.9), "StoolLeg", {"kind": "metal"})
	var win := _group(room, id, "ControlWindow", Vector3(0, 1.7, -hd + 0.15))
	_c(win, Vector3(2.8, 1.0, 0.06), Vector3.ZERO, "WindowGlass", {"kind": "glass"})
	_c(win, Vector3(3.0, 1.2, 0.04), Vector3(0, 0, -0.04), "WindowFrame", {})


func _live(room: Node3D, id: String, hw: float, hd: float) -> void:
	var kit := _group(room, id, "DrumKit", Vector3(-1.4, 0, -hd + 1.4))
	_c(kit, Vector3(0.7, 0.45, 0.7), Vector3(0, 0.225, 0), "DrumKick", {"kind": "red"})
	for x in [-0.7, 0.7]:
		_c(kit, Vector3(0.4, 0.25, 0.4), Vector3(x, 0.8, 0.2), "DrumTom", {"kind": "plastic", "tint": Color(1.2, 1.2, 1.3)})
	_c(kit, Vector3(0.5, 0.04, 0.5), Vector3(1.0, 1.2, 0), "CymbalDisc", {"kind": "metal", "tint": Color(1.4, 1.3, 0.8)})
	_c(kit, Vector3(0.04, 1.2, 0.04), Vector3(1.0, 0.6, 0), "CymbalStand", {"kind": "metal"})
	var piano := _group(room, id, "Piano", Vector3(1.8, 0, -hd + 1.0))
	_c(piano, Vector3(1.8, 0.9, 0.7), Vector3(0, 0.45, 0), "PianoBody", {"tint": Color(0.45, 0.4, 0.5)})
	_c(piano, Vector3(1.7, 0.05, 0.3), Vector3(0, 0.92, 0.3), "PianoKeys", {"kind": "label", "tint": Color(1.3, 1.3, 1.2)})
	for x in [-hw + 0.6, hw - 0.6]:
		var amp := _group(room, id, "Amp%s" % ("L" if x < 0 else "R"), Vector3(x, 0, 0.3))
		_c(amp, Vector3(0.6, 0.9, 0.5), Vector3(0, 0.45, 0), "AmpBody", {"kind": "plastic", "tint": Color(0.8, 0.8, 0.9)})
		_c(amp, Vector3(0.4, 0.4, 0.04), Vector3(0, 0.45, 0.27), "AmpGrille", {"kind": "fabric", "tint": Color(0.6, 0.6, 0.7)})
	var rug := _group(room, id, "Rug", Vector3(0, 0.01, hd - 1.6))
	_c(rug, Vector3(3.4, 0.03, 1.8), Vector3.ZERO, "RugMat", {"kind": "fabric", "tint": Color(0.9, 0.6, 0.7), "ao": 1.0})


func _tapes(room: Node3D, id: String, hw: float, hd: float) -> void:
	for i in 3:
		var shelf := _group(room, id, "TapeShelf%d" % i, Vector3(-hw + 1.2 + i * 1.7, 0, -hd + 1.0))
		_c(shelf, Vector3(1.4, 2.2, 0.5), Vector3(0, 1.1, 0), "ShelfBody", {})
		for y in [0.5, 1.1, 1.7]:
			_c(shelf, Vector3(1.42, 0.05, 0.52), Vector3(0, y, 0), "ShelfBoard", {})
			for j in 4:
				_c(shelf, Vector3(0.26, 0.26, 0.3), Vector3(-0.5 + j * 0.34, y + 0.17, 0), "TapeReel", {"kind": ["metal", "red", "plastic", "label"][j], "tint": Color(0.9, 0.9, 1.0)})
	var table := _group(room, id, "ListeningTable", Vector3(0, 0, hd - 1.4))
	_c(table, Vector3(2.2, 0.08, 0.9), Vector3(0, 0.75, 0), "TableTop", {})
	for x in [-1.0, 1.0]:
		_c(table, Vector3(0.1, 0.75, 0.8), Vector3(x, 0.375, 0), "TableLeg", {})
	_c(table, Vector3(0.6, 0.18, 0.4), Vector3(0, 0.88, 0), "ReelDeck", {"kind": "plastic"})


func _transmitter(room: Node3D, id: String, hw: float, hd: float) -> void:
	for i in 3:
		var rack := _group(room, id, "TxRack%d" % i, Vector3(-hw + 1.0 + i * 1.3, 0, -hd + 0.8))
		_c(rack, Vector3(1.0, 2.2, 0.8), Vector3(0, 1.1, 0), "RackBody", {"kind": "metal", "tint": Color(0.6, 0.6, 0.68)})
		for j in 5:
			_c(rack, Vector3(1.02, 0.18, 0.04), Vector3(0, 0.3 + j * 0.4, 0.42), "RackUnit", {"kind": "plastic", "tint": Color(0.9, 0.9, 1.0)})
			_c(rack, Vector3(0.05, 0.05, 0.04), Vector3(0.4, 0.34 + j * 0.4, 0.45), "LedRack", {})
	var coil := _group(room, id, "Transformer", Vector3(hw - 1.4, 0, 0.4))
	_c(coil, Vector3(1.2, 1.4, 1.2), Vector3(0, 0.7, 0), "TransformerBody", {"kind": "metal", "tint": Color(0.7, 0.75, 0.8)})
	for i in 4:
		_c(coil, Vector3(0.14, 0.4, 0.14), Vector3(-0.4 + i * 0.27, 1.6, 0), "InsulatorPost", {"kind": "glass"})
	var mast := _group(room, id, "AntennaMast", Vector3(hw - 0.7, 0, -hd + 0.7))
	_c(mast, Vector3(0.12, HEIGHT, 0.12), Vector3(0, HEIGHT * 0.5, 0), "MastPipe", {"kind": "metal"})
	_c(mast, Vector3(0.5, 0.2, 0.5), Vector3(0, 0.1, 0), "MastBase", {"kind": "metal"})


func _crawl(room: Node3D, id: String, hw: float, hd: float) -> void:
	var duct := _group(room, id, "Duct", Vector3(0, 0, 0))
	_c(duct, Vector3(rc_w(hw) - 0.8, 1.1, 1.4), Vector3(0, 0.55, 0), "DuctTube", {"kind": "metal", "tint": Color(0.9, 0.95, 1.05)})
	for x in [-1.2, 0.0, 1.2]:
		_c(duct, Vector3(0.14, 1.2, 1.5), Vector3(x if hw > 1.5 else 0.0, 0.55, 0), "DuctBand", {"kind": "metal", "tint": Color(0.7, 0.7, 0.75)})
	_c(duct, Vector3(0.5, 0.6, 0.06), Vector3(0, 0.55, 0.74), "DuctHatch", {"kind": "plastic"})
	var riser := _group(room, id, "DuctRiser", Vector3(hw - 0.6, 0, -hd + 0.6))
	_c(riser, Vector3(0.7, 2.4, 0.7), Vector3(0, 1.2, 0), "RiserTube", {"kind": "metal", "tint": Color(0.8, 0.85, 0.95)})


func rc_w(hw: float) -> float:
	return hw * 2.0


## World position of hunter slot 0 or 1 in a room (keyed by the rules' room id).
func stand_position(room_id: String, slot: int) -> Vector3:
	var room := rooms.get(room_id) as Node3D
	if room == null:
		return Vector3.ZERO
	var offset := Vector3(0.8, 0.0, 0.6) if slot == 0 else Vector3(-1.0, 0.0, -0.6)
	if room_id.begins_with("vent"):
		offset = Vector3(0.0 if slot == 0 else -1.2, 0.0, 0.9)
	return room.global_position + offset


## The feed camera's mount: high in the room's north-west corner, looking at the middle of the floor.
func camera_transform(room_id: String) -> Transform3D:
	var room := rooms.get(room_id) as Node3D
	if room == null:
		return Transform3D.IDENTITY
	var rc := LureMap.rect(String(map_ids[room_id]))
	var height := 2.2 if room_id.begins_with("vent") else 2.8
	var from := room.global_position + Vector3(-rc.size.x * 0.5 + 0.5, height, -rc.size.y * 0.5 + 0.5)
	var target := room.global_position + Vector3(rc.size.x * 0.12, 0.7, rc.size.y * 0.12)
	return Transform3D(Basis.IDENTITY, from).looking_at(target, Vector3.UP)
