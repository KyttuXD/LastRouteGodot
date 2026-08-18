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
signal taser_requested
signal tool_used(item_id: String)
signal interaction_message(message: String)

const CAMERA_HEIGHT := 1.6
const BODY_MODEL_SCENE := "res://art/props-3d/characters/player.tscn"
const ADMIN_BODY_MODEL_SCENE := "res://art/props-3d/characters/admin_kyttu.tscn"

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

var flashlight_enabled := false
## First-person equipment is deliberately camera-local. The authoritative
## taser hit is resolved by main_3d; this controller owns only input, cooldown
## presentation, and the local recoil animation.
var first_person_items: Node3D
var flashlight_view: Node3D
var taser_view: Node3D
var tool_views := {}
var taser_cooldown := 0.0
var _flashlight_lens_material: StandardMaterial3D
var _flashlight_item_tween: Tween
var _taser_item_tween: Tween
var _tool_item_tween: Tween
const FLASHLIGHT_ITEM_POSITION := Vector3(0.27, -0.22, -0.52)
const TASER_ITEM_POSITION := Vector3(-0.24, -0.22, -0.50)
const UTILITY_ITEM_POSITION := Vector3(.25, -.24, -.58)
const ITEM_MODEL_PATHS := {
	"flashlight": "res://art/props-3d/interactables/flashlight_item.glb",
	"taser": "res://art/props-3d/interactables/taser_item.glb",
	"lockpick": "res://art/props-3d/interactables/lockpick_set.glb",
	"crowbar": "res://art/props-3d/interactables/crowbar.glb",
	"rescue_axe": "res://art/props-3d/interactables/rescue_axe.glb",
}
const INVENTORY_ITEMS := ["flashlight", "taser", "lockpick", "crowbar", "rescue_axe"]
const INVENTORY_LABELS := {
	"flashlight": "FLASHLIGHT", "taser": "TASER", "lockpick": "LOCKPICK SET",
	"crowbar": "CROWBAR", "rescue_axe": "RESCUE AXE",
}
const INVENTORY_MAX_DURABILITY := {
	"lockpick": 12, "crowbar": 40, "rescue_axe": 24,
}
const BREACH_TOOLS := ["crowbar", "rescue_axe"]
const LOCK_TOOLS := ["lockpick", "crowbar"]
const FRIENDLY_FIRE_ENABLED := false
var selected_inventory_slot := -1
var owned_inventory_items := {
	"flashlight": false, "taser": false, "lockpick": false,
	"crowbar": false, "rescue_axe": false,
}
var inventory_durability := {
	"lockpick": 0, "crowbar": 0, "rescue_axe": 0,
}
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
## Capture presentation owns the view for its short lunge. This is separate
## from input_frozen because hiding and the escape struggle still allow the
## player to look around.
var look_frozen := false

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
var _body_model: Node3D
var _body_fade := 0.0
## The clip this body is playing, published so remote copies can play the same
## one. Set where the local body is told to play, so the two cannot disagree.
var _clip := "idle"
## One-frame hop request used by XR and deterministic gameplay validation.
## Keyboard/controller bindings still use Input's ordinary `jump` action.
var _jump_requested := false
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
## Fastest downward speed since leaving a floor. Sampling the landing frame's
## velocity alone is unreliable because move_and_slide() zeroes it on impact.
var _fall_speed := 0.0

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
	return cleared_message if not cleared_message.is_empty() else "Hidden. Interact to come out."


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
	if not owns_inventory_item("flashlight"):
		return
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
	# Keeps a grounded body attached to the stair ramp while walking down it.
	# The snap is shorter than a real fall, so stepping off the mezzanine still
	# becomes airborne and reaches the fall-stun path below.
	floor_snap_length = 0.28
	var body_scene := ADMIN_BODY_MODEL_SCENE if Backend.admin_authorized() \
		else BODY_MODEL_SCENE
	var model := ModelSlot.instantiate(body_scene)
	if model:
		_body_model = model
		body_visual.add_child(model)
		_animation_player = ModelSlot.find_animation_player(model)
	_build_first_person_items()
	# Equipment is now found in the seeded facility. The beam must stay dark
	# until a flashlight pickup has actually granted the item.
	_set_flashlight(false)
	_connect_xr_buttons()
	if not _try_enter_xr():
		_enter_first_person()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not xr_active and not look_frozen:
		_yaw -= event.relative.x * Settings.mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * Settings.mouse_sensitivity, -1.4, 1.4)
		rotation.y = _yaw
		first_person_pivot.rotation.x = _pitch
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).physical_keycode
		if key >= KEY_1 and key <= KEY_4 and shop_resolver.is_valid():
			var message := String(shop_resolver.call(str(key - KEY_1 + 1)))
			if not message.is_empty():
				interaction_message.emit(message)
				return
		if key >= KEY_1 and key <= KEY_5:
			select_inventory_slot(key - KEY_1)
	elif event is InputEventMouseButton and event.pressed:
		var button := (event as InputEventMouseButton).button_index
		if button == MOUSE_BUTTON_WHEEL_UP:
			select_inventory_slot(selected_inventory_slot - 1)
		elif button == MOUSE_BUTTON_WHEEL_DOWN:
			select_inventory_slot(selected_inventory_slot + 1)


