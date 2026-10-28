class_name XRRoutePanel
extends Node

## The route's 2D screens in a headset (docs/XR_ANDROID.md). Once the route's player renders the root viewport in XR,
## CanvasLayers no longer reach the eyes, so the pause menu, map, inventory, chat, story and death screens would be
## invisible. This node moves every CanvasLayer of the route into its own 2D viewport (CanvasLayer.custom_viewport) and,
## while any of those screens is open, shows that viewport on a panel in front of the head. A laser from the right
## controller moves the mouse and the trigger clicks, through ordinary mouse events sent to the root viewport (the
## Controls still belong to it: custom_viewport only moves where they are drawn). Nothing happens unless the player is
## actually in XR, so desktop and phones never see it.

const RENDER_SCALE := 3
const PANEL_WIDTH := 1.4
const PANEL_DISTANCE := 1.2
const PANEL_DROP := 0.1
const RAY_LENGTH := 3.0

var route: Node
var player: Node3D
## Returns true while a 2D screen of the route is open (InfiniteRouteTest._xr_overlay_open).
var overlay_open: Callable
var _view: SubViewport
var _panel: MeshInstance3D
var _backdrop: MeshInstance3D
var _ray: MeshInstance3D
var _dot: MeshInstance3D
var _right: XRController3D
var _active := false
var _shown := false
var _pointer := Vector2(-1, -1)
var _held := false
var _trigger_down := false
var _scroll := XRPanelScroll.new()
var _left: XRController3D
var _gaze := XRGaze.new()


static func attach(host: Node, run_player: Node3D, open_check: Callable) -> XRRoutePanel:
	var panel := XRRoutePanel.new()
	panel.name = "XRRoutePanel"
	panel.route = host
	panel.player = run_player
	panel.overlay_open = open_check
	host.add_child(panel)
	return panel


## Points every CanvasLayer under `root` (except TouchControls and layers that already render elsewhere) at `view`.
## Returns how many it moved.
static func retarget_canvas_layers(root: Node, view: Viewport) -> int:
	var moved := 0
	for node in root.find_children("*", "CanvasLayer", true, false):
		var layer := node as CanvasLayer
		if layer is TouchControls or layer.custom_viewport != null:
			continue
		layer.custom_viewport = view
		moved += 1
	return moved


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # the pause menu pauses the tree, and it is what this shows


func _process(delta: float) -> void:
	if not _active:
		if player != null and bool(player.get("xr_active")):
			_activate()
		return
	var wanted := overlay_open.is_valid() and bool(overlay_open.call())
	if wanted != _shown:
		_shown = wanted
		if wanted:
			_place()
		else:
			_trigger(false)
		for node in [_panel, _backdrop, _ray]:
			node.visible = wanted
		_dot.visible = false
	if _shown:
		_point()
		_scroll.stick(get_tree().root, [_left.get_vector2("primary"), _right.get_vector2("primary")], delta)


func _activate() -> void:
	_active = true
	_view = SubViewport.new()
	_view.name = "XRRouteUI"
	# The same canvas the root lays the UI out on (480 x 270 stretched with "expand", so wider on a wide window).
	var canvas := Vector2i(get_tree().root.get_visible_rect().size.round())
	_view.size = canvas * RENDER_SCALE
	_view.size_2d_override = canvas
	_view.size_2d_override_stretch = true
	_view.transparent_bg = true
	_view.disable_3d = true
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_view)
	retarget_canvas_layers(route, _view)
	# The headset keyboard (XRMenuPanel's) draws on this panel while the route owns the view.
	for keyboard in get_tree().get_nodes_in_group(&"xr_keyboard"):
		(keyboard as CanvasLayer).custom_viewport = _view
	get_tree().node_added.connect(_on_node_added)   # the death screen, chat and friends are created later
	var origin := player.get("xr_origin") as XROrigin3D
	_right = player.get("xr_right") as XRController3D
	_left = player.get("xr_left") as XRController3D
	for controller in [_right, player.get("xr_left")]:
		(controller as Node).process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = MeshInstance3D.new()
	_panel.name = "RouteUIPanel"
	var quad := QuadMesh.new()
	quad.size = Vector2(PANEL_WIDTH, PANEL_WIDTH * canvas.y / float(canvas.x))
	_panel.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.render_priority = 2
	material.albedo_texture = _view.get_texture()
	_panel.material_override = material
	_panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	origin.add_child(_panel)
	var hint := XRMenuPanel.hint_label("STICK: SCROLL  //  TRIGGER: CLICK OR DRAG")
	hint.position = Vector3(0, -quad.size.y * 0.5 - 0.04, 0.01)
	_panel.add_child(hint)
	_backdrop = _box("RouteUIBackdrop", Vector3(PANEL_WIDTH * 1.04, quad.size.y * 1.06, 0.002), Color(0.02, 0.01, 0.03, 0.82), 1)
	_backdrop.position = Vector3(0, 0, -0.01)
	_panel.add_child(_backdrop)
	_ray = _box("RouteUILaser", Vector3(0.004, 0.004, RAY_LENGTH), Color(0.75, 0.6, 1.0, 0.7), 3)
	_ray.position = Vector3(0, 0, -RAY_LENGTH * 0.5)
	_right.add_child(_ray)
	_dot = _box("RouteUIDot", Vector3(0.016, 0.016, 0.004), Color(1, 1, 1), 4)
	origin.add_child(_dot)
	for node in [_panel, _ray, _dot]:
		node.visible = false
	_right.button_pressed.connect(_on_right_pressed)
	_right.button_released.connect(_on_right_released)
	_left.button_pressed.connect(_on_left_pressed)
	_left.button_released.connect(_on_right_released)


