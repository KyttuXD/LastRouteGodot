class_name OfficeView3D
extends SubViewportContainer

## The office rendered in 3D.
##
## It is a SubViewportContainer -- a Control -- so it occupies the same slot in
## the scene tree the flat ColorRect office used to, and main_office.gd drives
## it through one property, `can_move`. That is why the rest of the mode (the
## HUD, the control bar, the camera monitor) never had to change.
##
## The player is an OfficeWalker: seated at the desk by default, able to stand
## and walk the facility, and in real danger while away from it.
##
## Parts of the world are found BY NAME -- LeftDoor, RightDoor, DeskLamp,
## MonitorScreen, CamPanelScreen, CamPrev, CamNext -- which is why the exporter
## preserves group names; see scripts/validate_office_rooms.gd.

## The whole facility, split shell/props, WITH collision -- the player can walk
## out of the office and down the halls, so the world can no longer be one room.
const ROOM_SCENE := "res://scenes/office_map.tscn"

## The office room's footprint. Outside this you are "away from the desk", and
## the simulation starts counting.
const OFFICE_HALF_X := 3.2
const OFFICE_HALF_Z := 2.7

## Seat position in the room, in metres. The office is 6 x 5 m with the desk
## against the +Z wall spanning z 1.0-2.15, so the seat sits BEHIND it at 2.28
## -- the desk and its monitor are then in front of you and the doorways are
## forward-left and forward-right, which is the whole framing of the mode.
const SEAT := Vector3(0.0, 1.40, 2.28)

## How far the head may turn while seated. Also the scale `pan_ratio` reports
## against, for parity with the 2D view.
const YAW_LIMIT := 75.0

## How far outside a button's own face still counts as pointing at it, in
## metres across the console. The two buttons leave a 4.8 cm gap between them,
## so this stays under half of that and they can never both claim a point --
## which the validator checks, because the margin that makes near-misses count
## is exactly what would cause it.
const PICK_MARGIN := 0.018

## How far a button sinks when pressed, and for how long. These are momentary
## switches, not latching ones -- which feed is live is the screen's job to say.
const BUTTON_TRAVEL := 0.008
const BUTTON_HOLD := 0.13

const BUTTON_IDLE := Color(0.17, 0.31, 0.33)
const BUTTON_HOVER := Color(0.55, 0.95, 0.92)
const BUTTON_DEAD := Color(0.62, 0.24, 0.26)
## A latched control key: brighter than a camera button, because a closed door
## is a state you are paying power for and need to see without looking.
const CAP_LIVE_KEY := Color(0.42, 1.0, 0.78)

## Set false while the monitor is up -- you cannot look around the office with
## a tablet in your face.
var can_move := true

## Assigned by main_office.gd, exactly as it assigns monitor.simulation.
var simulation: OfficeSimulation

var _viewport: SubViewport
## Holder for the offscreen viewports (the CRT feed, the console's plan).
## They must NOT be direct children of this container: a SubViewportContainer
## draws every SubViewport child stacked over its own contents and force-sizes
## them to itself, so a feed parented here rendered at full screen resolution
## and then painted itself across the whole office.
var _offscreen: Node
var _camera: Camera3D
var _room: Node3D
var _lamp_light: OmniLight3D
var _ceiling_light: OmniLight3D
var _left_door: Node3D
var _right_door: Node3D
var _monitor_face: MeshInstance3D
var _feed: OfficeFeed
var _walker: OfficeWalker
var _feed_material: StandardMaterial3D
var _switch_flash := 0.0

# -- desk console --------------------------------------------------------
var _panel: OfficePanel
var _panel_face: MeshInstance3D
var _panel_material: StandardMaterial3D
## "prev" / "next" -> the button's node, its rest position, its rect on the
## console face, its material, and how long it has left to stay pressed in.
var _buttons := {}
var _button_rest := {}
var _button_rect := {}
var _button_materials := {}
var _button_flash := {"prev": 0.0, "next": 0.0}
var _panel_point := Vector3.ZERO
var _panel_right := Vector3.RIGHT
var _panel_up := Vector3.UP
var _panel_normal := Vector3.BACK
var _console_ready := false
var _hovered := ""

