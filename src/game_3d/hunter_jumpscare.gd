class_name HunterJumpscare
extends Node3D

## Local capture presentation. Hunter simulation remains host-authoritative;
## this director clones only the capturing hunter's presentation model beneath
## a private, pitch-black backdrop rather than the real level, so a guest's
## jumpscare cannot move the shared hunter, leak into another runner's view,
## or read differently depending on where in the facility the grab happened.

## Godot render layers are 1-indexed in the editor; this is that layer's bit
## value. Only the presentation's own camera and model use it, so the camera
## can sit inside the real level yet never render any of it.
const PRESENTATION_LAYER := 1 << 18

## Jumpscares are switched OFF: a catch goes straight to the game-over screen with no lunge, clip or
## sting. Set true to bring the whole presentation (hold during the struggle, lunge, audio) back.
const ENABLED := false

var duration := 1.15
var playing := false
## True for the sustained "grabbed" hold shown while an escape struggle is
## running; play() continues the same presentation into its final hit.
var holding := false
var last_hunter_id := ""

var _camera: Camera3D
var _source_camera: Camera3D
var _owns_source_camera := false
var _anchor: Node3D
var _overlay_layer: CanvasLayer
var _overlay: ColorRect
var _hold_tween: Tween


# Per-hunter/categorised camera and overlay tuning. A small default covers the
# whole roster; specific ids or categories (e.g. void) can override parts.
const JUMPSCARE_PROFILES := {
	# Catch-all for A-Z hunters
	"_default": {
		"duration": 1.15,
		"anchor_start": Vector3(0.14, -1.48, -1.85),
		"anchor_end": Vector3(0.00, -1.50, -0.46),
		"roll": 0.16,
		"scale": 1.08,
		"light_color": Color(0.95, 0.28, 0.35),
		"light_energy": 9.0,
		"light_range": 4.0,
		"overlay_tint": Color(0.55, 0.01, 0.035),
	},
	# Stronger, faster impact for the Void family
	"_void": {
		"duration": 0.95,
		"anchor_start": Vector3(0.18, -1.45, -1.75),
		"anchor_end": Vector3(0.00, -1.48, -0.40),
		"roll": 0.22,
		"scale": 1.14,
		"light_color": Color(0.98, 0.12, 0.18),
		"light_energy": 11.0,
		"light_range": 4.8,
		"overlay_tint": Color(0.70, 0.02, 0.03),
	},
	# Example bespoke A-Z tweaks (feel free to add more)
	"elise": {
		"duration": 1.20,
		"roll": 0.18,
		"scale": 1.10,
		"overlay_tint": Color(0.58, 0.06, 0.10),
	},
	"quenelle": {
		"duration": 1.05,
		"roll": 0.14,
		"scale": 1.06,
		"overlay_tint": Color(0.50, 0.04, 0.08),
	},
}


func _profile_for(id: String) -> Dictionary:
	var identity := HunterRoster.get_identity(id)
	var category := String(identity.get("category", "az"))
	if JUMPSCARE_PROFILES.has(id):
		return (JUMPSCARE_PROFILES[id] as Dictionary)
	if category == "void" and JUMPSCARE_PROFILES.has("_void"):
		return (JUMPSCARE_PROFILES["_void"] as Dictionary)
	return (JUMPSCARE_PROFILES["_default"] as Dictionary)


## Builds the isolated camera, model, light and flash overlay shared by both
## the sustained grab hold and the final jumpscare hit.
func _build_presentation(source_camera: Camera3D, hunter_id: String) -> void:
	if source_camera == null:
		source_camera = get_viewport().get_camera_3d()
	if source_camera == null:
		# A capture must never become an unpresented report just because the
		# active camera is between rigs. Keep a local camera alive for the
		# presentation; the overlay and fallback silhouette still communicate
		# the grab even when the source rig is unavailable.
		source_camera = Camera3D.new()
		source_camera.global_transform = Transform3D.IDENTITY
		source_camera.fov = 75.0
		add_child(source_camera)
		_owns_source_camera = true
	last_hunter_id = hunter_id if not hunter_id.is_empty() else HunterRoster.DEFAULT_ID
	_source_camera = source_camera

	# Freeze the exact view direction/FOV at the instant of capture, but never
	# the real level behind it: a private black backdrop plus a render layer
	# only this presentation uses means nothing else in the world can show
	# through, no matter where in the facility the grab happened.
	_camera = Camera3D.new()
	_camera.name = "JumpscareCamera"
	_camera.fov = source_camera.fov
	var backdrop := Environment.new()
	backdrop.background_mode = Environment.BG_COLOR
	backdrop.background_color = Color.BLACK
	backdrop.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# a faint red ambient so the dark cube textures still read as a figure, not just their eyes
	backdrop.ambient_light_color = Color(.55, .12, .14)
	backdrop.ambient_light_energy = .55
	backdrop.fog_enabled = false
	backdrop.glow_enabled = false
	_camera.environment = backdrop
	_camera.cull_mask = PRESENTATION_LAYER
	add_child(_camera)
	_camera.global_transform = source_camera.global_transform
	_camera.current = true

	_anchor = Node3D.new()
	_anchor.name = "HunterLunge"
	# Per-hunter profile (duration, anchor motion, roll, scale, tint)
	var profile := _profile_for(last_hunter_id)
	# Never so quick it reads as a flicker, even for the faster Void profiles.
	duration = maxf(float(profile.get("duration", duration)), 1.0)
	var side := 1.0 if abs(last_hunter_id.hash()) % 2 == 0 else -1.0
	var start: Vector3 = profile.get("anchor_start", Vector3(0.14, -1.48, -1.85))
	start.x *= side
	_anchor.position = start
	_camera.add_child(_anchor)

	var identity := HunterRoster.get_identity(last_hunter_id)
	var model := ModelSlot.instantiate_hunter(identity)
	if model != null:
		model.name = "JumpscareHunter"
		model.rotation.y = PI
		_anchor.add_child(model)
		var animation := ModelSlot.find_animation_player(model)
		# Authored models can opt into a dedicated clip without changing this
		# system. The current full roster has chase, which keeps every model alive
		# during the code-driven lunge instead of freezing in a rest pose.
		var capture_clip := ""
		for clip in ["jumpscare", "grab", "capture", "chase"]:
			if animation != null and animation.has_animation(clip):
				capture_clip = clip
				break
		if not capture_clip.is_empty():
			animation.play(capture_clip)
	else:
		# Guaranteed fallback: show a simple silhouetted figure so the player
		# always sees a jumpscare even when a model/animation is missing.
		var box := MeshInstance3D.new()
		box.name = "JumpscareFallback"
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.7, 1.7, 0.4)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.10, 0.10, 0.12)
		mat.roughness = 0.95
		box.mesh = mesh
		box.set_surface_override_material(0, mat)
		box.rotation.y = PI
		_anchor.add_child(box)
	_apply_presentation_layer(_anchor)

	var light := OmniLight3D.new()
	light.name = "JumpscareLight"
	light.light_color = profile.get("light_color", Color(0.95, 0.28, 0.35))
	light.light_energy = float(profile.get("light_energy", 4.5))
	light.omni_range = float(profile.get("light_range", 4.0))
	light.position = Vector3(0, 0.2, 0.2)
	_camera.add_child(light)

	_overlay_layer = CanvasLayer.new()
	_overlay_layer.name = "JumpscareOverlay"
	_overlay_layer.layer = 115
	add_child(_overlay_layer)
	_overlay = ColorRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tint: Color = profile.get("overlay_tint", Color(0.55, 0.01, 0.035))
	_overlay.color = Color(tint.r, tint.g, tint.b, 0.0)
	_overlay_layer.add_child(_overlay)


