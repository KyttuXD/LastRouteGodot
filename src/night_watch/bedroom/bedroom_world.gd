class_name BedroomWorld
extends Node3D

## Bedtime's room: a 5 x 5 m blocky bedroom seen from the pillow. The bed is against the south wall (the player lies in it, looking north), the closet
## is in the west wall (its door is held shut with A), the hall doorway is in the east wall with a long hall behind it (D puts a light down it), and
## the foot of the bed is the floor Haelith creeps across (F lights it). Built from shaded cubes (NightWatchArt). The only real lights are the two
## flashlight spots (off until held) and a faint window and hall glow, so the room is dark and the lights decide what you see.

const A := preload("res://src/night_watch/night_watch_art.gd")
const HALF := 2.5
const HEIGHT := 2.8
const EYE := Vector3(0.0, 0.95, 1.9)
## The hall runs east from the doorway; Javelle comes up it.
const DOORWAY := Vector3(HALF + 0.1, 0.0, -0.9)
const HALL_FAR := Vector3(HALF + 7.6, 0.0, -0.9)
const HALL_MID := Vector3(HALF + 4.4, 0.0, -0.9)
const HALL_NEAR := Vector3(HALF + 0.9, 0.0, -0.9)
## Haelith's way across the floor: from the dark north-west corner to the foot of the bed.
const CREEP_FROM := Vector3(-1.7, 0.0, -2.0)
const CREEP_TO := Vector3(0.15, 0.0, 0.75)
const CLOSET_Z := -0.9

var props := {}
var closet_pivot: Node3D
var hall_light: SpotLight3D
var bed_light: SpotLight3D
var moon: OmniLight3D
var hall_glow: OmniLight3D
var closet_ajar := -0.22   # radians the door stands open while nobody holds it


func _ready() -> void:
	if props.is_empty():
		build()


func _c(parent: Node3D, size: Vector3, pos: Vector3, node_name: String, opts := {}) -> MeshInstance3D:
	var o := opts.duplicate()
	o["name"] = node_name
	return A.box(parent, size, pos, o)


func _prop(prop_name: String, pos := Vector3.ZERO) -> Node3D:
	var node := A.prop(self, prop_name, pos)
	props[prop_name] = node
	return node


func build() -> void:
	_shell()
	_bed()
	_closet()
	_hall()
	_furniture()
	_decor()
	_lights()
	set_light("")
	set_closet_held(false)


