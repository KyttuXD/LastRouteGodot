class_name MaskOffice
extends NightWatchOffice

## Masked Hours' office (OFFICE CONTRACT, docs/NIGHT_WATCH_OFFICES.md): `front_office`, the front office / reception at the end of the wing, from the 2D
## picture (assets/offices/mask.png): a purple room with a checkerboard floor, an orange stripe along the walls and dark vent grates. There are no doors:
## the right-hand doorway is the hall the hall hunters walk in by, the left one is sealed, and the two vents (back wall) are the other ways in. On the
## desk: the monitor, the mask and the music box. It is the Classic room's mechanics (desk, chair, lamp, the hall light on the right panel) under its own
## shell, wall props and stations. Lights on at once: the desk lamp only (the vent lights and the hall light are held).

const PURPLE := Color(1.15, 0.85, 1.6)
const MAUVE := Color(1.0, 0.75, 1.35)
const ORANGE := Color(1.9, 1.0, 0.45)

var vent_beams := {}    # "L" / "R" -> SpotLight3D
var glints := {}        # "ventL" / "ventR" -> Node3D (eyeshine in the dark vent)
var box_gauge: MeshInstance3D
var mask_prop: Node3D


func _make_spec() -> NightWatchOfficeSpec:
	return make_spec()


static func make_spec() -> NightWatchOfficeSpec:
	return NightWatchOfficeSpec.make({
		"id": "front_office", "title": "Front office", "mode_ids": ["mask"],
		"footprint": Rect2(-HALF_W + 0.5, -HALF_D + 0.5, HALF_W * 2.0 - 1.0, HALF_D * 2.0 - 1.0),
		"spawn": SPAWN,
		"entrances": [
			{"id": "hall", "kind": "opening", "position": Vector3(HALF_W, 0.0, 0.0), "outward": Vector3(1, 0, 0), "sim_room": "hall", "blockable": false},
			{"id": "ventL", "kind": "vent", "position": Vector3(-2.3, 0.0, -HALF_D + 0.3), "outward": Vector3(0, 0, -1), "sim_room": "ventL", "blockable": false},
			{"id": "ventR", "kind": "vent", "position": Vector3(2.3, 0.0, -HALF_D + 0.3), "outward": Vector3(0, 0, -1), "sim_room": "ventR", "blockable": false},
		],
		"required_stations": ["monitor", "chair", "lamp", "mask", "musicbox", "vent", "ventR", "doorR_light"],
		"has_monitor": true,
		"mood": {"kind": "dusk", "ambient": Color(0.36, 0.38, 0.55), "lamp": Color(1.0, 0.82, 0.55), "accent": Color(1.0, 0.55, 0.2)},
		"tone_cue": "presence",
		"controls": ["nw_door_left", "nw_monitor", "nw_lamp", "nw_light_left", "nw_light_right", "nw_door_right"],
		"references": {"2d_screenshot": "docs/night_watch_offices/front_office_2d.png"},
	})


func build() -> void:
	super.build()
	snap_slabs({"doorL": true, "doorR": false})   # no doors: the left doorway is sealed, the right one is the hall
	for id in ["doorL_door", "doorL_light", "doorR_door"]:
		var st := stations[id] as NightWatchStation
		st.disabled = true
		st.prompt_text = ""
		var mesh := button_meshes.get(id) as MeshInstance3D
		if mesh != null:
			mesh.visible = false
	(stations["doorR_light"] as NightWatchStation).prompt_text = "HALL LIGHT // HOLD"
	if props.has("ControlPanelL"):
		(props["ControlPanelL"] as Node3D).visible = false
	(door_lights["doorL"] as SpotLight3D).visible = false
	# the vent lights (held) and the eyeshine in the dark vents
	for side in ["L", "R"]:
		var x := -2.3 if side == "L" else 2.3
		var beam := SpotLight3D.new()
		beam.name = "VentBeam" + side
		beam.light_color = Color(1.0, 0.97, 0.85)
		beam.light_energy = 6.0
		beam.spot_range = 5.0
		beam.spot_angle = 38.0
		beam.position = Vector3(x * 0.55, 1.5, 1.2)
		beam.look_at_from_position(beam.position, Vector3(x, 0.6, -HALF_D + 0.3), Vector3.UP)
		beam.visible = false
		add_child(beam)
		vent_beams[side] = beam
		var glint := Node3D.new()
		glint.name = "VentGlint" + side
		glint.position = Vector3(x, 0.5, -HALF_D + 0.2)
		add_child(glint)
		for gx in [-0.12, 0.12]:
			A.box(glint, Vector3(0.06, 0.04, 0.04), Vector3(gx, 0, 0), {"name": "GlowEye"})
		glint.visible = false
		glints["vent" + side] = glint
	# the mask on the desk and the music box beside it
	mask_prop = _prop("MaskProp", Vector3(0.55, 0.8, -1.45))
	_c(mask_prop, Vector3(0.22, 0.28, 0.05), Vector3(0, 0.16, 0), "MaskFace", {"kind": "plastic", "tint": Color(1.8, 1.75, 1.6)})
	_c(mask_prop, Vector3(0.14, 0.04, 0.03), Vector3(0, 0.2, 0.03), "MaskEyes", {"kind": "plastic", "tint": Color(0.25, 0.25, 0.3)})
	_station("mask", "MASK // PUT ON / TAKE OFF", Vector3(0.3, 0.3, 0.2), Vector3(0.55, 0.95, -1.45))
	var box := _prop("MusicBoxProp", Vector3(-1.3, 0.8, -2.0))
	_c(box, Vector3(0.42, 0.22, 0.3), Vector3(0, 0.11, 0), "BoxMusicBody", {"kind": "wood", "tint": Color(1.2, 0.9, 1.1)})
	_c(box, Vector3(0.44, 0.05, 0.32), Vector3(0, 0.24, 0), "BoxMusicLid", {"kind": "wood", "tint": Color(1.3, 1.0, 1.2)})
	_c(box, Vector3(0.05, 0.16, 0.05), Vector3(0.27, 0.16, 0), "HandleCrank", {"kind": "metal"})
	box_gauge = _c(box, Vector3(0.3, 0.03, 0.03), Vector3(0, 0.3, 0.14), "GlowGauge", {})
	_station("musicbox", "MUSIC BOX // HOLD TO WIND", Vector3(0.5, 0.3, 0.4), Vector3(-1.3, 0.95, -2.0))
	set_lamp(false)


