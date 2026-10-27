class_name NightWatchBuilding
extends Node3D

## The building the cameras look into: the eight rooms of Classic (NightWatchData.ROOMS) as small blocky rooms laid out on a grid
## far from the office, each with a camera mount and two floor spots for hunters. Everything is built from shaded cubes
## (NightWatchArt: baked vertex-colour shading and painted pixel textures, no post effects) in named prop groups; the feed camera
## has its own brighter ambient so the rooms read on the monitor while the office stays dark. Generated, so identical everywhere.

const A := preload("res://src/night_watch/night_watch_art.gd")
const CELL := 8.0
const ROOM_W := 6.0
const ROOM_H := 3.2
## Where the building sits relative to the office (north of it, out of sight of the office camera).
const ORIGIN := Vector3(-8.0, 0.0, -40.0)

## wall tint per room (multiplied with the wall texture)
const COLORS := {
	"stage": Color(1.25, 0.8, 1.0), "dining": Color(1.3, 1.1, 0.85), "backstage": Color(0.85, 0.95, 1.25),
	"westhall": Color(1.0, 1.05, 1.15), "closet": Color(1.2, 1.0, 0.85), "kitchen": Color(0.95, 1.25, 1.2),
	"easthall": Color(1.0, 1.05, 1.15), "corner": Color(1.2, 0.95, 1.25),
}

var rooms := {}   # room id -> Node3D (the room's centre on the floor)
var props := {}   # "room/prop" -> Node3D (for the validator)


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
		_build_room(room, String(id), COLORS.get(id, Color.WHITE))


func _c(parent: Node3D, size: Vector3, pos: Vector3, node_name: String, opts := {}) -> MeshInstance3D:
	var o := opts.duplicate()
	o["name"] = node_name
	return A.box(parent, size, pos, o)


func _group(room: Node3D, id: String, prop_name: String, pos := Vector3.ZERO) -> Node3D:
	var node := A.prop(room, prop_name, pos)
	props["%s/%s" % [id, prop_name]] = node
	return node