func _shell() -> void:
	var shell := _prop("Shell")
	var tint := Color(0.85, 0.8, 1.15)
	_c(shell, Vector3(HALF * 2 + 0.4, 0.2, HALF * 2 + 0.4), Vector3(0, -0.1, 0), "Floor", {"solid": true, "kind": "wood", "tint": Color(0.8, 0.7, 0.65)})
	_c(shell, Vector3(HALF * 2 + 0.4, 0.2, HALF * 2 + 0.4), Vector3(0, HEIGHT + 0.1, 0), "Ceiling", {"tint": Color(0.5, 0.5, 0.6)})
	_c(shell, Vector3(HALF * 2 + 0.4, HEIGHT, 0.2), Vector3(0, HEIGHT * 0.5, -HALF - 0.1), "WallNorth", {"solid": true, "tint": tint})
	_c(shell, Vector3(HALF * 2 + 0.4, HEIGHT, 0.2), Vector3(0, HEIGHT * 0.5, HALF + 0.1), "WallSouth", {"solid": true, "tint": tint})
	# the west wall holds the closet recess; the east wall has the hall doorway
	var piece := HALF - 0.55 - 0.9 + 0.0
	for side in [-1.0, 1.0]:
		var tag := "West" if side < 0.0 else "East"
		var x: float = side * (HALF + 0.1)
		var door_z := -0.9
		var gap := 1.1 if side > 0.0 else 1.2
		var a_len: float = (door_z - gap * 0.5) - (-HALF)
		var b_len: float = HALF - (door_z + gap * 0.5)
		_c(shell, Vector3(0.2, HEIGHT, a_len), Vector3(x, HEIGHT * 0.5, -HALF + a_len * 0.5), "Wall%sA" % tag, {"solid": true, "tint": tint})
		_c(shell, Vector3(0.2, HEIGHT, b_len), Vector3(x, HEIGHT * 0.5, HALF - b_len * 0.5), "Wall%sB" % tag, {"solid": true, "tint": tint})
		_c(shell, Vector3(0.2, HEIGHT - 2.2, gap), Vector3(x, 2.2 + (HEIGHT - 2.2) * 0.5, door_z), "Wall%sTop" % tag, {"tint": tint})
	for z in [-HALF + 0.04, HALF - 0.04]:
		_c(shell, Vector3(HALF * 2, 0.2, 0.08), Vector3(0, 0.1, z), "Baseboard", {"tint": Color(0.7, 0.7, 0.75)})
	_c(shell, Vector3(HALF * 2, 0.1, 0.08), Vector3(0, HEIGHT - 0.05, -HALF + 0.04), "CrownTrim", {"tint": Color(0.8, 0.8, 0.85)})
	var rug := _prop("Rug", Vector3(0.0, 0.0, -0.6))
	_c(rug, Vector3(2.6, 0.03, 2.0), Vector3.ZERO, "RugMat", {"kind": "fabric", "tint": Color(0.9, 0.6, 0.7), "ao": 1.0})
	_c(rug, Vector3(2.7, 0.032, 0.1), Vector3(0, 0, 0.95), "RugTrim", {"kind": "label", "tint": Color(0.9, 0.9, 0.8), "ao": 1.0})
	_c(rug, Vector3(2.7, 0.032, 0.1), Vector3(0, 0, -0.95), "RugTrim", {"kind": "label", "tint": Color(0.9, 0.9, 0.8), "ao": 1.0})
	# the window (north wall) and its curtains
	var win := _prop("Window", Vector3(-0.2, 1.6, -HALF + 0.12))
	_c(win, Vector3(1.4, 1.1, 0.06), Vector3.ZERO, "WindowFrame", {"tint": Color(0.8, 0.7, 0.6)})
	_c(win, Vector3(1.2, 0.9, 0.03), Vector3(0, 0, 0.04), "WindowGlowPane", {"tint": Color(0.35, 0.45, 0.8)})
	for x in [-0.85, 0.85]:
		_c(win, Vector3(0.35, 1.5, 0.1), Vector3(x, -0.1, 0.1), "CurtainDrape", {"tint": Color(0.7, 0.55, 0.95)})


func _bed() -> void:
	var bed := _prop("Bed", Vector3(0.0, 0.0, HALF - 1.2))
	_c(bed, Vector3(1.7, 0.35, 2.3), Vector3(0, 0.3, 0), "BedFrame", {"solid": true})
	_c(bed, Vector3(1.6, 0.25, 2.15), Vector3(0, 0.6, 0), "Mattress", {"kind": "fabric", "tint": Color(0.7, 0.8, 1.2)})
	_c(bed, Vector3(1.64, 0.08, 1.2), Vector3(0, 0.74, -0.45), "BlanketTop", {"kind": "fabric", "tint": Color(0.9, 0.55, 0.7)})
	_c(bed, Vector3(1.7, 0.7, 0.1), Vector3(0, 0.75, 1.2), "Headboard", {})
	_c(bed, Vector3(1.7, 0.5, 0.1), Vector3(0, 0.55, -1.2), "Footboard", {})
	for x in [-0.4, 0.4]:
		_c(bed, Vector3(0.6, 0.14, 0.4), Vector3(x, 0.78, 0.85), "PillowCushion", {"kind": "fabric", "tint": Color(1.3, 1.3, 1.4)})