# -- desk control strip --------------------------------------------------
## The nine shift controls as physical keys. Same machinery as the console --
## a plane, a rect per button, a ray -- but its own board, because it sits at a
## keyboard's angle in front of a monitor's.
##
## Key -> what the simulation calls it. Toggles go through toggle_control; the
## rest are one-shot commands, so the value is a Callable name instead.
const CONTROL_KEYS := {
	"LeftDoor": "leftDoor", "RightDoor": "rightDoor", "DeskLight": "deskLight",
	"Vent": "vent", "Monitor": "cameras",
}
const CONTROL_COMMANDS := {
	"Radio": "cycle_radio", "Breaker": "reset_breaker",
	"Reboot": "reboot_cameras", "Flash": "trigger_emergency_flash",
}
## What each key is called and what working it does, shown on the console
## screen while the pointer is on it. Nine unlabelled slabs is a puzzle; the
## keys are 22 cm wide and the art is 12 texels per metre, so a printed legend
## would be under three texels tall -- the name has to live somewhere it can
## actually be read.
const CONTROL_LABELS := {
	"LeftDoor": "LEFT DOOR", "RightDoor": "RIGHT DOOR",
	"DeskLight": "DESK LIGHT", "Vent": "VENT HATCH", "Monitor": "CAMERAS",
	"Radio": "RADIO", "Breaker": "BREAKER RESET", "Reboot": "CAMERA REBOOT",
	"Flash": "EMERGENCY FLASH",
}
## Keys are grouped by colour so the bank reads as three kinds of thing without
## being hovered: the two doors, the systems that sit on or off, and the
## one-shot commands that fire and are done.
const KEY_FAMILY := {
	"LeftDoor": Color(0.95, 0.62, 0.30), "RightDoor": Color(0.95, 0.62, 0.30),
	"DeskLight": Color(0.35, 0.85, 0.90), "Vent": Color(0.35, 0.85, 0.90),
	"Monitor": Color(0.35, 0.85, 0.90),
	"Radio": Color(0.85, 0.45, 0.55), "Breaker": Color(0.85, 0.45, 0.55),
	"Reboot": Color(0.85, 0.45, 0.55), "Flash": Color(0.85, 0.45, 0.55),
}
var _keys := {}
var _key_rest := {}
var _key_rect := {}
var _key_materials := {}
var _key_flash := {}
var _strip_point := Vector3.ZERO
var _strip_right := Vector3.RIGHT
var _strip_up := Vector3.UP
var _strip_normal := Vector3.BACK
var _strip_ready := false


func _ready() -> void:
	stretch = true
	_viewport = SubViewport.new()
	_viewport.transparent_bg = false
	_viewport.handle_input_locally = false
	# The room art is pixel-art at 12 texels/metre; smoothing the render would
	# undo the nearest-neighbour filtering the models were exported with.
	_viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	add_child(_viewport)

	_offscreen = Node.new()
	_offscreen.name = "Offscreen"
	add_child(_offscreen)

	var world := Node3D.new()
	world.name = "World"
	_viewport.add_child(world)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.012, 0.016, 0.022)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.28, 0.32, 0.38)
	e.ambient_light_energy = 0.18
	env.environment = e
	world.add_child(env)

	var packed: PackedScene = load(ROOM_SCENE)
	if packed != null:
		_room = packed.instantiate()
		world.add_child(_room)
		_left_door = _find(_room, "LeftDoor") as Node3D
		_right_door = _find(_room, "RightDoor") as Node3D
		# "MonitorScreen" is the GROUP; the exporter emits one node per group,
		# so the cube name "MonitorFace" is not a node and never resolved.
		_monitor_face = _find(_room, "MonitorScreen") as MeshInstance3D
		_attach_lamp()
	else:
		push_warning("OfficeView3D: could not load %s" % ROOM_SCENE)

	_build_feed()
	_build_console()

	_ceiling_light = OmniLight3D.new()
	_ceiling_light.position = Vector3(0.0, 2.7, 0.6)
	_ceiling_light.omni_range = 9.0
	_ceiling_light.light_energy = 0.55
	_ceiling_light.light_color = Color(0.62, 0.72, 0.78)
	world.add_child(_ceiling_light)

	_walker = OfficeWalker.new()
	_walker.seat_position = SEAT
	world.add_child(_walker)
	_camera = _walker.camera()