func _build_room(room: Node3D, id: String, tint: Color) -> void:
	var half := ROOM_W * 0.5
	var shell := _group(room, id, "Shell")
	# floor tiles, ceiling, three walls (the south side is open toward the camera side so the feed sees in)
	_c(shell, Vector3(ROOM_W, 0.2, ROOM_W), Vector3(0, -0.1, 0), "Floor", {"tint": tint * Color(0.95, 0.95, 0.95)})
	_c(shell, Vector3(ROOM_W, 0.2, ROOM_W), Vector3(0, ROOM_H + 0.1, 0), "Ceiling", {"tint": tint * Color(0.6, 0.6, 0.6)})
	_c(shell, Vector3(ROOM_W, ROOM_H, 0.2), Vector3(0, ROOM_H * 0.5, -half), "WallN", {"tint": tint})
	_c(shell, Vector3(0.2, ROOM_H, ROOM_W), Vector3(-half, ROOM_H * 0.5, 0), "WallW", {"tint": tint * Color(1.05, 1.05, 1.05)})
	_c(shell, Vector3(0.2, ROOM_H, ROOM_W), Vector3(half, ROOM_H * 0.5, 0), "WallE", {"tint": tint * Color(1.05, 1.05, 1.05)})
	# baseboards, a crown strip, vertical panel lines, a ceiling pipe, a lit ceiling panel, a floor stripe
	_c(shell, Vector3(ROOM_W, 0.24, 0.08), Vector3(0, 0.12, -half + 0.14), "Baseboard", {"tint": Color(0.7, 0.7, 0.75)})
	for sx in [-half + 0.14, half - 0.14]:
		_c(shell, Vector3(0.08, 0.24, ROOM_W), Vector3(sx, 0.12, 0), "Baseboard", {"tint": Color(0.7, 0.7, 0.75)})
		_c(shell, Vector3(0.08, 0.12, ROOM_W), Vector3(sx, ROOM_H - 0.06, 0), "CrownTrim", {"tint": Color(0.85, 0.85, 0.9)})
	_c(shell, Vector3(ROOM_W, 0.12, 0.08), Vector3(0, ROOM_H - 0.06, -half + 0.14), "CrownTrim", {"tint": Color(0.85, 0.85, 0.9)})
	for x in [-2.0, 0.0, 2.0]:
		_c(shell, Vector3(0.06, ROOM_H - 0.6, 0.05), Vector3(x, ROOM_H * 0.5, -half + 0.12), "PanelLine", {"tint": Color(0.8, 0.8, 0.85)})
	_c(shell, Vector3(ROOM_W - 0.4, 0.11, 0.11), Vector3(0, ROOM_H - 0.22, -half + 0.2), "PipeRoom", {"kind": "metal"})
	_c(shell, Vector3(1.4, 0.05, 1.4), Vector3(0, ROOM_H - 0.04, 0), "CeilingPanel", {})
	_c(shell, Vector3(ROOM_W, 0.02, 0.3), Vector3(0, 0.01, 0.8), "FloorStripe", {"kind": "label", "tint": Color(0.8, 0.8, 0.8)})
	_c(shell, Vector3(0.05, 0.05, 0.05), Vector3(-half + 0.2, 2.6, half - 0.3), "LedSmoke", {})
	# a vent grille on the north wall, wall bolts, a floor drain and a little clutter in every room
	var detail := _group(room, id, "Details")
	_c(detail, Vector3(0.7, 0.4, 0.06), Vector3(1.9, 2.5, -half + 0.14), "VentGrille", {"kind": "metal"})
	for i in 3:
		_c(detail, Vector3(0.6, 0.03, 0.04), Vector3(1.9, 2.4 + i * 0.1, -half + 0.19), "VentSlat", {"kind": "plastic"})
	for x in [-2.6, -1.0, 1.0, 2.6]:
		_c(detail, Vector3(0.06, 0.06, 0.04), Vector3(x, 0.4, -half + 0.12), "WallBolt", {"kind": "metal", "tint": Color(1.2, 1.2, 1.2)})
	_c(detail, Vector3(0.3, 0.02, 0.3), Vector3(2.0, 0.01, 1.6), "FloorDrain", {"kind": "metal", "tint": Color(0.6, 0.6, 0.65)})
	_c(detail, Vector3(0.2, 0.2, 0.2), Vector3(-2.4, 0.1, 2.0), "ClutterBox", {"kind": "wood", "tint": Color(0.9, 0.85, 0.8)})
	_c(detail, Vector3(0.16, 0.16, 0.16), Vector3(-2.15, 0.08, 2.1), "ClutterCan", {"kind": "metal", "tint": Color(0.8, 1.1, 0.8)})
	_c(detail, Vector3(0.3, 0.02, 0.22), Vector3(-2.3, 0.02, 1.7), "ClutterPaper", {"kind": "label", "tint": Color(1.2, 1.2, 1.1), "ao": 1.0})
	match id:
		"stage":
			_stage(room, id, half)
		"dining":
			_dining(room, id)
		"backstage":
			_backstage(room, id, half)
		"westhall", "easthall":
			_hall(room, id, half)
		"closet":
			_closet(room, id, half)
		"kitchen":
			_kitchen(room, id, half)
		"corner":
			_corner(room, id, half)


