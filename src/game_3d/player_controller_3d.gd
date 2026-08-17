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
@onready var xr_origin: XROrigin3D = $XROrigin
@onready var xr_camera: XRCamera3D = $XROrigin/XRCamera
@onready var xr_left: XRController3D = $XROrigin/LeftController
@onready var xr_right: XRController3D = $XROrigin/RightController
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

## Debug-only protections driven by main_3d's tools-gated admin overlay. They
## live on the controller so the same state can be published to the ENet host;
## release builds never get the menu which changes either value.
var admin_no_target := false
var admin_god_mode := false

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
## OpenXR is opt-in for desktop exports (`--xr` or an `xr` export feature) and
## automatic for the Quest preset. If initialization fails, the same binary
## falls back to the ordinary first-person camera.
var xr_active := false
var _xr_turn_latched := false

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

## Glyra's music box: winding it is resolved by whoever owns her gimmick
## (main_3d), the same indirection as interaction_veto/hiding_trap_resolver --
## a plain interactable has no business knowing what a hunter is.
var music_box_resolver: Callable

## Ilyra's pounce. Deliberately its OWN field rather than reusing
## input_frozen: a stun and a struggle/hiding freeze look the same to the
## player but come from unrelated systems that each clear input_frozen when
## THEY resolve -- exiting a locker while also stunned would have ended the
## stun early if it shared the flag. Independently ticked and checked.
var stun_timer := 0.0

## Verrine's vent network. Resolved the same indirection as
## music_box_resolver -- a plain interactable has no business knowing what a
## hunter is. `in_vent`/`vent_entry_id`/`vent_time_in` are read by
## VerrineGimmick through main_3d's per-frame target dict, mirroring how
## `hidden` already crosses that boundary.
var vent_resolver: Callable
var in_vent := false
var vent_entry_id := ""
var vent_time_in := 0.0

## Zephyra's shop -- the same indirection as vent_resolver/music_box_resolver.
## `shop_resolver.call("open")` opens or re-toasts the menu (the gimmick
## itself checks range, so a far-away call is a harmless no-op the same way
## _nearest_interactable() already handles distance for ordinary pickups);
## `.call("1")`..`.call("4")` chooses an offer while a menu is open. The
## original borrows its hotbar's digit keys for this; this port has no
## hotbar, so raw digit-key presses (see _unhandled_input) are the one
## deliberate exception to routing everything through a named input action.
var shop_resolver: Callable
var shop_prompt_provider: Callable

## Zephyra's pesticide trade: a real timer, not a boolean, so it reads the
## same way stun_timer/hiding_lock_timer do and main_3d can thread a plain
## "time remaining" into the hunter target dict for Loxelle/Ysolde to skip
## their own ability while it runs.
var pesticide_timer := 0.0


func is_stunned() -> bool:
	return stun_timer > 0.0


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
	_connect_xr_buttons()
	if not _try_enter_xr():
		_enter_first_person()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not xr_active:
		_yaw -= event.relative.x * Settings.mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * Settings.mouse_sensitivity, -1.4, 1.4)
		rotation.y = _yaw
		first_person_pivot.rotation.x = _pitch
	elif event is InputEventKey and event.pressed and not event.echo and shop_resolver.is_valid():
		var key := (event as InputEventKey).physical_keycode
		if key >= KEY_1 and key <= KEY_4:
			var message := String(shop_resolver.call(str(key - KEY_1 + 1)))
			if not message.is_empty():
				interaction_message.emit(message)


