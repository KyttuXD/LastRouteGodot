class_name XRComfort
extends Node

## OpenXR comfort and presentation for the route player (docs/XR_ANDROID.md). Created by PlayerController3D only once
## OpenXR has actually started, so desktop and phone runs never build any of it.
##
##   world scale  the runner is 1.60 m in a world built at hunter scale, whatever the player's real height
##                (Settings.xr_player_height): XROrigin3D.world_scale = PLAYER_HEIGHT / real height
##   seated       lifts the origin by the standing/seated eye difference so a seated player sees from 1.60 m
##   turning      snap (30 degrees, latched) or smooth (Settings.xr_smooth_turn) on the right stick
##   vignette     a soft tunnel in front of the eyes while moving or turning (Settings.xr_vignette)
##   wrist HUD    relays, light charge and stamina on the left wrist

const PLAYER_HEIGHT := 1.60
const SNAP_DEGREES := 30.0
const SMOOTH_TURN_DEGREES_PER_SECOND := 120.0
const SEATED_LIFT := 0.45
const VIGNETTE_MAX := 0.75

const VIGNETTE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, blend_mix, fog_disabled;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	// A ring that darkens toward the edge of view; the centre stays clear.
	float r = length(UV - vec2(0.5)) * 2.0;
	float edge = smoothstep(0.35, 0.95, r);
	ALBEDO = vec3(0.0);
	ALPHA = edge * strength;
}
"""

var player: Node3D
var origin: XROrigin3D
var camera: XRCamera3D
var left: XRController3D
var right: XRController3D
var vignette: MeshInstance3D
var wrist: Label3D
var _turn_latched := false
var _vignette_level := 0.0
var _wrist_left := 0.0


## The origin scale that makes a player of `real_height` metres see the world as a 1.60 m runner (clamped to sane values).
static func world_scale_for(real_height: float) -> float:
	return clampf(PLAYER_HEIGHT / clampf(real_height, 1.0, 2.3), 0.6, 1.6)


## Snap turn: one step per push past the dead zone, latched until the stick returns. Returns radians to turn by.
func snap_turn(stick_x: float) -> float:
	if absf(stick_x) < 0.45:
		_turn_latched = false
		return 0.0
	if _turn_latched:
		return 0.0
	_turn_latched = true
	return deg_to_rad(-SNAP_DEGREES if stick_x > 0.0 else SNAP_DEGREES)


static func smooth_turn(stick_x: float, delta: float) -> float:
	if absf(stick_x) < 0.2:
		return 0.0
	return -deg_to_rad(SMOOTH_TURN_DEGREES_PER_SECOND) * stick_x * delta


func setup(run_player: Node3D, xr_origin: XROrigin3D, xr_camera: XRCamera3D, xr_left: XRController3D, xr_right: XRController3D) -> void:
	player = run_player
	origin = xr_origin
	camera = xr_camera
	left = xr_left
	right = xr_right
	apply_settings()
	vignette = MeshInstance3D.new()
	vignette.name = "ComfortVignette"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	vignette.mesh = quad
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = VIGNETTE_SHADER
	material.shader = shader
	material.render_priority = 120
	vignette.material_override = material
	vignette.position = Vector3(0, 0, -0.12)
	vignette.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	camera.add_child(vignette)
	wrist = Label3D.new()
	wrist.name = "WristHUD"
	wrist.pixel_size = 0.0009
	wrist.font_size = 32
	wrist.outline_size = 6
	wrist.modulate = Color(0.85, 0.95, 1.0)
	wrist.no_depth_test = true
	wrist.position = Vector3(0, 0.03, 0.08)
	wrist.rotation_degrees = Vector3(-70, 0, 0)
	left.add_child(wrist)
	XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, true)


func apply_settings() -> void:
	if origin == null:
		return
	origin.world_scale = world_scale_for(Settings.xr_player_height)
	origin.position.y = SEATED_LIFT if Settings.xr_seated else 0.0


## Called every physics step by the player: turning, the vignette and the wrist readout.
func step(delta: float, moving: bool) -> void:
	var stick_x := right.get_vector2("primary").x
	var turn := smooth_turn(stick_x, delta) if Settings.xr_smooth_turn else snap_turn(stick_x)
	if turn != 0.0:
		player.rotate_y(turn)
	var wanted := 0.0
	if Settings.xr_vignette and (moving or (Settings.xr_smooth_turn and absf(stick_x) >= 0.2)):
		wanted = VIGNETTE_MAX
	_vignette_level = move_toward(_vignette_level, wanted, delta * 4.0)
	(vignette.material_override as ShaderMaterial).set_shader_parameter("strength", _vignette_level)
	vignette.visible = _vignette_level > 0.01
	_wrist_left -= delta
	if _wrist_left <= 0.0:
		_wrist_left = 0.25
		wrist.text = wrist_text()


func wrist_text() -> String:
	var battery := int(round(100.0 * float(player.get("lamp_charge")) / GameConfig.MAX_LAMP_CHARGE))
	var stamina := int(round(100.0 * float(player.get("stamina")) / GameConfig.MAX_STAMINA))
	return "RELAYS %d\nLIGHT %d%%\nSTAMINA %d%%" % [GameState.relays_collected, battery, stamina]


func recenter() -> void:
	XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, true)
