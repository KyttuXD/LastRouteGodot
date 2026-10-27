class_name DebugView
extends RefCounted

## Admin-only render debug: FULLBRIGHT (every 3D surface unshaded: no lights, shadows, fog, glow or darkness) and
## WIREFRAME. Purely a local Viewport debug draw on this client: the World/Environment, lights, LightField and every
## gameplay light rule are untouched, nothing goes over the network, and the HUD/UI (2D canvas) is unaffected.
## Toggled from any game's admin menu (AdminMenu adds the entries) or the "debug_fullbright" action (F7, admin only).

enum Mode { OFF, FULLBRIGHT, WIREFRAME }
const ACTION := "debug_fullbright"
const DEFAULT_KEY := KEY_F7

static var mode := Mode.OFF
static var _restore_draw := -1


## Capture tools (not a game build) may force the gate; nothing in the game sets it.
static var tool_override := false


static func allowed() -> bool:
	return (Build.tools_enabled() or tool_override) and not RoomState.public_route


static var _camera: Camera3D
static var _camera_env: Environment
static var _fullbright_env: Environment


## The flat, shadowless look: white ambient everywhere, no fog, volumetrics, glow, SSAO or SDFGI, linear tonemap. It is put
## on the CAMERA (a camera environment overrides the world's), so the WorldEnvironment and every light keep their real values
## and gameplay (LightField, hunter vision) never sees it. The Compatibility renderer ignores an unshaded debug draw, so this
## is the fullbright that works everywhere.
static func fullbright_environment() -> Environment:
	if _fullbright_env == null:
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.32, 0.34, 0.38)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color.WHITE
		env.ambient_light_energy = 1.0
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		env.fog_enabled = false
		env.volumetric_fog_enabled = false
		env.glow_enabled = false
		env.ssao_enabled = false
		env.sdfgi_enabled = false
		_fullbright_env = env
	return _fullbright_env


static func _viewport(viewport: Viewport) -> Viewport:
	return viewport if viewport != null else (Engine.get_main_loop() as SceneTree).root


static func set_mode(next: int, viewport: Viewport = null) -> void:
	if next != Mode.OFF and not allowed():
		next = Mode.OFF
	var target := _viewport(viewport)
	_release(target)
	if next == Mode.FULLBRIGHT:
		_grab_camera(target)
	elif next == Mode.WIREFRAME:
		_restore_draw = target.debug_draw
		target.debug_draw = Viewport.DEBUG_DRAW_WIREFRAME
	mode = next


## Keeps fullbright on whichever camera is current (cameras swap: death cams, spectating, cutscenes). Called every frame by
## the admin menu while fullbright is on.
static func maintain(viewport: Viewport = null) -> void:
	if mode != Mode.FULLBRIGHT:
		return
	var camera := _viewport(viewport).get_camera_3d()
	if camera != _camera:
		_put_back_camera()
		_grab_camera(_viewport(viewport))


static func _grab_camera(target: Viewport) -> void:
	_camera = target.get_camera_3d()
	if _camera != null:
		_camera_env = _camera.environment
		_camera.environment = fullbright_environment()


static func _put_back_camera() -> void:
	if _camera != null and is_instance_valid(_camera) and _camera.environment == _fullbright_env:
		_camera.environment = _camera_env
	_camera = null
	_camera_env = null


static func _release(target: Viewport) -> void:
	_put_back_camera()
	if _restore_draw >= 0:
		target.debug_draw = _restore_draw as Viewport.DebugDraw
	_restore_draw = -1


static func toggle_fullbright(viewport: Viewport = null) -> void:
	set_mode(Mode.OFF if mode == Mode.FULLBRIGHT else Mode.FULLBRIGHT, viewport)


## Badge suffix while a debug view is on.
static func badge_text() -> String:
	return "" if mode == Mode.OFF else (" // FULLBRIGHT" if mode == Mode.FULLBRIGHT else " // WIREFRAME")


static func ensure_action() -> void:
	if InputMap.has_action(ACTION):
		return
	InputMap.add_action(ACTION)
	var key := InputEventKey.new()
	key.physical_keycode = DEFAULT_KEY
	InputMap.action_add_event(ACTION, key)


static func admin_entries() -> Array:
	return [
		{"heading": "DEBUG VIEW", "permission": "visual"},
		{"label": "TOGGLE FULLBRIGHT", "permission": "visual", "state": func() -> bool: return mode == Mode.FULLBRIGHT,
			"action": func() -> void: toggle_fullbright()},
		{"label": "TOGGLE WIREFRAME", "permission": "visual", "state": func() -> bool: return mode == Mode.WIREFRAME,
			"action": func() -> void: set_mode(Mode.OFF if mode == Mode.WIREFRAME else Mode.WIREFRAME)},
	]
