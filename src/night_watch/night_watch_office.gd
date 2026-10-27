class_name NightWatchOffice
extends Node3D

## The security room: a walkable blocky 6 x 5 m room with a desk, monitor, radio and lamp against the back wall, a chair, a shelf, a
## breaker box and a vent hatch, and a doorway on each side wall with a sliding slab, a control panel (DOOR and LIGHT buttons) on
## the wall beside it and a short dark hall behind it. Everything is built from shaded cubes (NightWatchArt: baked vertex-colour
## shading and painted pixel textures, no post effects) in named prop groups. Everything solid has a collision body on layer 1;
## the things you can aim at are NightWatchStation nodes (shared interactables: prompt and use through the shared player). Real lights are only
## the desk lamp and the two door lights (on only while held) plus a very dim light in each hall (docs/REF_LOOK.md budget).

const A := preload("res://src/night_watch/night_watch_art.gd")
const HALF_W := 3.0
const HALF_D := 2.5
const HEIGHT := 3.0
const DOOR_W := 1.7
const DOOR_H := 2.4
const SLAB_OPEN_Y := DOOR_H + 1.3
const SLAB_CLOSED_Y := DOOR_H * 0.5
## Where the player starts (in the room, facing the desk) and the desk seat.
const SPAWN := Vector3(0.0, 0.0, 0.9)
const SEAT := Vector3(0.0, 0.0, -1.05)
## The hall mouth the player cannot pass (so nobody stands among the hunters): x beyond this is the hunters' side.
const HALL_GUARD_X := 3.7

var slabs := {}          # "doorL"/"doorR" -> Node3D
var door_lights := {}    # "doorL"/"doorR" -> SpotLight3D
var lamp: OmniLight3D
var lamp_shade: MeshInstance3D
var monitor_screen: MeshInstance3D
## station id -> prompt; the walker shows the prompt of the aimed station
var prompts := {}
var button_meshes := {}  # "doorL_door", "doorL_light", ... -> MeshInstance3D
## 0 = open, 1 = shut, per door: the slab slides toward its target in the scene's _process.
var slab_progress := {"doorL": 0.0, "doorR": 0.0}
var props := {}          # prop name -> Node3D group (for the validator)
var stations := {}       # station id -> NightWatchStation


func _ready() -> void:
	if slabs.is_empty():
		build()


func _c(parent: Node3D, size: Vector3, pos: Vector3, node_name: String, opts := {}) -> MeshInstance3D:
	var o := opts.duplicate()
	o["name"] = node_name
	return A.box(parent, size, pos, o)


func _prop(prop_name: String, pos := Vector3.ZERO) -> Node3D:
	var node := A.prop(self, prop_name, pos)
	props[prop_name] = node
	return node


