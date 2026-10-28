class_name PlayerController3D
extends CharacterBody3D

## First-person CharacterBody3D controller. It owns the shared stamina/lamp/
## interaction rules and movement on the XZ ground plane, with two
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
## A sewer ladder climb finished; the runner now stands on `to_level`.
signal ladder_climb_finished(to_level: int)
## The waterfall plunge is over: where the runner climbed out of the cistern (world position).
signal plunge_finished(exit_position: Vector3)
signal taser_requested
signal tool_used(item_id: String)
signal item_drop_requested(item_id: String, durability: int, slot: int)
signal interaction_message(message: String)

## Fallback only. At runtime the standing camera is aligned to the player
## model's authored eye attachments, keeping the first-person POV and visible
## co-op mannequin at the same height when the model is revised.
const CAMERA_HEIGHT := 1.6 * PlayerModels.SCALE
const CAMERA_HEIGHT_MIN := 1.35 * PlayerModels.SCALE
const CAMERA_HEIGHT_MAX := 1.78 * PlayerModels.SCALE
const CONTROLLER_LOOK_RADIANS_PER_SECOND := 2.8
## Capsule, eye, crouch and step all follow the runner's size (PlayerModels.SCALE); the radius stays as it is.
const STANDING_COLLISION_HEIGHT := 1.7 * PlayerModels.SCALE
const CROUCH_COLLISION_HEIGHT := 1.08 * PlayerModels.SCALE
const STANDING_COLLISION_CENTER_Y := STANDING_COLLISION_HEIGHT * .5
const CROUCH_COLLISION_CENTER_Y := CROUCH_COLLISION_HEIGHT * .5
## How far the floor snap reaches (keeps her on stair ramps going down), scaled with her.
const FLOOR_SNAP := .28 * PlayerModels.SCALE
const CROUCH_EYE_RATIO := .69
const CROUCH_EYE_TOP_CLEARANCE := .08
const CAMERA_BOB_WALK_AMPLITUDE := .024 * PlayerModels.SCALE
const CAMERA_BOB_SPRINT_AMPLITUDE := .038 * PlayerModels.SCALE
const CAMERA_BOB_CROUCH_AMPLITUDE := .012 * PlayerModels.SCALE
const FLASHLIGHT_MAX_RANGE := 16.0
const FLASHLIGHT_MIN_RANGE := .8
## Camera-local position of the flashlight's physical lens. The old light
## began at the camera behind the held model; once shadows were enabled, the
## flashlight body shadowed its own beam before it could reach the room.
# The hand model is deliberately camera-local and visually sits much farther
# forward than its physical world position should. Keep the real light just in
# front of the camera/capsule so it cannot cross into a nearby wall.
const FLASHLIGHT_BEAM_LOCAL_POSITION := Vector3(.08, -.05, -.12)
const BODY_MODEL_SCENE := PlayerModels.SCENE

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

## Floor surface under the runner (SurfaceSounds), set by the run scene each frame; "" = the generic step.
## How close to an interactable's focus point the view ray may stop and still count as reaching it (door leaf/frame).
const INTERACTION_FOCUS_TOLERANCE := 0.55
var footstep_surface := ""
var flashlight_enabled := false
## First-person equipment is deliberately camera-local. The authoritative
## taser hit is resolved by main_3d; this controller owns only input, cooldown
## presentation, and the local recoil animation.
var first_person_items: Node3D
var flashlight_view: Node3D
var taser_view: Node3D
var tool_views := {}
## Replicated with the movement state: every committed swing bumps the counter, so a peer plays one swing per increment (and plays the thud
## when the swing connected). A swing that hits nothing is a harmless whoosh: no durability, no noise, no deny blip.
var tool_swing_seq := 0
var tool_swing_item := ""
var tool_swing_hit := false
## Extra scene hook: returns true when the scene (a safe room to repair, a grabbed teammate) has a use for this tool right here.
var tool_context_probe := Callable()
var _noise_burst := 0.0
var _noise_burst_timer := 0.0
var _swing_busy_until_msec := 0
var _viewmodel_push := 0.0
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
const FLASHLIGHT_ITEM_POSITION := Vector3(0.27, -0.24, -0.52)
const TASER_ITEM_POSITION := Vector3(-0.24, -0.24, -0.50)
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
## The rescue axe is the heavy tool: a committed chop costs a quarter of its life (24 -> four chops), clears two boards at once, is loud enough
## for hunters to hear across a room, and is the one thing that cuts the player (or a teammate) out of a hunter's hold.
const TOOL_SWING_COST := {"crowbar": 1, "rescue_axe": 6}
const AXE_BREAK_FREE_COST := 8
const AXE_NOISE := 18.0
const AXE_NOISE_SECONDS := 0.9
const VIEWMODEL_PUSH_RANGE := 1.0
const VIEWMODEL_MAX_PUSH := 0.65
const LOCK_TOOLS := ["lockpick", "crowbar"]
const FRIENDLY_FIRE_ENABLED := false
## Games without items (Night Watch) switch the inventory off by configuration, not by forking the controller: the flashlight stays as a built-in tool in
## the hand (toggle action, sound and spot light as ever) and never drains; the slot keys, the wheel, drop, tool use, the taser, pickups and backpacks do nothing.
## The default (true) is Last Route's and the City's.
@export var inventory_enabled := true
## Night Watch gives Space to the cameras (the 2D game's camera toggle): its player scene switches jumping off by configuration; the default (true) is Last Route's and the City's.
@export var jump_enabled := true
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
## Orange Void's sabotage: one system ("flashlight", "climate" or "radar") offline until outage_left runs out.
var outage_system := ""
var outage_left := 0.0
var stamina := GameConfig.MAX_STAMINA
var lamp_charge := GameConfig.MAX_LAMP_CHARGE
var exhausted := false
var stamina_recovery_delay := 0.0
## Troll mode (docs/ANTI_CHEAT.md): the host caught this client cheating, or the server flagged the account. Faster
## stamina drain, a flickering flashlight and fake hunter footsteps; the host side (hunters, pickups) does the rest.
var troll_active := false
var _troll_step_in := 0.0
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
## A booth game (CarnivalBooth3D) holds the player at the counter: no walking, sprinting or jumping, but looking and aiming stay free, with mouse, stick, touch and XR.
var movement_locked := false

## Debug-only protections driven by main_3d's tools-gated admin overlay. They
## live on the controller so the same state can be published to the ENet host;
## release builds never get the menu which changes either value.
var admin_no_target := false
var admin_god_mode := false
var admin_noclip := false
## Admin run-speed multiplier (1 = normal); applied to walk, crouch and sprint.
var admin_speed_scale := 1.0
## A captured co-op guest remains in the room as a free-flying spectator rather
## than respawning or being forced back to the menu. The host still treats this
## state as game-over for targeting and replication purposes.
var spectator_mode := false
## Follow cam: while valid the spectator trails this world position instead of free-flying.
var spectator_follow_valid := false
var spectator_follow_at := Vector3.ZERO

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
var _airborne_time := 0.0
## One-frame hop request used by XR and deterministic gameplay validation.
## Keyboard/controller bindings still use Input's ordinary `jump` action.
var _jump_requested := false
## OpenXR is opt-in for desktop exports (`--xr` or an `xr` export feature) and
## automatic for the Quest preset. If initialization fails, the same binary
## falls back to the ordinary first-person camera.
var xr_active := false
## OpenXR comfort and the wrist HUD (built only once OpenXR has started).
var xr_comfort: XRComfort
## OpenXR hand interactions: hand-over-hand ladders, physical swings, pokes, the flashlight in the left hand.
var xr_hands: XRHands
var xr_fade: XRFade
const XR_REVEAL_FALLBACK_SECONDS := 2.5
## Metres a gripping hand pulled the runner up (+) or down (-) this frame (XRHands), applied by _update_ladder_climb.
var _xr_climb_pull := 0.0

## Out of sight, in a locker. Movement stops, the body is not drawn, and
## perception treats you as gone -- the shared brain's `hidden` gate has always
## been there, wired to a literal false because nothing could hide.
var hidden := false
var hidden_spot := Vector2i(-1, -1)
var _hiding_exit_position := Vector3.ZERO
var _hiding_collision_layer := 1
var _hiding_collision_mask := 1
var _hiding_fixture: Node3D
## Entering/leaving a hiding spot is a camera move, not a cut (docs/HIDING_PROPS.md). The body (gameplay position,
## collision, `hidden`) changes at once; only the first-person pivot and the view yaw ease along a path through the
## spot's entry point. A forced pull (a catch, a hunter's check) cancels it.
const HIDE_MOVE_SECONDS := 0.6
var _hide_move := {}

## Personal furniture pose. It is replicated through current_clip/transform,
## but does not mutate the shared prop, so two couch seats in co-op never need
## an authority round trip.
var resting_furniture: RouteInteractable3D
## A sewer ladder climb in progress (begin_ladder_climb): where it runs, how high the runner is and the
## phase (mount, climb, dismount).
## Movement, items and collision are off; the body plays "climb" (guests see it
## through current_clip) and the view shows both hands working the rungs.
var ladder_climb := {}
## The waterfall plunge in progress (begin_plunge), and the soaked status after it (seconds left).
var plunge := {}
var soaked_left := 0.0
var _drip_left := 0.0
var _climb_hands: Node3D
## Ladder handling: climb speed (m/s), the height under which jump lets go, and
## the smooth mount / dismount times.
## The waterfall jump (begin_plunge): an arc off the ledge into the cistern, a muffled moment under the surface, a slow swim to the
## walkway ring, then SOAKED_SECONDS of dripping and louder steps (hunters hear a wet runner from further away).
const PLUNGE_HOP_SPEED := 1.6
const PLUNGE_GRAVITY := 9.8
const PLUNGE_SPLASH_SECONDS := .55
const PLUNGE_SWIM_SPEED := 1.5
const PLUNGE_CLIMB_OUT_SECONDS := .6
const PLUNGE_SPLASH_NOISE := 3.0
const PLUNGE_SPLASH_NOISE_SECONDS := 1.2
const PLUNGE_SWIM_NOISE := .8
const SOAKED_SECONDS := 30.0
const SOAKED_NOISE_SCALE := 1.45
const SOAKED_DRIP_EVERY := Vector2(1.1, 2.4)
const LADDER_CLIMB_SPEED := 1.7
const LADDER_LET_GO_HEIGHT := 1.3 * PlayerModels.SCALE
const LADDER_MOUNT_SECONDS := .3
const LADDER_DISMOUNT_SECONDS := .45
var resting_pose := ""
## Rest camera (docs/REST_AND_SLEEP.md): the eye moves to a seated height facing out, or to pillow height looking along
## the bed, with a clamped look range around the furniture's facing, and eases there and back instead of snapping.
const SIT_EYE := 1.15
const LAY_EYE_ABOVE_MATTRESS := .22
const REST_EASE_SECONDS := 0.35
const SIT_YAW_LIMIT := deg_to_rad(75.0)
const LAY_YAW_LIMIT := deg_to_rad(55.0)
const SIT_PITCH := Vector2(-0.95, 0.6)
const LAY_PITCH := Vector2(-0.35, 1.05)
var _rest_yaw := 0.0
var _rest_eye := SIT_EYE
var _rest_ease := {}
## Sleep (docs/REST_AND_SLEEP.md). In a bed, jump sleeps / wakes. Asleep: dark screen, stamina refills, a hunter close by
## stirs you with a muffled cue and a closer one (or any noise event) wakes you with a jolt; you are an ordinary target.
## Solo only: lying idle in a bed for REST_DROWSY_AFTER seconds makes you drowsy (blinks, a yawn) and then you doze off,
## unless you move the mouse or press a key. Co-op turns accidental sleep off (accidental_sleep_enabled).
const REST_DROWSY_AFTER := 50.0
const DROWSY_SECONDS := 8.0
const SLEEP_STAMINA_PER_SECOND := 9.0
const SLEEP_STIR_DISTANCE := 12.0
const SLEEP_WAKE_DISTANCE := 5.0
var asleep := false
var drowsiness := 0.0
var accidental_sleep_enabled := true
var _rest_idle := 0.0
var _yawned := false
var _sleep_time := 0.0
var _sleep_stir_cooldown := 0.0
var _sleep_fade := 0.0
var _sleep_overlay: ColorRect
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