## Depth-first by name, matching either the bare group name or the merged map's
## prefixed one ("MonitorScreen" / "Office_MonitorScreen"), since the same
## models are built both standalone and as part of the facility.
##
## The exporter emits a "<name>-colonly" collision node alongside each mesh and
## Godot names the body it builds after that node MINUS the suffix, so the two
## share a name. First match wins, which is the visual node rather than the
## collider sitting at the local origin.
func _find(node: Node, wanted: String) -> Node:
	if node == null:
		return null
	var node_name := String(node.name)
	if node_name == wanted or node_name.ends_with("_" + wanted):
		return node
	for child in node.get_children():
		var found := _find(child, wanted)
		if found != null:
			return found
	return null


func _attach_lamp() -> void:
	var lamp := _find(_room, "DeskLamp")
	_lamp_light = OmniLight3D.new()
	_lamp_light.position = Vector3(0.93, 1.26, 1.44)
	_lamp_light.omni_range = 3.4
	_lamp_light.light_color = Color(0.98, 0.86, 0.55)
	_lamp_light.light_energy = 0.0
	if lamp is Node3D:
		(lamp as Node3D).add_child(_lamp_light)
		_lamp_light.position = Vector3(0.0, 0.0, 0.0)
		_lamp_light.global_position = Vector3(0.93, 1.26, 1.44)
	else:
		_room.add_child(_lamp_light)


## A display slab's faces all carry the same material in the model, so the
## mesh's UV bounds ARE its patch of the shared atlas. `material_override`
## replaces the material but keeps those UVs, which is why a viewport dropped
## straight onto a screen sampled a few pixels of atlas instead of the picture;
## scaling by the inverse of that patch maps the viewport onto the whole face.
func _fit_to_face(mesh: MeshInstance3D, material: StandardMaterial3D) -> bool:
	if mesh == null or mesh.mesh == null or mesh.mesh.get_surface_count() == 0:
		return false
	var uvs: PackedVector2Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	if uvs.is_empty():
		return false
	var lo := uvs[0]
	var hi := uvs[0]
	for uv in uvs:
		lo = lo.min(uv)
		hi = hi.max(uv)
	var span := hi - lo
	if span.x <= 0.0 or span.y <= 0.0:
		return false
	material.uv1_scale = Vector3(1.0 / span.x, 1.0 / span.y, 1.0)
	material.uv1_offset = Vector3(-lo.x / span.x, -lo.y / span.y, 0.0)
	return true


## The desk screen shows a LIVE 3D feed, not a texture: a SubViewport renders
## the selected camera's room and its ViewportTexture is the screen material.
## Unshaded, so the office's own dim lighting does not darken a CRT that is
## supposed to be emitting.
func _build_feed() -> void:
	if _monitor_face == null:
		return
	_feed = OfficeFeed.new()
	_offscreen.add_child(_feed)
	_feed_material = StandardMaterial3D.new()
	_feed_material.albedo_texture = _feed.get_texture()
	_feed_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_feed_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_fit_to_face(_monitor_face, _feed_material)
	_monitor_face.material_override = _feed_material


