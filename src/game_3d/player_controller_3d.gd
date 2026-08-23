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
signal item_drop_requested(item_id: String, durability: int, slot: int)
signal interaction_message(message: String)

## Fallback only. At runtime the standing camera is aligned to the player
## model's authored eye attachments, keeping the first-person POV and visible
## co-op mannequin at the same height when the model is revised.
const CAMERA_HEIGHT := 1.6
const CAMERA_HEIGHT_MIN := 1.35
const CAMERA_HEIGHT_MAX := 1.78
const CONTROLLER_LOOK_RADIANS_PER_SECOND := 2.8
const STANDING_COLLISION_HEIGHT := 1.7
const CROUCH_COLLISION_HEIGHT := 1.08
const STANDING_COLLISION_CENTER_Y := .85
const CROUCH_COLLISION_CENTER_Y := .54
const CROUCH_EYE_RATIO := .69
const CROUCH_EYE_TOP_CLEARANCE := .08
const CAMERA_BOB_WALK_AMPLITUDE := .024
const CAMERA_BOB_SPRINT_AMPLITUDE := .038
const CAMERA_BOB_CROUCH_AMPLITUDE := .012
const FLASHLIGHT_MAX_RANGE := 16.0
const FLASHLIGHT_MIN_RANGE := .8
## Camera-local position of the flashlight's physical lens. The old light
## began at the camera behind the held model; once shadows were enabled, the
## flashlight body shadowed its own beam before it could reach the room.
# The hand model is deliberately camera-local and visually sits much farther
# forward than its physical world position should. Keep the real light just in
# front of the camera/capsule so it cannot cross into a nearby wall.
const FLASHLIGHT_BEAM_LOCAL_POSITION := Vector3(.08, -.05, -.12)
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
@onready var player_collision: CollisionShape3D = $CollisionShape3D

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
var _flashlight_probe: RayCast3D
## Exact center-beam hit distance for interaction/effects which need it. It
## must not shorten the whole SpotLight cone: a single ray grazing a nearby
## wall used to black out every unblocked part of the beam too.
var flashlight_hit_distance := FLASHLIGHT_MAX_RANGE
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
	"battery": "res://art/props-3d/interactables/battery.glb",
}
const HOTBAR_SIZE := 5
const TOOL_ITEMS := ["flashlight", "taser", "lockpick", "crowbar", "rescue_axe"]
const BACKPACK_ITEMS := ["backpack_small", "backpack_medium", "backpack_large"]
## Physical items occupy inventory slots. Backpacks are permanent capacity
## upgrades collected from the world, so they deliberately do not appear in
## this catalog or become draggable/droppable hotbar entries.
const INVENTORY_ITEMS := TOOL_ITEMS + ["battery"]
const BACKPACK_CAPACITY := {
	"backpack_small": 5, "backpack_medium": 10, "backpack_large": 15,
}
const BACKPACK_RANK := {
	"": 0, "backpack_small": 1, "backpack_medium": 2, "backpack_large": 3,
}
const COLLECTIBLE_ITEMS := INVENTORY_ITEMS + BACKPACK_ITEMS
const INVENTORY_LABELS := {
	"flashlight": "FLASHLIGHT", "taser": "TASER", "lockpick": "LOCKPICK SET",
	"crowbar": "CROWBAR", "rescue_axe": "RESCUE AXE",
	"battery": "FLASHLIGHT BATTERY",
	"backpack_small": "SMALL BACKPACK", "backpack_medium": "MEDIUM BACKPACK",
	"backpack_large": "LARGE BACKPACK",
}
const INVENTORY_MAX_DURABILITY := {
	"flashlight": 100, "lockpick": 12, "crowbar": 40, "rescue_axe": 24,
}
const BREACH_TOOLS := ["crowbar", "rescue_axe"]
const LOCK_TOOLS := ["lockpick", "crowbar"]
const FRIENDLY_FIRE_ENABLED := false
var selected_inventory_slot := 0
## Five physical inventory slots. Empty strings are real empty spaces rather
## than hidden catalog entries, so dragging into a blank slot behaves like an
## inventory instead of reordering future pickups.
var inventory_order := ["flashlight", "", "", "", ""]
## Durability belongs to the physical slot, not the item id. This permits two
## flashlights/tools with independent remaining life instead of the old global
## per-type value making a duplicate pickup impossible to represent.
var inventory_slot_durability := [100, 0, 0, 0, 0]
var _active_flashlight_slot := 0
var equipped_backpack := ""
## One storage unit is five slots. A small/medium/large pickup contributes
## one/two/three units respectively, allowing repeated small packs to combine
## into larger storage without ever consuming an inventory slot themselves.
var backpack_storage_units := 0
var owned_inventory_items := {
	"flashlight": true, "taser": false, "lockpick": false,
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
var admin_noclip := false
## A captured co-op guest remains in the room as a free-flying spectator rather
## than respawning or being forced back to the menu. The host still treats this
## state as game-over for targeting and replication purposes.
var spectator_mode := false

## Exposure / noise / temperature, shared with hunter gimmicks that read them
## (see src/game/player_meters.gd).
var meters := PlayerMeters.new()
## Facing on the facility's XZ ground plane, for beam-aim checks (Nyxie's
## dispel). Derived from body yaw, which both control schemes already set.
var facing := Vector2(0, 1)

var _yaw := 0.0
var _pitch := 0.0
var _standing_camera_height := CAMERA_HEIGHT
var _crouched_physical := false
var _bob_phase := 0.0
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
var _hiding_exit_position := Vector3.ZERO
var _hiding_collision_layer := 1
var _hiding_collision_mask := 1
var _hiding_fixture: Node3D

## Personal furniture pose. It is replicated through current_clip/transform,
## but does not mutate the shared prop, so two couch seats in co-op never need
## an authority round trip.
var resting_furniture: RouteInteractable3D
var resting_pose := ""
var _furniture_return_position := Vector3.ZERO

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


func use_furniture(furniture: RouteInteractable3D, pose: String) -> String:
	if furniture == null or pose not in ["sit", "lay", "ride"]:
		return "That furniture cannot be used."
	if resting_furniture == furniture:
		return leave_furniture()
	if resting_furniture != null and not is_instance_valid(resting_furniture):
		# A streamed chunk can be evicted by an admin teleport. Recover at the
		# stored approach point instead of leaving a freed reference that freezes
		# this controller forever.
		resting_furniture = null
		resting_pose = ""
		global_position = _furniture_return_position
		first_person_pivot.position.y = _standing_camera_height
	if resting_furniture != null:
		leave_furniture()
	_furniture_return_position = global_position
	resting_furniture = furniture
	resting_pose = pose
	global_position = furniture.global_position
	rotation.y = furniture.global_rotation.y
	_yaw = rotation.y
	first_person_pivot.position.y = .72 if pose == "lay" else 1.02
	velocity = Vector3.ZERO
	_clip = "sit" if pose == "ride" else pose
	ModelSlot.play_if_available(_animation_player, _clip)
	if pose == "ride":
		Sound.menu_blip()
		return ""
	return "LYING DOWN // INTERACT TO GET UP" if pose == "lay" \
		else "SEATED // INTERACT TO STAND"


func leave_furniture() -> String:
	if resting_furniture == null:
		return ""
	global_position = _furniture_return_position
	resting_furniture = null
	resting_pose = ""
	first_person_pivot.position.y = _standing_camera_height
	_clip = "idle"
	ModelSlot.play_if_available(_animation_player, _clip)
	return "STOOD UP"


func enter_hiding(cell: Vector2i, inside_position: Vector3 = Vector3.ZERO,
		exit_position: Vector3 = Vector3.ZERO,
		fixture: Node3D = null) -> String:
	_hiding_exit_position = exit_position if exit_position != Vector3.ZERO \
		else global_position
	_hiding_fixture = fixture
	if is_instance_valid(_hiding_fixture):
		if _hiding_fixture.has_method("set_local_hiding_view"):
			_hiding_fixture.call("set_local_hiding_view", true)
		if _hiding_fixture.has_method("hiding_outward_yaw"):
			_yaw = float(_hiding_fixture.call("hiding_outward_yaw"))
			rotation.y = _yaw
			_pitch = 0.0
			first_person_pivot.rotation.x = 0.0
	_hiding_collision_layer = collision_layer
	_hiding_collision_mask = collision_mask
	collision_layer = 0
	collision_mask = 0
	if inside_position != Vector3.ZERO:
		global_position = inside_position
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
	if is_instance_valid(_hiding_fixture) \
			and _hiding_fixture.has_method("set_local_hiding_view"):
		_hiding_fixture.call("set_local_hiding_view", false)
	_hiding_fixture = null
	collision_layer = _hiding_collision_layer
	collision_mask = _hiding_collision_mask
	if at != Vector2.ZERO:
		global_position = Vector3(at.x, global_position.y, at.y)
	elif _hiding_exit_position != Vector3.ZERO:
		global_position = _hiding_exit_position
	_hiding_exit_position = Vector3.ZERO
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
	first_person_camera.fov = Settings.field_of_view
	Settings.visual_changed.connect(_apply_visual_settings)
	var body_scene := ADMIN_BODY_MODEL_SCENE if Backend.uses_kyttu_player_skin() \
		else BODY_MODEL_SCENE
	var model := ModelSlot.instantiate(body_scene)
	if model:
		_body_model = model
		body_visual.add_child(model)
		if not Backend.uses_kyttu_player_skin():
			ModelSlot.apply_character_hue(model, Settings.player_hue_degrees)
		_animation_player = ModelSlot.find_animation_player(model)
		_align_camera_to_model_eyes(model)
	flashlight.position = FLASHLIGHT_BEAM_LOCAL_POSITION
	_build_flashlight_probe()
	_build_first_person_items()
	# The starter flashlight is owned and visible in slot one, but begins off so
	# entering a route never spends charge before the player chooses to use it.
	_set_flashlight(false)
	_connect_xr_buttons()
	if not _try_enter_xr():
		_enter_first_person()


func _apply_visual_settings() -> void:
	first_person_camera.fov = Settings.field_of_view


func _align_camera_to_model_eyes(model: Node3D) -> void:
	var eye_heights: Array[float] = []
	for eye_name in ["L-Eye-Attachment", "R-Eye-Attachment"]:
		var eye := model.find_child(eye_name, true, false) as Node3D
		if eye != null:
			eye_heights.append(body_visual.to_local(eye.global_position).y)
	if eye_heights.is_empty():
		return
	var sum := 0.0
	for height in eye_heights:
		sum += height
	_standing_camera_height = clampf(sum / eye_heights.size(),
		CAMERA_HEIGHT_MIN, CAMERA_HEIGHT_MAX)
	first_person_pivot.position.y = _standing_camera_height


func _can_stand_up() -> bool:
	if admin_noclip or player_collision == null or get_world_3d() == null:
		return true
	# Query only the headroom gained by standing. Testing a complete standing
	# capsule also touches the floor and can falsely report the floor itself as
	# an obstruction.
	var standing_shape := BoxShape3D.new()
	var clearance_height := STANDING_COLLISION_HEIGHT - CROUCH_COLLISION_HEIGHT
	standing_shape.size = Vector3(.48, clearance_height - .02, .48)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = standing_shape
	query.transform = Transform3D(global_basis,
		global_position + Vector3.UP * (CROUCH_COLLISION_HEIGHT \
			+ clearance_height * .5))
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _update_crouch_hitbox(wants_crouch: bool) -> bool:
	if wants_crouch:
		_crouched_physical = true
	elif _crouched_physical and _can_stand_up():
		_crouched_physical = false
	var capsule := player_collision.shape as CapsuleShape3D
	if capsule != null:
		capsule.height = CROUCH_COLLISION_HEIGHT if _crouched_physical \
			else STANDING_COLLISION_HEIGHT
	player_collision.position.y = CROUCH_COLLISION_CENTER_Y if _crouched_physical \
		else STANDING_COLLISION_CENTER_Y
	return _crouched_physical


func _update_camera_pose(delta: float, moving_on_floor: bool,
		sprinting: bool, crouching: bool) -> void:
	# Never let the crouched camera sit above the shortened capsule. Otherwise
	# the hitbox can fit beneath a beam while the player's view clips through it.
	var crouch_eye_height := minf(_standing_camera_height * CROUCH_EYE_RATIO,
		CROUCH_COLLISION_HEIGHT - CROUCH_EYE_TOP_CLEARANCE)
	var base_height := crouch_eye_height if crouching else _standing_camera_height
	var amplitude := CAMERA_BOB_CROUCH_AMPLITUDE if crouching else (
		CAMERA_BOB_SPRINT_AMPLITUDE if sprinting else CAMERA_BOB_WALK_AMPLITUDE)
	if moving_on_floor:
		_bob_phase = fmod(_bob_phase + delta * (12.0 if sprinting else (
			6.5 if crouching else 8.5)), TAU)
	else:
		_bob_phase = move_toward(_bob_phase, 0.0, delta * 10.0)
		amplitude = 0.0
	var target_y := base_height + sin(_bob_phase * 2.0) * amplitude
	var target_x := cos(_bob_phase) * amplitude * .42 if moving_on_floor else 0.0
	first_person_pivot.position.y = move_toward(first_person_pivot.position.y,
		target_y, delta * 3.2)
	first_person_pivot.position.x = move_toward(first_person_pivot.position.x,
		target_x, delta * .8)


func _update_controller_look(delta: float) -> void:
	if xr_active or look_frozen or input_frozen:
		return
	# Digital IJKL / arrows share these actions with the right stick. WASD stays
	# on move_* so keyboard look is additive and a run can turn without capture.
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if stick.length_squared() <= 0.0001:
		return
	# The mouse sensitivity slider also scales stick look, avoiding two camera
	# speeds that feel unrelated without adding another last-minute setting.
	var sensitivity_scale := Settings.mouse_sensitivity / Settings.DEFAULT_MOUSE_SENSITIVITY
	_yaw -= stick.x * CONTROLLER_LOOK_RADIANS_PER_SECOND * sensitivity_scale * delta
	_pitch = clampf(_pitch - stick.y * CONTROLLER_LOOK_RADIANS_PER_SECOND \
		* sensitivity_scale * delta, -1.4, 1.4)
	_apply_look_rotation()


## True while look keys or the right stick are held. Gray Void AFK uses this so
## turning in place counts as activity the same way mouse look does.
func is_look_input_active() -> bool:
	if xr_active or look_frozen or input_frozen:
		return false
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	return stick.length_squared() > 0.0001


func _apply_look_rotation() -> void:
	rotation.y = _yaw
	first_person_pivot.rotation.x = _pitch
	facing = Vector2(-sin(rotation.y), -cos(rotation.y))


func _unhandled_input(event: InputEvent) -> void:
	# Uncaptured relative motion fights the OS cursor on remote/low-FPS
	# desktops. Keyboard look covers that case; mouse look stays capture-only.
	if event is InputEventMouseMotion and not xr_active and not look_frozen \
			and MouseLock.is_captured():
		_yaw -= event.relative.x * Settings.mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * Settings.mouse_sensitivity, -1.4, 1.4)
		_apply_look_rotation()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).physical_keycode
		if key >= KEY_1 and key <= KEY_4 and shop_resolver.is_valid():
			var message := String(shop_resolver.call(str(key - KEY_1 + 1)))
			if not message.is_empty():
				interaction_message.emit(message)
				return
		if key >= KEY_1 and key <= KEY_5:
			var target_slot := key - KEY_1
			select_inventory_slot(target_slot)
	elif event is InputEventMouseButton and event.pressed:
		var button := (event as InputEventMouseButton).button_index
		if button == MOUSE_BUTTON_WHEEL_UP:
			select_inventory_slot(selected_inventory_slot - 1)
		elif button == MOUSE_BUTTON_WHEEL_DOWN:
			select_inventory_slot(selected_inventory_slot + 1)


