class_name PlayerController3D
extends CharacterBody3D

## 3D counterpart to src/game/player_controller.gd. Same stamina/lamp/
## interaction rules (GameConfig is shared, untouched), CharacterBody3D
## movement on the XZ ground plane instead of CharacterBody2D on XY, and two
## camera rigs (orthographic top-down, perspective first-person) toggled by
## FIRST PERSON only.
##
## There was a top-down view on the V key, inherited from the 2D original. It
## rendered black in the 3D build and survived three attempts to fix it -- the
## camera was current, the world was in front of it, the ceiling was hidden and
## a directional light was on it, and it was still black. It is also redundant:
## the facility is a real 3D building now, and the memory map is the thing that
## reads a floor plan. So it is gone rather than carried as a broken option.

signal flashlight_changed(enabled: bool)
signal interaction_message(message: String)

const CAMERA_HEIGHT := 1.6
const BODY_MODEL_SCENE := "res://art/props-3d/characters/player.tscn"

## Sibling, not a child — the top-down camera must NOT inherit the player's
## facing rotation (it stays fixed, looking straight down, and only follows
## position each frame). See _physics_process.
@onready var first_person_camera: Camera3D = $FirstPersonPivot/FirstPersonCamera
@onready var first_person_pivot: Node3D = $FirstPersonPivot
@onready var flashlight: SpotLight3D = $FirstPersonPivot/Flashlight
## Empty container — its child model comes from ModelSlot (see _ready), so
## replacing BODY_MODEL_SCENE's contents with a real model needs no changes
## here.
@onready var body_visual: Node3D = $BodyVisual

var flashlight_enabled := true
## True while the facility's heater station is running — warms the ambient,
## and is Wynelle's counterplay (see heater_station in route_interactable_3d).
var heater_on := false
var stamina := GameConfig.MAX_STAMINA
var lamp_charge := GameConfig.MAX_LAMP_CHARGE
var exhausted := false
var stamina_recovery_delay := 0.0
var movement_mode := "walk"
## Noise emitted this frame by movement, consumed by hunter hearing
## (hunter_brain.gd) — matches the original's per-frame emittedNoise.
var noise := 0.0
## Frozen during the capture/escape struggle (main_3d.gd) — movement and
## interaction stop, but the scene keeps rendering/ticking around the player.
var input_frozen := false

## Exposure / noise / temperature, shared with hunter gimmicks that read them
## (see src/game/player_meters.gd).
var meters := PlayerMeters.new()
## Facing on the facility's XZ ground plane, for beam-aim checks (Nyxie's
## dispel). Derived from body yaw, which both control schemes already set.
var facing := Vector2(0, 1)

var _yaw := 0.0
var _pitch := 0.0
var _animation_player: AnimationPlayer
## The clip this body is playing, published so remote copies can play the same
## one. Set where the local body is told to play, so the two cannot disagree.
var _clip := "idle"

## Out of sight, in a locker. Movement stops, the body is not drawn, and
## perception treats you as gone -- the shared brain's `hidden` gate has always
## been there, wired to a literal false because nothing could hide.
var hidden := false
var hidden_spot := Vector2i(-1, -1)

## Ceryth's trap: a spot she has staked out answers the flashlight riddle wrong
## and locks you in rather than letting you hide. Set by the scene; called
## before every voluntary entry, never for a hunter reaching in from outside.
var hiding_trap_resolver: Callable
## Ceryth's lock. Counts down regardless of input_frozen, which is what makes
## it a real lock rather than a freeze the exit key already bypasses.
var hiding_lock_timer := 0.0


func enter_hiding(cell: Vector2i) -> String:
	var cleared_message := ""
	if hiding_trap_resolver.is_valid():
		var result: Dictionary = hiding_trap_resolver.call(cell, flashlight_enabled and lamp_charge > 0.0)
		if bool(result.get("trapped", false)):
			hidden = true
			hidden_spot = cell
			velocity = Vector3.ZERO
			input_frozen = true
			if body_visual:
				body_visual.visible = false
			hiding_lock_timer = GameConfig.CERYTH_LOCK_SECONDS
			_set_flashlight(false)
			return String(result.get("message", "Trapped."))
		# Answered right: she disperses, but the spot itself is a normal safe
		# hide from here on -- the riddle was the trap, not the locker.
		cleared_message = String(result.get("message", ""))
	hidden = true
	hidden_spot = cell
	velocity = Vector3.ZERO
	input_frozen = true
	if body_visual:
		body_visual.visible = false
	return cleared_message if not cleared_message.is_empty() else "Hidden. [E] to come out."