## Zellia's shop -- the same indirection as vent_resolver/music_box_resolver.
## `shop_resolver.call("open")` opens or re-toasts the menu (the gimmick
## itself checks range, so a far-away call is a harmless no-op the same way
## _nearest_interactable() already handles distance for ordinary pickups);
## `.call("1")`..`.call("4")` chooses an offer while a menu is open. The
## original borrows its hotbar's digit keys for this; this port has no
## hotbar, so raw digit-key presses (see _unhandled_input) are the one
## deliberate exception to routing everything through a named input action.
var shop_resolver: Callable
var shop_prompt_provider: Callable

## Zellia's pesticide trade: a real timer, not a boolean, so it reads the
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
		first_person_pivot.position = Vector3(0.0, _standing_camera_height, 0.0)
	if resting_furniture != null:
		leave_furniture()
	var start_camera := first_person_pivot.global_position
	_furniture_return_position = global_position
	resting_furniture = furniture
	resting_pose = pose
	var spot := rest_spot(furniture, pose)
	global_position = spot["body"]
	_rest_yaw = float(spot["yaw"])
	_rest_eye = float(spot["eye"])
	_yaw = _rest_yaw
	_pitch = float(spot["pitch"])
	_apply_look_rotation()
	first_person_pivot.position = Vector3(0.0, _rest_eye, 0.0)
	_rest_ease = {"from": start_camera, "t": 0.0, "leaving": false}
	_apply_rest_ease()
	_rest_idle = 0.0
	if first_person_items != null:
		first_person_items.visible = false    # nothing held in view while seated, lying or asleep
	velocity = Vector3.ZERO
	_clip = "sit" if pose == "ride" else pose
	ModelSlot.play_if_available(_animation_player, _clip)
	if pose == "ride":
		Sound.menu_blip()
		return ""
	return "LYING DOWN // %s SLEEP // %s GET UP" % [InputGlyphs.key("jump"), InputGlyphs.key("interact")] if pose == "lay" \
		else "SEATED // %s" % InputGlyphs.prompt("interact", "STAND")


## Where the body and eye go on a piece of furniture (the furniture interactable sits on the prop, facing its open side;
## its "rest_size" meta is the prop's footprint). Sitting: the body a little forward of the seat centre (clear of the
## backrest), eye at seated height, facing out. Lying: the body at the pillow end, eye just above the mattress, looking
## along the bed toward its foot, tipped up a little.
static func rest_spot(furniture: Node3D, pose: String) -> Dictionary:
	if not furniture.has_meta("rest_size"):
		# authored seats (Night Watch's office chair, its bedroom bed) place the body exactly on their own point
		return {"body": furniture.global_position, "eye": .72 if pose == "lay" else 1.02,
			"yaw": furniture.global_rotation.y, "pitch": 0.0}
	var size: Vector3 = furniture.get_meta("rest_size", Vector3(1.0, .8, 2.0) if pose == "lay" else Vector3(.5, .9, .5))
	var floor_y := furniture.global_position.y - (.48 if pose == "lay" else .03)
	var xf := furniture.global_transform
	if pose == "lay":
		var head := xf * Vector3(0.0, 0.0, maxf(0.0, size.z * .5 - .5))
		# the eye just above the pillow: the bed model's measured mattress top (the view's "rest_top"), else an estimate
		var eye := float(furniture.get_meta("rest_top")) + LAY_EYE_ABOVE_MATTRESS if furniture.has_meta("rest_top") \
			else (clampf(size.y * .62 + .14, .72, 1.05) if size.y < 1.6 else .95)
		return {"body": Vector3(head.x, floor_y, head.z), "eye": eye, "yaw": furniture.global_rotation.y, "pitch": .12}
	var seat := xf * Vector3(0.0, 0.0, -.06)
	return {"body": Vector3(seat.x, floor_y, seat.z), "eye": SIT_EYE, "yaw": furniture.global_rotation.y, "pitch": -.08}


func leave_furniture() -> String:
	if resting_furniture == null:
		return ""
	if asleep:
		wake_from_sleep("")
	var start_camera := first_person_pivot.global_position
	global_position = _furniture_return_position
	resting_furniture = null
	resting_pose = ""
	drowsiness = 0.0
	first_person_pivot.position = Vector3(0.0, _standing_camera_height, 0.0)
	_rest_ease = {"from": start_camera, "t": 0.0, "leaving": true}
	_apply_rest_ease()
	_clip = "idle"
	ModelSlot.play_if_available(_animation_player, _clip)
	return "STOOD UP"


func rest_ease_active() -> bool:
	return not _rest_ease.is_empty()


## The eye eases from where it was to its new place (both ways), in REST_EASE_SECONDS; input waits for it.
func _advance_rest_ease(delta: float) -> void:
	_rest_ease["t"] = minf(1.0, float(_rest_ease["t"]) + delta / REST_EASE_SECONDS)
	_apply_rest_ease()
	if float(_rest_ease["t"]) >= 1.0:
		if bool(_rest_ease.get("leaving", false)) and first_person_items != null:
			first_person_items.visible = true
		_rest_ease = {}
		first_person_pivot.position.x = 0.0
		first_person_pivot.position.z = 0.0


func _apply_rest_ease() -> void:
	var t := smoothstep(0.0, 1.0, float(_rest_ease.get("t", 1.0)))
	var target := global_position + Vector3.UP * (_rest_eye if resting_furniture != null else _standing_camera_height)
	first_person_pivot.global_position = (_rest_ease["from"] as Vector3).lerp(target, t)


## Look limits while resting: yaw within the furniture's facing +- the pose's limit, pitch in the pose's range.
func _clamp_rest_look() -> void:
	if resting_furniture == null:
		return
	var limit := LAY_YAW_LIMIT if resting_pose == "lay" else SIT_YAW_LIMIT
	_yaw = _rest_yaw + clampf(wrapf(_yaw - _rest_yaw, -PI, PI), -limit, limit)
	var pitch_range := LAY_PITCH if resting_pose == "lay" else SIT_PITCH
	_pitch = clampf(_pitch, pitch_range.x, pitch_range.y)


func toggle_sleep() -> String:
	if asleep:
		return wake_from_sleep("AWAKE")
	if resting_furniture == null or resting_pose != "lay" or rest_ease_active():
		return ""
	return fall_asleep(false)


func fall_asleep(accidental: bool) -> String:
	asleep = true
	drowsiness = 0.0
	_sleep_time = 0.0
	_sleep_stir_cooldown = 0.0
	_set_flashlight(false)
	Sound.sleep_settle()
	return "YOU DOZED OFF" if accidental else "ASLEEP // %s OR %s WAKE" % [InputGlyphs.key("jump"), InputGlyphs.key("interact")]


func wake_from_sleep(message: String = "WOKE WITH A JOLT") -> String:
	if not asleep:
		return ""
	asleep = false
	drowsiness = 0.0
	_rest_idle = 0.0
	_yawned = false
	if message == "WOKE WITH A JOLT":
		kick_view(.06)
		Sound.sleep_jolt()
	return message


## Called by the route every frame with the distance to the nearest hunter (INF when none) while this runner is asleep
## or drowsy: a stir cue in SLEEP_STIR_DISTANCE, a jolt awake inside SLEEP_WAKE_DISTANCE.
func sleep_disturb(hunter_distance: float, delta: float) -> String:
	if not asleep:
		return ""
	_sleep_stir_cooldown = maxf(0.0, _sleep_stir_cooldown - delta)
	if hunter_distance <= SLEEP_WAKE_DISTANCE:
		return wake_from_sleep()
	if hunter_distance <= SLEEP_STIR_DISTANCE and _sleep_stir_cooldown <= 0.0:
		_sleep_stir_cooldown = 3.0
		Sound.sleep_stir(0.0, clampf(1.0 - hunter_distance / SLEEP_STIR_DISTANCE, .25, 1.0))
	return ""


func _update_sleep(delta: float) -> void:
	var lying := resting_furniture != null and resting_pose == "lay"
	if asleep:
		_sleep_time += delta
		stamina = minf(GameConfig.MAX_STAMINA, stamina + SLEEP_STAMINA_PER_SECOND * delta)
		_sleep_fade = move_toward(_sleep_fade, 1.0, delta * 1.5)
	else:
		_sleep_fade = move_toward(_sleep_fade, 0.0, delta * 3.0)
		if lying and accidental_sleep_enabled and not rest_ease_active():
			_rest_idle += delta
			if _rest_idle >= REST_DROWSY_AFTER:
				if not _yawned:
					_yawned = true
					Sound.sleep_yawn()
					interaction_message.emit("DROWSY...")
				drowsiness = minf(1.0, (_rest_idle - REST_DROWSY_AFTER) / DROWSY_SECONDS)
				if drowsiness >= 1.0:
					interaction_message.emit(fall_asleep(true))
		else:
			drowsiness = 0.0
	# slow blinks while drowsy, full dark while asleep
	var blink := 0.0
	if drowsiness > 0.0:
		blink = drowsiness * .55 + .45 * drowsiness * maxf(0.0, sin(float(Time.get_ticks_msec()) * .0025))
	_set_sleep_overlay(maxf(_sleep_fade * .94, blink))


