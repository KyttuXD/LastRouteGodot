class_name HunterView3D
extends CharacterBody3D

## Thin 3D presentation wrapper around a HunterBrain: reads its grid-space
## `position`/`state` each frame and converts to world space (1 cell = 1
## meter, same convention as facility_view_3d.gd) plus a named animation.
## Which model to show comes from HunterRoster by `brain.hunter_id` — extend
## HunterRoster to add a hunter's model, nothing here needs to change.
##
## Umbriel is the one hunter whose *appearance* changes at runtime: her
## gimmick picks a `disguise_id` on a timer, which is presentation-only (on
## Standard she keeps all her own stats), so it's resolved here rather than in
## the brain.

var brain: HunterBrain
var surface_height_provider: Callable
## True while on a sewer ladder (set_climbing).
var climbing := false
## The clip played while `climbing`: "climb" on a ladder, "walk" down a ramp tunnel.
var climb_clip := "climb"
var _collider: CollisionShape3D
## Host-selected runner this brain is currently evaluating. Replicated with
## presentation state so only the pursued client receives chase audio.
var target_peer_id := 0
var has_look_target := false
var look_target_position := Vector2.ZERO

var _animation_player: AnimationPlayer
var _model: Node3D
var _shown_id := ""
var _flight := XivvyFlight.new()
var _flight_headroom := INF
var _flight_probe := 0.0
var _flight_yaw_last := 0.0
var _flight_was_flying := false
var _screech_cooldown := 0.0
var _flight_shadow: MeshInstance3D
var _wing_nodes: Array = []
var _wings_searched := false
var _wing_fold_applied := 0.0
var _desired_xz := Vector2.ZERO
var _surface_target_y := 0.0
var _streamed_height_override := 0.0
var _streamed_height_override_active := false
var _presentation_initialized := false
var _heading_initialized := false
var _head_node: Node3D
var _facing := HunterFacing.new()
## Night Watch: a pose from NightWatchPoses held until stop() (one-shots end on their own), and the
## procedural breathing / sway / lean layers (off elsewhere).
var nw_pose := ""
var _peek_pose := ""
## The scare beat: the local camera caught her head round a corner (once per peek).
signal peek_spotted(view: HunterView3D)
var _peek_spotted := false
const PEEK_SPOT_RANGE := 16.0
## The duck / shoulder turn through door frames (docs/DOORWAY_CLEARANCE.md); only humanoid rigs bind it.
var _doorway := DoorwayPose.new()
var nw_pose_opts := {}
var nw_layers := false
var _nw_started := ""
var _nw_layers := NightWatchPoseLayers.new()
## Per-hunter chase style (HunterChaseStyle): an upper-body layer over the chase clip. GRAB can switch it off for a
## grab (it blends out over a third of a second rather than popping).
var _chase := HunterChaseStyle.new()
var chase_layer_enabled := true
var _nw_last_yaw := 0.0
var _head_rest_q := Quaternion.IDENTITY
var _head_written_q := Quaternion.IDENTITY
var _kathy_beam: SpotLight3D
## While a grab holds a runner (HunterGrab marks it every frame it poses this hunter) Kathy's beam is off entirely (KT).
var grab_until_msec := 0
var _carries_scythe := false
var _was_stunned := false
var _recover_left := 0.0
var _expression := ""
var _blink_timer := 2.0
var _scream_latched := false
var _leap_seq_seen := 0
var _face_node: MeshInstance3D
var _gait_moving := false
var _stride_scale := 1.0
var _face_hold := 0.0
var _blink_left := 0.0
var _stars: Node3D
var _creature: CreatureView   # set for creature-rig hunters (SecretCreatures); the humanoid logic is skipped
## Kathy's visible beam: an unshaded additive cone (soft core + wider outer shell) hanging from the eye beam light. It is
## the light's colour while she patrols and turns RED (brighter, faster pulse) while she is chasing; no extra lights.
var _beam_core: MeshInstance3D
var _beam_shell: MeshInstance3D
var _beam_color := Color.WHITE
var _beam_neutral := Color.WHITE
var _beam_chase_mix := 0.0
## Emote presentation (see HunterEmoteCatalog). Driven by brain.emote_* so guests replay what the host decided.
var _emote_seen_seq := -1
var _emote_index := -1
var _emote_until_msec := 0
var _emote_clip := ""
var _emote_clip_started := false
var _move_speed := 0.0
## Seconds the body has barely moved; a walk/chase clip held past STILL_CLIP_AFTER would read as walking in place.
var _still_time := 0.0
const STILL_CLIP_AFTER := 0.35
const STILL_SPEED := 0.15
const SURVEY_INTERVAL := .1
## A frame-to-frame jump of her brain position beyond this is a teleport, not movement.
const TELEPORT_DISTANCE := 4.0
const SURVEY_DISTANCES := [0.0, 1.5, 3.0, 4.5, 6.0, 8.0, 10.0, 12.0]
## She starts walking above this ground speed (see the idle/walk hysteresis in _update_animation).
const GAIT_ENTER_SPEED := .35
const TRAVEL_BLEND := .15
var _last_brain_position := Vector2.ZERO
var _speed_primed := false