func _stage(room: Node3D, id: String, half: float) -> void:
	var stage := _group(room, id, "Stage", Vector3(0, 0, -1.8))
	_c(stage, Vector3(4.4, 0.45, 2.0), Vector3(0, 0.225, 0), "PlatformDeck", {})
	_c(stage, Vector3(4.5, 0.06, 2.1), Vector3(0, 0.46, 0), "PlatformEdge", {"tint": Color(1.2, 1.2, 1.2)})
	for i in 2:
		_c(stage, Vector3(1.4, 0.15 + i * 0.15, 0.3), Vector3(0, 0.075 + i * 0.075, 1.15 + (1 - i) * 0.3), "PlatformStep", {})
	var curtains := _group(room, id, "Curtains")
	for x in [-2.4, 2.4]:
		_c(curtains, Vector3(0.5, 2.6, 0.14), Vector3(x, 1.4, -2.7), "CurtainDrape", {"tint": Color(1.0, 0.35, 0.4)})
		_c(curtains, Vector3(0.1, 0.1, 0.18), Vector3(x + (0.3 if x < 0.0 else -0.3), 1.0, -2.68), "CurtainTie", {"kind": "label"})
	_c(curtains, Vector3(5.4, 0.3, 0.16), Vector3(0, 2.7, -2.7), "CurtainValance", {"tint": Color(1.0, 0.35, 0.4)})
	var lights := _group(room, id, "StageLights", Vector3(0, 2.8, -1.2))
	_c(lights, Vector3(4.0, 0.08, 0.08), Vector3.ZERO, "LightBar", {"kind": "metal"})
	for x in [-1.6, -0.5, 0.5, 1.6]:
		_c(lights, Vector3(0.22, 0.22, 0.3), Vector3(x, -0.15, 0), "LightCan", {"kind": "plastic"})
		_c(lights, Vector3(0.14, 0.14, 0.04), Vector3(x, -0.15, 0.17), "GlowCan", {})
	var mic := _group(room, id, "Microphone", Vector3(0.0, 0.46, -0.9))
	_c(mic, Vector3(0.3, 0.04, 0.3), Vector3(0, 0.02, 0), "MicBase", {"kind": "metal"})
	_c(mic, Vector3(0.04, 1.2, 0.04), Vector3(0, 0.6, 0), "MicStand", {"kind": "metal"})
	_c(mic, Vector3(0.08, 0.16, 0.08), Vector3(0, 1.28, 0), "MicHead", {"kind": "plastic"})


func _dining(room: Node3D, id: String) -> void:
	for t in [[-1.8, -1.2], [1.8, -1.2], [-1.8, 1.4], [1.8, 1.4]]:
		var table := _group(room, id, "Table%d" % props.size(), Vector3(t[0], 0, t[1]))
		_c(table, Vector3(1.2, 0.08, 1.2), Vector3(0, 0.75, 0), "TableTop", {})
		_c(table, Vector3(1.26, 0.03, 1.26), Vector3(0, 0.8, 0), "TableCloth", {"kind": "fabric", "tint": Color(1.3, 0.8, 0.8)})
		_c(table, Vector3(0.12, 0.75, 0.12), Vector3(0, 0.375, 0), "TableLeg", {})
		_c(table, Vector3(0.5, 0.03, 0.5), Vector3(0, 0.02, 0), "TableFoot", {"kind": "metal"})
		_c(table, Vector3(0.1, 0.16, 0.1), Vector3(0.0, 0.89, 0.0), "TableVase", {"kind": "glass"})
		for cx in [-0.8, 0.8]:
			_c(table, Vector3(0.4, 0.06, 0.4), Vector3(cx, 0.46, 0), "ChairSeat", {})
			_c(table, Vector3(0.06, 0.4, 0.4), Vector3(cx + (-0.17 if cx < 0.0 else 0.17), 0.7, 0), "ChairBack", {})
			for lz in [-0.15, 0.15]:
				_c(table, Vector3(0.05, 0.43, 0.05), Vector3(cx, 0.215, lz), "ChairLeg", {})


