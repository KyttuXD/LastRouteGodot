class_name MixedWorld
extends Node3D

## Mixed Shift's 3D map (MixedMap): the transit hub around the security office (hub_office at the origin; its two halls open into the arcades). Concourse (stage / platform side to the north), the
## platform and the ticket hall, the west and east arcades down either side, the cafe between the concourse and the office, lost property and the newsstand at the arcades' south ends. Walls with
## doorway gaps (recorded in `wall_boxes`), an AStar graph the hunters WALK (keys "C:<sim room>" and "D:doorL" / "D:doorR"; every sim room id is Classic's, the map names are MixedMap's), the feed
## cameras and the three nightly dressings: 0 the station as it is, 1 a party floor (Masked Hours' balloons, tables, streamers, arcade cabinets), 2 a salvage yard (Salvage Run's containers, scrap, barrels, a crane arm).

const A := preload("res://game/night_watch/night_watch_art.gd")
const H := 3.6
const THICK := 0.2
const BALLOON_TINTS := [Color(1.9, 0.5, 0.5), Color(0.6, 1.0, 1.9), Color(1.9, 1.6, 0.4), Color(0.7, 1.8, 0.7), Color(1.8, 0.7, 1.7)]
## each sim room: its floor rectangle [x0, x1, z0, z1] in building space (the office is at the origin) and the floor tint of the plain station
const AREAS := {
	"stage": [-9.5, 9.5, -46.0, -30.0, Color(1.0, 1.1, 1.4)],
	"backstage": [-26.0, -9.5, -46.0, -30.0, Color(0.9, 0.9, 1.3)],
	"dining": [-9.5, 9.5, -30.0, -14.0, Color(1.3, 1.25, 1.1)],
	"westhall": [-20.0, -9.5, -30.0, 6.0, Color(1.1, 1.2, 1.2)],
	"easthall": [9.5, 20.0, -30.0, 6.0, Color(1.1, 1.2, 1.2)],
	"kitchen": [-8.0, 8.0, -13.0, -5.0, Color(1.2, 1.3, 1.2)],
	"closet": [-20.0, -9.5, 6.0, 16.0, Color(1.2, 1.1, 0.9)],
	"corner": [9.5, 20.0, 6.0, 16.0, Color(1.2, 1.1, 0.9)],
}

var dress_set := 0
var astar := AStar3D.new()
var points := {}
var _ids := {}
var _keys := {}
var rooms := {}        # sim room id -> Node3D (the room's centre)
var wall_boxes := []
var office: Node3D


func _ready() -> void:
	if rooms.is_empty():
		build()


func _b(parent: Node3D, size: Vector3, pos: Vector3, node_name: String, opts := {}) -> MeshInstance3D:
	var o: Dictionary = opts.duplicate()
	o["name"] = node_name
	return A.box(parent, size, pos, o)


func _wall(parent: Node3D, along_x: bool, fixed: float, a: float, b: float, gaps: Array, tint: Color, node_name := "WallHub") -> void:
	var cuts := [a]
	for g in gaps:
		cuts.append(float(g[0]))
		cuts.append(float(g[1]))
	cuts.append(b)
	var i := 0
	while i < cuts.size() - 1:
		var s: float = cuts[i]
		var e: float = cuts[i + 1]
		i += 2
		if e - s < 0.05:
			continue
		var length := e - s
		var mid := (s + e) * 0.5
		_b(parent, Vector3(length, H, THICK) if along_x else Vector3(THICK, H, length), Vector3(mid, H * 0.5, fixed) if along_x else Vector3(fixed, H * 0.5, mid), node_name, {"tint": tint})
		wall_boxes.append({"name": node_name, "rect": Rect2(Vector2(s, fixed - THICK * 0.5), Vector2(length, THICK)) if along_x else Rect2(Vector2(fixed - THICK * 0.5, s), Vector2(THICK, length))})


