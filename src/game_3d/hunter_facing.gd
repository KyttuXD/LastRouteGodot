class_name HunterFacing
extends RefCounted

## Presentation-only facing for a walking character: where the BODY points and
## where the HEAD looks. Owns no node -- the caller feeds it the replicated 2D
## position each frame and applies the yaw / head angles it returns, so
## HunterView3D and any other creature view can share one behaviour.
##
## Nothing here touches the simulation or the network: heading comes from the
## position delta, the head target from the (host-only) A* route when there is
## one and from the movement direction when there is not (guests).

## Head behaviours. NONE fades the look layer out (stun, dead, emotes).
enum Mode { NONE, AHEAD, SCAN, LOCK, SWEEP }

const WALK_TURN := deg_to_rad(420.0)
const RUN_TURN := deg_to_rad(600.0)
## Proportional gain of the body turn: eases out instead of stopping dead.
const TURN_GAIN := 12.0
const MIN_HEADING_SPEED := .45
const TELEPORT_STEP := 3.0
## She counts as moving until this long after the last real step, so a guest
## whose position arrives in network ticks does not flicker between "moving"
## and "standing" on the frames in between.
const MOVING_HOLD := .25

const YAW_LIMIT := deg_to_rad(70.0)
const PITCH_LIMIT := deg_to_rad(35.0)
const LOOK_AHEAD_MIN := 2.0
const LOOK_AHEAD_MAX := 4.0
const HEAD_DAMP := 9.0
const FADE_SPEED := 4.0
## Beyond this distance from the camera the look layer is not evaluated.
const UPDATE_RANGE := 40.0
const AHEAD_SWAY := deg_to_rad(10.0)
const SCAN_SWING := deg_to_rad(42.0)
const SWEEP_SWING := deg_to_rad(22.0)
const NOD := deg_to_rad(5.0)

var move_dir := Vector2.ZERO
var speed := 0.0
var head_yaw := 0.0
var head_pitch := 0.0
## 0 = clip pose untouched, 1 = look layer fully applied.
var weight := 0.0
## Tests set this to 0 to remove the idle sway and read the pure target.
var scan_scale := 1.0
var phase := 0.0
## Largest single-frame body turn seen (radians); validators assert on it.
var max_frame_turn := 0.0

var _last_position := Vector2.ZERO
var _has_last := false
var _still_time := 0.0


func moving() -> bool:
	return _still_time < MOVING_HOLD and move_dir.length_squared() > .0001


## Feed the current position once per frame, before steer().
func track(position: Vector2, delta: float) -> void:
	var frame := clampf(delta, 1.0 / 240.0, .1)
	if not _has_last:
		_has_last = true
		_last_position = position
		return
	var step := position - _last_position
	_last_position = position
	var distance := step.length()
	if distance > TELEPORT_STEP:
		speed = 0.0
		move_dir = Vector2.ZERO
		_still_time = MOVING_HOLD
		return
	speed = lerpf(speed, distance / frame, .3)
	if distance / frame > MIN_HEADING_SPEED:
		_still_time = 0.0
		var direction := step / distance
		move_dir = direction if move_dir.length_squared() < .01 \
			else move_dir.lerp(direction, clampf(frame * 18.0, 0.0, 1.0))
	else:
		_still_time += frame


## New body yaw (Godot yaw: forward is -Z) after turning toward `direction`
## with a capped, eased turn. A zero direction keeps the current heading.
func steer(current: float, direction: Vector2, running: bool, delta: float) -> float:
	if direction.length_squared() < .0001:
		return current
	var frame := clampf(delta, 1.0 / 240.0, .1)
	var limit := (RUN_TURN if running else WALK_TURN) * frame
	var error := wrapf(atan2(-direction.x, -direction.y) - current, -PI, PI)
	var turn := clampf(error * clampf(frame * TURN_GAIN, 0.0, 1.0), -limit, limit)
	max_frame_turn = maxf(max_frame_turn, absf(turn))
	return current + turn


func look_ahead_distance() -> float:
	return clampf(LOOK_AHEAD_MIN + speed * .35, LOOK_AHEAD_MIN, LOOK_AHEAD_MAX)


## Advance the head. `target` is a world-space 2D point (ignored for NONE and
## SCAN); `origin` the character's 2D position; `body_yaw` its current yaw.
func update_head(delta: float, mode: int, body_yaw: float, origin: Vector2,
		target: Vector2, seconds: float) -> void:
	var frame := clampf(delta, 1.0 / 240.0, .1)
	weight = move_toward(weight, 0.0 if mode == Mode.NONE else 1.0, frame * FADE_SPEED)
	var yaw := 0.0
	var pitch := 0.0
	if mode != Mode.NONE:
		if mode != Mode.SCAN:
			var offset := target - origin
			if offset.length_squared() > .04:
				yaw = wrapf(atan2(-offset.x, -offset.y) - body_yaw, -PI, PI)
		match mode:
			Mode.AHEAD:
				yaw += sin(seconds * .9 + phase) * AHEAD_SWAY * scan_scale
			Mode.SWEEP:
				yaw += sin(seconds * 1.9 + phase) * SWEEP_SWING * scan_scale
			Mode.SCAN:
				yaw = sin(seconds * .7 + phase) * SCAN_SWING * scan_scale
		if mode != Mode.LOCK:
			pitch = sin(seconds * .5 + phase * 1.3) * NOD * scan_scale
	yaw = clampf(yaw, -YAW_LIMIT, YAW_LIMIT)
	pitch = clampf(pitch, -PITCH_LIMIT, PITCH_LIMIT)
	var blend := 1.0 - exp(-HEAD_DAMP * frame)
	head_yaw = lerpf(head_yaw, yaw, blend)
	head_pitch = lerpf(head_pitch, pitch, blend)
