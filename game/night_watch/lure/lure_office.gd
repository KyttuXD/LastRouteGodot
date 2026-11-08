class_name LureOffice
extends NightWatchOfficeBase

## Dead Air's office: a radio / broadcast booth (the OFFICE CONTRACT, docs/NIGHT_WATCH_OFFICES.md). A 6 x 5 m room lined with acoustic foam, a glass window
## onto a dark studio, a mixing console with the systems monitor, a boom microphone, a patch rack with reboot LEDs and an ON AIR lamp. The two ventilation
## hatches in the side walls are where Xivvy comes in: each has a slatted cover that drops shut (the DOOR button on the panel beside it seals it) and a service
## duct behind it that runs away from the booth. The LIGHT buttons on those panels run the heater (left) and the fan (right). Cubes only through NightWatchArt;
## real lights: the desk lamp and a faint glow in each duct.

const A := preload("res://game/night_watch/night_watch_art.gd")
const HALF_W := 3.0
const HALF_D := 2.5
const HEIGHT := 3.6
const VENT_W := 1.5
const VENT_H := 2.2
const SLAB_OPEN_Y := VENT_H + 1.3
const SLAB_CLOSED_Y := VENT_H * 0.5
const SPAWN := Vector3(0.0, 0.0, 0.9)
const HALL_GUARD_X := 3.7

var slabs := {}
var slab_progress := {"doorL": 0.0, "doorR": 0.0}
var prompts := {}
var button_meshes := {}
var lamp: OmniLight3D
var lamp_shade: MeshInstance3D
var monitor_screen: MeshInstance3D
var on_air: MeshInstance3D


func _make_spec() -> NightWatchOfficeSpec:
	return make_spec()


static func make_spec() -> NightWatchOfficeSpec:
	return NightWatchOfficeSpec.make({
		"id": "broadcast_booth", "title": "Broadcast booth", "mode_ids": ["lure"],
		"footprint": Rect2(-HALF_W + 0.5, -HALF_D + 0.5, HALF_W * 2.0 - 1.0, HALF_D * 2.0 - 1.0),
		"spawn": SPAWN,
		"entrances": [
			{"id": "doorL", "kind": "vent", "position": Vector3(-HALF_W, 0.0, 0.0), "outward": Vector3(-1, 0, 0), "sim_room": "officeL", "blockable": true},
			{"id": "doorR", "kind": "vent", "position": Vector3(HALF_W, 0.0, 0.0), "outward": Vector3(1, 0, 0), "sim_room": "officeR", "blockable": true},
			{"id": "studio_window", "kind": "window", "position": Vector3(0.0, 0.0, -HALF_D + 0.6), "outward": Vector3(0, 0, -1), "sim_room": "studio", "blockable": false},
		],
		"required_stations": ["monitor", "doorL_door", "doorR_door", "doorL_light", "doorR_light", "lamp", "chair"],
		"has_monitor": true,
		"mood": {"kind": "cold_monitor", "ambient": Color(0.34, 0.38, 0.55), "lamp": Color(1.0, 0.78, 0.5), "accent": Color(1.0, 0.3, 0.25)},
		"tone_cue": "static",
		"controls": ["nw_door_left", "nw_door_right", "nw_light_left", "nw_light_right", "nw_lamp", "nw_monitor"],
		"references": {"2d_screenshot": "docs/night_watch_offices/broadcast_booth_2d.png"},
	})


func _c(parent: Node3D, size: Vector3, pos: Vector3, node_name: String, opts := {}) -> MeshInstance3D:
	var o := opts.duplicate()
	o["name"] = node_name
	return A.box(parent, size, pos, o)


func _prop(prop_name: String, pos := Vector3.ZERO) -> Node3D:
	var node := A.prop(self, prop_name, pos)
	props[prop_name] = node
	return node


func _body(size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)


func _station(id: String, prompt: String, pos: Vector3) -> NightWatchStation:
	var st := NightWatchStation.new()
	st.name = "Station_" + id
	st.station_id = id
	st.prompt_text = prompt
	st.position = pos
	add_child(st)
	prompts[id] = prompt
	stations[id] = st
	return st


