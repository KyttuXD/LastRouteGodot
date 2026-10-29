class_name BedroomWing
extends Node3D

## The rest of Bedtime's house wing (BedroomMap has the floor plan): the kids' room, the bathroom, the landing and the stairs, the living room and the galley. The
## bedroom, its wardrobe and the hall are BedroomOffice's. Rooms are enclosed boxes with doorways in the walls they share (and in the hall's walls, which
## BedroomOffice leaves open at the same places). Built from shaded cubes (NightWatchArt); dark like the rest of the house, with one very faint glow in the living room.

const A := preload("res://src/night_watch/night_watch_art.gd")
const HEIGHT := 3.6
const DOOR_GAP := 1.6
const DOOR_TOP := 3.2
const WING_ROOMS := ["kids_room", "bathroom", "landing", "stairs", "living_room", "galley"]
const TINTS := {
	"kids": Color(0.8, 1.1, 1.3), "bath": Color(0.85, 1.25, 1.25), "landing": Color(1.0, 0.9, 1.2), "stairs": Color(0.9, 0.85, 1.1),
	"living": Color(1.2, 0.95, 1.0), "galley": Color(1.2, 1.15, 0.85),
}

var rooms := {}   # map room id -> Node3D (centre of the floor)
var props := {}


func _ready() -> void:
	if rooms.is_empty():
		build()


func build() -> void:
	for id in WING_ROOMS:
		var room := Node3D.new()
		room.name = "Room_%s" % id
		room.position = BedroomMap.center(id)
		add_child(room)
		rooms[id] = room
		_build_room(id, room, String(BedroomMap.ROOMS[id][4]))
	var glow := OmniLight3D.new()
	glow.name = "LivingGlow"
	glow.light_color = Color(0.5, 0.55, 0.95)
	glow.light_energy = 0.12
	glow.omni_range = 6.0
	glow.position = BedroomMap.center("living_room") + Vector3(0, 2.2, 0)
	add_child(glow)


func _c(parent: Node3D, size: Vector3, pos: Vector3, node_name: String, opts := {}) -> MeshInstance3D:
	var o := opts.duplicate()
	o["name"] = node_name
	return A.box(parent, size, pos, o)


func _group(room: Node3D, id: String, prop_name: String, pos := Vector3.ZERO) -> Node3D:
	var node := A.prop(room, prop_name, pos)
	props["%s/%s" % [id, prop_name]] = node
	return node


func _doors_of(id: String) -> Dictionary:
	var out := {"N": [], "S": [], "W": [], "E": []}
	var c := BedroomMap.center(id)
	var rc := BedroomMap.rect(id)
	for e in BedroomMap.EDGES:
		if e[0] != id and e[1] != id:
			continue
		var other: String = e[1] if e[0] == id else e[0]
		var d := BedroomMap.door_between(id, other)
		if d.is_empty():
			continue
		var p: Vector2 = d["point"]
		if d["along"] == "z":
			out["W" if is_equal_approx(p.x, rc.position.x) else "E"].append(p.y - c.z)
		else:
			out["N" if is_equal_approx(p.y, rc.position.y) else "S"].append(p.x - c.x)
	return out


func _wall(shell: Node3D, side: String, hw: float, hd: float, doors: Array, tint: Color) -> void:
	var along_x := side == "N" or side == "S"
	var half := (hw if along_x else hd)
	var fixed := (hd - 0.1) * (-1.0 if side == "N" else 1.0) if along_x else (hw - 0.1) * (-1.0 if side == "W" else 1.0)
	var cuts := doors.duplicate()
	cuts.sort()
	var cursor := -half
	for dc in cuts:
		_piece(shell, along_x, fixed, cursor, float(dc) - DOOR_GAP * 0.5, tint)
		var h := HEIGHT - DOOR_TOP
		var size := Vector3(DOOR_GAP, h, 0.2) if along_x else Vector3(0.2, h, DOOR_GAP)
		var pos := Vector3(float(dc), DOOR_TOP + h * 0.5, fixed) if along_x else Vector3(fixed, DOOR_TOP + h * 0.5, float(dc))
		_c(shell, size, pos, "Wall%sLintel" % side, {"tint": tint * Color(0.9, 0.9, 0.9)})
		cursor = float(dc) + DOOR_GAP * 0.5
	_piece(shell, along_x, fixed, cursor, half, tint)


func _piece(shell: Node3D, along_x: bool, fixed: float, a: float, b: float, tint: Color) -> void:
	if b - a < 0.05:
		return
	var mid := (a + b) * 0.5
	var size := Vector3(b - a, HEIGHT, 0.2) if along_x else Vector3(0.2, HEIGHT, b - a)
	var pos := Vector3(mid, HEIGHT * 0.5, fixed) if along_x else Vector3(fixed, HEIGHT * 0.5, mid)
	_c(shell, size, pos, "WallPiece", {"solid": true, "tint": tint})