func _physics_process(delta: float) -> void:
	taser_cooldown = maxf(0.0, taser_cooldown - delta)
	_update_first_person_item_lights()
	if hiding_lock_timer > 0.0:
		hiding_lock_timer = maxf(0.0, hiding_lock_timer - delta)
	if stun_timer > 0.0:
		stun_timer = maxf(0.0, stun_timer - delta)
	if pesticide_timer > 0.0:
		pesticide_timer = maxf(0.0, pesticide_timer - delta)
	if in_vent:
		vent_time_in += delta
	if input_frozen or stun_timer > 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
		_update_vertical_motion(delta, false)
		_move_and_resolve_landing()
		noise = 0.0
		_clip = "idle"
		ModelSlot.play_if_available(_animation_player, _clip)
		_update_crouch_fade(delta, false)
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
	# Keep "crouch" as network/gameplay state, but retire the imported pose:
	# its knees and elbows fold backward. A smooth fade now communicates quiet
	# movement while the stable idle pose keeps the body human-shaped.
	_clip = "crouch" if movement_mode == "crouch" else (
		movement_mode if is_moving else "idle")
	ModelSlot.play_if_available(_animation_player,
		"idle" if _clip == "crouch" else _clip)
	_update_crouch_fade(delta, movement_mode == "crouch")

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
	var ladder: Node3D = _nearby_ladder()
	var climbing := ladder != null and (absf(input_vector.y) > .1 \
		or Input.is_action_pressed("jump"))
	if climbing:
		floor_snap_length = 0.0
		var climb_direction := -input_vector.y
		if Input.is_action_pressed("jump"):
			climb_direction = 1.0
		velocity.y = climb_direction * GameConfig.LADDER_CLIMB_SPEED
		var guide: Vector3 = ladder.call("guide_world_position", global_position.y)
		velocity.x = (guide.x - global_position.x) * 5.0
		velocity.z = (guide.z - global_position.z) * 5.0
	else:
		floor_snap_length = .28
		_update_vertical_motion(delta, movement_mode != "crouch")
	_move_and_resolve_landing()
	if is_moving and is_on_floor():
		Sound.footstep(movement_mode)


	_update_flashlight_flicker(delta)
	if Input.is_action_just_pressed("flashlight") and owns_inventory_item("flashlight") \
			and not flashlight_seized():
		select_inventory_slot(0)
		_set_flashlight(not flashlight_enabled)
	if Input.is_action_just_pressed("taser") and owns_inventory_item("taser"):
		_fire_taser()
	if Input.is_action_just_pressed("tool_use"):
		_use_selected_item()

	_update_resecure(delta)
	if Input.is_action_just_pressed("interact"):
		_try_interact()


