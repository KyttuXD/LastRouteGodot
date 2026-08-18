class_name XivvyGimmick
extends HunterGimmick

## Xivvy's chase accelerator (hunterAbilities.xivvy.chaseAccelerator). Ported
## from xivvy.js's updateChaseAccelerator(): she locks onto the target by pure
## proximity — no sight, no hearing, no line of sight — and then her chase
## speed ramps for as long as the chase runs, resetting the moment she drops
## out of chase.
##
## The original's lock radius is `closeLockRadius * (.5 + exposure / 200)`.
## This pass retains the established resting scale for compatibility; wiring
## the live exposure meter into this radius is a separate tuning change. Her
## movement now visibly transitions from grounded locomotion to a winged
## flight loop after a short chase takeoff, while AI remains on the same 2D
## navigation plane as every other hunter.

var _chase_elapsed := 0.0
var _speed_scale := 1.0
var flying := false


func before_perception(brain: HunterBrain, delta: float, target: Dictionary, _generator) -> void:
	var hidden: bool = target.get("hidden", false)
	var in_safe_zone: bool = target.get("in_safe_zone", false)
	var target_position: Vector2 = target["position"]

	var lock_radius := GameConfig.XIVVY_CLOSE_LOCK_RADIUS * GameConfig.XIVVY_CLOSE_SCALE
	if not hidden and not in_safe_zone and brain.position.distance_to(target_position) <= lock_radius:
		brain.state = HunterBrain.State.CHASE
		brain.has_last_known = true
		brain.last_known = target_position

	# Measured on the state as it stands entering this frame, matching the
	# original's ordering: the lock above can start the chase, and the ramp
	# begins accumulating from that same frame.
	_chase_elapsed = _chase_elapsed + delta if brain.state == HunterBrain.State.CHASE else 0.0
	flying = _chase_elapsed >= GameConfig.XIVVY_TAKEOFF_SECONDS
	_speed_scale = minf(
		GameConfig.XIVVY_MAX_SPEED_SCALE,
		1.0 + _chase_elapsed * GameConfig.XIVVY_SPEED_PER_SECOND
	)


func speed_scale(_brain: HunterBrain) -> float:
	return _speed_scale


func network_state() -> Dictionary:
	return {"flying": flying}


func apply_network_state(state: Dictionary) -> void:
	flying = bool(state.get("flying", false))
