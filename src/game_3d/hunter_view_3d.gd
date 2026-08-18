class_name HunterView3D
extends Node3D

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

var _animation_player: AnimationPlayer
var _model: Node3D
var _shown_id := ""
var _flight_height := 0.0


func _ready() -> void:
	_apply_model(_desired_model_id())


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

	var identity := HunterRoster.get_identity(model_id)
	_model = ModelSlot.instantiate(identity["model_scene"])
	if _model:
		add_child(_model)
		_animation_player = ModelSlot.find_animation_player(_model)
		_apply_visibility()


## Porcelle is hidden every frame she exists; Ceryth only becomes hidden
## partway through the floor, the moment she disperses. Checked every sync
## rather than only when the model is (re)built, so a gimmick that changes its
## mind mid-floor is reflected without needing a model swap to trigger it.
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
	_model.visible = not (gimmick_hidden or inactive)


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
	position = Vector3(brain.position.x, surface_y, brain.position.y)
	if brain.facing.length_squared() > 0.0001:
		# Godot's forward direction is -Z. The old angle aligned +Z with the
		# brain direction, so every hunter visually ran back-first even though
		# her simulation and radar movement were correct.
		rotation.y = atan2(-brain.facing.x, -brain.facing.y)
	_apply_model(_desired_model_id())
	_apply_visibility()
	_update_animation()


## idle/walk/chase — see art/props-3d/README.md's animation convention.
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
				clip_name = "chase"
			HunterBrain.State.WANDER, HunterBrain.State.INVESTIGATE, HunterBrain.State.SEARCH:
				clip_name = "walk"
	ModelSlot.play_if_available(_animation_player, clip_name)