func _build_console() -> void:
	_panel_face = _find(_room, "CamPanelScreen") as MeshInstance3D
	for key in ["prev", "next"]:
		var button := _find(_room, "Cam%s" % key.capitalize()) as MeshInstance3D
		if button != null:
			_buttons[key] = button
	if _panel_face == null or _buttons.size() < 2:
		push_warning("OfficeView3D: no camera console in the map")
		return

	_panel = OfficePanel.new()
	_offscreen.add_child(_panel)
	_panel_material = StandardMaterial3D.new()
	_panel_material.albedo_texture = _panel.get_texture()
	_panel_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_panel_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_fit_to_face(_panel_face, _panel_material)
	_panel_face.material_override = _panel_material

	for name in CONTROL_KEYS.keys() + CONTROL_COMMANDS.keys():
		var node := _find(_room, "Ctrl%s" % name) as MeshInstance3D
		if node == null:
			continue
		_keys[name] = node
		_key_flash[name] = 0.0
		var key_material := StandardMaterial3D.new()
		key_material.emission_enabled = true
		_key_materials[name] = key_material
		node.material_override = key_material

	for key in _buttons:
		var material := StandardMaterial3D.new()
		material.emission_enabled = true
		_button_materials[key] = material
		(_buttons[key] as MeshInstance3D).material_override = material
		# The arrow is a separate node so it can keep its dark atlas material
		# while the button beneath lights up -- that contrast is what makes it
		# read from the seat. Reparenting it to the button, keeping its world
		# transform, is what stops it hanging in the air over a button that has
		# just been pressed in.
		var glyph := _find(_room, "Cam%sGlyph" % key.capitalize()) as Node3D
		if glyph != null:
			glyph.reparent(_buttons[key], true)
		else:
			push_warning("OfficeView3D: %s button has no arrow" % key)


## Measure the console off the model rather than restating its dimensions here.
## Runs once the scene has settled, because a global transform read during
## _ready is not guaranteed to be final.
func _measure_console() -> bool:
	if _panel_face == null or _buttons.size() < 2:
		return false
	var basis := _panel_face.global_transform.basis
	_panel_right = basis.x.normalized()
	_panel_up = basis.y.normalized()
	_panel_normal = basis.z.normalized()

	# The two buttons are coplanar, so their midpoint is a point on the plane a
	# finger would actually touch -- in front of the board they stand on.
	var centroid := Vector3.ZERO
	for key in _buttons:
		_button_rest[key] = (_buttons[key] as MeshInstance3D).global_position
		centroid += _button_rest[key] as Vector3
	_panel_point = centroid / float(_buttons.size())

	for key in _buttons:
		var button: MeshInstance3D = _buttons[key]
		var aabb := button.get_aabb()
		var xform := button.global_transform
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for corner in 8:
			var p := _to_panel(xform * aabb.get_endpoint(corner))
			lo = lo.min(p)
			hi = hi.max(p)
		if hi.x <= lo.x or hi.y <= lo.y:
			return false
		_button_rect[key] = Rect2(lo, hi - lo).grow(PICK_MARGIN)
	_measure_strip()
	return true


## The control strip's own plane. Measured the same way and separately, because
## it is tilted differently -- a ray hitting one board says nothing about where
## it crosses the other.
func _measure_strip() -> void:
	if _keys.is_empty():
		return
	var sample: MeshInstance3D = _keys.values()[0]
	var basis := sample.global_transform.basis
	_strip_right = basis.x.normalized()
	_strip_up = basis.y.normalized()
	_strip_normal = basis.z.normalized()
	var centroid := Vector3.ZERO
	for name in _keys:
		_key_rest[name] = (_keys[name] as MeshInstance3D).global_position
		centroid += _key_rest[name] as Vector3
	_strip_point = centroid / float(_keys.size())
	for name in _keys:
		var node: MeshInstance3D = _keys[name]
		var aabb := node.get_aabb()
		var xform := node.global_transform
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for corner in 8:
			var d := xform * aabb.get_endpoint(corner) - _strip_point
			var p := Vector2(d.dot(_strip_right), d.dot(_strip_up))
			lo = lo.min(p)
			hi = hi.max(p)
		_key_rect[name] = Rect2(lo, hi - lo).grow(0.012)
	_strip_ready = true


func _to_panel(point: Vector3) -> Vector2:
	var d := point - _panel_point
	return Vector2(d.dot(_panel_right), d.dot(_panel_up))


