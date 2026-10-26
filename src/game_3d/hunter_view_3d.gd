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
var _flight_height := 0.0
var _desired_xz := Vector2.ZERO
var _surface_target_y := 0.0
var _streamed_height_override := 0.0
var _streamed_height_override_active := false
var _presentation_initialized := false
var _heading_initialized := false
var _head_node: Node3D
var _head_base_y := 0.0
var _head_look_yaw := 0.0
var _head_scan_phase := 0.0
var _kathy_beam: SpotLight3D
var _carries_scythe := false

## Kathy (and Umbriel disguised as her) carries her scythe in the right hand: the model has a
## R-HandProp locator and scythe_idle / scythe_walk / scythe_swing clips for carrying it.
const SCYTHE_PATH := "res://assets/props_3d/kathy_scythe.glb"
## While she carries it, a chase uses the scythe walk played this much faster.
const SCYTHE_CHASE_SPEED := 1.8
const GRAVITY_ACCELERATION := 24.0
const MAX_PRESENTATION_SPEED := 12.0
const HUNTER_BODY_RADIUS := .28
const HUNTER_BODY_HEIGHT := 1.72
const HEAD_LOOK_LIMIT := deg_to_rad(52.0)
const HEAD_SCAN_LIMIT := deg_to_rad(24.0)
const HEAD_LOOK_SPEED := 5.5
## Body rotation follows the brain's movement without teleporting around a
## corner. This also prevents a newly selected wander waypoint behind the
## hunter from producing an instant 180-degree visual snap.
const BODY_TURN_SPEED := deg_to_rad(300.0)


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


func _physics_process(delta: float) -> void:
	if brain == null or not _presentation_initialized:
		return
	var planar := _desired_xz - Vector2(position.x, position.z)
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
			and (brain.gimmick as XivvyGimmick).flying:
		position.y = move_toward(position.y, _surface_target_y, delta * 3.5)
		velocity.y = 0.0
	else:
		if not is_on_floor():
			velocity.y -= GRAVITY_ACCELERATION * delta
		else:
			velocity.y = -0.35
	move_and_slide()
	# Streamed chunks may finish between physics frames. Do not allow a hunter
	# to fall forever while her destination floor is still being attached.
	if not _streamed_height_override_active \
			and position.y < _surface_target_y - StreamedFacilityView3D.LEVEL_HEIGHT:
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
		_carries_scythe = false

	var identity := HunterRoster.get_identity(model_id)
	_model = ModelSlot.instantiate_hunter(identity)
	if _model:
		add_child(_model)
		_animation_player = ModelSlot.find_animation_player(_model)
		_configure_character_lights()
		_attach_scythe()
		_apply_visibility()


func _attach_scythe() -> void:
	_carries_scythe = false
	if _shown_id != "kathy" or _animation_player == null \
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
	_head_base_y = _head_node.rotation.y
	_head_scan_phase = float(abs(hash(brain.hunter_id if brain != null else _shown_id)) % 628) \
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


func _update_head_look(delta: float) -> void:
	if _head_node == null or brain == null:
		return
	var desired_yaw := 0.0
	if has_look_target and brain.active and brain.stun_timer <= 0.0:
		var offset := look_target_position - brain.position
		if offset.length_squared() > .001:
			var target_yaw := atan2(-offset.x, -offset.y)
			desired_yaw = clampf(wrapf(target_yaw - rotation.y, -PI, PI),
				-HEAD_LOOK_LIMIT, HEAD_LOOK_LIMIT)
	elif brain.active and brain.stun_timer <= 0.0 \
			and brain.state != HunterBrain.State.CHASE:
		desired_yaw = sin(Time.get_ticks_msec() * .00135 + _head_scan_phase) \
			* HEAD_SCAN_LIMIT
	_head_look_yaw = lerp_angle(_head_look_yaw, desired_yaw,
		clampf(delta * HEAD_LOOK_SPEED, 0.0, 1.0))
	var head_rotation := _head_node.rotation
	head_rotation.y = _head_base_y + _head_look_yaw
	_head_node.rotation = head_rotation


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


func sync_from_brain() -> void:
	if brain == null:
		return
	var surface_y := float(surface_height_provider.call(brain.position)) \
		if surface_height_provider.is_valid() else 0.0
	var xivvy_flying := brain.gimmick is XivvyGimmick \
		and (brain.gimmick as XivvyGimmick).flying
	var flight_target := GameConfig.XIVVY_FLIGHT_HEIGHT if xivvy_flying else 0.0
	_flight_height = move_toward(_flight_height, flight_target,
		get_process_delta_time() * 1.7)
	if _flight_height > 0.0:
		_flight_height += sin(Time.get_ticks_msec() * 0.006) * 0.0015
	surface_y += _flight_height
	_desired_xz = brain.position
	_surface_target_y = surface_y
	if _streamed_height_override_active:
		_surface_target_y = _streamed_height_override
	if not _presentation_initialized:
		position = Vector3(brain.position.x, _surface_target_y, brain.position.y)
		_presentation_initialized = true
	if brain.facing.length_squared() > 0.0001:
		# Godot's forward direction is -Z. The old angle aligned +Z with the
		# brain direction, so every hunter visually ran back-first even though
		# her simulation and radar movement were correct.
		var target_yaw := atan2(-brain.facing.x, -brain.facing.y)
		if not _heading_initialized:
			rotation.y = target_yaw
			_heading_initialized = true
		else:
			var turn_step := BODY_TURN_SPEED * maxf(
				get_process_delta_time(), 1.0 / 60.0)
			var yaw_delta := wrapf(target_yaw - rotation.y, -PI, PI)
			rotation.y += clampf(yaw_delta, -turn_step, turn_step)
	_apply_model(_desired_model_id())
	_apply_visibility()
	_update_animation()


## idle/walk/chase/sprint/stun/flight/charge (plus scythe_* for Kathy) — the blocky rig's clips; older models
## without sprint fall back to chase through play_if_available.
## Investigate/search both read as "walk" (she's purposefully moving toward
## somewhere, just not at chase urgency yet); only an actual sighting-driven
## chase gets the more urgent clip.
func _update_animation() -> void:
	var clip_name := "idle"
	if brain.stun_timer > 0.0:
		clip_name = "stun"
	elif brain.gimmick is XivvyGimmick \
			and (brain.gimmick as XivvyGimmick).flying:
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
	if clip_name == "sprint" and _animation_player != null and not _animation_player.has_animation("sprint"):
		clip_name = "chase"
	var speed := 1.0
	if _carries_scythe:
		match clip_name:
			"idle":
				clip_name = "scythe_idle"
			"walk":
				clip_name = "scythe_walk"
			"chase", "sprint":
				clip_name = "scythe_walk"
				speed = SCYTHE_CHASE_SPEED
	ModelSlot.play_if_available(_animation_player, clip_name)
	if _animation_player != null:
		_animation_player.speed_scale = speed
