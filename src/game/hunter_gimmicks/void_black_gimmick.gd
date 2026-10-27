class_name VoidBlackGimmick
extends VoidGimmick

## Black Void, rearStalker: frozen while the player is looking at her (within 11 cells, 0.85 rad, clear line), 1.5x
## faster whenever she is not watched.

const GAZE_RANGE := 11.0
const GAZE_HALF_ANGLE := 0.85
const HIDDEN_SPEED_SCALE := 1.5

var watched := false


func before_perception(brain: HunterBrain, _delta: float, target: Dictionary, generator) -> void:
	watched = player_watching(target, brain.position, GAZE_RANGE, GAZE_HALF_ANGLE, generator)


func speed_scale(_brain: HunterBrain) -> float:
	return 0.0 if watched else HIDDEN_SPEED_SCALE


func network_state() -> Dictionary:
	return {"watched": watched}


func apply_network_state(state: Dictionary) -> void:
	watched = bool(state.get("watched", watched))
