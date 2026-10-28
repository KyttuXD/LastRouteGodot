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
var _trigger_down := false
## Stick and trigger-drag scrolling (XRPanelScroll).
var _scroll := XRPanelScroll.new()
const HINT := "STICK: SCROLL  //  TRIGGER: CLICK OR DRAG  //  LEFT MENU: RECENTRE"


## Creates the panel if OpenXR is running; returns null otherwise (desktop, phones, or a headset without a runtime).
static func attach(host: Node) -> XRMenuPanel:
	var openxr := XRServer.find_interface("OpenXR")
	if openxr == null or not openxr.is_initialized():
		return null
	var panel := XRMenuPanel.new()
	panel.name = "XRMenuPanel"
	host.add_child(panel)
	return panel


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
	_panel.add_child(hint_label(HINT))
	var keyboard := XRKeyboard.new()   # no system keyboard in an immersive app: type room codes and chat on the panel
	keyboard.name = "XRKeyboard"
	add_child(keyboard)


func _on_right_pressed(action: StringName) -> void:
	if action == &"trigger_click":
		_trigger(true)


func _on_right_released(action: StringName) -> void:
	if action == &"trigger_click":
		_trigger(false)


## A short line of help under a panel (how to scroll, click and drag with the controllers).
static func hint_label(text: String) -> Label3D:
	var hint := Label3D.new()
	hint.name = "PanelHint"
	hint.text = text
	hint.pixel_size = 0.0011
	hint.font_size = 24
	hint.outline_size = 6
	hint.modulate = Color(0.8, 0.72, 0.9)
	hint.no_depth_test = true
	hint.position = Vector3(0, -0.5, 0.01)
	return hint


## Trigger down: a press that moves past the dead zone scrolls like a finger, one that stays put clicks on release.
## Sliders and scroll bars under the laser get the real mouse press at once, so they still drag.
func _trigger(down: bool) -> void:
	var root := get_tree().root
	if down:
		if _pointer.x < 0.0:
			return
		_trigger_down = true
		_scroll.press(root, _canvas(_pointer))
		if _scroll.passthrough:
			_click(true)
		return
	if not _trigger_down:
		return
	_trigger_down = false
	var was_drag := _scroll.release()
	if _held:
		_click(false)
	elif not was_drag:
		_click(true)
		_click(false)


func _canvas(window_position: Vector2) -> Vector2:
	return get_tree().root.get_final_transform().affine_inverse() * window_position


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
			_trigger(false)
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
	(_panel.get_node("PanelHint") as Label3D).position = Vector3(0, -size.y * 0.5 - 0.04, 0.01)
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
	if at != _pointer:
		_pointer = at
		var motion := InputEventMouseMotion.new()
		motion.position = at
		motion.global_position = at
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT if _held else 0
		Input.parse_input_event(motion)
		if _trigger_down:
			_scroll.move(root, _canvas(at))
	_scroll.stick(root, [_left.get_vector2("primary"), _right.get_vector2("primary")], delta)


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