func _body(parent: Node3D, size: Vector3, pos: Vector3, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1 << (layer - 1)
	body.collision_mask = 0
	body.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	return body


## A station: a shared-style interactable the player aims at and uses with the interact action. `focus` is where the aim cone points.
func _station(id: String, prompt: String, _size: Vector3, pos: Vector3, focus := Vector3.ZERO) -> NightWatchStation:
	var st := NightWatchStation.new()
	st.name = "Station_" + id
	st.station_id = id
	st.prompt_text = prompt
	st.focus_local = focus
	st.position = pos
	add_child(st)
	prompts[id] = prompt
	stations[id] = st
	return st


func build() -> void:
	_build_shell()
	for side in [-1.0, 1.0]:
		_build_door_side(side)
	_build_desk()
	_build_chair()
	_build_wall_props()
	_build_extras()
	for key in slabs:
		_apply_slab(key)
	set_button("doorL_door", false)
	set_button("doorR_door", false)
	set_lamp(true)


# --- the shell: floor, ceiling, walls with trim, pipes and fixtures -------------------------------------------------------

func _build_shell() -> void:
	var shell := _prop("Shell")
	_c(shell, Vector3(HALF_W * 2.0 + 0.4, 0.2, HALF_D * 2.0 + 0.4), Vector3(0, -0.1, 0), "Floor", {"solid": true, "tint": Color(1.1, 1.1, 1.1)})
	_c(shell, Vector3(HALF_W * 2.0 + 0.4, 0.2, HALF_D * 2.0 + 0.4), Vector3(0, HEIGHT + 0.1, 0), "Ceiling", {"tint": Color(0.7, 0.7, 0.75)})
	_c(shell, Vector3(HALF_W * 2.0 + 0.4, HEIGHT, 0.2), Vector3(0, HEIGHT * 0.5, -HALF_D - 0.1), "WallBack", {"solid": true})
	_c(shell, Vector3(HALF_W * 2.0 + 0.4, HEIGHT, 0.2), Vector3(0, HEIGHT * 0.5, HALF_D + 0.1), "WallFront", {"solid": true, "tint": Color(0.85, 0.85, 0.9)})
	# baseboards, a crown strip and vertical panel lines on the back and front walls
	for z in [-HALF_D + 0.04, HALF_D - 0.04]:
		_c(shell, Vector3(HALF_W * 2.0, 0.22, 0.08), Vector3(0, 0.11, z), "Baseboard", {"tint": Color(0.7, 0.7, 0.75)})
		_c(shell, Vector3(HALF_W * 2.0, 0.12, 0.08), Vector3(0, HEIGHT - 0.06, z), "CrownTrim", {"tint": Color(0.8, 0.8, 0.85)})
		for x in [-2.0, -0.7, 0.7, 2.0]:
			_c(shell, Vector3(0.06, HEIGHT - 0.5, 0.05), Vector3(x, HEIGHT * 0.5, z), "PanelLine", {"tint": Color(0.75, 0.75, 0.8)})
	# pipes and a cable run along the ceiling, ceiling fixtures (off), bolts
	_c(shell, Vector3(HALF_W * 2.0, 0.12, 0.12), Vector3(0, HEIGHT - 0.2, -HALF_D + 0.2), "PipeBack", {"kind": "metal"})
	_c(shell, Vector3(HALF_W * 2.0, 0.07, 0.07), Vector3(0, HEIGHT - 0.35, -HALF_D + 0.18), "ConduitBack", {"kind": "plastic"})
	for x in [-2.5, -1.2, 0.0, 1.2, 2.5]:
		_c(shell, Vector3(0.16, 0.2, 0.16), Vector3(x, HEIGHT - 0.2, -HALF_D + 0.2), "PipeClamp", {"kind": "metal", "tint": Color(0.8, 0.8, 0.85)})
	for x in [-1.4, 1.4]:
		_c(shell, Vector3(1.1, 0.08, 0.5), Vector3(x, HEIGHT - 0.04, 0.2), "CeilingFixture", {"kind": "plastic"})
		_c(shell, Vector3(0.9, 0.02, 0.3), Vector3(x, HEIGHT - 0.1, 0.2), "CeilingLens", {"kind": "glass", "tint": Color(0.45, 0.5, 0.5)})
	_c(shell, Vector3(0.05, 0.05, 0.05), Vector3(2.7, 0.9, HALF_D - 0.1), "LedAlarm", {})
	# a hazard stripe along the floor in front of the desk and a floor mat
	_c(shell, Vector3(2.8, 0.01, 0.12), Vector3(0, 0.005, -0.55), "FloorStripe", {"hazard": "y", "tint": Color(0.8, 0.8, 0.8)})
	_c(shell, Vector3(1.6, 0.02, 1.0), Vector3(0, 0.01, -1.1), "FloorMat", {"tint": Color(0.9, 0.9, 0.95)})


# --- one door: frame, slab, panel, hall --------------------------------------------------------------------------------------

func _build_door_side(side: float) -> void:
	var tag := "L" if side < 0.0 else "R"
	var door := "doorL" if side < 0.0 else "doorR"
	var side_name := "LEFT" if side < 0.0 else "RIGHT"
	var x: float = side * (HALF_W + 0.1)
	var wall := _prop("Wall" + tag)
	var piece := (HALF_D * 2.0 - DOOR_W) * 0.5
	_c(wall, Vector3(0.2, HEIGHT, piece), Vector3(x, HEIGHT * 0.5, -HALF_D + piece * 0.5), "Wall%sA" % tag, {"solid": true})
	_c(wall, Vector3(0.2, HEIGHT, piece), Vector3(x, HEIGHT * 0.5, HALF_D - piece * 0.5), "Wall%sB" % tag, {"solid": true})
	_c(wall, Vector3(0.2, HEIGHT - DOOR_H, DOOR_W), Vector3(x, DOOR_H + (HEIGHT - DOOR_H) * 0.5, 0), "Wall%sTop" % tag, {})
	# baseboards and a crown strip on the inner face
	var ix: float = side * (HALF_W - 0.04)
	for zz in [-HALF_D + piece * 0.5, HALF_D - piece * 0.5]:
		_c(wall, Vector3(0.08, 0.22, piece), Vector3(ix, 0.11, zz), "Baseboard", {"tint": Color(0.7, 0.7, 0.75)})
	_c(wall, Vector3(0.08, 0.12, HALF_D * 2.0), Vector3(ix, HEIGHT - 0.06, 0), "CrownTrim", {"tint": Color(0.8, 0.8, 0.85)})
	# the frame: posts, a header with a hazard stripe, seals, a threshold
	var frame := _prop("DoorFrame" + tag)
	for zz in [-DOOR_W * 0.5 - 0.07, DOOR_W * 0.5 + 0.07]:
		_c(frame, Vector3(0.34, DOOR_H, 0.14), Vector3(x, DOOR_H * 0.5, zz), "FramePost", {"tint": Color(0.75, 0.7, 0.65)})
		_c(frame, Vector3(0.1, DOOR_H - 0.1, 0.05), Vector3(side * (HALF_W - 0.1), DOOR_H * 0.5, zz * 0.92), "Seal", {"kind": "plastic"})
	_c(frame, Vector3(0.34, 0.16, DOOR_W + 0.28), Vector3(x, DOOR_H + 0.06, 0), "FrameHeader", {"tint": Color(0.75, 0.7, 0.65)})
	_c(frame, Vector3(0.2, 0.09, DOOR_W), Vector3(side * (HALF_W - 0.02), DOOR_H - 0.06, 0), "HazardStripe", {"hazard": "x", "tint": Color(0.85, 0.85, 0.85)})
	_c(frame, Vector3(0.4, 0.05, DOOR_W), Vector3(x, 0.025, 0), "Threshold", {"kind": "metal", "tint": Color(0.85, 0.85, 0.9)})
	# the slab in the doorway (its body rides along, so a shut door really blocks the way)
	var slab := Node3D.new()
	slab.name = "Slab" + tag
	slab.set_meta("nw_prop", true)
	slab.position = Vector3(side * HALF_W, SLAB_OPEN_Y, 0.0)
	add_child(slab)
	props["Slab" + tag] = slab
	_c(slab, Vector3(0.14, DOOR_H, DOOR_W - 0.04), Vector3.ZERO, "SlabBody", {"solid": true})
	# four bands across the leaf: hazard tape at the top and bottom, a stepped metal rib at each of the two between (geometry, not texture lines)
	for i in 4:
		var by := -DOOR_H * 0.5 + 0.3 + i * 0.6
		if i == 0 or i == 3:
			_c(slab, Vector3(0.2, 0.12, DOOR_W - 0.06), Vector3(0, by, 0), "SlabStripe", {"hazard": "x", "tint": Color(1.0, 1.0, 1.0)})
		else:
			_c(slab, Vector3(0.18, 0.1, DOOR_W - 0.06), Vector3(0, by, 0), "SlabRibBand", {"kind": "metal", "tint": Color(0.85, 0.85, 0.9)})
			_c(slab, Vector3(0.2, 0.04, DOOR_W - 0.14), Vector3(0, by, 0), "SlabRibStep", {"kind": "metal", "tint": Color(1.05, 1.05, 1.1)})
	for zz in [-0.7, 0.7]:
		for yy in [-0.95, 0.0, 0.95]:
			_c(slab, Vector3(0.18, 0.07, 0.07), Vector3(0, yy, zz), "SlabBolt", {"kind": "metal", "tint": Color(1.1, 1.1, 1.1)})
	_c(slab, Vector3(0.2, 0.08, 0.5), Vector3(-side * 0.02, 0.05, 0.4), "SlabHandle", {"kind": "metal", "tint": Color(1.2, 1.2, 1.2)})
	_c(slab, Vector3(0.16, 0.5, 0.05), Vector3(0, 0.0, -0.45), "SlabRib", {"kind": "metal", "tint": Color(0.85, 0.85, 0.9)})
	slabs[door] = slab
	# the hall behind the doorway: floor, walls with trim, ceiling pipes, a sign, a very dim light, the guard the player cannot pass
	var hall := _prop("Hall" + tag)
	var hx: float = side * (HALF_W + 3.25)
	_c(hall, Vector3(6.3, 0.2, 3.2), Vector3(hx, -0.1, 0), "Hall%sFloor" % tag, {"solid": true, "tint": Color(0.85, 0.85, 0.9)})
	_c(hall, Vector3(6.3, 0.2, 3.2), Vector3(hx, HEIGHT + 0.1, 0), "Hall%sCeiling" % tag, {"tint": Color(0.6, 0.6, 0.65)})
	_c(hall, Vector3(6.3, HEIGHT, 0.2), Vector3(hx, HEIGHT * 0.5, -1.7), "Hall%sWallN" % tag, {"solid": true, "tint": Color(0.8, 0.8, 0.85)})
	_c(hall, Vector3(6.3, HEIGHT, 0.2), Vector3(hx, HEIGHT * 0.5, 1.7), "Hall%sWallS" % tag, {"solid": true, "tint": Color(0.8, 0.8, 0.85)})
	_c(hall, Vector3(0.2, HEIGHT, 3.2), Vector3(side * (HALF_W + 6.4), HEIGHT * 0.5, 0), "Hall%sEnd" % tag, {"solid": true, "tint": Color(0.7, 0.7, 0.75)})
	for zz in [-1.55, 1.55]:
		_c(hall, Vector3(6.2, 0.2, 0.08), Vector3(hx, 0.1, zz), "Baseboard", {"tint": Color(0.7, 0.7, 0.75)})
		_c(hall, Vector3(6.2, 0.1, 0.12), Vector3(hx, HEIGHT - 0.2, zz), "PipeHall", {"kind": "metal"})
	_c(hall, Vector3(6.2, 0.01, 0.2), Vector3(hx, 0.005, 0), "HallStripe", {"hazard": "y", "tint": Color(0.7, 0.7, 0.7)})
	_c(hall, Vector3(0.08, 1.9, 1.0), Vector3(side * (HALF_W + 6.28), 1.0, 0), "HallEndDoor", {"kind": "metal", "tint": Color(0.8, 0.8, 0.85)})
	_c(hall, Vector3(0.05, 0.2, 0.7), Vector3(side * (HALF_W + 6.28), 2.2, 0), "SignExit", {"tint": Color(0.5, 1.0, 0.6)})
	_body(self, Vector3(0.3, HEIGHT, 3.2), Vector3(side * HALL_GUARD_X, HEIGHT * 0.5, 0.0), 1)
	var dim := OmniLight3D.new()
	dim.name = "Hall%sGlow" % tag
	dim.light_color = Color(0.45, 0.55, 0.9)
	dim.light_energy = 0.14
	dim.omni_range = 5.0
	dim.position = Vector3(side * (HALF_W + 3.6), 2.4, 0)
	add_child(dim)
	# the door light: a spot from the desk side toward the hall, on only while held
	var spot := SpotLight3D.new()
	spot.name = "DoorLight" + tag
	spot.light_color = Color(1.0, 0.95, 0.82)
	spot.light_energy = 5.0
	spot.spot_range = 9.0
	spot.spot_angle = 34.0
	spot.shadow_enabled = false
	add_child(spot)
	spot.transform = Transform3D(Basis.IDENTITY, Vector3(side * 1.7, 1.55, 0.7)).looking_at(Vector3(side * (HALF_W + 4.2), 1.0, 0.0), Vector3.UP)
	spot.visible = false
	door_lights[door] = spot
	# the control panel on the wall beside the door: housing, screws, conduit, a name plate, a DOOR button above a LIGHT button
	var panel := _prop("ControlPanel" + tag)
	var px: float = side * (HALF_W - 0.06)
	_c(panel, Vector3(0.1, 0.78, 0.46), Vector3(px, 1.3, 1.55), "PanelHousing", {"solid": false})
	_c(panel, Vector3(0.05, 0.7, 0.4), Vector3(side * (HALF_W - 0.12), 1.3, 1.55), "PanelFace", {"kind": "plastic"})
	for zz in [1.37, 1.73]:
		for yy in [0.96, 1.64]:
			_c(panel, Vector3(0.07, 0.05, 0.05), Vector3(side * (HALF_W - 0.13), yy, zz), "PanelBolt", {"kind": "metal", "tint": Color(1.2, 1.2, 1.2)})
	_c(panel, Vector3(0.07, 0.07, 0.07), Vector3(px, 1.86, 1.55), "ConduitPanel", {"kind": "plastic"})
	_c(panel, Vector3(0.07, 0.9, 0.07), Vector3(px, 2.35, 1.55), "ConduitRise", {"kind": "plastic"})
	_c(panel, Vector3(0.06, 0.1, 0.28), Vector3(side * (HALF_W - 0.14), 1.74, 1.55), "LabelPlate", {})
	for entry in [["door", 1.47, "DOOR"], ["light", 1.15, "LIGHT"]]:
		var bx: float = side * (HALF_W - 0.15)
		_c(panel, Vector3(0.05, 0.26, 0.3), Vector3(side * (HALF_W - 0.14), float(entry[1]), 1.55), "Guard" + String(entry[2]), {"kind": "metal", "tint": Color(0.9, 0.9, 0.95)})
		var b := _c(panel, Vector3(0.06, 0.18, 0.22), Vector3(bx, float(entry[1]), 1.55), "Button%s%s" % [tag, entry[2]], {"kind": "red" if entry[0] == "door" else "light"})
		button_meshes["%s_%s" % [door, entry[0]]] = b
		var text := "%s DOOR // SHUT / OPEN" % side_name if entry[0] == "door" else "%s DOOR LIGHT // HOLD" % side_name
		_station("%s_%s" % [door, entry[0]], text, Vector3(0.22, 0.26, 0.34), Vector3(bx, float(entry[1]), 1.55))


# --- the desk, monitor, radio, lamp ----------------------------------------------------------------------------------------

func _build_desk() -> void:
	var desk := _prop("Desk", Vector3(0, 0, -1.95))
	_c(desk, Vector3(2.4, 0.08, 0.95), Vector3(0, 0.76, 0), "DeskTop", {})
	_c(desk, Vector3(2.44, 0.04, 0.99), Vector3(0, 0.8, 0), "DeskEdge", {"tint": Color(1.15, 1.15, 1.15)})
	for x in [-1.1, 1.1]:
		_c(desk, Vector3(0.1, 0.76, 0.85), Vector3(x, 0.38, 0), "DeskLeg", {})
	_c(desk, Vector3(2.1, 0.5, 0.04), Vector3(0, 0.45, -0.4), "DeskBackPanel", {"tint": Color(0.8, 0.8, 0.8)})
	for x in [-0.8, -0.3]:
		_c(desk, Vector3(0.42, 0.22, 0.04), Vector3(x, 0.55, 0.43), "DeskDrawer", {"tint": Color(1.05, 1.05, 1.05)})
		_c(desk, Vector3(0.16, 0.03, 0.04), Vector3(x, 0.57, 0.47), "DeskHandle", {"kind": "metal"})
	_body(self, Vector3(2.4, 0.9, 0.95), Vector3(0, 0.45, -1.95), 1)
	# the monitor: case, bezel, screen, neck, base, an LED, cables
	var monitor := _prop("Monitor", Vector3(0, 0, -2.2))
	_c(monitor, Vector3(0.96, 0.64, 0.09), Vector3(0, 1.12, 0), "MonitorCase", {})
	_c(monitor, Vector3(0.88, 0.56, 0.02), Vector3(0, 1.12, 0.05), "MonitorBezel", {"tint": Color(0.7, 0.7, 0.75)})
	monitor_screen = _c(monitor, Vector3(0.8, 0.48, 0.02), Vector3(0, 1.12, 0.06), "MonitorScreen", {})
	_c(monitor, Vector3(0.14, 0.18, 0.12), Vector3(0, 0.9, -0.02), "MonitorNeck", {})
	_c(monitor, Vector3(0.4, 0.04, 0.26), Vector3(0, 0.82, 0.0), "MonitorBase", {})
	_c(monitor, Vector3(0.04, 0.03, 0.02), Vector3(0.4, 0.83 + 0.2, 0.07), "LedPower", {})
	_c(monitor, Vector3(0.05, 0.4, 0.05), Vector3(0.3, 0.6, -0.1), "CableMonitor", {"kind": "plastic", "tint": Color(0.6, 0.6, 0.65)})
	# keyboard (a base and three key rows), a mouse, a stack of papers, a clipboard, a cup
	var kb := _prop("Keyboard", Vector3(0.0, 0.8, -1.6))
	_c(kb, Vector3(0.52, 0.03, 0.18), Vector3.ZERO, "KeyboardBase", {})
	for i in 3:
		_c(kb, Vector3(0.46, 0.015, 0.035), Vector3(0, 0.02, -0.05 + i * 0.05), "KeyboardKeys", {"kind": "metal", "tint": Color(0.9, 0.9, 0.95)})
	_c(kb, Vector3(0.07, 0.03, 0.1), Vector3(0.45, 0.0, 0.0), "KeyboardMouse", {})
	var papers := _prop("Papers", Vector3(-0.75, 0.8, -1.75))
	for i in 3:
		_c(papers, Vector3(0.28, 0.012, 0.36), Vector3(0.01 * i, 0.007 + i * 0.012, 0.01 * i), "PaperSheet", {"kind": "paper", "tint": Color(1.2, 1.2, 1.2), "ao": 1.0})
	_c(papers, Vector3(0.3, 0.015, 0.4), Vector3(0.45, 0.01, 0.0), "ClipboardBoard", {"kind": "wood"})
	_c(papers, Vector3(0.1, 0.02, 0.05), Vector3(0.45, 0.025, -0.18), "ClipboardClip", {"kind": "metal"})
	var cup := _prop("Cup", Vector3(-1.0, 0.8, -1.5))
	_c(cup, Vector3(0.14, 0.14, 0.14), Vector3(0, 0.07, 0), "CupBody", {"tint": Color(1.3, 1.3, 1.2)})
	_c(cup, Vector3(0.05, 0.08, 0.04), Vector3(0.09, 0.07, 0), "CupHandle", {})
	_c(cup, Vector3(0.1, 0.02, 0.1), Vector3(0, 0.145, 0), "CupCoffee", {"kind": "wood", "tint": Color(0.5, 0.4, 0.35)})
	# Zellia's radio: a box with a dial, a speaker grille, an antenna and a green LED
	var radio := _prop("Radio", Vector3(-0.35, 0.8, -2.1))
	_c(radio, Vector3(0.3, 0.16, 0.14), Vector3(0, 0.08, 0), "RadioCase", {"tint": Color(1.1, 1.1, 1.1)})
	_c(radio, Vector3(0.1, 0.1, 0.02), Vector3(-0.07, 0.08, 0.075), "RadioGrille", {"kind": "metal", "tint": Color(0.7, 0.7, 0.75)})
	_c(radio, Vector3(0.05, 0.05, 0.03), Vector3(0.06, 0.1, 0.075), "RadioDial", {"kind": "metal", "tint": Color(1.2, 1.2, 1.2)})
	_c(radio, Vector3(0.015, 0.2, 0.015), Vector3(0.11, 0.2, -0.03), "RadioAntenna", {"kind": "metal"})
	_c(radio, Vector3(0.025, 0.02, 0.02), Vector3(0.1, 0.14, 0.075), "LedRadio", {})
	# the desk lamp: base, two arm pieces, shade (emissive)
	var lamp_prop := _prop("DeskLampProp", Vector3(0.9, 0.8, -1.7))
	_c(lamp_prop, Vector3(0.18, 0.04, 0.18), Vector3(0, 0.02, 0), "LampBase", {})
	_c(lamp_prop, Vector3(0.04, 0.22, 0.04), Vector3(0, 0.15, 0), "LampArm", {})
	_c(lamp_prop, Vector3(0.18, 0.04, 0.04), Vector3(0.06, 0.27, 0), "LampArmTop", {})
	lamp_shade = _c(lamp_prop, Vector3(0.22, 0.14, 0.22), Vector3(0.1, 0.4 - 0.12, 0), "LampShade", {})
	lamp = OmniLight3D.new()
	lamp.name = "DeskLamp"
	lamp.light_color = Color(1.0, 0.82, 0.55)
	lamp.light_energy = 2.2
	lamp.omni_range = 5.0
	lamp.position = Vector3(0.9, 1.35, -1.6)
	add_child(lamp)
	_station("monitor", "MONITOR // CAMERAS", Vector3.ZERO, Vector3(0, 1.12, -2.0))
	_station("lamp", "DESK LAMP", Vector3(0.4, 0.6, 0.4), Vector3(0.9, 1.0, -1.7))


func _build_chair() -> void:
	var chair := _prop("Chair", Vector3(0.0, 0.0, -1.1))
	_c(chair, Vector3(0.46, 0.1, 0.46), Vector3(0, 0.5, 0), "ChairSeat", {"solid": true})
	_c(chair, Vector3(0.44, 0.5, 0.08), Vector3(0, 0.8, 0.2), "ChairBack", {})
	_c(chair, Vector3(0.1, 0.06, 0.3), Vector3(-0.28, 0.66, 0.0), "ChairArmL", {"kind": "plastic"})
	_c(chair, Vector3(0.1, 0.06, 0.3), Vector3(0.28, 0.66, 0.0), "ChairArmR", {"kind": "plastic"})
	_c(chair, Vector3(0.08, 0.3, 0.08), Vector3(0, 0.3, 0), "ChairColumn", {"kind": "metal"})
	_c(chair, Vector3(0.5, 0.05, 0.08), Vector3(0, 0.1, 0), "ChairBaseA", {"kind": "metal"})
	_c(chair, Vector3(0.08, 0.05, 0.5), Vector3(0, 0.1, 0), "ChairBaseB", {"kind": "metal"})
	for x in [-0.22, 0.22]:
		for z in [-0.22, 0.22]:
			_c(chair, Vector3(0.07, 0.07, 0.07), Vector3(x, 0.035, z), "ChairWheel", {"kind": "plastic", "tint": Color(0.7, 0.7, 0.7)})
	_station("chair", "SIT AT DESK", Vector3.ZERO, Vector3(0.0, 0.0, -1.05), Vector3(0.0, 0.62, 0.0))


# --- the breaker box, vent hatch, shelf, clock, poster, bin ----------------------------------------------------------------

func _build_wall_props() -> void:
	var breaker := _prop("BreakerBox", Vector3(2.3, 1.5, -HALF_D))
	_c(breaker, Vector3(0.64, 0.84, 0.14), Vector3(0, 0, 0.07), "BreakerHousing", {"solid": true})
	_c(breaker, Vector3(0.58, 0.78, 0.04), Vector3(0, 0, 0.16), "BreakerDoor", {"tint": Color(1.1, 1.1, 1.1)})
	for i in 2:
		_c(breaker, Vector3(0.05, 0.12, 0.05), Vector3(-0.31, -0.25 + i * 0.5, 0.15), "BreakerHinge", {"kind": "metal", "tint": Color(1.2, 1.2, 1.2)})
	for i in 4:
		_c(breaker, Vector3(0.07, 0.12, 0.05), Vector3(-0.17 + i * 0.11, 0.0, 0.2), "BreakerSwitch", {"kind": "plastic", "tint": Color(1.7, 1.7, 1.7)})
		_c(breaker, Vector3(0.03, 0.03, 0.03), Vector3(-0.17 + i * 0.11, 0.12, 0.2), "LedBreaker", {})
	_c(breaker, Vector3(0.46, 0.1, 0.04), Vector3(0, 0.3, 0.2), "LabelBreaker", {})
	_c(breaker, Vector3(0.07, 0.9, 0.07), Vector3(0.22, 0.85, 0.1), "ConduitBreaker", {"kind": "plastic"})
	_station("breaker", "BREAKER BOX // NOT USED TONIGHT", Vector3(0.7, 0.9, 0.3), Vector3(2.3, 1.5, -HALF_D + 0.2))
	var vent := _prop("VentHatch", Vector3(-2.3, 0.45, -HALF_D))
	_c(vent, Vector3(0.84, 0.54, 0.1), Vector3(0, 0, 0.05), "VentFrame", {"solid": true})
	for i in 5:
		_c(vent, Vector3(0.7, 0.035, 0.06), Vector3(0, -0.2 + i * 0.1, 0.12), "VentLouver", {"kind": "metal", "tint": Color(0.7, 0.7, 0.75)})
	for sx in [-0.38, 0.38]:
		for sy in [-0.24, 0.24]:
			_c(vent, Vector3(0.05, 0.05, 0.05), Vector3(sx, sy, 0.13), "VentScrew", {"kind": "metal", "tint": Color(1.3, 1.3, 1.3)})
	_station("vent", "VENT HATCH // SEALED", Vector3(0.9, 0.6, 0.3), Vector3(-2.3, 0.45, -HALF_D + 0.2))
	# a shelf unit in the back left corner with boxes, a bin by the desk
	var shelf := _prop("ShelfUnit", Vector3(-2.7, 0.0, -1.0))
	for x in [-0.18, 0.18]:
		for z in [-0.6, 0.6]:
			_c(shelf, Vector3(0.05, 1.8, 0.05), Vector3(x, 0.9, z), "ShelfPost", {"kind": "metal"})
	for i in 4:
		_c(shelf, Vector3(0.42, 0.04, 1.3), Vector3(0, 0.25 + i * 0.5, 0), "ShelfBoard", {})
	_body(self, Vector3(0.42, 1.8, 1.3), Vector3(-2.7, 0.9, -1.0), 1)
	for i in 3:
		_c(shelf, Vector3(0.32, 0.26, 0.4), Vector3(0.0, 0.41 + i * 0.5, -0.3 + (i % 2) * 0.5), "ShelfBox", {"kind": "wood", "tint": Color(0.85 + 0.1 * i, 0.85, 0.8)})
	_c(shelf, Vector3(0.3, 0.18, 0.3), Vector3(0.0, 0.34, 0.45), "ShelfCrate", {"kind": "wood", "tint": Color(0.7, 0.7, 0.75)})
	var bin := _prop("Bin", Vector3(1.55, 0.0, -1.55))
	_c(bin, Vector3(0.3, 0.38, 0.3), Vector3(0, 0.19, 0), "BinBody", {"solid": true, "tint": Color(0.9, 0.9, 1.0)})
	_c(bin, Vector3(0.34, 0.04, 0.34), Vector3(0, 0.4, 0), "BinRim", {"tint": Color(1.2, 1.2, 1.2)})
	var clock := _prop("WallClock", Vector3(1.4, 2.2, -HALF_D))
	_c(clock, Vector3(0.58, 0.58, 0.05), Vector3(0, 0, 0.03), "ClockFrame", {"kind": "plastic"})
	_c(clock, Vector3(0.5, 0.5, 0.03), Vector3(0, 0, 0.06), "ClockFace", {})
	_c(clock, Vector3(0.03, 0.18, 0.02), Vector3(0, 0.07, 0.09), "ClockHandA", {"kind": "plastic"})
	_c(clock, Vector3(0.14, 0.03, 0.02), Vector3(0.05, 0, 0.09), "ClockHandB", {"kind": "plastic"})
	var poster := _prop("Poster", Vector3(-1.4, 1.8, -HALF_D))
	_c(poster, Vector3(1.0, 1.3, 0.04), Vector3(0, 0, 0.02), "PosterFrame", {})
	_c(poster, Vector3(0.88, 1.18, 0.03), Vector3(0, 0, 0.05), "PosterPaper", {"kind": "fabric", "tint": Color(1.1, 0.9, 1.0)})
	_c(poster, Vector3(0.6, 0.14, 0.02), Vector3(0, 0.38, 0.07), "PosterTitle", {"kind": "label", "tint": Color(0.9, 0.9, 0.9)})


# --- extra detail: bolts, cables, an extinguisher, a notice board, a ceiling grille -----------------------------------------------

func _build_extras() -> void:
	var bolts := _prop("WallBolts")
	for x in [-2.6, -1.5, -0.4, 0.7, 1.8, 2.6]:
		_c(bolts, Vector3(0.06, 0.06, 0.04), Vector3(x, 0.32, -HALF_D + 0.03), "WallBolt", {"kind": "metal", "tint": Color(1.2, 1.2, 1.2)})
		_c(bolts, Vector3(0.06, 0.06, 0.04), Vector3(x, 0.32, HALF_D - 0.03), "WallBolt", {"kind": "metal", "tint": Color(1.2, 1.2, 1.2)})
	for z in [-2.0, -0.9, 0.0, 1.0, 2.0]:
		_c(bolts, Vector3(0.04, 0.06, 0.06), Vector3(-HALF_W + 0.03, 0.32, z), "WallBolt", {"kind": "metal", "tint": Color(1.2, 1.2, 1.2)})
		_c(bolts, Vector3(0.04, 0.06, 0.06), Vector3(HALF_W - 0.03, 0.32, z), "WallBolt", {"kind": "metal", "tint": Color(1.2, 1.2, 1.2)})
	for x in [-0.2, 2.0]:
		_c(bolts, Vector3(0.12, 0.18, 0.03), Vector3(x, 0.5, -HALF_D + 0.04), "OutletPlate", {"kind": "plastic", "tint": Color(1.5, 1.5, 1.5)})
		_c(bolts, Vector3(0.05, 0.06, 0.02), Vector3(x, 0.5, -HALF_D + 0.065), "OutletSocket", {"kind": "plastic", "tint": Color(0.5, 0.5, 0.5)})
	var cables := _prop("FloorCables")
	_c(cables, Vector3(0.05, 0.03, 1.1), Vector3(0.3, 0.02, -2.0), "CableRun", {"kind": "plastic"})
	_c(cables, Vector3(1.0, 0.03, 0.05), Vector3(0.8, 0.02, -2.4), "CableRun", {"kind": "plastic"})
	_c(cables, Vector3(0.05, 0.03, 0.9), Vector3(1.3, 0.02, -1.95), "CableRun", {"kind": "plastic", "tint": Color(0.8, 0.8, 0.9)})
	_c(cables, Vector3(0.14, 0.05, 0.14), Vector3(1.3, 0.025, -1.5), "CableClamp", {"kind": "metal"})
	var ext := _prop("Extinguisher", Vector3(2.8, 0.0, -0.9))
	_c(ext, Vector3(0.05, 0.9, 0.3), Vector3(0.1, 0.6, 0), "ExtBracket", {"kind": "metal"})
	_c(ext, Vector3(0.22, 0.6, 0.22), Vector3(0, 0.55, 0), "ExtBody", {"kind": "red"})
	_c(ext, Vector3(0.1, 0.1, 0.1), Vector3(0, 0.9, 0), "ExtHead", {"kind": "metal"})
	_c(ext, Vector3(0.05, 0.05, 0.25), Vector3(-0.1, 0.92, 0), "ExtNozzle", {"kind": "plastic"})
	_c(ext, Vector3(0.24, 0.1, 0.24), Vector3(0, 0.6, 0), "ExtBand", {"hazard": "xz", "tint": Color(0.9, 0.9, 0.9)})
	var board := _prop("NoticeBoard", Vector3(1.3, 1.7, HALF_D))
	_c(board, Vector3(1.2, 0.8, 0.05), Vector3(0, 0, -0.03), "BoardCork", {"kind": "wood", "tint": Color(1.1, 0.9, 0.7)})
	for i in 4:
		_c(board, Vector3(0.22, 0.28, 0.01), Vector3(-0.4 + i * 0.27, 0.08 - (i % 2) * 0.12, -0.07), "BoardNote", {"kind": "label", "tint": Color(1.2, 1.2, 1.1), "ao": 1.0})
	_c(board, Vector3(1.28, 0.05, 0.07), Vector3(0, 0.42, -0.03), "BoardTrim", {"kind": "metal"})
	var grille := _prop("CeilingGrille", Vector3(2.0, HEIGHT - 0.02, 1.4))
	_c(grille, Vector3(0.7, 0.04, 0.7), Vector3.ZERO, "GrilleFrame", {"kind": "metal"})
	for i in 4:
		_c(grille, Vector3(0.6, 0.02, 0.05), Vector3(0, -0.03, -0.24 + i * 0.16), "GrilleSlat", {"kind": "plastic"})


# --- the things the scene drives ---------------------------------------------------------------------------------------------

## A panel button's colour: the DOOR button is red while the door is shut, green when open; the LIGHT button glows while held.
func set_button(id: String, on: bool) -> void:
	var mesh := button_meshes.get(id) as MeshInstance3D
	if mesh == null:
		return
	if id.ends_with("_door"):
		mesh.material_override = A.material("red" if on else "green", Color.WHITE, true)
	else:
		mesh.material_override = A.material("light" if on else "plastic", Color.WHITE, on)


func set_lamp(on: bool) -> void:
	lamp.visible = on
	lamp_shade.material_override = A.material("light", Color.WHITE if on else Color(0.35, 0.3, 0.25), on)


## Move the slabs toward their targets (1 = shut). Returns true if anything moved.
func animate(shut: Dictionary, delta: float) -> bool:
	var moved := false
	for key in slabs:
		var target := 1.0 if bool(shut.get(key, false)) else 0.0
		var current: float = slab_progress[key]
		if not is_equal_approx(current, target):
			slab_progress[key] = move_toward(current, target, delta * 7.0)
			moved = true
			_apply_slab(key)
	return moved


func snap_slabs(shut: Dictionary) -> void:
	for key in slabs:
		slab_progress[key] = 1.0 if bool(shut.get(key, false)) else 0.0
		_apply_slab(key)


func _apply_slab(key: String) -> void:
	var slab := slabs[key] as Node3D
	slab.position.y = lerpf(SLAB_OPEN_Y, SLAB_CLOSED_Y, float(slab_progress[key]))


func set_light(key: String, on: bool) -> void:
	(door_lights[key] as SpotLight3D).visible = on


## Where a hunter at a door stands, from how far into her wait she is (0 = just arrived, 1 = about to attack): she starts well
## down the hall (peek), steps up to the doorway (stand) and leans in at the threshold, in the doorway itself (lean).
func door_stand(door: String, slot: int, progress := 0.0) -> Vector3:
	var side := -1.0 if door == "doorL" else 1.0
	var near := lerpf(HALF_W + 1.9, HALF_W + 0.55, clampf(progress, 0.0, 1.0))
	return Vector3(side * (near + slot * 1.3), 0.0, -0.4 * slot)
