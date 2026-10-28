class_name XRMenuPanel
extends Node

## XR headsets only (PlatformProfile.is_xr with OpenXR running; docs/XR_ANDROID.md). The game's screens are 2D and the
## root viewport is not an XR viewport until the route's player enters XR, so a headset would show nothing in the menus.
## This node renders its own small XR scene: the root viewport's picture on a floating panel in front of the player, with
## a laser from the right controller. Pointing moves the mouse and the trigger clicks, through ordinary mouse events, so
## every menu works unchanged. When the route's XR player takes over the root viewport the panel steps aside, and it
## comes back when the route ends. Desktop and phones never create it.

const PANEL_WIDTH := 1.6
const PANEL_DISTANCE := 1.5
const PANEL_DROP := 0.15
const RAY_LENGTH := 4.0
## The right stick scrolls what the laser points at (scroll containers only drag-scroll for touch, not for a pointer):
## one wheel step per SCROLL_STEP_SECONDS while pushed past SCROLL_DEADZONE.
const SCROLL_DEADZONE := 0.5
const SCROLL_STEP_SECONDS := 0.08

var _view: SubViewport
var _origin: XROrigin3D
var _camera: XRCamera3D
var _right: XRController3D
var _left: XRController3D
var _panel: MeshInstance3D
var _ray: MeshInstance3D
var _dot: MeshInstance3D
var _placed := false
var _place_wait := 0.0
var _pointer := Vector2(-1, -1)
var _held := false
var _scroll_wait := 0.0


## Creates the panel if OpenXR is running; returns null otherwise (desktop, phones, or a headset without a runtime).
static func attach(host: Node) -> XRMenuPanel:
	var openxr := XRServer.find_interface("OpenXR")
	if openxr == null or not openxr.is_initialized():
		return null
	var panel := XRMenuPanel.new()
	panel.name = "XRMenuPanel"
	host.add_child(panel)
	return panel


## Sends one mouse-wheel step at `at` (window coordinates) when the stick is pushed far enough; returns the new wait.
static func scroll_from_stick(stick_y: float, at: Vector2, wait: float, delta: float) -> float:
	wait = maxf(0.0, wait - delta)
	if absf(stick_y) < SCROLL_DEADZONE or wait > 0.0 or at.x < 0.0:
		return wait
	for pressed in [true, false]:
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP if stick_y > 0.0 else MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = pressed
		wheel.factor = 1.0
		wheel.position = at
		wheel.global_position = at
		Input.parse_input_event(wheel)
	return SCROLL_STEP_SECONDS


## Where a ray hits a panel of `size` metres whose centre and facing are `panel` (+Z towards the viewer), as 0..1 UV
## from the top-left, or (-1, -1) for a miss.
static func panel_uv(ray_origin: Vector3, ray_direction: Vector3, panel: Transform3D, size: Vector2) -> Vector2:
	var normal := panel.basis.z.normalized()
	var denominator := ray_direction.dot(normal)
	if absf(denominator) < 0.0001:
		return Vector2(-1, -1)
	var distance := (panel.origin - ray_origin).dot(normal) / denominator
	if distance <= 0.0:
		return Vector2(-1, -1)
	var local := panel.affine_inverse() * (ray_origin + ray_direction * distance)
	var uv := Vector2(local.x / size.x + 0.5, 0.5 - local.y / size.y)
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return Vector2(-1, -1)
	return uv


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_view = SubViewport.new()
	_view.name = "XRMenuView"
	_view.own_world_3d = true
	_view.use_xr = true
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_view)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.03, 0.02, 0.04)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_view.add_child(world_environment)
	_origin = XROrigin3D.new()
	_view.add_child(_origin)
	_camera = XRCamera3D.new()
	_origin.add_child(_camera)
	_left = XRController3D.new()
	_left.tracker = &"left_hand"
	_left.pose = &"aim"
	_origin.add_child(_left)
	_right = XRController3D.new()
	_right.tracker = &"right_hand"
	_right.pose = &"aim"
	_origin.add_child(_right)
	_panel = MeshInstance3D.new()
	_panel.name = "MenuPanel"
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = get_tree().root.get_texture()
	_panel.material_override = material
	_panel.mesh = QuadMesh.new()
	_view.add_child(_panel)
	_ray = _beam(Vector3(0.004, 0.004, RAY_LENGTH), Color(0.75, 0.6, 1.0, 0.7))
	_ray.position = Vector3(0, 0, -RAY_LENGTH * 0.5)
	_right.add_child(_ray)
	_dot = _beam(Vector3(0.018, 0.018, 0.004), Color(1, 1, 1))
	_view.add_child(_dot)
	_right.button_pressed.connect(_on_right_pressed)
	_right.button_released.connect(_on_right_released)
	_left.button_pressed.connect(_on_left_pressed)
	var keyboard := XRKeyboard.new()   # no system keyboard in an immersive app: type room codes and chat on the panel
	keyboard.name = "XRKeyboard"
	add_child(keyboard)