func _nearby_ladder() -> Node3D:
	for candidate in get_tree().get_nodes_in_group("climbable_ladder"):
		var ladder := candidate as Node3D
		if ladder and ladder.has_method("can_climb") \
				and bool(ladder.call("can_climb", global_position)):
			return ladder
	return null


## First person is the only view. The body is hidden because you are inside it,
## and the mouse is captured because the camera is aimed with it.
func _update_crouch_fade(delta: float, crouching: bool) -> void:
	var target := 0.55 if crouching else 0.0
	_body_fade = move_toward(_body_fade, target, delta * 2.8)
	ModelSlot.set_character_fade(_body_model, _body_fade)


## What this body is playing, for RemotePlayers to send on.
func current_clip() -> String:
	return _clip


func active_camera() -> Camera3D:
	return xr_camera if xr_active else first_person_camera


## Grounded, single-press hop. Gravity still runs while input is frozen so a
## capture, stun, or pause cannot leave a player suspended in midair. Crouch
## blocks takeoff, but releasing crouch before landing does not alter the arc.
func _update_vertical_motion(delta: float, allow_jump: bool) -> void:
	var wants_to_jump := _jump_requested or Input.is_action_just_pressed("jump")
	# Consume every request immediately, even in midair/frozen/crouching, so a
	# rejected press cannot be banked into an automatic hop on landing.
	_jump_requested = false
	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = 0.0
		if allow_jump and wants_to_jump:
			velocity.y = GameConfig.PLAYER_JUMP_VELOCITY
	else:
		velocity.y -= GameConfig.PLAYER_GRAVITY * delta


## Applies the route's fall consequence after CharacterBody resolves impact.
## Normal jumping peaks at roughly 3 m/s and stair walking remains snapped to
## the ramp, both below the 4 m/s safety threshold. A drop from the 1 m stair
## landing crosses it and produces a short, severity-scaled stun.
func _move_and_resolve_landing() -> void:
	var was_grounded := is_on_floor()
	_fall_speed = maxf(_fall_speed, maxf(0.0, -velocity.y))
	move_and_slide()
	if is_on_floor():
		if not was_grounded and _fall_speed >= GameConfig.PLAYER_FALL_STUN_SPEED:
			var severity := (_fall_speed - GameConfig.PLAYER_FALL_STUN_SPEED) / 4.0
			var duration := lerpf(GameConfig.PLAYER_FALL_STUN_MIN_SECONDS,
				GameConfig.PLAYER_FALL_STUN_MAX_SECONDS, clampf(severity, 0.0, 1.0))
			stun_timer = maxf(stun_timer, duration)
			interaction_message.emit("HARD LANDING // STUNNED %.1fs" % duration)
		_fall_speed = 0.0


func request_jump() -> void:
	_jump_requested = true


func _enter_first_person() -> void:
	first_person_camera.current = true
	body_visual.visible = false
	if first_person_items:
		first_person_items.visible = true
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
	# Desktop viewmodels are camera-framed props, not world-scale VR hands.
	# Hide them in OpenXR until controller-held models get their own pass.
	if first_person_items:
		first_person_items.visible = false
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
		"by_button":
			request_jump()
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
		"trigger_click":
			Input.action_press("taser")
		"primary_click":
			Input.action_press("crouch")
		"by_button":
			Input.action_press("toggle_map")
		"menu_button":
			_emit_xr_action_event("pause", true)


func _on_xr_left_released(action: StringName) -> void:
	match String(action):
		"trigger_click":
			Input.action_release("taser")
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
	flashlight_enabled = enabled and owns_inventory_item("flashlight") \
		and lamp_charge > 0.0
	flashlight.visible = flashlight_enabled
	_animate_flashlight_toggle()
	_update_first_person_item_lights()
	flashlight_changed.emit(flashlight_enabled)