func _closet() -> void:
	var closet := _prop("Closet", Vector3(-HALF - 0.1, 0.0, CLOSET_Z))
	_c(closet, Vector3(1.0, 2.3, 1.2), Vector3(-0.6, 1.15, 0), "ClosetInside", {"tint": Color(0.3, 0.3, 0.35)})
	_c(closet, Vector3(0.15, 2.3, 0.1), Vector3(0, 1.15, -0.65), "ClosetFrame", {})
	_c(closet, Vector3(0.15, 2.3, 0.1), Vector3(0, 1.15, 0.65), "ClosetFrame", {})
	_c(closet, Vector3(0.15, 0.1, 1.4), Vector3(0, 2.3, 0), "ClosetFrame", {})
	_c(closet, Vector3(0.9, 0.5, 0.9), Vector3(-0.35, 0.25, 0.0), "ClothesBox", {"tint": Color(0.7, 0.7, 0.8)})
	closet_pivot = Node3D.new()
	closet_pivot.name = "ClosetDoorPivot"
	closet_pivot.position = Vector3(0.05, 0.0, 0.62)
	closet.add_child(closet_pivot)
	_c(closet_pivot, Vector3(0.08, 2.2, 1.2), Vector3(0, 1.1, -0.6), "ClosetDoorSlab", {"kind": "wood", "tint": Color(1.0, 0.85, 0.75)})
	_c(closet_pivot, Vector3(0.1, 0.12, 0.08), Vector3(0.07, 1.1, -1.05), "ClosetDoorHandle", {"kind": "metal"})


func _hall() -> void:
	var hall := _prop("Hall")
	var hx: float = HALF + 4.0
	_c(hall, Vector3(8.2, 0.2, 1.8), Vector3(hx + 0.1, -0.1, -0.9), "HallFloor", {"solid": true, "tint": Color(0.7, 0.65, 0.7)})
	_c(hall, Vector3(8.2, 0.2, 1.8), Vector3(hx + 0.1, HEIGHT + 0.1, -0.9), "HallCeiling", {"tint": Color(0.5, 0.5, 0.55)})
	_c(hall, Vector3(8.2, HEIGHT, 0.2), Vector3(hx + 0.1, HEIGHT * 0.5, -1.9), "HallWallNorth", {"solid": true, "tint": Color(0.8, 0.75, 0.95)})
	_c(hall, Vector3(8.2, HEIGHT, 0.2), Vector3(hx + 0.1, HEIGHT * 0.5, 0.1), "HallWallSouth", {"solid": true, "tint": Color(0.8, 0.75, 0.95)})
	_c(hall, Vector3(0.2, HEIGHT, 1.8), Vector3(HALF + 8.3, HEIGHT * 0.5, -0.9), "HallEndWall", {"solid": true, "tint": Color(0.6, 0.6, 0.7)})
	_c(hall, Vector3(0.1, 2.0, 0.9), Vector3(HALF + 8.18, 1.0, -0.9), "HallEndDoor", {"kind": "wood"})
	_c(hall, Vector3(7.6, 0.03, 0.7), Vector3(hx, 0.02, -0.9), "HallRunner", {"kind": "fabric", "tint": Color(0.7, 0.5, 0.9), "ao": 1.0})
	for i in 3:
		_c(hall, Vector3(0.06, 0.8, 0.5), Vector3(HALF + 1.6 + i * 2.2, 1.7, -1.78), "HallFrame", {"tint": Color(0.9, 0.8, 0.7)})
	_c(hall, Vector3(0.2, 0.2, 0.2), Vector3(HALF + 6.0, 0.1, -1.6), "HallBox", {})