func _build_room(id: String, room: Node3D, theme: String) -> void:
	var rc := BedroomMap.rect(id)
	var hw := rc.size.x * 0.5
	var hd := rc.size.y * 0.5
	var tint: Color = TINTS[theme]
	var shell := _group(room, id, "Shell")
	_c(shell, Vector3(rc.size.x, 0.2, rc.size.y), Vector3(0, -0.1, 0), "Floor", {"solid": true, "kind": "wood" if theme != "bath" else "concrete", "tint": tint * Color(0.9, 0.9, 0.9)})
	_c(shell, Vector3(rc.size.x, 0.2, rc.size.y), Vector3(0, HEIGHT + 0.1, 0), "Ceiling", {"tint": tint * Color(0.55, 0.55, 0.6)})
	var doors := _doors_of(id)
	for side in ["N", "S", "W", "E"]:
		_wall(shell, side, hw, hd, doors[side], tint)
	_c(shell, Vector3(rc.size.x - 0.4, 0.2, 0.08), Vector3(0, 0.1, -hd + 0.14), "Baseboard", {"tint": Color(0.7, 0.7, 0.75)})
	match theme:
		"kids":
			_kids(room, id, hw, hd)
		"bath":
			_bath(room, id, hw, hd)
		"landing":
			_landing(room, id, hw, hd)
		"stairs":
			_stairs(room, id, hw, hd)
		"living":
			_living(room, id, hw, hd)
		"galley":
			_galley(room, id, hw, hd)


func _kids(room: Node3D, id: String, hw: float, hd: float) -> void:
	var bed := _group(room, id, "KidsBed", Vector3(-hw + 1.0, 0, hd - 1.2))
	_c(bed, Vector3(1.0, 0.35, 2.0), Vector3(0, 0.3, 0), "BedFrame", {})
	_c(bed, Vector3(0.9, 0.2, 1.9), Vector3(0, 0.55, 0), "Mattress", {"kind": "fabric", "tint": Color(0.6, 0.9, 1.3)})
	var chest := _group(room, id, "ToyChest", Vector3(hw - 0.8, 0, -hd + 0.6))
	_c(chest, Vector3(0.9, 0.5, 0.5), Vector3(0, 0.25, 0), "ChestBox", {})
	for i in 3:
		_c(chest, Vector3(0.22, 0.22, 0.22), Vector3(-0.25 + i * 0.25, 0.62, 0), "ToyCube", {"kind": ["red", "green", "light"][i]})
	var rug := _group(room, id, "Rug", Vector3(0.3, 0.01, 0))
	_c(rug, Vector3(1.6, 0.03, 1.6), Vector3.ZERO, "RugMat", {"kind": "fabric", "tint": Color(1.2, 0.7, 0.8), "ao": 1.0})


func _bath(room: Node3D, id: String, hw: float, hd: float) -> void:
	var tub := _group(room, id, "Tub", Vector3(-hw + 1.2, 0, -hd + 0.6))
	_c(tub, Vector3(1.9, 0.6, 0.8), Vector3(0, 0.3, 0), "TubBody", {"kind": "plastic", "tint": Color(1.5, 1.5, 1.6)})
	_c(tub, Vector3(1.7, 0.05, 0.6), Vector3(0, 0.62, 0), "TubWater", {"kind": "glass", "tint": Color(0.7, 0.9, 1.0)})
	var sink := _group(room, id, "Sink", Vector3(hw - 0.7, 0, -hd + 0.5))
	_c(sink, Vector3(0.7, 0.85, 0.45), Vector3(0, 0.425, 0), "SinkBody", {"kind": "concrete", "tint": Color(1.5, 1.5, 1.6)})
	_c(sink, Vector3(0.06, 0.25, 0.06), Vector3(0, 1.0, -0.1), "TapNeck", {"kind": "metal"})
	var toilet := _group(room, id, "Toilet", Vector3(0.2, 0, hd - 0.6))
	_c(toilet, Vector3(0.4, 0.4, 0.55), Vector3(0, 0.2, 0), "ToiletBowl", {"kind": "concrete", "tint": Color(1.5, 1.5, 1.6)})
	_c(toilet, Vector3(0.45, 0.6, 0.2), Vector3(0, 0.6, 0.3), "ToiletTank", {"kind": "concrete", "tint": Color(1.5, 1.5, 1.6)})
	_c(_group(room, id, "Mirror", Vector3(hw - 0.7, 1.6, -hd + 0.15)), Vector3(0.6, 0.8, 0.04), Vector3.ZERO, "MirrorGlass", {"kind": "glass"})


