class_name HardAbilities
extends RefCounted

## Extra hunter abilities for Normal (very rarely), Hard (regular) and Nightmare (frequent / stronger); Relaxed gets none. One small component per
## brain (HunterBrain.hard), host-simulated like every brain, its visible state replicated through network_state(). Persona-anchored: each ability lists
## the hunters that have it per mode. See docs/HUNTER_HARD_ABILITIES.md for the design, the numbers and the counterplay.
##
## FREQUENCY is an on/off gate (Relaxed 0 disables every ability; Normal .12, Hard 1 and Nightmare 1.6 are only tested as > 0). It does not multiply roll
## chances. Each ability uses the chance in its own table (pounce: .35 / .35 / .56 per eligible second) plus its cooldown and the party budget (at most one
## activation per BUDGET seconds across every hunter, so spawn growth cannot make Normal busy).
##
## Built so far: POUNCE, SLAM (door slam-through, applied by the route scene), BURST (sprint burst after losing sight), INTERCEPT (aims ahead of the runner).

const MODES := ["standard", "hard", "nightmare"]
const FREQUENCY := {"relaxed": 0.0, "standard": .12, "hard": 1.0, "nightmare": 1.6}
## Seconds between two activations of the same ability anywhere in the party.
const BUDGET := {"standard": 360.0, "hard": 45.0, "nightmare": 25.0}
## One pounce per runner within this window, whichever hunter.
const POUNCE_RUNNER_GUARD := 10.0

## ability -> mode -> hunter ids
const ROSTER := {
	"pounce": {
		"standard": ["haelith", "void_red"],
		"hard": ["haelith", "solyth", "xivvy", "void_red"],
		"nightmare": ["haelith", "solyth", "xivvy", "void_red", "void_black", "nyxie"],
	},
	"slam": {
		"standard": ["elise"],
		"hard": ["elise", "javelle", "solyth"],
		"nightmare": ["elise", "javelle", "solyth"],
	},
	"burst": {
		"standard": ["quenelle"],
		"hard": ["quenelle", "ferryn", "umbriel"],
		"nightmare": ["quenelle", "ferryn", "umbriel"],
	},
	"intercept": {
		"standard": ["mavrine"],
		"hard": ["mavrine", "kathy", "quenelle"],
		"nightmare": ["mavrine", "kathy", "quenelle"],
	},
}

## Per-mode numbers. `chance` is per eligible SECOND for the pounce, per EVENT for the others (before the mode factor is applied where noted).
const POUNCE := {
	"standard": {"min": 2.2, "max": 3.5, "rate": .35, "cooldown": 120.0, "per_chase": 1, "stumble": 1.6, "seconds": .45},
	"hard": {"min": 2.2, "max": 4.5, "rate": .35, "cooldown": 28.0, "per_chase": 2, "stumble": 1.1, "seconds": .5},
	"nightmare": {"min": 2.2, "max": 5.5, "rate": .56, "cooldown": 18.0, "per_chase": 2, "stumble": .8, "seconds": .5},
}
const LEAP_SPEED := 7.2
const LEAD_SECONDS := .15
const BONK_STUN := .8
const STUMBLE_SPEED := .3
const BURST := {
	"standard": {"chance": .12, "scale": 1.12, "seconds": 1.0, "cooldown": 90.0},
	"hard": {"chance": .6, "scale": 1.25, "seconds": 1.6, "cooldown": 25.0},
	"nightmare": {"chance": 1.0, "scale": 1.40, "seconds": 2.2, "cooldown": 25.0},
}
const INTERCEPT := {
	"standard": {"chance": .30, "lead": .4},
	"hard": {"chance": 1.0, "lead": 1.0},
	"nightmare": {"chance": 1.0, "lead": 1.8},
}
const SLAM := {
	"standard": {"chance": .10, "seconds": 8.0},
	"hard": {"chance": 1.0, "seconds": 20.0},
	"nightmare": {"chance": 1.0, "seconds": 35.0},
}

## Host switch (the room setting): false turns every ability off. The route scenes set it from RoomState.
static var enabled := true


## Both switches: the code-level one (tests) and the host's room setting.
static func active() -> bool:
	return enabled
## Tests set this to drive the budget clock; negative = real time.
static var clock_override := -1.0
static var _last_fire := {}
static var _last_pounce_at_runner := {}

# ---- per-brain state
var leaping := false
var leap_dir := Vector2.ZERO
var leap_seq := 0                 # increments on every launch (the view plays the single footfall on it)
var stumble_left := 0.0
var burst_left := 0.0
var mode := "standard"
var hunter_id := ""