func build() -> void:
	_shell()
	for side in [-1.0, 1.0]:
		_vent_side(side)
	_window()
	_console()
	_rack_and_shelves()
	for key in slabs:
		_apply_slab(key)
	set_button("doorL_door", false)
	set_button("doorR_door", false)
	set_button("doorL_light", false)
	set_button("doorR_light", false)
	set_lamp(true)


func _shell() -> void:
	var shell := _prop("Shell")
	_c(shell, Vector3(HALF_W * 2.0 + 0.4, 0.2, HALF_D * 2.0 + 0.4), Vector3(0, -0.1, 0), "Floor", {"solid": true, "kind": "fabric", "tint": Color(0.55, 0.5, 0.65)})
	_c(shell, Vector3(HALF_W * 2.0 + 0.4, 0.2, HALF_D * 2.0 + 0.4), Vector3(0, HEIGHT + 0.1, 0), "Ceiling", {"tint": Color(0.45, 0.45, 0.55)})
	_c(shell, Vector3(HALF_W * 2.0 + 0.4, HEIGHT, 0.2), Vector3(0, HEIGHT * 0.5, HALF_D + 0.1), "WallFront", {"solid": true, "tint": Color(0.6, 0.6, 0.75)})
	# acoustic foam: rows of wedge blocks on the front wall and the ceiling edge
	var foam := _prop("Foam")
	for ix in 11:
		for iy in 4:
			var shade := 0.55 + 0.1 * ((ix + iy) % 2)
			_c(foam, Vector3(0.5, 0.5, 0.12), Vector3(-2.5 + ix * 0.5, 0.7 + iy * 0.55, HALF_D - 0.06), "FoamWedge", {"kind": "fabric", "tint": Color(shade, shade * 0.9, shade * 1.3), "ao": 0.9})
	for z in [-HALF_D + 0.05, HALF_D - 0.05]:
		_c(shell, Vector3(HALF_W * 2.0, 0.2, 0.08), Vector3(0, 0.1, z), "Baseboard", {"tint": Color(0.5, 0.5, 0.55)})
	for x in [-1.4, 1.4]:
		_c(shell, Vector3(1.1, 0.08, 0.5), Vector3(x, HEIGHT - 0.04, 0.2), "CeilingFixture", {"kind": "plastic"})
	_c(shell, Vector3(HALF_W * 2.0, 0.12, 0.12), Vector3(0, HEIGHT - 0.2, HALF_D - 0.3), "PipeBack", {"kind": "metal"})
	_c(shell, Vector3(0.05, 0.05, 0.05), Vector3(2.7, 0.9, HALF_D - 0.1), "LedAlarm", {})