func _physics_process(delta: float) -> void:
	if hiding_lock_timer > 0.0:
		hiding_lock_timer = maxf(0.0, hiding_lock_timer - delta)
	if stun_timer > 0.0:
		stun_timer = maxf(0.0, stun_timer - delta)
	if pesticide_timer > 0.0:
		pesticide_timer = maxf(0.0, pesticide_timer - delta)
	if in_vent:
		vent_time_in += delta
	if input_frozen or stun_timer > 0.0:
		velocity = Vector3.ZERO
		move_and_slide()
		noise = 0.0
		_clip = "idle"
		ModelSlot.play_if_available(_animation_player, _clip)
		# Hiding freezes movement, and freezing movement used to swallow the key
		# that gets you back out -- a locker you could enter and never leave. The
		# struggle freeze is the other user of input_frozen and deliberately does
		# NOT get this: mashing [E] there is the escape, handled in main_3d. A
		# stun gets neither -- Ilyra's pounce is a real incapacitation, not a
		# state with its own exit key.
		if input_frozen and hidden and Input.is_action_just_pressed("interact"):
			_try_interact()
		return

	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if xr_active:
		var stick := xr_left.get_vector2("primary")
		if stick.length_squared() > input_vector.length_squared():
			# OpenXR stick-up is positive; Input.get_vector's forward/W is -Y.
			input_vector = Vector2(stick.x, -stick.y)
	var movement_speed := GameConfig.PLAYER_WALK_SPEED
	var difficulty := RoomState.difficulty_profile()
	var is_moving := input_vector.length_squared() > 0.0
	var wants_to_sprint := Input.is_action_pressed("sprint") and is_moving and not exhausted
	var is_sprinting := false

	if Input.is_action_pressed("crouch"):
		movement_speed = GameConfig.PLAYER_CROUCH_SPEED * float(difficulty["crouch_speed"])
		movement_mode = "crouch"
	elif wants_to_sprint and stamina > 0.0:
		movement_speed = GameConfig.PLAYER_SPRINT_SPEED * float(difficulty["sprint_speed"])
		is_sprinting = true
		movement_mode = "sprint"
	else:
		movement_speed *= float(difficulty["player_speed"])
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
	if xr_active:
		var head_forward := -xr_camera.global_basis.z
		head_forward.y = 0.0
		head_forward = head_forward.normalized()
		var head_right := xr_camera.global_basis.x
		head_right.y = 0.0
		head_right = head_right.normalized()
		move_direction = (head_right * input_vector.x + head_forward * -input_vector.y
			).normalized() if is_moving else Vector3.ZERO
	else:
		# Relative to facing: forward/back on move_up/move_down, strafe on move_left/move_right.
		move_direction = (transform.basis * Vector3(input_vector.x, 0.0, input_vector.y)).normalized() if is_moving else Vector3.ZERO

	# GameConfig's speed constants are px/s at TILE_SIZE=16px per 2D tile;
	# the 3D world uses 1 tile = 1 meter (see art/props-3d/README.md), so
	# converting px/s -> tiles/s gives the equivalent m/s. Freezing slows you.
	var speed_mps := movement_speed * meters.movement_scale() / GameConfig.TILE_SIZE
	# Grid-space facing: the facility's (x, y) maps onto XZ. A Node3D's own
	# forward is -Z (Godot's camera-forward convention, and this body's
	# camera is a plain child of it with no extra yaw of its own), which
	# rotation.y turns exactly like everything else here -- so the forward
	# vector at yaw θ is (-sin θ, 0, -cos θ), not (sin θ, 0, cos θ). The old
	# unnegated version pointed the minimap arrow, and every beam-aim check
	# that reads this field, exactly backwards.
	if xr_active:
		var look := -xr_camera.global_basis.z
		facing = Vector2(look.x, look.z).normalized()
		flashlight.global_transform = xr_camera.global_transform
		_update_xr_snap_turn()
	else:
		facing = Vector2(-sin(rotation.y), -cos(rotation.y))

	velocity.x = move_direction.x * speed_mps
	velocity.z = move_direction.z * speed_mps
	velocity.y = 0.0
	move_and_slide()
	if is_moving:
		Sound.footstep(movement_mode)


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


func _wants_xr() -> bool:
	return OS.has_feature("xr") or OS.get_cmdline_user_args().has("--xr")


func _try_enter_xr() -> bool:
	if not _wants_xr():
		return false
	var interface := XRServer.find_interface("OpenXR")
	if interface == null:
		push_warning("OPENXR // interface unavailable; using desktop camera")
		return false
	if not interface.is_initialized() and not interface.initialize():
		push_warning("OPENXR // runtime initialization failed; using desktop camera")
		return false
	xr_active = true
	get_viewport().use_xr = true
	first_person_camera.current = false
	xr_camera.current = true
	body_visual.visible = false
	MouseLock.set_gameplay_capture(false)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	return true