func build() -> void:
	var root := A.prop(self, "Hub")
	var skin_tint: Color = MixedSkin.skin(dress_set)["tint"]
	var wall: Color = Color(1.3, 1.25, 1.4) * skin_tint
	for id in AREAS:
		var r: Array = AREAS[id]
		var room := A.prop(root, "Area_%s" % id)
		var x0: float = r[0]
		var x1: float = r[1]
		var z0: float = r[2]
		var z1: float = r[3]
		var floor_tint: Color = (r[4] as Color) * skin_tint
		_b(room, Vector3(x1 - x0, 0.2, z1 - z0), Vector3((x0 + x1) * 0.5, -0.1, (z0 + z1) * 0.5), "FloorHub", {"tint": floor_tint})
		_b(room, Vector3(x1 - x0, 0.2, z1 - z0), Vector3((x0 + x1) * 0.5, H + 0.1, (z0 + z1) * 0.5), "CeilingHub", {"tint": Color(0.8, 0.8, 0.9)})
		var marker := Node3D.new()
		marker.name = "Room_%s" % id
		marker.position = Vector3((x0 + x1) * 0.5, 0.0, (z0 + z1) * 0.5)
		add_child(marker)
		rooms[id] = marker
	# the walls (a doorway is a gap): the concourse / platform / ticket hall block to the north, the arcades down both sides, the cafe, the two ends
	_wall(root, true, -46.0, -26.0, 9.5, [], wall)
	_wall(root, true, -30.0, -26.0, -9.5, [[-17.0, -13.0]], wall)       # ticket hall / west arcade (backstage - westhall)
	_wall(root, true, -30.0, -9.5, 9.5, [[-4.0, 4.0]], wall)             # platform / concourse (stage - dining)
	_wall(root, true, -30.0, 9.5, 20.0, [], wall)                        # the east arcade's north end
	_wall(root, false, -26.0, -46.0, -30.0, [], wall)
	_wall(root, false, -9.5, -46.0, -30.0, [[-40.0, -36.0]], wall)       # ticket hall / platform (backstage - stage)
	_wall(root, false, -9.5, -30.0, -14.0, [[-24.0, -20.0]], wall)       # concourse / west arcade (dining - westhall)
	_wall(root, false, 9.5, -30.0, -14.0, [[-24.0, -20.0]], wall)        # concourse / east arcade (dining - easthall)
	_wall(root, false, 9.5, -46.0, -30.0, [], wall)
	_wall(root, true, -14.0, -9.5, 9.5, [[-2.0, 2.0]], wall)             # concourse south wall, with the cafe door (dining - kitchen)
	_wall(root, true, -13.0, -8.0, 8.0, [[-2.0, 2.0]], wall, "WallCafe")
	_wall(root, true, -5.0, -8.0, 8.0, [], wall, "WallCafe")
	_wall(root, false, -8.0, -13.0, -5.0, [], wall, "WallCafe")
	_wall(root, false, 8.0, -13.0, -5.0, [], wall, "WallCafe")
	_wall(root, false, -20.0, -30.0, 16.0, [], wall)                     # the west arcade's and lost property's outer wall
	_wall(root, false, 20.0, -30.0, 16.0, [], wall)
	_wall(root, false, -9.5, -14.0, 16.0, [[-1.7, 1.7]], wall)           # the arcades' inner walls south of the concourse; the door halls open into them
	_wall(root, false, 9.5, -14.0, 16.0, [[-1.7, 1.7]], wall)
	_wall(root, true, 6.0, -20.0, -9.5, [[-17.0, -13.0]], wall)          # arcade / lost property (westhall - closet)
	_wall(root, true, 6.0, 9.5, 20.0, [[13.0, 17.0]], wall)
	_wall(root, true, 16.0, -20.0, -9.5, [], wall)
	_wall(root, true, 16.0, 9.5, 20.0, [], wall)
	_dress(root)
	_signs(root)
	_build_paths()


func _signs(root: Node3D) -> void:
	for pair in [["platform", Vector3(0, 2.8, -45.8)], ["concourse", Vector3(0, 2.8, -29.8)], ["west_arcade", Vector3(-19.8, 2.8, -10)], ["east_arcade", Vector3(19.8, 2.8, -10)],
			["cafe", Vector3(0, 2.6, -12.8)], ["ticket_hall", Vector3(-17.5, 2.8, -45.8)]]:
		_b(root, Vector3(3.0, 0.5, 0.1) if String(pair[0]) != "west_arcade" and String(pair[0]) != "east_arcade" else Vector3(0.1, 0.5, 3.0), pair[1], "SignHub", {"kind": "label", "tint": Color(1.5, 1.2, 0.5)})


