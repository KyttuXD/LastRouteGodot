class_name XRFade
extends MeshInstance3D

## Comfort fades for headsets (docs/XR_ANDROID.md, "Scene changes in a headset"). leaving a route and switching
## menus flashed heavily in VR. A scene change frees the camera the headset renders from and the menu panel only took
## the view back a frame later, so the eyes got frames with no camera, two XR viewports, or the old view torn down.
##
## Every XR camera carries one of these: a black sphere around the head, drawn over everything. A scene switch goes
##   fade out (FADE_SECONDS) on the view the headset shows -> the new scene loads (the headset keeps the last, black,
##   frame) -> the menu panel takes the view back black / the route enters XR black -> HOLD_SECONDS -> fade in
## and the brightness the eye sees only ever moves by one FADE_SECONDS ramp per frame step. Desktop and phones have no
## XR camera, so change_scene() is exactly tree.change_scene_to_file / _packed there.

const FADE_SECONDS := 0.3
const HOLD_SECONDS := 0.25
const GROUP := &"xr_fade"

## 0 = clear, 1 = black.
var alpha := 0.0
var target := 0.0
var _material: StandardMaterial3D


## A fade sphere on `camera`, starting at `start` (1 = black).
static func attach(camera: Camera3D, start := 0.0) -> XRFade:
	var fade := XRFade.new()
	fade.name = "XRFade"
	fade.alpha = start
	fade.target = start
	camera.add_child(fade)
	return fade


func _init() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	sphere.height = 0.4
	sphere.radial_segments = 16
	sphere.rings = 8
	mesh = sphere
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.no_depth_test = true
	_material.render_priority = Material.RENDER_PRIORITY_MAX
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_apply()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(GROUP)


func _process(delta: float) -> void:
	advance(delta)


func fade_to(value: float) -> void:
	target = clampf(value, 0.0, 1.0)


## One step of the ramp (the validator steps it with a fixed headset frame time).
func advance(delta: float) -> void:
	alpha = move_toward(alpha, target, delta / FADE_SECONDS)
	_apply()


func is_settled() -> bool:
	return is_equal_approx(alpha, target)


func _apply() -> void:
	if _material != null:
		_material.albedo_color = Color(0, 0, 0, alpha)
	visible = alpha > 0.001


## The fade the headset is looking through: the one on the current camera of a viewport that renders XR.
static func active(tree: SceneTree) -> XRFade:
	for node in tree.get_nodes_in_group(GROUP):
		var camera := node.get_parent() as Camera3D
		if camera != null and camera.is_inside_tree() and camera.current and camera.get_viewport().use_xr:
			return node
	return null


## Fades the headset to black, then switches to `target` (a scene path or PackedScene). Without an active XR fade (desktop,
## phones) the switch happens at once, synchronously, as before.
static func change_scene(tree: SceneTree, scene: Variant) -> void:
	var fade := active(tree)
	if fade != null:
		await to_black(tree, fade)
		if not tree.root.use_xr:   # between menus: the panel holds black until the new scene is up
			for panel in tree.get_nodes_in_group(XRMenuPanel.GROUP):
				(panel as XRMenuPanel).hold_dark()
	if scene is PackedScene:
		tree.change_scene_to_packed(scene)
	else:
		tree.change_scene_to_file(String(scene))


## Ramps `fade` to black and returns once it is (or once it has gone).
static func to_black(tree: SceneTree, fade: XRFade) -> void:
	fade.fade_to(1.0)
	while is_instance_valid(fade) and fade.is_inside_tree() and not fade.is_settled():
		await tree.process_frame