## Any deliberate input while resting keeps you awake (resets the drowsy clock).
func note_rest_activity() -> void:
	_rest_idle = 0.0
	if drowsiness > 0.0:
		drowsiness = 0.0
		_yawned = false


func _set_sleep_overlay(alpha: float) -> void:
	if alpha <= 0.001 and _sleep_overlay == null:
		return
	if _sleep_overlay == null:
		var layer := CanvasLayer.new()
		layer.name = "SleepOverlay"
		layer.layer = 40
		add_child(layer)
		_sleep_overlay = ColorRect.new()
		_sleep_overlay.color = Color(0, 0, 0, 0)
		_sleep_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sleep_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		layer.add_child(_sleep_overlay)
	_sleep_overlay.color = Color(0, 0, 0, clampf(alpha, 0.0, 1.0))
	_sleep_overlay.visible = alpha > .001


func sleep_overlay_alpha() -> float:
	return _sleep_overlay.color.a if _sleep_overlay != null and _sleep_overlay.visible else 0.0


func enter_hiding(cell: Vector2i, inside_position: Vector3 = Vector3.ZERO,
		exit_position: Vector3 = Vector3.ZERO,
		fixture: Node3D = null) -> String:
	_hiding_exit_position = exit_position if exit_position != Vector3.ZERO \
		else global_position
	var start_camera := first_person_pivot.global_position
	var start_yaw := _yaw
	_hiding_fixture = fixture
	if is_instance_valid(_hiding_fixture):
		if _hiding_fixture.has_method("set_local_hiding_view"):
			_hiding_fixture.call("set_local_hiding_view", true)
		if _hiding_fixture.has_method("hiding_outward_yaw"):
			_yaw = float(_hiding_fixture.call("hiding_outward_yaw"))
			rotation.y = _yaw
			_pitch = 0.0
			first_person_pivot.rotation.x = 0.0
		# Under a bed the view drops to the floor (docs/HIDING_PROPS.md); lockers and wardrobes keep eye height.
		if _hiding_fixture.has_method("hiding_eye_height"):
			var eye := float(_hiding_fixture.call("hiding_eye_height"))
			if eye >= 0.0:
				first_person_pivot.position.y = eye
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
	_begin_hide_move(start_camera, start_yaw, true)
	return cleared_message if not cleared_message.is_empty() else "Hidden. Interact to come out."


## `forced`: another hunter reaching in (Javelle, Loxelle) rather than the player
## working the exit key. A forced pull ignores Ceryth's lock on purpose --
## being physically dragged out is not the thing the lock exists to prevent.
func leave_hiding(at: Vector2 = Vector2.ZERO, forced: bool = false) -> String:
	if hiding_lock_timer > 0.0 and not forced:
		return "Locked in hiding for %.0fs." % hiding_lock_timer
	var start_camera := first_person_pivot.global_position
	var start_yaw := _yaw
	var entry := _hide_entry_point()
	var animate := not forced and at == Vector2.ZERO and is_instance_valid(_hiding_fixture)
	_hide_move = {}
	hidden = false
	hidden_spot = Vector2i(-1, -1)
	input_frozen = false
	hiding_lock_timer = 0.0
	if is_instance_valid(_hiding_fixture) \
			and _hiding_fixture.has_method("set_local_hiding_view"):
		_hiding_fixture.call("set_local_hiding_view", false)
	_hiding_fixture = null
	first_person_pivot.position = Vector3(0.0, _standing_camera_height, 0.0)
	collision_layer = _hiding_collision_layer
	collision_mask = _hiding_collision_mask
	if at != Vector2.ZERO:
		global_position = Vector3(at.x, global_position.y, at.y)
	elif _hiding_exit_position != Vector3.ZERO:
		global_position = _hiding_exit_position
	_hiding_exit_position = Vector3.ZERO
	if animate:
		# reverse: back out at hiding height to the opening, then stand up where you went in
		_hide_move = {"from": start_camera, "via": Vector3(entry.x, start_camera.y, entry.z),
			"from_yaw": start_yaw, "to_yaw": _yaw, "t": 0.0, "entering": false}
		input_frozen = true
		_apply_hide_move(0.0)
	return "Out of hiding."


## World point just outside the spot's opening (in front of the bed's foot, the wardrobe or locker doors).
func _hide_entry_point() -> Vector3:
	if not is_instance_valid(_hiding_fixture):
		return global_position
	var depth := .45
	var size = _hiding_fixture.get("hide_size")
	if size is Vector3 and not String(_hiding_fixture.get("hide_style")).is_empty():
		depth = (size as Vector3).z * .5 + .12
	return _hiding_fixture.global_transform * Vector3(0.0, 0.0, -depth)


func _begin_hide_move(start_camera: Vector3, start_yaw: float, entering: bool) -> void:
	var entry := _hide_entry_point()
	var eye := first_person_pivot.position.y
	# Bed: drop to the floor at the foot, then slide under at that height. Wardrobe/locker: walk to the doors at eye height.
	# to the opening at the current height (over furniture, never through it), down to the hiding height, then in
	var via := Vector3(entry.x, global_position.y + eye, entry.z)
	_hide_move = {"from": start_camera, "over": Vector3(entry.x, start_camera.y, entry.z), "via": via,
		"from_yaw": start_yaw, "to_yaw": _yaw, "t": 0.0, "entering": entering, "eye": eye}
	_apply_hide_move(0.0)


func hiding_style() -> String:
	if not hidden or not is_instance_valid(_hiding_fixture):
		return ""
	var style = _hiding_fixture.get("hide_style")
	return String(style) if style != null and not String(style).is_empty() else "locker"


func hide_move_active() -> bool:
	return not _hide_move.is_empty()


func _advance_hide_move(delta: float) -> void:
	_hide_move["t"] = minf(1.0, float(_hide_move["t"]) + delta / HIDE_MOVE_SECONDS)
	_apply_hide_move(float(_hide_move["t"]))
	if float(_hide_move["t"]) >= 1.0:
		var entering := bool(_hide_move["entering"])
		_hide_move = {}
		first_person_pivot.position.x = 0.0
		first_person_pivot.position.z = 0.0
		if not entering:
			input_frozen = false


func _apply_hide_move(t: float) -> void:
	var from: Vector3 = _hide_move["from"]
	var via: Vector3 = _hide_move["via"]
	var target := global_position + Vector3.UP * (float(_hide_move.get("eye", _standing_camera_height)) \
		if bool(_hide_move["entering"]) else _standing_camera_height)
	var over: Vector3 = _hide_move.get("over", via)
	var point: Vector3
	if t < .35:
		point = from.lerp(over, smoothstep(0.0, 1.0, t / .35))
	elif t < .6:
		point = over.lerp(via, smoothstep(0.0, 1.0, (t - .35) / .25))
	else:
		point = via.lerp(target, smoothstep(0.0, 1.0, (t - .6) / .4))
	first_person_pivot.global_position = point
	rotation.y = lerp_angle(float(_hide_move["from_yaw"]), float(_hide_move["to_yaw"]), smoothstep(0.0, 1.0, t))


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
	floor_snap_length = FLOOR_SNAP
	first_person_camera.fov = Settings.field_of_view
	if PlatformProfile.camera_far > 0.0:
		# phones and headsets draw less far (desktop keeps the scene's far plane)
		first_person_camera.far = PlatformProfile.camera_far
		xr_camera.far = PlatformProfile.camera_far
	Settings.visual_changed.connect(_apply_visual_settings)
	_warm_flashlight.call_deferred()
	var model := ModelSlot.instantiate(BODY_MODEL_SCENE)
	if model:
		_body_model = model
		model.scale = Vector3.ONE * PlayerModels.SCALE
		body_visual.add_child(model)
		ModelSlot.apply_character_hue(model, Settings.player_hue_degrees)
		PlayerSkin.set_arms(model, Settings.effective_slim())
		PlayerSkin.apply(model, PlayerSkin.active_texture())
		_animation_player = ModelSlot.find_animation_player(model)
		_align_camera_to_model_eyes(model)
	flashlight.position = FLASHLIGHT_BEAM_LOCAL_POSITION
	_build_flashlight_probe()
	_build_first_person_items()
	# The starter flashlight is owned and visible in slot one, but begins off so
	# entering a route never spends charge before the player chooses to use it.
	_set_flashlight(false)
	_update_crouch_hitbox(false)
	_connect_xr_buttons()
	if not _try_enter_xr():
		_enter_first_person()


func _apply_visual_settings() -> void:
	first_person_camera.fov = Settings.field_of_view
	if _body_model != null:
		PlayerSkin.set_arms(_body_model, Settings.effective_slim())
		PlayerSkin.apply(_body_model, PlayerSkin.active_texture())
	if first_person_items != null:
		for hand in first_person_items.find_children("FirstPersonHand", "Node3D", true, false):
			if bool(hand.get_meta("slim", false)) != Settings.effective_slim():
				var view := hand.get_parent()
				hand.free()   # the arm style changed: rebuild the hand from the other mannequin's parts
				_add_first_person_hand(view)
				continue
			PlayerSkin.apply(hand, PlayerSkin.active_texture())


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
	standing_shape.size = Vector3(.48, maxf(clearance_height - .02, .05), .48)
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


## Touch look (TouchControls.look_turn): radians to turn right (x) and tilt down (y), already scaled by the TOUCH LOOK
## settings, so the mouse sensitivity does not apply twice.
func apply_look_turn(turn: Vector2) -> void:
	if xr_active or look_frozen or input_frozen:
		return
	_yaw -= turn.x
	_pitch = clampf(_pitch - turn.y, -1.4, 1.4)
	if resting_furniture != null:
		note_rest_activity()
	_apply_look_rotation()


func _apply_look_rotation() -> void:
	rotation.y = _yaw
	first_person_pivot.rotation.x = _pitch
	facing = Vector2(-sin(rotation.y), -cos(rotation.y))


