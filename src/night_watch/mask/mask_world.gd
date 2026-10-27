class_name MaskWorld
extends Node3D

## Masked Hours' 3D world, laid out like a FNAF 2 floor plan (not Classic's corridor-and-two-doors building). The player's small office has NO doors: one wide opening onto
## the central MAIN HALL (CAM 8), which runs 15 m straight ahead (north) into the open-plan show floor. On the show floor: the GAME AREA (CAM 4, the junction, arcade cabinets,
## party tables, balloons), the SHOW STAGE (CAM 3, curtains, spotlights, three performers), the PRIZE CORNER (CAM 1, the prize counter and the big music box) to the west and
## the PARTS / SERVICE room (CAM 2) to the east, all open to the floor. Four PARTY ROOMS (alcoves with a party table, balloons and streamers) open off the main hall, two on each
## side. A LEFT HALL and a RIGHT HALL run down the outer sides from the prize corner and the service room to the VENT HUB (CAM 5, behind the office), from which two dark AIR VENT
## ducts (CAM 6 left, CAM 7 right) run to the office's two side vents. Every hunter route is a real walk over a waypoint graph (AStar3D) through these spaces; nothing jumps.
## The room ids are the 2D game's (music, costume, gallery, ballroom, crawl, ductL, ductR, hall), so the rules and the golden shifts are untouched; only the names and the places
## are new. Coordinates: the office is at the origin, +z is south (behind the player), the main hall runs along -z.

const A := preload("res://src/night_watch/night_watch_art.gd")
const HALL_NEAR := 3.3        # distance down the hall (from the office origin) of the last step before the opening
const HALL_FAR := 15.0        # the hall's far end where the hall walker comes in
const RUSH_DOOR := 2.6        # where Umbriel stops
const OFFICE_WALKER := Vector3(0.0, 0.0, -1.25)   # where the hall walker stands once she is in the office (just beyond the desk)
const VENT_STAND := {"L": Vector3(-1.75, 0.0, 0.55), "R": Vector3(1.75, 0.0, 0.55)}
const H := 3.2
const THICK := 0.2

const CENTRES := {
	"ballroom": Vector3(0, 0, -24), "music": Vector3(-14.5, 0, -25), "costume": Vector3(14.5, 0, -25), "gallery": Vector3(0, 0, -34),
	"crawl": Vector3(0, 0, 6.8), "ductL": Vector3(-5.2, 0, 0.6), "ductR": Vector3(5.2, 0, 0.6),
}
## The feed cameras: [mount, target] in world space (the hall's is over the office opening).
const MOUNTS := {
	"music": [Vector3(-11.6, 2.8, -20.2), Vector3(-15.5, 0.8, -26.5)],
	"costume": [Vector3(11.6, 2.8, -20.2), Vector3(15.5, 0.8, -26.5)],
	"gallery": [Vector3(7.5, 2.9, -28.5), Vector3(0, 1.1, -36.0)],
	"ballroom": [Vector3(10.0, 3.1, -31.0), Vector3(-1.0, 0.8, -21.5)],
	"crawl": [Vector3(11.5, 2.8, 4.2), Vector3(0, 0.7, 7.5)],
	"ductL": [Vector3(-8.1, 1.4, 0.6), Vector3(-3.0, 0.7, 0.6)],
	"ductR": [Vector3(8.1, 1.4, 0.6), Vector3(3.0, 0.7, 0.6)],
	"hall": [Vector3(0, 2.6, -1.9), Vector3(0, 1.0, -14.0)],
}
const BALLOON_TINTS := [Color(1.9, 0.5, 0.5), Color(0.6, 1.0, 1.9), Color(1.9, 1.6, 0.4), Color(0.7, 1.8, 0.7), Color(1.8, 0.7, 1.7)]

var astar := AStar3D.new()
var points := {}
var _ids := {}
var _keys := {}
var rooms := {}          # camera room id -> Node3D at its centre (for the validator and the scene)
var wall_boxes := []     # [{rect: Rect2 on the XZ plane (world), name}] for the path validator
var glints := {}         # duct room -> Node3D (eyeshine)
var duct_lights := {}    # duct room -> OmniLight3D
var office: Node3D
var box_gauge: MeshInstance3D
var _n := 0


func _ready() -> void:
	if rooms.is_empty():
		build()


func _b(parent: Node3D, size: Vector3, pos: Vector3, node_name: String, opts := {}) -> MeshInstance3D:
	var o: Dictionary = opts.duplicate()
	o["name"] = node_name
	return A.box(parent, size, pos, o)


