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
var nw_pose_opts := {}
var nw_layers := false
var _nw_started := ""
var _nw_layers := NightWatchPoseLayers.new()
var _nw_last_yaw := 0.0
var _head_rest_q := Quaternion.IDENTITY
var _head_written_q := Quaternion.IDENTITY
var _kathy_beam: SpotLight3D
var _carries_scythe := false
var _was_stunned := false
var _recover_left := 0.0
var _expression := ""
var _blink_timer := 2.0
var _scream_latched := false
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
	float rim = pow(clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 1.4);
	float pulse = 1.0 + 0.14 * sin(TIME * pulse_speed);
	ALBEDO = beam_color.rgb;
	ALPHA = clamp(strength * pulse * rim * (1.0 - along * 0.8), 0.0, 1.0);
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
const HUNTER_BODY_RADIUS := .28
const HUNTER_BODY_HEIGHT := 1.72
## Body yaw / head look live in HunterFacing so other creature views share them.



func _ready() -> void:
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
	var capsule := CapsuleShape3D.new()
	capsule.radius = HUNTER_BODY_RADIUS
	capsule.height = HUNTER_BODY_HEIGHT
	collider.shape = capsule
	collider.position.y = HUNTER_BODY_HEIGHT * .5
	add_child(collider)
	_apply_model(_desired_model_id())


func _process(delta: float) -> void:
	_update_head_look(delta)
	_update_nw_layers(delta)
	_update_beam_visual(delta)
	_update_expression(delta)
	_update_stars(delta)


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
		_wing_nodes.clear()
		_wings_searched = false
		_wing_fold_applied = 0.0

	var identity := HunterRoster.get_identity(model_id)
	_model = ModelSlot.instantiate_hunter(identity)
	if _model:
		add_child(_model)
		_animation_player = ModelSlot.find_animation_player(_model)
		if SecretCreatures.uses_creature_rig(model_id):
			_creature = CreatureView.new(self, _model)
		else:
			NightWatchPoses.install(_model, _animation_player, _shown_id)
			_nw_layers.bind(_model)
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
		_head_node.add_child(_kathy_beam)
		_beam_neutral = eye_color
		_beam_color = eye_color
		_beam_chase_mix = 0.0
		_build_beam_visual()


func _build_beam_visual() -> void:
	var length := GameConfig.KATHY_BEAM_RANGE
	var shell_radius := minf(length * tan(GameConfig.KATHY_BEAM_HALF_ANGLE), BEAM_SHELL_RADIUS_CAP)
	var shader := Shader.new()
	shader.code = BEAM_SHADER
	for part in ["Shell", "Core"]:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = shell_radius if part == "Shell" else shell_radius * .28
		cone.height = length
		cone.radial_segments = 20
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
		instance.rotation_degrees = Vector3(90, 0, 0)
		instance.position = Vector3(0, 0, -length * .5)
		_kathy_beam.add_child(instance)
		if part == "Shell":
			_beam_shell = instance
		else:
			_beam_core = instance
	_update_beam_visual(0.0)


## Neutral colour while patrolling, red while chasing; the light itself follows so the lit floor matches the beam.
func _update_beam_visual(delta: float) -> void:
	if _kathy_beam == null or brain == null:
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
		shell.set_shader_parameter("strength", lerpf(.22, .34, _beam_chase_mix) * dim)
		shell.set_shader_parameter("pulse_speed", pulse_speed)
	if _beam_core != null:
		var core := _beam_core.material_override as ShaderMaterial
		core.set_shader_parameter("beam_color", _beam_color.lerp(Color.WHITE, .35))
		core.set_shader_parameter("strength", lerpf(.5, .8, _beam_chase_mix) * dim)
		core.set_shader_parameter("pulse_speed", pulse_speed)


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
	var fade := .72 if gimmick_hidden else 0.0
	ModelSlot.set_character_fade(_model, fade)
	if _kathy_beam != null:
		_kathy_beam.visible = _model.visible


## Body follows the way she is actually travelling (smoothed position delta, so
## it also works on guests), turning at a capped rate with no snapping. Standing
## still: a chasing hunter turns toward the runner, anyone else keeps the
## brain's last real heading.
func _update_body_yaw() -> void:
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
func _emote_cue(radius: float) -> void:
	if radius <= 0.0 or not is_inside_tree():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var distance := global_position.distance_to(camera.global_position)
	if distance >= radius:
		return
	var side := (global_position - camera.global_position).dot(camera.global_basis.x)
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


func _update_animation() -> void:
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
	elif brain.gimmick is XivvyGimmick \
			and (brain.gimmick as XivvyGimmick).airborne():
		clip_name = "flight"
	elif brain.gimmick is LoxelleGimmick \
			and (brain.gimmick as LoxelleGimmick).charge_active():
		clip_name = "charge"
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