func _vent_side(side: float) -> void:
	var tag := "L" if side < 0.0 else "R"
	var door := "doorL" if side < 0.0 else "doorR"
	var x: float = side * (HALF_W + 0.1)
	var wall := _prop("Wall" + tag)
	var piece := (HALF_D * 2.0 - VENT_W) * 0.5
	_c(wall, Vector3(0.2, HEIGHT, piece), Vector3(x, HEIGHT * 0.5, -HALF_D + piece * 0.5), "Wall%sA" % tag, {"solid": true, "tint": Color(0.6, 0.6, 0.75)})
	_c(wall, Vector3(0.2, HEIGHT, piece), Vector3(x, HEIGHT * 0.5, HALF_D - piece * 0.5), "Wall%sB" % tag, {"solid": true, "tint": Color(0.6, 0.6, 0.75)})
	_c(wall, Vector3(0.2, HEIGHT - VENT_H, VENT_W), Vector3(x, VENT_H + (HEIGHT - VENT_H) * 0.5, 0), "Wall%sTop" % tag, {})
	var frame := _prop("VentFrame" + tag)
	for zz in [-VENT_W * 0.5 - 0.07, VENT_W * 0.5 + 0.07]:
		_c(frame, Vector3(0.34, VENT_H, 0.14), Vector3(x, VENT_H * 0.5, zz), "FramePost", {"tint": Color(0.5, 0.5, 0.55)})
	_c(frame, Vector3(0.34, 0.16, VENT_W + 0.28), Vector3(x, VENT_H + 0.06, 0), "FrameHeader", {"tint": Color(0.5, 0.5, 0.55)})
	_c(frame, Vector3(0.4, 0.05, VENT_W), Vector3(x, 0.025, 0), "Threshold", {"kind": "metal", "tint": Color(0.85, 0.85, 0.9)})
	# the cover: a slatted grille that drops shut
	var slab := Node3D.new()
	slab.name = "Slab" + tag
	slab.set_meta("nw_prop", true)
	slab.position = Vector3(side * HALF_W, SLAB_OPEN_Y, 0.0)
	add_child(slab)
	props["Slab" + tag] = slab
	_c(slab, Vector3(0.12, VENT_H, VENT_W - 0.04), Vector3.ZERO, "SlabBody", {"solid": true, "kind": "metal", "tint": Color(0.7, 0.72, 0.78)})
	for i in 8:
		_c(slab, Vector3(0.16, 0.07, VENT_W - 0.02), Vector3(0, -VENT_H * 0.5 + 0.2 + i * 0.27, 0), "SlabSlat", {"kind": "plastic", "tint": Color(0.5, 0.5, 0.55)})
	slabs[door] = slab
	# the service duct behind it: long, narrow, dim
	var duct := _prop("Duct" + tag)
	var hx: float = side * (HALF_W + 3.25)
	_c(duct, Vector3(6.3, 0.2, 2.2), Vector3(hx, -0.1, 0), "Duct%sFloor" % tag, {"solid": true, "kind": "metal", "tint": Color(0.7, 0.75, 0.85)})
	_c(duct, Vector3(6.3, 0.2, 2.2), Vector3(hx, HEIGHT + 0.1, 0), "Duct%sCeiling" % tag, {"tint": Color(0.5, 0.52, 0.6)})
	for zz in [-1.1, 1.1]:
		_c(duct, Vector3(6.3, HEIGHT, 0.2), Vector3(hx, HEIGHT * 0.5, zz), "Duct%sWall" % tag, {"solid": true, "kind": "metal", "tint": Color(0.65, 0.7, 0.8)})
	_c(duct, Vector3(0.2, HEIGHT, 2.2), Vector3(side * (HALF_W + 6.4), HEIGHT * 0.5, 0), "Duct%sEnd" % tag, {"solid": true, "kind": "metal", "tint": Color(0.5, 0.55, 0.65)})
	for i in 4:
		_c(duct, Vector3(0.12, HEIGHT - 0.1, 2.0), Vector3(side * (HALF_W + 0.8 + i * 1.6), HEIGHT * 0.5, 0), "DuctRib", {"kind": "metal", "tint": Color(0.8, 0.82, 0.9)})
	_body(Vector3(0.3, HEIGHT, 2.2), Vector3(side * HALL_GUARD_X, HEIGHT * 0.5, 0.0))
	var dim := OmniLight3D.new()
	dim.name = "Duct%sGlow" % tag
	dim.light_color = Color(0.5, 0.6, 0.95)
	dim.light_energy = 0.14
	dim.omni_range = 5.0
	dim.position = Vector3(side * (HALF_W + 3.6), 2.4, 0)
	add_child(dim)
	# the panel beside the vent: SEAL (the cover) and a second button (the heater on the left, the fan on the right)
	var panel := _prop("ControlPanel" + tag)
	var px: float = side * (HALF_W - 0.06)
	_c(panel, Vector3(0.1, 0.78, 0.46), Vector3(px, 1.3, 1.55), "PanelHousing", {})
	_c(panel, Vector3(0.05, 0.7, 0.4), Vector3(side * (HALF_W - 0.12), 1.3, 1.55), "PanelFace", {"kind": "plastic"})
	_c(panel, Vector3(0.06, 0.1, 0.28), Vector3(side * (HALF_W - 0.14), 1.74, 1.55), "LabelPlate", {})
	var names := ["SEAL LEFT VENT // SEAL / OPEN", "HEATER // ON / OFF"] if side < 0.0 else ["SEAL RIGHT VENT // SEAL / OPEN", "FAN // ON / OFF"]
	for entry in [["door", 1.47, names[0]], ["light", 1.15, names[1]]]:
		var bx: float = side * (HALF_W - 0.15)
		_c(panel, Vector3(0.05, 0.26, 0.3), Vector3(side * (HALF_W - 0.14), float(entry[1]), 1.55), "Guard" + String(entry[0]).capitalize(), {"kind": "metal", "tint": Color(0.9, 0.9, 0.95)})
		var b := _c(panel, Vector3(0.06, 0.18, 0.22), Vector3(bx, float(entry[1]), 1.55), "Button%s%s" % [tag, String(entry[0]).capitalize()], {"kind": "red" if entry[0] == "door" else "light"})
		button_meshes["%s_%s" % [door, entry[0]]] = b
		_station("%s_%s" % [door, entry[0]], String(entry[2]), Vector3(bx, float(entry[1]), 1.55))