## A wall along x (z fixed) or along z (x fixed) from a to b, with optional gaps [[from, to], ...] along its length (doorless openings), recorded for the path validator.
func _wall(parent: Node3D, along_x: bool, fixed: float, a: float, b: float, gaps: Array, tint: Color, node_name := "WallShow", height := H) -> void:
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
		var mid := (s + e) * 0.5
		var length := e - s
		var size := Vector3(length, height, THICK) if along_x else Vector3(THICK, height, length)
		var pos := Vector3(mid, height * 0.5, fixed) if along_x else Vector3(fixed, height * 0.5, mid)
		_b(parent, size, pos, node_name, {"tint": tint})
		var rect := Rect2(Vector2(s, fixed - THICK * 0.5), Vector2(length, THICK)) if along_x else Rect2(Vector2(fixed - THICK * 0.5, s), Vector2(THICK, length))
		wall_boxes.append({"name": node_name, "rect": rect})


func _floor(parent: Node3D, x0: float, x1: float, z0: float, z1: float, tint: Color, node_name := "FloorShow") -> void:
	_b(parent, Vector3(x1 - x0, 0.2, z1 - z0), Vector3((x0 + x1) * 0.5, -0.1, (z0 + z1) * 0.5), node_name, {"tint": tint})


func _ceiling(parent: Node3D, x0: float, x1: float, z0: float, z1: float, tint: Color, height := H) -> void:
	_b(parent, Vector3(x1 - x0, 0.2, z1 - z0), Vector3((x0 + x1) * 0.5, height + 0.1, (z0 + z1) * 0.5), "CeilingShow", {"tint": tint})


func build() -> void:
	var root := A.prop(self, "Wing")
	_build_shell(root)
	_build_game_area(root)
	_build_stage(root)
	_build_prize_corner(root)
	_build_parts_room(root)
	_build_hall_and_party_rooms(root)
	_build_vent_hub(root)
	_build_paths()
	for id in CENTRES:
		var marker := Node3D.new()
		marker.name = "Room_%s" % id
		marker.position = CENTRES[id]
		add_child(marker)
		rooms[id] = marker


# --- the shell: the show floor, the halls, the hub -------------------------------------------------------------------------------------

func _build_shell(root: Node3D) -> void:
	var s := A.prop(root, "Shell")
	var wallc := Color(1.5, 1.2, 1.6)
	_floor(s, -19.0, 19.0, -40.0, -17.0, Color(1.2, 1.1, 1.4))
	_ceiling(s, -19.0, 19.0, -40.0, -17.0, Color(0.9, 0.8, 1.1))
	# the show floor's perimeter: north, west and east walls; the south wall (z -17) has the main hall's mouth and the two outer halls' mouths
	_wall(s, true, -40.0, -19.0, 19.0, [], wallc)
	_wall(s, false, -19.0, -40.0, -17.0, [], wallc)
	_wall(s, false, 19.0, -40.0, -17.0, [], wallc)
	_wall(s, true, -17.0, -19.0, 19.0, [[-13.7, -11.3], [-1.9, 1.9], [11.3, 13.7]], wallc)
	# the prize corner and the parts room are alcoves open to the show floor: a short pier at each corner marks them off
	for x in [-11.0, 11.0]:
		_wall(s, false, x, -31.0, -28.0, [], wallc, "PierShow")
		_wall(s, false, x, -21.0, -19.0, [], wallc, "PierShow")
	# the hall (x +/-1.9, z -17 to -1.8) with two party-room arches on each side
	var gaps := [[-14.6, -11.0], [-9.0, -5.4]]
	var hall := A.prop(root, "MainHall")
	_floor(hall, -1.9, 1.9, -17.0, -1.8, Color(1.1, 1.05, 1.3), "FloorHall")
	_ceiling(hall, -1.9, 1.9, -17.0, -1.8, Color(0.9, 0.8, 1.1))
	_wall(hall, false, -1.9, -17.0, -1.8, gaps, wallc, "WallHall")
	_wall(hall, false, 1.9, -17.0, -1.8, gaps, wallc, "WallHall")
	for i in 5:   # a runner down the middle and the hall's pennants
		_b(hall, Vector3(1.2, 0.012, 2.4), Vector3(0, 0.006, -3.0 - i * 2.9), "RunnerHall", {"kind": "fabric", "tint": Color(1.8, 0.5, 0.6)})
	for i in 6:
		_b(hall, Vector3(3.6, 0.08, 0.1), Vector3(0, 2.7, -3.0 - i * 2.4), "StreamerHall", {"kind": "fabric", "tint": BALLOON_TINTS[i % 5]})