# --- the three dressings -------------------------------------------------------------------------------------------------------------

func _dress(root: Node3D) -> void:
	var kit := String(MixedSkin.skin(dress_set)["kit"])
	var d := A.prop(root, "Dressing%d" % dress_set)
	for id in AREAS:
		var r: Array = AREAS[id]
		var cx := (float(r[0]) + float(r[1])) * 0.5
		var cz := (float(r[2]) + float(r[3])) * 0.5
		var w := float(r[1]) - float(r[0])
		var l := float(r[3]) - float(r[2])
		# three props in the room's corners (the lanes along the room's middle stay clear)
		var spots := [Vector3(cx - w * 0.32, 0, cz - l * 0.3), Vector3(cx + w * 0.32, 0, cz + l * 0.3), Vector3(cx + w * 0.32, 0, cz - l * 0.3)]
		if id == "westhall" or id == "easthall":
			var side := -1.0 if id == "westhall" else 1.0
			spots = [Vector3(cx + side * 3.4, 0, cz - 14.0), Vector3(cx + side * 3.4, 0, cz + 8.0), Vector3(cx + side * 3.4, 0, cz - 3.0)]
		elif id == "kitchen":
			spots = [Vector3(cx - 5.0, 0, cz), Vector3(cx + 5.0, 0, cz)]
		for k in spots.size():
			match kit:
				"bench":
					_bench(d, spots[k], k)
				"party":
					_party(d, spots[k], k)
				"yard":
					_yard(d, spots[k], k)
				"pizzeria":
					_pizzeria(d, spots[k], k)
				"studio":
					_studio(d, spots[k], k)
				"house":
					_house(d, spots[k], k)
				"lab":
					_lab(d, spots[k], k)
				"shaft":
					_shaft(d, spots[k], k)
				_:
					_camp(d, spots[k], k)


func _bench(parent: Node3D, pos: Vector3, k: int) -> void:
	var p := A.prop(parent, "Bench", pos)
	_b(p, Vector3(2.0, 0.1, 0.6), Vector3(0, 0.5, 0), "SeatBench", {"kind": "wood", "tint": Color(1.4, 1.0, 0.8)})
	_b(p, Vector3(2.0, 0.5, 0.08), Vector3(0, 0.8, 0.28), "BackBench", {"kind": "wood", "tint": Color(1.4, 1.0, 0.8)})
	for sx in [-0.9, 0.9]:
		_b(p, Vector3(0.1, 0.5, 0.5), Vector3(sx, 0.25, 0), "LegBench", {"kind": "metal"})
	if k % 2 == 0:   # a departures board
		_b(p, Vector3(1.4, 0.8, 0.1), Vector3(0, 2.4, -0.4), "BoardHub", {"kind": "plastic"})
		_b(p, Vector3(1.2, 0.6, 0.04), Vector3(0, 2.4, -0.33), "ScreenBoardHub", {})
	else:   # a suitcase
		_b(p, Vector3(0.7, 0.5, 0.3), Vector3(1.4, 0.25, 0.3), "CaseHub", {"kind": "fabric", "tint": BALLOON_TINTS[k % 5]})