var _leap_left := 0.0
var _pounce_cooldown := 0.0
var _pounces_this_chase := 0
var _burst_cooldown := 0.0
var _was_visible := false
var _last_target := Vector2.INF
var _target_velocity := Vector2.ZERO
var _unwatched := 0.0
var _chase_started := false


## The component for this brain, or null when she has no ability on this difficulty (Relaxed never).
static func for_brain(brain) -> HardAbilities:
	var key := String(brain.difficulty_id)
	if not MODES.has(key):
		return null
	var component := HardAbilities.new()
	component.mode = key
	component.hunter_id = String(brain.hunter_id)
	return component if component.has_any() else null


func has_any() -> bool:
	for ability in ROSTER:
		if has(ability):
			return true
	return false


func has(ability: String) -> bool:
	return (ROSTER[ability][mode] as Array).has(hunter_id)


static func _now() -> float:
	return clock_override if clock_override >= 0.0 else Time.get_ticks_msec() / 1000.0


static func reset_director() -> void:
	_last_fire.clear()
	_last_pounce_at_runner.clear()
	clock_override = -1.0


## The party budget: true when this ability may fire now (and, with `commit`, records that it did).
func _budget_ok(ability: String, commit: bool) -> bool:
	var last := float(_last_fire.get(ability, -1.0e9))
	if _now() - last < float(BUDGET[mode]):
		return false
	if commit:
		_last_fire[ability] = _now()
	return true


func cancel() -> void:
	leaping = false
	_leap_left = 0.0
	stumble_left = 0.0


func network_state() -> Dictionary:
	return {"leap": leaping, "dir": leap_dir, "seq": leap_seq, "stumble": snappedf(stumble_left, .05), "burst": burst_left > 0.0}


func apply_network_state(state: Dictionary) -> void:
	leaping = bool(state.get("leap", false))
	leap_dir = state.get("dir", Vector2.ZERO)
	leap_seq = int(state.get("seq", leap_seq))
	stumble_left = float(state.get("stumble", 0.0))
	burst_left = 1.0 if bool(state.get("burst", false)) else 0.0


## Speed multiplier from the abilities (burst, stumble).
func speed_scale() -> float:
	var scale := 1.0
	if burst_left > 0.0:
		scale *= float(BURST[mode]["scale"])
	if stumble_left > 0.0:
		scale *= STUMBLE_SPEED
	return scale


## While she stumbles after a miss she cannot catch anyone.
func blocks_capture() -> bool:
	return stumble_left > 0.0


## Called once per brain update after perception and the gimmick hooks, before movement. Returns true when the leap drives her movement this frame.
func update(brain, delta: float, generator, target: Dictionary) -> bool:
	if not active() or FREQUENCY.get(String(brain.difficulty_id), 0.0) <= 0.0:
		cancel()
		return false
	_pounce_cooldown = maxf(0.0, _pounce_cooldown - delta)
	_burst_cooldown = maxf(0.0, _burst_cooldown - delta)
	burst_left = maxf(0.0, burst_left - delta)
	var was_stumbling := stumble_left > 0.0
	stumble_left = maxf(0.0, stumble_left - delta)
	var position_now: Vector2 = target.get("position", Vector2.INF)
	if position_now != Vector2.INF:
		if _last_target != Vector2.INF and delta > 0.0:
			_target_velocity = _target_velocity.lerp((position_now - _last_target) / delta, clampf(delta * 8.0, 0.0, 1.0))
		_last_target = position_now
	var visible: bool = brain.state == HunterBrain.State.CHASE and brain.direct_chase_visible
	if brain.state != HunterBrain.State.CHASE:
		_pounces_this_chase = 0
	if was_stumbling and stumble_left <= 0.0:
		pass
	if leaping:
		var driven := _step_leap(brain, delta, generator)
		_was_visible = visible
		return driven
	if _was_visible and not visible and brain.state == HunterBrain.State.CHASE:
		_on_sight_lost(brain, generator)
	_was_visible = visible
	if has("pounce") and not target.is_empty():
		_maybe_pounce(brain, delta, generator, target)
	return leaping


# ---------------------------------------------------------------------------------------------- pounce

func _pounce_allowed_for_hunter(brain, target: Dictionary, generator) -> bool:
	match hunter_id:
		"solyth":
			var meters = target.get("meters")
			return meters != null and float(meters.temperature) >= 60.0
		"nyxie":
			return not bool(target.get("flashlight_on", true))
		"void_red":
			return generator.room_at(brain.position.x, brain.position.y).is_empty()
		"void_black":
			return _unwatched >= 3.0
	return true