## Where the player is pointing, in this viewport's pixels. Seated, that is the
## cursor -- the same cursor that steers the head, and the one the control bar
## needs to stay usable. Standing, the mouse is captured, so it is the centre
## of the screen.
func _aim_point() -> Vector2:
	if _walker != null and not _walker.seated:
		return Vector2(_viewport.size) * 0.5
	return get_local_mouse_position()


## What the console screen should say about the key under the pointer -- its
## name and what working it would do right now, so a control is legible before
## it is pressed rather than after.
func _control_hint() -> String:
	if not _hovered.begins_with("ctrl:") or simulation == null:
		return ""
	var name := _hovered.substr(5)
	var label := String(CONTROL_LABELS.get(name, name.to_upper()))
	var control := String(CONTROL_KEYS.get(name, ""))
	if not control.is_empty():
		if simulation.is_system_disabled(control):
			return "%s // OFFLINE" % label
		return "%s // %s" % [label, "ON" if _is_control_on(control) else "OFF"]
	if name == "Radio":
		return "%s %d // CYCLE" % [label, simulation.radio_frequency]
	if name == "Flash" and not simulation.emergency_flash_ready:
		return "%s // RECHARGING" % label
	return label


## Which button the pointer is over: "prev", "next", or "".
##
## Against the console's PLANE rather than each button's collider, so a
## near-miss past the edge of a button still counts. They are 36 x 11 cm and
## 4.8 cm apart, which is over 20 pixels of cursor travel apiece -- the
## eleven-cap floor plan this replaced gave the tightest button 17 pixels and
## asked you to find it among ten others.
func _pick(aim: Vector2) -> String:
	if not _console_ready or _camera == null:
		return ""
	var from := _camera.project_ray_origin(aim)
	var direction := _camera.project_ray_normal(aim)
	var denominator := direction.dot(_panel_normal)
	if absf(denominator) < 0.0001:
		return ""
	var distance := (_panel_point - from).dot(_panel_normal) / denominator
	if distance <= 0.0:
		return ""
	var local := _to_panel(from + direction * distance)
	for key in _button_rect:
		if (_button_rect[key] as Rect2).has_point(local):
			return key
	return _pick_key(from, direction)


## Which control key the pointer is over, as "ctrl:<name>", or "".
func _pick_key(from: Vector3, direction: Vector3) -> String:
	if not _strip_ready:
		return ""
	var denominator := direction.dot(_strip_normal)
	if absf(denominator) < 0.0001:
		return ""
	var distance := (_strip_point - from).dot(_strip_normal) / denominator
	if distance <= 0.0:
		return ""
	var at := from + direction * distance - _strip_point
	var local := Vector2(at.dot(_strip_right), at.dot(_strip_up))
	for name in _key_rect:
		if (_key_rect[name] as Rect2).has_point(local):
			return "ctrl:%s" % name
	return ""


## Work whichever control the pointer is on. Toggles go through the simulation's
## own toggle_control so the physical key and the keyboard shortcut cannot
## disagree about what a door is doing; the rest are one-shot commands.
func _work_key(name: String) -> void:
	if simulation == null:
		return
	_key_flash[name] = BUTTON_HOLD
	if CONTROL_KEYS.has(name):
		simulation.toggle_control(String(CONTROL_KEYS[name]))
	elif CONTROL_COMMANDS.has(name):
		simulation.call(String(CONTROL_COMMANDS[name]))


## Step to the camera `delta` places along OfficeConfig.CAMERAS, wrapping.
## That order is also what the number-key shortcuts use, so pressing NEXT and
## pressing the next number agree about what comes next.
func _step(delta: int) -> void:
	if simulation == null or _panel == null:
		return
	_press(_panel.neighbour(delta))
	_button_flash["next" if delta > 0 else "prev"] = BUTTON_HOLD


## Switch the feed. Whether the press takes is the simulation's call -- it
## refuses and says why while the camera bus is down -- so the console cannot
## show a feed the tablet would not.
func _press(cam: String) -> void:
	if simulation == null or cam.is_empty() or simulation.current_camera == cam:
		return
	if simulation.select_camera(cam):
		_switch_flash = 1.0