func _window() -> void:
	# the glass window onto the studio (north wall) and the studio behind it
	var wall := _prop("WallBack")
	var gap := 3.2
	var seg := (HALF_W * 2.0 + 0.4 - gap) * 0.5
	for sgn in [-1.0, 1.0]:
		_c(wall, Vector3(seg, HEIGHT, 0.2), Vector3(sgn * (gap * 0.5 + seg * 0.5), HEIGHT * 0.5, -HALF_D - 0.1), "WallBackPiece", {"solid": true, "tint": Color(0.6, 0.6, 0.75)})
	_c(wall, Vector3(gap, 1.0, 0.2), Vector3(0, 0.5, -HALF_D - 0.1), "WallBackSill", {"solid": true, "tint": Color(0.6, 0.6, 0.75)})
	_c(wall, Vector3(gap, 0.5, 0.2), Vector3(0, HEIGHT - 0.25, -HALF_D - 0.1), "WallBackLintel", {"tint": Color(0.6, 0.6, 0.75)})
	var glass := _prop("StudioWindow", Vector3(0, 0, -HALF_D - 0.1))
	_c(glass, Vector3(gap, 1.5, 0.05), Vector3(0, 1.75, 0), "WindowGlass", {"kind": "glass", "tint": Color(0.7, 0.85, 0.9)})
	for x in [-gap * 0.5, 0.0, gap * 0.5]:
		_c(glass, Vector3(0.1, 1.6, 0.1), Vector3(x, 1.75, 0), "WindowMullion", {"kind": "metal"})
	var studio := _prop("Studio", Vector3(0, 0, -HALF_D - 2.2))
	_c(studio, Vector3(5.0, 0.2, 3.6), Vector3(0, -0.1, 0), "StudioFloor", {"kind": "fabric", "tint": Color(0.4, 0.4, 0.5)})
	_c(studio, Vector3(5.0, HEIGHT, 0.2), Vector3(0, HEIGHT * 0.5, -1.8), "StudioWall", {"tint": Color(0.45, 0.45, 0.6)})
	for x in [-2.5, 2.5]:
		_c(studio, Vector3(0.2, HEIGHT, 3.6), Vector3(x, HEIGHT * 0.5, 0), "StudioWall", {"tint": Color(0.45, 0.45, 0.6)})
	_c(studio, Vector3(5.0, 0.2, 3.6), Vector3(0, HEIGHT + 0.1, 0), "StudioCeiling", {"tint": Color(0.35, 0.35, 0.45)})
	_c(studio, Vector3(0.08, 1.5, 0.08), Vector3(-0.8, 0.75, -0.4), "MicStandPole", {"kind": "metal"})
	_c(studio, Vector3(0.14, 0.2, 0.14), Vector3(-0.8, 1.55, -0.4), "MicHead", {"kind": "plastic"})
	_c(studio, Vector3(0.4, 0.04, 0.4), Vector3(-0.8, 0.02, -0.4), "MicBase", {"kind": "metal"})
	_c(studio, Vector3(0.5, 0.5, 0.5), Vector3(1.0, 0.25, -0.6), "StoolSeat", {"kind": "fabric", "tint": Color(1.2, 0.8, 0.8)})
	# the ON AIR lamp above the window
	var sign := _prop("OnAirSign", Vector3(0, 2.75, -HALF_D + 0.1))
	_c(sign, Vector3(1.0, 0.3, 0.06), Vector3.ZERO, "SignPlate", {"kind": "plastic"})
	on_air = _c(sign, Vector3(0.84, 0.18, 0.03), Vector3(0, 0, 0.04), "SignOnAir", {"kind": "red"})