## `forced`: another hunter reaching in (Jyvra, Loxelle) rather than the player
## working the exit key. A forced pull ignores Ceryth's lock on purpose --
## being physically dragged out is not the thing the lock exists to prevent.
func leave_hiding(at: Vector2 = Vector2.ZERO, forced: bool = false) -> String:
	if hiding_lock_timer > 0.0 and not forced:
		return "Locked in hiding for %.0fs." % hiding_lock_timer
	hidden = false
	hidden_spot = Vector2i(-1, -1)
	input_frozen = false
	hiding_lock_timer = 0.0
	if at != Vector2.ZERO:
		global_position = Vector3(at.x, global_position.y, at.y)
	return "Out of hiding."


## Forces the flashlight to strobe on/off at random short intervals for
## `duration` seconds, then restores whatever it was actually set to --
## generic infrastructure for a hunter gimmick to reach for (a signal jam, a
## "she's close" tell), the same way interaction_veto/hiding_trap_resolver
## are. Overrides the beam regardless of the player's own F-key state while
## it runs; a forced effect the player could shrug off by holding F down
## would not read as forced.
var _flicker_remaining := 0.0
var _flicker_next_toggle := 0.0
var _flicker_min_period := 0.08
var _flicker_max_period := 0.35


## The other half of the same idea, for an effect that isn't the flashlight --
## TV static, currently. Set by the scene (HUD.trigger_static), called the
## same way: `player.trigger_static_effect.call(duration)`. A Callable rather
## than a direct HUD reference so a gimmick reaching for it needs only the
## player, matching interaction_veto/hiding_trap_resolver.
var trigger_static_effect: Callable


func force_flashlight_flicker(duration: float, min_period: float = 0.08, max_period: float = 0.35) -> void:
	_flicker_remaining = maxf(_flicker_remaining, duration)
	_flicker_min_period = min_period
	_flicker_max_period = max_period
	_flicker_next_toggle = 0.0


## True while a hunter is holding the beam hostage -- so the player's own [F]
## does not fight it or leave the light in a state force_flashlight_flicker
## did not intend.
func flashlight_seized() -> bool:
	return _flicker_remaining > 0.0


func _ready() -> void:
	var model := ModelSlot.instantiate(BODY_MODEL_SCENE)
	if model:
		body_visual.add_child(model)
		_animation_player = ModelSlot.find_animation_player(model)
	# Explicitly through _set_flashlight rather than by poking `visible`, so the
	# lamp-charge gate applies at spawn exactly as it does on a manual toggle.
	# The maze is lit almost entirely by this beam; starting dark reads as a
	# broken build rather than as atmosphere.
	_set_flashlight(true)
	_enter_first_person()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_yaw -= event.relative.x * Settings.mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * Settings.mouse_sensitivity, -1.4, 1.4)
		rotation.y = _yaw
		first_person_pivot.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	if hiding_lock_timer > 0.0:
		hiding_lock_timer = maxf(0.0, hiding_lock_timer - delta)
	if input_frozen:
		velocity = Vector3.ZERO
		move_and_slide()
		noise = 0.0
		_clip = "idle"
		ModelSlot.play_if_available(_animation_player, _clip)
		# Hiding freezes movement, and freezing movement used to swallow the key
		# that gets you back out -- a locker you could enter and never leave. The
		# struggle freeze is the other user of input_frozen and deliberately does
		# NOT get this: mashing [E] there is the escape, handled in main_3d.
		if hidden and Input.is_action_just_pressed("interact"):
			_try_interact()
		return

	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var movement_speed := GameConfig.PLAYER_WALK_SPEED
	var is_moving := input_vector.length_squared() > 0.0
	var wants_to_sprint := Input.is_action_pressed("sprint") and is_moving and not exhausted
	var is_sprinting := false

	if Input.is_action_pressed("crouch"):
		movement_speed = GameConfig.PLAYER_CROUCH_SPEED
		movement_mode = "crouch"
	elif wants_to_sprint and stamina > 0.0:
		movement_speed = GameConfig.PLAYER_SPRINT_SPEED
		is_sprinting = true
		movement_mode = "sprint"
	else:
		movement_mode = "walk"

	noise = 0.0 if not is_moving else (GameConfig.NOISE_CROUCH if movement_mode == "crouch" else (GameConfig.NOISE_SPRINT if is_sprinting else GameConfig.NOISE_WALK))

	meters.update(delta, {
		"flashlight_on": flashlight_enabled,
		"noise": noise,
		"crouching": movement_mode == "crouch",
		"hidden": hidden,
		"in_safe_zone": is_in_safe_zone(),
		"heater_on": heater_on,
	})

	_update_stamina(delta, is_sprinting)
	_update_lamp(delta, is_sprinting)
	_clip = movement_mode if is_moving else "idle"
	ModelSlot.play_if_available(_animation_player, _clip)

	var move_direction: Vector3
	# Movement is camera-relative: forward is where you are looking.
	if true:
		# Relative to facing: forward/back on move_up/move_down, strafe on move_left/move_right.
		move_direction = (transform.basis * Vector3(input_vector.x, 0.0, input_vector.y)).normalized() if is_moving else Vector3.ZERO
	else:
		# Fixed world axes, matching the 2D top-down control scheme.
		move_direction = Vector3(input_vector.x, 0.0, input_vector.y)
		if is_moving:
			rotation.y = atan2(input_vector.x, input_vector.y)
			_yaw = rotation.y

	# GameConfig's speed constants are px/s at TILE_SIZE=16px per 2D tile;
	# the 3D world uses 1 tile = 1 meter (see art/props-3d/README.md), so
	# converting px/s -> tiles/s gives the equivalent m/s. Freezing slows you.
	var speed_mps := movement_speed * meters.movement_scale() / GameConfig.TILE_SIZE
	# Grid-space facing: the facility's (x, y) maps onto XZ, and body yaw is
	# measured with atan2(x, z), so this is the same direction the beam points.
	facing = Vector2(sin(rotation.y), cos(rotation.y))

	velocity.x = move_direction.x * speed_mps
	velocity.z = move_direction.z * speed_mps
	velocity.y = 0.0
	move_and_slide()


	_update_flashlight_flicker(delta)
	if Input.is_action_just_pressed("flashlight") and not flashlight_seized():
		_set_flashlight(not flashlight_enabled)

	_update_resecure(delta)
	if Input.is_action_just_pressed("interact"):
		_try_interact()


