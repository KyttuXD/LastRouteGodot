extends Node3D

## The low rumble of a lava pit, heard within RADIUS of it, every few seconds.

const RADIUS := 26.0
const EVERY := Vector2(5.0, 9.0)

var _left := 1.0


func _process(delta: float) -> void:
	_left -= delta
	if _left > 0.0:
		return
	_left = randf_range(EVERY.x, EVERY.y)
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var distance := global_position.distance_to(camera.global_position)
	if distance < RADIUS:
		var side := (global_position - camera.global_position).dot(camera.global_basis.x)
		Sound.pit_rumble(clampf(side / maxf(distance, 1.0), -1.0, 1.0), clampf(1.3 - distance / RADIUS, .15, 1.3))
