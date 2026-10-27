class_name VoidWhiteGimmick
extends VoidGimmick

## White Void, lightFrozen: frozen while the player's lit torch hits her (10 cells, 0.42 rad), 1.35x faster in the dark.

const BEAM_RANGE := 10.0
const BEAM_HALF_ANGLE := 0.42
const DARK_SPEED_SCALE := 1.35

var lit := false


func before_perception(brain: HunterBrain, _delta: float, target: Dictionary, generator) -> void:
	lit = beam_on(target, brain.position, BEAM_RANGE, BEAM_HALF_ANGLE, generator)


func speed_scale(_brain: HunterBrain) -> float:
	return 0.0 if lit else DARK_SPEED_SCALE


func network_state() -> Dictionary:
	return {"lit": lit}


func apply_network_state(state: Dictionary) -> void:
	lit = bool(state.get("lit", lit))