func set_admin_noclip(enabled: bool) -> void:
	if admin_noclip == enabled:
		return
	if enabled and hidden:
		leave_hiding(Vector2.ZERO, true)
	admin_noclip = enabled
	velocity = Vector3.ZERO
	collision_layer = 0 if enabled else 1
	collision_mask = 0 if enabled else 1


func enter_spectator() -> void:
	# Capture/death spectator for guests: ensure no admin cheats remain active.
	admin_no_target = false
	admin_god_mode = false
	set_admin_noclip(false)
	spectator_mode = true
	input_frozen = false
	look_frozen = false
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	if player_collision != null:
		player_collision.disabled = true
	if body_visual != null:
		body_visual.visible = false


func leave_spectator() -> void:
	spectator_mode = false
	velocity = Vector3.ZERO
	collision_layer = 1
	collision_mask = 1
	if player_collision != null:
		player_collision.disabled = false
	if body_visual != null:
		body_visual.visible = true


func _update_spectator(delta: float) -> void:
	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var basis := active_camera().global_basis
	var direction := basis.x * input_vector.x + (-basis.z) * -input_vector.y
	if Input.is_action_pressed("jump"):
		direction += Vector3.UP
	if Input.is_action_pressed("crouch"):
		direction += Vector3.DOWN
	var fast := Input.is_action_pressed("sprint")
	var speed := 12.0 if fast else 6.0
	if direction.length_squared() > 0.0:
		global_position += direction.normalized() * speed * delta
	velocity = Vector3.ZERO
	noise = 0.0
	_clip = "idle"
	ModelSlot.play_if_available(_animation_player, _clip)


