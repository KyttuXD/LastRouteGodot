class_name MaskOffice
extends NightWatchOfficeBase

## Masked Hours' office (OFFICE CONTRACT, docs/NIGHT_WATCH_OFFICES.md): `front_office`, the night guard's small office at the end of the main hall, in the FNAF 2 manner: a
## little room with NO doors, one wide opening straight onto the main hall (a velvet rope keeps you in), a desk right in front of you with the monitor, the mask and the music
## box, a vent grate in each side wall (the left and right air vents) and a decorative front vent above the opening. Kids' drawings, a clock, a fan and a pizza box on the desk.
## It is its own room (not the Classic security room): the hall runs 15 m straight ahead (-z); the wing behind it is MaskWorld. Lights on at once: the desk lamp (off at the
## start); the hall light and the vent lights are held. Real lights: the lamp, the hall light, two vent beams: at most the lamp and one held light are ever on together.

const A := preload("res://game/night_watch/night_watch_art.gd")
const HALF_W := 3.4
const FRONT_Z := -1.8
const BACK_Z := 3.6
const HEIGHT := 3.7
const OPENING := 2.5      # half-width of the opening onto the hall
const SPAWN := Vector3(0.0, 0.0, 1.35)
const WALL := Color(1.8, 1.25, 1.9)
const WOOD := Color(1.6, 1.1, 0.8)
const PAPER := Color(1.8, 1.8, 1.6)

var lamp: OmniLight3D
var lamp_shade: MeshInstance3D
var monitor_screen: MeshInstance3D
var button_meshes := {}
var door_lights := {}    # "hall" -> SpotLight3D (the hall light)
var vent_beams := {}     # "L" / "R" -> SpotLight3D
var glints := {}         # "ventL" / "ventR" -> Node3D (eyeshine in the dark vent)
var box_gauge: MeshInstance3D
var mask_prop: Node3D
var prompts := {}
var fan_blades: Node3D


func _make_spec() -> NightWatchOfficeSpec:
	return make_spec()


static func make_spec() -> NightWatchOfficeSpec:
	return NightWatchOfficeSpec.make({
		"id": "front_office", "title": "Night guard's office", "mode_ids": ["mask"],
		"footprint": Rect2(-HALF_W + 0.5, FRONT_Z + 0.5, HALF_W * 2.0 - 1.0, BACK_Z - FRONT_Z - 1.0),
		"spawn": SPAWN,
		"entrances": [
			{"id": "hall", "kind": "opening", "position": Vector3(0.0, 0.0, FRONT_Z), "outward": Vector3(0, 0, -1), "sim_room": "hall", "blockable": false},
			{"id": "ventL", "kind": "vent", "position": Vector3(-HALF_W, 0.0, 0.6), "outward": Vector3(-1, 0, 0), "sim_room": "ventL", "blockable": false},
			{"id": "ventR", "kind": "vent", "position": Vector3(HALF_W, 0.0, 0.6), "outward": Vector3(1, 0, 0), "sim_room": "ventR", "blockable": false},
		],
		"required_stations": ["monitor", "chair", "lamp", "mask", "musicbox", "ventL", "ventR", "hall_light"],
		"has_monitor": true,
		"mood": {"kind": "dusk", "ambient": Color(0.36, 0.38, 0.55), "lamp": Color(1.0, 0.82, 0.55), "accent": Color(1.0, 0.55, 0.2)},
		"tone_cue": "presence",
		"controls": ["nw_door_left", "nw_monitor", "nw_lamp", "nw_light_left", "nw_light_right", "nw_door_right"],
		"references": {"2d_screenshot": "docs/night_watch_offices/front_office_2d.png"},
	})


func _c(parent: Node3D, size: Vector3, pos: Vector3, node_name: String, opts := {}) -> MeshInstance3D:
	var o: Dictionary = opts.duplicate()
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


func _station(id: String, prompt: String, pos: Vector3, focus := Vector3.ZERO) -> NightWatchStation:
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
	_build_desk()
	_build_vents()
	_build_hall_rope()
	_build_decor()
	set_lamp(false)


