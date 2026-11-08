class_name NightWatchDescentWorld
extends Node3D

## The Descent's 3D set: a service elevator car seen from inside (a blocky room, NightWatchArt cubes) with the service panel on the back
## wall between two caged windows, and the shaft outside them. A sill runs outside each window; Elise comes along the sill on her side
## (she is a walking blocky model placed by the game scene). While the car drops a floor the shaft's beams slide past. Real lights are
## the car's ceiling lamp and one dim lamp over each sill.

const A := preload("res://game/night_watch/night_watch_art.gd")
const HALF_W := 1.7
const HALF_D := 1.4
const HEIGHT := 3.6
const WINDOW_X := 1.1          # centre of each window
const WINDOW_W := 0.9
const WINDOW_BOTTOM := 0.85
const WINDOW_TOP := 3.2
const BEAM_GAP := 3.0
const RIDE_DROP := 3.0         # how far the shaft slides past in one ride (one beam gap)
const SILL_FAR := -5.6         # where Elise starts, far down the sill
const SILL_NEAR := -1.95       # at the glass

var camera: Camera3D
var lamp: OmniLight3D
var sill_lights := {}
var dress: Node3D              # the shaft's beams and rails, slid past while the car drops
var panel_plate: MeshInstance3D
var props := {}


func _ready() -> void:
	if camera == null:
		build()


func _prop(prop_name: String) -> Node3D:
	var node := A.prop(self, prop_name)
	props[prop_name] = node
	return node


func _c(parent: Node3D, size: Vector3, pos: Vector3, node_name: String, opts := {}) -> MeshInstance3D:
	var o := opts.duplicate()
	o["name"] = node_name
	return A.box(parent, size, pos, o)


func build() -> void:
	_build_car()
	_build_windows()
	_build_shaft()
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.position = Vector3(0.0, 1.5, 1.1)
	camera.fov = 62.0
	camera.current = true
	add_child(camera)
	camera.rotation_degrees = Vector3(-3.0, 0.0, 0.0)
	lamp = OmniLight3D.new()
	lamp.name = "CarLamp"
	lamp.position = Vector3(0.0, HEIGHT - 0.25, 0.1)
	lamp.light_color = Color(1.0, 0.86, 0.62)
	lamp.light_energy = 1.5
	lamp.omni_range = 5.0
	add_child(lamp)
	for side in ["L", "R"]:
		var sl := OmniLight3D.new()
		sl.name = "SillLight" + side
		sl.position = Vector3((-1.0 if side == "L" else 1.0) * WINDOW_X, 2.3, -2.9)
		sl.light_color = Color(0.45, 0.55, 0.85)
		sl.light_energy = 0.8
		sl.omni_range = 5.0
		add_child(sl)
		sill_lights[side] = sl


