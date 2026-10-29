class_name VoidGrayGimmick
extends VoidGimmick

## Gray Void, antiIdle (voids/gray.js): relay-pressure anti-idle signal. She is DORMANT (unseen, still, uncatchable) while the team keeps
## collecting relays; a grace window of 180 s (120 s on Nightmare) restarts at every relay. Once it has run out, standing still in the
## open (not hiding, not in a safe room) for 45 s (30 s on Nightmare) opens a SIGNAL ROUTE: 5 E presses with 2.5 s for each (1.8 s on
## Nightmare). Clearing it keeps her dormant; missing one (or letting the clock run out) shows her and starts a normal chase that only
## the next relay resets. She chases whoever failed regardless of light.
##
## The route itself runs on the failing player's own machine (main_3d counts the E presses against the timer) and reports back with
## route_result(); the host keeps a watchdog so a lost report still ends it.

const IDLE_SECONDS := 45.0
const NIGHTMARE_IDLE_SECONDS := 30.0
const NODES := 5
const SECONDS_PER_NODE := 2.5
const NIGHTMARE_SECONDS_PER_NODE := 1.8
const RELAY_GRACE_SECONDS := 180.0
const NIGHTMARE_RELAY_GRACE_SECONDS := 120.0
## Slower than this (cells/s) counts as standing still.
const STILL_SPEED := .15
const REPORT_SLACK := 3.0
const LOCK_RELEASE_DISTANCE := 5.0

var hunting := false
## Woken by the anti-idle / anti-AFK pressure: she knows the runner's exact position and keeps it (no search, no lost-sight
## grace) for as long as they stay within LOCK_RELEASE_DISTANCE of where they were when she woke.
var locked := false
var dormant := true
var route_active := false
var route_peer := 1
var route_nodes := NODES
var route_seconds := SECONDS_PER_NODE

var _grace := 0.0
var _idle := 0.0
var _route_left := 0.0
var _relays := -1
var _last_position := Vector2.INF
var _last_target_position := Vector2.ZERO
var _lock_origin := Vector2.ZERO


static func idle_limit(nightmare: bool) -> float:
	return NIGHTMARE_IDLE_SECONDS if nightmare else IDLE_SECONDS


static func grace_limit(nightmare: bool) -> float:
	return NIGHTMARE_RELAY_GRACE_SECONDS if nightmare else RELAY_GRACE_SECONDS


static func node_seconds(nightmare: bool) -> float:
	return NIGHTMARE_SECONDS_PER_NODE if nightmare else SECONDS_PER_NODE


func before_perception(brain: HunterBrain, delta: float, target: Dictionary, _generator) -> void:
	var nightmare := brain.difficulty_id == "nightmare"
	if _relays < 0:
		_relays = brain.relays_seen
	if brain.relays_seen != _relays:
		var collected := brain.relays_seen > _relays
		_relays = brain.relays_seen
		if collected:
			_grace = 0.0
			_idle = 0.0
			hunting = false
			dormant = true
			route_active = false
			brain.state = HunterBrain.State.IDLE
			brain.has_last_known = false
			brain.world_events.append({"what": "message", "message": "GRAY PRESSURE RESET // RELAY SECURED"})
	if hunting:
		dormant = false
		if locked and not target.is_empty():
			var at_now: Vector2 = target.get("position", _lock_origin)
			if at_now.distance_to(_lock_origin) > LOCK_RELEASE_DISTANCE:
				locked = false   # they moved on: a normal hunt from here
			else:
				_last_target_position = at_now
				brain.lost_sight_timer = 0.0
				brain.has_last_known = true
				brain.last_known = at_now
				if brain.state != HunterBrain.State.CHASE:
					brain.continue_chase_from(at_now)
		return
	dormant = true
	_grace = minf(grace_limit(nightmare), _grace + delta)
	if route_active:
		_route_left -= delta
		if _route_left <= 0.0:
			_fail(brain)
		return
	if _grace < grace_limit(nightmare) or target.is_empty():
		_idle = 0.0
		return
	var at: Vector2 = target.get("position", _last_position)
	_last_target_position = at
	var moving := _last_position != Vector2.INF and at.distance_to(_last_position) / maxf(delta, .001) > STILL_SPEED
	_last_position = at
	# Hiding and a safe room are legitimate reasons to be still; only standing around in the open counts.
	var still := not moving and not bool(target.get("hidden", false)) and not bool(target.get("in_safe_zone", false))
	_idle = _idle + delta if still else 0.0
	if _idle < idle_limit(nightmare):
		return
	_idle = 0.0
	route_active = true
	route_peer = int(target.get("peer_id", 1))
	route_nodes = NODES
	route_seconds = node_seconds(nightmare)
	_route_left = route_nodes * route_seconds + REPORT_SLACK
	brain.world_events.append({"what": "signal_route", "nodes": route_nodes, "seconds": route_seconds,
		"peer_id": route_peer, "sound": "alert", "message": "SIGNAL ROUTE OPEN // MASH E"})


func after_perception(brain: HunterBrain, _delta: float, _target: Dictionary, _generator) -> void:
	# Dormant, she does not notice anyone: whatever perception just decided is undone.
	if dormant and not hunting:
		brain.state = HunterBrain.State.IDLE
		brain.has_last_known = false


## The failing/clearing player's report. ok: all nodes pressed in time.
func route_result(brain: HunterBrain, ok: bool) -> void:
	if not route_active:
		return
	if ok:
		route_active = false
		_idle = 0.0
		brain.world_events.append({"what": "message", "message": "SIGNAL ROUTE CLEARED"})
	else:
		_fail(brain)


## The anti-idle pressure reached an idle runner: Gray stops being dormant and goes straight for where they stand.
func force_hunt(brain: HunterBrain, at: Vector2) -> void:
	route_active = false
	hunting = true
	dormant = false
	locked = true
	_lock_origin = at
	_last_target_position = at
	brain.continue_chase_from(at)


func _fail(brain: HunterBrain) -> void:
	route_active = false
	_grace = 0.0
	hunting = true
	dormant = false
	brain.state = HunterBrain.State.CHASE
	brain.has_last_known = true
	brain.last_known = _last_target_position
	brain.world_events.append({"what": "message", "sound": "alert", "message": "SIGNAL ROUTE FAILED // GRAY IS HUNTING"})


func hidden_from_view() -> bool:
	return dormant and not hunting


func holds_position() -> bool:
	return dormant and not hunting


func immune_to_capture() -> bool:
	return dormant and not hunting


func network_state() -> Dictionary:
	return {"hunting": hunting, "dormant": dormant, "route": route_active, "locked": locked}


func apply_network_state(state: Dictionary) -> void:
	hunting = bool(state.get("hunting", hunting))
	dormant = bool(state.get("dormant", dormant))
	route_active = bool(state.get("route", route_active))
	locked = bool(state.get("locked", locked))
