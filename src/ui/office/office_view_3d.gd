class_name OfficeView3D
extends SubViewportContainer

## The office rendered in 3D, as a drop-in replacement for OfficeView.
##
## It is a SubViewportContainer -- a Control -- so it occupies exactly the same
## slot in the scene tree as the 2D view, and main_office.gd drives it through
## the same single property, `can_move`. Everything else in scenes/office.tscn
## (the HUD, the control bar, the camera monitor) is untouched, and
## scenes/office.tscn itself stays as the 2D fallback.
##
## The player is an OfficeWalker: seated at the desk by default, able to stand
## and walk the facility, and in real danger while away from it.
##
## Parts of the world are found BY NAME -- LeftDoor, RightDoor, DeskLamp,
## MonitorScreen, CamPanelScreen, CamButton1..11 -- which is why the exporter
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

## How far past the console's edge still counts as pointing at it, in metres.
## Small: everything INSIDE the panel belongs to some room already.
const PICK_MARGIN := 0.012

## How far the live camera's cap sits into the panel. A latched button that
## stays down says which feed is up without relying on colour, so the console
## still reads during a blackout.
const CAP_TRAVEL := 0.006

const CAP_IDLE := Color(0.16, 0.30, 0.32)
const CAP_LIVE := Color(0.35, 1.0, 0.92)
const CAP_DEAD := Color(0.95, 0.28, 0.32)

## Set false while the monitor is up -- you cannot look around the office with
## a tablet in your face. Same contract as OfficeView.can_move.
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
var _caps := {}                 # camera id -> MeshInstance3D
var _cap_rest := {}             # camera id -> global position, cap out
var _cap_local := {}            # camera id -> (right, up) on the console face
var _cap_materials := {}        # camera id -> StandardMaterial3D
var _panel_point := Vector3.ZERO
var _panel_right := Vector3.RIGHT
var _panel_up := Vector3.UP
var _panel_normal := Vector3.BACK
var _panel_rect := Rect2()
var _console_ready := false
var _hovered := ""


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
	for index in OfficeConfig.CAMERAS.size():
		var cap := _find(_room, "CamButton%d" % (index + 1)) as MeshInstance3D
		if cap != null:
			_caps[OfficeConfig.CAMERAS[index]] = cap
	if _panel_face == null or _caps.is_empty():
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

	for cam in _caps:
		var material := StandardMaterial3D.new()
		material.emission_enabled = true
		_cap_materials[cam] = material
		(_caps[cam] as MeshInstance3D).material_override = material


## Measure the console off the model rather than restating its dimensions here.
## Runs once the scene has settled, because a global transform read during
## _ready is not guaranteed to be final.
func _measure_console() -> bool:
	if _panel_face == null or _caps.is_empty():
		return false
	var basis := _panel_face.global_transform.basis
	_panel_right = basis.x.normalized()
	_panel_up = basis.y.normalized()
	_panel_normal = basis.z.normalized()

	# The caps are coplanar, so their centroid is a point on the plane a finger
	# would actually touch -- better than the display surface behind them.
	var centroid := Vector3.ZERO
	for cam in _caps:
		var cap: MeshInstance3D = _caps[cam]
		_cap_rest[cam] = cap.global_position
		centroid += cap.global_position
	_panel_point = centroid / float(_caps.size())

	for cam in _caps:
		_cap_local[cam] = _to_panel(_cap_rest[cam])

	# The drawable area, from the display mesh's own bounds projected onto the
	# same plane, so the plan fills the glass exactly.
	var aabb := _panel_face.get_aabb()
	var xform := _panel_face.global_transform
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for corner in 8:
		var p := _to_panel(xform * aabb.get_endpoint(corner))
		lo = lo.min(p)
		hi = hi.max(p)
	_panel_rect = Rect2(lo, hi - lo)
	if _panel_rect.size.x <= 0.0 or _panel_rect.size.y <= 0.0:
		return false

	_panel.cap_tex = {}
	for cam in _cap_local:
		_panel.cap_tex[cam] = _to_texture(_cap_local[cam])
	_panel.to_tex = _fit_plan()
	return true


