class_name CityRain
extends Node3D

## Rain over the City: one GPUParticles3D box that follows the camera and drops thin unlit streaks. It is a setting
## (Settings.city_rain, the RAIN button on the City menu); indoors the emitter pauses so nothing falls through a roof. No
## post effects, no collision, one draw call.

const COUNT := 900
const BOX := Vector3(26.0, 16.0, 26.0)

var _particles: GPUParticles3D
var indoor_check: Callable = Callable()


func _ready() -> void:
	top_level = true
	_particles = GPUParticles3D.new()
	_particles.name = "Drops"
	_particles.amount = COUNT
	_particles.lifetime = 1.1
	_particles.explosiveness = 0.0
	_particles.visibility_aabb = AABB(-BOX * .5 - Vector3(0, 12, 0), BOX + Vector3(0, 24, 0))
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = BOX * .5
	material.direction = Vector3(0.15, -1.0, 0.05)
	material.spread = 2.0
	material.initial_velocity_min = 14.0
	material.initial_velocity_max = 17.0
	material.gravity = Vector3(0, -4.0, 0)
	_particles.process_material = material
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.03, 0.55)
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.albedo_color = Color(0.72, 0.82, 0.95, 0.42)
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	look.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = look
	_particles.draw_pass_1 = mesh
	_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_particles)


func set_raining(on: bool) -> void:
	_particles.emitting = on
	visible = on


func is_raining() -> bool:
	return _particles.emitting


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	global_position = camera.global_position + Vector3(0, BOX.y * .5, 0)
	if indoor_check.is_valid() and visible:
		var indoors := bool(indoor_check.call(Vector2(camera.global_position.x, camera.global_position.z)))
		_particles.emitting = not indoors