func _backstage(room: Node3D, id: String, half: float) -> void:
	var crates := _group(room, id, "Crates", Vector3(-1.3, 0, -1.95))
	for p in [[-0.5, 0.45, 0.0], [0.5, 0.45, -0.05], [0.0, 1.35, -0.02]]:
		_c(crates, Vector3(0.9, 0.9, 0.9), Vector3(p[0], p[1], p[2]), "CrateBox", {})
		_c(crates, Vector3(0.94, 0.08, 0.94), Vector3(p[0], p[1] + 0.3, p[2]), "CrateBand", {"kind": "metal", "tint": Color(0.8, 0.8, 0.85)})
	var rack := _group(room, id, "CostumeRack", Vector3(1.6, 0, -1.8))
	_c(rack, Vector3(1.6, 0.05, 0.05), Vector3(0, 1.7, 0), "RackRail", {"kind": "metal"})
	for x in [-0.75, 0.75]:
		_c(rack, Vector3(0.05, 1.7, 0.05), Vector3(x, 0.85, 0), "RackPost", {"kind": "metal"})
		_c(rack, Vector3(0.05, 0.05, 0.5), Vector3(x, 0.025, 0), "RackFoot", {"kind": "metal"})
	for i in 5:
		_c(rack, Vector3(0.22, 0.9 - (i % 2) * 0.2, 0.12), Vector3(-0.6 + i * 0.3, 1.2 - (i % 2) * 0.1, 0), "RackCostume", {"kind": "fabric", "tint": Color(0.8 + 0.15 * i, 1.0 - 0.1 * i, 1.2)})
	var mirror := _group(room, id, "Mirror", Vector3(-half + 0.2, 1.4, 0.4))
	_c(mirror, Vector3(0.08, 1.4, 0.9), Vector3.ZERO, "MirrorFrame", {})
	_c(mirror, Vector3(0.05, 1.3, 0.8), Vector3(0.04, 0, 0), "MirrorGlass", {"kind": "glass"})


func _hall(room: Node3D, id: String, half: float) -> void:
	var side := -1.0 if id == "westhall" else 1.0
	var lockers := _group(room, id, "Lockers", Vector3(side * (half - 0.35), 0, 1.4))
	for i in 3:
		_c(lockers, Vector3(0.55, 2.1, 0.7), Vector3(0, 1.05, -i * 0.74), "LockerBody", {"tint": Color(0.75 + 0.1 * i, 0.85, 1.0)})
		_c(lockers, Vector3(0.05, 1.9, 0.6), Vector3(-side * 0.29, 1.05, -i * 0.74), "LockerDoor", {"kind": "metal", "tint": Color(0.9, 0.9, 0.95)})
		_c(lockers, Vector3(0.05, 0.06, 0.18), Vector3(-side * 0.32, 1.1, -i * 0.74 + 0.2), "LockerHandle", {"kind": "plastic", "tint": Color(1.4, 1.4, 1.4)})
		for v in 3:
			_c(lockers, Vector3(0.05, 0.02, 0.3), Vector3(-side * 0.32, 1.7 + v * 0.06, -i * 0.74), "LockerVent", {"kind": "plastic"})
	var runner := _group(room, id, "Runner")
	_c(runner, Vector3(0.9, 0.04, 4.8), Vector3(0, 0.02, 0), "RunnerMat", {"kind": "fabric", "tint": Color(0.9, 0.8, 1.0)})
	for z in [-2.2, 2.2]:
		_c(runner, Vector3(0.9, 0.045, 0.1), Vector3(0, 0.025, z), "RunnerTrim", {"kind": "label", "tint": Color(0.9, 0.9, 0.9)})
	var sign := _group(room, id, "Signs", Vector3(0, 2.2, -half + 0.2))
	_c(sign, Vector3(1.4, 0.3, 0.05), Vector3.ZERO, "SignPlate", {"kind": "plastic"})
	_c(sign, Vector3(1.2, 0.14, 0.03), Vector3(0, 0, 0.03), "SignText", {})
	var lamp := _group(room, id, "EmergencyLight", Vector3(side * (half - 0.25), 2.5, -0.5))
	_c(lamp, Vector3(0.2, 0.14, 0.2), Vector3.ZERO, "EmergencyHousing", {"kind": "plastic"})
	_c(lamp, Vector3(0.14, 0.08, 0.04), Vector3(-side * 0.0, 0.0, 0.11), "GlowEmergency", {"kind": "red"})