func _build_car() -> void:
	var shell := _prop("Car")
	_c(shell, Vector3(HALF_W * 2.0 + 0.4, 0.2, HALF_D * 2.0 + 0.4), Vector3(0, -0.1, 0), "Floor", {"solid": true, "tint": Color(1.0, 1.0, 1.0)})
	_c(shell, Vector3(HALF_W * 2.0 + 0.4, 0.2, HALF_D * 2.0 + 0.4), Vector3(0, HEIGHT + 0.1, 0), "Ceiling", {"tint": Color(0.7, 0.7, 0.75)})
	for x in [-HALF_W - 0.1, HALF_W + 0.1]:
		_c(shell, Vector3(0.2, HEIGHT, HALF_D * 2.0), Vector3(x, HEIGHT * 0.5, 0), "WallSide", {"solid": true, "tint": Color(0.8, 0.8, 0.85)})
	_c(shell, Vector3(HALF_W * 2.0 + 0.4, HEIGHT, 0.2), Vector3(0, HEIGHT * 0.5, HALF_D + 0.1), "WallFront", {"solid": true, "tint": Color(0.7, 0.7, 0.75)})
	# the back wall, with a window opening each side of the service panel
	_c(shell, Vector3(HALF_W * 2.0, WINDOW_BOTTOM, 0.2), Vector3(0, WINDOW_BOTTOM * 0.5, -HALF_D - 0.1), "WallBackLow", {"solid": true, "tint": Color(0.85, 0.85, 0.9)})
	_c(shell, Vector3(HALF_W * 2.0, HEIGHT - WINDOW_TOP, 0.2), Vector3(0, WINDOW_TOP + (HEIGHT - WINDOW_TOP) * 0.5, -HALF_D - 0.1), "WallBackHigh", {"solid": true, "tint": Color(0.85, 0.85, 0.9)})
	var mid_h := WINDOW_TOP - WINDOW_BOTTOM
	var mid_y := WINDOW_BOTTOM + mid_h * 0.5
	var edge_w := HALF_W - (WINDOW_X + WINDOW_W * 0.5)
	var centre_w := (WINDOW_X - WINDOW_W * 0.5) * 2.0
	_c(shell, Vector3(centre_w, mid_h, 0.2), Vector3(0, mid_y, -HALF_D - 0.1), "WallBackPanel", {"solid": true, "tint": Color(0.85, 0.85, 0.9)})
	for s in [-1.0, 1.0]:
		_c(shell, Vector3(edge_w, mid_h, 0.2), Vector3(s * (HALF_W - edge_w * 0.5), mid_y, -HALF_D - 0.1), "WallBackEdge", {"solid": true, "tint": Color(0.85, 0.85, 0.9)})
	# the service panel plate on the wall between the windows (the repair screen is drawn over it)
	panel_plate = _c(shell, Vector3(centre_w - 0.1, mid_h - 0.1, 0.05), Vector3(0, mid_y, -HALF_D + 0.03), "PanelPlate", {"kind": "metal", "tint": Color(0.5, 0.52, 0.58)})
	for z in [-HALF_D + 0.04, HALF_D - 0.04]:
		_c(shell, Vector3(HALF_W * 2.0, 0.2, 0.08), Vector3(0, 0.1, z), "Baseboard", {"tint": Color(0.7, 0.7, 0.75)})
		_c(shell, Vector3(HALF_W * 2.0, 0.12, 0.08), Vector3(0, HEIGHT - 0.06, z), "CrownTrim", {"tint": Color(0.8, 0.8, 0.85)})
	# a hand rail along the side walls, floor stripes, a ceiling fixture
	for x in [-HALF_W + 0.05, HALF_W - 0.05]:
		_c(shell, Vector3(0.06, 0.06, HALF_D * 2.0 - 0.3), Vector3(x, 1.0, 0), "HandRail", {"kind": "metal"})
	_c(shell, Vector3(2.4, 0.01, 0.12), Vector3(0, 0.005, 0.3), "FloorStripe", {"kind": "label", "tint": Color(0.8, 0.8, 0.8)})
	_c(shell, Vector3(1.1, 0.08, 0.5), Vector3(0, HEIGHT - 0.04, 0.1), "CeilingFixture", {"kind": "plastic"})
	_c(shell, Vector3(0.9, 0.02, 0.3), Vector3(0, HEIGHT - 0.1, 0.1), "CeilingLens", {"kind": "glass", "tint": Color(0.7, 0.62, 0.45)})
	_c(shell, Vector3(0.06, 0.06, 0.02), Vector3(-1.5, 2.2, -HALF_D + 0.03), "LedAlarm", {})


func _build_windows() -> void:
	var cages := _prop("Windows")
	for s in [-1.0, 1.0]:
		var cx: float = s * WINDOW_X
		# a cage of bars across the opening, a frame, and the glass behind it
		var bars := int(WINDOW_W / 0.12)
		for i in range(bars + 1):
			var bx := cx - WINDOW_W * 0.5 + 0.06 + i * ((WINDOW_W - 0.12) / maxf(1.0, float(bars)))
			_c(cages, Vector3(0.03, WINDOW_TOP - WINDOW_BOTTOM, 0.03), Vector3(bx, (WINDOW_TOP + WINDOW_BOTTOM) * 0.5, -HALF_D - 0.02), "CageBar", {"kind": "metal", "tint": Color(0.55, 0.55, 0.6)})
		for y in [WINDOW_BOTTOM + 0.02, WINDOW_TOP - 0.02, (WINDOW_TOP + WINDOW_BOTTOM) * 0.5]:
			_c(cages, Vector3(WINDOW_W, 0.04, 0.04), Vector3(cx, y, -HALF_D - 0.02), "CageRail", {"kind": "metal", "tint": Color(0.55, 0.55, 0.6)})