func _connect_xr_buttons() -> void:
	xr_right.button_pressed.connect(_on_xr_right_pressed)
	xr_right.button_released.connect(_on_xr_right_released)
	xr_left.button_pressed.connect(_on_xr_left_pressed)
	xr_left.button_released.connect(_on_xr_left_released)


func _on_xr_right_pressed(action: StringName) -> void:
	match String(action):
		"trigger_click":
			Input.action_press("interact")
		"ax_button":
			Input.action_press("flashlight")
		"grip_click":
			Input.action_press("sprint")


func _on_xr_right_released(action: StringName) -> void:
	match String(action):
		"trigger_click":
			Input.action_release("interact")
		"ax_button":
			Input.action_release("flashlight")
		"grip_click":
			Input.action_release("sprint")


func _on_xr_left_pressed(action: StringName) -> void:
	match String(action):
		"primary_click":
			Input.action_press("crouch")
		"by_button":
			Input.action_press("toggle_map")
		"menu_button":
			_emit_xr_action_event("pause", true)


func _on_xr_left_released(action: StringName) -> void:
	match String(action):
		"primary_click":
			Input.action_release("crouch")
		"by_button":
			Input.action_release("toggle_map")
		"menu_button":
			_emit_xr_action_event("pause", false)


func _emit_xr_action_event(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)


## Thirty-degree comfort turn with a latch, so holding the stick cannot spin
## several steps per physics frame. Physical room-scale offset remains owned
## by OpenXR beneath this body.
func _update_xr_snap_turn() -> void:
	var turn := xr_right.get_vector2("primary").x
	if absf(turn) < 0.45:
		_xr_turn_latched = false
		return
	if _xr_turn_latched:
		return
	_xr_turn_latched = true
	rotate_y(deg_to_rad(-30.0 if turn > 0.0 else 30.0))


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
	var difficulty := RoomState.difficulty_profile()
	var drain := GameConfig.LAMP_IDLE_DRAIN * float(difficulty["lamp_drain"])
	if is_sprinting:
		drain += GameConfig.LAMP_SPRINT_DRAIN * float(difficulty["sprint_drain"])
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
	if target != null:
		var prompt: String = target.get_prompt()
		if not prompt.is_empty():
			return "[E] %s" % prompt
	if shop_prompt_provider.is_valid():
		var shop_prompt: String = String(shop_prompt_provider.call())
		if not shop_prompt.is_empty():
			return "[E] %s" % shop_prompt
	return ""


## Something on the floor may refuse an interaction outright -- Opalie standing
## watch over a relay. Set by the scene that owns the hunters; returns the
## refusal to show, or "" to let it through. A Callable rather than a direct
## call because the player has no business knowing what a hunter is.
var interaction_veto: Callable


func _try_interact() -> void:
	var target := _nearest_interactable()
	if target == null:
		if shop_resolver.is_valid():
			var message := String(shop_resolver.call("open"))
			if not message.is_empty():
				interaction_message.emit(message)
				return
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


## Nearest interactable in reach AND actually being looked at -- being close
## to something used to be enough on its own, which let a player trigger
## whatever was nearest behind or beside them without turning to face it.
## Facing is checked on the grid plane only (same 2D convention `facing`
## already uses for the hunters' own beam-aim checks), so looking up or down
## at a target roughly at eye height still counts.
func _nearest_interactable() -> RouteInteractable3D:
	var nearest: RouteInteractable3D = null
	var nearest_distance := GameConfig.INTERACTION_RANGE / GameConfig.TILE_SIZE
	for candidate in get_tree().get_nodes_in_group("interactable"):
		if not candidate is RouteInteractable3D:
			continue
		var offset := Vector2(candidate.global_position.x - global_position.x,
			candidate.global_position.z - global_position.z)
		var distance := offset.length()
		if distance > nearest_distance or candidate.get_prompt().is_empty():
			continue
		if distance > 0.001 and offset.normalized().dot(facing) < cos(GameConfig.INTERACTION_FACING_HALF_ANGLE):
			continue
		nearest = candidate
		nearest_distance = distance
	return nearest