func _build_game_area(root: Node3D) -> void:
	var p := A.prop(root, "GameArea", CENTRES["ballroom"])
	# a checkerboard of three-metre tiles
	for ix in 7:
		for iz in 4:
			if (ix + iz) % 2 == 0:
				_b(p, Vector3(3.0, 0.012, 3.0), Vector3(-9.0 + ix * 3.0, 0.006, -7.5 + iz * 3.0 + 1.5), "FloorTile", {"kind": "floor", "tint": Color(1.8, 1.4, 2.2)})
	# arcade cabinets along the south wall, party tables in two rows (the lanes down x 0 and along z -24 stay clear), balloons and streamers overhead
	for i in 4:
		var side := -1.0 if i < 2 else 1.0
		var x := side * (4.5 + (i % 2) * 2.0)
		_arcade(p, Vector3(x, 0, 5.2), BALLOON_TINTS[i])
	for pos in [Vector3(-5.0, 0, -4.5), Vector3(5.0, 0, -4.5), Vector3(-5.0, 0, 3.5), Vector3(5.0, 0, 3.5)]:
		_party_table(p, pos, BALLOON_TINTS[(int(pos.x) + 7) % 5])
	_balloons(p, Vector3(-8.0, 0, -6.0), 4)
	_balloons(p, Vector3(8.0, 0, -6.0), 4)
	for i in 5:
		_b(p, Vector3(22.0, 0.08, 0.1), Vector3(0, 3.0 - (i % 2) * 0.15, -6.5 + i * 3.2), "StreamerGame", {"kind": "fabric", "tint": BALLOON_TINTS[i]})
	for x in [-9.5, 9.5]:   # pillars
		_b(p, Vector3(0.5, H, 0.5), Vector3(x, H * 0.5, 0), "PillarGame", {"kind": "concrete", "tint": Color(1.4, 1.2, 1.6), "solid": true})
	_b(p, Vector3(3.0, 0.5, 0.3), Vector3(0, 2.6, 6.8), "SignGame", {"kind": "label", "tint": Color(1.6, 1.0, 0.5)})


func _arcade(parent: Node3D, pos: Vector3, tint: Color) -> void:
	var c := A.prop(parent, "Arcade", pos)
	_b(c, Vector3(0.9, 1.9, 0.8), Vector3(0, 0.95, 0), "ArcadeBody", {"kind": "plastic", "tint": tint})
	_b(c, Vector3(0.7, 0.5, 0.04), Vector3(0, 1.35, 0.42), "ScreenArcade", {})
	_b(c, Vector3(0.9, 0.2, 0.3), Vector3(0, 0.95, 0.45), "ArcadeDeck", {"kind": "plastic", "tint": Color(0.7, 0.7, 0.8)})
	_b(c, Vector3(0.9, 0.2, 0.1), Vector3(0, 1.85, 0.4), "SignArcade", {"kind": "label", "tint": Color(1.4, 1.2, 0.6)})


func _party_table(parent: Node3D, pos: Vector3, tint: Color) -> void:
	var t := A.prop(parent, "PartyTable", pos)
	_b(t, Vector3(1.8, 0.08, 1.0), Vector3(0, 0.78, 0), "TableTop", {"kind": "fabric", "tint": tint})
	for sx in [-0.8, 0.8]:
		for sz in [-0.4, 0.4]:
			_b(t, Vector3(0.08, 0.76, 0.08), Vector3(sx, 0.38, sz), "TableLeg", {"kind": "metal"})
	_b(t, Vector3(0.32, 0.22, 0.32), Vector3(0, 0.93, 0), "CakeTable", {"kind": "fabric", "tint": Color(1.8, 1.5, 1.6)})
	for hx in [-0.6, 0.6]:
		_b(t, Vector3(0.16, 0.24, 0.16), Vector3(hx, 0.94, 0.25), "HatTable", {"kind": "fabric", "tint": BALLOON_TINTS[(int(hx * 10) + 8) % 5]})
	for sx in [-0.5, 0.5]:   # four stools
		for sz in [-0.85, 0.85]:
			_b(t, Vector3(0.36, 0.45, 0.36), Vector3(sx, 0.22, sz), "StoolTable", {"kind": "plastic", "tint": Color(1.3, 0.8, 0.8)})


func _balloons(parent: Node3D, pos: Vector3, n: int) -> void:
	var g := A.prop(parent, "Balloons", pos)
	for i in n:
		var h := 2.0 + (i % 3) * 0.35
		_b(g, Vector3(0.02, h, 0.02), Vector3(-0.3 + i * 0.2, h * 0.5, 0.05 * i), "StringBalloon", {"kind": "plastic", "tint": Color(1.6, 1.6, 1.6)})
		_b(g, Vector3(0.42, 0.5, 0.42), Vector3(-0.3 + i * 0.2, h + 0.2, 0.05 * i), "BalloonCube", {"kind": "fabric", "tint": BALLOON_TINTS[i % 5]})
	_b(g, Vector3(0.3, 0.3, 0.3), Vector3(0, 0.15, 0), "WeightBalloon", {"kind": "metal"})