func _update_admin_noclip(delta: float) -> void:
	# Free-flight follows the view, including pitch, while vertical keys remain
	# explicit so an admin can inspect stacked floors without aiming straight up.
	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var basis := active_camera().global_basis
	var direction := basis.x * input_vector.x + (-basis.z) * -input_vector.y
	if Input.is_action_pressed("jump"):
		direction += Vector3.UP
	if Input.is_action_pressed("crouch"):
		direction += Vector3.DOWN
	var fast := Input.is_action_pressed("sprint")
	var speed := 9.0 if fast else 4.5
	if direction.length_squared() > 0.0:
		global_position += direction.normalized() * speed * delta
		_clip = "sprint" if fast else "walk"
	else:
		_clip = "idle"
	velocity = Vector3.ZERO
	noise = 0.0
	ModelSlot.play_if_available(_animation_player, _clip)


func _physics_process(delta: float) -> void:
	_update_controller_look(delta)
	taser_cooldown = maxf(0.0, taser_cooldown - delta)
	_update_first_person_item_lights()
	_update_flashlight_occlusion()
	if spectator_mode:
		_update_spectator(delta)
		return
	if hiding_lock_timer > 0.0:
		hiding_lock_timer = maxf(0.0, hiding_lock_timer - delta)
	if stun_timer > 0.0:
		stun_timer = maxf(0.0, stun_timer - delta)
	if pesticide_timer > 0.0:
		pesticide_timer = maxf(0.0, pesticide_timer - delta)
	if in_vent:
		vent_time_in += delta
	# Noclip is gravity-free even while a menu freezes input. Previously the
	# frozen branch ran first, applied gravity with collision disabled, and
	# dropped an admin through every floor while the admin panel was open.
	if admin_noclip:
		if input_frozen or stun_timer > 0.0:
			velocity = Vector3.ZERO
			noise = 0.0
			_clip = "idle"
			ModelSlot.play_if_available(_animation_player, _clip)
		else:
			_update_admin_noclip(delta)
		return
	if resting_furniture != null and not is_instance_valid(resting_furniture):
		# An admin teleport can evict the furniture's streamed chunk while the
		# player is resting. Recover rather than freezing on a freed reference.
		resting_furniture = null
		resting_pose = ""
		global_position = _furniture_return_position
		first_person_pivot.position.y = _standing_camera_height
	if resting_furniture != null:
		velocity = Vector3.ZERO
		noise = 0.0
		_clip = resting_pose
		ModelSlot.play_if_available(_animation_player, _clip)
		if Input.is_action_just_pressed("interact"):
			interaction_message.emit(leave_furniture())
		return
	if input_frozen or stun_timer > 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
		if hidden:
			velocity.y = 0.0
		else:
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
			# Leaving a locker is state-driven, not another ray-cast interaction.
			# E therefore works without aiming back at a now-local-hidden fixture.
			interaction_message.emit(leave_hiding())
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
	var is_crouching := _update_crouch_hitbox(Input.is_action_pressed("crouch"))
	var wants_to_sprint := Input.is_action_pressed("sprint") and is_moving \
		and (admin_god_mode or not exhausted)
	var is_sprinting := false

	if is_crouching:
		movement_speed = GameConfig.PLAYER_CROUCH_SPEED * float(difficulty["crouch_speed"])
		movement_mode = "crouch"
	elif wants_to_sprint and (admin_god_mode or stamina > 0.0):
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
		flashlight.global_transform = xr_camera.global_transform.translated_local(
			Vector3(0.0, -.08, -.18))
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
	_update_camera_pose(delta, is_moving and is_on_floor(), is_sprinting,
		movement_mode == "crouch")
	if is_moving and is_on_floor():
		Sound.footstep(movement_mode)


	_update_flashlight_flicker(delta)
	if Input.is_action_just_pressed("flashlight") and owns_inventory_item("flashlight") \
			and not flashlight_seized():
		select_inventory_slot(inventory_order.find("flashlight"))
		_set_flashlight(not flashlight_enabled)
	if Input.is_action_just_pressed("taser") and owns_inventory_item("taser"):
		_fire_taser()
	if Input.is_action_just_pressed("tool_use"):
		_use_selected_item()
	if Input.is_action_just_pressed("drop_item"):
		request_drop_selected_item()
	if Input.is_action_just_pressed("hotbar_previous"):
		select_inventory_slot(selected_inventory_slot - 1)
	if Input.is_action_just_pressed("hotbar_next"):
		select_inventory_slot(selected_inventory_slot + 1)

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
## Normal jumps, room-height drops and imperfect stair transitions stay below
## the safety threshold. A near-full-level fall produces a short,
## severity-scaled stun rather than locking the runner after every small drop.
func _move_and_resolve_landing() -> void:
	var was_grounded := is_on_floor()
	_fall_speed = maxf(_fall_speed, maxf(0.0, -velocity.y))
	move_and_slide()
	if is_on_floor():
		if not was_grounded and _fall_speed >= GameConfig.PLAYER_FALL_STUN_SPEED:
			var severity := (_fall_speed - GameConfig.PLAYER_FALL_STUN_SPEED) \
				/ (GameConfig.PLAYER_FALL_STUN_FULL_SPEED \
					- GameConfig.PLAYER_FALL_STUN_SPEED)
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
	if admin_god_mode:
		stamina = GameConfig.MAX_STAMINA
		stamina_recovery_delay = 0.0
		exhausted = false
		return
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
	_save_active_flashlight_charge()
	if lamp_charge <= 0.0:
		_break_inventory_item("flashlight", _active_flashlight_slot)