func _party(parent: Node3D, pos: Vector3, k: int) -> void:
	var p := A.prop(parent, "PartyDress", pos)
	if k % 3 == 0:
		_b(p, Vector3(1.8, 0.08, 1.0), Vector3(0, 0.78, 0), "TableTop", {"kind": "fabric", "tint": BALLOON_TINTS[k % 5]})
		for sx in [-0.8, 0.8]:
			_b(p, Vector3(0.08, 0.76, 0.08), Vector3(sx, 0.38, 0), "TableLeg", {"kind": "metal"})
		_b(p, Vector3(0.32, 0.22, 0.32), Vector3(0, 0.93, 0), "CakeTable", {"kind": "fabric", "tint": Color(1.8, 1.5, 1.6)})
	elif k % 3 == 1:
		for i in 4:
			var h := 2.0 + (i % 3) * 0.35
			_b(p, Vector3(0.02, h, 0.02), Vector3(-0.3 + i * 0.2, h * 0.5, 0), "StringBalloon", {"kind": "plastic", "tint": Color(1.6, 1.6, 1.6)})
			_b(p, Vector3(0.42, 0.5, 0.42), Vector3(-0.3 + i * 0.2, h + 0.2, 0), "BalloonCube", {"kind": "fabric", "tint": BALLOON_TINTS[i % 5]})
	else:
		_b(p, Vector3(0.9, 1.9, 0.8), Vector3(0, 0.95, 0), "ArcadeBody", {"kind": "plastic", "tint": BALLOON_TINTS[(k + 1) % 5]})
		_b(p, Vector3(0.7, 0.5, 0.04), Vector3(0, 1.35, 0.42), "ScreenArcade", {})
	_b(p, Vector3(5.0, 0.08, 0.1), Vector3(0, 3.0, 0), "StreamerHub", {"kind": "fabric", "tint": BALLOON_TINTS[(k + 2) % 5]})


func _yard(parent: Node3D, pos: Vector3, k: int) -> void:
	var p := A.prop(parent, "YardDress", pos)
	if k % 3 == 0:
		_b(p, Vector3(3.0, 1.4, 1.3), Vector3(0, 0.7, 0), "BodyContainer", {"kind": "metal", "tint": BALLOON_TINTS[k % 5], "solid": false})
		for i in 4:
			_b(p, Vector3(0.06, 1.4, 1.34), Vector3(-1.2 + i * 0.8, 0.7, 0), "RibContainer", {"kind": "metal", "tint": Color(0.9, 0.7, 0.6)})
	elif k % 3 == 1:
		for i in 5:
			_b(p, Vector3(0.9 + (i % 3) * 0.3, 0.6 + (i % 2) * 0.4, 0.9), Vector3(-0.9 + (i % 3) * 0.9, 0.35 + (i / 3) * 0.7, -0.3 + (i % 2) * 0.6), "ScrapBlock", {"kind": "metal", "tint": Color(1.6, 0.9, 0.6) * Color(1.0 - 0.08 * i, 1.0, 1.0)})
	else:
		for i in 3:
			_b(p, Vector3(0.7, 0.95, 0.7), Vector3(i * 0.8, 0.48, (i % 2) * 0.5), "BarrelHold", {"kind": "metal", "tint": Color(1.7, 0.6, 0.4)})
		_b(p, Vector3(0.3, 3.0, 0.3), Vector3(-1.0, 1.5, 0), "LegCrane", {"kind": "metal", "tint": Color(1.7, 1.4, 0.3)})
		_b(p, Vector3(3.0, 0.3, 0.3), Vector3(0.4, 3.0, 0), "BeamCrane", {"kind": "metal", "tint": Color(1.7, 1.4, 0.3)})


# --- the other maps' props (MixedSkin): three small pieces per kit, never in the lanes the hunters walk -----------------------------------

func _pizzeria(parent: Node3D, pos: Vector3, k: int) -> void:
	var p := A.prop(parent, "PizzaDress", pos)
	if k % 3 == 0:   # a table with a cake and two party hats
		_b(p, Vector3(1.6, 0.08, 1.0), Vector3(0, 0.78, 0), "TablePizza", {"kind": "fabric", "tint": Color(1.6, 0.6, 0.5)})
		_b(p, Vector3(0.12, 0.76, 0.12), Vector3(0, 0.38, 0), "LegPizza", {"kind": "metal"})
		_b(p, Vector3(0.3, 0.2, 0.3), Vector3(0, 0.92, 0), "CakePizza", {"kind": "fabric", "tint": Color(1.8, 1.5, 1.6)})
		for sx in [-0.5, 0.5]:
			_b(p, Vector3(0.2, 0.3, 0.2), Vector3(sx, 0.97, 0.3), "HatPizza", {"kind": "plastic", "tint": BALLOON_TINTS[int(sx > 0) + k % 3]})
	elif k % 3 == 1:   # a banner and a checker rug
		_b(p, Vector3(2.4, 0.02, 1.6), Vector3(0, 0.01, 0), "RugPizza", {"kind": "fabric", "tint": Color(1.7, 0.5, 0.5)})
		_b(p, Vector3(3.0, 0.5, 0.05), Vector3(0, 2.8, 0), "BannerPizza", {"kind": "fabric", "tint": Color(1.7, 1.4, 0.4)})
	else:   # a prize cabinet
		_b(p, Vector3(0.8, 1.7, 0.6), Vector3(0, 0.85, 0), "CabinetPizza", {"kind": "plastic", "tint": Color(0.5, 0.9, 1.7)})
		_b(p, Vector3(0.6, 0.6, 0.04), Vector3(0, 1.2, 0.32), "ScreenPizza", {})


