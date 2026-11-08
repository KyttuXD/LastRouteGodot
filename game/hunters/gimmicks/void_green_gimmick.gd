class_name VoidGreenGimmick
extends VoidGimmick

## Green Void, ventRelocate: every 22 s, if she is at least 14 cells from the player she submerges for 2 s (hidden,
## still, unable to grab) and surfaces 9 cells from them in a random direction, investigating.
## She never vents toward a runner inside an intact safe room, and a death/restart rearms her full interval: otherwise
## her long-spent cooldown fired the instant a respawned runner appeared far away at the checkpoint, dropping her 9
## cells from it to wait at the door -- a contact-death loop.

const INTERVAL := 22.0
const MINIMUM_DISTANCE := 14.0
const DROP_DISTANCE := 9.0
const SUBMERGE_SECONDS := 2.0

var _cooldown := INTERVAL
var submerged := 0.0


func after_perception(brain: HunterBrain, delta: float, target: Dictionary, generator) -> void:
	if submerged > 0.0:
		submerged -= delta
		if submerged > 0.0:
			return
		var at: Vector2 = target.get("position", brain.position)
		var angle := brain.next_random_float() * TAU
		var wanted := at + Vector2(cos(angle), sin(angle)) * DROP_DISTANCE
		var open: Dictionary = generator.nearest_open_position(wanted.x, wanted.y, brain.radius)
		if not open.is_empty():
			brain.position = Vector2(open["x"], open["y"])
		brain.state = HunterBrain.State.INVESTIGATE
		brain.has_last_known = true
		brain.last_known = at
		brain.emit_world_event({"what": "message", "message": "A VENT GRATE CLATTERS NEARBY"})
		return
	_cooldown -= delta
	if _cooldown > 0.0 or target.is_empty() or bool(target.get("in_safe_zone", false)):
		return
	var player_at: Vector2 = target.get("position", brain.position)
	if brain.position.distance_to(player_at) < MINIMUM_DISTANCE:
		return
	_cooldown = INTERVAL
	submerged = SUBMERGE_SECONDS


func on_runner_respawn(_brain: HunterBrain) -> void:
	submerged = 0.0
	_cooldown = INTERVAL


func holds_position() -> bool:
	return submerged > 0.0


func hidden_from_view() -> bool:
	return submerged > 0.0


func immune_to_capture() -> bool:
	return submerged > 0.0


func network_state() -> Dictionary:
	return {"submerged": submerged > 0.0}


func apply_network_state(state: Dictionary) -> void:
	submerged = 1.0 if bool(state.get("submerged", false)) else 0.0