func _update_flashlight_flicker(delta: float) -> void:
	if _flicker_remaining <= 0.0:
		return
	_flicker_remaining -= delta
	_flicker_next_toggle -= delta
	if _flicker_remaining <= 0.0:
		# Restore the real state rather than leaving the beam wherever the
		# last random toggle left it.
		flashlight.visible = _flashlight_beam_should_be_visible()
		return
	if not _flashlight_beam_should_be_visible():
		flashlight.visible = false
		return
	if _flicker_next_toggle <= 0.0:
		flashlight.visible = not flashlight.visible
		_flicker_next_toggle = randf_range(_flicker_min_period, _flicker_max_period)


func _set_flashlight(enabled: bool) -> void:
	flashlight_enabled = enabled and owns_inventory_item("flashlight") \
		and lamp_charge > 0.0
	flashlight.visible = _flashlight_beam_should_be_visible()
	if _flashlight_probe != null:
		_flashlight_probe.enabled = flashlight.visible
	_animate_flashlight_toggle()
	_update_first_person_item_lights()
	flashlight_changed.emit(flashlight_enabled)


func _build_flashlight_probe() -> void:
	_flashlight_probe = RayCast3D.new()
	_flashlight_probe.name = "FlashlightOcclusionRay"
	_flashlight_probe.position = flashlight.position
	_flashlight_probe.target_position = Vector3(0.0, 0.0, -FLASHLIGHT_MAX_RANGE)
	_flashlight_probe.collision_mask = 1
	_flashlight_probe.collide_with_areas = false
	_flashlight_probe.collide_with_bodies = true
	_flashlight_probe.enabled = false
	_flashlight_probe.add_exception(self)
	first_person_pivot.add_child(_flashlight_probe)