func _build_stage(root: Node3D) -> void:
	var p := A.prop(root, "ShowStage", CENTRES["gallery"])
	_b(p, Vector3(12.0, 0.7, 5.0), Vector3(0, 0.35, -2.0), "PlatformStage", {"kind": "wood", "tint": Color(1.5, 1.0, 0.8)})
	_b(p, Vector3(12.2, 0.08, 5.2), Vector3(0, 0.74, -2.0), "PlatformEdge", {"kind": "label", "tint": Color(1.6, 1.3, 0.7)})
	for sx in [-5.6, 5.6]:
		_b(p, Vector3(0.8, 3.0, 0.3), Vector3(sx, 1.9, -4.4), "CurtainStage", {"kind": "fabric", "tint": Color(1.9, 0.4, 0.5)})
	_b(p, Vector3(12.0, 0.5, 0.3), Vector3(0, 3.0, -4.4), "ValanceStage", {"kind": "fabric", "tint": Color(1.9, 0.4, 0.5)})
	_b(p, Vector3(5.0, 0.7, 0.1), Vector3(0, 2.4, -4.6), "SignStage", {"kind": "label", "tint": Color(1.5, 1.1, 0.5)})
	for x in [-3.5, 0.0, 3.5]:
		_b(p, Vector3(0.5, 0.25, 0.4), Vector3(x, 3.2, -1.5), "SpotStage", {"kind": "plastic"})
		_b(p, Vector3(0.3, 0.1, 0.3), Vector3(x, 3.05, -1.4), "GlowSpot", {})
	var tints := [Color(1.4, 0.9, 0.6), Color(0.7, 0.8, 1.7), Color(1.8, 1.6, 0.5)]
	for i in 3:
		_performer(p, Vector3(-3.0 + i * 3.0, 0.7, -2.4), tints[i], i)


func _performer(parent: Node3D, pos: Vector3, tint: Color, kind: int) -> void:
	var f := A.prop(parent, "Performer", pos)
	_b(f, Vector3(0.9, 1.1, 0.6), Vector3(0, 1.0, 0), "BodyPerformer", {"kind": "fabric", "tint": tint})
	_b(f, Vector3(0.7, 0.6, 0.6), Vector3(0, 1.85, 0), "HeadPerformer", {"kind": "fabric", "tint": tint})
	for ex in [-0.16, 0.16]:
		_b(f, Vector3(0.14, 0.14, 0.04), Vector3(ex, 1.9, 0.32), "EyePerformer", {"kind": "plastic", "tint": Color(1.8, 1.8, 1.8)})
	_b(f, Vector3(0.3, 0.2, 0.2), Vector3(0, 1.72, 0.38), "SnoutPerformer", {"kind": "fabric", "tint": Color(1.8, 1.5, 1.2)})
	_b(f, Vector3(0.4, 0.14, 0.1), Vector3(0, 1.42, 0.32), "BowPerformer", {"kind": "fabric", "tint": Color(1.9, 0.5, 0.6)})
	for ax in [-0.58, 0.58]:
		_b(f, Vector3(0.22, 0.9, 0.3), Vector3(ax, 0.95, 0), "ArmPerformer", {"kind": "fabric", "tint": tint})
	for lx in [-0.25, 0.25]:
		_b(f, Vector3(0.3, 0.6, 0.4), Vector3(lx, 0.3, 0), "LegPerformer", {"kind": "fabric", "tint": tint})
	if kind == 0:   # ears
		for ex in [-0.3, 0.3]:
			_b(f, Vector3(0.22, 0.22, 0.12), Vector3(ex, 2.3, 0), "EarPerformer", {"kind": "fabric", "tint": tint})
	elif kind == 1:
		for ex in [-0.2, 0.2]:
			_b(f, Vector3(0.14, 0.5, 0.1), Vector3(ex, 2.4, 0), "EarBunny", {"kind": "fabric", "tint": tint})
	else:   # a beak and a crest
		_b(f, Vector3(0.3, 0.12, 0.3), Vector3(0, 1.82, 0.5), "BeakPerformer", {"kind": "label", "tint": Color(1.6, 1.0, 0.4)})
		_b(f, Vector3(0.2, 0.2, 0.1), Vector3(0, 2.25, 0), "CrestPerformer", {"kind": "fabric", "tint": Color(1.9, 0.5, 0.5)})