func set_lamp(on: bool) -> void:
	lamp.visible = on
	lamp_shade.material_override = A.material("light", Color.WHITE if on else Color(0.35, 0.3, 0.25), on)


## The hall light (key "hall") is a held spotlight down the main hall.
func set_light(key: String, on: bool) -> void:
	if door_lights.has(key):
		(door_lights[key] as SpotLight3D).visible = on


func set_button(id: String, on: bool) -> void:
	var mesh := button_meshes.get(id) as MeshInstance3D
	if mesh != null:
		mesh.material_override = A.material("light" if on else "plastic", Color.WHITE, on)


## The gauge bar on the music box: its length is the winding left.
func set_box(percent: float) -> void:
	if box_gauge != null:
		box_gauge.scale.x = clampf(percent / 100.0, 0.02, 1.0)
		box_gauge.position.x = -0.15 * (1.0 - box_gauge.scale.x)


func _process(delta: float) -> void:
	if fan_blades != null:
		fan_blades.rotation.y += delta * 9.0


# --- the shell: a small room open to the hall -----------------------------------------------------------------------------------------

func _build_shell() -> void:
	var shell := _prop("Shell")
	var w := HALF_W * 2.0 + 0.4
	var d := BACK_Z - FRONT_Z + 0.4
	_c(shell, Vector3(w, 0.2, d), Vector3(0, -0.1, (BACK_Z + FRONT_Z) * 0.5), "Floor", {"solid": true, "tint": Color(1.5, 1.1, 1.5)})
	_c(shell, Vector3(w, 0.2, d), Vector3(0, HEIGHT + 0.1, (BACK_Z + FRONT_Z) * 0.5), "Ceiling", {"tint": Color(0.9, 0.8, 1.1)})
	# the south wall, the two side walls (the vents are low in them) and the north wall around the opening with a header above it
	_c(shell, Vector3(w, HEIGHT, 0.2), Vector3(0, HEIGHT * 0.5, BACK_Z + 0.1), "WallBack", {"solid": true, "tint": WALL})
	for sx in [-1.0, 1.0]:
		_c(shell, Vector3(0.2, HEIGHT, BACK_Z - FRONT_Z + 0.2), Vector3(sx * (HALF_W + 0.1), HEIGHT * 0.5, (BACK_Z + FRONT_Z) * 0.5), "WallSide", {"solid": true, "tint": WALL})
		_c(shell, Vector3(HALF_W - OPENING + 0.2, HEIGHT, 0.2), Vector3(sx * (OPENING + (HALF_W - OPENING) * 0.5 + 0.1), HEIGHT * 0.5, FRONT_Z - 0.1), "WallFront", {"solid": true, "tint": WALL})
	_c(shell, Vector3(OPENING * 2.0, HEIGHT - 2.5, 0.2), Vector3(0, 2.5 + (HEIGHT - 2.5) * 0.5, FRONT_Z - 0.1), "WallHeader", {"tint": WALL})
	# baseboards, an orange stripe round the room, a crown strip
	for sx in [-1.0, 1.0]:
		_c(shell, Vector3(0.08, 0.22, BACK_Z - FRONT_Z), Vector3(sx * (HALF_W - 0.04), 0.11, (BACK_Z + FRONT_Z) * 0.5), "Baseboard", {"tint": Color(1.3, 0.9, 1.1)})
		_c(shell, Vector3(0.05, 0.1, BACK_Z - FRONT_Z), Vector3(sx * (HALF_W - 0.03), 1.1, (BACK_Z + FRONT_Z) * 0.5), "StripeOrange", {"kind": "label", "tint": Color(1.9, 1.0, 0.45)})
	_c(shell, Vector3(HALF_W * 2.0, 0.22, 0.08), Vector3(0, 0.11, BACK_Z - 0.04), "Baseboard", {"tint": Color(1.3, 0.9, 1.1)})
	_c(shell, Vector3(HALF_W * 2.0, 0.1, 0.05), Vector3(0, 1.1, BACK_Z - 0.03), "StripeOrange", {"kind": "label", "tint": Color(1.9, 1.0, 0.45)})
	for x in [-2.0, 2.0]:
		_c(shell, Vector3(1.0, 0.08, 0.5), Vector3(x, HEIGHT - 0.04, 0.3), "CeilingFixture", {"kind": "plastic"})
		_c(shell, Vector3(0.8, 0.02, 0.3), Vector3(x, HEIGHT - 0.1, 0.3), "CeilingLens", {"kind": "glass", "tint": Color(0.6, 0.55, 0.7)})
	# the front vent: a decorative grille above the opening (sealed; nothing comes out of it in this mode)
	var front := _prop("VentFront", Vector3(0.0, 2.85, FRONT_Z))
	_c(front, Vector3(1.0, 0.5, 0.1), Vector3(0, 0, -0.05), "VentFrame", {"kind": "metal", "tint": Color(0.5, 0.5, 0.6)})
	for i in 4:
		_c(front, Vector3(0.9, 0.04, 0.06), Vector3(0, -0.15 + i * 0.1, 0.02), "VentLouver", {"kind": "metal", "tint": Color(0.4, 0.4, 0.5)})