func _maybe_pounce(brain, delta: float, generator, target: Dictionary) -> void:
	if hunter_id == "void_black":
		var black = brain.gimmick
		_unwatched = 0.0 if black != null and bool(black.get("watched")) else _unwatched + delta
	var numbers: Dictionary = POUNCE[mode]
	if _pounce_cooldown > 0.0 or stumble_left > 0.0 or _pounces_this_chase >= int(numbers["per_chase"]):
		return
	if brain.state != HunterBrain.State.CHASE or not brain.direct_chase_visible or brain.stun_timer > 0.0:
		return
	if bool(target.get("hidden", false)) or bool(target.get("in_safe_zone", false)) or bool(target.get("in_vent", false)) \
			or bool(target.get("no_target", false)) or bool(target.get("on_link", false)):
		return
	var at: Vector2 = target["position"]
	var distance: float = brain.position.distance_to(at)
	if distance < float(numbers["min"]) or distance > float(numbers["max"]):
		return
	if brain.near_link.is_valid() and (bool(brain.near_link.call(brain.position, 1.5)) or bool(brain.near_link.call(at, 1.5))):
		return   # never launch within 1.5 cells of a ladder, stairs, manhole, grate, elevator or drop link (either end)
	if not _pounce_allowed_for_hunter(brain, target, generator):
		return
	if not brain._clear_sweep(generator, brain.position, at):
		return
	var runner := int(target.get("peer_id", 1))
	if _now() - float(_last_pounce_at_runner.get(runner, -1.0e9)) < POUNCE_RUNNER_GUARD:
		return
	if brain.next_random_float() >= float(numbers["rate"]) * delta:
		return
	if not _budget_ok("pounce", false):
		return
	_budget_ok("pounce", true)
	_last_pounce_at_runner[runner] = _now()
	_launch(brain, at)


func _launch(brain, at: Vector2) -> void:
	var predicted := at + _target_velocity * LEAD_SECONDS
	var direction: Vector2 = predicted - brain.position
	if direction.length_squared() < .0001:
		direction = at - brain.position
	leap_dir = direction.normalized()
	leaping = true
	_leap_left = float(POUNCE[mode]["seconds"])
	leap_seq += 1
	_pounces_this_chase += 1
	brain.facing = leap_dir


func _step_leap(brain, delta: float, generator) -> bool:
	var wanted := LEAP_SPEED * minf(delta, _leap_left)
	var moved: float = brain._move_with_collision(leap_dir.x * wanted, leap_dir.y * wanted, generator)
	brain.facing = leap_dir
	_leap_left -= delta
	if wanted > 0.001 and moved < wanted * .5:
		# a wall, prop or door stopped the leap: she is stunned for a moment
		leaping = false
		_pounce_cooldown = float(POUNCE[mode]["cooldown"])
		brain.apply_stun(BONK_STUN)
		return true
	if _leap_left <= 0.0:
		leaping = false
		_pounce_cooldown = float(POUNCE[mode]["cooldown"])
		stumble_left = float(POUNCE[mode]["stumble"])   # she overshoots and stumbles: escapable
	return true


# --------------------------------------------------------------------------- sight lost: burst + intercept

func _on_sight_lost(brain, generator) -> void:
	if has("intercept") and brain.next_random_float() < float(INTERCEPT[mode]["chance"]) and _budget_ok("intercept", true):
		var ahead: Vector2 = brain.last_known + _target_velocity * float(INTERCEPT[mode]["lead"])
		var open: Dictionary = generator.nearest_open_position(ahead.x, ahead.y, brain.radius)
		if not open.is_empty():
			brain.last_known = Vector2(open["x"], open["y"])
			brain.has_last_known = true
	if has("burst") and _burst_cooldown <= 0.0 and brain.next_random_float() < float(BURST[mode]["chance"]) and _budget_ok("burst", true):
		burst_left = float(BURST[mode]["seconds"])
		_burst_cooldown = float(BURST[mode]["cooldown"])


# --------------------------------------------------------------------------------------- door slam-through

## Called by the route scene when this hunter, chasing, reaches a closed room door: seconds the door stays slammed open (0 = she opens it normally).
func door_slam_seconds(brain) -> float:
	if not active() or not has("slam") or brain.state != HunterBrain.State.CHASE:
		return 0.0
	if brain.next_random_float() >= float(SLAM[mode]["chance"]) or not _budget_ok("slam", true):
		return 0.0
	return float(SLAM[mode]["seconds"])
