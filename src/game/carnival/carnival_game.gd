class_name CarnivalGame
extends RefCounted

## One booth game as pure, steppable rules: no nodes, no input singletons. The booth node feeds it the player's aim (in the booth's plane, metres, u right / v up from the game's centre),
## fire / move / hold, and steps it every frame; it answers with `events` (what to animate and make noise for) and a `state()` dictionary of the part positions to draw.
## Subclasses override _tick, _on_fire (and _on_move / _on_hold), state(), max_score(), won(), prompt().

var seed_value := 0
var rng := RandomNumberGenerator.new()
var seconds := 20.0
var elapsed := 0.0
var booth_score := 0
var finished := false
## the player's aim in the booth plane
var aim := Vector2.ZERO
var move := Vector2.ZERO
var holding := false
## [{"type": String, ...}] since the last take_events()
var events: Array = []


func _init(seed_number := 0) -> void:
	seed_value = seed_number
	rng.seed = absi(seed_number) + 7919


## Advance by dt seconds. A finished game ignores further steps.
func step(dt: float) -> void:
	if finished:
		return
	elapsed += dt
	_tick(dt)
	if elapsed >= seconds or _done():
		finished = true
		events.append({"type": "end", "won": won(), "booth_score": booth_score})


func fire() -> void:
	if not finished:
		_on_fire()


func set_aim(plane_point: Vector2) -> void:
	aim = plane_point


func set_move(direction: Vector2) -> void:
	move = direction.limit_length(1.0)


func set_hold(on: bool) -> void:
	if on != holding:
		holding = on
		if not finished:
			_on_hold(on)


func take_events() -> Array:
	var out := events
	events = []
	return out


func time_left() -> float:
	return maxf(0.0, seconds - elapsed)


func max_score() -> int:
	return 1


func won() -> bool:
	return booth_score >= 1


## One line under the crosshair: what to do and how it stands.
func prompt() -> String:
	return ""


func state() -> Dictionary:
	return {}


func _tick(_dt: float) -> void:
	pass


func _on_fire() -> void:
	pass


func _on_hold(_on: bool) -> void:
	pass


func _done() -> bool:
	return false