func _update_flashlight_occlusion() -> void:
	if _flashlight_probe == null:
		return
	var lit := _flashlight_beam_should_be_visible()
	_flashlight_probe.enabled = lit
	# SpotLight3D's shadow map is the correct cone-shaped occlusion system. Keep
	# its full range so adjacent walls shadow only their part of the cone.
	flashlight.spot_range = FLASHLIGHT_MAX_RANGE
	if not lit:
		flashlight_hit_distance = FLASHLIGHT_MAX_RANGE
		return
	# XR moves the light onto the tracked head each frame; keep the occlusion
	# ray on that exact transform instead of leaving it at the desktop pivot.
	if xr_active:
		_flashlight_probe.global_transform = flashlight.global_transform
	_flashlight_probe.force_raycast_update()
	if not _flashlight_probe.is_colliding():
		flashlight_hit_distance = FLASHLIGHT_MAX_RANGE
		return
	flashlight_hit_distance = _flashlight_probe.global_position.distance_to(
		_flashlight_probe.get_collision_point())


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
	_build_utility_view("battery")
	_refresh_inventory_view()


func _build_utility_view(item_id: String) -> void:
	var view := Node3D.new()
	view.name = "%sView" % item_id.to_pascal_case()
	view.position = UTILITY_ITEM_POSITION
	first_person_items.add_child(view)
	var scale_amount := .52 if item_id == "lockpick" else .43
	if item_id == "battery":
		scale_amount = .62
	_add_authored_item_model(view, item_id, scale_amount)
	view.visible = false
	tool_views[item_id] = view


func _add_authored_item_model(view: Node3D, item_id: String, scale_amount: float) -> void:
	var model_path := String(ITEM_MODEL_PATHS.get(item_id, ""))
	var model := ModelSlot.instantiate_prop(model_path)
	if model:
		model.name = "AuthoredToolModel"
		model.scale = Vector3.ONE * scale_amount
		model.rotation.x = deg_to_rad(-72.0)
		model.position = Vector3(0, -.02, -.18)
		_disable_first_person_shadows(model)
		view.add_child(model)
	else:
		push_error("FIRST-PERSON TOOL MODEL MISSING // %s" % model_path)


func _disable_first_person_shadows(node: Node) -> void:
	# Camera-local held equipment must never occlude a light or shadow the
	# nearby world. World pickups keep their ordinary shadow behavior because
	# this is applied only to the first-person instance.
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = \
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_first_person_shadows(child)


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


func _flashlight_beam_should_be_visible() -> bool:
	return flashlight_enabled and selected_inventory_item() == "flashlight"