func _console() -> void:
	var desk := _prop("Console", Vector3(0, 0, -1.6))
	_c(desk, Vector3(2.6, 0.08, 0.95), Vector3(0, 0.76, 0), "DeskTop", {})
	for x in [-1.2, 1.2]:
		_c(desk, Vector3(0.1, 0.76, 0.85), Vector3(x, 0.38, 0), "DeskLeg", {})
	_c(desk, Vector3(2.2, 0.5, 0.04), Vector3(0, 0.45, -0.4), "DeskBackPanel", {"tint": Color(0.8, 0.8, 0.8)})
	_body(Vector3(2.6, 0.9, 0.95), Vector3(0, 0.45, -1.6))
	# the mixing board: a sloped block with rows of faders and two level LEDs
	var mixer := _prop("MixingBoard", Vector3(-0.7, 0.8, -1.55))
	_c(mixer, Vector3(1.2, 0.1, 0.55), Vector3(0, 0.05, 0), "MixerBody", {"kind": "plastic"})
	for i in 8:
		_c(mixer, Vector3(0.05, 0.03, 0.22), Vector3(-0.5 + i * 0.14, 0.12, 0.05), "MixerFader", {"kind": "metal", "tint": Color(1.2, 1.2, 1.25)})
		_c(mixer, Vector3(0.1, 0.02, 0.06), Vector3(-0.5 + i * 0.14, 0.11, -0.15), "MixerKnob", {"kind": "red" if i % 3 == 0 else "plastic"})
	_c(mixer, Vector3(0.04, 0.04, 0.04), Vector3(0.52, 0.12, -0.2), "LedMixer", {})
	# the systems monitor: a screen on an arm
	var monitor := _prop("Monitor", Vector3(0.7, 0.0, -2.0))
	_c(monitor, Vector3(0.96, 0.64, 0.09), Vector3(0, 1.2, 0), "MonitorCase", {})
	monitor_screen = _c(monitor, Vector3(0.8, 0.48, 0.02), Vector3(0, 1.2, 0.06), "MonitorScreen", {})
	_c(monitor, Vector3(0.14, 0.4, 0.12), Vector3(0, 0.95, -0.02), "MonitorNeck", {})
	_c(monitor, Vector3(0.4, 0.04, 0.26), Vector3(0, 0.82, 0.0), "MonitorBase", {})
	# the boom microphone and headphones
	var boom := _prop("BoomMic", Vector3(-1.2, 0.8, -1.9))
	_c(boom, Vector3(0.06, 0.8, 0.06), Vector3(0, 0.4, 0), "BoomPost", {"kind": "metal"})
	_c(boom, Vector3(0.7, 0.05, 0.05), Vector3(0.3, 0.8, 0), "BoomArm", {"kind": "metal"})
	_c(boom, Vector3(0.12, 0.16, 0.12), Vector3(0.65, 0.76, 0), "BoomCapsule", {"kind": "plastic"})
	var phones := _prop("Headphones", Vector3(1.1, 0.8, -1.4))
	_c(phones, Vector3(0.3, 0.04, 0.12), Vector3(0, 0.18, 0), "PhonesBand", {"kind": "plastic"})
	for x in [-0.15, 0.15]:
		_c(phones, Vector3(0.1, 0.14, 0.14), Vector3(x, 0.08, 0), "PhonesCup", {"kind": "fabric", "tint": Color(0.8, 0.8, 0.9)})
	# the desk lamp
	var lamp_prop := _prop("DeskLampProp", Vector3(1.0, 0.8, -1.9))
	_c(lamp_prop, Vector3(0.18, 0.04, 0.18), Vector3(0, 0.02, 0), "LampBase", {})
	_c(lamp_prop, Vector3(0.04, 0.22, 0.04), Vector3(0, 0.15, 0), "LampArm", {})
	lamp_shade = _c(lamp_prop, Vector3(0.22, 0.14, 0.22), Vector3(0.1, 0.28, 0), "LampShade", {})
	lamp = OmniLight3D.new()
	lamp.name = "DeskLamp"
	lamp.light_color = Color(1.0, 0.78, 0.5)
	lamp.light_energy = 2.0
	lamp.omni_range = 5.0
	lamp.position = Vector3(1.1, 1.35, -1.6)
	add_child(lamp)
	_station("monitor", "SYSTEMS MONITOR // CAMERAS, LURE, REBOOT", Vector3(0.7, 1.2, -1.95))
	_station("lamp", "DESK LAMP", Vector3(1.0, 1.0, -1.85))
	# the chair
	var chair := _prop("Chair", Vector3(0.0, 0.0, -0.9))
	_c(chair, Vector3(0.46, 0.1, 0.46), Vector3(0, 0.5, 0), "ChairSeat", {"solid": true})
	_c(chair, Vector3(0.44, 0.5, 0.08), Vector3(0, 0.8, 0.2), "ChairBack", {})
	_c(chair, Vector3(0.08, 0.3, 0.08), Vector3(0, 0.3, 0), "ChairColumn", {"kind": "metal"})
	_c(chair, Vector3(0.5, 0.05, 0.08), Vector3(0, 0.1, 0), "ChairBaseA", {"kind": "metal"})
	_c(chair, Vector3(0.08, 0.05, 0.5), Vector3(0, 0.1, 0), "ChairBaseB", {"kind": "metal"})
	_station("chair", "SIT AT THE CONSOLE", Vector3(0.0, 0.0, -0.85))