func _furniture() -> void:
	var table := _prop("Nightstand", Vector3(1.3, 0.0, HALF - 0.4))
	_c(table, Vector3(0.5, 0.55, 0.45), Vector3(0, 0.275, 0), "NightstandBox", {"solid": true})
	_c(table, Vector3(0.18, 0.04, 0.18), Vector3(0, 0.57, 0), "LampBase", {})
	_c(table, Vector3(0.22, 0.2, 0.22), Vector3(0, 0.7, 0), "NightLampHood", {"kind": "fabric", "tint": Color(1.1, 1.0, 0.8)})
	var shelf := _prop("ToyShelf", Vector3(-1.2, 0.0, -HALF + 0.3))
	_c(shelf, Vector3(1.4, 1.2, 0.35), Vector3(0, 0.6, 0), "ShelfBody", {"solid": true})
	for i in 4:
		_c(shelf, Vector3(0.25, 0.25, 0.25), Vector3(-0.5 + i * 0.33, 1.32, 0), "ToyCube", {"kind": ["red", "green", "light", "glass"][i], "tint": Color(0.8, 0.8, 0.9)})
	var chair := _prop("DeskChair", Vector3(1.6, 0.0, -1.8))
	_c(chair, Vector3(0.45, 0.08, 0.45), Vector3(0, 0.45, 0), "ChairSeat", {})
	_c(chair, Vector3(0.45, 0.5, 0.08), Vector3(0, 0.75, -0.2), "ChairBack", {})
	for x in [-0.18, 0.18]:
		for z in [-0.18, 0.18]:
			_c(chair, Vector3(0.06, 0.45, 0.06), Vector3(x, 0.225, z), "ChairLeg", {})


func _decor() -> void:
	# a dresser, a bookcase, posters, a toy box, a ceiling lamp and clutter, so the dark has things in it
	var dresser := _prop("Dresser", Vector3(-1.9, 0.0, 1.0))
	_c(dresser, Vector3(0.5, 0.9, 1.2), Vector3(0, 0.45, 0), "DresserBody", {"solid": true})
	for i in 3:
		_c(dresser, Vector3(0.04, 0.22, 1.0), Vector3(0.26, 0.2 + i * 0.28, 0), "DresserDrawer", {"tint": Color(1.1, 1.05, 1.0)})
		_c(dresser, Vector3(0.05, 0.04, 0.2), Vector3(0.29, 0.22 + i * 0.28, 0), "DresserHandle", {"kind": "metal"})
	_c(dresser, Vector3(0.3, 0.3, 0.3), Vector3(0, 1.05, 0.2), "DresserBox", {"tint": Color(0.9, 0.8, 1.1)})
	var books := _prop("Bookcase", Vector3(0.9, 0.0, -HALF + 0.3))
	_c(books, Vector3(0.9, 1.9, 0.35), Vector3(0, 0.95, 0), "BookcaseBody", {"solid": true})
	for y in [0.35, 0.8, 1.25, 1.7]:
		_c(books, Vector3(0.84, 0.04, 0.38), Vector3(0, y, 0.01), "BookcaseShelf", {})
		for i in 4:
			_c(books, Vector3(0.1, 0.3 + (i % 2) * 0.05, 0.24), Vector3(-0.3 + i * 0.18, y + 0.19, 0.0), "BookSpine", {"kind": ["red", "green", "fabric", "label"][i], "tint": Color(0.8, 0.8, 0.9)})
	for i in 3:
		var poster := _prop("Poster%d" % i, Vector3(-HALF + 0.08 if i < 1 else 1.4 + (i - 1) * 0.8, 1.7, -0.2 if i < 1 else -HALF + 0.1))
		_c(poster, Vector3(0.04 if i < 1 else 0.5, 0.7, 0.5 if i < 1 else 0.04), Vector3.ZERO, "PosterPage", {"kind": "fabric", "tint": Color(1.0 + 0.2 * i, 0.8, 1.3 - 0.2 * i)})
	var toybox := _prop("ToyBox", Vector3(-2.0, 0.0, 1.9))
	_c(toybox, Vector3(0.7, 0.45, 0.45), Vector3(0, 0.225, 0), "ToyBoxBody", {})
	_c(toybox, Vector3(0.72, 0.06, 0.47), Vector3(0, 0.48, 0), "ToyBoxLid", {"tint": Color(1.2, 0.9, 0.9)})
	_c(toybox, Vector3(0.2, 0.2, 0.2), Vector3(0.1, 0.65, 0.0), "ToyBlock", {"kind": "red"})
	var lamp := _prop("CeilingLamp", Vector3(0.0, HEIGHT - 0.15, -0.4))
	_c(lamp, Vector3(0.04, 0.3, 0.04), Vector3(0, 0.1, 0), "CeilingRod", {"kind": "metal"})
	_c(lamp, Vector3(0.5, 0.2, 0.5), Vector3(0, -0.1, 0), "CeilingShade", {"kind": "fabric", "tint": Color(1.1, 1.0, 0.9)})
	var clutter := _prop("Clutter", Vector3(0.6, 0.0, 0.2))
	_c(clutter, Vector3(0.3, 0.12, 0.2), Vector3(0, 0.06, 0), "ClutterSock", {"kind": "fabric", "tint": Color(1.2, 0.9, 1.1)})
	_c(clutter, Vector3(0.25, 0.08, 0.3), Vector3(0.5, 0.04, 0.4), "ClutterShoe", {"kind": "plastic"})
	_c(clutter, Vector3(0.18, 0.18, 0.18), Vector3(-0.4, 0.09, -0.3), "ClutterBall", {"kind": "red"})