func _process(delta: float) -> void:
	if not _console_ready and _panel_face != null:
		_console_ready = _measure_console()
	# The raised tablet is a full-screen Control, so it needs the pointer.
	MouseLock.claim("tablet", not can_move)

	_hovered = _pick(_aim_point()) if can_move else ""
	if _panel != null:
		_panel.simulation = simulation
		_panel.hovered = _hovered if not _hovered.begins_with("ctrl:") else ""
		_panel.control_hint = _control_hint()

	_update_seating()
	_switch_flash = maxf(0.0, _switch_flash - delta * 5.0)
	_reflect_simulation()
	_reflect_console(delta)


## Sit and stand with the interact key, and only when close enough to the desk
## -- so returning to the office is a deliberate act, not a teleport. Pointing
## at the console takes priority: the same key works the button you are looking
## at, so standing up never happens by accident while cycling feeds.
func _update_seating() -> void:
	if _walker == null:
		return
	if Input.is_action_just_pressed("interact") and can_move:
		if _hovered.begins_with("ctrl:"):
			_work_key(_hovered.substr(5))
		elif not _hovered.is_empty():
			_step(1 if _hovered == "next" else -1)
		elif _walker.seated:
			_walker.stand()
		elif _walker.can_sit():
			_walker.sit()
	if simulation != null:
		var p := _walker.global_position
		simulation.away_from_desk = not _walker.seated and (
			absf(p.x) > OFFICE_HALF_X or absf(p.z) > OFFICE_HALF_Z)


func _unhandled_input(event: InputEvent) -> void:
	if not can_move or _hovered.is_empty() or not event is InputEventMouseButton:
		return
	var click := event as InputEventMouseButton
	if not click.pressed:
		return
	match click.button_index:
		MOUSE_BUTTON_LEFT:
			if _hovered.begins_with("ctrl:"):
				_work_key(_hovered.substr(5))
			else:
				_step(1 if _hovered == "next" else -1)
		# Scrolling over the console cycles too. With only two buttons the wheel
		# is the natural way to run down the bank quickly, and it costs nothing.
		MOUSE_BUTTON_WHEEL_DOWN:
			_step(1)
		MOUSE_BUTTON_WHEEL_UP:
			_step(-1)
		_:
			return
	get_viewport().set_input_as_handled()


## Everything here READS the simulation; nothing writes to it. The sim stays
## authoritative, exactly as it is for the 2D view.
func _reflect_simulation() -> void:
	if simulation == null:
		return

	# Doors are modelled full-height with their pivot at the TOP of the
	# opening, so closing is a Y scale of 0 -> 1: a shutter rolling down.
	_set_door(_left_door, simulation.left_door)
	_set_door(_right_door, simulation.right_door)

	var blacked_out := simulation.blackout_timer > 0.0
	if _lamp_light != null:
		var want := 1.5 if (simulation.desk_light and not blacked_out) else 0.0
		_lamp_light.light_energy = lerpf(_lamp_light.light_energy, want, 0.25)
	if _ceiling_light != null:
		_ceiling_light.light_energy = 0.0 if blacked_out else 0.55
	if _feed != null:
		_feed.select(simulation.current_camera)
	if _feed_material != null:
		# A dead feed is a dark screen, not a hidden one -- the CRT is still
		# physically there. Corrupted reads red, matching the 2D monitor, and a
		# switch whites the tube for a moment the way a real one settles.
		var tint := Color(1, 1, 1)
		if blacked_out:
			tint = Color(0.05, 0.05, 0.06)
		elif simulation.corrupted_cameras.has(simulation.current_camera):
			tint = Color(0.9, 0.35, 0.35)
		_feed_material.albedo_color = _feed_material.albedo_color.lerp(tint, 0.2)
		if _switch_flash > 0.0:
			_feed_material.albedo_color = _feed_material.albedo_color.lerp(
				Color(1.6, 1.7, 1.7), _switch_flash * 0.8)


