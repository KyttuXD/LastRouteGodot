class_name VoidYellowGimmick
extends VoidGimmick

## Yellow Void, mapPressure: while the full-screen map is open her speed multiplier grows 0.06 per second up to 1.7x,
## and stays for the rest of the route.

const SPEED_PER_SECOND := 0.06
const MAXIMUM_SPEED_SCALE := 1.7

var scale := 1.0


func before_perception(_brain: HunterBrain, delta: float, target: Dictionary, _generator) -> void:
	if bool(target.get("map_open", false)):
		scale = minf(MAXIMUM_SPEED_SCALE, scale + SPEED_PER_SECOND * delta)


func speed_scale(_brain: HunterBrain) -> float:
	return scale


func network_state() -> Dictionary:
	return {"scale": scale}


func apply_network_state(state: Dictionary) -> void:
	scale = float(state.get("scale", scale))