func _on_right_pressed(action: StringName) -> void:
	if action == &"trigger_click":
		_click(true)


func _on_right_released(action: StringName) -> void:
	if action == &"trigger_click":
		_click(false)


## The left menu button re-centres the panel in front of the head.
func _on_left_pressed(action: StringName) -> void:
	if action == &"menu_button":
		_placed = false


func _beam(size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	var beam := MeshInstance3D.new()
	beam.mesh = mesh
	beam.material_override = material
	return beam


## The route's player renders the root viewport in XR (PlayerController3D._try_enter_xr).
func _player_in_xr() -> bool:
	var root := get_tree().root
	return root.use_xr and root.get_camera_3d() is XRCamera3D


func _process(delta: float) -> void:
	var root := get_tree().root
	if _player_in_xr():
		if _view.use_xr:
			_view.use_xr = false
			_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
			_click(false)
		return
	if root.use_xr:
		root.use_xr = false   # a route that ended in XR leaves the flag behind
	if not _view.use_xr:
		_view.use_xr = true
		_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_placed = false
	var screen := Vector2(root.size)
	var size := Vector2(PANEL_WIDTH, PANEL_WIDTH * screen.y / maxf(screen.x, 1.0))
	(_panel.mesh as QuadMesh).size = size
	if not _placed:
		_place_wait += delta
		if _camera.position.length_squared() > 0.0001 or _place_wait > 1.0:
			_place()
	var uv := panel_uv(_right.global_position, -_right.global_basis.z, _panel.global_transform, size)
	_dot.visible = uv.x >= 0.0
	if uv.x < 0.0:
		return
	_dot.global_transform = _panel.global_transform.translated_local(
		Vector3((uv.x - 0.5) * size.x, (0.5 - uv.y) * size.y, 0.003))
	var at := (uv * screen).round()
	_scroll_wait = scroll_from_stick(_right.get_vector2("primary").y, at, _scroll_wait, delta)
	if at != _pointer:
		_pointer = at
		var motion := InputEventMouseMotion.new()
		motion.position = at
		motion.global_position = at
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT if _held else 0
		Input.parse_input_event(motion)


## Puts the panel in front of the head at a comfortable height, facing it (yaw only).
func _place() -> void:
	_placed = true
	_place_wait = 0.0
	var head := _camera.global_transform
	var forward := -head.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD
	var centre := head.origin + forward * PANEL_DISTANCE + Vector3(0, -PANEL_DROP, 0)
	_panel.global_transform = Transform3D(Basis.looking_at(forward, Vector3.UP), centre)


func _click(pressed: bool) -> void:
	if pressed == _held or (pressed and _pointer.x < 0.0):
		return
	_held = pressed
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_LEFT
	button.pressed = pressed
	button.position = _pointer
	button.global_position = _pointer
	button.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(button)