## Camera-local authored equipment keeps the held item readable without
## leaking it into the player's world collider. The same GLBs are used for
## floor pickups and HUD renders, so all three presentations stay consistent.
func _build_first_person_items() -> void:
	first_person_items = Node3D.new()
	first_person_items.name = "FirstPersonItems"
	first_person_camera.add_child(first_person_items)

	flashlight_view = Node3D.new()
	flashlight_view.name = "FlashlightView"
	flashlight_view.position = FLASHLIGHT_ITEM_POSITION
	first_person_items.add_child(flashlight_view)
	_add_authored_item_model(flashlight_view, "flashlight", .50)

	taser_view = Node3D.new()
	taser_view.name = "TaserView"
	taser_view.position = TASER_ITEM_POSITION
	first_person_items.add_child(taser_view)
	_add_authored_item_model(taser_view, "taser", .50)
	taser_view.visible = false

	_build_utility_view("lockpick")
	_build_utility_view("crowbar")
	_build_utility_view("rescue_axe")
	_refresh_inventory_view()


func _build_utility_view(item_id: String) -> void:
	var view := Node3D.new()
	view.name = "%sView" % item_id.to_pascal_case()
	view.position = UTILITY_ITEM_POSITION
	first_person_items.add_child(view)
	_add_authored_item_model(view, item_id, .52 if item_id == "lockpick" else .43)
	view.visible = false
	tool_views[item_id] = view


func _add_authored_item_model(view: Node3D, item_id: String, scale_amount: float) -> void:
	var model_path := String(ITEM_MODEL_PATHS.get(item_id, ""))
	var model := ModelSlot.instantiate(model_path)
	if model:
		model.name = "AuthoredToolModel"
		model.scale = Vector3.ONE * scale_amount
		model.rotation.x = deg_to_rad(-72.0)
		model.position = Vector3(0, -.02, -.18)
		view.add_child(model)
	else:
		push_error("FIRST-PERSON TOOL MODEL MISSING // %s" % model_path)


func _add_item_part(parent: Node3D, part_name: String, size: Vector3,
		at: Vector3, color: Color, override_material: Material = null) -> void:
	var box := BoxMesh.new()
	box.size = size
	var mesh := MeshInstance3D.new()
	mesh.name = part_name
	mesh.mesh = box
	mesh.position = at
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.material_override = override_material if override_material else _item_material(color)
	parent.add_child(mesh)


func _item_material(color: Color, emission: Color = Color(0, 0, 0, 1)) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .58
	if emission.r > 0.0 or emission.g > 0.0 or emission.b > 0.0:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 1.8
	return material


func _update_first_person_item_lights() -> void:
	if _flashlight_lens_material == null:
		return
	var lit := flashlight != null and flashlight.visible
	_flashlight_lens_material.emission_enabled = lit
	_flashlight_lens_material.albedo_color = Color("eee3ad") if lit else Color("3c3b35")


func _animate_flashlight_toggle() -> void:
	if flashlight_view == null:
		return
	if _flashlight_item_tween and _flashlight_item_tween.is_valid():
		_flashlight_item_tween.kill()
	flashlight_view.position = FLASHLIGHT_ITEM_POSITION
	_flashlight_item_tween = create_tween().set_trans(Tween.TRANS_QUAD)
	_flashlight_item_tween.tween_property(flashlight_view, "position",
		FLASHLIGHT_ITEM_POSITION + Vector3(0, -.055, .035), .09)
	_flashlight_item_tween.tween_property(flashlight_view, "position",
		FLASHLIGHT_ITEM_POSITION, .14).set_ease(Tween.EASE_OUT)


func _fire_taser() -> void:
	if not owns_inventory_item("taser") or taser_cooldown > 0.0 \
			or input_frozen or stun_timer > 0.0:
		return
	select_inventory_slot(1)
	taser_cooldown = GameConfig.TASER_COOLDOWN_SECONDS
	Sound.taser()
	_animate_taser_fire()
	taser_requested.emit()


