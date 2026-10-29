class_name AdminPulse3D
extends Node3D

## Admin-only "find this player" marker in the 3D world: a tall beam and two expanding rings drawn through walls (no depth test) at
## the target's position for a few seconds. The host decides who may see one; this node only draws. `follow` returns the target's
## live position (Vector3.INF when unknown, then the position it was given stays).

const BEAM_HEIGHT := 40.0
const RING_PERIOD := 1.1

var seconds_left := 6.0
var follow: Callable
var _beam: MeshInstance3D
var _rings: Array[MeshInstance3D] = []
var _material: StandardMaterial3D
var _age := 0.0


func setup(at: Vector3, seconds: float, follow_source: Callable = Callable()) -> void:
	position = at
	seconds_left = seconds
	follow = follow_source
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.no_depth_test = true
	_material.render_priority = 100
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.albedo_color = Color(0.22, 0.9, 0.85, 0.55)
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.07
	cylinder.bottom_radius = 0.07
	cylinder.height = BEAM_HEIGHT
	_beam = MeshInstance3D.new()
	_beam.mesh = cylinder
	_beam.material_override = _material
	_beam.position = Vector3(0, BEAM_HEIGHT * 0.5, 0)
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)
	for i in 2:
		var torus := TorusMesh.new()
		torus.inner_radius = 0.46
		torus.outer_radius = 0.5
		var ring := MeshInstance3D.new()
		ring.mesh = torus
		ring.material_override = _material.duplicate()
		ring.position = Vector3(0, 0.15 if i == 0 else 1.6, 0)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
		_rings.append(ring)


func _process(delta: float) -> void:
	_age += delta
	seconds_left -= delta
	if seconds_left <= 0.0:
		queue_free()
		return
	if follow.is_valid():
		var live: Vector3 = follow.call()
		if live != Vector3.INF:
			position = live
	var fade := clampf(seconds_left / 1.0, 0.0, 1.0)
	for i in _rings.size():
		var phase := fposmod(_age / RING_PERIOD + float(i) * 0.5, 1.0)
		var scale_value := 0.6 + phase * 4.0
		_rings[i].scale = Vector3(scale_value, 1.0, scale_value)
		var material := _rings[i].material_override as StandardMaterial3D
		material.albedo_color.a = (1.0 - phase) * 0.8 * fade
	_material.albedo_color.a = (0.35 + 0.2 * sin(_age * 7.0)) * fade