func _unhandled_input(event: InputEvent) -> void:
	# Uncaptured relative motion fights the OS cursor on remote/low-FPS
	# desktops. Keyboard look covers that case; mouse look stays capture-only.
	# Phones look with the touch drag (apply_look_turn); the mouse motion Godot emulates from touches is ignored.
	if event is InputEventMouseMotion and xr_active and not look_frozen and not input_frozen:
		rotate_y(-event.relative.x * Settings.mouse_sensitivity)   # a paired mouse turns a headset player; the head looks
		return
	if event is InputEventMouseMotion and not xr_active and not look_frozen \
			and MouseLock.is_captured() and not PlatformProfile.is_phone:
		_yaw -= event.relative.x * Settings.mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * Settings.mouse_sensitivity, -1.4, 1.4)
		if resting_furniture != null:
			if not asleep:
				_clamp_rest_look()
				if event.relative.length() > 2.0:
					note_rest_activity()
			else:
				_yaw = rotation.y
				_pitch = first_person_pivot.rotation.x
		_apply_look_rotation()
	elif event is InputEventKey and event.pressed and not event.echo:
		if resting_furniture != null:
			note_rest_activity()
		var key := (event as InputEventKey).physical_keycode
		if key >= KEY_1 and key <= KEY_4 and shop_resolver.is_valid():
			var message := String(shop_resolver.call(str(key - KEY_1 + 1)))
			if not message.is_empty():
				interaction_message.emit(message)
				return
		if key >= KEY_1 and key <= KEY_5 and inventory_enabled:
			var target_slot := key - KEY_1
			select_inventory_slot(target_slot)
	elif event is InputEventMouseButton and event.pressed and inventory_enabled:
		var button := (event as InputEventMouseButton).button_index
		if button == MOUSE_BUTTON_WHEEL_UP:
			select_inventory_slot(selected_inventory_slot - 1)
		elif button == MOUSE_BUTTON_WHEEL_DOWN:
			select_inventory_slot(selected_inventory_slot + 1)


func is_climbing() -> bool:
	return not ladder_climb.is_empty()


func is_plunging() -> bool:
	return not plunge.is_empty()


## The deliberate waterfall jump (docs/SEWERS.md): from the ledge `from`, an arc into the cistern pool at `land` (its water surface at
## `surface_y`), the splash and a muffled moment, a slow swim to `exit` on the walkway ring (floor height `exit.y`), then SOAKED_SECONDS
## of soaked. Collision is off for the duration; no damage, input is ignored. The level changes by itself as the feet cross the storey.
func begin_plunge(from: Vector3, land: Vector3, exit: Vector3, surface_y: float) -> void:
	if is_plunging() or is_climbing() or hidden or spectator_mode:
		return
	if resting_furniture != null:
		leave_furniture()
	var drop := maxf(from.y - surface_y, .5)
	var fall_seconds := (PLUNGE_HOP_SPEED + sqrt(PLUNGE_HOP_SPEED * PLUNGE_HOP_SPEED + 2.0 * PLUNGE_GRAVITY * drop)) / PLUNGE_GRAVITY
	var bed_y := surface_y - SewerRouteGenerator.CHANNEL_DEPTH - SewerRouteGenerator.WATER_SURFACE
	var swim_distance := Vector2(land.x, land.z).distance_to(Vector2(exit.x, exit.z))
	plunge = {"phase": "fall", "t": 0.0, "from": from, "land": land, "exit": exit, "surface": surface_y,
		"fall_seconds": fall_seconds, "swim_seconds": maxf(2.0, swim_distance / PLUNGE_SWIM_SPEED), "bed": bed_y, "splashed": false}
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	if first_person_items != null:
		first_person_items.visible = false


func _update_plunge(delta: float) -> void:
	var phase := String(plunge["phase"])
	var surface := float(plunge["surface"])
	var wade_y := float(plunge["bed"])    # feet on the bed: the eye just clears the surface
	var from: Vector3 = plunge["from"]
	var land: Vector3 = plunge["land"]
	var exit: Vector3 = plunge["exit"]
	plunge["t"] = float(plunge["t"]) + delta
	var t := float(plunge["t"])
	match phase:
		"fall":
			var d := float(plunge["fall_seconds"])
			var k := clampf(t / d, 0.0, 1.0)
			var y := from.y + PLUNGE_HOP_SPEED * t - .5 * PLUNGE_GRAVITY * t * t
			global_position = Vector3(lerpf(from.x, land.x, k), maxf(y, surface), lerpf(from.z, land.z, k))
			noise = 0.0
			if t >= d:
				plunge["phase"] = "splash"
				plunge["t"] = 0.0
				Sound.splash_big(0.0, 1.2)
				Sound.set_muffled(true)
				emit_noise_burst(PLUNGE_SPLASH_NOISE, PLUNGE_SPLASH_NOISE_SECONDS)
				force_flashlight_flicker(1.4)
				plunge["splashed"] = true
		"splash":
			var k := clampf(t / PLUNGE_SPLASH_SECONDS, 0.0, 1.0)
			global_position = Vector3(land.x, lerpf(surface, wade_y, _smooth(k)), land.z)
			noise = maxf(noise, _noise_burst)
			if t >= PLUNGE_SPLASH_SECONDS:
				plunge["phase"] = "swim"
				plunge["t"] = 0.0
		"swim":
			var d := float(plunge["swim_seconds"])
			var k := clampf(t / d, 0.0, 1.0)
			var bob := sin(t * 3.0) * .04
			global_position = Vector3(lerpf(land.x, exit.x, _smooth(k)), wade_y + bob, lerpf(land.z, exit.z, _smooth(k)))
			noise = PLUNGE_SWIM_NOISE
			if t >= d:
				plunge["phase"] = "climb_out"
				plunge["t"] = 0.0
				plunge["swim_end"] = global_position
				Sound.set_muffled(false)
		"climb_out":
			var k := clampf(t / PLUNGE_CLIMB_OUT_SECONDS, 0.0, 1.0)
			var start: Vector3 = plunge["swim_end"]
			global_position = start.lerp(exit, _smooth(k)) + Vector3(0, sin(k * PI) * .12, 0)
			noise = 0.3
			if t >= PLUNGE_CLIMB_OUT_SECONDS:
				plunge = {}
				collision_layer = 1
				collision_mask = 1
				if first_person_items != null:
					first_person_items.visible = true
				soaked_left = SOAKED_SECONDS
				_drip_left = 1.0
				_clip = "idle"
				plunge_finished.emit(exit)
				return
	velocity = Vector3.ZERO
	_clip = "idle"


func _update_soaked(delta: float) -> void:
	if soaked_left <= 0.0:
		return
	soaked_left = maxf(0.0, soaked_left - delta)
	_drip_left -= delta
	if _drip_left <= 0.0:
		_drip_left = randf_range(SOAKED_DRIP_EVERY.x, SOAKED_DRIP_EVERY.y)
		Sound.water_drip(randf_range(-.3, .3), .35 + .65 * soaked_left / SOAKED_SECONDS)


## Gets onto a sewer ladder (docs/SEWERS.md). The ladder's line runs up from
## `foot` (its base on the lower floor, against the rungs) for `rise` metres;
## the runner mounts at `height` above the foot and from then on climbs under
## their own control: hold move up / move down to climb at CLIMB_SPEED, release
## to hang still. At either end the climb dismounts smoothly onto `top_exit` or
## `bottom_exit` (the floor in front of the ladder); jump near the bottom lets go.
## The camera stays free; movement, items and collision are off on the rungs.
func begin_ladder_climb(foot: Vector3, rise: float, height: float, yaw: float,
		top_exit: Vector3, bottom_exit: Vector3, top_level: int, bottom_level: int) -> void:
	if is_climbing() or hidden or spectator_mode:
		return
	if resting_furniture != null:
		leave_furniture()
	ladder_climb = {"foot": foot, "rise": rise, "height": clampf(height, 0.0, rise),
		"top_exit": top_exit, "bottom_exit": bottom_exit, "top_level": top_level, "bottom_level": bottom_level,
		"phase": "mount", "t": 0.0, "from": global_position, "to_level": top_level, "travel": 0.0}
	velocity = Vector3.ZERO
	rotation.y = yaw
	collision_layer = 0
	collision_mask = 0
	if first_person_items != null:
		first_person_items.visible = false
	_show_climb_hands(true)


## How far up the ladder the runner is, 0 (bottom) .. 1 (top).
func ladder_climb_progress() -> float:
	if ladder_climb.is_empty():
		return 0.0
	return clampf(float(ladder_climb["height"]) / maxf(float(ladder_climb["rise"]), .01), 0.0, 1.0)


func _ladder_point() -> Vector3:
	return Vector3(ladder_climb["foot"]) + Vector3(0, float(ladder_climb["height"]), 0)


func _update_ladder_climb(delta: float) -> void:
	var rise := float(ladder_climb["rise"])
	var moving := false
	match String(ladder_climb["phase"]):
		"mount":
			ladder_climb["t"] = minf(1.0, float(ladder_climb["t"]) + delta / LADDER_MOUNT_SECONDS)
			var k := _smooth(float(ladder_climb["t"]))
			global_position = Vector3(ladder_climb["from"]).lerp(_ladder_point(), k)
			if float(ladder_climb["t"]) >= 1.0:
				ladder_climb["phase"] = "climb"
		"climb":
			# W / stick forward climbs up, S / stick back climbs down; nothing pressed: hang
			var axis := -Input.get_vector("move_left", "move_right", "move_up", "move_down").y
			if input_frozen or stun_timer > 0.0:
				axis = 0.0
			var height := float(ladder_climb["height"])
			var pull := _xr_climb_pull
			_xr_climb_pull = 0.0
			if input_frozen or stun_timer > 0.0:
				pull = 0.0
			if Input.is_action_just_pressed("jump") and height <= LADDER_LET_GO_HEIGHT:
				_ladder_dismount("bottom")
			elif pull > 0.0 and height >= rise:
				_ladder_dismount("top")
			elif pull < 0.0 and height <= 0.0:
				_ladder_dismount("bottom")
			elif pull != 0.0:
				ladder_climb["height"] = clampf(height + pull, 0.0, rise)
				ladder_climb["travel"] = float(ladder_climb["travel"]) + absf(pull)
				moving = true
			elif axis > .2 and height >= rise:
				_ladder_dismount("top")
			elif axis < -.2 and height <= 0.0:
				_ladder_dismount("bottom")
			elif absf(axis) > .2:
				var step := signf(axis) * LADDER_CLIMB_SPEED * delta
				ladder_climb["height"] = clampf(height + step, 0.0, rise)
				ladder_climb["travel"] = float(ladder_climb["travel"]) + absf(step)
				moving = true
			global_position = _ladder_point()
		"dismount":
			ladder_climb["t"] = minf(1.0, float(ladder_climb["t"]) + delta / LADDER_DISMOUNT_SECONDS)
			var k := _smooth(float(ladder_climb["t"]))
			var to: Vector3 = ladder_climb["to"]
			# a small lift over the lip of the hatch on the way off at the top
			var lift := sin(k * PI) * (.25 if bool(ladder_climb["over_top"]) else 0.0)
			global_position = Vector3(ladder_climb["from"]).lerp(to, k) + Vector3(0, lift, 0)
			moving = true
	velocity = Vector3.ZERO
	noise = 0.35 if moving else 0.0   # rungs clank while you move: a hunter near either end hears it
	_clip = "climb"
	ModelSlot.play_if_available(_animation_player, _clip)
	if _animation_player != null:
		_animation_player.speed_scale = 1.0 if moving else 0.0
	_animate_climb_hands(float(ladder_climb["travel"]) / LADDER_CLIMB_SPEED, true)
	if String(ladder_climb["phase"]) == "dismount" and float(ladder_climb["t"]) >= 1.0:
		var to_level := int(ladder_climb["to_level"])
		ladder_climb = {}
		collision_layer = 1
		collision_mask = 1
		_show_climb_hands(false)
		if first_person_items != null:
			first_person_items.visible = true
		if _animation_player != null:
			_animation_player.speed_scale = 1.0
		_clip = "idle"
		ladder_climb_finished.emit(to_level)