func _animate_taser_fire() -> void:
	if taser_view == null:
		return
	if _taser_item_tween and _taser_item_tween.is_valid():
		_taser_item_tween.kill()
	taser_view.visible = true
	taser_view.position = TASER_ITEM_POSITION
	_taser_item_tween = create_tween().set_trans(Tween.TRANS_BACK)
	_taser_item_tween.tween_property(taser_view, "position",
		TASER_ITEM_POSITION + Vector3(0, .015, .09), .07)
	_taser_item_tween.tween_property(taser_view, "position", TASER_ITEM_POSITION, .18)
	_taser_item_tween.tween_interval(.28)
	_taser_item_tween.tween_callback(_refresh_inventory_view)


func select_inventory_slot(slot: int) -> void:
	var candidate := wrapi(slot, 0, INVENTORY_ITEMS.size())
	var found := -1
	for offset in INVENTORY_ITEMS.size():
		var checked := wrapi(candidate + offset, 0, INVENTORY_ITEMS.size())
		if bool(owned_inventory_items.get(INVENTORY_ITEMS[checked], false)):
			found = checked
			break
	selected_inventory_slot = found
	_refresh_inventory_view()


func selected_inventory_item() -> String:
	if selected_inventory_slot < 0 or selected_inventory_slot >= INVENTORY_ITEMS.size():
		return ""
	if not owns_inventory_item(INVENTORY_ITEMS[selected_inventory_slot]):
		return ""
	return INVENTORY_ITEMS[selected_inventory_slot]


func grant_inventory_item(item_id: String) -> bool:
	if not INVENTORY_ITEMS.has(item_id):
		return false
	owned_inventory_items[item_id] = true
	if item_id == "flashlight":
		restore_lamp(GameConfig.MAX_LAMP_CHARGE)
	elif item_id == "taser":
		taser_cooldown = 0.0
	elif INVENTORY_MAX_DURABILITY.has(item_id):
		inventory_durability[item_id] = int(INVENTORY_MAX_DURABILITY[item_id])
	select_inventory_slot(INVENTORY_ITEMS.find(item_id))
	return true


func owns_inventory_item(item_id: String) -> bool:
	return bool(owned_inventory_items.get(item_id, false))


func item_durability(item_id: String) -> int:
	return int(inventory_durability.get(item_id, 0))


func consume_item_durability(item_id: String, amount: int = 1) -> bool:
	if not owns_inventory_item(item_id) or not INVENTORY_MAX_DURABILITY.has(item_id):
		return false
	var remaining := maxi(0, item_durability(item_id) - maxi(1, amount))
	inventory_durability[item_id] = remaining
	if remaining <= 0:
		owned_inventory_items[item_id] = false
		interaction_message.emit("%s BROKE // FIND OR ADMIN-GIVE A REPLACEMENT" %
			String(INVENTORY_LABELS[item_id]))
		select_inventory_slot(selected_inventory_slot + 1)
	return true


func inventory_durability_snapshot() -> Dictionary:
	return inventory_durability.duplicate(true)


func inventory_owned_snapshot() -> Dictionary:
	return owned_inventory_items.duplicate(true)


func _use_selected_item() -> void:
	var item_id := selected_inventory_item()
	if item_id.is_empty():
		interaction_message.emit("EMPTY HANDS // FIND EQUIPMENT IN THE FACILITY")
		return
	match item_id:
		"flashlight":
			if not flashlight_seized():
				_set_flashlight(not flashlight_enabled)
		"taser":
			_fire_taser()
		_:
			_use_selected_tool()


func _use_selected_tool() -> void:
	if input_frozen or stun_timer > 0.0:
		return
	var item_id := selected_inventory_item()
	if not BREACH_TOOLS.has(item_id) and not LOCK_TOOLS.has(item_id):
		interaction_message.emit("SELECT A HAND TOOL // SLOTS 3-5")
		return
	# A committed swing/use spends durability before any hit result. This makes
	# ally hits cost the tool without ever creating friendly-fire damage.
	if not consume_item_durability(item_id):
		interaction_message.emit("%s IS BROKEN" % String(INVENTORY_LABELS[item_id]))
		return
	_animate_tool_use(item_id)
	tool_used.emit(item_id)
	var target := _nearest_interactable()
	if target != null and (target.kind == RouteInteractable3D.Kind.BOARDED_PATH \
			or (target.kind == RouteInteractable3D.Kind.RELAY and target.locked_cache)):
		interaction_message.emit(target.activate_with_tool(self, item_id, true))
	else:
		interaction_message.emit("TOOL USED // TEAMMATES CANNOT TAKE DAMAGE")