# --- the desk: monitor, mask, music box, lamp, fan -------------------------------------------------------------------------------------

func _build_desk() -> void:
	var desk := _prop("Desk", Vector3(0.0, 0.0, -0.5))
	_c(desk, Vector3(2.5, 0.08, 0.85), Vector3(0, 0.76, 0), "DeskTop", {"kind": "wood", "tint": WOOD})
	_c(desk, Vector3(2.54, 0.04, 0.89), Vector3(0, 0.8, 0), "DeskEdge", {"kind": "wood", "tint": Color(1.9, 1.3, 0.9)})
	for x in [-1.15, 1.15]:
		_c(desk, Vector3(0.1, 0.76, 0.75), Vector3(x, 0.38, 0), "DeskLeg", {"kind": "wood", "tint": WOOD})
	_c(desk, Vector3(2.2, 0.55, 0.04), Vector3(0, 0.45, 0.38), "DeskFrontPanel", {"kind": "wood", "tint": Color(1.3, 0.9, 0.7)})
	_body(Vector3(2.5, 0.85, 0.85), Vector3(0.0, 0.42, -0.5))
	# the monitor (left), keyboard, papers, a pizza box
	var monitor := _prop("Monitor", Vector3(-0.65, 0.8, -0.65))
	_c(monitor, Vector3(0.78, 0.55, 0.1), Vector3(0, 0.32, 0), "MonitorBody", {"kind": "plastic"})
	monitor_screen = _c(monitor, Vector3(0.68, 0.45, 0.02), Vector3(0, 0.32, 0.06), "MonitorScreen", {})
	_c(monitor, Vector3(0.2, 0.06, 0.2), Vector3(0, 0.03, 0), "MonitorFoot", {"kind": "plastic"})
	var kb := _prop("Keyboard", Vector3(-0.65, 0.8, -0.25))
	_c(kb, Vector3(0.5, 0.03, 0.18), Vector3(0, 0.015, 0), "KeyboardBody", {"kind": "plastic", "tint": Color(1.2, 1.2, 1.3)})
	var papers := _prop("Papers", Vector3(0.0, 0.8, -0.7))
	for i in 3:
		_c(papers, Vector3(0.32, 0.01, 0.4), Vector3(0.0, 0.006 + i * 0.01, 0), "PaperSheet", {"kind": "label", "tint": PAPER, "ao": 1.0})
	var pizza := _prop("PizzaBox", Vector3(0.95, 0.8, -0.2))
	_c(pizza, Vector3(0.4, 0.06, 0.4), Vector3(0, 0.03, 0), "PizzaBoxBody", {"kind": "wood", "tint": Color(1.8, 1.5, 1.1)})
	# the fan on the desk (its blades turn)
	var fan := _prop("DeskFan", Vector3(0.45, 0.8, -0.75))
	_c(fan, Vector3(0.18, 0.04, 0.18), Vector3(0, 0.02, 0), "FanBase", {"kind": "plastic"})
	_c(fan, Vector3(0.04, 0.28, 0.04), Vector3(0, 0.18, 0), "FanStem", {"kind": "metal"})
	fan_blades = Node3D.new()
	fan_blades.name = "FanBlades"
	fan_blades.position = Vector3(0, 0.34, 0.05)
	fan.add_child(fan_blades)
	_c(fan_blades, Vector3(0.34, 0.02, 0.06), Vector3.ZERO, "FanBlade", {"kind": "plastic", "tint": Color(1.5, 1.5, 1.6)})
	_c(fan_blades, Vector3(0.06, 0.02, 0.34), Vector3.ZERO, "FanBlade", {"kind": "plastic", "tint": Color(1.5, 1.5, 1.6)})
	# the lamp (right)
	var lamp_prop := _prop("DeskLampProp", Vector3(0.95, 0.8, -0.65))
	_c(lamp_prop, Vector3(0.18, 0.04, 0.18), Vector3(0, 0.02, 0), "LampBase", {"kind": "metal"})
	_c(lamp_prop, Vector3(0.04, 0.22, 0.04), Vector3(0, 0.15, 0), "LampArm", {"kind": "metal"})
	lamp_shade = _c(lamp_prop, Vector3(0.22, 0.14, 0.22), Vector3(0.0, 0.28, 0), "LampShade", {})
	lamp = OmniLight3D.new()
	lamp.name = "DeskLamp"
	lamp.light_color = Color(1.0, 0.82, 0.55)
	lamp.light_energy = 2.2
	lamp.omni_range = 5.0
	lamp.position = Vector3(0.95, 1.35, -0.5)
	add_child(lamp)
	# the mask and the music box
	mask_prop = _prop("MaskProp", Vector3(0.3, 0.8, -0.35))
	_c(mask_prop, Vector3(0.22, 0.28, 0.05), Vector3(0, 0.16, 0), "MaskFace", {"kind": "plastic", "tint": Color(1.8, 1.75, 1.6)})
	_c(mask_prop, Vector3(0.14, 0.04, 0.03), Vector3(0, 0.2, 0.03), "MaskEyes", {"kind": "plastic", "tint": Color(0.25, 0.25, 0.3)})
	var box := _prop("MusicBoxProp", Vector3(-1.1, 0.8, -0.3))
	_c(box, Vector3(0.42, 0.22, 0.3), Vector3(0, 0.11, 0), "BoxMusicBody", {"kind": "wood", "tint": Color(1.2, 0.9, 1.1)})
	_c(box, Vector3(0.44, 0.05, 0.32), Vector3(0, 0.24, 0), "BoxMusicLid", {"kind": "wood", "tint": Color(1.3, 1.0, 1.2)})
	_c(box, Vector3(0.05, 0.16, 0.05), Vector3(0.27, 0.16, 0), "HandleCrank", {"kind": "metal"})
	box_gauge = _c(box, Vector3(0.3, 0.03, 0.03), Vector3(0, 0.3, 0.14), "GlowGauge", {})
	# the chair behind the desk
	var chair := _prop("Chair", Vector3(0.0, 0.0, 0.55))
	_c(chair, Vector3(0.5, 0.08, 0.5), Vector3(0, 0.46, 0), "ChairSeat", {"kind": "fabric", "tint": Color(1.6, 0.6, 0.6)})
	_c(chair, Vector3(0.5, 0.55, 0.08), Vector3(0, 0.78, 0.24), "ChairBack", {"kind": "fabric", "tint": Color(1.6, 0.6, 0.6)})
	_c(chair, Vector3(0.06, 0.4, 0.06), Vector3(0, 0.22, 0), "ChairStem", {"kind": "metal"})
	_c(chair, Vector3(0.5, 0.04, 0.5), Vector3(0, 0.03, 0), "ChairBase", {"kind": "metal"})
	# the stations
	_station("monitor", "MONITOR // CAMERAS", Vector3(-0.65, 1.1, -0.65))
	_station("lamp", "DESK LAMP", Vector3(0.95, 1.0, -0.65))
	_station("mask", "MASK // PUT ON / TAKE OFF", Vector3(0.3, 0.95, -0.35))
	_station("musicbox", "MUSIC BOX // HOLD TO WIND", Vector3(-1.1, 0.95, -0.3))
	_station("chair", "SIT AT DESK", Vector3(0.0, 0.0, 0.5), Vector3(0.0, 0.62, 0.0))


