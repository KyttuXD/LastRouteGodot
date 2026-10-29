class_name VoidBlueGimmick
extends VoidGimmick

## Blue Void, silentStalker: invisible (and off the maps) unless revealed. The player's beam (12 cells, 0.48 rad)
## shoves her 6 cells straight away from them and shows her for 3.5 s.

const REVEAL_SECONDS := 3.5
const PUSHBACK := 6.0
const BEAM_RANGE := 12.0
const BEAM_HALF_ANGLE := 0.48

var reveal_remaining := 0.0


func before_perception(brain: HunterBrain, delta: float, target: Dictionary, generator) -> void:
	reveal_remaining = maxf(0.0, reveal_remaining - delta)
	if not beam_on(target, brain.position, BEAM_RANGE, BEAM_HALF_ANGLE, generator):
		return
	var from: Vector2 = target["position"]
	var away := (brain.position - from).normalized()
	var wanted := brain.position + away * PUSHBACK
	var open: Dictionary = generator.nearest_open_position(wanted.x, wanted.y, brain.radius)
	if not open.is_empty() and Vector2(open["x"], open["y"]).distance_to(brain.position) <= PUSHBACK + 1.5:
		brain.position = Vector2(open["x"], open["y"])
	if reveal_remaining <= 0.0:
		brain.world_events.append({"what": "message", "message": "SOMETHING WAS STANDING THERE"})
	reveal_remaining = REVEAL_SECONDS


func hidden_from_view() -> bool:
	return reveal_remaining <= 0.0


func network_state() -> Dictionary:
	return {"revealed": reveal_remaining > 0.0}


func apply_network_state(state: Dictionary) -> void:
	reveal_remaining = 1.0 if bool(state.get("revealed", false)) else 0.0