func _closet(room: Node3D, id: String, half: float) -> void:
	var shelves := _group(room, id, "Shelves", Vector3(-2.4, 0, -0.4))
	for z in [-1.8, 1.8]:
		_c(shelves, Vector3(0.5, 2.4, 0.06), Vector3(0, 1.2, z), "ShelfSide", {})
	for i in 4:
		_c(shelves, Vector3(0.5, 0.05, 3.6), Vector3(0, 0.3 + i * 0.6, 0), "ShelfBoard", {})
	for i in 7:
		_c(shelves, Vector3(0.36, 0.2 + (i % 3) * 0.06, 0.34), Vector3(0, 0.45 + (i % 4) * 0.6 + 0.0, -1.5 + i * 0.5), "ShelfBox", {"kind": "wood", "tint": Color(0.8 + (i % 3) * 0.12, 0.85, 0.8)})
	var bucket := _group(room, id, "MopBucket", Vector3(1.6, 0, -2.0))
	_c(bucket, Vector3(0.42, 0.34, 0.42), Vector3(0, 0.17, 0), "BucketBody", {"kind": "plastic", "tint": Color(1.2, 1.4, 1.8)})
	_c(bucket, Vector3(0.04, 1.5, 0.04), Vector3(0.1, 0.9, 0.0), "MopHandle", {})
	_c(bucket, Vector3(0.18, 0.2, 0.18), Vector3(0.1, 0.35, 0.0), "MopHead", {"kind": "fabric", "tint": Color(1.3, 1.3, 1.3)})
	var cans := _group(room, id, "Paint", Vector3(0.6, 0, -2.4))
	for i in 3:
		_c(cans, Vector3(0.22, 0.22, 0.22), Vector3(-0.3 + i * 0.28, 0.11, 0), "PaintCan", {"kind": "metal", "tint": Color(0.8 + i * 0.2, 1.0 - i * 0.2, 0.8)})


func _kitchen(room: Node3D, id: String, half: float) -> void:
	var counter := _group(room, id, "Counter", Vector3(0, 0, -2.3))
	_c(counter, Vector3(4.6, 0.9, 0.9), Vector3(0, 0.45, 0), "CounterBody", {})
	_c(counter, Vector3(4.7, 0.06, 1.0), Vector3(0, 0.93, 0), "CounterTop", {"kind": "metal", "tint": Color(1.2, 1.2, 1.25)})
	for x in [-1.8, -0.6, 0.6, 1.8]:
		_c(counter, Vector3(0.9, 0.5, 0.04), Vector3(x, 0.5, 0.47), "CounterDoor", {"kind": "plastic", "tint": Color(1.3, 1.3, 1.3)})
		_c(counter, Vector3(0.12, 0.03, 0.04), Vector3(x, 0.7, 0.5), "CounterHandle", {"kind": "metal"})
	_c(counter, Vector3(0.7, 0.04, 0.5), Vector3(1.4, 0.97, 0.0), "SinkBasin", {"kind": "metal", "tint": Color(0.6, 0.6, 0.65)})
	_c(counter, Vector3(0.06, 0.3, 0.06), Vector3(1.4, 1.1, -0.3), "TapNeck", {"kind": "metal"})
	var hood := _group(room, id, "Hood", Vector3(-1.2, 2.0, -2.45))
	_c(hood, Vector3(1.6, 0.5, 0.7), Vector3(0, 0.25, 0), "HoodBody", {"kind": "metal"})
	_c(hood, Vector3(0.4, 0.8, 0.4), Vector3(0, 0.9, 0), "HoodDuct", {"kind": "metal"})
	for i in 3:
		_c(hood, Vector3(0.08, 0.5, 0.06), Vector3(-0.5 + i * 0.5, -0.45, 0.2), "HangingPan", {"kind": "metal", "tint": Color(0.6, 0.6, 0.65)})
	var fridge := _group(room, id, "Fridge", Vector3(2.1, 0, 1.5))
	_c(fridge, Vector3(1.0, 2.0, 1.0), Vector3(0, 1.0, 0), "FridgeBody", {"tint": Color(1.2, 1.25, 1.3)})
	_c(fridge, Vector3(0.05, 0.6, 0.06), Vector3(-0.52, 1.3, 0.3), "FridgeHandle", {"kind": "metal"})
	_c(fridge, Vector3(0.9, 0.04, 0.04), Vector3(0, 1.4, -0.52), "FridgeSeam", {"kind": "plastic"})
	var stove := _group(room, id, "Stove", Vector3(-1.5, 0, -2.3))
	for x in [-0.3, 0.3]:
		for z in [-0.2, 0.2]:
			_c(stove, Vector3(0.28, 0.03, 0.28), Vector3(x, 0.97, z), "StoveBurner", {"kind": "plastic"})