## First person is the only view. The body is hidden because you are inside it,
## and the mouse is captured because the camera is aimed with it.
## What this body is playing, for RemotePlayers to send on.
func current_clip() -> String:
	return _clip


func _enter_first_person() -> void:
	first_person_camera.current = true
	body_visual.visible = false
	# Stated as a preference, not set directly: a menu on top has to be able to
	# hand the cursor back without this taking it again next frame.
	MouseLock.set_gameplay_capture(true)


func _update_stamina(delta: float, is_sprinting: bool) -> void:
	if is_sprinting:
		stamina = maxf(0.0, stamina - GameConfig.STAMINA_SPRINT_DRAIN * delta)
		stamina_recovery_delay = GameConfig.STAMINA_RECOVERY_DELAY
		if stamina <= 0.0:
			exhausted = true
		return

	stamina_recovery_delay = maxf(0.0, stamina_recovery_delay - delta)
	if stamina_recovery_delay <= 0.0:
		stamina = minf(GameConfig.MAX_STAMINA, stamina + GameConfig.STAMINA_RECOVERY * delta)
	if exhausted and stamina >= GameConfig.STAMINA_EXHAUSTED_RECOVERY:
		exhausted = false


func _update_lamp(delta: float, is_sprinting: bool) -> void:
	if not flashlight_enabled:
		return
	var drain := GameConfig.LAMP_IDLE_DRAIN
	if is_sprinting:
		drain += GameConfig.LAMP_SPRINT_DRAIN
	lamp_charge = maxf(0.0, lamp_charge - drain * meters.drain_scale() * delta)
	if lamp_charge <= 0.0:
		_set_flashlight(false)


func _update_flashlight_flicker(delta: float) -> void:
	if _flicker_remaining <= 0.0:
		return
	_flicker_remaining -= delta
	_flicker_next_toggle -= delta
	if _flicker_remaining <= 0.0:
		# Restore the real state rather than leaving the beam wherever the
		# last random toggle left it.
		flashlight.visible = flashlight_enabled
		return
	if _flicker_next_toggle <= 0.0:
		flashlight.visible = not flashlight.visible
		_flicker_next_toggle = randf_range(_flicker_min_period, _flicker_max_period)


func _set_flashlight(enabled: bool) -> void:
	flashlight_enabled = enabled and lamp_charge > 0.0
	flashlight.visible = flashlight_enabled
	flashlight_changed.emit(flashlight_enabled)