func _build_prize_corner(root: Node3D) -> void:
	var p := A.prop(root, "PrizeCorner", CENTRES["music"])
	_floor(p, -3.5, 3.5, -6.0, 6.0, Color(1.7, 1.3, 1.0), "FloorPrize")
	# the prize counter along the west wall: a glass case, shelves of plush boxes, a sign
	_b(p, Vector3(1.0, 1.0, 5.0), Vector3(-2.5, 0.5, 0), "CounterPrize", {"kind": "wood", "tint": Color(1.6, 1.0, 0.8)})
	_b(p, Vector3(0.9, 0.5, 4.8), Vector3(-2.5, 1.25, 0), "CaseGlassPrize", {"kind": "glass", "tint": Color(1.2, 1.4, 1.5)})
	for i in 3:
		_b(p, Vector3(0.6, 0.05, 4.8), Vector3(-3.2, 1.4 + i * 0.55, 0), "ShelfPrize", {"kind": "wood", "tint": Color(1.4, 0.9, 0.7)})
		for j in 6:
			_b(p, Vector3(0.4, 0.4, 0.5), Vector3(-3.2, 1.65 + i * 0.55, -2.1 + j * 0.85), "PlushPrize", {"kind": "fabric", "tint": BALLOON_TINTS[(i + j) % 5]})
	_b(p, Vector3(0.1, 0.7, 4.0), Vector3(-3.4, 3.0, 0), "SignPrize", {"kind": "label", "tint": Color(1.6, 1.1, 0.5)})
	# the big music box (a gift box with a crank and a gauge) and a ring of balloons
	var box := A.prop(p, "MusicBoxBig", Vector3(0.6, 0, 0.0))
	_b(box, Vector3(1.4, 1.0, 1.2), Vector3(0, 0.5, 0), "BoxPuppet", {"kind": "fabric", "tint": Color(1.8, 0.7, 1.4)})
	_b(box, Vector3(1.5, 0.2, 1.3), Vector3(0, 1.1, 0), "LidPuppet", {"kind": "fabric", "tint": Color(1.9, 1.5, 0.5)})
	_b(box, Vector3(0.12, 0.7, 0.12), Vector3(0.85, 0.7, 0), "HandleCrank", {"kind": "metal"})
	box_gauge = _b(box, Vector3(1.0, 0.08, 0.04), Vector3(0, 1.3, 0.62), "GlowGauge", {})
	_balloons(p, Vector3(2.4, 0, -3.5), 5)
	_balloons(p, Vector3(-1.2, 0, -4.8), 4)
	_b(p, Vector3(7.0, 0.08, 0.1), Vector3(0, 3.0, -4.0), "StreamerPrize", {"kind": "fabric", "tint": BALLOON_TINTS[2]})
	_b(p, Vector3(7.0, 0.08, 0.1), Vector3(0, 3.0, 4.0), "StreamerPrize", {"kind": "fabric", "tint": BALLOON_TINTS[3]})


## The big music box's gauge on the prize corner's camera: its length is the winding left.
func set_box(percent: float) -> void:
	if box_gauge != null:
		box_gauge.scale.x = clampf(percent / 100.0, 0.02, 1.0)
		box_gauge.position.x = -0.5 * (1.0 - box_gauge.scale.x)


func _build_parts_room(root: Node3D) -> void:
	var p := A.prop(root, "PartsService", CENTRES["costume"])
	_floor(p, -3.5, 3.5, -6.0, 6.0, Color(0.9, 1.0, 1.2), "FloorParts")
	# shelving along the east wall with spare heads, a workbench, a bin of limbs, a repair chair
	for i in 3:
		_b(p, Vector3(0.6, 0.05, 5.2), Vector3(3.0, 0.5 + i * 0.7, 0), "ShelfParts", {"kind": "metal"})
		for j in 5:
			_b(p, Vector3(0.4, 0.4, 0.4), Vector3(3.0, 0.75 + i * 0.7, -2.0 + j * 1.0), "HeadParts", {"kind": "fabric", "tint": BALLOON_TINTS[(i + j) % 5] * Color(0.8, 0.8, 0.8)})
			_b(p, Vector3(0.1, 0.08, 0.04), Vector3(2.7, 0.8 + i * 0.7, -2.0 + j * 1.0), "EyeParts", {"kind": "plastic", "tint": Color(1.8, 1.8, 1.8)})
	_b(p, Vector3(2.4, 0.9, 1.0), Vector3(-0.5, 0.45, -4.2), "BenchParts", {"kind": "metal", "tint": Color(0.9, 0.9, 1.1)})
	_b(p, Vector3(1.0, 0.7, 1.0), Vector3(-1.5, 0.35, 3.8), "BinParts", {"kind": "plastic", "tint": Color(1.0, 0.7, 0.7)})
	for i in 4:
		_b(p, Vector3(0.14, 0.14, 0.9), Vector3(-1.5 + (i % 2) * 0.3, 0.8, 3.8 + (i - 1.5) * 0.1), "LimbParts", {"kind": "metal", "tint": Color(1.2, 1.2, 1.3)})
	_b(p, Vector3(0.9, 0.5, 0.1), Vector3(0.0, 2.3, -5.9), "SignParts", {"kind": "label", "tint": Color(1.5, 1.2, 0.5)})
	_balloons(p, Vector3(-2.4, 0, 0), 3)