func _corner(room: Node3D, id: String, half: float) -> void:
	var pillar := _group(room, id, "Pillar", Vector3(-2.0, 0, -2.0))
	_c(pillar, Vector3(0.7, 3.2, 0.7), Vector3(0, 1.6, 0), "PillarBody", {})
	_c(pillar, Vector3(0.85, 0.25, 0.85), Vector3(0, 0.125, 0), "PillarFoot", {"tint": Color(1.2, 1.2, 1.2)})
	_c(pillar, Vector3(0.85, 0.2, 0.85), Vector3(0, 3.0, 0), "PillarCap", {"tint": Color(1.2, 1.2, 1.2)})
	_c(pillar, Vector3(0.1, 0.5, 0.05), Vector3(0.0, 1.5, 0.38), "PillarSign", {"kind": "label"})
	var bench := _group(room, id, "Bench", Vector3(2.0, 0, -2.3))
	_c(bench, Vector3(1.6, 0.1, 0.55), Vector3(0, 0.5, 0), "BenchSeat", {})
	_c(bench, Vector3(1.6, 0.5, 0.08), Vector3(0, 0.8, -0.25), "BenchBack", {})
	for x in [-0.7, 0.7]:
		_c(bench, Vector3(0.1, 0.5, 0.45), Vector3(x, 0.25, 0), "BenchLeg", {"kind": "metal"})
	var vend := _group(room, id, "VendingMachine", Vector3(0.3, 0, -2.2))
	_c(vend, Vector3(1.0, 1.9, 0.8), Vector3(0, 0.95, 0), "VendBody", {"kind": "plastic", "tint": Color(1.6, 0.9, 0.9)})
	_c(vend, Vector3(0.7, 1.2, 0.04), Vector3(-0.08, 1.1, 0.42), "VendGlass", {"kind": "glass"})
	_c(vend, Vector3(0.7, 0.08, 0.03), Vector3(-0.08, 1.75, 0.44), "SignVend", {})
	for i in 4:
		_c(vend, Vector3(0.62, 0.03, 0.2), Vector3(-0.08, 0.75 + i * 0.28, 0.35), "VendShelf", {"kind": "metal"})
	_c(vend, Vector3(0.14, 0.5, 0.04), Vector3(0.38, 1.2, 0.42), "VendKeypad", {"kind": "plastic"})
	var plant := _group(room, id, "Plant", Vector3(-0.3, 0, 1.9))
	_c(plant, Vector3(0.4, 0.4, 0.4), Vector3(0, 0.2, 0), "PlantPot", {"kind": "concrete", "tint": Color(1.3, 0.9, 0.8)})
	for i in 4:
		_c(plant, Vector3(0.12, 0.5 + 0.1 * i, 0.12), Vector3(-0.1 + (i % 2) * 0.2, 0.65 + 0.05 * i, -0.08 + (i / 2) * 0.16), "PlantLeaf", {"kind": "green", "tint": Color(0.6, 1.0, 0.6)})


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