# --- the side vents and the hall light ---------------------------------------------------------------------------------------------------

func _build_vents() -> void:
	for side in [-1.0, 1.0]:
		var left: bool = side < 0.0
		var vent := _prop("VentHatch" if left else "VentHatchR", Vector3(side * HALF_W, 0.45, 0.6))
		_c(vent, Vector3(0.1, 0.54, 0.84), Vector3(-side * 0.05, 0, 0), "VentFrame", {"solid": true})
		for i in 5:
			_c(vent, Vector3(0.06, 0.035, 0.7), Vector3(-side * 0.12, -0.2 + i * 0.1, 0), "VentLouver", {"kind": "metal", "tint": Color(0.4, 0.4, 0.5)})
		for sz in [-0.38, 0.38]:
			for sy in [-0.24, 0.24]:
				_c(vent, Vector3(0.05, 0.05, 0.05), Vector3(-side * 0.13, sy, sz), "VentScrew", {"kind": "metal", "tint": Color(1.3, 1.3, 1.3)})
		_station("ventL" if left else "ventR", ("LEFT" if left else "RIGHT") + " VENT // HOLD FOR LIGHT", Vector3(side * (HALF_W - 0.2), 0.45, 0.6))
		var key := "L" if left else "R"
		var beam := SpotLight3D.new()
		beam.name = "VentBeam" + key
		beam.light_color = Color(1.0, 0.97, 0.85)
		beam.light_energy = 6.0
		beam.spot_range = 5.0
		beam.spot_angle = 38.0
		beam.position = Vector3(side * 0.7, 1.5, 1.7)
		beam.look_at_from_position(beam.position, Vector3(side * HALF_W, 0.6, 0.6), Vector3.UP)
		beam.visible = false
		add_child(beam)
		vent_beams[key] = beam
		var glint := Node3D.new()
		glint.name = "VentGlint" + key
		glint.position = Vector3(side * (HALF_W - 0.2), 0.5, 0.6)
		add_child(glint)
		for gz in [-0.12, 0.12]:
			_c(glint, Vector3(0.04, 0.04, 0.06), Vector3(0, 0, gz), "GlowEye", {})
		glint.visible = false
		glints["vent" + key] = glint