func _build_shaft() -> void:
	var shaft := _prop("Shaft")
	# the far wall and the side walls of the shaft
	_c(shaft, Vector3(9.0, 12.0, 0.3), Vector3(0, 3.0, -6.3), "ShaftWallBack", {"kind": "concrete", "tint": Color(0.45, 0.47, 0.55)})
	for x in [-4.4, 4.4]:
		_c(shaft, Vector3(0.3, 12.0, 6.0), Vector3(x, 3.0, -3.6), "ShaftWallSide", {"kind": "concrete", "tint": Color(0.4, 0.42, 0.5)})
	# a sill outside each window for Elise to walk along
	for s in [-1.0, 1.0]:
		_c(shaft, Vector3(1.2, 0.2, 4.3), Vector3(s * WINDOW_X, -0.1, -3.75), "SillPlatform", {"kind": "metal", "tint": Color(0.5, 0.5, 0.55)})
		_c(shaft, Vector3(0.06, 0.9, 4.3), Vector3(s * (WINDOW_X + 0.6), 0.45, -3.75), "SillRail", {"kind": "metal", "tint": Color(0.6, 0.5, 0.2)})
	# the beams and rails that slide past while the car drops a floor
	dress = Node3D.new()
	dress.name = "ShaftDress"
	shaft.add_child(dress)
	for k in range(-4, 5):
		var y := float(k) * BEAM_GAP
		_c(dress, Vector3(8.4, 0.25, 0.35), Vector3(0, y, -6.0), "BeamCross", {"kind": "metal", "tint": Color(0.5, 0.52, 0.6)})
		for x in [-3.2, 3.2]:
			_c(dress, Vector3(0.35, 0.25, 4.6), Vector3(x, y + 0.5, -3.6), "BeamArm", {"kind": "metal", "tint": Color(0.5, 0.5, 0.58)})
		_c(dress, Vector3(0.5, 0.18, 0.08), Vector3(-3.9, y + 1.0, -5.8), "Sign", {"tint": Color(0.9, 0.7, 0.3)})
		# the stairwell level: a landing on the left wall and a flight of steps up to the next one
		_c(dress, Vector3(1.0, 0.15, 1.2), Vector3(-3.7, y, -5.2), "StairLanding", {"kind": "metal", "tint": Color(0.55, 0.55, 0.6)})
		for i in 5:
			_c(dress, Vector3(0.7, 0.12, 0.42), Vector3(-3.8, y + 0.12 + 0.55 * float(i), -4.5 + 0.5 * float(i)), "StairStep", {"kind": "metal", "tint": Color(0.5, 0.5, 0.55)})
		# the service pipes on the right wall with a valve and a fuse box per level, a label by the landing
		for dx in [0.0, 0.22, 0.44]:
			_c(dress, Vector3(0.14, 3.0, 0.14), Vector3(3.6 + dx, y + 1.5, -5.7), "PipeRun", {"kind": "metal", "tint": Color(0.6, 0.45, 0.35) if dx < 0.3 else Color(0.5, 0.55, 0.65)})
		_c(dress, Vector3(0.36, 0.3, 0.3), Vector3(3.8, y + 1.2, -5.5), "PipeValve", {"kind": "metal", "tint": Color(0.8, 0.25, 0.2)})
		_c(dress, Vector3(0.7, 0.5, 0.2), Vector3(1.6, y + 1.5, -6.05), "FuseCabinet", {"kind": "metal", "tint": Color(0.45, 0.5, 0.5)})
		_c(dress, Vector3(0.08, 0.08, 0.04), Vector3(1.8, y + 1.6, -5.92), "LedLevel", {})
	for x in [-3.9, -1.9, 1.9, 3.9]:
		_c(dress, Vector3(0.15, 24.0, 0.15), Vector3(x, 0.0, -5.9), "RailTall", {"kind": "metal", "tint": Color(0.6, 0.6, 0.65)})


## 0..1 through a ride: the shaft slides up past the windows by one beam gap (looks the same at both ends).
func set_ride(progress: float) -> void:
	dress.position.y = RIDE_DROP * smoothstep(0.0, 1.0, clampf(progress, 0.0, 1.0))


## Where Elise stands on `side` ("L" / "R") when she is `closeness` (0..100) of the way in: far down the sill, then at the glass.
func elise_position(side: String, closeness: float) -> Vector3:
	var t := clampf(closeness / 100.0, 0.0, 1.0)
	return Vector3((-1.0 if side == "L" else 1.0) * WINDOW_X, 0.0, lerpf(SILL_FAR, SILL_NEAR, t))


## The car's lamp reddens and dims as she closes in.
func set_alarm(closeness: float) -> void:
	var t := clampf(closeness / 100.0, 0.0, 1.0)
	lamp.light_color = Color(1.0, 0.86, 0.62).lerp(Color(1.0, 0.35, 0.28), t)
	lamp.light_energy = lerpf(1.5, 1.0, t)