func _to_panel(point: Vector3) -> Vector2:
	var d := point - _panel_point
	return Vector2(d.dot(_panel_right), d.dot(_panel_up))


## Console face -> the panel viewport's pixels. The vertical flip is the usual
## one: the face's local +Y is up, a texture's +Y is down.
func _to_texture(local: Vector2) -> Vector2:
	var size := Vector2(OfficePanel.PANEL_SIZE)
	return Vector2(
		(local.x - _panel_rect.position.x) / _panel_rect.size.x * size.x,
		(_panel_rect.end.y - local.y) / _panel_rect.size.y * size.y)


## Map metres -> panel pixels, solved from where two pairs of caps physically
## are. The plan is affine in map coordinates, so the extreme cameras on each
## axis pin it exactly -- and deriving it means the drawn rooms land under the
## buttons even if the console is moved or resized in the editor.
func _fit_plan() -> Transform2D:
	var by_x := _cap_local.keys()
	by_x.sort_custom(func(a, b): return _map_xz(a).x < _map_xz(b).x)
	var by_z := _cap_local.keys()
	by_z.sort_custom(func(a, b): return _map_xz(a).y < _map_xz(b).y)
	var xa: String = by_x.front()
	var xb: String = by_x.back()
	var za: String = by_z.front()
	var zb: String = by_z.back()
	var sx := (_to_texture(_cap_local[xb]).x - _to_texture(_cap_local[xa]).x) \
		/ maxf(0.001, _map_xz(xb).x - _map_xz(xa).x)
	var sz := (_to_texture(_cap_local[zb]).y - _to_texture(_cap_local[za]).y) \
		/ maxf(0.001, _map_xz(zb).y - _map_xz(za).y)
	return Transform2D(Vector2(sx, 0.0), Vector2(0.0, sz), Vector2(
		_to_texture(_cap_local[xa]).x - sx * _map_xz(xa).x,
		_to_texture(_cap_local[za]).y - sz * _map_xz(za).y))


func _map_xz(cam: String) -> Vector2:
	var at: Variant = OfficeLayout.CAMERA_XZ.get(cam, Vector2.ZERO)
	return at


## Where the player is pointing, in this viewport's pixels. Seated, that is the
## cursor -- the same cursor that steers the head, and the one the control bar
## needs to stay usable. Standing, the mouse is captured, so it is the centre
## of the screen.
func _aim_point() -> Vector2:
	if _walker != null and not _walker.seated:
		return Vector2(_viewport.size) * 0.5
	return get_local_mouse_position()


## Which cap the pointer is over, and where on the console the ray lands.
## Picking against the console's PLANE rather than each cap's collider is what
## makes 2.8 cm buttons usable: the nearest cap within PICK_RADIUS wins, so
## aiming into the gap between two of them still selects one.
func _pick(aim: Vector2) -> Dictionary:
	if not _console_ready or _camera == null:
		return {}
	var from := _camera.project_ray_origin(aim)
	var direction := _camera.project_ray_normal(aim)
	var denominator := direction.dot(_panel_normal)
	if absf(denominator) < 0.0001:
		return {}
	var distance := (_panel_point - from).dot(_panel_normal) / denominator
	if distance <= 0.0:
		return {}
	var local := _to_panel(from + direction * distance)
	if not _panel_rect.grow(PICK_MARGIN).has_point(local):
		return {}
	# The caps PARTITION the console: every point on the glass belongs to the
	# nearest one, with no dead space between them. Requiring a hit on a cap's
	# own 2.8 cm face would be hopeless -- the whole console is about 64 x 55
	# pixels of cursor travel at this project's 480 x 270 base resolution,
	# because seated the cursor swings the head as well as the ray. Partitioned,
	# aiming at a region of the building is enough.
	var best := ""
	var best_distance := INF
	for cam in _cap_local:
		var d: float = local.distance_to(_cap_local[cam])
		if d < best_distance:
			best_distance = d
			best = cam
	return {"local": local, "cam": best}


