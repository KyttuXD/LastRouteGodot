class_name VoidPinkGimmick
extends VoidGimmick

## Pink Void, falseSignal: she never attacks. Every 11 s she has a 60 % chance to send a "FOOTSTEPS // SOMEWHERE CLOSE"
## cue. (The two fake radar contacts for 6 s need the radar to accept ghost marks and are still to do, see
## docs/HUNTER_PARITY.md.)

const INTERVAL := 11.0
const CHANCE := 0.6

var _cooldown := INTERVAL


func after_perception(brain: HunterBrain, delta: float, _target: Dictionary, _generator) -> void:
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	_cooldown = INTERVAL
	if brain.next_random_float() < CHANCE:
		brain.world_events.append({"what": "message", "sound": "alert", "message": "FOOTSTEPS // SOMEWHERE CLOSE"})


func immune_to_capture() -> bool:
	return true