## The gauge bar on the music box: its length is the winding left.
func set_box(percent: float) -> void:
	if box_gauge != null:
		box_gauge.scale.x = clampf(percent / 100.0, 0.02, 1.0)
		box_gauge.position.x = -0.15 * (1.0 - box_gauge.scale.x)


# --- the shell: purple walls, an orange stripe, a checkerboard floor -------------------------------------------------------

func _build_shell() -> void:
	var shell := _prop("Shell")
	var w := HALF_W * 2.0 + 0.4
	var d := HALF_D * 2.0 + 0.4
	_c(shell, Vector3(w, 0.2, d), Vector3(0, -0.1, 0), "Floor", {"solid": true, "tint": Color(0.7, 0.6, 1.0)})
	# the checkerboard: one-metre tiles, every other one lighter
	for ix in 6:
		for iz in 5:
			if (ix + iz) % 2 == 0:
				_c(shell, Vector3(1.0, 0.012, 1.0), Vector3(-2.5 + ix, 0.006, -2.0 + iz), "FloorTile", {"kind": "floor", "tint": Color(1.6, 1.3, 2.2)})
	_c(shell, Vector3(w, 0.2, d), Vector3(0, HEIGHT + 0.1, 0), "Ceiling", {"tint": Color(0.5, 0.45, 0.7)})
	_c(shell, Vector3(w, HEIGHT, 0.2), Vector3(0, HEIGHT * 0.5, -HALF_D - 0.1), "WallBack", {"solid": true, "tint": PURPLE})
	_c(shell, Vector3(w, HEIGHT, 0.2), Vector3(0, HEIGHT * 0.5, HALF_D + 0.1), "WallFront", {"solid": true, "tint": MAUVE})
	# the orange stripe along the back and front walls, a crown strip and a striped curtain behind the desk
	for z in [-HALF_D + 0.04, HALF_D - 0.04]:
		_c(shell, Vector3(HALF_W * 2.0, 0.22, 0.08), Vector3(0, 0.11, z), "Baseboard", {"tint": Color(0.7, 0.6, 0.9)})
		_c(shell, Vector3(HALF_W * 2.0, 0.1, 0.05), Vector3(0, 1.1, z), "StripeOrange", {"kind": "label", "tint": ORANGE})
		_c(shell, Vector3(HALF_W * 2.0, 0.12, 0.08), Vector3(0, HEIGHT - 0.06, z), "CrownTrim", {"tint": Color(0.8, 0.7, 1.0)})
	for i in 7:
		_c(shell, Vector3(0.28, 1.9, 0.06), Vector3(-1.4 + i * 0.47, 1.9, -HALF_D + 0.1), "CurtainStrip", {"kind": "fabric", "tint": Color(1.6, 0.8 + 0.5 * (i % 2), 1.4)})
	_c(shell, Vector3(HALF_W * 2.0, 0.12, 0.12), Vector3(0, HEIGHT - 0.2, -HALF_D + 0.2), "PipeBack", {"kind": "metal"})
	for x in [-1.4, 1.4]:
		_c(shell, Vector3(1.1, 0.08, 0.5), Vector3(x, HEIGHT - 0.04, 0.2), "CeilingFixture", {"kind": "plastic"})
		_c(shell, Vector3(0.9, 0.02, 0.3), Vector3(x, HEIGHT - 0.1, 0.2), "CeilingLens", {"kind": "glass", "tint": Color(0.5, 0.45, 0.6)})
	_c(shell, Vector3(0.05, 0.05, 0.05), Vector3(2.7, 0.9, HALF_D - 0.1), "LedAlarm", {})
	_c(shell, Vector3(1.6, 0.02, 1.0), Vector3(0, 0.02, -1.1), "FloorMat", {"tint": Color(1.2, 0.8, 1.3)})