func _rack_and_shelves() -> void:
	var rack := _prop("PatchRack", Vector3(-2.7, 0.0, -1.7))
	_c(rack, Vector3(0.5, 2.0, 0.7), Vector3(0, 1.0, 0), "RackBody", {"kind": "metal", "tint": Color(0.6, 0.6, 0.68)})
	for i in 6:
		_c(rack, Vector3(0.04, 0.2, 0.6), Vector3(0.26, 0.3 + i * 0.28, 0), "RackUnit", {"kind": "plastic", "tint": Color(0.9, 0.9, 1.0)})
		_c(rack, Vector3(0.03, 0.04, 0.04), Vector3(0.29, 0.35 + i * 0.28, 0.2), "LedRack", {})
	_body(Vector3(0.5, 2.0, 0.7), Vector3(-2.7, 1.0, -1.7))
	var vinyl := _prop("VinylShelf", Vector3(2.7, 0.0, -1.5))
	_c(vinyl, Vector3(0.4, 1.6, 1.4), Vector3(0, 0.8, 0), "VinylShelfBody", {})
	for i in 3:
		_c(vinyl, Vector3(0.42, 0.04, 1.4), Vector3(0, 0.3 + i * 0.5, 0), "VinylShelfBoard", {})
		for j in 5:
			_c(vinyl, Vector3(0.3, 0.3, 0.06), Vector3(0, 0.47 + i * 0.5, -0.5 + j * 0.25), "VinylSleeve", {"kind": ["red", "fabric", "green", "label", "metal"][j], "tint": Color(0.9, 0.9, 1.0)})
	_body(Vector3(0.4, 1.6, 1.4), Vector3(2.7, 0.8, -1.5))
	var clock := _prop("WallClock", Vector3(-1.9, 2.2, HALF_D - 0.1))
	_c(clock, Vector3(0.5, 0.5, 0.05), Vector3.ZERO, "ClockFrame", {"kind": "plastic"})
	_c(clock, Vector3(0.42, 0.42, 0.03), Vector3(0, 0, -0.03), "ClockFace", {})
	var poster := _prop("Poster", Vector3(1.8, 1.9, HALF_D - 0.1))
	_c(poster, Vector3(0.9, 1.2, 0.04), Vector3.ZERO, "PosterFrame", {})
	_c(poster, Vector3(0.78, 1.08, 0.03), Vector3(0, 0, -0.03), "PosterPaper", {"kind": "fabric", "tint": Color(1.2, 0.7, 0.8)})


# --- the things the scene drives (the same surface as the Classic room's) ---------------------------------------------------------

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


func set_light(_key: String, _on: bool) -> void:
	pass   # the booth has no door lights (the LIGHT buttons run the heater and the fan)


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
	(slabs[key] as Node3D).position.y = lerpf(SLAB_OPEN_Y, SLAB_CLOSED_Y, float(slab_progress[key]))


## Where a hunter at a vent stands, from how far into her wait she is: well down the duct, then up to the hatch.
func door_stand(door: String, slot: int, progress := 0.0) -> Vector3:
	var side := -1.0 if door == "doorL" else 1.0
	var near := lerpf(HALF_W + 1.9, HALF_W + 0.55, clampf(progress, 0.0, 1.0))
	return Vector3(side * (near + slot * 1.3), 0.0, -0.4 * slot)
