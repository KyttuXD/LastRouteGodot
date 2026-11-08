class_name VoidBrownGimmick
extends VoidGimmick

## Brown Void, spotJammer: every 18 s up to two hiding spots within 9 cells of the player (never the occupied one)
## are jammed shut for 20 s.

const INTERVAL := 18.0
const JAM_SECONDS := 20.0
const RANGE := 9.0
const COUNT := 2

var _cooldown := INTERVAL
var _jammed: Array = []


func after_perception(brain: HunterBrain, delta: float, target: Dictionary, generator) -> void:
	for entry in _jammed.duplicate():
		entry["left"] = float(entry["left"]) - delta
		if float(entry["left"]) <= 0.0:
			_jammed.erase(entry)
			brain.emit_world_event({"what": "hiding_disabled", "cell": entry["cell"], "disabled": false})
	_cooldown -= delta
	if _cooldown > 0.0 or target.is_empty():
		return
	_cooldown = INTERVAL
	var at: Vector2 = target.get("position", brain.position)
	var occupied: Vector2i = Vector2i(target.get("hiding_spot", Vector2i(-1, -1)))
	var near := []
	for spot in generator.hiding_spots:
		var cell := Vector2i(int(spot["x"]), int(spot["y"]))
		if cell == occupied or _is_jammed(cell):
			continue
		if (Vector2(cell) + Vector2(.5, .5)).distance_to(at) <= RANGE:
			near.append(cell)
	var jammed := 0
	while jammed < COUNT and not near.is_empty():
		var cell: Vector2i = near.pop_at(brain.next_random_index(near.size()))
		_jammed.append({"cell": cell, "left": JAM_SECONDS})
		brain.emit_world_event({"what": "hiding_disabled", "cell": cell, "disabled": true})
		jammed += 1
	if jammed > 0:
		brain.emit_world_event({"what": "message", "sound": "alert",
			"message": "%d HIDING SPOT%s JAMMED SHUT" % [jammed, "" if jammed == 1 else "S"]})


func _is_jammed(cell: Vector2i) -> bool:
	for entry in _jammed:
		if entry["cell"] == cell:
			return true
	return false