func _ladder_dismount(end: String) -> void:
	var top := end == "top"
	ladder_climb["phase"] = "dismount"
	ladder_climb["t"] = 0.0
	ladder_climb["from"] = global_position
	ladder_climb["to"] = ladder_climb["top_exit"] if top else ladder_climb["bottom_exit"]
	ladder_climb["to_level"] = int(ladder_climb["top_level"] if top else ladder_climb["bottom_level"])
	ladder_climb["over_top"] = top


static func _smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


## Two blocky fists gripping rungs in front of the camera, hand over hand.
func _show_climb_hands(on: bool) -> void:
	if _climb_hands == null and on:
		_climb_hands = Node3D.new()
		_climb_hands.name = "ClimbHands"
		var skin := StandardMaterial3D.new()
		skin.albedo_color = Color("d9a98a")
		MaterialLook.tame(skin)
		var sleeve := StandardMaterial3D.new()
		sleeve.albedo_color = Color("3a4250")
		MaterialLook.tame(sleeve)
		for side in [-1.0, 1.0]:
			var arm := Node3D.new()
			arm.name = "L" if side < 0.0 else "R"
			var forearm := MeshInstance3D.new()
			var forearm_mesh := BoxMesh.new()
			forearm_mesh.size = Vector3(.07, .07, .26)
			forearm.mesh = forearm_mesh
			forearm.material_override = sleeve
			forearm.position = Vector3(0, -.02, .13)
			arm.add_child(forearm)
			var fist := MeshInstance3D.new()
			var fist_mesh := BoxMesh.new()
			fist_mesh.size = Vector3(.085, .085, .09)
			fist.mesh = fist_mesh
			fist.material_override = skin
			arm.add_child(fist)
			for child in arm.get_children():
				(child as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			arm.position = Vector3(.16 * side, -.1, -.34)
			_climb_hands.add_child(arm)
		first_person_camera.add_child(_climb_hands)
	if _climb_hands != null:
		_climb_hands.visible = on


func _animate_climb_hands(elapsed: float, up: bool) -> void:
	if _climb_hands == null:
		return
	var phase := elapsed * TAU * (1.0 if up else -1.0)
	for arm_value in _climb_hands.get_children():
		var arm := arm_value as Node3D
		var side := -1.0 if arm.name == "L" else 1.0
		var reach := sin(phase + (0.0 if side < 0.0 else PI))
		arm.position = Vector3(.16 * side, -.1 + .12 * reach, -.34 + .03 * absf(reach))
		arm.rotation.x = -.35 * reach


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
	admin_speed_scale = 1.0
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
	spectator_follow_valid = false
	velocity = Vector3.ZERO
	collision_layer = 1
	collision_mask = 1
	if player_collision != null:
		player_collision.disabled = false
	if body_visual != null:
		body_visual.visible = true


func _update_spectator(delta: float) -> void:
	if spectator_follow_valid:
		var forward := -active_camera().global_basis.z
		forward.y = 0.0
		forward = forward.normalized() if forward.length_squared() > 0.001 else Vector3.FORWARD
		var wanted := spectator_follow_at + Vector3.UP * 1.3 - forward * 3.0
		global_position = global_position.lerp(wanted, clampf(delta * 8.0, 0.0, 1.0))
		velocity = Vector3.ZERO
		noise = 0.0
		_clip = "idle"
		ModelSlot.play_if_available(_animation_player, _clip)
		return
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


func begin_outage(system: String, seconds: float) -> void:
	outage_system = system
	outage_left = maxf(seconds, 0.0)
	if system == "flashlight" and flashlight_enabled:
		_set_flashlight(false)


func system_offline(system: String) -> bool:
	return outage_left > 0.0 and outage_system == system


func _physics_process(delta: float) -> void:
	if outage_left > 0.0:
		outage_left = maxf(0.0, outage_left - delta)
		if outage_left <= 0.0:
			outage_system = ""
	_update_controller_look(delta)
	_update_soaked(delta)
	_noise_burst_timer = maxf(0.0, _noise_burst_timer - delta)
	_update_viewmodel_push(delta)
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
	if not ladder_climb.is_empty():
		_update_ladder_climb(delta)
		return
	if not plunge.is_empty():
		_update_plunge(delta)
		return
	if resting_furniture != null and not is_instance_valid(resting_furniture):
		# An admin teleport can evict the furniture's streamed chunk while the
		# player is resting. Recover rather than freezing on a freed reference.
		resting_furniture = null
		resting_pose = ""
		global_position = _furniture_return_position
		first_person_pivot.position.y = _standing_camera_height
	if not _rest_ease.is_empty() and bool(_rest_ease["leaving"]):
		velocity = Vector3.ZERO
		_advance_rest_ease(delta)
		_update_sleep(delta)
		return
	if resting_furniture != null:
		velocity = Vector3.ZERO
		noise = 0.0
		_clip = resting_pose
		ModelSlot.play_if_available(_animation_player, _clip)
		if not _rest_ease.is_empty():
			_advance_rest_ease(delta)
		_update_sleep(delta)
		if Input.is_action_just_pressed("interact"):
			if asleep:
				interaction_message.emit(wake_from_sleep("AWAKE"))
			else:
				interaction_message.emit(leave_furniture())
		elif Input.is_action_just_pressed("jump") and resting_pose == "lay":
			interaction_message.emit(toggle_sleep())
		return
	if _sleep_fade > 0.0 or drowsiness > 0.0:
		_update_sleep(delta)
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
		if not _hide_move.is_empty():
			_advance_hide_move(delta)
			return
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
	if movement_locked:
		input_vector = Vector2.ZERO
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

	movement_speed *= admin_speed_scale

	noise = 0.0 if not is_moving else (GameConfig.NOISE_CROUCH if movement_mode == "crouch" else (GameConfig.NOISE_SPRINT if is_sprinting else GameConfig.NOISE_WALK))
	if _noise_burst_timer > 0.0:
		noise = maxf(noise, _noise_burst)
	if soaked_left > 0.0:
		noise *= SOAKED_NOISE_SCALE

	meters.update(delta, {
		"flashlight_on": flashlight_enabled,
		"noise": noise,
		"crouching": movement_mode == "crouch",
		"hidden": hidden,
		"in_safe_zone": is_in_safe_zone(),
		"heater_on": heater_on and not system_offline("climate"),
	})

	_update_stamina(delta, is_sprinting)
	_update_lamp(delta, is_sprinting)
	# Keep "crouch" as network/gameplay state, but retire the imported pose:
	# its knees and elbows fold backward. A smooth fade now communicates quiet
	# movement while the stable idle pose keeps the body human-shaped.
	_clip = "crouch" if movement_mode == "crouch" else (
		movement_mode if is_moving else "idle")
	_airborne_time = 0.0 if is_on_floor() else _airborne_time + delta   # ramps and stairs briefly leave the floor
	# The blocky player rig also has stun / jump / fall clips; rigs without them keep the movement clip.
	if stun_timer > 0.0:
		_clip = "stun"
	elif _airborne_time > .18 and not in_vent:
		_clip = "fall" if velocity.y < -1.0 else "jump"
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
		xr_comfort.step(delta, move_direction.length_squared() > 0.0)
		xr_hands.step(delta)
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
		floor_snap_length = FLOOR_SNAP
		_update_vertical_motion(delta, movement_mode != "crouch")
	_move_and_resolve_landing()
	_update_camera_pose(delta, is_moving and is_on_floor(), is_sprinting,
		movement_mode == "crouch")
	if is_moving and is_on_floor():
		Sound.footstep(movement_mode, footstep_surface)


	_update_troll(delta)
	_update_flashlight_flicker(delta)
	if Input.is_action_just_pressed("flashlight") and owns_inventory_item("flashlight") \
			and not flashlight_seized():
		select_inventory_slot(inventory_order.find("flashlight"))
		if lamp_charge <= 0.0 and not flashlight_enabled:
			Sound.light_switch()    # an empty flashlight just clicks
		_set_flashlight(not flashlight_enabled)
	# Left click acts only while the cursor was already captured last frame too: the click that re-captures the
	# mouse (after focus loss or a menu) and clicks on open menus never swing, spend or blip.
	var click_ready := xr_active or (_cursor_was_captured and MouseLock.is_captured())
	_cursor_was_captured = MouseLock.is_captured()
	if inventory_enabled:
		if inventory_enabled and Input.is_action_just_pressed("taser") and owns_inventory_item("taser"):
			_fire_taser()
		if Input.is_action_just_pressed("tool_use") and click_ready and not movement_locked:
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


var _cursor_was_captured := false


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
	var wants_to_jump := jump_enabled and not movement_locked and (_jump_requested or Input.is_action_just_pressed("jump"))
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


## A turning platform (CarouselRide3D) carries the player: the view turns with it.
func rotate_with_platform(angle: float) -> void:
	_yaw += angle
	_apply_look_rotation()


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


## Fades the headset in from black (after the spawn settles; see _try_enter_xr).
func reveal_xr_view() -> void:
	if xr_fade != null and is_instance_valid(xr_fade):
		xr_fade.fade_to(0.0)


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
	# The headset renders from the CURRENT XROrigin3D. The menu panel (XRMenuPanel) has its own; unless this one takes
	# over, the route is drawn from that origin, i.e. world (0, 0, 0), a corner between rooms, not from the runner.
	xr_origin.current = true
	get_viewport().use_xr = true
	first_person_camera.current = false
	xr_camera.current = true
	# Comfort (XRFade): the route starts black and fades in once the spawn has settled (reveal_xr_view), so the eye never
	# sees the world stream in or the spawn move; a fallback fades in anyway.
	xr_fade = XRFade.attach(xr_camera, 1.0)
	get_tree().create_timer(XR_REVEAL_FALLBACK_SECONDS).timeout.connect(reveal_xr_view)
	body_visual.visible = false
	# Desktop viewmodels are camera-framed props, not world-scale VR hands.
	# Hide them in OpenXR until controller-held models get their own pass.
	if first_person_items:
		first_person_items.visible = false
	MouseLock.set_gameplay_capture(false)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	xr_comfort = XRComfort.new()
	xr_comfort.name = "XRComfort"
	add_child(xr_comfort)
	xr_comfort.setup(self, xr_origin, xr_camera, xr_left, xr_right)
	xr_hands = XRHands.new()
	xr_hands.name = "XRHands"
	add_child(xr_hands)
	xr_hands.setup(self, xr_origin, xr_left, xr_right)
	if OS.is_debug_build():
		get_tree().create_timer(5.0).timeout.connect(_xr_smoke_log)
	return true


## Debug builds on a headset: one line of XR state five seconds after entering XR (docs/XR_ANDROID.md, device smoke
## log): whether XR is on, the controller trackers and poses OpenXR really offers, whether the hands track, where the
## head is relative to the body, and whether the panels exist. Read it with adb logcat | grep XR_SMOKE.
func _xr_smoke_log() -> void:
	var trackers := []
	for key in XRServer.get_trackers(XRServer.TRACKER_CONTROLLER):
		var tracker := XRServer.get_tracker(key) as XRPositionalTracker
		var poses := []
		for pose_name in ["default", "default_pose", "aim", "aim_pose", "grip", "grip_pose"]:
			if tracker != null and tracker.has_pose(pose_name):
				poses.append(pose_name)
		trackers.append("%s%s" % [key, poses])
	var head := xr_camera.global_position - global_position
	print("XR_SMOKE xr_active=%s trackers=%s left=[%s %s tracked=%s] right=[%s %s tracked=%s] head_offset=%s horizontal=%.2f world_scale=%.3f wrist=%s route_panel=%s" % [
		xr_active, trackers, xr_left.tracker, xr_left.pose, xr_left.get_has_tracking_data(),
		xr_right.tracker, xr_right.pose, xr_right.get_has_tracking_data(), head, Vector2(head.x, head.z).length(),
		xr_origin.world_scale, xr_comfort != null and xr_comfort.wrist != null and xr_comfort.wrist.is_visible_in_tree(),
		get_tree().root.find_children("XRRoutePanel", "", true, false).size()])
	for panel in get_tree().root.find_children("XRRoutePanel", "", true, false):
		print("XR_SMOKE_PANEL canvas=%s root=%s" % [(panel as XRRoutePanel).canvas_size(), get_viewport().get_visible_rect().size])
	var cell := Vector2(fposmod(global_position.x, GameConfig.TILE_SIZE), fposmod(global_position.z, GameConfig.TILE_SIZE))
	var blocked := spot_blocked(global_position)
	print("XR_SMOKE_SEED %s yaw=%.3f origin_current=%s" % [RoomState.seed_text, rotation.y, xr_origin.current])
	print("XR_SMOKE_PLACE body=%s camera=%s origin=%s cell_offset=%s origin_parent=%s body_blocked=%s" % [global_position,
		xr_camera.global_position, xr_origin.global_position, cell, xr_origin.get_parent().name, blocked])
	var eye := xr_camera.global_position
	for node in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var shape := node as GeometryInstance3D
		if not shape.is_visible_in_tree() or not (shape.global_transform * shape.get_aabb()).grow(0.35).has_point(eye):
			continue
		var many := shape as MultiMeshInstance3D
		if many != null and many.multimesh != null and many.multimesh.mesh != null:
			for i in many.multimesh.instance_count:
				var box := many.global_transform * many.multimesh.get_instance_transform(i) * many.multimesh.mesh.get_aabb()
				if box.grow(0.35).has_point(eye):
					print("XR_SMOKE_NEAR_EYE %s #%d aabb=%s" % [shape.name, i, box])
		elif (shape.global_transform * shape.get_aabb()).size.length() < 20.0:
			print("XR_SMOKE_NEAR_EYE %s aabb=%s" % [shape.get_path(), shape.global_transform * shape.get_aabb()])
	var cell_kind := "unknown"
	var facility := get_tree().root.find_child("StreamedFacility", true, false)
	if facility != null and facility.get("generator") != null:
		var generator = facility.get("generator")
		var size: int = generator.CHUNK_SIZE
		var coord := Vector3i(floori(global_position.x / size), 0, floori(global_position.z / size))
		var grid: Array = generator.chunk(coord).get("grid", [])
		var local := Vector2i(posmod(floori(global_position.x), size), posmod(floori(global_position.z), size))
		if local.y < grid.size() and local.x < (grid[local.y] as Array).size():
			cell_kind = "open" if int(grid[local.y][local.x]) == 0 else "wall"
	var clearance := INF
	var space := get_world_3d().direct_space_state
	for i in 16:
		var direction := Vector3(cos(TAU * i / 16.0), 0, sin(TAU * i / 16.0))
		var from := global_position + Vector3.UP * 1.0
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + direction * 3.0, collision_mask, [get_rid()]))
		if not hit.is_empty():
			clearance = minf(clearance, from.distance_to(hit["position"]))
	print("XR_SMOKE_CELL kind=%s clearance=%.2f" % [cell_kind, clearance])
	var problems := []
	if cell_kind != "open":
		problems.append("the body stands on a %s cell" % cell_kind)
	if clearance < 0.4:
		problems.append("a wall is %.2f m from the body" % clearance)
	if not xr_active:
		problems.append("xr_active is false")
	for hand in [xr_left, xr_right]:
		if XRServer.get_tracker(hand.tracker) == null:
			problems.append("no OpenXR tracker named %s" % hand.tracker)
		elif not hand.get_has_tracking_data():
			problems.append("%s not tracked (controller asleep?)" % hand.tracker)
	if Vector2(head.x, head.z).length() > 0.3:
		problems.append("head %.2f m from the body" % Vector2(head.x, head.z).length())
	if blocked:
		problems.append("the body is inside level geometry or off the floor")
	if not xr_origin.current:
		problems.append("the runner's XROrigin3D is not the current origin (the headset renders from another one)")
	var render_origin := XRServer.world_origin.origin
	print("XR_SMOKE_WORLD_ORIGIN %s" % render_origin)
	if Vector2(render_origin.x - global_position.x, render_origin.z - global_position.z).length() > 0.3:
		problems.append("the headset renders from %s, not the body" % render_origin)
	var marker := get_tree().root.find_child("StartingSafeZoneMarker", true, false) as Node3D
	if marker != null and Vector2(marker.global_position.x - global_position.x, marker.global_position.z - global_position.z).length() < 0.6:
		problems.append("the body stands on the safe-zone marker post")
	if get_tree().root.find_children("XRRoutePanel", "", true, false).is_empty():
		problems.append("no route panel")
	print("XR_SMOKE_RESULT %s" % ("PASS" if problems.is_empty() else "FAIL: " + ", ".join(problems)))