func _build_hall_rope() -> void:
	# a velvet rope across the opening (the player stays in the office), a hall light switch on the wall beside it and the hall light itself
	var rope := _prop("HallRope", Vector3(0.0, 0.0, FRONT_Z + 0.1))
	for x in [-OPENING + 0.1, 0.0, OPENING - 0.1]:
		_c(rope, Vector3(0.1, 1.0, 0.1), Vector3(x, 0.5, 0), "PostRope", {"kind": "metal", "tint": Color(1.6, 1.4, 0.8)})
		_c(rope, Vector3(0.18, 0.08, 0.18), Vector3(x, 1.02, 0), "KnobRope", {"kind": "metal", "tint": Color(1.7, 1.5, 0.8)})
	for seg in [[-OPENING * 0.5, 0.0], [OPENING * 0.5, 0.0]]:
		_c(rope, Vector3(OPENING - 0.2, 0.06, 0.06), Vector3(float(seg[0]), 0.88, 0), "RopeVelvet", {"kind": "fabric", "tint": Color(1.9, 0.3, 0.4)})
	_body(Vector3(OPENING * 2.0, 1.4, 0.2), Vector3(0.0, 0.7, FRONT_Z + 0.1))
	var panel := _prop("HallSwitch", Vector3(OPENING + 0.2, 1.4, FRONT_Z + 0.05))
	_c(panel, Vector3(0.3, 0.4, 0.06), Vector3.ZERO, "PanelFace", {"kind": "metal"})
	var b := _c(panel, Vector3(0.18, 0.18, 0.06), Vector3(0, 0, 0.05), "ButtonHall", {"kind": "plastic"})
	button_meshes["hall_light"] = b
	_station("hall_light", "HALL LIGHT // HOLD", Vector3(OPENING + 0.2, 1.4, FRONT_Z + 0.4))
	var spot := SpotLight3D.new()
	spot.name = "HallLight"
	spot.light_color = Color(1.0, 0.97, 0.85)
	spot.light_energy = 9.0
	spot.spot_range = 20.0
	spot.spot_angle = 24.0
	spot.position = Vector3(0.0, 2.7, FRONT_Z + 0.3)
	spot.look_at_from_position(spot.position, Vector3(0.0, 0.6, -14.0), Vector3.UP)
	spot.visible = false
	add_child(spot)
	door_lights["hall"] = spot


