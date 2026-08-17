class_name HunterJumpscare
extends Node3D

## Local capture presentation. Hunter simulation remains host-authoritative;
## this director clones only the capturing hunter's presentation model beneath
## a temporary camera, so a guest's jumpscare cannot move the shared hunter or
## leak into another runner's view.

var duration := 1.15
var playing := false
var last_hunter_id := ""

var _camera: Camera3D
var _source_camera: Camera3D
var _anchor: Node3D
var _overlay_layer: CanvasLayer
var _overlay: ColorRect


func play(source_camera: Camera3D, hunter_id: String) -> void:
	if playing or source_camera == null:
		return
	playing = true
	last_hunter_id = hunter_id if not hunter_id.is_empty() else HunterRoster.DEFAULT_ID
	_source_camera = source_camera

	# Freeze the exact view at the instant of capture. This is a real camera
	# takeover rather than moving the player controller (which would publish a
	# false transform to the host during co-op).
	_camera = Camera3D.new()
	_camera.name = "JumpscareCamera"
	_camera.fov = source_camera.fov
	add_child(_camera)
	_camera.global_transform = source_camera.global_transform
	_camera.current = true

	_anchor = Node3D.new()
	_anchor.name = "HunterLunge"
	_anchor.position = Vector3(0.14 if abs(last_hunter_id.hash()) % 2 == 0 else -0.14,
		-1.48, -1.85)
	_camera.add_child(_anchor)

	var identity := HunterRoster.get_identity(last_hunter_id)
	var model := ModelSlot.instantiate(String(identity.get("model_scene", "")))
	if model != null:
		model.name = "JumpscareHunter"
		model.rotation.y = PI
		_anchor.add_child(model)
		var animation := ModelSlot.find_animation_player(model)
		# Authored models can opt into a dedicated clip without changing this
		# system. The current full roster has chase, which keeps every model alive
		# during the code-driven lunge instead of freezing in a rest pose.
		if animation != null and animation.has_animation("jumpscare"):
			animation.play("jumpscare")
		else:
			ModelSlot.play_if_available(animation, "chase")

	var light := OmniLight3D.new()
	light.name = "JumpscareLight"
	light.light_color = Color(0.95, 0.28, 0.35)
	light.light_energy = 4.5
	light.omni_range = 4.0
	light.position = Vector3(0, 0.2, 0.2)
	_camera.add_child(light)

	_overlay_layer = CanvasLayer.new()
	_overlay_layer.name = "JumpscareOverlay"
	_overlay_layer.layer = 115
	add_child(_overlay_layer)
	_overlay = ColorRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.color = Color(0.55, 0.01, 0.035, 0.0)
	_overlay_layer.add_child(_overlay)

	# A fast approach, asymmetric tilt and a close final snap reads cleanly with
	# every block-model silhouette. The id-derived side makes repeated hunters
	# consistent without using nondeterministic camera motion.
	var side := 1.0 if abs(last_hunter_id.hash()) % 2 == 0 else -1.0
	var lunge := create_tween().set_parallel(true)
	lunge.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	lunge.tween_property(_anchor, "position", Vector3(0, -1.5, -0.46),
		duration * 0.78)
	lunge.tween_property(_anchor, "rotation:z", side * 0.16, duration * 0.52)
	lunge.tween_property(_anchor, "scale", Vector3.ONE * 1.08, duration * 0.78)

	var shake := create_tween()
	shake.tween_property(_camera, "rotation",
		Vector3(-0.025, side * 0.035, side * 0.025), duration * 0.20)
	shake.tween_property(_camera, "rotation",
		Vector3(0.035, -side * 0.045, -side * 0.04), duration * 0.18)
	shake.tween_property(_camera, "rotation", Vector3.ZERO, duration * 0.18)

	var flash := create_tween()
	flash.tween_property(_overlay, "color:a", 0.38, duration * 0.18)
	flash.tween_property(_overlay, "color:a", 0.05, duration * 0.20)
	flash.tween_property(_overlay, "color:a", 0.72, duration * 0.30)
	flash.tween_property(_overlay, "color", Color(0.0, 0.0, 0.0, 1.0),
		duration * 0.25)

	await get_tree().create_timer(duration).timeout
	_cleanup()


func _cleanup() -> void:
	if _source_camera != null and is_instance_valid(_source_camera):
		_source_camera.current = true
	if _camera != null:
		_camera.queue_free()
	if _overlay_layer != null:
		_overlay_layer.queue_free()
	_camera = null
	_source_camera = null
	_anchor = null
	_overlay_layer = null
	_overlay = null
	playing = false