func restore_lamp(amount: float) -> void:
	lamp_charge = minf(GameConfig.MAX_LAMP_CHARGE, lamp_charge + amount)


## World position projected onto facility_generator.gd's grid-cell space —
## valid because the 3D world uses 1 cell = 1 meter with the grid's (x,y)
## mapped directly onto the XZ ground plane (see facility_view_3d.gd).
func grid_position() -> Vector2:
	return Vector2(global_position.x, global_position.z)


func restore_at_safe_zone() -> void:
	stamina = GameConfig.MAX_STAMINA
	lamp_charge = GameConfig.MAX_LAMP_CHARGE
	exhausted = false


## Mirrors ui-controller.js's inSafeZone battery-color branch — true while
## standing within a safe zone's rest radius, regardless of whether it has
## already been activated with [E].
func is_in_safe_zone() -> bool:
	var radius_m := GameConfig.SAFE_ZONE_RADIUS / GameConfig.TILE_SIZE
	for candidate in get_tree().get_nodes_in_group("interactable"):
		if candidate is RouteInteractable3D and candidate.kind == RouteInteractable3D.Kind.SAFE_ZONE \
			and global_position.distance_to(candidate.global_position) <= radius_m:
			return true
	return false


func get_interaction_prompt() -> String:
	var percent := resecure_percent()
	if percent >= 0:
		return "RESTORING SIGNAL // %d%%" % percent
	var target := _nearest_interactable()
	if target == null:
		return ""
	var prompt: String = target.get_prompt()
	return "[E] %s" % prompt if not prompt.is_empty() else ""


## Something on the floor may refuse an interaction outright -- Opalie standing
## watch over a relay. Set by the scene that owns the hunters; returns the
## refusal to show, or "" to let it through. A Callable rather than a direct
## call because the player has no business knowing what a hunter is.
var interaction_veto: Callable


func _try_interact() -> void:
	var target := _nearest_interactable()
	if target == null:
		interaction_message.emit("Nothing is within reach.")
		return
	# A sabotaged relay is worked entirely through the hold in
	# _update_resecure() -- a single press would just bounce off activate()'s
	# "already collected" case, which is technically true but not what a
	# HOLD prompt told the player to do.
	if target.kind == RouteInteractable3D.Kind.RELAY and target.sabotaged:
		return
	if interaction_veto.is_valid():
		var refused := String(interaction_veto.call(target))
		if not refused.is_empty():
			interaction_message.emit(refused)
			return
	interaction_message.emit(target.activate(self))


## Briselle's counter: hold [E] near a relay she has sabotaged for
## RELAY_RESECURE_SECONDS to bring it back online. Continuous, not
## edge-triggered like _try_interact -- matches the original's own hold-to-
## restore, and unlike a single press this has visible progress to show.
var _resecure_target: RouteInteractable3D
var _resecure_progress := 0.0


func _update_resecure(delta: float) -> void:
	var target := _nearest_interactable()
	var is_sabotaged_relay := target != null and target.kind == RouteInteractable3D.Kind.RELAY \
		and target.sabotaged
	if not is_sabotaged_relay or target != _resecure_target:
		_resecure_target = target if is_sabotaged_relay else null
		_resecure_progress = 0.0
	if _resecure_target == null:
		return
	if not Input.is_action_pressed("interact"):
		_resecure_progress = 0.0
		return
	_resecure_progress += delta
	if _resecure_progress >= GameConfig.RELAY_RESECURE_SECONDS:
		var message := _resecure_target.set_sabotaged(false)
		_resecure_progress = 0.0
		_resecure_target = null
		if not message.is_empty():
			interaction_message.emit(message)


## Percent through a resecure hold, or -1 while nothing is being held --
## the interaction prompt reads this to show live progress the same way the
## original's own "[ HOLD E ] // 40%" readout does.
func resecure_percent() -> int:
	if _resecure_target == null:
		return -1
	return clampi(roundi(_resecure_progress / GameConfig.RELAY_RESECURE_SECONDS * 100.0), 0, 100)


func _nearest_interactable() -> RouteInteractable3D:
	var nearest: RouteInteractable3D = null
	var nearest_distance := GameConfig.INTERACTION_RANGE / GameConfig.TILE_SIZE
	for candidate in get_tree().get_nodes_in_group("interactable"):
		if not candidate is RouteInteractable3D:
			continue
		var distance := global_position.distance_to(candidate.global_position)
		if distance <= nearest_distance and not candidate.get_prompt().is_empty():
			nearest = candidate
			nearest_distance = distance
	return nearest