## Network peers need the camera pitch as well as the controller body's yaw.
## Publishing only rotation.y made another runner's light stay horizontal when
## they looked up/down, and mounting the replicated SpotLight on their torso
## then let the mannequin shadow its own beam.
func equipment_aim_direction() -> Vector3:
	var source_basis := xr_camera.global_basis if xr_active \
		else first_person_camera.global_basis
	var direction := -source_basis.z
	return direction.normalized() if direction.length_squared() > .0001 \
		else -global_basis.z.normalized()


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
	select_inventory_slot(inventory_order.find("taser"))
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
	# Storage rows are rearrangeable but never become a held hand slot. Number
	# keys and the wheel always remain the five-slot quick bar.
	_save_active_flashlight_charge()
	selected_inventory_slot = wrapi(slot, 0, HOTBAR_SIZE)
	if inventory_order[selected_inventory_slot] == "flashlight":
		_activate_flashlight_slot(selected_inventory_slot)
	_refresh_inventory_view()
	_sync_flashlight_to_held_item()


func _sync_flashlight_to_held_item() -> void:
	if flashlight_enabled and selected_inventory_item() != "flashlight":
		_set_flashlight(false)
	else:
		flashlight.visible = _flashlight_beam_should_be_visible()
		_update_first_person_item_lights()


func selected_inventory_item() -> String:
	if selected_inventory_slot < 0 or selected_inventory_slot >= inventory_order.size():
		return ""
	return String(inventory_order[selected_inventory_slot])


func move_inventory_slot(from_slot: int, to_slot: int) -> void:
	if from_slot < 0 or to_slot < 0 or from_slot >= inventory_order.size() \
			or to_slot >= inventory_order.size() or from_slot == to_slot:
		return
	_save_active_flashlight_charge()
	var from_item = inventory_order[from_slot]
	inventory_order[from_slot] = inventory_order[to_slot]
	inventory_order[to_slot] = from_item
	var from_durability = inventory_slot_durability[from_slot]
	inventory_slot_durability[from_slot] = inventory_slot_durability[to_slot]
	inventory_slot_durability[to_slot] = from_durability
	if _active_flashlight_slot == from_slot:
		_active_flashlight_slot = to_slot
	elif _active_flashlight_slot == to_slot:
		_active_flashlight_slot = from_slot
	if from_slot < HOTBAR_SIZE and to_slot < HOTBAR_SIZE:
		if selected_inventory_slot == from_slot:
			selected_inventory_slot = to_slot
		elif selected_inventory_slot == to_slot:
			selected_inventory_slot = from_slot
	if selected_inventory_item() == "flashlight":
		_activate_flashlight_slot(selected_inventory_slot)
	_refresh_inventory_view()
	_sync_flashlight_to_held_item()


func grant_inventory_item(item_id: String, restored_durability: int = -1) -> bool:
	if BACKPACK_CAPACITY.has(item_id):
		return collect_backpack(item_id)
	if not INVENTORY_ITEMS.has(item_id):
		return false
	var slot := inventory_order.find("")
	if slot < 0:
		return false
	inventory_order[slot] = item_id
	if item_id == "flashlight":
		inventory_slot_durability[slot] = roundi(clampf(float(restored_durability), 0.0,
			GameConfig.MAX_LAMP_CHARGE) if restored_durability >= 0 \
			else GameConfig.MAX_LAMP_CHARGE)
	elif item_id == "taser":
		inventory_slot_durability[slot] = 0
		taser_cooldown = 0.0
	elif item_id == "battery":
		inventory_slot_durability[slot] = 0
	elif INVENTORY_MAX_DURABILITY.has(item_id):
		inventory_slot_durability[slot] = clampi(restored_durability, 1,
			int(INVENTORY_MAX_DURABILITY[item_id])) if restored_durability > 0 \
			else int(INVENTORY_MAX_DURABILITY[item_id])
	_sync_owned_inventory_items()
	if slot < HOTBAR_SIZE:
		select_inventory_slot(slot)
	else:
		_refresh_inventory_view()
	return true


func equip_backpack(item_id: String) -> bool:
	if not BACKPACK_CAPACITY.has(item_id) \
			or int(BACKPACK_RANK[item_id]) <= backpack_storage_units:
		return false
	backpack_storage_units = int(BACKPACK_RANK[item_id])
	_refresh_backpack_storage()
	return true


func collect_backpack(item_id: String) -> bool:
	if not BACKPACK_CAPACITY.has(item_id):
		return false
	backpack_storage_units += int(BACKPACK_RANK[item_id])
	_refresh_backpack_storage()
	return true


static func can_accept_backpack(_order: Array, item_id: String) -> bool:
	# Storage upgrades never need an empty physical slot.
	return BACKPACK_CAPACITY.has(item_id)


func _refresh_backpack_storage() -> void:
	equipped_backpack = "" if backpack_storage_units <= 0 else (
		"backpack_small" if backpack_storage_units == 1 else (
			"backpack_medium" if backpack_storage_units == 2 else "backpack_large"))
	var wanted := HOTBAR_SIZE + backpack_storage_units * 5
	while inventory_order.size() < wanted:
		inventory_order.append("")
		inventory_slot_durability.append(0)
	_refresh_inventory_view()


func inventory_capacity() -> int:
	return inventory_order.size()


func backpack_extra_slots() -> int:
	return backpack_storage_units * 5