func _build_hall_and_party_rooms(root: Node3D) -> void:
	var wallc := Color(1.5, 1.2, 1.6)
	var z_ranges := [[-14.6, -11.0], [-9.0, -5.4]]
	var n := 0
	for side in [-1.0, 1.0]:
		for zr in z_ranges:
			n += 1
			var z0: float = zr[0]
			var z1: float = zr[1]
			var room := A.prop(root, "PartyRoom%d" % n, Vector3.ZERO)
			var x_in: float = side * 1.9
			var x_out: float = side * 8.0
			_floor(room, minf(x_in, x_out), maxf(x_in, x_out), z0 - 0.4, z1 + 0.4, Color(1.6, 1.4, 1.2), "FloorParty")
			_ceiling(room, minf(x_in, x_out), maxf(x_in, x_out), z0 - 0.4, z1 + 0.4, Color(0.9, 0.8, 1.1))
			_wall(room, false, x_out, z0 - 0.4, z1 + 0.4, [], wallc, "WallParty")
			_wall(room, true, z0 - 0.4, minf(x_in, x_out), maxf(x_in, x_out), [], wallc, "WallParty")
			_wall(room, true, z1 + 0.4, minf(x_in, x_out), maxf(x_in, x_out), [], wallc, "WallParty")
			_party_table(room, Vector3(side * 5.2, 0, (z0 + z1) * 0.5), BALLOON_TINTS[n % 5])
			_balloons(room, Vector3(side * 7.3, 0, z0 + 0.2), 3)
			for i in 3:
				_b(room, Vector3(0.1, 0.08, 5.0), Vector3(side * (3.0 + i * 1.6), 3.0, (z0 + z1) * 0.5), "StreamerParty", {"kind": "fabric", "tint": BALLOON_TINTS[(n + i) % 5]})
			_b(room, Vector3(0.1, 0.5, 1.6), Vector3(side * 7.9, 2.4, (z0 + z1) * 0.5), "SignParty", {"kind": "label", "tint": Color(1.5, 1.1, 0.5)})
	# the left and right halls: dark service corridors down the outer sides to the vent hub
	for side in [-1.0, 1.0]:
		var hallw := A.prop(root, "SideHall%s" % ("L" if side < 0.0 else "R"), Vector3.ZERO)
		var x: float = side * 12.5
		_floor(hallw, x - 1.2, x + 1.2, -17.0, 3.0, Color(0.9, 0.9, 1.1), "FloorSide")
		_ceiling(hallw, x - 1.2, x + 1.2, -17.0, 3.0, Color(0.7, 0.7, 0.9))
		_wall(hallw, false, x - 1.2, -17.0, 3.0, [], wallc * Color(0.8, 0.8, 0.9), "WallSide")
		_wall(hallw, false, x + 1.2, -17.0, 3.0, [], wallc * Color(0.8, 0.8, 0.9), "WallSide")
		for i in 4:
			_b(hallw, Vector3(0.9, 0.1, 0.06), Vector3(x, 2.4, -15.0 + i * 4.6), "PosterSide", {"kind": "label", "tint": Color(1.2, 0.9, 0.5)})
			_b(hallw, Vector3(0.08, 0.6, 0.5), Vector3(x - side * 1.1, 1.5, -13.0 + i * 4.6), "PennantSide", {"kind": "fabric", "tint": BALLOON_TINTS[i]})