func _build_decor() -> void:
	# kids' drawings and a poster on the back and side walls, a clock, a balloon on a string, a stack of party hats
	var art := _prop("Drawings", Vector3(0.0, 1.8, BACK_Z))
	for i in 5:
		var tint: Color = MaskWorld.BALLOON_TINTS[i]
		_c(art, Vector3(0.45, 0.6, 0.03), Vector3(-2.0 + i * 1.0, (i % 2) * 0.25 - 0.1, -0.03), "DrawingPaper", {"kind": "label", "tint": PAPER * Color(0.9, 0.9, 0.9), "ao": 1.0})
		_c(art, Vector3(0.3, 0.3, 0.02), Vector3(-2.0 + i * 1.0, (i % 2) * 0.25 - 0.1, -0.06), "DrawingBlob", {"kind": "fabric", "tint": tint})
	var clock := _prop("WallClock", Vector3(2.5, 2.5, BACK_Z))
	_c(clock, Vector3(0.58, 0.58, 0.05), Vector3(0, 0, -0.03), "ClockFrame", {"kind": "plastic"})
	_c(clock, Vector3(0.5, 0.5, 0.03), Vector3(0, 0, -0.06), "ClockFace", {})
	_c(clock, Vector3(0.03, 0.18, 0.02), Vector3(0, 0.07, -0.09), "ClockHandA", {"kind": "plastic"})
	_c(clock, Vector3(0.14, 0.03, 0.02), Vector3(0.05, 0, -0.09), "ClockHandB", {"kind": "plastic"})
	var poster := _prop("PosterShow", Vector3(-HALF_W, 1.9, -0.4))
	_c(poster, Vector3(0.04, 1.0, 0.75), Vector3(0.03, 0, 0), "PosterPaper", {"kind": "fabric", "tint": Color(1.9, 1.0, 0.5)})
	_c(poster, Vector3(0.04, 0.2, 0.5), Vector3(0.06, 0.32, 0), "PosterTitle", {"kind": "label", "tint": Color(0.9, 0.9, 0.9)})
	var balloon := _prop("Balloon", Vector3(-2.8, 0.0, 2.9))
	_c(balloon, Vector3(0.02, 1.8, 0.02), Vector3(0, 0.9, 0), "StringBalloon", {"kind": "plastic", "tint": Color(1.6, 1.6, 1.6)})
	_c(balloon, Vector3(0.42, 0.5, 0.42), Vector3(0, 2.0, 0), "BalloonCube", {"kind": "fabric", "tint": MaskWorld.BALLOON_TINTS[0]})
	var hats := _prop("PartyHats", Vector3(2.8, 0.0, 2.9))
	for i in 3:
		_c(hats, Vector3(0.3, 0.26 - i * 0.04, 0.3), Vector3(0, 0.13 + i * 0.26, 0), "HatCone", {"kind": "fabric", "tint": MaskWorld.BALLOON_TINTS[i + 1]})