## Kathy (and Umbriel disguised as her) carries her scythe in the right hand: the model has a
## R-HandProp locator and scythe_idle / scythe_walk / scythe_swing clips for carrying it.
const BEAM_CHASE_COLOR := Color(1.0, .10, .08)
const BEAM_SHELL_RADIUS_CAP := 1.5
const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 beam_color : source_color = vec4(1.0);
uniform float strength = 1.0;
uniform float length_m = 11.5;
uniform float pulse_speed = 3.0;
varying float along;
void vertex() {
	along = clamp(0.5 - VERTEX.y / length_m, 0.0, 1.0);
}
void fragment() {
	// KT: a blocky beam -- a 4-sided frustum. Each face fades out toward its two edges (UV.x runs once round the
	// mesh, a quarter per face), so the square silhouette stays soft, plus a mild view-angle term.
	float e = fract(UV.x * 4.0);
	float edge = pow(smoothstep(0.0, 0.5, min(e, 1.0 - e)), 1.6);
	float facing = mix(0.55, 1.0, clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0));
	float pulse = 1.0 + 0.14 * sin(TIME * pulse_speed);
	// a camera inside or right next to the beam sees it fade away instead of filling the screen
	float near_fade = smoothstep(0.4, 3.0, length(VERTEX));
	// voxel-like steps along its length: the fade drops in eight blocks rather than a smooth ramp
	float stepped = mix(along, floor(along * 8.0) / 8.0, 0.6);
	ALBEDO = beam_color.rgb;
	ALPHA = clamp(strength * pulse * edge * facing * near_fade * (1.0 - smoothstep(0.0, 1.0, stepped) * 0.9), 0.0, 0.35);
}
"""
const SCYTHE_PATH := "res://assets/props_3d/kathy_scythe.glb"
## While she carries it, a chase uses the scythe walk played this much faster.
const SCYTHE_CHASE_SPEED := 1.8
## Chasing hunters switch to the wide-eyed scream face this close to the runner (grid cells).
const SCREAM_DISTANCE := 2.6
const FACE_HOLD := .45
const STAR_COUNT := 3
const STAR_ORBIT_RADIUS := .34
## Presentation height follows the floor at this rate (m/s); deeper than FALL_RECOVERY_DEPTH below it counts as a recovery.
const SETTLE_SPEED := 14.0
const FALL_RECOVERY_DEPTH := 1.0
const MAX_PRESENTATION_SPEED := 12.0
const PRESENTATION_DEAD_ZONE := .006
## View collider: slightly wider than the brain footprint (GameConfig.HUNTER_RADIUS) and as tall as the scaled model.
const HUNTER_BODY_RADIUS := GameConfig.HUNTER_RADIUS + .05
## Beyond this distance from the camera nobody sees the doorway pose, so it is not worked out.
const DOORWAY_POSE_RANGE := 45.0
const HUNTER_BODY_HEIGHT := 1.72 * HunterRoster.MODEL_SCALE
## Body yaw / head look live in HunterFacing so other creature views share them.



func _ready() -> void:
	add_to_group("hunter_views")
	# AnimationPlayer updates at the default process priority. Apply the
	# presentation-only neck look afterward so clips keep their pitch/roll while
	# the head can scan independently from the body.
	process_priority = 50
	collision_layer = 1
	collision_mask = 1
	floor_snap_length = .32
	floor_max_angle = deg_to_rad(50.0)
	safe_margin = .035
	var collider := CollisionShape3D.new()
	collider.name = "HunterCollision"
	_collider = collider
	var capsule := CapsuleShape3D.new()
	capsule.radius = HUNTER_BODY_RADIUS
	capsule.height = HUNTER_BODY_HEIGHT
	collider.shape = capsule
	collider.position.y = HUNTER_BODY_HEIGHT * .5
	add_child(collider)
	_apply_model(_desired_model_id())


func _process(delta: float) -> void:
	_update_lens_cull()
	_end_grab_pose(delta)
	_doorway.restore()
	_chase.restore()
	_update_head_look(delta)
	_update_chase_style(delta)
	_update_nw_layers(delta)
	_update_beam_visual(delta)
	_update_expression(delta)
	_update_stars(delta)
	_update_doorway(delta)


## Lens culling in normal play (KT: Verrine up close showed the inside of her body as white and grey bands). A hunter's arms reach
## right up to the runner's face, so the camera's near plane can slice through a cube and draw its inside. Any box of her model the
## near plane is inside (or within LENS_MARGIN of) is drawn on a layer the viewing camera skips, for that frame only, and put back
## the next; her light and shadow are untouched. Grabs do the same for themselves (HunterGrab._cull_near).
const LENS_LAYER := 1 << 16
const LENS_RANGE := 3.0
const LENS_MARGIN := .02
var _lens_culled: Array = []


func _update_lens_cull() -> void:
	for node in _lens_culled:
		if is_instance_valid(node) and (node as Node).has_meta("lens_layers"):
			(node as MeshInstance3D).layers = int((node as Node).get_meta("lens_layers"))
			(node as Node).remove_meta("lens_layers")
	_lens_culled.clear()
	if _model == null or not is_inside_tree() or grabbing():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var at := camera.global_position
	if at.distance_squared_to(global_position) > LENS_RANGE * LENS_RANGE:
		return
	camera.cull_mask &= ~LENS_LAYER
	var reach := camera.near + LENS_MARGIN
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null or not mesh_node.visible or mesh_node.has_meta("grab_layers"):
			continue
		var transform := mesh_node.global_transform
		if absf(transform.basis.determinant()) < 1e-9:
			continue
		var scale := transform.basis.get_scale()
		var local := transform.affine_inverse() * at
		if mesh_node.mesh.get_aabb().grow(reach / maxf(minf(scale.x, minf(scale.y, scale.z)), .001)).has_point(local):
			mesh_node.set_meta("lens_layers", mesh_node.layers)
			mesh_node.layers = LENS_LAYER
			_lens_culled.append(mesh_node)


## In a door frame: duck under a low lintel and turn the shoulders through a narrow opening (DoorwayPose), last of
## the layers so it bends whatever the clip and the head look made of the pose.
func _update_doorway(delta: float) -> void:
	if _model == null or not _doorway.bound() or not is_inside_tree():
		return
	var camera := get_viewport().get_camera_3d()
	if camera != null and global_position.distance_squared_to(camera.global_position) > DOORWAY_POSE_RANGE * DOORWAY_POSE_RANGE:
		return
	var frame := DoorwayFrames.nearest(global_position)
	_doorway.update(delta, frame, float(frame.get("along", INF)))


func _physics_process(delta: float) -> void:
	if brain == null or not _presentation_initialized:
		return
	var planar := _desired_xz - Vector2(position.x, position.z)
	if planar.length() < PRESENTATION_DEAD_ZONE:
		# Sub-centimetre corrections (network rounding, interpolation noise) are applied directly: feeding them to
		# move_and_slide made the body creep within its safe margin and bob up and down while she stood.
		position.x = _desired_xz.x
		position.z = _desired_xz.y
		planar = Vector2.ZERO
	var wanted_velocity := planar / maxf(delta, .001)
	wanted_velocity = wanted_velocity.limit_length(MAX_PRESENTATION_SPEED)
	velocity.x = wanted_velocity.x
	velocity.z = wanted_velocity.y
	if _streamed_height_override_active:
		# Stair travel supplies the authored ramp height. Gravity resumes as soon
		# as both feet reach the destination floor.
		position.y = _streamed_height_override
		velocity.y = 0.0
	elif brain.gimmick is XivvyGimmick \
			and ((brain.gimmick as XivvyGimmick).airborne() or _flight.altitude > 0.0):
		# airborne: follow the flight altitude (also while she settles back down after the flag drops)
		position.y = move_toward(position.y, _surface_target_y, delta * 6.0)
		velocity.y = 0.0
	else:
		# Hunters are grid simulations on a flat level floor: their height is the floor height, never physics. A body
		# that fell under gravity dropped through the map as soon as the chunk beneath it had no collider (far hunters,
		# chunks still streaming, a chunk freed under her). Collision stays for the planar slide against loaded walls.
		if position.y < _surface_target_y - FALL_RECOVERY_DEPTH:
			brain.fall_recoveries += 1   # safety net: should never happen now, counted for the admin list and the tests
		position.y = move_toward(position.y, _surface_target_y, delta * SETTLE_SPEED)
		velocity.y = 0.0
	# The floor snap would pull a flying hunter back to the floor every step.
	floor_snap_length = 0.0 if _flight.altitude > .02 else .32
	move_and_slide()
	if not _streamed_height_override_active and position.y < _surface_target_y - FALL_RECOVERY_DEPTH:
		position.y = _surface_target_y
		velocity.y = 0.0


## On a sewer ladder (LadderTraffic): the body rises or sinks with the climb,
## faces the rungs, plays the climb clip and has no collision, so the maze floor
## collider over the shaft does not push her back out.
## Asleep in a bed (HunterNaps, docs/REST_AND_SLEEP.md): the model lies on its back along the bed (head toward the
## headboard), on the mattress. Set every sync by the host and from the hunter report on guests.
var _asleep := false
var _sleep_yaw := 0.0
const SLEEP_MATTRESS_Y := .62


var _sleep_stage := 0


func set_asleep(on: bool, yaw: float = 0.0, stage: int = 0) -> void:
	_asleep = on
	_sleep_yaw = yaw
	_sleep_stage = stage if on else 0
	_apply_sleep_pose()


## HunterNaps wake meter: 0 sound asleep, 1 stirring, 2 turned over, 3 snore stopped.
func sleep_stage() -> int:
	return _sleep_stage


func is_asleep() -> bool:
	return _asleep


func _apply_sleep_pose() -> void:
	if _model == null or not is_instance_valid(_model):
		return
	if _asleep:
		if not _model.has_meta("awake_position"):
			_model.set_meta("awake_position", _model.position)
		rotation.y = _sleep_yaw
		_model.rotation.x = PI * .5
		# turned over onto one side once the meter passes the second cue
		_model.rotation.z = .55 if _sleep_stage >= 2 else (.08 * sin(float(Time.get_ticks_msec()) * .004) if _sleep_stage == 1 else 0.0)
		var length := 1.8 * _model.scale.y
		_model.position = (_model.get_meta("awake_position") as Vector3) + Vector3(0.0, SLEEP_MATTRESS_Y, -length * .5)
	elif _model.has_meta("awake_position"):
		_model.rotation.x = 0.0
		_model.rotation.z = 0.0
		_model.position = _model.get_meta("awake_position")
		_model.remove_meta("awake_position")


## Seated on a seat (HunterSeats, docs/SEATING.md): facing out of the seat, in the shared "sit" pose. Set every sync by
## the host and from the hunter report on guests.
var _seated := false


func set_seated(on: bool, yaw: float = 0.0) -> void:
	if on:
		rotation.y = yaw
		if nw_pose != HunterSeats.POSE:
			NightWatchPoses.play(self, HunterSeats.POSE)
	elif _seated and nw_pose == HunterSeats.POSE:
		NightWatchPoses.stop(self)
	_seated = on


func is_seated() -> bool:
	return _seated


func set_climbing(on: bool, height: float = 0.0, facing_yaw: float = 0.0, clip: String = "climb") -> void:
	climb_clip = clip
	if on:
		set_streamed_height_override(height)
		rotation.y = facing_yaw
	elif climbing:
		clear_streamed_height_override()
	climbing = on
	if _collider != null:
		_collider.disabled = on


func set_streamed_height_override(height: float) -> void:
	_streamed_height_override = height
	_streamed_height_override_active = true


func clear_streamed_height_override() -> void:
	_streamed_height_override_active = false
	velocity.y = 0.0


func _desired_model_id() -> String:
	if brain == null:
		return HunterRoster.DEFAULT_ID
	if brain.gimmick is UmbrielGimmick:
		var disguise: String = brain.gimmick.disguise_id
		if not disguise.is_empty():
			return disguise
	return brain.hunter_id


func _apply_model(model_id: String) -> void:
	if model_id == _shown_id:
		return
	_shown_id = model_id
	if _model:
		_model.queue_free()
		_model = null
		_animation_player = null
		_head_node = null
		_kathy_beam = null
		_beam_core = null
		_beam_shell = null
		_carries_scythe = false
		_expression = ""
		_stars = null
		_creature = null
		_doorway = DoorwayPose.new()
		_wing_nodes.clear()
		_wings_searched = false
		_wing_fold_applied = 0.0

	var identity := HunterRoster.get_identity(model_id)
	_model = ModelSlot.instantiate_hunter(identity)
	if _model:
		_model.scale = Vector3.ONE * HunterRoster.scale_for(model_id)   # feet stay on the origin, so the body grows upward
		add_child(_model)
		_animation_player = ModelSlot.find_animation_player(_model)
		if SecretCreatures.uses_creature_rig(model_id):
			_creature = CreatureView.new(self, _model)
		else:
			NightWatchPoses.install(_model, _animation_player, _shown_id)
			_doorway.bind(_model)
			_nw_layers.bind(_model)
			_chase.bind(_model)
			_nw_layers.phase = float(abs(hash(_shown_id)) % 628) / 100.0
		_configure_character_lights()
		_attach_scythe()
		_apply_visibility()


func _attach_scythe() -> void:
	_carries_scythe = false
	# Rare: only some Kathys carry it (seeded per spawn, the same on every peer); the rest are unarmed.
	if _shown_id != "kathy" or brain == null or not HunterRoster.carries_scythe(brain.spawn_seed_text) \
			or _animation_player == null \
			or not _animation_player.has_animation("scythe_idle"):
		return
	var hand := _model.find_child("R-HandProp", true, false) as Node3D
	if hand == null:
		return
	var scythe := ModelSlot.instantiate(SCYTHE_PATH)
	if scythe == null:
		return
	scythe.name = "KathyScythe"
	hand.add_child(scythe)
	_carries_scythe = true


func set_look_target(value: Variant) -> void:
	has_look_target = value is Vector2
	if has_look_target:
		look_target_position = value


func _configure_character_lights() -> void:
	_head_node = _model.find_child("Head", true, false) as Node3D
	if _head_node == null:
		return
	_head_rest_q = _head_node.quaternion
	_head_written_q = _head_rest_q
	_facing.phase = float(abs(hash(brain.hunter_id if brain != null else _shown_id)) % 628) \
		/ 100.0
	# Glow eyes belong to the authored A-Z maze roster. Void/office hunters keep
	# the eyes painted into their own skins; synthetic attachments both obscured
	# those textures and made several dark Void faces look mis-mapped.
	if not HunterRoster.A_Z_IDS.has(_shown_id):
		return
	var eye_color := HunterRoster.eye_glow_color(_shown_id)
	var head_bounds := (_head_node as MeshInstance3D).get_aabb() \
		if _head_node is MeshInstance3D else AABB(
			Vector3(-.257812, .103125, -.275),
			Vector3(.515625, .48125, .48125))
	# No glowing eye quads any more: the faces carry their own eyes. The eye locators are only used to
	# place Kathy's beam.
	var corrected_eye_y := 0.0
	var corrected_eye_count := 0
	for attachment_name in ["L-Eye-Attachment", "R-Eye-Attachment"]:
		var attachment := _head_node.find_child(attachment_name, true, false) as Node3D
		if attachment == null:
			continue
		corrected_eye_y += attachment.position.y
		corrected_eye_count += 1
	if brain != null and brain.hunter_id == "kathy":
		_kathy_beam = SpotLight3D.new()
		_kathy_beam.name = "KathyEyeBeam"
		_kathy_beam.position = Vector3(0.0,
			corrected_eye_y / float(corrected_eye_count) if corrected_eye_count > 0 \
			else head_bounds.position.y + head_bounds.size.y * .31,
			head_bounds.position.z - .015)
		_kathy_beam.light_color = eye_color
		_kathy_beam.light_energy = 5.0
		_kathy_beam.spot_range = GameConfig.KATHY_BEAM_RANGE
		_kathy_beam.spot_angle = rad_to_deg(GameConfig.KATHY_BEAM_HALF_ANGLE) + 3.0
		_kathy_beam.spot_angle_attenuation = 1.35
		_kathy_beam.shadow_enabled = true
		_kathy_beam.shadow_bias = .25
		# The light stays round: a square projector cookie would match the blocky beam, but the project's Compatibility
		# renderer does not draw spot projectors (tried; the footprint just came out round and wider).
		_head_node.add_child(_kathy_beam)
		_beam_neutral = eye_color
		_beam_color = eye_color
		_beam_chase_mix = 0.0
		_build_beam_visual()


func _build_beam_visual() -> void:
	var length := GameConfig.KATHY_BEAM_RANGE
	# a square frustum: CylinderMesh with 4 sides has its corners on the radius, so a half-width w needs radius w * sqrt 2
	var shell_radius := minf(length * tan(GameConfig.KATHY_BEAM_HALF_ANGLE), BEAM_SHELL_RADIUS_CAP) * sqrt(2.0)
	var shader := Shader.new()
	shader.code = BEAM_SHADER
	for part in ["Shell", "Core"]:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = shell_radius if part == "Shell" else shell_radius * .28
		cone.height = length
		cone.radial_segments = 4   # square (KT: blocky), edges softened per face in the shader
		cone.rings = 1
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("length_m", length)
		var instance := MeshInstance3D.new()
		instance.name = "Beam" + part
		instance.mesh = cone
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# the cone's apex sits at the eye and it opens along the light's -Z
		# the 45 degree twist puts the square's sides level with her head, not its corners
		instance.basis = Basis(Vector3.RIGHT, PI * .5) * Basis(Vector3.UP, PI * .25)
		instance.position = Vector3(0, 0, -length * .5)
		_kathy_beam.add_child(instance)
		if part == "Shell":
			_beam_shell = instance
		else:
			_beam_core = instance
	_update_beam_visual(0.0)


## Neutral colour while patrolling, red while chasing; the light itself follows so the lit floor matches the beam.
func grabbing() -> bool:
	return Time.get_ticks_msec() < grab_until_msec


## Once a grab (on this peer or drawn for another) lets go of her, her model, arms and stretch ease back over
## GRAB_EASE_SECONDS from where the grab last posed them to where she is and what her clip does: nothing pops, on any
## machine. Checked after everything else this frame (deferred: a guest's copy of the grab poses her deferred too), so a
## frame she is still held is never eased.
const GRAB_EASE_SECONDS := .45
var _grab_ease := 0.0
var _grab_ease_from := {}
var _grab_ease_delta := 0.0


func _end_grab_pose(delta: float) -> void:
	if _model == null:
		return
	if _model.has_meta("grab_rest") or _grab_ease > 0.0:
		_grab_ease_delta = delta
		# twice deferred: after every first-level deferred call this frame, a guest's posing of her among them
		(func(): ease_out_grab.call_deferred()).call_deferred()
	elif not grabbing():
		var arm := _model.find_child("R-Arm", true, false)
		if arm != null and arm.has_meta("grab_scale"):
			HunterGrab.stretch_arms(self, 1.0)


func ease_out_grab() -> void:
	if _model == null or not is_instance_valid(_model):
		return
	if int(get_meta("grab_posed_frame", -1)) == Engine.get_process_frames():
		_grab_ease = 0.0   # held (again) this frame: the grab has her
		_grab_ease_from = {}
		return
	if _grab_ease_from.is_empty():
		if not _model.has_meta("grab_rest"):
			return
		# let go: ease from the last held pose (her stretch is taken off now; the bones' blend carries it)
		_grab_ease_from = {"model": _model.transform, "bones": get_meta("grab_bones", {}), "target": {}, "written": {},
			"stretch": _arm_stretch_now()}
		_grab_ease = 1.0
		remove_meta("grab_anchor")
		remove_meta("grab_along")
		HunterGrab.stretch_arms(self, 1.0)
		for bone in _grab_ease_from["bones"]:
			if is_instance_valid(bone):
				# where the bone goes back to: what something else (a clip, the chase layer) has put on it since the grab,
				# else the pose under her crouch, else where it is
				var node := bone as Node3D
				var crouched: bool = bone.has_meta("bend_written") and node.transform.is_equal_approx(bone.get_meta("bend_written"))
				_grab_ease_from["target"][bone] = bone.get_meta("bend_base") if crouched else node.transform
		HunterGrab.unbend(_model)
	# smoothstep over GRAB_EASE_SECONDS, so it starts and ends slowly (an exponential ease moves fastest the moment she lets go)
	_grab_ease_from["t"] = float(_grab_ease_from.get("t", 0.0)) + _grab_ease_delta
	_grab_ease = 1.0 - GrabStyles.smooth(float(_grab_ease_from["t"]) / GRAB_EASE_SECONDS)
	var rest: Transform3D = _model.get_meta("grab_rest")
	var bones: Dictionary = _grab_ease_from["bones"]
	var target: Dictionary = _grab_ease_from["target"]
	var written: Dictionary = _grab_ease_from["written"]
	for bone in bones:
		if not is_instance_valid(bone):
			continue
		var node := bone as Node3D
		if written.has(bone) and not node.transform.is_equal_approx(written[bone]):
			# rewritten since (a clip keys it): that is where it goes back to now, at the size it has without the grab
			var scale := (target[bone] as Transform3D).basis.get_scale()
			target[bone] = Transform3D(Basis(node.transform.basis.get_rotation_quaternion()).scaled(scale), node.transform.origin)
		var w := _grab_ease if _grab_ease >= .01 else 0.0
		if HunterGrab.ARM_BONES.has(String(node.name)):
			# an arm turns back only: its length (the grab's stretch, set on each bone in world space) eases off below
			var from_q := (target[bone] as Transform3D).basis.get_rotation_quaternion()
			node.quaternion = from_q.slerp((bones[bone] as Transform3D).basis.get_rotation_quaternion(), w)
		else:
			node.transform = (target[bone] as Transform3D).interpolate_with(bones[bone], w)
	var stretch := 1.0 + (float(_grab_ease_from["stretch"]) - 1.0) * (_grab_ease if _grab_ease >= .01 else 0.0)
	HunterGrab.stretch_arms(self, stretch)
	for bone in bones:
		if is_instance_valid(bone):
			written[bone] = (bone as Node3D).transform
	if _head_node != null:
		_head_written_q = _head_node.quaternion   # her own head look goes on from the rest pose next frame, as it does after hers
	if _grab_ease < .01:
		_model.transform = rest
		_model.remove_meta("grab_rest")
		_grab_ease = 0.0
		_grab_ease_from = {}
		return
	_model.transform = rest.interpolate_with(_grab_ease_from["model"], _grab_ease)


## How far a grab has her upper arm stretched right now (1 when it has not).
func _arm_stretch_now() -> float:
	var arm := _model.find_child("R-Arm", true, false) as Node3D
	if arm == null or not arm.has_meta("grab_scale"):
		return 1.0
	var parent := arm.get_parent() as Node3D
	var rest := (arm.get_meta("grab_scale") as Vector3).y * (parent.global_basis.get_scale().y if parent != null else 1.0)
	return arm.global_basis.y.length() / maxf(rest, 1e-6)


func _update_beam_visual(delta: float) -> void:
	if _kathy_beam == null or brain == null:
		return
	var off := grabbing()
	for part in [_beam_shell, _beam_core]:
		if part != null:
			(part as Node3D).visible = not off and _kathy_beam.visible
	if off:
		_kathy_beam.visible = false
		return
	var chasing := brain.active and brain.state == HunterBrain.State.CHASE and brain.stun_timer <= 0.0
	_beam_chase_mix = move_toward(_beam_chase_mix, 1.0 if chasing else 0.0, delta * 4.0)
	_beam_color = _beam_neutral.lerp(BEAM_CHASE_COLOR, _beam_chase_mix)
	var dim := .25 if brain.stun_timer > 0.0 else 1.0
	_kathy_beam.light_color = _beam_color
	_kathy_beam.light_energy = lerpf(5.0, 7.5, _beam_chase_mix) * dim
	var pulse_speed := lerpf(2.6, 7.5, _beam_chase_mix)
	if _beam_shell != null:
		var shell := _beam_shell.material_override as ShaderMaterial
		shell.set_shader_parameter("beam_color", _beam_color)
		# KT: "much less visible" -- about 30% of the old .22-.34; the light on the floor and walls carries the cue
		shell.set_shader_parameter("strength", lerpf(.066, .10, _beam_chase_mix) * dim)
		shell.set_shader_parameter("pulse_speed", pulse_speed)
	if _beam_core != null:
		var core := _beam_core.material_override as ShaderMaterial
		core.set_shader_parameter("beam_color", _beam_color.lerp(Color.WHITE, .35))
		core.set_shader_parameter("strength", lerpf(.15, .24, _beam_chase_mix) * dim)
		core.set_shader_parameter("pulse_speed", pulse_speed)


## The chase style layer: on while she is in a live chase on foot and nothing else is posing her.
func _update_chase_style(delta: float) -> void:
	if brain == null or _model == null or _creature != null:
		return
	var flying := brain.gimmick is XivvyGimmick and (brain.gimmick as XivvyGimmick).airborne()
	var chasing := chase_layer_enabled and brain.active and brain.state == HunterBrain.State.CHASE \
		and brain.stun_timer <= 0.0 and _recover_left <= 0.0 and not climbing and not flying and not has_nw_pose() \
		and not (_emote_index >= 0 and not _emote_clip.is_empty()) \
		and not (has_method("grabbing") and bool(call("grabbing")))   # GRAB's every-peer signal (HunterGrab)
	var aim := 0.0
	if has_look_target and HunterChaseStyle.reaches(brain.chase_style):
		var forward := Vector2(-sin(rotation.y), -cos(rotation.y))
		var to_runner := look_target_position - brain.position
		if to_runner.length() > .1:
			aim = clampf(forward.angle_to(to_runner.normalized()), -HunterChaseStyle.AIM_LIMIT, HunterChaseStyle.AIM_LIMIT)
	_chase.apply(brain.chase_style, chasing, delta, -aim, Time.get_ticks_msec() * .001)


func _update_head_look(delta: float) -> void:
	if _head_node == null or brain == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera != null and global_position.distance_squared_to(camera.global_position) \
			> HunterFacing.UPDATE_RANGE * HunterFacing.UPDATE_RANGE:
		_facing.weight = 0.0
		return
	var live := brain.active and brain.stun_timer <= 0.0 and _recover_left <= 0.0 \
		and (_emote_index < 0 or _emote_clip.is_empty())
	var mode := HunterFacing.Mode.NONE
	var target := Vector2.ZERO
	if live:
		mode = _head_mode()
		if mode == HunterFacing.Mode.LOCK or mode == HunterFacing.Mode.SWEEP:
			target = look_target_position
		elif mode == HunterFacing.Mode.AHEAD:
			target = _head_ahead_point()
			if target == Vector2.INF:
				mode = HunterFacing.Mode.SCAN
	_facing.update_head(delta, mode, rotation.y, brain.position, target,
		Time.get_ticks_msec() * .001)
	# Additive on whatever the clip left on the head: when the clip drives the
	# Head bone the current rotation is the clip's pose, otherwise it is still
	# what this function wrote last frame and the rest pose is the base.
	var current := _head_node.quaternion
	var base := _head_rest_q if current.is_equal_approx(_head_written_q) else current
	var look := Quaternion(Vector3.UP, _facing.head_yaw * _facing.weight) \
		* Quaternion(Vector3.RIGHT, _facing.head_pitch * _facing.weight)
	_head_node.quaternion = look * base
	_head_written_q = _head_node.quaternion


## chase locks on the runner (the brain keeps last_known on her while she has
## sight), search/investigate sweep toward the noise, everything else looks
## where the path leads -- or scans while she stands.
func _head_mode() -> int:
	match brain.state:
		HunterBrain.State.CHASE:
			if has_look_target:
				return HunterFacing.Mode.LOCK
		HunterBrain.State.INVESTIGATE, HunterBrain.State.SEARCH:
			if has_look_target:
				return HunterFacing.Mode.SWEEP
		HunterBrain.State.INSPECT:
			if brain.inspect_phase != HunterBrain.Inspect.WALK:
				return HunterFacing.Mode.NONE   # the lean pose aims her face straight in at the slats
	return HunterFacing.Mode.AHEAD if _facing.moving() else HunterFacing.Mode.SCAN


## 2-4 m ahead along the route; flight and charge (and any guest, which has no
## route) use the travel direction instead.
func _head_ahead_point() -> Vector2:
	var distance := _facing.look_ahead_distance()
	var straight := brain.gimmick is XivvyGimmick and (brain.gimmick as XivvyGimmick).airborne()
	if brain.gimmick is LoxelleGimmick and (brain.gimmick as LoxelleGimmick).charge_active():
		straight = true
	if not straight:
		var ahead := brain.path_look_ahead(distance)
		if ahead != Vector2.INF:
			return ahead
	if _facing.moving():
		return brain.position + _facing.move_dir.normalized() * distance
	return Vector2.INF


## Stealth presentation is checked every sync rather than only when the model is
## (re)built, so a gimmick that changes its mind mid-floor is reflected without
## needing a model swap to trigger it.
##
## Also hidden while `brain.active` is false -- matching the original's own
## renderer, which only ever draws `hunter.active` hunters. Rule-summoned
## specials (Nyxie, Solyth) exist on the floor from the start but stay
## INACTIVE until their own wake condition fires, sitting inert wherever they
## spawned; nothing here used to hide that, so a special was a fully visible,
## motionless, silently-standing figure for however long it took the player
## to stumble across her -- which reads as a broken model, not as a hunter
## who has not woken up yet.
## KT 2026-10-28: "no character should have full invisibility". A stealth gimmick (hidden_from_view: Blue Void, Gray,
## Verrine, Porcelle, Ilyra's banish, ...) fades the model to MIN_VISIBLE_ALPHA, never further: a faint silhouette while
## the hunter is awake. Only dormant hunters (brain.active false: Nyxie/Solyth/Wynelle before they wake) and a dispersed
## Ceryth (retired, out of the room) draw nothing.
const MIN_VISIBLE_ALPHA := .28


## How much of the model shows: 0 dormant or retired, MIN_VISIBLE_ALPHA while a gimmick hides her, 1 otherwise.
static func model_alpha(hunter: HunterBrain) -> float:
	if hunter == null:
		return 1.0
	if not hunter.active or (hunter.gimmick is CerythGimmick and (hunter.gimmick as CerythGimmick).dispersed):
		return 0.0
	return MIN_VISIBLE_ALPHA if hunter.gimmick != null and hunter.gimmick.hidden_from_view() else 1.0


func _apply_visibility() -> void:
	if _model == null:
		return
	var gimmick_hidden := brain != null and brain.gimmick != null and brain.gimmick.hidden_from_view()
	var inactive := brain != null and not brain.active
	var retired := brain != null and brain.gimmick is CerythGimmick \
		and (brain.gimmick as CerythGimmick).dispersed
	# Active stealth hunters must never become a completely missing render. Their
	# gimmicks still make them extremely hard to see, but retain a trace silhouette
	# for close-range readability.
	_model.visible = not inactive and not retired
	# This leaves 28% of the authored model visible. The fade helper also lifts
	# ALPHA_SCISSOR while ghosted -- otherwise the remaining alpha falls under the
	# default 0.5 MASK cutoff and the silhouette is gone.
	var fade := 1.0 - MIN_VISIBLE_ALPHA if gimmick_hidden else 0.0
	ModelSlot.set_character_fade(_model, fade)
	if _kathy_beam != null:
		_kathy_beam.visible = _model.visible and not grabbing()


## Body follows the way she is actually travelling (smoothed position delta, so
## it also works on guests), turning at a capped rate with no snapping. Standing
## still: a chasing hunter turns toward the runner, anyone else keeps the
## brain's last real heading.
func _update_body_yaw() -> void:
	if climbing:
		return
	var direction := Vector2.ZERO
	if _facing.moving():
		direction = _facing.move_dir
	elif has_look_target and brain.active and brain.stun_timer <= 0.0 \
			and brain.state == HunterBrain.State.CHASE:
		direction = look_target_position - brain.position
	if direction.length_squared() < .0001:
		direction = brain.facing
	if direction.length_squared() < .0001:
		return
	if not _heading_initialized:
		rotation.y = atan2(-direction.x, -direction.y)
		_heading_initialized = true
		return
	var running := brain.state == HunterBrain.State.CHASE or _facing.speed > 4.5
	rotation.y = _facing.steer(rotation.y, direction, running, get_process_delta_time())


## Xivvy's flying chase: altitude / bank / pitch / wing cadence from XivvyFlight, a floor shadow, and the screech and
## wing cues. Runs on every peer from replicated data only (the gimmick's flying flag, the motion and the look target).
func _update_flight(flying: bool, floor_y: float) -> void:
	if not brain.gimmick is XivvyGimmick:
		return
	var gimmick := brain.gimmick as XivvyGimmick
	var delta := get_process_delta_time()
	var yaw_rate := wrapf(rotation.y - _flight_yaw_last, -PI, PI) / maxf(delta, .001)
	_flight_yaw_last = rotation.y
	var runner_distance := brain.position.distance_to(look_target_position) \
		if has_look_target and brain.state == HunterBrain.State.CHASE else INF
	var chasing := flying or brain.state == HunterBrain.State.CHASE
	if gimmick.replicated_recently():
		# a guest: the host decided the mode and the cruise altitude (it has the geometry and the route)
		_flight.fly_ok = gimmick.fly_ok
		_flight.override_cruise = gimmick.altitude_hint
	else:
		_flight.override_cruise = -1.0
		_flight_probe -= delta
		if _flight_probe <= 0.0 and (chasing or _flight.altitude > 0.0):
			_flight_probe = SURVEY_INTERVAL
			var survey := _survey_route(floor_y)
			_flight_headroom = survey["near"]
			_flight.update_mode(SURVEY_INTERVAL, float(survey["far"]), bool(survey["gap"]))
			gimmick.fly_ok = _flight.fly_ok
			gimmick.altitude_hint = _flight.cruise_altitude(_flight_headroom)
		elif not chasing and _flight.altitude <= 0.0:
			_flight.fly_ok = true
			gimmick.fly_ok = true
	_flight.update(delta, flying and _flight.fly_ok, _move_speed, yaw_rate, runner_distance, _flight_headroom)
	if _model != null:
		_model.rotation = Vector3(_flight.pitch, _model.rotation.y, _flight.bank)
	_apply_wing_fold()
	var airborne := flying and _flight.fly_ok
	_screech_cooldown = maxf(0.0, _screech_cooldown - delta)
	if airborne and not _flight_was_flying:
		_flight_cue(true)
		_screech_cooldown = 4.0
	elif airborne and runner_distance < XivvyFlight.SWOOP_RANGE * .45 and _screech_cooldown <= 0.0:
		_flight_cue(true)
		_screech_cooldown = 4.5
	_flight_was_flying = airborne
	if _flight.flapped:
		_flight_cue(false)
	_update_flight_shadow(floor_y)


## The wings fold while she lands (and open again once she is on her feet).
func _apply_wing_fold() -> void:
	if _model == null:
		return
	if _wing_nodes.is_empty() and not _wings_searched:
		_wings_searched = true
		for node in _model.find_children("*Wing*", "Node3D", true, false):
			_wing_nodes.append(node)
	var fold := _flight.wing_fold
	if fold <= 0.001 and _wing_fold_applied <= 0.001:
		return
	_wing_fold_applied = fold
	for node in _wing_nodes:
		(node as Node3D).scale = Vector3(1.0 - .6 * fold, 1.0 - .1 * fold, 1.0 - .35 * fold)


## Samples the route ahead (host only): the lowest ceiling over the next stretch, the lowest near her (cruise altitude),
## and whether a doorway-sized gap (walls close on both sides) is on the way.
func _survey_route(floor_y: float) -> Dictionary:
	var far := INF
	var near := INF
	var gap := false
	if not is_inside_tree():
		return {"far": far, "near": near, "gap": gap}
	var space := get_world_3d().direct_space_state
	var excluded := [get_rid()]
	var heading := _facing.move_dir if _facing.moving() else brain.facing
	if heading.length_squared() < .0001:
		heading = Vector2(0, 1)
	heading = heading.normalized()
	for distance in SURVEY_DISTANCES:
		var point := brain.position
		if distance > 0.0:
			point = brain.path_look_ahead(distance)
			if point == Vector2.INF:
				point = brain.position + heading * distance
		var origin := Vector3(point.x, floor_y + .3, point.y)
		var up := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.UP * 12.0, 1, excluded)
		var hit := space.intersect_ray(up)
		var headroom: float = hit["position"].y - floor_y if not hit.is_empty() else INF
		far = minf(far, headroom)
		if distance <= 3.0:
			near = minf(near, headroom)
		# a doorway: walls within GAP_HALF_WIDTH on both sides at chest height
		var along := (brain.path_look_ahead(distance + 1.0) - point) if distance > 0.0 and brain.path_look_ahead(distance + 1.0) != Vector2.INF else heading
		if along.length_squared() < .0001:
			along = heading
		var side := Vector2(-along.y, along.x).normalized()
		var chest := Vector3(point.x, floor_y + 1.0, point.y)
		var side3 := Vector3(side.x, 0.0, side.y)
		var left := PhysicsRayQueryParameters3D.create(chest, chest + side3 * XivvyFlight.GAP_HALF_WIDTH, 1, excluded)
		var right := PhysicsRayQueryParameters3D.create(chest, chest - side3 * XivvyFlight.GAP_HALF_WIDTH, 1, excluded)
		if not space.intersect_ray(left).is_empty() and not space.intersect_ray(right).is_empty():
			gap = true
	return {"far": far, "near": near, "gap": gap}


func _flight_cue(screech: bool) -> void:
	if not is_inside_tree():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var distance := global_position.distance_to(camera.global_position)
	if distance >= 40.0:
		return
	var side := (global_position - camera.global_position).dot(camera.global_basis.x)
	var pan := clampf(side / maxf(distance, 1.0), -1.0, 1.0)
	var loudness := clampf(1.5 - distance / 30.0, .25, 1.4)
	if screech:
		Sound.xivvy_screech(pan, loudness)
	else:
		Sound.xivvy_wing(pan, loudness * .8)


## A soft dark disc on the floor under her: smaller and fainter the higher she is.
func _update_flight_shadow(floor_y: float) -> void:
	if _flight.altitude <= .05:
		if _flight_shadow != null:
			_flight_shadow.visible = false
		return
	if _flight_shadow == null:
		_flight_shadow = MeshInstance3D.new()
		_flight_shadow.name = "FlightShadow"
		var disc := CylinderMesh.new()
		disc.top_radius = .55
		disc.bottom_radius = .55
		disc.height = .01
		disc.radial_segments = 20
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(0, 0, 0, .42)
		material.no_depth_test = false
		disc.material = material
		_flight_shadow.mesh = disc
		_flight_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_flight_shadow.top_level = true
		add_child(_flight_shadow)
	_flight_shadow.visible = true
	var spread := clampf(1.0 - _flight.altitude / 3.4, .35, 1.0)
	_flight_shadow.scale = Vector3(spread * 1.35, 1.0, spread * 1.35)
	(_flight_shadow.mesh.material as StandardMaterial3D).albedo_color.a = lerpf(.12, .42, spread)
	_flight_shadow.global_position = Vector3(global_position.x, floor_y + .025, global_position.z)


func sync_from_brain() -> void:
	if brain == null:
		return
	var surface_y := float(surface_height_provider.call(brain.position)) \
		if surface_height_provider.is_valid() else 0.0
	var xivvy_flying := brain.gimmick is XivvyGimmick \
		and (brain.gimmick as XivvyGimmick).flying
	_update_flight(xivvy_flying, surface_y)
	surface_y += _flight.altitude
	_desired_xz = brain.position
	_surface_target_y = surface_y
	if _streamed_height_override_active:
		_surface_target_y = _streamed_height_override
	if not _presentation_initialized:
		position = Vector3(brain.position.x, _surface_target_y, brain.position.y)
		_presentation_initialized = true
	var frame := maxf(get_process_delta_time(), 1.0 / 120.0)
	# The very first sample (the last position is still the zero default) or a jump of several metres (spawn, stairs, a streamed
	# floor) is a teleport, not walking: reading it as speed made every hunter "walk" in place for a second after appearing.
	var step := brain.position.distance_to(_last_brain_position)
	if not _speed_primed or step > TELEPORT_DISTANCE:
		_move_speed = 0.0
		_still_time = STILL_CLIP_AFTER + .01 if not _speed_primed else _still_time
	else:
		_move_speed = lerpf(_move_speed, step / frame, .3)
	_speed_primed = true
	_last_brain_position = brain.position
	_still_time = _still_time + frame if _move_speed < STILL_SPEED else 0.0
	_facing.track(brain.position, get_process_delta_time())
	_update_body_yaw()
	_apply_model(_desired_model_id())
	if _asleep:
		_apply_sleep_pose()
	_apply_visibility()
	_update_emote_state()
	_update_animation()


## idle/walk/chase/sprint/stun/flight/charge (plus scythe_* for Kathy) — the blocky rig's clips; older models
## without sprint fall back to chase through play_if_available.
## Investigate/search both read as "walk" (she's purposefully moving toward
## somewhere, just not at chase urgency yet); only an actual sighting-driven
## chase gets the more urgent clip.
func _update_emote_state() -> void:
	if _creature != null:
		return
	var now := Time.get_ticks_msec()
	if brain.emote_seq != _emote_seen_seq:
		_emote_seen_seq = brain.emote_seq
		_end_emote()
		if HunterEmoteCatalog.valid(brain.emote_id) and brain.emote_left > 0.0:
			_begin_emote(brain.emote_id, brain.emote_left)
	elif _emote_index >= 0 and (brain.emote_id != _emote_index or now >= _emote_until_msec):
		_end_emote()


func _begin_emote(index: int, seconds: float) -> void:
	_emote_index = index
	_emote_until_msec = Time.get_ticks_msec() + int(seconds * 1000.0)
	_emote_clip_started = false
	# Kathy's scythe is held by the carry clips; she emotes with her face only.
	_emote_clip = "" if _carries_scythe else HunterEmoteCatalog.resolve_clip(index,
		_shown_id, _animation_player, HunterEmotePersonality.clip_override(_shown_id, index))
	var voice := HunterEmotePersonality.voice(_shown_id, index)
	if not voice.is_empty():
		# a content pack's voice for this emote: heard like the noisy emotes, even when this one is normally silent
		_emote_cue(maxf(HunterEmoteCatalog.noise(index), VOICE_RADIUS), voice[randi() % voice.size()])
	else:
		_emote_cue(HunterEmoteCatalog.noise(index))


func _end_emote() -> void:
	_emote_index = -1
	_emote_clip = ""
	_emote_clip_started = false


## The clip only replaces the walk/idle clip when the hunter is not busy being stunned/flying/charging and either
## stands still or this emote is meant to be played on the move; otherwise it is face-only for that moment.
func _emote_plays_now() -> bool:
	if _emote_index < 0 or brain.stun_timer > 0.0 or _recover_left > 0.0:
		return false
	if brain.gimmick is XivvyGimmick and (brain.gimmick as XivvyGimmick).airborne():
		return false
	if brain.gimmick is LoxelleGimmick and (brain.gimmick as LoxelleGimmick).charge_active():
		return false
	return HunterEmoteCatalog.moving_ok(_emote_index) or _move_speed < .6


## Small positional cue for noisy emotes (laugh, hum, dance): quieter with distance, silent beyond the radius.
const VOICE_RADIUS := 16.0


func _emote_cue(radius: float, voice: AudioStream = null) -> void:
	if radius <= 0.0 or not is_inside_tree():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var distance := global_position.distance_to(camera.global_position)
	if distance >= radius:
		return
	var side := (global_position - camera.global_position).dot(camera.global_basis.x)
	if voice != null:
		Sound.play_voice(voice, 1.0 - distance / radius)
		return
	Sound.hunter_laugh(clampf(side / maxf(radius * .5, 1.0), -1.0, 1.0), .05 * (1.0 - distance / radius))


## Switches between walk/chase/sprint with a short blend and keeps the stride phase, so the legs do not jump.
func _play_travel(clip_name: String) -> void:
	var player := _animation_player
	if player.has_animation(clip_name) and (player.assigned_animation != clip_name or not player.is_playing()):
		var phase := 0.0
		if player.is_playing() and player.assigned_animation in ["walk", "chase", "sprint", "scythe_walk"]:
			phase = player.current_animation_position / maxf(player.current_animation_length, .01)
		player.play(clip_name, TRAVEL_BLEND)
		if phase > 0.0:
			player.seek(phase * player.get_animation(clip_name).length, false)


## The model id this view is showing (Umbriel's disguise included).
func shown_id() -> String:
	return _shown_id


## Corner peek (HunterPeek): the deep lean pose while her head is out past the edge, toward the edge's side. Only
## clears a pose it set, so Night Watch's own poses are never touched.
func _sync_peek_pose() -> void:
	if brain == null:
		return
	var wanted := ""
	if brain.peeking_out() and brain.stun_timer <= 0.0:
		wanted = "corner_peek_left" if brain.peek_side > 0 else "corner_peek_right"
	elif brain.inspecting_close() and brain.stun_timer <= 0.0:
		wanted = "locker_lean"   # bent in at the slats (HunterInspect); blends in over the shot's 1.6 s bow
	if wanted == _peek_pose:
		return
	if wanted.is_empty():
		if nw_pose == _peek_pose:
			nw_pose = ""
	elif nw_pose.is_empty() or nw_pose == _peek_pose:
		nw_pose = wanted
		nw_pose_opts = {"blend": HunterInspect.LEAN_SECONDS} if wanted == "locker_lean" else {}
	_peek_pose = wanted


## Locker inspection: one close breath when she settles at the slats, heard only near the spot (the hider, mostly).
var _breathed := false


func _update_inspect_breath() -> void:
	var lingering := brain.state == HunterBrain.State.INSPECT and brain.inspect_phase == HunterBrain.Inspect.LINGER
	if not lingering:
		_breathed = false
		return
	if _breathed or not is_inside_tree():
		return
	_breathed = true
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var gap := global_position.distance_to(camera.global_position)
	if gap > 3.5:
		return
	var side := (global_position - camera.global_position).dot(camera.global_basis.x)
	var breaths := int(HunterInspect.tuning(brain.hunter_id)["breaths"])   # Nyxie's easter egg breathes twice, longer
	for i in breaths:
		if i > 0:
			await get_tree().create_timer(1.1).timeout
			if not is_inside_tree():
				return
		Sound.nw("breath", clampf(side, -1.0, 1.0), (1.0 - gap / 3.5 * .5) * (1.15 if breaths > 1 else 1.0))


## Glyra hums while her music box plays and falls silent when it stops (GlyraGimmick.humming, replicated mood).
var _hum: AudioStreamPlayer3D


func _update_glyra_hum() -> void:
	if not brain.gimmick is GlyraGimmick:
		return
	var on := brain.active and (brain.gimmick as GlyraGimmick).humming()
	if _hum == null:
		if not on:
			return
		_hum = AudioStreamPlayer3D.new()
		_hum.name = "GlyraHum"
		_hum.unit_size = 4.0
		_hum.max_distance = 14.0
		_hum.volume_db = 3.0
		_hum.position = Vector3(0, 1.5, 0)
		var hum := Sound.render_cue("glyra_hum").duplicate() as AudioStreamWAV
		if hum != null:
			hum.loop_mode = AudioStreamWAV.LOOP_FORWARD
			hum.loop_begin = 0
			hum.loop_end = int(hum.data.size() / 4)
			_hum.stream = hum
		add_child(_hum)
	if on and not _hum.playing and _hum.stream != null and DisplayServer.get_name() != "headless":
		_hum.play()
	elif not on and _hum.playing:
		_hum.stop()


## Runs on every peer from replicated state: when this machine's camera has a clear line to her leaned-out head, play
## the sting once for this peek. The head is where the brain says it is, so the beat matches what she can see back.
func _update_peek_spot() -> void:
	if not brain.peeking_out():
		_peek_spotted = false
		return
	if _peek_spotted or not is_inside_tree():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var head := Vector3(brain.peek_head.x, global_position.y + 1.5 * HunterRoster.scale_for(_shown_id), brain.peek_head.y)
	var to_head := head - camera.global_position
	if to_head.length() > PEEK_SPOT_RANGE or (-camera.global_basis.z).dot(to_head.normalized()) < .55:
		return
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, head)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and not is_ancestor_of(hit.get("collider")) and hit.get("collider") != self:
		return
	_peek_spotted = true
	Sound.alert()
	peek_spotted.emit(self)


func has_nw_pose() -> bool:
	return _animation_player != null and not nw_pose.is_empty() \
		and _animation_player.has_animation(NightWatchPoses.clip_name(nw_pose))


func _update_nw_layers(delta: float) -> void:
	if _model == null or brain == null:
		return
	var yaw_rate := wrapf(rotation.y - _nw_last_yaw, -PI, PI) / maxf(delta, .001)
	_nw_last_yaw = rotation.y
	var spec := NightWatchPoses.pose(nw_pose) if not nw_pose.is_empty() else {}
	var on: bool = nw_layers and brain.active and brain.stun_timer <= 0.0 and bool(spec.get("layers", true))
	_nw_layers.apply(delta, Time.get_ticks_msec() * .001, yaw_rate, _facing.moving(), on)


## Holds the requested Night Watch pose; false when there is none (or she is stunned, which wins).
func _play_nw_pose() -> bool:
	if not has_nw_pose():
		if nw_pose.is_empty():
			_nw_started = ""
		return false
	if brain.stun_timer > 0.0:
		return false
	var clip := NightWatchPoses.clip_name(nw_pose)
	var spec := NightWatchPoses.pose(nw_pose)
	if not (_animation_player.is_playing() and _animation_player.current_animation == clip):
		if _nw_started == nw_pose and _animation_player.assigned_animation == clip:
			# the one-shot finished: back to the normal clips
			nw_pose = ""
			_nw_started = ""
			return false
		_nw_started = nw_pose
		_animation_player.play(clip, float(nw_pose_opts.get("blend", spec.get("blend", .3))))
	if nw_pose_opts.has("speed"):
		_animation_player.speed_scale = float(nw_pose_opts["speed"])
	elif spec.has("travel"):
		# a travelling pose (the vent crawl) plays at real ground speed / its measured stride speed, and holds still when she does
		var wanted := 0.0
		if _gait_pose_moving():
			wanted = clampf(_move_speed / HunterStride.ref_speed(_shown_id, clip), HunterStride.HARD_MIN, HunterStride.HARD_MAX)
		_stride_scale = lerpf(_stride_scale, wanted, 1.0 - exp(-10.0 * get_process_delta_time()))
		_animation_player.speed_scale = _stride_scale if wanted > 0.0 or _stride_scale > .05 else 0.0
	else:
		_animation_player.speed_scale = 1.0
	return true


func _gait_pose_moving() -> bool:
	return _move_speed > GAIT_ENTER_SPEED * .5


## The one sound of a pounce: a single footfall as she launches (nothing earlier).
func _update_pounce_cue() -> void:
	if brain == null or brain.hard == null:
		return
	if brain.hard.leap_seq != _leap_seq_seen:
		_leap_seq_seen = brain.hard.leap_seq
		if brain.hard.leaping and is_inside_tree():
			var camera := get_viewport().get_camera_3d()
			if camera != null:
				var distance := global_position.distance_to(camera.global_position)
				if distance < 30.0:
					var side := (global_position - camera.global_position).dot(camera.global_basis.x)
					Sound.hunter_footstep(clampf(side / maxf(distance, 1.0), -1.0, 1.0), clampf(1.4 - distance / 30.0, .3, 1.4) * .05)


func _update_animation() -> void:
	_update_pounce_cue()
	if _creature != null:
		_creature.tick(get_process_delta_time())
		return
	var clip_name := "idle"
	var delta := get_process_delta_time()
	if brain.stun_timer > 0.0:
		clip_name = "stun"
		_was_stunned = true
		_recover_left = 0.0
	elif _was_stunned:
		# stun just ended: play the wake-up once (it is a one-shot) before going back to normal
		_was_stunned = false
		if _animation_player != null and _animation_player.has_animation("stun_recover"):
			_recover_left = _animation_player.get_animation("stun_recover").length - .03
	if clip_name != "stun" and _recover_left > 0.0:
		_recover_left -= delta
		clip_name = "stun_recover"
	elif brain.stun_timer > 0.0:
		pass
	elif climbing:
		clip_name = climb_clip
	elif brain.gimmick is XivvyGimmick \
			and (brain.gimmick as XivvyGimmick).airborne():
		clip_name = "flight"
	elif brain.gimmick is LoxelleGimmick \
			and (brain.gimmick as LoxelleGimmick).charge_active():
		clip_name = "charge"
	elif brain.hard != null and brain.hard.leaping:
		clip_name = "charge"        # the pounce: the leap pose is the only tell
	elif brain.hard != null and brain.hard.stumble_left > 0.0 and _animation_player != null \
			and _animation_player.has_animation("stun_recover"):
		clip_name = "stun_recover"  # the stumble after a miss
	else:
		match brain.state:
			HunterBrain.State.CHASE:
				# a full-speed dash while she can see the runner and still has breath
				clip_name = "sprint" if brain.direct_chase_visible and not brain.winded else "chase"
			HunterBrain.State.WANDER, HunterBrain.State.INVESTIGATE, HunterBrain.State.SEARCH:
				clip_name = "walk"
	# A hunter pinned against geometry (or waiting on a route) stands instead of treading on the spot.
	# Hysteresis: she starts walking above GAIT_ENTER_SPEED and only stands again after STILL_CLIP_AFTER of
	# near-stillness, so a hunter creeping at the threshold does not flap between idle and walk.
	if clip_name in ["walk", "chase", "sprint"]:
		if _gait_moving and _still_time > STILL_CLIP_AFTER:
			_gait_moving = false
		elif not _gait_moving and _move_speed > GAIT_ENTER_SPEED:
			_gait_moving = true
		if not _gait_moving:
			clip_name = "idle"
	if clip_name == "sprint" and _animation_player != null and not _animation_player.has_animation("sprint"):
		clip_name = "chase"
	var speed := 1.0
	if _carries_scythe:
		match clip_name:
			"stun":
				clip_name = "scythe_stun"
			"stun_recover":
				clip_name = "scythe_stun_recover"
			"idle":
				clip_name = "scythe_idle"
			"walk":
				clip_name = "scythe_walk"
			"chase", "sprint":
				clip_name = "scythe_walk"
	# Travel clips play at real ground speed / the clip's measured stride speed (HunterStride), swapping to the
	# neighbouring walk/chase/sprint clip when the pace is far outside one clip's range, so the planted foot stays put.
	if clip_name == "flight":
		speed = _flight.flight_clip_speed(_move_speed)
	var travelling := clip_name in ["walk", "chase", "sprint", "scythe_walk"] and _animation_player != null
	if travelling:
		var pick := HunterStride.choose(_shown_id, clip_name, _move_speed,
			["scythe_walk"] if clip_name == "scythe_walk" else HunterStride.TRAVEL_CLIPS)
		if _animation_player.has_animation(String(pick["clip"])):
			clip_name = String(pick["clip"])
		_stride_scale = lerpf(_stride_scale, float(pick["scale"]), 1.0 - exp(-10.0 * delta))
		speed = _stride_scale
	_sync_peek_pose()
	_update_peek_spot()
	_update_glyra_hum()
	_update_inspect_breath()
	if _play_nw_pose():
		return
	if _emote_clip != "" and _animation_player != null and _emote_plays_now():
		if not _emote_clip_started:
			_emote_clip_started = true
			_animation_player.play(_emote_clip)
		speed = 1.0
	elif travelling:
		_play_travel(clip_name)
	else:
		ModelSlot.play_if_available(_animation_player, clip_name)
	if _animation_player != null:
		_animation_player.speed_scale = speed


## Which face the hunter shows right now (BlockyFace cells; models without a Face quad ignore it):
## stunned -> stun, waking up -> blank, chasing -> chase (scream when the runner is close), searching a lost
## target -> derp (the irises roll: she is confused), anything else -> neutral with an occasional blink.
func _desired_expression() -> String:
	if brain == null or not brain.active:
		return "neutral"
	if brain.stun_timer > 0.0:
		return "stun"
	if _recover_left > 0.0:
		return "blank"
	if _emote_index >= 0:
		return HunterEmoteCatalog.face(_emote_index)
	match brain.state:
		HunterBrain.State.CHASE:
			# Latched: she screams inside SCREAM_DISTANCE and keeps screaming until the runner is clearly
			# out of it, so a runner circling the edge of the range cannot flicker the face every frame.
			var gap := brain.position.distance_to(look_target_position) if has_look_target else INF
			_scream_latched = gap < SCREAM_DISTANCE or (_scream_latched and gap < SCREAM_DISTANCE * 1.4)
			return "scream" if _scream_latched else "chase"
		HunterBrain.State.SEARCH:
			return "derp"
	return "neutral"


func _update_expression(delta: float) -> void:
	if _model == null or brain == null:
		return
	var wanted := _desired_expression()
	if wanted == "neutral":
		_blink_left = maxf(0.0, _blink_left - delta)
		_blink_timer -= delta
		if _blink_timer <= 0.0:
			_blink_timer = randf_range(2.2, 5.0)
			_blink_left = .13
		if _blink_left > 0.0:
			wanted = "blink"
	_face_hold = maxf(0.0, _face_hold - delta)
	if wanted == _expression:
		if _face_node == null or not is_instance_valid(_face_node) or not _model.is_ancestor_of(_face_node):
			_face_node = _model.find_child("Face", true, false) as MeshInstance3D
		var face := _face_node
		if face == null or BlockyFace.owns_material(face):
			return
		# something replaced the quad's material (fade / restore): wear the expression again
		BlockyFace.set_expression(_model, wanted)
		return
	# A face holds for a moment before it may change again (blinks and the stun/wake faces are exempt), so a
	# state that flips back and forth never reads as a flickering texture.
	var quick := wanted == "blink" or _expression == "blink" or wanted == "stun" or wanted == "blank" \
		or _expression == "stun" or _expression == "blank" or _expression.is_empty()
	if not quick and _face_hold > 0.0:
		return
	_face_hold = FACE_HOLD
	_expression = wanted
	BlockyFace.set_expression(_model, wanted)


## Three little stars circle the head while she is stunned: readable at gameplay distance when the face is not.
func _update_stars(delta: float) -> void:
	var stunned := brain != null and brain.active and brain.stun_timer > 0.0 and _model != null and _head_node != null
	if not stunned:
		if _stars != null:
			_stars.visible = false
		return
	if _stars == null:
		_stars = Node3D.new()
		_stars.name = "StunStars"
		var mesh := BoxMesh.new()
		mesh.size = Vector3(.09, .09, .09)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(1.0, .86, .25)
		mesh.material = material
		for i in STAR_COUNT:
			var star := MeshInstance3D.new()
			star.mesh = mesh
			star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_stars.add_child(star)
		add_child(_stars)
	_stars.visible = true
	var top := _head_node.global_position.y - global_position.y + .5
	_stars.position = Vector3(0.0, top, 0.0)
	var phase := Time.get_ticks_msec() * .004
	for i in _stars.get_child_count():
		var angle := phase + TAU * float(i) / float(STAR_COUNT)
		(_stars.get_child(i) as Node3D).position = Vector3(cos(angle), sin(angle * 2.0) * .04, sin(angle)) * STAR_ORBIT_RADIUS
		(_stars.get_child(i) as Node3D).rotation = Vector3(angle, angle * 1.3, 0.0)