## Press a cap. Whether the press takes is the simulation's call -- it refuses
## and says why while the camera bus is down -- so the console cannot show a
## feed the tablet would not.
func _press(cam: String) -> void:
	if simulation == null or cam.is_empty() or simulation.current_camera == cam:
		return
	if simulation.select_camera(cam):
		_switch_flash = 1.0


func _process(delta: float) -> void:
	if not _console_ready and _panel_face != null:
		_console_ready = _measure_console()

	var hit: Dictionary = _pick(_aim_point()) if can_move else {}
	_hovered = String(hit.get("cam", ""))
	if _panel != null:
		_panel.simulation = simulation
		_panel.hovered = _hovered
		_panel.pointing = not hit.is_empty()
		if not hit.is_empty():
			_panel.pointer = _plan_position(hit["local"])

	_update_seating()
	_switch_flash = maxf(0.0, _switch_flash - delta * 5.0)
	_reflect_simulation()
	_reflect_console(delta)


## The pointer's console position expressed back in map metres, so the panel
## can draw a reticle on its own plan without knowing anything about 3D.
func _plan_position(local: Vector2) -> Vector2:
	var tex := _to_texture(local)
	return _panel.to_tex.affine_inverse() * tex


## Sit and stand with the interact key, and only when close enough to the desk
## -- so returning to the office is a deliberate act, not a teleport. Pointing
## at the console takes priority: the same key presses the button you are
## looking at, which is why standing up never happens by accident mid-sweep.
func _update_seating() -> void:
	if _walker == null:
		return
	if Input.is_action_just_pressed("interact") and can_move:
		if not _hovered.is_empty():
			_press(_hovered)
		elif _walker.seated:
			_walker.stand()
		elif _walker.can_sit():
			_walker.sit()
	if simulation != null:
		var p := _walker.global_position
		simulation.away_from_desk = not _walker.seated and (
			absf(p.x) > OFFICE_HALF_X or absf(p.z) > OFFICE_HALF_Z)


func _unhandled_input(event: InputEvent) -> void:
	if not can_move or _hovered.is_empty():
		return
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			_press(_hovered)
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


## Cap state, on the two channels a control panel has: what colour it burns,
## and whether it is latched down. Colour alone would vanish in a blackout,
## which is exactly when knowing the live feed matters most.
func _reflect_console(delta: float) -> void:
	if not _console_ready or simulation == null:
		return
	var offline := simulation.blackout_timer > 0.0 \
		or simulation.is_system_disabled("cameras")
	for cam in _caps:
		var colour := CAP_IDLE
		var energy := 0.22
		if simulation.corrupted_cameras.has(cam):
			colour = CAP_DEAD
			energy = 0.85
		else:
			var seen: Array = simulation.camera_signals(cam)
			if not seen.is_empty():
				colour = simulation.threats[seen[0]]["color"] as Color
				energy = 0.8
		if simulation.current_camera == cam:
			colour = colour.lerp(CAP_LIVE, 0.7)
			energy = maxf(energy, 1.15)
		if cam == _hovered:
			colour = colour.lerp(Color.WHITE, 0.4)
			energy += 0.35
		if offline:
			colour = colour.darkened(0.72)
			energy *= 0.2

		var material: StandardMaterial3D = _cap_materials[cam]
		material.albedo_color = colour.darkened(0.55)
		material.emission = colour
		material.emission_energy_multiplier = energy

		var cap: MeshInstance3D = _caps[cam]
		var sunk: float = CAP_TRAVEL if simulation.current_camera == cam else 0.0
		var want: Vector3 = _cap_rest[cam] - _panel_normal * sunk
		cap.global_position = cap.global_position.lerp(want, clampf(delta * 14.0, 0.0, 1.0))


func _set_door(door: Node3D, closed: bool) -> void:
	if door == null:
		return
	var want := 1.0 if closed else 0.0
	door.scale.y = lerpf(door.scale.y, want, 0.2)


## Kept for parity with OfficeView so either view satisfies the same surface.
## 0.0 centred, -1.0 fully left, 1.0 fully right.
func pan_ratio() -> float:
	if _walker == null or YAW_LIMIT <= 0.0:
		return 0.0
	return clampf(-_walker.rotation.y / deg_to_rad(YAW_LIMIT), -1.0, 1.0)