func _studio(parent: Node3D, pos: Vector3, k: int) -> void:
	var p := A.prop(parent, "StudioDress", pos)
	if k % 3 == 0:   # a desk with a microphone and a reel
		_b(p, Vector3(1.8, 0.08, 0.8), Vector3(0, 0.76, 0), "DeskStudio", {"kind": "wood", "tint": Color(0.9, 0.8, 0.7)})
		_b(p, Vector3(0.04, 0.5, 0.04), Vector3(0.3, 1.05, 0), "MicStandStudio", {"kind": "metal"})
		_b(p, Vector3(0.14, 0.14, 0.14), Vector3(0.3, 1.34, 0), "MicStudio", {"kind": "plastic", "tint": Color(0.4, 0.4, 0.45)})
		_b(p, Vector3(0.3, 0.06, 0.3), Vector3(-0.5, 0.83, 0), "ReelStudio", {"kind": "metal", "tint": Color(1.2, 1.2, 1.3)})
	elif k % 3 == 1:   # a speaker stack
		for i in 3:
			_b(p, Vector3(0.7, 0.7, 0.6), Vector3(0, 0.35 + i * 0.7, 0), "SpeakerStudio", {"kind": "plastic", "tint": Color(0.5, 0.5, 0.55)})
	else:   # an ON AIR sign
		_b(p, Vector3(1.0, 0.35, 0.08), Vector3(0, 2.6, 0), "OnAirStudio", {"kind": "label", "tint": Color(1.9, 0.3, 0.3)})
		_b(p, Vector3(0.9, 0.5, 0.9), Vector3(0, 0.25, 0), "RackStudio", {"kind": "metal", "tint": Color(0.6, 0.65, 0.7)})


func _house(parent: Node3D, pos: Vector3, k: int) -> void:
	var p := A.prop(parent, "HouseDress", pos)
	if k % 3 == 0:   # a bed
		_b(p, Vector3(1.0, 0.4, 2.0), Vector3(0, 0.3, 0), "BedHouse", {"kind": "wood", "tint": Color(1.3, 0.9, 0.7)})
		_b(p, Vector3(0.9, 0.18, 1.5), Vector3(0, 0.58, 0.2), "BlanketHouse", {"kind": "fabric", "tint": BALLOON_TINTS[k % 5]})
		_b(p, Vector3(0.6, 0.15, 0.35), Vector3(0, 0.62, -0.8), "PillowHouse", {"kind": "fabric", "tint": Color(1.8, 1.8, 1.7)})
	elif k % 3 == 1:   # a wardrobe
		_b(p, Vector3(1.2, 2.2, 0.6), Vector3(0, 1.1, 0), "WardrobeHouse", {"kind": "wood", "tint": Color(1.1, 0.8, 0.6)})
		_b(p, Vector3(0.04, 1.0, 0.02), Vector3(0, 1.1, 0.31), "SeamHouse", {"kind": "metal"})
	else:   # a toy chest with blocks
		_b(p, Vector3(0.9, 0.5, 0.6), Vector3(0, 0.25, 0), "ChestHouse", {"kind": "wood", "tint": Color(1.5, 0.8, 0.5)})
		for i in 3:
			_b(p, Vector3(0.25, 0.25, 0.25), Vector3(-0.6 - i * 0.2, 0.13, 0.3 * (i % 2)), "BlockHouse", {"kind": "plastic", "tint": BALLOON_TINTS[i % 5]})