func _lights() -> void:
	moon = OmniLight3D.new()
	moon.name = "WindowGlow"
	moon.light_color = Color(0.45, 0.55, 1.0)
	moon.light_energy = 0.28
	moon.omni_range = 6.0
	moon.position = Vector3(-0.2, 2.0, -HALF + 0.8)
	add_child(moon)
	hall_glow = OmniLight3D.new()
	hall_glow.name = "HallGlow"
	hall_glow.light_color = Color(0.55, 0.5, 0.9)
	hall_glow.light_energy = 0.1
	hall_glow.omni_range = 5.0
	hall_glow.position = Vector3(HALF + 6.5, 2.4, -0.9)
	add_child(hall_glow)
	hall_light = SpotLight3D.new()
	hall_light.name = "HallLight"
	hall_light.light_color = Color(1.0, 0.95, 0.82)
	hall_light.light_energy = 6.0
	hall_light.spot_range = 12.0
	hall_light.spot_angle = 18.0
	hall_light.shadow_enabled = false
	add_child(hall_light)
	hall_light.transform = Transform3D(Basis.IDENTITY, EYE + Vector3(0.25, 0.1, 0.0)).looking_at(Vector3(HALF + 5.0, 1.0, -0.9), Vector3.UP)
	bed_light = SpotLight3D.new()
	bed_light.name = "BedLight"
	bed_light.light_color = Color(1.0, 0.95, 0.82)
	bed_light.light_energy = 5.0
	bed_light.spot_range = 8.0
	bed_light.spot_angle = 38.0
	bed_light.shadow_enabled = false
	add_child(bed_light)
	bed_light.transform = Transform3D(Basis.IDENTITY, EYE + Vector3(-0.25, 0.1, 0.0)).looking_at(Vector3(-0.3, 0.2, -0.6), Vector3.UP)


## "hall", "bed" or "" (dark): which flashlight is on.
func set_light(kind: String) -> void:
	hall_light.visible = kind == "hall"
	bed_light.visible = kind == "bed"


func set_closet_held(held: bool) -> void:
	closet_pivot.rotation.y = 0.0 if held else closet_ajar


func open_closet_wide() -> void:
	closet_pivot.rotation.y = -1.3


## Where Haelith stands when she is p percent of the way to you.
func creep_position(p: float) -> Vector3:
	return CREEP_FROM.lerp(CREEP_TO, clampf(p / 100.0, 0.0, 1.0))