func remove_inventory_item(item_id: String, preferred_slot: int = -1) -> Dictionary:
	if not INVENTORY_ITEMS.has(item_id) or not owns_inventory_item(item_id):
		return {}
	_save_active_flashlight_charge()
	var slot := preferred_slot if preferred_slot >= 0 \
			and preferred_slot < inventory_order.size() \
			and inventory_order[preferred_slot] == item_id else _preferred_item_slot(item_id)
	if slot < 0:
		return {}
	var durability := _slot_durability(slot)
	inventory_order[slot] = ""
	inventory_slot_durability[slot] = 0
	if item_id == "flashlight":
		_set_flashlight(false)
		if slot == _active_flashlight_slot:
			_active_flashlight_slot = inventory_order.find("flashlight")
			lamp_charge = float(_slot_durability(_active_flashlight_slot)) \
				if _active_flashlight_slot >= 0 else 0.0
	elif item_id == "taser":
		taser_cooldown = 0.0
	_sync_owned_inventory_items()
	_refresh_inventory_view()
	return {"item": item_id, "durability": durability, "slot": slot}


func request_drop_selected_item() -> bool:
	if input_frozen or stun_timer > 0.0:
		return false
	var item_id := selected_inventory_item()
	if item_id.is_empty():
		Sound.interaction_fail()
		return false
	item_drop_requested.emit(item_id, item_durability(item_id),
		selected_inventory_slot)
	return true


func owns_inventory_item(item_id: String) -> bool:
	return inventory_order.has(item_id)


func item_durability(item_id: String) -> int:
	_save_active_flashlight_charge()
	return _slot_durability(_preferred_item_slot(item_id))


func consume_item_durability(item_id: String, amount: int = 1) -> bool:
	if not owns_inventory_item(item_id) or not INVENTORY_MAX_DURABILITY.has(item_id):
		return false
	_save_active_flashlight_charge()
	var used_slot := _preferred_item_slot(item_id)
	if used_slot < 0:
		return false
	var remaining := maxi(0, _slot_durability(used_slot) - maxi(1, amount))
	inventory_slot_durability[used_slot] = remaining
	if remaining <= 0:
		_break_inventory_item(item_id, used_slot)
	return true


func _break_inventory_item(item_id: String, slot: int) -> void:
	if slot < 0 or slot >= inventory_order.size() \
			or inventory_order[slot] != item_id:
		return
	Sound.tool_break()
	remove_inventory_item(item_id, slot)
	# If the broken item occupied the selected quick slot, move to the nearest
	# remaining hotbar item. No zero-durability entry is retained anywhere.
	if slot == selected_inventory_slot:
		for offset in range(1, HOTBAR_SIZE + 1):
			var candidate := wrapi(slot + offset, 0, HOTBAR_SIZE)
			if not String(inventory_order[candidate]).is_empty():
				select_inventory_slot(candidate)
				return
	_refresh_inventory_view()


func inventory_durability_snapshot() -> Dictionary:
	_save_active_flashlight_charge()
	var snapshot := {}
	for item_id in INVENTORY_ITEMS:
		var slot := _preferred_item_slot(item_id)
		snapshot[item_id] = _slot_durability(slot)
	return snapshot


func inventory_slot_durability_snapshot() -> Array:
	_save_active_flashlight_charge()
	return inventory_slot_durability.duplicate()


func inventory_max_durability_snapshot() -> Dictionary:
	return INVENTORY_MAX_DURABILITY.duplicate(true)


func inventory_order_snapshot() -> Array:
	return inventory_order.duplicate()


func inventory_owned_snapshot() -> Dictionary:
	_sync_owned_inventory_items()
	return owned_inventory_items.duplicate(true)


func run_save_snapshot() -> Dictionary:
	_save_active_flashlight_charge()
	return {
		"position": global_position,
		"level": roundi(global_position.y / StreamedFacilityView3D.LEVEL_HEIGHT),
		"yaw": _yaw,
		"pitch": _pitch,
		"inventory_order": inventory_order.duplicate(),
		"inventory_slot_durability": inventory_slot_durability.duplicate(),
		"backpack_storage_units": backpack_storage_units,
		"selected_inventory_slot": selected_inventory_slot,
		"flashlight_enabled": flashlight_enabled,
		"stamina": stamina,
		"stamina_recovery_delay": stamina_recovery_delay,
		"meters": meters.snapshot(),
	}


func restore_run_save(state: Dictionary) -> bool:
	var order_value = state.get("inventory_order")
	var durability_value = state.get("inventory_slot_durability")
	var position_value = state.get("position")
	if not order_value is Array or not durability_value is Array \
			or not position_value is Vector3:
		return false
	var units := clampi(int(state.get("backpack_storage_units", 0)), 0, 24)
	var capacity := HOTBAR_SIZE + units * 5
	var saved_order: Array = order_value
	var saved_durability: Array = durability_value
	if saved_order.size() != capacity or saved_durability.size() != capacity:
		return false
	var restored_order := []
	var restored_durability := []
	for index in capacity:
		var item_id := String(saved_order[index])
		if not item_id.is_empty() and not INVENTORY_ITEMS.has(item_id):
			return false
		restored_order.append(item_id)
		var maximum := int(INVENTORY_MAX_DURABILITY.get(item_id, 0))
		var durability := maxi(0, int(saved_durability[index]))
		if maximum > 0:
			durability = mini(durability, maximum)
		restored_durability.append(durability)
	inventory_order = restored_order
	inventory_slot_durability = restored_durability
	backpack_storage_units = units
	equipped_backpack = "" if units <= 0 else (
		"backpack_small" if units == 1 else (
			"backpack_medium" if units == 2 else "backpack_large"))
	selected_inventory_slot = clampi(int(state.get("selected_inventory_slot", 0)),
		0, HOTBAR_SIZE - 1)
	_active_flashlight_slot = inventory_order.find("flashlight")
	lamp_charge = float(_slot_durability(_active_flashlight_slot)) \
		if _active_flashlight_slot >= 0 else 0.0
	stamina = clampf(float(state.get("stamina", GameConfig.MAX_STAMINA)),
		0.0, GameConfig.MAX_STAMINA)
	stamina_recovery_delay = maxf(0.0,
		float(state.get("stamina_recovery_delay", 0.0)))
	exhausted = stamina <= 0.0
	_yaw = float(state.get("yaw", 0.0))
	_pitch = clampf(float(state.get("pitch", 0.0)), deg_to_rad(-85.0),
		deg_to_rad(85.0))
	rotation.y = _yaw
	first_person_pivot.rotation.x = _pitch
	global_position = position_value
	velocity = Vector3.ZERO
	hidden = false
	resting_furniture = null
	resting_pose = ""
	input_frozen = false
	look_frozen = false
	meters.adopt(state.get("meters", {}))
	_sync_owned_inventory_items()
	_refresh_inventory_view()
	var wants_light := bool(state.get("flashlight_enabled", false)) \
		and selected_inventory_item() == "flashlight" and lamp_charge > 0.0
	_set_flashlight(wants_light)
	return true