func _connect_xr_buttons() -> void:
	for hand in [xr_left, xr_right]:
		hand.show_when_tracked = true   # a sleeping or absent controller hides its hand, laser and wrist instead of lying on the floor
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
		"primary_click":
			if not xr_left.get_has_tracking_data():
				_emit_xr_action_event("pause", true)   # right hand only: the stick click opens the menu
				_emit_xr_action_event("pause", false)
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
		"ax_button":
			if InputMap.has_action("quick_chat"):   # registered by RoomChat in co-op scenes
				_emit_xr_action_event("quick_chat", true)   # hold X and tilt the stick to pick a quick-chat preset
		"trigger_click":
			Input.action_press("taser")
		"primary_click":
			Input.action_press("crouch")
		"by_button":
			Input.action_press("toggle_map")
		"grip_click":
			Input.action_press("tool_use")
		"menu_button":
			_emit_xr_action_event("pause", true)


func _on_xr_left_released(action: StringName) -> void:
	match String(action):
		"ax_button":
			if InputMap.has_action("quick_chat"):
				_emit_xr_action_event("quick_chat", false)
		"trigger_click":
			Input.action_release("taser")
		"primary_click":
			Input.action_release("crouch")
		"by_button":
			Input.action_release("toggle_map")
		"grip_click":
			Input.action_release("tool_use")
		"menu_button":
			_emit_xr_action_event("pause", false)


func _emit_xr_action_event(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)


func _update_stamina(delta: float, is_sprinting: bool) -> void:
	if admin_god_mode:
		stamina = GameConfig.MAX_STAMINA
		stamina_recovery_delay = 0.0
		exhausted = false
		return
	if is_sprinting:
		stamina = maxf(0.0, stamina - GameConfig.STAMINA_SPRINT_DRAIN \
			* (GameConfig.TROLL_STAMINA_DRAIN_SCALE if troll_active else 1.0) * delta)
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
	if not flashlight_enabled or not inventory_enabled:
		return   # the built-in flashlight of an item-less game never drains
	var difficulty := RoomState.difficulty_profile()
	var drain := GameConfig.LAMP_IDLE_DRAIN * float(difficulty["lamp_drain"])
	if is_sprinting:
		drain += GameConfig.LAMP_SPRINT_DRAIN * float(difficulty["sprint_drain"])
	lamp_charge = maxf(0.0, lamp_charge - drain * meters.drain_scale() * delta)
	_save_active_flashlight_charge()
	if lamp_charge <= 0.0:
		# KT: the flashlight never breaks. An empty one sputters out and stays in its slot until a battery recharges it.
		_set_flashlight(false)
		Sound.light_switch()
		interaction_message.emit("FLASHLIGHT DEAD // FIND A BATTERY")


func _update_troll(delta: float) -> void:
	if not troll_active:
		return
	_troll_step_in -= delta
	if _troll_step_in > 0.0:
		return
	_troll_step_in = randf_range(GameConfig.TROLL_FAKE_STEP_SECONDS.x, GameConfig.TROLL_FAKE_STEP_SECONDS.y)
	Sound.hunter_footstep(randf_range(-1.0, 1.0), randf_range(.05, .12))
	if flashlight_enabled:
		force_flashlight_flicker(randf_range(.4, 1.2))


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
		and lamp_charge > 0.0 and not system_offline("flashlight")
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
	# smaller hands: the held items shrink with her
	first_person_items.scale = Vector3.ONE * PlayerModels.SCALE
	first_person_camera.add_child(first_person_items)

	flashlight_view = Node3D.new()
	flashlight_view.name = "FlashlightView"
	flashlight_view.position = HeldItemPoses.first_person_hand("flashlight")
	first_person_items.add_child(flashlight_view)
	_add_authored_item_model(flashlight_view, "flashlight", .50)

	taser_view = Node3D.new()
	taser_view.name = "TaserView"
	taser_view.position = HeldItemPoses.first_person_hand("taser")
	first_person_items.add_child(taser_view)
	_add_authored_item_model(taser_view, "taser", .50)
	taser_view.visible = false

	_build_utility_view("lockpick")
	_build_utility_view("crowbar")
	_build_utility_view("rescue_axe")
	_build_utility_view("battery")
	for view in [flashlight_view, taser_view] + tool_views.values():
		_add_first_person_hand(view as Node3D)
	_refresh_inventory_view()


