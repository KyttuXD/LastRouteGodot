class_name VoidCyanGimmick
extends VoidGimmick

## Cyan Void, signalPing: 2.5 s of unbroken sight of the player broadcasts their exact position, so every other active
## hunter investigates it; then a 30 s cooldown.

const SIGHT_REQUIRED := 2.5
const INTERVAL := 30.0

var _seen := 0.0
var _cooldown := 0.0


func after_perception(brain: HunterBrain, delta: float, target: Dictionary, _generator) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if _cooldown > 0.0:
		return
	if brain.direct_chase_visible and not bool(target.get("hidden", false)) and not bool(target.get("in_safe_zone", false)):
		_seen += delta
	else:
		_seen = 0.0
	if _seen < SIGHT_REQUIRED:
		return
	_seen = 0.0
	_cooldown = INTERVAL
	brain.emit_world_event({"what": "facility_alert", "at": target["position"], "except": brain.hunter_id,
		"message": "CYAN SIGNAL // YOUR POSITION WAS BROADCAST"})