func _build_vent_hub(root: Node3D) -> void:
	var wallc := Color(0.9, 0.9, 1.1)
	var hub := A.prop(root, "VentHub", Vector3.ZERO)
	_floor(hub, -14.0, 14.0, 3.0, 10.0, Color(0.8, 0.8, 1.0), "FloorHub")
	_ceiling(hub, -14.0, 14.0, 3.0, 10.0, Color(0.6, 0.6, 0.8), 2.6)
	_wall(hub, true, 10.0, -14.0, 14.0, [], wallc, "WallHub", 2.6)
	_wall(hub, true, 3.0, -14.0, 14.0, [[-13.7, -11.3], [-8.9, -7.1], [7.1, 8.9], [11.3, 13.7]], wallc, "WallHub", 2.6)
	_wall(hub, false, -14.0, 3.0, 10.0, [], wallc, "WallHub", 2.6)
	_wall(hub, false, 14.0, 3.0, 10.0, [], wallc, "WallHub", 2.6)
	# pipes, grates and a few crates: the hunters' nest
	for i in 3:
		_b(hub, Vector3(26.0, 0.15, 0.15), Vector3(0, 2.3, 4.5 + i * 2.0), "PipeHub", {"kind": "metal"})
	for x in [-9.0, -3.0, 4.0, 10.0]:
		_b(hub, Vector3(1.2, 0.9, 1.2), Vector3(x, 0.45, 8.5), "CrateHub", {"kind": "wood", "tint": Color(1.1, 0.9, 0.8)})
	_b(hub, Vector3(3.0, 0.4, 0.1), Vector3(0, 2.0, 9.85), "SignHub", {"kind": "label", "tint": Color(1.4, 1.0, 0.5)})
	# the two air vent ducts: from the hub north, then east / west to the office's side vents (low, dark, a ribbed tube)
	for side in [-1.0, 1.0]:
		var id: String = "ductL" if side < 0.0 else "ductR"
		var d := A.prop(root, "Duct%s" % ("L" if side < 0.0 else "R"), Vector3.ZERO)
		var x0: float = minf(side * 2.4, side * 8.8)
		var x1: float = maxf(side * 2.4, side * 8.8)
		_b(d, Vector3(x1 - x0, 0.1, 1.6), Vector3((x0 + x1) * 0.5, 0.05, 0.6), "DuctFloor", {"kind": "metal", "tint": Color(0.7, 0.7, 0.75)})
		_b(d, Vector3(x1 - x0, 1.8, 0.1), Vector3((x0 + x1) * 0.5, 0.9, -0.2), "DuctSide", {"kind": "metal", "tint": Color(0.6, 0.6, 0.65)})
		_b(d, Vector3(x1 - x0, 1.8, 0.1), Vector3((x0 + x1) * 0.5, 0.9, 1.4), "DuctSide", {"kind": "metal", "tint": Color(0.6, 0.6, 0.65)})
		_b(d, Vector3(x1 - x0, 0.1, 1.8), Vector3((x0 + x1) * 0.5, 1.85, 0.6), "DuctTop", {"kind": "metal", "tint": Color(0.5, 0.5, 0.55)})
		_b(d, Vector3(1.6, 0.1, 2.0), Vector3(side * 8.0, 0.05, 2.2), "DuctFloor", {"kind": "metal", "tint": Color(0.7, 0.7, 0.75)})
		_b(d, Vector3(0.1, 1.8, 0.1 + 1.6), Vector3(side * 8.9, 0.9, 0.6), "DuctEnd", {"kind": "metal", "tint": Color(0.4, 0.4, 0.45)})
		for i in 5:
			_b(d, Vector3(0.08, 0.12, 1.7), Vector3(side * (3.0 + i * 1.2), 1.75, 0.6), "DuctRib", {"kind": "metal", "tint": Color(0.7, 0.7, 0.75)})
		var glint := Node3D.new()
		glint.name = "Glint"
		glint.position = Vector3(side * 5.4, 0.9, 0.6)
		d.add_child(glint)
		for gz in [0.5, 0.7]:
			_b(glint, Vector3(0.04, 0.04, 0.06), Vector3(0, 0, gz - 0.6), "GlowEye", {})
		glint.visible = false
		glints[id] = glint
		var lamp := OmniLight3D.new()
		lamp.name = "DuctLight"
		lamp.light_color = Color(1.0, 0.95, 0.8)
		lamp.light_energy = 2.2
		lamp.omni_range = 7.0
		lamp.position = Vector3(side * 7.5, 1.5, 0.6)
		lamp.visible = false
		d.add_child(lamp)
		duct_lights[id] = lamp


# --- the hall and the feeds ------------------------------------------------------------------------------------------------------------

func feed_transform(room: String) -> Transform3D:
	var m: Array = MOUNTS[room]
	var o := office.global_position if office != null else Vector3.ZERO
	return Transform3D(Basis.IDENTITY, o + (m[0] as Vector3)).looking_at(o + (m[1] as Vector3), Vector3.UP)


func camera_transform(room: String) -> Transform3D:
	return feed_transform(room)


## Where a hunter stands in a room as the feed sees her (slot 0/1/2); the hall is the main hall, the office is just beyond the desk.
func stand_at(room: String, slot: int, at := "stand") -> Vector3:
	var o := office.global_position if office != null else Vector3.ZERO
	if room == "hall":
		return o + Vector3(0.0, 0.0, -(HALL_NEAR + slot * 1.2))
	if room == "office":
		return o + OFFICE_WALKER + Vector3(slot * 0.9, 0.0, 0.0)
	var c: Vector3 = CENTRES[room]
	if room == "ductL" or room == "ductR":
		var side := -1.0 if room == "ductL" else 1.0
		var x: float = {"far": 7.2, "stand": 5.4, "near": 3.5}.get(at, 5.4)
		return o + Vector3(side * x, 0.0, 0.6)
	var offset := Vector3(0.9, 0.0, 0.6) if slot == 0 else (Vector3(-0.9, 0.0, -0.6) if slot == 1 else Vector3(0.0, 0.0, -1.6))
	if room == "gallery":
		offset += Vector3(0.0, 0.7, 3.2)   # on the stage's front edge... the performers stand behind her
	return o + c + offset