# --- the wall props: two vent grates, a mask rack, a reception counter, a sign, a clock --------------------------------------

func _build_wall_props() -> void:
	for side in [-1.0, 1.0]:
		var vent := _prop("VentHatch" if side < 0.0 else "VentHatchR", Vector3(side * 2.3, 0.45, -HALF_D))
		_c(vent, Vector3(0.84, 0.54, 0.1), Vector3(0, 0, 0.05), "VentFrame", {"solid": true})
		for i in 5:
			_c(vent, Vector3(0.7, 0.035, 0.06), Vector3(0, -0.2 + i * 0.1, 0.12), "VentLouver", {"kind": "metal", "tint": Color(0.4, 0.4, 0.5)})
		for sx in [-0.38, 0.38]:
			for sy in [-0.24, 0.24]:
				_c(vent, Vector3(0.05, 0.05, 0.05), Vector3(sx, sy, 0.13), "VentScrew", {"kind": "metal", "tint": Color(1.3, 1.3, 1.3)})
		var left: bool = side < 0.0
		_station("vent" if left else "ventR", ("LEFT" if left else "RIGHT") + " VENT // HOLD FOR LIGHT", Vector3(0.9, 0.6, 0.3), Vector3(side * 2.3, 0.45, -HALF_D + 0.2))
	# a rack of masks on the left wall beside the sealed doorway
	var rack := _prop("MaskRack", Vector3(-HALF_W + 0.1, 1.5, 1.7))
	_c(rack, Vector3(0.06, 1.0, 1.1), Vector3(0, 0, 0), "RackBoard", {"kind": "wood", "tint": Color(1.2, 0.8, 0.9)})
	for i in 4:
		for j in 2:
			_c(rack, Vector3(0.05, 0.3, 0.22), Vector3(0.06, -0.22 + j * 0.46, -0.4 + i * 0.27), "RackMask", {"kind": "plastic", "tint": Color(1.7 + 0.1 * j, 1.65, 1.55)})
			_c(rack, Vector3(0.04, 0.05, 0.14), Vector3(0.09, -0.15 + j * 0.46, -0.4 + i * 0.27), "RackMaskEyes", {"kind": "plastic", "tint": Color(0.25, 0.25, 0.3)})
	# the reception counter in the front-right corner, with a bell
	var counter := _prop("Counter", Vector3(2.0, 0.0, 1.9))
	_c(counter, Vector3(1.9, 0.96, 0.6), Vector3(0, 0.48, 0), "CounterBody", {"kind": "wood", "tint": Color(1.3, 0.9, 1.0)})
	_c(counter, Vector3(2.0, 0.07, 0.7), Vector3(0, 1.0, 0), "CounterTop", {"kind": "wood", "tint": Color(1.5, 1.2, 1.1)})
	_c(counter, Vector3(0.18, 0.1, 0.18), Vector3(0.3, 1.09, 0), "BellCounter", {"kind": "metal", "tint": Color(1.6, 1.4, 0.8)})
	_body(self, Vector3(1.9, 0.96, 0.6), Vector3(2.0, 0.48, 1.9), 1)
	# a sign over the desk and a clock
	var sign_prop := _prop("FrontSign", Vector3(0, 2.55, -HALF_D))
	_c(sign_prop, Vector3(1.4, 0.26, 0.04), Vector3(0, 0, 0.04), "SignFront", {"kind": "label", "tint": Color(1.2, 0.7, 0.3)})
	var clock := _prop("WallClock", Vector3(1.8, 2.1, -HALF_D))
	_c(clock, Vector3(0.58, 0.58, 0.05), Vector3(0, 0, 0.03), "ClockFrame", {"kind": "plastic"})
	_c(clock, Vector3(0.5, 0.5, 0.03), Vector3(0, 0, 0.06), "ClockFace", {})
	_c(clock, Vector3(0.03, 0.18, 0.02), Vector3(0, 0.07, 0.09), "ClockHandA", {"kind": "plastic"})
	_c(clock, Vector3(0.14, 0.03, 0.02), Vector3(0.05, 0, 0.09), "ClockHandB", {"kind": "plastic"})
