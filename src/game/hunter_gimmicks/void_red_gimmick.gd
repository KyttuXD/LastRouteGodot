class_name VoidRedGimmick
extends VoidGimmick

## Red Void, hallRunner: 1.55x faster in hallways and 0.78x inside rooms.

const CORRIDOR_SPEED_SCALE := 1.55
const ROOM_SPEED_SCALE := 0.78

var _in_room := false


func before_perception(brain: HunterBrain, _delta: float, _target: Dictionary, generator) -> void:
	_in_room = not generator.room_at(brain.position.x, brain.position.y).is_empty()


func speed_scale(_brain: HunterBrain) -> float:
	return ROOM_SPEED_SCALE if _in_room else CORRIDOR_SPEED_SCALE