func _lab(parent: Node3D, pos: Vector3, k: int) -> void:
	var p := A.prop(parent, "LabDress", pos)
	if k % 3 == 0:   # a bench with a beaker
		_b(p, Vector3(2.0, 0.9, 0.8), Vector3(0, 0.45, 0), "BenchLab", {"kind": "metal", "tint": Color(0.9, 1.1, 1.0)})
		_b(p, Vector3(0.16, 0.3, 0.16), Vector3(0.5, 1.05, 0), "BeakerLab", {"kind": "plastic", "tint": Color(0.6, 1.8, 1.2)})
	elif k % 3 == 1:   # a pipe rack
		for i in 3:
			_b(p, Vector3(0.12, 3.0, 0.12), Vector3(-0.4 + i * 0.4, 1.5, 0), "PipeLab", {"kind": "metal", "tint": Color(1.2, 1.1, 0.6) * Color(1.0 - 0.1 * i, 1.0, 1.0)})
	else:   # a console with a status light
		_b(p, Vector3(1.4, 1.0, 0.7), Vector3(0, 0.5, 0), "ConsoleLab", {"kind": "metal", "tint": Color(0.7, 0.8, 0.8)})
		_b(p, Vector3(1.2, 0.5, 0.04), Vector3(0, 1.2, 0.2), "ScreenLab", {})
		_b(p, Vector3(0.2, 0.2, 0.06), Vector3(0.5, 1.7, 0.3), "LightLab", {"kind": "label", "tint": Color(0.4, 1.9, 0.6)})


func _shaft(parent: Node3D, pos: Vector3, k: int) -> void:
	var p := A.prop(parent, "ShaftDress", pos)
	if k % 3 == 0:   # a pillar with a cable
		_b(p, Vector3(0.6, 3.4, 0.6), Vector3(0, 1.7, 0), "PillarShaft", {"kind": "metal", "tint": Color(0.6, 0.65, 0.8)})
		_b(p, Vector3(0.05, 3.0, 0.05), Vector3(0.45, 1.6, 0), "CableShaft", {"kind": "metal", "tint": Color(0.3, 0.3, 0.35)})
	elif k % 3 == 1:   # a lift frame
		_b(p, Vector3(1.6, 0.1, 1.6), Vector3(0, 0.05, 0), "BaseShaft", {"kind": "metal", "tint": Color(1.3, 1.2, 0.5)})
		for sx in [-0.75, 0.75]:
			_b(p, Vector3(0.1, 2.6, 0.1), Vector3(sx, 1.3, 0), "FrameShaft", {"kind": "metal", "tint": Color(1.3, 1.2, 0.5)})
		_b(p, Vector3(1.6, 0.1, 0.1), Vector3(0, 2.6, 0), "BeamShaft", {"kind": "metal", "tint": Color(1.3, 1.2, 0.5)})
	else:   # a counterweight stack
		for i in 4:
			_b(p, Vector3(0.9, 0.3, 0.6), Vector3(0, 0.15 + i * 0.32, 0), "WeightShaft", {"kind": "metal", "tint": Color(0.5, 0.5, 0.58)})


func _camp(parent: Node3D, pos: Vector3, k: int) -> void:
	var p := A.prop(parent, "CampDress", pos)
	if k % 3 == 0:   # a tent
		_b(p, Vector3(2.0, 0.1, 2.0), Vector3(0, 0.05, 0), "GroundCamp", {"kind": "fabric", "tint": Color(0.7, 0.9, 0.6)})
		for sx in [-0.5, 0.5]:
			_b(p, Vector3(1.0, 1.4, 1.8), Vector3(sx, 0.75, 0), "TentCamp", {"kind": "fabric", "tint": Color(1.5, 0.9, 0.4) * Color(1.0 - 0.15 * int(sx > 0), 1.0, 1.0)})
	elif k % 3 == 1:   # logs round a fire
		for i in 3:
			_b(p, Vector3(1.2, 0.3, 0.3), Vector3(0, 0.15, (i - 1) * 0.5), "LogCamp", {"kind": "wood", "tint": Color(1.2, 0.8, 0.5)})
	else:   # a lantern on a post
		_b(p, Vector3(0.1, 2.2, 0.1), Vector3(0, 1.1, 0), "PostCamp", {"kind": "wood", "tint": Color(1.1, 0.8, 0.6)})
		_b(p, Vector3(0.3, 0.4, 0.3), Vector3(0, 2.3, 0), "LanternCamp", {"kind": "label", "tint": Color(1.9, 1.5, 0.6)})