## First-person hands (docs/RESCUE_AXE.md): the mannequin's own right forearm and hand (same meshes, atlas and player
## hue as the body), with the hand's prop point (R-HandProp) on the held item's grip, the view origin, and the forearm
## running back and down toward the camera. `first_person_hands` turns them off (held items only).
static var first_person_hands := true
const FP_HAND_SCALE := .37          # mannequin units -> camera space, matched to the held items' scale
const FP_ARM_TILT := 118.0          # degrees: the forearm comes up from below-behind into the grip
static var _fp_hand_parts: Array = []   # classic arms: [[mesh, material_override or null, transform relative to R-HandProp], ...]
static var _fp_hand_parts_slim: Array = []   # the same from the slim (Alex) mannequin


static func _mannequin_hand_parts(slim: bool = false) -> Array:
	var cache: Array = _fp_hand_parts_slim if slim else _fp_hand_parts
	if not cache.is_empty():
		return cache
	var scene := load((PlayerModels.BLOCKY_SLIM if slim else PlayerModels.BLOCKY).replace(".tscn", ".glb")) as PackedScene
	if scene == null:
		return []
	var root := scene.instantiate()
	var prop := root.find_child("R-HandProp", true, false) as Node3D
	if prop != null:
		var prop_xf := _local_to(root, prop)
		for part_name in ["R-Forearm", "R-Hand"]:
			var part := root.find_child(part_name, true, false) as MeshInstance3D
			if part != null:
				cache.append([part.mesh, part.material_override, prop_xf.affine_inverse() * _local_to(root, part)])
	root.free()
	return cache