## Only VisualInstance3D nodes carry a render layer; an imported multi-mesh
## model needs every descendant tagged, not just its root.
static func _apply_presentation_layer(node: Node) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = PRESENTATION_LAYER
	for child in node.get_children():
		_apply_presentation_layer(child)


## Sustained "grabbed" pose shown for as long as an escape struggle runs.
## Follow with stop_hold() on a successful struggle, or play() to continue
## straight into the final hit.
func start_hold(source_camera: Camera3D, hunter_id: String) -> void:
	last_hunter_id = hunter_id if not hunter_id.is_empty() else HunterRoster.DEFAULT_ID
	if not ENABLED:
		return
	while playing or holding:
		await get_tree().process_frame
	holding = true
	_build_presentation(source_camera, hunter_id)
	_hold_tween = create_tween().set_loops()
	_hold_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var held_y := _anchor.position.y
	_hold_tween.tween_property(_anchor, "position:y", held_y + 0.03, 0.6)
	_hold_tween.tween_property(_anchor, "position:y", held_y, 0.6)
	_overlay.color.a = 0.22


## Releases a grab hold without playing the final hit (a successful escape).
func stop_hold() -> void:
	if not holding:
		return
	holding = false
	if _hold_tween != null:
		_hold_tween.kill()
		_hold_tween = null
	if _overlay != null:
		var fade := create_tween()
		fade.tween_property(_overlay, "color:a", 0.0, 0.25)
		await fade.finished
	_cleanup()


func play(source_camera: Camera3D, hunter_id: String) -> void:
	last_hunter_id = hunter_id if not hunter_id.is_empty() else HunterRoster.DEFAULT_ID
	if not ENABLED:
		return
	# Capture events can arrive twice while a host and guest resolve the same
	# grab. Do not let the second call turn the first presentation into an
	# immediate game-over transition.
	while playing:
		await get_tree().process_frame
	if holding:
		# Continue the hold already on screen into its final hit instead of
		# tearing down and rebuilding the presentation.
		if _hold_tween != null:
			_hold_tween.kill()
			_hold_tween = null
		holding = false
	else:
		_build_presentation(source_camera, hunter_id)
	playing = true

	var profile := _profile_for(last_hunter_id)
	var side := 1.0 if abs(last_hunter_id.hash()) % 2 == 0 else -1.0

	# A fast approach, asymmetric tilt and a close final snap reads cleanly with
	# every block-model silhouette. The id-derived side makes repeated hunters
	# consistent without using nondeterministic camera motion.
	var lunge := create_tween().set_parallel(true)
	lunge.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	var end: Vector3 = profile.get("anchor_end", Vector3(0.0, -1.50, -0.46))
	end.x *= side
	lunge.tween_property(_anchor, "position", end, duration * 0.78)
	var roll := float(profile.get("roll", 0.16))
	lunge.tween_property(_anchor, "rotation:z", side * roll, duration * 0.52)
	var scl := float(profile.get("scale", 1.08))
	lunge.tween_property(_anchor, "scale", Vector3.ONE * scl, duration * 0.78)

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
	if not _owns_source_camera and _source_camera != null \
			and is_instance_valid(_source_camera):
		_source_camera.current = true
	if _camera != null:
		_camera.queue_free()
	if _owns_source_camera and _source_camera != null:
		_source_camera.queue_free()
	if _overlay_layer != null:
		_overlay_layer.queue_free()
	_camera = null
	_source_camera = null
	_owns_source_camera = false
	_anchor = null
	_overlay_layer = null
	_overlay = null
	playing = false
	holding = false