## Light the two buttons and push one in when it is worked.
##
## They carry no feed state of their own -- these are momentary switches, and
## which camera is live is the screen's job. All they have to say is "you are
## pointing at me", "I just fired", and "the bus is down so I will do nothing".
func _reflect_console(delta: float) -> void:
	if not _console_ready or simulation == null:
		return
	var offline := simulation.blackout_timer > 0.0 \
		or simulation.is_system_disabled("cameras")
	for key in _buttons:
		_button_flash[key] = maxf(0.0, float(_button_flash[key]) - delta)
		var pressed: bool = _button_flash[key] > 0.0
		var colour := BUTTON_DEAD if offline else BUTTON_IDLE
		var energy := 0.2 if offline else 0.3
		if key == _hovered and not offline:
			colour = BUTTON_HOVER
			energy = 0.75
		if pressed:
			colour = colour.lerp(Color.WHITE, 0.5)
			energy += 0.6

		var material: StandardMaterial3D = _button_materials[key]
		material.albedo_color = colour.darkened(0.55)
		material.emission = colour
		material.emission_energy_multiplier = energy

		var button: MeshInstance3D = _buttons[key]
		var sunk: float = BUTTON_TRAVEL if pressed else 0.0
		var want: Vector3 = (_button_rest[key] as Vector3) - _panel_normal * sunk
		button.global_position = button.global_position.lerp(
			want, clampf(delta * 22.0, 0.0, 1.0))

	_reflect_keys(delta, offline)


## The control keys. Unlike the camera buttons these are LATCHING where the
## control is -- a closed door stays lit and stays down, because that is the
## thing the player most needs to read at a glance and the one the power meter
## is quietly charging them for.
func _reflect_keys(delta: float, _offline: bool) -> void:
	for name in _keys:
		_key_flash[name] = maxf(0.0, float(_key_flash[name]) - delta)
		var control := String(CONTROL_KEYS.get(name, ""))
		var latched := not control.is_empty() and _is_control_on(control)
		var dead := not control.is_empty() and simulation.is_system_disabled(control)
		# Dim in its family colour when off, full when on -- so the grouping
		# survives the state rather than being replaced by it.
		var family: Color = KEY_FAMILY.get(name, BUTTON_IDLE)
		var colour := family.darkened(0.55)
		var energy := 0.3
		if dead:
			colour = BUTTON_DEAD
			energy = 0.2
		elif latched:
			colour = family
			energy = 1.0
		if ("ctrl:%s" % name) == _hovered and not dead:
			colour = colour.lerp(Color.WHITE, 0.4)
			energy += 0.4
		if float(_key_flash[name]) > 0.0:
			colour = colour.lerp(Color.WHITE, 0.5)
			energy += 0.5

		var material: StandardMaterial3D = _key_materials[name]
		material.albedo_color = colour.darkened(0.55)
		material.emission = colour
		material.emission_energy_multiplier = energy

		var node: MeshInstance3D = _keys[name]
		var down: bool = latched or float(_key_flash[name]) > 0.0
		var want: Vector3 = (_key_rest[name] as Vector3) \
			- _strip_normal * (BUTTON_TRAVEL if down else 0.0)
		node.global_position = node.global_position.lerp(
			want, clampf(delta * 22.0, 0.0, 1.0))


func _is_control_on(control: String) -> bool:
	match control:
		"leftDoor": return simulation.left_door
		"rightDoor": return simulation.right_door
		"deskLight": return simulation.desk_light
		"vent": return simulation.vent_sealed
		"cameras": return simulation.monitor_open
	return false


func _set_door(door: Node3D, closed: bool) -> void:
	if door == null:
		return
	var want := 1.0 if closed else 0.0
	door.scale.y = lerpf(door.scale.y, want, 0.2)


## How far the head is turned: 0.0 centred, -1.0 fully left, 1.0 fully right.
func pan_ratio() -> float:
	if _walker == null or YAW_LIMIT <= 0.0:
		return 0.0
	return clampf(-_walker.rotation.y / deg_to_rad(YAW_LIMIT), -1.0, 1.0)