static func _local_to(root: Node, node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var at: Node = node
	while at != null and at != root:
		if at is Node3D:
			xf = (at as Node3D).transform * xf
		at = at.get_parent()
	return xf


func _add_first_person_hand(view: Node3D) -> void:
	var parts := _mannequin_hand_parts(Settings.effective_slim())
	if parts.is_empty():
		return
	var hand := Node3D.new()
	hand.name = "FirstPersonHand"
	hand.set_meta("slim", Settings.effective_slim())
	hand.basis = Basis(Vector3.RIGHT, deg_to_rad(FP_ARM_TILT)).scaled(Vector3.ONE * FP_HAND_SCALE)
	for part_value in parts:
		var part: Array = part_value
		var mesh_node := MeshInstance3D.new()
		mesh_node.mesh = part[0]
		if part[1] != null:
			mesh_node.material_override = part[1]
		mesh_node.transform = part[2]
		mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hand.add_child(mesh_node)
	ModelSlot.apply_character_hue(hand, Settings.player_hue_degrees)
	PlayerSkin.apply(hand, PlayerSkin.active_texture())
	hand.visible = first_person_hands
	view.add_child(hand)


func set_first_person_hands(on: bool) -> void:
	first_person_hands = on
	if first_person_items == null:
		return
	for hand in first_person_items.find_children("FirstPersonHand", "Node3D", true, false):
		(hand as Node3D).visible = on


func _build_utility_view(item_id: String) -> void:
	var view := Node3D.new()
	view.name = "%sView" % item_id.to_pascal_case()
	view.position = HeldItemPoses.first_person_hand(item_id)
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
		if HeldItemPoses.FIRST_PERSON.has(item_id):
			# held by the grip, which is the view's origin: swings and the push-back pivot around the handle
			model.transform = HeldItemPoses.first_person_transform(item_id)
		else:
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


## The first time the shadowed SpotLight becomes visible the renderer compiles its shader variants and allocates the
## positional shadow atlas, a long frame. Do that once right after spawning, at zero energy, so the player's first
## toggle (and every later one) only flips visibility.
func _warm_flashlight() -> void:
	if flashlight == null:
		return
	for _i in 2:
		await get_tree().process_frame
	if flashlight == null or flashlight.visible:
		return
	var energy := flashlight.light_energy
	flashlight.light_energy = 0.0
	flashlight.visible = true
	for _i in 3:
		await get_tree().process_frame
	if flashlight == null:
		return
	flashlight.light_energy = energy
	flashlight.visible = _flashlight_beam_should_be_visible()


func _flashlight_beam_should_be_visible() -> bool:
	return flashlight_enabled and selected_inventory_item() == "flashlight"


## Network peers need the camera pitch as well as the controller body's yaw.
## Publishing only rotation.y made another runner's light stay horizontal when
## they looked up/down, and mounting the replicated SpotLight on their torso
## then let the mannequin shadow its own beam.
func equipment_aim_direction() -> Vector3:
	var source_basis := first_person_camera.global_basis
	if xr_active:
		source_basis = xr_left.global_basis if xr_left.get_has_tracking_data() else xr_camera.global_basis
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
	taser_cooldown = GameConfig.profile_value(RoomState.difficulty_id(), "taser_cooldown")
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
	if not inventory_enabled:
		return false
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
	if not inventory_enabled:
		return false
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
	if not inventory_enabled:
		return false
	if input_frozen or stun_timer > 0.0:
		return false
	var item_id := selected_inventory_item()
	if item_id.is_empty():
		return false   # nothing in hand: dropping is silent
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
		"level": StreamedFacilityView3D.snapped_level_for_world_y(global_position.y),
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
		return   # empty hand: a click with nothing to use is silent
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
		return   # lamp already full: nothing to do, no blip
	var used_slot := selected_inventory_slot
	if used_slot < 0 or used_slot >= inventory_order.size() \
			or String(inventory_order[used_slot]) != "battery":
		return
	remove_inventory_item("battery", used_slot)
	restore_lamp(GameConfig.BATTERY_RECHARGE)
	Sound.recharge(GameConfig.BATTERY_RECHARGE)


func _use_selected_tool() -> void:
	if input_frozen or stun_timer > 0.0:
		return
	var item_id := selected_inventory_item()
	if not BREACH_TOOLS.has(item_id) and not LOCK_TOOLS.has(item_id):
		return   # not a tool: a click with it is silent
	if Time.get_ticks_msec() < _swing_busy_until_msec:
		return   # mid-swing
	var target := _tool_target()
	var context := tool_context_probe.is_valid() and bool(tool_context_probe.call(item_id))
	if target != null and not _tool_fits_target(item_id, target):
		# a target is right there but this tool cannot work it: say why, spend nothing
		target.activate_with_tool(self, item_id, false)
		Sound.interaction_fail()
		return
	if target == null and not context:
		# nothing to work: the axe and crowbar still swing (a whoosh), everything else stays silent
		if HeldItemPoses.SWINGS.has(item_id):
			_begin_tool_swing(item_id, false)
		return
	# A committed swing spends durability before any hit result. This makes ally hits cost the tool without ever creating friendly-fire damage.
	if not consume_item_durability(item_id, int(TOOL_SWING_COST.get(item_id, 1))):
		Sound.interaction_fail()
		return
	_begin_tool_swing(item_id, true)
	tool_used.emit(item_id)
	if target != null:
		var impact_delay := _swing_impact_delay(item_id)
		if impact_delay > 0.0:
			await get_tree().create_timer(impact_delay).timeout
		if is_instance_valid(target) and is_inside_tree():
			target.activate_with_tool(self, item_id, true)
			if target.last_activation_failed:
				Sound.interaction_fail()


## The boarded path or locked cache the player is aiming at, or null.
func _tool_target() -> RouteInteractable3D:
	var target := _nearest_interactable()
	if target != null and (target.kind == RouteInteractable3D.Kind.BOARDED_PATH \
			or (target.kind == RouteInteractable3D.Kind.RELAY and target.locked_cache)):
		return target
	return null


func _tool_fits_target(item_id: String, target: RouteInteractable3D) -> bool:
	if target.kind == RouteInteractable3D.Kind.BOARDED_PATH:
		return BREACH_TOOLS.has(item_id)
	return LOCK_TOOLS.has(item_id)


func _swing_impact_delay(item_id: String) -> float:
	var swing: Dictionary = HeldItemPoses.SWINGS.get(item_id, {})
	return float(swing.get("windup", 0.0)) + float(swing.get("strike", 0.0))


## Starts a swing: first-person arc around the grip, the replicated counter for everyone else, and (on a hit) noise, thud, debris and a light
## camera kick timed to the end of the strike. Any caller (a board, a grabbed teammate, the escape struggle) goes through here.
func _begin_tool_swing(item_id: String, hit: bool) -> void:
	_animate_tool_use(item_id)
	var swing: Dictionary = HeldItemPoses.SWINGS.get(item_id, {})
	var total := float(swing.get("windup", 0.0)) + float(swing.get("strike", 0.0)) + float(swing.get("recover", 0.0))
	_swing_busy_until_msec = Time.get_ticks_msec() + int(total * 1000.0) if not swing.is_empty() else 0
	tool_swing_seq += 1
	tool_swing_item = item_id
	tool_swing_hit = hit
	if swing.is_empty():
		return
	if item_id == "rescue_axe":
		Sound.axe_swing()
	if not hit:
		return
	await get_tree().create_timer(_swing_impact_delay(item_id)).timeout
	if not is_inside_tree():
		return
	if item_id == "rescue_axe":
		Sound.axe_chop()
		emit_noise_burst(AXE_NOISE, AXE_NOISE_SECONDS)
	else:
		Sound.door_breach()
	spawn_chop_debris()
	kick_view(.012 if item_id == "rescue_axe" else .006)


## The rescue axe cutting its owner out of a hunter's hold (input is frozen then, so this bypasses the normal use gate).
func swing_axe_for_escape() -> void:
	_swing_busy_until_msec = 0
	_begin_tool_swing("rescue_axe", true)


func emit_noise_burst(level: float, seconds: float) -> void:
	_noise_burst = maxf(_noise_burst if _noise_burst_timer > 0.0 else 0.0, level)
	_noise_burst_timer = maxf(_noise_burst_timer, seconds)
	noise = maxf(noise, _noise_burst)


## Wood chips and dust where the tool lands, in front of the camera.
func spawn_chop_debris() -> void:
	var camera := active_camera()
	if camera == null or DisplayServer.get_name() == "headless":
		return
	var chips := CPUParticles3D.new()
	chips.name = "ChopDebris"
	chips.one_shot = true
	chips.amount = 18
	chips.lifetime = .55
	chips.explosiveness = 1.0
	chips.emitting = false
	var chip_mesh := BoxMesh.new()
	chip_mesh.size = Vector3(.045, .018, .018)
	chips.mesh = chip_mesh
	var chip_material := StandardMaterial3D.new()
	chip_material.albedo_color = Color("9a6b3c")
	chips.material_override = chip_material
	chips.direction = Vector3(0, .6, 1)
	chips.spread = 55.0
	chips.initial_velocity_min = 1.6
	chips.initial_velocity_max = 3.4
	chips.gravity = Vector3(0, -9.0, 0)
	chips.angular_velocity_min = -360.0
	chips.angular_velocity_max = 360.0
	chips.top_level = true
	get_tree().current_scene.add_child(chips)
	chips.global_position = camera.global_position - camera.global_basis.z * 1.15 - Vector3(0, .25, 0)
	chips.look_at(chips.global_position + camera.global_basis.z, Vector3.UP)
	chips.restart()
	chips.emitting = true
	get_tree().create_timer(1.2).timeout.connect(chips.queue_free)


## A short camera nudge (screen shake) that settles on its own; never touches the look direction.
func kick_view(amount: float) -> void:
	if first_person_camera == null or xr_active:
		return
	var tween := create_tween().set_trans(Tween.TRANS_SINE)
	tween.tween_property(first_person_camera, "v_offset", -amount, .05)
	tween.parallel().tween_property(first_person_camera, "h_offset", amount * .6, .05)
	tween.tween_property(first_person_camera, "v_offset", 0.0, .16)
	tween.parallel().tween_property(first_person_camera, "h_offset", 0.0, .16)


## Keeps the viewmodel out of walls: when geometry is close in front of the camera the whole hand slides back (and drops a little) instead of
## the tool head poking through.
func _update_viewmodel_push(delta: float) -> void:
	if first_person_items == null or first_person_camera == null or not first_person_items.visible:
		return
	var origin := first_person_camera.global_position
	var forward := -first_person_camera.global_basis.z
	var query := PhysicsRayQueryParameters3D.create(origin, origin + forward * VIEWMODEL_PUSH_RANGE, 1)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var wanted := 0.0
	if not hit.is_empty():
		wanted = viewmodel_push_for(origin.distance_to(hit["position"] as Vector3),
			float(HeldItemPoses.REACH.get(selected_inventory_item(), .95)))
	_viewmodel_push = move_toward(_viewmodel_push, wanted, delta * 3.0 if wanted > _viewmodel_push else delta * 1.4)
	first_person_items.position = viewmodel_offset(_viewmodel_push)


## How far the hand slides back when a wall is `wall_distance` in front of the camera and the held model reaches `reach` forward.
static func viewmodel_push_for(wall_distance: float, reach: float) -> float:
	return clampf(reach - wall_distance + .04, 0.0, VIEWMODEL_MAX_PUSH)


static func viewmodel_offset(push: float) -> Vector3:
	return Vector3(0.0, -push * .25, push)


func _animate_tool_use(item_id: String) -> void:
	var view := tool_views.get(item_id) as Node3D
	if view == null:
		return
	if _tool_item_tween and _tool_item_tween.is_valid():
		_tool_item_tween.kill()
	var hand := HeldItemPoses.first_person_hand(item_id)
	view.position = hand
	view.rotation = Vector3.ZERO
	var swing: Dictionary = HeldItemPoses.SWINGS.get(item_id, {})
	_tool_item_tween = create_tween().set_trans(Tween.TRANS_QUAD)
	if swing.is_empty():
		_tool_item_tween.tween_property(view, "rotation:z", -.72, .09)
		_tool_item_tween.parallel().tween_property(view, "position",
			hand + Vector3(-.10, .04, -.06), .09)
		_tool_item_tween.tween_property(view, "rotation:z", 0.0, .16)
		_tool_item_tween.parallel().tween_property(view, "position", hand, .16)
		return
	# overhead arc around the grip: head back and up, then down through the target, then settle
	var arc := deg_to_rad(float(swing["arc"]))
	_tool_item_tween.tween_property(view, "rotation:x", arc * .70, float(swing["windup"]))\
		.set_ease(Tween.EASE_OUT)
	_tool_item_tween.parallel().tween_property(view, "position", hand + Vector3(.02, .05, .06),
		float(swing["windup"]))
	_tool_item_tween.tween_property(view, "rotation:x", -arc * 1.15, float(swing["strike"]))\
		.set_ease(Tween.EASE_IN)
	_tool_item_tween.parallel().tween_property(view, "position", hand + Vector3(-.03, -.05, -.12),
		float(swing["strike"]))
	_tool_item_tween.tween_property(view, "rotation:x", 0.0, float(swing["recover"]))\
		.set_ease(Tween.EASE_OUT)
	_tool_item_tween.parallel().tween_property(view, "position", hand, float(swing["recover"]))


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


## Whether the capsule would sit inside level geometry at `at` (feet position), or has no floor under it.
func spot_blocked(at: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = player_collision.shape
	query.transform = Transform3D(player_collision.global_basis, at + (player_collision.global_position - global_position))
	query.exclude = [get_rid()]
	query.collision_mask = collision_mask
	if not space.intersect_shape(query, 1).is_empty():
		return true
	var floor_ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at + Vector3.DOWN * 0.6, collision_mask, [get_rid()])
	return space.intersect_ray(floor_ray).is_empty()


## A clear spot for the runner near `at`: `at` itself if the capsule fits there on a floor (and it is at least
## `avoid_distance` from `avoid`), else the nearest cell centre (the route's 1 m grid) within `radius` cells that is.
## The route spawn sits on the starting safe-zone marker post, which has no collider: a headset camera started inside
## it ("between four rooms"), so the spawn avoids it.
func clear_spot_near(at: Vector3, radius := 4, avoid := Vector3.INF, avoid_distance := 0.0) -> Vector3:
	var near_avoid := func(spot: Vector3) -> bool:
		return avoid != Vector3.INF and Vector2(spot.x - avoid.x, spot.z - avoid.z).length() < avoid_distance
	if not spot_blocked(at) and not near_avoid.call(at):
		return at
	var cell := Vector2i(floori(at.x), floori(at.z))
	var best := at
	var best_distance := INF
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var candidate := Vector3(cell.x + dx + 0.5, at.y, cell.y + dz + 0.5)
			var distance := Vector2(candidate.x - at.x, candidate.z - at.z).length()
			if distance < best_distance and not near_avoid.call(candidate) and not spot_blocked(candidate):
				best = candidate
				best_distance = distance
	return best


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
	if resting_furniture != null:
		# resting: what you can do from here, never the "LIE DOWN" of the furniture you are on
		if asleep:
			return "ASLEEP // %s WAKE" % InputGlyphs.key("jump")
		if resting_pose == "lay":
			return "LYING DOWN // %s SLEEP // %s GET UP" % [InputGlyphs.key("jump"), InputGlyphs.key("interact")]
		return "SEATED // %s" % InputGlyphs.prompt("interact", "STAND")
	if hidden:
		if hiding_lock_timer > 0.0:
			return "LOCKED IN // %ds" % ceili(hiding_lock_timer)
		return InputGlyphs.prompt("interact", "LEAVE")
	if is_climbing():
		return InputGlyphs.climb_prompt(float(ladder_climb.get("height", 0.0)) <= LADDER_LET_GO_HEIGHT)
	var percent := resecure_percent()
	if percent >= 0:
		return "RESTORING SIGNAL // %d%%" % percent
	var target := _nearest_interactable()
	if target != null:
		var prompt: String = target.get_prompt()
		# Generic development interactables ("USE") add nothing; every other prompt names its action and gets the key
		# for the active device: "[E] HIDE", "[E] OPEN DOOR", "HOLD [E] RESTORE SABOTAGED RELAY".
		if prompt.strip_edges().to_upper() == "USE":
			prompt = ""
		if prompt.begins_with("HOLD INTERACT // "):
			return InputGlyphs.hold("interact", prompt.trim_prefix("HOLD INTERACT // "))
		if not prompt.is_empty():
			return InputGlyphs.prompt("interact", prompt)
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


## Where [E] aims from: the head on desktop and phones, the right hand in XR (point and pull the trigger).
func interaction_aim() -> Transform3D:
	if xr_active and xr_right.get_has_tracking_data():
		return xr_right.global_transform
	return active_camera().global_transform   # flat, or a headset without a tracked right hand: aim with the head


## XRHands: a gripping hand moved the runner `amount` metres along the ladder this frame (+ is up).
func xr_climb_pull(amount: float) -> void:
	_xr_climb_pull += amount


## XRHands: a fast right-hand swing. Only the breaching tools swing physically; returns whether it swung.
func xr_swing() -> bool:
	if not inventory_enabled or not BREACH_TOOLS.has(selected_inventory_item()):
		return false
	_use_selected_tool()
	return true


## XRHands: the right fingertip touched an interactable, which works it like [E].
func xr_poke(target: RouteInteractable3D) -> void:
	if input_frozen or stun_timer > 0.0 or is_climbing():
		return
	_activate_interactable(target)


func _try_interact() -> void:
	var target := _nearest_interactable()
	if target == null:
		if shop_resolver.is_valid():
			var message := String(shop_resolver.call("open"))
			if not message.is_empty():
				interaction_message.emit(message)
				return
		return   # E with nothing in reach is silent (the cue is only for a visible interactable that refuses)
	_activate_interactable(target)


func _activate_interactable(target: RouteInteractable3D) -> void:
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
	if active_camera() == null:
		return null
	var aim := interaction_aim()
	var origin := aim.origin
	var look := -aim.basis.z.normalized()
	var maximum_distance := GameConfig.INTERACTION_RANGE / GameConfig.TILE_SIZE * PlayerModels.SCALE
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
	var query := PhysicsRayQueryParameters3D.create(interaction_aim().origin, focus)
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	var collider = hit.get("collider")
	if collider == candidate or (collider is Node and candidate.is_ancestor_of(collider)):
		return true
	# A door's leaf, frame and keep-clear colliders are separate bodies (CollisionWorld / the chunk), so the ray toward
	# its focus point stops on the door itself or its frame a few cm short. That still is the door: a hit at the focus
	# counts. Only something well in front of it (a wall, a prop) blocks the interaction.
	return (hit.get("position", interaction_aim().origin) as Vector3).distance_to(focus) <= INTERACTION_FOCUS_TOLERANCE