func stand_position(room: String, slot: int) -> Vector3:
	return stand_at(room, slot)


func hall_pos(step: int) -> Vector3:
	var o := office.global_position if office != null else Vector3.ZERO
	return o + Vector3(0.0, 0.0, -lerpf(HALL_FAR, HALL_NEAR, clampf(float(step) / float(MaskLogic.T["hallSteps"]), 0.0, 1.0)))


func rush_pos(progress: float) -> Vector3:
	var o := office.global_position if office != null else Vector3.ZERO
	return o + Vector3(0.0, 0.0, -lerpf(HALL_FAR, RUSH_DOOR, clampf(progress, 0.0, 1.0)))


# --- walking: the waypoint graph ---------------------------------------------------------------------------------------------------------

func _add(key: String, x: float, z: float) -> void:
	var id := astar.get_available_point_id()
	var pos := Vector3(x, 0.0, z)
	astar.add_point(id, pos)
	_ids[key] = id
	_keys[id] = key
	points[key] = pos


func _link(a: String, b: String) -> void:
	astar.connect_points(int(_ids[a]), int(_ids[b]), true)


func _build_paths() -> void:
	# the show floor: the junction, the three rooms around it, an open lane to each
	_add("C:ballroom", 0.0, -24.0)
	_add("C:music", -14.5, -25.0)
	_add("C:costume", 14.5, -25.0)
	_add("C:gallery", 0.0, -34.0)
	_add("GA_W", -9.0, -24.0)
	_add("GA_E", 9.0, -24.0)
	_add("GA_N", 0.0, -29.0)
	_add("GA_S", 0.0, -18.5)
	for pair in [["C:music", "GA_W"], ["GA_W", "C:ballroom"], ["C:costume", "GA_E"], ["GA_E", "C:ballroom"], ["C:gallery", "GA_N"], ["GA_N", "C:ballroom"], ["C:ballroom", "GA_S"]]:
		_link(pair[0], pair[1])
	# the main hall, straight into the office (a waypoint every three metres)
	var zs := [-15.0, -12.0, -9.0, -6.0, -3.3]
	var prev := "GA_S"
	for z in zs:
		var key := "H:%d" % int(-z)
		_add(key, 0.0, z)
		_link(prev, key)
		prev = key
	_add("H:in", 0.0, -1.25)
	_link(prev, "H:in")
	# the left and right halls, from the prize corner / the service room to the vent hub
	for side in [-1.0, 1.0]:
		var tag := "L" if side < 0.0 else "R"
		var room := "C:music" if side < 0.0 else "C:costume"
		_add("S%s_N" % tag, side * 12.5, -22.0)
		_add("S%s_1" % tag, side * 12.5, -14.0)
		_add("S%s_2" % tag, side * 12.5, -4.0)
		_add("S%s_3" % tag, side * 12.5, 5.0)
		_link(room, "S%s_N" % tag)
		_link("S%s_N" % tag, "S%s_1" % tag)
		_link("S%s_1" % tag, "S%s_2" % tag)
		_link("S%s_2" % tag, "S%s_3" % tag)
	# the vent hub and the two ducts
	_add("C:crawl", 0.0, 6.8)
	_add("HUB_W", -8.0, 6.2)
	_add("HUB_E", 8.0, 6.2)
	_link("C:crawl", "HUB_W")
	_link("C:crawl", "HUB_E")
	_link("HUB_W", "SL_3")
	_link("HUB_E", "SR_3")
	for side in [-1.0, 1.0]:
		var tag2 := "L" if side < 0.0 else "R"
		_add("D%s1" % tag2, side * 8.0, 3.4)
		_add("D%s2" % tag2, side * 8.0, 0.6)
		_add("C:duct%s" % tag2, side * 5.2, 0.6)
		_link("HUB_%s" % ("W" if side < 0.0 else "E"), "D%s1" % tag2)
		_link("D%s1" % tag2, "D%s2" % tag2)
		_link("D%s2" % tag2, "C:duct%s" % tag2)


func key_for(room: String) -> String:
	if room == "hall":
		return "H:15"
	if room == "office":
		return "H:in"
	return "C:%s" % room


func route(from_key: String, to_key: String) -> Array:
	var out := []
	if not _ids.has(from_key) or not _ids.has(to_key):
		return out
	for id in astar.get_id_path(int(_ids[from_key]), int(_ids[to_key])):
		var key := String(_keys[id])
		out.append({"p": points[key], "jump": false, "key": key})
	return out


## The route from where a hunter stands now to a sim room.
func legs_from(pos: Vector3, to_room: String) -> Array:
	var start := int(astar.get_closest_point(pos))
	if start < 0:
		return []
	return route(String(_keys[start]), key_for(to_room))