func _exit_tree() -> void:
	for keyboard in get_tree().get_nodes_in_group(&"xr_keyboard"):
		if (keyboard as CanvasLayer).custom_viewport == _view:
			(keyboard as CanvasLayer).custom_viewport = null


func _box(node_name: String, size: Vector3, color: Color, priority: int) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.render_priority = priority
	material.albedo_color = color
	var box := MeshInstance3D.new()
	box.name = node_name
	box.mesh = mesh
	box.material_override = material
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return box


func _on_node_added(node: Node) -> void:
	if node is CanvasLayer and not node is TouchControls and route.is_ancestor_of(node) \
			and (node as CanvasLayer).custom_viewport == null:
		(node as CanvasLayer).custom_viewport = _view


## In front of the head at a comfortable height, facing it (yaw only), in the origin's space so it travels with the
## player while the screen is open.
func _place() -> void:
	var camera := player.get("xr_camera") as XRCamera3D
	var head := camera.global_transform
	var forward := -head.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.0001 else -player.global_basis.z
	var centre := head.origin + forward * PANEL_DISTANCE + Vector3(0, -PANEL_DROP, 0)
	_panel.global_transform = Transform3D(Basis.looking_at(forward, Vector3.UP), centre)


func _on_left_pressed(action: StringName) -> void:
	if action == &"trigger_click" and _shown and XRGaze.pointer_hand(_left, _right) == _left:
		_trigger(true)


## The pointer: the tracked hand's laser, else the head (gaze dwell when nothing else can click; see XRGaze).
func _point() -> void:
	var size := (_panel.mesh as QuadMesh).size
	var hand := XRGaze.pointer_hand(_left, _right)
	var source: Node3D = hand if hand != null else player.get("xr_camera") as Node3D
	_ray.visible = hand != null
	if hand != null and _ray.get_parent() != hand:
		_ray.reparent(hand, false)
	var uv := XRMenuPanel.panel_uv(source.global_position, -source.global_basis.z, _panel.global_transform, size)
	_dot.visible = uv.x >= 0.0
	if uv.x < 0.0:
		_gaze.reset()
		return
	if XRGaze.dwell_wanted(hand) and _gaze.update(get_tree().root, _canvas(_pointer), get_process_delta_time()):
		_click(true)
		_click(false)
	_dot.global_transform = _panel.global_transform.translated_local(
		Vector3((uv.x - 0.5) * size.x, (0.5 - uv.y) * size.y, 0.004))
	var root := get_tree().root
	var at := (root.get_final_transform() * (uv * root.get_visible_rect().size)).round()
	if at == _pointer:
		return
	_pointer = at
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT if _held else 0
	Input.parse_input_event(motion)
	if _trigger_down:
		_scroll.move(get_tree().root, _canvas(at))


func _on_right_pressed(action: StringName) -> void:
	if action == &"trigger_click" and _shown:
		_trigger(true)


func _on_right_released(action: StringName) -> void:
	if action == &"trigger_click":
		_trigger(false)


## Same as XRMenuPanel._trigger: drag past the dead zone scrolls, a still press clicks on release.
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