# --- cameras, stands, walking ---------------------------------------------------------------------------------------------------------

func centre_of(sim_room: String) -> Vector3:
	var r: Array = AREAS[sim_room]
	return Vector3((float(r[0]) + float(r[1])) * 0.5, 0.0, (float(r[2]) + float(r[3])) * 0.5)


## The feed camera: high in a corner of the room, looking at its middle.
func camera_transform(sim_room: String) -> Transform3D:
	var r: Array = AREAS[sim_room]
	var c := centre_of(sim_room)
	var w := float(r[1]) - float(r[0])
	var l := float(r[3]) - float(r[2])
	var from := c + Vector3(w * 0.42, 3.0, l * 0.42)
	return Transform3D(Basis.IDENTITY, from).looking_at(c + Vector3(-w * 0.05, 0.8, -l * 0.05), Vector3.UP)


func stand_position(sim_room: String, slot: int) -> Vector3:
	return centre_of(sim_room) + (Vector3(1.0, 0.0, 0.6) if slot == 0 else Vector3(-1.0, 0.0, -0.6))


func _add(key: String, x: float, z: float) -> void:
	var id := astar.get_available_point_id()
	var pos := Vector3(x, 0.0, z)
	astar.add_point(id, pos)
	_ids[key] = id
	_keys[id] = key
	points[key] = pos


func _chain(keys: Array) -> void:
	for i in range(keys.size() - 1):
		astar.connect_points(int(_ids[keys[i]]), int(_ids[keys[i + 1]]), true)


func _build_paths() -> void:
	for p in [["C:stage", 0.0, -38.0], ["P1", 0.0, -30.0], ["C:dining", 0.0, -22.0], ["PB", -9.5, -38.0], ["C:backstage", -18.0, -38.0], ["BW", -15.0, -30.0], ["W26", -15.0, -26.0],
			["W22", -15.0, -22.0], ["DWc", -9.5, -22.0], ["C:westhall", -15.0, -10.0], ["W0", -15.0, 0.0], ["HLW", -9.5, 0.0], ["D:doorL", -4.9, 0.0], ["WC", -15.0, 6.0], ["C:closet", -15.0, 11.0],
			["DEc", 9.5, -22.0], ["E22", 15.0, -22.0], ["E26", 15.0, -26.0], ["C:easthall", 15.0, -10.0], ["E0", 15.0, 0.0], ["HLE", 9.5, 0.0], ["D:doorR", 4.9, 0.0], ["EC", 15.0, 6.0],
			["C:corner", 15.0, 11.0], ["K1", 0.0, -14.0], ["C:kitchen", 0.0, -9.0]]:
		_add(String(p[0]), float(p[1]), float(p[2]))
	_chain(["C:stage", "P1", "C:dining"])
	_chain(["C:stage", "PB", "C:backstage"])
	_chain(["C:backstage", "BW", "W26", "W22", "C:westhall", "W0", "HLW", "D:doorL"])
	_chain(["C:dining", "DWc", "W22"])
	_chain(["C:westhall", "WC", "C:closet"])
	_chain(["C:dining", "DEc", "E22", "E26"])
	_chain(["E22", "C:easthall", "E0", "HLE", "D:doorR"])
	_chain(["C:easthall", "EC", "C:corner"])
	_chain(["C:dining", "K1", "C:kitchen"])


func key_for(room: String) -> String:
	return "D:%s" % room if room.begins_with("door") else "C:%s" % room


func route(from_key: String, to_key: String) -> Array:
	var out := []
	if not _ids.has(from_key) or not _ids.has(to_key):
		return out
	for id in astar.get_id_path(int(_ids[from_key]), int(_ids[to_key])):
		var key := String(_keys[id])
		out.append({"p": points[key], "jump": false, "key": key})
	return out


## The walk from where a hunter stands now to a sim room (or a door).
func legs_from(pos: Vector3, to_room: String) -> Array:
	var start := int(astar.get_closest_point(pos))
	if start < 0:
		return []
	return route(String(_keys[start]), key_for(to_room))