func _animate_tool_use(item_id: String) -> void:
	var view := tool_views.get(item_id) as Node3D
	if view == null:
		return
	if _tool_item_tween and _tool_item_tween.is_valid():
		_tool_item_tween.kill()
	view.position = UTILITY_ITEM_POSITION
	view.rotation = Vector3.ZERO
	_tool_item_tween = create_tween().set_trans(Tween.TRANS_QUAD)
	_tool_item_tween.tween_property(view, "rotation:z", -.72, .09)
	_tool_item_tween.parallel().tween_property(view, "position",
		UTILITY_ITEM_POSITION + Vector3(-.10, .04, -.06), .09)
	_tool_item_tween.tween_property(view, "rotation:z", 0.0, .16)
	_tool_item_tween.parallel().tween_property(view, "position", UTILITY_ITEM_POSITION, .16)


func _refresh_inventory_view() -> void:
	var selected := selected_inventory_item()
	if flashlight_view:
		flashlight_view.visible = selected == "flashlight"
	if taser_view:
		taser_view.visible = selected == "taser"
	for item_id in tool_views:
		var view := tool_views[item_id] as Node3D
		if view:
			view.visible = selected == item_id


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
			return prompt
	if shop_prompt_provider.is_valid():
		var shop_prompt: String = String(shop_prompt_provider.call())
		if not shop_prompt.is_empty():
			return shop_prompt
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


## Best interactable under the camera crosshair: in reach, inside a modest aim
## cone and not hidden behind facility collision. This used to select whichever
## prop was nearest on the XZ plane, even when the camera was pitched toward a
## different one. Scoring alignment before distance also makes two props in
## reach deterministic without letting the nearer one steal focus from the
## thing the player is actually looking at.
func _nearest_interactable() -> RouteInteractable3D:
	var chosen: RouteInteractable3D = null
	var chosen_alignment := -1.0
	var chosen_distance := INF
	var camera := active_camera()
	if camera == null:
		return null
	var origin := camera.global_position
	var look := -camera.global_basis.z.normalized()
	var maximum_distance := GameConfig.INTERACTION_RANGE / GameConfig.TILE_SIZE
	for candidate in get_tree().get_nodes_in_group("interactable"):
		if not candidate is RouteInteractable3D:
			continue
		var horizontal_offset := Vector2(candidate.global_position.x - global_position.x,
			candidate.global_position.z - global_position.z)
		var horizontal_distance := horizontal_offset.length()
		if horizontal_distance > maximum_distance or candidate.get_prompt().is_empty():
			continue
		var focus: Vector3 = candidate.interaction_focus()
		var to_focus := focus - origin
		var ray_distance := to_focus.length()
		if ray_distance <= 0.001:
			continue
		var alignment := look.dot(to_focus / ray_distance)
		if alignment < cos(GameConfig.INTERACTION_AIM_HALF_ANGLE):
			continue
		if not _interaction_has_line_of_sight(focus, candidate):
			continue
		if alignment > chosen_alignment + 0.0001 \
				or (is_equal_approx(alignment, chosen_alignment) and horizontal_distance < chosen_distance):
			chosen = candidate
			chosen_alignment = alignment
			chosen_distance = horizontal_distance
	return chosen


func _interaction_has_line_of_sight(focus: Vector3, candidate: RouteInteractable3D) -> bool:
	var camera := active_camera()
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, focus)
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	var collider = hit.get("collider")
	return collider == candidate or (collider is Node and candidate.is_ancestor_of(collider))