func _landing(room: Node3D, id: String, hw: float, hd: float) -> void:
	var rail := _group(room, id, "Railing", Vector3(0, 0, hd - 0.4))
	_c(rail, Vector3(hw * 2.0 - 0.4, 0.06, 0.06), Vector3(0, 1.0, 0), "RailTop", {"kind": "metal"})
	for i in 5:
		_c(rail, Vector3(0.05, 1.0, 0.05), Vector3(-hw + 0.4 + i * (hw * 2.0 - 0.8) / 4.0, 0.5, 0), "RailPost", {"kind": "metal"})
	var rug := _group(room, id, "Rug", Vector3(0, 0.01, -0.4))
	_c(rug, Vector3(1.4, 0.03, 1.8), Vector3.ZERO, "RugMat", {"kind": "fabric", "tint": Color(0.8, 0.6, 1.0), "ao": 1.0})
	var win := _group(room, id, "LandingWindow", Vector3(hw - 0.2, 1.6, 0))
	_c(win, Vector3(0.05, 0.9, 0.9), Vector3.ZERO, "WindowGlowPane", {"tint": Color(0.35, 0.45, 0.8)})


func _stairs(room: Node3D, id: String, hw: float, hd: float) -> void:
	var steps := _group(room, id, "Steps", Vector3(0, 0, hd - 0.4))
	for i in 7:
		_c(steps, Vector3(hw * 2.0 - 0.8, 0.2 * (i + 1), 0.45), Vector3(0, 0.1 * (i + 1), -i * 0.5), "StepBlock", {"kind": "wood"})
	var rail := _group(room, id, "StairRail", Vector3(hw - 0.3, 0, hd - 0.4))
	_c(rail, Vector3(0.06, 0.06, 3.4), Vector3(0, 1.1, -1.7), "RailTop", {"kind": "metal"})


func _living(room: Node3D, id: String, hw: float, hd: float) -> void:
	var sofa := _group(room, id, "Sofa", Vector3(0.0, 0, hd - 1.0))
	_c(sofa, Vector3(2.6, 0.45, 0.9), Vector3(0, 0.225, 0), "SofaSeat", {"kind": "fabric", "tint": Color(0.9, 0.6, 0.7)})
	_c(sofa, Vector3(2.6, 0.8, 0.2), Vector3(0, 0.65, 0.4), "SofaBack", {"kind": "fabric", "tint": Color(0.8, 0.5, 0.65)})
	var tv := _group(room, id, "TvUnit", Vector3(hw - 0.5, 0, 0.0))
	_c(tv, Vector3(0.5, 0.5, 2.0), Vector3(0, 0.25, 0), "TvStand", {})
	_c(tv, Vector3(0.1, 0.8, 1.4), Vector3(-0.05, 0.9, 0), "TvScreenOff", {"kind": "plastic", "tint": Color(0.5, 0.55, 0.6)})
	var table := _group(room, id, "CoffeeTable", Vector3(0.2, 0, 0.2))
	_c(table, Vector3(1.4, 0.06, 0.8), Vector3(0, 0.45, 0), "TableTop", {})
	for x in [-0.6, 0.6]:
		_c(table, Vector3(0.08, 0.45, 0.6), Vector3(x, 0.225, 0), "TableLeg", {})
	var shelf := _group(room, id, "Bookshelf", Vector3(-hw + 0.4, 0, -1.0))
	_c(shelf, Vector3(0.4, 1.9, 1.6), Vector3(0, 0.95, 0), "ShelfBody", {})
	for i in 4:
		_c(shelf, Vector3(0.3, 0.3, 0.3), Vector3(0, 0.3 + i * 0.45, 0), "BookBox", {"kind": ["red", "green", "fabric", "label"][i], "tint": Color(0.8, 0.8, 0.9)})


func _galley(room: Node3D, id: String, hw: float, hd: float) -> void:
	var counter := _group(room, id, "Counter", Vector3(0, 0, -hd + 0.6))
	_c(counter, Vector3(hw * 2.0 - 1.0, 0.9, 0.8), Vector3(0, 0.45, 0), "CounterBody", {})
	_c(counter, Vector3(hw * 2.0 - 0.9, 0.06, 0.9), Vector3(0, 0.93, 0), "CounterTop", {"kind": "metal", "tint": Color(1.2, 1.2, 1.25)})
	var fridge := _group(room, id, "Fridge", Vector3(hw - 0.8, 0, hd - 0.8))
	_c(fridge, Vector3(0.9, 1.9, 0.9), Vector3(0, 0.95, 0), "FridgeBody", {"tint": Color(1.2, 1.25, 1.3)})
	var table := _group(room, id, "KitchenTable", Vector3(-1.0, 0, 0.8))
	_c(table, Vector3(1.4, 0.08, 1.0), Vector3(0, 0.75, 0), "TableTop", {})
	for x in [-0.6, 0.6]:
		for z in [-0.4, 0.4]:
			_c(table, Vector3(0.08, 0.75, 0.08), Vector3(x, 0.375, z), "TableLeg", {})
	for x in [-0.5, 0.5]:
		_c(table, Vector3(0.4, 0.06, 0.4), Vector3(x, 0.45, 0.75), "ChairSeat", {})