func _preferred_item_slot(item_id: String) -> int:
	if selected_inventory_slot >= 0 and selected_inventory_slot < inventory_order.size() \
			and inventory_order[selected_inventory_slot] == item_id:
		return selected_inventory_slot
	if item_id == "flashlight" and _active_flashlight_slot >= 0 \
			and _active_flashlight_slot < inventory_order.size() \
			and inventory_order[_active_flashlight_slot] == item_id:
		return _active_flashlight_slot
	return inventory_order.find(item_id)


func _slot_durability(slot: int) -> int:
	if slot < 0 or slot >= inventory_slot_durability.size():
		return 0
	return int(inventory_slot_durability[slot])


func _save_active_flashlight_charge() -> void:
	if _active_flashlight_slot >= 0 \
			and _active_flashlight_slot < inventory_order.size() \
			and inventory_order[_active_flashlight_slot] == "flashlight":
		inventory_slot_durability[_active_flashlight_slot] = roundi(lamp_charge)


func _activate_flashlight_slot(slot: int) -> void:
	if slot < 0 or slot >= inventory_order.size() \
			or inventory_order[slot] != "flashlight":
		return
	_save_active_flashlight_charge()
	_active_flashlight_slot = slot
	lamp_charge = float(_slot_durability(slot))


func _sync_owned_inventory_items() -> void:
	for item_id in INVENTORY_ITEMS:
		owned_inventory_items[item_id] = inventory_order.has(item_id)


func _use_selected_item() -> void:
	var item_id := selected_inventory_item()
	if item_id.is_empty():
		Sound.interaction_fail()
		return
	match item_id:
		"flashlight":
			# F / the dedicated flashlight bind is the only toggle. Left click
			# is tool_use (focus, mouse capture, looking) and must not flip or
			# drain the lamp, or a window-focus click can leave it on the floor.
			return
		"taser":
			_fire_taser()
		"battery":
			_use_battery()
		_:
			_use_selected_tool()


func _use_battery() -> void:
	if lamp_charge >= GameConfig.MAX_LAMP_CHARGE - .01:
		Sound.interaction_fail()
		return
	var used_slot := selected_inventory_slot
	if used_slot < 0 or used_slot >= inventory_order.size() \
			or String(inventory_order[used_slot]) != "battery":
		Sound.interaction_fail()
		return
	remove_inventory_item("battery", used_slot)
	restore_lamp(GameConfig.BATTERY_RECHARGE)
	Sound.recharge(GameConfig.BATTERY_RECHARGE)


func _use_selected_tool() -> void:
	if input_frozen or stun_timer > 0.0:
		return
	var item_id := selected_inventory_item()
	if not BREACH_TOOLS.has(item_id) and not LOCK_TOOLS.has(item_id):
		Sound.interaction_fail()
		return
	# A committed swing/use spends durability before any hit result. This makes
	# ally hits cost the tool without ever creating friendly-fire damage.
	if not consume_item_durability(item_id):
		Sound.interaction_fail()
		return
	_animate_tool_use(item_id)
	tool_used.emit(item_id)
	var target := _nearest_interactable()
	if target != null and (target.kind == RouteInteractable3D.Kind.BOARDED_PATH \
			or (target.kind == RouteInteractable3D.Kind.RELAY and target.locked_cache)):
		target.activate_with_tool(self, item_id, true)
		if target.last_activation_failed:
			Sound.interaction_fail()


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
	_save_active_flashlight_charge()


## World position projected onto facility_generator.gd's grid-cell space —
## valid because the 3D world uses 1 cell = 1 meter with the grid's (x,y)
## mapped directly onto the XZ ground plane (see facility_view_3d.gd).
func grid_position() -> Vector2:
	return Vector2(global_position.x, global_position.z)


func restore_at_safe_zone() -> void:
	stamina = GameConfig.MAX_STAMINA
	lamp_charge = GameConfig.MAX_LAMP_CHARGE
	_save_active_flashlight_charge()
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
		# Hiding fixtures and generic development interactables remain usable with
		# E/right-click, but their one-word toasts add no useful information and sit
		# directly over the first-person view. Keep contextual prompts (doors, vents,
		# pickups, furniture) because those communicate a distinct action.
		if prompt.strip_edges().to_upper() in ["HIDE", "USE"]:
			prompt = ""
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
		Sound.interaction_fail()
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
			Sound.interaction_fail()
			return
	var message := target.activate(self)
	if target.last_activation_failed:
		Sound.interaction_fail()
	elif not message.is_empty():
		interaction_message.emit(message)


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
